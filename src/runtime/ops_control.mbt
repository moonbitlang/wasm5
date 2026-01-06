///|
/// Local access uses unified stack: stack[bp + idx]
fn op_local_get(rt : Runtime) -> Runtime {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let value = rt.stack.unsafe_get(rt.bp + idx)
  rt.stack.unsafe_set(rt.sp, value)
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
}

///|
fn op_local_set(rt : Runtime) -> Runtime {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let value = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(rt.bp + idx, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_local_tee(rt : Runtime) -> Runtime {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let value = rt.stack.unsafe_get(rt.sp - 1)
  rt.stack.unsafe_set(rt.bp + idx, value)
  { ..rt, pc: rt.pc + 2 }
}

// ============================================================================
// Stack operations
// ============================================================================

///|
fn op_drop(rt : Runtime) -> Runtime {
  { ..rt, sp: rt.sp - 1, pc: rt.pc + 1 }
}

///|
fn op_select(rt : Runtime) -> Runtime {
  let stack_top = rt.sp - 3
  let cond = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let val2 = rt.stack.unsafe_get(rt.sp - 2)
  let val1 = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(stack_top, if cond != 0U { val1 } else { val2 })
  { ..rt, sp: stack_top + 1, pc: rt.pc + 1 }
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
  let else_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let cond = rt.stack.unsafe_get(stack_top).to_uint()
  if cond != 0U {
    { ..rt, sp: stack_top, pc: rt.pc + 2 }
  } else {
    { ..rt, sp: stack_top, pc: else_pc }
  }
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
fn op_br(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()

  // In-place stack shuffle: move arity values down by drop_count positions
  // Stack: [..., drop_values (drop_count), result_values (arity)]
  // Want:  [..., result_values (arity)]
  if drop_count > 0 && arity > 0 {
    let result_start = rt.sp - arity
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
  { ..rt, sp: rt.sp - drop_count, pc: target_pc }
}

///|
fn op_br_if(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let stack_top = rt.sp - 1
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
    { ..rt, sp: stack_top - drop_count, pc: target_pc }
  } else {
    { ..rt, sp: stack_top, pc: rt.pc + 4 }
  }
}

///|
fn op_br_table(rt : Runtime) -> Runtime {
  let num_labels = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 1
  let index = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Select target: use index if in range, otherwise use default (last entry)
  let selected = if index >= 0 && index < num_labels {
    index
  } else {
    num_labels
  }
  // Each label entry is 2 immediates: (target_pc, drop_count)
  // Labels start at pc + 3
  let label_base = rt.pc + 3 + selected * 2
  let target_pc = rt.ops.unsafe_get(label_base).to_int()
  let drop_count = rt.ops
    .unsafe_get(label_base + 1)
    .reinterpret_as_int64()
    .to_int()

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
  { ..rt, sp: stack_top - drop_count, pc: target_pc }
}

///|
fn op_br_on_null(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()
  // Pop reference value (refs are stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  let ref_idx = ref_val.to_int()
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
    { ..rt, sp: stack_top - drop_count, pc: target_pc }
  } else {
    // Not null - push back the value and continue
    rt.stack.unsafe_set(stack_top, ref_val)
    { ..rt, pc: rt.pc + 4 }
  }
}

///|
fn op_br_on_non_null(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()
  // Pop reference value (refs are stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  let ref_idx = ref_val.to_int()
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
    { ..rt, sp: stack_top - drop_count, pc: target_pc }
  } else {
    // Null - don't push anything, continue
    { ..rt, sp: stack_top, pc: rt.pc + 4 }
  }
}

///|
/// Call a local (module-defined) function.
/// Immediates (all computed at compile time):
///   pc+1: callee_pc
///   pc+2: num_params
///   pc+3: num_locals
///   pc+4: max_stack_height
/// Uses native stack: recursively calls execute() for the callee.
fn op_call_local(rt : Runtime) -> Runtime {
  let callee_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_params = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let num_locals = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let max_stack_height = rt.ops.unsafe_get(rt.pc + 4).to_int()

  // Unified stack: arguments are already on stack, they become callee's first locals
  let new_bp = rt.sp - num_params

  // Check stack capacity for the callee
  if new_bp + max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller state on native stack
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let return_pc = rt.pc + 5 // Next instruction after call (op + 4 immediates)

  // Set up callee frame (locals will be initialized by compiled code)
  let rt = { ..rt, sp: new_bp + num_params, bp: new_bp, num_locals }

  // Recursively execute callee using native stack
  let rt = execute_call(rt, callee_pc, caller_bp, caller_num_locals, return_pc) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return { ..rt, status: Trap }
    }
  }
  rt
}

