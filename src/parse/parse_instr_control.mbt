///|
fn parse_instr_control(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    0x00 => Some(@core.Instr::Unreachable)
    0x01 => Some(@core.Instr::Nop)
    0x02 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Some(@core.Instr::Block(blocktype, instrs))
    }
    0x03 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Some(@core.Instr::Loop(blocktype, instrs))
    }
    0x04 => {
      let blocktype = parse_blocktype(parser)
      let then_instrs = parse_instrs(parser)
      // Check if there's an else (0x05) or end (0x0B)
      let marker = parser.read_byte()
      if marker == 0x05 {
        // There's an else block
        let else_instrs = parse_instrs(parser)
        let _ = parser.read_byte() // consume final 0x0B end marker
        Some(@core.Instr::If(blocktype, then_instrs, else_instrs))
      } else {
        // No else block, marker is 0x0B which ends the if
        Some(@core.Instr::If(blocktype, then_instrs, []))
      }
    }
    // Exception handling proposal (skip for compatibility)
    0x06 => {
      // try blocktype - treat as block
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Some(@core.Instr::Block(blocktype, instrs))
    }
    0x07 => {
      // catch tagidx - skip tag index, return nop
      let _ = parser.read_u32_leb128()
      Some(@core.Instr::Nop)
    }
    0x08 => {
      // throw tagidx - skip tag index, return unreachable
      let _ = parser.read_u32_leb128()
      Some(@core.Instr::Unreachable)
    }
    0x09 => {
      // rethrow labelidx - skip label, return unreachable
      let _ = parser.read_u32_leb128()
      Some(@core.Instr::Unreachable)
    }
    0x0A => Some(@core.Instr::Nop) // catch_all - just nop
    0x0B => Some(@core.Instr::Nop) // delegate - should not be reached as instruction
    0x0C => Some(@core.Instr::Br(parser.read_u32_leb128()))
    0x0D => Some(@core.Instr::BrIf(parser.read_u32_leb128()))
    0x0E => {
      let count = parser.read_u32_leb128()
      let labels = []
      for _ in 0U..<count {
        labels.push(parser.read_u32_leb128())
      }
      let default_label = parser.read_u32_leb128()
      Some(@core.Instr::BrTable(labels, default_label))
    }
    0x0F => Some(@core.Instr::Return)
    0x10 => Some(@core.Instr::Call(parser.read_u32_leb128()))
    0x11 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      Some(@core.Instr::CallIndirect(type_idx, table_idx))
    }
    // Tail call proposal
    0x12 => Some(@core.Instr::ReturnCall(parser.read_u32_leb128()))
    0x13 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      Some(@core.Instr::ReturnCallIndirect(type_idx, table_idx))
    }
    // Typed function references: call_ref
    0x14 => Some(@core.Instr::CallRef(parser.read_u32_leb128()))
    // Typed function references: return_call_ref
    0x15 => Some(@core.Instr::ReturnCallRef(parser.read_u32_leb128()))
    // Exception handling: try_table
    0x1F => {
      let blocktype = parse_blocktype(parser)
      // Read catch clauses
      let catch_count = parser.read_u32_leb128()
      for _ in 0U..<catch_count {
        let catch_kind = parser.read_byte()
        match catch_kind {
          0x00 => {
            // catch tagidx labelidx
            let _ = parser.read_u32_leb128()
            let _ = parser.read_u32_leb128()

          }
          0x01 => {
            // catch_ref tagidx labelidx
            let _ = parser.read_u32_leb128()
            let _ = parser.read_u32_leb128()

          }
          0x02 => {
            // catch_all labelidx
            let _ = parser.read_u32_leb128()

          }
          0x03 => {
            // catch_all_ref labelidx
            let _ = parser.read_u32_leb128()

          }
          _ => ()
        }
      }
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Some(@core.Instr::Block(blocktype, instrs))
    }
    _ => None
  }
}
