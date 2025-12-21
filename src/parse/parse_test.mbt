///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn push_u32_leb(dst : Array[Byte], value : UInt) -> Unit {
  let mut remaining = value
  while true {
    let mut byte_val = remaining & 0x7FU
    remaining = remaining >> 7
    if remaining != 0 {
      byte_val = byte_val | 0x80U
    }
    dst.push(byte_val.to_byte())
    if remaining == 0 {
      break
    }
  }
}

///|
fn make_section(id : Byte, payload : Array[Byte]) -> Array[Byte] {
  let section : Array[Byte] = []
  section.push(id)
  push_u32_leb(section, payload.length().reinterpret_as_uint())
  append_bytes(section, payload)
  section
}

///|
fn build_module(sections : Array[Array[Byte]]) -> Bytes {
  let buf : Array[Byte] = [
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
  ]
  for section in sections {
    append_bytes(buf, section)
  }
  Bytes::from_array(buf)
}

///|
fn encode_limits(min : UInt, max : UInt?) -> Array[Byte] {
  let buf : Array[Byte] = []
  match max {
    Some(max_val) => {
      buf.push(b'\x01')
      push_u32_leb(buf, min)
      push_u32_leb(buf, max_val)
    }
    None => {
      buf.push(b'\x00')
      push_u32_leb(buf, min)
    }
  }
  buf
}

///|
fn encode_func_type(params : Array[Byte], results : Array[Byte]) -> Array[Byte] {
  let buf : Array[Byte] = []
  buf.push(b'\x60')
  push_u32_leb(buf, params.length().reinterpret_as_uint())
  for param in params {
    buf.push(param)
  }
  push_u32_leb(buf, results.length().reinterpret_as_uint())
  for result in results {
    buf.push(result)
  }
  buf
}

///|
fn encode_locals_i32(count : UInt) -> Array[Byte] {
  if count == 0U {
    return [b'\x00']
  }
  let buf : Array[Byte] = []
  push_u32_leb(buf, 1U)
  push_u32_leb(buf, count)
  buf.push(b'\x7f')
  buf
}

///|
fn encode_function_body(
  locals_decl : Array[Byte],
  instrs : Array[Byte],
) -> Array[Byte] {
  let body : Array[Byte] = []
  append_bytes(body, locals_decl)
  append_bytes(body, instrs)
  let out : Array[Byte] = []
  push_u32_leb(out, body.length().reinterpret_as_uint())
  append_bytes(out, body)
  out
}

///|
fn emit_i32_const(buf : Array[Byte], value : UInt) -> Unit {
  buf.push(b'\x41')
  push_u32_leb(buf, value)
}

///|
fn emit_i64_const(buf : Array[Byte], value : UInt) -> Unit {
  buf.push(b'\x42')
  push_u32_leb(buf, value)
}

///|
fn emit_f32_const_zero(buf : Array[Byte]) -> Unit {
  buf.push(b'\x43')
  for _ in 0..<4 {
    buf.push(b'\x00')
  }
}

///|
fn emit_f64_const_zero(buf : Array[Byte]) -> Unit {
  buf.push(b'\x44')
  for _ in 0..<8 {
    buf.push(b'\x00')
  }
}

///|
fn emit_drop(buf : Array[Byte]) -> Unit {
  buf.push(b'\x1a')
}

///|
fn emit_ref_null_funcref(buf : Array[Byte]) -> Unit {
  buf.push(b'\xd0')
  buf.push(b'\x70')
}

///|
fn emit_memarg_zero(buf : Array[Byte]) -> Unit {
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
}

///|
fn emit_prefix_fc(buf : Array[Byte], sub_opcode : UInt) -> Unit {
  buf.push(b'\xfc')
  push_u32_leb(buf, sub_opcode)
}

