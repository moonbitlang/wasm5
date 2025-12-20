// =============================================================================
// Unified Stack Architecture
// =============================================================================
//
// This implementation uses a SINGLE unified stack for both locals and
// temporary values (operand stack), inspired by wasm3's design. This
// eliminates the overhead of separate stacks and reduces allocations
// during function calls.
//
// STACK LAYOUT
// ============
//
// The stack is organized into frames, where each frame contains:
//   1. Locals (function parameters + local variables)
//   2. Temps (operand stack for intermediate values)
//
// Frame Structure:
//   stack[sp .. sp+num_locals)     ← Frame's locals (params + local vars)
//   stack[sp+num_locals .. ]       ← Frame's temps (operand stack)
//
// Example with nested calls:
//   stack[0..3)         ← Frame 0 locals (sp=0, num_locals=3)
//   stack[3..5)         ← Frame 0 temps
//   stack[5..7)         ← Frame 1 locals (sp=5, num_locals=2)
//   stack[7..9)         ← Frame 1 temps
//   stack[9..10)        ← Frame 2 locals (sp=9, num_locals=1)
//   stack[10..]         ← Frame 2 temps
//
// FUNCTION CALLS
// ==============
//
// When calling a function:
//   1. Arguments are already on stack as caller's temps
//   2. Set new_sp = stack.length() - num_params (arguments stay in place!)
//   3. Arguments are now at stack[new_sp..new_sp+num_params)
//   4. Initialize remaining locals with default values
//   5. Update rt.sp, rt.num_locals, rt.pc
//
// Key optimization: Arguments stay on the stack and become the new frame's
// first locals directly - no popping/re-pushing, no array allocation!
//
// Important: We do NOT trim caller's temps! Some temps are operands
// needed after the call returns (e.g., first operand to i64.mul in
// nested expressions like: (i64.mul (local.get 0) (call $f ...))).
//
// FUNCTION RETURNS
// ================
//
// When returning from a function:
//   1. Return values are temps at: stack[sp+num_locals .. stack.len)
//   2. Extract return values into temporary array
//   3. Trim stack to rt.sp (removes entire callee frame)
//   4. Push return values back (they become caller's temps)
//   5. Restore caller's sp, num_locals, pc from CallFrame
//
// Critical: Trim to rt.sp (callee's sp), NOT to prev_sp + prev_num_locals!
// This preserves all caller temps that existed before the call.
//
// TAIL CALLS
// ==========
//
// Tail calls reuse the current stack frame:
//   1. Pop arguments into temporary array
//   2. Trim stack back to rt.sp (remove all locals and temps)
//   3. Push arguments as new locals (reusing same sp)
//   4. Initialize remaining locals
//   5. Update num_locals and pc (sp stays the same)
//   6. Do NOT push CallFrame (reuse existing frame)
//
// This prevents stack growth for tail-recursive functions.
//
// LOCAL ACCESS
// ============
//
// Locals are accessed via: stack[sp + local_idx]
// Where:
//   - sp points to the start of current frame's locals
//   - local_idx is the local variable index (0-based)
//   - First num_params locals are function parameters
//   - Remaining locals are local variables
//
// =============================================================================

///|
#tailcall
fn op_local_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack[rt.sp + idx]
  rt.stack.push(value)
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_local_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.stack[rt.sp + idx] = value
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_local_tee(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack[rt.stack.length() - 1]
  rt.stack[rt.sp + idx] = value
  rt.pc += 1
  return next_op(rt)
}

// ============================================================================
// Stack operations
// ============================================================================

///|
#tailcall
fn op_drop(rt : Runtime) -> RetCode {
  let _ = rt.stack.unsafe_pop()
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_select(rt : Runtime) -> RetCode {
  let cond = rt.pop_i32()
  let val2 = rt.stack.unsafe_pop()
  let val1 = rt.stack.unsafe_pop()
  rt.stack.push(if cond != 0U { val1 } else { val2 })
  rt.pc += 1
  return next_op(rt)
}

// ============================================================================
// Control flow operations
// ============================================================================

///|
#tailcall
fn op_if(rt : Runtime) -> RetCode {
  let else_pc = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    rt.pc += 1
    return next_op(rt)
  } else {
    rt.pc = else_pc
    return next_op(rt)
  }
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
#tailcall
fn op_br(rt : Runtime) -> RetCode {
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
  return next_op(rt)
}

///|
#tailcall
fn op_br_if(rt : Runtime) -> RetCode {
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
    return next_op(rt)
  } else {
    rt.pc += 1
    return next_op(rt)
  }
}

///|
#tailcall
fn op_br_table(rt : Runtime) -> RetCode {
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
  return next_op(rt)
}

///|
#tailcall
fn op_br_on_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's null
  let is_null = match ref_val {
    Ref(-1) => true
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
    return next_op(rt)
  } else {
    // Not null - push back the value and continue
    rt.stack.push(ref_val)
    rt.pc += 1
    return next_op(rt)
  }
}

