///|
test "compile context branch helpers" {
  let ctx = CompileCtx::new()
  ctx.push_control(LoopKind, [@core.ValType::I32], [@core.ValType::I64], 7)
  ctx.push_control(BlockKind, [], [@core.ValType::I32], 0)
  assert_eq(ctx.get_branch_arity(1), 1)
  assert_eq(ctx.get_target_pc(1), 7)
}
