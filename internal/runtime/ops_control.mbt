///|
/// Local access uses unified stack: stack[bp + idx]
fn op_local_get(rt : Instance) -> ReturnCode {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let value = rt.stack.unsafe_get(rt.bp + idx)
  rt.stack.unsafe_set(rt.sp, value)
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_local_set(rt : Instance) -> ReturnCode {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let value = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(rt.bp + idx, value)
  rt.sp = stack_top
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_local_tee(rt : Instance) -> ReturnCode {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let value = rt.stack.unsafe_get(rt.sp - 1)
  rt.stack.unsafe_set(rt.bp + idx, value)
  rt.pc = rt.pc + 2
  Running
}

// ============================================================================
// Stack operations
// ============================================================================

///|
fn op_drop(rt : Instance) -> ReturnCode {
  rt.sp = rt.sp - 1
  rt.pc = rt.pc + 1
  Running
}

///|
fn op_select(rt : Instance) -> ReturnCode {
  let stack_top = rt.sp - 3
  let cond = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let val2 = rt.stack.unsafe_get(rt.sp - 2)
  let val1 = rt.stack.unsafe_get(stack_top)
  rt.stack.unsafe_set(stack_top, if cond != 0U { val1 } else { val2 })
  rt.sp = stack_top + 1
  rt.pc = rt.pc + 1
  Running
}

// ============================================================================
// Slot-based control helpers (unified IR)
// ============================================================================

///|
fn op_entry(rt : Instance) -> ReturnCode {
  let num_locals = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let first_local = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let num_to_zero = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let new_sp = rt.bp + num_locals
  if new_sp > rt.stack.length() {
    rt.ctx.error_detail = "stack overflow"
    return Trap
  }
  for i = 0; i < num_to_zero; i = i + 1 {
    rt.stack.unsafe_set(rt.bp + first_local + i, 0UL)
  }
  rt.sp = new_sp
  rt.num_locals = num_locals
  rt.pc = rt.pc + 4
  Running
}

///|
fn op_copy_slot(rt : Instance) -> ReturnCode {
  let src_slot = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let dst_slot = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let value = rt.stack.unsafe_get(rt.bp + src_slot)
  rt.stack.unsafe_set(rt.bp + dst_slot, value)
  rt.pc = rt.pc + 3
  Running
}

///|
fn op_set_sp(rt : Instance) -> ReturnCode {
  let slot = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let new_sp = rt.bp + slot
  if new_sp > rt.stack.length() {
    rt.ctx.error_detail = "stack overflow"
    return Trap
  }
  rt.sp = new_sp
  rt.pc = rt.pc + 2
  Running
}

///|
fn get_func_type_or_error(
  rt : Instance,
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
fn op_if(rt : Instance) -> ReturnCode {
  let else_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let cond = rt.stack.unsafe_get(stack_top).to_uint()
  if cond != 0U {
    rt.sp = stack_top
    rt.pc = rt.pc + 2
    Running
  } else {
    rt.sp = stack_top
    rt.pc = else_pc
    Running
  }
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
fn op_br(rt : Instance) -> ReturnCode {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  rt.pc = target_pc
  Running
}

///|
fn op_br_if(rt : Instance) -> ReturnCode {
  let taken_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let not_taken_pc = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 1
  let cond = rt.stack.unsafe_get(stack_top).to_uint()
  rt.sp = stack_top
  if cond != 0U {
    rt.pc = taken_pc
  } else {
    rt.pc = not_taken_pc
  }
  Running
}

///|
fn op_br_table(rt : Instance) -> ReturnCode {
  let num_labels = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let stack_top = rt.sp - 1
  let index = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  rt.sp = stack_top

  // Select target: use index if in range, otherwise use default (last entry)
  let selected = if index >= 0 && index < num_labels {
    index
  } else {
    num_labels
  }
  let target_pc = rt.ops.unsafe_get(rt.pc + 2 + selected).to_int()
  rt.pc = target_pc
  Running
}

///|
fn op_br_on_null(rt : Instance) -> ReturnCode {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let not_taken_pc = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  if ref_val.reinterpret_as_int64() == -1L {
    rt.sp = stack_top
    rt.pc = target_pc
  } else {
    rt.pc = not_taken_pc
  }
  Running
}

///|
fn op_br_on_non_null(rt : Instance) -> ReturnCode {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let not_taken_pc = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top)
  if ref_val.reinterpret_as_int64() != -1L {
    rt.pc = target_pc
  } else {
    rt.sp = stack_top
    rt.pc = not_taken_pc
  }
  Running
}

///|
/// Call a local (module-defined) function.
/// Immediates:
///   pc+1: callee_pc
///   pc+2: frame_offset (relative to bp, args already in place)
/// Uses native stack: recursively calls execute() for the callee.
fn op_call(rt : Instance) -> ReturnCode {
  let callee_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let frame_offset = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let caller_sp = rt.sp
  let return_pc = rt.pc + 3

  // Set up callee frame (locals will be initialized by compiled code)
  let new_bp = caller_bp + frame_offset
  rt.bp = new_bp

  // Recursively execute callee using native stack
  let _ = execute_call(
    rt, callee_pc, caller_bp, caller_num_locals, caller_sp, return_pc,
  ) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return Trap
    }
  }
  Running
}

///|
/// Call an imported function. Immediates: import_idx, frame_offset.
fn op_call_import(rt : Instance) -> ReturnCode {
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let _frame_offset = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let num_imported_funcs = rt.ctx.num_imported_funcs
  let type_idx = @core.get_func_type_idx(
    rt.ctx.module_,
    func_idx,
    num_imported_funcs,
  )
  if type_idx < 0 {
    rt.ctx.error_detail = "call: invalid imported function index"
    return Trap
  }
  let func_type = match get_func_type_or_error(rt, type_idx, "call") {
    Some(found) => found
    None => return Trap
  }
  let { rt, args } = pop_arguments(rt, func_type)
  let rt = call_imported_function(
    rt,
    func_idx,
    args,
    func_type.results.length(),
  )
  rt.pc = rt.pc + 3
  Running
}

///|
/// Call a function in another module (not supported in MoonBit runtime).
fn op_call_external(rt : Instance) -> ReturnCode {
  rt.ctx.error_detail = "call_external not implemented"
  Trap
}

///|
/// Copy results to bp and return a return code.
fn finish_function_return(rt : Instance, num_results : Int) -> ReturnCode {
  let return_start = rt.sp - num_results
  for i = 0; i < num_results; i = i + 1 {
    rt.stack.unsafe_set(rt.bp + i, rt.stack.unsafe_get(return_start + i))
  }
  rt.sp = rt.bp + num_results
  if rt.bp == 0 {
    Terminated
  } else {
    Returned
  }
}

///|
/// Return from a function. Uses native stack approach.
/// Copies return values to bp position and returns Returned for non-entry calls.
fn op_return(rt : Instance) -> ReturnCode {
  let num_return_values = rt.ops.unsafe_get(rt.pc + 1).to_int()
  finish_function_return(rt, num_return_values)
}

///|
/// End of function (implicit return).
fn op_end(rt : Instance) -> ReturnCode {
  let num_results = rt.ops.unsafe_get(rt.pc + 1).to_int()
  finish_function_return(rt, num_results)
}

///|
/// Function exit without copying (results already placed at bp).
fn op_func_exit(rt : Instance) -> ReturnCode {
  if rt.bp == 0 {
    Terminated
  } else {
    Returned
  }
}

///|
/// Call a function indirectly via table. Uses native stack approach.
fn op_call_indirect(rt : Instance) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let frame_offset = rt.ops.unsafe_get(rt.pc + 3).to_int()

  // Pop the function index from the stack
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  rt.sp = stack_top
  let caller_sp = rt.sp

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "call_indirect: invalid table index"
    return Trap
  }
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "undefined element"
    return Trap
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  // Check for null (0xFFFFFFFFFFFFFFFF)
  if func_ref == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "uninitialized element"
    return Trap
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
    None => return Trap
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
      return Trap
    }
    // Pop arguments and call external function
    let { rt, args } = pop_arguments(rt, expected_type)
    let results = (ext_func.func)(args)
    // Push results back onto the stack
    let rt = push_results(rt, results)
    rt.pc = rt.pc + 4
    return Running
  }
  let num_imported_funcs = rt.ctx.num_imported_funcs

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = @core.get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "call_indirect: invalid imported function index"
      return Trap
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
      Some(found) => found
      None => return Trap
    }

    // Check type matches using nominal typing (GC proposal)
    if not(gc_is_type_subtype(rt, actual_type_idx, type_idx)) {
      rt.ctx.error_detail = "indirect call type mismatch"
      return Trap
    }
    let { rt, args } = pop_arguments(rt, actual_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      expected_type.results.length(),
    )
    rt.pc = rt.pc + 4
    return Running
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 ||
    local_func_idx >= rt.ctx.compiled.func_entries.length() {
    rt.ctx.error_detail = "call_indirect: invalid function index"
    return Trap
  }

  // Get the actual function type
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let _actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_indirect") {
    Some(found) => found
    None => return Trap
  }

  // Check type matches using nominal typing (GC proposal)
  // For call_indirect, actual type must match expected type via type index subtyping
  if not(gc_is_type_subtype(rt, actual_type_idx, type_idx)) {
    rt.ctx.error_detail = "indirect call type mismatch"
    return Trap
  }
  let callee_pc = rt.ctx.compiled.func_entries[local_func_idx]

  // Save caller state on native stack
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let return_pc = rt.pc + 4 // Next instruction after call_indirect

  // Set up callee frame (locals will be initialized by compiled code)
  rt.bp = caller_bp + frame_offset

  // Recursively execute callee using native stack
  let _ = execute_call(
    rt, callee_pc, caller_bp, caller_num_locals, caller_sp, return_pc,
  ) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return Trap
    }
  }
  Running
}

