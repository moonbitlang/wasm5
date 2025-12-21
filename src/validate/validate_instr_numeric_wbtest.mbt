///|
fn expect_numeric(
  instr : @core.Instr,
  input : Array[@core.ValType],
  expected : Array[@core.ValType],
) -> Unit raise {
  let ctx = ValidationCtx::new()
  for val in input {
    ctx.stack.push(val)
  }
  let mut saw_error = false
  let ok = validate_instruction_numeric(test_empty_module(), ctx, instr) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, false)
  assert_eq(ok, true)
  assert_eq(ctx.stack.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(ctx.stack[i], expected[i])
  }
}

///|
test "validate numeric instruction groups" {
  expect_numeric(@core.Instr::I32Const(0U), [], [@core.ValType::I32])
  expect_numeric(
    @core.Instr::I32Add,
    [@core.ValType::I32, @core.ValType::I32],
    [@core.ValType::I32],
  )
  expect_numeric(@core.Instr::I32Eq, [@core.ValType::I32, @core.ValType::I32], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I32Eqz, [@core.ValType::I32], [@core.ValType::I32])
  expect_numeric(
    @core.Instr::I64Add,
    [@core.ValType::I64, @core.ValType::I64],
    [@core.ValType::I64],
  )
  expect_numeric(@core.Instr::I64Eq, [@core.ValType::I64, @core.ValType::I64], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I64Eqz, [@core.ValType::I64], [@core.ValType::I32])
  expect_numeric(@core.Instr::I64Clz, [@core.ValType::I64], [@core.ValType::I64])
  expect_numeric(@core.Instr::I64ExtendI32S, [@core.ValType::I32], [
    @core.ValType::I64,
  ])
  expect_numeric(@core.Instr::I32WrapI64, [@core.ValType::I64], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::F32Eq, [@core.ValType::F32, @core.ValType::F32], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::F64Eq, [@core.ValType::F64, @core.ValType::F64], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::F32Abs, [@core.ValType::F32], [@core.ValType::F32])
  expect_numeric(@core.Instr::F64Abs, [@core.ValType::F64], [@core.ValType::F64])
  expect_numeric(
    @core.Instr::F32Add,
    [@core.ValType::F32, @core.ValType::F32],
    [@core.ValType::F32],
  )
  expect_numeric(
    @core.Instr::F64Add,
    [@core.ValType::F64, @core.ValType::F64],
    [@core.ValType::F64],
  )
  expect_numeric(@core.Instr::F32ConvertI32S, [@core.ValType::I32], [
    @core.ValType::F32,
  ])
  expect_numeric(@core.Instr::F64ConvertI32U, [@core.ValType::I32], [
    @core.ValType::F64,
  ])
  expect_numeric(@core.Instr::F32ConvertI64S, [@core.ValType::I64], [
    @core.ValType::F32,
  ])
  expect_numeric(@core.Instr::F64ConvertI64U, [@core.ValType::I64], [
    @core.ValType::F64,
  ])
  expect_numeric(@core.Instr::F64PromoteF32, [@core.ValType::F32], [
    @core.ValType::F64,
  ])
  expect_numeric(@core.Instr::F32DemoteF64, [@core.ValType::F64], [
    @core.ValType::F32,
  ])
  expect_numeric(@core.Instr::I32TruncF32S, [@core.ValType::F32], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I32TruncF64U, [@core.ValType::F64], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I64TruncF32S, [@core.ValType::F32], [
    @core.ValType::I64,
  ])
  expect_numeric(@core.Instr::I64TruncF64U, [@core.ValType::F64], [
    @core.ValType::I64,
  ])
  expect_numeric(@core.Instr::I32TruncSatF32S, [@core.ValType::F32], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I32TruncSatF64U, [@core.ValType::F64], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I64TruncSatF32U, [@core.ValType::F32], [
    @core.ValType::I64,
  ])
  expect_numeric(@core.Instr::I64TruncSatF64S, [@core.ValType::F64], [
    @core.ValType::I64,
  ])
  expect_numeric(@core.Instr::F32ReinterpretI32, [@core.ValType::I32], [
    @core.ValType::F32,
  ])
  expect_numeric(@core.Instr::F64ReinterpretI64, [@core.ValType::I64], [
    @core.ValType::F64,
  ])
  expect_numeric(@core.Instr::I32ReinterpretF32, [@core.ValType::F32], [
    @core.ValType::I32,
  ])
  expect_numeric(@core.Instr::I64ReinterpretF64, [@core.ValType::F64], [
    @core.ValType::I64,
  ])
}

///|
test "validate numeric instruction dispatch misses" {
  let ctx = ValidationCtx::new()
  let mut saw_error = false
  let ok = validate_instruction_numeric(
    test_empty_module(),
    ctx,
    @core.Instr::Nop,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, false)
  assert_eq(ok, false)
}
