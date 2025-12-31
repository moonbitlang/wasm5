// ============================================================================
// Compiler - compile-time context for building instruction arrays
// ============================================================================

///|
/// Pending call patch for forward references
struct PendingCallPatch {
  local_func_idx : Int // Which function is being called
  slot : Int // Which slot in ops needs the callee_pc
}

///|
/// Compiler holds the instruction array during compilation.
/// After compilation, the ops array is converted to FixedArray for runtime.
pub struct Compiler {
  module_ : @core.Module
  ops : Array[UInt64]
  pending_call_patches : Array[PendingCallPatch] // Forward call references to patch
}

///|
/// Create a new compiler for a module
pub fn Compiler::new(module_ : @core.Module) -> Compiler {
  { module_, ops: [], pending_call_patches: [] }
}

///|
/// Emit a function pointer as UInt64
fn Compiler::emit_fn(self : Compiler, f : (Runtime) -> Runtime) -> Unit {
  self.ops.push(unsafe_function_to_uint64(f))
}

///|
/// Emit an immediate i32 value as UInt64
fn Compiler::emit_i32(self : Compiler, value : UInt) -> Unit {
  self.ops.push(value.to_uint64())
}

///|
/// Emit an immediate index value as UInt64
fn Compiler::emit_idx(self : Compiler, value : Int) -> Unit {
  self.ops.push(value.to_int64().reinterpret_as_uint64())
}

///|
/// Finish compilation and return the FixedArray of instructions
pub fn Compiler::finish(self : Compiler) -> FixedArray[UInt64] {
  FixedArray::from_array(self.ops)
}

///|
/// Get the initialization category for a local type.
/// Returns: 0 = zero (i32/i64/f32/f64), 1 = null ref, -1 = unsupported
fn local_init_category(t : @core.ValType) -> Int {
  match t {
    I32 | I64 | F32 | F64 => 0 // zero
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
    | Ref(_, _) => 1 // null ref
    _ => -1 // unsupported (V128, etc.)
  }
}

///|
/// Emit batch initialization ops for declared locals.
/// Groups consecutive locals by type (zero vs null ref) for efficiency.
/// Unsupported types (V128) cause a trap instruction to be emitted.
fn Compiler::emit_locals_init(
  self : Compiler,
  locals : Array[@core.ValType],
) -> Unit {
  if locals.length() == 0 {
    return
  }
  let mut i = 0
  while i < locals.length() {
    let category = local_init_category(locals[i])
    if category < 0 {
      // Unsupported local type - emit trap
      self.emit_fn(op_local_init_unsupported)
      return
    }
    let mut count = 1
    // Count consecutive locals of same category
    while i + count < locals.length() &&
          local_init_category(locals[i + count]) == category {
      count += 1
    }
    // Emit batch init op
    if category == 1 {
      self.emit_fn(op_init_null_refs)
    } else {
      self.emit_fn(op_init_zeros)
    }
    self.emit_idx(count)
    i += count
  }
}

///|
fn Compiler::compile_func(
  self : Compiler,
  func_idx : Int, // Index into module_.funcs (excludes imports)
  code : @core.Code,
) -> Unit raise RuntimeError {
  // Get function type
  let type_idx = self.module_.funcs[func_idx].reinterpret_as_int()
  let func_type = require_func_type(self.module_, type_idx, "compile_func")

  // Create compile-time context with function result count
  let ctx = CompileCtx::new(func_type.results.length())

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

  // Emit batch initialization for declared locals (params are already on stack)
  self.emit_locals_init(code.locals)

  // Compile function body
  for instr in code.body.instrs {
    self.compile_wasm_instr(ctx, instr)
  }
  // Emit implicit return at function end
  self.emit_fn(op_return)
  let end_pc = self.ops.length() - 1 // Points to op_return (before immediate)
  self.emit_idx(ctx.func_result_count)
  let func_block = ctx.pop_control()
  for slot in func_block.pending_br_patches {
    self.ops[slot] = end_pc.to_int64().reinterpret_as_uint64()
  }
  code.compiled = Some(start_pc)
  // Store max stack height: num_locals + max_operand_depth
  let num_locals = func_type.params.length() + code.locals.length()
  code.max_stack_height = num_locals + ctx.max_stack_depth
}

///|
pub fn Compiler::compile(self : Compiler) -> Unit raise RuntimeError {
  for i, code in self.module_.codes {
    self.compile_func(i, code)
  }
  // Patch forward call references now that all functions are compiled
  for patch in self.pending_call_patches {
    let code = self.module_.codes[patch.local_func_idx]
    guard code.compiled is Some(callee_pc) else {
      raise RuntimeError::FunctionNotCompiled(
        "Forward call to uncompiled function: \{patch.local_func_idx}",
      )
    }
    self.ops[patch.slot] = callee_pc.to_int64().reinterpret_as_uint64()
  }
}
