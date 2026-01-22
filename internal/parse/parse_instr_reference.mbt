///|
fn parse_instr_reference(
  parser : Parser,
  opcode : Byte,
) -> @core.Instr? raise ParseError {
  match opcode {
    // GC proposal: ref.as_non_null - check reference is not null
    0x16 => {
      let _ = parser.read_u32_leb128() // type index
      Some(Nop) // Placeholder - needs proper implementation
    }
    // Reference instructions
    0xD0 => {
      // ref.null heaptype
      let heap_type = parser.read_byte()
      let ref_type : @core.RefType = match heap_type {
        0x70 => Func // funcref
        0x6F => Extern // externref
        0x6E => Any // anyref
        0x6D => Eq // eqref
        0x6C => I31 // i31ref
        0x6B => Struct // structref
        0x6A => Array // arrayref
        0x69 => Exn // exnref
        0x71 => None // none
        0x72 => NoExtern // noextern
        0x73 => NoFunc // nofunc
        0x74 => NoExn // noexn
        _ => {
          // Assume it's a type index (negative or positive)
          parser.pos = parser.pos - 1
          let type_idx = parser.read_i32_leb128()
          TypeIndex(type_idx)
        }
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
    0xD3 => Some(RefEq) // ref.eq
    0xD4 => Some(RefAsNonNull) // ref.as_non_null
    0xD5 => Some(BrOnNull(parser.read_u32_leb128()))
    0xD6 => Some(BrOnNonNull(parser.read_u32_leb128()))
    _ => None
  }
}
