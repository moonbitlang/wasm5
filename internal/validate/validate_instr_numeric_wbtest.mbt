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
  expect_numeric(I32Const(0U), [], [I32])
  expect_numeric(I32Add, [I32, I32], [I32])
  expect_numeric(I32Eq, [I32, I32], [I32])
  expect_numeric(I32Eqz, [I32], [I32])
  expect_numeric(I64Add, [I64, I64], [I64])
  expect_numeric(I64Eq, [I64, I64], [I32])
  expect_numeric(I64Eqz, [I64], [I32])
  expect_numeric(I64Clz, [I64], [I64])
  expect_numeric(I64ExtendI32S, [I32], [I64])
  expect_numeric(I32WrapI64, [I64], [I32])
  expect_numeric(F32Eq, [F32, F32], [I32])
  expect_numeric(F64Eq, [F64, F64], [I32])
  expect_numeric(F32Abs, [F32], [F32])
  expect_numeric(F64Abs, [F64], [F64])
  expect_numeric(F32Add, [F32, F32], [F32])
  expect_numeric(F64Add, [F64, F64], [F64])
  expect_numeric(F32ConvertI32S, [I32], [F32])
  expect_numeric(F64ConvertI32U, [I32], [F64])
  expect_numeric(F32ConvertI64S, [I64], [F32])
  expect_numeric(F64ConvertI64U, [I64], [F64])
  expect_numeric(F64PromoteF32, [F32], [F64])
  expect_numeric(F32DemoteF64, [F64], [F32])
  expect_numeric(I32TruncF32S, [F32], [I32])
  expect_numeric(I32TruncF64U, [F64], [I32])
  expect_numeric(I64TruncF32S, [F32], [I64])
  expect_numeric(I64TruncF64U, [F64], [I64])
  expect_numeric(I32TruncSatF32S, [F32], [I32])
  expect_numeric(I32TruncSatF64U, [F64], [I32])
  expect_numeric(I64TruncSatF32U, [F32], [I64])
  expect_numeric(I64TruncSatF64S, [F64], [I64])
  expect_numeric(F32ReinterpretI32, [I32], [F32])
  expect_numeric(F64ReinterpretI64, [I64], [F64])
  expect_numeric(I32ReinterpretF32, [F32], [I32])
  expect_numeric(I64ReinterpretF64, [F64], [I64])
}

///|
test "validate numeric instruction dispatch misses" {
  let ctx = ValidationCtx::new()
  let mut saw_error = false
  let ok = validate_instruction_numeric(test_empty_module(), ctx, Nop) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, false)
  assert_eq(ok, false)
}
