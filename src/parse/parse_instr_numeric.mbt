///|
fn parse_instr_numeric(parser : Parser, opcode : Byte) -> @core.Instr? raise {
  match opcode {
    // Numeric instructions - constants
    0x41 =>
      Some(
        @core.Instr::I32Const(parser.read_i32_leb128().reinterpret_as_uint()),
      )
    0x42 =>
      Some(
        @core.Instr::I64Const(parser.read_i64_leb128().reinterpret_as_uint64()),
      )
    0x43 => Some(@core.Instr::F32Const(parser.read_f32()))
    0x44 => Some(@core.Instr::F64Const(parser.read_f64()))

    // i32 operations
    0x45 => Some(@core.Instr::I32Eqz)
    0x46 => Some(@core.Instr::I32Eq)
    0x47 => Some(@core.Instr::I32Ne)
    0x48 => Some(@core.Instr::I32LtS)
    0x49 => Some(@core.Instr::I32LtU)
    0x4A => Some(@core.Instr::I32GtS)
    0x4B => Some(@core.Instr::I32GtU)
    0x4C => Some(@core.Instr::I32LeS)
    0x4D => Some(@core.Instr::I32LeU)
    0x4E => Some(@core.Instr::I32GeS)
    0x4F => Some(@core.Instr::I32GeU)

    // i64 operations
    0x50 => Some(@core.Instr::I64Eqz)
    0x51 => Some(@core.Instr::I64Eq)
    0x52 => Some(@core.Instr::I64Ne)
    0x53 => Some(@core.Instr::I64LtS)
    0x54 => Some(@core.Instr::I64LtU)
    0x55 => Some(@core.Instr::I64GtS)
    0x56 => Some(@core.Instr::I64GtU)
    0x57 => Some(@core.Instr::I64LeS)
    0x58 => Some(@core.Instr::I64LeU)
    0x59 => Some(@core.Instr::I64GeS)
    0x5A => Some(@core.Instr::I64GeU)

    // f32 operations
    0x5B => Some(@core.Instr::F32Eq)
    0x5C => Some(@core.Instr::F32Ne)
    0x5D => Some(@core.Instr::F32Lt)
    0x5E => Some(@core.Instr::F32Gt)
    0x5F => Some(@core.Instr::F32Le)
    0x60 => Some(@core.Instr::F32Ge)

    // f64 operations
    0x61 => Some(@core.Instr::F64Eq)
    0x62 => Some(@core.Instr::F64Ne)
    0x63 => Some(@core.Instr::F64Lt)
    0x64 => Some(@core.Instr::F64Gt)
    0x65 => Some(@core.Instr::F64Le)
    0x66 => Some(@core.Instr::F64Ge)

    // i32 unary/binary operations
    0x67 => Some(@core.Instr::I32Clz)
    0x68 => Some(@core.Instr::I32Ctz)
    0x69 => Some(@core.Instr::I32Popcnt)
    0x6A => Some(@core.Instr::I32Add)
    0x6B => Some(@core.Instr::I32Sub)
    0x6C => Some(@core.Instr::I32Mul)
    0x6D => Some(@core.Instr::I32DivS)
    0x6E => Some(@core.Instr::I32DivU)
    0x6F => Some(@core.Instr::I32RemS)
    0x70 => Some(@core.Instr::I32RemU)
    0x71 => Some(@core.Instr::I32And)
    0x72 => Some(@core.Instr::I32Or)
    0x73 => Some(@core.Instr::I32Xor)
    0x74 => Some(@core.Instr::I32Shl)
    0x75 => Some(@core.Instr::I32ShrS)
    0x76 => Some(@core.Instr::I32ShrU)
    0x77 => Some(@core.Instr::I32Rotl)
    0x78 => Some(@core.Instr::I32Rotr)

    // i64 unary/binary operations
    0x79 => Some(@core.Instr::I64Clz)
    0x7A => Some(@core.Instr::I64Ctz)
    0x7B => Some(@core.Instr::I64Popcnt)
    0x7C => Some(@core.Instr::I64Add)
    0x7D => Some(@core.Instr::I64Sub)
    0x7E => Some(@core.Instr::I64Mul)
    0x7F => Some(@core.Instr::I64DivS)
    0x80 => Some(@core.Instr::I64DivU)
    0x81 => Some(@core.Instr::I64RemS)
    0x82 => Some(@core.Instr::I64RemU)
    0x83 => Some(@core.Instr::I64And)
    0x84 => Some(@core.Instr::I64Or)
    0x85 => Some(@core.Instr::I64Xor)
    0x86 => Some(@core.Instr::I64Shl)
    0x87 => Some(@core.Instr::I64ShrS)
    0x88 => Some(@core.Instr::I64ShrU)
    0x89 => Some(@core.Instr::I64Rotl)
    0x8A => Some(@core.Instr::I64Rotr)

    // f32 unary/binary operations
    0x8B => Some(@core.Instr::F32Abs)
    0x8C => Some(@core.Instr::F32Neg)
    0x8D => Some(@core.Instr::F32Ceil)
    0x8E => Some(@core.Instr::F32Floor)
    0x8F => Some(@core.Instr::F32Trunc)
    0x90 => Some(@core.Instr::F32Nearest)
    0x91 => Some(@core.Instr::F32Sqrt)
    0x92 => Some(@core.Instr::F32Add)
    0x93 => Some(@core.Instr::F32Sub)
    0x94 => Some(@core.Instr::F32Mul)
    0x95 => Some(@core.Instr::F32Div)
    0x96 => Some(@core.Instr::F32Min)
    0x97 => Some(@core.Instr::F32Max)
    0x98 => Some(@core.Instr::F32Copysign)

    // f64 unary/binary operations
    0x99 => Some(@core.Instr::F64Abs)
    0x9A => Some(@core.Instr::F64Neg)
    0x9B => Some(@core.Instr::F64Ceil)
    0x9C => Some(@core.Instr::F64Floor)
    0x9D => Some(@core.Instr::F64Trunc)
    0x9E => Some(@core.Instr::F64Nearest)
    0x9F => Some(@core.Instr::F64Sqrt)
    0xA0 => Some(@core.Instr::F64Add)
    0xA1 => Some(@core.Instr::F64Sub)
    0xA2 => Some(@core.Instr::F64Mul)
    0xA3 => Some(@core.Instr::F64Div)
    0xA4 => Some(@core.Instr::F64Min)
    0xA5 => Some(@core.Instr::F64Max)
    0xA6 => Some(@core.Instr::F64Copysign)

    // Conversion instructions
    0xA7 => Some(@core.Instr::I32WrapI64)
    0xA8 => Some(@core.Instr::I32TruncF32S)
    0xA9 => Some(@core.Instr::I32TruncF32U)
    0xAA => Some(@core.Instr::I32TruncF64S)
    0xAB => Some(@core.Instr::I32TruncF64U)
    0xAC => Some(@core.Instr::I64ExtendI32S)
    0xAD => Some(@core.Instr::I64ExtendI32U)
    0xAE => Some(@core.Instr::I64TruncF32S)
    0xAF => Some(@core.Instr::I64TruncF32U)
    0xB0 => Some(@core.Instr::I64TruncF64S)
    0xB1 => Some(@core.Instr::I64TruncF64U)
    0xB2 => Some(@core.Instr::F32ConvertI32S)
    0xB3 => Some(@core.Instr::F32ConvertI32U)
    0xB4 => Some(@core.Instr::F32ConvertI64S)
    0xB5 => Some(@core.Instr::F32ConvertI64U)
    0xB6 => Some(@core.Instr::F32DemoteF64)
    0xB7 => Some(@core.Instr::F64ConvertI32S)
    0xB8 => Some(@core.Instr::F64ConvertI32U)
    0xB9 => Some(@core.Instr::F64ConvertI64S)
    0xBA => Some(@core.Instr::F64ConvertI64U)
    0xBB => Some(@core.Instr::F64PromoteF32)
    0xBC => Some(@core.Instr::I32ReinterpretF32)
    0xBD => Some(@core.Instr::I64ReinterpretF64)
    0xBE => Some(@core.Instr::F32ReinterpretI32)
    0xBF => Some(@core.Instr::F64ReinterpretI64)

    // Sign extension instructions
    0xC0 => Some(@core.Instr::I32Extend8S)
    0xC1 => Some(@core.Instr::I32Extend16S)
    0xC2 => Some(@core.Instr::I64Extend8S)
    0xC3 => Some(@core.Instr::I64Extend16S)
    0xC4 => Some(@core.Instr::I64Extend32S)
    _ => None
  }
}
