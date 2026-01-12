///|
/// Compile a module to threaded code for C runtime.
pub fn compile(mod_ : @core.Module) -> CompiledModule {
  let ctx = CompileCtx::new()
  let num_imported_funcs = count_imported_funcs(mod_)

  // Compile all functions
  let func_entries : Array[Int] = []
  let func_num_locals : Array[Int] = []
  let func_max_stack : Array[Int] = []
  for i, code in mod_.codes {
    let entry = ctx.code.length()
    func_entries.push(entry)

    // Count locals (params + locals)
    let func_idx = num_imported_funcs + i
    let type_idx = mod_.funcs[func_idx].reinterpret_as_int()
    let func_type = get_func_type(mod_, type_idx)
    let num_params = func_type.params.length()
    let num_locals = num_params + code.locals.length()
    func_num_locals.push(num_locals)

    // Initialize slot tracking for this function
    ctx.init_function(num_locals)

    // Compile function body
    compile_expr(ctx, code.body)

    // Emit implicit return/end
    ctx.emit(end())

    // Emit deferred resolution blocks (for br_if, br_table)
    ctx.emit_deferred_blocks()

    // Record max stack (placeholder - would need proper analysis)
    func_max_stack.push(16) // TODO: compute actual max stack
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
  target_pc : Int          // For loops: start PC. For blocks/ifs: patched at end
  arity : Int              // Number of results (for br target)
  result_slots : Array[Int]  // Pre-allocated result slot positions
  sp_at_entry : Int        // Stack pointer (slot) at block entry
  pending_patches : Array[Int]  // Code positions that need patching
}

///|
/// Deferred resolution block (emitted at end of function)
priv struct DeferredBlock {
  patch_pos : Int          // Position in code to patch with block address
  src_slots : Array[Int]   // Source slot positions (captured at branch time)
  dst_slots : Array[Int]   // Destination (pre-allocated) result slots
  target_sp : Int          // Stack pointer after branch
  target_label : Int       // Label depth for final jump target
  is_loop : Bool           // Whether target is a loop (known PC) or block (needs patch)
  loop_pc : Int            // Loop PC if is_loop is true
}

///|
/// Compilation context with slot-based tracking (wasm3 style)
priv struct CompileCtx {
  code : Array[UInt64]
  control_stack : Array[ControlFrame]
  deferred_blocks : Array[DeferredBlock]  // Resolution blocks to emit at end
  slot_stack : Array[Int]  // Maps logical stack index to slot number
  mut next_slot : Int      // Next available slot for allocation
  mut num_locals : Int     // Number of locals (slots 0..num_locals-1)
}

///|
fn CompileCtx::new() -> CompileCtx {
  { code: [], control_stack: [], deferred_blocks: [], slot_stack: [], next_slot: 0, num_locals: 0 }
}

///|
/// Initialize context for a function with given number of locals
fn CompileCtx::init_function(self : CompileCtx, num_locals : Int) -> Unit {
  self.slot_stack.clear()
  self.num_locals = num_locals
  self.next_slot = num_locals  // Operand slots start after locals
}

///|
/// Current stack height (number of values on operand stack)
fn CompileCtx::stack_height(self : CompileCtx) -> Int {
  self.slot_stack.length()
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
/// Peek at top slot without popping
fn CompileCtx::top_slot(self : CompileCtx) -> Int {
  guard self.slot_stack.length() > 0 else { return 0 }
  self.slot_stack[self.slot_stack.length() - 1]
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
    arity,
    result_slots,
    sp_at_entry: self.current_sp(),
    pending_patches: [],
  })
}

///|
/// Pop a control frame and patch pending branches
fn CompileCtx::pop_control(self : CompileCtx) -> Unit {
  guard self.control_stack.length() > 0 else { return }
  let frame = self.control_stack.pop().unwrap()
  let end_pc = self.code.length()
  // Patch all pending forward branches to point here
  for patch_pos in frame.pending_patches {
    self.code[patch_pos] = end_pc.reinterpret_as_uint().to_uint64()
  }
}

