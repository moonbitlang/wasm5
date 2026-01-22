///|
fn parse_instr_prefix_fd(parser : Parser) -> @core.Instr raise ParseError {
  let sub_opcode = parser.read_u32_leb128()
  match @core.simd_spec_by_opcode(sub_opcode) {
    Some(spec) => {
      let imm = match spec.imm {
        None => @core.SimdImmediate::None
        MemArg => {
          let (align, offset, memory_idx) = parser.read_memarg()
          @core.SimdImmediate::MemArg(align, offset, memory_idx)
        }
        Lane => {
          let lane = parser.read_byte().to_uint()
          @core.SimdImmediate::Lane(lane)
        }
        MemArgLane => {
          let (align, offset, memory_idx) = parser.read_memarg()
          let lane = parser.read_byte().to_uint()
          @core.SimdImmediate::MemArgLane(align, offset, memory_idx, lane)
        }
        Shuffle => {
          let raw = parser.read_bytes(16U)
          let bytes : Array[Byte] = []
          for b in raw {
            bytes.push(b)
          }
          @core.SimdImmediate::Shuffle(bytes)
        }
        V128Const => {
          let raw = parser.read_bytes(16U)
          let bytes : Array[Byte] = []
          for b in raw {
            bytes.push(b)
          }
          @core.SimdImmediate::V128Const(bytes)
        }
      }
      @core.Instr::Simd(@core.SimdInstr::{ opcode: sub_opcode, imm })
    }
    None =>
      raise ParseError::InvalidFormat("unknown 0xFD sub-opcode: \{sub_opcode}")
  }
}
