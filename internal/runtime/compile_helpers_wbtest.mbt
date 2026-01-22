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
  let rt = initialize_entry_locals(rt, [Value::I32(9U)], code)
  // Check: args pushed, but declared locals NOT pushed (done by compiled code)
  assert_eq(rt.sp, 1) // Only args pushed
  assert_eq(rt.stack.unsafe_get(0), 9UL) // arg
  assert_eq(rt.bp, 0)
  assert_eq(rt.num_locals, 3) // Still 3 locals expected (1 arg + 2 declared)
}

///|
test "compile helpers type signature mismatch" {
  let expected : @core.FuncType = { params: [I32], results: [] }
  let actual : @core.FuncType = { params: [], results: [] }
  let rt = make_runtime([], [], 0)
  let rc = check_type_signature_match(expected, actual, "bad", rt)
  assert_trap(rc)
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
  assert_eq(@core.get_func_type_idx(module_, 0, 1), 0)
}

///|
test "compile helpers imported func result truncation" {
  let ctx = RuntimeContext::new_with_gc_heap(
    empty_module(),
    [],
    None,
    [],
    [],
    [HostFunc::new(fn(_args) { [Value::I32(1U), Value::I32(2U)] })],
    [],
    [],
  )
  let rt = Instance::{
    ops: FixedArray::from_array([]),
    stack: FixedArray::make(64, 0UL),
    sp: 0,
    bp: 0,
    num_locals: 0,
    pc: 0,
    ctx,
  }
  let rt = call_imported_function(rt, 0, [], 1)
  assert_eq(rt.sp, 1)
  assert_eq(rt.stack.unsafe_get(0), 1UL)
}

///|
test "compile helpers tail call return branches" {
  // Test nested call (bp != 0) - should return Returned
  let rt = make_runtime([], [], 0)
  let rt = { ..rt, bp: 5, num_locals: 3 }
  let rc = handle_tail_call_return(rt)
  assert_eq(rc, Returned)
  assert_eq(rt.bp, 5) // bp unchanged - caller's execute_call will restore

  // Test entry function (bp == 0) - should return Terminated
  let rt_entry = make_runtime([], [], 0)
  let rt_entry = { ..rt_entry, bp: 0 }
  let rc_entry = handle_tail_call_return(rt_entry)
  assert_eq(rc_entry, Terminated)
}

///|