///|
/// Get branch target info: (target_pc, result_slots, target_sp)
fn CompileCtx::get_branch_target(self : CompileCtx, label : Int) -> (Int, Array[Int], Int) {
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
fn CompileCtx::add_patch(self : CompileCtx, label : Int, patch_pos : Int) -> Unit {
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
fn get_block_arity(bt : @core.BlockType) -> Int {
  match bt {
    Empty => 0
    Value(_) => 1
    TypeIndex(_) => 1 // Simplified - would need type lookup for multi-value
  }
}

///|
/// Emit stack resolution: copy current top values to pre-allocated result slots, set sp
fn CompileCtx::emit_resolution(self : CompileCtx, result_slots : Array[Int], target_sp : Int) -> Unit {
  let arity = result_slots.length()
  // Copy each result from current slot to pre-allocated slot
  for i in 0..<arity {
    let src_slot = self.slot_at(arity - 1 - i)  // Get slot of i-th result (from bottom)
    let dst_slot = result_slots[i]
    if src_slot != dst_slot {
      self.emit(copy_slot())
      self.emit_idx(src_slot)
      self.emit_idx(dst_slot)
    }
  }
  // Set sp to target position
  self.emit(set_sp())
  self.emit_idx(target_sp)
}

///|
/// Capture current slot positions for results
fn CompileCtx::capture_result_slots(self : CompileCtx, arity : Int) -> Array[Int] {
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
  self.deferred_blocks.push({ patch_pos, src_slots, dst_slots, target_sp, target_label, is_loop, loop_pc })
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
    // Set sp to target position
    self.emit(set_sp())
    self.emit_idx(block.target_sp)

    // Emit final jump
    self.emit(br())
    if block.is_loop {
      self.emit_idx(block.loop_pc)
    } else {
      // Need to patch this to block end - add to pending patches
      let patch_pos = self.code.length()
      self.emit_idx(0)
      self.add_patch(block.target_label, patch_pos)
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
fn compile_expr(ctx : CompileCtx, expr : @core.Expr) -> Unit {
  for instr in expr.instrs {
    compile_instr(ctx, instr)
  }
}

///|
/// Compile a single instruction
fn compile_instr(ctx : CompileCtx, instr : @core.Instr) -> Unit {
  match instr {
    // Control
    Unreachable => ctx.emit(wasm_unreachable())
    Nop => ctx.emit(nop())
    Return => ctx.emit(wasm_return())

    // Constants
    I32Const(n) => {
      ctx.emit(i32_const())
      ctx.emit_i32(n)
    }
    I64Const(n) => {
      ctx.emit(i64_const())
      ctx.emit_i64(n)
    }
    F32Const(f) => {
      ctx.emit(f32_const())
      ctx.emit_i64(f.reinterpret_as_uint().to_uint64())
    }
    F64Const(f) => {
      ctx.emit(f64_const())
      ctx.emit_i64(f.reinterpret_as_uint64())
    }

    // Locals
    LocalGet(idx) => {
      ctx.emit(local_get())
      ctx.emit_idx(idx.reinterpret_as_int())
    }
    LocalSet(idx) => {
      ctx.emit(local_set())
      ctx.emit_idx(idx.reinterpret_as_int())
    }
    LocalTee(idx) => {
      ctx.emit(local_tee())
      ctx.emit_idx(idx.reinterpret_as_int())
    }

    // Globals
    GlobalGet(idx) => {
      ctx.emit(global_get())
      ctx.emit_idx(idx.reinterpret_as_int())
    }
    GlobalSet(idx) => {
      ctx.emit(global_set())
      ctx.emit_idx(idx.reinterpret_as_int())
    }

    // i32 arithmetic
    I32Add => ctx.emit(i32_add())
    I32Sub => ctx.emit(i32_sub())
    I32Mul => ctx.emit(i32_mul())
    I32DivS => ctx.emit(i32_div_s())
    I32DivU => ctx.emit(i32_div_u())
    I32RemS => ctx.emit(i32_rem_s())
    I32RemU => ctx.emit(i32_rem_u())
    I32And => ctx.emit(i32_and())
    I32Or => ctx.emit(i32_or())
    I32Xor => ctx.emit(i32_xor())
    I32Shl => ctx.emit(i32_shl())
    I32ShrS => ctx.emit(i32_shr_s())
    I32ShrU => ctx.emit(i32_shr_u())
    I32Rotl => ctx.emit(i32_rotl())
    I32Rotr => ctx.emit(i32_rotr())

    // i32 comparison
    I32Eqz => ctx.emit(i32_eqz())
    I32Eq => ctx.emit(i32_eq())
    I32Ne => ctx.emit(i32_ne())
    I32LtS => ctx.emit(i32_lt_s())
    I32LtU => ctx.emit(i32_lt_u())
    I32GtS => ctx.emit(i32_gt_s())
    I32GtU => ctx.emit(i32_gt_u())
    I32LeS => ctx.emit(i32_le_s())
    I32LeU => ctx.emit(i32_le_u())
    I32GeS => ctx.emit(i32_ge_s())
    I32GeU => ctx.emit(i32_ge_u())

    // i32 unary
    I32Clz => ctx.emit(i32_clz())
    I32Ctz => ctx.emit(i32_ctz())
    I32Popcnt => ctx.emit(i32_popcnt())

    // i64 arithmetic
    I64Add => ctx.emit(i64_add())
    I64Sub => ctx.emit(i64_sub())
    I64Mul => ctx.emit(i64_mul())
    I64DivS => ctx.emit(i64_div_s())
    I64DivU => ctx.emit(i64_div_u())
    I64RemS => ctx.emit(i64_rem_s())
    I64RemU => ctx.emit(i64_rem_u())
    I64And => ctx.emit(i64_and())
    I64Or => ctx.emit(i64_or())
    I64Xor => ctx.emit(i64_xor())
    I64Shl => ctx.emit(i64_shl())
    I64ShrS => ctx.emit(i64_shr_s())
    I64ShrU => ctx.emit(i64_shr_u())
    I64Rotl => ctx.emit(i64_rotl())
    I64Rotr => ctx.emit(i64_rotr())

    // i64 comparison
    I64Eqz => ctx.emit(i64_eqz())
    I64Eq => ctx.emit(i64_eq())
    I64Ne => ctx.emit(i64_ne())
    I64LtS => ctx.emit(i64_lt_s())
    I64LtU => ctx.emit(i64_lt_u())
    I64GtS => ctx.emit(i64_gt_s())
    I64GtU => ctx.emit(i64_gt_u())
    I64LeS => ctx.emit(i64_le_s())
    I64LeU => ctx.emit(i64_le_u())
    I64GeS => ctx.emit(i64_ge_s())
    I64GeU => ctx.emit(i64_ge_u())

    // i64 unary
    I64Clz => ctx.emit(i64_clz())
    I64Ctz => ctx.emit(i64_ctz())
    I64Popcnt => ctx.emit(i64_popcnt())

    // f32 arithmetic
    F32Add => ctx.emit(f32_add())
    F32Sub => ctx.emit(f32_sub())
    F32Mul => ctx.emit(f32_mul())
    F32Div => ctx.emit(f32_div())
    F32Min => ctx.emit(f32_min())
    F32Max => ctx.emit(f32_max())
    F32Copysign => ctx.emit(f32_copysign())

    // f32 comparison
    F32Eq => ctx.emit(f32_eq())
    F32Ne => ctx.emit(f32_ne())
    F32Lt => ctx.emit(f32_lt())
    F32Gt => ctx.emit(f32_gt())
    F32Le => ctx.emit(f32_le())
    F32Ge => ctx.emit(f32_ge())

    // f32 unary
    F32Abs => ctx.emit(f32_abs())
    F32Neg => ctx.emit(f32_neg())
    F32Ceil => ctx.emit(f32_ceil())
    F32Floor => ctx.emit(f32_floor())
    F32Trunc => ctx.emit(f32_trunc())
    F32Nearest => ctx.emit(f32_nearest())
    F32Sqrt => ctx.emit(f32_sqrt())

    // f64 arithmetic
    F64Add => ctx.emit(f64_add())
    F64Sub => ctx.emit(f64_sub())
    F64Mul => ctx.emit(f64_mul())
    F64Div => ctx.emit(f64_div())
    F64Min => ctx.emit(f64_min())
    F64Max => ctx.emit(f64_max())
    F64Copysign => ctx.emit(f64_copysign())

    // f64 comparison
    F64Eq => ctx.emit(f64_eq())
    F64Ne => ctx.emit(f64_ne())
    F64Lt => ctx.emit(f64_lt())
    F64Gt => ctx.emit(f64_gt())
    F64Le => ctx.emit(f64_le())
    F64Ge => ctx.emit(f64_ge())

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
    Select(_) => {
      ctx.emit(select())
      ignore(ctx.pop_slot()) // condition
      ignore(ctx.pop_slot()) // val2
      // val1 stays, result goes to new slot
      ignore(ctx.pop_slot())
      ignore(ctx.push_slot())
    }

    // Block structures
    Block(bt, body) => {
      let arity = get_block_arity(bt)
      ctx.push_control(Block, arity, 0) // target_pc will be patched at end
      compile_expr(ctx, { instrs: body })
      // At block end, copy results to pre-allocated slots
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      ctx.emit_resolution(frame.result_slots, frame.sp_at_entry)
      ctx.pop_control()
      // Push result slots back onto logical stack
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
    }
    Loop(bt, body) => {
      let arity = get_block_arity(bt)
      let loop_start = ctx.code.length()
      ctx.push_control(Loop, arity, loop_start)
      compile_expr(ctx, { instrs: body })
      // Loop falls through (no resolution needed at end)
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      ctx.pop_control()
      // Push result slots back onto logical stack
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
    }
    If(bt, then_body, else_body) => {
      ignore(ctx.pop_slot()) // Consume condition
      let arity = get_block_arity(bt)
      ctx.emit(wasm_if())
      let else_patch = ctx.code.length()
      ctx.emit_idx(0) // Placeholder for else_pc
      ctx.push_control(If, arity, 0)
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      // Compile then branch
      compile_expr(ctx, { instrs: then_body })
      // Copy results to pre-allocated slots
      ctx.emit_resolution(frame.result_slots, frame.sp_at_entry)
      if else_body.length() > 0 {
        // Emit branch to skip else
        ctx.emit(br())
        let end_patch = ctx.code.length()
        ctx.emit_idx(0) // Placeholder for end_pc
        // Patch else_pc to here
        ctx.code[else_patch] = ctx.code.length().reinterpret_as_uint().to_uint64()
        // Reset slot state for else branch
        ctx.next_slot = frame.sp_at_entry
        ctx.slot_stack.clear()
        // Compile else branch
        compile_expr(ctx, { instrs: else_body })
        // Copy results to pre-allocated slots
        ctx.emit_resolution(frame.result_slots, frame.sp_at_entry)
        // Patch end_pc
        ctx.code[end_patch] = ctx.code.length().reinterpret_as_uint().to_uint64()
      } else {
        // No else - patch else_pc to end
        ctx.code[else_patch] = ctx.code.length().reinterpret_as_uint().to_uint64()
      }
      ctx.pop_control()
      // Push result slots back onto logical stack
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
    }

    // Branches - emit resolution inline for br, defer for br_if/br_table
    Br(label) => {
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(label_int)
      let arity = result_slots.length()
      // Emit resolution code inline
      ctx.emit_resolution(result_slots, target_sp)
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
    }
    BrIf(label) => {
      ignore(ctx.pop_slot()) // Consume condition
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(label_int)
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
      ctx.defer_resolution(taken_patch, src_slots, result_slots, target_sp, label_int, ctx.is_loop_target(label_int), target_pc)
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
        let (target_pc, result_slots, target_sp) = ctx.get_branch_target(label_int)
        ctx.defer_resolution(patches[i], src_slots, result_slots, target_sp, label_int, ctx.is_loop_target(label_int), target_pc)
      }
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(default_int)
      ctx.defer_resolution(patches[labels.length()], src_slots, result_slots, target_sp, default_int, ctx.is_loop_target(default_int), target_pc)
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
