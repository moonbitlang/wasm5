// =============================================================================
// NaN Canonicalization for WebAssembly Compliance
// =============================================================================
//
// WebAssembly requires that when a floating-point operation produces a NaN
// result, it must be a "canonical NaN" with a specific bit pattern:
//
//   - f64 canonical NaN: 0x7FF8000000000000 (positive quiet NaN)
//   - f32 canonical NaN: 0x7FC00000 (positive quiet NaN)
//
// The sign bit must be 0 (positive), and the payload must be the canonical
// quiet NaN pattern.
//
// WHY THIS MATTERS:
// Native floating-point hardware may produce different NaN bit patterns when
// propagating NaN through operations. For example:
//   - Adding -0.0 + (-NaN) might produce a negative NaN (sign bit = 1)
//   - Different CPUs may set different payload bits
//
// The WebAssembly spec tests (wast files) check for exact bit patterns in
// "nan:canonical" assertions, so we must canonicalize all NaN results.
//
// WHICH OPERATIONS NEED CANONICALIZATION:
// Any operation that can produce NaN as a result needs canonicalization:
//   - Arithmetic: add, sub, mul, div (when operands include NaN or produce NaN)
//   - Unary: sqrt (negative input), ceil, floor, trunc, nearest (NaN passthrough)
//   - Min/max: when either operand is NaN
//
// Note: Operations like neg, abs, and copysign have special NaN handling
// defined by the spec and don't use canonicalization.
// =============================================================================

///|
/// Canonical NaN values for WebAssembly
/// f64 canonical NaN: 0x7FF8000000000000
pub let canonical_nan_f64 : Double = 0x7ff8_0000_0000_0000UL.reinterpret_as_double()

///|
/// f32 canonical NaN: 0x7FC00000
pub let canonical_nan_f32 : Float = Float::reinterpret_from_uint(0x7fc0_0000U)

///|
/// Canonicalize NaN values - if value is NaN, return canonical NaN.
/// This ensures WebAssembly spec compliance for NaN bit patterns.
fn canonicalize_f64(v : Double) -> Double {
  if v.is_nan() {
    canonical_nan_f64
  } else {
    v
  }
}

///|
/// Canonicalize NaN values - if value is NaN, return canonical NaN.
/// This ensures WebAssembly spec compliance for NaN bit patterns.
fn canonicalize_f32(v : Float) -> Float {
  if v.is_nan() {
    canonical_nan_f32
  } else {
    v
  }
}

///|
pub extern "C" fn rint(x : Double) -> Double = "rint"

///|
pub extern "C" fn rintf(x : Float) -> Float = "rintf"

