///|
test "compile context branch helpers" {
  let ctx = CompileCtx::new()
  ctx.push_control(LoopKind, [I32], [I64], 7)
  ctx.push_control(BlockKind, [], [I32], 0)
  assert_eq(ctx.get_branch_arity(1), 1)
  assert_eq(ctx.get_target_pc(1), 7)
}