///|
/// Tail call a local (module-defined) function.
/// Immediates (all computed at compile time):
///   pc+1: callee_pc
///   pc+2: num_params
///   pc+3: num_locals
fn op_return_call_local(rt : Instance) -> ReturnCode {
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
  rt.sp = rt.bp + num_params
  rt.num_locals = num_locals
  rt.pc = callee_pc
  Running
}

///|
/// Tail call an imported function. Immediate is the original func_idx.
fn op_return_call_import(rt : Instance) -> ReturnCode {
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_imported_funcs = rt.ctx.num_imported_funcs
  let type_idx = @core.get_func_type_idx(
    rt.ctx.module_,
    func_idx,
    num_imported_funcs,
  )
  if type_idx < 0 {
    rt.ctx.error_detail = "return_call: invalid imported function index"
    return Trap
  }
  let func_type = match get_func_type_or_error(rt, type_idx, "return_call") {
    Some(found) => found
    None => return Trap
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
fn op_return_call_indirect(rt : Instance) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Pop the function index from the stack
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  rt.sp = stack_top
  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "return_call_indirect: invalid table index"
    return Trap
  }
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "undefined element"
    return Trap
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  // Check for null (0xFFFFFFFFFFFFFFFF)
  if func_ref == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "uninitialized element"
    return Trap
  }
  // Extract func_idx from tagged funcref (remove tag bits)
  let func_idx = func_ref
    .land(0x3FFFFFFFFFFFFFFFUL)
    .reinterpret_as_int64()
    .to_int()
  let num_imported_funcs = rt.ctx.num_imported_funcs

  // Get the expected type
  let expected_type = match
    get_func_type_or_error(rt, type_idx, "return_call_indirect") {
    Some(found) => found
    None => return Trap
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = @core.get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "return_call_indirect: invalid imported function index"
      return Trap
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
      Some(found) => found
      None => return Trap
    }

    // Check type signature matches
    let check_code = check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if check_code == Trap {
      return Trap
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
    return Trap
  }

  // Get the actual function type
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_indirect") {
    Some(found) => found
    None => return Trap
  }

  // Check type signature matches
  let check_code = check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if check_code == Trap {
    return Trap
  }
  let callee_pc = rt.ctx.compiled.func_entries[local_func_idx]
  let num_locals = rt.ctx.compiled.func_num_locals[local_func_idx]

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
  rt.sp = rt.bp + num_params
  rt.num_locals = num_locals
  rt.pc = callee_pc
  Running
}

