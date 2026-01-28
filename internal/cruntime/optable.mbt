///|
/// C Instance Function Signature:
///
/// ```c
/// typedef struct {
///     uint64_t* pc;      // Program counter into code array
///     uint64_t* sp;      // Stack pointer (points to next push slot)
///     uint8_t* mem;      // Linear memory
/// } CRuntime;
///
/// typedef void (*OpFn)(CRuntime* rt);
///
/// // Each handler tail-calls next op: ((OpFn)*rt->pc++)(rt)
/// ```

// Control
extern "C" fn wasm_unreachable() -> UInt64 = "wasm_unreachable"

///|
extern "C" fn nop() -> UInt64 = "nop"

///|
extern "C" fn wasm_return() -> UInt64 = "wasm_return"

///|
extern "C" fn end() -> UInt64 = "end"

///|
extern "C" fn func_exit() -> UInt64 = "func_exit"

///|
extern "C" fn copy_slot() -> UInt64 = "copy_slot"

///|
extern "C" fn set_sp() -> UInt64 = "set_sp"

///|
extern "C" fn br() -> UInt64 = "br"

///|
extern "C" fn br_if() -> UInt64 = "br_if"

///|
extern "C" fn wasm_if() -> UInt64 = "wasm_if"

///|
extern "C" fn br_table() -> UInt64 = "br_table"

///|
extern "C" fn call() -> UInt64 = "call"

///|
extern "C" fn call_import() -> UInt64 = "call_import"

///|
extern "C" fn return_call() -> UInt64 = "return_call"

///|
extern "C" fn return_call_import() -> UInt64 = "return_call_import"

///|
extern "C" fn return_call_indirect() -> UInt64 = "return_call_indirect"

///|
extern "C" fn return_call_ref() -> UInt64 = "return_call_ref"

///|
extern "C" fn call_external() -> UInt64 = "call_external"

///|
extern "C" fn entry() -> UInt64 = "entry"

///|
let _unused_nop : () -> UInt64 = nop

// Constants

///|
extern "C" fn i32_const() -> UInt64 = "i32_const"

///|
extern "C" fn i64_const() -> UInt64 = "i64_const"

///|
extern "C" fn f32_const() -> UInt64 = "f32_const"

///|
extern "C" fn f64_const() -> UInt64 = "f64_const"

// Local/Global access

///|
extern "C" fn local_get() -> UInt64 = "local_get"

///|
extern "C" fn local_set() -> UInt64 = "local_set"

///|
extern "C" fn local_tee() -> UInt64 = "local_tee"

///|
extern "C" fn global_get() -> UInt64 = "global_get"

///|
extern "C" fn global_set() -> UInt64 = "global_set"

// i32 arithmetic

///|
extern "C" fn i32_add() -> UInt64 = "i32_add"

///|
extern "C" fn i32_sub() -> UInt64 = "i32_sub"

///|
extern "C" fn i32_mul() -> UInt64 = "i32_mul"

///|
extern "C" fn i32_div_s() -> UInt64 = "i32_div_s"

///|
extern "C" fn i32_div_u() -> UInt64 = "i32_div_u"

///|
extern "C" fn i32_rem_s() -> UInt64 = "i32_rem_s"

///|
extern "C" fn i32_rem_u() -> UInt64 = "i32_rem_u"

///|
extern "C" fn i32_and() -> UInt64 = "i32_and"

///|
extern "C" fn i32_or() -> UInt64 = "i32_or"

///|
extern "C" fn i32_xor() -> UInt64 = "i32_xor"

///|
extern "C" fn i32_shl() -> UInt64 = "i32_shl"

///|
extern "C" fn i32_shr_s() -> UInt64 = "i32_shr_s"

///|
extern "C" fn i32_shr_u() -> UInt64 = "i32_shr_u"

///|
extern "C" fn i32_rotl() -> UInt64 = "i32_rotl"

///|
extern "C" fn i32_rotr() -> UInt64 = "i32_rotr"

// i32 comparison

///|
extern "C" fn i32_eqz() -> UInt64 = "i32_eqz"

///|
extern "C" fn i32_eq() -> UInt64 = "i32_eq"

///|
extern "C" fn i32_ne() -> UInt64 = "i32_ne"

///|
extern "C" fn i32_lt_s() -> UInt64 = "i32_lt_s"

