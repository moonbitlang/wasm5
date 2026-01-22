///|
/// Instance value types for WebAssembly execution.
pub(all) enum Value {
  I32(UInt)
  I64(UInt64)
  F32(Float)
  F64(Double)
  Ref(Int?) // For GC refs (struct, array, i31)
  Funcref(Int?) // For function references
  Externref(Int?) // For external references
} derive(Eq, Show)
