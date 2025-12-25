// Section parsers: memory section

///|
fn parse_memory_section(
  parser : Parser,
) -> Array[@core.MemType] raise ParseError {
  let count = parser.read_u32_leb128()
  let mems = []
  for i in 0U..<count {
    let mem_type = parser.read_memtype()
    mems.push(mem_type)
  }
  mems
}
