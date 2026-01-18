// Start section parser (section 8)

///|
/// Parse component start (section 8)
fn parse_start(parser : Parser) -> @core.ComponentStart raise ParseError {
  let func_idx = parser.read_u32_leb128()
  let arg_count = parser.read_u32_leb128()
  let args : Array[UInt] = []
  for i = 0; i.reinterpret_as_uint() < arg_count; i = i + 1 {
    args.push(parser.read_u32_leb128())
  }
  let results = parser.read_u32_leb128()
  @core.ComponentStart::{ func_idx, args, results }
}
