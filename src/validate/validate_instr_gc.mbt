///|
fn validate_instruction_gc(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    StructNew(type_idx) => {
      let struct_type = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.new",
      )
      for i = struct_type.fields.length() - 1; i >= 0; i = i - 1 {
        let field = struct_type.fields[i]
        let value_type = storage_value_type(field.storage)
        ctx.poly_pop_expect(module_, value_type, "struct.new field")
      }
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    StructNewDefault(type_idx) => {
      let _ = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.new_default",
      )
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    StructGet(type_idx, field_idx) => {
      let struct_type = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.get",
      )
      let field = get_field(struct_type, field_idx, "struct.get")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "struct.get ref",
      )
      stack.push(storage_value_type(field.storage))
    }
    StructGetS(type_idx, field_idx) => {
      let struct_type = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.get_s",
      )
      let field = get_field(struct_type, field_idx, "struct.get_s")
      guard is_packed_storage(field.storage) else {
        raise ValidationError::TypeMismatch("struct.get_s expects packed field")
      }
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "struct.get_s ref",
      )
      stack.push(I32)
    }
    StructGetU(type_idx, field_idx) => {
      let struct_type = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.get_u",
      )
      let field = get_field(struct_type, field_idx, "struct.get_u")
      guard is_packed_storage(field.storage) else {
        raise ValidationError::TypeMismatch("struct.get_u expects packed field")
      }
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "struct.get_u ref",
      )
      stack.push(I32)
    }
    StructSet(type_idx, field_idx) => {
      let struct_type = require_struct_type(
        module_,
        type_idx.reinterpret_as_int(),
        "struct.set",
      )
      let field = get_field(struct_type, field_idx, "struct.set")
      // Check that field is mutable
      guard field.mutable else {
        raise ValidationError::TypeMismatch("struct.set: immutable field")
      }
      let value_type = storage_value_type(field.storage)
      ctx.poly_pop_expect(module_, value_type, "struct.set value")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "struct.set ref",
      )
    }
    ArrayNew(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.new",
      )
      ctx.poly_pop_expect(module_, I32, "array.new length")
      ctx.poly_pop_expect(
        module_,
        storage_value_type(array_type.element.storage),
        "array.new element",
      )
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    ArrayNewDefault(type_idx) => {
      let _ = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.new_default",
      )
      ctx.poly_pop_expect(module_, I32, "array.new_default length")
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    ArrayNewFixed(type_idx, len) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.new_fixed",
      )
      let elem_type = storage_value_type(array_type.element.storage)
      for _ in 0..<len.reinterpret_as_int() {
        ctx.poly_pop_expect(module_, elem_type, "array.new_fixed element")
      }
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    ArrayNewData(type_idx, data_idx) => {
      let _ = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.new_data",
      )
      validate_data_index(module_, data_idx, "array.new_data")
      ctx.poly_pop_expect(module_, I32, "array.new_data offset")
      ctx.poly_pop_expect(module_, I32, "array.new_data length")
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    ArrayNewElem(type_idx, elem_idx) => {
      let _ = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.new_elem",
      )
      validate_elem_index(module_, elem_idx, "array.new_elem")
      ctx.poly_pop_expect(module_, I32, "array.new_elem offset")
      ctx.poly_pop_expect(module_, I32, "array.new_elem length")
      stack.push(Ref(TypeIndex(type_idx.reinterpret_as_int()), false))
    }
    ArrayGet(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.get",
      )
      ctx.poly_pop_expect(module_, I32, "array.get index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.get ref",
      )
      stack.push(storage_value_type(array_type.element.storage))
    }
    ArrayGetS(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.get_s",
      )
      guard is_packed_storage(array_type.element.storage) else {
        raise ValidationError::TypeMismatch(
          "array.get_s expects packed element",
        )
      }
      ctx.poly_pop_expect(module_, I32, "array.get_s index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.get_s ref",
      )
      stack.push(I32)
    }
    ArrayGetU(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.get_u",
      )
      guard is_packed_storage(array_type.element.storage) else {
        raise ValidationError::TypeMismatch(
          "array.get_u expects packed element",
        )
      }
      ctx.poly_pop_expect(module_, I32, "array.get_u index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.get_u ref",
      )
      stack.push(I32)
    }
    ArraySet(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.set",
      )
      // Check that array is mutable
      guard array_type.element.mutable else {
        raise ValidationError::TypeMismatch("array.set: immutable array")
      }
      let elem_type = storage_value_type(array_type.element.storage)
      ctx.poly_pop_expect(module_, elem_type, "array.set value")
      ctx.poly_pop_expect(module_, I32, "array.set index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.set ref",
      )
    }
    ArrayLen => {
      ctx.poly_pop_expect(module_, ArrayRef, "array.len ref")
      stack.push(I32)
    }
    ArrayFill(type_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.fill",
      )
      // Array must be mutable
      guard array_type.element.mutable else {
        raise ValidationError::TypeMismatch("immutable array")
      }
      let elem_type = storage_value_type(array_type.element.storage)
      ctx.poly_pop_expect(module_, I32, "array.fill length")
      ctx.poly_pop_expect(module_, elem_type, "array.fill value")
      ctx.poly_pop_expect(module_, I32, "array.fill index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.fill ref",
      )
    }
    ArrayCopy(dst_type, src_type) => {
      let dst_arr_type = require_array_type(
        module_,
        dst_type.reinterpret_as_int(),
        "array.copy",
      )
      let src_arr_type = require_array_type(
        module_,
        src_type.reinterpret_as_int(),
        "array.copy",
      )
      // Destination array must be mutable
      guard dst_arr_type.element.mutable else {
        raise ValidationError::TypeMismatch("immutable array")
      }
      // Element types must match (source must be subtype of destination)
      let dst_elem = dst_arr_type.element.storage
      let src_elem = src_arr_type.element.storage
      guard dst_elem == src_elem else {
        raise ValidationError::TypeMismatch("array types do not match")
      }
      ctx.poly_pop_expect(module_, I32, "array.copy length")
      ctx.poly_pop_expect(module_, I32, "array.copy src index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(src_type.reinterpret_as_int()), true),
        "array.copy src ref",
      )
      ctx.poly_pop_expect(module_, I32, "array.copy dst index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(dst_type.reinterpret_as_int()), true),
        "array.copy dst ref",
      )
    }
    ArrayInitData(type_idx, data_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.init_data",
      )
      guard array_type.element.mutable else {
        raise ValidationError::TypeMismatch("immutable array")
      }
      // Element type must be numeric or vector (not a reference type)
      guard is_numeric_or_vector_storage(array_type.element.storage) else {
        raise ValidationError::TypeMismatch(
          "array type is not numeric or vector",
        )
      }
      validate_data_index(module_, data_idx, "array.init_data")
      ctx.poly_pop_expect(module_, I32, "array.init_data length")
      ctx.poly_pop_expect(module_, I32, "array.init_data offset")
      ctx.poly_pop_expect(module_, I32, "array.init_data index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.init_data ref",
      )
    }
    ArrayInitElem(type_idx, elem_idx) => {
      let array_type = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.init_elem",
      )
      guard array_type.element.mutable else {
        raise ValidationError::TypeMismatch("immutable array")
      }
      // Array element type must be a reference type
      let arr_elem_val = match array_type.element.storage {
        Val(v) => v
        _ =>
          raise ValidationError::TypeMismatch(
            "array.init_elem: element type must be reference",
          )
      }
      guard arr_elem_val.is_ref_type() else {
        raise ValidationError::TypeMismatch(
          "array.init_elem: element type must be reference",
        )
      }
      // Element segment type must be subtype of array element type
      validate_elem_index(module_, elem_idx, "array.init_elem")
      let elem_idx_int = elem_idx.reinterpret_as_int()
      let elem = module_.elems[elem_idx_int]
      let elem_val = reftype_to_valtype(elem.elem_type)
      if not(is_subtype(module_, elem_val, arr_elem_val)) {
        raise ValidationError::TypeMismatch(
          "array.init_elem: element segment type not subtype of array element",
        )
      }
      ctx.poly_pop_expect(module_, I32, "array.init_elem length")
      ctx.poly_pop_expect(module_, I32, "array.init_elem offset")
      ctx.poly_pop_expect(module_, I32, "array.init_elem index")
      ctx.poly_pop_expect(
        module_,
        Ref(TypeIndex(type_idx.reinterpret_as_int()), true),
        "array.init_elem ref",
      )
    }
    BrOnCast(
      _label,
      target_type,
      target_nullable,
      source_type,
      source_nullable
    ) => {
      let source_val = heap_type_valtype(source_type, source_nullable)
      let target_val = heap_type_valtype(target_type, target_nullable)
      // Target type must be a subtype of source type (you can only downcast)
      guard is_subtype(module_, target_val, source_val) else {
        raise ValidationError::TypeMismatch(
          "br_on_cast target type must be subtype of source type",
        )
      }
      ctx.poly_pop_expect(module_, source_val, "br_on_cast ref")
      // Fallthrough type is the difference type: rt1 \ rt2
      // If target is nullable, the fallthrough is non-nullable (null would have branched)
      let diff_nullable = source_nullable && not(target_nullable)
      let diff_val = heap_type_valtype(source_type, diff_nullable)
      stack.push(diff_val)
    }
    BrOnCastFail(
      _label,
      target_type,
      target_nullable,
      source_type,
      source_nullable
    ) => {
      let source_val = heap_type_valtype(source_type, source_nullable)
      let target_val = heap_type_valtype(target_type, target_nullable)
      // Target type must be a subtype of source type (you can only downcast)
      guard is_subtype(module_, target_val, source_val) else {
        raise ValidationError::TypeMismatch(
          "br_on_cast_fail target type must be subtype of source type",
        )
      }
      ctx.poly_pop_expect(module_, source_val, "br_on_cast_fail ref")
      // Fallthrough type is the target type (cast succeeded)
      stack.push(target_val)
    }
    AnyConvertExtern => {
      ctx.poly_pop_expect(module_, ExternRef, "any.convert_extern")
      stack.push(AnyRef)
    }
    ExternConvertAny => {
      ctx.poly_pop_expect(module_, AnyRef, "extern.convert_any")
      stack.push(ExternRef)
    }
    RefI31 => {
      ctx.poly_pop_expect(module_, I32, "ref.i31")
      stack.push(Ref(I31, false))
    }
    I31GetS => {
      ctx.poly_pop_expect(module_, I31Ref, "i31.get_s")
      stack.push(I32)
    }
    I31GetU => {
      ctx.poly_pop_expect(module_, I31Ref, "i31.get_u")
      stack.push(I32)
    }
    _ => return false
  }
  true
}

