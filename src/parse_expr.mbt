// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> Expr raise {
  let instrs = parse_instrs(parser)
  // parse_instrs puts back the 0x0B, we need to consume it
  let end_marker = parser.read_byte()
  guard end_marker == 0x0B else {
    raise ParseError::InvalidFormat(
      "expected end marker 0x0B, got 0x\{end_marker.to_int().to_string()}",
    )
  }
  { instrs, }
}

// Parse instructions until 0x0B (end marker)

///|
fn parse_instrs(parser : Parser) -> Array[Instr] raise {
  fn read_loop(instrs : Array[Instr]) -> Array[Instr] raise {
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
fn parse_instr(parser : Parser, opcode : Byte) -> Instr raise {
  match opcode {
    // Control instructions
    0x00 => Unreachable
    0x01 => Nop
    0x02 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Block(blocktype, instrs)
    }
    0x03 => {
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Loop(blocktype, instrs)
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
        If(blocktype, then_instrs, else_instrs)
      } else {
        // No else block, marker is 0x0B which ends the if
        If(blocktype, then_instrs, [])
      }
    }
    // Exception handling proposal (skip for compatibility)
    0x06 => {
      // try blocktype - treat as block
      let blocktype = parse_blocktype(parser)
      let instrs = parse_instrs(parser)
      let _ = parser.read_byte() // consume 0x0B end marker
      Block(blocktype, instrs)
    }
    0x07 => {
      // catch tagidx - skip tag index, return nop
      let _ = parser.read_u32_leb128()
      Nop
    }
    0x08 => {
      // throw tagidx - skip tag index, return unreachable
      let _ = parser.read_u32_leb128()
      Unreachable
    }
    0x09 => {
      // rethrow labelidx - skip label, return unreachable
      let _ = parser.read_u32_leb128()
      Unreachable
    }
    0x0A => Nop // catch_all - just nop
    0x0B => Nop // delegate - should not be reached as instruction (it's a block terminator)
    0x0C => Br(parser.read_u32_leb128())
    0x0D => BrIf(parser.read_u32_leb128())
    0x0E => {
      let count = parser.read_u32_leb128()
      let labels = []
      for i in 0U..<count {
        labels.push(parser.read_u32_leb128())
      }
      let default_label = parser.read_u32_leb128()
      BrTable(labels, default_label)
    }
    0x0F => Return
    0x10 => Call(parser.read_u32_leb128())
    0x11 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      CallIndirect(type_idx, table_idx)
    }
    // Tail call proposal
    0x12 => ReturnCall(parser.read_u32_leb128())
    0x13 => {
      let type_idx = parser.read_u32_leb128()
      let table_idx = parser.read_u32_leb128()
      ReturnCallIndirect(type_idx, table_idx)
    }
    // Typed function references: call_ref
    0x14 => CallRef(parser.read_u32_leb128())
    // Typed function references: return_call_ref
    0x15 => ReturnCallRef(parser.read_u32_leb128())
    // GC proposal: ref.as_non_null - check reference is not null
    0x16 => {
      let _ = parser.read_u32_leb128() // type index
      Nop // Placeholder - needs proper implementation
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
      Block(blocktype, instrs)
    }

    // Parametric instructions
    0x1A => Drop
    0x1B => Select
    0x1C => {
      // select t* - typed select with value type vector
      // Read the number of types (should be 1 for MVP)
      let num_types = parser.read_u32_leb128()
      // Read the type(s)
      let types : Array[ValType] = []
      for _ in 0U..<num_types {
        types.push(parser.read_valtype())
      }
      SelectTyped(types)
    }

    // Variable instructions
    0x20 => LocalGet(parser.read_u32_leb128())
    0x21 => LocalSet(parser.read_u32_leb128())
    0x22 => LocalTee(parser.read_u32_leb128())
    0x23 => GlobalGet(parser.read_u32_leb128())
    0x24 => GlobalSet(parser.read_u32_leb128())

    // Memory instructions
    0x28 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Load(align, offset)
    }
    0x29 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load(align, offset)
    }
    0x2A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      F32Load(align, offset)
    }
    0x2B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      F64Load(align, offset)
    }
    0x2C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Load8S(align, offset)
    }
    0x2D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Load8U(align, offset)
    }
    0x2E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Load16S(align, offset)
    }
    0x2F => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Load16U(align, offset)
    }
    0x30 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load8S(align, offset)
    }
    0x31 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load8U(align, offset)
    }
    0x32 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load16S(align, offset)
    }
    0x33 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load16U(align, offset)
    }
    0x34 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load32S(align, offset)
    }
    0x35 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Load32U(align, offset)
    }
    0x36 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Store(align, offset)
    }
    0x37 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Store(align, offset)
    }
    0x38 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      F32Store(align, offset)
    }
    0x39 => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      F64Store(align, offset)
    }
    0x3A => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Store8(align, offset)
    }
    0x3B => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I32Store16(align, offset)
    }
    0x3C => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Store8(align, offset)
    }
    0x3D => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Store16(align, offset)
    }
    0x3E => {
      let (align, offset, _memory_idx) = parser.read_memarg()
      I64Store32(align, offset)
    }
    0x25 => {
      let table_idx = parser.read_u32_leb128()
      TableGet(table_idx)
    }
    0x26 => {
      let table_idx = parser.read_u32_leb128()
      TableSet(table_idx)
    }
    0x3F => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      MemorySize(mem_idx.to_uint())
    }
    0x40 => {
      let mem_idx = parser.read_byte() // memory index (usually 0x00)
      MemoryGrow(mem_idx.to_uint())
    }

    // Reference instructions
    0xD0 => {
      // ref.null heaptype
      let heap_type = parser.read_byte()
      let ref_type : RefType = match heap_type {
        0x70 => RefType::Func // funcref
        0x6F => RefType::Extern // externref
        0x6E => RefType::Any // anyref
        0x6D => RefType::Eq // eqref
        0x6C => RefType::I31 // i31ref
        0x6B => RefType::Struct // structref
        0x6A => RefType::Array // arrayref
        0x69 => RefType::Exn // exnref
        0x71 => RefType::None // none
        0x72 => RefType::NoExtern // noextern
        0x73 => RefType::NoFunc // nofunc
        0x74 => RefType::NoExn // noexn
        _ => {
          // Assume it's a type index (negative or positive)
          parser.pos = parser.pos - 1
          let type_idx = parser.read_i32_leb128()
          RefType::TypeIndex(type_idx)
        }
      }
      RefNull(ref_type)
    }
    0xD1 => RefIsNull // ref.is_null
    0xD2 => {
      // ref.func funcidx
      let func_idx = parser.read_u32_leb128()
      RefFunc(func_idx)
    }
    // GC proposal reference instructions
    0xD3 => RefIsNull // ref.eq - compare two references, treat as ref.is_null for now
    0xD4 => Nop // ref.as_non_null - just pass through for now
    0xD5 => BrOnNull(parser.read_u32_leb128()) // br_on_null labelidx
    0xD6 => BrOnNonNull(parser.read_u32_leb128()) // br_on_non_null labelidx

    // Numeric instructions - constants
    0x41 => I32Const(parser.read_i32_leb128().reinterpret_as_uint())
    0x42 => I64Const(parser.read_i64_leb128().reinterpret_as_uint64())
    0x43 => F32Const(parser.read_f32())
    0x44 => F64Const(parser.read_f64())

    // i32 operations
    0x45 => I32Eqz
    0x46 => I32Eq
    0x47 => I32Ne
    0x48 => I32LtS
    0x49 => I32LtU
    0x4A => I32GtS
    0x4B => I32GtU
    0x4C => I32LeS
    0x4D => I32LeU
    0x4E => I32GeS
    0x4F => I32GeU

    // i64 operations
    0x50 => I64Eqz
    0x51 => I64Eq
    0x52 => I64Ne
    0x53 => I64LtS
    0x54 => I64LtU
    0x55 => I64GtS
    0x56 => I64GtU
    0x57 => I64LeS
    0x58 => I64LeU
    0x59 => I64GeS
    0x5A => I64GeU

    // f32 operations
    0x5B => F32Eq
    0x5C => F32Ne
    0x5D => F32Lt
    0x5E => F32Gt
    0x5F => F32Le
    0x60 => F32Ge

    // f64 operations
    0x61 => F64Eq
    0x62 => F64Ne
    0x63 => F64Lt
    0x64 => F64Gt
    0x65 => F64Le
    0x66 => F64Ge

    // i32 unary/binary operations
    0x67 => I32Clz
    0x68 => I32Ctz
    0x69 => I32Popcnt
    0x6A => I32Add
    0x6B => I32Sub
    0x6C => I32Mul
    0x6D => I32DivS
    0x6E => I32DivU
    0x6F => I32RemS
    0x70 => I32RemU
    0x71 => I32And
    0x72 => I32Or
    0x73 => I32Xor
    0x74 => I32Shl
    0x75 => I32ShrS
    0x76 => I32ShrU
    0x77 => I32Rotl
    0x78 => I32Rotr

    // i64 unary/binary operations
    0x79 => I64Clz
    0x7A => I64Ctz
    0x7B => I64Popcnt
    0x7C => I64Add
    0x7D => I64Sub
    0x7E => I64Mul
    0x7F => I64DivS
    0x80 => I64DivU
    0x81 => I64RemS
    0x82 => I64RemU
    0x83 => I64And
    0x84 => I64Or
    0x85 => I64Xor
    0x86 => I64Shl
    0x87 => I64ShrS
    0x88 => I64ShrU
    0x89 => I64Rotl
    0x8A => I64Rotr

    // f32 unary/binary operations
    0x8B => F32Abs
    0x8C => F32Neg
    0x8D => F32Ceil
    0x8E => F32Floor
    0x8F => F32Trunc
    0x90 => F32Nearest
    0x91 => F32Sqrt
    0x92 => F32Add
    0x93 => F32Sub
    0x94 => F32Mul
    0x95 => F32Div
    0x96 => F32Min
    0x97 => F32Max
    0x98 => F32Copysign

    // f64 unary/binary operations
    0x99 => F64Abs
    0x9A => F64Neg
    0x9B => F64Ceil
    0x9C => F64Floor
    0x9D => F64Trunc
    0x9E => F64Nearest
    0x9F => F64Sqrt
    0xA0 => F64Add
    0xA1 => F64Sub
    0xA2 => F64Mul
    0xA3 => F64Div
    0xA4 => F64Min
    0xA5 => F64Max
    0xA6 => F64Copysign

    // Conversion instructions
    0xA7 => I32WrapI64
    0xA8 => I32TruncF32S
    0xA9 => I32TruncF32U
    0xAA => I32TruncF64S
    0xAB => I32TruncF64U
    0xAC => I64ExtendI32S
    0xAD => I64ExtendI32U
    0xAE => I64TruncF32S
    0xAF => I64TruncF32U
    0xB0 => I64TruncF64S
    0xB1 => I64TruncF64U
    0xB2 => F32ConvertI32S
    0xB3 => F32ConvertI32U
    0xB4 => F32ConvertI64S
    0xB5 => F32ConvertI64U
    0xB6 => F32DemoteF64
    0xB7 => F64ConvertI32S
    0xB8 => F64ConvertI32U
    0xB9 => F64ConvertI64S
    0xBA => F64ConvertI64U
    0xBB => F64PromoteF32
    0xBC => I32ReinterpretF32
    0xBD => I64ReinterpretF64
    0xBE => F32ReinterpretI32
    0xBF => F64ReinterpretI64

    // Sign extension instructions
    0xC0 => I32Extend8S
    0xC1 => I32Extend16S
    0xC2 => I64Extend8S
    0xC3 => I64Extend16S
    0xC4 => I64Extend32S
    // Multi-byte instructions (0xFC prefix)
    0xFC => {
      let sub_opcode = parser.read_u32_leb128()
      match sub_opcode {
        // Saturating truncation instructions
        0x00 => I32TruncSatF32S
        0x01 => I32TruncSatF32U
        0x02 => I32TruncSatF64S
        0x03 => I32TruncSatF64U
        0x04 => I64TruncSatF32S
        0x05 => I64TruncSatF32U
        0x06 => I64TruncSatF64S
        0x07 => I64TruncSatF64U
        // Bulk memory instructions
        0x08 => {
          // memory.init data_idx mem_idx
          let data_idx = parser.read_u32_leb128()
          let mem_idx = parser.read_u32_leb128()
          guard mem_idx == 0 else {
            raise ValidationError::TypeMismatch(
              "memory.init: multi-memory not supported, mem_idx must be 0",
            )
          }
          MemoryInit(data_idx)
        }
        0x09 => {
          // data.drop data_idx
          let data_idx = parser.read_u32_leb128()
          DataDrop(data_idx)
        }
        0x0A => {
          // memory.copy mem_idx_dst mem_idx_src
          let mem_idx_dst = parser.read_u32_leb128()
          let mem_idx_src = parser.read_u32_leb128()
          guard mem_idx_dst == 0 && mem_idx_src == 0 else {
            raise ValidationError::TypeMismatch(
              "memory.copy: multi-memory not supported, both indices must be 0",
            )
          }
          MemoryCopy
        }
        0x0B => {
          // memory.fill mem_idx
          let mem_idx = parser.read_u32_leb128()
          guard mem_idx == 0 else {
            raise ValidationError::TypeMismatch(
              "memory.fill: multi-memory not supported, mem_idx must be 0",
            )
          }
          MemoryFill
        }
        0x0C => {
          // table.init elem_idx table_idx
          let elem_idx = parser.read_u32_leb128()
          let table_idx = parser.read_u32_leb128()
          TableInit(table_idx, elem_idx)
        }
        0x0D => {
          // elem.drop elem_idx
          let elem_idx = parser.read_u32_leb128()
          ElemDrop(elem_idx)
        }
        0x0E => {
          // table.copy table_idx_dst table_idx_src
          let table_idx_dst = parser.read_u32_leb128()
          let table_idx_src = parser.read_u32_leb128()
          TableCopy(table_idx_dst, table_idx_src)
        }
        // table.grow
        0x0F => {
          let table_idx = parser.read_u32_leb128()
          TableGrow(table_idx)
        }
        // table.size
        0x10 => {
          let table_idx = parser.read_u32_leb128()
          TableSize(table_idx)
        }
        _ =>
          raise ValidationError::TypeMismatch(
            "unknown 0xFC sub-opcode: \{sub_opcode}",
          )
      }
    }
    _ =>
      raise ValidationError::TypeMismatch(
        "unknown opcode: 0x\{opcode.to_string().to_upper()}",
      )
  }
}

