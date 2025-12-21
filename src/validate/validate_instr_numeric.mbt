///|
fn validate_instruction_numeric(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
) -> Bool raise @core.ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    @core.Instr::I32Const(_) => stack.push(@core.ValType::I32)
    @core.Instr::I64Const(_) => stack.push(@core.ValType::I64)
    @core.Instr::F32Const(_) => stack.push(@core.ValType::F32)
    @core.Instr::F64Const(_) => stack.push(@core.ValType::F64)

    // Binary operations
    @core.Instr::I32Add
    | @core.Instr::I32Sub
    | @core.Instr::I32Mul
    | @core.Instr::I32DivS
    | @core.Instr::I32DivU
    | @core.Instr::I32RemS
    | @core.Instr::I32RemU
    | @core.Instr::I32And
    | @core.Instr::I32Or
    | @core.Instr::I32Xor
    | @core.Instr::I32Shl
    | @core.Instr::I32ShrS
    | @core.Instr::I32ShrU
    | @core.Instr::I32Rotl
    | @core.Instr::I32Rotr =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I32,
        @core.ValType::I32,
        "i32 binary op",
      )

    // Comparison operations
    @core.Instr::I32Eq
    | @core.Instr::I32Ne
    | @core.Instr::I32LtS
    | @core.Instr::I32LtU
    | @core.Instr::I32GtS
    | @core.Instr::I32GtU
    | @core.Instr::I32LeS
    | @core.Instr::I32LeU
    | @core.Instr::I32GeS
    | @core.Instr::I32GeU =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I32,
        @core.ValType::I32,
        "i32 comparison",
      )

    // Unary operations
    @core.Instr::I32Eqz
    | @core.Instr::I32Clz
    | @core.Instr::I32Ctz
    | @core.Instr::I32Popcnt
    | @core.Instr::I32Extend8S
    | @core.Instr::I32Extend16S => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "i32 unary op")
      stack.push(@core.ValType::I32)
    }

    // i64 binary operations
    @core.Instr::I64Add
    | @core.Instr::I64Sub
    | @core.Instr::I64Mul
    | @core.Instr::I64DivS
    | @core.Instr::I64DivU
    | @core.Instr::I64RemS
    | @core.Instr::I64RemU
    | @core.Instr::I64And
    | @core.Instr::I64Or
    | @core.Instr::I64Xor
    | @core.Instr::I64Shl
    | @core.Instr::I64ShrS
    | @core.Instr::I64ShrU
    | @core.Instr::I64Rotl
    | @core.Instr::I64Rotr =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I64,
        @core.ValType::I64,
        "i64 binary op",
      )

    // i64 comparison operations
    @core.Instr::I64Eq
    | @core.Instr::I64Ne
    | @core.Instr::I64LtS
    | @core.Instr::I64LtU
    | @core.Instr::I64GtS
    | @core.Instr::I64GtU
    | @core.Instr::I64LeS
    | @core.Instr::I64LeU
    | @core.Instr::I64GeS
    | @core.Instr::I64GeU =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I64,
        @core.ValType::I32,
        "i64 comparison",
      )

    // i64 test operation (returns i32)
    @core.Instr::I64Eqz => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i64.eqz")
      stack.push(@core.ValType::I32)
    }

    // i64 unary operations (return i64)
    @core.Instr::I64Clz
    | @core.Instr::I64Ctz
    | @core.Instr::I64Popcnt
    | @core.Instr::I64Extend8S
    | @core.Instr::I64Extend16S
    | @core.Instr::I64Extend32S => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i64 unary op")
      stack.push(@core.ValType::I64)
    }

    // i32 to i64 conversion operations
    @core.Instr::I64ExtendI32S | @core.Instr::I64ExtendI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "i64 extension")
      stack.push(@core.ValType::I64)
    }

    // i64 to i32 conversion (wrap)
    @core.Instr::I32WrapI64 => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i32.wrap_i64")
      stack.push(@core.ValType::I32)
    }

    // f32 comparison operations
    @core.Instr::F32Eq
    | @core.Instr::F32Ne
    | @core.Instr::F32Lt
    | @core.Instr::F32Gt
    | @core.Instr::F32Le
    | @core.Instr::F32Ge =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F32,
        @core.ValType::I32,
        "f32 comparison",
      )

    // f64 comparison operations
    @core.Instr::F64Eq
    | @core.Instr::F64Ne
    | @core.Instr::F64Lt
    | @core.Instr::F64Gt
    | @core.Instr::F64Le
    | @core.Instr::F64Ge =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F64,
        @core.ValType::I32,
        "f64 comparison",
      )

    // f32 unary operations
    @core.Instr::F32Abs
    | @core.Instr::F32Neg
    | @core.Instr::F32Ceil
    | @core.Instr::F32Floor
    | @core.Instr::F32Trunc
    | @core.Instr::F32Nearest
    | @core.Instr::F32Sqrt => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "f32 unary op")
      stack.push(@core.ValType::F32)
    }

    // f64 unary operations
    @core.Instr::F64Abs
    | @core.Instr::F64Neg
    | @core.Instr::F64Ceil
    | @core.Instr::F64Floor
    | @core.Instr::F64Trunc
    | @core.Instr::F64Nearest
    | @core.Instr::F64Sqrt => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "f64 unary op")
      stack.push(@core.ValType::F64)
    }

    // f32 binary operations
    @core.Instr::F32Add
    | @core.Instr::F32Sub
    | @core.Instr::F32Mul
    | @core.Instr::F32Div
    | @core.Instr::F32Min
    | @core.Instr::F32Max
    | @core.Instr::F32Copysign =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F32,
        @core.ValType::F32,
        "f32 binary op",
      )

    // f64 binary operations
    @core.Instr::F64Add
    | @core.Instr::F64Sub
    | @core.Instr::F64Mul
    | @core.Instr::F64Div
    | @core.Instr::F64Min
    | @core.Instr::F64Max
    | @core.Instr::F64Copysign =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F64,
        @core.ValType::F64,
        "f64 binary op",
      )

    // Conversion operations: i32 -> f32/f64
    @core.Instr::F32ConvertI32S | @core.Instr::F32ConvertI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f32.convert_i32")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ConvertI32S | @core.Instr::F64ConvertI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f64.convert_i32")
      stack.push(@core.ValType::F64)
    }

    // Conversion operations: i64 -> f32/f64
    @core.Instr::F32ConvertI64S | @core.Instr::F32ConvertI64U => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f32.convert_i64")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ConvertI64S | @core.Instr::F64ConvertI64U => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f64.convert_i64")
      stack.push(@core.ValType::F64)
    }

    // Promotion/demotion: f32 <-> f64
    @core.Instr::F64PromoteF32 => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "f64.promote_f32")
      stack.push(@core.ValType::F64)
    }
    @core.Instr::F32DemoteF64 => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "f32.demote_f64")
      stack.push(@core.ValType::F32)
    }

    // Truncation: f32/f64 -> i32/i64
    @core.Instr::I32TruncF32S | @core.Instr::I32TruncF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.trunc_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I32TruncF64S | @core.Instr::I32TruncF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i32.trunc_f64")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64TruncF32S | @core.Instr::I64TruncF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i64.trunc_f32")
      stack.push(@core.ValType::I64)
    }
    @core.Instr::I64TruncF64S | @core.Instr::I64TruncF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.trunc_f64")
      stack.push(@core.ValType::I64)
    }

    // Saturating truncation: f32/f64 -> i32/i64 (same types as regular trunc)
    @core.Instr::I32TruncSatF32S | @core.Instr::I32TruncSatF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.trunc_sat_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I32TruncSatF64S | @core.Instr::I32TruncSatF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i32.trunc_sat_f64")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64TruncSatF32S | @core.Instr::I64TruncSatF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i64.trunc_sat_f32")
      stack.push(@core.ValType::I64)
    }
    @core.Instr::I64TruncSatF64S | @core.Instr::I64TruncSatF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.trunc_sat_f64")
      stack.push(@core.ValType::I64)
    }

    // Reinterpret operations
    @core.Instr::F32ReinterpretI32 => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f32.reinterpret_i32")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ReinterpretI64 => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f64.reinterpret_i64")
      stack.push(@core.ValType::F64)
    }
    @core.Instr::I32ReinterpretF32 => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.reinterpret_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64ReinterpretF64 => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.reinterpret_f64")
      stack.push(@core.ValType::I64)
    }
    _ => return false
  }
  true
}
