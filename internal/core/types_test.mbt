///|
test "valtype defaultable numeric" {
  assert_eq(ValType::I32.is_defaultable(), true)
  assert_eq(ValType::I64.is_defaultable(), true)
  assert_eq(ValType::F32.is_defaultable(), true)
  assert_eq(ValType::F64.is_defaultable(), true)
  assert_eq(ValType::V128.is_defaultable(), true)
}

///|
test "valtype defaultable refs" {
  assert_eq(ValType::FuncRef.is_defaultable(), true)
  assert_eq(ValType::ExternRef.is_defaultable(), true)
  assert_eq(ValType::NullRef.is_defaultable(), true)
  assert_eq(ValType::Ref(RefType::Func, true).is_defaultable(), true)
  assert_eq(ValType::Ref(RefType::Extern, false).is_defaultable(), false)
}
