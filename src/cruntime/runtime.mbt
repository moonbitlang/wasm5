///|
/// Runtime for C-based threaded code execution.
pub struct CRuntime {
  module_ : @core.Module
  compiled : CompiledModule
  // TODO: memory, globals
}

// Import Value type from core

///|
using @core {type Value}

///|
/// Load a module and compile it for C runtime execution.
pub fn CRuntime::load(module_ : @core.Module) -> CRuntime {
  let compiled = compile(module_)
  { module_, compiled }
}

///|
/// Run the start function if present.
pub fn CRuntime::run_start(self : CRuntime) -> Unit {
  match self.module_.start {
    Some(start_idx) => {
      let num_imported = count_imported_funcs(self.module_)
      let local_idx = start_idx.reinterpret_as_int() - num_imported
      if local_idx >= 0 && local_idx < self.compiled.func_entries.length() {
        let entry = self.compiled.func_entries[local_idx]
        let num_locals = self.compiled.func_num_locals[local_idx]
        let _ = c_execute_ffi(self.compiled.code, entry, num_locals, [], 0)

      }
    }
    None => ()
  }
}

///|
/// Call an exported function by name.
pub fn CRuntime::call_compiled(
  self : CRuntime,
  name : Bytes,
  args : Array[Value],
) -> Array[Value] {
  let name_str = @encoding/utf8.decode(name) catch { _ => return [] }
  match self.compiled.exports.get(name_str) {
    Some(func_idx) => {
      // Get function type for result conversion
      let num_imported = count_imported_funcs(self.module_)
      let abs_idx = num_imported + func_idx
      let type_idx = self.module_.funcs[abs_idx].reinterpret_as_int()
      let func_type = get_func_type(self.module_, type_idx)

      // Convert args to UInt64
      let args_u64 : Array[UInt64] = []
      for arg in args {
        args_u64.push(value_to_u64(arg))
      }
      let entry = self.compiled.func_entries[func_idx]
      let num_locals = self.compiled.func_num_locals[func_idx]
      let args_fixed = FixedArray::from_array(args_u64)
      let result = c_execute_ffi(
        self.compiled.code,
        entry,
        num_locals,
        args_fixed,
        args_u64.length(),
      )

      // Convert result based on function type
      let results : Array[Value] = []
      if func_type.results.length() > 0 {
        results.push(u64_to_value(result, func_type.results[0]))
      }
      results
    }
    None => []
  }
}

///|
fn value_to_u64(v : Value) -> UInt64 {
  match v {
    I32(n) => n.to_uint64()
    I64(n) => n
    F32(f) => f.reinterpret_as_uint().to_uint64()
    F64(f) => f.reinterpret_as_uint64()
    Ref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Ref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Funcref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Funcref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Externref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Externref(None) => 0xFFFFFFFF_FFFFFFFFUL
  }
}

///|
fn u64_to_value(raw : UInt64, ty : @core.ValType) -> Value {
  match ty {
    I32 => Value::I32(raw.to_uint())
    I64 => Value::I64(raw)
    F32 => Value::F32(Float::reinterpret_from_uint(raw.to_uint()))
    F64 => Value::F64(raw.reinterpret_as_double())
    FuncRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Funcref(None)
      } else {
        Value::Funcref(Some(raw.to_uint().reinterpret_as_int()))
      }
    ExternRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Externref(None)
      } else {
        Value::Externref(Some(raw.to_uint().reinterpret_as_int()))
      }
    _ => Value::I64(raw)
  }
}
