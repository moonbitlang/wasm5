///|
fn make_code(locals : Array[@core.ValType]) -> @core.Code {
  { locals, body: @core.Expr::{ instrs: [] }, compiled: None }
}

///|
test "compile helpers initialize locals" {
  let rt = make_runtime([], [], 0)
  let code = make_code([
    @core.ValType::I32,
    @core.ValType::Ref(@core.RefType::Func, true),
  ])
  assert_ok(rt.initialize_locals([Value::I32(9U)], code))
  assert_eq(rt.locals.length(), 3)
  assert_eq(rt.locals[0], Value::I32(9U))
  assert_eq(rt.locals[1], Value::I32(0U))
  assert_eq(rt.locals[2], Value::Ref(None))
}

///|
test "compile helpers initialize locals unsupported" {
  let rt = make_runtime([], [], 0)
  let code = make_code([@core.ValType::V128])
  assert_ret(rt.initialize_locals([], code), UnsupportedLocalType)
}

///|
test "compile helpers type signature mismatch" {
  let expected : @core.FuncType = { params: [@core.ValType::I32], results: [] }
  let actual : @core.FuncType = { params: [], results: [] }
  let rt = make_runtime([], [], 0)
  assert_ret(
    check_type_signature_match(expected, actual, "bad", rt),
    InvalidType,
  )
}

///|
test "compile helpers func type lookup with non func imports" {
  let module_ : @core.Module = {
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      {
        module_: b"m",
        name: b"mem",
        desc: @core.ImportDesc::Mem({ limits: { min: 1U, max: None } }),
      },
      { module_: b"m", name: b"f", desc: @core.ImportDesc::Func(0U) },
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
    stack: [],
    locals: [],
    pc: 0,
    running: false,
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
  assert_eq(rt.stack, [Value::I32(1U)])
}

///|
test "compile helpers tail call return branches" {
  let rt = make_runtime([], [], 0)
  rt.running = true
  rt.call_stack.push(CallFrame::{ return_pc: 3, locals: [Value::I32(7U)] })
  assert_ok(rt.handle_tail_call_return())
  assert_eq(rt.pc, 4)
  assert_eq(rt.locals, [Value::I32(7U)])
  let rt_empty = make_runtime([], [], 0)
  rt_empty.running = true
  assert_ok(rt_empty.handle_tail_call_return())
  assert_eq(rt_empty.running, false)
}
