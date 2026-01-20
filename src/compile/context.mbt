///|
/// Control frame kind for tracking nested control structures
priv enum ControlKind {
  Block
  Loop
  If
} derive(Eq)

///|
/// Control frame for tracking nested blocks during compilation
priv struct ControlFrame {
  kind : ControlKind
  target_pc : Int // For loops: start PC. For blocks/ifs: patched at end
  result_slots : Array[Int] // Pre-allocated result slot positions
  sp_at_entry : Int // Stack pointer (slot) at block entry
  slot_stack_len_at_entry : Int // slot_stack.length() at block entry
  pending_patches : Array[Int] // Code positions that need patching
}

///|
/// Deferred resolution block (emitted at end of function for br_if/br_table)
priv struct DeferredBlock {
  patch_pos : Int // Position in code to patch with block address
  src_slots : Array[Int] // Source slot positions (captured at branch time)
  dst_slots : Array[Int] // Destination (pre-allocated) result slots
  target_sp : Int // Stack pointer after branch
  target_label : Int // Absolute control stack index at creation time
  is_loop : Bool // Whether target is a loop (known PC) or block (needs patch)
  loop_pc : Int // Loop PC if is_loop is true
  mut end_pc : Int // Actual end PC (filled in by pop_control for non-loops)
  mut resolved : Bool // Whether end_pc has been set (prevents overwriting)
}

///|
/// Pending call patch (for forward calls to functions not yet compiled)
priv struct CallPatch {
  patch_pos : Int // Position in code to patch with callee entry
  func_idx : Int // Local function index (0-based)
}

///|
/// Module info needed during compilation
priv struct ModuleInfo {
  mod_ : @core.Module
  func_entries : Array[Int] // Entry points for compiled functions
  func_num_params : Array[Int] // Number of params per function
  func_num_results : Array[Int] // Number of results per function
  num_imported_funcs : Int
}

///|
/// Compilation context with slot-based tracking (wasm3 style).
/// Produces universal IR as Array[Int64] with opcode tags.
priv struct CompileCtx {
  code : Array[Int64] // Universal IR output
  control_stack : Array[ControlFrame]
  deferred_blocks : Array[DeferredBlock] // Resolution blocks to emit at end
  call_patches : Array[CallPatch] // Pending call patches
  slot_stack : Array[Int] // Maps logical stack index to slot number
  mut next_slot : Int // Next available slot for allocation
  mut num_results : Int // Number of results for current function
  mut is_unreachable : Bool // True after unconditional branch until block end
}

///|
fn CompileCtx::new() -> CompileCtx {
  {
    code: [],
    control_stack: [],
    deferred_blocks: [],
    call_patches: [],
    slot_stack: [],
    next_slot: 0,
    num_results: 0,
    is_unreachable: false,
  }
}

///|
/// Initialize context for a function with given number of locals and results
fn CompileCtx::init_function(
  self : CompileCtx,
  num_locals : Int,
  num_results : Int,
) -> Unit {
  self.slot_stack.clear()
  self.num_results = num_results
  self.next_slot = num_locals // Operand slots start after locals
  self.is_unreachable = false
}

///|
/// Current stack pointer (next slot after top of stack)
fn CompileCtx::current_sp(self : CompileCtx) -> Int {
  self.next_slot
}

///|
/// Push a value, allocating a new slot
fn CompileCtx::push_slot(self : CompileCtx) -> Int {
  let slot = self.next_slot
  self.slot_stack.push(slot)
  self.next_slot += 1
  slot
}

///|
/// Pop a value, returning its slot (slot can be reused)
fn CompileCtx::pop_slot(self : CompileCtx) -> Int {
  guard self.slot_stack.length() > 0 else { return 0 }
  let slot = self.slot_stack.pop().unwrap()
  // Reclaim slot for reuse if it was the last allocated
  if slot + 1 == self.next_slot {
    self.next_slot = slot
  }
  slot
}

///|
/// Get slot at stack depth (0 = top)
fn CompileCtx::slot_at(self : CompileCtx, depth : Int) -> Int {
  let idx = self.slot_stack.length() - 1 - depth
  guard idx >= 0 else { return 0 }
  self.slot_stack[idx]
}

///|
/// Push a control frame with pre-allocated result slots
fn CompileCtx::push_control(
  self : CompileCtx,
  kind : ControlKind,
  arity : Int,
  target_pc : Int,
) -> Unit {
  // Save slot_stack length before allocating result slots
  let slot_stack_len = self.slot_stack.length()
  // Pre-allocate result slots (wasm3 style)
  let result_slots : Array[Int] = []
  for _ in 0..<arity {
    result_slots.push(self.push_slot())
  }
  // Pop them back - they're reserved but not "on stack" yet
  for _ in 0..<arity {
    ignore(self.pop_slot())
  }
  self.control_stack.push({
    kind,
    target_pc,
    result_slots,
    sp_at_entry: self.current_sp(),
    slot_stack_len_at_entry: slot_stack_len,
    pending_patches: [],
  })
}

