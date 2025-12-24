///|
fn base_module(
  types : Array[@core.FuncType],
  funcs : Array[UInt],
  codes : Array[@core.Code],
  imports : Array[@core.Import],
) -> @core.Module {
  {
    types,
    funcs,
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports,
    exports: [],
    codes,
  }
}

///|
fn base_runtime(
  module_ : @core.Module,
  ops : Array[MInstr],
  stack : Array[Value],
) -> Runtime {
  // Convert Value arrays to UInt64
  let stack64 = stack.map(value_to_stack)
  Runtime::{
    module_,
    ops,
    stack: stack64,
    sp: 0,
    num_locals: 0,
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
}

///|
fn assert_ctrl_stack_eq(got : UInt64, expected : Value) -> Unit {
  let exp = value_to_stack(expected)
  if got != exp {
    abort("stack element mismatch")
  }
}

///|
test "ops control drop and select" {
  let rt_drop = base_runtime(base_module([], [], [], []), [], [Value::I32(1U)])
  assert_ok(op_drop(rt_drop))
  assert_eq(rt_drop.stack.length(), 0)
  let rt_select = base_runtime(base_module([], [], [], []), [], [
    Value::I32(10U),
    Value::I32(20U),
    Value::I32(1U),
  ])
  assert_ok(op_select(rt_select))
  assert_ctrl_stack_eq(rt_select.stack[0], Value::I32(10U))
}

///|
test "ops control branching" {
  let rt_if_true = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(7)],
    [Value::I32(1U)],
  )
  assert_ok(op_if(rt_if_true))
  assert_eq(rt_if_true.pc, 2)
  let rt_if_false = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(9)],
    [Value::I32(0U)],
  )
  assert_ok(op_if(rt_if_false))
  assert_eq(rt_if_false.pc, 9)
  let rt_br = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(10), ImmediateIdx(1), ImmediateIdx(1)],
    [Value::I32(1U), Value::I32(2U), Value::I32(3U)],
  )
  assert_ok(op_br(rt_br))
  assert_eq(rt_br.pc, 10)
  assert_eq(rt_br.stack, [1UL, 3UL])
  let rt_br_if = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(5), ImmediateIdx(1), ImmediateIdx(0)],
    [Value::I32(9U), Value::I32(1U)],
  )
  assert_ok(op_br_if(rt_br_if))
  assert_eq(rt_br_if.pc, 5)
  assert_ctrl_stack_eq(rt_br_if.stack[0], Value::I32(9U))
  let rt_br_if_false = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(5), ImmediateIdx(1), ImmediateIdx(0)],
    [Value::I32(9U), Value::I32(0U)],
  )
  assert_ok(op_br_if(rt_br_if_false))
  assert_eq(rt_br_if_false.pc, 4)
  let rt_br_table = base_runtime(
    base_module([], [], [], []),
    [
      ImmediateIdx(0),
      ImmediateIdx(2),
      ImmediateIdx(1),
      ImmediateIdx(10),
      ImmediateIdx(0),
      ImmediateIdx(20),
      ImmediateIdx(0),
      ImmediateIdx(30),
      ImmediateIdx(0),
    ],
    [Value::I32(7U), Value::I32(1U)],
  )
  assert_ok(op_br_table(rt_br_table))
  assert_eq(rt_br_table.pc, 20)
  let rt_br_table_default = base_runtime(
    base_module([], [], [], []),
    [
      ImmediateIdx(0),
      ImmediateIdx(2),
      ImmediateIdx(1),
      ImmediateIdx(10),
      ImmediateIdx(0),
      ImmediateIdx(20),
      ImmediateIdx(0),
      ImmediateIdx(30),
      ImmediateIdx(0),
    ],
    [Value::I32(7U), Value::I32(5U)],
  )
  assert_ok(op_br_table(rt_br_table_default))
  assert_eq(rt_br_table_default.pc, 30)
  let rt_br_on_null = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(8), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(None)],
  )
  assert_ok(op_br_on_null(rt_br_on_null))
  assert_eq(rt_br_on_null.pc, 8)
  let rt_br_on_non_null = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(4), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(Some(1))],
  )
  assert_ok(op_br_on_non_null(rt_br_on_non_null))
  assert_eq(rt_br_on_non_null.pc, 4)
}

