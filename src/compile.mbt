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
pub extern "C" fn rint(x : Double) -> Double = "rint"

///|
pub extern "C" fn rintf(x : Float) -> Float = "rintf"

///|
/// Count the number of imported functions in a module
fn count_imported_funcs(module_ : Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      ImportDesc::Func(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Get the type index for a function (imported or local)
/// Returns -1 if the function index is invalid
fn get_func_type_idx(
  module_ : Module,
  func_idx : Int,
  num_imported : Int,
) -> Int {
  if func_idx < num_imported {
    // Imported function - find type index from imports
    let mut import_idx = 0
    let mut type_idx = -1
    for imp in module_.imports {
      match imp.desc {
        ImportDesc::Func(tidx) => {
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
  code : Code
) -> RetCode {
  self.locals = []
  for arg in args {
    self.locals.push(arg)
  }
  for local_type in code.locals {
    match local_type {
      ValType::I32 => self.locals.push(Value::I32(0U))
      ValType::I64 => self.locals.push(Value::I64(0UL))
      ValType::F32 => self.locals.push(Value::F32(0.0))
      ValType::F64 => self.locals.push(Value::F64(0.0))
      ValType::FuncRef => self.locals.push(Value::Ref(None))
      ValType::ExternRef => self.locals.push(Value::Ref(None))
      ValType::AnyRef
      | ValType::ExnRef
      | ValType::NullRef
      | ValType::NullFuncRef
      | ValType::NullExnRef
      | ValType::NullExternRef
      | ValType::EqRef
      | ValType::I31Ref
      | ValType::StructRef
      | ValType::ArrayRef
      | ValType::Ref(_, _) => self.locals.push(Value::Ref(None))
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
  expected : FuncType,
  actual : FuncType,
  error_msg : String,
  rt : Runtime
) -> RetCode {
  if expected.params.length() != actual.params.length() ||
    expected.results.length() != actual.results.length() {
    rt.error_detail = error_msg
    return InvalidType
  }
  for i = 0; i < expected.params.length(); i = i + 1 {
    if expected.params[i] != actual.params[i] {
      rt.error_detail = error_msg
      return InvalidType
    }
  }
  for i = 0; i < expected.results.length(); i = i + 1 {
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
  expected_results : Int
) -> Unit {
  let imported_func = self.imported_funcs[func_idx]
  let results = (imported_func.func)(args)
  for i = 0; i < expected_results && i < results.length(); i = i + 1 {
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
/// Return code for operations - simple integer enum for efficient ABI
pub enum RetCode {
  OK = 0
  DivisionByZero = 1
  IntegerOverflow = 2
  MemoryOutOfBounds = 3
  Unreachable = 4
  InvalidType = 5
  FunctionNotCompiled = 6
  UnsupportedLocalType = 7
} derive(Eq)

///|
/// Convert RetCode to RuntimeError using error_detail from Runtime
fn RetCode::to_error(self : RetCode, detail : String) -> RuntimeError {
  match self {
    OK => abort("OK is not an error")
    DivisionByZero => RuntimeError::DivisionByZero
    IntegerOverflow => RuntimeError::IntegerOverflow
    MemoryOutOfBounds => RuntimeError::MemoryOutOfBounds
    Unreachable => RuntimeError::Unreachable
    InvalidType => RuntimeError::InvalidType(detail)
    FunctionNotCompiled => RuntimeError::FunctionNotCompiled(detail)
    UnsupportedLocalType => RuntimeError::UnsupportedLocalType(detail)
  }
}

///|
/// Intermediate instruction for threaded interpreter
/// Operations return RetCode (0 = OK, non-zero = error)
enum MInstr {
  WasmInstr((Runtime) -> RetCode)
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Call frame for function calls
struct CallFrame {
  return_pc : Int
  locals : Array[Value]
}

///|
/// Block kind for compile-time control flow tracking
enum CompileBlockKind {
  BlockKind // br jumps to end, uses results
  LoopKind // br jumps to start, uses params
  IfKind // br jumps to end, uses results
} derive(Eq)

///|
/// Compile-time control frame for tracking block types and stack heights
priv struct CompileBlock {
  kind : CompileBlockKind
  params : Array[ValType]
  results : Array[ValType]
  stack_height_at_entry : Int // type_stack.length() when block started (after params popped)
  // For loops: the PC to jump to (known at block start)
  // For blocks/if: 0 (unused, patches go to pending_br_patches)
  target_pc : Int
  // Slots that need to be patched with the end PC (for blocks/if)
  pending_br_patches : Array[Int]
}

///|
/// Compile-time context for tracking types during compilation
priv struct CompileCtx {
  type_stack : Array[ValType]
  control_stack : Array[CompileBlock]
}

///|
fn CompileCtx::new() -> CompileCtx {
  { type_stack: [], control_stack: [] }
}

///|
fn CompileCtx::push_type(self : CompileCtx, t : ValType) -> Unit {
  self.type_stack.push(t)
}

///|
fn CompileCtx::pop_type(self : CompileCtx) -> Unit {
  if self.type_stack.length() > 0 {
    let _ = self.type_stack.unsafe_pop()

  }
}

///|
fn CompileCtx::pop_types(self : CompileCtx, n : Int) -> Unit {
  for _ in 0..<n {
    self.pop_type()
  }
}

///|
fn CompileCtx::push_types(self : CompileCtx, types : Array[ValType]) -> Unit {
  for t in types {
    self.push_type(t)
  }
}

///|
fn CompileCtx::push_control(
  self : CompileCtx,
  kind : CompileBlockKind,
  params : Array[ValType],
  results : Array[ValType],
  target_pc : Int, // For loops: start PC; for blocks/if: placeholder (0), will be patched
) -> Unit {
  // Pop params from type stack (they're consumed by the block)
  self.pop_types(params.length())
  let height = self.type_stack.length()
  self.control_stack.push({
    kind,
    params,
    results,
    stack_height_at_entry: height,
    target_pc,
    pending_br_patches: [],
  })
  // Push params back as the block's initial stack (block body sees them)
  self.push_types(params)
}

///|
fn CompileCtx::pop_control(self : CompileCtx) -> CompileBlock {
  self.control_stack.unsafe_pop()
}

///|
/// Truncate type stack to a given height
fn CompileCtx::truncate_stack(self : CompileCtx, height : Int) -> Unit {
  while self.type_stack.length() > height {
    let _ = self.type_stack.unsafe_pop()

  }
}

///|
/// Get the branch target arity for a given label depth
/// For blocks/if: arity = number of result types
/// For loops: arity = number of param types (loop restarts)
fn CompileCtx::get_branch_arity(self : CompileCtx, label : Int) -> Int {
  let idx = self.control_stack.length() - 1 - label
  let block = self.control_stack[idx]
  match block.kind {
    LoopKind => block.params.length()
    BlockKind | IfKind => block.results.length()
  }
}

///|
/// Get the stack height at the target block's entry
fn CompileCtx::get_target_stack_height(self : CompileCtx, label : Int) -> Int {
  let idx = self.control_stack.length() - 1 - label
  self.control_stack[idx].stack_height_at_entry
}

///|
/// Calculate how many values to drop when branching to a label
fn CompileCtx::calc_drop_count(
  self : CompileCtx,
  label : Int,
  arity : Int,
) -> Int {
  let current_height = self.type_stack.length()
  let target_height = self.get_target_stack_height(label)
  current_height - target_height - arity
}

///|
/// Get the target PC for a branch to the given label
/// For loops, this is the known start PC
/// For blocks/if, returns the current target_pc (may be placeholder if not yet known)
fn CompileCtx::get_target_pc(self : CompileCtx, label : Int) -> Int {
  let idx = self.control_stack.length() - 1 - label
  self.control_stack[idx].target_pc
}

///|
/// Check if the target block is a loop (target PC is already known)
fn CompileCtx::is_loop_target(self : CompileCtx, label : Int) -> Bool {
  let idx = self.control_stack.length() - 1 - label
  self.control_stack[idx].kind == LoopKind
}

///|
/// Register a slot that needs to be patched with the target PC when the block ends
fn CompileCtx::add_br_patch(self : CompileCtx, label : Int, slot : Int) -> Unit {
  let idx = self.control_stack.length() - 1 - label
  self.control_stack[idx].pending_br_patches.push(slot)
}

///|
/// Get block type from BlockType enum (similar to validation's get_block_type)
fn get_compile_block_type(
  module_ : Module,
  block_type : BlockType,
) -> (Array[ValType], Array[ValType]) {
  match block_type {
    Empty => ([], [])
    Value(t) => ([], [t])
    TypeIndex(idx) => {
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
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
// Helper to pop two i32 values
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

// ============================================================================
// i32 instruction implementations
// ============================================================================

///|
fn op_i32_const(rt : Runtime) -> RetCode {
  let value = rt.read_imm_i32()
  rt.stack.push(Value::I32(value))
  rt.pc += 1
  OK
}

///|
fn op_i32_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a + b))
  rt.pc += 1
  OK
}

///|
fn op_i32_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a - b))
  rt.pc += 1
  OK
}

///|
fn op_i32_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a * b))
  rt.pc += 1
  OK
}

///|
fn op_i32_div_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return DivisionByZero
  }
  if a == 0x80000000U && b == 0xFFFFFFFFU {
    return IntegerOverflow
  }
  let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_div_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return DivisionByZero
  }
  rt.stack.push(Value::I32(a / b))
  rt.pc += 1
  OK
}

///|
fn op_i32_rem_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return DivisionByZero
  }
  let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_rem_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return DivisionByZero
  }
  rt.stack.push(Value::I32(a % b))
  rt.pc += 1
  OK
}

