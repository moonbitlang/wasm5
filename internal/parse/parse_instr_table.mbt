///|
fn parse_instr_table(
  parser : Parser,
  opcode : Byte,
) -> @core.Instr? raise ParseError {
  match opcode {
    0x25 => {
      let table_idx = parser.read_u32_leb128()
      Some(TableGet(table_idx))
    }
    0x26 => {
      let table_idx = parser.read_u32_leb128()
      Some(TableSet(table_idx))
    }
    _ => None
  }
}
