// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> @core.Expr raise {
  let instrs = parse_instrs(parser)
  // parse_instrs puts back the 0x0B, we need to consume it
  match parser.view() {
    [0x0B, .. rest] => parser.update_view(rest)
    [byte, ..] =>
      raise ParseError::InvalidFormat(
        "expected end marker 0x0B, got 0x\{byte.to_int().to_string()}",
      )
    _ => raise ParseError::UnexpectedEof
  }
  @core.Expr::{ instrs, }
}

// Parse instructions until 0x0B (end marker)

///|
fn parse_instrs(parser : Parser) -> Array[@core.Instr] raise {
  fn read_loop(instrs : Array[@core.Instr]) -> Array[@core.Instr] raise {
    match parser.view() {
      // End marker (0x0B) - leave it for the caller to handle
      [0x0B, ..] => instrs
      // Else marker (0x05) - leave it for the if parser to handle
      [0x05, ..] => instrs
      [opcode, .. rest] => {
        parser.update_view(rest)
        instrs.push(parse_instr(parser, opcode))
        read_loop(instrs)
      }
      _ => raise ParseError::UnexpectedEof
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
  match parser.view() {
    [0x40, .. rest] => {
      parser.update_view(rest)
      Empty // empty block type
    }
    [0x7F, .. rest] => {
      parser.update_view(rest)
      Value(I32)
    }
    [0x7E, .. rest] => {
      parser.update_view(rest)
      Value(I64)
    }
    [0x7D, .. rest] => {
      parser.update_view(rest)
      Value(F32)
    }
    [0x7C, .. rest] => {
      parser.update_view(rest)
      Value(F64)
    }
    [0x7B, .. rest] => {
      parser.update_view(rest)
      Value(V128)
    }
    [0x70, .. rest] => {
      parser.update_view(rest)
      Value(FuncRef)
    }
    [0x6F, .. rest] => {
      parser.update_view(rest)
      Value(ExternRef)
    }
    [0x6E, .. rest] => {
      parser.update_view(rest)
      Value(AnyRef)
    }
    [0x6D, .. rest] => {
      parser.update_view(rest)
      Value(EqRef)
    }
    [0x6C, .. rest] => {
      parser.update_view(rest)
      Value(I31Ref)
    }
    [0x6B, .. rest] => {
      parser.update_view(rest)
      Value(StructRef)
    }
    [0x6A, .. rest] => {
      parser.update_view(rest)
      Value(ArrayRef)
    }
    [0x69, .. rest] => {
      parser.update_view(rest)
      Value(ExnRef)
    }
    [0x71, .. rest] => {
      parser.update_view(rest)
      Value(NullRef)
    }
    [0x72, .. rest] => {
      parser.update_view(rest)
      Value(NullExternRef)
    }
    [0x73, .. rest] => {
      parser.update_view(rest)
      Value(NullFuncRef)
    }
    [0x74, .. rest] => {
      parser.update_view(rest)
      Value(NullExnRef)
    }
    // GC proposal: (ref null $t) - nullable typed reference
    [0x63, .. rest] => {
      parser.update_view(rest)
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, true))
    }
    // GC proposal: (ref $t) - non-null typed reference
    [0x64, .. rest] => {
      parser.update_view(rest)
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, false))
    }
    [_byte, ..] => {
      // Type index encoded as signed LEB128
      let type_idx = parser.read_i32_leb128()
      TypeIndex(type_idx)
    }
    _ => raise ParseError::UnexpectedEof
  }
}
