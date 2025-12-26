///|
fn make_code(locals : Array[@core.ValType]) -> @core.Code {
  {
    locals,
    body: @core.Expr::{ instrs: [] },
    compiled: None,
    max_stack_height: 0,
  }
}

///|
test "compile helpers initialize entry locals" {
  let rt = make_runtime([], [], 0)
  let code = make_code([I32, Ref(Func, true)])
  rt.initialize_entry_locals([Value::I32(9U)], code)
  assert_ok(rt)
  // Check unified stack: [arg0=9, local0=0, local1=null_ref]
  assert_eq(rt.stack_top, 3)
  assert_eq(rt.stack.unsafe_get(0), 9UL) // arg
  assert_eq(rt.stack.unsafe_get(1), 0UL) // i32 local
  assert_eq(rt.stack.unsafe_get(2), (-1L).reinterpret_as_uint64()) // null ref
  assert_eq(rt.sp, 0)
  assert_eq(rt.num_locals, 3)
}

///|
test "compile helpers init declared locals unsupported" {
  let rt = make_runtime([], [], 0)
  let code = make_code([V128])
  rt.init_declared_locals(code)
  assert_trap(rt)
}

///|
test "compile helpers type signature mismatch" {
  let expected : @core.FuncType = { params: [I32], results: [] }
  let actual : @core.FuncType = { params: [], results: [] }
  let rt = make_runtime([], [], 0)
  check_type_signature_match(expected, actual, "bad", rt)
  assert_trap(rt)
}

///|
test "compile helpers func type lookup with non func imports" {
  let module_ : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      {
        module_: b"m",
        name: b"mem",
        desc: Mem({
          limits: { min: 1UL, max: None },
          shared: false,
          memory64: false,
        }),
      },
      { module_: b"m", name: b"f", desc: Func(0U) },
    ],
    exports: [],
    codes: [],
  }
  assert_eq(get_func_type_idx(module_, 0, 1), 0)
}

///|
test "compile helpers imported func result truncation" {
  let rt = Runtime::{
    module_: empty_module(),
    ops: [],
    stack: FixedArray::make(64, 0UL),
    stack_top: 0,
    sp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
    call_stack: [],
    memory: [],
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [
      ImportedFunc::new(0U, fn(_args) { [Value::I32(1U), Value::I32(2U)] }),
    ],
    data_segments: [],
    error_detail: "",
  }
  rt.call_imported_function(0, [], 1)
  assert_eq(rt.stack_top, 1)
  assert_eq(rt.stack.unsafe_get(0), 1UL)
}

///|
test "compile helpers tail call return branches" {
  let rt = make_runtime([], [], 0)
  rt.status = Running
  rt.sp = 5
  rt.num_locals = 3
  rt.call_stack.push(CallFrame::{
    return_pc: 3,
    caller_sp: 10,
    caller_num_locals: 2,
  })
  let _ = rt.handle_tail_call_return()
  assert_eq(rt.pc, 4)
  assert_eq(rt.sp, 10)
  assert_eq(rt.num_locals, 2)
  let rt_empty = make_runtime([], [], 0)
  rt_empty.status = Running
  let _ = rt_empty.handle_tail_call_return()
  assert_eq(rt_empty.status, Terminated)
}
