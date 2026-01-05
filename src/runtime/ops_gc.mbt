///|
/// GC Object representation
/// GC objects are stored in the gc_heap array
/// Reference encoding uses tagging in high bits:
/// - 0xFFFFFFFFFFFFFFFF = null
/// - Low bit = 1, no high tag = i31ref ((value << 1) | 1)
/// - Low bit = 0, no high tag = GC ref (index << 1)
/// - Bit 62 set (0x4000...) = funcref
/// - Bit 61 set (0x2000...) = externref (including internalized via any.convert_extern)

///|
/// Reference tag constants
let ref_tag_funcref : UInt64 = 0x4000000000000000UL

///|
let ref_tag_externref : UInt64 = 0x2000000000000000UL

///|
let ref_tag_mask : UInt64 = 0x6000000000000000UL

///|
let ref_null : UInt64 = 0xFFFFFFFFFFFFFFFFUL

///|
/// GC Struct instance - stores field values as UInt64 array
pub(all) struct GcStruct {
  type_idx : Int
  fields : Array[UInt64]
}

///|
/// GC Array instance - stores element values as UInt64 array
pub(all) struct GcArray {
  type_idx : Int
  elements : Array[UInt64]
}

///|
/// GC Object - either a struct or an array
pub(all) enum GcObject {
  Struct(GcStruct)
  Array(GcArray)
  I31(Int) // i31ref - 31-bit integer as reference
}

// =============================================================================
// GC Heap operations
// =============================================================================

///|
/// Allocate a new struct on the GC heap
fn gc_alloc_struct(rt : Runtime, type_idx : Int, fields : Array[UInt64]) -> Int {
  let obj = GcObject::Struct({ type_idx, fields })
  rt.ctx.gc_heap.push(obj)
  // Encode as (index << 1) to distinguish from i31refs which have low bit set
  rt.ctx.gc_heap.length() << 1
}

///|
/// Allocate a new array on the GC heap
fn gc_alloc_array(
  rt : Runtime,
  type_idx : Int,
  elements : Array[UInt64],
) -> Int {
  let obj = GcObject::Array({ type_idx, elements })
  rt.ctx.gc_heap.push(obj)
  // Encode as (index << 1) to distinguish from i31refs which have low bit set
  rt.ctx.gc_heap.length() << 1
}

///|
/// Get the element storage type of an array type
fn get_array_element_type(rt : Runtime, type_idx : Int) -> @core.StorageType? {
  if type_idx < 0 || type_idx >= rt.ctx.module_.types.length() {
    return None
  }
  match rt.ctx.module_.types[type_idx] {
    Array(arr_type) => Some(arr_type.element.storage)
    _ => None
  }
}

///|
/// Get the default value for a storage type
/// Reference types default to null (0xFFFFFFFFFFFFFFFF)
/// Numeric types default to 0
fn storage_default_value(storage : @core.StorageType) -> UInt64 {
  match storage {
    I8 | I16 => 0UL
    Val(I32) | Val(I64) | Val(F32) | Val(F64) | Val(V128) => 0UL
    Val(_) => 0xFFFFFFFFFFFFFFFFUL // Reference types: null
  }
}

///|
/// Get a GC object by reference
/// GC refs are encoded as (1-based-index << 1), so we decode by right-shifting
fn gc_get_object(rt : Runtime, ref_value : Int) -> GcObject? {
  // Decode: right shift to get 1-based index
  let index = ref_value >> 1
  if index <= 0 {
    None
  } else if index > rt.ctx.gc_heap.length() {
    None
  } else {
    Some(rt.ctx.gc_heap[index - 1])
  }
}

// =============================================================================
// Struct operations
// =============================================================================

///|
/// struct.new type_idx
/// Pops field values from stack, creates new struct
fn op_struct_new(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_fields = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Pop field values from stack (in reverse order)
  let fields : Array[UInt64] = Array::make(num_fields, 0UL)
  let mut sp = rt.sp
  for i = num_fields - 1; i >= 0; i = i - 1 {
    sp = sp - 1
    fields[i] = rt.stack.unsafe_get(sp)
  }

  // Allocate struct
  let ref_value = gc_alloc_struct(rt, type_idx, fields)

  // Push reference
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 3 }
}

///|
/// struct.new_default type_idx
/// Creates a new struct with default (zero) values
fn op_struct_new_default(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_fields = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Create fields with default values (all zeros)
  let fields : Array[UInt64] = Array::make(num_fields, 0UL)

  // Allocate struct
  let ref_value = gc_alloc_struct(rt, type_idx, fields)

  // Push reference
  rt.stack.unsafe_set(rt.sp, ref_value.to_uint64())
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 3 }
}

