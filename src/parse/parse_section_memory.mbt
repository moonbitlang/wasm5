// Section parsers: memory section

///|
fn parse_memory_section(
  parser : Parser,
) -> Array[@core.MemType] raise @errors.ParseError {
  let count = parser.read_u32_leb128()
  let mems = []
  for i in 0U..<count {
    let limits = parser.read_limits()
    mems.push(@core.MemType::{ limits, })
  }
  mems
}