///|
extern "C" fn i32_lt_u() -> UInt64 = "i32_lt_u"

///|
extern "C" fn i32_gt_s() -> UInt64 = "i32_gt_s"

///|
extern "C" fn i32_gt_u() -> UInt64 = "i32_gt_u"

///|
extern "C" fn i32_le_s() -> UInt64 = "i32_le_s"

///|
extern "C" fn i32_le_u() -> UInt64 = "i32_le_u"

///|
extern "C" fn i32_ge_s() -> UInt64 = "i32_ge_s"

///|
extern "C" fn i32_ge_u() -> UInt64 = "i32_ge_u"

// i32 unary

///|
extern "C" fn i32_clz() -> UInt64 = "i32_clz"

///|
extern "C" fn i32_ctz() -> UInt64 = "i32_ctz"

///|
extern "C" fn i32_popcnt() -> UInt64 = "i32_popcnt"

// i64 arithmetic

///|
extern "C" fn i64_add() -> UInt64 = "i64_add"

///|
extern "C" fn i64_sub() -> UInt64 = "i64_sub"

///|
extern "C" fn i64_mul() -> UInt64 = "i64_mul"

///|
extern "C" fn i64_div_s() -> UInt64 = "i64_div_s"

///|
extern "C" fn i64_div_u() -> UInt64 = "i64_div_u"

///|
extern "C" fn i64_rem_s() -> UInt64 = "i64_rem_s"

///|
extern "C" fn i64_rem_u() -> UInt64 = "i64_rem_u"

///|
extern "C" fn i64_and() -> UInt64 = "i64_and"

///|
extern "C" fn i64_or() -> UInt64 = "i64_or"

///|
extern "C" fn i64_xor() -> UInt64 = "i64_xor"

///|
extern "C" fn i64_shl() -> UInt64 = "i64_shl"

///|
extern "C" fn i64_shr_s() -> UInt64 = "i64_shr_s"

///|
extern "C" fn i64_shr_u() -> UInt64 = "i64_shr_u"

///|
extern "C" fn i64_rotl() -> UInt64 = "i64_rotl"

///|
extern "C" fn i64_rotr() -> UInt64 = "i64_rotr"

// i64 comparison

///|
extern "C" fn i64_eqz() -> UInt64 = "i64_eqz"

///|
extern "C" fn i64_eq() -> UInt64 = "i64_eq"

///|
extern "C" fn i64_ne() -> UInt64 = "i64_ne"

///|
extern "C" fn i64_lt_s() -> UInt64 = "i64_lt_s"

///|
extern "C" fn i64_lt_u() -> UInt64 = "i64_lt_u"

///|
extern "C" fn i64_gt_s() -> UInt64 = "i64_gt_s"

///|
extern "C" fn i64_gt_u() -> UInt64 = "i64_gt_u"

///|
extern "C" fn i64_le_s() -> UInt64 = "i64_le_s"

///|
extern "C" fn i64_le_u() -> UInt64 = "i64_le_u"

///|
extern "C" fn i64_ge_s() -> UInt64 = "i64_ge_s"

///|
extern "C" fn i64_ge_u() -> UInt64 = "i64_ge_u"

// i64 unary

///|
extern "C" fn i64_clz() -> UInt64 = "i64_clz"

///|
extern "C" fn i64_ctz() -> UInt64 = "i64_ctz"

///|
extern "C" fn i64_popcnt() -> UInt64 = "i64_popcnt"

// f32 arithmetic

///|
extern "C" fn f32_add() -> UInt64 = "f32_add"

///|
extern "C" fn f32_sub() -> UInt64 = "f32_sub"

///|
extern "C" fn f32_mul() -> UInt64 = "f32_mul"

///|
extern "C" fn f32_div() -> UInt64 = "f32_div"

///|
extern "C" fn f32_min() -> UInt64 = "f32_min"

///|
extern "C" fn f32_max() -> UInt64 = "f32_max"

///|
extern "C" fn f32_copysign() -> UInt64 = "f32_copysign"

// f32 comparison

///|
extern "C" fn f32_eq() -> UInt64 = "f32_eq"

///|
extern "C" fn f32_ne() -> UInt64 = "f32_ne"

///|
extern "C" fn f32_lt() -> UInt64 = "f32_lt"

