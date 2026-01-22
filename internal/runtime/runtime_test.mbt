///|
fn make_const_module(value : UInt, name : Bytes) -> @core.Module {
  let func_type : @core.TypeDef = Func({ params: [], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [I32Const(value)] },
    compiled: None,
    max_stack_height: 0,
  }
  @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
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
  let func_type : @core.TypeDef = Func({ params: [], results: [I32] })
  let code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: [Call(0U)] },
    compiled: None,
    max_stack_height: 0,
  }
  let import_ : @core.Import = { module_: b"m", name: b"f", desc: Func(0U) }
  let export_ : @core.Export = { name: b"call_imported", desc: Func(1U) }
  @core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_],
    exports: [export_],
    codes: [code],
  }
}

///|
fn make_memory_global_table_module() -> @core.Module {
  let mem_type : @core.MemType = {
    limits: { min: 1UL, max: Some(2UL) },
    shared: false,
    memory64: false,
  }
  let table_type : @core.TableType = {
    elem_type: @core.Func,
    limits: { min: 1UL, max: None },
    init: None,
    nullable: true,
    table64: false,
  }
  let global_type : @core.GlobalType = { val_type: I32, mutable: true }
  let global_ : @core.Global = {
    type_: global_type,
    init: @core.Expr::{ instrs: [I32Const(10U)] },
  }
  @core.Module::{
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [table_type],
    mems: [mem_type],
    globals: [global_],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @core.Export::{ name: b"memory", desc: Mem(0U) },
      @core.Export::{ name: b"table", desc: Table(0U) },
      @core.Export::{ name: b"global", desc: Global(0U) },
    ],
    codes: [],
  }
}

///|
test "runtime call compiled constant" {
  let module_ = make_const_module(42U, b"answer")
  let runtime = Instance::new(module_, Imports::new())
  runtime.run_start()
  let results = runtime.call_compiled(b"answer", [])
  assert_eq(results.length(), 1)
  assert_eq(results[0], Value::I32(42U))
}

///|
test "runtime call imported function" {
  let module_ = make_import_call_module()
  let resolver = Imports::new()
  let imported = HostFunc::new(fn(_args) { [Value::I32(7U)] })
  resolver.add_func(b"m", b"f", imported)
  let runtime = Instance::new(module_, resolver)
  runtime.run_start()
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
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [global_],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let runtime = Instance::new(module_, Imports::new())
  let globals = runtime.get_globals()
  assert_eq(globals.length(), 1)
  assert_eq(globals[0], Value::I32(3U))
}

///|
test "typed func export" {
  let module_ = make_const_module(7U, b"answer")
  let runtime = Instance::new(module_, Imports::new())
  match runtime.get_func("answer") {
    Some(func) => {
      let results = func.call([])
      assert_eq(results.length(), 1)
      assert_eq(results[0], Value::I32(7U))
    }
    None => abort("expected func export")
  }
}

///|
test "typed memory/global/table exports" {
  let module_ = make_memory_global_table_module()
  let runtime = Instance::new(module_, Imports::new())
  match runtime.get_memory("memory") {
    Some(memory) => {
      let data = Bytes::from_array([b'h', b'i'])
      memory.write(0, data)
      let read = memory.read(0, 2)
      assert_eq(read, data)
      assert_eq(memory.size(), 1)
    }
    None => abort("expected memory export")
  }
  match runtime.get_global("global") {
    Some(global) => {
      assert_eq(global.get(), Value::I32(10U))
      global.set(Value::I32(12U))
      assert_eq(global.get(), Value::I32(12U))
    }
    None => abort("expected global export")
  }
  match runtime.get_table("table") {
    Some(table) => {
      assert_eq(table.size(), 1)
      table.set(0, Value::Funcref(Some(0)))
      match table.get(0) {
        Some(_) => ()
        None => abort("expected table element")
      }
    }
    None => abort("expected table export")
  }
}
