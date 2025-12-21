///|
fn parse_instr_variable(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x20 => Some(@core.Instr::LocalGet(parser.read_u32_leb128()))
    0x21 => Some(@core.Instr::LocalSet(parser.read_u32_leb128()))
    0x22 => Some(@core.Instr::LocalTee(parser.read_u32_leb128()))
    0x23 => Some(@core.Instr::GlobalGet(parser.read_u32_leb128()))
    0x24 => Some(@core.Instr::GlobalSet(parser.read_u32_leb128()))
    _ => None
  }
}
