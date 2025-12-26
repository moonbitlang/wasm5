///|
/// Local access uses unified stack: stack[sp + idx]
fn op_local_get(rt : Runtime) -> Runtime {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_get(rt.sp + idx)
  rt.stack.unsafe_set(rt.stack_top, value)
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_local_set(rt : Runtime) -> Runtime {
  let idx = rt.read_imm_idx()
  rt.stack_top -= 1
  let value = rt.stack.unsafe_get(rt.stack_top)
  rt.stack.unsafe_set(rt.sp + idx, value)
  rt.pc += 1
  rt
}

///|
fn op_local_tee(rt : Runtime) -> Runtime {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.sp + idx, value)
  rt.pc += 1
  rt
}

// ============================================================================
// Stack operations
// ============================================================================

///|
fn op_drop(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  rt.pc += 1
  rt
}

///|
fn op_select(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let cond = rt.stack.unsafe_get(rt.stack_top).to_uint()
  rt.stack_top -= 1
  let val2 = rt.stack.unsafe_get(rt.stack_top)
  rt.stack_top -= 1
  let val1 = rt.stack.unsafe_get(rt.stack_top)
  rt.stack.unsafe_set(rt.stack_top, if cond != 0U { val1 } else { val2 })
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn get_func_type_or_error(
  rt : Runtime,
  type_idx : Int,
  context : String,
) -> @core.FuncType? {
  if type_idx < 0 || type_idx >= rt.module_.types.length() {
    rt.error_detail = "\{context}: invalid type index \{type_idx}"
    return None
  }
  match rt.module_.types[type_idx] {
    Func(func_type) => Some(func_type)
    _ => {
      rt.error_detail = "\{context}: expected func type"
      None
    }
  }
}

// ============================================================================
// Control flow operations
// ============================================================================

///|
fn op_if(rt : Runtime) -> Runtime {
  let else_pc = rt.read_imm_idx()
  rt.stack_top -= 1
  let cond = rt.stack.unsafe_get(rt.stack_top).to_uint()
  if cond != 0U {
    rt.pc += 1
  } else {
    rt.pc = else_pc
  }
  rt
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
fn op_br(rt : Runtime) -> Runtime {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()

  // In-place stack shuffle: move arity values down by drop_count positions
  // Stack: [..., drop_values (drop_count), result_values (arity)]
  // Want:  [..., result_values (arity)]
  if drop_count > 0 && arity > 0 {
    let result_start = rt.stack_top - arity
    let target_start = result_start - drop_count
    // Copy forward is safe since target_start < result_start
    for i = 0; i < arity; i = i + 1 {
      rt.stack.unsafe_set(
        target_start + i,
        rt.stack.unsafe_get(result_start + i),
      )
    }
  }

  // Trim stack to remove drop_count values
  rt.stack_top -= drop_count
  rt.pc = target_pc
  rt
}

///|
fn op_br_if(rt : Runtime) -> Runtime {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  rt.stack_top -= 1
  let cond = rt.stack.unsafe_get(rt.stack_top).to_uint()
  if cond != 0U {
    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = rt.stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    rt.stack_top -= drop_count
    rt.pc = target_pc
  } else {
    rt.pc += 1
  }
  rt
}

///|
fn op_br_table(rt : Runtime) -> Runtime {
  let num_labels = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  rt.stack_top -= 1
  let index = rt.stack.unsafe_get(rt.stack_top).to_uint().reinterpret_as_int()

  // Read all target_pc+drop_count pairs, selecting the right one
  let mut target_pc = 0
  let mut drop_count = 0
  for i = 0; i <= num_labels; i = i + 1 {
    let pc = rt.read_imm_idx()
    let lbl_drop = rt.read_imm_idx()
    if i == index && i < num_labels {
      target_pc = pc
      drop_count = lbl_drop
    } else if i == num_labels && (index < 0 || index >= num_labels) {
      // Default label
      target_pc = pc
      drop_count = lbl_drop
    }
  }

  // In-place stack shuffle: move arity values down by drop_count positions
  if drop_count > 0 && arity > 0 {
    let result_start = rt.stack_top - arity
    let target_start = result_start - drop_count
    for i = 0; i < arity; i = i + 1 {
      rt.stack.unsafe_set(
        target_start + i,
        rt.stack.unsafe_get(result_start + i),
      )
    }
  }

  // Trim stack to remove drop_count values
  rt.stack_top -= drop_count
  rt.pc = target_pc
  rt
}

///|
fn op_br_on_null(rt : Runtime) -> Runtime {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value (refs are stored as Int64, -1 = null)
  rt.stack_top -= 1
  let ref_val = rt.stack.unsafe_get(rt.stack_top)
  let ref_idx = ref_val.reinterpret_as_int64().to_int()
  let is_null = ref_idx == -1
  if is_null {
    // Ref is consumed (not passed to branch target), just shuffle remaining values
    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = rt.stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    rt.stack_top -= drop_count
    rt.pc = target_pc
  } else {
    // Not null - push back the value and continue
    rt.stack.unsafe_set(rt.stack_top, ref_val)
    rt.stack_top += 1
    rt.pc += 1
  }
  rt
}

///|
fn op_br_on_non_null(rt : Runtime) -> Runtime {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value (refs are stored as Int64, -1 = null)
  rt.stack_top -= 1
  let ref_val = rt.stack.unsafe_get(rt.stack_top)
  let ref_idx = ref_val.reinterpret_as_int64().to_int()
  let is_non_null = ref_idx != -1
  if is_non_null {
    // Push ref back first - arity values include the ref we just pushed
    rt.stack.unsafe_set(rt.stack_top, ref_val)
    rt.stack_top += 1

    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = rt.stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    rt.stack_top -= drop_count
    rt.pc = target_pc
  } else {
    // Null - don't push anything, continue
    rt.pc += 1
  }
  rt
}

///|
fn op_call(rt : Runtime) -> Runtime {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "call: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let func_type = match get_func_type_or_error(rt, type_idx, "call") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }
    let args = rt.pop_arguments(func_type)
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return rt
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = match get_func_type_or_error(rt, type_idx, "call") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  // new_sp points to where arguments start (they stay in place!)
  let num_params = func_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    rt.status = Trap
    return rt
  }

  // Save caller's frame
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals (not params - they're already on stack)
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  rt.sp = new_sp
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_return(rt : Runtime) -> Runtime {
  // Read result count from immediate (emitted at compile time)
  let num_return_values = rt.read_imm_idx()

  // Unified stack return:
  // Return values are the top num_return_values values on the stack
  // Copy them in-place to: stack[sp .. sp + num_return_values)
  // Then trim stack to sp + num_return_values
  let return_start = rt.stack_top - num_return_values

  // Copy return values to start of frame
  for i = 0; i < num_return_values; i = i + 1 {
    rt.stack.unsafe_set(rt.sp + i, rt.stack.unsafe_get(return_start + i))
  }

  // Trim stack to keep only return values at frame position
  rt.stack_top = rt.sp + num_return_values
  if rt.call_stack.length() == 0 {
    // Entry function returning - results are now at stack[0..num_return_values)
    rt.status = Terminated
    return rt
  }

  // Restore caller's state
  let frame = rt.call_stack.unsafe_pop()
  rt.sp = frame.caller_sp
  rt.num_locals = frame.caller_num_locals
  rt.pc = frame.return_pc + 1
  rt
}

///|
fn op_call_indirect(rt : Runtime) -> Runtime {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  rt.stack_top -= 1
  let elem_idx = rt.stack
    .unsafe_get(rt.stack_top)
    .to_uint()
    .reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "call_indirect: invalid table index"
    rt.status = Trap
    return rt
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    rt.status = Trap
    return rt
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    rt.status = Trap
    return rt
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "call_indirect") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "call_indirect: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }

    // Check type signature matches
    check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let args = rt.pop_arguments(actual_type)
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    rt.pc += 1
    return rt
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_indirect: invalid function index"
    rt.status = Trap
    return rt
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check type signature matches
  check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  let num_params = actual_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    rt.status = Trap
    return rt
  }

  // Save caller's frame
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  rt.sp = new_sp
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_return_call(rt : Runtime) -> Runtime {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "return_call: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }
    let args = rt.pop_arguments(func_type)
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }
  // Tail call: reuse current frame
  // Move arguments in-place from stack top to sp position
  let num_params = func_type.params.length()
  let args_start = rt.stack_top - num_params

  // Copy arguments to sp position (they become new locals)
  if num_params > 0 && args_start > rt.sp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.sp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to sp + num_params
  rt.stack_top = rt.sp + num_params

  // Push default values for declared locals
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_return_call_indirect(rt : Runtime) -> Runtime {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  rt.stack_top -= 1
  let elem_idx = rt.stack
    .unsafe_get(rt.stack_top)
    .to_uint()
    .reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "return_call_indirect: invalid table index"
    rt.status = Trap
    return rt
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    rt.status = Trap
    return rt
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    rt.status = Trap
    return rt
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "return_call_indirect") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "return_call_indirect: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }

    // Check type signature matches
    check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let args = rt.pop_arguments(actual_type)
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_indirect: invalid function index"
    rt.status = Trap
    return rt
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check type signature matches
  check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }

  // Tail call: reuse current frame
  // Move arguments in-place from stack top to sp position
  let num_params = actual_type.params.length()
  let args_start = rt.stack_top - num_params

  // Copy arguments to sp position (they become new locals)
  if num_params > 0 && args_start > rt.sp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.sp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to sp + num_params
  rt.stack_top = rt.sp + num_params

  // Push default values for declared locals
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_call_ref(rt : Runtime) -> Runtime {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  rt.stack_top -= 1
  let func_ref_raw = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  if func_ref_raw == -1 {
    rt.error_detail = "call_ref: null function reference"
    rt.status = Trap
    return rt
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = match get_func_type_or_error(rt, type_idx, "call_ref") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "call_ref: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_ref") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }

    // Check type signature matches
    check_type_signature_match(
      func_type, actual_type, "call_ref: type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let args = rt.pop_arguments(func_type)
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return rt
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_ref: invalid function index"
    rt.status = Trap
    return rt
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_ref") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check type signature matches
  check_type_signature_match(
    func_type, actual_type, "call_ref: type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  let num_params = func_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    rt.status = Trap
    return rt
  }

  // Save caller's frame
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  rt.sp = new_sp
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_return_call_ref(rt : Runtime) -> Runtime {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  rt.stack_top -= 1
  let func_ref_raw = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  if func_ref_raw == -1 {
    rt.error_detail = "return_call_ref: null function reference"
    rt.status = Trap
    return rt
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = match
    get_func_type_or_error(rt, type_idx, "return_call_ref") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "return_call_ref: invalid imported function index"
      rt.status = Trap
      return rt
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
      Some(found) => found
      None => {
        rt.status = Trap
        return rt
      }
    }

    // Check type signature matches
    check_type_signature_match(
      func_type, actual_type, "return_call_ref: type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let args = rt.pop_arguments(func_type)
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_ref: invalid function index"
    rt.status = Trap
    return rt
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
    Some(found) => found
    None => {
      rt.status = Trap
      return rt
    }
  }

  // Check type signature matches
  check_type_signature_match(
    func_type, actual_type, "return_call_ref: type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    rt.status = Trap
    return rt
  }

  // Tail call: reuse current frame
  // Move arguments in-place from stack top to sp position
  let num_params = func_type.params.length()
  let args_start = rt.stack_top - num_params

  // Copy arguments to sp position (they become new locals)
  if num_params > 0 && args_start > rt.sp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.sp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to sp + num_params
  rt.stack_top = rt.sp + num_params

  // Push default values for declared locals
  rt.init_declared_locals(code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  rt.num_locals = num_params + code.locals.length()
  rt.pc = callee_pc
  rt
}

///|
fn op_nop(rt : Runtime) -> Runtime {
  rt.pc += 1
  rt
}

///|
fn op_unreachable(rt : Runtime) -> Runtime {
  rt.error_detail = "unreachable"
  rt.status = Trap
  rt
}

///|
fn op_throw(rt : Runtime) -> Runtime {
  let tag_idx = rt.read_imm_idx()
  rt.error_detail = "throw not implemented for tag \{tag_idx}"
  rt.status = Trap
  rt
}

///|
fn op_rethrow(rt : Runtime) -> Runtime {
  let label_idx = rt.read_imm_idx()
  rt.error_detail = "rethrow not implemented for label \{label_idx}"
  rt.status = Trap
  rt
}

///|
fn op_simd_unimplemented(rt : Runtime) -> Runtime {
  rt.error_detail = "simd instruction not implemented"
  rt.status = Trap
  rt
}

///|
fn op_atomic_unimplemented(rt : Runtime) -> Runtime {
  rt.error_detail = "atomic instruction not implemented"
  rt.status = Trap
  rt
}

///|
fn op_gc_unimplemented(rt : Runtime) -> Runtime {
  rt.error_detail = "gc instruction not implemented"
  rt.status = Trap
  rt
}
// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
fn op_table_init(rt : Runtime) -> Runtime {
  let _table_idx = rt.read_imm_idx()
  let _elem_idx = rt.read_imm_idx()
  rt.stack_top -= 1
  let _n = rt.stack.unsafe_get(rt.stack_top).to_uint()
  rt.stack_top -= 1
  let _src = rt.stack.unsafe_get(rt.stack_top).to_uint()
  rt.stack_top -= 1
  let _dest = rt.stack.unsafe_get(rt.stack_top).to_uint()
  // TODO: Implement table.init
  rt.pc += 1
  rt
}

///|
fn op_table_copy(rt : Runtime) -> Runtime {
  let _dst_table_idx = rt.read_imm_idx()
  let _src_table_idx = rt.read_imm_idx()
  rt.stack_top -= 1
  let _n = rt.stack.unsafe_get(rt.stack_top).to_uint()
  rt.stack_top -= 1
  let _src = rt.stack.unsafe_get(rt.stack_top).to_uint()
  rt.stack_top -= 1
  let _dest = rt.stack.unsafe_get(rt.stack_top).to_uint()
  // TODO: Implement table.copy
  rt.pc += 1
  rt
}

///|
fn op_table_fill(rt : Runtime) -> Runtime {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    rt.status = Trap
    return rt
  }
  rt.stack_top -= 1
  let n = rt.stack.unsafe_get(rt.stack_top).to_uint().reinterpret_as_int()
  rt.stack_top -= 1
  let raw_ref = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  let ref_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  rt.stack_top -= 1
  let dest = rt.stack.unsafe_get(rt.stack_top).to_uint().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if dest < 0 || n < 0 || dest + n > table.length() {
    rt.error_detail = "table fill out of bounds"
    rt.status = Trap
    return rt
  }
  for i = 0; i < n; i = i + 1 {
    table[dest + i] = ref_value
  }
  rt.pc += 1
  rt
}

///|
fn op_elem_drop(rt : Runtime) -> Runtime {
  let _elem_idx = rt.read_imm_idx()
  // TODO: Implement elem.drop
  rt.pc += 1
  rt
}

// =============================================================================
// Table operations
// =============================================================================

///|
fn op_table_size(rt : Runtime) -> Runtime {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    rt.status = Trap
    return rt
  }
  let size = rt.tables[table_idx].data.length()
  rt.stack.unsafe_set(rt.stack_top, size.reinterpret_as_uint().to_uint64())
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_table_get(rt : Runtime) -> Runtime {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    rt.status = Trap
    return rt
  }
  rt.stack_top -= 1
  let elem_idx = rt.stack
    .unsafe_get(rt.stack_top)
    .to_uint()
    .reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    rt.status = Trap
    return rt
  }
  // Return the function reference (or null) - stored as Int64, -1 = null
  let ref_val = match table[elem_idx] {
    Some(idx) => idx.to_int64()
    None => (-1).to_int64()
  }
  rt.stack.unsafe_set(rt.stack_top, ref_val.reinterpret_as_uint64())
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_table_set(rt : Runtime) -> Runtime {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    rt.status = Trap
    return rt
  }
  // Pop ref value - stored as Int64, -1 = null
  rt.stack_top -= 1
  let raw_ref = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  let ref_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  rt.stack_top -= 1
  let elem_idx = rt.stack
    .unsafe_get(rt.stack_top)
    .to_uint()
    .reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    rt.status = Trap
    return rt
  }
  table[elem_idx] = ref_value
  rt.pc += 1
  rt
}

