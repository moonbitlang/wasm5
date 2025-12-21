// Parse limits

///|
fn Parser::read_limits(self : Parser) -> @core.Limits raise ParseError {
  let flags = match self.view() {
    [byte, .. rest] => {
      self.update_view(rest)
      byte
    }
    _ => raise ParseError::UnexpectedEof
  }
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}
