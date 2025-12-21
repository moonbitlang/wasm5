///|
fn parse_instr_prefix_fc(parser : Parser) -> @core.Instr raise {
  let sub_opcode = parser.read_u32_leb128()
  match sub_opcode {
    // Saturating truncation instructions
    0x00 => @core.Instr::I32TruncSatF32S
    0x01 => @core.Instr::I32TruncSatF32U
    0x02 => @core.Instr::I32TruncSatF64S
    0x03 => @core.Instr::I32TruncSatF64U
    0x04 => @core.Instr::I64TruncSatF32S
    0x05 => @core.Instr::I64TruncSatF32U
    0x06 => @core.Instr::I64TruncSatF64S
    0x07 => @core.Instr::I64TruncSatF64U
    // Bulk memory instructions
    0x08 => {
      // memory.init data_idx mem_idx
      let data_idx = parser.read_u32_leb128()
      let mem_idx = parser.read_u32_leb128()
      guard mem_idx == 0 else {
        raise @core.ValidationError::TypeMismatch(
          "memory.init: multi-memory not supported, mem_idx must be 0",
        )
      }
      @core.Instr::MemoryInit(data_idx)
    }
    0x09 => {
      // data.drop data_idx
      let data_idx = parser.read_u32_leb128()
      @core.Instr::DataDrop(data_idx)
    }
    0x0A => {
      // memory.copy mem_idx_dst mem_idx_src
      let mem_idx_dst = parser.read_u32_leb128()
      let mem_idx_src = parser.read_u32_leb128()
      guard mem_idx_dst == 0 && mem_idx_src == 0 else {
        raise @core.ValidationError::TypeMismatch(
          "memory.copy: multi-memory not supported, both indices must be 0",
        )
      }
      @core.Instr::MemoryCopy
    }
    0x0B => {
      // memory.fill mem_idx
      let mem_idx = parser.read_u32_leb128()
      guard mem_idx == 0 else {
        raise @core.ValidationError::TypeMismatch(
          "memory.fill: multi-memory not supported, mem_idx must be 0",
        )
      }
      @core.Instr::MemoryFill
    }
    0x0C => {
      // table.init elem_idx table_idx
      let elem_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      @core.Instr::TableInit(table_idx, elem_idx)
    }
    0x0D => {
      // elem.drop elem_idx
      let elem_idx = parser.read_u32_leb128()
      @core.Instr::ElemDrop(elem_idx)
    }
    0x0E => {
      // table.copy table_idx_dst table_idx_src
      let table_idx_dst = parser.read_u32_leb128()
      let table_idx_src = parser.read_u32_leb128()
      @core.Instr::TableCopy(table_idx_dst, table_idx_src)
    }
    // table.grow
    0x0F => {
      let table_idx = parser.read_u32_leb128()
      @core.Instr::TableGrow(table_idx)
    }
    // table.size
    0x10 => {
      let table_idx = parser.read_u32_leb128()
      @core.Instr::TableSize(table_idx)
    }
    _ =>
      raise @core.ValidationError::TypeMismatch(
        "unknown 0xFC sub-opcode: \{sub_opcode}",
      )
  }
}