///|
fn op_i32_and(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a & b))
  rt.pc += 1
  OK
}

///|
fn op_i32_or(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a | b))
  rt.pc += 1
  OK
}

///|
fn op_i32_xor(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a ^ b))
  rt.pc += 1
  OK
}

///|
fn op_i32_shl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a << shift))
  rt.pc += 1
  OK
}

///|
fn op_i32_shr_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  let result = (a.reinterpret_as_int() >> shift).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_shr_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a >> shift))
  rt.pc += 1
  OK
}

///|
fn op_i32_rotl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a << rotation) | (a >> (32 - rotation))
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_rotr(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a >> rotation) | (a << (32 - rotation))
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

// Comparison operations

///|
fn op_i32_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_lt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() < b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_lt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_gt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() > b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_gt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_le_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() <= b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_le_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_ge_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() >= b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_ge_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

// Unary operations

///|
fn op_i32_eqz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(if a == 0U { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i32_clz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.clz().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_ctz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.ctz().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_popcnt(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.popcnt().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_extend8_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let byte = a & 0xFFU
  let result = if (byte & 0x80U) != 0U { byte | 0xFFFFFF00U } else { byte }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_extend16_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let half = a & 0xFFFFU
  let result = if (half & 0x8000U) != 0U { half | 0xFFFF0000U } else { half }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_wrap_i64(rt : Runtime) -> RetCode {
  match rt.stack.unsafe_pop() {
    Value::I64(v) => rt.stack.push(Value::I32((v & 0xFFFFFFFFUL).to_uint()))
    _ => abort("Type error: expected i64")
  }
  rt.pc += 1
  OK
}

// ============================================================================
// i64 instruction implementations
// ============================================================================

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
fn op_i64_const(rt : Runtime) -> RetCode {
  // Read two i32 immediates to form i64
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let value = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::I64(value))
  rt.pc += 1
  OK
}

///|
fn op_f32_const(rt : Runtime) -> RetCode {
  let bits = rt.read_imm_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(bits)))
  rt.pc += 1
  OK
}

///|
fn op_f64_const(rt : Runtime) -> RetCode {
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let bits = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::F64(bits.reinterpret_as_double()))
  rt.pc += 1
  OK
}

///|
fn op_i64_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a + b))
  rt.pc += 1
  OK
}

///|
fn op_i64_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a - b))
  rt.pc += 1
  OK
}

///|
fn op_i64_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a * b))
  rt.pc += 1
  OK
}

///|
fn op_i64_div_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return DivisionByZero
  }
  if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
    return IntegerOverflow
  }
  let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_div_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return DivisionByZero
  }
  rt.stack.push(Value::I64(a / b))
  rt.pc += 1
  OK
}

///|
fn op_i64_rem_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return DivisionByZero
  }
  let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_rem_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return DivisionByZero
  }
  rt.stack.push(Value::I64(a % b))
  rt.pc += 1
  OK
}

///|
fn op_i64_and(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a & b))
  rt.pc += 1
  OK
}

///|
fn op_i64_or(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a | b))
  rt.pc += 1
  OK
}

///|
fn op_i64_xor(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a ^ b))
  rt.pc += 1
  OK
}

///|
fn op_i64_shl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a << shift))
  rt.pc += 1
  OK
}

///|
fn op_i64_shr_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  let result = (a.reinterpret_as_int64() >> shift).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_shr_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a >> shift))
  rt.pc += 1
  OK
}

///|
fn op_i64_rotl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a << rotation) | (a >> (64 - rotation))
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_rotr(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a >> rotation) | (a << (64 - rotation))
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

// i64 comparison operations

///|
fn op_i64_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_lt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() < b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_lt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_gt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() > b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_gt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_le_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() <= b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_le_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_ge_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() >= b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_ge_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

// i64 unary operations

///|
fn op_i64_eqz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I32(if a == 0UL { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_i64_clz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.clz().to_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_ctz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.ctz().to_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_popcnt(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.popcnt().to_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_extend8_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let byte = a & 0xFFUL
  let result = if (byte & 0x80UL) != 0UL {
    byte | 0xFFFFFFFFFFFFFF00UL
  } else {
    byte
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_extend16_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let half = a & 0xFFFFUL
  let result = if (half & 0x8000UL) != 0UL {
    half | 0xFFFFFFFFFFFF0000UL
  } else {
    half
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_extend32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let word = a & 0xFFFFFFFFUL
  let result = if (word & 0x80000000UL) != 0UL {
    word | 0xFFFFFFFF00000000UL
  } else {
    word
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_extend_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let result = a.reinterpret_as_int().to_int64().reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_extend_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I64(a.to_uint64()))
  rt.pc += 1
  OK
}

// ============================================================================
// Local/Global variable operations
// ============================================================================

///|
fn op_local_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.locals[idx])
  rt.pc += 1
  OK
}

///|
fn op_local_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.locals[idx] = value
  rt.pc += 1
  OK
}

///|
fn op_local_tee(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack[rt.stack.length() - 1]
  rt.locals[idx] = value
  rt.pc += 1
  OK
}

// ============================================================================
// Stack operations
// ============================================================================

///|
fn op_drop(rt : Runtime) -> RetCode {
  let _ = rt.stack.unsafe_pop()
  rt.pc += 1
  OK
}

///|
fn op_select(rt : Runtime) -> RetCode {
  let cond = rt.pop_i32()
  let val2 = rt.stack.unsafe_pop()
  let val1 = rt.stack.unsafe_pop()
  rt.stack.push(if cond != 0U { val1 } else { val2 })
  rt.pc += 1
  OK
}

// ============================================================================
// Control flow operations
// ============================================================================

///|
fn op_if(rt : Runtime) -> RetCode {
  let else_pc = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    rt.pc += 1
  } else {
    rt.pc = else_pc
  }
  OK
}

// NOTE: op_else, op_end_block, op_push_block_target, op_push_loop_target removed
// Branch targets are now computed at compile time and embedded directly in branch instructions

///|
fn op_br(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()

  // Save the top `arity` values (the branch result values)
  let results : Array[Value] = []
  for _ in 0..<arity {
    results.push(rt.stack.unsafe_pop())
  }

  // Drop the unwanted values
  for _ in 0..<drop_count {
    let _ = rt.stack.unsafe_pop()

  }

  // Push results back (in reverse order since we popped them)
  for i = results.length() - 1; i >= 0; i = i - 1 {
    rt.stack.push(results[i])
  }
  rt.pc = target_pc
  OK
}

///|
fn op_br_if(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    // Save the top `arity` values (the branch result values)
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back (in reverse order since we popped them)
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    rt.pc += 1
  }
  OK
}

///|
fn op_br_table(rt : Runtime) -> RetCode {
  let num_labels = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let index = rt.pop_i32().reinterpret_as_int()

  // Read all target_pc+drop_count pairs, selecting the right one
  let mut target_pc = 0
  let mut drop_count = 0
  for i = 0; i <= num_labels; i = i + 1 {
    let pc = rt.read_imm_idx()
    let lbl_drop = rt.read_imm_idx()
    if i == index && i < num_labels {
      target_pc = pc
      drop_count = lbl_drop
    } else if i == num_labels && (index < 0 || index >= num_labels) {
      // Default label
      target_pc = pc
      drop_count = lbl_drop
    }
  }

  // Save the top `arity` values (the branch result values)
  let results : Array[Value] = []
  for _ in 0..<arity {
    results.push(rt.stack.unsafe_pop())
  }

  // Drop the unwanted values
  for _ in 0..<drop_count {
    let _ = rt.stack.unsafe_pop()

  }

  // Push results back (in reverse order since we popped them)
  for i = results.length() - 1; i >= 0; i = i - 1 {
    rt.stack.push(results[i])
  }
  rt.pc = target_pc
  OK
}

