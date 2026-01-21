///|
/// Execute threaded code (FFI binding)
/// Returns trap code (0 = success), stores results in result_out[0..num_results-1]
#borrow(code, args, result_out, globals, memory, memory_pages, tables_flat, table_offsets, table_sizes, table_max_sizes, func_entries, func_num_locals, func_type_idxs, type_sig_hash1, type_sig_hash2, import_num_params, import_num_results, import_handler_ids, output_buffer, output_length, import_context_ptrs, import_target_func_idxs, data_segments_flat, data_segment_offsets, data_segment_sizes, elem_segments_flat, elem_segment_offsets, elem_segment_sizes, elem_segment_dropped)
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
  mem_max_size : Int,
  memory_pages : FixedArray[Int],
  tables_flat : FixedArray[Int], // All tables flattened into one array
  table_offsets : FixedArray[Int], // Offset of each table in tables_flat
  table_sizes : FixedArray[Int], // Current size of each table
  table_max_sizes : FixedArray[Int], // Max size (capacity) of each table for table.grow
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
  import_handler_ids : FixedArray[Int], // Host handler id for each imported function
  output_buffer : FixedArray[Byte], // Output buffer for spectest handlers
  output_length : FixedArray[Int], // Current output length
  output_capacity : Int, // Output buffer capacity in bytes
  import_context_ptrs : FixedArray[Int64], // Target context pointers for cross-module calls
  import_target_func_idxs : FixedArray[Int], // Target function indices for cross-module calls
  data_segments_flat : FixedArray[Byte], // All data segments flattened
  data_segment_offsets : FixedArray[Int], // Offset of each segment in data_segments_flat
  data_segment_sizes : FixedArray[Int], // Size of each segment (mutable for data.drop)
  num_data_segments : Int, // Number of data segments
  elem_segments_flat : FixedArray[Int], // All element segments flattened (func indices, -1 for null)
  elem_segment_offsets : FixedArray[Int], // Offset of each segment in elem_segments_flat
  elem_segment_sizes : FixedArray[Int], // Size of each segment
  elem_segment_dropped : FixedArray[Int], // Whether each segment has been dropped
  num_elem_segments : Int, // Number of element segments
  num_external_funcrefs : Int, // Number of external funcref entries
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
    11 => TrapCode::TableBoundsAccess
    12 => TrapCode::NullReference
    _ => TrapCode::Unreachable // Unknown trap code
  }
}