///|
/// Pop a control frame and patch pending branches
fn CompileCtx::pop_control(self : CompileCtx) -> Unit {
  guard self.control_stack.length() > 0 else { return }
  let abs_idx = self.control_stack.length() - 1 // Index of frame being popped
  let frame = self.control_stack.pop().unwrap()
  let end_pc = self.code.length()
  // Patch all pending forward branches to point here
  for patch_pos in frame.pending_patches {
    self.code[patch_pos] = end_pc.to_int64()
  }
  // Update end_pc for all unresolved deferred blocks targeting this frame
  for block in self.deferred_blocks {
    if not(block.is_loop) &&
      not(block.resolved) &&
      block.target_label == abs_idx {
      block.end_pc = end_pc
      block.resolved = true
    }
  }
}

///|
/// Get branch target info: (target_pc, result_slots, target_sp)
fn CompileCtx::get_branch_target(
  self : CompileCtx,
  label : Int,
) -> (Int, Array[Int], Int) {
  let idx = self.control_stack.length() - 1 - label
  guard idx >= 0 else { return (0, [], 0) }
  let frame = self.control_stack[idx]
  // For loops, branch back to start; for blocks, branch to end
  let target_sp = frame.sp_at_entry
  (frame.target_pc, frame.result_slots, target_sp)
}

///|
/// Register a patch location for a forward branch
fn CompileCtx::add_patch(
  self : CompileCtx,
  label : Int,
  patch_pos : Int,
) -> Unit {
  let idx = self.control_stack.length() - 1 - label
  guard idx >= 0 else { return }
  self.control_stack[idx].pending_patches.push(patch_pos)
}

///|
/// Check if branch target is a loop (backward branch)
fn CompileCtx::is_loop_target(self : CompileCtx, label : Int) -> Bool {
  let idx = self.control_stack.length() - 1 - label
  guard idx >= 0 else { return false }
  self.control_stack[idx].kind == Loop
}

///|
/// Emit an opcode tag
fn CompileCtx::emit_op(self : CompileCtx, tag : @core.OpTag) -> Unit {
  self.code.push(tag.to_int64())
}

///|
/// Emit an i32 immediate
fn CompileCtx::emit_i32(self : CompileCtx, value : UInt) -> Unit {
  self.code.push(value.to_int64())
}

///|
/// Emit an i64 immediate
fn CompileCtx::emit_i64(self : CompileCtx, value : UInt64) -> Unit {
  self.code.push(value.reinterpret_as_int64())
}

///|
/// Emit an index immediate
fn CompileCtx::emit_idx(self : CompileCtx, value : Int) -> Unit {
  self.code.push(value.to_int64())
}

///|
/// Emit a binary operation (pops 2, pushes 1 = net pop 1)
fn CompileCtx::emit_binary_op(self : CompileCtx, tag : @core.OpTag) -> Unit {
  self.emit_op(tag)
  ignore(self.pop_slot())
}

///|
/// Emit a unary operation (pops 1, pushes 1 = no net change)
fn CompileCtx::emit_unary_op(self : CompileCtx, tag : @core.OpTag) -> Unit {
  self.emit_op(tag)
}

///|
/// Emit a load operation (consumes address, produces value = no net change)
fn CompileCtx::emit_load(
  self : CompileCtx,
  tag : @core.OpTag,
  offset : UInt,
  mem_idx : UInt,
) -> Unit {
  self.emit_op(tag)
  self.emit_idx(offset.reinterpret_as_int())
  self.emit_idx(mem_idx.reinterpret_as_int())
}

///|
/// Emit a store operation (consumes address and value = net pop 2)
fn CompileCtx::emit_store(
  self : CompileCtx,
  tag : @core.OpTag,
  offset : UInt,
  mem_idx : UInt,
) -> Unit {
  self.emit_op(tag)
  self.emit_idx(offset.reinterpret_as_int())
  self.emit_idx(mem_idx.reinterpret_as_int())
  ignore(self.pop_slot()) // value
  ignore(self.pop_slot()) // address
}

///|
/// Emit stack resolution: copy current top values to pre-allocated result slots, set sp
fn CompileCtx::emit_resolution(
  self : CompileCtx,
  result_slots : Array[Int],
  target_sp : Int,
  is_loop : Bool,
) -> Unit {
  let arity = result_slots.length()
  // Copy each result from current slot to pre-allocated slot
  for i in 0..<arity {
    let src_slot = self.slot_at(arity - 1 - i)
    let dst_slot = result_slots[i]
    if src_slot != dst_slot {
      self.emit_op(@core.OpTag::CopySlot)
      self.emit_idx(src_slot)
      self.emit_idx(dst_slot)
    }
  }
  // Set sp to correct position
  self.emit_op(@core.OpTag::SetSp)
  if is_loop {
    self.emit_idx(target_sp) // For loops: params are BEFORE target_sp
  } else {
    self.emit_idx(target_sp + arity) // For blocks: results are AT target_sp
  }
}