///|
/// struct.get type_idx field_idx
/// Pops struct ref, pushes field value
fn op_struct_get(rt : Runtime) -> Runtime {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null structure reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      let value = s.fields[field_idx]
      rt.stack.unsafe_set(sp, value)
      { ..rt, sp: sp + 1, pc: rt.pc + 2 }
    }
    _ => {
      rt.ctx.error_detail = "struct.get: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// struct.get_s type_idx field_idx (sign-extend packed field)
fn op_struct_get_s(rt : Runtime) -> Runtime {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let storage_type = rt.ops.unsafe_get(rt.pc + 2).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "struct.get_s: null reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      let raw_value = s.fields[field_idx].to_uint()
      let signed_value = if storage_type == 0 {
        // i8 sign extend
        let v = raw_value & 0xFFU
        if (v & 0x80U) != 0U {
          v | 0xFFFFFF00U
        } else {
          v
        }
      } else {
        // i16 sign extend
        let v = raw_value & 0xFFFFU
        if (v & 0x8000U) != 0U {
          v | 0xFFFF0000U
        } else {
          v
        }
      }
      rt.stack.unsafe_set(sp, signed_value.to_uint64())
      { ..rt, sp: sp + 1, pc: rt.pc + 3 }
    }
    _ => {
      rt.ctx.error_detail = "struct.get_s: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// struct.get_u type_idx field_idx (zero-extend packed field)
fn op_struct_get_u(rt : Runtime) -> Runtime {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let storage_type = rt.ops.unsafe_get(rt.pc + 2).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "struct.get_u: null reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      let raw_value = s.fields[field_idx].to_uint()
      let value = if storage_type == 0 {
        raw_value & 0xFFU
      } else { // i8
        raw_value & 0xFFFFU
      } // i16
      rt.stack.unsafe_set(sp, value.to_uint64())
      { ..rt, sp: sp + 1, pc: rt.pc + 3 }
    }
    _ => {
      rt.ctx.error_detail = "struct.get_u: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// struct.set type_idx field_idx
/// Pops struct ref and value, sets field
fn op_struct_set(rt : Runtime) -> Runtime {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let value = rt.stack.unsafe_get(sp + 1)

  // Null check (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null structure reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      s.fields[field_idx] = value
      { ..rt, sp, pc: rt.pc + 2 }
    }
    _ => {
      rt.ctx.error_detail = "struct.set: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

// =============================================================================
// Array operations
// =============================================================================

///|
/// array.new type_idx
/// Pops value and length, creates new array filled with value
fn op_array_new(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 2
  let init_value = rt.stack.unsafe_get(sp)
  let length = rt.stack.unsafe_get(sp + 1).to_int()
  let elements = Array::make(length, init_value)
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 2 }
}

///|
/// array.new_default type_idx
/// Pops length, creates new array with default values
fn op_array_new_default(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 1
  let length = rt.stack.unsafe_get(sp).to_int()
  // Determine default value based on element type
  // For reference types, default is null (0xFFFFFFFFFFFFFFFF)
  // For numeric types, default is 0
  let default_value : UInt64 = match get_array_element_type(rt, type_idx) {
    Some(storage) => storage_default_value(storage)
    None => 0UL
  }
  let elements : Array[UInt64] = Array::make(length, default_value)
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 2 }
}

///|
/// array.new_fixed type_idx length
/// Pops length values from stack, creates array
fn op_array_new_fixed(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let length = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let elements : Array[UInt64] = Array::make(length, 0UL)
  let mut sp = rt.sp
  for i = length - 1; i >= 0; i = i - 1 {
    sp = sp - 1
    elements[i] = rt.stack.unsafe_get(sp)
  }
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 3 }
}

///|
/// array.new_data type_idx data_idx
/// Pops offset and length, creates array from data segment
fn op_array_new_data(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let data_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let elem_size = rt.ops.unsafe_get(rt.pc + 3).to_int() // 1, 2, 4, or 8 bytes
  let sp = rt.sp - 2
  let offset = rt.stack.unsafe_get(sp).to_int()
  let length = rt.stack.unsafe_get(sp + 1).to_int()

  // Get data segment
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "array.new_data: invalid data segment index"
    return { ..rt, status: Trap }
  }
  let data = rt.ctx.data_segments[data_idx]

  // Bounds check
  if offset < 0 || offset + length * elem_size > data.length() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, status: Trap }
  }

  // Create array elements from data segment
  let elements : Array[UInt64] = Array::make(length, 0UL)
  for i = 0; i < length; i = i + 1 {
    let byte_offset = offset + i * elem_size
    let mut value = 0UL
    for j = 0; j < elem_size; j = j + 1 {
      value = value | (data[byte_offset + j].to_uint64() << (j * 8))
    }
    elements[i] = value
  }
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 4 }
}