// Parse block type (can be empty, a value type, or a type index)

///|
fn parse_blocktype(parser : Parser) -> BlockType raise ParseError {
  let byte = parser.read_byte()
  match byte {
    0x40 => Empty // empty block type
    0x7F => Value(I32)
    0x7E => Value(I64)
    0x7D => Value(F32)
    0x7C => Value(F64)
    0x7B => Value(V128)
    0x70 => Value(FuncRef)
    0x6F => Value(ExternRef)
    0x6E => Value(AnyRef)
    0x6D => Value(EqRef)
    0x6C => Value(I31Ref)
    0x6B => Value(StructRef)
    0x6A => Value(ArrayRef)
    0x69 => Value(ExnRef)
    0x71 => Value(NullRef)
    0x72 => Value(NullExternRef)
    0x73 => Value(NullFuncRef)
    0x74 => Value(NullExnRef)
    // GC proposal: (ref null $t) - nullable typed reference
    0x63 => {
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, true))
    }
    // GC proposal: (ref $t) - non-null typed reference
    0x64 => {
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, false))
    }
    _ => {
      // Type index encoded as signed LEB128
      // Put the byte back and read as signed LEB128
      parser.pos = parser.pos - 1
      let type_idx = parser.read_i32_leb128()
      TypeIndex(type_idx)
    }
  }
}
