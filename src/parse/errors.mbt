///|
/// Parse error types for both Core WASM and Component Model
pub(all) suberror ParseError {
  // Common errors
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
  // Component Model specific errors
  InvalidLayer // Invalid component layer byte
  UnsupportedSection(UInt) // Unsupported section type
  InvalidSectionOrder // Invalid section order
  NestedError(String) // Error in nested module/component
} derive(Show)
