// Parse limits

///|
fn Parser::read_limits(self : Parser) -> (@core.Limits, Bool) raise ParseError {
  let flags = self.read_byte()
  let has_max = (flags & 0x01) != 0
  let table64 = (flags & 0x04) != 0
  if (flags & 0xFA) != 0 {
    raise ParseError::InvalidFormat(
      "invalid table limits flags: 0x\{flags.to_int().to_string()}",
    )
  }
  let min = if table64 {
    self.read_u64_leb128()
  } else {
    self.read_u32_leb128().to_uint64()
  }
  let max = if has_max {
    Some(
      if table64 {
        self.read_u64_leb128()
      } else {
        self.read_u32_leb128().to_uint64()
      },
    )
  } else {
    None
  }
  ({ min, max }, table64)
}

///|
fn Parser::read_memtype(self : Parser) -> @core.MemType raise ParseError {
  let flags = self.read_byte()
  let has_max = (flags & 0x01) != 0
  let shared = (flags & 0x02) != 0
  let memory64 = (flags & 0x04) != 0
  if (flags & 0xF8) != 0 {
    raise ParseError::InvalidFormat(
      "invalid memory limits flags: 0x\{flags.to_int().to_string()}",
    )
  }
  if shared && not(has_max) {
    raise ParseError::InvalidFormat("shared memory requires maximum")
  }
  let min = if memory64 {
    self.read_u64_leb128()
  } else {
    self.read_u32_leb128().to_uint64()
  }
  let max = if has_max {
    Some(
      if memory64 {
        self.read_u64_leb128()
      } else {
        self.read_u32_leb128().to_uint64()
      },
    )
  } else {
    None
  }
  @core.MemType::{ limits: { min, max }, shared, memory64 }
}