///|
fn require_struct_type(
  module_ : @core.Module,
  type_idx : Int,
  context : String,
) -> @core.StructType raise ValidationError {
  if type_idx < 0 || type_idx >= module_.types.length() {
    raise ValidationError::InvalidTypeIndex(type_idx)
  }
  match module_.types[type_idx] {
    Struct(struct_type) => struct_type
    _ => raise ValidationError::TypeMismatch("\{context} expects struct type")
  }
}

///|
fn require_array_type(
  module_ : @core.Module,
  type_idx : Int,
  context : String,
) -> @core.ArrayType raise ValidationError {
  if type_idx < 0 || type_idx >= module_.types.length() {
    raise ValidationError::InvalidTypeIndex(type_idx)
  }
  match module_.types[type_idx] {
    Array(array_type) => array_type
    _ => raise ValidationError::TypeMismatch("\{context} expects array type")
  }
}

///|
fn get_field(
  struct_type : @core.StructType,
  field_idx : UInt,
  context : String,
) -> @core.FieldType raise ValidationError {
  let idx = field_idx.reinterpret_as_int()
  if idx < 0 || idx >= struct_type.fields.length() {
    raise ValidationError::TypeMismatch("\{context} invalid field index")
  }
  struct_type.fields[idx]
}

///|
fn storage_value_type(storage : @core.StorageType) -> @core.ValType {
  match storage {
    Val(val_type) => val_type
    I8 | I16 => I32
  }
}

