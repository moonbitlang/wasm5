// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> @core.Expr raise {
  let instrs = parse_instrs(parser)
  // parse_instrs puts back the 0x0B, we need to consume it
  let end_marker = parser.read_byte()
  guard end_marker == 0x0B else {
    raise ParseError::InvalidFormat(
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
  if opcode == 0xFC {
    return parse_instr_prefix_fc(parser)
  }
  if opcode == 0xFD {
    return parse_instr_prefix_fd(parser)
  }
  if opcode == 0xFE {
    return parse_instr_prefix_fe(parser)
  }
  let instr = parse_instr_control(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_parametric(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_variable(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_table(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_memory(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_reference(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  let instr = parse_instr_numeric(parser, opcode)
  match instr {
    Some(value) => return value
    None => ()
  }
  raise @validate.ValidationError::TypeMismatch(
    "unknown opcode: 0x\{opcode.to_string().to_upper()}",
  )
}

// Parse block type (can be empty, a value type, or a type index)

///|
fn parse_blocktype(parser : Parser) -> @core.BlockType raise ParseError {
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
