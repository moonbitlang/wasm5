///|
priv struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
fn Parser::new(bytes : Bytes) -> Parser {
  { bytes, pos: 0 }
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn Parser::peek(self : Parser) -> Byte raise ParseError {
  if self.pos < self.bytes.length() {
    self.bytes.unsafe_get(self.pos)
  } else {
    raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_byte(self : Parser) -> Byte raise ParseError {
  if self.pos < self.bytes.length() {
    let byte = self.bytes.unsafe_get(self.pos)
    self.pos = self.pos + 1
    byte
  } else {
    raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_bytes(self : Parser, n : UInt) -> BytesView raise ParseError {
  let n_int = UInt::reinterpret_as_int(n)
  guard n_int >= 0 else {
    raise ParseError::InvalidFormat("bytes length beyond Int max value")
  }
  if self.pos + n_int <= self.bytes.length() {
    let result = self.bytes[self.pos:self.pos + n_int]
    self.pos = self.pos + n_int
    result
  } else {
    raise ParseError::UnexpectedEof
  }
}

// LEB128 decoding

///|
fn Parser::read_u32_leb128(self : Parser) -> UInt raise ParseError {
  fn read_loop(shift : Int, result : UInt) -> UInt raise ParseError {
    let byte = self.read_byte()
    let value = byte.land(0x7f).to_uint() << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      new_result
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  read_loop(0, 0)
}

///|
fn Parser::read_i32_leb128(self : Parser) -> Int raise ParseError {
  // Returns (result, shift, last_byte) where last_byte is the final 7-bit chunk
  fn read_loop(shift : Int, result : Int) -> (Int, Int, Int) raise ParseError {
    let byte = self.read_byte().to_int()
    let value = (byte & 0x7f) << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      (new_result, shift, byte & 0x7f)
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  let (result, shift, last_byte) = read_loop(0, 0)
  // Sign extend if the sign bit (bit 6 of last 7-bit chunk) is set
  if shift < 32 && (last_byte & 0x40) != 0 {
    result | (-1 << (shift + 7))
  } else {
    result
  }
}

///|
fn Parser::read_i64_leb128(self : Parser) -> Int64 raise ParseError {
  // Returns (result, shift, last_byte) where last_byte is the final 7-bit chunk
  fn read_loop(
    shift : Int,
    result : Int64,
  ) -> (Int64, Int, Int) raise ParseError {
    let byte = self.read_byte()
    let value = byte.land(0x7f).to_int64() << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      (new_result, shift, byte.land(0x7f).to_int())
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  let (result, shift, last_byte) = read_loop(0, 0L)
  // Sign extend if the sign bit (bit 6 of last 7-bit chunk) is set
  if shift < 64 && (last_byte & 0x40) != 0 {
    result | (-1L << (shift + 7))
  } else {
    result
  }
}

///|
fn Parser::read_f32(self : Parser) -> Float raise ParseError {
  match self.bytes[self.pos:] {
    [u32le(bits), ..] => {
      self.pos = self.pos + 4
      Float::reinterpret_from_uint(bits)
    }
    _ => raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_f64(self : Parser) -> Double raise ParseError {
  match self.bytes[self.pos:] {
    [u64le(bits), ..] => {
      self.pos = self.pos + 8
      UInt64::reinterpret_as_double(bits)
    }
    _ => raise ParseError::UnexpectedEof
  }
}

// Read name (length-prefixed UTF-8 string)

///|
fn Parser::read_name(self : Parser) -> String raise ParseError {
  let len = self.read_u32_leb128()
  let bytes = self.read_bytes(len)
  // For now, assume UTF-8 is valid
  bytes.to_string()
}

// Parse value type

///|
fn Parser::read_valtype(self : Parser) -> ValType raise {
  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128
    0x70 => FuncRef
    0x6F => ExternRef
    _ =>
      raise ValidationError::TypeMismatch(
        "invalid value type: 0x\{byte.to_string()}",
      )
  }
}

// Parse reference type

///|
fn Parser::read_reftype(self : Parser) -> RefType raise {
  let byte = self.read_byte()
  match byte {
    0x70 => FuncRef
    0x6F => ExternRef
    _ =>
      raise ValidationError::TypeMismatch(
        "invalid reference type: 0x\{byte.to_string()}",
      )
  }
}

// Parse limits

///|
fn Parser::read_limits(self : Parser) -> Limits raise ParseError {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}

// Section parsers

///|
fn parse_type_section(parser : Parser) -> Array[FuncType] raise {
  let count = parser.read_u32_leb128()
  let types = []
  for i in 0U..<count {
    let tag = parser.read_byte()
    if tag != 0x60 {
      raise ValidationError::TypeMismatch(
        "expected function type tag 0x60, got 0x\{tag.to_string()}",
      )
    }

    // Read params
    let param_count = parser.read_u32_leb128()
    let params = []
    for j in 0U..<param_count {
      params.push(parser.read_valtype())
    }

    // Read results
    let result_count = parser.read_u32_leb128()
    let results = []
    for j in 0U..<result_count {
      results.push(parser.read_valtype())
    }
    types.push({ params, results })
  }
  types
}

///|
fn parse_import_section(parser : Parser) -> Array[Import] raise {
  let count = parser.read_u32_leb128()
  let imports = []
  for i in 0U..<count {
    let module_ = parser.read_name()
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc = match desc_tag {
      0x00 => ImportDesc::Func(parser.read_u32_leb128())
      0x01 => {
        let elem_type = parser.read_reftype()
        let limits = parser.read_limits()
        ImportDesc::Table({ elem_type, limits })
      }
      0x02 => ImportDesc::Mem({ limits: parser.read_limits() })
      0x03 => {
        let val_type = parser.read_valtype()
        let mutable = parser.read_byte() == 0x01
        ImportDesc::Global({ val_type, mutable })
      }
      _ =>
        raise ValidationError::TypeMismatch(
          "invalid import descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    imports.push({ module_, name, desc })
  }
  imports
}

///|
fn parse_function_section(parser : Parser) -> Array[UInt] raise ParseError {
  let count = parser.read_u32_leb128()
  let funcs = []
  for i in 0U..<count {
    funcs.push(parser.read_u32_leb128())
  }
  funcs
}

///|
fn parse_table_section(parser : Parser) -> Array[TableType] raise {
  let count = parser.read_u32_leb128()
  let tables = []
  for i in 0U..<count {
    let elem_type = parser.read_reftype()
    let limits = parser.read_limits()
    tables.push({ elem_type, limits })
  }
  tables
}

///|
fn parse_memory_section(parser : Parser) -> Array[MemType] raise ParseError {
  let count = parser.read_u32_leb128()
  let mems = []
  for i in 0U..<count {
    let limits = parser.read_limits()
    mems.push({ limits, })
  }
  mems
}

///|
fn parse_global_section(parser : Parser) -> Array[Global] raise {
  let count = parser.read_u32_leb128()
  let globals = []
  for i in 0U..<count {
    let val_type = parser.read_valtype()
    let mutable = parser.read_byte() == 0x01
    let init = parse_expr(parser)
    globals.push({ type_: { val_type, mutable }, init })
  }
  globals
}

///|
fn parse_export_section(parser : Parser) -> Array[Export] raise {
  let count = parser.read_u32_leb128()
  let exports = []
  for i in 0U..<count {
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc = match desc_tag {
      0x00 => ExportDesc::Func(parser.read_u32_leb128())
      0x01 => ExportDesc::Table(parser.read_u32_leb128())
      0x02 => ExportDesc::Mem(parser.read_u32_leb128())
      0x03 => ExportDesc::Global(parser.read_u32_leb128())
      _ =>
        raise ValidationError::TypeMismatch(
          "invalid export descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    exports.push({ name, desc })
  }
  exports
}

///|
fn parse_element_section(parser : Parser) -> Array[Elem] raise {
  let count = parser.read_u32_leb128()
  let elems = []
  for i in 0U..<count {
    let flags = parser.read_u32_leb128()
    // Element segment format depends on flags:
    // flags=0: active, table 0, offset expr, vec of funcidx
    // flags=1: passive, elemkind, vec of funcidx
    // flags=2: active, tableidx, offset expr, elemkind, vec of funcidx
    // flags=3: declarative, elemkind, vec of funcidx
    // flags=4: active, table 0, offset expr, vec of expr
    // flags=5: passive, reftype, vec of expr
    // flags=6: active, tableidx, offset expr, reftype, vec of expr
    // flags=7: declarative, reftype, vec of expr
    let table_idx : UInt = match flags {
      0 | 4 => 0U // implicit table 0
      2 | 6 => parser.read_u32_leb128() // explicit table index
      _ => 0U // passive/declarative segments have no table
    }
    let offset : Expr = match flags {
      0 | 2 | 4 | 6 => parse_expr(parser) // active segments have offset
      _ => { instrs: [I32Const(0U)] } // dummy offset for passive/declarative
    }
    // Read elemkind or reftype for certain flags
    match flags {
      1 | 3 => {
        let _ = parser.read_byte()
        // elemkind (0x00 = funcref)
      }
      2 => {
        let _ = parser.read_byte()
        // elemkind
      }
      5 | 7 => {
        let _ = parser.read_reftype()
        // reftype
      }
      6 => {
        let _ = parser.read_reftype()
        // reftype
      }
      _ => ()
    }
    // Read init vector
    let init_count = parser.read_u32_leb128()
    let init = []
    let uses_exprs = flags >= 4
    for j in 0U..<init_count {
      if uses_exprs {
        // Parse expression (ref.func idx or ref.null)
        let expr = parse_expr(parser)
        // Extract function index from expression if it's ref.func
        match expr.instrs.get(0) {
          Some(RefFunc(idx)) => init.push(idx)
          _ => init.push(0U) // ref.null or other
        }
      } else {
        init.push(parser.read_u32_leb128())
      }
    }
    elems.push({ table_idx, offset, init })
  }
  elems
}

///|
fn parse_code_section(parser : Parser) -> Array[Code] raise {
  let count = parser.read_u32_leb128()
  let codes = []
  for i in 0U..<count {
    let _code_size = parser.read_u32_leb128()

    // Parse locals
    let locals_count = parser.read_u32_leb128()
    let locals = []
    for j in 0U..<locals_count {
      let n = parser.read_u32_leb128()
      let val_type = parser.read_valtype()
      for k in 0U..<n {
        locals.push(val_type)
      }
    }

    // Parse body
    let body = parse_expr(parser)
    codes.push({ locals, body, compiled: None })
  }
  codes
}

///|
fn parse_data_section(parser : Parser) -> Array[Data] raise {
  let count = parser.read_u32_leb128()
  let datas = []
  for i in 0U..<count {
    let mem_idx = parser.read_u32_leb128()
    let offset = parse_expr(parser)
    let init_len = parser.read_u32_leb128()
    let init = parser.read_bytes(init_len)
    datas.push({ mem_idx, offset, init })
  }
  datas
}

// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> Expr raise {
  let instrs = parse_instrs(parser)
  { instrs, }
}

// Parse instructions until 0x0B (end marker)

///|
fn parse_instrs(parser : Parser) -> Array[Instr] raise {
  fn read_loop(instrs : Array[Instr]) -> Array[Instr] raise {
    let opcode = parser.read_byte()
    if opcode == 0x0B {
      // End marker (0x0B)
      instrs
    } else if opcode == 0x05 {
      // Else marker (0x05) - put it back for the if parser to handle
      parser.pos = parser.pos - 1
      instrs
    } else {
      instrs.push(parse_instr(parser, opcode))
      read_loop(instrs)
    }
  }

  read_loop([])
}

// Parse a single instruction

///|
fn parse_instr(parser : Parser, opcode : Byte) -> Instr raise {
  match opcode {
    // Control instructions
    0x00 => Unreachable
    0x01 => Nop
    0x02 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      Block(blocktype, instrs)
    }
    0x03 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      Loop(blocktype, instrs)
    }
    0x04 => {
      let blocktype = parse_blocktype(parser)
      let then_instrs = parse_instrs(parser)
      // Check if there's an else
      if parser.peek() == 0x05 {
        let _ = parser.read_byte() // consume 0x05
        let else_instrs = parse_instrs(parser)
        If(blocktype, then_instrs, else_instrs)
      } else {
        If(blocktype, then_instrs, [])
      }
    }
    0x0C => Br(parser.read_u32_leb128())
    0x0D => BrIf(parser.read_u32_leb128())
    0x0E => {
      let count = parser.read_u32_leb128()
      let labels = []
      for i in 0U..<count {
        labels.push(parser.read_u32_leb128())
      }
      let default_label = parser.read_u32_leb128()
      BrTable(labels, default_label)
    }
    0x0F => Return
    0x10 => Call(parser.read_u32_leb128())
    0x11 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      CallIndirect(type_idx, table_idx)
    }

    // Parametric instructions
    0x1A => Drop
    0x1B => Select
    0x1C => {
      // select t* - typed select with value type vector
      // Read the number of types (should be 1 for MVP)
      let num_types = parser.read_u32_leb128()
      // Read and discard the type(s) - we treat it the same as untyped select at runtime
      for _ in 0U..<num_types {
        let _ = parser.read_valtype()
      }
      Select
    }

    // Variable instructions
    0x20 => LocalGet(parser.read_u32_leb128())
    0x21 => LocalSet(parser.read_u32_leb128())
    0x22 => LocalTee(parser.read_u32_leb128())
    0x23 => GlobalGet(parser.read_u32_leb128())
    0x24 => GlobalSet(parser.read_u32_leb128())

    // Memory instructions
    0x28 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Load(align, offset)
    }
    0x29 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load(align, offset)
    }
    0x2A => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      F32Load(align, offset)
    }
    0x2B => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      F64Load(align, offset)
    }
    0x2C => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Load8S(align, offset)
    }
    0x2D => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Load8U(align, offset)
    }
    0x2E => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Load16S(align, offset)
    }
    0x2F => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Load16U(align, offset)
    }
    0x30 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load8S(align, offset)
    }
    0x31 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load8U(align, offset)
    }
    0x32 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load16S(align, offset)
    }
    0x33 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load16U(align, offset)
    }
    0x34 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load32S(align, offset)
    }
    0x35 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Load32U(align, offset)
    }
    0x36 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Store(align, offset)
    }
    0x37 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Store(align, offset)
    }
    0x38 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      F32Store(align, offset)
    }
    0x39 => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      F64Store(align, offset)
    }
    0x3A => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Store8(align, offset)
    }
    0x3B => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I32Store16(align, offset)
    }
    0x3C => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Store8(align, offset)
    }
    0x3D => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Store16(align, offset)
    }
    0x3E => {
      let align = parser.read_u32_leb128()
      let offset = parser.read_u32_leb128()
      I64Store32(align, offset)
    }
    0x25 => {
      let table_idx = parser.read_u32_leb128()
      TableGet(table_idx)
    }
    0x26 => {
      let table_idx = parser.read_u32_leb128()
      TableSet(table_idx)
    }
    0x3F => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      MemorySize(mem_idx.to_uint())
    }
    0x40 => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      MemoryGrow(mem_idx.to_uint())
    }

    // Reference instructions
    0xD0 => {
      // ref.null heaptype
      let heap_type = parser.read_byte()
      let ref_type : RefType = match heap_type {
        0x70 => RefType::FuncRef
        0x6F => RefType::ExternRef
        _ => RefType::FuncRef // Default to funcref for other types
      }
      RefNull(ref_type)
    }
    0xD1 => RefIsNull // ref.is_null
    0xD2 => {
      // ref.func funcidx
      let func_idx = parser.read_u32_leb128()
      RefFunc(func_idx)
    }

    // Numeric instructions - constants
    0x41 => I32Const(parser.read_i32_leb128().reinterpret_as_uint())
    0x42 => I64Const(parser.read_i64_leb128().reinterpret_as_uint64())
    0x43 => F32Const(parser.read_f32())
    0x44 => F64Const(parser.read_f64())

    // i32 operations
    0x45 => I32Eqz
    0x46 => I32Eq
    0x47 => I32Ne
    0x48 => I32LtS
    0x49 => I32LtU
    0x4A => I32GtS
    0x4B => I32GtU
    0x4C => I32LeS
    0x4D => I32LeU
    0x4E => I32GeS
    0x4F => I32GeU

    // i64 operations
    0x50 => I64Eqz
    0x51 => I64Eq
    0x52 => I64Ne
    0x53 => I64LtS
    0x54 => I64LtU
    0x55 => I64GtS
    0x56 => I64GtU
    0x57 => I64LeS
    0x58 => I64LeU
    0x59 => I64GeS
    0x5A => I64GeU

    // f32 operations
    0x5B => F32Eq
    0x5C => F32Ne
    0x5D => F32Lt
    0x5E => F32Gt
    0x5F => F32Le
    0x60 => F32Ge

    // f64 operations
    0x61 => F64Eq
    0x62 => F64Ne
    0x63 => F64Lt
    0x64 => F64Gt
    0x65 => F64Le
    0x66 => F64Ge

    // i32 unary/binary operations
    0x67 => I32Clz
    0x68 => I32Ctz
    0x69 => I32Popcnt
    0x6A => I32Add
    0x6B => I32Sub
    0x6C => I32Mul
    0x6D => I32DivS
    0x6E => I32DivU
    0x6F => I32RemS
    0x70 => I32RemU
    0x71 => I32And
    0x72 => I32Or
    0x73 => I32Xor
    0x74 => I32Shl
    0x75 => I32ShrS
    0x76 => I32ShrU
    0x77 => I32Rotl
    0x78 => I32Rotr

    // i64 unary/binary operations
    0x79 => I64Clz
    0x7A => I64Ctz
    0x7B => I64Popcnt
    0x7C => I64Add
    0x7D => I64Sub
    0x7E => I64Mul
    0x7F => I64DivS
    0x80 => I64DivU
    0x81 => I64RemS
    0x82 => I64RemU
    0x83 => I64And
    0x84 => I64Or
    0x85 => I64Xor
    0x86 => I64Shl
    0x87 => I64ShrS
    0x88 => I64ShrU
    0x89 => I64Rotl
    0x8A => I64Rotr

    // f32 unary/binary operations
    0x8B => F32Abs
    0x8C => F32Neg
    0x8D => F32Ceil
    0x8E => F32Floor
    0x8F => F32Trunc
    0x90 => F32Nearest
    0x91 => F32Sqrt
    0x92 => F32Add
    0x93 => F32Sub
    0x94 => F32Mul
    0x95 => F32Div
    0x96 => F32Min
    0x97 => F32Max
    0x98 => F32Copysign

    // f64 unary/binary operations
    0x99 => F64Abs
    0x9A => F64Neg
    0x9B => F64Ceil
    0x9C => F64Floor
    0x9D => F64Trunc
    0x9E => F64Nearest
    0x9F => F64Sqrt
    0xA0 => F64Add
    0xA1 => F64Sub
    0xA2 => F64Mul
    0xA3 => F64Div
    0xA4 => F64Min
    0xA5 => F64Max
    0xA6 => F64Copysign

    // Conversion instructions
    0xA7 => I32WrapI64
    0xA8 => I32TruncF32S
    0xA9 => I32TruncF32U
    0xAA => I32TruncF64S
    0xAB => I32TruncF64U
    0xAC => I64ExtendI32S
    0xAD => I64ExtendI32U
    0xAE => I64TruncF32S
    0xAF => I64TruncF32U
    0xB0 => I64TruncF64S
    0xB1 => I64TruncF64U
    0xB2 => F32ConvertI32S
    0xB3 => F32ConvertI32U
    0xB4 => F32ConvertI64S
    0xB5 => F32ConvertI64U
    0xB6 => F32DemoteF64
    0xB7 => F64ConvertI32S
    0xB8 => F64ConvertI32U
    0xB9 => F64ConvertI64S
    0xBA => F64ConvertI64U
    0xBB => F64PromoteF32
    0xBC => I32ReinterpretF32
    0xBD => I64ReinterpretF64
    0xBE => F32ReinterpretI32
    0xBF => F64ReinterpretI64

    // Sign extension instructions
    0xC0 => I32Extend8S
    0xC1 => I32Extend16S
    0xC2 => I64Extend8S
    0xC3 => I64Extend16S
    0xC4 => I64Extend32S
    // Multi-byte instructions (0xFC prefix)
    0xFC => {
      let sub_opcode = parser.read_u32_leb128()
      match sub_opcode {
        // table.grow
        0x0F => {
          let table_idx = parser.read_u32_leb128()
          TableGrow(table_idx)
        }
        // table.size
        0x10 => {
          let table_idx = parser.read_u32_leb128()
          TableSize(table_idx)
        }
        _ =>
          raise ValidationError::TypeMismatch(
            "unknown 0xFC sub-opcode: \{sub_opcode}",
          )
      }
    }
    _ =>
      raise ValidationError::TypeMismatch(
        "unknown opcode: 0x\{opcode.to_string().to_upper()}",
      )
  }
}

