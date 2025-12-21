///|
fn validate_instruction_numeric(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
) -> Bool raise @errors.ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    I32Const(_) => stack.push(I32)
    I64Const(_) => stack.push(I64)
    F32Const(_) => stack.push(F32)
    F64Const(_) => stack.push(F64)

    // Binary operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr => validate_binary_op(ctx, module_, I32, I32, "i32 binary op")

    // Comparison operations
    I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU => validate_binary_op(ctx, module_, I32, I32, "i32 comparison")

    // Unary operations
    I32Eqz | I32Clz | I32Ctz | I32Popcnt | I32Extend8S | I32Extend16S => {
      ctx.poly_pop_expect(module_, I32, "i32 unary op")
      stack.push(I32)
    }

    // i64 binary operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr => validate_binary_op(ctx, module_, I64, I64, "i64 binary op")

    // i64 comparison operations
    I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU => validate_binary_op(ctx, module_, I64, I32, "i64 comparison")

    // i64 test operation (returns i32)
    I64Eqz => {
      ctx.poly_pop_expect(module_, I64, "i64.eqz")
      stack.push(I32)
    }

    // i64 unary operations (return i64)
    I64Clz | I64Ctz | I64Popcnt | I64Extend8S | I64Extend16S | I64Extend32S => {
      ctx.poly_pop_expect(module_, I64, "i64 unary op")
      stack.push(I64)
    }

    // i32 to i64 conversion operations
    I64ExtendI32S | I64ExtendI32U => {
      ctx.poly_pop_expect(module_, I32, "i64 extension")
      stack.push(I64)
    }

    // i64 to i32 conversion (wrap)
    I32WrapI64 => {
      ctx.poly_pop_expect(module_, I64, "i32.wrap_i64")
      stack.push(I32)
    }

    // f32 comparison operations
    F32Eq | F32Ne | F32Lt | F32Gt | F32Le | F32Ge =>
      validate_binary_op(ctx, module_, F32, I32, "f32 comparison")

    // f64 comparison operations
    F64Eq | F64Ne | F64Lt | F64Gt | F64Le | F64Ge =>
      validate_binary_op(ctx, module_, F64, I32, "f64 comparison")

    // f32 unary operations
    F32Abs | F32Neg | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Sqrt => {
      ctx.poly_pop_expect(module_, F32, "f32 unary op")
      stack.push(F32)
    }

    // f64 unary operations
    F64Abs | F64Neg | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Sqrt => {
      ctx.poly_pop_expect(module_, F64, "f64 unary op")
      stack.push(F64)
    }

    // f32 binary operations
    F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign =>
      validate_binary_op(ctx, module_, F32, F32, "f32 binary op")

    // f64 binary operations
    F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign =>
      validate_binary_op(ctx, module_, F64, F64, "f64 binary op")

    // Conversion operations: i32 -> f32/f64
    F32ConvertI32S | F32ConvertI32U => {
      ctx.poly_pop_expect(module_, I32, "f32.convert_i32")
      stack.push(F32)
    }
    F64ConvertI32S | F64ConvertI32U => {
      ctx.poly_pop_expect(module_, I32, "f64.convert_i32")
      stack.push(F64)
    }

    // Conversion operations: i64 -> f32/f64
    F32ConvertI64S | F32ConvertI64U => {
      ctx.poly_pop_expect(module_, I64, "f32.convert_i64")
      stack.push(F32)
    }
    F64ConvertI64S | F64ConvertI64U => {
      ctx.poly_pop_expect(module_, I64, "f64.convert_i64")
      stack.push(F64)
    }

    // Promotion/demotion: f32 <-> f64
    F64PromoteF32 => {
      ctx.poly_pop_expect(module_, F32, "f64.promote_f32")
      stack.push(F64)
    }
    F32DemoteF64 => {
      ctx.poly_pop_expect(module_, F64, "f32.demote_f64")
      stack.push(F32)
    }

    // Truncation: f32/f64 -> i32/i64
    I32TruncF32S | I32TruncF32U => {
      ctx.poly_pop_expect(module_, F32, "i32.trunc_f32")
      stack.push(I32)
    }
    I32TruncF64S | I32TruncF64U => {
      ctx.poly_pop_expect(module_, F64, "i32.trunc_f64")
      stack.push(I32)
    }
    I64TruncF32S | I64TruncF32U => {
      ctx.poly_pop_expect(module_, F32, "i64.trunc_f32")
      stack.push(I64)
    }
    I64TruncF64S | I64TruncF64U => {
      ctx.poly_pop_expect(module_, F64, "i64.trunc_f64")
      stack.push(I64)
    }

    // Saturating truncation: f32/f64 -> i32/i64 (same types as regular trunc)
    I32TruncSatF32S | I32TruncSatF32U => {
      ctx.poly_pop_expect(module_, F32, "i32.trunc_sat_f32")
      stack.push(I32)
    }
    I32TruncSatF64S | I32TruncSatF64U => {
      ctx.poly_pop_expect(module_, F64, "i32.trunc_sat_f64")
      stack.push(I32)
    }
    I64TruncSatF32S | I64TruncSatF32U => {
      ctx.poly_pop_expect(module_, F32, "i64.trunc_sat_f32")
      stack.push(I64)
    }
    I64TruncSatF64S | I64TruncSatF64U => {
      ctx.poly_pop_expect(module_, F64, "i64.trunc_sat_f64")
      stack.push(I64)
    }

    // Reinterpret operations
    F32ReinterpretI32 => {
      ctx.poly_pop_expect(module_, I32, "f32.reinterpret_i32")
      stack.push(F32)
    }
    F64ReinterpretI64 => {
      ctx.poly_pop_expect(module_, I64, "f64.reinterpret_i64")
      stack.push(F64)
    }
    I32ReinterpretF32 => {
      ctx.poly_pop_expect(module_, F32, "i32.reinterpret_f32")
      stack.push(I32)
    }
    I64ReinterpretF64 => {
      ctx.poly_pop_expect(module_, F64, "i64.reinterpret_f64")
      stack.push(I64)
    }
    _ => return false
  }
  true
}
