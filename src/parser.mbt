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
fn Parser::peek(self : Parser) -> Int {
  if self.pos < self.bytes.length() {
    self.bytes[self.pos].to_int()
  } else {
    abort("unexpected end of file")
  }
}

///|
fn Parser::read_byte(self : Parser) -> Int {
  if self.pos < self.bytes.length() {
    let byte = self.bytes[self.pos].to_int()
    self.pos = self.pos + 1
    byte
  } else {
    abort("unexpected end of file")
  }
}

///|
fn Parser::read_bytes(self : Parser, n : Int) -> Bytes {
  if self.pos + n <= self.bytes.length() {
    let result = self.bytes[self.pos:self.pos + n].to_bytes()
    self.pos = self.pos + n
    result
  } else {
    abort("unexpected end of file")
  }
}

// LEB128 decoding

///|
fn Parser::read_u32_leb128(self : Parser) -> UInt {
  fn read_loop(shift : Int, result : UInt) -> UInt {
    let byte = self.read_byte()
    let value = byte.land(0x7f).to_uint().lsl(shift)
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
fn Parser::read_i32_leb128(self : Parser) -> Int {
  fn read_loop(shift : Int, result : Int) -> (Int, Int) {
    let byte = self.read_byte()
    let value = byte.land(0x7f).lsl(shift)
    let new_result = result | value
    if (byte & 0x80) == 0 {
      (new_result, shift)
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  let (result, shift) = read_loop(0, 0)
  let byte = result.lsr(shift) & 0x7f
  // Sign extend if needed
  if shift < 32 && (byte & 0x40) != 0 {
    result | (-1).lsl(shift + 7)
  } else {
    result
  }
}

///|
fn Parser::read_i64_leb128(self : Parser) -> Int64 {
  fn read_loop(shift : Int, result : Int64) -> (Int64, Int) {
    let byte = self.read_byte()
    let value = byte.land(0x7f).to_int64().lsl(shift)
    let new_result = result | value
    if (byte & 0x80) == 0 {
      (new_result, shift)
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  let (result, shift) = read_loop(0, 0L)
  let byte = result.lsr(shift).land(0x7fL).to_int()
  // Sign extend if needed
  if shift < 64 && (byte & 0x40) != 0 {
    result | (-1L).lsl(shift + 7)
  } else {
    result
  }
}

// Read f32 and f64 (little-endian IEEE 754)
// TODO: Need proper from_bits implementation

///|
fn Parser::read_f32(self : Parser) -> Float {
  let b0 = self.read_byte()
  let b1 = self.read_byte()
  let b2 = self.read_byte()
  let b3 = self.read_byte()
  let bits = b0 | b1.lsl(8) | b2.lsl(16) | b3.lsl(24)
  // Placeholder: need from_bits function
  reinterpret_i32_as_f32(bits)
}

///|
fn Parser::read_f64(self : Parser) -> Double {
  let b0 = self.read_byte().to_int64()
  let b1 = self.read_byte().to_int64()
  let b2 = self.read_byte().to_int64()
  let b3 = self.read_byte().to_int64()
  let b4 = self.read_byte().to_int64()
  let b5 = self.read_byte().to_int64()
  let b6 = self.read_byte().to_int64()
  let b7 = self.read_byte().to_int64()
  let bits = b0 |
    b1.lsl(8) |
    b2.lsl(16) |
    b3.lsl(24) |
    b4.lsl(32) |
    b5.lsl(40) |
    b6.lsl(48) |
    b7.lsl(56)
  // Placeholder: need from_bits function
  reinterpret_i64_as_f64(bits)
}

///|
fn reinterpret_i32_as_f32(bits : Int) -> Float {
  Float::reinterpret_from_int(bits)
}

///|
fn reinterpret_i64_as_f64(bits : Int64) -> Double {
  bits.reinterpret_as_double()
}

// Read name (length-prefixed UTF-8 string)

///|
fn Parser::read_name(self : Parser) -> String {
  let len = self.read_u32_leb128().to_int()
  let bytes = self.read_bytes(len)
  // For now, assume UTF-8 is valid
  bytes.to_string()
}

// Parse value type

///|
fn Parser::read_valtype(self : Parser) -> ValType raise ValidationError {
  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128
    0x70 => FuncRef
    0x6F => ExternRef
    _ => raise ValidationError::TypeMismatch("invalid value type: 0x\{byte.to_string()}")
  }
}

// Parse reference type

///|
fn Parser::read_reftype(self : Parser) -> RefType raise ValidationError {
  let byte = self.read_byte()
  match byte {
    0x70 => FuncRef
    0x6F => ExternRef
    _ => raise ValidationError::TypeMismatch("invalid reference type: 0x\{byte.to_string()}")
  }
}

// Parse limits

///|
fn Parser::read_limits(self : Parser) -> Limits {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}

// Section parsers

///|
fn parse_type_section(parser : Parser) -> Array[FuncType] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let types = []
  for i = 0; i < count; i = i + 1 {
    let tag = parser.read_byte()
    if tag != 0x60 {
      raise ValidationError::TypeMismatch("expected function type tag 0x60, got 0x\{tag.to_string()}")
    }

    // Read params
    let param_count = parser.read_u32_leb128().to_int()
    let params = []
    for j = 0; j < param_count; j = j + 1 {
      params.push(parser.read_valtype())
    }

    // Read results
    let result_count = parser.read_u32_leb128().to_int()
    let results = []
    for j = 0; j < result_count; j = j + 1 {
      results.push(parser.read_valtype())
    }
    types.push({ params, results })
  }
  types
}

///|
fn parse_import_section(parser : Parser) -> Array[Import] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let imports = []
  for i = 0; i < count; i = i + 1 {
    let module = parser.read_name()
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
      _ => raise ValidationError::TypeMismatch("invalid import descriptor tag: 0x\{desc_tag.to_string()}")
    }
    imports.push({ module, name, desc })
  }
  imports
}

///|
fn parse_function_section(parser : Parser) -> Array[UInt] {
  let count = parser.read_u32_leb128().to_int()
  let funcs = []
  for i = 0; i < count; i = i + 1 {
    funcs.push(parser.read_u32_leb128())
  }
  funcs
}

///|
fn parse_table_section(parser : Parser) -> Array[TableType] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let tables = []
  for i = 0; i < count; i = i + 1 {
    let elem_type = parser.read_reftype()
    let limits = parser.read_limits()
    tables.push({ elem_type, limits })
  }
  tables
}

///|
fn parse_memory_section(parser : Parser) -> Array[MemType] {
  let count = parser.read_u32_leb128().to_int()
  let mems = []
  for i = 0; i < count; i = i + 1 {
    let limits = parser.read_limits()
    mems.push({ limits, })
  }
  mems
}

///|
fn parse_global_section(parser : Parser) -> Array[Global] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let globals = []
  for i = 0; i < count; i = i + 1 {
    let val_type = parser.read_valtype()
    let mutable = parser.read_byte() == 0x01
    let init = parse_expr(parser)
    globals.push({ type_: { val_type, mutable }, init })
  }
  globals
}

