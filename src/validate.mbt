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
/// Get the function type signature for a block type
fn get_block_type(
  module_ : Module,
  block_type : BlockType,
) -> (Array[ValType], Array[ValType]) {
  match block_type {
    Empty => ([], [])
    Value(t) => ([], [t])
    TypeIndex(idx) => {
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
}

///|
/// Validation context that tracks both the type stack and unreachable state
struct ValidationCtx {
  stack : Array[ValType]
  mut is_unreachable : Bool
  // Stack of control frames - each frame tracks the expected result types
  // For br validation, we need to know what types the target label expects
  control_stack : Array[(Array[ValType], Array[ValType])] // (params, results) for each control frame
}

///|
fn ValidationCtx::new() -> ValidationCtx {
  { stack: [], is_unreachable: false, control_stack: [] }
}

///|
fn ValidationCtx::push_control(
  self : ValidationCtx,
  params : Array[ValType],
  results : Array[ValType],
) -> Unit {
  self.control_stack.push((params, results))
}

///|
fn ValidationCtx::pop_control(
  self : ValidationCtx,
) -> (Array[ValType], Array[ValType]) {
  self.control_stack.unsafe_pop()
}

///|
fn ValidationCtx::get_label_types(
  self : ValidationCtx,
  label : UInt,
) -> Array[ValType] {
  // Labels are relative depth: 0 is innermost, 1 is next outer, etc.
  let idx = self.control_stack.length() - 1 - label.reinterpret_as_int()
  if idx >= 0 && idx < self.control_stack.length() {
    let (_, results) = self.control_stack[idx]
    results
  } else {
    []
  }
}

///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module_ : Module,
  func_type : FuncType,
  code : Code,
  ctx : ValidationCtx,
  instr : Instr,
) -> Unit raise ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    I32Const(_) => stack.push(I32)
    I64Const(_) => stack.push(I64)
    F32Const(_) => stack.push(F32)
    F64Const(_) => stack.push(F64)

    // Binary operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for binary op",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != I32 || b != I32 {
        raise ValidationError::TypeMismatch(
          "i32 binary operation requires i32 operands",
        )
      }
      stack.push(I32)
    }

    // Comparison operations
    I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for comparison",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != I32 || b != I32 {
        raise ValidationError::TypeMismatch(
          "i32 comparison requires i32 operands",
        )
      }
      stack.push(I32)
    }

    // Unary operations
    I32Eqz | I32Clz | I32Ctz | I32Popcnt | I32Extend8S | I32Extend16S => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected at least 1 value on stack for unary op",
        )
      }
      let a = stack.unsafe_pop()
      if a != I32 {
        raise ValidationError::TypeMismatch(
          "i32 unary operation requires i32 operand",
        )
      }
      stack.push(I32)
    }

    // i64 binary operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for binary op",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != I64 || b != I64 {
        raise ValidationError::TypeMismatch(
          "i64 binary operation requires i64 operands",
        )
      }
      stack.push(I64)
    }

    // i64 comparison operations
    I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for comparison",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != I64 || b != I64 {
        raise ValidationError::TypeMismatch(
          "i64 comparison requires i64 operands",
        )
      }
      stack.push(I32)
    }

    // i64 test operation (returns i32)
    I64Eqz => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected at least 1 value on stack for unary op",
        )
      }
      let a = stack.unsafe_pop()
      if a != I64 {
        raise ValidationError::TypeMismatch("i64.eqz requires i64 operand")
      }
      stack.push(I32)
    }

    // i64 unary operations (return i64)
    I64Clz | I64Ctz | I64Popcnt | I64Extend8S | I64Extend16S | I64Extend32S => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected at least 1 value on stack for unary op",
        )
      }
      let a = stack.unsafe_pop()
      if a != I64 {
        raise ValidationError::TypeMismatch(
          "i64 unary operation requires i64 operand",
        )
      }
      stack.push(I64)
    }

    // i32 to i64 conversion operations
    I64ExtendI32S | I64ExtendI32U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected i32 on stack for i64 extension",
        )
      }
      let a = stack.unsafe_pop()
      if a != I32 {
        raise ValidationError::TypeMismatch(
          "i64 extension requires i32 operand",
        )
      }
      stack.push(I64)
    }

    // f32 comparison operations
    F32Eq | F32Ne | F32Lt | F32Gt | F32Le | F32Ge => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for comparison",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != F32 || b != F32 {
        raise ValidationError::TypeMismatch(
          "f32 comparison requires f32 operands",
        )
      }
      stack.push(I32)
    }

    // f64 comparison operations
    F64Eq | F64Ne | F64Lt | F64Gt | F64Le | F64Ge => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for comparison",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != F64 || b != F64 {
        raise ValidationError::TypeMismatch(
          "f64 comparison requires f64 operands",
        )
      }
      stack.push(I32)
    }

    // f32 unary operations
    F32Abs | F32Neg | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Sqrt => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected at least 1 value on stack for f32 unary op",
        )
      }
      let a = stack.unsafe_pop()
      if a != F32 {
        raise ValidationError::TypeMismatch("f32 unary op requires f32 operand")
      }
      stack.push(F32)
    }

    // f64 unary operations
    F64Abs | F64Neg | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Sqrt => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected at least 1 value on stack for f64 unary op",
        )
      }
      let a = stack.unsafe_pop()
      if a != F64 {
        raise ValidationError::TypeMismatch("f64 unary op requires f64 operand")
      }
      stack.push(F64)
    }

    // f32 binary operations
    F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for f32 binary op",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != F32 || b != F32 {
        raise ValidationError::TypeMismatch(
          "f32 binary op requires f32 operands",
        )
      }
      stack.push(F32)
    }

    // f64 binary operations
    F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected at least 2 values on stack for f64 binary op",
        )
      }
      let b = stack.unsafe_pop()
      let a = stack.unsafe_pop()
      if a != F64 || b != F64 {
        raise ValidationError::TypeMismatch(
          "f64 binary op requires f64 operands",
        )
      }
      stack.push(F64)
    }

    // Conversion operations: i32 -> f32/f64
    F32ConvertI32S | F32ConvertI32U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i32 for convert")
      }
      let a = stack.unsafe_pop()
      if a != I32 {
        raise ValidationError::TypeMismatch("f32.convert_i32 requires i32")
      }
      stack.push(F32)
    }
    F64ConvertI32S | F64ConvertI32U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i32 for convert")
      }
      let a = stack.unsafe_pop()
      if a != I32 {
        raise ValidationError::TypeMismatch("f64.convert_i32 requires i32")
      }
      stack.push(F64)
    }

    // Conversion operations: i64 -> f32/f64
    F32ConvertI64S | F32ConvertI64U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i64 for convert")
      }
      let a = stack.unsafe_pop()
      if a != I64 {
        raise ValidationError::TypeMismatch("f32.convert_i64 requires i64")
      }
      stack.push(F32)
    }
    F64ConvertI64S | F64ConvertI64U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i64 for convert")
      }
      let a = stack.unsafe_pop()
      if a != I64 {
        raise ValidationError::TypeMismatch("f64.convert_i64 requires i64")
      }
      stack.push(F64)
    }

    // Promotion/demotion: f32 <-> f64
    F64PromoteF32 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f32 for promote")
      }
      let a = stack.unsafe_pop()
      if a != F32 {
        raise ValidationError::TypeMismatch("f64.promote_f32 requires f32")
      }
      stack.push(F64)
    }
    F32DemoteF64 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f64 for demote")
      }
      let a = stack.unsafe_pop()
      if a != F64 {
        raise ValidationError::TypeMismatch("f32.demote_f64 requires f64")
      }
      stack.push(F32)
    }

    // Truncation: f32/f64 -> i32/i64
    I32TruncF32S | I32TruncF32U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f32 for trunc")
      }
      let a = stack.unsafe_pop()
      if a != F32 {
        raise ValidationError::TypeMismatch("i32.trunc_f32 requires f32")
      }
      stack.push(I32)
    }
    I32TruncF64S | I32TruncF64U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f64 for trunc")
      }
      let a = stack.unsafe_pop()
      if a != F64 {
        raise ValidationError::TypeMismatch("i32.trunc_f64 requires f64")
      }
      stack.push(I32)
    }
    I64TruncF32S | I64TruncF32U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f32 for trunc")
      }
      let a = stack.unsafe_pop()
      if a != F32 {
        raise ValidationError::TypeMismatch("i64.trunc_f32 requires f32")
      }
      stack.push(I64)
    }
    I64TruncF64S | I64TruncF64U => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f64 for trunc")
      }
      let a = stack.unsafe_pop()
      if a != F64 {
        raise ValidationError::TypeMismatch("i64.trunc_f64 requires f64")
      }
      stack.push(I64)
    }

    // Reinterpret operations
    F32ReinterpretI32 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i32 for reinterpret")
      }
      let a = stack.unsafe_pop()
      if a != I32 {
        raise ValidationError::TypeMismatch("f32.reinterpret_i32 requires i32")
      }
      stack.push(F32)
    }
    F64ReinterpretI64 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected i64 for reinterpret")
      }
      let a = stack.unsafe_pop()
      if a != I64 {
        raise ValidationError::TypeMismatch("f64.reinterpret_i64 requires i64")
      }
      stack.push(F64)
    }
    I32ReinterpretF32 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f32 for reinterpret")
      }
      let a = stack.unsafe_pop()
      if a != F32 {
        raise ValidationError::TypeMismatch("i32.reinterpret_f32 requires f32")
      }
      stack.push(I32)
    }
    I64ReinterpretF64 => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected f64 for reinterpret")
      }
      let a = stack.unsafe_pop()
      if a != F64 {
        raise ValidationError::TypeMismatch("i64.reinterpret_f64 requires f64")
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
        raise ValidationError::TypeMismatch(
          "expected value on stack for local.set",
        )
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      let val_type = stack.unsafe_pop()
      if val_type != local_type {
        raise ValidationError::TypeMismatch(
          "local.set type mismatch: expected \{local_type}, got \{val_type}",
        )
      }
      match instr {
        LocalTee(_) => stack.push(val_type)
        _ => ()
      }
    }

    // Global operations
    GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      if global_idx < 0 || global_idx >= module_.globals.length() {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      stack.push(module_.globals[global_idx].type_.val_type)
    }
    GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      if global_idx < 0 || global_idx >= module_.globals.length() {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected value on stack for global.set",
        )
      }
      let _ = stack.unsafe_pop()

    }

    // Memory operations
    I32Load(_, _) => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "expected address on stack for i32.load",
        )
      }
      let addr = stack.unsafe_pop()
      if addr != I32 {
        raise ValidationError::TypeMismatch("i32.load requires i32 address")
      }
      stack.push(I32)
    }
    I32Store(_, _) => {
      if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "expected address and value on stack for i32.store",
        )
      }
      let value = stack.unsafe_pop()
      let addr = stack.unsafe_pop()
      if addr != I32 || value != I32 {
        raise ValidationError::TypeMismatch(
          "i32.store requires i32 address and value",
        )
      }
    }

    // Block instructions
    Block(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack and push onto block stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        if stack.length() < 1 {
          raise ValidationError::TypeMismatch(
            "block expects parameters on stack",
          )
        }
        let param = stack.unsafe_pop()
        if param != params[i] {
          raise ValidationError::TypeMismatch("block parameter type mismatch")
        }
      }
      // Create new validation context for block
      let block_ctx = ValidationCtx::new()
      // Add parameters to block stack in correct order
      for param in params {
        block_ctx.stack.push(param)
      }
      // Copy parent control stack and add this block's frame
      for frame in ctx.control_stack {
        block_ctx.control_stack.push(frame)
      }
      block_ctx.push_control(params, results)
      // Validate block body
      for block_instr in instrs {
        validate_instruction(module_, func_type, code, block_ctx, block_instr)
      }
      let _ = block_ctx.pop_control()
      // Check block produces correct results
      if block_ctx.is_unreachable {
        // Unreachable code - valid, push expected results
        for result in results {
          stack.push(result)
        }
      } else if block_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - this is a type mismatch
        raise ValidationError::TypeMismatch(
          "block: expected \{results.length()} values, got \{block_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types
        for i = 0; i < results.length(); i = i + 1 {
          if block_ctx.stack[i] != results[i] {
            raise ValidationError::TypeMismatch("block result type mismatch")
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    Loop(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack and push onto loop stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        if stack.length() < 1 {
          raise ValidationError::TypeMismatch(
            "loop expects parameters on stack",
          )
        }
        let param = stack.unsafe_pop()
        if param != params[i] {
          raise ValidationError::TypeMismatch("loop parameter type mismatch")
        }
      }
      // Create new validation context for loop
      let loop_ctx = ValidationCtx::new()
      // Add parameters to loop stack in correct order
      for param in params {
        loop_ctx.stack.push(param)
      }
      // Copy parent control stack and add this loop's frame
      // Note: For loops, br targets the beginning (params), not the end (results)
      for frame in ctx.control_stack {
        loop_ctx.control_stack.push(frame)
      }
      loop_ctx.push_control(params, params) // Loop's br target uses params, not results
      // Validate loop body
      for loop_instr in instrs {
        validate_instruction(module_, func_type, code, loop_ctx, loop_instr)
      }
      let _ = loop_ctx.pop_control()
      // Check loop produces correct results
      if loop_ctx.is_unreachable {
        // Unreachable code - valid
        for result in results {
          stack.push(result)
        }
      } else if loop_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - type mismatch
        raise ValidationError::TypeMismatch(
          "loop: expected \{results.length()} values, got \{loop_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types
        for i = 0; i < results.length(); i = i + 1 {
          if loop_ctx.stack[i] != results[i] {
            raise ValidationError::TypeMismatch("loop result type mismatch")
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    If(block_type, then_instrs, else_instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop condition
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("if expects condition on stack")
      }
      let cond = stack.unsafe_pop()
      if cond != I32 {
        raise ValidationError::TypeMismatch("if condition must be i32")
      }
      // Pop parameters from parent stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        if stack.length() < 1 {
          raise ValidationError::TypeMismatch("if expects parameters on stack")
        }
        let param = stack.unsafe_pop()
        if param != params[i] {
          raise ValidationError::TypeMismatch("if parameter type mismatch")
        }
      }
      // Validate then branch
      let then_ctx = ValidationCtx::new()
      for param in params {
        then_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        then_ctx.control_stack.push(frame)
      }
      then_ctx.push_control(params, results)
      for then_instr in then_instrs {
        validate_instruction(module_, func_type, code, then_ctx, then_instr)
      }
      let _ = then_ctx.pop_control()
      // Check then branch produces correct results
      if then_ctx.is_unreachable {
        // Unreachable - valid
      } else if then_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if then branch: expected \{results.length()} values, got \{then_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types
        for i = 0; i < results.length(); i = i + 1 {
          if then_ctx.stack[i] != results[i] {
            raise ValidationError::TypeMismatch(
              "if then branch result type mismatch",
            )
          }
        }
      }
      // Validate else branch
      let else_ctx = ValidationCtx::new()
      for param in params {
        else_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        else_ctx.control_stack.push(frame)
      }
      else_ctx.push_control(params, results)
      for else_instr in else_instrs {
        validate_instruction(module_, func_type, code, else_ctx, else_instr)
      }
      let _ = else_ctx.pop_control()
      // Check else branch produces correct results
      if else_ctx.is_unreachable {
        // Unreachable - valid
      } else if else_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if else branch: expected \{results.length()} values, got \{else_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types
        for i = 0; i < results.length(); i = i + 1 {
          if else_ctx.stack[i] != results[i] {
            raise ValidationError::TypeMismatch(
              "if else branch result type mismatch",
            )
          }
        }
      }
      // Push results onto parent stack
      for result in results {
        stack.push(result)
      }
    }

    // Control flow
    Return => {
      // Check we have the right values on stack for function return
      if stack.length() < func_type.results.length() {
        raise ValidationError::TypeMismatch(
          "return: expected \{func_type.results.length()} values on stack",
        )
      }
      // Validate result types
      for i = 0; i < func_type.results.length(); i = i + 1 {
        let stack_idx = stack.length() - func_type.results.length() + i
        if stack[stack_idx] != func_type.results[i] {
          raise ValidationError::TypeMismatch("return: result type mismatch")
        }
      }
      // Mark as unreachable and clear stack
      ctx.is_unreachable = true
      stack.clear()
    }
    Br(label) => {
      // Unconditional branch - validate we have required values for target
      let target_types = ctx.get_label_types(label)
      if stack.length() < target_types.length() {
        raise ValidationError::TypeMismatch(
          "br: expected \{target_types.length()} values on stack for branch target",
        )
      }
      // Validate types for the branch target
      for i = 0; i < target_types.length(); i = i + 1 {
        let stack_idx = stack.length() - target_types.length() + i
        if stack[stack_idx] != target_types[i] {
          raise ValidationError::TypeMismatch("br: branch target type mismatch")
        }
      }
      // Mark as unreachable and clear stack
      ctx.is_unreachable = true
      stack.clear()
    }
    BrIf(_label) => {
      // Conditional branch - pop i32 condition
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "br_if expects i32 condition on stack",
        )
      }
      let cond = stack.unsafe_pop()
      if cond != I32 {
        raise ValidationError::TypeMismatch("br_if condition must be i32")
      }
      // Stack continues after (not unreachable)
    }
    BrTable(_labels, default_label) => {
      // Table branch - pop i32 index
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "br_table expects i32 index on stack",
        )
      }
      let index = stack.unsafe_pop()
      if index != I32 {
        raise ValidationError::TypeMismatch("br_table index must be i32")
      }
      // Validate we have required values for branch targets
      let target_types = ctx.get_label_types(default_label)
      if stack.length() < target_types.length() {
        raise ValidationError::TypeMismatch(
          "br_table: expected \{target_types.length()} values on stack for branch target",
        )
      }
      // Code after is unreachable
      ctx.is_unreachable = true
      stack.clear()
    }
    Drop => {
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for drop")
      }
      let _ = stack.unsafe_pop()

    }
    Select => {
      // Pop condition (i32), then two values of same type, push one back
      if stack.length() < 3 {
        raise ValidationError::TypeMismatch("select expects 3 values on stack")
      }
      let cond = stack.unsafe_pop()
      if cond != I32 {
        raise ValidationError::TypeMismatch("select condition must be i32")
      }
      let val2 = stack.unsafe_pop()
      let val1 = stack.unsafe_pop()
      // Both values should be same type
      if val1 != val2 {
        raise ValidationError::TypeMismatch("select values must have same type")
      }
      // Push the selected value type back
      stack.push(val1)
    }
    Nop => ()
    Call(func_idx) => {
      let idx = func_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.funcs.length() {
        raise ValidationError::InvalidFunctionIndex(idx)
      }
      let type_idx = module_.funcs[idx].reinterpret_as_int()
      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        if stack.length() < 1 {
          raise ValidationError::TypeMismatch("call expects arguments on stack")
        }
        let arg = stack.unsafe_pop()
        if arg != func_type_called.params[i] {
          raise ValidationError::TypeMismatch("call argument type mismatch")
        }
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    CallIndirect(type_idx, _table_idx) => {
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "call_indirect expects table index on stack",
        )
      }
      let table_index = stack.unsafe_pop()
      if table_index != I32 {
        raise ValidationError::TypeMismatch(
          "call_indirect table index must be i32",
        )
      }
      // Pop arguments from stack
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        if stack.length() < 1 {
          raise ValidationError::TypeMismatch(
            "call_indirect expects arguments on stack",
          )
        }
        let arg = stack.unsafe_pop()
        if arg != func_type_called.params[i] {
          raise ValidationError::TypeMismatch(
            "call_indirect argument type mismatch",
          )
        }
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    _ => ()
  }
}

///|
/// Validate a single function
fn validate_function(
  module_ : Module,
  func_type : FuncType,
  code : Code,
) -> Unit raise ValidationError {
  // Create validation context
  let ctx = ValidationCtx::new()
  // Push function-level control frame with empty params and function results
  ctx.push_control([], func_type.results)

  // Validate each instruction in the function body
  for instr in code.body.instrs {
    validate_instruction(module_, func_type, code, ctx, instr)
  }

  // Check final stack matches return type
  let stack = ctx.stack
  if ctx.is_unreachable {
    // Unreachable code - valid regardless of stack
  } else if stack.length() != func_type.results.length() {
    // Stack size doesn't match expected return values
    if stack.length() < func_type.results.length() {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    } else if func_type.results.length() == 0 && stack.length() > 0 {
      raise ValidationError::StackSizeMismatch(
        "function: void function should not have values on stack, got \{stack.length()}",
      )
    } else {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    }
  } else {
    // Check types from top of stack
    for i = 0; i < func_type.results.length(); i = i + 1 {
      if stack[i] != func_type.results[i] {
        raise ValidationError::TypeMismatch("function return type mismatch")
      }
    }
  }
}
