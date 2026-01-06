///|
/// RuntimeContext holds the "cold" data that is less frequently accessed
/// during instruction execution. This is a reference type.
pub struct RuntimeContext {
  module_ : @core.Module
  memory : Array[Byte]
  memory_max : UInt64?
  globals : Array[Value]
  tables : Array[RuntimeTable]
  imported_funcs : Array[ImportedFunc]
  data_segments : Array[Array[Byte]]
  gc_heap : Array[GcObject] // GC heap for struct/array instances
  // External function references from other modules.
  // Used for cross-module funcref globals and table entries.
  // Accessed via negative indices: index -1 = external_funcrefs[0], -2 = [1], etc.
  external_funcrefs : Array[ImportedFunc]
  // Track which element segments have been dropped.
  // Active segments are dropped after instantiation, declarative segments are always dropped.
  dropped_elems : Array[Bool]
  mut error_detail : String
}

///|
/// Create a new RuntimeContext
fn RuntimeContext::new(
  module_ : @core.Module,
  memory : Array[Byte],
  memory_max : UInt64?,
  globals : Array[Value],
  tables : Array[RuntimeTable],
  imported_funcs : Array[ImportedFunc],
  data_segments : Array[Array[Byte]],
  external_funcrefs? : Array[ImportedFunc] = [],
  dropped_elems? : Array[Bool] = [],
) -> RuntimeContext {
  {
    module_,
    memory,
    memory_max,
    globals,
    tables,
    imported_funcs,
    data_segments,
    gc_heap: [],
    external_funcrefs,
    dropped_elems,
    error_detail: "",
  }
}

///|
/// Create a new RuntimeContext with a pre-initialized gc_heap
fn RuntimeContext::new_with_gc_heap(
  module_ : @core.Module,
  memory : Array[Byte],
  memory_max : UInt64?,
  globals : Array[Value],
  tables : Array[RuntimeTable],
  imported_funcs : Array[ImportedFunc],
  data_segments : Array[Array[Byte]],
  gc_heap : Array[GcObject],
  external_funcrefs? : Array[ImportedFunc] = [],
  dropped_elems? : Array[Bool] = [],
) -> RuntimeContext {
  {
    module_,
    memory,
    memory_max,
    globals,
    tables,
    imported_funcs,
    data_segments,
    gc_heap,
    external_funcrefs,
    dropped_elems,
    error_detail: "",
  }
}