///|
fn parse_export_section(parser : Parser) -> Array[Export] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let exports = []
  for i = 0; i < count; i = i + 1 {
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc = match desc_tag {
      0x00 => ExportDesc::Func(parser.read_u32_leb128())
      0x01 => ExportDesc::Table(parser.read_u32_leb128())
      0x02 => ExportDesc::Mem(parser.read_u32_leb128())
      0x03 => ExportDesc::Global(parser.read_u32_leb128())
      _ => raise ValidationError::TypeMismatch("invalid export descriptor tag: 0x\{desc_tag.to_string()}")
    }
    exports.push({ name, desc })
  }
  exports
}

///|
fn parse_element_section(parser : Parser) -> Array[Elem] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let elems = []
  for i = 0; i < count; i = i + 1 {
    let table_idx = parser.read_u32_leb128()
    let offset = parse_expr(parser)
    let init_count = parser.read_u32_leb128().to_int()
    let init = []
    for j = 0; j < init_count; j = j + 1 {
      init.push(parser.read_u32_leb128())
    }
    elems.push({ table_idx, offset, init })
  }
  elems
}

///|
fn parse_code_section(parser : Parser) -> Array[Code] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let codes = []
  for i = 0; i < count; i = i + 1 {
    let code_size = parser.read_u32_leb128()

    // Parse locals
    let locals_count = parser.read_u32_leb128().to_int()
    let locals = []
    for j = 0; j < locals_count; j = j + 1 {
      let n = parser.read_u32_leb128().to_int()
      let val_type = parser.read_valtype()
      for k = 0; k < n; k = k + 1 {
        locals.push(val_type)
      }
    }

    // Parse body
    let body = parse_expr(parser)
    codes.push({ locals, body })
  }
  codes
}

///|
fn parse_data_section(parser : Parser) -> Array[Data] raise ValidationError {
  let count = parser.read_u32_leb128().to_int()
  let datas = []
  for i = 0; i < count; i = i + 1 {
    let mem_idx = parser.read_u32_leb128()
    let offset = parse_expr(parser)
    let init_len = parser.read_u32_leb128().to_int()
    let init = parser.read_bytes(init_len)
    datas.push({ mem_idx, offset, init })
  }
  datas
}

// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> Expr raise ValidationError {
  let instrs = parse_instrs(parser)
  { instrs, }
}

// Parse instructions until 0x0B (end marker)

///|
fn parse_instrs(parser : Parser) -> Array[Instr] raise ValidationError {
  fn read_loop(instrs : Array[Instr]) -> Array[Instr] raise ValidationError {
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
fn parse_instr(parser : Parser, opcode : Int) -> Instr raise ValidationError {
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
      let count = parser.read_u32_leb128().to_int()
      let labels = []
      for i = 0; i < count; i = i + 1 {
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
    0x3F => {
      let _ = parser.read_byte() // reserved byte (must be 0x00)
      MemorySize
    }
    0x40 => {
      let _ = parser.read_byte() // reserved byte (must be 0x00)
      MemoryGrow
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
    _ => raise ValidationError::TypeMismatch("unknown opcode: 0x\{opcode.to_string().to_upper()}")
  }
}

// Parse block type (can be empty, a value type, or a type index)

///|
fn parse_blocktype(parser : Parser) -> BlockType {
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