///|
extern "C" fn f32_gt() -> UInt64 = "f32_gt"

///|
extern "C" fn f32_le() -> UInt64 = "f32_le"

///|
extern "C" fn f32_ge() -> UInt64 = "f32_ge"

// f32 unary

///|
extern "C" fn f32_abs() -> UInt64 = "f32_abs"

///|
extern "C" fn f32_neg() -> UInt64 = "f32_neg"

///|
extern "C" fn f32_ceil() -> UInt64 = "f32_ceil"

///|
extern "C" fn f32_floor() -> UInt64 = "f32_floor"

///|
extern "C" fn f32_trunc() -> UInt64 = "f32_trunc"

///|
extern "C" fn f32_nearest() -> UInt64 = "f32_nearest"

///|
extern "C" fn f32_sqrt() -> UInt64 = "f32_sqrt"

// f64 arithmetic

///|
extern "C" fn f64_add() -> UInt64 = "f64_add"

///|
extern "C" fn f64_sub() -> UInt64 = "f64_sub"

///|
extern "C" fn f64_mul() -> UInt64 = "f64_mul"

///|
extern "C" fn f64_div() -> UInt64 = "f64_div"

///|
extern "C" fn f64_min() -> UInt64 = "f64_min"

///|
extern "C" fn f64_max() -> UInt64 = "f64_max"

///|
extern "C" fn f64_copysign() -> UInt64 = "f64_copysign"

// f64 comparison

///|
extern "C" fn f64_eq() -> UInt64 = "f64_eq"

///|
extern "C" fn f64_ne() -> UInt64 = "f64_ne"

///|
extern "C" fn f64_lt() -> UInt64 = "f64_lt"

///|
extern "C" fn f64_gt() -> UInt64 = "f64_gt"

///|
extern "C" fn f64_le() -> UInt64 = "f64_le"

///|
extern "C" fn f64_ge() -> UInt64 = "f64_ge"

// f64 unary

///|
extern "C" fn f64_abs() -> UInt64 = "f64_abs"

///|
extern "C" fn f64_neg() -> UInt64 = "f64_neg"

///|
extern "C" fn f64_ceil() -> UInt64 = "f64_ceil"

///|
extern "C" fn f64_floor() -> UInt64 = "f64_floor"

///|
extern "C" fn f64_trunc() -> UInt64 = "f64_trunc"

///|
extern "C" fn f64_nearest() -> UInt64 = "f64_nearest"

///|
extern "C" fn f64_sqrt() -> UInt64 = "f64_sqrt"

// Conversions

///|
extern "C" fn i32_wrap_i64() -> UInt64 = "i32_wrap_i64"

///|
extern "C" fn i32_trunc_f32_s() -> UInt64 = "i32_trunc_f32_s"

///|
extern "C" fn i32_trunc_f32_u() -> UInt64 = "i32_trunc_f32_u"

///|
extern "C" fn i32_trunc_f64_s() -> UInt64 = "i32_trunc_f64_s"

///|
extern "C" fn i32_trunc_f64_u() -> UInt64 = "i32_trunc_f64_u"

///|
extern "C" fn i64_extend_i32_s() -> UInt64 = "i64_extend_i32_s"

///|
extern "C" fn i64_extend_i32_u() -> UInt64 = "i64_extend_i32_u"

///|
extern "C" fn i64_trunc_f32_s() -> UInt64 = "i64_trunc_f32_s"

///|
extern "C" fn i64_trunc_f32_u() -> UInt64 = "i64_trunc_f32_u"

///|
extern "C" fn i64_trunc_f64_s() -> UInt64 = "i64_trunc_f64_s"

///|
extern "C" fn i64_trunc_f64_u() -> UInt64 = "i64_trunc_f64_u"

// Saturating truncation operations

///|
extern "C" fn i32_trunc_sat_f32_s() -> UInt64 = "i32_trunc_sat_f32_s"

///|
extern "C" fn i32_trunc_sat_f32_u() -> UInt64 = "i32_trunc_sat_f32_u"

///|
extern "C" fn i32_trunc_sat_f64_s() -> UInt64 = "i32_trunc_sat_f64_s"

///|
extern "C" fn i32_trunc_sat_f64_u() -> UInt64 = "i32_trunc_sat_f64_u"

