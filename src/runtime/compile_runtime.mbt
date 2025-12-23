///|
fn Runtime::compile_func(
  self : Runtime,
  func_idx : Int, // Index into module_.funcs (excludes imports)
  code : @core.Code,
) -> Unit raise RuntimeError {
  // Get function type
  let type_idx = self.module_.funcs[func_idx].reinterpret_as_int()
  let func_type = self.module_.types[type_idx]

  // Create compile-time context
  let ctx = CompileCtx::new()

  // Push function parameters onto type stack (they become locals)
  // Parameters are already in locals, but we need them on the type stack
  // for the implicit function block
  for param in func_type.params {
    ctx.push_type(param)
  }

  // Push implicit function-level control frame
  // The function body acts like a block with params=[] and results=func_type.results
  // But parameters are already popped into locals, so we model it as empty params
  // target_pc is 0 placeholder - will be patched at end
  ctx.push_control(BlockKind, [], func_type.results, 0)
  let start_pc = self.ops.length()
  // Compile function body
  for instr in code.body.instrs {
    self.compile_wasm_instr(ctx, instr)
  }
  self.emit(WasmInstr(op_end))

  // Now we know the end PC - patch all pending branches from function body
  let end_pc = self.ops.length() - 1 // Points to op_end
  let func_block = ctx.pop_control()
  for slot in func_block.pending_br_patches {
    self.ops[slot] = ImmediateIdx(end_pc)
  }
  code.compiled = Some(start_pc)
}

///|
pub fn Runtime::compile(self : Runtime) -> Unit raise RuntimeError {
  for i, code in self.module_.codes {
    self.compile_func(i, code)
  }

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

        // Set up execution context for start function
        self.locals = []
        for local_type in code.locals {
          match local_type {
            I32 => self.locals.push(Value::I32(0U))
            I64 => self.locals.push(Value::I64(0UL))
            F32 => self.locals.push(Value::F32(0.0))
            F64 => self.locals.push(Value::F64(0.0))
            FuncRef => self.locals.push(Value::Ref(None))
            ExternRef => self.locals.push(Value::Ref(None))
            _ => self.locals.push(Value::I32(0U))
          }
        }
        self.stack.clear()
        self.call_stack.clear()
        self.pc = start_pc

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        self.execute() catch {
          _ => () // Ignore runtime errors in start function
        }

        // Clear state after start function execution
        self.stack.clear()
      }
    }
    None => ()
  }
}

///|
fn Runtime::execute(self : Runtime) -> Unit raise RuntimeError {
  self.running = true
  while self.running {
    guard self.ops.unsafe_get(self.pc) is WasmInstr(f) else {
      raise RuntimeError::UnimplementedInstruction(
        "Expected instruction at PC \{self.pc}",
      )
    }
    let ret = f(self)
    if ret != OK {
      raise ret.to_error(self.error_detail)
    }
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
  let func_type = self.module_.types[type_idx]
  let code = self.module_.codes[local_idx]
  guard code.compiled is Some(start_pc) else {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: \{func_name}",
    )
  }
  let init_result = self.initialize_locals(args, code)
  if init_result != OK {
    raise init_result.to_error(self.error_detail)
  }
  self.stack.clear()
  self.call_stack.clear()
  self.pc = start_pc
  self.execute()
  let results : Array[Value] = []
  let result_types = func_type.results
  for i in 0..<result_types.length() {
    if self.stack.length() > 0 {
      let raw = self.stack.unsafe_pop()
      // Pop in reverse order, so access result types from the end
      let type_idx = result_types.length() - 1 - i
      results.push(stack_to_value(raw, result_types[type_idx]))
    }
  }
  results.rev_in_place()
  results
}