///|
/// Call a function via reference. Uses native stack approach.
fn op_call_ref(rt : Instance) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let frame_offset = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  rt.sp = stack_top
  let caller_sp = rt.sp
  if func_ref_raw == -1 {
    rt.ctx.error_detail = "call_ref: null function reference"
    return Trap
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = rt.ctx.num_imported_funcs

  // Get the expected function type
  let func_type = match get_func_type_or_error(rt, type_idx, "call_ref") {
    Some(found) => found
    None => return Trap
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = @core.get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "call_ref: invalid imported function index"
      return Trap
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "call_ref") {
      Some(found) => found
      None => return Trap
    }

    // Check type signature matches
    let check_code = check_type_signature_match(
      func_type, actual_type, "call_ref: type mismatch", rt,
    )
    if check_code == Trap {
      return Trap
    }
    let { rt, args } = pop_arguments(rt, func_type)
    let rt = call_imported_function(
      rt,
      func_idx,
      args,
      func_type.results.length(),
    )
    rt.pc = rt.pc + 3
    return Running
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 ||
    local_func_idx >= rt.ctx.compiled.func_entries.length() {
    rt.ctx.error_detail = "call_ref: invalid function index"
    return Trap
  }
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "call_ref") {
    Some(found) => found
    None => return Trap
  }

  // Check type signature matches
  let check_code = check_type_signature_match(
    func_type, actual_type, "call_ref: type mismatch", rt,
  )
  if check_code == Trap {
    return Trap
  }
  let callee_pc = rt.ctx.compiled.func_entries[local_func_idx]

  // Save caller state on native stack
  let caller_bp = rt.bp
  let caller_num_locals = rt.num_locals
  let return_pc = rt.pc + 3 // Next instruction after call_ref

  // Set up callee frame (locals will be initialized by compiled code)
  rt.bp = caller_bp + frame_offset

  // Recursively execute callee using native stack
  let _ = execute_call(
    rt, callee_pc, caller_bp, caller_num_locals, caller_sp, return_pc,
  ) catch {
    err => {
      rt.ctx.error_detail = err.to_string()
      return Trap
    }
  }
  rt.sp = caller_bp + frame_offset + func_type.results.length()
  Running
}

