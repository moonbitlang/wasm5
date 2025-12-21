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
  locals : Array[Value],
) -> Runtime {
  Runtime::{
    module_,
    ops,
    stack,
    locals,
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
test "ops control locals and stack" {
  let ops = [ImmediateIdx(0), ImmediateIdx(1)]
  let rt_get = base_runtime(base_module([], [], [], []), ops, [], [
    Value::I32(1U),
    Value::I32(2U),
  ])
  assert_ok(op_local_get(rt_get))
  assert_eq(rt_get.stack[0], Value::I32(2U))
  let rt_set = base_runtime(
    base_module([], [], [], []),
    ops,
    [Value::I32(9U)],
    [Value::I32(1U), Value::I32(2U)],
  )
  assert_ok(op_local_set(rt_set))
  assert_eq(rt_set.locals[1], Value::I32(9U))
  let rt_tee = base_runtime(
    base_module([], [], [], []),
    ops,
    [Value::I32(7U)],
    [Value::I32(1U), Value::I32(2U)],
  )
  assert_ok(op_local_tee(rt_tee))
  assert_eq(rt_tee.locals[1], Value::I32(7U))
  let rt_drop = base_runtime(
    base_module([], [], [], []),
    [],
    [Value::I32(1U)],
    [],
  )
  assert_ok(op_drop(rt_drop))
  assert_eq(rt_drop.stack.length(), 0)
  let rt_select = base_runtime(
    base_module([], [], [], []),
    [],
    [Value::I32(10U), Value::I32(20U), Value::I32(1U)],
    [],
  )
  assert_ok(op_select(rt_select))
  assert_eq(rt_select.stack[0], Value::I32(10U))
}

///|
test "ops control branching" {
  let rt_if_true = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(7)],
    [Value::I32(1U)],
    [],
  )
  assert_ok(op_if(rt_if_true))
  assert_eq(rt_if_true.pc, 2)
  let rt_if_false = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(9)],
    [Value::I32(0U)],
    [],
  )
  assert_ok(op_if(rt_if_false))
  assert_eq(rt_if_false.pc, 9)
  let rt_br = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(10), ImmediateIdx(1), ImmediateIdx(1)],
    [Value::I32(1U), Value::I32(2U), Value::I32(3U)],
    [],
  )
  assert_ok(op_br(rt_br))
  assert_eq(rt_br.pc, 10)
  assert_eq(rt_br.stack, [Value::I32(1U), Value::I32(3U)])
  let rt_br_if = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(5), ImmediateIdx(1), ImmediateIdx(0)],
    [Value::I32(9U), Value::I32(1U)],
    [],
  )
  assert_ok(op_br_if(rt_br_if))
  assert_eq(rt_br_if.pc, 5)
  assert_eq(rt_br_if.stack[0], Value::I32(9U))
  let rt_br_if_false = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(5), ImmediateIdx(1), ImmediateIdx(0)],
    [Value::I32(9U), Value::I32(0U)],
    [],
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
    [],
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
    [],
  )
  assert_ok(op_br_table(rt_br_table_default))
  assert_eq(rt_br_table_default.pc, 30)
  let rt_br_on_null = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(8), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(None)],
    [],
  )
  assert_ok(op_br_on_null(rt_br_on_null))
  assert_eq(rt_br_on_null.pc, 8)
  let rt_br_on_non_null = base_runtime(
    base_module([], [], [], []),
    [ImmediateIdx(0), ImmediateIdx(4), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(Some(1))],
    [],
  )
  assert_ok(op_br_on_non_null(rt_br_on_non_null))
  assert_eq(rt_br_on_non_null.pc, 4)
}

///|
test "ops control calls and return" {
  let type0 : @core.FuncType = { params: [], results: [I32] }
  let code0 : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [] },
    compiled: Some(3),
  }
  let module_import = base_module([type0], [], [], [
    { module_: b"m", name: b"f", desc: Func(0U) },
  ])
  let rt_import = Runtime::{
    module_: module_import,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [],
    locals: [],
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [ImportedFunc::new(0U, fn(_args) { [Value::I32(7U)] })],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_call(rt_import))
  assert_eq(rt_import.stack[0], Value::I32(7U))
  let module_local = base_module([type0], [0U], [code0], [])
  let rt_local = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [],
    [],
  )
  assert_ok(op_call(rt_local))
  assert_eq(rt_local.pc, 3)
  assert_eq(rt_local.call_stack.length(), 1)
  let frame = CallFrame::{ return_pc: 5, locals: [] }
  let rt_return = base_runtime(module_local, [], [Value::I32(1U)], [])
  rt_return.call_stack.push(frame)
  assert_ok(op_return(rt_return))
  assert_eq(rt_return.pc, 6)
  assert_eq(rt_return.stack[0], Value::I32(1U))
}