///|
/// Call an imported function. Immediate is the original func_idx.
fn op_call_import(rt : Runtime) -> Runtime {
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)
  let type_idx = get_func_type_idx(rt.ctx.module_, func_idx, num_imported_funcs)
  if type_idx < 0 {
    rt.ctx.error_detail = "call: invalid imported function index"
    return { ..rt, status: Trap }
  }
  let func_type = match get_func_type_or_error(rt, type_idx, "call") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }
  let { rt, args } = pop_arguments(rt, func_type)
  let rt = call_imported_function(
    rt,
    func_idx,
    args,
    func_type.results.length(),
  )
  { ..rt, pc: rt.pc + 2 }
}

///|
/// Return from a function. Uses native stack approach.
/// Copies return values to bp position and sets Returned status.
/// The caller's execute_call will restore caller state.
fn op_return(rt : Runtime) -> Runtime {
  // Read result count from immediate (emitted at compile time)
  let num_return_values = rt.ops
    .unsafe_get(rt.pc + 1)
    .reinterpret_as_int64()
    .to_int()

  // Unified stack return:
  // Return values are the top num_return_values values on the stack
  // Copy them in-place to: stack[bp .. bp + num_return_values)
  let return_start = rt.sp - num_return_values

  // Copy return values to start of frame
  for i = 0; i < num_return_values; i = i + 1 {
    rt.stack.unsafe_set(rt.bp + i, rt.stack.unsafe_get(return_start + i))
  }

  // Trim stack to keep only return values at frame position
  let stack_top = rt.bp + num_return_values

  // Check if this is the entry function (bp == 0) or a nested call
  if rt.bp == 0 {
    // Entry function returning - results are now at stack[0..num_return_values)
    { ..rt, sp: stack_top, status: Terminated }
  } else {
    // Nested call returning - let native stack unwind
    // Caller's execute_call will restore bp, num_locals, pc
    { ..rt, sp: stack_top, status: Returned }
  }
}

