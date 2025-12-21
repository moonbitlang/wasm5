// Memarg and numeric readers

///|
/// Parse memory argument (memarg) with multi-memory support
/// Returns (align, offset, memory_index)
/// In multi-memory proposal, the first byte encodes:
/// - bits 0-5: alignment (log2)
/// - bit 6: if set, memory index follows
/// If bit 6 is not set, memory index defaults to 0
fn Parser::read_memarg(self : Parser) -> (UInt, UInt, UInt) raise ParseError {
  let flags_and_align = self.read_u32_leb128()
  let align = flags_and_align & 0x3F // bits 0-5
  let has_memory_index = (flags_and_align & 0x40) != 0 // bit 6
  let memory_idx = if has_memory_index { self.read_u32_leb128() } else { 0 }
  let offset = self.read_u32_leb128()
  (align, offset, memory_idx)
}

///|
fn Parser::read_f32(self : Parser) -> Float raise ParseError {
  Float::reinterpret_from_uint(self.take_u32le())
}

///|
fn Parser::read_f64(self : Parser) -> Double raise ParseError {
  UInt64::reinterpret_as_double(self.take_u64le())
}
