// LEB128 decoding

///|
fn Parser::read_u32_leb128(self : Parser) -> UInt raise ParseError {
  fn read_loop(shift : Int, result : UInt) -> UInt raise ParseError {
    let byte = match self.view() {
      [value, .. rest] => {
        self.update_view(rest)
        value
      }
      _ => raise ParseError::UnexpectedEof
    }
    // Check for overflow: shift >= 28 means we're on the 5th byte (bits 28-34)
    // For a valid u32, the 5th byte must have value <= 0x0F (only 4 bits used)
    // and no continuation bit (high bit must be 0)
    if shift >= 28 && byte > 0x0F {
      raise ParseError::InvalidFormat(
        "LEB128 u32 overflow: value exceeds 32 bits",
      )
    }
    let value = byte.land(0x7f).to_uint() << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      new_result
    } else {
      if shift >= 28 {
        // Continuation bit set on 5th byte - invalid
        raise ParseError::InvalidFormat(
          "LEB128 u32 overflow: too many continuation bytes",
        )
      }
      read_loop(shift + 7, new_result)
    }
  }

  read_loop(0, 0)
}

///|
fn Parser::read_i32_leb128(self : Parser) -> Int raise ParseError {
  let mut result = 0
  let mut shift = 0
  let mut byte = 0
  while true {
    let next_byte = match self.view() {
      [value, .. rest] => {
        self.update_view(rest)
        value
      }
      _ => raise ParseError::UnexpectedEof
    }
    byte = next_byte.to_int()
    result = result | ((byte & 0x7f) << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 35 {
      raise ParseError::InvalidFormat("LEB128 i32 too long")
    }
  }

  // Sign extend: if the sign bit of the last 7-bit group is set
  // and we haven't filled all 32 bits, we need to sign extend
  if shift < 32 && (byte & 0x40) != 0 {
    // Set all bits from 'shift' to 31
    result = result | (-1 << shift)
  }
  result
}

///|
fn Parser::read_i64_leb128(self : Parser) -> Int64 raise ParseError {
  let mut result = 0L
  let mut shift = 0
  let mut byte = 0
  while true {
    let next_byte = match self.view() {
      [value, .. rest] => {
        self.update_view(rest)
        value
      }
      _ => raise ParseError::UnexpectedEof
    }
    byte = next_byte.to_int()
    result = result | ((byte & 0x7f).to_int64() << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 70 {
      raise ParseError::InvalidFormat("LEB128 i64 too long")
    }
  }

  // Sign extend: if the sign bit of the last 7-bit group is set
  // and we haven't filled all 64 bits, we need to sign extend
  if shift < 64 && (byte & 0x40) != 0 {
    // Set all bits from 'shift' to 63
    result = result | (-1L << shift)
  }
  result
}
