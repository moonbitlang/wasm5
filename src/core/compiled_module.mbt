///|
/// A compiled WebAssembly module containing universal IR.
/// This structure is produced by the unified compiler and consumed by
/// both the MoonBit runtime (via switch dispatch) and the C runtime
/// (via opcode-to-function-pointer transformation).
pub(all) struct CompiledModule {
  /// Universal instruction stream (flat Int64 array).
  /// Opcodes are stored as Int64 values, with immediates following each opcode.
  /// The number of immediates per opcode is determined by get_immediate_count().
  code : Array[Int64]
  /// Entry point (code index) for each function.
  func_entries : Array[Int]
  /// Number of locals for each function (includes parameters).
  func_num_locals : Array[Int]
  /// Number of parameters for each function.
  func_num_params : Array[Int]
  /// Number of results for each function.
  func_num_results : Array[Int]
  /// Maximum stack slots needed for each function (for stack overflow checks).
  func_max_stack : Array[Int]
  /// Export name to function index mapping.
  exports : Map[String, Int]
  /// Format version for compatibility checking.
  version : Int
}

///|
/// Current version of the compiled module format.
pub let compiled_module_version : Int = 1

///|
/// Create an empty CompiledModule.
pub fn CompiledModule::new() -> CompiledModule {
  {
    code: [],
    func_entries: [],
    func_num_locals: [],
    func_num_params: [],
    func_num_results: [],
    func_max_stack: [],
    exports: {},
    version: compiled_module_version,
  }
}

///|
/// Get the number of functions in the module.
pub fn CompiledModule::func_count(self : CompiledModule) -> Int {
  self.func_entries.length()
}

///|
/// Look up a function index by export name.
/// Returns None if the export doesn't exist.
pub fn CompiledModule::get_export(self : CompiledModule, name : String) -> Int? {
  self.exports.get(name)
}

///|
/// Get the entry point (code index) for a function.
pub fn CompiledModule::get_func_entry(
  self : CompiledModule,
  func_idx : Int,
) -> Int {
  self.func_entries[func_idx]
}

///|
/// Get the number of locals for a function.
pub fn CompiledModule::get_func_num_locals(
  self : CompiledModule,
  func_idx : Int,
) -> Int {
  self.func_num_locals[func_idx]
}

///|
/// Get the number of parameters for a function.
pub fn CompiledModule::get_func_num_params(
  self : CompiledModule,
  func_idx : Int,
) -> Int {
  self.func_num_params[func_idx]
}

///|
/// Get the number of results for a function.
pub fn CompiledModule::get_func_num_results(
  self : CompiledModule,
  func_idx : Int,
) -> Int {
  self.func_num_results[func_idx]
}

///|
/// Get the maximum stack slots needed for a function.
pub fn CompiledModule::get_func_max_stack(
  self : CompiledModule,
  func_idx : Int,
) -> Int {
  self.func_max_stack[func_idx]
}
