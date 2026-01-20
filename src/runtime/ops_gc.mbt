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
fn op_struct_new(rt : Runtime) -> ReturnCode {
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
  rt.sp = sp + 1
  rt.pc = rt.pc + 3
  Running
}

///|
/// struct.new_default type_idx
/// Creates a new struct with default (zero) values
fn op_struct_new_default(rt : Runtime) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let num_fields = rt.ops.unsafe_get(rt.pc + 2).to_int()

  // Create fields with default values (all zeros)
  let fields : Array[UInt64] = Array::make(num_fields, 0UL)

  // Allocate struct
  let ref_value = gc_alloc_struct(rt, type_idx, fields)

  // Push reference
  rt.stack.unsafe_set(rt.sp, ref_value.to_uint64())
  rt.sp = rt.sp + 1
  rt.pc = rt.pc + 3
  Running
}

///|
/// struct.get type_idx field_idx
/// Pops struct ref, pushes field value
fn op_struct_get(rt : Runtime) -> ReturnCode {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null structure reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      let value = s.fields[field_idx]
      rt.stack.unsafe_set(sp, value)
      rt.sp = sp + 1
      rt.pc = rt.pc + 2
      Running
    }
    _ => {
      rt.ctx.error_detail = "struct.get: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// struct.get_s type_idx field_idx (sign-extend packed field)
fn op_struct_get_s(rt : Runtime) -> ReturnCode {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let storage_type = rt.ops.unsafe_get(rt.pc + 2).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "struct.get_s: null reference"
    rt.status = Trap
    return Trap
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
      rt.sp = sp + 1
      rt.pc = rt.pc + 3
      Running
    }
    _ => {
      rt.ctx.error_detail = "struct.get_s: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// struct.get_u type_idx field_idx (zero-extend packed field)
fn op_struct_get_u(rt : Runtime) -> ReturnCode {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let storage_type = rt.ops.unsafe_get(rt.pc + 2).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "struct.get_u: null reference"
    rt.status = Trap
    return Trap
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
      rt.sp = sp + 1
      rt.pc = rt.pc + 3
      Running
    }
    _ => {
      rt.ctx.error_detail = "struct.get_u: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// struct.set type_idx field_idx
/// Pops struct ref and value, sets field
fn op_struct_set(rt : Runtime) -> ReturnCode {
  let field_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let value = rt.stack.unsafe_get(sp + 1)

  // Null check (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null structure reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Struct(s)) => {
      s.fields[field_idx] = value
      rt.pc = rt.pc + 2
      Running
    }
    _ => {
      rt.ctx.error_detail = "struct.set: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

// =============================================================================
// Array operations
// =============================================================================

///|
/// array.new type_idx
/// Pops value and length, creates new array filled with value
fn op_array_new(rt : Runtime) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let sp = rt.sp - 2
  let init_value = rt.stack.unsafe_get(sp)
  let length = rt.stack.unsafe_get(sp + 1).to_int()
  let elements = Array::make(length, init_value)
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
/// array.new_default type_idx
/// Pops length, creates new array with default values
fn op_array_new_default(rt : Runtime) -> ReturnCode {
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
  rt.sp = sp + 1
  rt.pc = rt.pc + 2
  Running
}

///|
/// array.new_fixed type_idx length
/// Pops length values from stack, creates array
fn op_array_new_fixed(rt : Runtime) -> ReturnCode {
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
  rt.sp = sp + 1
  rt.pc = rt.pc + 3
  Running
}

///|
/// array.new_data type_idx data_idx
/// Pops offset and length, creates array from data segment
fn op_array_new_data(rt : Runtime) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let data_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let elem_size = rt.ops.unsafe_get(rt.pc + 3).to_int() // 1, 2, 4, or 8 bytes
  let sp = rt.sp - 2
  let offset = rt.stack.unsafe_get(sp).to_int()
  let length = rt.stack.unsafe_get(sp + 1).to_int()

  // Get data segment
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "array.new_data: invalid data segment index"
    rt.status = Trap
    return Trap
  }
  let data = rt.ctx.data_segments[data_idx]

  // Bounds check
  if offset < 0 || offset + length * elem_size > data.length() {
    rt.ctx.error_detail = "out of bounds memory access"
    rt.status = Trap
    return Trap
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
  rt.sp = sp + 1
  rt.pc = rt.pc + 4
  Running
}

///|
/// array.get type_idx
/// Pops array ref and index, pushes element
fn op_array_get(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }
      let value = a.elements[index]
      rt.stack.unsafe_set(sp, value)
      rt.sp = sp + 1
      rt.pc = rt.pc + 1
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.get: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.get_s type_idx (sign-extend packed element)
fn op_array_get_s(rt : Runtime) -> ReturnCode {
  let storage_type = rt.ops.unsafe_get(rt.pc + 1).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
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
      rt.sp = sp + 1
      rt.pc = rt.pc + 2
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.get_s: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.get_u type_idx (zero-extend packed element)
fn op_array_get_u(rt : Runtime) -> ReturnCode {
  let storage_type = rt.ops.unsafe_get(rt.pc + 1).to_int() // 0=i8, 1=i16
  let sp = rt.sp - 2
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }
      let raw_value = a.elements[index].to_uint()
      let value = if storage_type == 0 {
        raw_value & 0xFFU
      } else {
        raw_value & 0xFFFFU
      }
      rt.stack.unsafe_set(sp, value.to_uint64())
      rt.sp = sp + 1
      rt.pc = rt.pc + 2
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.get_u: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.set type_idx
/// Pops array ref, index, and value, sets element
fn op_array_set(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 3
  let ref_raw = rt.stack.unsafe_get(sp)
  let index = rt.stack.unsafe_get(sp + 1).to_int()
  let value = rt.stack.unsafe_get(sp + 2)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if index < 0 || index >= a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }
      a.elements[index] = value
      rt.pc = rt.pc + 1
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.set: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.len
/// Pops array ref, pushes length
fn op_array_len(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 1
  let ref_raw = rt.stack.unsafe_get(sp)

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      let len = a.elements.length()
      rt.stack.unsafe_set(sp, len.to_uint64())
      rt.sp = sp + 1
      rt.pc = rt.pc + 1
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.len: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.fill type_idx
/// Pops array, offset, value, length and fills the array
fn op_array_fill(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 4
  let ref_raw = rt.stack.unsafe_get(sp)
  let offset = rt.stack.unsafe_get(sp + 1).to_int()
  let value = rt.stack.unsafe_get(sp + 2)
  let length = rt.stack.unsafe_get(sp + 3).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
  }
  let ref_value = ref_raw.to_int()
  match gc_get_object(rt, ref_value) {
    Some(Array(a)) => {
      if offset < 0 || offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }
      for i = 0; i < length; i = i + 1 {
        a.elements[offset + i] = value
      }
      rt.pc = rt.pc + 1
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.fill: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.copy dst_type src_type
/// Copies elements from src array to dst array
fn op_array_copy(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 5
  let dst_ref_raw = rt.stack.unsafe_get(sp)
  let dst_offset = rt.stack.unsafe_get(sp + 1).to_int()
  let src_ref_raw = rt.stack.unsafe_get(sp + 2)
  let src_offset = rt.stack.unsafe_get(sp + 3).to_int()
  let length = rt.stack.unsafe_get(sp + 4).to_int()

  // Null check (null is 0xFFFFFFFFFFFFFFFF)
  if dst_ref_raw == 0xFFFFFFFFFFFFFFFFUL || src_ref_raw == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null array reference"
    rt.status = Trap
    return Trap
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
        rt.status = Trap
        return Trap
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
      rt.pc = rt.pc + 1
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.copy: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

// =============================================================================
// i31 operations
// =============================================================================

///|
/// ref.i31
/// Pops i32, pushes i31ref (31-bit signed integer as reference)
fn op_ref_i31(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 1
  let value = rt.stack.unsafe_get(sp).to_uint()

  // i31 is a 31-bit signed integer stored as a special reference
  // Encode as: (value << 1) | 1 to distinguish from GC heap references
  let i31_value = value & 0x7FFFFFFFU
  let encoded = (i31_value << 1) | 1U
  rt.stack.unsafe_set(sp, encoded.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 1
  Running
}

///|
/// i31.get_s
/// Pops i31ref, pushes sign-extended i32
fn op_i31_get_s(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 1
  let encoded = rt.stack.unsafe_get(sp)

  // Check for null reference first (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if encoded == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null i31 reference"
    rt.status = Trap
    return Trap
  }
  let encoded_u32 = encoded.to_uint()
  // Check if it's a valid i31ref (lowest bit set)
  if (encoded_u32 & 1U) != 1U {
    rt.ctx.error_detail = "i31.get_s: not an i31ref"
    rt.status = Trap
    return Trap
  }

  // Decode: (encoded >> 1) with sign extension from bit 30
  let raw = encoded_u32 >> 1
  let signed : UInt = if (raw & 0x40000000U) != 0U {
    raw | 0x80000000U
  } else { // Sign extend from bit 30
    raw
  }
  rt.stack.unsafe_set(sp, signed.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 1
  Running
}

///|
/// i31.get_u
/// Pops i31ref, pushes zero-extended i32
fn op_i31_get_u(rt : Runtime) -> ReturnCode {
  let sp = rt.sp - 1
  let encoded = rt.stack.unsafe_get(sp)

  // Check for null reference first (null is -1 / 0xFFFFFFFFFFFFFFFF)
  if encoded == 0xFFFFFFFFFFFFFFFFUL {
    rt.ctx.error_detail = "null i31 reference"
    rt.status = Trap
    return Trap
  }
  let encoded_u32 = encoded.to_uint()
  // Check if it's a valid i31ref
  if (encoded_u32 & 1U) != 1U {
    rt.ctx.error_detail = "i31.get_u: not an i31ref"
    rt.status = Trap
    return Trap
  }

  // Decode: (encoded >> 1) masked to 31 bits
  let value = (encoded_u32 >> 1) & 0x7FFFFFFFU
  rt.stack.unsafe_set(sp, value.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 1
  Running
}

// =============================================================================
// Reference conversion operations
// =============================================================================

///|
/// any.convert_extern
/// Converts externref to anyref
/// The value keeps its externref tag so it can still be identified as an
/// "internalized externref" - it matches any/eq but not i31/struct/array
fn op_any_convert_extern(rt : Runtime) -> ReturnCode {
  // Value stays unchanged - an internalized externref still has the externref tag
  // but is now typed as anyref. The tag allows gc_ref_matches_type to correctly
  // identify it as matching "any" but not more specific types like i31/struct/array.
  rt.pc = rt.pc + 1
  Running
}

///|
/// extern.convert_any
/// Converts anyref to externref by adding externref tag
fn op_extern_convert_any(rt : Runtime) -> ReturnCode {
  let ref_value = rt.stack.unsafe_get(rt.sp - 1)
  // Null stays as null
  if ref_value == ref_null {
    rt.pc = rt.pc + 1
    return Running
  }
  // Add externref tag (bit 61)
  let tagged = ref_value | 0x2000000000000000UL
  rt.stack.unsafe_set(rt.sp - 1, tagged)
  rt.pc = rt.pc + 1
  Running
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
      let num_imported = rt.ctx.num_imported_funcs
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

  // Check structural type equivalence using rec group-aware logic
  // In WebAssembly GC, types from equivalent rec groups are considered equal
  if gc_types_equivalent(rt, type_idx, target_type_idx) {
    return true
  }

  // Also need to check if the target is an equivalent of any supertype
  // This handles cases where we have equivalent types in the subtype chain
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      let current_idx = subtype_def.type_idx.reinterpret_as_int()
      if current_idx == type_idx {
        for supertype in subtype_def.supertypes {
          let super_idx = supertype.reinterpret_as_int()
          // Check if target is equivalent to this supertype
          if gc_types_equivalent(rt, super_idx, target_type_idx) {
            return true
          }
        }
      }
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
  // Use rec group aware equivalence check
  let (group1_idx, _) = get_rec_group_info(rt, type_idx1)
  let (group2_idx, _) = get_rec_group_info(rt, type_idx2)
  let visited : Array[(Int, Int)] = []
  rec_groups_equivalent(rt, group1_idx, group2_idx, visited)
}

///|
/// Get the rec group index and position within group for a type index
/// Returns (group_index, position_in_group) or (-1, -1) if not found
fn get_rec_group_info(rt : Runtime, type_idx : Int) -> (Int, Int) {
  for group_idx, group in rt.ctx.module_.type_groups {
    for pos, subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        return (group_idx, pos)
      }
    }
  }
  (-1, -1)
}

///|
/// Get all type indices in a rec group
fn get_rec_group_types(rt : Runtime, group_idx : Int) -> Array[Int] {
  let result : Array[Int] = []
  if group_idx >= 0 && group_idx < rt.ctx.module_.type_groups.length() {
    let group = rt.ctx.module_.type_groups[group_idx]
    for subtype_def in group.subtypes {
      result.push(subtype_def.type_idx.reinterpret_as_int())
    }
  }
  result
}

///|
/// Check if a type index is within a given rec group
fn is_in_rec_group(types : Array[Int], type_idx : Int) -> Bool {
  for t in types {
    if t == type_idx {
      return true
    }
  }
  false
}

///|
/// Get the position of a type within its rec group
fn get_position_in_group(types : Array[Int], type_idx : Int) -> Int {
  for i, t in types {
    if t == type_idx {
      return i
    }
  }
  -1
}

///|
/// Check if two rec groups are structurally equivalent
/// This handles the recursive type equivalence rules in WebAssembly GC
fn rec_groups_equivalent(
  rt : Runtime,
  group1_idx : Int,
  group2_idx : Int,
  visited : Array[(Int, Int)],
) -> Bool {
  // Same group is equivalent
  if group1_idx == group2_idx {
    return true
  }
  // Check if we've already determined these groups are equivalent (cycle detection)
  for v in visited {
    if (v.0 == group1_idx && v.1 == group2_idx) ||
      (v.0 == group2_idx && v.1 == group1_idx) {
      return true
    }
  }
  let types1 = get_rec_group_types(rt, group1_idx)
  let types2 = get_rec_group_types(rt, group2_idx)
  // Groups must have same number of types
  if types1.length() != types2.length() {
    return false
  }
  // Mark as being compared to handle cycles
  visited.push((group1_idx, group2_idx))
  // Check each corresponding type
  for i in 0..<types1.length() {
    let t1 = types1[i]
    let t2 = types2[i]
    if not(types_equivalent_in_context(rt, t1, t2, types1, types2, visited)) {
      return false
    }
  }
  true
}

///|
/// Check if two types are equivalent in the context of their rec groups
fn types_equivalent_in_context(
  rt : Runtime,
  type_idx1 : Int,
  type_idx2 : Int,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  let module_ = rt.ctx.module_
  if type_idx1 < 0 ||
    type_idx1 >= module_.types.length() ||
    type_idx2 < 0 ||
    type_idx2 >= module_.types.length() {
    return false
  }
  // Check structural type match
  match (module_.types[type_idx1], module_.types[type_idx2]) {
    (Func(f1), Func(f2)) => {
      // Check finality
      if is_type_final_runtime(rt, type_idx1) !=
        is_type_final_runtime(rt, type_idx2) {
        return false
      }
      // Check params and results, handling recursive references
      if f1.params.length() != f2.params.length() ||
        f1.results.length() != f2.results.length() {
        return false
      }
      for i in 0..<f1.params.length() {
        if not(
            valtypes_equivalent_in_context(
              rt,
              f1.params[i],
              f2.params[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      for i in 0..<f1.results.length() {
        if not(
            valtypes_equivalent_in_context(
              rt,
              f1.results[i],
              f2.results[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      // Check supertypes are equivalent
      let supers1 = get_supertypes(rt, type_idx1)
      let supers2 = get_supertypes(rt, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              rt,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    (Struct(s1), Struct(s2)) => {
      if is_type_final_runtime(rt, type_idx1) !=
        is_type_final_runtime(rt, type_idx2) {
        return false
      }
      if s1.fields.length() != s2.fields.length() {
        return false
      }
      for i in 0..<s1.fields.length() {
        if s1.fields[i].mutable != s2.fields[i].mutable {
          return false
        }
        if not(
            storage_types_equivalent_in_context(
              rt,
              s1.fields[i].storage,
              s2.fields[i].storage,
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      let supers1 = get_supertypes(rt, type_idx1)
      let supers2 = get_supertypes(rt, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              rt,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    (Array(a1), Array(a2)) => {
      if is_type_final_runtime(rt, type_idx1) !=
        is_type_final_runtime(rt, type_idx2) {
        return false
      }
      if a1.element.mutable != a2.element.mutable {
        return false
      }
      if not(
          storage_types_equivalent_in_context(
            rt,
            a1.element.storage,
            a2.element.storage,
            group1_types,
            group2_types,
            visited,
          ),
        ) {
        return false
      }
      let supers1 = get_supertypes(rt, type_idx1)
      let supers2 = get_supertypes(rt, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              rt,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Check if two type references are equivalent considering rec group context
fn type_refs_equivalent_in_context(
  rt : Runtime,
  ref1 : Int,
  ref2 : Int,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  let in_group1 = is_in_rec_group(group1_types, ref1)
  let in_group2 = is_in_rec_group(group2_types, ref2)
  if in_group1 && in_group2 {
    // Both are internal references - must be at same position
    let pos1 = get_position_in_group(group1_types, ref1)
    let pos2 = get_position_in_group(group2_types, ref2)
    pos1 == pos2
  } else if not(in_group1) && not(in_group2) {
    // Both are external references - must point to equivalent types
    if ref1 == ref2 {
      return true
    }
    let (g1, _) = get_rec_group_info(rt, ref1)
    let (g2, _) = get_rec_group_info(rt, ref2)
    rec_groups_equivalent(rt, g1, g2, visited)
  } else {
    // One internal, one external - not equivalent
    false
  }
}

///|
/// Check if two value types are equivalent in rec group context
fn valtypes_equivalent_in_context(
  rt : Runtime,
  vt1 : @core.ValType,
  vt2 : @core.ValType,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  match (vt1, vt2) {
    (Ref(TypeIndex(idx1), n1), Ref(TypeIndex(idx2), n2)) =>
      n1 == n2 &&
      type_refs_equivalent_in_context(
        rt, idx1, idx2, group1_types, group2_types, visited,
      )
    _ => vt1 == vt2
  }
}

///|
/// Check if two storage types are equivalent in rec group context
fn storage_types_equivalent_in_context(
  rt : Runtime,
  st1 : @core.StorageType,
  st2 : @core.StorageType,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  match (st1, st2) {
    (Val(vt1), Val(vt2)) =>
      valtypes_equivalent_in_context(
        rt, vt1, vt2, group1_types, group2_types, visited,
      )
    _ => st1 == st2
  }
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
/// Check if a type at the given index is final at runtime
fn is_type_final_runtime(rt : Runtime, type_idx : Int) -> Bool {
  for group in rt.ctx.module_.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        return subtype_def.is_final
      }
    }
  }
  // Type not found in any SubTypeDef - implicitly final
  true
}

// =============================================================================
// ref.test / ref.cast operations
// =============================================================================

///|
/// ref.test heap_type nullable
/// Tests if a reference is of the given type, pushes i32 result
fn op_ref_test(rt : Runtime) -> ReturnCode {
  let target_type = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 2).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)
  let matches = gc_ref_matches_type(rt, ref_value, target_type, target_nullable)
  let result = if matches { 1U } else { 0U }
  rt.stack.unsafe_set(sp, result.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 3
  Running
}

///|
/// ref.cast heap_type nullable
/// Casts a reference to the given type, traps on failure
fn op_ref_cast(rt : Runtime) -> ReturnCode {
  let target_type = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let target_nullable = rt.ops.unsafe_get(rt.pc + 2).to_int() != 0
  let sp = rt.sp - 1
  let ref_value = rt.stack.unsafe_get(sp)
  if gc_ref_matches_type(rt, ref_value, target_type, target_nullable) {
    // Cast succeeds - leave value on stack
    rt.sp = sp + 1
    rt.pc = rt.pc + 3
    Running
  } else {
    rt.ctx.error_detail = "ref.cast: cast failed"
    rt.status = Trap
    Trap
  }
}

// =============================================================================
// br_on_cast operations with proper type checking
// =============================================================================

///|
/// br_on_cast label target_type target_nullable
fn op_br_on_cast(rt : Runtime) -> ReturnCode {
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
    rt.sp = rt.sp - drop_count
    rt.pc = target_pc
    Running
  } else {
    // Continue - leave reference on stack
    rt.sp = sp + 1
    rt.pc = rt.pc + 6
    Running
  }
}

///|
/// br_on_cast_fail label target_type target_nullable
fn op_br_on_cast_fail(rt : Runtime) -> ReturnCode {
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
    rt.sp = rt.sp - drop_count
    rt.pc = target_pc
    Running
  } else {
    // Continue - leave reference on stack
    rt.sp = sp + 1
    rt.pc = rt.pc + 6
    Running
  }
}

// =============================================================================
// array.new_elem, array.init_data, array.init_elem operations
// =============================================================================

///|
/// array.new_elem type_idx elem_idx
/// Creates a new array from element segment values
fn op_array_new_elem(rt : Runtime) -> ReturnCode {
  let type_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let elem_idx = rt.ops.unsafe_get(rt.pc + 2).to_int()
  let sp = rt.sp - 2
  let offset = rt.stack.unsafe_get(sp).to_int()
  let length = rt.stack.unsafe_get(sp + 1).to_int()

  // Get element segment from module
  if elem_idx < 0 || elem_idx >= rt.ctx.module_.elems.length() {
    rt.ctx.error_detail = "array.new_elem: invalid element segment index"
    rt.status = Trap
    return Trap
  }
  let elem = rt.ctx.module_.elems[elem_idx]

  // Check if segment is dropped (active/declarative segments are dropped after instantiation)
  if elem_idx >= 0 &&
    elem_idx < rt.ctx.dropped_elems.length() &&
    rt.ctx.dropped_elems[elem_idx] {
    // Dropped segment: any non-zero length or offset is out of bounds
    if length != 0 || offset != 0 {
      rt.ctx.error_detail = "out of bounds table access"
      rt.status = Trap
      return Trap
    }
    // n=0, src=0 is valid even for dropped segments - create empty array
    let elements : Array[UInt64] = []
    let ref_value = gc_alloc_array(rt, type_idx, elements)
    rt.stack.unsafe_set(sp, ref_value.to_uint64())
    rt.sp = sp + 1
    rt.pc = rt.pc + 3
    return Running
  }

  // Bounds check
  if offset < 0 || offset + length > elem.init.length() {
    rt.ctx.error_detail = "out of bounds table access"
    rt.status = Trap
    return Trap
  }

  // Create array elements by evaluating element expressions
  let elements : Array[UInt64] = Array::make(length, 0UL)
  for i = 0; i < length; i = i + 1 {
    let expr = elem.init[offset + i]
    // Evaluate the element expression using full GC-aware evaluator
    let value = eval_elem_expr_gc(rt, expr, elem.elem_type)
    elements[i] = value
  }
  let ref_value = gc_alloc_array(rt, type_idx, elements)
  rt.stack.unsafe_set(sp, ref_value.to_uint64())
  rt.sp = sp + 1
  rt.pc = rt.pc + 3
  Running
}

///|
/// array.init_data type_idx data_idx
/// Initializes array elements from data segment
fn op_array_init_data(rt : Runtime) -> ReturnCode {
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
    rt.status = Trap
    return Trap
  }
  let arr_ref = arr_ref_raw.to_int()

  // Get data segment
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "array.init_data: invalid data segment index"
    rt.status = Trap
    return Trap
  }
  let data = rt.ctx.data_segments[data_idx]
  match gc_get_object(rt, arr_ref) {
    Some(Array(a)) => {
      // Check array bounds first (spec requires this order)
      if arr_offset < 0 || arr_offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }

      // Bounds check on data segment
      if data_offset < 0 || data_offset + length * elem_size > data.length() {
        rt.ctx.error_detail = "out of bounds memory access"
        rt.status = Trap
        return Trap
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
      rt.pc = rt.pc + 4
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.init_data: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// array.init_elem type_idx elem_idx
/// Initializes array elements from element segment
fn op_array_init_elem(rt : Runtime) -> ReturnCode {
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
    rt.status = Trap
    return Trap
  }
  let arr_ref = arr_ref_raw.to_int()

  // Get element segment
  if elem_idx < 0 || elem_idx >= rt.ctx.module_.elems.length() {
    rt.ctx.error_detail = "array.init_elem: invalid element segment index"
    rt.status = Trap
    return Trap
  }
  let elem = rt.ctx.module_.elems[elem_idx]
  match gc_get_object(rt, arr_ref) {
    Some(Array(a)) => {
      // Check array bounds first (spec requires this order)
      if arr_offset < 0 || arr_offset + length > a.elements.length() {
        rt.ctx.error_detail = "out of bounds array access"
        rt.status = Trap
        return Trap
      }

      // Check if segment is dropped (active/declarative segments are dropped after instantiation)
      if elem_idx >= 0 &&
        elem_idx < rt.ctx.dropped_elems.length() &&
        rt.ctx.dropped_elems[elem_idx] {
        // Dropped segment: any non-zero length or offset is out of bounds
        if length != 0 || elem_offset != 0 {
          rt.ctx.error_detail = "out of bounds table access"
          rt.status = Trap
          return Trap
        }
        // n=0, src=0 is valid even for dropped segments
        rt.pc = rt.pc + 3
        return Running
      }

      // Bounds check on element segment
      if elem_offset < 0 || elem_offset + length > elem.init.length() {
        rt.ctx.error_detail = "out of bounds table access"
        rt.status = Trap
        return Trap
      }

      // Copy element expressions to array elements
      for i = 0; i < length; i = i + 1 {
        let expr = elem.init[elem_offset + i]
        let value = eval_elem_expr_gc(rt, expr, elem.elem_type)
        a.elements[arr_offset + i] = value
      }
      ignore(type_idx)
      rt.pc = rt.pc + 3
      Running
    }
    _ => {
      rt.ctx.error_detail = "array.init_elem: invalid reference"
      rt.status = Trap
      Trap
    }
  }
}

///|
/// Evaluate an element segment expression to get a reference value
fn eval_elem_expr_gc(
  rt : Runtime,
  expr : @core.Expr,
  elem_type : @core.RefType,
) -> UInt64 {
  // Use the full GC-aware constant expression evaluator
  let ctx = ConstExprContext::{
    gc_heap: rt.ctx.gc_heap,
    module_: Some(rt.ctx.module_),
  }
  let value = eval_const_expr_with_context(expr, rt.ctx.globals, ctx) catch {
    _ => return 0xFFFFFFFFFFFFFFFFUL // Return null on error
  }
  // Convert Value to UInt64 with proper encoding
  match value {
    Ref(Some(idx)) =>
      // For GC refs (struct, array, i31), the idx is already properly encoded
      // For typed function refs, check elem_type
      match elem_type {
        @core.Func | @core.NoFunc =>
          // Funcref - add funcref tag
          (idx.to_int64().reinterpret_as_uint64() & 0x3FFFFFFFFFFFFFFFUL) |
          0x4000000000000000UL
        @core.Extern | @core.NoExtern =>
          // Externref - add externref tag
          (idx.to_int64().reinterpret_as_uint64() & 0x3FFFFFFFFFFFFFFFUL) |
          0x2000000000000000UL
        _ =>
          // i31, struct, array, or other GC ref - already encoded
          idx.to_int64().reinterpret_as_uint64()
      }
    Ref(None) => 0xFFFFFFFFFFFFFFFFUL
    Funcref(Some(idx)) => idx.to_uint64() | 0x4000000000000000UL
    Funcref(None) => 0xFFFFFFFFFFFFFFFFUL
    Externref(Some(idx)) => idx.to_uint64() | 0x2000000000000000UL
    Externref(None) => 0xFFFFFFFFFFFFFFFFUL
    _ => 0xFFFFFFFFFFFFFFFFUL // Shouldn't happen for elem expressions
  }
}
