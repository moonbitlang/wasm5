// Section parsers: export section

///|
fn parse_export_section(
  parser : Parser,
) -> Array[@core.Export] raise ParseError {
  let count = parser.read_u32_leb128()
  let exports = []
  for i in 0U..<count {
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc : @core.ExportDesc = match desc_tag {
      0x00 => Func(parser.read_u32_leb128())
      0x01 => Table(parser.read_u32_leb128())
      0x02 => Mem(parser.read_u32_leb128())
      0x03 => Global(parser.read_u32_leb128())
      // Exception handling: tag export
      0x04 => Tag(parser.read_u32_leb128())
      _ =>
        raise ParseError::InvalidFormat(
          "invalid export descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    exports.push(@core.Export::{ name, desc })
  }
  exports
}
