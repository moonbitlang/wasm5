///|
/// Intermediate instruction for threaded interpreter
enum MInstr {
  WasmInstr((Runtime) -> Unit)
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Advance to next instruction and execute it
fn Runtime::next(self : Runtime) -> Unit {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is WasmInstr(f)
  f(self)
}

///|
/// Emit an instruction to the ops array
fn Runtime::emit(self : Runtime, instr : MInstr) -> Unit {
  self.ops.push(instr)
}

///|
/// Read immediate i32 value and advance PC
fn Runtime::read_imm_i32(self : Runtime) -> UInt {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateI32(value)
  value
}

///|
/// Read immediate index value and advance PC
fn Runtime::read_imm_idx(self : Runtime) -> Int {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateIdx(value)
  value
}

// ============================================================================
// Instruction implementations
// ============================================================================

///|
/// i32.const: push immediate i32 value
fn op_i32_const(rt : Runtime) -> Unit {
  let value = rt.read_imm_i32()
  rt.stack.push(Value::I32(value))
  rt.next()
}

///|
/// i32.add: pop two i32 values, push sum
fn op_i32_add(rt : Runtime) -> Unit {
  let b = rt.stack.unsafe_pop()
  let a = rt.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) =>
      rt.stack.push(Value::I32(a_val + b_val))
    _ => abort("Type error in i32.add")
  }
  rt.next()
}

///|
/// local.get: push local variable value
fn op_local_get(rt : Runtime) -> Unit {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.locals[idx])
  rt.next()
}

///|
/// local.set: pop value and store to local variable
fn op_local_set(rt : Runtime) -> Unit {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.locals[idx] = value
  rt.next()
}

///|
/// local.tee: peek value and store to local variable (don't pop)
fn op_local_tee(rt : Runtime) -> Unit {
  let idx = rt.read_imm_idx()
  // Peek the top value without popping
  let value = rt.stack[rt.stack.length() - 1]
  rt.locals[idx] = value
  rt.next()
}

///|
/// end: terminate execution (no-op, just stops the chain)
fn op_end(_rt : Runtime) -> Unit {
  // Do nothing - this terminates the instruction chain
}

// ============================================================================
// Compilation
// ============================================================================

///|
/// Compile a single WASM instruction to threaded code
fn Runtime::compile_wasm_instr(self : Runtime, instr : Instr) -> Unit {
  match instr {
    I32Const(value) => {
      self.emit(WasmInstr(op_i32_const))
      self.emit(ImmediateI32(value))
    }
    I32Add => self.emit(WasmInstr(op_i32_add))
    LocalGet(idx) => {
      self.emit(WasmInstr(op_local_get))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    LocalSet(idx) => {
      self.emit(WasmInstr(op_local_set))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    LocalTee(idx) => {
      self.emit(WasmInstr(op_local_tee))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    _ => abort("Unimplemented instruction in compiler: \{instr}")
  }
}

///|
/// Compile a function body
fn Runtime::compile_func(self : Runtime, code : Code) -> Unit {
  let start_pc = self.ops.length()
  for instr in code.body.instrs {
    self.compile_wasm_instr(instr)
  }
  // Emit end instruction to terminate execution
  self.emit(WasmInstr(op_end))
  code.compiled = Some(start_pc)
}

///|
/// Compile all functions in the module
pub fn Runtime::compile(self : Runtime) -> Unit {
  for code in self.module_.codes {
    self.compile_func(code)
  }
}

///|
/// Call an exported function by name using the compiled code
pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> Array[Value] {
  let func_name_str = func_name.to_string()
  // Find exported function by name
  let mut func_idx : Int? = None
  for exp in self.module_.exports {
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
  guard func_idx is Some(idx) else { abort("Function not found: \{func_name}") }

  // Get function info
  let type_idx = self.module_.funcs[idx].reinterpret_as_int()
  let func_type = self.module_.types[type_idx]
  let code = self.module_.codes[idx]

  // Ensure function is compiled
  guard code.compiled is Some(start_pc) else {
    abort("Function not compiled: \{func_name}")
  }

  // Initialize locals: parameters + local variables
  self.locals = []

  // Add parameters from args
  for arg in args {
    self.locals.push(arg)
  }

  // Add local variables (initialized to zero)
  for local_type in code.locals {
    match local_type {
      ValType::I32 => self.locals.push(Value::I32(0U))
      ValType::I64 => self.locals.push(Value::I64(0UL))
      ValType::F32 => self.locals.push(Value::F32(0.0))
      ValType::F64 => self.locals.push(Value::F64(0.0))
      _ => abort("Unsupported local type")
    }
  }

  // Clear the stack
  self.stack.clear()

  // Set PC to function start and execute first instruction
  self.pc = start_pc
  guard self.ops.unsafe_get(self.pc) is WasmInstr(f)
  f(self)

  // Collect results from stack
  let results : Array[Value] = []
  for _i = 0; _i < func_type.results.length(); _i = _i + 1 {
    if self.stack.length() > 0 {
      results.push(self.stack.unsafe_pop())
    }
  }

  // Reverse to get correct order
  results.rev_in_place()
  results
}
