///|
pub suberror EncodeError {
  Unsupported(String)
} derive(Show)

///|
pub fn encode(module_ : @core.Module) -> Bytes raise EncodeError {
  let out : Array[Byte] = []
  append_bytes(out, [
    0x00U.to_byte(),
    0x61U.to_byte(),
    0x73U.to_byte(),
    0x6dU.to_byte(),
  ])
  append_bytes(out, [
    0x01U.to_byte(),
    0x00U.to_byte(),
    0x00U.to_byte(),
    0x00U.to_byte(),
  ])
  let type_payload = encode_type_section(module_.types)
  push_section(out, 1U, type_payload)
  let import_payload = encode_import_section(module_.imports)
  push_section(out, 2U, import_payload)
  let func_payload = encode_function_section(module_.funcs)
  push_section(out, 3U, func_payload)
  let table_payload = encode_table_section(module_.tables)
  push_section(out, 4U, table_payload)
  let mem_payload = encode_memory_section(module_.mems)
  push_section(out, 5U, mem_payload)
  let global_payload = encode_global_section(module_.globals)
  push_section(out, 6U, global_payload)
  let export_payload = encode_export_section(module_.exports)
  push_section(out, 7U, export_payload)
  let start_payload = encode_start_section(module_.start)
  push_section(out, 8U, start_payload)
  let elem_payload = encode_element_section(module_.elems)
  push_section(out, 9U, elem_payload)
  let code_payload = encode_code_section(module_.codes)
  push_section(out, 10U, code_payload)
  let data_payload = encode_data_section(module_.datas)
  push_section(out, 11U, data_payload)
  Bytes::from_array(out)
}

///|
fn push_section(out : Array[Byte], id : UInt, payload : Array[Byte]) -> Unit {
  guard payload.length() > 0 else { return }
  out.push(id.to_byte())
  append_bytes(out, encode_u32_leb128(payload.length().reinterpret_as_uint()))
  append_bytes(out, payload)
}

///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn append_bytesview(dst : Array[Byte], src : BytesView) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn append_u32_le(dst : Array[Byte], value : UInt) -> Unit {
  dst.push((value & 0xFFU).to_byte())
  dst.push(((value >> 8) & 0xFFU).to_byte())
  dst.push(((value >> 16) & 0xFFU).to_byte())
  dst.push(((value >> 24) & 0xFFU).to_byte())
}

///|
fn append_u64_le(dst : Array[Byte], value : UInt64) -> Unit {
  dst.push((value & 0xFFUL).to_byte())
  dst.push(((value >> 8) & 0xFFUL).to_byte())
  dst.push(((value >> 16) & 0xFFUL).to_byte())
  dst.push(((value >> 24) & 0xFFUL).to_byte())
  dst.push(((value >> 32) & 0xFFUL).to_byte())
  dst.push(((value >> 40) & 0xFFUL).to_byte())
  dst.push(((value >> 48) & 0xFFUL).to_byte())
  dst.push(((value >> 56) & 0xFFUL).to_byte())
}

///|
fn encode_type_section(
  types : Array[@core.FuncType],
) -> Array[Byte] raise EncodeError {
  guard types.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(types.length().reinterpret_as_uint()))
  for func_type in types {
    payload.push(0x60U.to_byte())
    append_bytes(
      payload,
      encode_u32_leb128(func_type.params.length().reinterpret_as_uint()),
    )
    for param in func_type.params {
      payload.push(encode_valtype(param))
    }
    append_bytes(
      payload,
      encode_u32_leb128(func_type.results.length().reinterpret_as_uint()),
    )
    for result in func_type.results {
      payload.push(encode_valtype(result))
    }
  }
  payload
}

///|
fn encode_import_section(
  imports : Array[@core.Import],
) -> Array[Byte] raise EncodeError {
  guard imports.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(imports.length().reinterpret_as_uint()),
  )
  for imp in imports {
    append_name(payload, imp.module_)
    append_name(payload, imp.name)
    match imp.desc {
      Func(type_idx) => {
        payload.push(0x00U.to_byte())
        append_bytes(payload, encode_u32_leb128(type_idx))
      }
      Table(_) => raise EncodeError::Unsupported("table import")
      Mem(mem_type) => {
        payload.push(0x02U.to_byte())
        append_bytes(payload, encode_limits(mem_type.limits))
      }
      Global(global_type) => {
        payload.push(0x03U.to_byte())
        payload.push(encode_valtype(global_type.val_type))
        payload.push(
          if global_type.mutable {
            0x01U.to_byte()
          } else {
            0x00U.to_byte()
          },
        )
      }
      Tag(_) => raise EncodeError::Unsupported("tag import")
    }
  }
  payload
}