///|
fn is_packed_storage(storage : @core.StorageType) -> Bool {
  match storage {
    I8 | I16 => true
    Val(_) => false
  }
}

///|
fn is_numeric_or_vector_storage(storage : @core.StorageType) -> Bool {
  match storage {
    I8 | I16 => true
    Val(I32) | Val(I64) | Val(F32) | Val(F64) | Val(V128) => true
    _ => false // Reference types
  }
}

///|
fn heap_type_valtype(
  ref_type : @core.RefType,
  nullable : Bool,
) -> @core.ValType {
  let base = reftype_to_valtype(ref_type)
  if nullable {
    base
  } else {
    non_null_ref_type(base)
  }
}

///|

///|
fn validate_data_index(
  module_ : @core.Module,
  data_idx : UInt,
  context : String,
) -> Unit raise ValidationError {
  let idx = data_idx.reinterpret_as_int()
  if idx < 0 || idx >= module_.datas.length() {
    raise ValidationError::TypeMismatch("\{context} invalid data index")
  }
}

///|
fn validate_elem_index(
  module_ : @core.Module,
  elem_idx : UInt,
  context : String,
) -> Unit raise ValidationError {
  let idx = elem_idx.reinterpret_as_int()
  if idx < 0 || idx >= module_.elems.length() {
    raise ValidationError::TypeMismatch("\{context} invalid elem index")
  }
}
