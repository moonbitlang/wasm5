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
/// Runtime structure that holds a loaded WebAssembly module
pub struct Runtime {
  module_ : Module
  ops : Array[MInstr]
  stack : Array[Value]
  mut locals : Array[Value]
  mut pc : Int
  call_stack : Array[CallFrame]
  branch_targets : Array[Int] // Stack of branch target PCs (for br instructions)
  memory : Array[Byte] // Linear memory
  globals : Array[Value] // Global variables
}

///|
/// Load a WebAssembly module into the runtime
pub fn Runtime::load(m : Module) -> Runtime raise RuntimeError {
  // Initialize memory
  let memory_size = if m.mems.length() > 0 {
    m.mems[0].limits.min.reinterpret_as_int() * 65536 // Pages to bytes
  } else {
    0
  }
  let memory = Array::make(memory_size, b'\x00')
  // Initialize globals
  let globals : Array[Value] = []
  for i = 0; i < m.globals.length(); i = i + 1 {
    let global = m.globals[i]
    let value = eval_const_expr(global.init, [])
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
  Runtime::{
    module_: m,
    ops: [],
    stack: [],
    locals: [],
    pc: 0,
    call_stack: [],
    branch_targets: [],
    memory,
    globals,
  }
}

///|
fn eval_const_expr(
  expr : Expr,
  globals : Array[Value],
) -> Value raise RuntimeError {
  // Simple constant expression evaluator for init expressions
  if expr.instrs.length() == 0 {
    raise RuntimeError::UnsupportedInitExpression("empty init expression")
  }
  match expr.instrs[0] {
    I32Const(v) => I32(v)
    I64Const(v) => I64(v)
    F32Const(v) => F32(v)
    F64Const(v) => F64(v)
    GlobalGet(idx) => {
      let idx_int = idx.reinterpret_as_int()
      guard idx_int >= 0 && idx_int < globals.length() else {
        raise RuntimeError::UnsupportedInitExpression(
          "global index out of bounds in init expression",
        )
      }
      globals[idx_int]
    }
    _ =>
      raise RuntimeError::UnsupportedInitExpression(
        "unsupported init expression: \{expr.instrs[0]}",
      )
  }
}
