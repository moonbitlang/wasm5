///|
/// Instance value types for WebAssembly execution.
pub(all) enum Value {
  I32(UInt32)
  I64(UInt64)
  F32(Float)
  F64(Double)
  Ref(Int32?) // For GC refs (struct, array, i31)
  Funcref(Int32?) // For function references
  Externref(Int32?) // For external references
} derive(Eq, Debug)

///|
pub impl Show for Value with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
