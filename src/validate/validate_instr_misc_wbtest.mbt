///|
fn test_module_with_memory() -> @core.Module {
  {
    types: [],
    type_groups: [],
    funcs: [],
    tables: [],
    mems: [{ limits: { min: 0U, max: None }, shared: false }],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
}

///|
fn test_module_with_table(elem_type : @core.RefType) -> @core.Module {
  {
    types: [],
    type_groups: [],
    funcs: [],
    tables: [
      { elem_type, limits: { min: 0U, max: None }, init: None, nullable: true },
    ],
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
}

///|
test "validate variable instruction errors" {
  let module_empty = test_empty_module()
  let func_type : @core.FuncType = { params: [], results: [] }
  let code = test_make_code([], [])
  let ctx = ValidationCtx::new_with_locals(func_type, code)
  let mut saw_error = false
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx,
    get_import_counts(module_empty),
    LocalGet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let code_uninit = test_make_code([Ref(Func, false)], [])
  let ctx_uninit = ValidationCtx::new_with_locals(func_type, code_uninit)
  saw_error = false
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code_uninit,
    ctx_uninit,
    get_import_counts(module_empty),
    LocalGet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_global = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx_global,
    get_import_counts(module_empty),
    GlobalGet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let module_global : @core.Module = {
    types: [],
    type_groups: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      {
        type_: { val_type: I32, mutable: false },
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
  let ctx_set = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_global,
    func_type,
    code,
    ctx_set,
    get_import_counts(module_global),
    GlobalSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let func_type_params : @core.FuncType = { params: [I32], results: [] }
  let code_params = test_make_code([], [])
  let ctx_param_get = ValidationCtx::new_with_locals(
    func_type_params, code_params,
  )
  let ok = validate_instruction_variable(
    module_empty,
    func_type_params,
    code_params,
    ctx_param_get,
    get_import_counts(module_empty),
    LocalGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_param_get.stack.length(), 1)
  saw_error = false
  let ctx_bad_set = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx_bad_set,
    get_import_counts(module_empty),
    LocalSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_bad_tee = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx_bad_tee,
    get_import_counts(module_empty),
    LocalTee(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_set_local = ValidationCtx::new()
  ctx_set_local.stack.push(I32)
  let ok = validate_instruction_variable(
    module_empty,
    func_type_params,
    code_params,
    ctx_set_local,
    get_import_counts(module_empty),
    LocalSet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_set_local.initialized_locals.length() > 0, true)
  let ctx_tee_local = ValidationCtx::new()
  ctx_tee_local.stack.push(I32)
  let ok = validate_instruction_variable(
    module_empty,
    func_type_params,
    code_params,
    ctx_tee_local,
    get_import_counts(module_empty),
    LocalTee(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_tee_local.initialized_locals.length() > 0, true)
  let module_imported : @core.Module = {
    types: [],
    type_groups: [],
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
        desc: Global({ val_type: I64, mutable: false }),
      },
    ],
    exports: [],
    codes: [],
  }
  let ctx_import_get = ValidationCtx::new()
  let ok = validate_instruction_variable(
    module_imported,
    func_type,
    code,
    ctx_import_get,
    get_import_counts(module_imported),
    GlobalGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_import_get.stack[0], I64)
  let module_imported_mut : @core.Module = {
    types: [],
    type_groups: [],
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
  let ctx_import_set = ValidationCtx::new()
  ctx_import_set.stack.push(I32)
  let ok = validate_instruction_variable(
    module_imported_mut,
    func_type,
    code,
    ctx_import_set,
    get_import_counts(module_imported_mut),
    GlobalSet(0U),
  )
  assert_eq(ok, true)
  let module_import_scan : @core.Module = {
    types: [],
    type_groups: [],
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
        desc: Global({ val_type: I32, mutable: true }),
      },
    ],
    exports: [],
    codes: [],
  }
  let ctx_scan_get = ValidationCtx::new()
  let ok = validate_instruction_variable(
    module_import_scan,
    func_type,
    code,
    ctx_scan_get,
    get_import_counts(module_import_scan),
    GlobalGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_scan_get.stack[0], I32)
  let ctx_scan_set = ValidationCtx::new()
  ctx_scan_set.stack.push(I32)
  let ok = validate_instruction_variable(
    module_import_scan,
    func_type,
    code,
    ctx_scan_set,
    get_import_counts(module_import_scan),
    GlobalSet(0U),
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_bad_global = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx_bad_global,
    get_import_counts(module_empty),
    GlobalSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate parametric instruction errors" {
  let module_empty = test_empty_module()
  let mut saw_error = false
  let ctx_non_numeric = ValidationCtx::new()
  ctx_non_numeric.stack.push(FuncRef)
  ctx_non_numeric.stack.push(FuncRef)
  ctx_non_numeric.stack.push(I32)
  let _ = validate_instruction_parametric(module_empty, ctx_non_numeric, Select) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_incompatible = ValidationCtx::new()
  ctx_incompatible.stack.push(I32)
  ctx_incompatible.stack.push(I64)
  ctx_incompatible.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_incompatible,
    Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_bad_arity = ValidationCtx::new()
  ctx_bad_arity.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_bad_arity,
    SelectTyped([I32, I64]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_bad_type = ValidationCtx::new()
  ctx_bad_type.stack.push(I64)
  ctx_bad_type.stack.push(I64)
  ctx_bad_type.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_bad_type,
    SelectTyped([I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_drop = ValidationCtx::new()
  ctx_drop.stack.push(I32)
  let ok = validate_instruction_parametric(module_empty, ctx_drop, Drop)
  assert_eq(ok, true)
  assert_eq(ctx_drop.stack.length(), 0)
  let mut saw_error = false
  let ctx_drop_empty = ValidationCtx::new()
  let _ = validate_instruction_parametric(module_empty, ctx_drop_empty, Drop) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  ctx_unreachable.stack.push(I32)
  ctx_unreachable.stack.push(I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_unreachable,
    Select,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable.stack.length(), 1)
  saw_error = false
  let ctx_unreachable_bad = ValidationCtx::new()
  ctx_unreachable_bad.mark_unreachable()
  ctx_unreachable_bad.stack.push(ExternRef)
  ctx_unreachable_bad.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_unreachable_bad,
    Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_unreachable_empty = ValidationCtx::new()
  ctx_unreachable_empty.mark_unreachable()
  ctx_unreachable_empty.stack.push(I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_unreachable_empty,
    Select,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable_empty.stack[0], I32)
  saw_error = false
  let ctx_missing = ValidationCtx::new()
  ctx_missing.stack.push(I32)
  ctx_missing.stack.push(I32)
  let _ = validate_instruction_parametric(module_empty, ctx_missing, Select) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_condition_only = ValidationCtx::new()
  ctx_condition_only.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_condition_only,
    Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_typed_unreachable = ValidationCtx::new()
  ctx_typed_unreachable.mark_unreachable()
  ctx_typed_unreachable.stack.push(I32)
  ctx_typed_unreachable.stack.push(I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_typed_unreachable,
    SelectTyped([I32]),
  )
  assert_eq(ok, true)
  assert_eq(ctx_typed_unreachable.stack.length(), 1)
  saw_error = false
  let ctx_typed_bad_val2 = ValidationCtx::new()
  ctx_typed_bad_val2.stack.push(I32)
  ctx_typed_bad_val2.stack.push(I64)
  ctx_typed_bad_val2.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_bad_val2,
    SelectTyped([I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_typed_unreachable_bad = ValidationCtx::new()
  ctx_typed_unreachable_bad.mark_unreachable()
  ctx_typed_unreachable_bad.stack.push(I64)
  ctx_typed_unreachable_bad.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_unreachable_bad,
    SelectTyped([I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_typed_missing = ValidationCtx::new()
  ctx_typed_missing.stack.push(I32)
  ctx_typed_missing.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_missing,
    SelectTyped([I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_typed_condition_only = ValidationCtx::new()
  ctx_typed_condition_only.stack.push(I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_condition_only,
    SelectTyped([I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_typed_empty = ValidationCtx::new()
  ctx_typed_empty.mark_unreachable()
  ctx_typed_empty.stack.push(I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_typed_empty,
    SelectTyped([I32]),
  )
  assert_eq(ok, true)
  assert_eq(ctx_typed_empty.stack.length(), 1)
  let ctx_other = ValidationCtx::new()
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_other,
    I32Const(0U),
  )
  assert_eq(ok, false)
}

///|
test "validate memory instruction errors" {
  let module_mem = test_module_with_memory()
  let counts = get_import_counts(module_mem)
  let mut saw_error = false
  let ctx_init = ValidationCtx::new()
  let _ = validate_instruction_memory(
    module_mem,
    ctx_init,
    counts,
    MemoryInit(0U, 0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_drop = ValidationCtx::new()
  let _ = validate_instruction_memory(
    module_mem,
    ctx_drop,
    counts,
    DataDrop(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_align = ValidationCtx::new()
  ctx_align.stack.push(I32)
  let _ = validate_instruction_memory(
    module_mem,
    ctx_align,
    counts,
    I32Load(3U, 0U, 0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_load = ValidationCtx::new()
  ctx_load.stack.push(I32)
  let ok = validate_instruction_memory(
    module_mem,
    ctx_load,
    counts,
    I32Load(0U, 0U, 0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_load.stack.length(), 1)
  assert_eq(ctx_load.stack[0], I32)
}

///|
test "validate reference instruction errors" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let mut saw_error = false
  let ctx_ref_func = ValidationCtx::new()
  let _ = validate_instruction_reference(
    module_empty,
    ctx_ref_func,
    counts,
    RefFunc(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_ref_is_null = ValidationCtx::new()
  let _ = validate_instruction_reference(
    module_empty,
    ctx_ref_is_null,
    counts,
    RefIsNull,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_ref_null = ValidationCtx::new()
  let ok = validate_instruction_reference(
    module_empty,
    ctx_ref_null,
    counts,
    RefNull(Extern),
  )
  assert_eq(ok, true)
  assert_eq(ctx_ref_null.stack.length(), 1)
  assert_eq(ctx_ref_null.stack[0], ExternRef)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  let ok = validate_instruction_reference(
    module_empty,
    ctx_unreachable,
    counts,
    RefIsNull,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable.stack.length(), 1)
}

///|
test "validate table instruction errors" {
  let module_table = test_module_with_table(Func)
  let mut saw_error = false
  let ctx_set = ValidationCtx::new()
  ctx_set.stack.push(I32)
  ctx_set.stack.push(ExternRef)
  let _ = validate_instruction_table(module_table, ctx_set, TableSet(0U)) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_grow = ValidationCtx::new()
  ctx_grow.stack.push(I32)
  let _ = validate_instruction_table(module_table, ctx_grow, TableGrow(0U)) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_get = ValidationCtx::new()
  ctx_get.stack.push(I32)
  let ok = validate_instruction_table(module_table, ctx_get, TableGet(0U))
  assert_eq(ok, true)
  assert_eq(ctx_get.stack[0], FuncRef)
  let ctx_missing = ValidationCtx::new()
  ctx_missing.stack.push(I32)
  let ok = validate_instruction_table(module_table, ctx_missing, TableGet(9U))
  assert_eq(ok, true)
  assert_eq(ctx_missing.stack[0], FuncRef)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  let ok = validate_instruction_table(
    module_table,
    ctx_unreachable,
    TableSet(0U),
  )
  assert_eq(ok, true)
  let mut saw_error = false
  let ctx_empty = ValidationCtx::new()
  let _ = validate_instruction_table(module_table, ctx_empty, TableSet(0U)) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_missing_table = ValidationCtx::new()
  ctx_missing_table.stack.push(ExternRef)
  let _ = validate_instruction_table(
    module_table,
    ctx_missing_table,
    TableSet(2U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_grow_unreachable = ValidationCtx::new()
  ctx_grow_unreachable.mark_unreachable()
  let ok = validate_instruction_table(
    module_table,
    ctx_grow_unreachable,
    TableGrow(0U),
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_grow_mismatch = ValidationCtx::new()
  ctx_grow_mismatch.stack.push(ExternRef)
  ctx_grow_mismatch.stack.push(I32)
  let _ = validate_instruction_table(
    module_table,
    ctx_grow_mismatch,
    TableGrow(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_grow_default = ValidationCtx::new()
  ctx_grow_default.stack.push(I32)
  ctx_grow_default.stack.push(I32)
  let _ = validate_instruction_table(
    module_table,
    ctx_grow_default,
    TableGrow(3U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate control instruction branches" {
  let func_type : @core.FuncType = { params: [I32], results: [I32] }
  let module_funcs : @core.Module = {
    types: [Func(func_type)],
    type_groups: [],
    funcs: [0U],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0U, max: None },
        init: None,
        nullable: true,
      },
    ],
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
  let counts = get_import_counts(module_funcs)
  let code = test_make_code([], [])
  let mut saw_error = false
  let _ = get_block_type(test_empty_module(), TypeIndex(1)) catch {
    _ => {
      saw_error = true
      ([], [])
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = validate_tail_call_return_type(
    test_empty_module(),
    { params: [], results: [I32] },
    { params: [], results: [] },
    "return_call",
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = validate_tail_call_return_type(
    test_empty_module(),
    { params: [], results: [I64] },
    { params: [], results: [I32] },
    "return_call",
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let ctx_block = ValidationCtx::new()
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_block,
    Block(Empty, []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_loop = ValidationCtx::new()
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_loop,
    Loop(Empty, []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_if = ValidationCtx::new()
  ctx_if.stack.push(I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_if,
    If(Empty, [], []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_br = ValidationCtx::new()
  ctx_br.push_control([], [I32])
  ctx_br.stack.push(I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_br,
    Br(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br.is_unreachable, true)
  let ctx_br_if = ValidationCtx::new()
  ctx_br_if.push_control([], [I32])
  ctx_br_if.stack.push(I32)
  ctx_br_if.stack.push(I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_br_if,
    BrIf(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_if.stack.length(), 1)
  let ctx_br_table = ValidationCtx::new()
  ctx_br_table.push_control([], [I32])
  ctx_br_table.stack.push(I32)
  ctx_br_table.stack.push(I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_br_table,
    BrTable([], 0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_table.is_unreachable, true)
  let ctx_br_on_null = ValidationCtx::new()
  ctx_br_on_null.stack.push(FuncRef)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_br_on_null,
    BrOnNull(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_on_null.stack[0], Ref(Func, false))
  let ctx_br_on_non_null = ValidationCtx::new()
  ctx_br_on_non_null.stack.push(FuncRef)
  let ok = validate_instruction_control(
    test_empty_module(),
    { params: [], results: [] },
    code,
    ctx_br_on_non_null,
    BrOnNonNull(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_on_non_null.stack.length(), 0)
  saw_error = false
  let ctx_return = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_funcs,
    { params: [], results: [I32] },
    code,
    ctx_return,
    Return,
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_call = ValidationCtx::new()
  ctx_call.stack.push(I32)
  let ok = validate_instruction_control(
    module_funcs,
    { params: [], results: [] },
    code,
    ctx_call,
    Call(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call.stack.length(), 1)
  let ctx_call_indirect = ValidationCtx::new()
  ctx_call_indirect.stack.push(I32)
  ctx_call_indirect.stack.push(I32)
  let ok = validate_instruction_control(
    module_funcs,
    { params: [], results: [] },
    code,
    ctx_call_indirect,
    CallIndirect(0U, 0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call_indirect.stack.length(), 1)
  let ctx_return_call = ValidationCtx::new()
  ctx_return_call.stack.push(I32)
  let ok = validate_instruction_control(
    module_funcs,
    { params: [I32], results: [I32] },
    code,
    ctx_return_call,
    ReturnCall(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call.is_unreachable, true)
  let ctx_return_call_indirect = ValidationCtx::new()
  ctx_return_call_indirect.stack.push(I32)
  ctx_return_call_indirect.stack.push(I32)
  let ok = validate_instruction_control(
    module_funcs,
    { params: [I32], results: [I32] },
    code,
    ctx_return_call_indirect,
    ReturnCallIndirect(0U, 0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call_indirect.is_unreachable, true)
  let ctx_call_ref = ValidationCtx::new()
  ctx_call_ref.stack.push(I32)
  ctx_call_ref.stack.push(Ref(TypeIndex(0), true))
  let ok = validate_instruction_control(
    module_funcs,
    { params: [], results: [] },
    code,
    ctx_call_ref,
    CallRef(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call_ref.stack.length(), 1)
  let ctx_return_call_ref = ValidationCtx::new()
  ctx_return_call_ref.stack.push(I32)
  ctx_return_call_ref.stack.push(Ref(TypeIndex(0), true))
  let ok = validate_instruction_control(
    module_funcs,
    { params: [I32], results: [I32] },
    code,
    ctx_return_call_ref,
    ReturnCallRef(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call_ref.is_unreachable, true)
}

///|
test "validate control block loop if branches" {
  let block_type : @core.FuncType = { params: [I32], results: [I64] }
  let module_block : @core.Module = {
    types: [Func(block_type)],
    type_groups: [],
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
  let counts = get_import_counts(module_block)
  let code = test_make_code([], [])
  let empty_func : @core.FuncType = { params: [], results: [] }
  let ctx_block = ValidationCtx::new()
  ctx_block.stack.push(I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_block,
    Block(TypeIndex(0), [Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_block.stack[0], I64)
  let mut saw_error = false
  let ctx_block_mismatch = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_block_mismatch,
    Block(Value(I32), []),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_block_type = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_block_type,
    Block(Value(I32), [I64Const(0UL)]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_loop = ValidationCtx::new()
  ctx_loop.stack.push(I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_loop,
    Loop(TypeIndex(0), [Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_loop.stack[0], I64)
  saw_error = false
  let ctx_loop_mismatch = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_loop_mismatch,
    Loop(Value(I32), []),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_loop_type = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_loop_type,
    Loop(Value(I32), [I64Const(0UL)]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_if = ValidationCtx::new()
  ctx_if.stack.push(I32)
  ctx_if.stack.push(I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if,
    If(TypeIndex(0), [Drop, I64Const(0UL)], [Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_if.stack[0], I64)
  saw_error = false
  let ctx_if_then = ValidationCtx::new()
  ctx_if_then.stack.push(I32)
  ctx_if_then.stack.push(I32)
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if_then,
    If(Value(I32), [], []),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_if_else = ValidationCtx::new()
  ctx_if_else.stack.push(I32)
  ctx_if_else.stack.push(I32)
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if_else,
    If(Value(I32), [I32Const(0U)], [I64Const(0UL)]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate control branch errors" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let func_type_ret : @core.FuncType = { params: [], results: [I32] }
  let mut saw_error = false
  let ctx_return_bad = ValidationCtx::new()
  ctx_return_bad.stack.push(I64)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_return_bad,
    Return,
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_br_short = ValidationCtx::new()
  ctx_br_short.push_control([], [I32])
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_short,
    Br(0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_br_mismatch = ValidationCtx::new()
  ctx_br_mismatch.push_control([], [I32])
  ctx_br_mismatch.stack.push(I64)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_mismatch,
    Br(0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_br_unreachable = ValidationCtx::new()
  ctx_br_unreachable.mark_unreachable()
  ctx_br_unreachable.push_control([], [I32, I32])
  ctx_br_unreachable.stack.push(I32)
  let ok = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_unreachable,
    Br(0U),
    counts,
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_br_table_arity = ValidationCtx::new()
  ctx_br_table_arity.push_control([], [])
  ctx_br_table_arity.push_control([], [I32])
  ctx_br_table_arity.stack.push(I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_arity,
    BrTable([1U], 0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_br_table_short = ValidationCtx::new()
  ctx_br_table_short.push_control([], [I32])
  ctx_br_table_short.stack.push(I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_short,
    BrTable([], 0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_br_table_unreachable = ValidationCtx::new()
  ctx_br_table_unreachable.mark_unreachable()
  ctx_br_table_unreachable.push_control([], [I32, I32])
  ctx_br_table_unreachable.stack.push(I32)
  ctx_br_table_unreachable.stack.push(I32)
  let ok = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_unreachable,
    BrTable([], 0U),
    counts,
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_br_table_mismatch = ValidationCtx::new()
  ctx_br_table_mismatch.push_control([], [I32])
  ctx_br_table_mismatch.stack.push(I64)
  ctx_br_table_mismatch.stack.push(I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_mismatch,
    BrTable([], 0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_br_on_null_err = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_on_null_err,
    BrOnNull(0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_br_on_non_null_err = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_on_non_null_err,
    BrOnNonNull(0U),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate control loop results" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let ctx_loop_result = ValidationCtx::new()
  let ok = validate_instruction_control(
    module_empty,
    { params: [], results: [] },
    code,
    ctx_loop_result,
    Loop(Value(I32), [I32Const(0U)]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_loop_result.stack.length(), 1)
  assert_eq(ctx_loop_result.stack[0], I32)
}

///|
test "validate control if branch coverage" {
  let block_type : @core.FuncType = { params: [I32], results: [I32] }
  let module_if : @core.Module = {
    types: [Func(block_type)],
    type_groups: [],
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
  let counts = get_import_counts(module_if)
  let code = test_make_code([], [])
  let empty_func : @core.FuncType = { params: [], results: [] }
  let ctx_then_unreachable = ValidationCtx::new()
  ctx_then_unreachable.stack.push(I32)
  ctx_then_unreachable.stack.push(I32)
  let ok = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_then_unreachable,
    If(TypeIndex(0), [Unreachable], [Drop, I32Const(0U)]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_then_unreachable.stack.length(), 1)
  let ctx_else_unreachable = ValidationCtx::new()
  ctx_else_unreachable.stack.push(I32)
  ctx_else_unreachable.stack.push(I32)
  let ok = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_else_unreachable,
    If(TypeIndex(0), [Drop, I32Const(1U)], [Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_else_unreachable.stack.length(), 1)
  let mut saw_error = false
  let ctx_else_mismatch = ValidationCtx::new()
  ctx_else_mismatch.stack.push(I32)
  let _ = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_else_mismatch,
    If(Value(I32), [I32Const(0U)], []),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_then_mismatch = ValidationCtx::new()
  ctx_then_mismatch.stack.push(I32)
  ctx_then_mismatch.stack.push(I32)
  let _ = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_then_mismatch,
    If(TypeIndex(0), [Drop, I64Const(0UL)], [Drop, I32Const(0U)]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate control returns false on non-control" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let ctx = ValidationCtx::new()
  let ok = validate_instruction_control(
    module_empty,
    { params: [], results: [] },
    code,
    ctx,
    I32Const(0U),
    counts,
  )
  assert_eq(ok, false)
}

///|
test "validate control br_on_null conversions" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let empty_func : @core.FuncType = { params: [], results: [] }
  let ctx_ref_nullable = ValidationCtx::new()
  ctx_ref_nullable.stack.push(Ref(Func, true))
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_ref_nullable,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_ref_nullable.stack[0], Ref(Func, false))
  let ctx_ref_nonnull = ValidationCtx::new()
  ctx_ref_nonnull.stack.push(Ref(Func, false))
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_ref_nonnull,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_ref_nonnull.stack[0], Ref(Func, false))
  let ctx_extern = ValidationCtx::new()
  ctx_extern.stack.push(ExternRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_extern,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_extern.stack[0], Ref(Extern, false))
  let ctx_any = ValidationCtx::new()
  ctx_any.stack.push(AnyRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_any,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_any.stack[0], Ref(Any, false))
  let ctx_null_func = ValidationCtx::new()
  ctx_null_func.stack.push(NullFuncRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_func,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_null_func.stack[0], Ref(Func, false))
  let ctx_null_extern = ValidationCtx::new()
  ctx_null_extern.stack.push(NullExternRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_extern,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_null_extern.stack[0], Ref(Extern, false))
  let ctx_null_any = ValidationCtx::new()
  ctx_null_any.stack.push(NullRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_any,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_null_any.stack[0], Ref(Any, false))
  let ctx_other = ValidationCtx::new()
  ctx_other.stack.push(I32)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_other,
    BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_other.stack[0], I32)
}

///|
test "validate control call errors" {
  let module_empty = test_empty_module()
  let counts_empty = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let empty_func : @core.FuncType = { params: [], results: [] }
  let mut saw_error = false
  let ctx_call_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_call_bad,
    Call(0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_call_indirect_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_call_indirect_bad,
    CallIndirect(0U, 0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let module_import_table : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
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
          limits: { min: 0U, max: None },
          init: None,
          nullable: true,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  let counts_import = get_import_counts(module_import_table)
  let ctx_call_indirect = ValidationCtx::new()
  ctx_call_indirect.stack.push(I32)
  let ok = validate_instruction_control(
    module_import_table,
    empty_func,
    code,
    ctx_call_indirect,
    CallIndirect(0U, 0U),
    counts_import,
  )
  assert_eq(ok, true)
  let module_import_scan : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
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
        name: Bytes::from_array([b't']),
        desc: Table({
          elem_type: Func,
          limits: { min: 0U, max: None },
          init: None,
          nullable: true,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  let counts_scan = get_import_counts(module_import_scan)
  let ctx_call_indirect_scan = ValidationCtx::new()
  ctx_call_indirect_scan.stack.push(I32)
  let ok = validate_instruction_control(
    module_import_scan,
    empty_func,
    code,
    ctx_call_indirect_scan,
    CallIndirect(0U, 0U),
    counts_scan,
  )
  assert_eq(ok, true)
  let ctx_return_call_indirect_scan = ValidationCtx::new()
  ctx_return_call_indirect_scan.stack.push(I32)
  let ok = validate_instruction_control(
    module_import_scan,
    empty_func,
    code,
    ctx_return_call_indirect_scan,
    ReturnCallIndirect(0U, 0U),
    counts_scan,
  )
  assert_eq(ok, true)
  saw_error = false
  let module_table_bad : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    funcs: [],
    tables: [
      {
        elem_type: Extern,
        limits: { min: 0U, max: None },
        init: None,
        nullable: true,
      },
    ],
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
  let ctx_call_indirect_bad_table = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_bad,
    empty_func,
    code,
    ctx_call_indirect_bad_table,
    CallIndirect(0U, 0U),
    get_import_counts(module_table_bad),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let module_table_no_types : @core.Module = {
    types: [],
    type_groups: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0U, max: None },
        init: None,
        nullable: true,
      },
    ],
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
  let ctx_call_indirect_bad_type = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_no_types,
    empty_func,
    code,
    ctx_call_indirect_bad_type,
    CallIndirect(0U, 0U),
    get_import_counts(module_table_no_types),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let module_return_call : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    funcs: [1U],
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
  let ctx_return_call_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_return_call,
    empty_func,
    code,
    ctx_return_call_bad,
    ReturnCall(0U),
    get_import_counts(module_return_call),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_return_call_indirect_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_return_call_indirect_bad,
    ReturnCallIndirect(0U, 0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_return_call_indirect = ValidationCtx::new()
  ctx_return_call_indirect.stack.push(I32)
  let ok = validate_instruction_control(
    module_import_table,
    empty_func,
    code,
    ctx_return_call_indirect,
    ReturnCallIndirect(0U, 0U),
    counts_import,
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_return_call_indirect_bad_table = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_bad,
    empty_func,
    code,
    ctx_return_call_indirect_bad_table,
    ReturnCallIndirect(0U, 0U),
    get_import_counts(module_table_bad),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_return_call_indirect_bad_type = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_no_types,
    empty_func,
    code,
    ctx_return_call_indirect_bad_type,
    ReturnCallIndirect(0U, 0U),
    get_import_counts(module_table_no_types),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_call_ref_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_call_ref_bad,
    CallRef(0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_return_call_ref_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_return_call_ref_bad,
    ReturnCallRef(0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate function stack mismatch" {
  let module_empty = test_empty_module()
  let func_type : @core.FuncType = { params: [], results: [] }
  let code = test_make_code([], [I32Const(0U)])
  let mut saw_error = false
  let _ = validate_function(
    module_empty,
    func_type,
    code,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_types : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
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
  let func_type_param : @core.FuncType = {
    params: [Ref(TypeIndex(0), true)],
    results: [],
  }
  let code_empty = test_make_code([], [])
  validate_function(
    module_types,
    func_type_param,
    code_empty,
    get_import_counts(module_types),
  )
  saw_error = false
  let func_type_result : @core.FuncType = { params: [], results: [I32] }
  let code_result = test_make_code([], [I64Const(0UL)])
  let _ = validate_function(
    module_empty,
    func_type_result,
    code_result,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let code_missing = test_make_code([], [])
  let _ = validate_function(
    module_empty,
    func_type_result,
    code_missing,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let code_extra = test_make_code([], [I32Const(0U), I32Const(1U)])
  let _ = validate_function(
    module_empty,
    func_type_result,
    code_extra,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}