///|
/// array.get type_idx
/// Pops array ref and index, pushes element
fn op_array_get(rt : Runtime) -> Runtime {
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      let value = a.elements[index]
      rt.stack.unsafe_set(sp, value)
      { ..rt, sp: sp + 1, pc: rt.pc + 1 }
    }
    _ => {
      rt.ctx.error_detail = "array.get: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.get_s type_idx (sign-extend packed element)
fn op_array_get_s(rt : Runtime) -> Runtime {
  let storage_type = rt.ops.unsafe_get(rt.pc + 1).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      let raw_value = a.elements[index].to_uint()
      let signed_value = if storage_type == 0 {
        let v = raw_value & 0xFFU
        if (v & 0x80U) != 0U {
          v | 0xFFFFFF00U
        } else {
          v
        }
      } else {
        let v = raw_value & 0xFFFFU
        if (v & 0x8000U) != 0U {
          v | 0xFFFF0000U
        } else {
          v
        }
      }
      rt.stack.unsafe_set(sp, signed_value.to_uint64())
      { ..rt, sp: sp + 1, pc: rt.pc + 2 }
    }
    _ => {
      rt.ctx.error_detail = "array.get_s: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.get_u type_idx (zero-extend packed element)
fn op_array_get_u(rt : Runtime) -> Runtime {
  let storage_type = rt.ops.unsafe_get(rt.pc + 1).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      let raw_value = a.elements[index].to_uint()
      let value = if storage_type == 0 {
        raw_value & 0xFFU
      } else {
        raw_value & 0xFFFFU
      }
      rt.stack.unsafe_set(sp, value.to_uint64())
      { ..rt, sp: sp + 1, pc: rt.pc + 2 }
    }
    _ => {
      rt.ctx.error_detail = "array.get_u: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.set type_idx
/// Pops array ref, index, and value, sets element
fn op_array_set(rt : Runtime) -> Runtime {
  let sp = rt.sp - 3
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()
  let value = rt.stack.unsafe_get(sp + 2)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      a.elements[index] = value
      { ..rt, sp, pc: rt.pc + 1 }
    }
    _ => {
      rt.ctx.error_detail = "array.set: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.len
/// Pops array ref, pushes length
fn op_array_len(rt : Runtime) -> Runtime {
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      let len = a.elements.length()
      rt.stack.unsafe_set(sp, len.to_uint64())
      { ..rt, sp: sp + 1, pc: rt.pc + 1 }
    }
    _ => {
      rt.ctx.error_detail = "array.len: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.fill type_idx
/// Pops array, offset, value, length and fills the array
fn op_array_fill(rt : Runtime) -> Runtime {
  let sp = rt.sp - 4
  let ref_raw = rt.stack.unsafe_get(sp)
  let offset = rt.stack.unsafe_get(sp + 1).to_int()
  let value = rt.stack.unsafe_get(sp + 2)
  let length = rt.stack.unsafe_get(sp + 3).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if offset < 0 || offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      for i = 0; i < length; i = i + 1 {
        a.elements[offset + i] = value
      }
      { ..rt, sp, pc: rt.pc + 1 }
    }
    _ => {
      rt.ctx.error_detail = "array.fill: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.copy dst_type src_type
/// Copies elements from src array to dst array
fn op_array_copy(rt : Runtime) -> Runtime {
  let sp = rt.sp - 5
  let dst_ref_raw = rt.stack.unsafe_get(sp)
  let dst_offset = rt.stack.unsafe_get(sp + 1).to_int()
  let src_ref_raw = rt.stack.unsafe_get(sp + 2)
  let src_offset = rt.stack.unsafe_get(sp + 3).to_int()
  let length = rt.stack.unsafe_get(sp + 4).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if dst_ref_raw == 0xFFFFFFFFFFFFFFFFUL || src_ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let dst_ref = dst_ref_raw.to_int()
  let src_ref = src_ref_raw.to_int()
  match (gc_get_object(rt, dst_ref), gc_get_object(rt, src_ref)) {
    (Some(Array(dst)), Some(Array(src))) => {
      if dst_offset < 0 ||
        dst_offset + length > dst.elements.length() ||
        src_offset < 0 ||
        src_offset + length > src.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }
      // Handle overlapping regions
      if dst_ref == src_ref && dst_offset > src_offset {
        for i = length - 1; i >= 0; i = i - 1 {
          dst.elements[dst_offset + i] = src.elements[src_offset + i]
        }
      } else {
        for i = 0; i < length; i = i + 1 {
          dst.elements[dst_offset + i] = src.elements[src_offset + i]
        }
      }
      { ..rt, sp, pc: rt.pc + 1 }
    }
    _ => {
      rt.ctx.error_detail = "array.copy: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

// =============================================================================
// i31 operations
// =============================================================================

///|
/// ref.i31
/// Pops i32, pushes i31ref (31-bit signed integer as reference)
fn op_ref_i31(rt : Runtime) -> Runtime {
  let sp = rt.sp - 1
  let value = rt.stack.unsafe_get(sp).to_uint()

  // i31 is a 31-bit signed integer stored as a special reference
  // Encode as: (value << 1) | 1 to distinguish from GC heap references
  let i31_value = value & 0x7FFFFFFFU
  let encoded = (i31_value << 1) | 1U
  rt.stack.unsafe_set(sp, encoded.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 1 }
}

///|
/// i31.get_s
/// Pops i31ref, pushes sign-extended i32
fn op_i31_get_s(rt : Runtime) -> Runtime {
  let sp = rt.sp - 1
  let encoded = rt.stack.unsafe_get(sp)

  // Check for null reference first (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if encoded == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null i31 reference"
    return { ..rt, status: Trap }
  }
  let encoded_u32 = encoded.to_uint()
  // Check if it's a valid i31ref (lowest bit set)
  if (encoded_u32 & 1U) != 1U {
    rt.ctx.error_detail = "i31.get_s: not an i31ref"
    return { ..rt, status: Trap }
  }

  // Decode: (encoded >> 1) with sign extension from bit 30
  let raw = encoded_u32 >> 1
  let signed : UInt = if (raw & 0x40000000U) != 0U {
    raw | 0x80000000U
  } else { // Sign extend from bit 30
    raw
  }
  rt.stack.unsafe_set(sp, signed.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 1 }
}

///|
/// i31.get_u
/// Pops i31ref, pushes zero-extended i32
fn op_i31_get_u(rt : Runtime) -> Runtime {
  let sp = rt.sp - 1
  let encoded = rt.stack.unsafe_get(sp)

  // Check for null reference first (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if encoded == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null i31 reference"
    return { ..rt, status: Trap }
  }
  let encoded_u32 = encoded.to_uint()
  // Check if it's a valid i31ref
  if (encoded_u32 & 1U) != 1U {
    rt.ctx.error_detail = "i31.get_u: not an i31ref"
    return { ..rt, status: Trap }
  }

  // Decode: (encoded >> 1) masked to 31 bits
  let value = (encoded_u32 >> 1) & 0x7FFFFFFFU
  rt.stack.unsafe_set(sp, value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 1 }
}

// =============================================================================
// Reference conversion operations
// =============================================================================

///|
/// any.convert_extern
/// Converts externref to anyref
/// The value keeps its externref tag so it can still be identified as an
/// "internalized externref" - it matches any/eq but not i31/struct/array
fn op_any_convert_extern(rt : Runtime) -> Runtime {
  // Value stays unchanged - an internalized externref still has the externref tag
  // but is now typed as anyref. The tag allows gc_ref_matches_type to correctly
  // identify it as matching "any" but not more specific types like i31/struct/array.
  { ..rt, pc: rt.pc + 1 }
}

///|
/// extern.convert_any
/// Converts anyref to externref by adding externref tag
fn op_extern_convert_any(rt : Runtime) -> Runtime {
  let ref_value = rt.stack.unsafe_get(rt.sp - 1)
  // Null stays as null
  if ref_value == ref_null {
    return { ..rt, pc: rt.pc + 1 }
  }
  // Add externref tag (bit 61)
  let tagged = ref_value | 0x2000000000000000UL
  rt.stack.unsafe_set(rt.sp - 1, tagged)
  { ..rt, pc: rt.pc + 1 }
}

// =============================================================================
// Reference null/test operations
// =============================================================================

// Note: op_ref_null, op_ref_is_null, op_ref_as_non_null, and op_ref_eq
// are already defined in ops_control.mbt

// =============================================================================
// Runtime type checking helpers
// =============================================================================

///|
/// Check if a GC object reference matches or is a subtype of a target heap type
/// Returns true if the reference can be cast to the target type
fn gc_ref_matches_type(
  rt : Runtime,
  ref_value : UInt64,
  target_type : Int,
  target_nullable : Bool,
) -> Bool {
  // Check for null reference (stored as -1, i.e., 0xFFFFFFFFFFFFFFFF)
  if ref_value == ref_null {
    return target_nullable
  }

  // Check for funcref tag (bit 62 set)
  if (ref_value & ref_tag_funcref) == ref_tag_funcref {
    // Funcref: matches func (-7) or concrete function types
    if target_type == -7 {
      return true // func
    }
    if target_type >= 0 {
      // Check if function type matches target type
      let func_idx = ref_value.land(ref_tag_funcref.lnot()).to_int()
      let module_ = rt.ctx.module_
      let num_imported = count_imported_funcs(module_)
      if func_idx < num_imported {
        // Imported function - check type against imports
        for imp in module_.imports {
          match imp.desc {
            Func(type_idx) =>
              if type_idx.reinterpret_as_int() == target_type {
                return true
              }
            _ => continue
          }
        }
        return false
      } else {
        // Local function
        let local_idx = func_idx - num_imported
        if local_idx < module_.funcs.length() {
          let type_idx = module_.funcs[local_idx].reinterpret_as_int()
          return gc_is_type_subtype(rt, type_idx, target_type)
        }
      }
    }
    return false
  }

  // Check for externref/internalized externref tag (bit 61 set)
  if (ref_value & ref_tag_externref) == ref_tag_externref {
    // Externref or internalized externref
    // After any.convert_extern, matches any (-2)
    // Also matches extern (-8) in extern context
    return target_type == -2 || // any
      target_type == -8 // extern
  }

  // Check for i31ref (encoded with lowest bit set, no high tags)
  if (ref_value & ref_tag_mask) == 0UL && (ref_value & 1UL) == 1UL {
    // i31ref: check if target is i31, eq, or any
    return target_type == -4 || // I31
      target_type == -3 || // Eq
      target_type == -2 // Any
  }

  // Get the GC object
  let ref_int = ref_value.to_int()
  match gc_get_object(rt, ref_int) {
    Some(Struct(s)) =>
      // Struct reference: check if s.type_idx matches target
      if target_type >= 0 {
        // Target is a concrete type index
        gc_is_type_subtype(rt, s.type_idx, target_type)
      } else {
        // Target is an abstract type (-5=Struct, -3=Eq, -2=Any)
        target_type == -5 || target_type == -3 || target_type == -2
      }
    Some(Array(a)) =>
      // Array reference: check if a.type_idx matches target
      if target_type >= 0 {
        gc_is_type_subtype(rt, a.type_idx, target_type)
      } else {
        // Target is an abstract type (-6=Array, -3=Eq, -2=Any)
        target_type == -6 || target_type == -3 || target_type == -2
      }
    Some(I31(_)) =>
      // I31 value: check if target is i31, eq, or any
      target_type == -4 || target_type == -3 || target_type == -2
    None => false
  }
}

///|
/// Check if type_idx is a subtype of target_type_idx at runtime
/// This mirrors the validation-time is_type_index_subtype function
fn gc_is_type_subtype(
  rt : Runtime,
  type_idx : Int,
  target_type_idx : Int,
) -> Bool {
  if type_idx == target_type_idx {
    return true
  }
  let module_ = rt.ctx.module_

  // Search through type_groups for supertype declarations
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      let current_idx = subtype_def.type_idx.reinterpret_as_int()
      if current_idx == type_idx {
        for supertype in subtype_def.supertypes {
          let super_idx = supertype.reinterpret_as_int()
          if super_idx == target_type_idx {
            return true
          }
          if gc_is_type_subtype(rt, super_idx, target_type_idx) {
            return true
          }
        }
      }
    }
  }

  // Check structural type equivalence (not subtyping)
  // In WebAssembly GC, structurally identical types with the same supertype chain
  // are considered equivalent and can be used interchangeably
  if type_idx >= 0 &&
    type_idx < module_.types.length() &&
    target_type_idx >= 0 &&
    target_type_idx < module_.types.length() {
    match (module_.types[type_idx], module_.types[target_type_idx]) {
      (Struct(s1), Struct(s2)) =>
        return gc_is_struct_equivalent(rt, type_idx, s1, target_type_idx, s2)
      (Array(a1), Array(a2)) =>
        return gc_is_array_equivalent(rt, type_idx, a1, target_type_idx, a2)
      _ => ()
    }
  }
  false
}

///|
/// Check if two types (by index) are equivalent
fn gc_types_equivalent(rt : Runtime, type_idx1 : Int, type_idx2 : Int) -> Bool {
  // Same index = same type
  if type_idx1 == type_idx2 {
    return true
  }
  let module_ = rt.ctx.module_
  if type_idx1 < 0 ||
    type_idx1 >= module_.types.length() ||
    type_idx2 < 0 ||
    type_idx2 >= module_.types.length() {
    return false
  }
  match (module_.types[type_idx1], module_.types[type_idx2]) {
    (Struct(s1), Struct(s2)) =>
      gc_is_struct_equivalent(rt, type_idx1, s1, type_idx2, s2)
    (Array(a1), Array(a2)) =>
      gc_is_array_equivalent(rt, type_idx1, a1, type_idx2, a2)
    (Func(f1), Func(f2)) => f1 == f2 // Function types just need structural equality
    _ => false
  }
}

///|
/// Check if two struct types are equivalent (same structure and same supertypes)
fn gc_is_struct_equivalent(
  rt : Runtime,
  type_idx1 : Int,
  struct1 : @core.StructType,
  type_idx2 : Int,
  struct2 : @core.StructType,
) -> Bool {
  // First check structural equivalence - must have same number of fields with same types
  if struct1.fields.length() != struct2.fields.length() {
    return false
  }
  for i in 0..<struct1.fields.length() {
    let f1 = struct1.fields[i]
    let f2 = struct2.fields[i]
    if f1.mutable != f2.mutable {
      return false
    }
    if f1.storage != f2.storage {
      return false
    }
  }

  // Then check that supertypes are equivalent (not just same index)
  let supers1 = get_supertypes(rt, type_idx1)
  let supers2 = get_supertypes(rt, type_idx2)
  if supers1.length() != supers2.length() {
    return false
  }
  for i in 0..<supers1.length() {
    if supers1[i] != supers2[i] {
      // Different indices - check if they're equivalent types
      if not(gc_types_equivalent(rt, supers1[i], supers2[i])) {
        return false
      }
    }
  }
  true
}

///|
/// Check if two array types are equivalent
fn gc_is_array_equivalent(
  rt : Runtime,
  type_idx1 : Int,
  arr1 : @core.ArrayType,
  type_idx2 : Int,
  arr2 : @core.ArrayType,
) -> Bool {
  if arr1.element.mutable != arr2.element.mutable {
    return false
  }
  if arr1.element.storage != arr2.element.storage {
    return false
  }

  // Check supertypes are equivalent (not just same index)
  let supers1 = get_supertypes(rt, type_idx1)
  let supers2 = get_supertypes(rt, type_idx2)
  if supers1.length() != supers2.length() {
    return false
  }
  for i in 0..<supers1.length() {
    if supers1[i] != supers2[i] {
      if not(gc_types_equivalent(rt, supers1[i], supers2[i])) {
        return false
      }
    }
  }
  true
}

///|
/// Get the list of supertypes for a type index
fn get_supertypes(rt : Runtime, type_idx : Int) -> Array[Int] {
  let result : Array[Int] = []
  for group in rt.ctx.module_.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        for supertype in subtype_def.supertypes {
          result.push(supertype.reinterpret_as_int())
        }
        return result
      }
    }
  }
  result
}

///|
/// Check structural subtyping for struct types at runtime
fn gc_is_struct_subtype(
  rt : Runtime,
  struct1 : @core.StructType,
  struct2 : @core.StructType,
) -> Bool {
  if struct2.fields.length() > struct1.fields.length() {
    return false
  }
  for i in 0..<struct2.fields.length() {
    let f1 = struct1.fields[i]
    let f2 = struct2.fields[i]
    if f1.mutable != f2.mutable {
      return false
    }
    if not(gc_is_storage_type_subtype(rt, f1.storage, f2.storage, f1.mutable)) {
      return false
    }
  }
  true
}

///|
/// Check structural subtyping for array types at runtime
fn gc_is_array_subtype(
  rt : Runtime,
  arr1 : @core.ArrayType,
  arr2 : @core.ArrayType,
) -> Bool {
  if arr1.element.mutable != arr2.element.mutable {
    return false
  }
  gc_is_storage_type_subtype(
    rt,
    arr1.element.storage,
    arr2.element.storage,
    arr1.element.mutable,
  )
}

///|
/// Check storage type subtyping at runtime
fn gc_is_storage_type_subtype(
  rt : Runtime,
  storage1 : @core.StorageType,
  storage2 : @core.StorageType,
  mutable : Bool,
) -> Bool {
  match (storage1, storage2) {
    (Val(v1), Val(v2)) =>
      if mutable {
        v1 == v2
      } else {
        gc_is_valtype_subtype(rt, v1, v2)
      }
    (I8, I8) | (I16, I16) => true
    _ => false
  }
}

///|
/// Check value type subtyping at runtime
fn gc_is_valtype_subtype(
  rt : Runtime,
  t1 : @core.ValType,
  t2 : @core.ValType,
) -> Bool {
  if t1 == t2 {
    return true
  }
  match (t1, t2) {
    (Ref(TypeIndex(n1), _), Ref(TypeIndex(n2), _)) =>
      gc_is_type_subtype(rt, n1, n2)
    (Ref(_, false), Ref(ht, true)) => t1 == Ref(ht, false)
    (I31Ref, EqRef) | (I31Ref, AnyRef) => true
    (StructRef, EqRef) | (StructRef, AnyRef) => true
    (ArrayRef, EqRef) | (ArrayRef, AnyRef) => true
    (EqRef, AnyRef) => true
    _ => false
  }
}

///|
/// Convert heap type code to type index for runtime checking
/// Negative values represent abstract types:
/// -2 = Any, -3 = Eq, -4 = I31, -5 = Struct, -6 = Array, -7 = Func, -8 = Extern
fn heap_type_to_target_type(heap_type_code : Int) -> Int {
  match heap_type_code {
    0 => -7 // Func
    1 => -8 // Extern
    2 => -2 // Any
    3 => -3 // Eq
    4 => -4 // I31
    5 => -5 // Struct
    6 => -6 // Array
    _ => heap_type_code // TypeIndex (positive values)
  }
}

// =============================================================================
// ref.test / ref.cast operations
// =============================================================================

///|
/// ref.test heap_type nullable
/// Tests if a reference is of the given type, pushes i32 result
fn op_ref_test(rt : Runtime) -> Runtime {
  let target_type = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 2).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)
  let matches = gc_ref_matches_type(rt, ref_value, target_type, target_nullable)
  let result = if matches { 1U } else { 0U }
  rt.stack.unsafe_set(sp, result.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 3 }
}

