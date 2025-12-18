///|
pub fn op_local_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.locals[idx])
  rt.pc += 1
  OK
}

///|
pub fn op_local_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.locals[idx] = value
  rt.pc += 1
  OK
}

///|
pub fn op_local_tee(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack[rt.stack.length() - 1]
  rt.locals[idx] = value
  rt.pc += 1
  OK
}

// ============================================================================
// Stack operations
// ============================================================================

///|
pub fn op_drop(rt : Runtime) -> RetCode {
  let _ = rt.stack.unsafe_pop()
  rt.pc += 1
  OK
}

///|
pub fn op_select(rt : Runtime) -> RetCode {
  let cond = rt.pop_i32()
  let val2 = rt.stack.unsafe_pop()
  let val1 = rt.stack.unsafe_pop()
  rt.stack.push(if cond != 0U { val1 } else { val2 })
  rt.pc += 1
  OK
}

// ============================================================================
// Control flow operations
// ============================================================================

///|
pub fn op_if(rt : Runtime) -> RetCode {
  let else_pc = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    rt.pc += 1
  } else {
    rt.pc = else_pc
  }
  OK
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
pub fn op_br(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()

  // Save the top `arity` values (the branch result values)
  let results : Array[Value] = []
  for _ in 0..<arity {
    results.push(rt.stack.unsafe_pop())
  }

  // Drop the unwanted values
  for _ in 0..<drop_count {
    let _ = rt.stack.unsafe_pop()

  }

  // Push results back (in reverse order since we popped them)
  for i = results.length() - 1; i >= 0; i = i - 1 {
    rt.stack.push(results[i])
  }
  rt.pc = target_pc
  OK
}

///|
pub fn op_br_if(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    // Save the top `arity` values (the branch result values)
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back (in reverse order since we popped them)
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    rt.pc += 1
  }
  OK
}

///|
pub fn op_br_table(rt : Runtime) -> RetCode {
  let num_labels = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let index = rt.pop_i32().reinterpret_as_int()

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

  // Save the top `arity` values (the branch result values)
  let results : Array[Value] = []
  for _ in 0..<arity {
    results.push(rt.stack.unsafe_pop())
  }

  // Drop the unwanted values
  for _ in 0..<drop_count {
    let _ = rt.stack.unsafe_pop()

  }

  // Push results back (in reverse order since we popped them)
  for i = results.length() - 1; i >= 0; i = i - 1 {
    rt.stack.push(results[i])
  }
  rt.pc = target_pc
  OK
}

///|
pub fn op_br_on_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's null
  let is_null = match ref_val {
    Ref(None) => true
    _ => false
  }
  if is_null {
    // Save the top `arity` values
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    // Not null - push back the value and continue
    rt.stack.push(ref_val)
    rt.pc += 1
  }
  OK
}

///|
pub fn op_br_on_non_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's not null
  let is_non_null = match ref_val {
    Ref(None) => false
    _ => true
  }
  if is_non_null {
    // Save the top `arity` values (includes the ref we just popped if arity > 0)
    rt.stack.push(ref_val) // Push it back first for proper handling
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    // Null - don't push anything, continue
    rt.pc += 1
  }
  OK
}

