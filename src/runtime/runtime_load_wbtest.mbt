///|
fn make_expr(instrs : Array[@core.Instr]) -> @core.Expr {
  @core.Expr::{ instrs, }
}

///|
test "runtime load with resolver" {
  let func_type : @core.TypeDef = Func({ params: [], results: [] })
  let mem_type : @core.MemType = {
    limits: { min: 1UL, max: Some(2UL) },
    shared: false,
    memory64: false,
  }
  let table_type : @core.TableType = {
    elem_type: Func,
    limits: { min: 1UL, max: Some(2UL) },
    init: None,
    nullable: true,
    table64: false,
  }
  let data_view = b"hi".sub()
  let module_ : @core.Module = {
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [table_type],
    mems: [],
    globals: [
      {
        type_: { val_type: I32, mutable: false },
        init: make_expr([I32Const(7U)]),
      },
    ],
    tags: [],
    elems: [
      {
        table_idx: 0U,
        offset: make_expr([I32Const(0U)]),
        init: [make_expr([RefFunc(0U)])],
        is_active: true,
        is_declarative: false,
        elem_type: Func,
        elem_nullable: true,
        explicit_table: false,
      },
    ],
    datas: [
      {
        mem_idx: 0U,
        offset: make_expr([I32Const(0U)]),
        init: data_view,
        is_active: true,
      },
    ],
    start: None,
    imports: [
      { module_: b"m", name: b"f", desc: Func(0U) },
      { module_: b"m", name: b"mem", desc: Mem(mem_type) },
      {
        module_: b"m",
        name: b"g0",
        desc: Global({ val_type: I32, mutable: false }),
      },
      {
        module_: b"m",
        name: b"g1",
        desc: Global({ val_type: F64, mutable: false }),
      },
      { module_: b"m", name: b"t0", desc: Table(table_type) },
      { module_: b"m", name: b"t1", desc: Table(table_type) },
    ],
    exports: [],
    codes: [make_code([])],
  }
  let resolver = ImportResolver::new()
  resolver.add_func(b"m", b"f", ImportedFunc::new(0U, fn(_args) { [] }))
  resolver.add_global(b"m", b"g0", Value::I32(42U))
  resolver.add_table(b"m", b"t0", RuntimeTable::{
    data: [None, None],
    max: Some(2UL),
  })
  resolver.add_memory(b"m", b"mem", ImportedMemory::{
    data: Array::make(8, b'\x00'),
    max: Some(2UL),
  })
  let rt = Runtime::load_with_resolver(module_, resolver)
  assert_eq(rt.memory.length(), 8)
  assert_eq(rt.memory[0], b'h')
  assert_eq(rt.memory[1], b'i')
  assert_eq(rt.globals.length(), 3)
  assert_eq(rt.globals[0], Value::I32(42U))
  match rt.globals[1] {
    Value::F64(v) => assert_eq(v, 666.6)
    _ => abort("expected f64 global")
  }
  assert_eq(rt.globals[2], Value::I32(7U))
  assert_eq(rt.tables.length(), 3)
  assert_eq(rt.tables[0].data.length(), 2)
  assert_eq(rt.tables[1].data.length(), 10)
  assert_eq(rt.tables[2].data.length(), 1)
  assert_eq(rt.tables[0].data[0], Some(0))
  assert_eq(rt.data_segments.length(), 1)
  assert_eq(rt.data_segments[0][0], b'h')
}

///|
test "runtime load fallback memory" {
  let mem_type : @core.MemType = {
    limits: { min: 1UL, max: Some(2UL) },
    shared: false,
    memory64: false,
  }
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
    imports: [{ module_: b"m", name: b"mem", desc: Mem(mem_type) }],
    exports: [],
    codes: [],
  }
  let rt = Runtime::load_with_resolver(module_, ImportResolver::new())
  assert_eq(rt.memory.length(), 65536)
  assert_eq(rt.memory_max, Some(2UL))
}

///|
test "runtime load local memory" {
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
    exports: [],
    codes: [],
  }
  let rt = Runtime::load_with_resolver(module_, ImportResolver::new())
  assert_eq(rt.memory.length(), 65536)
  assert_eq(rt.memory_max, None)
}

///|
test "runtime load missing imported function" {
  let func_type : @core.TypeDef = Func({ params: [], results: [] })
  let module_ : @core.Module = {
    types: [func_type],
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
    imports: [{ module_: b"m", name: b"f", desc: Func(0U) }],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = Runtime::load_with_resolver(module_, ImportResolver::new()) catch {
    _ => {
      saw_error = true
      make_runtime([], [], 0)
    }
  }
  assert_eq(saw_error, true)
}

///|
test "eval const expr values" {
  let globals = [Value::I32(4U)]
  let add_expr = make_expr([I32Const(3U), GlobalGet(0U), I32Add])
  assert_eq(eval_const_expr(add_expr, globals), Value::I32(7U))
  let sub_expr = make_expr([I32Const(5U), I32Const(2U), I32Sub])
  assert_eq(eval_const_expr(sub_expr, []), Value::I32(3U))
  let mul_expr = make_expr([I32Const(2U), I32Const(4U), I32Mul])
  assert_eq(eval_const_expr(mul_expr, []), Value::I32(8U))
  let i64_expr = make_expr([I64Const(10UL)])
  assert_eq(eval_const_expr(i64_expr, []), Value::I64(10UL))
  let i64_add = make_expr([I64Const(1UL), I64Const(2UL), I64Add])
  assert_eq(eval_const_expr(i64_add, []), Value::I64(3UL))
  let i64_sub = make_expr([I64Const(5UL), I64Const(3UL), I64Sub])
  assert_eq(eval_const_expr(i64_sub, []), Value::I64(2UL))
  let i64_mul = make_expr([I64Const(2UL), I64Const(6UL), I64Mul])
  assert_eq(eval_const_expr(i64_mul, []), Value::I64(12UL))
  let ref_expr = make_expr([RefFunc(2U)])
  assert_eq(eval_const_expr(ref_expr, []), Value::Ref(Some(2)))
}

///|
test "eval const expr errors" {
  let mut saw_error = false
  let _ = eval_const_expr(make_expr([]), []) catch {
    _ => {
      saw_error = true
      Value::I32(0U)
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = eval_const_expr(make_expr([GlobalGet(0U)]), []) catch {
    _ => {
      saw_error = true
      Value::I32(0U)
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = eval_const_expr(make_expr([I32Const(1U), F32Const(1.0), I32Add]), []) catch {
    _ => {
      saw_error = true
      Value::I32(0U)
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = eval_const_expr(make_expr([Nop]), []) catch {
    _ => {
      saw_error = true
      Value::I32(0U)
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = eval_const_expr(make_expr([I32Const(1U), I32Const(2U)]), []) catch {
    _ => {
      saw_error = true
      Value::I32(0U)
    }
  }
  assert_eq(saw_error, true)
}
