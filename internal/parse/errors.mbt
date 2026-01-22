///|
/// Parse error types
pub suberror ParseError {
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
} derive(Show)
