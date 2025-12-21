///|
fn parse_instr_memory(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x28 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Load(align, offset))
    }
    0x29 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load(align, offset))
    }
    0x2A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::F32Load(align, offset))
    }
    0x2B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::F64Load(align, offset))
    }
    0x2C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Load8S(align, offset))
    }
    0x2D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Load8U(align, offset))
    }
    0x2E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Load16S(align, offset))
    }
    0x2F => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Load16U(align, offset))
    }
    0x30 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load8S(align, offset))
    }
    0x31 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load8U(align, offset))
    }
    0x32 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load16S(align, offset))
    }
    0x33 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load16U(align, offset))
    }
    0x34 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load32S(align, offset))
    }
    0x35 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Load32U(align, offset))
    }
    0x36 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Store(align, offset))
    }
    0x37 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Store(align, offset))
    }
    0x38 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::F32Store(align, offset))
    }
    0x39 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::F64Store(align, offset))
    }
    0x3A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Store8(align, offset))
    }
    0x3B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I32Store16(align, offset))
    }
    0x3C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Store8(align, offset))
    }
    0x3D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Store16(align, offset))
    }
    0x3E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      Some(@core.Instr::I64Store32(align, offset))
    }
    0x3F => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      Some(@core.Instr::MemorySize(mem_idx.to_uint()))
    }
    0x40 => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      Some(@core.Instr::MemoryGrow(mem_idx.to_uint()))
    }
    _ => None
  }
}