///|
test "ops control indirect calls" {
  let type0 : @core.FuncType = { params: [], results: [] }
  let code0 : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [] },
    compiled: Some(2),
  }
  let module_local = base_module([type0], [0U], [code0], [])
  let rt_indirect = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    stack: [Value::I32(0U)],
    locals: [],
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [RuntimeTable::{ data: [Some(0)], max: None }],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_call_indirect(rt_indirect))
  assert_eq(rt_indirect.pc, 2)
  let rt_indirect_bad = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(1), ImmediateIdx(0)],
    stack: [Value::I32(0U)],
    locals: [],
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
  assert_ret(op_call_indirect(rt_indirect_bad), InvalidType)
  let rt_ret_indirect = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    stack: [Value::I32(0U)],
    locals: [],
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [RuntimeTable::{ data: [Some(0)], max: None }],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_return_call_indirect(rt_ret_indirect))
  assert_eq(rt_ret_indirect.pc, 2)
}

///|
test "ops control ref calls and tables" {
  let type0 : @core.FuncType = { params: [], results: [] }
  let code0 : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [] },
    compiled: Some(4),
  }
  let module_local = base_module([type0], [0U], [code0], [])
  let rt_call_ref = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(Some(0))],
    [],
  )
  assert_ok(op_call_ref(rt_call_ref))
  assert_eq(rt_call_ref.pc, 4)
  let rt_return_ref = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [Value::Ref(Some(0))],
    [],
  )
  assert_ok(op_return_call_ref(rt_return_ref))
  assert_eq(rt_return_ref.pc, 4)
  let rt_table = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [Value::I32(0U), Value::Ref(Some(0))],
    locals: [],
    pc: 0,
    running: true,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [RuntimeTable::{ data: [None], max: Some(2U) }],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_table_set(rt_table))
  rt_table.stack.clear()
  rt_table.pc = 0
  rt_table.stack.push(Value::I32(0U))
  assert_ok(op_table_get(rt_table))
  assert_eq(rt_table.stack[0], Value::Ref(Some(0)))
}

///|
test "ops control table grow and globals" {
  let module_local = base_module([], [], [], [])
  let rt_table_size = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [],
    locals: [],
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
  assert_eq(rt_table_size.stack[0], Value::I32(2U))
  let rt_table_grow = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [Value::Ref(None), Value::I32(1U)],
    locals: [],
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
  assert_eq(rt_table_grow.stack[0], Value::I32(1U))
  let rt_global = Runtime::{
    module_: module_local,
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [Value::I32(9U)],
    locals: [],
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
  assert_eq(rt_global.stack[0], Value::I32(9U))
}

///|
test "ops control reference ops" {
  let module_local = base_module([], [], [], [])
  let rt_ref_null = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [],
    [],
  )
  assert_ok(op_ref_null(rt_ref_null))
  assert_eq(rt_ref_null.stack[0], Value::Ref(None))
  let rt_ref_is_null = base_runtime(module_local, [], [Value::Ref(None)], [])
  assert_ok(op_ref_is_null(rt_ref_is_null))
  assert_eq(rt_ref_is_null.stack[0], Value::I32(1U))
}

///|
test "ops control table bulk stubs" {
  let module_local = base_module([], [], [], [])
  let rt_table_init = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
    [],
  )
  assert_ok(op_table_init(rt_table_init))
  let rt_table_copy = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0), ImmediateIdx(0)],
    [Value::I32(0U), Value::I32(0U), Value::I32(0U)],
    [],
  )
  assert_ok(op_table_copy(rt_table_copy))
  let rt_elem_drop = base_runtime(
    module_local,
    [ImmediateIdx(0), ImmediateIdx(0)],
    [],
    [],
  )
  assert_ok(op_elem_drop(rt_elem_drop))
}

///|
test "ops control nop and unreachable" {
  let module_local = base_module([], [], [], [])
  let rt_nop = base_runtime(module_local, [], [], [])
  assert_ok(op_nop(rt_nop))
  assert_ret(op_unreachable(rt_nop), Unreachable)
}
