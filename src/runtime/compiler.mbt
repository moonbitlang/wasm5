// ============================================================================
// Compiler - compile-time context for building instruction arrays
// ============================================================================

///|
/// Compiler holds the instruction array during compilation.
/// After compilation, the ops array is converted to FixedArray for runtime.
pub struct Compiler {
  module_ : @core.Module
  ops : Array[UInt64]
}

///|
/// Create a new compiler for a module
pub fn Compiler::new(module_ : @core.Module) -> Compiler {
  { module_, ops: [] }
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
}
