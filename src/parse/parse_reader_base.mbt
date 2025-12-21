///|
priv struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
fn Parser::new(bytes : Bytes) -> Parser {
  { bytes, pos: 0 }
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn Parser::read_byte(self : Parser) -> Byte raise @errors.ParseError {
  if self.pos < self.bytes.length() {
    let byte = self.bytes.unsafe_get(self.pos)
    self.pos = self.pos + 1
    byte
  } else {
    raise @errors.ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_bytes(
  self : Parser,
  n : UInt,
) -> BytesView raise @errors.ParseError {
  let n_int = UInt::reinterpret_as_int(n)
  guard n_int >= 0 else {
    raise @errors.ParseError::InvalidFormat("bytes length beyond Int max value")
  }
  if self.pos + n_int <= self.bytes.length() {
    let result = self.bytes[self.pos:self.pos + n_int]
    self.pos = self.pos + n_int
    result
  } else {
    raise @errors.ParseError::UnexpectedEof
  }
}
