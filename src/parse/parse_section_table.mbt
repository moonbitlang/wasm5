// Section parsers: table section

///|
fn parse_table_section(parser : Parser) -> Array[@core.TableType] raise {
  let count = parser.read_u32_leb128()
  let tables = []
  for i in 0U..<count {
    // GC proposal: tables can have encoding prefix:
    // - 0x40 0x00: reftype + limits + init_expr (explicit initializer)
    // - otherwise: reftype + limits (old format, implicit null init)
    match parser.peek_byte() {
      Some(0x40) => {
        let _ = parser.next_byte()
        // New encoding with explicit init expression
        // Skip the reserved byte (always 0x00)
        let _ = parser.next_byte()
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
      Some(_) => {
        // Old encoding: first byte is the reftype (always nullable)
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let limits = parser.read_limits()
        tables.push(@core.TableType::{ elem_type, limits, init: None, nullable })
      }
      None => raise ParseError::UnexpectedEof
    }
  }
  tables
}
