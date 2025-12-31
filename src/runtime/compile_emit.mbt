// ============================================================================
// Compilation
// ============================================================================

///|
fn Compiler::compile_wasm_instr(
  self : Compiler,
  ctx : CompileCtx,
  instr : @core.Instr,
) -> Unit raise RuntimeError {
  match instr {
    // Constants
    I32Const(value) => {
      self.emit_fn(op_i32_const)
      ctx.push_type(I32)
      self.emit_i32(value)
    }
    // Arithmetic (binary: pop 2, push 1)
    I32Add => {
      ctx.pop_type()
      self.emit_fn(op_i32_add)
    }
    I32Sub => {
      ctx.pop_type()
      self.emit_fn(op_i32_sub)
    }
    I32Mul => {
      ctx.pop_type()
      self.emit_fn(op_i32_mul)
    }
    I32DivS => {
      ctx.pop_type()
      self.emit_fn(op_i32_div_s)
    }
    I32DivU => {
      ctx.pop_type()
      self.emit_fn(op_i32_div_u)
    }
    I32RemS => {
      ctx.pop_type()
      self.emit_fn(op_i32_rem_s)
    }
    I32RemU => {
      ctx.pop_type()
      self.emit_fn(op_i32_rem_u)
    }
    // Bitwise (binary: pop 2, push 1)
    I32And => {
      ctx.pop_type()
      self.emit_fn(op_i32_and)
    }
    I32Or => {
      ctx.pop_type()
      self.emit_fn(op_i32_or)
    }
    I32Xor => {
      ctx.pop_type()
      self.emit_fn(op_i32_xor)
    }
    I32Shl => {
      ctx.pop_type()
      self.emit_fn(op_i32_shl)
    }
    I32ShrS => {
      ctx.pop_type()
      self.emit_fn(op_i32_shr_s)
    }
    I32ShrU => {
      ctx.pop_type()
      self.emit_fn(op_i32_shr_u)
    }
    I32Rotl => {
      ctx.pop_type()
      self.emit_fn(op_i32_rotl)
    }
    I32Rotr => {
      ctx.pop_type()
      self.emit_fn(op_i32_rotr)
    }
    // Comparison (binary: pop 2, push 1 i32)
    I32Eq => {
      ctx.pop_type()
      self.emit_fn(op_i32_eq)
    }
    I32Ne => {
      ctx.pop_type()
      self.emit_fn(op_i32_ne)
    }
    I32LtS => {
      ctx.pop_type()
      self.emit_fn(op_i32_lt_s)
    }
    I32LtU => {
      ctx.pop_type()
      self.emit_fn(op_i32_lt_u)
    }
    I32GtS => {
      ctx.pop_type()
      self.emit_fn(op_i32_gt_s)
    }
    I32GtU => {
      ctx.pop_type()
      self.emit_fn(op_i32_gt_u)
    }
    I32LeS => {
      ctx.pop_type()
      self.emit_fn(op_i32_le_s)
    }
    I32LeU => {
      ctx.pop_type()
      self.emit_fn(op_i32_le_u)
    }
    I32GeS => {
      ctx.pop_type()
      self.emit_fn(op_i32_ge_s)
    }
    I32GeU => {
      ctx.pop_type()
      self.emit_fn(op_i32_ge_u)
    }
    // Unary (pop 1, push 1)
    I32Eqz => self.emit_fn(op_i32_eqz) // i32 -> i32
    I32Clz => self.emit_fn(op_i32_clz) // i32 -> i32
    I32Ctz => self.emit_fn(op_i32_ctz) // i32 -> i32
    I32Popcnt => self.emit_fn(op_i32_popcnt) // i32 -> i32
    I32Extend8S => self.emit_fn(op_i32_extend8_s) // i32 -> i32
    I32Extend16S => self.emit_fn(op_i32_extend16_s) // i32 -> i32
    I32WrapI64 => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_wrap_i64)
    } // i64 -> i32
    // i64 Constants
    I64Const(value) => {
      self.emit_fn(op_i64_const)
      // Split i64 into two i32 immediates
      self.emit_i32((value & 0xFFFFFFFFUL).to_uint())
      self.emit_i32((value >> 32).to_uint())
      ctx.push_type(I64)
    }
    // f32/f64 Constants
    F32Const(value) => {
      self.emit_fn(op_f32_const)
      self.emit_i32(value.reinterpret_as_uint())
      ctx.push_type(F32)
    }
    F64Const(value) => {
      self.emit_fn(op_f64_const)
      let bits = value.reinterpret_as_uint64()
      self.emit_i32((bits & 0xFFFFFFFFUL).to_uint())
      self.emit_i32((bits >> 32).to_uint())
      ctx.push_type(F64)
    }
    // i64 Arithmetic (binary: pop 2, push 1)
    I64Add => {
      ctx.pop_type()
      self.emit_fn(op_i64_add)
    }
    I64Sub => {
      ctx.pop_type()
      self.emit_fn(op_i64_sub)
    }
    I64Mul => {
      ctx.pop_type()
      self.emit_fn(op_i64_mul)
    }
    I64DivS => {
      ctx.pop_type()
      self.emit_fn(op_i64_div_s)
    }
    I64DivU => {
      ctx.pop_type()
      self.emit_fn(op_i64_div_u)
    }
    I64RemS => {
      ctx.pop_type()
      self.emit_fn(op_i64_rem_s)
    }
    I64RemU => {
      ctx.pop_type()
      self.emit_fn(op_i64_rem_u)
    }
    // i64 Bitwise (binary: pop 2, push 1)
    I64And => {
      ctx.pop_type()
      self.emit_fn(op_i64_and)
    }
    I64Or => {
      ctx.pop_type()
      self.emit_fn(op_i64_or)
    }
    I64Xor => {
      ctx.pop_type()
      self.emit_fn(op_i64_xor)
    }
    I64Shl => {
      ctx.pop_type()
      self.emit_fn(op_i64_shl)
    }
    I64ShrS => {
      ctx.pop_type()
      self.emit_fn(op_i64_shr_s)
    }
    I64ShrU => {
      ctx.pop_type()
      self.emit_fn(op_i64_shr_u)
    }
    I64Rotl => {
      ctx.pop_type()
      self.emit_fn(op_i64_rotl)
    }
    I64Rotr => {
      ctx.pop_type()
      self.emit_fn(op_i64_rotr)
    }
    // i64 Comparison (pop 2 i64, push 1 i32)
    I64Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_eq)
    }
    I64Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_ne)
    }
    I64LtS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_lt_s)
    }
    I64LtU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_lt_u)
    }
    I64GtS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_gt_s)
    }
    I64GtU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_gt_u)
    }
    I64LeS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_le_s)
    }
    I64LeU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_le_u)
    }
    I64GeS => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_ge_s)
    }
    I64GeU => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_i64_ge_u)
    }
    // i64 Unary
    I64Eqz => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i64_eqz)
    } // i64 -> i32
    I64Clz => self.emit_fn(op_i64_clz) // i64 -> i64
    I64Ctz => self.emit_fn(op_i64_ctz) // i64 -> i64
    I64Popcnt => self.emit_fn(op_i64_popcnt) // i64 -> i64
    I64Extend8S => self.emit_fn(op_i64_extend8_s) // i64 -> i64
    I64Extend16S => self.emit_fn(op_i64_extend16_s) // i64 -> i64
    I64Extend32S => self.emit_fn(op_i64_extend32_s) // i64 -> i64
    I64ExtendI32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_extend_i32_s)
    } // i32 -> i64
    I64ExtendI32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_extend_i32_u)
    } // i32 -> i64
    // Float comparisons (pop 2, push i32)
    F32Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_eq)
    }
    F32Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_ne)
    }
    F32Lt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_lt)
    }
    F32Gt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_gt)
    }
    F32Le => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_le)
    }
    F32Ge => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f32_ge)
    }
    F64Eq => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_eq)
    }
    F64Ne => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_ne)
    }
    F64Lt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_lt)
    }
    F64Gt => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_gt)
    }
    F64Le => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_le)
    }
    F64Ge => {
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_f64_ge)
    }
    // Float unary (same type in/out)
    F32Neg => self.emit_fn(op_f32_neg)
    F32Abs => self.emit_fn(op_f32_abs)
    F32Sqrt => self.emit_fn(op_f32_sqrt)
    F32Ceil => self.emit_fn(op_f32_ceil)
    F32Floor => self.emit_fn(op_f32_floor)
    F32Trunc => self.emit_fn(op_f32_trunc)
    F32Nearest => self.emit_fn(op_f32_nearest)
    F64Neg => self.emit_fn(op_f64_neg)
    F64Abs => self.emit_fn(op_f64_abs)
    F64Sqrt => self.emit_fn(op_f64_sqrt)
    F64Ceil => self.emit_fn(op_f64_ceil)
    F64Floor => self.emit_fn(op_f64_floor)
    F64Trunc => self.emit_fn(op_f64_trunc)
    F64Nearest => self.emit_fn(op_f64_nearest)
    // Float binary (pop 2, push 1)
    F32Add => {
      ctx.pop_type()
      self.emit_fn(op_f32_add)
    }
    F32Sub => {
      ctx.pop_type()
      self.emit_fn(op_f32_sub)
    }
    F32Mul => {
      ctx.pop_type()
      self.emit_fn(op_f32_mul)
    }
    F32Div => {
      ctx.pop_type()
      self.emit_fn(op_f32_div)
    }
    F32Min => {
      ctx.pop_type()
      self.emit_fn(op_f32_min)
    }
    F32Max => {
      ctx.pop_type()
      self.emit_fn(op_f32_max)
    }
    F32Copysign => {
      ctx.pop_type()
      self.emit_fn(op_f32_copysign)
    }
    F64Add => {
      ctx.pop_type()
      self.emit_fn(op_f64_add)
    }
    F64Sub => {
      ctx.pop_type()
      self.emit_fn(op_f64_sub)
    }
    F64Mul => {
      ctx.pop_type()
      self.emit_fn(op_f64_mul)
    }
    F64Div => {
      ctx.pop_type()
      self.emit_fn(op_f64_div)
    }
    F64Min => {
      ctx.pop_type()
      self.emit_fn(op_f64_min)
    }
    F64Max => {
      ctx.pop_type()
      self.emit_fn(op_f64_max)
    }
    F64Copysign => {
      ctx.pop_type()
      self.emit_fn(op_f64_copysign)
    }
    // Float conversions
    F64ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_convert_i64_u)
    }
    F64ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_convert_i64_s)
    }
    F64ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_convert_i32_u)
    }
    F64ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_convert_i32_s)
    }
    F64PromoteF32 => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_promote_f32)
    }
    F32DemoteF64 => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_demote_f64)
    }
    F32ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_convert_i32_s)
    }
    F32ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_convert_i32_u)
    }
    F32ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_convert_i64_s)
    }
    F32ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_convert_i64_u)
    }
    // Truncations
    I64TruncF64S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_f64_s)
    }
    I64TruncF64U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_f64_u)
    }
    I32TruncF32S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_f32_s)
    }
    I32TruncF32U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_f32_u)
    }
    I32TruncF64S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_f64_s)
    }
    I32TruncF64U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_f64_u)
    }
    I64TruncF32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_f32_s)
    }
    I64TruncF32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_f32_u)
    }
    // Saturating truncations
    I32TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_sat_f32_s)
    }
    I32TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_sat_f32_u)
    }
    I32TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_sat_f64_s)
    }
    I32TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_trunc_sat_f64_u)
    }
    I64TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_sat_f32_s)
    }
    I64TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_sat_f32_u)
    }
    I64TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_sat_f64_s)
    }
    I64TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_trunc_sat_f64_u)
    }
    // Reinterpret (same size, different type)
    I32ReinterpretF32 => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_i32_reinterpret_f32)
    }
    I64ReinterpretF64 => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_reinterpret_f64)
    }
    F32ReinterpretI32 => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_reinterpret_i32)
    }
    F64ReinterpretI64 => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_reinterpret_i64)
    }
    // Locals - we don't track local types here, just use a placeholder
    LocalGet(_idx) => {
      self.emit_fn(op_local_get)
      self.emit_idx(_idx.reinterpret_as_int())
      // We need to push the local's type, but we don't have access to it here
      // For simplicity, push I32 as placeholder (the exact type doesn't matter for branch arity)
      ctx.push_type(I32)
    }
    LocalSet(_idx) => {
      ctx.pop_type()
      self.emit_fn(op_local_set)
      self.emit_idx(_idx.reinterpret_as_int())
    }
    LocalTee(_idx) => {
      // Tee keeps the value on stack
      self.emit_fn(op_local_tee)
      self.emit_idx(_idx.reinterpret_as_int())
    }
    // Stack
    Drop => {
      ctx.pop_type()
      self.emit_fn(op_drop)
    }
    Select => {
      ctx.pop_types(2)
      self.emit_fn(op_select)
    } // pop 3, push 1 => net -2
    SelectTyped(_types) => {
      // Runtime behavior is identical to untyped select
      ctx.pop_types(2)
      self.emit_fn(op_select)
    } // pop 3, push 1 => net -2
    Nop => self.emit_fn(op_nop)
    Unreachable => self.emit_fn(op_unreachable)
    Throw(tag_idx) => {
      let tag_idx_int = tag_idx.reinterpret_as_int()
      let num_imported = count_imported_tags(self.module_)
      let type_idx = get_tag_type_idx(self.module_, tag_idx_int, num_imported)
      if type_idx >= 0 {
        let tag_type = require_func_type(self.module_, type_idx, "throw")
        ctx.pop_types(tag_type.params.length())
      }
      self.emit_fn(op_throw)
      self.emit_idx(tag_idx_int)
    }
    Rethrow(label_idx) => {
      self.emit_fn(op_rethrow)
      self.emit_idx(label_idx.reinterpret_as_int())
    }
    Simd(simd) => {
      match @core.simd_spec_by_opcode(simd.opcode) {
        Some(spec) =>
          match @core.simd_stack_effect(spec.name) {
            Const => ctx.push_type(V128)
            Load => {
              ctx.pop_type()
              ctx.push_type(V128)
            }
            Store => ctx.pop_types(2)
            LoadLane => {
              ctx.pop_types(2)
              ctx.push_type(V128)
            }
            StoreLane => ctx.pop_types(2)
            Unary => {
              ctx.pop_type()
              ctx.push_type(V128)
            }
            Binary => {
              ctx.pop_types(2)
              ctx.push_type(V128)
            }
            Ternary => {
              ctx.pop_types(3)
              ctx.push_type(V128)
            }
            Shift => {
              ctx.pop_types(2)
              ctx.push_type(V128)
            }
            ToI32 => {
              ctx.pop_type()
              ctx.push_type(I32)
            }
            Splat(_t) => {
              ctx.pop_type()
              ctx.push_type(V128)
            }
            Extract(t) => {
              ctx.pop_type()
              ctx.push_type(t)
            }
            Replace(_t) => {
              ctx.pop_types(2)
              ctx.push_type(V128)
            }
          }
        None => ()
      }
      self.emit_fn(op_simd_unimplemented)
    }
    Atomic(atomic_instr) => {
      match @core.atomic_spec_by_opcode(atomic_instr.opcode) {
        Some(spec) =>
          match @core.atomic_stack_effect(spec.name) {
            Fence => ()
            Notify => {
              ctx.pop_types(2)
              ctx.push_type(I32)
            }
            Wait32 => {
              ctx.pop_types(3)
              ctx.push_type(I32)
            }
            Wait64 => {
              ctx.pop_types(3)
              ctx.push_type(I32)
            }
            Load(t, _size) => {
              ctx.pop_type()
              ctx.push_type(t)
            }
            Store(_t, _size) => ctx.pop_types(2)
            Rmw(t, _size) => {
              ctx.pop_types(2)
              ctx.push_type(t)
            }
            Cmpxchg(t, _size) => {
              ctx.pop_types(3)
              ctx.push_type(t)
            }
          }
        None => ()
      }
      self.emit_fn(op_atomic_unimplemented)
    }
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
        self.ops[slot] = end_pc.to_int64().reinterpret_as_uint64()
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
      self.emit_fn(op_br)
      // Emit target PC slot - for loops it's known, for blocks we need to patch
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        // Loop target is known
        self.emit_idx(ctx.get_target_pc(label_int))
      } else {
        // Block/if target - emit placeholder and register for patching
        self.emit_idx(0)
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit_idx(arity)
      self.emit_idx(drop_count)
    }
    BrIf(label) => {
      ctx.pop_type() // Pop condition
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit_fn(op_br_if)
      // Emit target PC slot
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit_idx(ctx.get_target_pc(label_int))
      } else {
        self.emit_idx(0)
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit_idx(arity)
      self.emit_idx(drop_count)
    }
    BrTable(labels, default_label) => {
      ctx.pop_type() // Pop index
      // Use default label for arity calculation (all must have same arity per validation)
      let default_int = default_label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(default_int)
      self.emit_fn(op_br_table)
      self.emit_idx(labels.length())
      self.emit_idx(arity)
      // For each label, emit target_pc + drop_count
      for label in labels {
        let label_int = label.reinterpret_as_int()
        let drop_count = ctx.calc_drop_count(label_int, arity)
        let target_pc_slot = self.ops.length()
        if ctx.is_loop_target(label_int) {
          self.emit_idx(ctx.get_target_pc(label_int))
        } else {
          self.emit_idx(0)
          ctx.add_br_patch(label_int, target_pc_slot)
        }
        self.emit_idx(drop_count)
      }
      // Default label
      let default_drop = ctx.calc_drop_count(default_int, arity)
      let default_pc_slot = self.ops.length()
      if ctx.is_loop_target(default_int) {
        self.emit_idx(ctx.get_target_pc(default_int))
      } else {
        self.emit_idx(0)
        ctx.add_br_patch(default_int, default_pc_slot)
      }
      self.emit_idx(default_drop)
    }
    BrOnNull(label) => {
      // br_on_null: branch if ref is null, leaving ref on stack if not null
      ctx.pop_type() // Pop the reference type
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit_fn(op_br_on_null)
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit_idx(ctx.get_target_pc(label_int))
      } else {
        self.emit_idx(0)
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit_idx(arity)
      self.emit_idx(drop_count)
      // In fallthrough case, ref is pushed back
      ctx.push_type(FuncRef)
    }
    BrOnNonNull(label) => {
      // br_on_non_null: branch if ref is not null
      // Calculate arity and drop_count BEFORE popping the ref type,
      // because at runtime the ref will be pushed back before the shuffle
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      ctx.pop_type() // Pop the reference type
      self.emit_fn(op_br_on_non_null)
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        self.emit_idx(ctx.get_target_pc(label_int))
      } else {
        self.emit_idx(0)
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit_idx(arity)
      self.emit_idx(drop_count)
      // In fallthrough case (null), ref is discarded
    }
    If(block_type, then_instrs, else_instrs) => {
      ctx.pop_type() // Pop condition
      let (params, results) = get_compile_block_type(self.module_, block_type)
      // Push control frame - target_pc is 0 (placeholder), will be patched at if end
      ctx.push_control(IfKind, params, results, 0)
      let entry_height = ctx.control_stack[ctx.control_stack.length() - 1].stack_height_at_entry
      // Emit if instruction with placeholder for else branch
      self.emit_fn(op_if)
      let else_pc_slot = self.ops.length()
      self.emit_idx(0)
      // Compile then branch
      for instr in then_instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      // Emit jump over else branch (unconditional)
      self.emit_fn(op_br)
      let end_jump_slot = self.ops.length()
      self.emit_idx(0) // Will be patched to end
      self.emit_idx(results.length()) // arity = results
      self.emit_idx(0) // drop_count = 0 (then branch should have correct stack)
      // Patch else_pc to point here
      let else_start = self.ops.length()
      self.ops[else_pc_slot] = else_start.to_int64().reinterpret_as_uint64()
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
      self.ops[end_jump_slot] = end_pc.to_int64().reinterpret_as_uint64()
      // Pop control frame and patch all pending branches from inside the if
      let block = ctx.pop_control()
      for slot in block.pending_br_patches {
        self.ops[slot] = end_pc.to_int64().reinterpret_as_uint64()
      }
      ctx.truncate_stack(block.stack_height_at_entry)
      ctx.push_types(block.results)
    }
    TryTable(block_type, _catches, instrs) => {
      let (params, results) = get_compile_block_type(self.module_, block_type)
      ctx.push_control(BlockKind, params, results, 0)
      for instr in instrs {
        self.compile_wasm_instr(ctx, instr)
      }
      let end_pc = self.ops.length()
      let block = ctx.pop_control()
      for slot in block.pending_br_patches {
        self.ops[slot] = end_pc.to_int64().reinterpret_as_uint64()
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
        let func_type = require_func_type(self.module_, type_idx, "call")
        // Pop params from type stack
        ctx.pop_types(func_type.params.length())
        // Push results to type stack
        for result_type in func_type.results {
          ctx.push_type(result_type)
        }
      }

      // Emit appropriate op based on whether function is imported or local
      if func_idx_int < num_imported {
        self.emit_fn(op_call_import)
        self.emit_idx(func_idx_int)
      } else {
        // Emit op_call_local with all immediates computed at compile time:
        // - callee_pc (or placeholder for forward ref)
        // - num_params
        // - num_locals
        // - max_stack_height
        let local_func_idx = func_idx_int - num_imported
        let code = self.module_.codes[local_func_idx]
        let func_type = require_func_type(self.module_, type_idx, "call")
        let num_params = func_type.params.length()
        let num_locals = num_params + code.locals.length()
        self.emit_fn(op_call_local)
        let callee_pc_slot = self.ops.length()
        match code.compiled {
          Some(callee_pc) => self.emit_idx(callee_pc)
          None => {
            // Forward reference - emit placeholder and record for patching
            self.emit_idx(0)
            self.pending_call_patches.push({
              local_func_idx,
              slot: callee_pc_slot,
            })
          }
        }
        self.emit_idx(num_params)
        self.emit_idx(num_locals)
        self.emit_idx(code.max_stack_height)
      }
    }
    Return => {
      self.emit_fn(op_return)
      self.emit_idx(ctx.func_result_count)
    }
    // Memory instructions (load: pop addr, push value; store: pop addr+value)
    I32Load(_align, offset, _mem_idx) => {
      // pop i32 addr, push i32 value
      self.emit_fn(op_i32_load)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Store(_align, offset, _mem_idx) => {
      ctx.pop_types(2) // pop addr and value
      self.emit_fn(op_i32_store)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Load8S(_align, offset, _mem_idx) => {
      self.emit_fn(op_i32_load8_s)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Load8U(_align, offset, _mem_idx) => {
      self.emit_fn(op_i32_load8_u)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Load16S(_align, offset, _mem_idx) => {
      self.emit_fn(op_i32_load16_s)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Load16U(_align, offset, _mem_idx) => {
      self.emit_fn(op_i32_load16_u)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Store8(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i32_store8)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I32Store16(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i32_store16)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Store(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i64_store)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load8S(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load8_s)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load8U(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load8_u)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load16S(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load16_s)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load16U(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load16_u)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load32S(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load32_s)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Load32U(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(I64)
      self.emit_fn(op_i64_load32_u)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Store8(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i64_store8)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Store16(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i64_store16)
      self.emit_idx(offset.reinterpret_as_int())
    }
    I64Store32(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_i64_store32)
      self.emit_idx(offset.reinterpret_as_int())
    }
    F32Load(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(F32)
      self.emit_fn(op_f32_load)
      self.emit_idx(offset.reinterpret_as_int())
    }
    F32Store(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_f32_store)
      self.emit_idx(offset.reinterpret_as_int())
    }
    F64Load(_align, offset, _mem_idx) => {
      ctx.pop_type()
      ctx.push_type(F64)
      self.emit_fn(op_f64_load)
      self.emit_idx(offset.reinterpret_as_int())
    }
    F64Store(_align, offset, _mem_idx) => {
      ctx.pop_types(2)
      self.emit_fn(op_f64_store)
      self.emit_idx(offset.reinterpret_as_int())
    }
    // Global instructions
    GlobalGet(_idx) => {
      ctx.push_type(I32) // Placeholder type
      self.emit_fn(op_global_get)
      self.emit_idx(_idx.reinterpret_as_int())
    }
    GlobalSet(_idx) => {
      ctx.pop_type()
      self.emit_fn(op_global_set)
      self.emit_idx(_idx.reinterpret_as_int())
    }
    // Memory size and grow
    MemorySize(_mem_idx) => {
      ctx.push_type(I32)
      self.emit_fn(op_memory_size)
    }
    MemoryGrow(_mem_idx) => self.emit_fn(op_memory_grow) // i32 -> i32

    // Bulk memory instructions
    MemoryCopy(_dst_idx, _src_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit_fn(op_memory_copy)
    }
    MemoryFill(_mem_idx) => {
      ctx.pop_types(3) // pop dest, val, n
      self.emit_fn(op_memory_fill)
    }
    MemoryInit(data_idx, _mem_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit_fn(op_memory_init)
      self.emit_idx(data_idx.reinterpret_as_int())
    }
    DataDrop(data_idx) => {
      self.emit_fn(op_data_drop)
      self.emit_idx(data_idx.reinterpret_as_int())
    }

    // Table bulk operations
    TableInit(table_idx, elem_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit_fn(op_table_init)
      self.emit_idx(table_idx.reinterpret_as_int())
      self.emit_idx(elem_idx.reinterpret_as_int())
    }
    TableCopy(dst_table_idx, src_table_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit_fn(op_table_copy)
      self.emit_idx(dst_table_idx.reinterpret_as_int())
      self.emit_idx(src_table_idx.reinterpret_as_int())
    }
    TableFill(table_idx) => {
      ctx.pop_types(3) // pop dest, val, n
      self.emit_fn(op_table_fill)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    ElemDrop(elem_idx) => {
      self.emit_fn(op_elem_drop)
      self.emit_idx(elem_idx.reinterpret_as_int())
    }

    // Table instructions
    TableSize(table_idx) => {
      ctx.push_type(I32)
      self.emit_fn(op_table_size)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    TableGet(table_idx) => {
      // pop i32 index, push ref
      self.emit_fn(op_table_get)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    TableSet(table_idx) => {
      ctx.pop_types(2) // pop index and ref
      self.emit_fn(op_table_set)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    TableGrow(table_idx) => {
      ctx.pop_type() // pop count, keep delta -> result
      self.emit_fn(op_table_grow)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    // Reference instructions
    RefNull(_ref_type) => {
      ctx.push_type(reftype_to_valtype(_ref_type))
      self.emit_fn(op_ref_null)
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
      self.emit_idx(type_idx)
    }
    RefFunc(func_idx) => {
      let func_idx_int = func_idx.reinterpret_as_int()
      let num_imported = count_imported_funcs(self.module_)
      let type_idx = get_func_type_idx(self.module_, func_idx_int, num_imported)
      if type_idx >= 0 {
        ctx.push_type(Ref(TypeIndex(type_idx), false))
      } else {
        ctx.push_type(FuncRef)
      }
      self.emit_fn(op_ref_func)
      self.emit_idx(func_idx.reinterpret_as_int())
    }
    RefIsNull => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_ref_is_null)
    }
    RefEq => {
      ctx.pop_type()
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_ref_eq)
    }
    RefAsNonNull => {
      let popped = ctx.pop_type_value()
      match popped {
        Some(val_type) => ctx.push_type(non_null_ref_type(val_type))
        None => ctx.push_type(Ref(Any, false))
      }
      self.emit_fn(op_ref_as_non_null)
    }
    RefTest(_ref_type, _nullable) => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    RefCast(ref_type, nullable) => {
      let target = reftype_to_valtype(ref_type)
      let result_type = if nullable {
        target
      } else {
        non_null_ref_type(target)
      }
      ctx.pop_type()
      ctx.push_type(result_type)
      self.emit_fn(op_gc_unimplemented)
    }
    StructNew(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let struct_type = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.new",
      )
      ctx.pop_types(struct_type.fields.length())
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    StructNewDefault(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.new_default",
      )
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    StructGet(type_idx, field_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let field_idx_int = field_idx.reinterpret_as_int()
      let struct_type = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.get",
      )
      if field_idx_int < 0 || field_idx_int >= struct_type.fields.length() {
        raise RuntimeError::InvalidType("struct.get: invalid field index")
      }
      let field = struct_type.fields[field_idx_int]
      ctx.pop_type()
      ctx.push_type(storage_value_type(field.storage))
      self.emit_fn(op_gc_unimplemented)
    }
    StructGetS(type_idx, field_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let field_idx_int = field_idx.reinterpret_as_int()
      let struct_type = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.get_s",
      )
      if field_idx_int < 0 || field_idx_int >= struct_type.fields.length() {
        raise RuntimeError::InvalidType("struct.get_s: invalid field index")
      }
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    StructGetU(type_idx, field_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let field_idx_int = field_idx.reinterpret_as_int()
      let struct_type = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.get_u",
      )
      if field_idx_int < 0 || field_idx_int >= struct_type.fields.length() {
        raise RuntimeError::InvalidType("struct.get_u: invalid field index")
      }
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    StructSet(type_idx, field_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let field_idx_int = field_idx.reinterpret_as_int()
      let struct_type = require_struct_type(
        self.module_,
        type_idx_int,
        "struct.set",
      )
      if field_idx_int < 0 || field_idx_int >= struct_type.fields.length() {
        raise RuntimeError::InvalidType("struct.set: invalid field index")
      }
      ctx.pop_types(2)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayNew(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.new")
      ctx.pop_types(2)
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayNewDefault(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(
        self.module_,
        type_idx_int,
        "array.new_default",
      )
      ctx.pop_type()
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayNewFixed(type_idx, len) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.new_fixed")
      ctx.pop_types(len.reinterpret_as_int())
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayNewData(type_idx, _data_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.new_data")
      ctx.pop_types(2)
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayNewElem(type_idx, _elem_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.new_elem")
      ctx.pop_types(2)
      ctx.push_type(Ref(TypeIndex(type_idx_int), false))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayGet(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let array_type = require_array_type(
        self.module_,
        type_idx_int,
        "array.get",
      )
      ctx.pop_types(2)
      ctx.push_type(storage_value_type(array_type.element.storage))
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayGetS(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.get_s")
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayGetU(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.get_u")
      ctx.pop_types(2)
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    ArraySet(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.set")
      ctx.pop_types(3)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayLen => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayFill(type_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.fill")
      ctx.pop_types(4)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayCopy(dst_type, src_type) => {
      let dst_int = dst_type.reinterpret_as_int()
      let src_int = src_type.reinterpret_as_int()
      let _ = require_array_type(self.module_, dst_int, "array.copy")
      let _ = require_array_type(self.module_, src_int, "array.copy")
      ctx.pop_types(5)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayInitData(type_idx, _data_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.init_data")
      ctx.pop_types(4)
      self.emit_fn(op_gc_unimplemented)
    }
    ArrayInitElem(type_idx, _elem_idx) => {
      let type_idx_int = type_idx.reinterpret_as_int()
      let _ = require_array_type(self.module_, type_idx_int, "array.init_elem")
      ctx.pop_types(4)
      self.emit_fn(op_gc_unimplemented)
    }
    BrOnCast(_label, _tref, _tnull, _sref, _snull) => {
      ctx.pop_type()
      ctx.push_type(Ref(Any, true))
      self.emit_fn(op_gc_unimplemented)
    }
    BrOnCastFail(_label, _tref, _tnull, _sref, _snull) => {
      ctx.pop_type()
      ctx.push_type(Ref(Any, true))
      self.emit_fn(op_gc_unimplemented)
    }
    AnyConvertExtern => {
      ctx.pop_type()
      ctx.push_type(AnyRef)
      self.emit_fn(op_gc_unimplemented)
    }
    ExternConvertAny => {
      ctx.pop_type()
      ctx.push_type(ExternRef)
      self.emit_fn(op_gc_unimplemented)
    }
    RefI31 => {
      ctx.pop_type()
      ctx.push_type(Ref(I31, false))
      self.emit_fn(op_gc_unimplemented)
    }
    I31GetS => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    I31GetU => {
      ctx.pop_type()
      ctx.push_type(I32)
      self.emit_fn(op_gc_unimplemented)
    }
    // Indirect call
    CallIndirect(type_idx, table_idx) => {
      // Pop table index (i32)
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = require_func_type(
        self.module_,
        type_idx_int,
        "call_indirect",
      )
      // Pop params from type stack
      ctx.pop_types(func_type.params.length())
      // Push results to type stack
      for result_type in func_type.results {
        ctx.push_type(result_type)
      }
      self.emit_fn(op_call_indirect)
      self.emit_idx(type_idx_int)
      self.emit_idx(table_idx.reinterpret_as_int())
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
        let func_type = require_func_type(self.module_, type_idx, "return_call")
        ctx.pop_types(func_type.params.length())
      }

      // Emit appropriate op based on whether function is imported or local
      if func_idx_int < num_imported {
        self.emit_fn(op_return_call_import)
        self.emit_idx(func_idx_int)
      } else {
        // Emit op_return_call_local with all immediates computed at compile time
        let local_func_idx = func_idx_int - num_imported
        let code = self.module_.codes[local_func_idx]
        let func_type = require_func_type(self.module_, type_idx, "return_call")
        let num_params = func_type.params.length()
        let num_locals = num_params + code.locals.length()
        self.emit_fn(op_return_call_local)
        let callee_pc_slot = self.ops.length()
        match code.compiled {
          Some(callee_pc) => self.emit_idx(callee_pc)
          None => {
            // Forward reference - emit placeholder and record for patching
            self.emit_idx(0)
            self.pending_call_patches.push({
              local_func_idx,
              slot: callee_pc_slot,
            })
          }
        }
        self.emit_idx(num_params)
        self.emit_idx(num_locals)
      }
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      // Pop table index (i32)
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = require_func_type(
        self.module_,
        type_idx_int,
        "return_call_indirect",
      )
      // Pop params from type stack (no results - tail call)
      ctx.pop_types(func_type.params.length())
      self.emit_fn(op_return_call_indirect)
      self.emit_idx(type_idx_int)
      self.emit_idx(table_idx.reinterpret_as_int())
    }
    // Typed function references
    CallRef(type_idx) => {
      // Pop the function reference
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = require_func_type(self.module_, type_idx_int, "call_ref")
      // Pop params from type stack
      ctx.pop_types(func_type.params.length())
      // Push results to type stack
      for result_type in func_type.results {
        ctx.push_type(result_type)
      }
      self.emit_fn(op_call_ref)
      self.emit_idx(type_idx_int)
    }
    ReturnCallRef(type_idx) => {
      // Pop the function reference
      ctx.pop_type()
      // Get function type to properly track types
      let type_idx_int = type_idx.reinterpret_as_int()
      let func_type = require_func_type(
        self.module_,
        type_idx_int,
        "return_call_ref",
      )
      // Pop params from type stack (no results - tail call)
      ctx.pop_types(func_type.params.length())
      self.emit_fn(op_return_call_ref)
      self.emit_idx(type_idx_int)
    }
  }
}

///|
fn reftype_to_valtype(ref_type : @core.RefType) -> @core.ValType {
  match ref_type {
    Func => FuncRef
    Extern => ExternRef
    Any => AnyRef
    Eq => EqRef
    I31 => I31Ref
    Struct => StructRef
    Array => ArrayRef
    Exn => ExnRef
    None => NullRef
    NoFunc => NullFuncRef
    NoExtern => NullExternRef
    NoExn => NullExnRef
    TypeIndex(_) => Ref(ref_type, true)
  }
}

///|
fn non_null_ref_type(val_type : @core.ValType) -> @core.ValType {
  match val_type {
    Ref(heap_type, true) => Ref(heap_type, false)
    Ref(heap_type, false) => Ref(heap_type, false)
    FuncRef => Ref(Func, false)
    ExternRef => Ref(Extern, false)
    AnyRef => Ref(Any, false)
    EqRef => Ref(Eq, false)
    I31Ref => Ref(I31, false)
    StructRef => Ref(Struct, false)
    ArrayRef => Ref(Array, false)
    ExnRef => Ref(Exn, false)
    NullRef => Ref(Any, false)
    NullFuncRef => Ref(Func, false)
    NullExternRef => Ref(Extern, false)
    NullExnRef => Ref(Exn, false)
    _ => val_type
  }
}
