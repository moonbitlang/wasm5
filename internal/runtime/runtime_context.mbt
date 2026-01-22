///|
/// RuntimeContext holds the "cold" data that is less frequently accessed
/// during instruction execution. This is a reference type.
pub struct RuntimeContext {
  module_ : @core.Module
  compiled : @core.CompiledModule
  memory : Array[Byte]
  memory_max : UInt64?
  globals : Array[Value]
  tables : Array[RuntimeTable]
  imported_funcs : Array[HostFunc]
  data_segments : Array[Array[Byte]]
  gc_heap : Array[GcObject] // GC heap for struct/array instances
  output : Array[String] // Collected spectest output
  // External function references from other modules.
  // Used for cross-module funcref globals and table entries.
  // Accessed via negative indices: index -1 = external_funcrefs[0], -2 = [1], etc.
  external_funcrefs : Array[HostFunc]
  // Track which element segments have been dropped.
  // Active segments are dropped after instantiation, declarative segments are always dropped.
  dropped_elems : Array[Bool]
  // Cached count of imported functions (avoids linear scan at runtime)
  num_imported_funcs : Int
  mut error_detail : String
}

///|
/// Count the number of imported functions in a module
fn count_module_imported_funcs(module_ : @core.Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Func(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Create a new RuntimeContext with a pre-initialized gc_heap
fn RuntimeContext::new_with_gc_heap(
  module_ : @core.Module,
  memory : Array[Byte],
  memory_max : UInt64?,
  globals : Array[Value],
  tables : Array[RuntimeTable],
  imported_funcs : Array[HostFunc],
  data_segments : Array[Array[Byte]],
  gc_heap : Array[GcObject],
  output? : Array[String] = [],
  compiled? : @core.CompiledModule = @core.CompiledModule::new(),
  external_funcrefs? : Array[HostFunc] = [],
  dropped_elems? : Array[Bool] = [],
) -> RuntimeContext {
  {
    module_,
    compiled,
    memory,
    memory_max,
    globals,
    tables,
    imported_funcs,
    data_segments,
    gc_heap,
    output,
    external_funcrefs,
    dropped_elems,
    num_imported_funcs: count_module_imported_funcs(module_),
    error_detail: "",
  }
}

///|
pub fn RuntimeContext::push_output(self : RuntimeContext, s : String) -> Unit {
  self.output.push(s)
}

///|
pub fn RuntimeContext::get_output(self : RuntimeContext) -> Array[String] {
  self.output
}

///|
pub fn RuntimeContext::clear_output(self : RuntimeContext) -> Unit {
  self.output.clear()
}
