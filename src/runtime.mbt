///|
/// Runtime error types
pub suberror RuntimeError {
  DivisionByZero
  IntegerOverflow
  StackUnderflow
  MemoryOutOfBounds
  InvalidType(String)
  FunctionNotFound(String)
  Branch(UInt) // Internal: branch control flow (label depth)
  UnimplementedInstruction(String) // Instruction not yet implemented
  Unreachable // Unreachable instruction executed
  FunctionNotCompiled(String) // Function not compiled
  UnsupportedLocalType(String) // Unsupported local type
  UnsupportedInitExpression(String) // Unsupported init expression
} derive(Show)

///|
/// Parse error types
pub suberror ParseError {
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
} derive(Show)

///|
/// Validation error types
pub suberror ValidationError {
  TypeMismatch(String)
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  StackSizeMismatch(String)
  InvalidAlignment(String)
  UnknownLabel(Int)
  InvalidStartFunction(String)
  UnknownMemory(Int)
  InvalidMemorySize(String)
  ImmutableGlobal(Int)
  DuplicateExport(String)
  UnknownExportedFunction(Int)
  UnknownExportedMemory(Int)
  UnknownExportedTable(Int)
  UnknownExportedGlobal(Int)
} derive(Show)

///|
/// Runtime value type
pub(all) enum Value {
  I32(UInt)
  I64(UInt64)
  F32(Float)
  F64(Double)
  Ref(Int?) // For FuncRef and ExternRef (using index or null)
} derive(Eq, Show)

///|
/// Table with its limits
struct RuntimeTable {
  data : Array[Int?] // Table data (function indices, None = null ref)
  max : UInt? // Maximum size limit (None = no limit)
}

///|
struct ImportedFunc {
  arity : UInt
  func : (Array[Value]) -> Array[Value]
}

///|
/// Runtime structure that holds a loaded WebAssembly module
pub struct Runtime {
  module_ : Module
  ops : Array[MInstr]
  stack : Array[Value]
  mut locals : Array[Value]
  mut pc : Int
  call_stack : Array[CallFrame]
  memory : Array[Byte] // Linear memory
  globals : Array[Value] // Global variables
  tables : Array[RuntimeTable] // Tables with limits
  imported_funcs : Array[ImportedFunc] // Imported functions
}

///|
/// Load a WebAssembly module into the runtime
pub fn Runtime::load(m : Module) -> Runtime raise RuntimeError {
  // Initialize memory
  // Limit to 256 pages (16MB) to avoid memory allocation issues
  // WebAssembly spec allows up to 65536 pages (4GB), but we cap it for practical reasons
  let max_pages : UInt = 256
  let memory_size = if m.mems.length() > 0 {
    let pages = m.mems[0].limits.min
    let capped_pages = if pages > max_pages { max_pages } else { pages }
    capped_pages.reinterpret_as_int() * 65536
  } else {
    0
  }
  let memory = Array::make(memory_size, b'\x00')
  // Initialize globals
  // First, add imported globals with default values (since we don't have a host environment)
  let globals : Array[Value] = []
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Global(gt) =>
        match gt.val_type {
          ValType::I32 => globals.push(Value::I32(666U)) // spectest global_i32 = 666
          ValType::I64 => globals.push(Value::I64(666UL)) // spectest global_i64 = 666
          ValType::F32 => globals.push(Value::F32(0.0))
          ValType::F64 => globals.push(Value::F64(0.0))
          ValType::FuncRef => globals.push(Value::Ref(None))
          ValType::ExternRef => globals.push(Value::Ref(None))
          _ => globals.push(Value::I32(0U))
        }
      _ => ()
    }
  }
  // Then add local globals
  for i = 0; i < m.globals.length(); i = i + 1 {
    let global = m.globals[i]
    let value = eval_const_expr(global.init, globals)
    globals.push(value)
  }
  // Initialize data segments (copy data into memory)
  for data in m.datas {
    // Evaluate offset expression to get the starting address
    let offset_value = eval_const_expr(data.offset, globals)
    let offset = match offset_value {
      I32(v) => v.reinterpret_as_int()
      _ =>
        raise RuntimeError::UnsupportedInitExpression(
          "data segment offset must be i32",
        )
    }
    // Copy data bytes into memory
    for i = 0; i < data.init.length(); i = i + 1 {
      let addr = offset + i
      if addr >= 0 && addr < memory.length() {
        memory[addr] = data.init[i]
      }
    }
  }
  // Initialize tables
  let tables : Array[RuntimeTable] = []
  for table in m.tables {
    let table_size = table.limits.min.reinterpret_as_int()
    // Initialize table with null references
    let table_data : Array[Int?] = Array::make(table_size, None)
    tables.push({ data: table_data, max: table.limits.max })
  }
  // Initialize element segments (copy function references into tables)
  for elem in m.elems {
    let table_idx = elem.table_idx.reinterpret_as_int()
    if table_idx >= 0 && table_idx < tables.length() {
      // Evaluate offset expression
      let offset_value = eval_const_expr(elem.offset, globals)
      let offset = match offset_value {
        I32(v) => v.reinterpret_as_int()
        _ =>
          raise RuntimeError::UnsupportedInitExpression(
            "elem segment offset must be i32",
          )
      }
      // Copy function indices into table
      let table = tables[table_idx]
      for i = 0; i < elem.init.length(); i = i + 1 {
        let addr = offset + i
        if addr >= 0 && addr < table.data.length() {
          table.data[addr] = Some(elem.init[i].reinterpret_as_int())
        }
      }
    }
  }
  let imported_funcs : Array[ImportedFunc] = []
  for imp in m.imports {
    let module_ = imp.module_
    let name = imp.name
    match imp.desc {
      Func(_type_idx) =>
        if module_ == "spectest" {
          if name == "print" {
            imported_funcs.push({ arity: 0U, func: spectest_print })
          } else if name == "print_i32" {
            imported_funcs.push({ arity: 1U, func: spectest_print_i32 })
          } else if name == "print_i64" {
            imported_funcs.push({ arity: 1U, func: spectest_print_i64 })
          } else if name == "print_f32" {
            imported_funcs.push({ arity: 1U, func: spectest_print_f32 })
          } else if name == "print_f64" {
            imported_funcs.push({ arity: 1U, func: spectest_print_f64 })
          } else if name == "print_i32_f32" {
            imported_funcs.push({ arity: 2U, func: spectest_print_i32_f32 })
          } else if name == "print_f64_f64" {
            imported_funcs.push({ arity: 2U, func: spectest_print_f64_f64 })
          } else {
            raise RuntimeError::FunctionNotFound(
              "imported function not found: \{module_}.\{name}",
            )
          }
        }
      Table(_) | Mem(_) | Global(_) => ()
    }
  }
  Runtime::{
    module_: m,
    ops: [],
    stack: [],
    locals: [],
    pc: 0,
    call_stack: [],
    memory,
    globals,
    tables,
    imported_funcs,
  }
}