///|
fn encode_function_section(funcs : Array[UInt]) -> Array[Byte] {
  guard funcs.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(funcs.length().reinterpret_as_uint()))
  for idx in funcs {
    append_bytes(payload, encode_u32_leb128(idx))
  }
  payload
}

///|
fn encode_table_section(
  tables : Array[@core.TableType],
) -> Array[Byte] raise EncodeError {
  guard tables.length() > 0 else { return [] }
  raise EncodeError::Unsupported("table section")
}

///|
fn encode_memory_section(mems : Array[@core.MemType]) -> Array[Byte] {
  guard mems.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(mems.length().reinterpret_as_uint()))
  for mem_type in mems {
    append_bytes(payload, encode_limits(mem_type.limits))
  }
  payload
}

///|
fn encode_global_section(
  globals : Array[@core.Global],
) -> Array[Byte] raise EncodeError {
  guard globals.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(globals.length().reinterpret_as_uint()),
  )
  for global_ in globals {
    payload.push(encode_valtype(global_.type_.val_type))
    payload.push(
      if global_.type_.mutable {
        0x01U.to_byte()
      } else {
        0x00U.to_byte()
      },
    )
    append_bytes(payload, encode_expr(global_.init))
  }
  payload
}

///|
fn encode_export_section(
  exports : Array[@core.Export],
) -> Array[Byte] raise EncodeError {
  guard exports.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(exports.length().reinterpret_as_uint()),
  )
  for export_ in exports {
    append_name(payload, export_.name)
    match export_.desc {
      Func(idx) => {
        payload.push(0x00U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Table(_) => raise EncodeError::Unsupported("table export")
      Mem(idx) => {
        payload.push(0x02U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Global(idx) => {
        payload.push(0x03U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Tag(_) => raise EncodeError::Unsupported("tag export")
    }
  }
  payload
}

///|
fn encode_start_section(start : UInt?) -> Array[Byte] {
  match start {
    Some(idx) => encode_u32_leb128(idx)
    None => []
  }
}

///|
fn encode_element_section(
  _elems : Array[@core.Elem],
) -> Array[Byte] raise EncodeError {
  guard _elems.length() > 0 else { return [] }
  raise EncodeError::Unsupported("element section")
}

///|
fn encode_code_section(
  codes : Array[@core.Code],
) -> Array[Byte] raise EncodeError {
  guard codes.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(codes.length().reinterpret_as_uint()))
  for code in codes {
    let body : Array[Byte] = []
    append_bytes(body, encode_locals(code.locals))
    append_bytes(body, encode_expr(code.body))
    append_bytes(
      payload,
      encode_u32_leb128(body.length().reinterpret_as_uint()),
    )
    append_bytes(payload, body)
  }
  payload
}

///|
fn encode_data_section(
  datas : Array[@core.Data],
) -> Array[Byte] raise EncodeError {
  guard datas.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(datas.length().reinterpret_as_uint()))
  for data in datas {
    guard data.is_active else {
      raise EncodeError::Unsupported("passive data segment")
    }
    if data.mem_idx != 0U {
      raise EncodeError::Unsupported("data segment with non-zero memory index")
    }
    payload.push(0x00U.to_byte())
    append_bytes(payload, encode_expr(data.offset))
    append_bytes(
      payload,
      encode_u32_leb128(data.init.length().reinterpret_as_uint()),
    )
    append_bytesview(payload, data.init)
  }
  payload
}

///|
fn encode_limits(limits : @core.Limits) -> Array[Byte] {
  let payload : Array[Byte] = []
  match limits.max {
    Some(max) => {
      payload.push(0x01U.to_byte())
      append_bytes(payload, encode_u32_leb128(limits.min))
      append_bytes(payload, encode_u32_leb128(max))
    }
    None => {
      payload.push(0x00U.to_byte())
      append_bytes(payload, encode_u32_leb128(limits.min))
    }
  }
  payload
}

///|
fn encode_locals(
  locals : Array[@core.ValType],
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  if locals.length() == 0 {
    append_bytes(payload, encode_u32_leb128(0U))
    return payload
  }
  let groups : Array[(UInt, @core.ValType)] = []
  let mut current = locals[0]
  let mut count = 1U
  for i in 1..<locals.length() {
    if locals[i] == current {
      count = count + 1U
    } else {
      groups.push((count, current))
      current = locals[i]
      count = 1U
    }
  }
  groups.push((count, current))
  append_bytes(
    payload,
    encode_u32_leb128(groups.length().reinterpret_as_uint()),
  )
  for i in 0..<groups.length() {
    let group = groups[i]
    let cnt = group.0
    let val_type = group.1
    append_bytes(payload, encode_u32_leb128(cnt))
    payload.push(encode_valtype(val_type))
  }
  payload
}

///|
fn encode_expr(expr : @core.Expr) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  for instr in expr.instrs {
    append_bytes(payload, encode_instr(instr))
  }
  payload.push(0x0BU.to_byte())
  payload
}

///|
fn encode_instr(instr : @core.Instr) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match instr {
    Unreachable => payload.push(0x00U.to_byte())
    Nop => payload.push(0x01U.to_byte())
    Drop => payload.push(0x1AU.to_byte())
    Return => payload.push(0x0FU.to_byte())
    Call(idx) => {
      payload.push(0x10U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalGet(idx) => {
      payload.push(0x20U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalSet(idx) => {
      payload.push(0x21U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalTee(idx) => {
      payload.push(0x22U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    GlobalGet(idx) => {
      payload.push(0x23U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    GlobalSet(idx) => {
      payload.push(0x24U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    I32Const(value) => {
      payload.push(0x41U.to_byte())
      append_bytes(payload, encode_i32_leb128(value.reinterpret_as_int()))
    }
    I64Const(value) => {
      payload.push(0x42U.to_byte())
      append_bytes(payload, encode_i64_leb128(value.reinterpret_as_int64()))
    }
    F32Const(value) => {
      payload.push(0x43U.to_byte())
      append_u32_le(payload, value.reinterpret_as_uint())
    }
    F64Const(value) => {
      payload.push(0x44U.to_byte())
      append_u64_le(payload, value.reinterpret_as_uint64())
    }
    I32Add => payload.push(0x6AU.to_byte())
    I32Sub => payload.push(0x6BU.to_byte())
    I32Mul => payload.push(0x6CU.to_byte())
    _ => raise EncodeError::Unsupported("instruction \{instr}")
  }
  payload
}

///|
fn encode_valtype(val_type : @core.ValType) -> Byte raise EncodeError {
  match val_type {
    I32 => 0x7FU.to_byte()
    I64 => 0x7EU.to_byte()
    F32 => 0x7DU.to_byte()
    F64 => 0x7CU.to_byte()
    V128 => 0x7BU.to_byte()
    FuncRef => 0x70U.to_byte()
    ExternRef => 0x6FU.to_byte()
    _ => raise EncodeError::Unsupported("valtype \{val_type}")
  }
}

///|
fn append_name(dst : Array[Byte], name : Bytes) -> Unit {
  append_bytes(dst, encode_u32_leb128(name.length().reinterpret_as_uint()))
  for b in name {
    dst.push(b)
  }
}

///|
fn encode_u32_leb128(value : UInt) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let mut byte = (v & 0x7FU).to_byte()
    v = v >> 7
    if v != 0U {
      byte = (byte.to_uint() | 0x80U).to_byte()
      out.push(byte)
    } else {
      out.push(byte)
      break
    }
  }
  out
}

///|
fn encode_i32_leb128(value : Int) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let byte_val = v & 0x7F
    let byte = byte_val.reinterpret_as_uint().to_byte()
    let sign = (byte_val & 0x40) != 0
    v = v >> 7
    let done = (v == 0 && not(sign)) || (v == -1 && sign)
    if done {
      out.push(byte)
      break
    } else {
      out.push((byte.to_uint() | 0x80U).to_byte())
    }
  }
  out
}

///|
fn encode_i64_leb128(value : Int64) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let byte_val = v & 0x7FL
    let byte = byte_val.reinterpret_as_uint64().to_uint().to_byte()
    let sign = (byte_val & 0x40L) != 0L
    v = v >> 7
    let done = (v == 0L && not(sign)) || (v == -1L && sign)
    if done {
      out.push(byte)
      break
    } else {
      out.push((byte.to_uint() | 0x80U).to_byte())
    }
  }
  out
}