///|
fn op_br_on_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's null
  let is_null = match ref_val {
    Ref(None) => true
    _ => false
  }
  if is_null {
    // Save the top `arity` values
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    // Not null - push back the value and continue
    rt.stack.push(ref_val)
    rt.pc += 1
  }
  OK
}

///|
fn op_br_on_non_null(rt : Runtime) -> RetCode {
  let target_pc = rt.read_imm_idx()
  let arity = rt.read_imm_idx()
  let drop_count = rt.read_imm_idx()
  // Pop reference value
  let ref_val = rt.stack.unsafe_pop()
  // Check if it's not null
  let is_non_null = match ref_val {
    Ref(None) => false
    _ => true
  }
  if is_non_null {
    // Save the top `arity` values (includes the ref we just popped if arity > 0)
    rt.stack.push(ref_val) // Push it back first for proper handling
    let results : Array[Value] = []
    for _ in 0..<arity {
      results.push(rt.stack.unsafe_pop())
    }

    // Drop the unwanted values
    for _ in 0..<drop_count {
      let _ = rt.stack.unsafe_pop()

    }

    // Push results back
    for i = results.length() - 1; i >= 0; i = i - 1 {
      rt.stack.push(results[i])
    }
    rt.pc = target_pc
  } else {
    // Null - don't push anything, continue
    rt.pc += 1
  }
  OK
}

