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
  UnknownTag(Int)
  UnknownExportedTag(Int)
  InvalidTableSize(String)
  UnknownTable(Int)
  ConstantExpressionRequired(String)
  UninitializedLocal(Int) // Local with non-defaultable type used before initialization
  UnknownType(Int) // Type index in ref type doesn't exist
  UndeclaredFunctionReference(Int) // ref.func used for undeclared function
  InvalidElemIndex(Int) // Element segment index out of range
} derive(Show)