///|
test "ops control table grow and globals" {
  let module_local = base_module([], [], [], [])
  let rt_table_size = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [],
    sp: 0,
    num_locals: 0,
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [RuntimeTable::{ data: [None, None], max: Some(3U) }],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_table_size(rt_table_size))
  assert_ctrl_stack_eq(rt_table_size.stack[0], Value::I32(2U))
  let rt_table_grow = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [0xFFFFFFFF_FFFFFFFFUL, 1UL], // Ref(None)=-1, I32(1)
    sp: 0,
    num_locals: 0,
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [RuntimeTable::{ data: [None], max: Some(3U) }],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_table_grow(rt_table_grow))
  assert_ctrl_stack_eq(rt_table_grow.stack[0], Value::I32(1U))
  let rt_global = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [9UL],
    sp: 0,
    num_locals: 0,
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [Value::I32(1U)],
    tables: [],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_global_set(rt_global))
  rt_global.stack.clear()
  rt_global.pc = 0
  assert_ok(op_global_get(rt_global))
  assert_ctrl_stack_eq(rt_global.stack[0], Value::I32(9U))
}

///|
test "ops control reference ops" {
  let module_local = base_module([], [], [], [])
  let rt_ref_null = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [],
  )
  assert_ok(op_ref_null(rt_ref_null))
  assert_ctrl_stack_eq(rt_ref_null.stack[0], Value::Ref(None))
  let rt_ref_is_null = base_runtime(module_local, [], [Value::Ref(None)])
  assert_ok(op_ref_is_null(rt_ref_is_null))
  assert_ctrl_stack_eq(rt_ref_is_null.stack[0], Value::I32(1U))
  let rt_ref_eq_same = base_runtime(module_local, [], [
    Value::Ref(Some(1)),
    Value::Ref(Some(1)),
  ])
  assert_ok(op_ref_eq(rt_ref_eq_same))
  assert_ctrl_stack_eq(rt_ref_eq_same.stack[0], Value::I32(1U))
  let rt_ref_eq_diff = base_runtime(module_local, [], [
    Value::Ref(Some(1)),
    Value::Ref(Some(2)),
  ])
  assert_ok(op_ref_eq(rt_ref_eq_diff))
  assert_ctrl_stack_eq(rt_ref_eq_diff.stack[0], Value::I32(0U))
  let rt_ref_as_non_null = base_runtime(module_local, [], [Value::Ref(Some(0))])
  assert_ok(op_ref_as_non_null(rt_ref_as_non_null))
  assert_ctrl_stack_eq(rt_ref_as_non_null.stack[0], Value::Ref(Some(0)))
  let rt_ref_as_non_null_null = base_runtime(module_local, [], [
    Value::Ref(None),
  ])
  assert_ret(op_ref_as_non_null(rt_ref_as_non_null_null), InvalidType)
}

///|
test "ops control table bulk stubs" {
  let module_local = base_module([], [], [], [])
  let rt_table_init = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
  )
  assert_ok(op_table_init(rt_table_init))
  let rt_table_copy = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
  )
  assert_ok(op_table_copy(rt_table_copy))
  let rt_elem_drop = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [],
  )
  assert_ok(op_elem_drop(rt_elem_drop))
}

///|
test "ops control nop and unreachable" {
  let module_local = base_module([], [], [], [])
  let rt_nop = base_runtime(module_local, [], [])
  assert_ok(op_nop(rt_nop))
  assert_ret(op_unreachable(rt_nop), Unreachable)
}
