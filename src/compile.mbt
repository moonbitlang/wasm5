///|
/// Intermediate instruction for threaded interpreter
enum MInstr {
  WasmInstr((Runtime) -> ControlFlow)
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Control flow signal from instruction execution
enum ControlFlow {
  Next // Continue to next instruction
  Jump(Int) // Jump to specific PC
  End // Stop execution
}

///|
/// Call frame for function calls
struct CallFrame {
  return_pc : Int
  locals : Array[Value]
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
// Instruction implementations (trampoline style - return ControlFlow)
// ============================================================================

///|
/// i32.const: push immediate i32 value
fn op_i32_const(rt : Runtime) -> ControlFlow {
  let value = rt.read_imm_i32()
  rt.stack.push(Value::I32(value))
  Next
}

///|
/// i32.add: pop two i32 values, push sum
fn op_i32_add(rt : Runtime) -> ControlFlow {
  let b = rt.stack.unsafe_pop()
  let a = rt.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) =>
      rt.stack.push(Value::I32(a_val + b_val))
    _ => abort("Type error in i32.add")
  }
  Next
}

///|
/// i32.sub: pop two i32 values, push difference
fn op_i32_sub(rt : Runtime) -> ControlFlow {
  let b = rt.stack.unsafe_pop()
  let a = rt.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) =>
      rt.stack.push(Value::I32(a_val - b_val))
    _ => abort("Type error in i32.sub")
  }
  Next
}

///|
/// i32.le_s: signed less-than-or-equal comparison
fn op_i32_le_s(rt : Runtime) -> ControlFlow {
  let b = rt.stack.unsafe_pop()
  let a = rt.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) => {
      let result = if a_val.reinterpret_as_int() <= b_val.reinterpret_as_int() {
        1U
      } else {
        0U
      }
      rt.stack.push(Value::I32(result))
    }
    _ => abort("Type error in i32.le_s")
  }
  Next
}

///|
/// local.get: push local variable value
fn op_local_get(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.locals[idx])
  Next
}

///|
/// local.set: pop value and store to local variable
fn op_local_set(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.locals[idx] = value
  Next
}

///|
/// local.tee: peek value and store to local variable (don't pop)
fn op_local_tee(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  // Peek the top value without popping
  let value = rt.stack[rt.stack.length() - 1]
  rt.locals[idx] = value
  Next
}

///|
/// if: conditional branch
/// Layout: op_if | else_pc | ... then instrs ... | op_else | end_pc | ... else instrs ... | op_end_block
fn op_if(rt : Runtime) -> ControlFlow {
  let else_pc = rt.read_imm_idx()
  let cond = rt.stack.unsafe_pop()
  match cond {
    Value::I32(v) =>
      if v != 0U {
        // Condition true: continue to then branch
        Next
      } else {
        // Condition false: jump to else branch
        Jump(else_pc)
      }
    _ => abort("Type error in if: expected i32 condition")
  }
}

///|
/// else: jump to end of if block (executed after then branch completes)
/// Layout: op_else | end_pc
fn op_else(rt : Runtime) -> ControlFlow {
  let end_pc = rt.read_imm_idx()
  // Skip over else branch to end
  Jump(end_pc)
}

///|
/// end_block: end of a control structure, continue execution
fn op_end_block(_rt : Runtime) -> ControlFlow {
  Next
}

///|
/// call: call a function by index
/// Layout: op_call | func_idx
fn op_call(rt : Runtime) -> ControlFlow {
  let func_idx = rt.read_imm_idx()

  // Get function info
  let type_idx = rt.module_.funcs[func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[func_idx]

  guard code.compiled is Some(callee_pc) else {
    abort("Function not compiled: \{func_idx}")
  }

  // Pop arguments from stack (in reverse order)
  let num_params = func_type.params.length()
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = rt.stack.unsafe_pop()
  }

  // Save current frame
  let saved_frame = CallFrame::{ return_pc: rt.pc, locals: rt.locals }
  rt.call_stack.push(saved_frame)

  // Set up new locals
  rt.locals = []

  // Add parameters
  for arg in args {
    rt.locals.push(arg)
  }

  // Add local variables (initialized to zero)
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.locals.push(Value::I32(0U))
      ValType::I64 => rt.locals.push(Value::I64(0UL))
      ValType::F32 => rt.locals.push(Value::F32(0.0))
      ValType::F64 => rt.locals.push(Value::F64(0.0))
      _ => abort("Unsupported local type")
    }
  }

  // Jump to callee
  Jump(callee_pc)
}

///|
/// return_op: return from function
fn op_return(rt : Runtime) -> ControlFlow {
  if rt.call_stack.length() == 0 {
    // Top-level return, just stop
    return End
  }

  // Get return value (if any) from stack
  // For simplicity, we assume at most one return value
  let return_value : Value? = if rt.stack.length() > 0 {
    Some(rt.stack.unsafe_pop())
  } else {
    None
  }

  // Restore caller frame
  let frame = rt.call_stack.unsafe_pop()
  rt.locals = frame.locals

  // Push return value if any
  match return_value {
    Some(v) => rt.stack.push(v)
    None => ()
  }

  // Continue after call instruction (return_pc points to op_call, need +1 to skip func_idx)
  Jump(frame.return_pc + 1)
}

///|
/// end: terminate execution (for function end)
fn op_end(rt : Runtime) -> ControlFlow {
  // Check if we need to return from a call
  if rt.call_stack.length() > 0 {
    op_return(rt)
  } else {
    // Top-level function end - stop
    End
  }
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
    I32Sub => self.emit(WasmInstr(op_i32_sub))
    I32LeS => self.emit(WasmInstr(op_i32_le_s))
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
    If(_block_type, then_instrs, else_instrs) => {
      // Emit: op_if | else_pc (placeholder)
      self.emit(WasmInstr(op_if))
      let else_pc_slot = self.ops.length()
      self.emit(ImmediateIdx(0)) // Placeholder for else_pc

      // Compile then branch
      for instr in then_instrs {
        self.compile_wasm_instr(instr)
      }

      // Emit: op_else | end_pc (placeholder)
      self.emit(WasmInstr(op_else))
      let end_pc_slot = self.ops.length()
      self.emit(ImmediateIdx(0)) // Placeholder for end_pc

      // Patch else_pc to point here (start of else branch)
      let else_start = self.ops.length()
      self.ops[else_pc_slot] = ImmediateIdx(else_start)

      // Compile else branch
      for instr in else_instrs {
        self.compile_wasm_instr(instr)
      }

      // Emit end of if block
      self.emit(WasmInstr(op_end_block))

      // Patch end_pc to point here
      let end_pc = self.ops.length() - 1 // Point to op_end_block
      self.ops[end_pc_slot] = ImmediateIdx(end_pc)
    }
    Call(func_idx) => {
      self.emit(WasmInstr(op_call))
      self.emit(ImmediateIdx(func_idx.reinterpret_as_int()))
    }
    Return => self.emit(WasmInstr(op_return))
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
/// Execute compiled code using trampoline loop
fn Runtime::execute(self : Runtime) -> Unit {
  while true {
    guard self.ops.unsafe_get(self.pc) is WasmInstr(f) else {
      abort("Expected instruction at PC \{self.pc}")
    }
    match f(self) {
      Next => self.pc += 1
      Jump(target) => self.pc = target
      End => return
    }
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

  // Clear the stack and call stack
  self.stack.clear()
  self.call_stack.clear()

  // Set PC to function start and execute using trampoline
  self.pc = start_pc
  self.execute()

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