///|
/// Capture current slot positions for results
fn CompileCtx::capture_result_slots(
  self : CompileCtx,
  arity : Int,
) -> Array[Int] {
  let slots : Array[Int] = []
  for i in 0..<arity {
    slots.push(self.slot_at(arity - 1 - i))
  }
  slots
}

///|
/// Add a deferred resolution block
fn CompileCtx::defer_resolution(
  self : CompileCtx,
  patch_pos : Int,
  src_slots : Array[Int],
  dst_slots : Array[Int],
  target_sp : Int,
  target_label : Int,
  is_loop : Bool,
  loop_pc : Int,
) -> Unit {
  // Convert relative label to absolute control stack index
  let abs_label_idx = self.control_stack.length() - 1 - target_label
  self.deferred_blocks.push({
    patch_pos,
    src_slots,
    dst_slots,
    target_sp,
    target_label: abs_label_idx,
    is_loop,
    loop_pc,
    end_pc: 0,
    resolved: false,
  })
}

///|
/// Emit all deferred resolution blocks (call at end of function)
fn CompileCtx::emit_deferred_blocks(self : CompileCtx) -> Unit {
  for block in self.deferred_blocks {
    // Patch the reference to point here
    let block_pc = self.code.length()
    self.code[block.patch_pos] = block_pc.to_int64()

    // Emit resolution code: copy from captured src slots to dst slots
    for i in 0..<block.src_slots.length() {
      let src_slot = block.src_slots[i]
      let dst_slot = block.dst_slots[i]
      if src_slot != dst_slot {
        self.emit_op(@core.OpTag::CopySlot)
        self.emit_idx(src_slot)
        self.emit_idx(dst_slot)
      }
    }
    // Set sp to correct position
    let arity = block.src_slots.length()
    self.emit_op(@core.OpTag::SetSp)
    if block.is_loop {
      self.emit_idx(block.target_sp)
    } else {
      self.emit_idx(block.target_sp + arity)
    }

    // Emit final jump
    if block.is_loop {
      self.emit_op(@core.OpTag::Br)
      self.emit_idx(block.loop_pc)
    } else if block.target_label == 0 {
      // Function-level branch: results already at fp[0..n-1], just exit
      self.emit_op(@core.OpTag::FuncExit)
    } else {
      // Block-level branch: jump to end of block
      self.emit_op(@core.OpTag::Br)
      self.emit_idx(block.end_pc)
    }
  }
  self.deferred_blocks.clear()
}

///|
/// Get block result arity from block type
fn get_block_arity(mod_ : @core.Module, bt : @core.BlockType) -> Int {
  match bt {
    Empty => 0
    Value(_) => 1
    TypeIndex(idx) =>
      match mod_.types[idx] {
        Func(ft) => ft.results.length()
        _ => 1
      }
  }
}

///|
/// Get param and result arity from block type
fn get_block_arities(mod_ : @core.Module, bt : @core.BlockType) -> (Int, Int) {
  match bt {
    Empty => (0, 0)
    Value(_) => (0, 1)
    TypeIndex(idx) =>
      match mod_.types[idx] {
        Func(ft) => (ft.params.length(), ft.results.length())
        _ => (0, 1)
      }
  }
}

///|
/// Count imported functions
fn count_imported_funcs(mod_ : @core.Module) -> Int {
  let mut count = 0
  for imp in mod_.imports {
    match imp.desc {
      Func(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Get function type by index
fn get_func_type(mod_ : @core.Module, type_idx : Int) -> @core.FuncType {
  match mod_.types[type_idx] {
    Func(ft) => ft
    _ => { params: [], results: [] }
  }
}

///|
/// Get the type index for an imported function by its import index
fn get_imported_func_type_idx(
  mod_ : @core.Module,
  import_func_idx : Int,
) -> Int {
  let mut func_import_count = 0
  for imp in mod_.imports {
    match imp.desc {
      Func(type_idx) => {
        if func_import_count == import_func_idx {
          return type_idx.reinterpret_as_int()
        }
        func_import_count += 1
      }
      _ => ()
    }
  }
  0
}

///|
/// Encode a reference type to an integer for the ref.null immediate
fn encode_ref_type(ref_type : @core.RefType) -> Int {
  match ref_type {
    Func => 0x70
    Extern => 0x6F
    Any => 0x6E
    Eq => 0x6D
    I31 => 0x6C
    Struct => 0x6B
    Array => 0x6A
    Exn => 0x69
    None => 0x71
    NoFunc => 0x73
    NoExtern => 0x72
    NoExn => 0x74
    TypeIndex(idx) => idx
  }
}
