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
let canonical_nan_f64 : Double = 0x7ff8_0000_0000_0000UL.reinterpret_as_double()

///|
/// f32 canonical NaN: 0x7FC00000
let canonical_nan_f32 : Float = Float::reinterpret_from_uint(0x7fc0_0000U)

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
/// Round to nearest even (banker's rounding) for f64.
/// IEEE 754 "round to nearest, ties to even" - required by WebAssembly nearest.
fn round_nearest_even_f64(x : Double) -> Double {
  if x.is_nan() || x.is_inf() {
    return x
  }
  // Handle zero specially to preserve sign of -0.0
  if x == 0.0 {
    return x
  }
  // Handle negative numbers by working with absolute value
  let is_negative = x < 0.0
  let abs_x = x.abs()
  let floor_val = abs_x.floor()
  let frac = abs_x - floor_val
  let result = if frac < 0.5 {
    floor_val
  } else if frac > 0.5 {
    floor_val + 1.0
  } else {
    // Exactly 0.5 - round to nearest even
    let floor_int = floor_val.to_int64()
    if floor_int % 2L == 0L {
      floor_val // floor is even, round down
    } else {
      floor_val + 1.0 // floor is odd, round up to make it even
    }
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Round to nearest even (banker's rounding) for f32.
/// IEEE 754 "round to nearest, ties to even" - required by WebAssembly nearest.
fn round_nearest_even_f32(x : Float) -> Float {
  if x.is_nan() || x.is_inf() {
    return x
  }
  // Handle zero specially to preserve sign of -0.0
  if x == 0.0 {
    return x
  }
  // Handle negative numbers by working with absolute value
  let is_negative = x < 0.0
  let abs_x = x.abs()
  let floor_val = abs_x.floor()
  let frac = abs_x - floor_val
  let result : Float = if frac < 0.5 {
    floor_val
  } else if frac > 0.5 {
    floor_val + 1.0
  } else {
    // Exactly 0.5 - round to nearest even
    let floor_int = floor_val.to_int()
    if floor_int % 2 == 0 {
      floor_val // floor is even, round down
    } else {
      floor_val + 1.0 // floor is odd, round up to make it even
    }
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Convert f64 to uint64 with proper handling for large values.
/// MoonBit's to_uint64() may not work correctly for values >= 2^63.
/// For values in [0, 2^63), use standard conversion.
/// For values in [2^63, 2^64), subtract 2^63, convert, then add back.
fn f64_to_uint64(x : Double) -> UInt64 {
  // 2^63 = 9223372036854775808.0
  let two_pow_63 = 9223372036854775808.0
  if x < two_pow_63 {
    // Value is in range [0, 2^63), can convert directly via signed
    x.to_int64().reinterpret_as_uint64()
  } else {
    // Value is in range [2^63, 2^64), need special handling
    // Subtract 2^63, convert, then add 2^63 back as uint64
    let adjusted = x - two_pow_63
    let low_part = adjusted.to_int64().reinterpret_as_uint64()
    low_part + 0x8000000000000000UL
  }
}

///|
/// Convert f32 to uint64 with proper handling for large values.
fn f32_to_uint64(x : Float) -> UInt64 {
  f64_to_uint64(x.to_double())
}

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
  rt.sp = stack_top
  { rt, args }
}

///|
/// Initialize locals for entry point (call_compiled, start function).
/// Pushes args onto stack and sets bp/num_locals.
/// Declared locals will be initialized by compiled code's first instructions.
/// Returns Runtime with updated sp, bp, num_locals.
fn initialize_entry_locals(
  rt : Runtime,
  args : Array[Value],
  code : @core.Code,
) -> Runtime {
  // bp points to start of frame
  let bp = rt.sp
  let mut stack_top = rt.sp

  // Push arguments as first locals
  for arg in args {
    rt.stack.unsafe_set(stack_top, value_to_stack(arg))
    stack_top += 1
  }

  // Set num_locals (declared locals will be initialized by compiled code)
  let num_locals = args.length() + code.locals.length()
  rt.sp = stack_top
  rt.bp = bp
  rt.num_locals = num_locals
  rt
}

///|
/// Check if two function type signatures match.
/// Returns Trap on mismatch.
fn check_type_signature_match(
  expected : @core.FuncType,
  actual : @core.FuncType,
  error_msg : String,
  rt : Runtime,
) -> ReturnCode {
  if expected.params.length() != actual.params.length() ||
    expected.results.length() != actual.results.length() {
    rt.ctx.error_detail = error_msg
    return Trap
  }
  for i in 0..<expected.params.length() {
    if expected.params[i] != actual.params[i] {
      rt.ctx.error_detail = error_msg
      return Trap
    }
  }
  for i in 0..<expected.results.length() {
    if expected.results[i] != actual.results[i] {
      rt.ctx.error_detail = error_msg
      return Trap
    }
  }
  Running
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
  rt.sp = stack_top
  rt
}

///|
/// Push results from an external function call onto the stack.
/// Returns Runtime with updated sp.
fn push_results(rt : Runtime, results : Array[Value]) -> Runtime {
  let mut stack_top = rt.sp
  for i in 0..<results.length() {
    rt.stack.unsafe_set(stack_top, value_to_stack(results[i]))
    stack_top += 1
  }
  rt.sp = stack_top
  rt
}

///|
/// Handle return from a tail call to imported function.
/// Results are already on stack at sp, copy to bp and return a tail-call code.
/// Uses native stack approach - caller's execute_call will restore caller state.
fn handle_tail_call_return(rt : Runtime) -> ReturnCode {
  // Results are at stack[rt.bp..rt.sp) - they're already in place for tail calls
  // Just signal return to let native stack unwind
  if rt.bp == 0 {
    // Entry function - terminate
    Terminated
  } else {
    // Nested call - let native stack restore caller state
    Returned
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
    Ref(None) => 0xFFFFFFFFFFFFFFFFUL // null
    Ref(Some(idx)) => idx.to_int64().reinterpret_as_uint64()
    Funcref(None) => 0xFFFFFFFFFFFFFFFFUL // null
    Funcref(Some(idx)) => idx.to_uint64() | 0x4000000000000000UL // tag bit 62
    Externref(None) => 0xFFFFFFFFFFFFFFFFUL // null
    Externref(Some(idx)) => idx.to_uint64() | 0x2000000000000000UL
  } // tag bit 61
}
