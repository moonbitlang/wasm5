///|
/// Run the start function if present.
/// Returns the runtime after start function execution (if any).
/// Note: Compilation now happens during Runtime::load.
pub fn Runtime::compile(self : Runtime) -> Runtime raise RuntimeError {
  // Execute the start function if present
  match self.ctx.module_.start {
    Some(start_idx) => {
      // Call the start function
      // Start function must have type [] -> []
      let func_idx = start_idx.reinterpret_as_int()
      let num_imported_funcs = count_imported_funcs(self.ctx.module_)

      // Only execute if it's a local function (not imported)
      // Imported start functions would require host environment support
      if func_idx >= num_imported_funcs {
        let local_idx = func_idx - num_imported_funcs
        let code = self.ctx.module_.codes[local_idx]
        guard code.compiled is Some(start_pc) else {
          raise RuntimeError::FunctionNotCompiled("Start function not compiled")
        }

        // Clear stack before setting up locals
        self.sp = 0
        self.status = Terminated

        // Initialize entry locals (start function has no parameters)
        let rt = initialize_entry_locals(self, [], code)
        if rt.status == Trap {
          raise RuntimeError::from_detail(rt.ctx.error_detail)
        }
        rt.pc = start_pc

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        let rt = execute(rt) catch {
          _ => rt // Ignore runtime errors in start function
        }

        // Return with cleared stack
        rt.sp = 0
        return rt
      }
      self
    }
    None => self
  }
}

///|
fn execute(rt : Runtime) -> Runtime raise RuntimeError {
  let mut rt = rt
  rt.status = Running
  while rt.status is Running {
    let f = unsafe_uint64_to_function(rt.ops.unsafe_get(rt.pc))
    rt = f(rt)
  }
  if rt.status is Trap {
    raise RuntimeError::from_detail(rt.ctx.error_detail)
  }
  // Returned and Terminated both exit normally
  rt
}

///|
/// Execute a local function call using native stack.
/// Caller state is preserved on the MoonBit stack frame.
/// Returns the runtime with results on the stack after callee returns.
fn execute_call(
  rt : Runtime,
  callee_pc : Int,
  caller_bp : Int,
  caller_num_locals : Int,
  return_pc : Int,
) -> Runtime raise RuntimeError {
  // Execute callee
  rt.pc = callee_pc
  let rt = execute(rt)

  // Callee has returned - results are at stack[rt.bp .. rt.sp)
  // Return values are already copied to bp by op_return
  // Restore caller's state
  rt.bp = caller_bp
  rt.num_locals = caller_num_locals
  rt.pc = return_pc
  rt.status = Running
  rt
}

///|
/// Call a compiled function by name with the given arguments.
/// Returns tuple of (updated Runtime, results).
pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> (Runtime, Array[Value]) raise RuntimeError {
  let mut func_idx : Int? = None
  for exp in self.ctx.module_.exports {
    if exp.name == func_name {
      match exp.desc {
        Func(idx) => {
          func_idx = Some(idx.reinterpret_as_int())
          break
        }
        _ => continue
      }
    }
  }
  guard func_idx is Some(idx) else {
    raise RuntimeError::FunctionNotFound("Function not found: \{func_name}")
  }
  let num_imported_funcs = count_imported_funcs(self.ctx.module_)

  // Check if it's an imported function - call it directly via import resolver
  if idx < num_imported_funcs {
    let imported_func = self.ctx.imported_funcs[idx]
    return (self, (imported_func.func)(args))
  }

  // Adjust to local function index
  let local_idx = idx - num_imported_funcs
  let type_idx = self.ctx.module_.funcs[local_idx].reinterpret_as_int()
  let func_type = require_func_type(self.ctx.module_, type_idx, "call_compiled")
  let code = self.ctx.module_.codes[local_idx]
  guard code.compiled is Some(start_pc) else {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: \{func_name}",
    )
  }

  // Clear stack before setting up entry frame
  self.sp = 0
  self.status = Terminated

  // Initialize entry locals (pushes args and locals onto stack, sets sp/num_locals)
  let rt = initialize_entry_locals(self, args, code)
  if rt.status == Trap {
    raise RuntimeError::from_detail(rt.ctx.error_detail)
  }
  rt.pc = start_pc
  let rt = execute(rt)

  // Extract results from unified stack
  // After function returns, results are at stack[0..num_results)
  let results : Array[Value] = []
  let result_types = func_type.results
  for i in 0..<result_types.length() {
    if i < rt.sp {
      results.push(stack_to_value(rt.stack.unsafe_get(i), result_types[i]))
    }
  }
  (rt, results)
}