///|
extern "C" fn i64_trunc_sat_f32_s() -> UInt64 = "i64_trunc_sat_f32_s"

///|
extern "C" fn i64_trunc_sat_f32_u() -> UInt64 = "i64_trunc_sat_f32_u"

///|
extern "C" fn i64_trunc_sat_f64_s() -> UInt64 = "i64_trunc_sat_f64_s"

///|
extern "C" fn i64_trunc_sat_f64_u() -> UInt64 = "i64_trunc_sat_f64_u"

///|
extern "C" fn f32_convert_i32_s() -> UInt64 = "f32_convert_i32_s"

///|
extern "C" fn f32_convert_i32_u() -> UInt64 = "f32_convert_i32_u"

///|
extern "C" fn f32_convert_i64_s() -> UInt64 = "f32_convert_i64_s"

///|
extern "C" fn f32_convert_i64_u() -> UInt64 = "f32_convert_i64_u"

///|
extern "C" fn f32_demote_f64() -> UInt64 = "f32_demote_f64"

///|
extern "C" fn f64_convert_i32_s() -> UInt64 = "f64_convert_i32_s"

///|
extern "C" fn f64_convert_i32_u() -> UInt64 = "f64_convert_i32_u"

///|
extern "C" fn f64_convert_i64_s() -> UInt64 = "f64_convert_i64_s"

///|
extern "C" fn f64_convert_i64_u() -> UInt64 = "f64_convert_i64_u"

///|
extern "C" fn f64_promote_f32() -> UInt64 = "f64_promote_f32"

///|
extern "C" fn i32_reinterpret_f32() -> UInt64 = "i32_reinterpret_f32"

///|
extern "C" fn i64_reinterpret_f64() -> UInt64 = "i64_reinterpret_f64"

///|
extern "C" fn f32_reinterpret_i32() -> UInt64 = "f32_reinterpret_i32"

///|
extern "C" fn f64_reinterpret_i64() -> UInt64 = "f64_reinterpret_i64"

// Sign extension

///|
extern "C" fn i32_extend8_s() -> UInt64 = "i32_extend8_s"

///|
extern "C" fn i32_extend16_s() -> UInt64 = "i32_extend16_s"

///|
extern "C" fn i64_extend8_s() -> UInt64 = "i64_extend8_s"

///|
extern "C" fn i64_extend16_s() -> UInt64 = "i64_extend16_s"

///|
extern "C" fn i64_extend32_s() -> UInt64 = "i64_extend32_s"

// Stack operations

///|
extern "C" fn drop() -> UInt64 = "wasm_drop"

///|
extern "C" fn select() -> UInt64 = "wasm_select"

// Memory operations

///|
extern "C" fn memory_grow() -> UInt64 = "memory_grow"

///|
extern "C" fn memory_size() -> UInt64 = "memory_size"

///|
extern "C" fn i32_load() -> UInt64 = "i32_load"

///|
extern "C" fn i32_store() -> UInt64 = "i32_store"

///|
extern "C" fn i32_load8_s() -> UInt64 = "i32_load8_s"

///|
extern "C" fn i32_load8_u() -> UInt64 = "i32_load8_u"

///|
extern "C" fn i32_load16_s() -> UInt64 = "i32_load16_s"

///|
extern "C" fn i32_load16_u() -> UInt64 = "i32_load16_u"

///|
extern "C" fn i32_store8() -> UInt64 = "i32_store8"

///|
extern "C" fn i32_store16() -> UInt64 = "i32_store16"

// i64 loads

///|
extern "C" fn i64_load() -> UInt64 = "i64_load"

///|
extern "C" fn i64_load8_s() -> UInt64 = "i64_load8_s"

///|
extern "C" fn i64_load8_u() -> UInt64 = "i64_load8_u"

///|
extern "C" fn i64_load16_s() -> UInt64 = "i64_load16_s"

///|
extern "C" fn i64_load16_u() -> UInt64 = "i64_load16_u"

///|
extern "C" fn i64_load32_s() -> UInt64 = "i64_load32_s"

///|
extern "C" fn i64_load32_u() -> UInt64 = "i64_load32_u"

// i64 stores

///|
extern "C" fn i64_store() -> UInt64 = "i64_store"

///|
extern "C" fn i64_store8() -> UInt64 = "i64_store8"

///|
extern "C" fn i64_store16() -> UInt64 = "i64_store16"

