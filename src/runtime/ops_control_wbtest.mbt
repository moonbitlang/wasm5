///|
fn base_module(
  types : Array[@core.TypeDef],
  funcs : Array[UInt],
  codes : Array[@core.Code],
  imports : Array[@core.Import],
) -> @core.Module {
  {
    types,
    type_groups: [],
    customs: [],
    funcs,
    tables: [],
    mems: [],
    globals: [],
    tags: [],
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
  ops : Array[UInt64],
  stack : Array[Value],
) -> Runtime {
  // Convert Value arrays to UInt64 and allocate fixed buffer
  let stack64 = stack.map(value_to_stack)
  let stack_len = stack64.length()
  // Allocate buffer with some capacity, copy values
  let capacity = if stack_len < 64 { 64 } else { stack_len * 2 }
  let stack_buf = FixedArray::make(capacity, 0UL)
  for i in 0..<stack_len {
    stack_buf[i] = stack64[i]
  }
  let ctx = RuntimeContext::new(module_, [], None, [], [], [], [])
  Runtime::{
    ops: FixedArray::from_array(ops),
    stack: stack_buf,
    sp: stack_len,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Running,
    ctx,
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
  let rt_drop = op_drop(rt_drop)
  assert_ok(rt_drop)
  assert_eq(rt_drop.sp, 0)
  let rt_select = base_runtime(base_module([], [], [], []), [], [
    Value::I32(10U),
    Value::I32(20U),
    Value::I32(1U),
  ])
  let rt_select = op_select(rt_select)
  assert_ok(rt_select)
  assert_ctrl_stack_eq(rt_select.stack[0], Value::I32(10U))
}

///|
test "ops control branching" {
  let rt_if_true = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(7)],
    [Value::I32(1U)],
  )
  let rt_if_true = op_if(rt_if_true)
  assert_ok(rt_if_true)
  assert_eq(rt_if_true.pc, 2)
  let rt_if_false = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(9)],
    [Value::I32(0U)],
  )
  let rt_if_false = op_if(rt_if_false)
  assert_ok(rt_if_false)
  assert_eq(rt_if_false.pc, 9)
  let rt_br = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(10), idx(1), idx(1)],
    [Value::I32(1U), Value::I32(2U), Value::I32(3U)],
  )
  let rt_br = op_br(rt_br)
  assert_ok(rt_br)
  assert_eq(rt_br.pc, 10)
  assert_eq(rt_br.sp, 2)
  assert_eq(rt_br.stack.unsafe_get(0), 1UL)
  assert_eq(rt_br.stack.unsafe_get(1), 3UL)
  let rt_br_if = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(5), idx(1), idx(0)],
    [Value::I32(9U), Value::I32(1U)],
  )
  let rt_br_if = op_br_if(rt_br_if)
  assert_ok(rt_br_if)
  assert_eq(rt_br_if.pc, 5)
  assert_ctrl_stack_eq(rt_br_if.stack[0], Value::I32(9U))
  let rt_br_if_false = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(5), idx(1), idx(0)],
    [Value::I32(9U), Value::I32(0U)],
  )
  let rt_br_if_false = op_br_if(rt_br_if_false)
  assert_ok(rt_br_if_false)
  assert_eq(rt_br_if_false.pc, 4)
  let rt_br_table = base_runtime(
    base_module([], [], [], []),
    [
      idx(0),
      idx(2),
      idx(1),
      idx(10),
      idx(0),
      idx(20),
      idx(0),
      idx(30),
      idx(0),
    ],
    [Value::I32(7U), Value::I32(1U)],
  )
  let rt_br_table = op_br_table(rt_br_table)
  assert_ok(rt_br_table)
  assert_eq(rt_br_table.pc, 20)
  let rt_br_table_default = base_runtime(
    base_module([], [], [], []),
    [
      idx(0),
      idx(2),
      idx(1),
      idx(10),
      idx(0),
      idx(20),
      idx(0),
      idx(30),
      idx(0),
    ],
    [Value::I32(7U), Value::I32(5U)],
  )
  let rt_br_table_default = op_br_table(rt_br_table_default)
  assert_ok(rt_br_table_default)
  assert_eq(rt_br_table_default.pc, 30)
  let rt_br_on_null = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(8), idx(0), idx(0)],
    [Value::Ref(None)],
  )
  let rt_br_on_null = op_br_on_null(rt_br_on_null)
  assert_ok(rt_br_on_null)
  assert_eq(rt_br_on_null.pc, 8)
  let rt_br_on_non_null = base_runtime(
    base_module([], [], [], []),
    [idx(0), idx(4), idx(0), idx(0)],
    [Value::Ref(Some(1))],
  )
  let rt_br_on_non_null = op_br_on_non_null(rt_br_on_non_null)
  assert_ok(rt_br_on_non_null)
  assert_eq(rt_br_on_non_null.pc, 4)
}