///|
fn op_call(rt : Runtime) -> RetCode {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "call: invalid imported function index"
      return InvalidType
    }
    let func_type = rt.module_.types[type_idx]
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(func_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_return(rt : Runtime) -> RetCode {
  if rt.call_stack.length() == 0 {
    rt.running = false
    return OK
  }
  let return_value : Value? = if rt.stack.length() > 0 {
    Some(rt.stack.unsafe_pop())
  } else {
    None
  }
  let frame = rt.call_stack.unsafe_pop()
  rt.locals = frame.locals
  match return_value {
    Some(v) => rt.stack.push(v)
    None => ()
  }
  rt.pc = frame.return_pc + 1
  OK
}

///|
fn op_call_indirect(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  let elem_idx = rt.pop_i32().reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "call_indirect: invalid table index"
    return InvalidType
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    return InvalidType
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = rt.module_.types[type_idx]

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "call_indirect: invalid imported function index"
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      expected_type,
      actual_type,
      "indirect call type mismatch",
      rt,
    )
    if check_result != OK {
      return check_result
    }

    let args = rt.pop_arguments(actual_type.params.length())
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_indirect: invalid function index"
    return InvalidType
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    expected_type,
    actual_type,
    "indirect call type mismatch",
    rt,
  )
  if check_result != OK {
    return check_result
  }

  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(actual_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_end(rt : Runtime) -> RetCode {
  if rt.call_stack.length() > 0 {
    op_return(rt)
  } else {
    rt.running = false
    OK
  }
}

///|
fn op_return_call(rt : Runtime) -> RetCode {
  let func_idx = rt.read_imm_idx()
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let type_idx = get_func_type_idx(rt.module_, func_idx, num_imported_funcs)
    if type_idx < 0 {
      rt.error_detail = "return_call: invalid imported function index"
      return InvalidType
    }
    let func_type = rt.module_.types[type_idx]
    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  let type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(func_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_return_call_indirect(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()
  let table_idx = rt.read_imm_idx()

  // Pop the function index from the stack
  let elem_idx = rt.pop_i32().reinterpret_as_int()

  // Check table bounds
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "return_call_indirect: invalid table index"
    return InvalidType
  }
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "undefined element"
    return InvalidType
  }

  // Get function reference from table
  let func_ref = table[elem_idx]
  guard func_ref is Some(func_idx) else {
    rt.error_detail = "uninitialized element"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected type
  let expected_type = rt.module_.types[type_idx]

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "return_call_indirect: invalid imported function index"
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      expected_type,
      actual_type,
      "indirect call type mismatch",
      rt,
    )
    if check_result != OK {
      return check_result
    }

    let args = rt.pop_arguments(actual_type.params.length())
    rt.call_imported_function(func_idx, args, expected_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust to local function index
  let local_func_idx = func_idx - num_imported_funcs

  // Check function index bounds
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_indirect: invalid function index"
    return InvalidType
  }

  // Get the actual function type
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    expected_type,
    actual_type,
    "indirect call type mismatch",
    rt,
  )
  if check_result != OK {
    return check_result
  }

  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(actual_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(Some(func_idx)) else {
    rt.error_detail = "call_ref: null or invalid function reference"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = rt.module_.types[type_idx]

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "call_ref: invalid imported function index"
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      func_type,
      actual_type,
      "call_ref: type mismatch",
      rt,
    )
    if check_result != OK {
      return check_result
    }

    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    rt.pc += 1
    return OK
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "call_ref: invalid function index"
    return InvalidType
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    func_type,
    actual_type,
    "call_ref: type mismatch",
    rt,
  )
  if check_result != OK {
    return check_result
  }

  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(func_type.params.length())

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_return_call_ref(rt : Runtime) -> RetCode {
  let type_idx = rt.read_imm_idx()

  // Pop the function reference from the stack
  let func_ref_value = rt.stack.unsafe_pop()
  guard func_ref_value is Ref(Some(func_idx)) else {
    rt.error_detail = "return_call_ref: null or invalid function reference"
    return InvalidType
  }
  let num_imported_funcs = count_imported_funcs(rt.module_)

  // Get the expected function type
  let func_type = rt.module_.types[type_idx]

  // Check if calling an imported function
  if func_idx < num_imported_funcs {
    // Get the imported function's type from the import descriptor
    let actual_type_idx = get_func_type_idx(
      rt.module_,
      func_idx,
      num_imported_funcs,
    )
    if actual_type_idx < 0 {
      rt.error_detail = "return_call_ref: invalid imported function index"
      return InvalidType
    }
    let actual_type = rt.module_.types[actual_type_idx]

    // Check type signature matches
    let check_result = check_type_signature_match(
      func_type,
      actual_type,
      "return_call_ref: type mismatch",
      rt,
    )
    if check_result != OK {
      return check_result
    }

    let args = rt.pop_arguments(func_type.params.length())
    rt.call_imported_function(func_idx, args, func_type.results.length())
    return rt.handle_tail_call_return()
  }

  // Adjust index for local functions
  let local_func_idx = func_idx - num_imported_funcs
  if local_func_idx < 0 || local_func_idx >= rt.module_.codes.length() {
    rt.error_detail = "return_call_ref: invalid function index"
    return InvalidType
  }
  let actual_type_idx = rt.module_.funcs[local_func_idx].reinterpret_as_int()
  let actual_type = rt.module_.types[actual_type_idx]

  // Check type signature matches
  let check_result = check_type_signature_match(
    func_type,
    actual_type,
    "return_call_ref: type mismatch",
    rt,
  )
  if check_result != OK {
    return check_result
  }

  let code = rt.module_.codes[local_func_idx]
  guard code.compiled is Some(callee_pc) else {
    rt.error_detail = "Function not compiled: \{func_idx}"
    return FunctionNotCompiled
  }

  let args = rt.pop_arguments(func_type.params.length())

  // For tail call: replace current locals instead of pushing new frame
  let init_result = rt.initialize_locals(args, code)
  if init_result != OK {
    return init_result
  }

  rt.pc = callee_pc
  OK
}

///|
fn op_nop(rt : Runtime) -> RetCode {
  rt.pc += 1
  OK
}

///|
fn op_unreachable(_rt : Runtime) -> RetCode {
  return Unreachable
}

// =============================================================================
// Memory Operations - Bounds Checking
// =============================================================================
//
// IMPORTANT: Memory address bounds checking must check for BOTH:
//   1. addr < 0 (negative addresses)
//   2. addr + size > memory.length() (overflow past end)
//
// WHY NEGATIVE ADDRESS CHECK IS NEEDED:
// WebAssembly addresses are unsigned 32-bit values, but when we convert them
// to signed integers for array indexing (via reinterpret_as_int()), large
// unsigned values (>= 2^31) become negative signed values.
//
// For example:
//   - Address 0xFFFFFFFF (u32 max) becomes -1 when reinterpreted as signed
//   - Without the addr < 0 check, this would cause an array index out of bounds
//     crash instead of a proper WebAssembly trap
//
// The check `addr < 0` catches these cases and returns MemoryOutOfBounds trap.
// =============================================================================

///|
fn op_i32_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  // Use 64-bit arithmetic to detect overflow
  // Base address is treated as unsigned 32-bit value
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  rt.stack.push(Value::I32(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
  rt.pc += 1
  OK
}

///|
fn op_i32_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

// Additional memory load operations

///|
fn op_i32_load8_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.memory[addr].to_int()
  // Sign extend from 8 bits
  let value = if b >= 128 { b - 256 } else { b }
  rt.stack.push(Value::I32(value.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_load8_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.stack.push(Value::I32(rt.memory[addr].to_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_load16_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int()
  let b1 = rt.memory[addr + 1].to_int()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768 { value16 - 65536 } else { value16 }
  rt.stack.push(Value::I32(value.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_load16_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  rt.stack.push(Value::I32(b0 | (b1 << 8)))
  rt.pc += 1
  OK
}

///|
fn op_i64_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  rt.stack.push(
    Value::I64(
      b0 |
      (b1 << 8) |
      (b2 << 16) |
      (b3 << 24) |
      (b4 << 32) |
      (b5 << 40) |
      (b6 << 48) |
      (b7 << 56),
    ),
  )
  rt.pc += 1
  OK
}

///|
fn op_i64_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_load8_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.memory[addr].to_int64()
  // Sign extend from 8 bits
  let value = if b >= 128L { b - 256L } else { b }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_load8_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.stack.push(Value::I64(rt.memory[addr].to_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_load16_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768L { value16 - 65536L } else { value16 }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_load16_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  rt.stack.push(Value::I64(b0 | (b1 << 8)))
  rt.pc += 1
  OK
}

///|
fn op_i64_load32_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let b2 = rt.memory[addr + 2].to_int64()
  let b3 = rt.memory[addr + 3].to_int64()
  let value32 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  // Sign extend from 32 bits
  let value = if value32 >= 0x80000000L {
    value32 - 0x100000000L
  } else {
    value32
  }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_load32_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  rt.stack.push(Value::I64(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
  rt.pc += 1
  OK
}

///|
fn op_f32_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(bits)))
  rt.pc += 1
  OK
}

///|
fn op_f64_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  rt.stack.push(Value::F64(bits.reinterpret_as_double()))
  rt.pc += 1
  OK
}

///|
fn op_f32_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_f32().reinterpret_as_uint()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_f64_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_f64().reinterpret_as_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

// Narrow store operations

///|
fn op_i32_store8(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i32_store16(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store8(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store16(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store32(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

// Memory size and grow operations
// WebAssembly memory is measured in pages of 64KB (65536 bytes)

///|
let wasm_page_size : Int = 65536

///|
fn op_memory_size(rt : Runtime) -> RetCode {
  // Return current memory size in pages
  let size_in_pages = rt.memory.length() / wasm_page_size
  rt.stack.push(Value::I32(size_in_pages.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_memory_grow(rt : Runtime) -> RetCode {
  let delta_pages = rt.pop_i32().reinterpret_as_int()
  let old_size_pages = rt.memory.length() / wasm_page_size

  // Check for overflow or negative delta
  if delta_pages < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let new_size_pages = old_size_pages + delta_pages

  // Check against maximum memory limit from module definition
  // If no max is defined, WebAssembly spec allows up to 65536 pages (4GB)
  let max_pages = match rt.memory_max {
    Some(max) => max.reinterpret_as_int()
    None => 65536 // No limit specified in module
  }
  if new_size_pages > max_pages {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }

  // Grow the memory by appending zero bytes
  let bytes_to_add = delta_pages * wasm_page_size
  for i = 0; i < bytes_to_add; i = i + 1 {
    rt.memory.push(b'\x00')
  }

  // Return old size in pages (success)
  rt.stack.push(Value::I32(old_size_pages.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

// =============================================================================
// Bulk memory operations
// =============================================================================

///|
fn op_memory_copy(rt : Runtime) -> RetCode {
  let n = rt.pop_i32().reinterpret_as_int()
  let src = rt.pop_i32().reinterpret_as_int()
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > rt.memory.length() ||
    dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Handle overlapping regions correctly
  if n > 0 {
    if dest <= src {
      // Copy forward
      for i = 0; i < n; i = i + 1 {
        rt.memory[dest + i] = rt.memory[src + i]
      }
    } else {
      // Copy backward (for overlapping regions where dest > src)
      for i = n - 1; i >= 0; i = i - 1 {
        rt.memory[dest + i] = rt.memory[src + i]
      }
    }
  }
  rt.pc += 1
  OK
}

///|
fn op_memory_fill(rt : Runtime) -> RetCode {
  let n = rt.pop_i32().reinterpret_as_int()
  let val = rt.pop_i32().reinterpret_as_int() & 0xFF // Truncate to byte
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check bounds
  if dest < 0 || n < 0 || dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Fill memory
  let byte_val = val.to_byte()
  for i = 0; i < n; i = i + 1 {
    rt.memory[dest + i] = byte_val
  }
  rt.pc += 1
  OK
}

///|
fn op_memory_init(rt : Runtime) -> RetCode {
  let data_idx = rt.read_imm_idx()
  let n = rt.pop_i32().reinterpret_as_int()
  let src = rt.pop_i32().reinterpret_as_int()
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.data_segments.length() {
    rt.error_detail = "unknown data segment"
    return InvalidType
  }
  let data = rt.data_segments[data_idx]

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > data.length() ||
    dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Copy from data segment to memory
  for i = 0; i < n; i = i + 1 {
    rt.memory[dest + i] = data[src + i]
  }
  rt.pc += 1
  OK
}

///|
fn op_data_drop(rt : Runtime) -> RetCode {
  let data_idx = rt.read_imm_idx()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.data_segments.length() {
    rt.error_detail = "unknown data segment"
    return InvalidType
  }

  // Drop the data segment (make it empty)
  rt.data_segments[data_idx] = []
  rt.pc += 1
  OK
}

// =============================================================================
// Table bulk operations (stub implementations)
// =============================================================================

///|
fn op_table_init(rt : Runtime) -> RetCode {
  let _table_idx = rt.read_imm_idx()
  let _elem_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.init
  rt.pc += 1
  OK
}

///|
fn op_table_copy(rt : Runtime) -> RetCode {
  let _dst_table_idx = rt.read_imm_idx()
  let _src_table_idx = rt.read_imm_idx()
  let _n = rt.pop_i32()
  let _src = rt.pop_i32()
  let _dest = rt.pop_i32()
  // TODO: Implement table.copy
  rt.pc += 1
  OK
}

///|
fn op_elem_drop(rt : Runtime) -> RetCode {
  let _elem_idx = rt.read_imm_idx()
  // TODO: Implement elem.drop
  rt.pc += 1
  OK
}

// =============================================================================
// Table operations
// =============================================================================

///|
fn op_table_size(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let size = rt.tables[table_idx].data.length()
  rt.stack.push(Value::I32(size.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_table_get(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    return InvalidType
  }
  // Return the function reference (or null)
  rt.stack.push(Value::Ref(table[elem_idx]))
  rt.pc += 1
  OK
}

///|
fn op_table_set(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.error_detail = "table index out of bounds"
    return InvalidType
  }
  let ref_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.error_detail = "expected funcref for table.set"
      return InvalidType
    }
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    rt.error_detail = "table element index out of bounds"
    return InvalidType
  }
  table[elem_idx] = ref_value
  rt.pc += 1
  OK
}

///|
fn op_table_grow(rt : Runtime) -> RetCode {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let delta = rt.pop_i32().reinterpret_as_int()
  let init_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.stack.push(Value::I32(0xFFFFFFFFU))
      rt.pc += 1
      return OK
    }
  }
  let runtime_table = rt.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()
  if delta < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.push(Value::I32(0xFFFFFFFFU))
        rt.pc += 1
        return OK
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }
  rt.stack.push(Value::I32(old_size.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

// =============================================================================
// Reference operations
// =============================================================================

///|
fn op_ref_null(rt : Runtime) -> RetCode {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.read_imm_idx() // Skip the heap type encoding
  rt.stack.push(Value::Ref(None))
  rt.pc += 1
  OK
}

///|
fn op_ref_func(rt : Runtime) -> RetCode {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.read_imm_idx()
  rt.stack.push(Value::Ref(Some(func_idx)))
  rt.pc += 1
  OK
}

///|
fn op_ref_is_null(rt : Runtime) -> RetCode {
  // ref.is_null tests whether a reference is null
  let ref_val = rt.stack.unsafe_pop()
  let is_null = match ref_val {
    Value::Ref(None) => 1U
    Value::Ref(Some(_)) => 0U
    _ => 0U // Non-ref values are considered not null
  }
  rt.stack.push(Value::I32(is_null))
  rt.pc += 1
  OK
}

// Float operations

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

///|
fn op_f32_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_lt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_gt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_le(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_ge(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_lt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_gt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_le(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_ge(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

// Float unary operations

///|
fn op_f32_neg(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(-a))
  rt.pc += 1
  OK
}

///|
fn op_f32_abs(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(a.abs()))
  rt.pc += 1
  OK
}

///|
fn op_f32_sqrt(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.sqrt())))
  rt.pc += 1
  OK
}

///|
fn op_f32_ceil(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.ceil())))
  rt.pc += 1
  OK
}

///|
fn op_f32_floor(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.floor())))
  rt.pc += 1
  OK
}

///|
fn op_f32_trunc(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.trunc())))
  rt.pc += 1
  OK
}

///|
fn op_f32_nearest(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(rintf(a))))
  rt.pc += 1
  OK
}

///|
fn op_f64_neg(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(-a))
  rt.pc += 1
  OK
}

// Float binary operations

///|
fn op_f32_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a + b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a - b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a * b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_div(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a / b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_min(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a < b {
    a
  } else if b < a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // -0.0 is considered "smaller" than +0.0 for min
    // Check sign bits: if either is negative zero, return negative zero
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    let sign_mask = 0x8000_0000U
    if (a_bits & sign_mask) != 0U || (b_bits & sign_mask) != 0U {
      // At least one is negative, return the one with negative sign
      if (a_bits & sign_mask) != 0U {
        a
      } else {
        b
      }
    } else {
      a // Both positive, return either
    }
  }
  rt.stack.push(Value::F32(result))
  rt.pc += 1
  OK
}

///|
fn op_f32_max(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a > b {
    a
  } else if b > a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // +0.0 is considered "larger" than -0.0 for max
    // Check sign bits: if either is positive zero, return positive zero
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    let sign_mask = 0x8000_0000U
    if (a_bits & sign_mask) == 0U || (b_bits & sign_mask) == 0U {
      // At least one is positive, return the one with positive sign
      if (a_bits & sign_mask) == 0U {
        a
      } else {
        b
      }
    } else {
      a // Both negative, return either
    }
  }
  rt.stack.push(Value::F32(result))
  rt.pc += 1
  OK
}

