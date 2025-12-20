// ============================================================================
// Compilation
// ============================================================================

///|
fn Runtime::compile_wasm_instr(
  self : Runtime,
  ctx : CompileCtx,
  instr : @core.Instr,
) -> Unit raise RuntimeError {
  match instr {
    // Constants
    @core.Instr::I32Const(value) => {
      self.emit(WasmInstr(op_i32_const))
      ctx.push_type(@core.ValType::I32)
      self.emit(ImmediateI32(value))
    }
    // Arithmetic (binary: pop 2, push 1)
    @core.Instr::I32Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_add))
    }
    @core.Instr::I32Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_sub))
    }
    @core.Instr::I32Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_mul))
    }
    @core.Instr::I32DivS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_div_s))
    }
    @core.Instr::I32DivU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_div_u))
    }
    @core.Instr::I32RemS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rem_s))
    }
    @core.Instr::I32RemU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rem_u))
    }
    // Bitwise (binary: pop 2, push 1)
    @core.Instr::I32And => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_and))
    }
    @core.Instr::I32Or => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_or))
    }
    @core.Instr::I32Xor => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_xor))
    }
    @core.Instr::I32Shl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shl))
    }
    @core.Instr::I32ShrS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shr_s))
    }
    @core.Instr::I32ShrU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_shr_u))
    }
    @core.Instr::I32Rotl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rotl))
    }
    @core.Instr::I32Rotr => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_rotr))
    }
    // Comparison (binary: pop 2, push 1 i32)
    @core.Instr::I32Eq => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_eq))
    }
    @core.Instr::I32Ne => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ne))
    }
    @core.Instr::I32LtS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_lt_s))
    }
    @core.Instr::I32LtU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_lt_u))
    }
    @core.Instr::I32GtS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_gt_s))
    }
    @core.Instr::I32GtU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_gt_u))
    }
    @core.Instr::I32LeS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_le_s))
    }
    @core.Instr::I32LeU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_le_u))
    }
    @core.Instr::I32GeS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ge_s))
    }
    @core.Instr::I32GeU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i32_ge_u))
    }
    // Unary (pop 1, push 1)
    @core.Instr::I32Eqz => self.emit(WasmInstr(op_i32_eqz)) // i32 -> i32
    @core.Instr::I32Clz => self.emit(WasmInstr(op_i32_clz)) // i32 -> i32
    @core.Instr::I32Ctz => self.emit(WasmInstr(op_i32_ctz)) // i32 -> i32
    @core.Instr::I32Popcnt => self.emit(WasmInstr(op_i32_popcnt)) // i32 -> i32
    @core.Instr::I32Extend8S => self.emit(WasmInstr(op_i32_extend8_s)) // i32 -> i32
    @core.Instr::I32Extend16S => self.emit(WasmInstr(op_i32_extend16_s)) // i32 -> i32
    @core.Instr::I32WrapI64 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_wrap_i64))
    } // i64 -> i32
    // i64 Constants
    @core.Instr::I64Const(value) => {
      self.emit(WasmInstr(op_i64_const))
      // Split i64 into two i32 immediates
      self.emit(ImmediateI32((value & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((value >> 32).to_uint()))
      ctx.push_type(@core.ValType::I64)
    }
    // f32/f64 Constants
    @core.Instr::F32Const(value) => {
      self.emit(WasmInstr(op_f32_const))
      self.emit(ImmediateI32(value.reinterpret_as_uint()))
      ctx.push_type(@core.ValType::F32)
    }
    @core.Instr::F64Const(value) => {
      self.emit(WasmInstr(op_f64_const))
      let bits = value.reinterpret_as_uint64()
      self.emit(ImmediateI32((bits & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((bits >> 32).to_uint()))
      ctx.push_type(@core.ValType::F64)
    }
    // i64 Arithmetic (binary: pop 2, push 1)
    @core.Instr::I64Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_add))
    }
    @core.Instr::I64Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_sub))
    }
    @core.Instr::I64Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_mul))
    }
    @core.Instr::I64DivS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_div_s))
    }
    @core.Instr::I64DivU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_div_u))
    }
    @core.Instr::I64RemS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rem_s))
    }
    @core.Instr::I64RemU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rem_u))
    }
    // i64 Bitwise (binary: pop 2, push 1)
    @core.Instr::I64And => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_and))
    }
    @core.Instr::I64Or => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_or))
    }
    @core.Instr::I64Xor => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_xor))
    }
    @core.Instr::I64Shl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shl))
    }
    @core.Instr::I64ShrS => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shr_s))
    }
    @core.Instr::I64ShrU => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_shr_u))
    }
    @core.Instr::I64Rotl => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rotl))
    }
    @core.Instr::I64Rotr => {
      ctx.pop_type()
      self.emit(WasmInstr(op_i64_rotr))
    }
    // i64 Comparison (pop 2 i64, push 1 i32)
    @core.Instr::I64Eq => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_eq))
    }
    @core.Instr::I64Ne => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_ne))
    }
    @core.Instr::I64LtS => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_lt_s))
    }
    @core.Instr::I64LtU => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_lt_u))
    }
    @core.Instr::I64GtS => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_gt_s))
    }
    @core.Instr::I64GtU => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_gt_u))
    }
    @core.Instr::I64LeS => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_le_s))
    }
    @core.Instr::I64LeU => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_le_u))
    }
    @core.Instr::I64GeS => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_ge_s))
    }
    @core.Instr::I64GeU => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_ge_u))
    }
    // i64 Unary
    @core.Instr::I64Eqz => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i64_eqz))
    } // i64 -> i32
    @core.Instr::I64Clz => self.emit(WasmInstr(op_i64_clz)) // i64 -> i64
    @core.Instr::I64Ctz => self.emit(WasmInstr(op_i64_ctz)) // i64 -> i64
    @core.Instr::I64Popcnt => self.emit(WasmInstr(op_i64_popcnt)) // i64 -> i64
    @core.Instr::I64Extend8S => self.emit(WasmInstr(op_i64_extend8_s)) // i64 -> i64
    @core.Instr::I64Extend16S => self.emit(WasmInstr(op_i64_extend16_s)) // i64 -> i64
    @core.Instr::I64Extend32S => self.emit(WasmInstr(op_i64_extend32_s)) // i64 -> i64
    @core.Instr::I64ExtendI32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_extend_i32_s))
    } // i32 -> i64
    @core.Instr::I64ExtendI32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_extend_i32_u))
    } // i32 -> i64
    // Float comparisons (pop 2, push i32)
    @core.Instr::F32Eq => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_eq))
    }
    @core.Instr::F32Ne => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_ne))
    }
    @core.Instr::F32Lt => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_lt))
    }
    @core.Instr::F32Gt => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_gt))
    }
    @core.Instr::F32Le => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_le))
    }
    @core.Instr::F32Ge => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f32_ge))
    }
    @core.Instr::F64Eq => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_eq))
    }
    @core.Instr::F64Ne => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_ne))
    }
    @core.Instr::F64Lt => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_lt))
    }
    @core.Instr::F64Gt => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_gt))
    }
    @core.Instr::F64Le => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_le))
    }
    @core.Instr::F64Ge => {
      ctx.pop_types(2)
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_f64_ge))
    }
    // Float unary (same type in/out)
    @core.Instr::F32Neg => self.emit(WasmInstr(op_f32_neg))
    @core.Instr::F32Abs => self.emit(WasmInstr(op_f32_abs))
    @core.Instr::F32Sqrt => self.emit(WasmInstr(op_f32_sqrt))
    @core.Instr::F32Ceil => self.emit(WasmInstr(op_f32_ceil))
    @core.Instr::F32Floor => self.emit(WasmInstr(op_f32_floor))
    @core.Instr::F32Trunc => self.emit(WasmInstr(op_f32_trunc))
    @core.Instr::F32Nearest => self.emit(WasmInstr(op_f32_nearest))
    @core.Instr::F64Neg => self.emit(WasmInstr(op_f64_neg))
    @core.Instr::F64Abs => self.emit(WasmInstr(op_f64_abs))
    @core.Instr::F64Sqrt => self.emit(WasmInstr(op_f64_sqrt))
    @core.Instr::F64Ceil => self.emit(WasmInstr(op_f64_ceil))
    @core.Instr::F64Floor => self.emit(WasmInstr(op_f64_floor))
    @core.Instr::F64Trunc => self.emit(WasmInstr(op_f64_trunc))
    @core.Instr::F64Nearest => self.emit(WasmInstr(op_f64_nearest))
    // Float binary (pop 2, push 1)
    @core.Instr::F32Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_add))
    }
    @core.Instr::F32Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_sub))
    }
    @core.Instr::F32Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_mul))
    }
    @core.Instr::F32Div => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_div))
    }
    @core.Instr::F32Min => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_min))
    }
    @core.Instr::F32Max => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_max))
    }
    @core.Instr::F32Copysign => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f32_copysign))
    }
    @core.Instr::F64Add => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_add))
    }
    @core.Instr::F64Sub => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_sub))
    }
    @core.Instr::F64Mul => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_mul))
    }
    @core.Instr::F64Div => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_div))
    }
    @core.Instr::F64Min => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_min))
    }
    @core.Instr::F64Max => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_max))
    }
    @core.Instr::F64Copysign => {
      ctx.pop_type()
      self.emit(WasmInstr(op_f64_copysign))
    }
    // Float conversions
    @core.Instr::F64ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_convert_i64_u))
    }
    @core.Instr::F64ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_convert_i64_s))
    }
    @core.Instr::F64ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_convert_i32_u))
    }
    @core.Instr::F64ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_convert_i32_s))
    }
    @core.Instr::F64PromoteF32 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_promote_f32))
    }
    @core.Instr::F32DemoteF64 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_demote_f64))
    }
    @core.Instr::F32ConvertI32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_convert_i32_s))
    }
    @core.Instr::F32ConvertI32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_convert_i32_u))
    }
    @core.Instr::F32ConvertI64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_convert_i64_s))
    }
    @core.Instr::F32ConvertI64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_convert_i64_u))
    }
    // Truncations
    @core.Instr::I64TruncF64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_f64_s))
    }
    @core.Instr::I64TruncF64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_f64_u))
    }
    @core.Instr::I32TruncF32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_f32_s))
    }
    @core.Instr::I32TruncF32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_f32_u))
    }
    @core.Instr::I32TruncF64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_f64_s))
    }
    @core.Instr::I32TruncF64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_f64_u))
    }
    @core.Instr::I64TruncF32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_f32_s))
    }
    @core.Instr::I64TruncF32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_f32_u))
    }
    // Saturating truncations
    @core.Instr::I32TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f32_s))
    }
    @core.Instr::I32TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f32_u))
    }
    @core.Instr::I32TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f64_s))
    }
    @core.Instr::I32TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_trunc_sat_f64_u))
    }
    @core.Instr::I64TruncSatF32S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f32_s))
    }
    @core.Instr::I64TruncSatF32U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f32_u))
    }
    @core.Instr::I64TruncSatF64S => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f64_s))
    }
    @core.Instr::I64TruncSatF64U => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_trunc_sat_f64_u))
    }
    // Reinterpret (same size, different type)
    @core.Instr::I32ReinterpretF32 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_i32_reinterpret_f32))
    }
    @core.Instr::I64ReinterpretF64 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_reinterpret_f64))
    }
    @core.Instr::F32ReinterpretI32 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_reinterpret_i32))
    }
    @core.Instr::F64ReinterpretI64 => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_reinterpret_i64))
    }
    // Locals - we don't track local types here, just use a placeholder
    @core.Instr::LocalGet(_idx) => {
      self.emit(WasmInstr(op_local_get))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
      // We need to push the local's type, but we don't have access to it here
      // For simplicity, push @core.ValType::I32 as placeholder (the exact type doesn't matter for branch arity)
      ctx.push_type(@core.ValType::I32)
    }
    @core.Instr::LocalSet(_idx) => {
      ctx.pop_type()
      self.emit(WasmInstr(op_local_set))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    @core.Instr::LocalTee(_idx) => {
      // Tee keeps the value on stack
      self.emit(WasmInstr(op_local_tee))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    // Stack
    @core.Instr::Drop => {
      ctx.pop_type()
      self.emit(WasmInstr(op_drop))
    }
    @core.Instr::Select => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_select))
    } // pop 3, push 1 => net -2
    @core.Instr::SelectTyped(_types) => {
      // Runtime behavior is identical to untyped select
      ctx.pop_types(2)
      self.emit(WasmInstr(op_select))
    } // pop 3, push 1 => net -2
    @core.Instr::Nop => self.emit(WasmInstr(op_nop))
    @core.Instr::Unreachable => self.emit(WasmInstr(op_unreachable))
    // Control flow
    @core.Instr::Block(block_type, instrs) => {
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
    @core.Instr::Loop(block_type, instrs) => {
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
    @core.Instr::Br(label) => {
      let label_int = label.reinterpret_as_int()
      let arity = ctx.get_branch_arity(label_int)
      let drop_count = ctx.calc_drop_count(label_int, arity)
      self.emit(WasmInstr(op_br))
      // Emit target PC slot - for loops it's known, for blocks we need to patch
      let target_pc_slot = self.ops.length()
      if ctx.is_loop_target(label_int) {
        // @core.Instr::Loop target is known
        self.emit(ImmediateIdx(ctx.get_target_pc(label_int)))
      } else {
        // @core.Instr::Block/if target - emit placeholder and register for patching
        self.emit(ImmediateIdx(0))
        ctx.add_br_patch(label_int, target_pc_slot)
      }
      self.emit(ImmediateIdx(arity))
      self.emit(ImmediateIdx(drop_count))
    }
    @core.Instr::BrIf(label) => {
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
    @core.Instr::BrTable(labels, default_label) => {
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
    @core.Instr::BrOnNull(label) => {
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
      ctx.push_type(@core.ValType::FuncRef)
    }
    @core.Instr::BrOnNonNull(label) => {
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
    @core.Instr::If(block_type, then_instrs, else_instrs) => {
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
    @core.Instr::Call(func_idx) => {
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
    @core.Instr::Return => self.emit(WasmInstr(op_return))
    // Memory instructions (load: pop addr, push value; store: pop addr+value)
    @core.Instr::I32Load(_align, offset) => {
      // pop i32 addr, push i32 value
      self.emit(WasmInstr(op_i32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Store(_align, offset) => {
      ctx.pop_types(2) // pop addr and value
      self.emit(WasmInstr(op_i32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Load8S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Load8U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Load16S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Load16U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Store8(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i32_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I32Store16(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i32_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load8S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load8U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load16S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load16U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load32S(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load32_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Load32U(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I64)
      self.emit(WasmInstr(op_i64_load32_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Store8(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Store16(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::I64Store32(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_i64_store32))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::F32Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F32)
      self.emit(WasmInstr(op_f32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::F32Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_f32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::F64Load(_align, offset) => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::F64)
      self.emit(WasmInstr(op_f64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    @core.Instr::F64Store(_align, offset) => {
      ctx.pop_types(2)
      self.emit(WasmInstr(op_f64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    // Global instructions
    @core.Instr::GlobalGet(_idx) => {
      ctx.push_type(@core.ValType::I32) // Placeholder type
      self.emit(WasmInstr(op_global_get))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    @core.Instr::GlobalSet(_idx) => {
      ctx.pop_type()
      self.emit(WasmInstr(op_global_set))
      self.emit(ImmediateIdx(_idx.reinterpret_as_int()))
    }
    // Memory size and grow
    @core.Instr::MemorySize(_) => {
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_memory_size))
    }
    @core.Instr::MemoryGrow(_) => self.emit(WasmInstr(op_memory_grow)) // i32 -> i32

    // Bulk memory instructions
    @core.Instr::MemoryCopy => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_memory_copy))
    }
    @core.Instr::MemoryFill => {
      ctx.pop_types(3) // pop dest, val, n
      self.emit(WasmInstr(op_memory_fill))
    }
    @core.Instr::MemoryInit(data_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_memory_init))
      self.emit(ImmediateIdx(data_idx.reinterpret_as_int()))
    }
    @core.Instr::DataDrop(data_idx) => {
      self.emit(WasmInstr(op_data_drop))
      self.emit(ImmediateIdx(data_idx.reinterpret_as_int()))
    }

    // Table bulk operations
    @core.Instr::TableInit(table_idx, elem_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_table_init))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
      self.emit(ImmediateIdx(elem_idx.reinterpret_as_int()))
    }
    @core.Instr::TableCopy(dst_table_idx, src_table_idx) => {
      ctx.pop_types(3) // pop dest, src, n
      self.emit(WasmInstr(op_table_copy))
      self.emit(ImmediateIdx(dst_table_idx.reinterpret_as_int()))
      self.emit(ImmediateIdx(src_table_idx.reinterpret_as_int()))
    }
    @core.Instr::ElemDrop(elem_idx) => {
      self.emit(WasmInstr(op_elem_drop))
      self.emit(ImmediateIdx(elem_idx.reinterpret_as_int()))
    }

    // Table instructions
    @core.Instr::TableSize(table_idx) => {
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_table_size))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    @core.Instr::TableGet(table_idx) => {
      // pop i32 index, push ref
      self.emit(WasmInstr(op_table_get))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    @core.Instr::TableSet(table_idx) => {
      ctx.pop_types(2) // pop index and ref
      self.emit(WasmInstr(op_table_set))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    @core.Instr::TableGrow(table_idx) => {
      ctx.pop_type() // pop count, keep delta -> result
      self.emit(WasmInstr(op_table_grow))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    // Reference instructions
    @core.Instr::RefNull(_ref_type) => {
      ctx.push_type(@core.ValType::FuncRef) // Use @core.ValType::FuncRef as placeholder
      self.emit(WasmInstr(op_ref_null))
      // Encode the ref type as an immediate
      let type_idx = match _ref_type {
        @core.RefType::Func => 0
        @core.RefType::Extern => 1
        @core.RefType::Any => 2
        @core.RefType::Eq => 3
        @core.RefType::I31 => 4
        @core.RefType::Struct => 5
        @core.RefType::Array => 6
        @core.RefType::Exn => 7
        @core.RefType::None => 8
        @core.RefType::NoFunc => 9
        @core.RefType::NoExtern => 10
        @core.RefType::NoExn => 11
        @core.RefType::TypeIndex(idx) => idx
      }
      self.emit(ImmediateIdx(type_idx))
    }
    @core.Instr::RefFunc(func_idx) => {
      ctx.push_type(@core.ValType::FuncRef)
      self.emit(WasmInstr(op_ref_func))
      self.emit(ImmediateIdx(func_idx.reinterpret_as_int()))
    }
    @core.Instr::RefIsNull => {
      ctx.pop_type()
      ctx.push_type(@core.ValType::I32)
      self.emit(WasmInstr(op_ref_is_null))
    }
    // Indirect call
    @core.Instr::CallIndirect(type_idx, table_idx) => {
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
    @core.Instr::ReturnCall(func_idx) => {
      // Look up function signature to properly track types (same as @core.Instr::Call)
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
    @core.Instr::ReturnCallIndirect(type_idx, table_idx) => {
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
    @core.Instr::CallRef(type_idx) => {
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
    @core.Instr::ReturnCallRef(type_idx) => {
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
