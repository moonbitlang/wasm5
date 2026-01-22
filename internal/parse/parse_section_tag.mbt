// Section parsers: tag section (exception handling)

///|
fn parse_tag_section(parser : Parser) -> Array[@core.Tag] raise {
  let count = parser.read_u32_leb128()
  let tags : Array[@core.Tag] = []
  for _ in 0U..<count {
    let attr = parser.read_byte()
    guard attr == 0x00 else {
      raise @validate.ValidationError::TypeMismatch(
        "invalid tag attribute: 0x\{attr.to_string()}",
      )
    }
    let type_idx = parser.read_u32_leb128()
    tags.push(@core.Tag::{ type_idx, })
  }
  tags
}
