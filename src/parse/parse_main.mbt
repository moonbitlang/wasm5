///|
pub fn parse(b : Bytes) -> @core.Module raise {
  let parser = Parser::new(b)
  guard parser.view() is [0x00, 0x61, 0x73, 0x6D, .. rest] else {
    raise ParseError::InvalidMagic
  }
  parser.update_view(rest)
  guard parser.view() is [0x01, 0x00, 0x00, 0x00, .. rest] else {
    raise ParseError::UnsupportedVersion
  }
  parser.update_view(rest)

  // Parse sections
  let mut types : Array[@core.FuncType] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[@core.TableType] = []
  let mut mems : Array[@core.MemType] = []
  let mut globals : Array[@core.Global] = []
  let mut elems : Array[@core.Elem] = []
  let mut datas : Array[@core.Data] = []
  let mut start : UInt? = None
  let mut imports : Array[@core.Import] = []
  let mut exports : Array[@core.Export] = []
  let mut codes : Array[@core.Code] = []
  while !parser.eof() {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.pos
    match section_id {
      1 => types = parse_type_section(parser)
      2 => imports = parse_import_section(parser)
      3 => funcs = parse_function_section(parser)
      4 => tables = parse_table_section(parser)
      5 => mems = parse_memory_section(parser)
      6 => globals = parse_global_section(parser)
      7 => exports = parse_export_section(parser)
      8 => start = Some(parser.read_u32_leb128())
      9 => elems = parse_element_section(parser)
      10 => codes = parse_code_section(parser)
      11 => datas = parse_data_section(parser)
      0 =>
        // Custom section - skip
        parser.pos = section_start + section_size.reinterpret_as_int()
      _ =>
        // Unknown section - skip it
        parser.pos = section_start + section_size.reinterpret_as_int()
    }
  }
  let module_ = @core.Module::{
    types,
    funcs,
    tables,
    mems,
    globals,
    elems,
    datas,
    start,
    imports,
    exports,
    codes,
  }

  // Validate the module
  @validate.validate_module(module_)
  module_
}
