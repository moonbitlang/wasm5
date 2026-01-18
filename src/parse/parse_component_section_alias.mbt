// Alias section parser (section 5)

///|
/// Parse alias (section 5)
/// aliassecsort encoding:
/// - 0x00 + core-sort: core alias (core-sort: 0x00=module, 0x10=func, 0x11=table, 0x12=memory, 0x13=global, 0x14=type)
/// - 0x01: func
/// - 0x02: value
/// - 0x03: type
/// - 0x04: component
/// - 0x05: instance
fn parse_alias(parser : Parser) -> @core.Alias raise ParseError {
  let sort_byte = parser.read_byte().to_uint()

  // Parse aliassecsort - may be one or two bytes
  let kind = if sort_byte == 0x00 {
    // Core sort: read second byte for core-sort type
    let core_sort = parser.read_byte().to_uint()
    parse_core_alias_kind(core_sort)
  } else {
    // Component sort: single byte
    parse_component_alias_kind(sort_byte)
  }

  // Parse target
  let target_kind = parser.read_byte().to_uint()
  let target = match target_kind {
    0x00 => {
      // Export
      let instance_idx = parser.read_u32_leb128()
      let name = parser.read_name()
      @core.AliasTarget::Export(instance_idx, name)
    }
    0x01 => {
      // CoreExport
      let instance_idx = parser.read_u32_leb128()
      let name = parser.read_name()
      @core.AliasTarget::CoreExport(instance_idx, name)
    }
    0x02 => {
      // Outer
      let count = parser.read_u32_leb128()
      let idx = parser.read_u32_leb128()
      @core.AliasTarget::Outer(count, idx)
    }
    _ => raise ParseError::InvalidFormat("invalid alias target kind")
  }
  @core.Alias::{ kind, target }
}

///|
/// Parse core alias kind (after 0x00 prefix)
/// core-sort encoding in alias section:
/// - 0x00 = func
/// - 0x01 = table
/// - 0x02 = memory
/// - 0x03 = global
/// - 0x04 = tag
/// - 0x10 = type
/// - 0x11 = module
fn parse_core_alias_kind(core_sort : UInt) -> @core.AliasKind raise ParseError {
  match core_sort {
    0x00 => @core.AliasKind::CoreFunc
    0x01 => @core.AliasKind::CoreTable
    0x02 => @core.AliasKind::CoreMemory
    0x03 => @core.AliasKind::CoreGlobal
    0x04 => @core.AliasKind::CoreTag
    0x10 => @core.AliasKind::CoreType
    0x11 => @core.AliasKind::CoreModule
    _ => raise ParseError::InvalidFormat("invalid core alias sort")
  }
}

///|
/// Parse component alias kind
fn parse_component_alias_kind(sort : UInt) -> @core.AliasKind raise ParseError {
  match sort {
    0x01 => @core.AliasKind::Func
    0x02 => @core.AliasKind::Value
    0x03 => @core.AliasKind::Type
    0x04 => @core.AliasKind::Component
    0x05 => @core.AliasKind::Instance
    _ => raise ParseError::InvalidFormat("invalid component alias sort")
  }
}

///|
fn parse_alias_kind(sort : UInt) -> @core.AliasKind raise ParseError {
  match sort {
    0x00 => @core.AliasKind::CoreModule
    0x01 => @core.AliasKind::CoreType
    0x02 => @core.AliasKind::CoreTable
    0x03 => @core.AliasKind::CoreFunc
    0x04 => @core.AliasKind::CoreMemory
    0x05 => @core.AliasKind::CoreGlobal
    0x10 => @core.AliasKind::Type
    0x11 => @core.AliasKind::Component
    0x12 => @core.AliasKind::Instance
    0x13 => @core.AliasKind::Func
    0x14 => @core.AliasKind::Value
    _ => raise ParseError::InvalidFormat("invalid alias sort")
  }
}
