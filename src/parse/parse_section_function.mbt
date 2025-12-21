// Section parsers: function section

///|
fn parse_function_section(
  parser : Parser,
) -> Array[UInt] raise @errors.ParseError {
  let count = parser.read_u32_leb128()
  let funcs = []
  for i in 0U..<count {
    funcs.push(parser.read_u32_leb128())
  }
  funcs
}
