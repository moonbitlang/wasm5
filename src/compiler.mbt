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
