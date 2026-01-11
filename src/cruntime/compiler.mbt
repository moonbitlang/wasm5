///|
/// Compile a module to threaded code for C runtime.
pub fn compile(mod_ : @core.Module) -> CompiledModule {
  let ctx = CompileCtx::new()

  // Compile all functions
  let func_entries : Array[Int] = []
  let func_num_locals : Array[Int] = []
  let func_max_stack : Array[Int] = []
  for i, code in mod_.codes {
    let entry = ctx.code.length()
    func_entries.push(entry)

    // Count locals (params + locals)
    let func_idx = count_imported_funcs(mod_) + i
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
  {
    code: FixedArray::from_array(ctx.code),
    func_entries: FixedArray::from_array(func_entries),
    func_num_locals: FixedArray::from_array(func_num_locals),
    func_max_stack: FixedArray::from_array(func_max_stack),
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