///|
/// Call a function indirectly via table. Uses native stack approach.
fn op_call_indirect(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Pop the function index from the stack
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let rt = { ..rt, sp: stack_top }

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
  // Check for null (0xFFFFFFFFFFFFFFFF)
  if func_ref == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "uninitialized element"
    return { ..rt, status: Trap }
  }
  // Extract func_idx from tagged funcref (remove tag bits)
  let func_idx = func_ref
    .land(0x3FFFFFFFFFFFFFFFUL)
    .reinterpret_as_int64()
    .to_int()

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "call_indirect") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }

  // Check if this is an external funcref (negative index from external_funcrefs)
  // External funcrefs are stored as funcref tag | negative value
  // Need to decode and check for external refs
  let is_external = (func_ref & 0x4000000000000000UL) != 0UL && func_idx < 0
  if is_external {
    let ext_idx = -(func_idx + 1)
    // First check the table's external_funcrefs (for cross-module table sharing)
    let table = rt.ctx.tables[table_idx]
    let ext_func = if ext_idx >= 0 && ext_idx < table.external_funcrefs.length() {
      table.external_funcrefs[ext_idx]
    } else if ext_idx >= 0 && ext_idx < rt.ctx.external_funcrefs.length() {
      // Fall back to runtime's external_funcrefs (for imported funcref globals)
      rt.ctx.external_funcrefs[ext_idx]
    } else {
      rt.ctx.error_detail = "call_indirect: invalid external funcref index"
      return { ..rt, status: Trap }
    }
    // Pop arguments and call external function
    let { rt, args } = pop_arguments(rt, expected_type)
    let results = (ext_func.func)(args)
    // Push results back onto the stack
    let rt = push_results(rt, results)
    return { ..rt, pc: rt.pc + 3 }
  }
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)

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

    // Check type matches using nominal typing (GC proposal)
    if not(gc_is_type_subtype(rt, actual_type_idx, type_idx)) {
      rt.ctx.error_detail = "indirect call type mismatch"
      return { ..rt, status: Trap }
    }
    let { rt, args } = pop_arguments(rt, actual_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      expected_type.results.length(),
    )
    return { ..rt, pc: rt.pc + 3 }
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

  // Check type matches using nominal typing (GC proposal)
  // For call_indirect, actual type must match expected type via type index subtyping
  if not(gc_is_type_subtype(rt, actual_type_idx, type_idx)) {
    rt.ctx.error_detail = "indirect call type mismatch"
    return { ..rt, status: Trap }
  }
  let code = rt.ctx.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.ctx.error_detail = "Function not compiled: \{func_idx}"
    return { ..rt, status: Trap }
  }

  // Unified stack: arguments are already on stack, they become callee's first locals
  let num_params = actual_type.params.length()
  let new_bp = rt.sp - num_params

  // Check stack capacity for the callee
  if new_bp + code.max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller state on native stack
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let return_pc = rt.pc + 3 // Next instruction after call_indirect

  // Set up callee frame (locals will be initialized by compiled code)
  let rt = {
    ..rt,
    sp: new_bp + num_params,
    bp: new_bp,
    num_locals: num_params + code.locals.length(),
  }

  // Recursively execute callee using native stack
  let rt = execute_call(rt, callee_pc, caller_bp, caller_num_locals, return_pc) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return { ..rt, status: Trap }
    }
  }
  rt
}

///|
/// Tail call a local (module-defined) function.
/// Immediates (all computed at compile time):
///   pc+1: callee_pc
///   pc+2: num_params
///   pc+3: num_locals
fn op_return_call_local(rt : Runtime) -> Runtime {
  let callee_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_params = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let num_locals = rt.ops.unsafe_get(rt.pc + 3).to_int()

  // Tail call: reuse current frame
  // Move arguments in-place from stack top to bp position
  let args_start = rt.sp - num_params

  // Copy arguments to bp position (they become new locals)
  if num_params > 0 && args_start > rt.bp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.bp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to bp + num_params (locals will be initialized by compiled code)
  { ..rt, sp: rt.bp + num_params, num_locals, pc: callee_pc }
}

///|
/// Tail call an imported function. Immediate is the original func_idx.
fn op_return_call_import(rt : Runtime) -> Runtime {
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_imported_funcs = count_imported_funcs(rt.ctx.module_)
  let type_idx = get_func_type_idx(rt.ctx.module_, func_idx, num_imported_funcs)
  if type_idx < 0 {
    rt.ctx.error_detail = "return_call: invalid imported function index"
    return { ..rt, status: Trap }
  }
  let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
    Some(found) => found
    None => return { ..rt, status: Trap }
  }
  let { rt, args } = pop_arguments(rt, func_type)
  let rt = call_imported_function(
    rt,
    func_idx,
    args,
    func_type.results.length(),
  )
  handle_tail_call_return(rt)
}

