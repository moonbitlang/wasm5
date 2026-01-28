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
  NullFunctionReference = 8 // call_ref with null funcref
  StackOverflow = 9
  UninitializedElement = 10 // "uninitialized element" - null entry in table
  TableBoundsAccess = 11 // "out of bounds table access" - for bulk table ops
  NullReference = 12 // ref.as_non_null on null ref
  WasiExit = 13 // WASI proc_exit was called (not a real trap)
  OutOfBoundsArrayAccess = 14 // "out of bounds array access"
  NullArrayReference = 15 // "null array reference"
  InvalidArrayReference = 16 // "array: invalid reference"
} derive(Eq, Show)

///|
/// Information about a resolved import for cross-module calls.
/// Used when compiling a module that imports from a registered module.
pub(all) struct ResolvedImport {
  /// Pointer to the target CRuntime's context (as Int64)
  target_context_ptr : Int64
  /// Function index in the target module
  target_func_idx : Int
  /// Number of parameters the function takes
  num_params : Int
  /// Number of results the function returns
  num_results : Int
} derive(Show)

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