///|
fn emit_i32_unary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_i32_binary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_i32_const(buf, 0U)
    emit_i32_const(buf, 1U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_i64_unary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_i64_const(buf, 0U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_i64_binary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_i64_const(buf, 0U)
    emit_i64_const(buf, 1U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_f32_unary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_f32_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_f32_binary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_f32_const_zero(buf)
    emit_f32_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_f64_unary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_f64_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_f64_binary_ops(buf : Array[Byte], ops : Array[UInt]) -> Unit {
  for op in ops {
    emit_f64_const_zero(buf)
    emit_f64_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
}

///|
fn emit_numeric_ops(buf : Array[Byte]) -> Unit {
  let i32_unary_ops : Array[UInt] = [0x45, 0x67, 0x68, 0x69, 0xc0, 0xc1]
  let i32_binary_ops : Array[UInt] = [
    0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76,
    0x77, 0x78,
  ]
  let i32_compare_ops : Array[UInt] = [
    0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
  ]
  let i64_unary_ops : Array[UInt] = [0x50, 0x79, 0x7a, 0x7b, 0xc2, 0xc3, 0xc4]
  let i64_binary_ops : Array[UInt] = [
    0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88,
    0x89, 0x8a,
  ]
  let i64_compare_ops : Array[UInt] = [
    0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a,
  ]
  let f32_compare_ops : Array[UInt] = [0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60]
  let f64_compare_ops : Array[UInt] = [0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
  let f32_unary_ops : Array[UInt] = [0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91]
  let f64_unary_ops : Array[UInt] = [0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f]
  let f32_binary_ops : Array[UInt] = [0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98]
  let f64_binary_ops : Array[UInt] = [0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6]
  let i64_extend_i32_ops : Array[UInt] = [0xac, 0xad]
  let i32_to_float_ops : Array[UInt] = [0xb2, 0xb3, 0xb7, 0xb8]
  let i64_to_float_ops : Array[UInt] = [0xb4, 0xb5, 0xb9, 0xba]
  let f32_to_i32_ops : Array[UInt] = [0xa8, 0xa9]
  let f64_to_i32_ops : Array[UInt] = [0xaa, 0xab]
  let f32_to_i64_ops : Array[UInt] = [0xae, 0xaf]
  let f64_to_i64_ops : Array[UInt] = [0xb0, 0xb1]
  emit_i32_unary_ops(buf, i32_unary_ops)
  emit_i32_binary_ops(buf, i32_binary_ops)
  emit_i32_binary_ops(buf, i32_compare_ops)
  emit_i64_unary_ops(buf, i64_unary_ops)
  emit_i64_binary_ops(buf, i64_binary_ops)
  emit_i64_binary_ops(buf, i64_compare_ops)
  emit_f32_binary_ops(buf, f32_compare_ops)
  emit_f64_binary_ops(buf, f64_compare_ops)
  emit_f32_unary_ops(buf, f32_unary_ops)
  emit_f64_unary_ops(buf, f64_unary_ops)
  emit_f32_binary_ops(buf, f32_binary_ops)
  emit_f64_binary_ops(buf, f64_binary_ops)
  for op in i64_extend_i32_ops {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  emit_i64_const(buf, 0U)
  buf.push(b'\xa7')
  emit_drop(buf)
  for op in i32_to_float_ops {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  for op in i64_to_float_ops {
    emit_i64_const(buf, 0U)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  for op in f32_to_i32_ops {
    emit_f32_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  for op in f64_to_i32_ops {
    emit_f64_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  for op in f32_to_i64_ops {
    emit_f32_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  for op in f64_to_i64_ops {
    emit_f64_const_zero(buf)
    buf.push(op.to_byte())
    emit_drop(buf)
  }
  emit_f64_const_zero(buf)
  buf.push(b'\xb6')
  emit_drop(buf)
  emit_f32_const_zero(buf)
  buf.push(b'\xbb')
  emit_drop(buf)
  emit_f32_const_zero(buf)
  buf.push(b'\xbc')
  emit_drop(buf)
  emit_f64_const_zero(buf)
  buf.push(b'\xbd')
  emit_drop(buf)
  emit_i32_const(buf, 0U)
  buf.push(b'\xbe')
  emit_drop(buf)
  emit_i64_const(buf, 0U)
  buf.push(b'\xbf')
  emit_drop(buf)
}

///|
fn emit_trunc_sat_ops(buf : Array[Byte]) -> Unit {
  let f32_ops : Array[UInt] = [0x00, 0x01, 0x04, 0x05]
  let f64_ops : Array[UInt] = [0x02, 0x03, 0x06, 0x07]
  for op in f32_ops {
    emit_f32_const_zero(buf)
    emit_prefix_fc(buf, op)
    emit_drop(buf)
  }
  for op in f64_ops {
    emit_f64_const_zero(buf)
    emit_prefix_fc(buf, op)
    emit_drop(buf)
  }
}

///|
fn emit_memory_ops(buf : Array[Byte]) -> Unit {
  let i32_loads : Array[UInt] = [0x28, 0x2c, 0x2d, 0x2e, 0x2f]
  let i64_loads : Array[UInt] = [0x29, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35]
  let f32_loads : Array[UInt] = [0x2a]
  let f64_loads : Array[UInt] = [0x2b]
  let i32_stores : Array[UInt] = [0x36, 0x3a, 0x3b]
  let i64_stores : Array[UInt] = [0x37, 0x3c, 0x3d, 0x3e]
  let f32_stores : Array[UInt] = [0x38]
  let f64_stores : Array[UInt] = [0x39]
  for op in i32_loads {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
    emit_drop(buf)
  }
  for op in i64_loads {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
    emit_drop(buf)
  }
  for op in f32_loads {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
    emit_drop(buf)
  }
  for op in f64_loads {
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
    emit_drop(buf)
  }
  for op in i32_stores {
    emit_i32_const(buf, 0U)
    emit_i32_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
  }
  for op in i64_stores {
    emit_i32_const(buf, 0U)
    emit_i64_const(buf, 0U)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
  }
  for op in f32_stores {
    emit_i32_const(buf, 0U)
    emit_f32_const_zero(buf)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
  }
  for op in f64_stores {
    emit_i32_const(buf, 0U)
    emit_f64_const_zero(buf)
    buf.push(op.to_byte())
    emit_memarg_zero(buf)
  }
  buf.push(b'\x3f')
  buf.push(b'\x00')
  emit_drop(buf)
  emit_i32_const(buf, 0U)
  buf.push(b'\x40')
  buf.push(b'\x00')
  emit_drop(buf)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_prefix_fc(buf, 0x08)
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  emit_prefix_fc(buf, 0x09)
  push_u32_leb(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_prefix_fc(buf, 0x0a)
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_prefix_fc(buf, 0x0b)
  push_u32_leb(buf, 0U)
}

///|
fn emit_table_ops(buf : Array[Byte]) -> Unit {
  emit_i32_const(buf, 0U)
  buf.push(b'\x25')
  push_u32_leb(buf, 0U)
  emit_drop(buf)
  emit_i32_const(buf, 0U)
  emit_ref_null_funcref(buf)
  buf.push(b'\x26')
  push_u32_leb(buf, 0U)
  emit_ref_null_funcref(buf)
  emit_i32_const(buf, 1U)
  emit_prefix_fc(buf, 0x0f)
  push_u32_leb(buf, 0U)
  emit_drop(buf)
  emit_prefix_fc(buf, 0x10)
  push_u32_leb(buf, 0U)
  emit_drop(buf)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_prefix_fc(buf, 0x0c)
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_i32_const(buf, 0U)
  emit_prefix_fc(buf, 0x0e)
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  emit_prefix_fc(buf, 0x0d)
  push_u32_leb(buf, 0U)
}

///|
fn emit_reference_ops(buf : Array[Byte]) -> Unit {
  emit_ref_null_funcref(buf)
  buf.push(b'\xd1')
  emit_drop(buf)
  emit_ref_null_funcref(buf)
  buf.push(b'\xd3')
  emit_drop(buf)
  buf.push(b'\xd2')
  push_u32_leb(buf, 1U)
  buf.push(b'\xd1')
  emit_drop(buf)
  buf.push(b'\x16')
  push_u32_leb(buf, 0U)
  buf.push(b'\xd4')
}

///|
fn emit_parametric_ops(buf : Array[Byte]) -> Unit {
  emit_i32_const(buf, 0U)
  emit_drop(buf)
  emit_i32_const(buf, 1U)
  emit_i32_const(buf, 2U)
  emit_i32_const(buf, 1U)
  buf.push(b'\x1b')
  emit_drop(buf)
  emit_i32_const(buf, 3U)
  emit_i32_const(buf, 4U)
  emit_i32_const(buf, 0U)
  buf.push(b'\x1c')
  push_u32_leb(buf, 1U)
  buf.push(b'\x7f')
  emit_drop(buf)
}

///|
fn emit_variable_ops(buf : Array[Byte]) -> Unit {
  emit_i32_const(buf, 1U)
  buf.push(b'\x21')
  push_u32_leb(buf, 0U)
  buf.push(b'\x20')
  push_u32_leb(buf, 0U)
  emit_drop(buf)
  emit_i32_const(buf, 2U)
  buf.push(b'\x22')
  push_u32_leb(buf, 0U)
  emit_drop(buf)
  emit_i32_const(buf, 3U)
  buf.push(b'\x24')
  push_u32_leb(buf, 0U)
  buf.push(b'\x23')
  push_u32_leb(buf, 0U)
  emit_drop(buf)
}

///|
fn emit_control_ops(buf : Array[Byte]) -> Unit {
  buf.push(b'\x02')
  buf.push(b'\x40')
  buf.push(b'\x01')
  buf.push(b'\x00')
  buf.push(b'\x0b')
  buf.push(b'\x02')
  buf.push(b'\x7f')
  emit_i32_const(buf, 0U)
  buf.push(b'\x0b')
  emit_drop(buf)
  buf.push(b'\x03')
  buf.push(b'\x40')
  buf.push(b'\x01')
  buf.push(b'\x0b')
  emit_i32_const(buf, 1U)
  buf.push(b'\x04')
  buf.push(b'\x40')
  buf.push(b'\x01')
  buf.push(b'\x05')
  buf.push(b'\x01')
  buf.push(b'\x0b')
  buf.push(b'\x02')
  buf.push(b'\x40')
  emit_i32_const(buf, 1U)
  buf.push(b'\x0d')
  push_u32_leb(buf, 0U)
  emit_i32_const(buf, 0U)
  buf.push(b'\x0e')
  push_u32_leb(buf, 1U)
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  buf.push(b'\x0c')
  push_u32_leb(buf, 0U)
  buf.push(b'\x0b')
  buf.push(b'\x02')
  buf.push(b'\x40')
  emit_ref_null_funcref(buf)
  buf.push(b'\xd5')
  push_u32_leb(buf, 0U)
  buf.push(b'\xd6')
  push_u32_leb(buf, 0U)
  buf.push(b'\x0b')
  buf.push(b'\x02')
  buf.push(b'\x40')
  buf.push(b'\x06')
  buf.push(b'\x40')
  buf.push(b'\x0b')
  buf.push(b'\x07')
  push_u32_leb(buf, 0U)
  buf.push(b'\x08')
  push_u32_leb(buf, 0U)
  buf.push(b'\x09')
  push_u32_leb(buf, 0U)
  buf.push(b'\x0a')
  buf.push(b'\x1f')
  buf.push(b'\x40')
  push_u32_leb(buf, 0U)
  buf.push(b'\x0b')
  buf.push(b'\x0b')
  buf.push(b'\x10')
  push_u32_leb(buf, 1U)
  emit_i32_const(buf, 0U)
  buf.push(b'\x11')
  push_u32_leb(buf, 0U)
  push_u32_leb(buf, 0U)
  buf.push(b'\xd2')
  push_u32_leb(buf, 1U)
  buf.push(b'\x14')
  push_u32_leb(buf, 0U)
}

///|
fn build_main_instrs() -> Array[Byte] {
  let instrs : Array[Byte] = []
  emit_control_ops(instrs)
  emit_variable_ops(instrs)
  emit_parametric_ops(instrs)
  emit_reference_ops(instrs)
  emit_table_ops(instrs)
  emit_memory_ops(instrs)
  emit_numeric_ops(instrs)
  emit_trunc_sat_ops(instrs)
  instrs.push(b'\x0f')
  instrs.push(b'\x0b')
  instrs
}

///|
test "parse import and export sections" {
  let type_payload : Array[Byte] = []
  push_u32_leb(type_payload, 1U)
  append_bytes(type_payload, encode_func_type([], []))
  let import_payload : Array[Byte] = []
  push_u32_leb(import_payload, 5U)
  // func import
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'f')
  import_payload.push(b'\x00')
  push_u32_leb(import_payload, 0U)
  // table import
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  push_u32_leb(import_payload, 1U)
  import_payload.push(b't')
  import_payload.push(b'\x01')
  import_payload.push(b'\x63')
  import_payload.push(b'\x00')
  append_bytes(import_payload, encode_limits(1U, None))
  // memory import
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  import_payload.push(b'\x02')
  append_bytes(import_payload, encode_limits(1U, None))
  // global import
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'g')
  import_payload.push(b'\x03')
  import_payload.push(b'\x7f')
  import_payload.push(b'\x00')
  // tag import
  push_u32_leb(import_payload, 1U)
  import_payload.push(b'm')
  push_u32_leb(import_payload, 3U)
  append_bytes(import_payload, [b't', b'a', b'g'])
  import_payload.push(b'\x04')
  import_payload.push(b'\x00')
  push_u32_leb(import_payload, 0U)
  let export_payload : Array[Byte] = []
  push_u32_leb(export_payload, 5U)
  // func export
  push_u32_leb(export_payload, 1U)
  export_payload.push(b'f')
  export_payload.push(b'\x00')
  push_u32_leb(export_payload, 0U)
  // table export
  push_u32_leb(export_payload, 1U)
  export_payload.push(b't')
  export_payload.push(b'\x01')
  push_u32_leb(export_payload, 0U)
  // memory export
  push_u32_leb(export_payload, 1U)
  export_payload.push(b'm')
  export_payload.push(b'\x02')
  push_u32_leb(export_payload, 0U)
  // global export
  push_u32_leb(export_payload, 1U)
  export_payload.push(b'g')
  export_payload.push(b'\x03')
  push_u32_leb(export_payload, 0U)
  // tag export
  push_u32_leb(export_payload, 3U)
  append_bytes(export_payload, [b't', b'a', b'g'])
  export_payload.push(b'\x04')
  push_u32_leb(export_payload, 0U)
  let sections : Array[Array[Byte]] = [
    make_section(b'\x01', type_payload),
    make_section(b'\x02', import_payload),
    make_section(b'\x07', export_payload),
  ]
  let module_ = parse(build_module(sections))
  assert_eq(module_.imports.length(), 5)
  assert_eq(module_.exports.length(), 5)
}

///|
test "parse type section rec group" {
  let type_payload : Array[Byte] = []
  push_u32_leb(type_payload, 2U)
  append_bytes(type_payload, encode_func_type([], []))
  type_payload.push(b'\x4e')
  push_u32_leb(type_payload, 2U)
  type_payload.push(b'\x5f')
  push_u32_leb(type_payload, 0U)
  type_payload.push(b'\x5e')
  type_payload.push(b'\x7f')
  type_payload.push(b'\x00')
  let sections : Array[Array[Byte]] = [make_section(b'\x01', type_payload)]
  let module_ = parse(build_module(sections))
  assert_eq(module_.types.length(), 3)
}

///|
test "parse valtype variants" {
  let type_payload : Array[Byte] = []
  push_u32_leb(type_payload, 1U)
  let func_type : Array[Byte] = []
  func_type.push(b'\x60')
  push_u32_leb(func_type, 21U)
  append_bytes(func_type, [
    b'\x7f', b'\x7e', b'\x7d', b'\x7c', b'\x7b', b'\x70', b'\x6f', b'\x6e', b'\x6d',
    b'\x6c', b'\x6b', b'\x6a', b'\x69', b'\x71', b'\x72', b'\x73', b'\x74', b'\x63',
    b'\x70', b'\x63', b'\x00', b'\x64', b'\x70', b'\x64', b'\x00',
  ])
  push_u32_leb(func_type, 0U)
  append_bytes(type_payload, func_type)
  let sections : Array[Array[Byte]] = [make_section(b'\x01', type_payload)]
  let module_ = parse(build_module(sections))
  assert_eq(module_.types[0].params.length(), 21)
}

///|
test "parse instructions and sections" {
  let type_payload : Array[Byte] = []
  push_u32_leb(type_payload, 1U)
  append_bytes(type_payload, encode_func_type([], []))
  let func_payload : Array[Byte] = []
  push_u32_leb(func_payload, 3U)
  push_u32_leb(func_payload, 0U)
  push_u32_leb(func_payload, 0U)
  push_u32_leb(func_payload, 0U)
  let table_payload : Array[Byte] = []
  push_u32_leb(table_payload, 2U)
  table_payload.push(b'\x70')
  append_bytes(table_payload, encode_limits(1U, Some(1U)))
  table_payload.push(b'\x40')
  table_payload.push(b'\x00')
  table_payload.push(b'\x64')
  table_payload.push(b'\x70')
  append_bytes(table_payload, encode_limits(1U, Some(1U)))
  table_payload.push(b'\xd2')
  push_u32_leb(table_payload, 1U)
  table_payload.push(b'\x0b')
  let mem_payload : Array[Byte] = []
  push_u32_leb(mem_payload, 1U)
  append_bytes(mem_payload, encode_limits(1U, Some(1U)))
  let global_payload : Array[Byte] = []
  push_u32_leb(global_payload, 1U)
  global_payload.push(b'\x7f')
  global_payload.push(b'\x01')
  emit_i32_const(global_payload, 0U)
  global_payload.push(b'\x0b')
  let elem_payload : Array[Byte] = []
  push_u32_leb(elem_payload, 2U)
  push_u32_leb(elem_payload, 4U)
  emit_i32_const(elem_payload, 0U)
  elem_payload.push(b'\x0b')
  push_u32_leb(elem_payload, 1U)
  elem_payload.push(b'\xd2')
  push_u32_leb(elem_payload, 1U)
  elem_payload.push(b'\x0b')
  push_u32_leb(elem_payload, 5U)
  elem_payload.push(b'\x63')
  elem_payload.push(b'\x70')
  push_u32_leb(elem_payload, 1U)
  elem_payload.push(b'\xd2')
  push_u32_leb(elem_payload, 1U)
  elem_payload.push(b'\x0b')
  let data_payload : Array[Byte] = []
  push_u32_leb(data_payload, 2U)
  push_u32_leb(data_payload, 0U)
  emit_i32_const(data_payload, 0U)
  data_payload.push(b'\x0b')
  push_u32_leb(data_payload, 1U)
  data_payload.push(b'\x01')
  push_u32_leb(data_payload, 1U)
  push_u32_leb(data_payload, 2U)
  append_bytes(data_payload, [b'\x02', b'\x03'])
  let code_payload : Array[Byte] = []
  push_u32_leb(code_payload, 3U)
  let func0 = encode_function_body(encode_locals_i32(1U), build_main_instrs())
  let func1 = encode_function_body(encode_locals_i32(0U), [b'\x0b'])
  let func2_instrs : Array[Byte] = []
  func2_instrs.push(b'\x00')
  func2_instrs.push(b'\x12')
  push_u32_leb(func2_instrs, 1U)
  func2_instrs.push(b'\x13')
  push_u32_leb(func2_instrs, 0U)
  push_u32_leb(func2_instrs, 0U)
  func2_instrs.push(b'\x15')
  push_u32_leb(func2_instrs, 0U)
  func2_instrs.push(b'\x0b')
  let func2 = encode_function_body(encode_locals_i32(0U), func2_instrs)
  append_bytes(code_payload, func0)
  append_bytes(code_payload, func1)
  append_bytes(code_payload, func2)
  let sections : Array[Array[Byte]] = [
    make_section(b'\x01', type_payload),
    make_section(b'\x03', func_payload),
    make_section(b'\x04', table_payload),
    make_section(b'\x05', mem_payload),
    make_section(b'\x06', global_payload),
    make_section(b'\x09', elem_payload),
    make_section(b'\x0a', code_payload),
    make_section(b'\x0b', data_payload),
  ]
  let module_ = parse(build_module(sections))
  assert_eq(module_.codes.length(), 3)
  assert_eq(module_.tables.length(), 2)
  assert_eq(module_.datas.length(), 2)
}