///|
fn op_f32_copysign(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  let a_bits = a.reinterpret_as_uint()
  let b_bits = b.reinterpret_as_uint()
  let sign_mask = 0x8000_0000U
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(result_bits)))
  rt.pc += 1
  OK
}

///|
fn op_f64_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a + b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a - b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a * b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_div(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a / b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_min(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  // WebAssembly min semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a < b {
    a
  } else if b < a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // -0.0 is considered "smaller" than +0.0 for min
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    let sign_mask = 0x8000_0000_0000_0000UL
    if (a_bits & sign_mask) != 0UL || (b_bits & sign_mask) != 0UL {
      // At least one is negative, return the one with negative sign
      if (a_bits & sign_mask) != 0UL {
        a
      } else {
        b
      }
    } else {
      a // Both positive, return either
    }
  }
  rt.stack.push(Value::F64(result))
  rt.pc += 1
  OK
}

///|
fn op_f64_max(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  // WebAssembly max semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a > b {
    a
  } else if b > a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // +0.0 is considered "larger" than -0.0 for max
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    let sign_mask = 0x8000_0000_0000_0000UL
    if (a_bits & sign_mask) == 0UL || (b_bits & sign_mask) == 0UL {
      // At least one is positive, return the one with positive sign
      if (a_bits & sign_mask) == 0UL {
        a
      } else {
        b
      }
    } else {
      a // Both negative, return either
    }
  }
  rt.stack.push(Value::F64(result))
  rt.pc += 1
  OK
}

///|
fn op_f64_copysign(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  let a_bits = a.reinterpret_as_uint64()
  let b_bits = b.reinterpret_as_uint64()
  let sign_mask = 0x8000_0000_0000_0000UL
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F64(result_bits.reinterpret_as_double()))
  rt.pc += 1
  OK
}

// Float unary operations

///|
fn op_f64_abs(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(a.abs()))
  rt.pc += 1
  OK
}

///|
fn op_f64_sqrt(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.sqrt())))
  rt.pc += 1
  OK
}

///|
fn op_f64_ceil(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.ceil())))
  rt.pc += 1
  OK
}

///|
fn op_f64_floor(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.floor())))
  rt.pc += 1
  OK
}

///|
fn op_f64_trunc(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.trunc())))
  rt.pc += 1
  OK
}

///|
fn op_f64_nearest(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(rint(a))))
  rt.pc += 1
  OK
}

// Float conversion operations

///|
fn op_f64_convert_i64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_promote_f32(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f32_demote_f64(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F32(Float::from_double(a)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F32(Float::from_int(a)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(Float::from_double(a.to_double())))
  rt.pc += 1
  OK
}

///|
extern "C" fn f32_from_i64(a : Int64) -> Float = "f32_from_i64"

///|
extern "C" fn f32_from_u64(a : UInt64) -> Float = "f32_from_u64"

///|
fn op_f32_convert_i64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F32(f32_from_i64(a)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F32(f32_from_u64(a)))
  rt.pc += 1
  OK
}

// Truncation operations (with trapping on overflow/NaN)

///|
fn op_i64_trunc_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_int64().reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 18446744073709551616.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow // "invalid conversion to integer"
  }
  if a >= 2147483648.0 || a < -2147483648.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 4294967296.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_double().to_uint64().to_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 2147483648.0 || a <= -2147483649.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 4294967296.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_uint64().to_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_int64().reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 18446744073709551616.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_uint64()))
  rt.pc += 1
  OK
}

// =============================================================================
// Saturating Truncation Operations
// =============================================================================
// These operations convert floats to integers but instead of trapping on
// overflow/NaN, they "saturate" to the min/max value or return 0 for NaN.

