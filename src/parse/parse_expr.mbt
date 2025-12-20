// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> @core.Expr raise {
  let instrs = parse_instrs(parser)
  // parse_instrs puts back the 0x0B, we need to consume it
  let end_marker = parser.read_byte()
  guard end_marker == 0x0B else {
    raise @core.ParseError::InvalidFormat(
      "expected end marker 0x0B, got 0x\{end_marker.to_int().to_string()}",
    )
  }
  @core.Expr::{ instrs, }
}

// Parse instructions until 0x0B (end marker)

///|
fn parse_instrs(parser : Parser) -> Array[@core.Instr] raise {
  fn read_loop(instrs : Array[@core.Instr]) -> Array[@core.Instr] raise {
    let opcode = parser.read_byte()
    if opcode == 0x0B {
      // End marker (0x0B) - put it back for caller to handle
      parser.pos = parser.pos - 1
      instrs
    } else if opcode == 0x05 {
      // Else marker (0x05) - put it back for the if parser to handle
      parser.pos = parser.pos - 1
      instrs
    } else {
      instrs.push(parse_instr(parser, opcode))
      read_loop(instrs)
    }
  }

  read_loop([])
}

// Parse a single instruction

///|
fn parse_instr(parser : Parser, opcode : Byte) -> @core.Instr raise {
  match opcode {
    // Control instructions
    0x00 => @core.Instr::Unreachable
    0x01 => @core.Instr::Nop
    0x02 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      @core.Instr::Block(blocktype, instrs)
    }
    0x03 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      @core.Instr::Loop(blocktype, instrs)
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
        @core.Instr::If(blocktype, then_instrs, else_instrs)
      } else {
        // No else block, marker is 0x0B which ends the if
        @core.Instr::If(blocktype, then_instrs, [])
      }
    }
    // Exception handling proposal (skip for compatibility)
    0x06 => {
      // try blocktype - treat as block
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      @core.Instr::Block(blocktype, instrs)
    }
    0x07 => {
      // catch tagidx - skip tag index, return nop
      let _ = parser.read_u32_leb128()
      @core.Instr::Nop
    }
    0x08 => {
      // throw tagidx - skip tag index, return unreachable
      let _ = parser.read_u32_leb128()
      @core.Instr::Unreachable
    }
    0x09 => {
      // rethrow labelidx - skip label, return unreachable
      let _ = parser.read_u32_leb128()
      @core.Instr::Unreachable
    }
    0x0A => @core.Instr::Nop // catch_all - just nop
    0x0B => @core.Instr::Nop // delegate - should not be reached as instruction (it's a block terminator)
    0x0C => @core.Instr::Br(parser.read_u32_leb128())
    0x0D => @core.Instr::BrIf(parser.read_u32_leb128())
    0x0E => {
      let count = parser.read_u32_leb128()
      let labels = []
      for i in 0U..<count {
        labels.push(parser.read_u32_leb128())
      }
      let default_label = parser.read_u32_leb128()
      @core.Instr::BrTable(labels, default_label)
    }
    0x0F => @core.Instr::Return
    0x10 => @core.Instr::Call(parser.read_u32_leb128())
    0x11 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      @core.Instr::CallIndirect(type_idx, table_idx)
    }
    // Tail call proposal
    0x12 => @core.Instr::ReturnCall(parser.read_u32_leb128())
    0x13 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      @core.Instr::ReturnCallIndirect(type_idx, table_idx)
    }
    // Typed function references: call_ref
    0x14 => @core.Instr::CallRef(parser.read_u32_leb128())
    // Typed function references: return_call_ref
    0x15 => @core.Instr::ReturnCallRef(parser.read_u32_leb128())
    // GC proposal: ref.as_non_null - check reference is not null
    0x16 => {
      let _ = parser.read_u32_leb128() // type index
      @core.Instr::Nop // Placeholder - needs proper implementation
    }
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
      @core.Instr::Block(blocktype, instrs)
    }

    // Parametric instructions
    0x1A => @core.Instr::Drop
    0x1B => @core.Instr::Select
    0x1C => {
      // select t* - typed select with value type vector
      // Read the number of types (should be 1 for MVP)
      let num_types = parser.read_u32_leb128()
      // Read the type(s)
      let types : Array[@core.ValType] = []
      for _ in 0U..<num_types {
        types.push(parser.read_valtype())
      }
      @core.Instr::SelectTyped(types)
    }

    // Variable instructions
    0x20 => @core.Instr::LocalGet(parser.read_u32_leb128())
    0x21 => @core.Instr::LocalSet(parser.read_u32_leb128())
    0x22 => @core.Instr::LocalTee(parser.read_u32_leb128())
    0x23 => @core.Instr::GlobalGet(parser.read_u32_leb128())
    0x24 => @core.Instr::GlobalSet(parser.read_u32_leb128())

    // Memory instructions
    0x28 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Load(align, offset)
    }
    0x29 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load(align, offset)
    }
    0x2A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::F32Load(align, offset)
    }
    0x2B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::F64Load(align, offset)
    }
    0x2C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Load8S(align, offset)
    }
    0x2D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Load8U(align, offset)
    }
    0x2E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Load16S(align, offset)
    }
    0x2F => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Load16U(align, offset)
    }
    0x30 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load8S(align, offset)
    }
    0x31 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load8U(align, offset)
    }
    0x32 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load16S(align, offset)
    }
    0x33 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load16U(align, offset)
    }
    0x34 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load32S(align, offset)
    }
    0x35 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Load32U(align, offset)
    }
    0x36 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Store(align, offset)
    }
    0x37 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Store(align, offset)
    }
    0x38 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::F32Store(align, offset)
    }
    0x39 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::F64Store(align, offset)
    }
    0x3A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Store8(align, offset)
    }
    0x3B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I32Store16(align, offset)
    }
    0x3C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Store8(align, offset)
    }
    0x3D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Store16(align, offset)
    }
    0x3E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      @core.Instr::I64Store32(align, offset)
    }
    0x25 => {
      let table_idx = parser.read_u32_leb128()
      @core.Instr::TableGet(table_idx)
    }
    0x26 => {
      let table_idx = parser.read_u32_leb128()
      @core.Instr::TableSet(table_idx)
    }
    0x3F => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      @core.Instr::MemorySize(mem_idx.to_uint())
    }
    0x40 => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      @core.Instr::MemoryGrow(mem_idx.to_uint())
    }

    // Reference instructions
    0xD0 => {
      // ref.null heaptype
      let heap_type = parser.read_byte()
      let ref_type : @core.RefType = match heap_type {
        0x70 => @core.RefType::Func // funcref
        0x6F => @core.RefType::Extern // externref
        0x6E => @core.RefType::Any // anyref
        0x6D => @core.RefType::Eq // eqref
        0x6C => @core.RefType::I31 // i31ref
        0x6B => @core.RefType::Struct // structref
        0x6A => @core.RefType::Array // arrayref
        0x69 => @core.RefType::Exn // exnref
        0x71 => @core.RefType::None // none
        0x72 => @core.RefType::NoExtern // noextern
        0x73 => @core.RefType::NoFunc // nofunc
        0x74 => @core.RefType::NoExn // noexn
        _ => {
          // Assume it's a type index (negative or positive)
          parser.pos = parser.pos - 1
          let type_idx = parser.read_i32_leb128()
          @core.RefType::TypeIndex(type_idx)
        }
      }
      @core.Instr::RefNull(ref_type)
    }
    0xD1 => @core.Instr::RefIsNull // ref.is_null
    0xD2 => {
      // ref.func funcidx
      let func_idx = parser.read_u32_leb128()
      @core.Instr::RefFunc(func_idx)
    }
    // GC proposal reference instructions
    0xD3 => @core.Instr::RefIsNull // ref.eq - compare two references, treat as ref.is_null for now
    0xD4 => @core.Instr::Nop // ref.as_non_null - just pass through for now
    0xD5 => @core.Instr::BrOnNull(parser.read_u32_leb128()) // br_on_null labelidx
    0xD6 => @core.Instr::BrOnNonNull(parser.read_u32_leb128()) // br_on_non_null labelidx

    // Numeric instructions - constants
    0x41 =>
      @core.Instr::I32Const(parser.read_i32_leb128().reinterpret_as_uint())
    0x42 =>
      @core.Instr::I64Const(parser.read_i64_leb128().reinterpret_as_uint64())
    0x43 => @core.Instr::F32Const(parser.read_f32())
    0x44 => @core.Instr::F64Const(parser.read_f64())

    // i32 operations
    0x45 => @core.Instr::I32Eqz
    0x46 => @core.Instr::I32Eq
    0x47 => @core.Instr::I32Ne
    0x48 => @core.Instr::I32LtS
    0x49 => @core.Instr::I32LtU
    0x4A => @core.Instr::I32GtS
    0x4B => @core.Instr::I32GtU
    0x4C => @core.Instr::I32LeS
    0x4D => @core.Instr::I32LeU
    0x4E => @core.Instr::I32GeS
    0x4F => @core.Instr::I32GeU

    // i64 operations
    0x50 => @core.Instr::I64Eqz
    0x51 => @core.Instr::I64Eq
    0x52 => @core.Instr::I64Ne
    0x53 => @core.Instr::I64LtS
    0x54 => @core.Instr::I64LtU
    0x55 => @core.Instr::I64GtS
    0x56 => @core.Instr::I64GtU
    0x57 => @core.Instr::I64LeS
    0x58 => @core.Instr::I64LeU
    0x59 => @core.Instr::I64GeS
    0x5A => @core.Instr::I64GeU

    // f32 operations
    0x5B => @core.Instr::F32Eq
    0x5C => @core.Instr::F32Ne
    0x5D => @core.Instr::F32Lt
    0x5E => @core.Instr::F32Gt
    0x5F => @core.Instr::F32Le
    0x60 => @core.Instr::F32Ge

    // f64 operations
    0x61 => @core.Instr::F64Eq
    0x62 => @core.Instr::F64Ne
    0x63 => @core.Instr::F64Lt
    0x64 => @core.Instr::F64Gt
    0x65 => @core.Instr::F64Le
    0x66 => @core.Instr::F64Ge

    // i32 unary/binary operations
    0x67 => @core.Instr::I32Clz
    0x68 => @core.Instr::I32Ctz
    0x69 => @core.Instr::I32Popcnt
    0x6A => @core.Instr::I32Add
    0x6B => @core.Instr::I32Sub
    0x6C => @core.Instr::I32Mul
    0x6D => @core.Instr::I32DivS
    0x6E => @core.Instr::I32DivU
    0x6F => @core.Instr::I32RemS
    0x70 => @core.Instr::I32RemU
    0x71 => @core.Instr::I32And
    0x72 => @core.Instr::I32Or
    0x73 => @core.Instr::I32Xor
    0x74 => @core.Instr::I32Shl
    0x75 => @core.Instr::I32ShrS
    0x76 => @core.Instr::I32ShrU
    0x77 => @core.Instr::I32Rotl
    0x78 => @core.Instr::I32Rotr

    // i64 unary/binary operations
    0x79 => @core.Instr::I64Clz
    0x7A => @core.Instr::I64Ctz
    0x7B => @core.Instr::I64Popcnt
    0x7C => @core.Instr::I64Add
    0x7D => @core.Instr::I64Sub
    0x7E => @core.Instr::I64Mul
    0x7F => @core.Instr::I64DivS
    0x80 => @core.Instr::I64DivU
    0x81 => @core.Instr::I64RemS
    0x82 => @core.Instr::I64RemU
    0x83 => @core.Instr::I64And
    0x84 => @core.Instr::I64Or
    0x85 => @core.Instr::I64Xor
    0x86 => @core.Instr::I64Shl
    0x87 => @core.Instr::I64ShrS
    0x88 => @core.Instr::I64ShrU
    0x89 => @core.Instr::I64Rotl
    0x8A => @core.Instr::I64Rotr

    // f32 unary/binary operations
    0x8B => @core.Instr::F32Abs
    0x8C => @core.Instr::F32Neg
    0x8D => @core.Instr::F32Ceil
    0x8E => @core.Instr::F32Floor
    0x8F => @core.Instr::F32Trunc
    0x90 => @core.Instr::F32Nearest
    0x91 => @core.Instr::F32Sqrt
    0x92 => @core.Instr::F32Add
    0x93 => @core.Instr::F32Sub
    0x94 => @core.Instr::F32Mul
    0x95 => @core.Instr::F32Div
    0x96 => @core.Instr::F32Min
    0x97 => @core.Instr::F32Max
    0x98 => @core.Instr::F32Copysign

    // f64 unary/binary operations
    0x99 => @core.Instr::F64Abs
    0x9A => @core.Instr::F64Neg
    0x9B => @core.Instr::F64Ceil
    0x9C => @core.Instr::F64Floor
    0x9D => @core.Instr::F64Trunc
    0x9E => @core.Instr::F64Nearest
    0x9F => @core.Instr::F64Sqrt
    0xA0 => @core.Instr::F64Add
    0xA1 => @core.Instr::F64Sub
    0xA2 => @core.Instr::F64Mul
    0xA3 => @core.Instr::F64Div
    0xA4 => @core.Instr::F64Min
    0xA5 => @core.Instr::F64Max
    0xA6 => @core.Instr::F64Copysign

    // Conversion instructions
    0xA7 => @core.Instr::I32WrapI64
    0xA8 => @core.Instr::I32TruncF32S
    0xA9 => @core.Instr::I32TruncF32U
    0xAA => @core.Instr::I32TruncF64S
    0xAB => @core.Instr::I32TruncF64U
    0xAC => @core.Instr::I64ExtendI32S
    0xAD => @core.Instr::I64ExtendI32U
    0xAE => @core.Instr::I64TruncF32S
    0xAF => @core.Instr::I64TruncF32U
    0xB0 => @core.Instr::I64TruncF64S
    0xB1 => @core.Instr::I64TruncF64U
    0xB2 => @core.Instr::F32ConvertI32S
    0xB3 => @core.Instr::F32ConvertI32U
    0xB4 => @core.Instr::F32ConvertI64S
    0xB5 => @core.Instr::F32ConvertI64U
    0xB6 => @core.Instr::F32DemoteF64
    0xB7 => @core.Instr::F64ConvertI32S
    0xB8 => @core.Instr::F64ConvertI32U
    0xB9 => @core.Instr::F64ConvertI64S
    0xBA => @core.Instr::F64ConvertI64U
    0xBB => @core.Instr::F64PromoteF32
    0xBC => @core.Instr::I32ReinterpretF32
    0xBD => @core.Instr::I64ReinterpretF64
    0xBE => @core.Instr::F32ReinterpretI32
    0xBF => @core.Instr::F64ReinterpretI64

    // Sign extension instructions
    0xC0 => @core.Instr::I32Extend8S
    0xC1 => @core.Instr::I32Extend16S
    0xC2 => @core.Instr::I64Extend8S
    0xC3 => @core.Instr::I64Extend16S
    0xC4 => @core.Instr::I64Extend32S
    // Multi-byte instructions (0xFC prefix)
    0xFC => {
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
    _ =>
      raise @core.ValidationError::TypeMismatch(
        "unknown opcode: 0x\{opcode.to_string().to_upper()}",
      )
  }
}

