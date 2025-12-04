///|
/// Runtime error types
pub suberror RuntimeError {
  DivisionByZero
  IntegerOverflow
  StackUnderflow
  MemoryOutOfBounds
  InvalidType(String)
  FunctionNotFound(String)
}

///|
/// Validation error types
pub suberror ValidationError {
  TypeMismatch(String)
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  StackSizeMismatch(String)
}

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
}

///|
/// Load a WebAssembly module into the runtime
pub fn Runtime::load(m : Module) -> Runtime {
  Runtime::{ module_: m }
}

///|
/// Call an exported function by name with arguments
pub fn Runtime::call(
  r : Runtime,
  func_name : Bytes,
  args : FixedArray[Value],
) -> Value raise RuntimeError {
  // Find exported function by name
  let func_name_str = func_name.to_string()
  let mut func_idx : Int? = None
  for i = 0; i < r.module_.exports.length(); i = i + 1 {
    let exp = r.module_.exports[i]
    if exp.name == func_name_str {
      match exp.desc {
        Func(idx) => {
          func_idx = Some(idx.reinterpret_as_int())
          break
        }
        _ => continue
      }
    }
  }
  match func_idx {
    None => raise RuntimeError::FunctionNotFound(func_name_str)
    Some(idx) => {
      // Create execution context
      let ctx = ExecutionContext::new(r.module_)

      // Execute the function
      let result = execute_function(ctx, idx, args)

      // Return the result or a default value
      match result {
        Some(v) => v
        None => I32(0U) // Default return value if function has no result
      }
    }
  }
}

///|
priv struct ExecutionContext {
  module_ : Module
  stack : Array[Value] // Operand stack
  mut locals : Array[Value] // Current function locals (reassigned per function call)
  memory : Array[Byte] // Linear memory
  globals : Array[Value] // Global variables
  mut pc : Int // Program counter
}

///|
fn ExecutionContext::new(module : Module) -> ExecutionContext {
  // Initialize memory
  let memory_size = if module.mems.length() > 0 {
    module.mems[0].limits.min.reinterpret_as_int() * 65536 // Pages to bytes
  } else {
    0
  }
  let memory = Array::make(memory_size, b'\x00')

  // Initialize globals
  let globals = []
  for i = 0; i < module.globals.length(); i = i + 1 {
    let global = module.globals[i]
    // Evaluate init expression
    let value = eval_const_expr(global.init, [])
    globals.push(value)
  }

  // Apply data segments
  for i = 0; i < module.datas.length(); i = i + 1 {
    let data = module.datas[i]
    let offset = eval_const_expr(data.offset, [])
    match offset {
      I32(off) => {
        let off_int = off.reinterpret_as_int()
        for j = 0; j < data.init.length(); j = j + 1 {
          memory[off_int + j] = data.init[j]
        }
      }
      _ => abort("data offset must be i32")
    }
  }
  { module_: module, stack: [], locals: [], memory, globals, pc: 0 }
}

///|
fn eval_const_expr(expr : Expr, globals : Array[Value]) -> Value {
  // Simple constant expression evaluator for init expressions
  if expr.instrs.length() == 0 {
    abort("empty init expression")
  }
  match expr.instrs[0] {
    I32Const(v) => I32(v)
    I64Const(v) => I64(v)
    F32Const(v) => F32(v)
    F64Const(v) => F64(v)
    GlobalGet(idx) =>
      if idx.to_int() < globals.length() {
        globals[idx.to_int()]
      } else {
        abort("global index out of bounds in init expression")
      }
    _ => abort("unsupported init expression")
  }
}

///|
fn ExecutionContext::push(self : ExecutionContext, value : Value) -> Unit {
  self.stack.push(value)
}

///|
fn ExecutionContext::pop(self : ExecutionContext) -> Value raise RuntimeError {
  if self.stack.length() == 0 {
    raise RuntimeError::StackUnderflow
  }
  self.stack.pop_exn()
}

///|
fn ExecutionContext::pop_i32(self : ExecutionContext) -> UInt raise RuntimeError {
  match self.pop() {
    I32(v) => v
    _ => raise RuntimeError::InvalidType("expected i32")
  }
}