///|
fn op_table_grow(rt : Runtime) -> Runtime {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.stack.unsafe_set(rt.stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    rt.stack_top += 1
    rt.pc += 1
    return rt
  }
  rt.stack_top -= 1
  let delta = rt.stack.unsafe_get(rt.stack_top).to_uint().reinterpret_as_int()
  // Pop ref value - stored as Int64, -1 = null
  rt.stack_top -= 1
  let raw_ref = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  let init_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  let runtime_table = rt.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.unsafe_set(rt.stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    rt.stack_top += 1
    rt.pc += 1
    return rt
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int64().to_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.unsafe_set(rt.stack_top, 0xFFFFFFFFUL)
        rt.stack_top += 1
        rt.pc += 1
        return rt
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.unsafe_set(rt.stack_top, old_size.reinterpret_as_uint().to_uint64())
  rt.stack_top += 1
  rt.pc += 1
  rt
}

// =============================================================================
// Reference operations
// =============================================================================

///|
fn op_ref_null(rt : Runtime) -> Runtime {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.read_imm_idx() // Skip the heap type encoding
  // Push null ref as -1 (Int64)
  rt.stack.unsafe_set(rt.stack_top, (-1).to_int64().reinterpret_as_uint64())
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_ref_func(rt : Runtime) -> Runtime {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.read_imm_idx()
  // Push func ref as Int64
  rt.stack.unsafe_set(rt.stack_top, func_idx.to_int64().reinterpret_as_uint64())
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_ref_is_null(rt : Runtime) -> Runtime {
  // ref.is_null tests whether a reference is null
  // Refs are stored as Int64, -1 = null
  rt.stack_top -= 1
  let ref_val = rt.stack
    .unsafe_get(rt.stack_top)
    .reinterpret_as_int64()
    .to_int()
  let is_null : UInt64 = if ref_val == -1 { 1UL } else { 0UL }
  rt.stack.unsafe_set(rt.stack_top, is_null)
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_ref_eq(rt : Runtime) -> Runtime {
  // ref.eq compares two references for identity equality
  // Refs are stored as Int64, -1 = null
  rt.stack_top -= 1
  let rhs = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_int64().to_int()
  rt.stack_top -= 1
  let lhs = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_int64().to_int()
  let eq : UInt64 = if lhs == rhs { 1UL } else { 0UL }
  rt.stack.unsafe_set(rt.stack_top, eq)
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_ref_as_non_null(rt : Runtime) -> Runtime {
  // ref.as_non_null traps on null references
  // Refs are stored as Int64, -1 = null
  rt.stack_top -= 1
  let value = rt.stack.unsafe_get(rt.stack_top)
  let ref_val = value.reinterpret_as_int64().to_int()
  if ref_val == -1 {
    rt.error_detail = "ref.as_non_null: null reference"
    rt.status = Trap
    return rt
  }
  // Push back the non-null reference
  rt.stack.unsafe_set(rt.stack_top, value)
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_global_get(rt : Runtime) -> Runtime {
  let idx = rt.read_imm_idx()
  // Convert Value to UInt64 for stack
  rt.stack.unsafe_set(rt.stack_top, value_to_stack(rt.globals[idx]))
  rt.stack_top += 1
  rt.pc += 1
  rt
}

///|
fn op_global_set(rt : Runtime) -> Runtime {
  let idx = rt.read_imm_idx()
  rt.stack_top -= 1
  let raw = rt.stack.unsafe_get(rt.stack_top)
  // Infer the value type from the existing global's tag
  // (handles both imported and defined globals without index adjustment)
  let val_type : @core.ValType = match rt.globals[idx] {
    I32(_) => I32
    I64(_) => I64
    F32(_) => F32
    F64(_) => F64
    Ref(_) => FuncRef // Ref types all stored the same way
  }
  rt.globals[idx] = stack_to_value(raw, val_type)
  rt.pc += 1
  rt
}
