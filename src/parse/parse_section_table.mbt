// Section parsers: table section

///|
fn parse_table_section(parser : Parser) -> Array[@core.TableType] raise {
  let count = parser.read_u32_leb128()
  let tables = []
  for i in 0U..<count {
    // GC proposal: tables can have encoding prefix:
    // - 0x40 0x00: reftype + limits + init_expr (explicit initializer)
    // - otherwise: reftype + limits (old format, implicit null init)
    match parser.view() {
      [0x40, .. rest] => {
        parser.update_view(rest)
        // New encoding with explicit init expression
        // Skip the reserved byte (always 0x00)
        let _ = match parser.view() {
          [byte, .. tail] => {
            parser.update_view(tail)
            byte
          }
          _ => raise ParseError::UnexpectedEof
        }
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let limits = parser.read_limits()
        let init_expr = parse_expr(parser)
        tables.push(@core.TableType::{
          elem_type,
          limits,
          init: Some(init_expr),
          nullable,
        })
      }
      [_first_byte, ..] => {
        // Old encoding: first byte is the reftype (always nullable)
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let limits = parser.read_limits()
        tables.push(@core.TableType::{ elem_type, limits, init: None, nullable })
      }
      _ => raise ParseError::UnexpectedEof
    }
  }
  tables
}
