// Parse expression (sequence of instructions ending with 0x0B)

///|
fn parse_expr(parser : Parser) -> @core.Expr raise {
  let instrs = parse_instrs(parser)
  // parse_instrs puts back the 0x0B, we need to consume it
  let end_marker = parser.next_byte()
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
    match parser.peek_byte() {
      // End marker (0x0B) - leave it for the caller to handle
      Some(0x0B) => instrs
      // Else marker (0x05) - leave it for the if parser to handle
      Some(0x05) => instrs
      Some(opcode) => {
        let _ = parser.next_byte()
        instrs.push(parse_instr(parser, opcode))
        read_loop(instrs)
      }
      None => raise ParseError::UnexpectedEof
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
  match parser.peek_byte() {
    Some(0x40) => {
      let _ = parser.next_byte()
      Empty // empty block type
    }
    Some(0x7F) => {
      let _ = parser.next_byte()
      Value(I32)
    }
    Some(0x7E) => {
      let _ = parser.next_byte()
      Value(I64)
    }
    Some(0x7D) => {
      let _ = parser.next_byte()
      Value(F32)
    }
    Some(0x7C) => {
      let _ = parser.next_byte()
      Value(F64)
    }
    Some(0x7B) => {
      let _ = parser.next_byte()
      Value(V128)
    }
    Some(0x70) => {
      let _ = parser.next_byte()
      Value(FuncRef)
    }
    Some(0x6F) => {
      let _ = parser.next_byte()
      Value(ExternRef)
    }
    Some(0x6E) => {
      let _ = parser.next_byte()
      Value(AnyRef)
    }
    Some(0x6D) => {
      let _ = parser.next_byte()
      Value(EqRef)
    }
    Some(0x6C) => {
      let _ = parser.next_byte()
      Value(I31Ref)
    }
    Some(0x6B) => {
      let _ = parser.next_byte()
      Value(StructRef)
    }
    Some(0x6A) => {
      let _ = parser.next_byte()
      Value(ArrayRef)
    }
    Some(0x69) => {
      let _ = parser.next_byte()
      Value(ExnRef)
    }
    Some(0x71) => {
      let _ = parser.next_byte()
      Value(NullRef)
    }
    Some(0x72) => {
      let _ = parser.next_byte()
      Value(NullExternRef)
    }
    Some(0x73) => {
      let _ = parser.next_byte()
      Value(NullFuncRef)
    }
    Some(0x74) => {
      let _ = parser.next_byte()
      Value(NullExnRef)
    }
    // GC proposal: (ref null $t) - nullable typed reference
    Some(0x63) => {
      let _ = parser.next_byte()
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, true))
    }
    // GC proposal: (ref $t) - non-null typed reference
    Some(0x64) => {
      let _ = parser.next_byte()
      let heap_type = parser.read_heap_type()
      Value(Ref(heap_type, false))
    }
    Some(_) => {
      // Type index encoded as signed LEB128
      let type_idx = parser.read_i32_leb128()
      TypeIndex(type_idx)
    }
    None => raise ParseError::UnexpectedEof
  }
}