// Parse block type (can be empty, a value type, or a type index)

///|
fn parse_blocktype(parser : Parser) -> @core.BlockType raise @core.ParseError {
  let byte = parser.read_byte()
  match byte {
    0x40 => @core.BlockType::Empty // empty block type
    0x7F => @core.BlockType::Value(@core.ValType::I32)
    0x7E => @core.BlockType::Value(@core.ValType::I64)
    0x7D => @core.BlockType::Value(@core.ValType::F32)
    0x7C => @core.BlockType::Value(@core.ValType::F64)
    0x7B => @core.BlockType::Value(@core.ValType::V128)
    0x70 => @core.BlockType::Value(@core.ValType::FuncRef)
    0x6F => @core.BlockType::Value(@core.ValType::ExternRef)
    0x6E => @core.BlockType::Value(@core.ValType::AnyRef)
    0x6D => @core.BlockType::Value(@core.ValType::EqRef)
    0x6C => @core.BlockType::Value(@core.ValType::I31Ref)
    0x6B => @core.BlockType::Value(@core.ValType::StructRef)
    0x6A => @core.BlockType::Value(@core.ValType::ArrayRef)
    0x69 => @core.BlockType::Value(@core.ValType::ExnRef)
    0x71 => @core.BlockType::Value(@core.ValType::NullRef)
    0x72 => @core.BlockType::Value(@core.ValType::NullExternRef)
    0x73 => @core.BlockType::Value(@core.ValType::NullFuncRef)
    0x74 => @core.BlockType::Value(@core.ValType::NullExnRef)
    // GC proposal: (ref null $t) - nullable typed reference
    0x63 => {
      let heap_type = parser.read_heap_type()
      @core.BlockType::Value(@core.ValType::Ref(heap_type, true))
    }
    // GC proposal: (ref $t) - non-null typed reference
    0x64 => {
      let heap_type = parser.read_heap_type()
      @core.BlockType::Value(@core.ValType::Ref(heap_type, false))
    }
    _ => {
      // Type index encoded as signed LEB128
      // Put the byte back and read as signed LEB128
      parser.pos = parser.pos - 1
      let type_idx = parser.read_i32_leb128()
      @core.BlockType::TypeIndex(type_idx)
    }
  }
}