///|
extern "C" fn i64_store32() -> UInt64 = "i64_store32"

// f32 load/store

///|
extern "C" fn f32_load() -> UInt64 = "f32_load"

///|
extern "C" fn f32_store() -> UInt64 = "f32_store"

// f64 load/store

///|
extern "C" fn f64_load() -> UInt64 = "f64_load"

///|
extern "C" fn f64_store() -> UInt64 = "f64_store"

// Bulk memory operations

///|
extern "C" fn memory_copy() -> UInt64 = "memory_copy"

///|
extern "C" fn memory_fill() -> UInt64 = "memory_fill"

///|
extern "C" fn memory_init() -> UInt64 = "memory_init"

///|
extern "C" fn data_drop() -> UInt64 = "data_drop"

// Bulk table operations

///|
extern "C" fn table_copy() -> UInt64 = "table_copy"

///|
extern "C" fn table_fill() -> UInt64 = "table_fill"

///|
extern "C" fn table_init() -> UInt64 = "table_init"

///|
extern "C" fn elem_drop() -> UInt64 = "elem_drop"

///|
extern "C" fn call_indirect() -> UInt64 = "call_indirect"

// Reference type operations

///|
extern "C" fn ref_null() -> UInt64 = "ref_null"

///|
extern "C" fn ref_func() -> UInt64 = "ref_func"

///|
extern "C" fn ref_is_null() -> UInt64 = "ref_is_null"

///|
extern "C" fn ref_eq() -> UInt64 = "ref_eq"

///|
extern "C" fn ref_as_non_null() -> UInt64 = "ref_as_non_null"

// GC operations (arrays only; structs/i31/casts unimplemented in C runtime)

///|
extern "C" fn struct_new() -> UInt64 = "struct_new"

///|
extern "C" fn struct_new_default() -> UInt64 = "struct_new_default"

///|
extern "C" fn struct_get() -> UInt64 = "struct_get"

///|
extern "C" fn struct_get_s() -> UInt64 = "struct_get_s"

///|
extern "C" fn struct_get_u() -> UInt64 = "struct_get_u"

///|
extern "C" fn struct_set() -> UInt64 = "struct_set"

///|
extern "C" fn array_new() -> UInt64 = "array_new"

///|
extern "C" fn array_new_default() -> UInt64 = "array_new_default"

///|
extern "C" fn array_new_fixed() -> UInt64 = "array_new_fixed"

///|
extern "C" fn array_new_data() -> UInt64 = "array_new_data"

///|
extern "C" fn array_new_elem() -> UInt64 = "array_new_elem"

///|
extern "C" fn array_get() -> UInt64 = "array_get"

///|
extern "C" fn array_get_s() -> UInt64 = "array_get_s"

///|
extern "C" fn array_get_u() -> UInt64 = "array_get_u"

///|
extern "C" fn array_set() -> UInt64 = "array_set"

///|
extern "C" fn array_len() -> UInt64 = "array_len"

///|
extern "C" fn array_fill() -> UInt64 = "array_fill"

///|
extern "C" fn array_copy() -> UInt64 = "array_copy"

///|
extern "C" fn array_init_data() -> UInt64 = "array_init_data"

///|
extern "C" fn array_init_elem() -> UInt64 = "array_init_elem"

///|
extern "C" fn ref_i31() -> UInt64 = "ref_i31"

///|
extern "C" fn i31_get_s() -> UInt64 = "i31_get_s"

///|
extern "C" fn i31_get_u() -> UInt64 = "i31_get_u"

///|
extern "C" fn any_convert_extern() -> UInt64 = "any_convert_extern"

///|
extern "C" fn extern_convert_any() -> UInt64 = "extern_convert_any"

///|
extern "C" fn ref_test() -> UInt64 = "ref_test"

///|
extern "C" fn ref_cast() -> UInt64 = "ref_cast"

///|
extern "C" fn br_on_cast() -> UInt64 = "br_on_cast"

///|
extern "C" fn br_on_cast_fail() -> UInt64 = "br_on_cast_fail"

///|
extern "C" fn br_on_null() -> UInt64 = "br_on_null"

///|
extern "C" fn br_on_non_null() -> UInt64 = "br_on_non_null"

///|
extern "C" fn call_ref() -> UInt64 = "call_ref"

