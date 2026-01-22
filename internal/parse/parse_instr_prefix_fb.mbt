///|
fn parse_instr_prefix_fb(parser : Parser) -> @core.Instr raise ParseError {
  let sub_opcode = parser.read_u32_leb128()
  match sub_opcode {
    0x00 => StructNew(parser.read_u32_leb128())
    0x01 => StructNewDefault(parser.read_u32_leb128())
    0x02 => {
      let type_idx = parser.read_u32_leb128()
      let field_idx = parser.read_u32_leb128()
      StructGet(type_idx, field_idx)
    }
    0x03 => {
      let type_idx = parser.read_u32_leb128()
      let field_idx = parser.read_u32_leb128()
      StructGetS(type_idx, field_idx)
    }
    0x04 => {
      let type_idx = parser.read_u32_leb128()
      let field_idx = parser.read_u32_leb128()
      StructGetU(type_idx, field_idx)
    }
    0x05 => {
      let type_idx = parser.read_u32_leb128()
      let field_idx = parser.read_u32_leb128()
      StructSet(type_idx, field_idx)
    }
    0x06 => ArrayNew(parser.read_u32_leb128())
    0x07 => ArrayNewDefault(parser.read_u32_leb128())
    0x08 => {
      let type_idx = parser.read_u32_leb128()
      let len = parser.read_u32_leb128()
      ArrayNewFixed(type_idx, len)
    }
    0x09 => {
      let type_idx = parser.read_u32_leb128()
      let data_idx = parser.read_u32_leb128()
      ArrayNewData(type_idx, data_idx)
    }
    0x0A => {
      let type_idx = parser.read_u32_leb128()
      let elem_idx = parser.read_u32_leb128()
      ArrayNewElem(type_idx, elem_idx)
    }
    0x0B => ArrayGet(parser.read_u32_leb128())
    0x0C => ArrayGetS(parser.read_u32_leb128())
    0x0D => ArrayGetU(parser.read_u32_leb128())
    0x0E => ArraySet(parser.read_u32_leb128())
    0x0F => ArrayLen
    0x10 => ArrayFill(parser.read_u32_leb128())
    0x11 => {
      let dst = parser.read_u32_leb128()
      let src = parser.read_u32_leb128()
      ArrayCopy(dst, src)
    }
    0x12 => {
      let type_idx = parser.read_u32_leb128()
      let data_idx = parser.read_u32_leb128()
      ArrayInitData(type_idx, data_idx)
    }
    0x13 => {
      let type_idx = parser.read_u32_leb128()
      let elem_idx = parser.read_u32_leb128()
      ArrayInitElem(type_idx, elem_idx)
    }
    0x14 => {
      let heap_type = parser.read_heap_type()
      RefTest(heap_type, false)
    }
    0x15 => {
      let heap_type = parser.read_heap_type()
      RefTest(heap_type, true)
    }
    0x16 => {
      let heap_type = parser.read_heap_type()
      RefCast(heap_type, false)
    }
    0x17 => {
      let heap_type = parser.read_heap_type()
      RefCast(heap_type, true)
    }
    0x18 => {
      let flags = parser.read_byte()
      let label = parser.read_u32_leb128()
      // Binary format: source type first, then target type
      let source_type = parser.read_heap_type()
      let target_type = parser.read_heap_type()
      let source_nullable = (flags.to_uint() & 0x01U) != 0U
      let target_nullable = (flags.to_uint() & 0x02U) != 0U
      BrOnCast(
        label, target_type, target_nullable, source_type, source_nullable,
      )
    }
    0x19 => {
      let flags = parser.read_byte()
      let label = parser.read_u32_leb128()
      // Binary format: source type first, then target type
      let source_type = parser.read_heap_type()
      let target_type = parser.read_heap_type()
      let source_nullable = (flags.to_uint() & 0x01U) != 0U
      let target_nullable = (flags.to_uint() & 0x02U) != 0U
      BrOnCastFail(
        label, target_type, target_nullable, source_type, source_nullable,
      )
    }
    0x1A => AnyConvertExtern
    0x1B => ExternConvertAny
    0x1C => RefI31
    0x1D => I31GetS
    0x1E => I31GetU
    _ =>
      raise ParseError::InvalidFormat("unknown 0xFB sub-opcode: \{sub_opcode}")
  }
}