// Parse block type (can be empty, a value type, or a type index)

///|
fn parse_blocktype(parser : Parser) -> BlockType raise ParseError {
  let byte = parser.read_byte()
  match byte {
    0x40 => Empty // empty block type
    0x7F => Value(I32)
    0x7E => Value(I64)
    0x7D => Value(F32)
    0x7C => Value(F64)
    0x7B => Value(V128)
    0x70 => Value(FuncRef)
    0x6F => Value(ExternRef)
    _ => {
      // Type index encoded as signed LEB128
      // Put the byte back and read as signed LEB128
      parser.pos = parser.pos - 1
      let type_idx = parser.read_i32_leb128()
      TypeIndex(type_idx)
    }
  }
}

///|

///|
pub fn parse(b : Bytes) -> Module raise {
  let parser = Parser::new(b)

  // Parse magic number
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // Parse version
  let version = parser.read_bytes(4)
  if version[0].to_int() != 0x01 ||
    version[1].to_int() != 0x00 ||
    version[2].to_int() != 0x00 ||
    version[3].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // Parse sections
  let mut types : Array[FuncType] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[TableType] = []
  let mut mems : Array[MemType] = []
  let mut globals : Array[Global] = []
  let mut elems : Array[Elem] = []
  let mut datas : Array[Data] = []
  let mut start : UInt? = None
  let mut imports : Array[Import] = []
  let mut exports : Array[Export] = []
  let mut codes : Array[Code] = []
  while not(parser.eof()) {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.pos
    match section_id {
      1 => types = parse_type_section(parser)
      2 => imports = parse_import_section(parser)
      3 => funcs = parse_function_section(parser)
      4 => tables = parse_table_section(parser)
      5 => mems = parse_memory_section(parser)
      6 => globals = parse_global_section(parser)
      7 => exports = parse_export_section(parser)
      8 => start = Some(parser.read_u32_leb128())
      9 => elems = parse_element_section(parser)
      10 => codes = parse_code_section(parser)
      11 => datas = parse_data_section(parser)
      0 =>
        // Custom section - skip
        parser.pos = section_start + section_size.reinterpret_as_int()
      _ =>
        // Unknown section - skip it
        parser.pos = section_start + section_size.reinterpret_as_int()
    }
  }
  let module_ = Module::{
    types,
    funcs,
    tables,
    mems,
    globals,
    elems,
    datas,
    start,
    imports,
    exports,
    codes,
  }

  // Validate the module
  validate_module(module_)
  module_
}
