///|
fn make_const_module(value : UInt, name : Bytes) -> @core.Module {
  let func_type : @core.FuncType = { params: [], results: [I32] }
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [I32Const(value)] },
    compiled: None,
  }
  @core.Module::{
    types: [func_type],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [@core.Export::{ name, desc: Func(0U) }],
    codes: [code],
  }
}

///|
fn make_import_call_module() -> @core.Module {
  let func_type : @core.FuncType = { params: [], results: [I32] }
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [Call(0U)] },
    compiled: None,
  }
  let import_ : @core.Import = { module_: b"m", name: b"f", desc: Func(0U) }
  let export_ : @core.Export = { name: b"call_imported", desc: Func(1U) }
  @core.Module::{
    types: [func_type],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_],
    exports: [export_],
    codes: [code],
  }
}

///|
test "runtime call compiled constant" {
  let module_ = make_const_module(42U, b"answer")
  let runtime = Runtime::load(module_)
  runtime.compile()
  let results = runtime.call_compiled(b"answer", [])
  assert_eq(results.length(), 1)
  assert_eq(results[0], Value::I32(42U))
}

///|
test "runtime call imported function" {
  let module_ = make_import_call_module()
  let resolver = ImportResolver::new()
  let imported = ImportedFunc::new(0U, fn(_args) { [Value::I32(7U)] })
  resolver.add_func(b"m", b"f", imported)
  let runtime = Runtime::load_with_resolver(module_, resolver)
  runtime.compile()
  let results = runtime.call_compiled(b"call_imported", [])
  assert_eq(results.length(), 1)
  assert_eq(results[0], Value::I32(7U))
}

///|
test "runtime evaluates global init expr" {
  let global_type : @core.GlobalType = { val_type: I32, mutable: false }
  let global_ : @core.Global = {
    type_: global_type,
    init: @core.Expr::{ instrs: [I32Const(1U), I32Const(2U), I32Add] },
  }
  let module_ : @core.Module = {
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [global_],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let runtime = Runtime::load(module_)
  let globals = runtime.get_globals()
  assert_eq(globals.length(), 1)
  assert_eq(globals[0], Value::I32(3U))
}