///|
/// ref.cast heap_type nullable
/// Casts a reference to the given type, traps on failure
fn op_ref_cast(rt : Runtime) -> Runtime {
  let target_type = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 2).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)
  if gc_ref_matches_type(rt, ref_value, target_type, target_nullable) {
    // Cast succeeds - leave value on stack
    { ..rt, sp: sp + 1, pc: rt.pc + 3 }
  } else {
    rt.ctx.error_detail = "ref.cast: cast failed"
    { ..rt, status: Trap }
  }
}

// =============================================================================
// br_on_cast operations with proper type checking
// =============================================================================

///|
/// br_on_cast label target_type target_nullable
fn op_br_on_cast(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let target_type = rt.ops.unsafe_get(rt.pc + 4).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 5).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)

  // Check if cast succeeds using proper type checking
  let cast_succeeds = gc_ref_matches_type(
    rt, ref_value, target_type, target_nullable,
  )
  if cast_succeeds {
    // Branch - copy result values and jump
    if drop_count > 0 && arity > 0 {
      let result_start = rt.sp - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }
    { ..rt, sp: rt.sp - drop_count, pc: target_pc }
  } else {
    // Continue - leave reference on stack
    { ..rt, sp: sp + 1, pc: rt.pc + 6 }
  }
}

///|
/// br_on_cast_fail label target_type target_nullable
fn op_br_on_cast_fail(rt : Runtime) -> Runtime {
  let target_pc = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let arity = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let drop_count = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let target_type = rt.ops.unsafe_get(rt.pc + 4).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 5).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)

  // Check if cast fails using proper type checking
  let cast_fails = not(
    gc_ref_matches_type(rt, ref_value, target_type, target_nullable),
  )
  if cast_fails {
    // Branch
    if drop_count > 0 && arity > 0 {
      let result_start = rt.sp - arity
      let target_start = result_start - drop_count
      for i = 0; i < arity; i = i + 1 {
        rt.stack.unsafe_set(
          target_start + i,
          rt.stack.unsafe_get(result_start + i),
        )
      }
    }
    { ..rt, sp: rt.sp - drop_count, pc: target_pc }
  } else {
    // Continue - leave reference on stack
    { ..rt, sp: sp + 1, pc: rt.pc + 6 }
  }
}

