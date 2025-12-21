///|
/// Parse error types
pub(all) suberror ParseError {
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
} derive(Show)

///|
/// Validation error types
pub(all) suberror ValidationError {
  TypeMismatch(String)
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  UnknownGlobal(Int) // Global not available in current context (e.g., local global in table init)
  StackSizeMismatch(String)
  InvalidResultArity(String)
  InvalidAlignment(String)
  UnknownLabel(Int)
  InvalidStartFunction(String)
  UnknownMemory(Int)
  InvalidMemorySize(String)
  ImmutableGlobal(Int)
  DuplicateExport(String)
  UnknownExportedFunction(Int)
  UnknownExportedMemory(Int)
  UnknownExportedTable(Int)
  UnknownExportedGlobal(Int)
  InvalidTableSize(String)
  UnknownTable(Int)
  ConstantExpressionRequired(String)
  UninitializedLocal(Int) // Local with non-defaultable type used before initialization
  UnknownType(Int) // Type index in ref type doesn't exist
} derive(Show)