///|
#tailcall
fn op_br_on_non_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's not null
  let is_non_null = match ref_val {
    Ref(-1) => false
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
    return next_op(rt)
  } else {
    // Null - don't push anything, continue
    rt.pc += 1
    return next_op(rt)
  }
}

///|
#tailcall
fn op_call(rt : Runtime) -> RetCode {
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
    return next_op(rt)
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
  let num_params = func_type.params.length()
  let num_locals = code.locals.length()

  // Save frame with current sp
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    prev_sp: rt.sp,
    prev_num_locals: rt.num_locals,
  })

  // Arguments are already on stack as temps: stack[..., arg0, arg1, ..., argN]
  // New frame starts where the arguments begin (they become the new frame's first locals)
  let new_sp = rt.stack.length() - num_params

  // Arguments are now at stack[new_sp..new_sp+num_params) - no need to move them!

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // Update sp and num_locals for new frame
  rt.sp = new_sp
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_return(rt : Runtime) -> RetCode {
  if rt.call_stack.length() == 0 {
    rt.running = false
    return OK
  }

  // Return values are at top of stack (above current frame's locals)
  // We need to keep them but discard the entire frame

  // Collect return values (they're above sp + num_locals)
  let frame = rt.call_stack.unsafe_pop()

  // Return values start after locals: stack[sp + num_locals .. length-1]
  let num_return_values = rt.stack.length() - (rt.sp + rt.num_locals)

  // Save return values temporarily
  let return_values : Array[Value] = []
  for i = 0; i < num_return_values; i = i + 1 {
    return_values.push(rt.stack.unsafe_pop())
  }
  // Reverse since we popped backwards
  for i = 0; i < return_values.length() / 2; i = i + 1 {
    let j = return_values.length() - 1 - i
    let temp = return_values[i]
    return_values[i] = return_values[j]
    return_values[j] = temp
  }

  // Restore caller's sp and num_locals first
  let caller_sp = frame.prev_sp
  let caller_num_locals = frame.prev_num_locals

  // Trim stack to remove ONLY the callee's frame
  // The callee's frame starts at rt.sp (current sp before restoration)
  // Everything before rt.sp should be preserved (caller's locals AND temps)
  while rt.stack.length() > rt.sp {
    ignore(rt.stack.unsafe_pop())
  }

  // Push return values back (now they're temps in the caller's frame)
  for val in return_values {
    rt.stack.push(val)
  }

  // Update runtime state
  rt.sp = caller_sp
  rt.num_locals = caller_num_locals
  rt.pc = frame.return_pc + 1
  return next_op(rt)
}

///|
#tailcall
fn op_call_indirect(rt : Runtime) -> RetCode {
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
    return next_op(rt)
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
  let num_params = actual_type.params.length()
  let num_locals = code.locals.length()

  // Save frame with current sp
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    prev_sp: rt.sp,
    prev_num_locals: rt.num_locals,
  })

  // Arguments are already on stack as temps: stack[..., arg0, arg1, ..., argN]
  // New frame starts where the arguments begin (they become the new frame's first locals)
  let new_sp = rt.stack.length() - num_params

  // Arguments are now at stack[new_sp..new_sp+num_params) - no need to move them!

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // Update sp and num_locals for new frame
  rt.sp = new_sp
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_end(rt : Runtime) -> RetCode {
  if rt.call_stack.length() > 0 {
    return op_return(rt)
  } else {
    OK
  }
}

