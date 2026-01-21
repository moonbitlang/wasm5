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
  rt.run_start()
  assert_eq(rt.ops.length() > 0, true)
  // Stack is cleared after start function execution (unified stack model)
  assert_eq(rt.sp, 0)
}

///|
test "runtime execute error branches" {
  // Use the unreachable opcode to force a trap in the dispatcher.
  let rt_err = make_runtime([], [0UL], 0)
  let mut saw_invalid = false
  let _ = execute(rt_err) catch {
    _ => {
      saw_invalid = true
      rt_err
    }
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
  // The error is now detected at compile time and emitted as a trap instruction
  let func_type : @core.FuncType = { params: [], results: [] }
  let code_bad : @core.Code = {
    locals: [V128],
    body: @core.Expr::{ instrs: [] },
    compiled: None, // Let it be compiled - will emit op_local_init_unsupported
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
