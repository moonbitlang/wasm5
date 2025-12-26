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

        // Clear stack and call_stack before setting up locals
        self.ctx.call_stack.clear()
        let rt : Runtime = { ..self, sp: 0, status: Terminated }

        // Initialize entry locals (start function has no parameters)
        let rt = initialize_entry_locals(rt, [], code)
        if rt.status == Trap {
          raise RuntimeError::from_detail(rt.ctx.error_detail)
        }
        let rt = { ..rt, pc: start_pc }

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        let rt = execute(rt) catch {
          _ => rt // Ignore runtime errors in start function
        }

        // Return with cleared stack
        return { ..rt, sp: 0 }
      }
      self
    }
    None => self
  }
}

///|
fn execute(rt : Runtime) -> Runtime raise RuntimeError {
  let mut rt : Runtime = { ..rt, status: Running }
  while rt.status is Running {
    let f = unsafe_uint64_to_function(rt.ops.unsafe_get(rt.pc))
    rt = f(rt)
  }
  if rt.status is Trap {
    raise RuntimeError::from_detail(rt.ctx.error_detail)
  }
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

  // Clear stack and call_stack before setting up entry frame
  self.ctx.call_stack.clear()
  let rt : Runtime = { ..self, sp: 0, status: Terminated }

  // Initialize entry locals (pushes args and locals onto stack, sets sp/num_locals)
  let rt = initialize_entry_locals(rt, args, code)
  if rt.status == Trap {
    raise RuntimeError::from_detail(rt.ctx.error_detail)
  }
  let rt = { ..rt, pc: start_pc }
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
