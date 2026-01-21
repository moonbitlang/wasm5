// Component Instance section parser (section 4)

///|
/// Parse component instance (section 4)
/// instance ::= 0x00 idx vec(instantiatearg)   // Instantiate
///            | 0x01 vec(export)               // FromExports
fn parse_component_instance(
  parser : Parser,
) -> @core.ComponentInstance raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Instantiate
      let component_idx = parser.read_u32_leb128()
      let arg_count = parser.read_u32_leb128()
      let args : Array[@core.InstantiateArg] = []
      for i = 0; i.reinterpret_as_uint() < arg_count; i = i + 1 {
        let name = parser.read_name()
        let sort = parser.read_byte().to_uint()
        let arg = if sort == 0x00 {
          // Core sort - read sub-sort
          let core_sort = parser.read_byte().to_uint()
          let idx = parser.read_u32_leb128()
          match core_sort {
            0x00 => @core.InstantiateArg::CoreFunc(name, idx)
            0x01 => @core.InstantiateArg::CoreTable(name, idx)
            0x02 => @core.InstantiateArg::CoreMemory(name, idx)
            0x03 => @core.InstantiateArg::CoreGlobal(name, idx)
            0x10 => @core.InstantiateArg::CoreType(name, idx)
            0x11 => @core.InstantiateArg::CoreModule(name, idx)
            0x12 => @core.InstantiateArg::CoreInstance(name, idx)
            _ =>
              raise ParseError::InvalidFormat(
                "invalid core sort in instantiate arg: \{core_sort}",
              )
          }
        } else {
          // Component sort
          let idx = parser.read_u32_leb128()
          match sort {
            0x01 => @core.InstantiateArg::Func(name, idx)
            0x02 => @core.InstantiateArg::Value(name, idx)
            0x03 => @core.InstantiateArg::Type(name, idx)
            0x04 => @core.InstantiateArg::Component(name, idx)
            0x05 => @core.InstantiateArg::Instance(name, idx)
            _ =>
              raise ParseError::InvalidFormat(
                "invalid instantiate arg sort: \{sort}",
              )
          }
        }
        args.push(arg)
      }
      @core.ComponentInstance::Instantiate(component_idx, args)
    }
    0x01 => {
      // From exports
      let export_count = parser.read_u32_leb128()
      let exports : Array[@core.ComponentExport] = []
      for i = 0; i.reinterpret_as_uint() < export_count; i = i + 1 {
        let export_val = parse_inline_export(parser)
        exports.push(export_val)
      }
      @core.ComponentInstance::FromExports(exports)
    }
    _ => raise ParseError::InvalidFormat("invalid component instance kind")
  }
}

///|
fn parse_inline_export(
  parser : Parser,
) -> @core.ComponentExport raise ParseError {
  // externname format supports multiple discriminators:
  // 0x00: kebab-name
  // 0x01: interface specifier (with optional integrity)
  // 0x02: url
  // 0x03: relative integrity (hash)
  // 0x04: locked dependency (hash + string)
  let name_kind = parser.read_byte().to_uint()
  let name = match name_kind {
    0x00 => parser.read_name() // kebab-name
    0x01 =>
      // Interface specifier - may have optional integrity prefix
      // For now, just read the name part
      parser.read_name()
    0x02 => parser.read_name() // URL format
    0x03 => {
      // Relative integrity - skip hash bytes and read name
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      parser.read_name()
    }
    0x04 => {
      // Locked dependency - skip hash bytes and read name
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      parser.read_name()
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid inline export externname kind: 0x\{name_kind.to_string()}",
      )
  }
  // sortidx ::= 0x00 <core:sort> <idx> | <sort> <idx>
  let sort = parser.read_byte().to_uint()
  let kind = if sort == 0x00 {
    // Core sort - read core:sort byte then idx
    let core_sort = parser.read_byte().to_uint()
    let idx = parser.read_u32_leb128()
    match core_sort {
      0x11 => @core.ComponentExportKind::Module(idx)
      // Other core sorts can be added as needed:
      // 0x00 => func, 0x01 => table, 0x02 => memory, 0x03 => global
      // 0x12 => core instance
      _ =>
        raise ParseError::InvalidFormat(
          "invalid core export sort: 0x\{core_sort.to_string()}",
        )
    }
  } else {
    // Component sort
    let idx = parser.read_u32_leb128()
    match sort {
      0x01 => @core.ComponentExportKind::Func(idx)
      0x02 => @core.ComponentExportKind::Value(idx)
      0x03 => @core.ComponentExportKind::Type(idx)
      0x04 => @core.ComponentExportKind::Component(idx)
      0x05 => @core.ComponentExportKind::Instance(idx)
      _ =>
        raise ParseError::InvalidFormat(
          "invalid export sort: 0x\{sort.to_string()}",
        )
    }
  }
  @core.ComponentExport::{ name, kind, extern_type: None }
}
