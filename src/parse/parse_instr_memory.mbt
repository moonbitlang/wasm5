///|
fn parse_instr_memory(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x28 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Load(align, offset, memory_idx))
    }
    0x29 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load(align, offset, memory_idx))
    }
    0x2A => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(F32Load(align, offset, memory_idx))
    }
    0x2B => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(F64Load(align, offset, memory_idx))
    }
    0x2C => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Load8S(align, offset, memory_idx))
    }
    0x2D => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Load8U(align, offset, memory_idx))
    }
    0x2E => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Load16S(align, offset, memory_idx))
    }
    0x2F => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Load16U(align, offset, memory_idx))
    }
    0x30 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load8S(align, offset, memory_idx))
    }
    0x31 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load8U(align, offset, memory_idx))
    }
    0x32 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load16S(align, offset, memory_idx))
    }
    0x33 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load16U(align, offset, memory_idx))
    }
    0x34 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load32S(align, offset, memory_idx))
    }
    0x35 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Load32U(align, offset, memory_idx))
    }
    0x36 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Store(align, offset, memory_idx))
    }
    0x37 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Store(align, offset, memory_idx))
    }
    0x38 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(F32Store(align, offset, memory_idx))
    }
    0x39 => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(F64Store(align, offset, memory_idx))
    }
    0x3A => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Store8(align, offset, memory_idx))
    }
    0x3B => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I32Store16(align, offset, memory_idx))
    }
    0x3C => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Store8(align, offset, memory_idx))
    }
    0x3D => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Store16(align, offset, memory_idx))
    }
    0x3E => {
      let (align, offset, memory_idx) = parser.read_memarg()
      Some(I64Store32(align, offset, memory_idx))
    }
    0x3F => {
      let mem_idx = parser.read_u32_leb128()
      Some(MemorySize(mem_idx))
    }
    0x40 => {
      let mem_idx = parser.read_u32_leb128()
      Some(MemoryGrow(mem_idx))
    }
    _ => None
  }
}