///|
fn ExecutionContext::pop_i64(self : ExecutionContext) -> UInt64 raise RuntimeError {
  match self.pop() {
    I64(v) => v
    _ => raise RuntimeError::InvalidType("expected i64")
  }
}

///|
fn ExecutionContext::pop_f32(self : ExecutionContext) -> Float raise RuntimeError {
  match self.pop() {
    F32(v) => v
    _ => raise RuntimeError::InvalidType("expected f32")
  }
}

///|
fn ExecutionContext::pop_f64(self : ExecutionContext) -> Double raise RuntimeError {
  match self.pop() {
    F64(v) => v
    _ => raise RuntimeError::InvalidType("expected f64")
  }
}

///|
fn ExecutionContext::get_local(self : ExecutionContext, idx : UInt) -> Value {
  self.locals[idx.reinterpret_as_int()]
}

///|
fn ExecutionContext::set_local(
  self : ExecutionContext,
  idx : UInt,
  value : Value,
) -> Unit {
  self.locals[idx.reinterpret_as_int()] = value
}

///|
fn ExecutionContext::get_global(self : ExecutionContext, idx : UInt) -> Value {
  self.globals[idx.reinterpret_as_int()]
}

///|
fn ExecutionContext::set_global(
  self : ExecutionContext,
  idx : UInt,
  value : Value,
) -> Unit {
  self.globals[idx.reinterpret_as_int()] = value
}