///|
#tailcall
fn op_return_call(rt : Runtime) -> RetCode {
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
  let num_params = func_type.params.length()
  let num_locals = code.locals.length()

  // Pop arguments from stack
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = rt.stack.unsafe_pop()
  }

  // For tail call: trim stack back to current frame's base, reuse same sp
  while rt.stack.length() > rt.sp {
    let _ = rt.stack.unsafe_pop()

  }

  // Push new locals at current sp (replacing old frame)
  for arg in args {
    rt.stack.push(arg)
  }

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // sp stays the same (tail call reuses current frame's base)
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_return_call_indirect(rt : Runtime) -> RetCode {
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
  let num_params = actual_type.params.length()
  let num_locals = code.locals.length()

  // Pop arguments from stack
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = rt.stack.unsafe_pop()
  }

  // For tail call: trim stack back to current frame's base, reuse same sp
  while rt.stack.length() > rt.sp {
    let _ = rt.stack.unsafe_pop()

  }

  // Push new locals at current sp (replacing old frame)
  for arg in args {
    rt.stack.push(arg)
  }

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // sp stays the same (tail call reuses current frame's base)
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(func_idx) && func_idx != -1 else {
    rt.error_detail = "call_ref: null function reference"
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
    return next_op(rt)
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
  let num_params = func_type.params.length()
  let num_locals = code.locals.length()

  // Save frame with current sp
  rt.call_stack.push(CallFrame::{
    return_pc: rt.pc,
    prev_sp: rt.sp,
    prev_num_locals: rt.num_locals,
  })

  // Arguments are already on stack as temps: stack[..., arg0, arg1, ..., argN]
  // New frame starts where the arguments begin (they become the new frame's first locals)
  let new_sp = rt.stack.length() - num_params

  // Arguments are now at stack[new_sp..new_sp+num_params) - no need to move them!

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // Update sp and num_locals for new frame
  rt.sp = new_sp
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_return_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(func_idx) && func_idx != -1 else {
    rt.error_detail = "return_call_ref: null function reference"
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
  let num_params = func_type.params.length()
  let num_locals = code.locals.length()

  // Pop arguments from stack
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = rt.stack.unsafe_pop()
  }

  // For tail call: trim stack back to current frame's base, reuse same sp
  while rt.stack.length() > rt.sp {
    let _ = rt.stack.unsafe_pop()

  }

  // Push new locals at current sp (replacing old frame)
  for arg in args {
    rt.stack.push(arg)
  }

  // Initialize remaining locals with default values
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.stack.push(Value::I32(0U))
      ValType::I64 => rt.stack.push(Value::I64(0UL))
      ValType::F32 => rt.stack.push(Value::F32(0.0))
      ValType::F64 => rt.stack.push(Value::F64(0.0))
      ValType::FuncRef => rt.stack.push(Value::Ref(-1))
      ValType::ExternRef => rt.stack.push(Value::Ref(-1))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => rt.stack.push(Value::Ref(-1))
      _ => {
        rt.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }

  // sp stays the same (tail call reuses current frame's base)
  rt.num_locals = num_params + num_locals
  rt.pc = callee_pc
  return next_op(rt)
}

///|
#tailcall
fn op_nop(rt : Runtime) -> RetCode {
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_unreachable(_rt : Runtime) -> RetCode {
  return Unreachable
}
// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
#tailcall
fn op_table_init(rt : Runtime) -> RetCode {
  let _table_idx = rt.read_imm_idx()
  let _elem_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.init
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_table_copy(rt : Runtime) -> RetCode {
  let _dst_table_idx = rt.read_imm_idx()
  let _src_table_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.copy
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_elem_drop(rt : Runtime) -> RetCode {
  let _elem_idx = rt.read_imm_idx()
  // TODO: Implement elem.drop
  rt.pc += 1
  return next_op(rt)
}

// =============================================================================
// Table operations
// =============================================================================

///|
#tailcall
fn op_table_size(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let size = rt.tables[table_idx].data.length()
  rt.stack.push(Value::I32(size.reinterpret_as_uint()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_table_get(rt : Runtime) -> RetCode {
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
  // Convert Int? from table to Int for Value::Ref (-1 = null)
  let ref_as_int = match table[elem_idx] {
    Some(idx) => idx
    None => -1
  }
  rt.stack.push(Value::Ref(ref_as_int))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_table_set(rt : Runtime) -> RetCode {
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
  // Convert Int from Value::Ref to Int? for table (-1 = None)
  let table_value : Int? = if ref_value == -1 { None } else { Some(ref_value) }
  table[elem_idx] = table_value
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_table_grow(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return next_op(rt)
  }
  let delta = rt.pop_i32().reinterpret_as_int()
  let init_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.stack.push(Value::I32(0xFFFFFFFFU))
      rt.pc += 1
      return next_op(rt)
    }
  }
  let runtime_table = rt.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return next_op(rt)
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.push(Value::I32(0xFFFFFFFFU))
        rt.pc += 1
        return next_op(rt)
      }
    None => () // No max limit
  }

  // Grow the table
  // Convert Int from Value::Ref to Int? for table (-1 = None)
  let table_value : Int? = if init_value == -1 {
    None
  } else {
    Some(init_value)
  }
  for i = 0; i < delta; i = i + 1 {
    table.push(table_value)
  }
  rt.stack.push(Value::I32(old_size.reinterpret_as_uint()))
  rt.pc += 1
  return next_op(rt)
}

// =============================================================================
// Reference operations
// =============================================================================

///|
#tailcall
fn op_ref_null(rt : Runtime) -> RetCode {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.read_imm_idx() // Skip the heap type encoding
  rt.stack.push(Value::Ref(-1))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_ref_func(rt : Runtime) -> RetCode {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.read_imm_idx()
  rt.stack.push(Value::Ref(func_idx))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_ref_is_null(rt : Runtime) -> RetCode {
  // ref.is_null tests whether a reference is null
  let ref_val = rt.stack.unsafe_pop()
  let is_null = match ref_val {
    Value::Ref(-1) => 1U
    Value::Ref(_) => 0U
    _ => 0U // Non-ref values are considered not null
  }
  rt.stack.push(Value::I32(is_null))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_global_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.globals[idx])
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_global_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.globals[idx] = value
  rt.pc += 1
  return next_op(rt)
}
