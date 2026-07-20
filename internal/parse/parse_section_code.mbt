// Section parsers: code section

///|
fn parse_code_section(parser : Parser) -> Array[@core.Code] raise ParseError {
  let count = parser.read_u32_leb128()
  let codes = []
  for _ in 0U..<count {
    let _code_size = parser.read_u32_leb128()

    // Parse locals
    let locals_count = parser.read_u32_leb128()
    let locals = []
    for _ in 0U..<locals_count {
      let n = parser.read_u32_leb128()
      let val_type = parser.read_valtype()
      for _ in 0U..<n {
        locals.push(val_type)
      }
    }

    // Parse body
    let body = parse_expr(parser)
    codes.push(@core.Code::{ locals, body, compiled: None, max_stack_height: 0 })
  }
  codes
}
