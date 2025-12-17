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
pub enum MInstr {
  WasmInstr(FuncRef[(Runtime) -> RetCode])
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Call frame for function calls
pub struct CallFrame {
  return_pc : Int
  locals : Array[Value]
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
pub struct CompileCtx {
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
fn CompileCtx::push_types(
  self : CompileCtx,
  types : Array[ValType],
) -> Unit {
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
fn CompileCtx::get_target_stack_height(
  self : CompileCtx,
  label : Int,
) -> Int {
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
fn CompileCtx::add_br_patch(
  self : CompileCtx,
  label : Int,
  slot : Int,
) -> Unit {
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
