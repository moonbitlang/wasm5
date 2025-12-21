///|
priv enum Token {
  LParen
  RParen
  Atom(Bytes)
  StringLit(Bytes)
}

///|
priv struct Lexer {
  input : Bytes
  mut pos : Int
}

///|
fn Lexer::new(text : String) -> Lexer {
  { input: @encoding/utf8.encode(text), pos: 0 }
}

///|
fn Lexer::next(self : Lexer) -> Token? raise WatError {
  self.skip_ws_and_comments()
  if self.eof() {
    return None
  }
  match self.peek() {
    b'(' => {
      self.pos = self.pos + 1
      Some(LParen)
    }
    b')' => {
      self.pos = self.pos + 1
      Some(RParen)
    }
    b'"' => Some(StringLit(self.read_string()))
    _ => Some(Atom(self.read_atom()))
  }
}

///|
fn Lexer::read_atom(self : Lexer) -> Bytes {
  let start = self.pos
  while not(self.eof()) {
    let b = self.peek()
    if is_whitespace(b) || b == b'(' || b == b')' {
      break
    }
    self.pos = self.pos + 1
  }
  self.input[start:self.pos].to_bytes()
}

///|
fn Lexer::read_string(self : Lexer) -> Bytes raise WatError {
  self.pos = self.pos + 1
  let out : Array[Byte] = []
  while not(self.eof()) {
    let b = self.next_byte()
    if b == b'"' {
      return Bytes::from_array(out)
    }
    if b == b'\\' {
      if self.eof() {
        raise WatError::InvalidSyntax("unterminated string escape")
      }
      let esc = self.next_byte()
      match esc {
        b'"' => out.push(b'"')
        b'\\' => out.push(b'\\')
        b'n' => out.push(b'\n')
        b't' => out.push(b'\t')
        b'r' => out.push(b'\r')
        _ =>
          if is_hex(esc) {
            let hi = hex_value(esc) catch {
              _ => raise WatError::InvalidSyntax("invalid hex escape")
            }
            guard not(self.eof()) else {
              raise WatError::InvalidSyntax("truncated hex escape")
            }
            let lo = self.next_byte()
            guard is_hex(lo) else {
              raise WatError::InvalidSyntax("invalid hex escape")
            }
            let value = (hi << 4) | hex_value(lo)
            out.push(value.to_byte())
          } else {
            raise WatError::InvalidSyntax("unsupported escape")
          }
      }
      continue
    }
    out.push(b)
  }
  raise WatError::InvalidSyntax("unterminated string literal")
}

///|
fn Lexer::skip_ws_and_comments(self : Lexer) -> Unit raise WatError {
  while true {
    let mut progressed = false
    while not(self.eof()) && is_whitespace(self.peek()) {
      self.pos = self.pos + 1
      progressed = true
    }
    if self.starts_with(b";;") {
      self.pos = self.pos + 2
      while not(self.eof()) && self.peek() != b'\n' {
        self.pos = self.pos + 1
      }
      progressed = true
      continue
    }
    if self.starts_with(b"(;") {
      self.pos = self.pos + 2
      let mut depth = 1
      while depth > 0 {
        guard not(self.eof()) else {
          raise WatError::InvalidSyntax("unterminated block comment")
        }
        if self.starts_with(b"(;") {
          self.pos = self.pos + 2
          depth = depth + 1
          continue
        }
        if self.starts_with(b";)") {
          self.pos = self.pos + 2
          depth = depth - 1
          continue
        }
        self.pos = self.pos + 1
      }
      progressed = true
      continue
    }
    if not(progressed) {
      break
    }
  }
}

///|
fn Lexer::starts_with(self : Lexer, prefix : Bytes) -> Bool {
  let end = self.pos + prefix.length()
  guard end <= self.input.length() else { return false }
  let mut i = 0
  while i < prefix.length() {
    if self.input[self.pos + i] != prefix[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn Lexer::next_byte(self : Lexer) -> Byte {
  let b = self.input[self.pos]
  self.pos = self.pos + 1
  b
}

///|
fn Lexer::peek(self : Lexer) -> Byte {
  self.input[self.pos]
}

///|
fn Lexer::eof(self : Lexer) -> Bool {
  self.pos >= self.input.length()
}

///|
fn is_whitespace(b : Byte) -> Bool {
  b == b' ' || b == b'\n' || b == b'\t' || b == b'\r'
}

///|
fn is_hex(b : Byte) -> Bool {
  (b >= b'0' && b <= b'9') ||
  (b >= b'a' && b <= b'f') ||
  (b >= b'A' && b <= b'F')
}

///|
fn hex_value(b : Byte) -> UInt raise WatError {
  if b >= b'0' && b <= b'9' {
    return b.to_uint() - b'0'.to_uint()
  }
  if b >= b'a' && b <= b'f' {
    return b.to_uint() - b'a'.to_uint() + 10U
  }
  if b >= b'A' && b <= b'F' {
    return b.to_uint() - b'A'.to_uint() + 10U
  }
  raise WatError::InvalidSyntax("invalid hex digit")
}