///|
fn op_return_call_ref(rt : Instance) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()

  // Pop the function reference from the stack (stored as Int64, -1 = null)
  let stack_top = rt.sp - 1
  let func_ref_raw = rt.stack
    .unsafe_get(stack_top)
    .reinterpret_as_int64()
    .to_int()
  rt.sp = stack_top
  if func_ref_raw == -1 {
    rt.ctx.error_detail = "return_call_ref: null function reference"
    return Trap
  }
  let func_idx = func_ref_raw
  let num_imported_funcs = rt.ctx.num_imported_funcs

  // Get the expected function type
  let func_type = match
    get_func_type_or_error(rt, type_idx, "return_call_ref") {
    Some(found) => found
    None => return Trap
  }

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = @core.get_func_type_idx(
      rt.ctx.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.ctx.error_detail = "return_call_ref: invalid imported function index"
      return Trap
    }
    let actual_type = match
      get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
      Some(found) => found
      None => return Trap
    }

    // Check type signature matches
    let check_code = check_type_signature_match(
      func_type, actual_type, "return_call_ref: type mismatch", rt,
    )
    if check_code == Trap {
      return Trap
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
    return Trap
  }
  let actual_type_idx = rt.ctx.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = match
    get_func_type_or_error(rt, actual_type_idx, "return_call_ref") {
    Some(found) => found
    None => return Trap
  }

  // Check type signature matches
  let check_code = check_type_signature_match(
    func_type, actual_type, "return_call_ref: type mismatch", rt,
  )
  if check_code == Trap {
    return Trap
  }
  let callee_pc = rt.ctx.compiled.func_entries[local_func_idx]
  let num_locals = rt.ctx.compiled.func_num_locals[local_func_idx]

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
  rt.sp = rt.bp + num_params
  rt.num_locals = num_locals
  rt.pc = callee_pc
  Running
}