///|
test "ops control table grow and globals" {
  let module_local = base_module([], [], [], [])
  let ctx_table_size = RuntimeContext::new(
    module_local,
    [],
    None,
    [],
    [RuntimeTable::{ data: [None, None], max: Some(3UL) }],
    [],
    [],
  )
  let rt_table_size = Runtime::{
    ops: FixedArray::from_array([idx(0), idx(0)]),
    stack: FixedArray::make(64, 0UL),
    sp: 0,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Running,
    ctx: ctx_table_size,
  }
  let rt_table_size = op_table_size(rt_table_size)
  assert_ok(rt_table_size)
  assert_ctrl_stack_eq(rt_table_size.stack.unsafe_get(0), Value::I32(2U))
  let stack_grow = FixedArray::make(64, 0UL)
  stack_grow[0] = 0xFFFFFFFF_FFFFFFFFUL // Ref(None)=-1
  stack_grow[1] = 1UL // I32(1)
  let ctx_table_grow = RuntimeContext::new(
    module_local,
    [],
    None,
    [],
    [RuntimeTable::{ data: [None], max: Some(3UL) }],
    [],
    [],
  )
  let rt_table_grow = Runtime::{
    ops: FixedArray::from_array([idx(0), idx(0)]),
    stack: stack_grow,
    sp: 2,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Running,
    ctx: ctx_table_grow,
  }
  let rt_table_grow = op_table_grow(rt_table_grow)
  assert_ok(rt_table_grow)
  assert_ctrl_stack_eq(rt_table_grow.stack.unsafe_get(0), Value::I32(1U))
  let stack_global = FixedArray::make(64, 0UL)
  stack_global[0] = 9UL
  let ctx_global = RuntimeContext::new(
    module_local,
    [],
    None,
    [Value::I32(1U)],
    [],
    [],
    [],
  )
  let rt_global = Runtime::{
    ops: FixedArray::from_array([idx(0), idx(0)]),
    stack: stack_global,
    sp: 1,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Running,
    ctx: ctx_global,
  }
  let rt_global = op_global_set(rt_global)
  assert_ok(rt_global)
  let rt_global = { ..rt_global, sp: 0, pc: 0 }
  let rt_global = op_global_get(rt_global)
  assert_ok(rt_global)
  assert_ctrl_stack_eq(rt_global.stack.unsafe_get(0), Value::I32(9U))
}

///|
test "ops control reference ops" {
  let module_local = base_module([], [], [], [])
  let rt_ref_null = base_runtime(
    module_local,
    [idx(0), idx(0)],
    [],
  )
  let rt_ref_null = op_ref_null(rt_ref_null)
  assert_ok(rt_ref_null)
  assert_ctrl_stack_eq(rt_ref_null.stack[0], Value::Ref(None))
  let rt_ref_is_null = base_runtime(module_local, [], [Value::Ref(None)])
  let rt_ref_is_null = op_ref_is_null(rt_ref_is_null)
  assert_ok(rt_ref_is_null)
  assert_ctrl_stack_eq(rt_ref_is_null.stack[0], Value::I32(1U))
  let rt_ref_eq_same = base_runtime(module_local, [], [
    Value::Ref(Some(1)),
    Value::Ref(Some(1)),
  ])
  let rt_ref_eq_same = op_ref_eq(rt_ref_eq_same)
  assert_ok(rt_ref_eq_same)
  assert_ctrl_stack_eq(rt_ref_eq_same.stack[0], Value::I32(1U))
  let rt_ref_eq_diff = base_runtime(module_local, [], [
    Value::Ref(Some(1)),
    Value::Ref(Some(2)),
  ])
  let rt_ref_eq_diff = op_ref_eq(rt_ref_eq_diff)
  assert_ok(rt_ref_eq_diff)
  assert_ctrl_stack_eq(rt_ref_eq_diff.stack[0], Value::I32(0U))
  let rt_ref_as_non_null = base_runtime(module_local, [], [Value::Ref(Some(0))])
  let rt_ref_as_non_null = op_ref_as_non_null(rt_ref_as_non_null)
  assert_ok(rt_ref_as_non_null)
  assert_ctrl_stack_eq(rt_ref_as_non_null.stack[0], Value::Ref(Some(0)))
  let rt_ref_as_non_null_null = base_runtime(module_local, [], [
    Value::Ref(None),
  ])
  let rt_ref_as_non_null_null = op_ref_as_non_null(rt_ref_as_non_null_null)
  assert_trap(rt_ref_as_non_null_null)
}

///|
test "ops control table bulk stubs" {
  let module_local = base_module([], [], [], [])
  let rt_table_init = base_runtime(
    module_local,
    [idx(0), idx(0), idx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
  )
  let rt_table_init = op_table_init(rt_table_init)
  assert_ok(rt_table_init)
  let rt_table_copy = base_runtime(
    module_local,
    [idx(0), idx(0), idx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
  )
  let rt_table_copy = op_table_copy(rt_table_copy)
  assert_ok(rt_table_copy)
  let rt_elem_drop = base_runtime(
    module_local,
    [idx(0), idx(0)],
    [],
  )
  let rt_elem_drop = op_elem_drop(rt_elem_drop)
  assert_ok(rt_elem_drop)
}

///|
test "ops control nop and unreachable" {
  let module_local = base_module([], [], [], [])
  let rt_nop = base_runtime(module_local, [], [])
  let rt_nop = op_nop(rt_nop)
  assert_ok(rt_nop)
  let rt_nop = op_unreachable(rt_nop)
  assert_trap(rt_nop)
}