///|
fn op_return_call_indirect(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Pop the function index from the stack
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let rt = { ..rt, sp: stack_top }

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
  // Check for null (0xFFFFFFFFFFFFFFFF)
  if func_ref == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "uninitialized element"
    return { ..rt, status: Trap }
  }
  // Extract func_idx from tagged funcref (remove tag bits)
  let func_idx = func_ref
    .land(0x3FFFFFFFFFFFFFFFUL)
    .reinterpret_as_int64()
    .to_int()
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
    let { rt, args } = pop_arguments(rt, actual_type)
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
  let args_start = rt.sp - num_params

  // Copy arguments to sp position (they become new locals)
  if num_params > 0 && args_start > rt.bp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.bp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to bp + num_params (locals will be initialized by compiled code)
  {
    ..rt,
    sp: rt.bp + num_params,
    num_locals: num_params + code.locals.length(),
    pc: callee_pc,
  }
}

///|
/// Call a function via reference. Uses native stack approach.
fn op_call_ref(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  let rt = { ..rt, sp: stack_top }
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
    let { rt, args } = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    return { ..rt, pc: rt.pc + 2 }
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
  let new_bp = rt.sp - num_params

  // Check stack capacity for the callee
  if new_bp + code.max_stack_height > rt.stack.length() {
    rt.ctx.error_detail = "Stack overflow: need \{code.max_stack_height} slots"
    return { ..rt, status: Trap }
  }

  // Save caller state on native stack
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let return_pc = rt.pc + 2 // Next instruction after call_ref

  // Set up callee frame (locals will be initialized by compiled code)
  let rt = {
    ..rt,
    sp: new_bp + num_params,
    bp: new_bp,
    num_locals: num_params + code.locals.length(),
  }

  // Recursively execute callee using native stack
  let rt = execute_call(rt, callee_pc, caller_bp, caller_num_locals, return_pc) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return { ..rt, status: Trap }
    }
  }
  rt
}

///|
fn op_return_call_ref(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  let rt = { ..rt, sp: stack_top }
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
    let { rt, args } = pop_arguments(rt, func_type)
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
  let args_start = rt.sp - num_params

  // Copy arguments to sp position (they become new locals)
  if num_params > 0 && args_start > rt.bp {
    for i = 0; i < num_params; i = i + 1 {
      rt.stack.unsafe_set(rt.bp + i, rt.stack.unsafe_get(args_start + i))
    }
  }

  // Trim stack to bp + num_params (locals will be initialized by compiled code)
  {
    ..rt,
    sp: rt.bp + num_params,
    num_locals: num_params + code.locals.length(),
    pc: callee_pc,
  }
}

///|
fn op_nop(rt : Runtime) -> Runtime {
  { ..rt, pc: rt.pc + 1 }
}

///|
/// Batch initialize locals with zeros (for i32/i64/f32/f64).
/// Immediate: count of zeros to push.
fn op_init_zeros(rt : Runtime) -> Runtime {
  let count = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let mut sp = rt.sp
  for i = 0; i < count; i = i + 1 {
    rt.stack.unsafe_set(sp, 0UL)
    sp += 1
  }
  { ..rt, sp, pc: rt.pc + 2 }
}

///|
/// Batch initialize locals with null refs (for reference types).
/// Immediate: count of null refs to push.
fn op_init_null_refs(rt : Runtime) -> Runtime {
  let count = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let null_ref = (-1L).reinterpret_as_uint64()
  let mut sp = rt.sp
  for i = 0; i < count; i = i + 1 {
    rt.stack.unsafe_set(sp, null_ref)
    sp += 1
  }
  { ..rt, sp, pc: rt.pc + 2 }
}

///|
/// Trap for unsupported local type (V128, etc.)
fn op_local_init_unsupported(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "Unsupported local type"
  { ..rt, status: Trap }
}

///|
fn op_unreachable(rt : Runtime) -> Runtime {
  rt.ctx.error_detail = "unreachable"
  { ..rt, status: Trap }
}

///|
fn op_throw(rt : Runtime) -> Runtime {
  let tag_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  rt.ctx.error_detail = "throw not implemented for tag \{tag_idx}"
  { ..rt, status: Trap }
}