// Table access operations

///|
extern "C" fn table_get() -> UInt64 = "table_get"

///|
extern "C" fn table_set() -> UInt64 = "table_set"

///|
extern "C" fn table_size() -> UInt64 = "table_size"

///|
extern "C" fn table_grow() -> UInt64 = "table_grow"

// Cross-module call support

///|
/// Create a CRuntimeContext for cross-module calls.
/// Returns a pointer (as Int64) to a heap-allocated context structure.
#borrow(code, globals, memory, memory_pages, tables_flat, table_offsets, table_sizes, table_max_sizes, table_elem_is_funcref, func_entries, func_num_locals, func_type_idxs, type_sig_hash1, type_sig_hash2, import_num_params, import_num_results, import_handler_ids, output_buffer, output_length, import_context_ptrs, import_target_func_idxs, data_segments_flat, data_segment_offsets, data_segment_sizes, elem_segments_flat, elem_segments_flat_u64, elem_segment_offsets, elem_segment_sizes, elem_segment_dropped)
extern "C" fn c_create_runtime_context(
  code : FixedArray[UInt64],
  globals : FixedArray[UInt64],
  memory : FixedArray[Byte],
  memory_size : Int,
  memory_max_size : Int,
  memory_pages : FixedArray[Int],
  tables_flat : FixedArray[Int],
  table_offsets : FixedArray[Int],
  table_sizes : FixedArray[Int],
  table_max_sizes : FixedArray[Int],
  table_elem_is_funcref : FixedArray[Int],
  num_tables : Int,
  func_entries : FixedArray[Int],
  func_num_locals : FixedArray[Int],
  num_funcs : Int,
  num_imported_funcs : Int,
  func_type_idxs : FixedArray[Int],
  type_sig_hash1 : FixedArray[Int],
  type_sig_hash2 : FixedArray[Int],
  num_types : Int,
  import_num_params : FixedArray[Int],
  import_num_results : FixedArray[Int],
  import_handler_ids : FixedArray[Int],
  output_buffer : FixedArray[Byte],
  output_length : FixedArray[Int],
  output_capacity : Int,
  import_context_ptrs : FixedArray[Int64],
  import_target_func_idxs : FixedArray[Int],
  data_segments_flat : FixedArray[Byte],
  data_segment_offsets : FixedArray[Int],
  data_segment_sizes : FixedArray[Int],
  num_data_segments : Int,
  elem_segments_flat : FixedArray[Int],
  elem_segments_flat_u64 : FixedArray[UInt64],
  elem_segment_offsets : FixedArray[Int],
  elem_segment_sizes : FixedArray[Int],
  elem_segment_dropped : FixedArray[Int],
  num_elem_segments : Int,
  num_external_funcrefs : Int,
) -> Int64 = "create_runtime_context"

///|
/// Free a CRuntimeContext that was created with c_create_runtime_context.
extern "C" fn c_free_runtime_context(context_ptr : Int64) -> Unit = "free_runtime_context"

///|
/// Call a function in another CRuntime module using context switching.
/// Used for exported imports - functions that re-export an imported function.
#borrow(args, result_out)
extern "C" fn c_call_external_ffi(
  target_context_ptr : Int64,
  func_idx : Int,
  args : FixedArray[UInt64],
  num_args : Int,
  result_out : FixedArray[UInt64],
  num_results : Int,
) -> Int = "call_external_ffi"

///|
/// Initialize WASI context (with empty arguments for now).
/// Must be called before executing WASI modules.
extern "C" fn c_wasi_init_empty() -> Unit = "wasi_init_empty"

///|
/// Get the WASI exit code after proc_exit was called.
extern "C" fn c_wasi_get_exit_code() -> Int = "wasi_get_exit_code"

///|
/// Check if WASI has exited (proc_exit was called).
extern "C" fn c_wasi_has_exited() -> Int = "wasi_has_exited"

///|
/// Add a preopened file to the WASI environment.
/// Returns the WASI fd number (3+) or -1 on error.
extern "C" fn c_wasi_add_preopen_file(host_fd : Int) -> Int = "wasi_add_preopen_file_ffi"

///|
/// Reset preopens to just stdin/stdout/stderr.
extern "C" fn c_wasi_reset_preopens() -> Unit = "wasi_reset_preopens"
