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
      let view = parser.view()
      let ref_type : @core.RefType = match view {
        [0x70, .. rest] => {
          parser.update_view(rest)
          Func
        }
        [0x6F, .. rest] => {
          parser.update_view(rest)
          Extern
        }
        [0x6E, .. rest] => {
          parser.update_view(rest)
          Any
        }
        [0x6D, .. rest] => {
          parser.update_view(rest)
          Eq
        }
        [0x6C, .. rest] => {
          parser.update_view(rest)
          I31
        }
        [0x6B, .. rest] => {
          parser.update_view(rest)
          Struct
        }
        [0x6A, .. rest] => {
          parser.update_view(rest)
          Array
        }
        [0x69, .. rest] => {
          parser.update_view(rest)
          Exn
        }
        [0x71, .. rest] => {
          parser.update_view(rest)
          None
        }
        [0x72, .. rest] => {
          parser.update_view(rest)
          NoExtern
        }
        [0x73, .. rest] => {
          parser.update_view(rest)
          NoFunc
        }
        [0x74, .. rest] => {
          parser.update_view(rest)
          NoExn
        }
        [_, ..] => {
          // Assume it's a type index (negative or positive)
          let type_idx = parser.read_i32_leb128()
          TypeIndex(type_idx)
        }
        _ => raise ParseError::UnexpectedEof
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
