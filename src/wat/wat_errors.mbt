///|
pub suberror WatError {
  InvalidSyntax(String)
  InvalidNumber(String)
  UnknownIdentifier(String)
  Unsupported(String)
  Encode(String)
} derive(Show)
