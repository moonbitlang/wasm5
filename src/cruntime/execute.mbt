///|
/// Execute threaded code (FFI binding)
/// Returns trap code (0 = success), stores results in result_out[0..num_results-1]
#borrow(code, args, result_out, globals, memory, memory_pages, tables_flat, table_offsets, table_sizes, func_entries, func_num_locals, func_type_idxs, type_sig_hash1, type_sig_hash2, import_num_params, import_num_results)
extern "C" fn c_execute_ffi(
  code : FixedArray[UInt64],
  entry : Int,
  num_locals : Int,
  args : FixedArray[UInt64],
  num_args : Int,
  result_out : FixedArray[UInt64],
  num_results : Int,
  globals : FixedArray[UInt64],
  memory : FixedArray[Byte],
  mem_size : Int,
  memory_pages : FixedArray[Int],
  tables_flat : FixedArray[Int], // All tables flattened into one array
  table_offsets : FixedArray[Int], // Offset of each table in tables_flat
  table_sizes : FixedArray[Int], // Size of each table
  num_tables : Int,
  func_entries : FixedArray[Int], // Entry points for local functions
  func_num_locals : FixedArray[Int], // Number of locals per local function
  num_funcs : Int, // Number of local functions
  num_imported_funcs : Int, // Number of imported functions (for index offset)
  func_type_idxs : FixedArray[Int], // Type index for each function (imported + local)
  type_sig_hash1 : FixedArray[Int], // Primary signature hash for each type
  type_sig_hash2 : FixedArray[Int], // Secondary signature hash for each type
  num_types : Int,
  import_num_params : FixedArray[Int], // Number of params for each imported function
  import_num_results : FixedArray[Int], // Number of results for each imported function
) -> Int = "execute"

///|
/// Convert trap code integer to TrapCode enum
fn trap_code_from_int(code : Int) -> TrapCode {
  match code {
    0 => TrapCode::None
    1 => TrapCode::Unreachable
    2 => TrapCode::DivisionByZero
    3 => TrapCode::IntegerOverflow
    4 => TrapCode::InvalidConversionToInteger
    5 => TrapCode::OutOfBoundsMemoryAccess
    6 => TrapCode::OutOfBoundsTableAccess
    7 => TrapCode::IndirectCallTypeMismatch
    8 => TrapCode::NullFunctionReference
    9 => TrapCode::StackOverflow
    10 => TrapCode::UninitializedElement
    _ => TrapCode::Unreachable // Unknown trap code
  }
}
