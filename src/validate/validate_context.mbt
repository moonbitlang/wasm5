///|
/// Validation context that tracks both the type stack and unreachable state
priv struct ValidationCtx {
  stack : Array[@core.ValType]
  mut is_unreachable : Bool
  // Stack of control frames - each frame tracks the expected result types
  // For br validation, we need to know what types the target label expects
  control_stack : Array[(Array[@core.ValType], Array[@core.ValType])] // (params, results) for each control frame
  // Track which locals are initialized (for non-defaultable types)
  // Index corresponds to local index (params first, then locals)
  initialized_locals : Array[Bool]
}

///|
fn ValidationCtx::new() -> ValidationCtx {
  {
    stack: [],
    is_unreachable: false,
    control_stack: [],
    initialized_locals: [],
  }
}

///|
/// Create a validation context with initialized locals tracking
/// Params are always initialized; locals are initialized only if defaultable
fn ValidationCtx::new_with_locals(
  func_type : @core.FuncType,
  code : @core.Code,
) -> ValidationCtx {
  let total_locals = func_type.params.length() + code.locals.length()
  let initialized = Array::make(total_locals, false)
  // Parameters are always initialized
  for i in 0..<func_type.params.length() {
    initialized[i] = true
  }
  // Locals with defaultable types are initialized to their default value
  for i in 0..<code.locals.length() {
    let local_type = code.locals[i]
    if local_type.is_defaultable() {
      initialized[func_type.params.length() + i] = true
    }
  }
  {
    stack: [],
    is_unreachable: false,
    control_stack: [],
    initialized_locals: initialized,
  }
}

///|
fn ValidationCtx::push_control(
  self : ValidationCtx,
  params : Array[@core.ValType],
  results : Array[@core.ValType],
) -> Unit {
  self.control_stack.push((params, results))
}

///|
fn ValidationCtx::pop_control(
  self : ValidationCtx,
) -> (Array[@core.ValType], Array[@core.ValType]) {
  self.control_stack.unsafe_pop()
}

///|
fn ValidationCtx::get_label_types(
  self : ValidationCtx,
  label : UInt,
) -> Array[@core.ValType] raise @core.ValidationError {
  // Labels are relative depth: 0 is innermost, 1 is next outer, etc.
  let idx = self.control_stack.length() - 1 - label.reinterpret_as_int()
  if idx >= 0 && idx < self.control_stack.length() {
    let (_, results) = self.control_stack[idx]
    results
  } else {
    raise @core.ValidationError::UnknownLabel(label.reinterpret_as_int())
  }
}

// =============================================================================
// Polymorphic Stack Operations for @core.Instr::Unreachable @core.Code
// =============================================================================
//
// In WebAssembly, after an unconditional control flow instruction (br, return,
// unreachable), subsequent code is "unreachable" and uses polymorphic stack
// validation rules. This means:
//
//   1. Operations can "pop" values that don't exist on the stack
//   2. The stack is treated as having any types needed
//   3. Result types are still pushed for type checking of code after
//      control flow rejoins (e.g., after a block end)
//
// Example: (block (drop (i32.ctz (br 0))))
//   - br 0 branches away, making i32.ctz unreachable
//   - i32.ctz normally requires an i32 on stack, but in unreachable mode
//     it's valid even with an empty stack
//
// These helpers implement polymorphic pop operations that succeed in
// unreachable mode even when the stack is empty.
// =============================================================================

///|
/// Mark code as unreachable and clear the operand stack.
/// This implements the WebAssembly spec requirement that when code becomes
/// unreachable (e.g., after br, return, or tail calls), the operand stack is purged.
fn ValidationCtx::mark_unreachable(self : ValidationCtx) -> Unit {
  self.is_unreachable = true
  self.stack.clear()
}

///|
/// Pop a value from the stack, allowing empty stack in unreachable mode.
/// Returns the type if available, or the expected type if unreachable.
/// Only values below unreachable_stack_height are polymorphic.
fn ValidationCtx::poly_pop(
  self : ValidationCtx,
  expected : @core.ValType,
) -> @core.ValType raise @core.ValidationError {
  if self.stack.length() > 0 {
    self.stack.unsafe_pop()
  } else if self.is_unreachable {
    // In unreachable code with empty stack, this is a polymorphic pop
    // (popping from below the unreachable boundary)
    expected
  } else {
    raise @core.ValidationError::TypeMismatch(
      "expected value on stack, got empty stack",
    )
  }
}

///|
/// Check and pop a value of a specific type, allowing polymorphic behavior.
/// Concrete values (pushed after unreachable) must still type-check.
/// Uses subtyping: actual type must be a subtype of expected type.
fn ValidationCtx::poly_pop_expect(
  self : ValidationCtx,
  module_ : @core.Module,
  expected : @core.ValType,
  op_name : String,
) -> Unit raise @core.ValidationError {
  // In unreachable mode, concrete values are those currently on the stack
  // (they were pushed after unreachable). Polymorphic values are those
  // we pop from an empty stack (they would have been there before unreachable).
  let is_concrete_value = self.stack.length() > 0
  let actual = self.poly_pop(expected)

  // Type-check concrete values, or all values if not in unreachable mode
  // Use subtyping: actual must be a subtype of expected
  if (not(self.is_unreachable) || is_concrete_value) &&
    not(is_subtype(module_, actual, expected)) {
    raise @core.ValidationError::TypeMismatch(
      "\{op_name} requires \{expected}, got \{actual}",
    )
  }
}