///|
/// Count the number of imported functions in a module
fn count_imported_funcs(module_ : @core.Module) -> Int {
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
/// Count the number of imported tags in a module
fn count_imported_tags(module_ : @core.Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Tag(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
fn require_func_type(
  module_ : @core.Module,
  type_idx : Int,
  context : String,
) -> @core.FuncType raise RuntimeError {
  if type_idx < 0 || type_idx >= module_.types.length() {
    raise RuntimeError::InvalidType(
      "\{context}: invalid type index \{type_idx}",
    )
  }
  match module_.types[type_idx] {
    Func(func_type) => func_type
    _ => raise RuntimeError::InvalidType("\{context}: expected func type")
  }
}

///|
fn require_struct_type(
  module_ : @core.Module,
  type_idx : Int,
  context : String,
) -> @core.StructType raise RuntimeError {
  if type_idx < 0 || type_idx >= module_.types.length() {
    raise RuntimeError::InvalidType(
      "\{context}: invalid type index \{type_idx}",
    )
  }
  match module_.types[type_idx] {
    Struct(struct_type) => struct_type
    _ => raise RuntimeError::InvalidType("\{context}: expected struct type")
  }
}

///|
fn require_array_type(
  module_ : @core.Module,
  type_idx : Int,
  context : String,
) -> @core.ArrayType raise RuntimeError {
  if type_idx < 0 || type_idx >= module_.types.length() {
    raise RuntimeError::InvalidType(
      "\{context}: invalid type index \{type_idx}",
    )
  }
  match module_.types[type_idx] {
    Array(array_type) => array_type
    _ => raise RuntimeError::InvalidType("\{context}: expected array type")
  }
}

///|
fn storage_value_type(storage : @core.StorageType) -> @core.ValType {
  match storage {
    Val(val_type) => val_type
    I8 | I16 => I32
  }
}

///|
/// Get the type index for a function (imported or local)
/// Returns -1 if the function index is invalid
fn get_func_type_idx(
  module_ : @core.Module,
  func_idx : Int,
  num_imported : Int,
) -> Int {
  if func_idx < num_imported {
    // Imported function - find type index from imports
    let mut import_idx = 0
    let mut type_idx = -1
    for imp in module_.imports {
      match imp.desc {
        Func(tidx) => {
          if import_idx == func_idx {
            type_idx = tidx.reinterpret_as_int()
            break
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    type_idx
  } else {
    // Local function - look up in module funcs
    let local_idx = func_idx - num_imported
    if local_idx >= 0 && local_idx < module_.funcs.length() {
      module_.funcs[local_idx].reinterpret_as_int()
    } else {
      -1
    }
  }
}

///|
/// Get the type index for a tag (imported or local)
/// Returns -1 if the tag index is invalid
fn get_tag_type_idx(
  module_ : @core.Module,
  tag_idx : Int,
  num_imported : Int,
) -> Int {
  if tag_idx < num_imported {
    let mut import_idx = 0
    let mut type_idx = -1
    for imp in module_.imports {
      match imp.desc {
        Tag(tidx) => {
          if import_idx == tag_idx {
            type_idx = tidx.reinterpret_as_int()
            break
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    type_idx
  } else {
    let local_idx = tag_idx - num_imported
    if local_idx >= 0 && local_idx < module_.tags.length() {
      module_.tags[local_idx].type_idx.reinterpret_as_int()
    } else {
      -1
    }
  }
}

///|
/// Value struct for pop_arguments result (avoids tuple allocation)
priv struct PopArgs {
  rt : Runtime
  args : Array[Value]
}

///|
/// Pop function arguments from the stack (converts UInt64 to Value)
fn pop_arguments(rt : Runtime, func_type : @core.FuncType) -> PopArgs {
  let num_params = func_type.params.length()
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  let mut stack_top = rt.sp
  for i = num_params - 1; i >= 0; i = i - 1 {
    stack_top -= 1
    let raw = rt.stack.unsafe_get(stack_top)
    args[i] = stack_to_value(raw, func_type.params[i])
  }
  { rt: { ..rt, sp: stack_top }, args }
}

///|
/// Push default values for declared locals onto the unified stack.
/// Params are already on the stack - this only handles declared locals.
/// Returns Runtime with updated sp and status (Trap on error).
fn init_declared_locals(rt : Runtime, code : @core.Code) -> Runtime {
  let mut stack_top = rt.sp
  for local_type in code.locals {
    match local_type {
      I32 | I64 | F32 | F64 => {
        rt.stack.unsafe_set(stack_top, 0UL)
        stack_top += 1
      }
      FuncRef
      | ExternRef
      | AnyRef
      | ExnRef
      | NullRef
      | NullFuncRef
      | NullExnRef
      | NullExternRef
      | EqRef
      | I31Ref
      | StructRef
      | ArrayRef
      | Ref(_, _) => {
        rt.stack.unsafe_set(stack_top, (-1L).reinterpret_as_uint64()) // null ref
        stack_top += 1
      }
      _ => {
        rt.ctx.error_detail = "Unsupported local type: \{local_type}"
        return { ..rt, sp: stack_top, status: Trap }
      }
    }
  }
  { ..rt, sp: stack_top }
}

///|
/// Initialize locals for entry point (call_compiled, start function).
/// Pushes args onto stack, then declared locals, and sets sp/num_locals.
/// Returns Runtime with updated sp, bp, num_locals, and status.
fn initialize_entry_locals(
  rt : Runtime,
  args : Array[Value],
  code : @core.Code,
) -> Runtime {
  // sp points to start of locals (current stack position)
  let sp = rt.sp
  let mut stack_top = rt.sp

  // Push arguments as first locals
  for arg in args {
    rt.stack.unsafe_set(stack_top, value_to_stack(arg))
    stack_top += 1
  }

  // Push default values for declared locals
  let rt2 = init_declared_locals({ ..rt, sp: stack_top }, code)
  if rt2.status == Trap {
    return { ..rt2, bp: sp }
  }

  // Set num_locals
  let num_locals = args.length() + code.locals.length()
  { ..rt2, bp: sp, num_locals }
}

///|
/// Check if two function type signatures match.
/// Returns Runtime with status set to Trap on mismatch.
fn check_type_signature_match(
  expected : @core.FuncType,
  actual : @core.FuncType,
  error_msg : String,
  rt : Runtime,
) -> Runtime {
  if expected.params.length() != actual.params.length() ||
    expected.results.length() != actual.results.length() {
    rt.ctx.error_detail = error_msg
    return { ..rt, status: Trap }
  }
  for i in 0..<expected.params.length() {
    if expected.params[i] != actual.params[i] {
      rt.ctx.error_detail = error_msg
      return { ..rt, status: Trap }
    }
  }
  for i in 0..<expected.results.length() {
    if expected.results[i] != actual.results[i] {
      rt.ctx.error_detail = error_msg
      return { ..rt, status: Trap }
    }
  }
  rt
}

///|
/// Call an imported function and push results onto the stack (as UInt64)
/// Returns Runtime with updated sp.
fn call_imported_function(
  rt : Runtime,
  func_idx : Int,
  args : Array[Value],
  expected_results : Int,
) -> Runtime {
  let imported_func = rt.ctx.imported_funcs[func_idx]
  let results = (imported_func.func)(args)
  let count = if expected_results < results.length() {
    expected_results
  } else {
    results.length()
  }
  let mut stack_top = rt.sp
  for i in 0..<count {
    rt.stack.unsafe_set(stack_top, value_to_stack(results[i]))
    stack_top += 1
  }
  { ..rt, sp: stack_top }
}

///|
/// Handle return from a tail call to imported function.
/// Results are already on stack, just restore caller state.
fn handle_tail_call_return(rt : Runtime) -> Runtime {
  if rt.ctx.call_stack.length() > 0 {
    let frame = rt.ctx.call_stack.unsafe_pop()
    {
      ..rt,
      bp: frame.caller_sp,
      num_locals: frame.caller_num_locals,
      pc: frame.return_pc + 1,
    }
  } else {
    { ..rt, status: Terminated }
  }
}

// ============================================================================
// Tagless UInt64 stack representation
// ============================================================================
//
// All WebAssembly values are stored as UInt64 on the stack:
//   - i32: stored in lower 32 bits (zero-extended)
//   - i64: stored directly
//   - f32: bit pattern in lower 32 bits (zero-extended)
//   - f64: bit pattern stored directly
//   - ref: stored as Int64 (with -1 representing null)
//
// This eliminates tagged union overhead and enables:
//   - Faster stack operations (no tag checking)
//   - Unified locals and operand stack
//   - Arguments stay in place during calls (zero-copy)
// ============================================================================

// ============================================================================
// Value conversion helpers (for imported function interface)
// ============================================================================

///|
/// Convert UInt64 stack value to tagged Value based on expected type
fn stack_to_value(raw : UInt64, val_type : @core.ValType) -> Value {
  match val_type {
    I32 => Value::I32((raw & 0xFFFFFFFFUL).to_uint())
    I64 => Value::I64(raw)
    F32 =>
      Value::F32(Float::reinterpret_from_uint((raw & 0xFFFFFFFFUL).to_uint()))
    F64 => Value::F64(raw.reinterpret_as_double())
    FuncRef
    | ExternRef
    | AnyRef
    | NullRef
    | NullFuncRef
    | NullExternRef
    | EqRef
    | I31Ref
    | StructRef
    | ArrayRef
    | ExnRef
    | NullExnRef
    | Ref(_, _) => {
      let idx = raw.to_int()
      if idx == -1 {
        Value::Ref(None)
      } else {
        Value::Ref(Some(idx))
      }
    }
    V128 => Value::I32((raw & 0xFFFFFFFFUL).to_uint()) // V128 not fully supported yet
  }
}

///|
/// Convert tagged Value to UInt64 stack value
fn value_to_stack(v : Value) -> UInt64 {
  match v {
    I32(x) => x.to_uint64()
    I64(x) => x
    F32(x) => x.reinterpret_as_uint().to_uint64()
    F64(x) => x.reinterpret_as_uint64()
    Ref(None) => (-1).to_int64().reinterpret_as_uint64()
    Ref(Some(idx)) => idx.to_int64().reinterpret_as_uint64()
  }
}

///|
extern "C" fn unsafe_function_to_uint64(f : (Runtime) -> Runtime) -> UInt64 = "unsafe_function_to_uint64"

///|
extern "C" fn unsafe_uint64_to_function(u : UInt64) -> (Runtime) -> Runtime = "unsafe_uint64_to_function"