///|
pub fn op_call(rt : Runtime) -> RetCode {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "call: invalid imported function index"
      return InvalidType
    }
    let func_type = rt.module_.types[type_idx]
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(func_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_return(rt : Runtime) -> RetCode {
  if rt.call_stack.length() == 0 {
    rt.running = false
    return OK
  }
  let return_value : Value? = if rt.stack.length() > 0 {
    Some(rt.stack.unsafe_pop())
  } else {
    None
  }
  let frame = rt.call_stack.unsafe_pop()
  rt.locals = frame.locals
  match return_value {
    Some(v) => rt.stack.push(v)
    None => ()
  }
  rt.pc = frame.return_pc + 1
  OK
}

///|
pub fn op_call_indirect(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  let elem_idx = rt.pop_i32().reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "call_indirect: invalid table index"
    return InvalidType
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    return InvalidType
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = rt.module_.types[type_idx]

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
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if check_result != OK {
      return check_result
    }
    let args = rt.pop_arguments(actual_type.params.length())
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_indirect: invalid function index"
    return InvalidType
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if check_result != OK {
    return check_result
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(actual_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_end(rt : Runtime) -> RetCode {
  if rt.call_stack.length() > 0 {
    op_return(rt)
  } else {
    rt.running = false
    OK
  }
}

///|
pub fn op_return_call(rt : Runtime) -> RetCode {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "return_call: invalid imported function index"
      return InvalidType
    }
    let func_type = rt.module_.types[type_idx]
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(func_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_return_call_indirect(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  let elem_idx = rt.pop_i32().reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "return_call_indirect: invalid table index"
    return InvalidType
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    return InvalidType
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = rt.module_.types[type_idx]

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
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      expected_type, actual_type, "indirect call type mismatch", rt,
    )
    if check_result != OK {
      return check_result
    }
    let args = rt.pop_arguments(actual_type.params.length())
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_indirect: invalid function index"
    return InvalidType
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    expected_type, actual_type, "indirect call type mismatch", rt,
  )
  if check_result != OK {
    return check_result
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(actual_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(Some(func_idx)) else {
    rt.error_detail = "call_ref: null or invalid function reference"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = rt.module_.types[type_idx]

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
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      func_type, actual_type, "call_ref: type mismatch", rt,
    )
    if check_result != OK {
      return check_result
    }
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_ref: invalid function index"
    return InvalidType
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    func_type, actual_type, "call_ref: type mismatch", rt,
  )
  if check_result != OK {
    return check_result
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(func_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_return_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(Some(func_idx)) else {
    rt.error_detail = "return_call_ref: null or invalid function reference"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = rt.module_.types[type_idx]

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
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      func_type, actual_type, "return_call_ref: type mismatch", rt,
    )
    if check_result != OK {
      return check_result
    }
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_ref: invalid function index"
    return InvalidType
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    func_type, actual_type, "return_call_ref: type mismatch", rt,
  )
  if check_result != OK {
    return check_result
  }
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }
  let args = rt.pop_arguments(func_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }
  rt.pc = callee_pc
  OK
}

///|
pub fn op_nop(rt : Runtime) -> RetCode {
  rt.pc += 1
  OK
}

///|
pub fn op_unreachable(_rt : Runtime) -> RetCode {
  return Unreachable
}
// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
pub fn op_table_init(rt : Runtime) -> RetCode {
  let _table_idx = rt.read_imm_idx()
  let _elem_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.init
  rt.pc += 1
  OK
}

///|
pub fn op_table_copy(rt : Runtime) -> RetCode {
  let _dst_table_idx = rt.read_imm_idx()
  let _src_table_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.copy
  rt.pc += 1
  OK
}

///|
pub fn op_elem_drop(rt : Runtime) -> RetCode {
  let _elem_idx = rt.read_imm_idx()
  // TODO: Implement elem.drop
  rt.pc += 1
  OK
}

// =============================================================================
// Table operations
// =============================================================================

///|
pub fn op_table_size(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let size = rt.tables[table_idx].data.length()
  rt.stack.push(Value::I32(size.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
pub fn op_table_get(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    return InvalidType
  }
  // Return the function reference (or null)
  rt.stack.push(Value::Ref(table[elem_idx]))
  rt.pc += 1
  OK
}

///|
pub fn op_table_set(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let ref_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.error_detail = "expected funcref for table.set"
      return InvalidType
    }
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    return InvalidType
  }
  table[elem_idx] = ref_value
  rt.pc += 1
  OK
}

///|
pub fn op_table_grow(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let delta = rt.pop_i32().reinterpret_as_int()
  let init_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.stack.push(Value::I32(0xFFFFFFFFU))
      rt.pc += 1
      return OK
    }
  }
  let runtime_table = rt.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.push(Value::I32(0xFFFFFFFFU))
        rt.pc += 1
        return OK
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.push(Value::I32(old_size.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

// =============================================================================
// Reference operations
// =============================================================================

///|
pub fn op_ref_null(rt : Runtime) -> RetCode {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.read_imm_idx() // Skip the heap type encoding
  rt.stack.push(Value::Ref(None))
  rt.pc += 1
  OK
}

///|
pub fn op_ref_func(rt : Runtime) -> RetCode {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.read_imm_idx()
  rt.stack.push(Value::Ref(Some(func_idx)))
  rt.pc += 1
  OK
}

///|
pub fn op_ref_is_null(rt : Runtime) -> RetCode {
  // ref.is_null tests whether a reference is null
  let ref_val = rt.stack.unsafe_pop()
  let is_null = match ref_val {
    Value::Ref(None) => 1U
    Value::Ref(Some(_)) => 0U
    _ => 0U // Non-ref values are considered not null
  }
  rt.stack.push(Value::I32(is_null))
  rt.pc += 1
  OK
}

///|
pub fn op_global_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.globals[idx])
  rt.pc += 1
  OK
}

///|
pub fn op_global_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.globals[idx] = value
  rt.pc += 1
  OK
}
