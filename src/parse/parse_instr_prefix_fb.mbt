///|
fn parse_instr_prefix_fb(parser : Parser) -> @core.Instr raise {
  let sub_opcode = parser.read_u32_leb128()
  match sub_opcode {
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
    _ =>
      raise @validate.ValidationError::TypeMismatch(
        "unknown 0xFB sub-opcode: \{sub_opcode}",
      )
  }
}
