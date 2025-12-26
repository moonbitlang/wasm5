///|
/// Local access uses unified stack: stack[sp + idx]
fn op_local_get(rt : Runtime) -> Runtime {
  let (rt, idx) = read_imm_idx(rt)
  let value = rt.stack.unsafe_get(rt.sp + idx)
  rt.stack.unsafe_set(rt.stack_top, value)
  { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_local_set(rt : Runtime) -> Runtime {
  let (rt, idx) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 1
  let value = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(rt.sp + idx, value)
  { ..rt, stack_top, pc: rt.pc + 1 }
}

///|
fn op_local_tee(rt : Runtime) -> Runtime {
  let (rt, idx) = read_imm_idx(rt)
  let value = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.sp + idx, value)
  { ..rt, pc: rt.pc + 1 }
}

// ============================================================================
// Stack operations
// ============================================================================

///|
fn op_drop(rt : Runtime) -> Runtime {
  { ..rt, stack_top: rt.stack_top - 1, pc: rt.pc + 1 }
}

///|
fn op_select(rt : Runtime) -> Runtime {
  let stack_top = rt.stack_top - 3
  let cond = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let val2 = rt.stack.unsafe_get(rt.stack_top - 2)
  let val1 = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(stack_top, if cond != 0U { val1 } else { val2 })
  { ..rt, stack_top: stack_top + 1, pc: rt.pc + 1 }
}

///|
fn get_func_type_or_error(
  rt : Runtime,
  type_idx : Int,
  context : String,
) -> @core.FuncType? {
  if type_idx < 0 || type_idx >= rt.ctx.module_.types.length() {
    rt.ctx.error_detail = "\{context}: invalid type index \{type_idx}"
    return None
  }
  match rt.ctx.module_.types[type_idx] {
    Func(func_type) => Some(func_type)
    _ => {
      rt.ctx.error_detail = "\{context}: expected func type"
      None
    }
  }
}

// ============================================================================
// Control flow operations
// ============================================================================

///|
fn op_if(rt : Runtime) -> Runtime {
  let (rt, else_pc) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 1
  let cond = rt.stack.unsafe_get(stack_top).to_uint()
  if cond != 0U {
    { ..rt, stack_top, pc: rt.pc + 1 }
  } else {
    { ..rt, stack_top, pc: else_pc }
  }
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
fn op_br(rt : Runtime) -> Runtime {
  let (rt, target_pc) = read_imm_idx(rt)
  let (rt, arity) = read_imm_idx(rt)
  let (rt, drop_count) = read_imm_idx(rt)

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
  { ..rt, stack_top: rt.stack_top - drop_count, pc: target_pc }
}

///|
fn op_br_if(rt : Runtime) -> Runtime {
  let (rt, target_pc) = read_imm_idx(rt)
  let (rt, arity) = read_imm_idx(rt)
  let (rt, drop_count) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 1
  let cond = rt.stack.unsafe_get(stack_top).to_uint()
  if cond != 0U {
    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    { ..rt, stack_top: stack_top - drop_count, pc: target_pc }
  } else {
    { ..rt, stack_top, pc: rt.pc + 1 }
  }
}

///|
fn op_br_table(rt : Runtime) -> Runtime {
  let (rt, num_labels) = read_imm_idx(rt)
  let (rt, arity) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 1
  let index = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Read all target_pc+drop_count pairs, selecting the right one
  let mut target_pc = 0
  let mut drop_count = 0
  let mut rt = rt
  for i = 0; i <= num_labels; i = i + 1 {
    let (rt2, pc) = read_imm_idx(rt)
    let (rt3, lbl_drop) = read_imm_idx(rt2)
    rt = rt3
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
    let result_start = stack_top - arity
    let target_start = result_start - drop_count
    for i = 0; i < arity; i = i + 1 {
      rt.stack.unsafe_set(
        target_start + i,
        rt.stack.unsafe_get(result_start + i),
      )
    }
  }

  // Trim stack to remove drop_count values
  { ..rt, stack_top: stack_top - drop_count, pc: target_pc }
}

///|
fn op_br_on_null(rt : Runtime) -> Runtime {
  let (rt, target_pc) = read_imm_idx(rt)
  let (rt, arity) = read_imm_idx(rt)
  let (rt, drop_count) = read_imm_idx(rt)
  // Pop reference value (refs are stored as Int64, -1 = null)
  let stack_top = rt.stack_top - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  let ref_idx = ref_val.reinterpret_as_int64().to_int()
  let is_null = ref_idx == -1
  if is_null {
    // Ref is consumed (not passed to branch target), just shuffle remaining values
    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    { ..rt, stack_top: stack_top - drop_count, pc: target_pc }
  } else {
    // Not null - push back the value and continue
    rt.stack.unsafe_set(stack_top, ref_val)
    { ..rt, pc: rt.pc + 1 }
  }
}

///|
fn op_br_on_non_null(rt : Runtime) -> Runtime {
  let (rt, target_pc) = read_imm_idx(rt)
  let (rt, arity) = read_imm_idx(rt)
  let (rt, drop_count) = read_imm_idx(rt)
  // Pop reference value (refs are stored as Int64, -1 = null)
  let stack_top = rt.stack_top - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  let ref_idx = ref_val.reinterpret_as_int64().to_int()
  let is_non_null = ref_idx != -1
  if is_non_null {
    // Push ref back first - arity values include the ref we just pushed
    rt.stack.unsafe_set(stack_top, ref_val)
    let stack_top = stack_top + 1

    // In-place stack shuffle: move arity values down by drop_count positions
    if drop_count > 0 && arity > 0 {
      let result_start = stack_top - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }

    // Trim stack to remove drop_count values
    { ..rt, stack_top: stack_top - drop_count, pc: target_pc }
  } else {
    // Null - don't push anything, continue
    { ..rt, stack_top, pc: rt.pc + 1 }
  }
}

///|
fn op_call(rt : Runtime) -> Runtime {
  let (rt, func_idx) = read_imm_idx(rt)
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if type_idx < 0 {
      rt.ctx.error_detail = "call: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let func_type = match get_func_type_or_error(rt, type_idx, "call") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }
    let (rt, args) = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    return { ..rt, pc: rt.pc + 1 }
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = match get_func_type_or_error(rt, type_idx, "call") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  // new_sp points to where arguments start (they stay in place!)
  let num_params = func_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller's frame
  rt.ctx.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals (not params - they're already on stack)
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  {
    ..rt,
    sp: new_sp,
    num_locals: num_params + code.locals.length(),
    pc: callee_pc,
  }
}

///|
fn op_return(rt : Runtime) -> Runtime {
  // Read result count from immediate (emitted at compile time)
  let (rt, num_return_values) = read_imm_idx(rt)

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
  let stack_top = rt.sp + num_return_values
  if rt.ctx.call_stack.length() == 0 {
    // Entry function returning - results are now at stack[0..num_return_values)
    return { ..rt, stack_top, status: Terminated }
  }

  // Restore caller's state
  let frame = rt.ctx.call_stack.unsafe_pop()
  {
    ..rt,
    stack_top,
    sp: frame.caller_sp,
    num_locals: frame.caller_num_locals,
    pc: frame.return_pc + 1,
  }
}

///|
fn op_call_indirect(rt : Runtime) -> Runtime {
  let (rt, type_idx) = read_imm_idx(rt)
  let (rt, table_idx) = read_imm_idx(rt)

  // Pop the function index from the stack
  let stack_top = rt.stack_top - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let rt = { ..rt, stack_top, }

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "call_indirect: invalid table index"
    return { ..rt, status: Trap }
  }
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "undefined element"
    return { ..rt, status: Trap }
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.ctx.error_detail = "uninitialized element"
    return { ..rt, status: Trap }
  }
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "call_indirect") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "call_indirect: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }

    // Check type signature matches
    let rt = check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let (rt, args) = pop_arguments(rt, actual_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      expected_type.results.length(),
    )
    return { ..rt, pc: rt.pc + 1 }
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.ctx.module_.codes.length() {
    rt.ctx.error_detail = "call_indirect: invalid function index"
    return { ..rt, status: Trap }
  }

  // Get the actual function type
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check type signature matches
  let rt = check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  let num_params = actual_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller's frame
  rt.ctx.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  {
    ..rt,
    sp: new_sp,
    num_locals: num_params + code.locals.length(),
    pc: callee_pc,
  }
}

///|
fn op_return_call(rt : Runtime) -> Runtime {
  let (rt, func_idx) = read_imm_idx(rt)
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if type_idx < 0 {
      rt.ctx.error_detail = "return_call: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }
    let (rt, args) = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    return handle_tail_call_return(rt)
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
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
  let rt = { ..rt, stack_top: rt.sp + num_params }

  // Push default values for declared locals
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  { ..rt, num_locals: num_params + code.locals.length(), pc: callee_pc }
}

///|
fn op_return_call_indirect(rt : Runtime) -> Runtime {
  let (rt, type_idx) = read_imm_idx(rt)
  let (rt, table_idx) = read_imm_idx(rt)

  // Pop the function index from the stack
  let stack_top = rt.stack_top - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let rt = { ..rt, stack_top, }

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "return_call_indirect: invalid table index"
    return { ..rt, status: Trap }
  }
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "undefined element"
    return { ..rt, status: Trap }
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.ctx.error_detail = "uninitialized element"
    return { ..rt, status: Trap }
  }
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "return_call_indirect") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "return_call_indirect: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }

    // Check type signature matches
    let rt = check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let (rt, args) = pop_arguments(rt, actual_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      expected_type.results.length(),
    )
    return handle_tail_call_return(rt)
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.ctx.module_.codes.length() {
    rt.ctx.error_detail = "return_call_indirect: invalid function index"
    return { ..rt, status: Trap }
  }

  // Get the actual function type
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check type signature matches
  let rt = check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
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
  let rt = { ..rt, stack_top: rt.sp + num_params }

  // Push default values for declared locals
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  { ..rt, num_locals: num_params + code.locals.length(), pc: callee_pc }
}