///|
fn ExecutionContext::load_i32(self : ExecutionContext, addr : Int) -> UInt raise RuntimeError {
  if addr + 4 > self.memory.length() {
    raise RuntimeError::MemoryOutOfBounds
  }
  let b0 = self.memory[addr].to_uint()
  let b1 = self.memory[addr + 1].to_uint()
  let b2 = self.memory[addr + 2].to_uint()
  let b3 = self.memory[addr + 3].to_uint()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn ExecutionContext::store_i32(
  self : ExecutionContext,
  addr : Int,
  value : UInt,
) -> Unit raise RuntimeError {
  if addr + 4 > self.memory.length() {
    raise RuntimeError::MemoryOutOfBounds
  }
  self.memory[addr] = value.land(0xFF).to_byte()
  self.memory[addr + 1] = ((value >> 8).land(0xFF)).to_byte()
  self.memory[addr + 2] = ((value >> 16).land(0xFF)).to_byte()
  self.memory[addr + 3] = ((value >> 24).land(0xFF)).to_byte()
}

///|
fn execute_instr(ctx : ExecutionContext, instr : Instr) -> Bool raise RuntimeError {
  // Returns true if should continue, false if should return
  match instr {
    // Numeric constants
    I32Const(v) => {
      ctx.push(I32(v))
      true
    }
    I64Const(v) => {
      ctx.push(I64(v))
      true
    }
    F32Const(v) => {
      ctx.push(F32(v))
      true
    }
    F64Const(v) => {
      ctx.push(F64(v))
      true
    }

    // Local variables
    LocalGet(idx) => {
      ctx.push(ctx.get_local(idx))
      true
    }
    LocalSet(idx) => {
      let value = ctx.pop()
      ctx.set_local(idx, value)
      true
    }
    LocalTee(idx) => {
      let value = ctx.pop()
      ctx.set_local(idx, value)
      ctx.push(value)
      true
    }

    // Global variables
    GlobalGet(idx) => {
      ctx.push(ctx.get_global(idx))
      true
    }
    GlobalSet(idx) => {
      let value = ctx.pop()
      ctx.set_global(idx, value)
      true
    }

    // i32 arithmetic
    I32Add => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a + b))
      true
    }
    I32Sub => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a - b))
      true
    }
    I32Mul => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a * b))
      true
    }
    I32DivS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      if b == 0 {
        raise RuntimeError::DivisionByZero
      }
      // Check for integer overflow: INT32_MIN / -1 = overflow
      if a == 0x80000000U && b == 0xFFFFFFFFU {
        raise RuntimeError::IntegerOverflow
      }
      // Signed division: reinterpret as signed, divide, reinterpret back
      let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
      ctx.push(I32(result))
      true
    }
    I32DivU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      if b == 0 {
        raise RuntimeError::DivisionByZero
      }
      // Unsigned division works directly on UInt
      ctx.push(I32(a / b))
      true
    }
    I32RemS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      if b == 0 {
        raise RuntimeError::DivisionByZero
      }
      // Signed remainder: reinterpret as signed, compute remainder, reinterpret back
      let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
      ctx.push(I32(result))
      true
    }
    I32RemU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      if b == 0 {
        raise RuntimeError::DivisionByZero
      }
      // Unsigned remainder works directly on UInt
      ctx.push(I32(a % b))
      true
    }

    // i32 bitwise operations
    I32And => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a.land(b)))
      true
    }
    I32Or => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a.lor(b)))
      true
    }
    I32Xor => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(a.lxor(b)))
      true
    }

    // i32 shift operations
    I32Shl => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Shift amount is modulo 32
      let shift = b.land(0x1F)
      ctx.push(I32(a << shift.to_int()))
      true
    }
    I32ShrS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Shift amount is modulo 32
      let shift = b.land(0x1F)
      // Signed right shift: reinterpret as signed, shift, reinterpret back
      let result = (a.reinterpret_as_int() >> shift.to_int()).reinterpret_as_uint()
      ctx.push(I32(result))
      true
    }
    I32ShrU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Shift amount is modulo 32
      let shift = b.land(0x1F)
      // Unsigned right shift
      ctx.push(I32(a.lsr(shift.to_int())))
      true
    }

    // i32 rotation operations
    I32Rotl => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Rotation amount is modulo 32
      let rotation = b.land(0x1F).to_int()
      let result = (a << rotation).lor(a.lsr(32 - rotation))
      ctx.push(I32(result))
      true
    }
    I32Rotr => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Rotation amount is modulo 32
      let rotation = b.land(0x1F).to_int()
      let result = a.lsr(rotation).lor(a << (32 - rotation))
      ctx.push(I32(result))
      true
    }

    // i32 comparison
    I32Eq => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(if a == b { 1 } else { 0 }))
      true
    }
    I32Ne => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      ctx.push(I32(if a != b { 1 } else { 0 }))
      true
    }
    I32LtS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Signed comparison: reinterpret as signed Int
      ctx.push(I32(if a.reinterpret_as_int() < b.reinterpret_as_int() { 1 } else { 0 }))
      true
    }
    I32GtS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Signed comparison: reinterpret as signed Int
      ctx.push(I32(if a.reinterpret_as_int() > b.reinterpret_as_int() { 1 } else { 0 }))
      true
    }
    I32LeS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Signed comparison: reinterpret as signed Int
      ctx.push(I32(if a.reinterpret_as_int() <= b.reinterpret_as_int() { 1 } else { 0 }))
      true
    }
    I32GeS => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Signed comparison: reinterpret as signed Int
      ctx.push(I32(if a.reinterpret_as_int() >= b.reinterpret_as_int() { 1 } else { 0 }))
      true
    }
    I32LtU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Unsigned comparison
      ctx.push(I32(if a < b { 1 } else { 0 }))
      true
    }
    I32GtU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Unsigned comparison
      ctx.push(I32(if a > b { 1 } else { 0 }))
      true
    }
    I32LeU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Unsigned comparison
      ctx.push(I32(if a <= b { 1 } else { 0 }))
      true
    }
    I32GeU => {
      let b = ctx.pop_i32()
      let a = ctx.pop_i32()
      // Unsigned comparison
      ctx.push(I32(if a >= b { 1 } else { 0 }))
      true
    }

    // i32 unary operations
    I32Eqz => {
      let a = ctx.pop_i32()
      ctx.push(I32(if a == 0 { 1 } else { 0 }))
      true
    }
    I32Clz => {
      let a = ctx.pop_i32()
      ctx.push(I32(a.clz().reinterpret_as_uint()))
      true
    }
    I32Ctz => {
      let a = ctx.pop_i32()
      ctx.push(I32(a.ctz().reinterpret_as_uint()))
      true
    }
    I32Popcnt => {
      let a = ctx.pop_i32()
      ctx.push(I32(a.popcnt().reinterpret_as_uint()))
      true
    }

    // i32 sign extension operations
    I32Extend8S => {
      let a = ctx.pop_i32()
      // Extract low 8 bits and sign extend
      let byte = a.land(0xFF)
      let result = if byte.land(0x80) != 0 {
        // Negative: sign extend with 1s
        byte.lor(0xFFFFFF00U)
      } else {
        // Positive: already correct
        byte
      }
      ctx.push(I32(result))
      true
    }
    I32Extend16S => {
      let a = ctx.pop_i32()
      // Extract low 16 bits and sign extend
      let half = a.land(0xFFFF)
      let result = if half.land(0x8000) != 0 {
        // Negative: sign extend with 1s
        half.lor(0xFFFF0000U)
      } else {
        // Positive: already correct
        half
      }
      ctx.push(I32(result))
      true
    }

    // i64 arithmetic
    I64Add => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a + b))
      true
    }
    I64Sub => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a - b))
      true
    }
    I64Mul => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a * b))
      true
    }
    I64DivS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      if b == 0UL {
        raise RuntimeError::DivisionByZero
      }
      // Check for overflow: INT64_MIN / -1
      if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
        raise RuntimeError::IntegerOverflow
      }
      let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
      ctx.push(I64(result))
      true
    }
    I64DivU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      if b == 0UL {
        raise RuntimeError::DivisionByZero
      }
      ctx.push(I64(a / b))
      true
    }
    I64RemS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      if b == 0UL {
        raise RuntimeError::DivisionByZero
      }
      let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
      ctx.push(I64(result))
      true
    }
    I64RemU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      if b == 0UL {
        raise RuntimeError::DivisionByZero
      }
      ctx.push(I64(a % b))
      true
    }

    // i64 bitwise operations
    I64And => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a.land(b)))
      true
    }
    I64Or => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a.lor(b)))
      true
    }
    I64Xor => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I64(a.lxor(b)))
      true
    }

    // i64 shift operations
    I64Shl => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      let shift = b.land(0x3FUL)
      ctx.push(I64(a << shift.to_int()))
      true
    }
    I64ShrS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      let shift = b.land(0x3FUL)
      let result = (a.reinterpret_as_int64() >> shift.to_int()).reinterpret_as_uint64()
      ctx.push(I64(result))
      true
    }
    I64ShrU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      let shift = b.land(0x3FUL)
      ctx.push(I64(a.lsr(shift.to_int())))
      true
    }

    // i64 rotation operations
    I64Rotl => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      let rotation = b.land(0x3FUL).to_int()
      let result = (a << rotation).lor(a.lsr(64 - rotation))
      ctx.push(I64(result))
      true
    }
    I64Rotr => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      let rotation = b.land(0x3FUL).to_int()
      let result = a.lsr(rotation).lor(a << (64 - rotation))
      ctx.push(I64(result))
      true
    }

    // i64 comparison operations
    I64Eq => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a == b { 1U } else { 0U }))
      true
    }
    I64Ne => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a != b { 1U } else { 0U }))
      true
    }
    I64LtS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a.reinterpret_as_int64() < b.reinterpret_as_int64() { 1U } else { 0U }))
      true
    }
    I64LtU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a < b { 1U } else { 0U }))
      true
    }
    I64GtS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a.reinterpret_as_int64() > b.reinterpret_as_int64() { 1U } else { 0U }))
      true
    }
    I64GtU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a > b { 1U } else { 0U }))
      true
    }
    I64LeS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a.reinterpret_as_int64() <= b.reinterpret_as_int64() { 1U } else { 0U }))
      true
    }
    I64LeU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a <= b { 1U } else { 0U }))
      true
    }
    I64GeS => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a.reinterpret_as_int64() >= b.reinterpret_as_int64() { 1U } else { 0U }))
      true
    }
    I64GeU => {
      let b = ctx.pop_i64()
      let a = ctx.pop_i64()
      ctx.push(I32(if a >= b { 1U } else { 0U }))
      true
    }

    // i64 unary operations
    I64Eqz => {
      let a = ctx.pop_i64()
      ctx.push(I32(if a == 0UL { 1U } else { 0U }))
      true
    }
    I64Clz => {
      let a = ctx.pop_i64()
      ctx.push(I64(a.clz().to_uint64()))
      true
    }
    I64Ctz => {
      let a = ctx.pop_i64()
      ctx.push(I64(a.ctz().to_uint64()))
      true
    }
    I64Popcnt => {
      let a = ctx.pop_i64()
      ctx.push(I64(a.popcnt().to_uint64()))
      true
    }

    // i64 sign extension operations
    I64Extend8S => {
      let a = ctx.pop_i64()
      // Extract low 8 bits and sign extend
      let byte = a.land(0xFFUL)
      let result = if byte.land(0x80UL) != 0UL {
        // Negative: sign extend with 1s
        byte.lor(0xFFFFFFFFFFFFFF00UL)
      } else {
        // Positive: already correct
        byte
      }
      ctx.push(I64(result))
      true
    }
    I64Extend16S => {
      let a = ctx.pop_i64()
      // Extract low 16 bits and sign extend
      let half = a.land(0xFFFFUL)
      let result = if half.land(0x8000UL) != 0UL {
        // Negative: sign extend with 1s
        half.lor(0xFFFFFFFFFFFF0000UL)
      } else {
        // Positive: already correct
        half
      }
      ctx.push(I64(result))
      true
    }
    I64Extend32S => {
      let a = ctx.pop_i64()
      // Extract low 32 bits and sign extend
      let word = a.land(0xFFFFFFFFUL)
      let result = if word.land(0x80000000UL) != 0UL {
        // Negative: sign extend with 1s
        word.lor(0xFFFFFFFF00000000UL)
      } else {
        // Positive: already correct
        word
      }
      ctx.push(I64(result))
      true
    }

    // Memory operations
    I32Load(_align, offset) => {
      let addr = ctx.pop_i32()
      let value = ctx.load_i32(addr.reinterpret_as_int() + offset.reinterpret_as_int())
      ctx.push(I32(value))
      true
    }
    I32Store(_align, offset) => {
      let value = ctx.pop_i32()
      let addr = ctx.pop_i32()
      ctx.store_i32(addr.reinterpret_as_int() + offset.reinterpret_as_int(), value)
      true
    }

    // Control flow
    Return => false
    Drop => {
      let _ = ctx.pop()
      true
    }
    Nop => true
    _ => abort("instruction \{instr} not implemented")
  }
}

