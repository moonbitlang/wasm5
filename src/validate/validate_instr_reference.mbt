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
    RefEq => {
      // ref.eq pops two references and pushes i32
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 2 {
        raise ValidationError::TypeMismatch(
          "ref.eq expects two references on stack",
        )
      } else {
        let rhs = stack.unsafe_pop()
        let lhs = stack.unsafe_pop()
        guard is_ref_valtype(lhs) && is_ref_valtype(rhs) else {
          raise ValidationError::TypeMismatch(
            "ref.eq expects reference operands",
          )
        }
      }
      stack.push(I32)
    }
    RefAsNonNull =>
      // ref.as_non_null pops a reference and pushes a non-nullable reference
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, result stays polymorphic
        ()
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.as_non_null expects reference on stack",
        )
      } else {
        let popped = stack.unsafe_pop()
        guard is_ref_valtype(popped) else {
          raise ValidationError::TypeMismatch(
            "ref.as_non_null expects reference operand",
          )
        }
        stack.push(non_null_ref_type(popped))
      }
    RefTest(_, _) => {
      // ref.test pops a reference and pushes i32
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.test expects reference on stack",
        )
      } else {
        let popped = stack.unsafe_pop()
        guard is_ref_valtype(popped) else {
          raise ValidationError::TypeMismatch(
            "ref.test expects reference operand",
          )
        }
      }
      stack.push(I32)
    }
    RefCast(ref_type, nullable) => {
      // ref.cast pops a reference and pushes a reference of the target type
      let target = reftype_to_valtype(ref_type)
      let result_type = if nullable {
        target
      } else {
        non_null_ref_type(target)
      }
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.cast expects reference on stack",
        )
      } else {
        let popped = stack.unsafe_pop()
        guard is_ref_valtype(popped) else {
          raise ValidationError::TypeMismatch(
            "ref.cast expects reference operand",
          )
        }
      }
      stack.push(result_type)
    }
    _ => return false
  }
  true
}

///|
fn is_ref_valtype(val_type : @core.ValType) -> Bool {
  match val_type {
    FuncRef
    | ExternRef
    | AnyRef
    | EqRef
    | I31Ref
    | StructRef
    | ArrayRef
    | ExnRef
    | NullRef
    | NullFuncRef
    | NullExternRef
    | NullExnRef
    | Ref(_, _) => true
    _ => false
  }
}

///|
fn non_null_ref_type(val_type : @core.ValType) -> @core.ValType {
  match val_type {
    Ref(heap_type, true) => Ref(heap_type, false)
    Ref(heap_type, false) => Ref(heap_type, false)
    FuncRef => Ref(Func, false)
    ExternRef => Ref(Extern, false)
    AnyRef => Ref(Any, false)
    EqRef => Ref(Eq, false)
    I31Ref => Ref(I31, false)
    StructRef => Ref(Struct, false)
    ArrayRef => Ref(Array, false)
    ExnRef => Ref(Exn, false)
    NullRef => Ref(Any, false)
    NullFuncRef => Ref(Func, false)
    NullExternRef => Ref(Extern, false)
    NullExnRef => Ref(Exn, false)
    _ => val_type
  }
}
