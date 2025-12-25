///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module_ : @core.Module,
  func_type : @core.FuncType,
  code : @core.Code,
  ctx : ValidationCtx,
  instr : @core.Instr,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  if validate_instruction_numeric(module_, ctx, instr) {
    return
  }
  if validate_instruction_simd(module_, ctx, instr, import_counts) {
    return
  }
  if validate_instruction_atomic(module_, ctx, instr, import_counts) {
    return
  }
  if validate_instruction_variable(
      module_, func_type, code, ctx, import_counts, instr,
    ) {
    return
  }
  if validate_instruction_parametric(module_, ctx, instr) {
    return
  }
  if validate_instruction_memory(module_, ctx, import_counts, instr) {
    return
  }
  if validate_instruction_table(module_, ctx, import_counts, instr) {
    return
  }
  if validate_instruction_gc(module_, ctx, instr) {
    return
  }
  if validate_instruction_reference(module_, ctx, import_counts, instr) {
    return
  }
  if validate_instruction_control(
      module_, func_type, code, ctx, instr, import_counts,
    ) {
    return
  }
  abort("unhandled instruction: \{instr}")
}
