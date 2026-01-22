// Section parsers: type section

///|
fn parse_type_def_with_tag(
  parser : Parser,
  tag : Byte,
) -> @core.TypeDef raise ParseError {
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
      @core.TypeDef::Func(@core.FuncType::{ params, results })
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
            raise ParseError::InvalidFormat(
              "invalid mutability byte: 0x\{mut_byte.to_string()}",
            )
        }
        fields.push({ storage, mutable })
      }
      @core.TypeDef::Struct(@core.StructType::{ fields, })
    }
    // array type (GC proposal)
    0x5E => {
      let storage = parser.read_storage_type()
      let mut_byte = parser.read_byte()
      let mutable = match mut_byte {
        0x00 => false
        0x01 => true
        _ =>
          raise ParseError::InvalidFormat(
            "invalid mutability byte: 0x\{mut_byte.to_string()}",
          )
      }
      @core.TypeDef::Array(@core.ArrayType::{
        element: @core.FieldType::{ storage, mutable },
      })
    }
    _ =>
      raise ParseError::InvalidFormat(
        "expected composite type tag, got 0x\{tag.to_string()}",
      )
  }
}

///|
fn parse_type_def(parser : Parser) -> @core.TypeDef raise ParseError {
  parse_type_def_with_tag(parser, parser.read_byte())
}

///|
fn parse_subtype_entry_with_tag(
  parser : Parser,
  tag : Byte,
) -> (Array[UInt], Bool, @core.TypeDef) raise ParseError {
  match tag {
    0x4F | 0x50 => {
      let is_final = tag == 0x4F
      let supertype_count = parser.read_u32_leb128()
      let supertypes : Array[UInt] = []
      for _ in 0U..<supertype_count {
        supertypes.push(parser.read_u32_leb128())
      }
      let type_def = parse_type_def(parser)
      (supertypes, is_final, type_def)
    }
    0x60 | 0x5F | 0x5E => {
      let type_def = parse_type_def_with_tag(parser, tag)
      ([], true, type_def)
    }
    _ =>
      raise ParseError::InvalidFormat(
        "expected type tag, got 0x\{tag.to_string()}",
      )
  }
}

///|
fn parse_subtype_entry(
  parser : Parser,
) -> (Array[UInt], Bool, @core.TypeDef) raise ParseError {
  parse_subtype_entry_with_tag(parser, parser.read_byte())
}

///|
fn parse_type_section(
  parser : Parser,
) -> (Array[@core.TypeDef], Array[@core.TypeGroup]) raise ParseError {
  let count = parser.read_u32_leb128()
  let types = []
  let type_groups : Array[@core.TypeGroup] = []
  for _ in 0U..<count {
    let tag = parser.read_byte()
    match tag {
      0x4E => {
        let rec_count = parser.read_u32_leb128()
        let subtypes : Array[@core.SubTypeDef] = []
        for _ in 0U..<rec_count {
          let (supertypes, is_final, type_def) = parse_subtype_entry(parser)
          let type_idx = types.length().reinterpret_as_uint()
          types.push(type_def)
          subtypes.push(@core.SubTypeDef::{ type_idx, supertypes, is_final })
        }
        type_groups.push(@core.TypeGroup::{ subtypes, explicit: true })
      }
      _ => {
        let (supertypes, is_final, type_def) = parse_subtype_entry_with_tag(
          parser, tag,
        )
        let type_idx = types.length().reinterpret_as_uint()
        types.push(type_def)
        type_groups.push(@core.TypeGroup::{
          subtypes: [@core.SubTypeDef::{ type_idx, supertypes, is_final }],
          explicit: false,
        })
      }
    }
  }
  (types, type_groups)
}
