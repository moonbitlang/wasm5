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
/// Compile a module to threaded code for C runtime.
pub fn compile(mod_ : @core.Module) -> CompiledModule {
  let ctx = CompileCtx::new()
  let num_imported_funcs = count_imported_funcs(mod_)

  // Pre-compute function info
  let func_entries : Array[Int] = []
  let func_num_locals : Array[Int] = []
  let func_num_params : Array[Int] = []
  let func_num_results : Array[Int] = []
  let func_max_stack : Array[Int] = []
  for i, code in mod_.codes {
    let func_idx = num_imported_funcs + i
    let type_idx = mod_.funcs[func_idx].reinterpret_as_int()
    let func_type = get_func_type(mod_, type_idx)
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    let num_locals = num_params + code.locals.length()
    func_num_params.push(num_params)
    func_num_results.push(num_results)
    func_num_locals.push(num_locals)
    func_entries.push(0) // Will be filled during compilation
    func_max_stack.push(16) // TODO: compute actual max stack
  }
  let mod_info : ModuleInfo = {
    mod_,
    func_entries,
    func_num_params,
    func_num_results,
    num_imported_funcs,
  }

  // Compile all functions
  for i, code in mod_.codes {
    let func_entry = ctx.code.length()
    func_entries[i] = func_entry
    let num_params = func_num_params[i]
    let num_locals = func_num_locals[i]
    let num_results = func_num_results[i]
    let num_non_arg_locals = num_locals - num_params

    // Initialize slot tracking for this function
    ctx.init_function(num_locals, num_results)

    // Always emit entry instruction to set sp and zero non-arg locals
    // entry(num_locals, first_local_to_zero, num_to_zero)
    ctx.emit(entry())
    ctx.emit_idx(num_locals) // sp = fp + num_locals
    ctx.emit_idx(num_params) // first_local: index of first non-arg local
    ctx.emit_idx(num_non_arg_locals) // num_to_zero

    // Push implicit function block for br 0 to target
    // Result slots are at fp[0..num_results-1] per wasm3 convention
    let func_result_slots : Array[Int] = []
    for j in 0..<num_results {
      func_result_slots.push(j)
    }
    ctx.control_stack.push({
      kind: Block,
      target_pc: 0, // Will be patched to end
      result_slots: func_result_slots,
      sp_at_entry: num_locals,
      slot_stack_len_at_entry: 0,
      pending_patches: [],
    })

    // Compile function body
    compile_expr(ctx, mod_info, code.body)

    // Pop implicit function block and patch any br 0 targets
    let func_frame_idx = ctx.control_stack.length() - 1
    let func_frame = ctx.control_stack.pop().unwrap()
    let end_pc = ctx.code.length()
    for patch_pos in func_frame.pending_patches {
      ctx.code[patch_pos] = end_pc.reinterpret_as_uint().to_uint64()
    }
    // Update end_pc for deferred blocks (br_if, br_table) targeting function frame
    for block in ctx.deferred_blocks {
      if not(block.is_loop) &&
        not(block.resolved) &&
        block.target_label == func_frame_idx {
        block.end_pc = end_pc
        block.resolved = true
      }
    }

    // Emit implicit return/end (wasm3 style: end acts like return)
    ctx.emit(end())
    ctx.emit_idx(num_results)

    // Emit deferred resolution blocks (for br_if, br_table)
    ctx.emit_deferred_blocks()
  }

  // Patch forward call targets
  for patch in ctx.call_patches {
    ctx.code[patch.patch_pos] = func_entries[patch.func_idx]
      .reinterpret_as_uint()
      .to_uint64()
  }

  // Collect function exports
  let exports : Map[String, Int] = {}
  for exp in mod_.exports {
    if exp.desc is Func(idx) {
      // Convert absolute func index to local index (excluding imports)
      let local_idx = idx.reinterpret_as_int() - num_imported_funcs
      if local_idx >= 0 {
        let name = @encoding/utf8.decode(exp.name) catch { _ => continue }
        exports[name] = local_idx
      }
    }
  }
  {
    code: FixedArray::from_array(ctx.code),
    func_entries: FixedArray::from_array(func_entries),
    func_num_locals: FixedArray::from_array(func_num_locals),
    func_max_stack: FixedArray::from_array(func_max_stack),
    exports,
  }
}

///|
/// Control frame kind
priv enum ControlKind {
  Block
  Loop
  If
} derive(Eq)

