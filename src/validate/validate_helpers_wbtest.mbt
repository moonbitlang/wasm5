///|
test "validate helper ref type conversions" {
  assert_eq(reftype_to_valtype(Extern), ExternRef)
  assert_eq(reftype_to_valtype(Any), AnyRef)
  assert_eq(reftype_to_valtype(Eq), EqRef)
  assert_eq(reftype_to_valtype(I31), I31Ref)
  assert_eq(reftype_to_valtype(Struct), StructRef)
  assert_eq(reftype_to_valtype(Array), ArrayRef)
  assert_eq(reftype_to_valtype(Exn), ExnRef)
  assert_eq(reftype_to_valtype(None), NullRef)
  assert_eq(reftype_to_valtype(NoFunc), NullFuncRef)
  assert_eq(reftype_to_valtype(NoExtern), NullExternRef)
  assert_eq(reftype_to_valtype(NoExn), NullExnRef)
  assert_eq(reftype_to_valtype(TypeIndex(3)), Ref(TypeIndex(3), true))
}

///|
test "validate helper counts and type lookup" {
  let func_type0 : @core.FuncType = { params: [], results: [] }
  let func_type1 : @core.FuncType = { params: [I32], results: [I32] }
  let table_type : @core.TableType = {
    elem_type: Func,
    limits: { min: 0UL, max: None },
    init: None,
    nullable: true,
    table64: false,
  }
  let mem_type : @core.MemType = {
    limits: { min: 0UL, max: None },
    shared: false,
    memory64: false,
  }
  let global_type : @core.GlobalType = { val_type: I32, mutable: false }
  let imports : Array[@core.Import] = [
    {
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'f']),
      desc: Func(1U),
    },
    {
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b't']),
      desc: Table(table_type),
    },
    {
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'm']),
      desc: Mem(mem_type),
    },
    {
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'g']),
      desc: Global(global_type),
    },
  ]
  let module_ : @core.Module = {
    types: [Func(func_type0), Func(func_type1)],
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
    imports,
    exports: [],
    codes: [],
  }
  let counts = get_import_counts(module_)
  assert_eq(counts.funcs, 1)
  assert_eq(counts.tables, 1)
  assert_eq(counts.mems, 1)
  assert_eq(counts.globals, 1)
  let type_idx_import = get_func_type_index(module_, 0, counts)
  assert_eq(type_idx_import, 1)
  let type_idx_local = get_func_type_index(module_, 1, counts)
  assert_eq(type_idx_local, 0)
  let mut saw_error = false
  let _ = get_func_type_index(module_, 2, counts) catch {
    _ => {
      saw_error = true
      0
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate helper import scan in func lookup" {
  let func_type : @core.FuncType = { params: [], results: [] }
  let table_type : @core.TableType = {
    elem_type: Func,
    limits: { min: 0UL, max: None },
    init: None,
    nullable: true,
    table64: false,
  }
  let module_ : @core.Module = {
    types: [Func(func_type)],
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
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b't']),
        desc: Table(table_type),
      },
      {
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'f']),
        desc: Func(0U),
      },
    ],
    exports: [],
    codes: [],
  }
  let counts = get_import_counts(module_)
  let type_idx = get_func_type_index(module_, 0, counts)
  assert_eq(type_idx, 0)
}

///|
test "validate const expr checks" {
  let valid_expr : @core.Expr = { instrs: [I32Const(0U), I32Const(1U), I32Add] }
  validate_const_expr_instructions(valid_expr)
  let mut saw_error = false
  let _ = validate_const_expr_instructions({ instrs: [Nop] }) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_empty = test_empty_module()
  let expr_global : @core.Expr = { instrs: [GlobalGet(0U)] }
  saw_error = false
  let _ = validate_table_init_expr(
    module_empty,
    expr_global,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_imported : @core.Module = {
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
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: Global({ val_type: I32, mutable: true }),
      },
    ],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_table_init_expr(
    module_imported,
    expr_global,
    get_import_counts(module_imported),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_scan : @core.Module = {
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
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b't']),
        desc: Table({
          elem_type: Func,
          limits: { min: 0UL, max: None },
          init: None,
          nullable: true,
          table64: false,
        }),
      },
      {
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: Global({ val_type: I32, mutable: false }),
      },
    ],
    exports: [],
    codes: [],
  }
  validate_table_init_expr(
    module_scan,
    expr_global,
    get_import_counts(module_scan),
  )
  let module_local : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      {
        type_: { val_type: I32, mutable: true },
        init: { instrs: [I32Const(0U)] },
      },
    ],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_const_expr_globals(
    module_local,
    expr_global,
    get_import_counts(module_local),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_import_const : @core.Module = {
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
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: Global({ val_type: I32, mutable: false }),
      },
    ],
    exports: [],
    codes: [],
  }
  validate_const_expr_globals(
    module_import_const,
    expr_global,
    get_import_counts(module_import_const),
  )
  let module_import_scan : @core.Module = {
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
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'f']),
        desc: Func(0U),
      },
      {
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: Global({ val_type: I32, mutable: false }),
      },
    ],
    exports: [],
    codes: [],
  }
  validate_const_expr_globals(
    module_import_scan,
    expr_global,
    get_import_counts(module_import_scan),
  )
}

