// Section parsers: data section

///|
fn parse_data_section(parser : Parser) -> Array[@core.Data] raise {
  let count = parser.read_u32_leb128()
  let datas = []
  for i in 0U..<count {
    // Read flags to determine encoding format
    let flags = parser.read_u32_leb128()
    let is_active = flags == 0 || flags == 2
    let (mem_idx, offset) = match flags {
      0 =>
        // Active segment with implicit memory 0
        (0U, parse_expr(parser))
      1 =>
        // Passive segment - no memory index or offset
        (0U, @core.Expr::{ instrs: [I32Const(0U)] }) // Dummy offset
      2 =>
        // Active segment with explicit memory index
        (parser.read_u32_leb128(), parse_expr(parser))
      _ =>
        // Unknown flag - try old format
        // Treat flags value as mem_idx
        (flags, parse_expr(parser))
    }
    let init_len = parser.read_u32_leb128()
    let init = parser.read_bytes(init_len)
    datas.push(@core.Data::{ mem_idx, offset, init, is_active })
  }
  datas
}
