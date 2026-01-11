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
}
