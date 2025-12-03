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
) -> Value {
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
    None => abort("exported function '\{func_name_str}' not found")
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
fn ExecutionContext::pop(self : ExecutionContext) -> Value {
  if self.stack.length() == 0 {
    abort("stack underflow")
  }
  self.stack.pop_exn()
}

///|
fn ExecutionContext::pop_i32(self : ExecutionContext) -> UInt {
  match self.pop() {
    I32(v) => v
    _ => abort("expected i32")
  }
}

///|
fn ExecutionContext::pop_i64(self : ExecutionContext) -> UInt64 {
  match self.pop() {
    I64(v) => v
    _ => abort("expected i64")
  }
}

///|
fn ExecutionContext::pop_f32(self : ExecutionContext) -> Float {
  match self.pop() {
    F32(v) => v
    _ => abort("expected f32")
  }
}

///|
fn ExecutionContext::pop_f64(self : ExecutionContext) -> Double {
  match self.pop() {
    F64(v) => v
    _ => abort("expected f64")
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
fn ExecutionContext::load_i32(self : ExecutionContext, addr : Int) -> UInt {
  if addr + 4 > self.memory.length() {
    abort("memory access out of bounds")
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
) -> Unit {
  if addr + 4 > self.memory.length() {
    abort("memory access out of bounds")
  }
  self.memory[addr] = value.land(0xFF).to_byte()
  self.memory[addr + 1] = ((value >> 8).land(0xFF)).to_byte()
  self.memory[addr + 2] = ((value >> 16).land(0xFF)).to_byte()
  self.memory[addr + 3] = ((value >> 24).land(0xFF)).to_byte()
}

///|
fn execute_instr(ctx : ExecutionContext, instr : Instr) -> Bool {
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
        abort("division by zero")
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
        abort("division by zero")
      }
      // Unsigned division works directly on UInt
      ctx.push(I32(a / b))
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
) -> Value? {
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