///|
fn op_call_ref(rt : Runtime) -> Runtime {
  let (rt, type_idx) = read_imm_idx(rt)

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.stack_top - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  let rt = { ..rt, stack_top, }
  if func_ref_raw == -1 {
    rt.ctx.error_detail = "call_ref: null function reference"
    return { ..rt, status: Trap }
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Get the expected function type
  let func_type = match get_func_type_or_error(rt, type_idx, "call_ref") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "call_ref: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_ref") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }

    // Check type signature matches
    let rt = check_type_signature_match(
      func_type, actual_type, "call_ref: type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let (rt, args) = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    return { ..rt, pc: rt.pc + 1 }
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.ctx.module_.codes.length() {
    rt.ctx.error_detail = "call_ref: invalid function index"
    return { ..rt, status: Trap }
  }
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_ref") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check type signature matches
  let rt = check_type_signature_match(
    func_type, actual_type, "call_ref: type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  let num_params = func_type.params.length()
  let new_sp = rt.stack_top - num_params

  // Check stack capacity for the callee
  if new_sp + code.max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller's frame
  rt.ctx.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    caller_sp: rt.sp,
    caller_num_locals: rt.num_locals,
  })

  // Push default values for declared locals
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update frame state
  {
    ..rt,
    sp: new_sp,
    num_locals: num_params + code.locals.length(),
    pc: callee_pc,
  }
}

