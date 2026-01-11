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

    // Compile function body
    compile_expr(ctx, code.body)

    // Emit implicit return/end
    ctx.emit(end())

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
/// Compilation context
priv struct CompileCtx {
  code : Array[UInt64]
}

///|
fn CompileCtx::new() -> CompileCtx {
  { code: [] }
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
    Drop => ctx.emit(drop())
    Select(_) => ctx.emit(select())

    // Block structures - TODO: need proper control flow handling
    Block(_, body) => compile_expr(ctx, { instrs: body })
    Loop(_, body) => compile_expr(ctx, { instrs: body })
    If(_, then_body, else_body) => {
      // Simplified: just compile both branches sequentially for now
      // Real implementation needs branch handling
      compile_expr(ctx, { instrs: then_body })
      compile_expr(ctx, { instrs: else_body })
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
