///|
/// RuntimeContext holds the "cold" data that is less frequently accessed
/// during instruction execution. This is a reference type.
pub struct RuntimeContext {
  module_ : @core.Module
  call_stack : Array[CallFrame]
  memory : Array[Byte]
  memory_max : UInt64?
  globals : Array[Value]
  tables : Array[RuntimeTable]
  imported_funcs : Array[ImportedFunc]
  data_segments : Array[Array[Byte]]
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
) -> RuntimeContext {
  {
    module_,
    call_stack: [],
    memory,
    memory_max,
    globals,
    tables,
    imported_funcs,
    data_segments,
    error_detail: "",
  }
}
