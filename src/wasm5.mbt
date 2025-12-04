// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Validate a WebAssembly module
fn validate_module(m : Module) -> Unit raise ValidationError {
  // Validate function type indices
  for i = 0; i < m.funcs.length(); i = i + 1 {
    let type_idx = m.funcs[i].reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
  }

  // Validate function bodies against their types
  for i = 0; i < m.codes.length(); i = i + 1 {
    let type_idx = m.funcs[i].reinterpret_as_int()
    let func_type = m.types[type_idx]
    let code = m.codes[i]

    // Validate the function body
    validate_function(m, func_type, code)
  }
}

///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module : Module,
  func_type : FuncType,
  code : Code,
  stack : Array[ValType],
  instr : Instr
) -> Unit raise ValidationError {
  match instr {
    // Constants
    I32Const(_) => stack.push(I32)
    I64Const(_) => stack.push(I64)
    F32Const(_) => stack.push(F32)
    F64Const(_) => stack.push(F64)

    // Binary operations
    I32Add | I32Sub | I32Mul | I32DivS | I32DivU | I32RemS | I32RemU |
    I32And | I32Or | I32Xor | I32Shl | I32ShrS | I32ShrU | I32Rotl | I32Rotr => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch("expected at least 2 values on stack for binary op")
      }
      let b = stack.pop_exn()
      let a = stack.pop_exn()
      if a != I32 || b != I32 {
        raise ValidationError::TypeMismatch("i32 binary operation requires i32 operands")
      }
      stack.push(I32)
    }

    // Comparison operations
    I32Eq | I32Ne | I32LtS | I32LtU | I32GtS | I32GtU | I32LeS | I32LeU | I32GeS | I32GeU => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch("expected at least 2 values on stack for comparison")
      }
      let b = stack.pop_exn()
      let a = stack.pop_exn()
      if a != I32 || b != I32 {
        raise ValidationError::TypeMismatch("i32 comparison requires i32 operands")
      }
      stack.push(I32)
    }

    // Unary operations
    I32Eqz | I32Clz | I32Ctz | I32Popcnt | I32Extend8S | I32Extend16S => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected at least 1 value on stack for unary op")
      }
      let a = stack.pop_exn()
      if a != I32 {
        raise ValidationError::TypeMismatch("i32 unary operation requires i32 operand")
      }
      stack.push(I32)
    }

    // i64 binary operations
    I64Add | I64Sub | I64Mul | I64DivS | I64DivU | I64RemS | I64RemU |
    I64And | I64Or | I64Xor | I64Shl | I64ShrS | I64ShrU | I64Rotl | I64Rotr => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch("expected at least 2 values on stack for binary op")
      }
      let b = stack.pop_exn()
      let a = stack.pop_exn()
      if a != I64 || b != I64 {
        raise ValidationError::TypeMismatch("i64 binary operation requires i64 operands")
      }
      stack.push(I64)
    }

    // i64 comparison operations
    I64Eq | I64Ne | I64LtS | I64LtU | I64GtS | I64GtU | I64LeS | I64LeU | I64GeS | I64GeU => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch("expected at least 2 values on stack for comparison")
      }
      let b = stack.pop_exn()
      let a = stack.pop_exn()
      if a != I64 || b != I64 {
        raise ValidationError::TypeMismatch("i64 comparison requires i64 operands")
      }
      stack.push(I32)
    }

    // i64 unary operations
    I64Eqz | I64Clz | I64Ctz | I64Popcnt | I64Extend8S | I64Extend16S | I64Extend32S => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected at least 1 value on stack for unary op")
      }
      let a = stack.pop_exn()
      if a != I64 {
        raise ValidationError::TypeMismatch("i64 unary operation requires i64 operand")
      }
      stack.push(I64)
    }

    // Local operations
    LocalGet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      stack.push(local_type)
    }

    LocalSet(idx) | LocalTee(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for local.set")
      }
      let val_type = stack.pop_exn()
      match instr {
        LocalTee(_) => stack.push(val_type)
        _ => ()
      }
    }

    // Global operations
    GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      if global_idx < 0 || global_idx >= module.globals.length() {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      stack.push(module.globals[global_idx].type_.val_type)
    }

    GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      if global_idx < 0 || global_idx >= module.globals.length() {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for global.set")
      }
      let _ = stack.pop_exn()
    }

    // Memory operations
    I32Load(_, _) => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected address on stack for i32.load")
      }
      let addr = stack.pop_exn()
      if addr != I32 {
        raise ValidationError::TypeMismatch("i32.load requires i32 address")
      }
      stack.push(I32)
    }

    I32Store(_, _) => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch("expected address and value on stack for i32.store")
      }
      let value = stack.pop_exn()
      let addr = stack.pop_exn()
      if addr != I32 || value != I32 {
        raise ValidationError::TypeMismatch("i32.store requires i32 address and value")
      }
    }

    // Block instructions
    Block(result_type, instrs) => {
      let block_stack : Array[ValType] = []
      for block_instr in instrs {
        validate_instruction(module, func_type, code, block_stack, block_instr)
      }
      match result_type {
        None => ()
        Some(t) => {
          if block_stack.length() < 1 {
            raise ValidationError::TypeMismatch("block expects result value on stack")
          }
          let result = block_stack.pop_exn()
          if result != t {
            raise ValidationError::TypeMismatch("block result type mismatch")
          }
          stack.push(t)
        }
      }
    }

    Loop(result_type, instrs) => {
      let loop_stack : Array[ValType] = []
      for loop_instr in instrs {
        validate_instruction(module, func_type, code, loop_stack, loop_instr)
      }
      match result_type {
        None => ()
        Some(t) => {
          if loop_stack.length() < 1 {
            raise ValidationError::TypeMismatch("loop expects result value on stack")
          }
          let result = loop_stack.pop_exn()
          if result != t {
            raise ValidationError::TypeMismatch("loop result type mismatch")
          }
          stack.push(t)
        }
      }
    }

    If(result_type, then_instrs, else_instrs) => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("if expects condition on stack")
      }
      let cond = stack.pop_exn()
      if cond != I32 {
        raise ValidationError::TypeMismatch("if condition must be i32")
      }
      let then_stack : Array[ValType] = []
      for then_instr in then_instrs {
        validate_instruction(module, func_type, code, then_stack, then_instr)
      }
      let else_stack : Array[ValType] = []
      for else_instr in else_instrs {
        validate_instruction(module, func_type, code, else_stack, else_instr)
      }
      match result_type {
        None => ()
        Some(t) => {
          if then_stack.length() < 1 || else_stack.length() < 1 {
            raise ValidationError::TypeMismatch("if branches expect result value")
          }
          let then_result = then_stack[then_stack.length() - 1]
          let else_result = else_stack[else_stack.length() - 1]
          if then_result != t || else_result != t {
            raise ValidationError::TypeMismatch("if branch result type mismatch")
          }
          stack.push(t)
        }
      }
    }

    // Control flow
    Return => {
      stack.clear()
      if func_type.results.length() > 0 {
        stack.push(func_type.results[0])
      }
    }

    Drop => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for drop")
      }
      let _ = stack.pop_exn()
    }

    Nop => ()

    _ => ()
  }
}