///|
fn op_rethrow(rt : Runtime) -> Runtime {
  let label_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
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

// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
fn op_table_init(rt : Runtime) -> Runtime {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let elem_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let src = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int()
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Check if element segment exists and is not dropped
  if elem_idx < 0 || elem_idx >= rt.ctx.dropped_elems.length() {
    rt.ctx.error_detail = "out of bounds table access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Check if segment is dropped (active/declarative segments are dropped after instantiation)
  if rt.ctx.dropped_elems[elem_idx] {
    // Dropped segment: any non-zero length is out of bounds
    if n != 0 || src != 0 {
      rt.ctx.error_detail = "out of bounds table access"
      return { ..rt, sp: stack_top, status: Trap }
    }
    // n=0, src=0 is valid even for dropped segments
    return { ..rt, sp: stack_top, pc: rt.pc + 3 }
  }

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let table = rt.ctx.tables[table_idx]
  let elem = rt.ctx.module_.elems[elem_idx]

  // Check bounds
  if n < 0 ||
    src < 0 ||
    dest < 0 ||
    src + n > elem.init.length() ||
    dest + n > table.data.length() {
    rt.ctx.error_detail = "out of bounds table access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Copy elements from segment to table
  for i = 0; i < n; i = i + 1 {
    let expr = elem.init[src + i]
    // Evaluate the init expression to get the reference value
    // Use eval_const_expr to handle all expression types including ref.i31
    try {
      let value = eval_const_expr(expr, rt.ctx.globals)
      // Convert Value to UInt64 for table storage
      table.data[dest + i] = value_to_stack(value)
    } catch {
      e => {
        rt.ctx.error_detail = "error evaluating element init: \{e}"
        return { ..rt, sp: stack_top, status: Trap }
      }
    }
  }
  { ..rt, sp: stack_top, pc: rt.pc + 3 }
}

///|
fn op_table_copy(rt : Runtime) -> Runtime {
  let dst_table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let src_table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 3

  // Bounds check table indices
  if dst_table_idx < 0 ||
    dst_table_idx >= rt.ctx.tables.length() ||
    src_table_idx < 0 ||
    src_table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let src = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int()
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let dst_table = rt.ctx.tables[dst_table_idx]
  let src_table = rt.ctx.tables[src_table_idx]

  // Bounds checking - stack values are dynamic, must check at runtime
  // The < 0 checks catch large unsigned values (>= 2^31) that appear negative when signed
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > src_table.data_length() ||
    dest + n > dst_table.data_length() {
    rt.ctx.error_detail = "out of bounds table access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Copy elements with proper overlap handling
  if dst_table_idx == src_table_idx && dest > src && dest < src + n {
    // Overlapping, dest > src: copy backwards
    for i = n - 1; i >= 0; i = i - 1 {
      dst_table.set_data(dest + i, src_table.get_data(src + i))
    }
  } else {
    // Non-overlapping or src >= dest: copy forwards
    for i = 0; i < n; i = i + 1 {
      dst_table.set_data(dest + i, src_table.get_data(src + i))
    }
  }
  { ..rt, sp: stack_top, pc: rt.pc + 3 }
}

///|
fn op_table_fill(rt : Runtime) -> Runtime {
  // Table index is validated at compile time by the validator
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  // Get the raw 64-bit reference value directly (preserves tags)
  let ref_value = rt.stack.unsafe_get(rt.sp - 2)
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if dest < 0 || n < 0 || dest + n > table.length() {
    rt.ctx.error_detail = "table fill out of bounds"
    return { ..rt, sp: stack_top, status: Trap }
  }
  for i = 0; i < n; i = i + 1 {
    table[dest + i] = ref_value
  }
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_elem_drop(rt : Runtime) -> Runtime {
  let elem_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Mark the element segment as dropped
  if elem_idx >= 0 && elem_idx < rt.ctx.dropped_elems.length() {
    rt.ctx.dropped_elems[elem_idx] = true
  }
  { ..rt, pc: rt.pc + 2 }
}

// =============================================================================
// Table operations
// =============================================================================

///|
fn op_table_size(rt : Runtime) -> Runtime {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  let size = rt.ctx.tables[table_idx].data.length()
  rt.stack.unsafe_set(rt.sp, size.reinterpret_as_uint().to_uint64())
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
}

///|
fn op_table_get(rt : Runtime) -> Runtime {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    return { ..rt, sp: stack_top, status: Trap }
  }
  // Return the function reference (or null) directly as UInt64
  let ref_val = table[elem_idx]
  rt.stack.unsafe_set(stack_top, ref_val)
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_table_set(rt : Runtime) -> Runtime {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return { ..rt, status: Trap }
  }
  // Pop ref value as 64-bit (preserves tags)
  let stack_top = rt.sp - 2
  let ref_value = rt.stack.unsafe_get(rt.sp - 1)
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    return { ..rt, sp: stack_top, status: Trap }
  }
  table[elem_idx] = ref_value
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_table_grow(rt : Runtime) -> Runtime {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.stack.unsafe_set(rt.sp, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
  }
  let stack_top = rt.sp - 2
  let delta = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  // Pop ref value as 64-bit (preserves tags)
  let init_value = rt.stack.unsafe_get(stack_top)
  let runtime_table = rt.ctx.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, sp: stack_top + 1, pc: rt.pc + 2 }
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.to_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL)
        return { ..rt, sp: stack_top + 1, pc: rt.pc + 2 }
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.unsafe_set(stack_top, old_size.reinterpret_as_uint().to_uint64())
  { ..rt, sp: stack_top + 1, pc: rt.pc + 2 }
}

// =============================================================================
// Reference operations
// =============================================================================

///|
fn op_ref_null(rt : Runtime) -> Runtime {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.ops.unsafe_get(rt.pc + 1).to_int() // Skip the heap type encoding
  // Push null ref as -1 (Int64)
  rt.stack.unsafe_set(rt.sp, (-1).to_int64().reinterpret_as_uint64())
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
}

///|
fn op_ref_func(rt : Runtime) -> Runtime {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Push func ref tagged with bit 62 (0x4000000000000000)
  let tagged = func_idx.to_uint64() | 0x4000000000000000UL
  rt.stack.unsafe_set(rt.sp, tagged)
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
}

///|
fn op_ref_is_null(rt : Runtime) -> Runtime {
  // ref.is_null tests whether a reference is null
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top).to_int()
  let is_null : UInt64 = if ref_val == -1 { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, is_null)
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_ref_eq(rt : Runtime) -> Runtime {
  // ref.eq compares two references for identity equality
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.sp - 2
  let rhs = rt.stack.unsafe_get(rt.sp - 1).to_int()
  let lhs = rt.stack.unsafe_get(stack_top).to_int()
  let eq : UInt64 = if lhs == rhs { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, eq)
  { ..rt, sp: stack_top + 1, pc: rt.pc + 1 }
}

///|
fn op_ref_as_non_null(rt : Runtime) -> Runtime {
  // ref.as_non_null traps on null references
  // Refs are stored as Int64, -1 = null
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let ref_val = value.to_int()
  if ref_val == -1 {
    rt.ctx.error_detail = "ref.as_non_null: null reference"
    return { ..rt, status: Trap }
  }
  // Push back the non-null reference (it's already there, just advance pc)
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_global_get(rt : Runtime) -> Runtime {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Convert Value to UInt64 for stack
  rt.stack.unsafe_set(rt.sp, value_to_stack(rt.ctx.globals[idx]))
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 2 }
}

///|
fn op_global_set(rt : Runtime) -> Runtime {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let raw = rt.stack.unsafe_get(stack_top)
  // Infer the value type from the existing global's tag
  // (handles both imported and defined globals without index adjustment)
  let val_type : @core.ValType = match rt.ctx.globals[idx] {
    I32(_) => I32
    I64(_) => I64
    F32(_) => F32
    F64(_) => F64
    Ref(_) | Funcref(_) | Externref(_) => FuncRef // Ref types all stored the same way
  }
  rt.ctx.globals[idx] = stack_to_value(raw, val_type)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}
