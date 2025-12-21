///|
fn parse_instr_reference(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    // GC proposal: ref.as_non_null - check reference is not null
    0x16 => {
      let _ = parser.read_u32_leb128() // type index
      Some(@core.Instr::Nop) // Placeholder - needs proper implementation
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
      Some(@core.Instr::RefNull(ref_type))
    }
    0xD1 => Some(@core.Instr::RefIsNull) // ref.is_null
    0xD2 => {
      // ref.func funcidx
      let func_idx = parser.read_u32_leb128()
      Some(@core.Instr::RefFunc(func_idx))
    }
    // GC proposal reference instructions
    0xD3 => Some(@core.Instr::RefIsNull) // ref.eq - treat as ref.is_null for now
    0xD4 => Some(@core.Instr::Nop) // ref.as_non_null - placeholder
    0xD5 => Some(@core.Instr::BrOnNull(parser.read_u32_leb128()))
    0xD6 => Some(@core.Instr::BrOnNonNull(parser.read_u32_leb128()))
    _ => None
  }
}