///|
fn op_i32_trunc_sat_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  let result = if a.is_nan() {
    0U
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFU
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000U
  } else {
    a.to_int().reinterpret_as_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  let result = if a.is_nan() {
    0U
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFU
  } else if a <= -1.0 {
    // negative, saturate to 0
    0U
  } else {
    a.to_double().to_uint64().to_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0U
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFU
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000U
  } else {
    a.to_int().reinterpret_as_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0U
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFU
  } else if a <= -1.0 {
    // negative, saturate to 0
    0U
  } else {
    a.to_uint64().to_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 9223372036854775808.0 {
    // >= 2^63, saturate to max i64
    0x7FFFFFFFFFFFFFFFUL
  } else if a < -9223372036854775808.0 {
    // < -2^63, saturate to min i64
    0x8000000000000000UL
  } else {
    a.to_int64().reinterpret_as_uint64()
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 18446744073709551616.0 {
    // >= 2^64, saturate to max u64
    0xFFFFFFFFFFFFFFFFUL
  } else if a <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    a.to_uint64()
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0UL
  } else if a >= 9223372036854775808.0 {
    // >= 2^63, saturate to max i64
    0x7FFFFFFFFFFFFFFFUL
  } else if a < -9223372036854775808.0 {
    // < -2^63, saturate to min i64
    0x8000000000000000UL
  } else {
    a.to_int64().reinterpret_as_uint64()
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0UL
  } else if a >= 18446744073709551616.0 {
    // >= 2^64, saturate to max u64
    0xFFFFFFFFFFFFFFFFUL
  } else if a <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    a.to_uint64()
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

// Reinterpret operations

///|
fn op_i32_reinterpret_f32(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::I32(a.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i64_reinterpret_f64(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::I64(a.reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_f32_reinterpret_i32(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(a)))
  rt.pc += 1
  OK
}

///|
fn op_f64_reinterpret_i64(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.reinterpret_as_double()))
  rt.pc += 1
  OK
}

// Global operations

///|
fn op_global_get(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.globals[idx])
  rt.pc += 1
  OK
}

///|
fn op_global_set(rt : Runtime) -> RetCode {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.globals[idx] = value
  rt.pc += 1
  OK
}

// ============================================================================
// Compilation
// ============================================================================

///|
fn Runtime::compile_wasm_instr(
  self : Runtime,
  ctx : CompileCtx,
  instr : Instr,
) -> Unit raise RuntimeError {
  match instr {
    // Constants
    I32Const(value) => {
      self.emit(WasmInstr(op_i32_const))
      ctx.push_type(I32)
      self.emit(ImmediateI32(value))
    }
    // Arithmetic (binary: pop 2, push 1)
    I32Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_add))
    }
    I32Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_sub))
    }
    I32Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_mul))
    }
    I32DivS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_div_s))
    }
    I32DivU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_div_u))
    }
    I32RemS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rem_s))
    }
    I32RemU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rem_u))
    }
    // Bitwise (binary: pop 2, push 1)
    I32And => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_and))
    }
    I32Or => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_or))
    }
    I32Xor => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_xor))
    }
    I32Shl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shl))
    }
    I32ShrS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shr_s))
    }
    I32ShrU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shr_u))
    }
    I32Rotl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rotl))
    }
    I32Rotr => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rotr))
    }
    // Comparison (binary: pop 2, push 1 i32)
    I32Eq => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_eq))
    }
    I32Ne => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ne))
    }
    I32LtS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_lt_s))
    }
    I32LtU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_lt_u))
    }
    I32GtS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_gt_s))
    }
    I32GtU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_gt_u))
    }
    I32LeS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_le_s))
    }
    I32LeU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_le_u))
    }
    I32GeS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ge_s))
    }
    I32GeU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ge_u))
    }
    // Unary (pop 1, push 1)
    I32Eqz => self.emit(WasmInstr(op_i32_eqz)) // i32 -> i32
    I32Clz => self.emit(WasmInstr(op_i32_clz)) // i32 -> i32
    I32Ctz => self.emit(WasmInstr(op_i32_ctz)) // i32 -> i32
    I32Popcnt => self.emit(WasmInstr(op_i32_popcnt)) // i32 -> i32
    I32Extend8S => self.emit(WasmInstr(op_i32_extend8_s)) // i32 -> i32
    I32Extend16S => self.emit(WasmInstr(op_i32_extend16_s)) // i32 -> i32
    I32WrapI64 => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_wrap_i64))
    } // i64 -> i32
    // i64 Constants
    I64Const(value) => {
      self.emit(WasmInstr(op_i64_const))
      // Split i64 into two i32 immediates
      self.emit(ImmediateI32((value & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((value >> 32).to_uint()))
      ctx.push_type(I64)
    }
    // f32/f64 Constants
    F32Const(value) => {
      self.emit(WasmInstr(op_f32_const))
      self.emit(ImmediateI32(value.reinterpret_as_uint()))
      ctx.push_type(F32)
    }
    F64Const(value) => {
      self.emit(WasmInstr(op_f64_const))
      let bits = value.reinterpret_as_uint64()
      self.emit(ImmediateI32((bits & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((bits >> 32).to_uint()))
      ctx.push_type(F64)
    }
    // i64 Arithmetic (binary: pop 2, push 1)
    I64Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_add))
    }
    I64Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_sub))
    }
    I64Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_mul))
    }
    I64DivS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_div_s))
    }
    I64DivU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_div_u))
    }
    I64RemS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rem_s))
    }
    I64RemU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rem_u))
    }
    // i64 Bitwise (binary: pop 2, push 1)
    I64And => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_and))
    }
    I64Or => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_or))
    }
    I64Xor => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_xor))
    }
    I64Shl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shl))
    }
    I64ShrS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shr_s))
    }
    I64ShrU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shr_u))
    }
    I64Rotl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rotl))
    }
    I64Rotr => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rotr))
    }
    // i64 Comparison (pop 2 i64, push 1 i32)
    I64Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_eq))
    }
    I64Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_ne))
    }
    I64LtS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_lt_s))
    }
    I64LtU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_lt_u))
    }
    I64GtS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_gt_s))
    }
    I64GtU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_gt_u))
    }
    I64LeS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_le_s))
    }
    I64LeU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_le_u))
    }
    I64GeS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_ge_s))
    }
    I64GeU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_ge_u))
    }
    // i64 Unary
    I64Eqz => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i64_eqz))
    } // i64 -> i32
    I64Clz => self.emit(WasmInstr(op_i64_clz)) // i64 -> i64
    I64Ctz => self.emit(WasmInstr(op_i64_ctz)) // i64 -> i64
    I64Popcnt => self.emit(WasmInstr(op_i64_popcnt)) // i64 -> i64
    I64Extend8S => self.emit(WasmInstr(op_i64_extend8_s)) // i64 -> i64
    I64Extend16S => self.emit(WasmInstr(op_i64_extend16_s)) // i64 -> i64
    I64Extend32S => self.emit(WasmInstr(op_i64_extend32_s)) // i64 -> i64
    I64ExtendI32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_extend_i32_s))
    } // i32 -> i64
    I64ExtendI32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_extend_i32_u))
    } // i32 -> i64
    // Float comparisons (pop 2, push i32)
    F32Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_eq))
    }
    F32Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_ne))
    }
    F32Lt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_lt))
    }
    F32Gt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_gt))
    }
    F32Le => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_le))
    }
    F32Ge => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f32_ge))
    }
    F64Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_eq))
    }
    F64Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_ne))
    }
    F64Lt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_lt))
    }
    F64Gt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_gt))
    }
    F64Le => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_le))
    }
    F64Ge => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit(WasmInstr(op_f64_ge))
    }
    // Float unary (same type in/out)
    F32Neg => self.emit(WasmInstr(op_f32_neg))
    F32Abs => self.emit(WasmInstr(op_f32_abs))
    F32Sqrt => self.emit(WasmInstr(op_f32_sqrt))
    F32Ceil => self.emit(WasmInstr(op_f32_ceil))
    F32Floor => self.emit(WasmInstr(op_f32_floor))
    F32Trunc => self.emit(WasmInstr(op_f32_trunc))
    F32Nearest => self.emit(WasmInstr(op_f32_nearest))
    F64Neg => self.emit(WasmInstr(op_f64_neg))
    F64Abs => self.emit(WasmInstr(op_f64_abs))
    F64Sqrt => self.emit(WasmInstr(op_f64_sqrt))
    F64Ceil => self.emit(WasmInstr(op_f64_ceil))
    F64Floor => self.emit(WasmInstr(op_f64_floor))
    F64Trunc => self.emit(WasmInstr(op_f64_trunc))
    F64Nearest => self.emit(WasmInstr(op_f64_nearest))
    // Float binary (pop 2, push 1)
    F32Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_add))
    }
    F32Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_sub))
    }
    F32Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_mul))
    }
    F32Div => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_div))
    }
    F32Min => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_min))
    }
    F32Max => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_max))
    }
    F32Copysign => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_copysign))
    }
    F64Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_add))
    }
    F64Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_sub))
    }
    F64Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_mul))
    }
    F64Div => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_div))
    }
    F64Min => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_min))
    }
    F64Max => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_max))
    }
    F64Copysign => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_copysign))
    }
    // Float conversions
    F64ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_convert_i64_u))
    }
    F64ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_convert_i64_s))
    }
    F64ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_convert_i32_u))
    }
    F64ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_convert_i32_s))
    }
    F64PromoteF32 => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_promote_f32))
    }
    F32DemoteF64 => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_demote_f64))
    }
    F32ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_convert_i32_s))
    }
    F32ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_convert_i32_u))
    }
    F32ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_convert_i64_s))
    }
    F32ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_convert_i64_u))
    }
    // Truncations
    I64TruncF64S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_f64_s))
    }
    I64TruncF64U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_f64_u))
    }
    I32TruncF32S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_f32_s))
    }
    I32TruncF32U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_f32_u))
    }
    I32TruncF64S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_f64_s))
    }
    I32TruncF64U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_f64_u))
    }
    I64TruncF32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_f32_s))
    }
    I64TruncF32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_f32_u))
    }
    // Saturating truncations
    I32TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f32_s))
    }
    I32TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f32_u))
    }
    I32TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f64_s))
    }
    I32TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f64_u))
    }
    I64TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f32_s))
    }
    I64TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f32_u))
    }
    I64TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f64_s))
    }
    I64TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f64_u))
    }
    // Reinterpret (same size, different type)
    I32ReinterpretF32 => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_i32_reinterpret_f32))
    }
    I64ReinterpretF64 => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_reinterpret_f64))
    }
    F32ReinterpretI32 => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_reinterpret_i32))
    }
    F64ReinterpretI64 => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_reinterpret_i64))
    }
    // Locals - we don't track local types here, just use a placeholder
    LocalGet(_idx) => {
      self.emit(WasmInstr(op_local_get))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
      // We need to push the local's type, but we don't have access to it here
      // For simplicity, push I32 as placeholder (the exact type doesn't matter for branch arity)
      ctx.push_type(I32)
    }
    LocalSet(_idx) => {
      ctx.pop_type()
      self.emit(WasmInstr(op_local_set))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    LocalTee(_idx) => {
      // Tee keeps the value on stack
      self.emit(WasmInstr(op_local_tee))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    // Stack
    Drop => {
      ctx.pop_type()
      self.emit(WasmInstr(op_drop))
    }
    Select => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_select))
    } // pop 3, push 1 => net -2
    SelectTyped(_types) => {
      // Runtime behavior is identical to untyped select
      ctx.pop_types(2)
      self.emit(WasmInstr(op_select))
    } // pop 3, push 1 => net -2
    Nop => self.emit(WasmInstr(op_nop))
    Unreachable => self.emit(WasmInstr(op_unreachable))
    // Control flow
    Block(block_type, instrs) => {
      let (params, results) = get_compile_block_type(self.module_, block_type)
      // Push control frame - target_pc is 0 (placeholder), will be patched at block end
      ctx.push_control(BlockKind, params, results, 0)
      // Compile block body
      for instr in instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      // Now we know the end PC - it's the current position
      let end_pc = self.ops.length()
      // Pop control frame and patch all pending branches
      let block = ctx.pop_control()
      for slot in block.pending_br_patches {
        self.ops[slot] = ImmediateIdx(end_pc)
      }
      // Reset type stack
      ctx.truncate_stack(block.stack_height_at_entry)
      ctx.push_types(block.results)
    }
    Loop(block_type, instrs) => {
      let (params, results) = get_compile_block_type(self.module_, block_type)
      // For loops, target_pc is the start (where br jumps back to)
      let loop_start = self.ops.length()
      ctx.push_control(LoopKind, params, results, loop_start)
      // Compile loop body
      for instr in instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      // Pop control frame (no patches needed for loops - target was known at start)
      let block = ctx.pop_control()
      ctx.truncate_stack(block.stack_height_at_entry)
      ctx.push_types(block.results)
    }
    Br(label) => {
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit(WasmInstr(op_br))
      // Emit target PC slot - for loops it's known, for blocks we need to patch
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        // Loop target is known
        self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
      } else {
        // Block/if target - emit placeholder and register for patching
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit(ImmediateIdx(arity))
      self.emit(ImmediateIdx(drop_count))
    }
    BrIf(label) => {
      ctx.pop_type() // Pop condition
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit(WasmInstr(op_br_if))
      // Emit target PC slot
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
      } else {
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit(ImmediateIdx(arity))
      self.emit(ImmediateIdx(drop_count))
    }
    BrTable(labels, default_label) => {
      ctx.pop_type() // Pop index
      // Use default label for arity calculation (all must have same arity per validation)
      let default_int = default_label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(default_int)
      self.emit(WasmInstr(op_br_table))
      self.emit(ImmediateIdx(labels.length()))
      self.emit(ImmediateIdx(arity))
      // For each label, emit target_pc + drop_count
      for label in labels {
        let label_int = label.reinterpret_as_int()
        let drop_count = ctx.calc_drop_count(label_int, arity)
        let target_pc_slot = self.ops.length()
        if ctx.is_loop_target(label_int) {
          self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
        } else {
          self.emit(ImmediateIdx(0))
          ctx.add_br_patch(label_int, target_pc_slot)
        }
        self.emit(ImmediateIdx(drop_count))
      }
      // Default label
      let default_drop = ctx.calc_drop_count(default_int, arity)
      let default_pc_slot = self.ops.length()
      if ctx.is_loop_target(default_int) {
        self.emit(ImmediateIdx(ctx.get_target_pc(default_int)))
      } else {
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(default_int, default_pc_slot)
      }
      self.emit(ImmediateIdx(default_drop))
    }
    BrOnNull(label) => {
      // br_on_null: branch if ref is null, leaving ref on stack if not null
      ctx.pop_type() // Pop the reference type
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit(WasmInstr(op_br_on_null))
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
      } else {
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit(ImmediateIdx(arity))
      self.emit(ImmediateIdx(drop_count))
      // In fallthrough case, ref is pushed back
      ctx.push_type(FuncRef)
    }
    BrOnNonNull(label) => {
      // br_on_non_null: branch if ref is not null
      ctx.pop_type() // Pop the reference type
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit(WasmInstr(op_br_on_non_null))
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
      } else {
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit(ImmediateIdx(arity))
      self.emit(ImmediateIdx(drop_count))
      // In fallthrough case (null), ref is discarded
    }
    If(block_type, then_instrs, else_instrs) => {
      ctx.pop_type() // Pop condition
      let (params, results) = get_compile_block_type(self.module_, block_type)
      // Push control frame - target_pc is 0 (placeholder), will be patched at if end
      ctx.push_control(IfKind, params, results, 0)
      let entry_height = ctx.control_stack[ctx.control_stack.length() - 1].stack_height_at_entry
      // Emit if instruction with placeholder for else branch
      self.emit(WasmInstr(op_if))
      let else_pc_slot = self.ops.length()
      self.emit(ImmediateIdx(0))
      // Compile then branch
      for instr in then_instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      // Emit jump over else branch (unconditional)
      self.emit(WasmInstr(op_br))
      let end_jump_slot = self.ops.length()
      self.emit(ImmediateIdx(0)) // Will be patched to end
      self.emit(ImmediateIdx(results.length())) // arity = results
      self.emit(ImmediateIdx(0)) // drop_count = 0 (then branch should have correct stack)
      // Patch else_pc to point here
      let else_start = self.ops.length()
      self.ops[else_pc_slot] = ImmediateIdx(else_start)
      // Reset stack for else branch
      ctx.truncate_stack(entry_height)
      ctx.push_types(params)
      // Compile else branch
      for instr in else_instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      // Now we know the end PC
      let end_pc = self.ops.length()
      // Patch the jump at end of then branch
      self.ops[end_jump_slot] = ImmediateIdx(end_pc)
      // Pop control frame and patch all pending branches from inside the if
      let block = ctx.pop_control()
      for slot in block.pending_br_patches {
        self.ops[slot] = ImmediateIdx(end_pc)
      }
      ctx.truncate_stack(block.stack_height_at_entry)
      ctx.push_types(block.results)
    }
    Call(func_idx) => {
      // Look up function signature to properly track types
      let func_idx_int = func_idx.reinterpret_as_int()
      let num_imported = count_imported_funcs(self.module_)
      let type_idx = get_func_type_idx(self.module_, func_idx_int, num_imported)

      // Get the function type and update type stack
      if type_idx >= 0 {
        let func_type = self.module_.types[type_idx]
        // Pop params from type stack
        ctx.pop_types(func_type.params.length())
        // Push results to type stack
        for result_type in func_type.results {
          ctx.push_type(result_type)
        }
      }
      self.emit(WasmInstr(op_call))
      self.emit(ImmediateIdx(func_idx_int))
    }
    Return => self.emit(WasmInstr(op_return))
    // Memory instructions (load: pop addr, push value; store: pop addr+value)
    I32Load(_align, offset) => {
      // pop i32 addr, push i32 value
      self.emit(WasmInstr(op_i32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store(_align, offset) => {
      ctx.pop_types(2) // pop addr and value
      self.emit(WasmInstr(op_i32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load8S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load8U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load16S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load16U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store8(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i32_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store16(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i32_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load8S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load8U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load16S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load16U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load32S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load32_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load32U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit(WasmInstr(op_i64_load32_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store8(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store16(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store32(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store32))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F32Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit(WasmInstr(op_f32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F32Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_f32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F64Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit(WasmInstr(op_f64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F64Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_f64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    // Global instructions
    GlobalGet(_idx) => {
      ctx.push_type(I32) // Placeholder type
      self.emit(WasmInstr(op_global_get))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    GlobalSet(_idx) => {
      ctx.pop_type()
      self.emit(WasmInstr(op_global_set))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    // Memory size and grow
    MemorySize(_) => {
      ctx.push_type(I32)
      self.emit(WasmInstr(op_memory_size))
    }
    MemoryGrow(_) => self.emit(WasmInstr(op_memory_grow)) // i32 -> i32

    // Bulk memory instructions
    MemoryCopy => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_memory_copy))
    }
    MemoryFill => {
      ctx.pop_types(3) // pop dest, val, n
      self.emit(WasmInstr(op_memory_fill))
    }
    MemoryInit(data_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_memory_init))
      self.emit(ImmediateIdx(data_idx.reinterpret_as_int()))
    }
    DataDrop(data_idx) => {
      self.emit(WasmInstr(op_data_drop))
      self.emit(ImmediateIdx(data_idx.reinterpret_as_int()))
    }

    // Table bulk operations
    TableInit(table_idx, elem_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_table_init))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
      self.emit(ImmediateIdx(elem_idx.reinterpret_as_int()))
    }
    TableCopy(dst_table_idx, src_table_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_table_copy))
      self.emit(ImmediateIdx(dst_table_idx.reinterpret_as_int()))
      self.emit(ImmediateIdx(src_table_idx.reinterpret_as_int()))
    }
    ElemDrop(elem_idx) => {
      self.emit(WasmInstr(op_elem_drop))
      self.emit(ImmediateIdx(elem_idx.reinterpret_as_int()))
    }

    // Table instructions
    TableSize(table_idx) => {
      ctx.push_type(I32)
      self.emit(WasmInstr(op_table_size))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableGet(table_idx) => {
      // pop i32 index, push ref
      self.emit(WasmInstr(op_table_get))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableSet(table_idx) => {
      ctx.pop_types(2) // pop index and ref
      self.emit(WasmInstr(op_table_set))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableGrow(table_idx) => {
      ctx.pop_type() // pop count, keep delta -> result
      self.emit(WasmInstr(op_table_grow))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    // Reference instructions
    RefNull(_ref_type) => {
      ctx.push_type(FuncRef) // Use FuncRef as placeholder
      self.emit(WasmInstr(op_ref_null))
      // Encode the ref type as an immediate
      let type_idx = match _ref_type {
        Func => 0
        Extern => 1
        Any => 2
        Eq => 3
        I31 => 4
        Struct => 5
        Array => 6
        Exn => 7
        None => 8
        NoFunc => 9
        NoExtern => 10
        NoExn => 11
        TypeIndex(idx) => idx
      }
      self.emit(ImmediateIdx(type_idx))
    }
    RefFunc(func_idx) => {
      ctx.push_type(FuncRef)
      self.emit(WasmInstr(op_ref_func))
      self.emit(ImmediateIdx(func_idx.reinterpret_as_int()))
    }
    RefIsNull => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit(WasmInstr(op_ref_is_null))
    }
    // Indirect call
    CallIndirect(type_idx, table_idx) => {
      // Pop table index (i32)
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = self.module_.types[type_idx_int]
      // Pop params from type stack
      ctx.pop_types(func_type.params.length())
      // Push results to type stack
      for result_type in func_type.results {
        ctx.push_type(result_type)
      }
      self.emit(WasmInstr(op_call_indirect))
      self.emit(ImmediateIdx(type_idx_int))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    // Tail calls
    ReturnCall(func_idx) => {
      // Look up function signature to properly track types (same as Call)
      let func_idx_int = func_idx.reinterpret_as_int()
      let num_imported = count_imported_funcs(self.module_)
      let type_idx = get_func_type_idx(self.module_, func_idx_int, num_imported)

      // Get the function type and update type stack
      // For tail calls, only pop params (results go to caller, not us)
      if type_idx >= 0 {
        let func_type = self.module_.types[type_idx]
        ctx.pop_types(func_type.params.length())
      }
      self.emit(WasmInstr(op_return_call))
      self.emit(ImmediateIdx(func_idx_int))
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      // Pop table index (i32)
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = self.module_.types[type_idx_int]
      // Pop params from type stack (no results - tail call)
      ctx.pop_types(func_type.params.length())
      self.emit(WasmInstr(op_return_call_indirect))
      self.emit(ImmediateIdx(type_idx_int))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    // Typed function references
    CallRef(type_idx) => {
      // Pop the function reference
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = self.module_.types[type_idx_int]
      // Pop params from type stack
      ctx.pop_types(func_type.params.length())
      // Push results to type stack
      for result_type in func_type.results {
        ctx.push_type(result_type)
      }
      self.emit(WasmInstr(op_call_ref))
      self.emit(ImmediateIdx(type_idx_int))
    }
    ReturnCallRef(type_idx) => {
      // Pop the function reference
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = self.module_.types[type_idx_int]
      // Pop params from type stack (no results - tail call)
      ctx.pop_types(func_type.params.length())
      self.emit(WasmInstr(op_return_call_ref))
      self.emit(ImmediateIdx(type_idx_int))
    }
  }
}

///|
fn Runtime::compile_func(
  self : Runtime,
  func_idx : Int, // Index into module_.funcs (excludes imports)
  code : Code,
) -> Unit raise RuntimeError {
  // Get function type
  let type_idx = self.module_.funcs[func_idx].reinterpret_as_int()
  let func_type = self.module_.types[type_idx]

  // Create compile-time context
  let ctx = CompileCtx::new()

  // Push function parameters onto type stack (they become locals)
  // Parameters are already in locals, but we need them on the type stack
  // for the implicit function block
  for param in func_type.params {
    ctx.push_type(param)
  }

  // Push implicit function-level control frame
  // The function body acts like a block with params=[] and results=func_type.results
  // But parameters are already popped into locals, so we model it as empty params
  // target_pc is 0 placeholder - will be patched at end
  ctx.push_control(BlockKind, [], func_type.results, 0)
  let start_pc = self.ops.length()
  // Compile function body
  for instr in code.body.instrs {
    self.compile_wasm_instr(ctx, instr)
  }
  self.emit(WasmInstr(op_end))

  // Now we know the end PC - patch all pending branches from function body
  let end_pc = self.ops.length() - 1 // Points to op_end
  let func_block = ctx.pop_control()
  for slot in func_block.pending_br_patches {
    self.ops[slot] = ImmediateIdx(end_pc)
  }
  code.compiled = Some(start_pc)
}

///|
pub fn Runtime::compile(self : Runtime) -> Unit raise RuntimeError {
  for i, code in self.module_.codes {
    self.compile_func(i, code)
  }

  // Execute the start function if present
  match self.module_.start {
    Some(start_idx) => {
      // Call the start function
      // Start function must have type [] -> []
      let func_idx = start_idx.reinterpret_as_int()
      let num_imported_funcs = count_imported_funcs(self.module_)

      // Only execute if it's a local function (not imported)
      // Imported start functions would require host environment support
      if func_idx >= num_imported_funcs {
        let local_idx = func_idx - num_imported_funcs
        let code = self.module_.codes[local_idx]
        guard code.compiled is Some(start_pc) else {
          raise RuntimeError::FunctionNotCompiled("Start function not compiled")
        }

        // Set up execution context for start function
        self.locals = []
        for local_type in code.locals {
          match local_type {
            ValType::I32 => self.locals.push(Value::I32(0U))
            ValType::I64 => self.locals.push(Value::I64(0UL))
            ValType::F32 => self.locals.push(Value::F32(0.0))
            ValType::F64 => self.locals.push(Value::F64(0.0))
            ValType::FuncRef => self.locals.push(Value::Ref(None))
            ValType::ExternRef => self.locals.push(Value::Ref(None))
            _ => self.locals.push(Value::I32(0U))
          }
        }
        self.stack.clear()
        self.call_stack.clear()
        self.pc = start_pc

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        self.execute() catch {
          _ => () // Ignore runtime errors in start function
        }

        // Clear state after start function execution
        self.stack.clear()
      }
    }
    None => ()
  }
}

///|
fn Runtime::execute(self : Runtime) -> Unit raise RuntimeError {
  self.running = true
  while self.running {
    guard self.ops.unsafe_get(self.pc) is WasmInstr(f) else {
      raise RuntimeError::UnimplementedInstruction(
        "Expected instruction at PC \{self.pc}",
      )
    }
    let ret = f(self)
    if ret != OK {
      raise ret.to_error(self.error_detail)
    }
  }
}

///|
pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  let mut func_idx : Int? = None
  for exp in self.module_.exports {
    if exp.name == func_name {
      match exp.desc {
        Func(idx) => {
          func_idx = Some(idx.reinterpret_as_int())
          break
        }
        _ => continue
      }
    }
  }
  guard func_idx is Some(idx) else {
    raise RuntimeError::FunctionNotFound("Function not found: \{func_name}")
  }
  let num_imported_funcs = count_imported_funcs(self.module_)

  // Check if it's an imported function - call it directly via import resolver
  if idx < num_imported_funcs {
    let imported_func = self.imported_funcs[idx]
    return (imported_func.func)(args)
  }

  // Adjust to local function index
  let local_idx = idx - num_imported_funcs
  let type_idx = self.module_.funcs[local_idx].reinterpret_as_int()
  let func_type = self.module_.types[type_idx]
  let code = self.module_.codes[local_idx]
  guard code.compiled is Some(start_pc) else {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: \{func_name}",
    )
  }
  let init_result = self.initialize_locals(args, code)
  if init_result != OK {
    raise init_result.to_error(self.error_detail)
  }
  self.stack.clear()
  self.call_stack.clear()
  self.pc = start_pc
  self.execute()
  let results : Array[Value] = []
  for _i = 0; _i < func_type.results.length(); _i = _i + 1 {
    if self.stack.length() > 0 {
      results.push(self.stack.unsafe_pop())
    }
  }
  results.rev_in_place()
  results
}