// =============================================================================
// array.new_elem, array.init_data, array.init_elem operations
// =============================================================================

///|
/// array.new_elem type_idx elem_idx
/// Creates a new array from element segment values
fn op_array_new_elem(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let elem_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let sp = rt.sp - 2
  let offset = rt.stack.unsafe_get(sp).to_int()
  let length = rt.stack.unsafe_get(sp + 1).to_int()

  // Get element segment from module
  if elem_idx < 0 || elem_idx >= rt.ctx.module_.elems.length() {
    rt.ctx.error_detail = "array.new_elem: invalid element segment index"
    return { ..rt, status: Trap }
  }
  let elem = rt.ctx.module_.elems[elem_idx]

  // Bounds check
  if offset < 0 || offset + length > elem.init.length() {
    rt.ctx.error_detail = "out of bounds table access"
    return { ..rt, status: Trap }
  }

  // Create array elements by evaluating element expressions
  let elements : Array[UInt64] = Array::make(length, 0UL)
  for i = 0; i < length; i = i + 1 {
    let expr = elem.init[offset + i]
    // Evaluate the element expression (typically ref.func or ref.null)
    let value = eval_elem_expr(expr)
    elements[i] = value
  }
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  { ..rt, sp: sp + 1, pc: rt.pc + 3 }
}

