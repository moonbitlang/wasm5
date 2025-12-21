// Parse limits

///|
fn Parser::read_limits(self : Parser) -> @core.Limits raise @errors.ParseError {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}
