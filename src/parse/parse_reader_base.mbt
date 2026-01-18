///|
/// Parser for WASM binary format (Core WASM and Component Model)
pub struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
pub fn Parser::new(bytes : Bytes) -> Parser {
  { bytes, pos: 0 }
}

///|
/// Get current position
pub fn Parser::get_pos(self : Parser) -> Int {
  self.pos
}

///|
/// Set current position
pub fn Parser::set_pos(self : Parser, pos : Int) -> Unit {
  self.pos = pos
}

///|
pub fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
/// Returns the number of bytes remaining to be parsed.
pub fn Parser::remaining(self : Parser) -> Int {
  self.bytes.length() - self.pos
}

///|
pub fn Parser::read_byte(self : Parser) -> Byte raise ParseError {
  if self.pos < self.bytes.length() {
    let byte = self.bytes.unsafe_get(self.pos)
    self.pos = self.pos + 1
    byte
  } else {
    raise ParseError::UnexpectedEof
  }
}

///|
/// Peek at the next byte without consuming it.
pub fn Parser::peek_byte(self : Parser) -> Byte? {
  if self.pos < self.bytes.length() {
    Some(self.bytes.unsafe_get(self.pos))
  } else {
    None
  }
}

///|
pub fn Parser::read_bytes(
  self : Parser,
  n : UInt,
) -> BytesView raise ParseError {
  let n_int = UInt::reinterpret_as_int(n)
  guard n_int >= 0 else {
    raise ParseError::InvalidFormat("bytes length beyond Int max value")
  }
  if self.pos + n_int <= self.bytes.length() {
    let result = self.bytes[self.pos:self.pos + n_int]
    self.pos = self.pos + n_int
    result
  } else {
    let rem = self.remaining()
    raise ParseError::InvalidFormat(
      "need \{n_int} bytes but only \{rem} remaining",
    )
  }
}

///|
/// Skip n bytes.
pub fn Parser::skip(self : Parser, n : Int) -> Unit raise ParseError {
  if self.pos + n <= self.bytes.length() {
    self.pos = self.pos + n
  } else {
    let rem = self.remaining()
    raise ParseError::InvalidFormat(
      "need to skip \{n} bytes but only \{rem} remaining",
    )
  }
}
