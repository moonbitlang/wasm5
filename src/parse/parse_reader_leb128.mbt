// LEB128 decoding

///|
pub fn Parser::read_u32_leb128(self : Parser) -> UInt raise ParseError {
  fn read_loop(shift : Int, result : UInt) -> UInt raise ParseError {
    let byte = self.read_byte()
    if shift >= 28 && (byte & 0x80) != 0 {
      raise ParseError::InvalidFormat(
        "LEB128 u32 overflow: too many continuation bytes",
      )
    }
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
      read_loop(shift + 7, new_result)
    }
  }

  read_loop(0, 0)
}

///|
pub fn Parser::read_u64_leb128(self : Parser) -> UInt64 raise ParseError {
  fn read_loop(shift : Int, result : UInt64) -> UInt64 raise ParseError {
    let byte = self.read_byte()
    if shift >= 63 && (byte & 0x80) != 0 {
      raise ParseError::InvalidFormat(
        "LEB128 u64 overflow: too many continuation bytes",
      )
    }
    if shift >= 63 && byte > 0x01 {
      raise ParseError::InvalidFormat(
        "LEB128 u64 overflow: value exceeds 64 bits",
      )
    }
    let value = byte.land(0x7f).to_uint64() << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      new_result
    } else {
      read_loop(shift + 7, new_result)
    }
  }

  read_loop(0, 0UL)
}

///|
pub fn Parser::read_i32_leb128(self : Parser) -> Int raise ParseError {
  let mut result = 0
  let mut shift = 0
  let mut byte = 0
  while true {
    byte = self.read_byte().to_int()
    result = result | ((byte & 0x7f) << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 35 {
      raise ParseError::InvalidFormat("LEB128 i32 too long")
    }
  }
  if shift < 32 && (byte & 0x40) != 0 {
    result = result | (-1 << shift)
  }
  result
}

///|
pub fn Parser::read_i64_leb128(self : Parser) -> Int64 raise ParseError {
  let mut result = 0L
  let mut shift = 0
  let mut byte = 0
  while true {
    byte = self.read_byte().to_int()
    result = result | ((byte & 0x7f).to_int64() << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 70 {
      raise ParseError::InvalidFormat("LEB128 i64 too long")
    }
  }
  if shift < 64 && (byte & 0x40) != 0 {
    result = result | (-1L << shift)
  }
  result
}