///|
/// Control frame for tracking nested blocks
priv struct ControlFrame {
  kind : ControlKind
  target_pc : Int // For loops: start PC. For blocks/ifs: patched at end
  result_slots : Array[Int] // Pre-allocated result slot positions
  sp_at_entry : Int // Stack pointer (slot) at block entry
  slot_stack_len_at_entry : Int // slot_stack.length() at block entry
  pending_patches : Array[Int] // Code positions that need patching
}

///|
/// Deferred resolution block (emitted at end of function)
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
/// Compilation context with slot-based tracking (wasm3 style)
priv struct CompileCtx {
  code : Array[UInt64]
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
    self.code[patch_pos] = end_pc.reinterpret_as_uint().to_uint64()
  }
  // Update end_pc for all unresolved deferred blocks targeting this frame
  // Note: We check `resolved` to prevent later blocks with the same abs_idx
  // (due to control stack reuse) from overwriting the end_pc
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
  // Target sp is after result slots
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
/// Get param and result arity from block type, using module types for TypeIndex
fn get_block_arities(mod_ : @core.Module, bt : @core.BlockType) -> (Int, Int) {
  match bt {
    Empty => (0, 0)
    Value(_) => (0, 1)
    TypeIndex(idx) =>
      // Look up the function type from the types section
      match mod_.types[idx] {
        Func(ft) => (ft.params.length(), ft.results.length())
        _ => (0, 1) // Fallback
      }
  }
}

///|
/// Emit stack resolution: copy current top values to pre-allocated result slots, set sp
/// For blocks: results are AT target_sp, so sp = target_sp + arity
/// For loops: params are BEFORE target_sp, so sp = target_sp
fn CompileCtx::emit_resolution(
  self : CompileCtx,
  result_slots : Array[Int],
  target_sp : Int,
  is_loop : Bool,
) -> Unit {
  let arity = result_slots.length()
  // Copy each result from current slot to pre-allocated slot
  for i in 0..<arity {
    let src_slot = self.slot_at(arity - 1 - i) // Get slot of i-th result (from bottom)
    let dst_slot = result_slots[i]
    if src_slot != dst_slot {
      self.emit(copy_slot())
      self.emit_idx(src_slot)
      self.emit_idx(dst_slot)
    }
  }
  // Set sp to correct position
  self.emit(set_sp())
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
    target_label: abs_label_idx, // Store absolute index
    is_loop,
    loop_pc,
    end_pc: 0, // Will be filled in by pop_control
    resolved: false,
  })
}

///|
/// Emit all deferred resolution blocks (call at end of function)
fn CompileCtx::emit_deferred_blocks(self : CompileCtx) -> Unit {
  for block in self.deferred_blocks {
    // Patch the reference to point here
    let block_pc = self.code.length()
    self.code[block.patch_pos] = block_pc.reinterpret_as_uint().to_uint64()

    // Emit resolution code: copy from captured src slots to dst slots
    for i in 0..<block.src_slots.length() {
      let src_slot = block.src_slots[i]
      let dst_slot = block.dst_slots[i]
      if src_slot != dst_slot {
        self.emit(copy_slot())
        self.emit_idx(src_slot)
        self.emit_idx(dst_slot)
      }
    }
    // Set sp to correct position
    let arity = block.src_slots.length()
    self.emit(set_sp())
    // For loops: params are BEFORE target_sp, so sp = target_sp
    // For blocks: results go AT target_sp, so sp = target_sp + arity
    if block.is_loop {
      self.emit_idx(block.target_sp)
    } else {
      self.emit_idx(block.target_sp + arity)
    }

    // Emit final jump
    if block.is_loop {
      self.emit(br())
      self.emit_idx(block.loop_pc)
    } else if block.target_label == 0 {
      // Function-level branch: results already at fp[0..n-1], just exit
      self.emit(func_exit())
    } else {
      // Block-level branch: jump to end of block
      self.emit(br())
      self.emit_idx(block.end_pc)
    }
  }
  self.deferred_blocks.clear()
}

///|
/// Emit a raw UInt64 value (function pointer or immediate)
fn CompileCtx::emit(self : CompileCtx, value : UInt64) -> Unit {
  self.code.push(value)
}

///|
/// Emit an i32 immediate
fn CompileCtx::emit_i32(self : CompileCtx, value : UInt) -> Unit {
  self.code.push(value.to_uint64())
}

///|
/// Emit an i64 immediate
fn CompileCtx::emit_i64(self : CompileCtx, value : UInt64) -> Unit {
  self.code.push(value)
}

///|
/// Emit an index immediate
fn CompileCtx::emit_idx(self : CompileCtx, value : Int) -> Unit {
  self.code.push(value.reinterpret_as_uint().to_uint64())
}

