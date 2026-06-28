///|
/// Parse error types
pub suberror ParseError {
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
} derive(Debug)

///|
pub impl Show for ParseError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
