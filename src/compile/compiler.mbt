///|
/// Compile a module to universal IR.
pub fn compile(mod_ : @core.Module) -> @core.CompiledModule {
  let ctx = CompileCtx::new()
  let num_imported_funcs = count_imported_funcs(mod_)

  // Pre-compute function info
  let func_entries : Array[Int] = []
  let func_num_locals : Array[Int] = []
  let func_num_params : Array[Int] = []
  let func_num_results : Array[Int] = []
  let func_max_stack : Array[Int] = []
  for i, code in mod_.codes {
    let type_idx = mod_.funcs[i].reinterpret_as_int()
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

    // Emit entry instruction
    ctx.emit_op(@core.OpTag::Entry)
    ctx.emit_idx(num_locals)
    ctx.emit_idx(num_params)
    ctx.emit_idx(num_non_arg_locals)

    // Push implicit function block
    let func_result_slots : Array[Int] = []
    for j in 0..<num_results {
      func_result_slots.push(j)
    }
    ctx.control_stack.push({
      kind: Block,
      target_pc: 0,
      result_slots: func_result_slots,
      sp_at_entry: num_locals,
      slot_stack_len_at_entry: 0,
      pending_patches: [],
    })

    // Compile function body
    compile_expr(ctx, mod_info, code.body)

    // Pop implicit function block and patch branches
    let func_frame_idx = ctx.control_stack.length() - 1
    let func_frame = ctx.control_stack.pop().unwrap()
    let end_pc = ctx.code.length()
    for patch_pos in func_frame.pending_patches {
      ctx.code[patch_pos] = end_pc.to_int64()
    }
    for block in ctx.deferred_blocks {
      if not(block.is_loop) &&
        not(block.resolved) &&
        block.target_label == func_frame_idx {
        block.end_pc = end_pc
        block.resolved = true
      }
    }

    // Emit implicit return/end
    ctx.emit_op(@core.OpTag::End)
    ctx.emit_idx(num_results)

    // Emit deferred resolution blocks
    ctx.emit_deferred_blocks()
  }

  // Patch forward call targets
  for patch in ctx.call_patches {
    ctx.code[patch.patch_pos] = func_entries[patch.func_idx].to_int64()
  }

  // Collect function exports
  let exports : Map[String, Int] = {}
  for exp in mod_.exports {
    if exp.desc is Func(idx) {
      let abs_idx = idx.reinterpret_as_int()
      if abs_idx < num_imported_funcs {
        let name = @utf8.decode(exp.name) catch { _ => continue }
        exports[name] = -(abs_idx + 1)
      } else {
        let local_idx = abs_idx - num_imported_funcs
        let name = @utf8.decode(exp.name) catch { _ => continue }
        exports[name] = local_idx
      }
    }
  }
  {
    code: ctx.code,
    func_entries,
    func_num_locals,
    func_num_params,
    func_num_results,
    func_max_stack,
    exports,
    version: @core.compiled_module_version,
  }
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
      ctx.emit_op(@core.OpTag::Unreachable)
      ctx.is_unreachable = true
    }
    Nop => ()
    Return => {
      ctx.emit_op(@core.OpTag::Return)
      ctx.emit_idx(ctx.num_results)
      ctx.is_unreachable = true
    }

    // Constants
    I32Const(n) => {
      ctx.emit_op(@core.OpTag::I32Const)
      ctx.emit_i32(n)
      ignore(ctx.push_slot())
    }
    I64Const(n) => {
      ctx.emit_op(@core.OpTag::I64Const)
      ctx.emit_i64(n)
      ignore(ctx.push_slot())
    }
    F32Const(f) => {
      ctx.emit_op(@core.OpTag::F32Const)
      ctx.emit_i64(f.reinterpret_as_uint().to_uint64())
      ignore(ctx.push_slot())
    }
    F64Const(f) => {
      ctx.emit_op(@core.OpTag::F64Const)
      ctx.emit_i64(f.reinterpret_as_uint64())
      ignore(ctx.push_slot())
    }

    // Locals
    LocalGet(idx) => {
      ctx.emit_op(@core.OpTag::LocalGet)
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    LocalSet(idx) => {
      ctx.emit_op(@core.OpTag::LocalSet)
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.pop_slot())
    }
    LocalTee(idx) => {
      ctx.emit_op(@core.OpTag::LocalTee)
      ctx.emit_idx(idx.reinterpret_as_int())
    }

    // Globals
    GlobalGet(idx) => {
      ctx.emit_op(@core.OpTag::GlobalGet)
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    GlobalSet(idx) => {
      ctx.emit_op(@core.OpTag::GlobalSet)
      ctx.emit_idx(idx.reinterpret_as_int())
      ignore(ctx.pop_slot())
    }

    // i32 arithmetic
    I32Add => ctx.emit_binary_op(@core.OpTag::I32Add)
    I32Sub => ctx.emit_binary_op(@core.OpTag::I32Sub)
    I32Mul => ctx.emit_binary_op(@core.OpTag::I32Mul)
    I32DivS => ctx.emit_binary_op(@core.OpTag::I32DivS)
    I32DivU => ctx.emit_binary_op(@core.OpTag::I32DivU)
    I32RemS => ctx.emit_binary_op(@core.OpTag::I32RemS)
    I32RemU => ctx.emit_binary_op(@core.OpTag::I32RemU)
    I32And => ctx.emit_binary_op(@core.OpTag::I32And)
    I32Or => ctx.emit_binary_op(@core.OpTag::I32Or)
    I32Xor => ctx.emit_binary_op(@core.OpTag::I32Xor)
    I32Shl => ctx.emit_binary_op(@core.OpTag::I32Shl)
    I32ShrS => ctx.emit_binary_op(@core.OpTag::I32ShrS)
    I32ShrU => ctx.emit_binary_op(@core.OpTag::I32ShrU)
    I32Rotl => ctx.emit_binary_op(@core.OpTag::I32Rotl)
    I32Rotr => ctx.emit_binary_op(@core.OpTag::I32Rotr)

    // i32 comparison
    I32Eqz => ctx.emit_unary_op(@core.OpTag::I32Eqz)
    I32Eq => ctx.emit_binary_op(@core.OpTag::I32Eq)
    I32Ne => ctx.emit_binary_op(@core.OpTag::I32Ne)
    I32LtS => ctx.emit_binary_op(@core.OpTag::I32LtS)
    I32LtU => ctx.emit_binary_op(@core.OpTag::I32LtU)
    I32GtS => ctx.emit_binary_op(@core.OpTag::I32GtS)
    I32GtU => ctx.emit_binary_op(@core.OpTag::I32GtU)
    I32LeS => ctx.emit_binary_op(@core.OpTag::I32LeS)
    I32LeU => ctx.emit_binary_op(@core.OpTag::I32LeU)
    I32GeS => ctx.emit_binary_op(@core.OpTag::I32GeS)
    I32GeU => ctx.emit_binary_op(@core.OpTag::I32GeU)

    // i32 unary
    I32Clz => ctx.emit_unary_op(@core.OpTag::I32Clz)
    I32Ctz => ctx.emit_unary_op(@core.OpTag::I32Ctz)
    I32Popcnt => ctx.emit_unary_op(@core.OpTag::I32Popcnt)

    // i64 arithmetic
    I64Add => ctx.emit_binary_op(@core.OpTag::I64Add)
    I64Sub => ctx.emit_binary_op(@core.OpTag::I64Sub)
    I64Mul => ctx.emit_binary_op(@core.OpTag::I64Mul)
    I64DivS => ctx.emit_binary_op(@core.OpTag::I64DivS)
    I64DivU => ctx.emit_binary_op(@core.OpTag::I64DivU)
    I64RemS => ctx.emit_binary_op(@core.OpTag::I64RemS)
    I64RemU => ctx.emit_binary_op(@core.OpTag::I64RemU)
    I64And => ctx.emit_binary_op(@core.OpTag::I64And)
    I64Or => ctx.emit_binary_op(@core.OpTag::I64Or)
    I64Xor => ctx.emit_binary_op(@core.OpTag::I64Xor)
    I64Shl => ctx.emit_binary_op(@core.OpTag::I64Shl)
    I64ShrS => ctx.emit_binary_op(@core.OpTag::I64ShrS)
    I64ShrU => ctx.emit_binary_op(@core.OpTag::I64ShrU)
    I64Rotl => ctx.emit_binary_op(@core.OpTag::I64Rotl)
    I64Rotr => ctx.emit_binary_op(@core.OpTag::I64Rotr)

    // i64 comparison
    I64Eqz => ctx.emit_unary_op(@core.OpTag::I64Eqz)
    I64Eq => ctx.emit_binary_op(@core.OpTag::I64Eq)
    I64Ne => ctx.emit_binary_op(@core.OpTag::I64Ne)
    I64LtS => ctx.emit_binary_op(@core.OpTag::I64LtS)
    I64LtU => ctx.emit_binary_op(@core.OpTag::I64LtU)
    I64GtS => ctx.emit_binary_op(@core.OpTag::I64GtS)
    I64GtU => ctx.emit_binary_op(@core.OpTag::I64GtU)
    I64LeS => ctx.emit_binary_op(@core.OpTag::I64LeS)
    I64LeU => ctx.emit_binary_op(@core.OpTag::I64LeU)
    I64GeS => ctx.emit_binary_op(@core.OpTag::I64GeS)
    I64GeU => ctx.emit_binary_op(@core.OpTag::I64GeU)

    // i64 unary
    I64Clz => ctx.emit_unary_op(@core.OpTag::I64Clz)
    I64Ctz => ctx.emit_unary_op(@core.OpTag::I64Ctz)
    I64Popcnt => ctx.emit_unary_op(@core.OpTag::I64Popcnt)

    // f32 arithmetic
    F32Add => ctx.emit_binary_op(@core.OpTag::F32Add)
    F32Sub => ctx.emit_binary_op(@core.OpTag::F32Sub)
    F32Mul => ctx.emit_binary_op(@core.OpTag::F32Mul)
    F32Div => ctx.emit_binary_op(@core.OpTag::F32Div)
    F32Min => ctx.emit_binary_op(@core.OpTag::F32Min)
    F32Max => ctx.emit_binary_op(@core.OpTag::F32Max)
    F32Copysign => ctx.emit_binary_op(@core.OpTag::F32Copysign)

    // f32 comparison
    F32Eq => ctx.emit_binary_op(@core.OpTag::F32Eq)
    F32Ne => ctx.emit_binary_op(@core.OpTag::F32Ne)
    F32Lt => ctx.emit_binary_op(@core.OpTag::F32Lt)
    F32Gt => ctx.emit_binary_op(@core.OpTag::F32Gt)
    F32Le => ctx.emit_binary_op(@core.OpTag::F32Le)
    F32Ge => ctx.emit_binary_op(@core.OpTag::F32Ge)

    // f32 unary
    F32Abs => ctx.emit_unary_op(@core.OpTag::F32Abs)
    F32Neg => ctx.emit_unary_op(@core.OpTag::F32Neg)
    F32Ceil => ctx.emit_unary_op(@core.OpTag::F32Ceil)
    F32Floor => ctx.emit_unary_op(@core.OpTag::F32Floor)
    F32Trunc => ctx.emit_unary_op(@core.OpTag::F32Trunc)
    F32Nearest => ctx.emit_unary_op(@core.OpTag::F32Nearest)
    F32Sqrt => ctx.emit_unary_op(@core.OpTag::F32Sqrt)

    // f64 arithmetic
    F64Add => ctx.emit_binary_op(@core.OpTag::F64Add)
    F64Sub => ctx.emit_binary_op(@core.OpTag::F64Sub)
    F64Mul => ctx.emit_binary_op(@core.OpTag::F64Mul)
    F64Div => ctx.emit_binary_op(@core.OpTag::F64Div)
    F64Min => ctx.emit_binary_op(@core.OpTag::F64Min)
    F64Max => ctx.emit_binary_op(@core.OpTag::F64Max)
    F64Copysign => ctx.emit_binary_op(@core.OpTag::F64Copysign)

    // f64 comparison
    F64Eq => ctx.emit_binary_op(@core.OpTag::F64Eq)
    F64Ne => ctx.emit_binary_op(@core.OpTag::F64Ne)
    F64Lt => ctx.emit_binary_op(@core.OpTag::F64Lt)
    F64Gt => ctx.emit_binary_op(@core.OpTag::F64Gt)
    F64Le => ctx.emit_binary_op(@core.OpTag::F64Le)
    F64Ge => ctx.emit_binary_op(@core.OpTag::F64Ge)

    // f64 unary
    F64Abs => ctx.emit_unary_op(@core.OpTag::F64Abs)
    F64Neg => ctx.emit_unary_op(@core.OpTag::F64Neg)
    F64Ceil => ctx.emit_unary_op(@core.OpTag::F64Ceil)
    F64Floor => ctx.emit_unary_op(@core.OpTag::F64Floor)
    F64Trunc => ctx.emit_unary_op(@core.OpTag::F64Trunc)
    F64Nearest => ctx.emit_unary_op(@core.OpTag::F64Nearest)
    F64Sqrt => ctx.emit_unary_op(@core.OpTag::F64Sqrt)

    // Conversions
    I32WrapI64 => ctx.emit_unary_op(@core.OpTag::I32WrapI64)
    I32TruncF32S => ctx.emit_unary_op(@core.OpTag::I32TruncF32S)
    I32TruncF32U => ctx.emit_unary_op(@core.OpTag::I32TruncF32U)
    I32TruncF64S => ctx.emit_unary_op(@core.OpTag::I32TruncF64S)
    I32TruncF64U => ctx.emit_unary_op(@core.OpTag::I32TruncF64U)
    I64ExtendI32S => ctx.emit_unary_op(@core.OpTag::I64ExtendI32S)
    I64ExtendI32U => ctx.emit_unary_op(@core.OpTag::I64ExtendI32U)
    I64TruncF32S => ctx.emit_unary_op(@core.OpTag::I64TruncF32S)
    I64TruncF32U => ctx.emit_unary_op(@core.OpTag::I64TruncF32U)
    I64TruncF64S => ctx.emit_unary_op(@core.OpTag::I64TruncF64S)
    I64TruncF64U => ctx.emit_unary_op(@core.OpTag::I64TruncF64U)
    I32TruncSatF32S => ctx.emit_unary_op(@core.OpTag::I32TruncSatF32S)
    I32TruncSatF32U => ctx.emit_unary_op(@core.OpTag::I32TruncSatF32U)
    I32TruncSatF64S => ctx.emit_unary_op(@core.OpTag::I32TruncSatF64S)
    I32TruncSatF64U => ctx.emit_unary_op(@core.OpTag::I32TruncSatF64U)
    I64TruncSatF32S => ctx.emit_unary_op(@core.OpTag::I64TruncSatF32S)
    I64TruncSatF32U => ctx.emit_unary_op(@core.OpTag::I64TruncSatF32U)
    I64TruncSatF64S => ctx.emit_unary_op(@core.OpTag::I64TruncSatF64S)
    I64TruncSatF64U => ctx.emit_unary_op(@core.OpTag::I64TruncSatF64U)
    F32ConvertI32S => ctx.emit_unary_op(@core.OpTag::F32ConvertI32S)
    F32ConvertI32U => ctx.emit_unary_op(@core.OpTag::F32ConvertI32U)
    F32ConvertI64S => ctx.emit_unary_op(@core.OpTag::F32ConvertI64S)
    F32ConvertI64U => ctx.emit_unary_op(@core.OpTag::F32ConvertI64U)
    F32DemoteF64 => ctx.emit_unary_op(@core.OpTag::F32DemoteF64)
    F64ConvertI32S => ctx.emit_unary_op(@core.OpTag::F64ConvertI32S)
    F64ConvertI32U => ctx.emit_unary_op(@core.OpTag::F64ConvertI32U)
    F64ConvertI64S => ctx.emit_unary_op(@core.OpTag::F64ConvertI64S)
    F64ConvertI64U => ctx.emit_unary_op(@core.OpTag::F64ConvertI64U)
    F64PromoteF32 => ctx.emit_unary_op(@core.OpTag::F64PromoteF32)
    I32ReinterpretF32 => ctx.emit_unary_op(@core.OpTag::I32ReinterpretF32)
    I64ReinterpretF64 => ctx.emit_unary_op(@core.OpTag::I64ReinterpretF64)
    F32ReinterpretI32 => ctx.emit_unary_op(@core.OpTag::F32ReinterpretI32)
    F64ReinterpretI64 => ctx.emit_unary_op(@core.OpTag::F64ReinterpretI64)

    // Sign extension
    I32Extend8S => ctx.emit_unary_op(@core.OpTag::I32Extend8S)
    I32Extend16S => ctx.emit_unary_op(@core.OpTag::I32Extend16S)
    I64Extend8S => ctx.emit_unary_op(@core.OpTag::I64Extend8S)
    I64Extend16S => ctx.emit_unary_op(@core.OpTag::I64Extend16S)
    I64Extend32S => ctx.emit_unary_op(@core.OpTag::I64Extend32S)

    // Stack operations
    Drop => {
      ctx.emit_op(@core.OpTag::Drop)
      ignore(ctx.pop_slot())
    }
    Select(_) | SelectTyped(_) => {
      ctx.emit_op(@core.OpTag::Select)
      ignore(ctx.pop_slot()) // condition
      ignore(ctx.pop_slot()) // val2
      ignore(ctx.pop_slot()) // val1
      ignore(ctx.push_slot()) // result
    }

    // Memory operations
    MemoryGrow(mem_idx) => {
      ctx.emit_op(@core.OpTag::MemoryGrow)
      ctx.emit_idx(mem_idx.reinterpret_as_int())
    }
    MemorySize(mem_idx) => {
      ctx.emit_op(@core.OpTag::MemorySize)
      ctx.emit_idx(mem_idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }

    // i32 load/store
    I32Load(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I32Load, offset, mem_idx)
    I32Store(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I32Store, offset, mem_idx)
    I32Load8S(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I32Load8S, offset, mem_idx)
    I32Load8U(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I32Load8U, offset, mem_idx)
    I32Load16S(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I32Load16S, offset, mem_idx)
    I32Load16U(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I32Load16U, offset, mem_idx)
    I32Store8(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I32Store8, offset, mem_idx)
    I32Store16(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I32Store16, offset, mem_idx)

    // i64 load/store
    I64Load(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load, offset, mem_idx)
    I64Load8S(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load8S, offset, mem_idx)
    I64Load8U(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load8U, offset, mem_idx)
    I64Load16S(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load16S, offset, mem_idx)
    I64Load16U(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load16U, offset, mem_idx)
    I64Load32S(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load32S, offset, mem_idx)
    I64Load32U(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::I64Load32U, offset, mem_idx)
    I64Store(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I64Store, offset, mem_idx)
    I64Store8(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I64Store8, offset, mem_idx)
    I64Store16(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I64Store16, offset, mem_idx)
    I64Store32(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::I64Store32, offset, mem_idx)

    // f32 load/store
    F32Load(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::F32Load, offset, mem_idx)
    F32Store(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::F32Store, offset, mem_idx)

    // f64 load/store
    F64Load(_, offset, mem_idx) =>
      ctx.emit_load(@core.OpTag::F64Load, offset, mem_idx)
    F64Store(_, offset, mem_idx) =>
      ctx.emit_store(@core.OpTag::F64Store, offset, mem_idx)

    // Bulk memory operations
    MemoryCopy(_, _) => {
      ctx.emit_op(@core.OpTag::MemoryCopy)
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // src
      ignore(ctx.pop_slot()) // dest
    }
    MemoryFill(_) => {
      ctx.emit_op(@core.OpTag::MemoryFill)
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // val
      ignore(ctx.pop_slot()) // dest
    }
    MemoryInit(data_idx, _) => {
      ctx.emit_op(@core.OpTag::MemoryInit)
      ctx.emit_idx(data_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // src
      ignore(ctx.pop_slot()) // dest
    }
    DataDrop(data_idx) => {
      ctx.emit_op(@core.OpTag::DataDrop)
      ctx.emit_idx(data_idx.reinterpret_as_int())
    }

    // Table operations
    TableCopy(dst_table_idx, src_table_idx) => {
      ctx.emit_op(@core.OpTag::TableCopy)
      ctx.emit_idx(dst_table_idx.reinterpret_as_int())
      ctx.emit_idx(src_table_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // src
      ignore(ctx.pop_slot()) // dest
    }
    TableFill(table_idx) => {
      ctx.emit_op(@core.OpTag::TableFill)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // val
      ignore(ctx.pop_slot()) // dest
    }
    TableInit(table_idx, elem_idx) => {
      ctx.emit_op(@core.OpTag::TableInit)
      ctx.emit_idx(elem_idx.reinterpret_as_int())
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // n
      ignore(ctx.pop_slot()) // src
      ignore(ctx.pop_slot()) // dest
    }
    ElemDrop(elem_idx) => {
      ctx.emit_op(@core.OpTag::ElemDrop)
      ctx.emit_idx(elem_idx.reinterpret_as_int())
    }
    TableGet(table_idx) => {
      ctx.emit_op(@core.OpTag::TableGet)
      ctx.emit_idx(table_idx.reinterpret_as_int())
    }
    TableSet(table_idx) => {
      ctx.emit_op(@core.OpTag::TableSet)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // i32 index
      ignore(ctx.pop_slot()) // ref value
    }
    TableSize(table_idx) => {
      ctx.emit_op(@core.OpTag::TableSize)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    TableGrow(table_idx) => {
      ctx.emit_op(@core.OpTag::TableGrow)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ignore(ctx.pop_slot()) // delta
    }

    // Block structures
    Block(bt, body) => {
      let arity = get_block_arity(mod_info.mod_, bt)
      ctx.push_control(Block, arity, 0)
      compile_expr(ctx, mod_info, { instrs: body })
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      let fallthrough_reachable = not(ctx.is_unreachable)
      if fallthrough_reachable {
        ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
      }
      let block_end_reachable = fallthrough_reachable ||
        frame.pending_patches.length() > 0
      ctx.pop_control()
      while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
        ignore(ctx.slot_stack.pop())
      }
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
      ctx.next_slot = frame.sp_at_entry + arity
      if block_end_reachable {
        ctx.is_unreachable = false
      }
    }
    Loop(bt, body) => {
      let (param_arity, _result_arity) = get_block_arities(mod_info.mod_, bt)
      let loop_start = ctx.code.length()
      let slot_stack_len = ctx.slot_stack.length()
      let param_slots : Array[Int] = []
      for i in 0..<param_arity {
        param_slots.push(ctx.slot_at(param_arity - 1 - i))
      }
      ctx.control_stack.push({
        kind: Loop,
        target_pc: loop_start,
        result_slots: param_slots,
        sp_at_entry: ctx.current_sp(),
        slot_stack_len_at_entry: slot_stack_len,
        pending_patches: [],
      })
      compile_expr(ctx, mod_info, { instrs: body })
      ctx.pop_control()
    }
    If(bt, then_body, else_body) => {
      ignore(ctx.pop_slot())
      let arity = get_block_arity(mod_info.mod_, bt)
      ctx.emit_op(@core.OpTag::If)
      let else_patch = ctx.code.length()
      ctx.emit_idx(0)
      ctx.push_control(If, arity, 0)
      let frame = ctx.control_stack[ctx.control_stack.length() - 1]
      compile_expr(ctx, mod_info, { instrs: then_body })
      let then_unreachable = ctx.is_unreachable
      if not(then_unreachable) {
        ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
      }
      if else_body.length() > 0 {
        let mut end_patch = 0
        if not(then_unreachable) {
          ctx.emit_op(@core.OpTag::Br)
          end_patch = ctx.code.length()
          ctx.emit_idx(0)
        }
        ctx.code[else_patch] = ctx.code.length().to_int64()
        while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
          ignore(ctx.slot_stack.pop())
        }
        let base_slot = frame.sp_at_entry - frame.slot_stack_len_at_entry
        while ctx.slot_stack.length() < frame.slot_stack_len_at_entry {
          ctx.slot_stack.push(base_slot + ctx.slot_stack.length())
        }
        ctx.next_slot = frame.sp_at_entry
        ctx.is_unreachable = false
        compile_expr(ctx, mod_info, { instrs: else_body })
        let else_unreachable = ctx.is_unreachable
        if not(else_unreachable) {
          ctx.emit_resolution(frame.result_slots, frame.sp_at_entry, false)
        }
        if not(then_unreachable) {
          ctx.code[end_patch] = ctx.code.length().to_int64()
        }
        ctx.is_unreachable = then_unreachable && else_unreachable
      } else {
        ctx.code[else_patch] = ctx.code.length().to_int64()
        ctx.is_unreachable = false
      }
      ctx.pop_control()
      while ctx.slot_stack.length() > frame.slot_stack_len_at_entry {
        ignore(ctx.slot_stack.pop())
      }
      for slot in frame.result_slots {
        ctx.slot_stack.push(slot)
      }
      ctx.next_slot = frame.sp_at_entry + arity
    }

    // Branches
    Br(label) => {
      let label_int = label.reinterpret_as_int()
      let is_loop = ctx.is_loop_target(label_int)
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      let arity = result_slots.length()
      ctx.emit_resolution(result_slots, target_sp, is_loop)
      ctx.emit_op(@core.OpTag::Br)
      if ctx.is_loop_target(label_int) {
        ctx.emit_idx(target_pc)
      } else {
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0)
        ctx.add_patch(label_int, patch_pos)
      }
      for _ in 0..<arity {
        ignore(ctx.pop_slot())
      }
      ctx.is_unreachable = true
    }
    BrIf(label) => {
      ignore(ctx.pop_slot())
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      let arity = result_slots.length()
      let src_slots = ctx.capture_result_slots(arity)
      ctx.emit_op(@core.OpTag::BrIf)
      let taken_patch = ctx.code.length()
      ctx.emit_idx(0)
      let not_taken_pc = ctx.code.length() + 1
      ctx.emit_idx(not_taken_pc)
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
      ignore(ctx.pop_slot())
      let default_int = default_label.reinterpret_as_int()
      let (_, default_result_slots, _) = ctx.get_branch_target(default_int)
      let arity = default_result_slots.length()
      let src_slots = ctx.capture_result_slots(arity)
      ctx.emit_op(@core.OpTag::BrTable)
      ctx.emit_idx(labels.length())
      let patches : Array[Int] = []
      for _ in labels {
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0)
        patches.push(patch_pos)
      }
      let default_patch = ctx.code.length()
      ctx.emit_idx(0)
      patches.push(default_patch)
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
      ctx.is_unreachable = true
    }

    // Function calls
    Call(func_idx_uint) => {
      let func_idx = func_idx_uint.reinterpret_as_int()
      let local_idx = func_idx - mod_info.num_imported_funcs
      if local_idx >= 0 && local_idx < mod_info.func_entries.length() {
        let num_params = mod_info.func_num_params[local_idx]
        let num_results = mod_info.func_num_results[local_idx]
        let frame_offset = if num_params > 0 {
          ctx.slot_at(num_params - 1)
        } else {
          ctx.current_sp()
        }
        for _ in 0..<num_params {
          ignore(ctx.pop_slot())
        }
        ctx.emit_op(@core.OpTag::Call)
        let patch_pos = ctx.code.length()
        ctx.emit_idx(0)
        ctx.emit_idx(frame_offset)
        ctx.emit_idx(num_params)
        ctx.emit_idx(num_results)
        ctx.call_patches.push({ patch_pos, func_idx: local_idx })
        for i in 0..<num_results {
          ctx.slot_stack.push(frame_offset + i)
        }
        ctx.next_slot = frame_offset + num_results
        ctx.emit_op(@core.OpTag::SetSp)
        ctx.emit_idx(ctx.current_sp())
      } else if func_idx >= 0 && func_idx < mod_info.num_imported_funcs {
        let type_idx = get_imported_func_type_idx(mod_info.mod_, func_idx)
        let func_type = get_func_type(mod_info.mod_, type_idx)
        let num_params = func_type.params.length()
        let num_results = func_type.results.length()
        let frame_offset = if num_params > 0 {
          ctx.slot_at(num_params - 1)
        } else {
          ctx.current_sp()
        }
        for _ in 0..<num_params {
          ignore(ctx.pop_slot())
        }
        ctx.emit_op(@core.OpTag::CallImport)
        ctx.emit_idx(func_idx)
        ctx.emit_idx(num_params)
        ctx.emit_idx(num_results)
        for i in 0..<num_results {
          ctx.slot_stack.push(frame_offset + i)
        }
        ctx.next_slot = frame_offset + num_results
        if num_results > 0 {
          ctx.emit_op(@core.OpTag::SetSp)
          ctx.emit_idx(ctx.current_sp())
        }
      }
    }
    CallIndirect(type_idx, table_idx) => {
      let type_int = type_idx.reinterpret_as_int()
      let func_type = get_func_type(mod_info.mod_, type_int)
      let num_params = func_type.params.length()
      let num_results = func_type.results.length()
      ignore(ctx.pop_slot())
      let frame_offset = if num_params > 0 {
        ctx.slot_at(num_params - 1)
      } else {
        ctx.current_sp()
      }
      for _ in 0..<num_params {
        ignore(ctx.pop_slot())
      }
      ctx.emit_op(@core.OpTag::CallIndirect)
      ctx.emit_idx(table_idx.reinterpret_as_int())
      ctx.emit_idx(type_int)
      ctx.emit_idx(num_params)
      ctx.emit_idx(num_results)
      for i in 0..<num_results {
        ctx.slot_stack.push(frame_offset + i)
      }
      ctx.next_slot = frame_offset + num_results
      ctx.emit_op(@core.OpTag::SetSp)
      ctx.emit_idx(ctx.current_sp())
    }

    // Reference types
    RefNull(ref_type) => {
      ctx.emit_op(@core.OpTag::RefNull)
      let type_code = encode_ref_type(ref_type)
      ctx.emit_idx(type_code)
      ignore(ctx.push_slot())
    }
    RefFunc(func_idx) => {
      ctx.emit_op(@core.OpTag::RefFunc)
      ctx.emit_idx(func_idx.reinterpret_as_int())
      ignore(ctx.push_slot())
    }
    RefIsNull => ctx.emit_op(@core.OpTag::RefIsNull)
    RefEq => {
      ctx.emit_op(@core.OpTag::RefEq)
      ignore(ctx.pop_slot())
    }
    RefAsNonNull => ctx.emit_op(@core.OpTag::RefAsNonNull)
    BrOnNull(label) => {
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      let arity = result_slots.length()
      ctx.emit_op(@core.OpTag::BrOnNull)
      let src_slots : Array[Int] = []
      for i in 0..<arity {
        src_slots.push(ctx.slot_at(arity - i))
      }
      let taken_patch = ctx.code.length()
      ctx.emit_idx(0)
      let not_taken_pc = ctx.code.length() + 1
      ctx.emit_idx(not_taken_pc)
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
    BrOnNonNull(label) => {
      let label_int = label.reinterpret_as_int()
      let (target_pc, result_slots, target_sp) = ctx.get_branch_target(
        label_int,
      )
      ctx.emit_op(@core.OpTag::BrOnNonNull)
      let arity = result_slots.length()
      let src_slots = ctx.capture_result_slots(arity)
      let taken_patch = ctx.code.length()
      ctx.emit_idx(0)
      let not_taken_pc = ctx.code.length() + 1
      ctx.emit_idx(not_taken_pc)
      ctx.defer_resolution(
        taken_patch,
        src_slots,
        result_slots,
        target_sp,
        label_int,
        ctx.is_loop_target(label_int),
        target_pc,
      )
      ignore(ctx.pop_slot())
    }
    CallRef(type_idx) => {
      let type_int = type_idx.reinterpret_as_int()
      let func_type = get_func_type(mod_info.mod_, type_int)
      let num_params = func_type.params.length()
      let num_results = func_type.results.length()
      ignore(ctx.pop_slot())
      let frame_offset = if num_params > 0 {
        ctx.slot_at(num_params - 1)
      } else {
        ctx.current_sp()
      }
      for _ in 0..<num_params {
        ignore(ctx.pop_slot())
      }
      ctx.emit_op(@core.OpTag::CallRef)
      ctx.emit_idx(type_int)
      ctx.emit_idx(num_results)
      for i in 0..<num_results {
        ctx.slot_stack.push(frame_offset + i)
      }
      ctx.next_slot = frame_offset + num_results
      if num_results > 0 {
        ctx.emit_op(@core.OpTag::SetSp)
        ctx.emit_idx(ctx.current_sp())
      }
    }

    // Unimplemented
    _ => ()
  }
}