///|
/// Validate a single function
fn validate_function(
  module : Module,
  func_type : FuncType,
  code : Code
) -> Unit raise ValidationError {
  // Simple stack-based type checking
  let stack : Array[ValType] = []

  // Validate each instruction in the function body
  for instr in code.body.instrs {
    validate_instruction(module, func_type, code, stack, instr)
  }

  // Check final stack matches return type
  if func_type.results.length() == 0 {
    ()
  } else if func_type.results.length() == 1 {
    if stack.length() < 1 {
      raise ValidationError::StackSizeMismatch("expected return value on stack")
    }
  }
}

pub fn parse(b : Bytes) -> Module raise ValidationError {
  let parser = Parser::new(b)

  // Parse magic number
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    abort("invalid magic number")
  }

  // Parse version
  let version = parser.read_bytes(4)
  if version[0].to_int() != 0x01 ||
    version[1].to_int() != 0x00 ||
    version[2].to_int() != 0x00 ||
    version[3].to_int() != 0x00 {
    abort("unsupported version")
  }

  // Parse sections
  let mut types : Array[FuncType] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[TableType] = []
  let mut mems : Array[MemType] = []
  let mut globals : Array[Global] = []
  let mut elems : Array[Elem] = []
  let mut datas : Array[Data] = []
  let mut start : UInt? = None
  let mut imports : Array[Import] = []
  let mut exports : Array[Export] = []
  let mut codes : Array[Code] = []

  while not(parser.eof()) {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.pos
    match section_id {
      1 => types = parse_type_section(parser)
      2 => imports = parse_import_section(parser)
      3 => funcs = parse_function_section(parser)
      4 => tables = parse_table_section(parser)
      5 => mems = parse_memory_section(parser)
      6 => globals = parse_global_section(parser)
      7 => exports = parse_export_section(parser)
      8 => start = Some(parser.read_u32_leb128())
      9 => elems = parse_element_section(parser)
      10 => codes = parse_code_section(parser)
      11 => datas = parse_data_section(parser)
      0 =>
        // Custom section - skip
        parser.pos = section_start + section_size.to_int()
      _ => abort("unknown section id: \{section_id}")
    }
  }

  let module_ = Module::{
    types,
    funcs,
    tables,
    mems,
    globals,
    elems,
    datas,
    start,
    imports,
    exports,
    codes,
  }

  // Validate the module
  validate_module(module_)

  module_
}