///|
/// Compile an expression (list of instructions)
fn compile_expr(
  ctx : CompileCtx,
  mod_info : ModuleInfo,
  expr : @core.Expr,
) -> Unit {
  for instr in expr.instrs {
    compile_instr(ctx, mod_info, instr)
  }
}

///|
/// Compile a single instruction
fn compile_instr(
  ctx : CompileCtx,
  mod_info : ModuleInfo,
  instr : @core.Instr,
) -> Unit {
  match instr {
    // Control
    Unreachable => {
      ctx.emit(wasm_unreachable())
      ctx.is_unreachable = true
    }
    Nop => () // No-op: skip at compile time
    Return => {
      ctx.emit(wasm_return())
      ctx.emit_idx(ctx.num_results)
      ctx.is_unreachable = true
    }

    // Constants - push to slot stack
    I32Const(n) => {
      ctx.emit(i32_const())
      ctx.emit_i32(n)
      ignore(ctx.push_slot())
    }
    I64Const(n) => {
      ctx.emit(i64_const())
      ctx.emit_i64(n)
      ignore(ctx.push_slot())
    }
    F32Const(f) => {
      ctx.emit(f32_const())
      ctx.emit_i64(f.reinterpret_as_uint().to_uint64())
      ignore(ctx.push_slot())
    }
    F64Const(f) => {
      ctx.emit(f64_const())
      ctx.emit_i64(f.reinterpret_as_uint64())
      ignore(ctx.push_slot())
    }

    // Locals
    LocalGet(idx) => {
      ctx.emit(local_get())
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    LocalSet(idx) => {
      ctx.emit(local_set())
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.pop_slot())
    }
    LocalTee(idx) => {
      ctx.emit(local_tee())
      ctx.emit_idx(idx.reinterpret_as_int())
    }

    // Globals
    GlobalGet(idx) => {
      ctx.emit(global_get())
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    GlobalSet(idx) => {
      ctx.emit(global_set())
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.pop_slot())
    }

    // i32 arithmetic (binary ops: pop 2, push 1 = net pop 1)
    I32Add => {
      ctx.emit(i32_add())
      ignore(ctx.pop_slot())
    }
    I32Sub => {
      ctx.emit(i32_sub())
      ignore(ctx.pop_slot())
    }
    I32Mul => {
      ctx.emit(i32_mul())
      ignore(ctx.pop_slot())
    }
    I32DivS => {
      ctx.emit(i32_div_s())
      ignore(ctx.pop_slot())
    }
    I32DivU => {
      ctx.emit(i32_div_u())
      ignore(ctx.pop_slot())
    }
    I32RemS => {
      ctx.emit(i32_rem_s())
      ignore(ctx.pop_slot())
    }
    I32RemU => {
      ctx.emit(i32_rem_u())
      ignore(ctx.pop_slot())
    }
    I32And => {
      ctx.emit(i32_and())
      ignore(ctx.pop_slot())
    }
    I32Or => {
      ctx.emit(i32_or())
      ignore(ctx.pop_slot())
    }
    I32Xor => {
      ctx.emit(i32_xor())
      ignore(ctx.pop_slot())
    }
    I32Shl => {
      ctx.emit(i32_shl())
      ignore(ctx.pop_slot())
    }
    I32ShrS => {
      ctx.emit(i32_shr_s())
      ignore(ctx.pop_slot())
    }
    I32ShrU => {
      ctx.emit(i32_shr_u())
      ignore(ctx.pop_slot())
    }
    I32Rotl => {
      ctx.emit(i32_rotl())
      ignore(ctx.pop_slot())
    }
    I32Rotr => {
      ctx.emit(i32_rotr())
      ignore(ctx.pop_slot())
    }

    // i32 comparison (binary ops: pop 2, push 1 = net pop 1)
    I32Eqz => ctx.emit(i32_eqz()) // unary: no net change
    I32Eq => {
      ctx.emit(i32_eq())
      ignore(ctx.pop_slot())
    }
    I32Ne => {
      ctx.emit(i32_ne())
      ignore(ctx.pop_slot())
    }
    I32LtS => {
      ctx.emit(i32_lt_s())
      ignore(ctx.pop_slot())
    }
    I32LtU => {
      ctx.emit(i32_lt_u())
      ignore(ctx.pop_slot())
    }
    I32GtS => {
      ctx.emit(i32_gt_s())
      ignore(ctx.pop_slot())
    }
    I32GtU => {
      ctx.emit(i32_gt_u())
      ignore(ctx.pop_slot())
    }
    I32LeS => {
      ctx.emit(i32_le_s())
      ignore(ctx.pop_slot())
    }
    I32LeU => {
      ctx.emit(i32_le_u())
      ignore(ctx.pop_slot())
    }
    I32GeS => {
      ctx.emit(i32_ge_s())
      ignore(ctx.pop_slot())
    }
    I32GeU => {
      ctx.emit(i32_ge_u())
      ignore(ctx.pop_slot())
    }

    // i32 unary
    I32Clz => ctx.emit(i32_clz())
    I32Ctz => ctx.emit(i32_ctz())
    I32Popcnt => ctx.emit(i32_popcnt())

    // i64 arithmetic (binary ops: pop 2, push 1 = net pop 1)
    I64Add => {
      ctx.emit(i64_add())
      ignore(ctx.pop_slot())
    }
    I64Sub => {
      ctx.emit(i64_sub())
      ignore(ctx.pop_slot())
    }
    I64Mul => {
      ctx.emit(i64_mul())
      ignore(ctx.pop_slot())
    }
    I64DivS => {
      ctx.emit(i64_div_s())
      ignore(ctx.pop_slot())
    }
    I64DivU => {
      ctx.emit(i64_div_u())
      ignore(ctx.pop_slot())
    }
    I64RemS => {
      ctx.emit(i64_rem_s())
      ignore(ctx.pop_slot())
    }
    I64RemU => {
      ctx.emit(i64_rem_u())
      ignore(ctx.pop_slot())
    }
    I64And => {
      ctx.emit(i64_and())
      ignore(ctx.pop_slot())
    }
    I64Or => {
      ctx.emit(i64_or())
      ignore(ctx.pop_slot())
    }
    I64Xor => {
      ctx.emit(i64_xor())
      ignore(ctx.pop_slot())
    }
    I64Shl => {
      ctx.emit(i64_shl())
      ignore(ctx.pop_slot())
    }
    I64ShrS => {
      ctx.emit(i64_shr_s())
      ignore(ctx.pop_slot())
    }
    I64ShrU => {
      ctx.emit(i64_shr_u())
      ignore(ctx.pop_slot())
    }
    I64Rotl => {
      ctx.emit(i64_rotl())
      ignore(ctx.pop_slot())
    }
    I64Rotr => {
      ctx.emit(i64_rotr())
      ignore(ctx.pop_slot())
    }

    // i64 comparison (binary ops: pop 2, push 1 = net pop 1)
    I64Eqz => ctx.emit(i64_eqz()) // unary: no net change
    I64Eq => {
      ctx.emit(i64_eq())
      ignore(ctx.pop_slot())
    }
    I64Ne => {
      ctx.emit(i64_ne())
      ignore(ctx.pop_slot())
    }
    I64LtS => {
      ctx.emit(i64_lt_s())
      ignore(ctx.pop_slot())
    }
    I64LtU => {
      ctx.emit(i64_lt_u())
      ignore(ctx.pop_slot())
    }
    I64GtS => {
      ctx.emit(i64_gt_s())
      ignore(ctx.pop_slot())
    }
    I64GtU => {
      ctx.emit(i64_gt_u())
      ignore(ctx.pop_slot())
    }
    I64LeS => {
      ctx.emit(i64_le_s())
      ignore(ctx.pop_slot())
    }
    I64LeU => {
      ctx.emit(i64_le_u())
      ignore(ctx.pop_slot())
    }
    I64GeS => {
      ctx.emit(i64_ge_s())
      ignore(ctx.pop_slot())
    }
    I64GeU => {
      ctx.emit(i64_ge_u())
      ignore(ctx.pop_slot())
    }

    // i64 unary
    I64Clz => ctx.emit(i64_clz())
    I64Ctz => ctx.emit(i64_ctz())
    I64Popcnt => ctx.emit(i64_popcnt())

    // f32 arithmetic (binary ops: pop 2, push 1 = net pop 1)
    F32Add => {
      ctx.emit(f32_add())
      ignore(ctx.pop_slot())
    }
    F32Sub => {
      ctx.emit(f32_sub())
      ignore(ctx.pop_slot())
    }
    F32Mul => {
      ctx.emit(f32_mul())
      ignore(ctx.pop_slot())
    }
    F32Div => {
      ctx.emit(f32_div())
      ignore(ctx.pop_slot())
    }
    F32Min => {
      ctx.emit(f32_min())
      ignore(ctx.pop_slot())
    }
    F32Max => {
      ctx.emit(f32_max())
      ignore(ctx.pop_slot())
    }
    F32Copysign => {
      ctx.emit(f32_copysign())
      ignore(ctx.pop_slot())
    }

    // f32 comparison (binary ops: pop 2, push 1 = net pop 1)
    F32Eq => {
      ctx.emit(f32_eq())
      ignore(ctx.pop_slot())
    }
    F32Ne => {
      ctx.emit(f32_ne())
      ignore(ctx.pop_slot())
    }
    F32Lt => {
      ctx.emit(f32_lt())
      ignore(ctx.pop_slot())
    }
    F32Gt => {
      ctx.emit(f32_gt())
      ignore(ctx.pop_slot())
    }
    F32Le => {
      ctx.emit(f32_le())
      ignore(ctx.pop_slot())
    }
    F32Ge => {
      ctx.emit(f32_ge())
      ignore(ctx.pop_slot())
    }

    // f32 unary
    F32Abs => ctx.emit(f32_abs())
    F32Neg => ctx.emit(f32_neg())
    F32Ceil => ctx.emit(f32_ceil())
    F32Floor => ctx.emit(f32_floor())
    F32Trunc => ctx.emit(f32_trunc())
    F32Nearest => ctx.emit(f32_nearest())
    F32Sqrt => ctx.emit(f32_sqrt())

    // f64 arithmetic (binary ops: pop 2, push 1 = net pop 1)
    F64Add => {
      ctx.emit(f64_add())
      ignore(ctx.pop_slot())
    }
    F64Sub => {
      ctx.emit(f64_sub())
      ignore(ctx.pop_slot())
    }
    F64Mul => {
      ctx.emit(f64_mul())
      ignore(ctx.pop_slot())
    }
    F64Div => {
      ctx.emit(f64_div())
      ignore(ctx.pop_slot())
    }
    F64Min => {
      ctx.emit(f64_min())
      ignore(ctx.pop_slot())
    }
    F64Max => {
      ctx.emit(f64_max())
      ignore(ctx.pop_slot())
    }
    F64Copysign => {
      ctx.emit(f64_copysign())
      ignore(ctx.pop_slot())
    }

    // f64 comparison (binary ops: pop 2, push 1 = net pop 1)
    F64Eq => {
      ctx.emit(f64_eq())
      ignore(ctx.pop_slot())
    }
    F64Ne => {
      ctx.emit(f64_ne())
      ignore(ctx.pop_slot())
    }
    F64Lt => {
      ctx.emit(f64_lt())
      ignore(ctx.pop_slot())
    }
    F64Gt => {
      ctx.emit(f64_gt())
      ignore(ctx.pop_slot())
    }
    F64Le => {
      ctx.emit(f64_le())
      ignore(ctx.pop_slot())
    }
    F64Ge => {
      ctx.emit(f64_ge())
      ignore(ctx.pop_slot())
    }

    // f64 unary
    F64Abs => ctx.emit(f64_abs())
    F64Neg => ctx.emit(f64_neg())
    F64Ceil => ctx.emit(f64_ceil())
    F64Floor => ctx.emit(f64_floor())
    F64Trunc => ctx.emit(f64_trunc())
    F64Nearest => ctx.emit(f64_nearest())
    F64Sqrt => ctx.emit(f64_sqrt())

    // Conversions
    I32WrapI64 => ctx.emit(i32_wrap_i64())
    I32TruncF32S => ctx.emit(i32_trunc_f32_s())
    I32TruncF32U => ctx.emit(i32_trunc_f32_u())
    I32TruncF64S => ctx.emit(i32_trunc_f64_s())
    I32TruncF64U => ctx.emit(i32_trunc_f64_u())
    I64ExtendI32S => ctx.emit(i64_extend_i32_s())
    I64ExtendI32U => ctx.emit(i64_extend_i32_u())
    I64TruncF32S => ctx.emit(i64_trunc_f32_s())
    I64TruncF32U => ctx.emit(i64_trunc_f32_u())
    I64TruncF64S => ctx.emit(i64_trunc_f64_s())
    I64TruncF64U => ctx.emit(i64_trunc_f64_u())
    F32ConvertI32S => ctx.emit(f32_convert_i32_s())
    F32ConvertI32U => ctx.emit(f32_convert_i32_u())
    F32ConvertI64S => ctx.emit(f32_convert_i64_s())
    F32ConvertI64U => ctx.emit(f32_convert_i64_u())
    F32DemoteF64 => ctx.emit(f32_demote_f64())
    F64ConvertI32S => ctx.emit(f64_convert_i32_s())
    F64ConvertI32U => ctx.emit(f64_convert_i32_u())
    F64ConvertI64S => ctx.emit(f64_convert_i64_s())
    F64ConvertI64U => ctx.emit(f64_convert_i64_u())
    F64PromoteF32 => ctx.emit(f64_promote_f32())
    I32ReinterpretF32 => ctx.emit(i32_reinterpret_f32())
    I64ReinterpretF64 => ctx.emit(i64_reinterpret_f64())
    F32ReinterpretI32 => ctx.emit(f32_reinterpret_i32())
    F64ReinterpretI64 => ctx.emit(f64_reinterpret_i64())

    // Sign extension
    I32Extend8S => ctx.emit(i32_extend8_s())
    I32Extend16S => ctx.emit(i32_extend16_s())
    I64Extend8S => ctx.emit(i64_extend8_s())
    I64Extend16S => ctx.emit(i64_extend16_s())
    I64Extend32S => ctx.emit(i64_extend32_s())

    // Stack operations
    Drop => {
      ctx.emit(drop())
      ignore(ctx.pop_slot())
    }
    Select(_) | SelectTyped(_) => {
      ctx.emit(select())
      ignore(ctx.pop_slot()) // condition
      ignore(ctx.pop_slot()) // val2
      // val1 stays, result goes to new slot
      ignore(ctx.pop_slot())
      ignore(ctx.push_slot())
    }

    // Memory operations
    MemoryGrow(mem_idx) => {
      ctx.emit(memory_grow())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes delta, produces old size - no net change
    }
    MemorySize(mem_idx) => {
      ctx.emit(memory_size())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    I32Load(align, offset, mem_idx) => {
      ctx.emit(i32_load())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes address, produces value - no net change
    }
    I32Store(align, offset, mem_idx) => {
      ctx.emit(i32_store())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // value
      ignore(ctx.pop_slot()) // address
    }
    I32Load8S(align, offset, mem_idx) => {
      ctx.emit(i32_load8_s())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes address, produces value - no net change
    }
    I32Load8U(align, offset, mem_idx) => {
      ctx.emit(i32_load8_u())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes address, produces value - no net change
    }
    I32Load16S(align, offset, mem_idx) => {
      ctx.emit(i32_load16_s())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes address, produces value - no net change
    }
    I32Load16U(align, offset, mem_idx) => {
      ctx.emit(i32_load16_u())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      // Consumes address, produces value - no net change
    }
    I32Store8(align, offset, mem_idx) => {
      ctx.emit(i32_store8())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // value
      ignore(ctx.pop_slot()) // address
    }
    I32Store16(align, offset, mem_idx) => {
      ctx.emit(i32_store16())
      ctx.emit_idx(align.reinterpret_as_int())
      ctx.emit_idx(offset.reinterpret_as_int())
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // value
      ignore(ctx.pop_slot()) // address
    }

    // Block structures
    Block(bt, body) => {
      let arity = get_block_arity(mod_info.mod_, bt)
      ctx.push_control(Block, arity, 0) // target_pc will be patched at end
      compile_expr(ctx, mod_info, { instrs: body })
      // At block end, copy results to pre-allocated slots (only if reachable)
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      let fallthrough_reachable = not(ctx.is_unreachable)
      if fallthrough_reachable {
        ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
      }
      // Block end is reachable if fallthrough is reachable OR any br targeted this block
      let block_end_reachable = fallthrough_reachable ||
        frame.pending_patches.length() > 0
      ctx.pop_control()
      // Restore slot_stack to entry state, then push result slots
      while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
        ignore(ctx.slot_stack.pop())
      }
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
      // Reset next_slot to after result slots
      ctx.next_slot = frame.sp_at_entry + arity
      // Only reset unreachable if block end is reachable
      if block_end_reachable {
        ctx.is_unreachable = false
      }
    }
    Loop(bt, body) => {
      // For loops: branch arity = param arity, result arity = result arity
      let (param_arity, _result_arity) = get_block_arities(mod_info.mod_, bt)
      let loop_start = ctx.code.length()
      // Save slot_stack length at loop entry
      let slot_stack_len = ctx.slot_stack.length()
      // For loops, the param slots are already on the stack from values pushed before the loop
      // Capture them as the branch target slots (NOT pre-allocated)
      let param_slots : Array[Int] = []
      for i in 0..<param_arity {
        // Get slot at depth (param_arity - 1 - i) to get them in order
        param_slots.push(ctx.slot_at(param_arity - 1 - i))
      }
      // Push control frame with captured param slots as result_slots
      ctx.control_stack.push({
        kind: Loop,
        target_pc: loop_start,
        result_slots: param_slots, // For loops, these are the param slots for branching
        sp_at_entry: ctx.current_sp(),
        slot_stack_len_at_entry: slot_stack_len,
        pending_patches: [],
      })
      compile_expr(ctx, mod_info, { instrs: body })
      // Loop falls through - pop the control frame
      ctx.pop_control()
      // The loop body has already set up the correct slot_stack state
      // with result_arity values on top. No additional adjustment needed.
      // NOTE: We do NOT reset is_unreachable here because:
      // - br to a loop jumps back to loop start (continues loop)
      // - If body ends unreachable (br to outer block), loop end is also unreachable
    }
    If(bt, then_body, else_body) => {
      ignore(ctx.pop_slot()) // Consume condition
      let arity = get_block_arity(mod_info.mod_, bt)
      ctx.emit(wasm_if())
      let else_patch = ctx.code.length()
      ctx.emit_idx(0) // Placeholder for else_pc
      ctx.push_control(If, arity, 0)
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      // Compile then branch
      compile_expr(ctx, mod_info, { instrs: then_body })
      // Copy results to pre-allocated slots (only if reachable)
      let then_unreachable = ctx.is_unreachable
      if not(then_unreachable) {
        ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
      }
      if else_body.length() > 0 {
        // Emit branch to skip else (only if then is reachable)
        let mut end_patch = 0
        if not(then_unreachable) {
          ctx.emit(br())
          end_patch = ctx.code.length()
          ctx.emit_idx(0) // Placeholder for end_pc
        }
        // Patch else_pc to here
        ctx.code[else_patch] = ctx.code
          .length()
          .reinterpret_as_uint()
          .to_uint64()
        // Restore slot state for else branch using saved entry state
        // Must rebuild slot_stack to have exactly the slots that existed at entry
        while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
          ignore(ctx.slot_stack.pop())
        }
        // If slot_stack is shorter (then branch consumed params), restore missing slots
        // Slots at entry were: [sp_at_entry - len_at_entry, ..., sp_at_entry - 1]
        let base_slot = frame.sp_at_entry - frame.slot_stack_len_at_entry
        while ctx.slot_stack.length() < frame.slot_stack_len_at_entry {
          ctx.slot_stack.push(base_slot + ctx.slot_stack.length())
        }
        ctx.next_slot = frame.sp_at_entry
        ctx.is_unreachable = false
        // Compile else branch
        compile_expr(ctx, mod_info, { instrs: else_body })
        // Copy results to pre-allocated slots (only if reachable)
        let else_unreachable = ctx.is_unreachable
        if not(else_unreachable) {
          ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
        }
        // Patch end_pc (only if then was reachable)
        if not(then_unreachable) {
          ctx.code[end_patch] = ctx.code
            .length()
            .reinterpret_as_uint()
            .to_uint64()
        }
        // If end is reachable if either branch is reachable
        ctx.is_unreachable = then_unreachable && else_unreachable
      } else {
        // No else - patch else_pc to end
        ctx.code[else_patch] = ctx.code
          .length()
          .reinterpret_as_uint()
          .to_uint64()
        // With no else, end is always reachable (else branch does nothing)
        ctx.is_unreachable = false
      }
      ctx.pop_control()
      // Restore slot_stack to entry state, then push result slots
      while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
        ignore(ctx.slot_stack.pop())
      }
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
      ctx.next_slot = frame.sp_at_entry + arity
    }

    // Branches - emit resolution inline for br, defer for br_if/br_table
    Br(label) => {
      let label_int = label.reinterpret_as_int()
      let is_loop = ctx.is_loop_target(label_int)
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      let arity = result_slots.length()
      // Emit resolution code inline
      ctx.emit_resolution(result_slots, target_sp, is_loop)
      // Emit simple jump
      ctx.emit(br())
      if ctx.is_loop_target(label_int) {
        ctx.emit_idx(target_pc)
      } else {
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0) // Placeholder
        ctx.add_patch(label_int, patch_pos)
      }
      // Pop consumed values from logical stack
      for _ in 0..<arity {
        ignore(ctx.pop_slot())
      }
      // Code after unconditional branch is unreachable
      ctx.is_unreachable = true
    }
    BrIf(label) => {
      ignore(ctx.pop_slot()) // Consume condition
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      let arity = result_slots.length()
      // Capture current slot positions for results
      let src_slots = ctx.capture_result_slots(arity)
      // Emit conditional branch: taken goes to deferred block, not-taken continues
      ctx.emit(br_if())
      let taken_patch = ctx.code.length()
      ctx.emit_idx(0) // Placeholder for taken path (deferred block)
      let not_taken_pc = ctx.code.length() + 1 // Next instruction after this
      ctx.emit_idx(not_taken_pc)
      // Defer the resolution block
      ctx.defer_resolution(
        taken_patch,
        src_slots,
        result_slots,
        target_sp,
        label_int,
        ctx.is_loop_target(label_int),
        target_pc,
      )
    }
    BrTable(labels, default_label) => {
      ignore(ctx.pop_slot()) // Consume index
      // Get arity from default label
      let default_int = default_label.reinterpret_as_int()
      let (_, default_result_slots, _) = ctx.get_branch_target(default_int)
      let arity = default_result_slots.length()
      // Capture current slot positions for results
      let src_slots = ctx.capture_result_slots(arity)
      ctx.emit(br_table())
      ctx.emit_idx(labels.length())
      // Emit placeholders for each entry (including default)
      let patches : Array[Int] = []
      for _ in labels {
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0)
        patches.push(patch_pos)
      }
      let default_patch = ctx.code.length()
      ctx.emit_idx(0)
      patches.push(default_patch)
      // Defer resolution blocks for each entry
      for i, label in labels {
        let label_int = label.reinterpret_as_int()
        let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
          label_int,
        )
        ctx.defer_resolution(
          patches[i],
          src_slots,
          result_slots,
          target_sp,
          label_int,
          ctx.is_loop_target(label_int),
          target_pc,
        )
      }
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        default_int,
      )
      ctx.defer_resolution(
        patches[labels.length()],
        src_slots,
        result_slots,
        target_sp,
        default_int,
        ctx.is_loop_target(default_int),
        target_pc,
      )
      // Code after br_table is unreachable
      ctx.is_unreachable = true
    }

    // Function calls (wasm3 style: compute frame layout at compile time)
    Call(func_idx_uint) => {
      let func_idx = func_idx_uint.reinterpret_as_int()
      // Convert absolute func index to local index (excluding imports)
      let local_idx = func_idx - mod_info.num_imported_funcs
      if local_idx >= 0 && local_idx < mod_info.func_entries.length() {
        // Local function call
        let num_params = mod_info.func_num_params[local_idx]
        let num_results = mod_info.func_num_results[local_idx]

        // Remember where first arg is - this will be frame_offset
        // Args are contiguous at slots: slot_at(num_params-1), slot_at(num_params-2), ..., slot_at(0)
        // where slot_at(num_params-1) is the first arg (pushed first, deepest)
        let frame_offset = if num_params > 0 {
          ctx.slot_at(num_params - 1)
        } else {
          ctx.current_sp()
        }

        // Pop arguments from slot stack first
        for _ in 0..<num_params {
          ignore(ctx.pop_slot())
        }

        // Now frame_offset points to where first arg was, which is contiguous
        // with remaining stack. Args are already at frame_offset..frame_offset+num_params-1
        // No copy needed before call!

        // Emit call instruction with callee_pc and frame_offset
        ctx.emit(call())
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0) // Placeholder for callee_pc (will be patched)
        ctx.emit_idx(frame_offset)

        // Add patch for the callee_pc
        ctx.call_patches.push({ patch_pos, func_idx: local_idx })

        // Results are returned at frame_offset..frame_offset+num_results-1
        // which is naturally contiguous with remaining stack
        // Push result slots directly
        for i in 0..<num_results {
          ctx.slot_stack.push(frame_offset + i)
        }
        ctx.next_slot = frame_offset + num_results

        // Set sp to after the result slots (for sp-relative operations)
        ctx.emit(set_sp())
        ctx.emit_idx(ctx.current_sp())
      }
      // TODO: handle imported function calls
    }

    // Indirect function call via table
    CallIndirect(type_idx, table_idx) => {
      // Get function type from type index
      let type_int = type_idx.reinterpret_as_int()
      let func_type = get_func_type(mod_info.mod_, type_int)
      let num_params = func_type.params.length()
      let num_results = func_type.results.length()

      // Stack has: [..., args..., elem_idx]
      // Pop the elem_idx from slot stack (handled by C at runtime)
      ignore(ctx.pop_slot())

      // Compute frame_offset from the args (same as Call)
      let frame_offset = if num_params > 0 {
        ctx.slot_at(num_params - 1)
      } else {
        ctx.current_sp()
      }

      // Pop args from slot stack
      for _ in 0..<num_params {
        ignore(ctx.pop_slot())
      }

      // Emit call_indirect: type_idx, table_idx, frame_offset
      ctx.emit(call_indirect())
      ctx.emit_idx(type_int)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ctx.emit_idx(frame_offset)

      // Push result slots
      for i in 0..<num_results {
        ctx.slot_stack.push(frame_offset + i)
      }
      ctx.next_slot = frame_offset + num_results

      // Set sp to after result slots
      ctx.emit(set_sp())
      ctx.emit_idx(ctx.current_sp())
    }

    // Placeholder for unimplemented instructions
    _ =>
      // TODO: implement remaining instructions
      ()
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
    _ => { params: [], results: [] } // Should not happen for valid modules
  }
}
