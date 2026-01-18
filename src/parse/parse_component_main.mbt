///|
/// Parse a WebAssembly Component binary
///
/// Component binary format:
/// - Magic: 0x00 0x61 0x73 0x6D (same as core WASM)
/// - Version: 0x0d 0x00 (Component Model version)
/// - Layer: 0x01 0x00 (Component layer)
/// - Sections: sequence of component sections
pub fn parse_component(b : Bytes) -> @core.Component raise ParseError {
  let parser = Parser::new(b)

  // Parse magic number (same as core WASM: \0asm)
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // Parse version - Component Model uses version 0x0d (13)
  let version = parser.read_bytes(2)
  if version[0].to_int() != 0x0d || version[1].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // Parse layer - Component layer is 0x01
  let layer = parser.read_bytes(2)
  if layer[0].to_int() != 0x01 || layer[1].to_int() != 0x00 {
    raise ParseError::InvalidLayer
  }

  // Parse sections
  let sections : Array[@core.ComponentSection] = []
  while not(parser.eof()) {
    let parsed = parse_section(parser)
    for section in parsed {
      sections.push(section)
    }
  }
  @core.Component::{ sections, }
}

///|
/// Parse a single component section (may return multiple items for vec sections)
fn parse_section(
  parser : Parser,
) -> Array[@core.ComponentSection] raise ParseError {
  let section_id = parser.read_byte().to_uint()
  let section_size = parser.read_u32_leb128()
  let section_start = parser.get_pos()
  let result : Array[@core.ComponentSection] = match section_id {
    0 =>
      // Section 0: Custom section
      [parse_custom_section(parser, section_size, section_start)]
    1 => {
      // Section 1: Core Module (single module, not vec-encoded)
      // The entire section content is the module bytes
      let module_bytes = parser.read_bytes(section_size).to_bytes()
      let module_ = parse(module_bytes) catch {
        e => raise ParseError::NestedError("\{e}")
      }
      [@core.ComponentSection::CoreModule(module_)]
    }
    2 => {
      // Section 2: Core Instance (vec)
      let count = parser.read_u32_leb128()
      let instances : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let instance = parse_core_instance(parser)
        instances.push(@core.ComponentSection::CoreInstance(instance))
      }
      instances
    }
    3 => {
      // Section 3: Core Type (vec)
      let count = parser.read_u32_leb128()
      let types : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let core_type = parse_core_type(parser)
        types.push(@core.ComponentSection::CoreType(core_type))
      }
      types
    }
    4 => {
      // Section 4: Component (single inline component)
      // The entire section content is the component bytes (like section 1 for core module)
      let component_bytes = parser.read_bytes(section_size).to_bytes()
      let component = parse_component(component_bytes)
      [@core.ComponentSection::Component(component)]
    }
    5 => {
      // Section 5: Component Instance (vec)
      let count = parser.read_u32_leb128()
      let instances : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let instance = parse_component_instance(parser)
        instances.push(@core.ComponentSection::Instance(instance))
      }
      instances
    }
    6 => {
      // Section 6: Alias (vec)
      let count = parser.read_u32_leb128()
      let aliases : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let alias_def = parse_alias(parser)
        aliases.push(@core.ComponentSection::Alias(alias_def))
      }
      aliases
    }
    7 => {
      // Section 7: Component Type (vec)
      // For top-level component/instance types, we need to pass the section boundary
      // because they don't have explicit decl_count prefix
      let section_end = section_start + section_size.reinterpret_as_int()
      let count = parser.read_u32_leb128()
      let types : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        // Pass section_end as boundary for the last type (or only type)
        // For multiple types, each type is self-delimiting except the last one
        let boundary = if i.reinterpret_as_uint() == count - 1U {
          Some(section_end)
        } else {
          None
        }
        let type_def = parse_component_type_def(parser, boundary)
        types.push(@core.ComponentSection::Type(type_def))
      }
      types
    }
    8 => {
      // Section 8: Canonical (vec)
      let count = parser.read_u32_leb128()
      let canons : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let canon = parse_canon(parser)
        canons.push(@core.ComponentSection::Canon(canon))
      }
      canons
    }
    9 => {
      // Section 9: Start (single)
      let start = parse_start(parser)
      [@core.ComponentSection::Start(start)]
    }
    10 => {
      // Section 10: Import (vec)
      let count = parser.read_u32_leb128()
      let imports : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let import_def = parse_component_import(parser)
        imports.push(@core.ComponentSection::Import(import_def))
      }
      imports
    }
    11 => {
      // Section 11: Export (vec)
      let count = parser.read_u32_leb128()
      let exports : Array[@core.ComponentSection] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        let export_def = parse_component_export(parser)
        exports.push(@core.ComponentSection::Export(export_def))
      }
      exports
    }
    _ => {
      // Unknown section - skip
      parser.skip(section_size.reinterpret_as_int())
      raise ParseError::UnsupportedSection(section_id)
    }
  }

  // Verify section was fully consumed
  let expected_end = section_start + section_size.reinterpret_as_int()
  if parser.get_pos() != expected_end {
    // Allow under-read for now (section may have padding)
    if parser.get_pos() < expected_end {
      parser.set_pos(expected_end)
    } else {
      raise ParseError::InvalidFormat("section size mismatch")
    }
  }
  result
}

///|
/// Parse custom section
fn parse_custom_section(
  parser : Parser,
  section_size : UInt,
  section_start : Int,
) -> @core.ComponentSection raise ParseError {
  let name = parser.read_name()
  let consumed = parser.get_pos() - section_start
  let remaining = section_size.reinterpret_as_int() - consumed
  guard remaining >= 0 else {
    raise ParseError::InvalidFormat("invalid custom section size")
  }
  let data = parser.read_bytes(remaining.reinterpret_as_uint()).to_bytes()
  @core.ComponentSection::Custom(@core.CustomSection::{
    name,
    data,
    placement: @core.CustomPlacement::Start,
  })
}