///|
test "validate valtype and subtype" {
  let module_empty = test_empty_module()
  let mut saw_error = false
  let _ = validate_valtype(module_empty, Ref(TypeIndex(0), true)) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_types : @core.Module = {
    types: [Func({ params: [], results: [] })],
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
    imports: [],
    exports: [],
    codes: [],
  }
  assert_eq(is_subtype(module_types, NullRef, AnyRef), true)
  assert_eq(
    is_subtype(module_types, NullFuncRef, Ref(TypeIndex(0), true)),
    true,
  )
  assert_eq(
    is_subtype(module_types, Ref(TypeIndex(0), false), Ref(Func, false)),
    true,
  )
  assert_eq(is_subtype(module_types, FuncRef, Ref(TypeIndex(0), true)), false)
  assert_eq(is_subtype(module_types, Ref(Extern, false), ExternRef), true)
  assert_eq(is_subtype(module_types, Ref(Any, false), AnyRef), true)
  assert_eq(is_subtype(module_types, NullFuncRef, FuncRef), true)
  assert_eq(is_subtype(module_types, NullExternRef, ExternRef), true)
  assert_eq(is_subtype(module_types, NullExnRef, ExnRef), true)
  assert_eq(is_subtype(module_types, NullFuncRef, Ref(Func, true)), true)
  assert_eq(is_subtype(module_types, I31Ref, EqRef), true)
  assert_eq(is_subtype(module_types, StructRef, AnyRef), true)
  assert_eq(is_subtype(module_types, ArrayRef, EqRef), true)
  assert_eq(is_subtype(module_types, EqRef, AnyRef), true)
  assert_eq(is_subtype(module_types, FuncRef, AnyRef), true)
  assert_eq(is_subtype(module_types, ExnRef, AnyRef), true)
  assert_eq(is_subtype(module_types, Ref(Func, false), FuncRef), true)
  assert_eq(is_subtype(module_types, Ref(TypeIndex(0), true), FuncRef), true)
  assert_eq(
    is_subtype(module_types, Ref(TypeIndex(0), true), Ref(Func, true)),
    true,
  )
  assert_eq(is_subtype(module_types, FuncRef, Ref(Func, true)), true)
  assert_eq(is_subtype(module_types, Ref(Exn, false), ExnRef), true)
  assert_eq(is_subtype(module_types, Ref(Struct, false), AnyRef), true)
}

///|
test "validate alignment and memory exists" {
  let mut saw_error = false
  let _ = validate_alignment(3U, 4) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = validate_alignment(4U, 12) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let module_empty = test_empty_module()
  let _ = validate_memory_index(
    module_empty,
    get_import_counts(module_empty),
    0U,
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validation context pop errors" {
  let module_empty = test_empty_module()
  let ctx = ValidationCtx::new()
  let mut saw_error = false
  let _ = ctx.poly_pop_expect(module_empty, I32, "pop") catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  ctx.stack.push(I64)
  ctx.mark_unreachable()
  ctx.stack.push(I64)
  ctx.poly_pop_expect(module_empty, I64, "pop ok")
  assert_eq(ctx.stack.length(), 0)
  let func_type : @core.FuncType = { params: [I32], results: [] }
  let code = test_make_code([], [])
  let ctx_locals = ValidationCtx::new_with_locals(func_type, code)
  assert_eq(ctx_locals.initialized_locals.length(), 1)
  assert_eq(ctx_locals.initialized_locals[0], true)
  saw_error = false
  let ctx_label = ValidationCtx::new()
  let _ = ctx_label.get_label_types(0U) catch {
    _ => {
      saw_error = true
      []
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_mismatch = ValidationCtx::new()
  ctx_mismatch.stack.push(I64)
  let _ = ctx_mismatch.poly_pop_expect(module_empty, I32, "mismatch") catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}
