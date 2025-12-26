///|
/// Run the start function if present.
/// Note: Compilation now happens during Runtime::load.
pub fn Runtime::compile(self : Runtime) -> Unit raise RuntimeError {
  // Execute the start function if present
  match self.module_.start {
    Some(start_idx) => {
      // Call the start function
      // Start function must have type [] -> []
      let func_idx = start_idx.reinterpret_as_int()
      let num_imported_funcs = count_imported_funcs(self.module_)

      // Only execute if it's a local function (not imported)
      // Imported start functions would require host environment support
      if func_idx >= num_imported_funcs {
        let local_idx = func_idx - num_imported_funcs
        let code = self.module_.codes[local_idx]
        guard code.compiled is Some(start_pc) else {
          raise RuntimeError::FunctionNotCompiled("Start function not compiled")
        }

        // Clear stack and call_stack before setting up locals
        self.stack_top = 0
        self.call_stack.clear()
        self.status = Terminated // Reset status

        // Initialize entry locals (start function has no parameters)
        self.initialize_entry_locals([], code)
        if self.status == Trap {
          raise RuntimeError::from_detail(self.error_detail)
        }
        self.pc = start_pc

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        self.execute() catch {
          _ => () // Ignore runtime errors in start function
        }

        // Clear state after start function execution
        self.stack_top = 0
      }
    }
    None => ()
  }
}

///|
fn Runtime::execute(self : Runtime) -> Unit raise RuntimeError {
  let mut rt : Runtime = { ..self, status: Running }
  while rt.status == Running {
    guard rt.ops.unsafe_get(rt.pc) is WasmInstr(f) else {
      raise RuntimeError::UnimplementedInstruction(
        "Expected instruction at PC \{rt.pc}",
      )
    }
    rt = f(rt)
  }
  // Copy final state back to self
  self.stack_top = rt.stack_top
  self.sp = rt.sp
  self.num_locals = rt.num_locals
  self.pc = rt.pc
  self.status = rt.status
  self.error_detail = rt.error_detail
  if self.status == Trap {
    raise RuntimeError::from_detail(self.error_detail)
  }
}

///|
pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  let mut func_idx : Int? = None
  for exp in self.module_.exports {
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
  let num_imported_funcs = count_imported_funcs(self.module_)

  // Check if it's an imported function - call it directly via import resolver
  if idx < num_imported_funcs {
    let imported_func = self.imported_funcs[idx]
    return (imported_func.func)(args)
  }

  // Adjust to local function index
  let local_idx = idx - num_imported_funcs
  let type_idx = self.module_.funcs[local_idx].reinterpret_as_int()
  let func_type = require_func_type(self.module_, type_idx, "call_compiled")
  let code = self.module_.codes[local_idx]
  guard code.compiled is Some(start_pc) else {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: \{func_name}",
    )
  }

  // Clear stack and call_stack before setting up entry frame
  self.stack_top = 0
  self.call_stack.clear()
  self.status = Terminated // Reset status in case previous call trapped

  // Initialize entry locals (pushes args and locals onto stack, sets sp/num_locals)
  self.initialize_entry_locals(args, code)
  if self.status == Trap {
    raise RuntimeError::from_detail(self.error_detail)
  }
  self.pc = start_pc
  self.execute()

  // Extract results from unified stack
  // After function returns, results are at stack[0..num_results)
  let results : Array[Value] = []
  let result_types = func_type.results
  for i in 0..<result_types.length() {
    if i < self.stack_top {
      results.push(stack_to_value(self.stack.unsafe_get(i), result_types[i]))
    }
  }
  results
}
