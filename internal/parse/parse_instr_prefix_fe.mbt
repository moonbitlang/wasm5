///|
fn parse_instr_prefix_fe(parser : Parser) -> @core.Instr raise ParseError {
  let sub_opcode = parser.read_u32_leb128()
  match @core.atomic_spec_by_opcode(sub_opcode) {
    Some(spec) => {
      let imm = match spec.imm {
        None => @core.AtomicImmediate::None
        MemArg => {
          let (align, offset, memory_idx) = parser.read_memarg()
          @core.AtomicImmediate::MemArg(align, offset, memory_idx)
        }
        Fence => {
          let flags = parser.read_byte().to_uint()
          @core.AtomicImmediate::Fence(flags)
        }
      }
      @core.Instr::Atomic(@core.AtomicInstr::{ opcode: sub_opcode, imm })
    }
    None =>
      raise ParseError::InvalidFormat("unknown 0xFE sub-opcode: \{sub_opcode}")
  }
}
