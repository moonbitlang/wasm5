///|
fn parse_instr_parametric(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x1A => Some(@core.Instr::Drop)
    0x1B => Some(@core.Instr::Select)
    0x1C => {
      // select t* - typed select with value type vector
      // Read the number of types (should be 1 for MVP)
      let num_types = parser.read_u32_leb128()
      // Read the type(s)
      let types : Array[@core.ValType] = []
      for _ in 0U..<num_types {
        types.push(parser.read_valtype())
      }
      Some(@core.Instr::SelectTyped(types))
    }
    _ => None
  }
}
