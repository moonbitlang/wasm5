///|
/// Runtime execution status
pub enum RuntimeStatus {
  Running
  Terminated
  Trap
} derive(Eq, Show)

///|
/// Intermediate instruction for threaded interpreter
pub enum MInstr {
  WasmInstr((Runtime) -> Unit)
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Call frame for function calls
pub struct CallFrame {
  return_pc : Int
  caller_sp : Int
  caller_num_locals : Int
}

///|
/// Block kind for compile-time control flow tracking
pub enum CompileBlockKind {
  BlockKind // br jumps to end, uses results
  LoopKind // br jumps to start, uses params
  IfKind // br jumps to end, uses results
} derive(Eq)

///|
/// Compile-time control frame for tracking block types and stack heights
pub struct CompileBlock {
  kind : CompileBlockKind
  params : Array[@core.ValType]
  results : Array[@core.ValType]
  stack_height_at_entry : Int // type_stack.length() when block started (after params popped)
  // For loops: the PC to jump to (known at block start)
  // For blocks/if: 0 (unused, patches go to pending_br_patches)
  target_pc : Int
  // Slots that need to be patched with the end PC (for blocks/if)
  pending_br_patches : Array[Int]
}

///|
/// Compile-time context for tracking types during compilation
pub struct CompileCtx {
  type_stack : Array[@core.ValType]
  control_stack : Array[CompileBlock]
  func_result_count : Int // Number of results the function returns
  mut max_stack_depth : Int // Maximum operand stack depth seen
}

///|
fn CompileCtx::new(func_result_count : Int) -> CompileCtx {
  { type_stack: [], control_stack: [], func_result_count, max_stack_depth: 0 }
}

///|
fn CompileCtx::push_type(self : CompileCtx, t : @core.ValType) -> Unit {
  self.type_stack.push(t)
  // Track maximum stack depth
  if self.type_stack.length() > self.max_stack_depth {
    self.max_stack_depth = self.type_stack.length()
  }
}

///|
fn CompileCtx::pop_type(self : CompileCtx) -> Unit {
  if self.type_stack.length() > 0 {
    let _ = self.type_stack.unsafe_pop()

  }
}

///|
fn CompileCtx::pop_type_value(self : CompileCtx) -> @core.ValType? {
  if self.type_stack.length() > 0 {
    Some(self.type_stack.unsafe_pop())
  } else {
    None
  }
}

///|
fn CompileCtx::pop_types(self : CompileCtx, n : Int) -> Unit {
  for _ in 0..<n {
    self.pop_type()
  }
}

///|
fn CompileCtx::push_types(
  self : CompileCtx,
  types : Array[@core.ValType],
) -> Unit {
  for t in types {
    self.push_type(t)
  }
}

///|
fn CompileCtx::push_control(
  self : CompileCtx,
  kind : CompileBlockKind,
  params : Array[@core.ValType],
  results : Array[@core.ValType],
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
  module_ : @core.Module,
  block_type : @core.BlockType,
) -> (Array[@core.ValType], Array[@core.ValType]) raise RuntimeError {
  match block_type {
    Empty => ([], [])
    Value(t) => ([], [t])
    TypeIndex(idx) => {
      let func_type = require_func_type(module_, idx, "block type")
      (func_type.params, func_type.results)
    }
  }
}
