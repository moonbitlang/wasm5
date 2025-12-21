///|
fn parse_instr_reference(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    // GC proposal: ref.as_non_null - check reference is not null
    0x16 => {
      let _ = parser.read_u32_leb128() // type index
      Some(Nop) // Placeholder - needs proper implementation
    }
    // Reference instructions
    0xD0 => {
      // ref.null heaptype
      let ref_type : @core.RefType = match parser.peek_byte() {
        Some(0x70) => {
          let _ = parser.next_byte()
          Func
        }
        Some(0x6F) => {
          let _ = parser.next_byte()
          Extern
        }
        Some(0x6E) => {
          let _ = parser.next_byte()
          Any
        }
        Some(0x6D) => {
          let _ = parser.next_byte()
          Eq
        }
        Some(0x6C) => {
          let _ = parser.next_byte()
          I31
        }
        Some(0x6B) => {
          let _ = parser.next_byte()
          Struct
        }
        Some(0x6A) => {
          let _ = parser.next_byte()
          Array
        }
        Some(0x69) => {
          let _ = parser.next_byte()
          Exn
        }
        Some(0x71) => {
          let _ = parser.next_byte()
          None
        }
        Some(0x72) => {
          let _ = parser.next_byte()
          NoExtern
        }
        Some(0x73) => {
          let _ = parser.next_byte()
          NoFunc
        }
        Some(0x74) => {
          let _ = parser.next_byte()
          NoExn
        }
        Some(_) => {
          // Assume it's a type index (negative or positive)
          let type_idx = parser.read_i32_leb128()
          TypeIndex(type_idx)
        }
        None => raise ParseError::UnexpectedEof
      }
      Some(RefNull(ref_type))
    }
    0xD1 => Some(RefIsNull) // ref.is_null
    0xD2 => {
      // ref.func funcidx
      let func_idx = parser.read_u32_leb128()
      Some(RefFunc(func_idx))
    }
    // GC proposal reference instructions
    0xD3 => Some(RefIsNull) // ref.eq - treat as ref.is_null for now
    0xD4 => Some(Nop) // ref.as_non_null - placeholder
    0xD5 => Some(BrOnNull(parser.read_u32_leb128()))
    0xD6 => Some(BrOnNonNull(parser.read_u32_leb128()))
    _ => None
  }
}