///|
fn op_return_call_ref(rt : Runtime) -> Runtime {
  let (rt, type_idx) = read_imm_idx(rt)

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.stack_top - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  let rt = { ..rt, stack_top, }
  if func_ref_raw == -1 {
    rt.ctx.error_detail = "return_call_ref: null function reference"
    return { ..rt, status: Trap }
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

  // Get the expected function type
  let func_type = match
    get_func_type_or_error(rt, type_idx, "return_call_ref") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "return_call_ref: invalid imported function index"
      return { ..rt, status: Trap }
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
      Some(found) => found
      None => return { ..rt, status: Trap }
    }

    // Check type signature matches
    let rt = check_type_signature_match(
      func_type, actual_type, "return_call_ref: type mismatch", rt,
    )
    if rt.status == Trap {
      return rt
    }
    let (rt, args) = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    return handle_tail_call_return(rt)
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.ctx.module_.codes.length() {
    rt.ctx.error_detail = "return_call_ref: invalid function index"
    return { ..rt, status: Trap }
  }
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check type signature matches
  let rt = check_type_signature_match(
    func_type, actual_type, "return_call_ref: type mismatch", rt,
  )
  if rt.status == Trap {
    return rt
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
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
  let rt = { ..rt, stack_top: rt.sp + num_params }

  // Push default values for declared locals
  let rt = init_declared_locals(rt, code)
  if rt.status == Trap {
    return rt
  }

  // Update num_locals (sp stays same)
  { ..rt, num_locals: num_params + code.locals.length(), pc: callee_pc }
}

///|
fn op_nop(rt : Runtime) -> Runtime {
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_unreachable(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "unreachable"
  { ..rt, status: Trap }
}

///|
fn op_throw(rt : Runtime) -> Runtime {
  let (rt, tag_idx) = read_imm_idx(rt)
  rt.ctx.error_detail = "throw not implemented for tag \{tag_idx}"
  { ..rt, status: Trap }
}

///|
fn op_rethrow(rt : Runtime) -> Runtime {
  let (rt, label_idx) = read_imm_idx(rt)
  rt.ctx.error_detail = "rethrow not implemented for label \{label_idx}"
  { ..rt, status: Trap }
}

///|
fn op_simd_unimplemented(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "simd instruction not implemented"
  { ..rt, status: Trap }
}

///|
fn op_atomic_unimplemented(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "atomic instruction not implemented"
  { ..rt, status: Trap }
}

///|
fn op_gc_unimplemented(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "gc instruction not implemented"
  { ..rt, status: Trap }
}
// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
fn op_table_init(rt : Runtime) -> Runtime {
  let (rt, _table_idx) = read_imm_idx(rt)
  let (rt, _elem_idx) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 3
  let _n = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let _src = rt.stack.unsafe_get(rt.stack_top - 2).to_uint()
  let _dest = rt.stack.unsafe_get(stack_top).to_uint()
  // TODO: Implement table.init
  { ..rt, stack_top, pc: rt.pc + 1 }
}

///|
fn op_table_copy(rt : Runtime) -> Runtime {
  let (rt, _dst_table_idx) = read_imm_idx(rt)
  let (rt, _src_table_idx) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 3
  let _n = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let _src = rt.stack.unsafe_get(rt.stack_top - 2).to_uint()
  let _dest = rt.stack.unsafe_get(stack_top).to_uint()
  // TODO: Implement table.copy
  { ..rt, stack_top, pc: rt.pc + 1 }
}

///|
fn op_table_fill(rt : Runtime) -> Runtime {
  let (rt, table_idx) = read_imm_idx(rt)
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  let stack_top = rt.stack_top - 3
  let n = rt.stack.unsafe_get(rt.stack_top - 1).to_uint().reinterpret_as_int()
  let raw_ref = rt.stack
    .unsafe_get(rt.stack_top - 2)
    .reinterpret_as_int64()
    .to_int()
  let ref_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if dest < 0 || n < 0 || dest + n > table.length() {
    rt.ctx.error_detail = "table fill out of bounds"
    return { ..rt, stack_top, status: Trap }
  }
  for i = 0; i < n; i = i + 1 {
    table[dest + i] = ref_value
  }
  { ..rt, stack_top, pc: rt.pc + 1 }
}

///|
fn op_elem_drop(rt : Runtime) -> Runtime {
  let (rt, _elem_idx) = read_imm_idx(rt)
  // TODO: Implement elem.drop
  { ..rt, pc: rt.pc + 1 }
}

// =============================================================================
// Table operations
// =============================================================================

///|
fn op_table_size(rt : Runtime) -> Runtime {
  let (rt, table_idx) = read_imm_idx(rt)
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  let size = rt.ctx.tables[table_idx].data.length()
  rt.stack.unsafe_set(rt.stack_top, size.reinterpret_as_uint().to_uint64())
  { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_table_get(rt : Runtime) -> Runtime {
  let (rt, table_idx) = read_imm_idx(rt)
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  let stack_top = rt.stack_top - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    return { ..rt, stack_top, status: Trap }
  }
  // Return the function reference (or null) - stored as Int64, -1 = null
  let ref_val = match table[elem_idx] {
    Some(idx) => idx.to_int64()
    None => (-1).to_int64()
  }
  rt.stack.unsafe_set(stack_top, ref_val.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_table_set(rt : Runtime) -> Runtime {
  let (rt, table_idx) = read_imm_idx(rt)
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  // Pop ref value - stored as Int64, -1 = null
  let stack_top = rt.stack_top - 2
  let raw_ref = rt.stack
    .unsafe_get(rt.stack_top - 1)
    .reinterpret_as_int64()
    .to_int()
  let ref_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    return { ..rt, stack_top, status: Trap }
  }
  table[elem_idx] = ref_value
  { ..rt, stack_top, pc: rt.pc + 1 }
}

///|
fn op_table_grow(rt : Runtime) -> Runtime {
  let (rt, table_idx) = read_imm_idx(rt)
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.stack.unsafe_set(rt.stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
  }
  let stack_top = rt.stack_top - 2
  let delta = rt.stack
    .unsafe_get(rt.stack_top - 1)
    .to_uint()
    .reinterpret_as_int()
  // Pop ref value - stored as Int64, -1 = null
  let raw_ref = rt.stack.unsafe_get(stack_top).reinterpret_as_int64().to_int()
  let init_value : Int? = if raw_ref == -1 { None } else { Some(raw_ref) }
  let runtime_table = rt.ctx.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, stack_top: stack_top + 1, pc: rt.pc + 1 }
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int64().to_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL)
        return { ..rt, stack_top: stack_top + 1, pc: rt.pc + 1 }
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.unsafe_set(stack_top, old_size.reinterpret_as_uint().to_uint64())
  { ..rt, stack_top: stack_top + 1, pc: rt.pc + 1 }
}

// =============================================================================
// Reference operations
// =============================================================================

///|
fn op_ref_null(rt : Runtime) -> Runtime {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let (rt, _) = read_imm_idx(rt) // Skip the heap type encoding
  // Push null ref as -1 (Int64)
  rt.stack.unsafe_set(rt.stack_top, (-1).to_int64().reinterpret_as_uint64())
  { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_ref_func(rt : Runtime) -> Runtime {
  // ref.func pushes a reference to the given function onto the stack
  let (rt, func_idx) = read_imm_idx(rt)
  // Push func ref as Int64
  rt.stack.unsafe_set(rt.stack_top, func_idx.to_int64().reinterpret_as_uint64())
  { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_ref_is_null(rt : Runtime) -> Runtime {
  // ref.is_null tests whether a reference is null
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.stack_top - 1
  let ref_val = rt.stack.unsafe_get(stack_top).reinterpret_as_int64().to_int()
  let is_null : UInt64 = if ref_val == -1 { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, is_null)
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_ref_eq(rt : Runtime) -> Runtime {
  // ref.eq compares two references for identity equality
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.stack_top - 2
  let rhs = rt.stack
    .unsafe_get(rt.stack_top - 1)
    .reinterpret_as_int64()
    .to_int()
  let lhs = rt.stack.unsafe_get(stack_top).reinterpret_as_int64().to_int()
  let eq : UInt64 = if lhs == rhs { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, eq)
  { ..rt, stack_top: stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_ref_as_non_null(rt : Runtime) -> Runtime {
  // ref.as_non_null traps on null references
  // Refs are stored as Int64, -1 = null
  let value = rt.stack.unsafe_get(rt.stack_top - 1)
  let ref_val = value.reinterpret_as_int64().to_int()
  if ref_val == -1 {
    rt.ctx.error_detail = "ref.as_non_null: null reference"
    return { ..rt, status: Trap }
  }
  // Push back the non-null reference (it's already there, just advance pc)
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_global_get(rt : Runtime) -> Runtime {
  let (rt, idx) = read_imm_idx(rt)
  // Convert Value to UInt64 for stack
  rt.stack.unsafe_set(rt.stack_top, value_to_stack(rt.ctx.globals[idx]))
  { ..rt, stack_top: rt.stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_global_set(rt : Runtime) -> Runtime {
  let (rt, idx) = read_imm_idx(rt)
  let stack_top = rt.stack_top - 1
  let raw = rt.stack.unsafe_get(stack_top)
  // Infer the value type from the existing global's tag
  // (handles both imported and defined globals without index adjustment)
  let val_type : @core.ValType = match rt.ctx.globals[idx] {
    I32(_) => I32
    I64(_) => I64
    F32(_) => F32
    F64(_) => F64
    Ref(_) => FuncRef // Ref types all stored the same way
  }
  rt.ctx.globals[idx] = stack_to_value(raw, val_type)
  { ..rt, stack_top, pc: rt.pc + 1 }
}
