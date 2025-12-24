// Section parsers: type section

///|
fn parse_single_type(parser : Parser) -> @core.TypeDef raise {
  let tag = parser.read_byte()
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
      TypeDef::Func({ params, results })
    }
    // struct type (GC proposal)
    0x5F => {
      let field_count = parser.read_u32_leb128()
      let fields : Array[@core.FieldType] = []
      for _ in 0U..<field_count {
        let storage = parser.read_storage_type()
        let mut_byte = parser.read_byte()
        let mutable = match mut_byte {
          0x00 => false
          0x01 => true
          _ =>
            raise @validate.ValidationError::TypeMismatch(
              "invalid mutability byte: 0x\{mut_byte.to_string()}",
            )
        }
        fields.push({ storage, mutable })
      }
      TypeDef::Struct({ fields })
    }
    // array type (GC proposal)
    0x5E => {
      let storage = parser.read_storage_type()
      let mut_byte = parser.read_byte()
      let mutable = match mut_byte {
        0x00 => false
        0x01 => true
        _ =>
          raise @validate.ValidationError::TypeMismatch(
            "invalid mutability byte: 0x\{mut_byte.to_string()}",
          )
      }
      TypeDef::Array({ element: { storage, mutable } })
    }
    _ =>
      raise @validate.ValidationError::TypeMismatch(
        "expected composite type tag, got 0x\{tag.to_string()}",
      )
  }
}

///|
fn parse_type_section(parser : Parser) -> Array[@core.TypeDef] raise {
  let count = parser.read_u32_leb128()
  let types = []
  for i in 0U..<count {
    let tag = parser.read_byte()
    // GC proposal: handle recursive type groups and subtypes
    match tag {
      // rec - recursive type group
      0x4E => {
        let rec_count = parser.read_u32_leb128()
        for _ in 0U..<rec_count {
          let type_def = parse_single_type(parser)
          types.push(type_def)
        }
        continue
      }
      // sub - subtype (with supertypes)
      0x4F => {
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let type_def = parse_single_type(parser)
        types.push(type_def)
        continue
      }
      // sub final - final subtype (with supertypes)
      0x50 => {
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let type_def = parse_single_type(parser)
        types.push(type_def)
        continue
      }
      // Standard function type
      0x60 => {
        parser.pos = parser.pos - 1 // Put the byte back
        let type_def = parse_single_type(parser)
        types.push(type_def)
      }
      _ =>
        raise @validate.ValidationError::TypeMismatch(
          "expected type tag, got 0x\{tag.to_string()}",
        )
    }
  }
  types
}
