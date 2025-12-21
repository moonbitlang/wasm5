///|
fn parse_instr_table(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x25 => {
      let table_idx = parser.read_u32_leb128()
      Some(@core.Instr::TableGet(table_idx))
    }
    0x26 => {
      let table_idx = parser.read_u32_leb128()
      Some(@core.Instr::TableSet(table_idx))
    }
    _ => None
  }
}
