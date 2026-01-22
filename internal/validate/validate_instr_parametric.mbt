///|
fn validate_instruction_parametric(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    Drop =>
      // In unreachable code, drop is valid even with empty stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - pretend we dropped something
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for drop")
      } else {
        let _ = stack.unsafe_pop()

      }
    Select => {
      // Untyped select (0x1B): only numeric types allowed
      // Pop condition (i32), then two values of same type, push one back
      ctx.poly_pop_expect(module_, I32, "select condition")
      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate
      if num_concrete >= 2 {
        // Both values are concrete - they must be compatible via subtyping
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // For untyped select, both values must be numeric types
        let is_val1_numeric = match val1 {
          I32 | I64 | F32 | F64 => true
          _ => false
        }
        let is_val2_numeric = match val2 {
          I32 | I64 | F32 | F64 => true
          _ => false
        }
        if not(is_val1_numeric) || not(is_val2_numeric) {
          raise ValidationError::TypeMismatch(
            "untyped select requires numeric types, got \{val1} and \{val2}",
          )
        }

        // Check if types are compatible: one must be subtype of the other
        let result_type = if is_subtype(module_, val1, val2) {
          val2 // val1 <: val2, so result is val2 (more general)
        } else if is_subtype(module_, val2, val1) {
          val1 // val2 <: val1, so result is val1 (more general)
        } else {
          raise ValidationError::TypeMismatch(
            "select values must have compatible types: got \{val1} and \{val2}",
          )
        }
        stack.push(result_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          // Verify it's numeric
          let is_numeric = match val {
            I32 | I64 | F32 | F64 => true
            _ => false
          }
          if not(is_numeric) {
            raise ValidationError::TypeMismatch(
              "untyped select requires numeric types, got \{val}",
            )
          }
          stack.push(val)
        } else {
          raise ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, assume a default type
        stack.push(I32)
      } else {
        raise ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    SelectTyped(result_types) => {
      // Typed select (0x1C): any type allowed, must match annotation
      // Pop condition (i32), then two values of annotated type, push one back
      ctx.poly_pop_expect(module_, I32, "select condition")

      // For MVP, result_types should have exactly 1 type
      if result_types.length() != 1 {
        raise ValidationError::InvalidResultArity(
          "select must have exactly 1 result type, got \{result_types.length()}",
        )
      }
      let expected_type = result_types[0]
      // Validate that type indices in the result type exist
      validate_valtype(module_, expected_type)

      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate they match expected type
      if num_concrete >= 2 {
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // Both values must be subtypes of the expected type
        if not(is_subtype(module_, val1, expected_type)) {
          raise ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val1}",
          )
        }
        if not(is_subtype(module_, val2, expected_type)) {
          raise ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val2}",
          )
        }
        stack.push(expected_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          if not(is_subtype(module_, val, expected_type)) {
            raise ValidationError::TypeMismatch(
              "select value type mismatch: expected \{expected_type}, got \{val}",
            )
          }
          stack.push(expected_type)
        } else {
          raise ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, push the expected type
        stack.push(expected_type)
      } else {
        raise ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    _ => return false
  }
  true
}
