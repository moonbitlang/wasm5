// Parse limits

///|
fn Parser::read_limits(self : Parser) -> @core.Limits raise ParseError {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}

///|
fn Parser::read_memtype(self : Parser) -> @core.MemType raise ParseError {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  match flags {
    0x00 => @core.MemType::{ limits: { min, max: None }, shared: false }
    0x01 => {
      let max = self.read_u32_leb128()
      @core.MemType::{ limits: { min, max: Some(max) }, shared: false }
    }
    0x03 => {
      let max = self.read_u32_leb128()
      @core.MemType::{ limits: { min, max: Some(max) }, shared: true }
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid memory limits flags: 0x\{flags.to_int().to_string()}",
      )
  }
}