///|
/// array.init_data type_idx data_idx
/// Initializes array elements from data segment
fn op_array_init_data(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let data_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let elem_size = rt.ops.unsafe_get(rt.pc + 3).to_int()
  let sp = rt.sp - 4
  let arr_ref_raw = rt.stack.unsafe_get(sp)
  let arr_offset = rt.stack.unsafe_get(sp + 1).to_int()
  let data_offset = rt.stack.unsafe_get(sp + 2).to_int()
  let length = rt.stack.unsafe_get(sp + 3).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if arr_ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let arr_ref = arr_ref_raw.to_int()

  // Get data segment
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "array.init_data: invalid data segment index"
    return { ..rt, status: Trap }
  }
  let data = rt.ctx.data_segments[data_idx]

  match gc_get_object(rt, arr_ref) {
    Some(Array(a)) => {
      // Check array bounds first (spec requires this order)
      if arr_offset < 0 || arr_offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }

      // Bounds check on data segment
      if data_offset < 0 || data_offset + length * elem_size > data.length() {
        rt.ctx.error_detail = "out of bounds memory access"
        return { ..rt, status: Trap }
      }

      // Copy data to array elements
      for i = 0; i < length; i = i + 1 {
        let byte_offset = data_offset + i * elem_size
        let mut value = 0UL
        for j = 0; j < elem_size; j = j + 1 {
          value = value | (data[byte_offset + j].to_uint64() << (j * 8))
        }
        a.elements[arr_offset + i] = value
      }
      ignore(type_idx)
      { ..rt, sp, pc: rt.pc + 4 }
    }
    _ => {
      rt.ctx.error_detail = "array.init_data: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// array.init_elem type_idx elem_idx
/// Initializes array elements from element segment
fn op_array_init_elem(rt : Runtime) -> Runtime {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let elem_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let sp = rt.sp - 4
  let arr_ref_raw = rt.stack.unsafe_get(sp)
  let arr_offset = rt.stack.unsafe_get(sp + 1).to_int()
  let elem_offset = rt.stack.unsafe_get(sp + 2).to_int()
  let length = rt.stack.unsafe_get(sp + 3).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if arr_ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    return { ..rt, status: Trap }
  }
  let arr_ref = arr_ref_raw.to_int()

  // Get element segment
  if elem_idx < 0 || elem_idx >= rt.ctx.module_.elems.length() {
    rt.ctx.error_detail = "array.init_elem: invalid element segment index"
    return { ..rt, status: Trap }
  }
  let elem = rt.ctx.module_.elems[elem_idx]

  match gc_get_object(rt, arr_ref) {
    Some(Array(a)) => {
      // Check array bounds first (spec requires this order)
      if arr_offset < 0 || arr_offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        return { ..rt, status: Trap }
      }

      // Check if segment is dropped (active/declarative segments are dropped after instantiation)
      if elem_idx >= 0 && elem_idx < rt.ctx.dropped_elems.length() &&
        rt.ctx.dropped_elems[elem_idx] {
        // Dropped segment: any non-zero length or offset is out of bounds
        if length != 0 || elem_offset != 0 {
          rt.ctx.error_detail = "out of bounds table access"
          return { ..rt, status: Trap }
        }
        // n=0, src=0 is valid even for dropped segments
        return { ..rt, sp, pc: rt.pc + 3 }
      }

      // Bounds check on element segment
      if elem_offset < 0 || elem_offset + length > elem.init.length() {
        rt.ctx.error_detail = "out of bounds table access"
        return { ..rt, status: Trap }
      }

      // Copy element expressions to array elements
      for i = 0; i < length; i = i + 1 {
        let expr = elem.init[elem_offset + i]
        let value = eval_elem_expr(expr)
        a.elements[arr_offset + i] = value
      }
      ignore(type_idx)
      { ..rt, sp, pc: rt.pc + 3 }
    }
    _ => {
      rt.ctx.error_detail = "array.init_elem: invalid reference"
      { ..rt, status: Trap }
    }
  }
}

///|
/// Evaluate an element segment expression to get a reference value
fn eval_elem_expr(expr : @core.Expr) -> UInt64 {
  // Element expressions are typically simple: ref.func or ref.null
  for instr in expr.instrs {
    match instr {
      RefFunc(idx) =>
        // Function reference - return the function index
        return idx.to_uint64()
      RefNull(_) =>
        // Null reference
        return 0UL
      I32Const(v) => return v.to_uint64()
      I64Const(v) => return v
      _ => ()
    }
  }
  // Default to null if expression is not recognized
  0UL
}