///|
fn execute_function(
  ctx : ExecutionContext,
  func_idx : Int,
  args : FixedArray[Value],
) -> Value? raise RuntimeError {
  // Get function type and code
  let mod = ctx.module_
  let type_idx = mod.funcs[func_idx].reinterpret_as_int()
  let func_type = mod.types[type_idx]
  let code = mod.codes[func_idx]

  // Initialize locals with parameters and local variables
  ctx.locals = []

  // Add parameters
  for i = 0; i < args.length(); i = i + 1 {
    ctx.locals.push(args[i])
  }

  // Add local variables (initialized to zero)
  for i = 0; i < code.locals.length(); i = i + 1 {
    match code.locals[i] {
      I32 => ctx.locals.push(I32(0U))
      I64 => ctx.locals.push(I64(0UL))
      F32 => ctx.locals.push(F32(0.0))
      F64 => ctx.locals.push(F64(0.0))
      FuncRef => ctx.locals.push(Ref(None))
      ExternRef => ctx.locals.push(Ref(None))
      _ => abort("unsupported local type")
    }
  }

  // Execute instructions
  for i = 0; i < code.body.instrs.length(); i = i + 1 {
    let should_continue = execute_instr(ctx, code.body.instrs[i])
    if not(should_continue) {
      break
    }
  }

  // Return value (if any)
  if func_type.results.length() > 0 {
    Some(ctx.pop())
  } else {
    None
  }
}

///|
