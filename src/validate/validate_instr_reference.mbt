///|
fn validate_instruction_reference(
  module_ : @core.Module,
  ctx : ValidationCtx,
  import_counts : ImportCounts,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    RefNull(ref_type) => {
      // ref.null pushes a null reference of the given type
      let val_type = reftype_to_valtype(ref_type)
      stack.push(val_type)
    }
    RefFunc(func_idx) => {
      // ref.func pushes a typed function reference (non-nullable)
      // Get the function's type index to create the proper typed reference
      let idx = func_idx.reinterpret_as_int()
      // Validate function index
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(idx)
      }
      let type_idx = get_func_type_index(module_, idx, import_counts)
      // Push typed function reference (non-nullable)
      stack.push(Ref(TypeIndex(type_idx), false))
    }
    RefIsNull => {
      // ref.is_null pops a reference type and pushes i32
      // In polymorphic context, allow any type on stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.is_null expects reference on stack",
        )
      } else {
        let _ = stack.unsafe_pop()
        // Pop the reference
      }
      stack.push(I32) // Push result
    }
    _ => return false
  }
  true
}
