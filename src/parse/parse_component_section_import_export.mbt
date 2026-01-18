// Import and Export section parsers (sections 10, 11)

///|
/// Parse externname - handles all discriminator types
fn parse_externname(parser : Parser) -> (Bytes, Bytes?) raise ParseError {
  let name_kind = parser.read_byte().to_uint()
  match name_kind {
    0x00 => (parser.read_name(), None) // kebab-name
    0x01 => {
      // Interface specifier (url format)
      let url_bytes = parser.read_name()
      (url_bytes, Some(url_bytes))
    }
    0x02 => (parser.read_name(), None) // URL
    0x03 => {
      // Relative integrity - skip hash, read name
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      (parser.read_name(), None)
    }
    0x04 => {
      // Locked dependency - skip hash, read name
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      (parser.read_name(), None)
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid externname kind: 0x\{name_kind.to_string()}",
      )
  }
}

///|
/// Parse component import (section 10)
fn parse_component_import(
  parser : Parser,
) -> @core.ComponentImport raise ParseError {
  let (name, url) = parse_externname(parser)
  let desc = parse_extern_desc(parser)
  @core.ComponentImport::{ name, url, desc }
}

///|
/// Parse component export (section 11)
/// Binary format (wasm-tools encoding):
/// export ::= externname sortidx externtypeopt
/// sortidx: sort + idx (where sort is 0x00=module, 0x01=func, 0x02=value, 0x03=type, 0x04=component, 0x05=instance)
/// externtypeopt: 0x00 (none) or externdesc
fn parse_component_export(
  parser : Parser,
) -> @core.ComponentExport raise ParseError {
  let (name, _url) = parse_externname(parser)

  // sortidx: 0x00 core-sort idx | component-sort idx
  // core-sort: 0x11 (module), 0x12 (instance), etc.
  // component-sort: 0x01 (func), 0x02 (value), 0x03 (type), 0x04 (component), 0x05 (instance)
  let sort_kind = parser.read_byte().to_uint()
  let kind = if sort_kind == 0x00 {
    // Core export: read core-sort byte then idx
    let core_sort = parser.read_byte().to_uint()
    let idx = parser.read_u32_leb128()
    match core_sort {
      0x11 => @core.ComponentExportKind::Module(idx)
      // Add other core sorts as needed (0x12=instance, etc.)
      _ =>
        raise ParseError::InvalidFormat(
          "invalid core export sort: 0x\{core_sort.to_string()}",
        )
    }
  } else {
    // Component export
    let idx = parser.read_u32_leb128()
    match sort_kind {
      0x01 => @core.ComponentExportKind::Func(idx)
      0x02 => @core.ComponentExportKind::Value(idx)
      0x03 => @core.ComponentExportKind::Type(idx)
      0x04 => @core.ComponentExportKind::Component(idx)
      0x05 => @core.ComponentExportKind::Instance(idx)
      _ =>
        raise ParseError::InvalidFormat(
          "invalid export sort kind: 0x\{sort_kind.to_string()}",
        )
    }
  }

  // externtypeopt: 0x00 = none, otherwise parse externdesc
  let externtypeopt_tag = parser.read_byte().to_uint()
  let extern_type : @core.ComponentExternDesc? = if externtypeopt_tag == 0x00 {
    None
  } else {
    // The tag byte we just read is the externdesc kind, so back up and parse
    parser.set_pos(parser.get_pos() - 1)
    Some(parse_extern_desc(parser))
  }
  @core.ComponentExport::{ name, kind, extern_type }
}
