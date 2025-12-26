///|
fn module_with(
  types : Array[@core.TypeDef],
  funcs : Array[UInt],
  codes : Array[@core.Code],
  imports : Array[@core.Import],
  exports : Array[@core.Export],
  start : UInt?,
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
    start,
    imports,
    exports,
    codes,
  }
}

///|
test "runtime compile start function" {
  let func_type : @core.TypeDef = Func({ params: [], results: [] })
  let code : @core.Code = {
    locals: [I32],
    body: @core.Expr::{ instrs: [] },
    compiled: None,
    max_stack_height: 0,
  }
  let module_ = module_with([func_type], [0U], [code], [], [], Some(0U))
  let rt = Runtime::load_with_resolver(module_, ImportResolver::new())
  rt.compile()
  assert_eq(rt.ops.length() > 0, true)
  // Stack is cleared after start function execution (unified stack model)
  assert_eq(rt.stack_top, 0)
}

///|
test "runtime execute error branches" {
  let rt_unimpl = make_runtime([], [ImmediateI32(0U)], 0)
  let mut saw_unimpl = false
  rt_unimpl.execute() catch {
    _ => saw_unimpl = true
  }
  assert_eq(saw_unimpl, true)
  let rt_err = make_runtime(
    [],
    [
      WasmInstr(fn(rt) {
        rt.error_detail = "bad"
        rt.status = Trap
      }),
    ],
    0,
  )
  let mut saw_invalid = false
  rt_err.execute() catch {
    _ => saw_invalid = true
  }
  assert_eq(saw_invalid, true)
}

///|
test "runtime call compiled imported func" {
  let func_type : @core.TypeDef = Func({ params: [], results: [I32] })
  let module_ = module_with(
    [func_type],
    [],
    [],
    [{ module_: b"m", name: b"f", desc: Func(0U) }],
    [{ name: b"f", desc: Func(0U) }],
    None,
  )
  let resolver = ImportResolver::new()
  resolver.add_func(
    b"m",
    b"f",
    ImportedFunc::new(0U, fn(_args) { [Value::I32(7U)] }),
  )
  let rt = Runtime::load_with_resolver(module_, resolver)
  let results = rt.call_compiled(b"f", [])
  assert_eq(results, [Value::I32(7U)])
}

///|
test "runtime call compiled non func export" {
  let mem_type : @core.MemType = {
    limits: { min: 1UL, max: None },
    shared: false,
    memory64: false,
  }
  let module_ : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [mem_type],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [{ name: b"mem", desc: Mem(0U) }],
    codes: [],
  }
  let rt = Runtime::load_with_resolver(module_, ImportResolver::new())
  let mut saw_error = false
  let _ = rt.call_compiled(b"mem", []) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
}

///|
test "runtime call compiled local errors" {
  // Test that unsupported local type (V128) causes error during call
  let func_type : @core.FuncType = { params: [], results: [] }
  let code_bad : @core.Code = {
    locals: [V128],
    body: @core.Expr::{ instrs: [] },
    compiled: Some(0),
    max_stack_height: 0,
  }
  let module_bad = module_with(
    [Func(func_type)],
    [0U],
    [code_bad],
    [],
    [{ name: b"bad", desc: Func(0U) }],
    None,
  )
  let rt_bad = Runtime::load_with_resolver(module_bad, ImportResolver::new())
  let mut saw_bad = false
  let _ = rt_bad.call_compiled(b"bad", []) catch {
    _ => {
      saw_bad = true
      []
    }
  }
  assert_eq(saw_bad, true)
}
