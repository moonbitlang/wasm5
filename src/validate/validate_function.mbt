///|
/// Validate a single function
fn validate_function(
  module_ : @core.Module,
  func_type : @core.FuncType,
  code : @core.Code,
  import_counts : ImportCounts,
) -> Unit raise @errors.ValidationError {
  // Validate type indices in function parameters
  for param in func_type.params {
    validate_valtype(module_, param)
  }
  // Validate type indices in function results
  for result in func_type.results {
    validate_valtype(module_, result)
  }
  // Validate type indices in local variables
  for local_type in code.locals {
    validate_valtype(module_, local_type)
  }

  // Create validation context with local initialization tracking
  let ctx = ValidationCtx::new_with_locals(func_type, code)
  // Push function-level control frame with empty params and function results
  ctx.push_control([], func_type.results)

  // Validate each instruction in the function body
  for instr in code.body.instrs {
    validate_instruction(module_, func_type, code, ctx, instr, import_counts)
  }

  // Check final stack matches return type
  let stack = ctx.stack
  if ctx.is_unreachable && stack.length() == 0 {
    // Unreachable code with empty stack - all values are polymorphic, valid
  } else if stack.length() != func_type.results.length() {
    // Stack size doesn't match expected return values
    if stack.length() < func_type.results.length() {
      raise @errors.ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    } else if func_type.results.length() == 0 && stack.length() > 0 {
      raise @errors.ValidationError::StackSizeMismatch(
        "function: void function should not have values on stack, got \{stack.length()}",
      )
    } else {
      raise @errors.ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    }
  } else {
    // Check types from top of stack (with subtyping)
    for i in 0..<func_type.results.length() {
      // Stack type must be a subtype of expected return type
      if not(is_subtype(module_, stack[i], func_type.results[i])) {
        raise @errors.ValidationError::TypeMismatch(
          "function return type mismatch: expected \{func_type.results[i]}, got \{stack[i]}",
        )
      }
    }
  }
}
