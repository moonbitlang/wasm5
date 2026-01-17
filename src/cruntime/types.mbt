///|
/// Trap codes returned by the C runtime.
/// Values must match the C side definitions in op.c.
pub enum TrapCode {
  None = 0
  Unreachable = 1
  DivisionByZero = 2
  IntegerOverflow = 3
  InvalidConversionToInteger = 4
  OutOfBoundsMemoryAccess = 5
  OutOfBoundsTableAccess = 6 // "undefined element" - index out of bounds (call_indirect)
  IndirectCallTypeMismatch = 7
  NullFunctionReference = 8
  StackOverflow = 9
  UninitializedElement = 10 // "uninitialized element" - null entry in table
  TableBoundsAccess = 11 // "out of bounds table access" - for bulk table ops
} derive(Eq, Show)

///|
/// Compiled module ready for C runtime execution.
/// The code array is heterogeneous: function pointers and immediates interleaved.
pub struct CompiledModule {
  /// Threaded code: function pointers (as UInt64) and immediates interleaved
  code : FixedArray[UInt64]
  /// Entry point (code index) for each function in the module
  func_entries : FixedArray[Int]
  /// Number of locals for each function (including parameters)
  func_num_locals : FixedArray[Int]
  /// Maximum stack height for each function
  func_max_stack : FixedArray[Int]
  /// Exported functions: name -> function index (into func_entries)
  exports : Map[String, Int]
}
