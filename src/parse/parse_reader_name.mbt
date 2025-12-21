// Read name (length-prefixed UTF-8 string)

///|
fn Parser::read_name(self : Parser) -> Bytes raise @errors.ParseError {
  let len = self.read_u32_leb128()
  let bytes = self.read_bytes(len)
  // For now, assume UTF-8 is valid
  bytes.to_bytes()
}
