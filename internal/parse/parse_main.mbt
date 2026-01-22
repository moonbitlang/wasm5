///|
pub fn parse(b : Bytes) -> @core.Module raise ParseError {
  let parser = Parser::new(b)

  // Parse magic number
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // Parse version
  let version = parser.read_bytes(4)
  if version[0].to_int() != 0x01 ||
    version[1].to_int() != 0x00 ||
    version[2].to_int() != 0x00 ||
    version[3].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // Parse sections
  let mut types : Array[@core.TypeDef] = []
  let mut type_groups : Array[@core.TypeGroup] = []
  let customs : Array[@core.CustomSection] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[@core.TableType] = []
  let mut mems : Array[@core.MemType] = []
  let mut globals : Array[@core.Global] = []
  let mut tags : Array[@core.Tag] = []
  let mut elems : Array[@core.Elem] = []
  let mut datas : Array[@core.Data] = []
  let mut start : UInt? = None
  let mut imports : Array[@core.Import] = []
  let mut exports : Array[@core.Export] = []
  let mut codes : Array[@core.Code] = []
  let mut last_section : @core.SectionId? = None
  while not(parser.eof()) {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.pos
    match section_id {
      0 => {
        let name = parser.read_name()
        let consumed = parser.pos - section_start
        let remaining = section_size.reinterpret_as_int() - consumed
        guard remaining >= 0 else {
          raise ParseError::InvalidFormat("invalid custom section size")
        }
        let data = parser.read_bytes(remaining.reinterpret_as_uint()).to_bytes()
        let placement = match last_section {
          Some(kind) => @core.CustomPlacement::After(kind)
          None => @core.CustomPlacement::Start
        }
        customs.push(@core.CustomSection::{ name, data, placement })
        parser.pos = section_start + section_size.reinterpret_as_int()
      }
      1 => {
        let (parsed_types, parsed_groups) = parse_type_section(parser)
        types = parsed_types
        type_groups = parsed_groups
        last_section = Some(@core.SectionId::Type)
      }
      2 => {
        imports = parse_import_section(parser)
        last_section = Some(@core.SectionId::Import)
      }
      3 => {
        funcs = parse_function_section(parser)
        last_section = Some(@core.SectionId::Func)
      }
      4 => {
        tables = parse_table_section(parser)
        last_section = Some(@core.SectionId::Table)
      }
      5 => {
        mems = parse_memory_section(parser)
        last_section = Some(@core.SectionId::Memory)
      }
      6 => {
        globals = parse_global_section(parser)
        last_section = Some(@core.SectionId::Global)
      }
      13 => {
        tags = parse_tag_section(parser)
        last_section = Some(@core.SectionId::Tag)
      }
      7 => {
        exports = parse_export_section(parser)
        last_section = Some(@core.SectionId::Export)
      }
      8 => {
        start = Some(parser.read_u32_leb128())
        last_section = Some(@core.SectionId::Start)
      }
      9 => {
        elems = parse_element_section(parser)
        last_section = Some(@core.SectionId::Elem)
      }
      12 => {
        let _ = parser.read_u32_leb128()
        last_section = Some(@core.SectionId::DataCount)
        parser.pos = section_start + section_size.reinterpret_as_int()
      }
      10 => {
        codes = parse_code_section(parser)
        last_section = Some(@core.SectionId::Code)
      }
      11 => {
        datas = parse_data_section(parser)
        last_section = Some(@core.SectionId::Data)
      }
      _ =>
        // Unknown section - skip it
        parser.pos = section_start + section_size.reinterpret_as_int()
    }
  }
  let module_ = @core.Module::{
    types,
    type_groups,
    customs,
    funcs,
    tables,
    mems,
    globals,
    tags,
    elems,
    datas,
    start,
    imports,
    exports,
    codes,
  }

  // Validate the module
  @validate.validate_module(module_) catch {
    e => raise ParseError::InvalidFormat(e.to_string())
  }
  module_
}

