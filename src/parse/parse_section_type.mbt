// Section parsers: type section

///|
fn parse_single_type(parser : Parser) -> @core.FuncType raise {
  let tag = parser.next_byte()
  // Handle composite types from GC proposal
  match tag {
    // func type
    0x60 => {
      let param_count = parser.read_u32_leb128()
      let params = []
      for _ in 0U..<param_count {
        params.push(parser.read_valtype())
      }
      let result_count = parser.read_u32_leb128()
      let results = []
      for _ in 0U..<result_count {
        results.push(parser.read_valtype())
      }
      { params, results }
    }
    // struct type (GC proposal) - skip fields, return empty func type
    0x5F => {
      let field_count = parser.read_u32_leb128()
      for _ in 0U..<field_count {
        let _ = parser.read_valtype() // field type
        let _ = parser.next_byte()
        // mutability
      }
      { params: [], results: [] }
    }
    // array type (GC proposal) - skip element, return empty func type
    0x5E => {
      let _ = parser.read_valtype() // element type
      let _ = parser.next_byte() // mutability
      { params: [], results: [] }
    }
    _ =>
      raise @validate.ValidationError::TypeMismatch(
        "expected composite type tag, got 0x\{tag.to_string()}",
      )
  }
}

///|
fn parse_type_section(parser : Parser) -> Array[@core.FuncType] raise {
  let count = parser.read_u32_leb128()
  let types = []
  for i in 0U..<count {
    // GC proposal: handle recursive type groups and subtypes
    match parser.peek_byte() {
      // rec - recursive type group
      Some(0x4E) => {
        let _ = parser.next_byte()
        let rec_count = parser.read_u32_leb128()
        for _ in 0U..<rec_count {
          let func_type = parse_single_type(parser)
          types.push(func_type)
        }
        continue
      }
      // sub - subtype (with supertypes)
      Some(0x4F) => {
        let _ = parser.next_byte()
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let func_type = parse_single_type(parser)
        types.push(func_type)
        continue
      }
      // sub final - final subtype (with supertypes)
      Some(0x50) => {
        let _ = parser.next_byte()
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let func_type = parse_single_type(parser)
        types.push(func_type)
        continue
      }
      // Standard function type
      Some(0x60) => {
        let func_type = parse_single_type(parser)
        types.push(func_type)
      }
      Some(tag) =>
        raise @validate.ValidationError::TypeMismatch(
          "expected type tag, got 0x\{tag.to_string()}",
        )
      None => raise ParseError::UnexpectedEof
    }
  }
  types
}
