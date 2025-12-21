///|
fn make_parser(bytes : Array[Byte]) -> Parser {
  Parser::new(Bytes::from_array(bytes))
}

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
fn emit_i32_const(buf : Array[Byte], value : UInt) -> Unit {
  buf.push(b'\x41')
  push_u32_leb(buf, value)
}

///|
test "parse expr invalid end marker" {
  let parser = make_parser([b'\x05'])
  let mut saw_error = false
  let _ = parse_expr(parser) catch {
    _ => {
      saw_error = true
      { instrs: [] }
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse instr unknown opcode" {
  let parser = make_parser([])
  let mut saw_error = false
  let _ = parse_instr(parser, b'\xff') catch {
    _ => {
      saw_error = true
      Nop
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse prefix fc errors" {
  let bytes_init : Array[Byte] = []
  push_u32_leb(bytes_init, 0x08U)
  push_u32_leb(bytes_init, 0U)
  push_u32_leb(bytes_init, 1U)
  let mut saw_error = false
  let _ = parse_instr_prefix_fc(make_parser(bytes_init)) catch {
    _ => {
      saw_error = true
      Nop
    }
  }
  assert_eq(saw_error, true)
  let bytes_copy : Array[Byte] = []
  push_u32_leb(bytes_copy, 0x0aU)
  push_u32_leb(bytes_copy, 1U)
  push_u32_leb(bytes_copy, 0U)
  saw_error = false
  let _ = parse_instr_prefix_fc(make_parser(bytes_copy)) catch {
    _ => {
      saw_error = true
      Nop
    }
  }
  assert_eq(saw_error, true)
  let bytes_fill : Array[Byte] = []
  push_u32_leb(bytes_fill, 0x0bU)
  push_u32_leb(bytes_fill, 1U)
  saw_error = false
  let _ = parse_instr_prefix_fc(make_parser(bytes_fill)) catch {
    _ => {
      saw_error = true
      Nop
    }
  }
  assert_eq(saw_error, true)
  let bytes_unknown : Array[Byte] = []
  push_u32_leb(bytes_unknown, 0x11U)
  saw_error = false
  let _ = parse_instr_prefix_fc(make_parser(bytes_unknown)) catch {
    _ => {
      saw_error = true
      Nop
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse instr control variants" {
  let instr = parse_instr_control(make_parser([b'\x40', b'\x0b']), b'\x06')
  assert_eq(instr is Some(_), true)
  let instr = parse_instr_control(make_parser([b'\x00']), b'\x07')
  assert_eq(instr is Some(_), true)
  let instr = parse_instr_control(make_parser([b'\x00']), b'\x08')
  assert_eq(instr is Some(_), true)
  let instr = parse_instr_control(make_parser([b'\x00']), b'\x09')
  assert_eq(instr is Some(_), true)
  let instr = parse_instr_control(make_parser([]), b'\x0a')
  assert_eq(instr is Some(_), true)
  let instr = parse_instr_control(make_parser([]), b'\x0b')
  assert_eq(instr is Some(_), true)
  let bytes_try_table : Array[Byte] = []
  bytes_try_table.push(b'\x40')
  push_u32_leb(bytes_try_table, 5U)
  bytes_try_table.push(b'\x00')
  push_u32_leb(bytes_try_table, 0U)
  push_u32_leb(bytes_try_table, 0U)
  bytes_try_table.push(b'\x01')
  push_u32_leb(bytes_try_table, 0U)
  push_u32_leb(bytes_try_table, 0U)
  bytes_try_table.push(b'\x02')
  push_u32_leb(bytes_try_table, 0U)
  bytes_try_table.push(b'\x03')
  push_u32_leb(bytes_try_table, 0U)
  bytes_try_table.push(b'\x04')
  bytes_try_table.push(b'\x0b')
  let instr = parse_instr_control(make_parser(bytes_try_table), b'\x1f')
  assert_eq(instr is Some(_), true)
}

///|
test "parse blocktype variants" {
  let instr = parse_instr_control(make_parser([b'\x7e', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(I64), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x7d', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(F32), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x7c', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(F64), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x7b', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(V128), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x70', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(FuncRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6f', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(ExternRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6e', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(AnyRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6d', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(EqRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6c', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(I31Ref), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6b', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(StructRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x6a', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(ArrayRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x69', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(ExnRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x71', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(NullRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x72', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(NullExternRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x73', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(NullFuncRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x74', b'\x0b']), b'\x02')
  match instr {
    Some(Block(Value(NullExnRef), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(
    make_parser([b'\x63', b'\x70', b'\x0b']),
    b'\x02',
  )
  match instr {
    Some(Block(Value(Ref(Func, true)), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(
    make_parser([b'\x64', b'\x70', b'\x0b']),
    b'\x02',
  )
  match instr {
    Some(Block(Value(Ref(Func, false)), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_control(make_parser([b'\x01', b'\x0b']), b'\x02')
  match instr {
    Some(Block(TypeIndex(1), _)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
}

///|
test "parse instr if without else" {
  let bytes : Array[Byte] = []
  bytes.push(b'\x40')
  bytes.push(b'\x01')
  bytes.push(b'\x0b')
  let instr = parse_instr_control(make_parser(bytes), b'\x04')
  match instr {
    Some(If(_, _, else_instrs)) => assert_eq(else_instrs.length(), 0)
    _ => assert_eq(true, false)
  }
}

///|
test "parse instr numeric i64 const" {
  let instr = parse_instr_numeric(make_parser([b'\x00']), b'\x42')
  match instr {
    Some(I64Const(value)) => assert_eq(value, 0UL)
    _ => assert_eq(true, false)
  }
}

///|
test "parse instr reference variants" {
  let instr = parse_instr_reference(make_parser([b'\x6f']), b'\xd0')
  match instr {
    Some(RefNull(Extern)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x6e']), b'\xd0')
  match instr {
    Some(RefNull(Any)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x6d']), b'\xd0')
  match instr {
    Some(RefNull(Eq)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x6c']), b'\xd0')
  match instr {
    Some(RefNull(I31)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x6b']), b'\xd0')
  match instr {
    Some(RefNull(Struct)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x6a']), b'\xd0')
  match instr {
    Some(RefNull(Array)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x69']), b'\xd0')
  match instr {
    Some(RefNull(Exn)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x71']), b'\xd0')
  match instr {
    Some(RefNull(None)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x72']), b'\xd0')
  match instr {
    Some(RefNull(NoExtern)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x73']), b'\xd0')
  match instr {
    Some(RefNull(NoFunc)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x74']), b'\xd0')
  match instr {
    Some(RefNull(NoExn)) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
  let instr = parse_instr_reference(make_parser([b'\x01']), b'\xd0')
  match instr {
    Some(RefNull(TypeIndex(1))) => assert_eq(true, true)
    _ => assert_eq(true, false)
  }
}

///|
test "parse reader errors" {
  let empty_view = Bytes::from_array([]).sub()
  let mut saw_error = false
  let _ = Parser::new(Bytes::from_array([])).next_byte() catch {
    _ => {
      saw_error = true
      b'\x00'
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = Parser::new(Bytes::from_array([b'\x00'])).read_bytes(2U) catch {
    _ => {
      saw_error = true
      empty_view
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let invalid_len = (-1).reinterpret_as_uint()
  let _ = Parser::new(Bytes::from_array([])).read_bytes(invalid_len) catch {
    _ => {
      saw_error = true
      empty_view
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let bytes_u32 : Array[Byte] = [b'\x80', b'\x80', b'\x80', b'\x80', b'\x10']
  let _ = Parser::new(Bytes::from_array(bytes_u32)).read_u32_leb128() catch {
    _ => {
      saw_error = true
      0U
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let bytes_i32 : Array[Byte] = [b'\x80', b'\x80', b'\x80', b'\x80', b'\x80']
  let _ = Parser::new(Bytes::from_array(bytes_i32)).read_i32_leb128() catch {
    _ => {
      saw_error = true
      0
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let bytes_i64 : Array[Byte] = [
    b'\x80', b'\x80', b'\x80', b'\x80', b'\x80', b'\x80', b'\x80', b'\x80', b'\x80',
    b'\x80',
  ]
  let _ = Parser::new(Bytes::from_array(bytes_i64)).read_i64_leb128() catch {
    _ => {
      saw_error = true
      0L
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = Parser::new(Bytes::from_array([b'\x00', b'\x00', b'\x00'])).read_f32() catch {
    _ => {
      saw_error = true
      0.0
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = Parser::new(
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    ]),
  ).read_f64() catch {
    _ => {
      saw_error = true
      0.0
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse leb128 sign extension" {
  let value = Parser::new(Bytes::from_array([b'\x7f'])).read_i32_leb128()
  assert_eq(value, -1)
  let value64 = Parser::new(Bytes::from_array([b'\x7f'])).read_i64_leb128()
  assert_eq(value64, -1L)
  let mut saw_error = false
  let _ = Parser::new(
    Bytes::from_array([b'\x80', b'\x80', b'\x80', b'\x80', b'\x80']),
  ).read_u32_leb128() catch {
    _ => {
      saw_error = true
      0U
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse memarg with memory index" {
  let parser = Parser::new(Bytes::from_array([b'\x40', b'\x01', b'\x00']))
  let (align, offset, mem_idx) = parser.read_memarg()
  assert_eq(align, 0U)
  assert_eq(offset, 0U)
  assert_eq(mem_idx, 1U)
}

///|
test "parse reftype variants" {
  let (ref_type, nullable) = Parser::new(Bytes::from_array([b'\x63', b'\x00'])).read_reftype_with_nullability()
  assert_eq(nullable, true)
  assert_eq(ref_type, TypeIndex(0))
  let (ref_type, nullable) = Parser::new(Bytes::from_array([b'\x64', b'\x70'])).read_reftype_with_nullability()
  assert_eq(nullable, false)
  assert_eq(ref_type, Func)
  let (ref_type, nullable) = Parser::new(Bytes::from_array([b'\x63', b'\x70'])).read_reftype_with_nullability()
  assert_eq(nullable, true)
  assert_eq(ref_type, Func)
  let (ref_type, nullable) = Parser::new(Bytes::from_array([b'\x64', b'\x01'])).read_reftype_with_nullability()
  assert_eq(nullable, false)
  assert_eq(ref_type, TypeIndex(1))
  let (ref_type, nullable) = Parser::new(Bytes::from_array([b'\x01'])).read_reftype_with_nullability()
  assert_eq(nullable, true)
  assert_eq(ref_type, TypeIndex(1))
  let mut saw_error = false
  let _ = Parser::new(Bytes::from_array([b'\x62'])).read_reftype_with_nullability() catch {
    _ => {
      saw_error = true
      (Func, true)
    }
  }
  assert_eq(saw_error, true)
  let ref_type = Parser::new(Bytes::from_array([b'\x63', b'\x70'])).read_reftype()
  assert_eq(ref_type, Func)
  let ref_type = Parser::new(Bytes::from_array([b'\x63', b'\x01'])).read_reftype()
  assert_eq(ref_type, TypeIndex(1))
  let ref_type = Parser::new(Bytes::from_array([b'\x64', b'\x70'])).read_reftype()
  assert_eq(ref_type, Func)
  let ref_type = Parser::new(Bytes::from_array([b'\x64', b'\x01'])).read_reftype()
  assert_eq(ref_type, TypeIndex(1))
  let ref_type = Parser::new(Bytes::from_array([b'\x01'])).read_reftype()
  assert_eq(ref_type, TypeIndex(1))
  let ref_type = Parser::new(Bytes::from_array([b'\x40'])).read_reftype()
  assert_eq(ref_type, Func)
  saw_error = false
  let _ = Parser::new(Bytes::from_array([b'\x62'])).read_reftype() catch {
    _ => {
      saw_error = true
      Func
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse invalid valtype" {
  let mut saw_error = false
  let _ = Parser::new(Bytes::from_array([b'\x62'])).read_valtype() catch {
    _ => {
      saw_error = true
      I32
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse main header errors" {
  let mut saw_error = false
  let _ = parse(
    Bytes::from_array([
      b'\x01', b'\x02', b'\x03', b'\x04', b'\x01', b'\x00', b'\x00', b'\x00',
    ]),
  ) catch {
    _ => {
      saw_error = true
      {
        types: [],
        funcs: [],
        tables: [],
        mems: [],
        globals: [],
        elems: [],
        datas: [],
        start: None,
        imports: [],
        exports: [],
        codes: [],
      }
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = parse(
    Bytes::from_array([
      b'\x00', b'\x61', b'\x73', b'\x6d', b'\x00', b'\x00', b'\x00', b'\x00',
    ]),
  ) catch {
    _ => {
      saw_error = true
      {
        types: [],
        funcs: [],
        tables: [],
        mems: [],
        globals: [],
        elems: [],
        datas: [],
        start: None,
        imports: [],
        exports: [],
        codes: [],
      }
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse main section skips" {
  let bytes : Array[Byte] = [
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
  ]
  bytes.push(b'\x00')
  push_u32_leb(bytes, 0U)
  bytes.push(b'\x63')
  push_u32_leb(bytes, 0U)
  bytes.push(b'\x08')
  push_u32_leb(bytes, 1U)
  push_u32_leb(bytes, 0U)
  let mut saw_error = false
  let _ = parse(Bytes::from_array(bytes)) catch {
    _ => {
      saw_error = true
      {
        types: [],
        funcs: [],
        tables: [],
        mems: [],
        globals: [],
        elems: [],
        datas: [],
        start: None,
        imports: [],
        exports: [],
        codes: [],
      }
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse type section invalid tag" {
  let bytes : Array[Byte] = []
  push_u32_leb(bytes, 1U)
  bytes.push(b'\x00')
  let mut saw_error = false
  let _ = parse_type_section(make_parser(bytes)) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse type section subtypes" {
  let bytes : Array[Byte] = []
  let empty_sig : Array[Byte] = []
  push_u32_leb(bytes, 2U)
  bytes.push(b'\x4f')
  push_u32_leb(bytes, 1U)
  push_u32_leb(bytes, 0U)
  append_bytes(bytes, encode_func_type(empty_sig, empty_sig))
  bytes.push(b'\x50')
  push_u32_leb(bytes, 1U)
  push_u32_leb(bytes, 0U)
  append_bytes(bytes, encode_func_type(empty_sig, empty_sig))
  let types = parse_type_section(make_parser(bytes))
  assert_eq(types.length(), 2)
}

///|
test "parse type section invalid composite tag" {
  let bytes : Array[Byte] = []
  push_u32_leb(bytes, 1U)
  bytes.push(b'\x4e')
  push_u32_leb(bytes, 1U)
  bytes.push(b'\x5d')
  let mut saw_error = false
  let _ = parse_type_section(make_parser(bytes)) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse type section results and struct" {
  let bytes : Array[Byte] = []
  let params : Array[Byte] = [b'\x7f']
  let results : Array[Byte] = [b'\x7e']
  push_u32_leb(bytes, 2U)
  append_bytes(bytes, encode_func_type(params, results))
  bytes.push(b'\x4e')
  push_u32_leb(bytes, 1U)
  bytes.push(b'\x5f')
  push_u32_leb(bytes, 1U)
  bytes.push(b'\x7f')
  bytes.push(b'\x00')
  let types = parse_type_section(make_parser(bytes))
  assert_eq(types.length(), 2)
}

///|
test "parse import/export invalid descriptor" {
  let import_bytes : Array[Byte] = []
  push_u32_leb(import_bytes, 1U)
  push_u32_leb(import_bytes, 0U)
  push_u32_leb(import_bytes, 0U)
  import_bytes.push(b'\x05')
  let mut saw_error = false
  let _ = parse_import_section(make_parser(import_bytes)) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
  let export_bytes : Array[Byte] = []
  push_u32_leb(export_bytes, 1U)
  push_u32_leb(export_bytes, 0U)
  export_bytes.push(b'\x05')
  saw_error = false
  let _ = parse_export_section(make_parser(export_bytes)) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
}

///|
test "parse element and data section variants" {
  let elem_bytes : Array[Byte] = []
  push_u32_leb(elem_bytes, 1U)
  push_u32_leb(elem_bytes, 2U)
  push_u32_leb(elem_bytes, 0U)
  emit_i32_const(elem_bytes, 0U)
  elem_bytes.push(b'\x0b')
  elem_bytes.push(b'\x00')
  push_u32_leb(elem_bytes, 1U)
  push_u32_leb(elem_bytes, 0U)
  let elems = parse_element_section(make_parser(elem_bytes))
  assert_eq(elems.length(), 1)
  let data_bytes : Array[Byte] = []
  push_u32_leb(data_bytes, 2U)
  push_u32_leb(data_bytes, 2U)
  push_u32_leb(data_bytes, 0U)
  emit_i32_const(data_bytes, 0U)
  data_bytes.push(b'\x0b')
  push_u32_leb(data_bytes, 1U)
  data_bytes.push(b'\x00')
  push_u32_leb(data_bytes, 3U)
  emit_i32_const(data_bytes, 0U)
  data_bytes.push(b'\x0b')
  push_u32_leb(data_bytes, 1U)
  data_bytes.push(b'\x01')
  let datas = parse_data_section(make_parser(data_bytes))
  assert_eq(datas.length(), 2)
}

///|
test "parse element section more flags" {
  let elem_bytes : Array[Byte] = []
  push_u32_leb(elem_bytes, 2U)
  push_u32_leb(elem_bytes, 1U)
  elem_bytes.push(b'\x00')
  push_u32_leb(elem_bytes, 1U)
  push_u32_leb(elem_bytes, 0U)
  push_u32_leb(elem_bytes, 6U)
  push_u32_leb(elem_bytes, 0U)
  emit_i32_const(elem_bytes, 0U)
  elem_bytes.push(b'\x0b')
  elem_bytes.push(b'\x70')
  push_u32_leb(elem_bytes, 1U)
  elem_bytes.push(b'\xd0')
  elem_bytes.push(b'\x70')
  elem_bytes.push(b'\x0b')
  let elems = parse_element_section(make_parser(elem_bytes))
  assert_eq(elems.length(), 2)
}
