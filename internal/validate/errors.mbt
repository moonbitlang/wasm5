///|
/// Validation error types
pub(all) suberror ValidationError {
  TypeMismatch(String)
  InvalidFunctionIndex(Int32)
  InvalidTypeIndex(Int32)
  InvalidLocalIndex(Int32)
  InvalidGlobalIndex(Int32)
  UnknownGlobal(Int32) // Global not available in current context (e.g., local global in table init)
  StackSizeMismatch(String)
  InvalidResultArity(String)
  InvalidAlignment(String)
  UnknownLabel(Int32)
  InvalidStartFunction(String)
  UnknownMemory(Int32)
  InvalidMemorySize(String)
  ImmutableGlobal(Int32)
  DuplicateExport(String)
  UnknownExportedFunction(Int32)
  UnknownExportedMemory(Int32)
  UnknownExportedTable(Int32)
  UnknownExportedGlobal(Int32)
  UnknownTag(Int32)
  UnknownExportedTag(Int32)
  InvalidTableSize(String)
  UnknownTable(Int32)
  ConstantExpressionRequired(String)
  UninitializedLocal(Int32) // Local with non-defaultable type used before initialization
  UnknownType(Int32) // Type index in ref type doesn't exist
  UndeclaredFunctionReference(Int32) // ref.func used for undeclared function
  InvalidElemIndex(Int32) // Element segment index out of range
  UnknownDataSegment(Int32) // Data segment index out of range
  InvalidSubtype(String) // Subtype declaration error (e.g., extending final type)
} derive(Debug)

///|
pub impl Show for ValidationError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
