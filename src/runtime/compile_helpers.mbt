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
/// Pop function arguments from the stack
fn Runtime::pop_arguments(self : Runtime, num_params : Int) -> Array[Value] {
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.unsafe_pop()
  }
  args
}

///|
/// Initialize local variables for a function call
fn Runtime::initialize_locals(
  self : Runtime,
  args : Array[Value],
  code : @core.Code,
) -> RetCode {
  self.locals = []
  for arg in args {
    self.locals.push(arg)
  }
  for local_type in code.locals {
    match local_type {
      I32 => self.locals.push(Value::I32(0U))
      I64 => self.locals.push(Value::I64(0UL))
      F32 => self.locals.push(Value::F32(0.0))
      F64 => self.locals.push(Value::F64(0.0))
      FuncRef => self.locals.push(Value::Ref(None))
      ExternRef => self.locals.push(Value::Ref(None))
      AnyRef
      | ExnRef
      | NullRef
      | NullFuncRef
      | NullExnRef
      | NullExternRef
      | EqRef
      | I31Ref
      | StructRef
      | ArrayRef
      | Ref(_, _) => self.locals.push(Value::Ref(None))
      _ => {
        self.error_detail = "Unsupported local type: \{local_type}"
        return UnsupportedLocalType
      }
    }
  }
  OK
}

///|
/// Check if two function type signatures match
fn check_type_signature_match(
  expected : @core.FuncType,
  actual : @core.FuncType,
  error_msg : String,
  rt : Runtime,
) -> RetCode {
  if expected.params.length() != actual.params.length() ||
    expected.results.length() != actual.results.length() {
    rt.error_detail = error_msg
    return InvalidType
  }
  for i in 0..<expected.params.length() {
    if expected.params[i] != actual.params[i] {
      rt.error_detail = error_msg
      return InvalidType
    }
  }
  for i in 0..<expected.results.length() {
    if expected.results[i] != actual.results[i] {
      rt.error_detail = error_msg
      return InvalidType
    }
  }
  OK
}

///|
/// Call an imported function and push results onto the stack
fn Runtime::call_imported_function(
  self : Runtime,
  func_idx : Int,
  args : Array[Value],
  expected_results : Int,
) -> Unit {
  let imported_func = self.imported_funcs[func_idx]
  let results = (imported_func.func)(args)
  let count = if expected_results < results.length() {
    expected_results
  } else {
    results.length()
  }
  for i in 0..<count {
    self.stack.push(results[i])
  }
}

///|
/// Handle return from a tail call (return_call variants)
fn Runtime::handle_tail_call_return(self : Runtime) -> RetCode {
  if self.call_stack.length() > 0 {
    let frame = self.call_stack.unsafe_pop()
    self.pc = frame.return_pc
    self.locals = frame.locals
    self.pc += 1
  } else {
    self.running = false
  }
  OK
}

///|
/// Emit an instruction to the ops array
fn Runtime::emit(self : Runtime, instr : MInstr) -> Unit {
  self.ops.push(instr)
}

///|
/// Read immediate i32 value and advance PC
fn Runtime::read_imm_i32(self : Runtime) -> UInt {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateI32(value)
  value
}

///|
/// Read immediate index value and advance PC
fn Runtime::read_imm_idx(self : Runtime) -> Int {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateIdx(value)
  value
}

// ============================================================================
// Stack value pop helpers
// ============================================================================

///|
fn Runtime::pop_two_i32(self : Runtime) -> (UInt, UInt) {
  let b = self.stack.unsafe_pop()
  let a = self.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) => (a_val, b_val)
    _ => abort("Type error: expected two i32 values")
  }
}

///|
fn Runtime::pop_i32(self : Runtime) -> UInt {
  match self.stack.unsafe_pop() {
    Value::I32(v) => v
    _ => abort("Type error: expected i32")
  }
}

///|
fn Runtime::pop_two_i64(self : Runtime) -> (UInt64, UInt64) {
  let b = self.stack.unsafe_pop()
  let a = self.stack.unsafe_pop()
  match (a, b) {
    (Value::I64(a_val), Value::I64(b_val)) => (a_val, b_val)
    _ => abort("Type error: expected two i64 values")
  }
}

///|
fn Runtime::pop_i64(self : Runtime) -> UInt64 {
  match self.stack.unsafe_pop() {
    Value::I64(v) => v
    _ => abort("Type error: expected i64")
  }
}

///|
fn Runtime::pop_f32(self : Runtime) -> Float {
  match self.stack.unsafe_pop() {
    Value::F32(v) => v
    _ => abort("Type error: expected f32")
  }
}

///|
fn Runtime::pop_two_f32(self : Runtime) -> (Float, Float) {
  let b = self.pop_f32()
  let a = self.pop_f32()
  (a, b)
}

///|
fn Runtime::pop_f64(self : Runtime) -> Double {
  match self.stack.unsafe_pop() {
    Value::F64(v) => v
    _ => abort("Type error: expected f64")
  }
}

///|
fn Runtime::pop_two_f64(self : Runtime) -> (Double, Double) {
  let b = self.pop_f64()
  let a = self.pop_f64()
  (a, b)
}