///|
fn eval_const_expr(
  expr : Expr,
  globals : Array[Value],
) -> Value raise RuntimeError {
  // Constant expression evaluator for init expressions
  // Supports multi-instruction expressions (e.g., arithmetic in global inits)
  if expr.instrs.length() == 0 {
    raise RuntimeError::UnsupportedInitExpression("empty init expression")
  }
  let stack : Array[Value] = []
  for instr in expr.instrs {
    match instr {
      I32Const(v) => stack.push(I32(v))
      I64Const(v) => stack.push(I64(v))
      F32Const(v) => stack.push(F32(v))
      F64Const(v) => stack.push(F64(v))
      RefNull(_) => stack.push(Ref(None))
      RefFunc(idx) => stack.push(Ref(Some(idx.reinterpret_as_int())))
      GlobalGet(idx) => {
        let idx_int = idx.reinterpret_as_int()
        guard idx_int >= 0 && idx_int < globals.length() else {
          raise RuntimeError::UnsupportedInitExpression(
            "global index out of bounds in init expression",
          )
        }
        stack.push(globals[idx_int])
      }
      // i32 arithmetic operations
      I32Add => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av + bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.add",
            )
        }
      }
      I32Sub => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av - bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.sub",
            )
        }
      }
      I32Mul => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av * bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.mul",
            )
        }
      }
      // i64 arithmetic operations
      I64Add => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av + bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.add",
            )
        }
      }
      I64Sub => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av - bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.sub",
            )
        }
      }
      I64Mul => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av * bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.mul",
            )
        }
      }
      _ =>
        raise RuntimeError::UnsupportedInitExpression(
          "unsupported init expression instruction: \{instr}",
        )
    }
  }
  guard stack.length() == 1 else {
    raise RuntimeError::UnsupportedInitExpression(
      "init expression should produce exactly one value",
    )
  }
  stack[0]
}

///|
fn spectest_print(args : Array[Value]) -> Array[Value] {
  guard args is []
  []
}

///|
fn spectest_print_i32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [I32(v)]
  println("\{v.reinterpret_as_int()} : i32")
  []
}

///|
fn spectest_print_i64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [I64(v)]
  println("\{v.reinterpret_as_int64()} : i64")
  []
}

///|
fn spectest_print_f32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [F32(v)]
  println("\{v} : f32")
  []
}

///|
fn spectest_print_f64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [F64(v)]
  println("\{v} : f64")
  []
}

///|
fn spectest_print_i32_f32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 2
  guard args is [I32(iv), F32(fv)]
  println("\{iv.reinterpret_as_int()} : i32, \{fv} : f32")
  []
}

///|
fn spectest_print_f64_f64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 2
  guard args is [F64(fv1), F64(fv2)]
  println("\{fv1} : f64, \{fv2} : f64")
  []
}