///|
fn op_nop(rt : Instance) -> ReturnCode {
  rt.pc = rt.pc + 1
  Running
}

///|
fn op_unreachable(rt : Instance) -> ReturnCode {
  rt.ctx.error_detail = "unreachable"
  Trap
}

// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
fn op_table_init(rt : Instance) -> ReturnCode {
  let elem_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let src = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int()
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Check if element segment exists and is not dropped
  if elem_idx < 0 || elem_idx >= rt.ctx.dropped_elems.length() {
    rt.ctx.error_detail = "out of bounds table access"
    rt.sp = stack_top
    return Trap
  }

  // Check if segment is dropped (active/declarative segments are dropped after instantiation)
  if rt.ctx.dropped_elems[elem_idx] {
    // Dropped segment: any non-zero length is out of bounds
    if n != 0 || src != 0 {
      rt.ctx.error_detail = "out of bounds table access"
      rt.sp = stack_top
      return Trap
    }
    // n=0, src=0 is valid even for dropped segments
    rt.sp = stack_top
    rt.pc = rt.pc + 3
    return Running
  }

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    rt.sp = stack_top
    return Trap
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
    rt.sp = stack_top
    return Trap
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
        rt.sp = stack_top
        return Trap
      }
    }
  }
  rt.sp = stack_top
  rt.pc = rt.pc + 3
  Running
}

///|
fn op_table_copy(rt : Instance) -> ReturnCode {
  let dst_table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let src_table_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let stack_top = rt.sp - 3

  // Bounds check table indices
  if dst_table_idx < 0 ||
    dst_table_idx >= rt.ctx.tables.length() ||
    src_table_idx < 0 ||
    src_table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    rt.sp = stack_top
    return Trap
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
    rt.sp = stack_top
    return Trap
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
  rt.sp = stack_top
  rt.pc = rt.pc + 3
  Running
}

///|
fn op_table_fill(rt : Instance) -> ReturnCode {
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
    rt.sp = stack_top
    return Trap
  }
  for i = 0; i < n; i = i + 1 {
    table[dest + i] = ref_value
  }
  rt.sp = stack_top
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_elem_drop(rt : Instance) -> ReturnCode {
  let elem_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Mark the element segment as dropped
  if elem_idx >= 0 && elem_idx < rt.ctx.dropped_elems.length() {
    rt.ctx.dropped_elems[elem_idx] = true
  }
  rt.pc = rt.pc + 2
  Running
}

// =============================================================================
// Table operations
// =============================================================================

