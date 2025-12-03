// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Parse a WebAssembly binary module
pub fn parse(b : Bytes) -> Module {
  let parser = Parser::new(b)

  // Parse magic number
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    abort("invalid magic number")
  }

  // Parse version
  let version = parser.read_bytes(4)
  if version[0].to_int() != 0x01 ||
    version[1].to_int() != 0x00 ||
    version[2].to_int() != 0x00 ||
    version[3].to_int() != 0x00 {
    abort("unsupported version")
  }

  // Parse sections
  let mut types : Array[FuncType] = []
  let mut funcs : Array[UInt] = []
  let mut tables : Array[TableType] = []
  let mut mems : Array[MemType] = []
  let mut globals : Array[Global] = []
  let mut elems : Array[Elem] = []
  let mut datas : Array[Data] = []
  let mut start : UInt? = None
  let mut imports : Array[Import] = []
  let mut exports : Array[Export] = []
  let mut codes : Array[Code] = []

  while not(parser.eof()) {
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
        parser.pos = section_start + section_size.to_int()
      _ => abort("unknown section id: \{section_id}")
    }
  }

  Module::{
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
}
