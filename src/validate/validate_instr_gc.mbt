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
      let _ = require_array_type(
        module_,
        dst_type.reinterpret_as_int(),
        "array.copy",
      )
      let _ = require_array_type(
        module_,
        src_type.reinterpret_as_int(),
        "array.copy",
      )
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
      let _ = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.init_data",
      )
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
      let _ = require_array_type(
        module_,
        type_idx.reinterpret_as_int(),
        "array.init_elem",
      )
      validate_elem_index(module_, elem_idx, "array.init_elem")
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
      _target_type,
      _target_nullable,
      source_type,
      source_nullable
    ) => {
      let source_val = heap_type_valtype(source_type, source_nullable)
      ctx.poly_pop_expect(module_, source_val, "br_on_cast ref")
      stack.push(source_val)
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
      ctx.poly_pop_expect(module_, source_val, "br_on_cast_fail ref")
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
