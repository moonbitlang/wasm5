///|
/// Compile a module to threaded code for C runtime using the unified compiler.
pub fn compile(mod_ : @core.Module) -> CompiledModule {
  compile_with_imports(mod_, Map::new())
}

///|
/// Compile a module to threaded code for C runtime with resolved imports.
/// Resolved imports are handled at runtime; compilation is identical.
pub fn compile_with_imports(
  mod_ : @core.Module,
  resolved_imports : Map[Int, ResolvedImport],
) -> CompiledModule {
  let _ = resolved_imports
  let universal = @compile.compile(mod_)
  let code = transform_to_c_runtime(universal.code)
  {
    code,
    func_entries: FixedArray::from_array(universal.func_entries),
    func_num_locals: FixedArray::from_array(universal.func_num_locals),
    func_max_stack: FixedArray::from_array(universal.func_max_stack),
    exports: universal.exports,
  }
}
