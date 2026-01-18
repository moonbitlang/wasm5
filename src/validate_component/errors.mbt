///|
/// Component Model validation error types
pub(all) suberror ComponentValidationError {
  // Index bounds errors
  TypeIndexOutOfBounds(UInt)
  FuncIndexOutOfBounds(UInt)
  InstanceIndexOutOfBounds(UInt)
  ComponentIndexOutOfBounds(UInt)
  ModuleIndexOutOfBounds(UInt)
  CoreTypeIndexOutOfBounds(UInt)
  CoreFuncIndexOutOfBounds(UInt)
  CoreInstanceIndexOutOfBounds(UInt)
  CoreModuleIndexOutOfBounds(UInt)
  CoreTableIndexOutOfBounds(UInt)
  CoreMemoryIndexOutOfBounds(UInt)
  CoreGlobalIndexOutOfBounds(UInt)
  CoreTagIndexOutOfBounds(UInt)
  ValueIndexOutOfBounds(UInt)
  IndexOutOfBounds(String) // Generic

  // Type mismatch errors
  NotAFunctionType(UInt)
  NotAnInstanceType(UInt)
  NotAComponentType(UInt)
  NotAModuleType(UInt)
  NotADefinedType(UInt)
  NotAResourceType(UInt)
  NotALocalResource(UInt)
  ResourceTypeMismatch(String)
  TypeMismatch(String)

  // Export/Import validation
  TypeNotValidAsExport(String)
  TypeNotValidAsImport(String)
  FuncNotValidAsExport(String)
  FuncNotValidAsImport(String)
  InvalidExternName(String)
  InvalidExportName(String)
  InvalidImportName(String)
  MissingImport(String)
  MissingExport(String) // instance has no export with given name
  ExportTypeMismatch(String) // export exists but has wrong type
  DuplicateExportName(String)
  DuplicateName(String)

  // Name validation errors
  NotKebabCase(String)
  NameCannotBeEmpty
  FailedToFindDotCharacter(String)
  InvalidBase64(String)
  UnexpectedCharacter(Char)

  // Canonical ABI errors
  CanonicalOptionMemoryRequired
  CanonicalOptionReallocRequired
  CanonicalOptionEncodingRequired

  // Resource errors
  ResourceNotDefinedInComponent(String)
  ResourceNameNotInContext(String)
  FunctionResourceNameMismatch(String, String)
  BorrowInResult(String)

  // Other errors
  InvalidOuterAliasCount(UInt)
  UnknownModule(String)
  LimitsMismatch(String)
  InvalidRepresentation(String)
  WrongDestructorSignature(String)
  TypeSizeExceedsLimit // effective type size exceeds the limit
} derive(Show)
