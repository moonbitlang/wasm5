///|
priv struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
fn Parser::view(self : Parser) -> BytesView {
  self.bytes[self.pos:]
}

///|
fn Parser::update_view(self : Parser, view : BytesView) -> Unit {
  let offset = view.start_offset()
  self.pos = offset
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
fn Parser::read_bytes(self : Parser, n : UInt) -> BytesView raise ParseError {
  let n_int = UInt::reinterpret_as_int(n)
  guard n_int >= 0 else {
    raise ParseError::InvalidFormat("bytes length beyond Int max value")
  }
  let view = self.view()
  if n_int <= view.length() {
    let result = view[:n_int]
    self.update_view(view[n_int:])
    result
  } else {
    raise ParseError::UnexpectedEof
  }
}