///|
/// Parse a WebAssembly binary without validation (for debugging)
pub fn parse_novalidate(b : Bytes) -> @core.Module raise ParseError {
  parse_skip_validation(b)
}

///|
/// Internal parse function that skips validation
fn parse_skip_validation(b : Bytes) -> @core.Module raise ParseError {
  let parser = Parser::new(b)

  // Parse magic number
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // Parse version
  let version = parser.read_bytes(4)
  if version[0].to_int() != 0x01 ||
    version[1].to_int() != 0x00 ||
    version[2].to_int() != 0x00 ||
    version[3].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // Parse sections
  let mut types : Array[@core.TypeDef] = []
  let mut type_groups : Array[@core.TypeGroup] = []
  let customs : Array[@core.CustomSection] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[@core.TableType] = []
  let mut mems : Array[@core.MemType] = []
  let mut globals : Array[@core.Global] = []
  let mut tags : Array[@core.Tag] = []
  let mut elems : Array[@core.Elem] = []
  let mut datas : Array[@core.Data] = []
  let mut start : UInt? = None
  let mut imports : Array[@core.Import] = []
  let mut exports : Array[@core.Export] = []
  let mut codes : Array[@core.Code] = []
  let mut last_section : @core.SectionId? = None
  while not(parser.eof()) {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.pos
    match section_id {
      0 => {
        let name = parser.read_name()
        let consumed = parser.pos - section_start
        let remaining = section_size.reinterpret_as_int() - consumed
        guard remaining >= 0 else {
          raise ParseError::InvalidFormat("invalid custom section size")
        }
        let data = parser.read_bytes(remaining.reinterpret_as_uint()).to_bytes()
        let placement = match last_section {
          Some(kind) => @core.CustomPlacement::After(kind)
          None => @core.CustomPlacement::Start
        }
        customs.push(@core.CustomSection::{ name, data, placement })
        parser.pos = section_start + section_size.reinterpret_as_int()
      }
      1 => {
        let (parsed_types, parsed_groups) = parse_type_section(parser)
        types = parsed_types
        type_groups = parsed_groups
        last_section = Some(@core.SectionId::Type)
      }
      2 => {
        imports = parse_import_section(parser)
        last_section = Some(@core.SectionId::Import)
      }
      3 => {
        funcs = parse_function_section(parser)
        last_section = Some(@core.SectionId::Func)
      }
      4 => {
        tables = parse_table_section(parser)
        last_section = Some(@core.SectionId::Table)
      }
      5 => {
        mems = parse_memory_section(parser)
        last_section = Some(@core.SectionId::Memory)
      }
      6 => {
        globals = parse_global_section(parser)
        last_section = Some(@core.SectionId::Global)
      }
      13 => {
        tags = parse_tag_section(parser)
        last_section = Some(@core.SectionId::Tag)
      }
      7 => {
        exports = parse_export_section(parser)
        last_section = Some(@core.SectionId::Export)
      }
      8 => {
        start = Some(parser.read_u32_leb128())
        last_section = Some(@core.SectionId::Start)
      }
      9 => {
        elems = parse_element_section(parser)
        last_section = Some(@core.SectionId::Elem)
      }
      12 => {
        let _ = parser.read_u32_leb128()
        last_section = Some(@core.SectionId::DataCount)
        parser.pos = section_start + section_size.reinterpret_as_int()
      }
      10 => {
        codes = parse_code_section(parser)
        last_section = Some(@core.SectionId::Code)
      }
      11 => {
        datas = parse_data_section(parser)
        last_section = Some(@core.SectionId::Data)
      }
      _ =>
        // Unknown section - skip it
        parser.pos = section_start + section_size.reinterpret_as_int()
    }
  }
  @core.Module::{
    types,
    type_groups,
    customs,
    funcs,
    tables,
    mems,
    globals,
    tags,
    elems,
    datas,
    start,
    imports,
    exports,
    codes,
  }
}