///|
fn op_table_size(rt : Instance) -> ReturnCode {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return Trap
  }
  let size = rt.ctx.tables[table_idx].data.length()
  rt.stack.unsafe_set(rt.sp, size.reinterpret_as_uint().to_uint64())
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_table_get(rt : Instance) -> ReturnCode {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return Trap
  }
  let stack_top = rt.sp - 1
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    rt.sp = stack_top
    return Trap
  }
  // Return the function reference (or null) directly as UInt64
  let ref_val = table[elem_idx]
  rt.stack.unsafe_set(stack_top, ref_val)
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_table_set(rt : Instance) -> ReturnCode {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.ctx.error_detail = "table index out of bounds"
    return Trap
  }
  // Pop ref value as 64-bit (preserves tags)
  let stack_top = rt.sp - 2
  let ref_value = rt.stack.unsafe_get(rt.sp - 1)
  let elem_idx = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()
  let table = rt.ctx.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.ctx.error_detail = "table element index out of bounds"
    rt.sp = stack_top
    return Trap
  }
  table[elem_idx] = ref_value
  rt.sp = stack_top
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_table_grow(rt : Instance) -> ReturnCode {
  let table_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  if table_idx < 0 || table_idx >= rt.ctx.tables.length() {
    rt.stack.unsafe_set(rt.sp, 0xFFFFFFFFUL) // -1 indicates failure
    rt.sp = rt.sp + 1
    rt.pc = rt.pc + 2
    return Running
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
    rt.sp = stack_top + 1
    rt.pc = rt.pc + 2
    return Running
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.to_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL)
        rt.sp = stack_top + 1
        rt.pc = rt.pc + 2
        return Running
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.unsafe_set(stack_top, old_size.reinterpret_as_uint().to_uint64())
  rt.sp = stack_top + 1
  rt.pc = rt.pc + 2
  Running
}

// =============================================================================
// Reference operations
// =============================================================================

///|
fn op_ref_null(rt : Instance) -> ReturnCode {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.ops.unsafe_get(rt.pc + 1).to_int() // Skip the heap type encoding
  // Push null ref as -1 (Int64)
  rt.stack.unsafe_set(rt.sp, (-1).to_int64().reinterpret_as_uint64())
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_ref_func(rt : Instance) -> ReturnCode {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Push func ref tagged with bit 62 (0x4000000000000000)
  let tagged = func_idx.to_uint64() | 0x4000000000000000UL
  rt.stack.unsafe_set(rt.sp, tagged)
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_ref_is_null(rt : Instance) -> ReturnCode {
  // ref.is_null tests whether a reference is null
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.sp - 1
  let ref_val = rt.stack.unsafe_get(stack_top).to_int()
  let is_null : UInt64 = if ref_val == -1 { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, is_null)
  rt.pc = rt.pc + 1
  Running
}

///|
fn op_ref_eq(rt : Instance) -> ReturnCode {
  // ref.eq compares two references for identity equality
  // Refs are stored as Int64, -1 = null
  let stack_top = rt.sp - 2
  let rhs = rt.stack.unsafe_get(rt.sp - 1).to_int()
  let lhs = rt.stack.unsafe_get(stack_top).to_int()
  let eq : UInt64 = if lhs == rhs { 1UL } else { 0UL }
  rt.stack.unsafe_set(stack_top, eq)
  rt.sp = stack_top + 1
  rt.pc = rt.pc + 1
  Running
}

///|
fn op_ref_as_non_null(rt : Instance) -> ReturnCode {
  // ref.as_non_null traps on null references
  // Refs are stored as Int64, -1 = null
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let ref_val = value.to_int()
  if ref_val == -1 {
    rt.ctx.error_detail = "ref.as_non_null: null reference"
    return Trap
  }
  // Push back the non-null reference (it's already there, just advance pc)
  rt.pc = rt.pc + 1
  Running
}

///|
fn op_global_get(rt : Instance) -> ReturnCode {
  let idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  // Convert Value to UInt64 for stack
  rt.stack.unsafe_set(rt.sp, value_to_stack(rt.ctx.globals[idx]))
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
fn op_global_set(rt : Instance) -> ReturnCode {
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
  rt.sp = stack_top
  rt.pc = rt.pc + 2
  Running
}
