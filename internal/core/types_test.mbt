///|
test "valtype defaultable numeric" {
  assert_eq(@core.ValType::I32.is_defaultable(), true)
  assert_eq(@core.ValType::I64.is_defaultable(), true)
  assert_eq(@core.ValType::F32.is_defaultable(), true)
  assert_eq(@core.ValType::F64.is_defaultable(), true)
  assert_eq(@core.ValType::V128.is_defaultable(), true)
}

///|
test "valtype defaultable refs" {
  assert_eq(@core.ValType::FuncRef.is_defaultable(), true)
  assert_eq(@core.ValType::ExternRef.is_defaultable(), true)
  assert_eq(@core.ValType::NullRef.is_defaultable(), true)
  assert_eq(
    @core.ValType::Ref(@core.RefType::Func, true).is_defaultable(),
    true,
  )
  assert_eq(
    @core.ValType::Ref(@core.RefType::Extern, false).is_defaultable(),
    false,
  )
}
