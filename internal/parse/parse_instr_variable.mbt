///|
fn parse_instr_variable(
  parser : Parser,
  opcode : Byte,
) -> @core.Instr? raise ParseError {
  match opcode {
    0x20 => Some(LocalGet(parser.read_u32_leb128()))
    0x21 => Some(LocalSet(parser.read_u32_leb128()))
    0x22 => Some(LocalTee(parser.read_u32_leb128()))
    0x23 => Some(GlobalGet(parser.read_u32_leb128()))
    0x24 => Some(GlobalSet(parser.read_u32_leb128()))
    _ => None
  }
}
