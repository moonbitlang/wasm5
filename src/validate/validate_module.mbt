///|
/// Validate a WebAssembly module
pub fn validate_module(m : @core.Module) -> Unit raise @errors.ValidationError {
  // Compute import counts once for efficiency
  let import_counts = get_import_counts(m)
  validate_module_type_indices(m)
  validate_module_start_function(m, import_counts)
  validate_module_global_initializers(m, import_counts)
  validate_module_memory_limits(m)
  validate_module_imported_memory_limits(m)
  validate_module_tables(m, import_counts)
  validate_module_element_segments(m, import_counts)
  validate_module_data_segments(m, import_counts)
  validate_module_function_bodies(m, import_counts)
  validate_module_exports(m, import_counts)
}
