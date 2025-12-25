///|
test "validate module type index errors" {
  let module_table : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: TypeIndex(1),
        limits: { min: 0UL, max: None },
        init: None,
        nullable: true,
        table64: false,
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
  let mut saw_error = false
  let _ = validate_module_type_indices(module_table) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_elem : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [
      {
        table_idx: 0U,
        offset: test_empty_expr(),
        init: [],
        is_active: false,
        is_declarative: false,
        elem_type: TypeIndex(1),
        elem_nullable: true,
        explicit_table: false,
      },
    ],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_type_indices(module_elem) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_import : @core.Module = {
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
    imports: [
      {
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'f']),
        desc: Func(1U),
      },
    ],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_type_indices(module_import) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_funcs : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
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
  saw_error = false
  let _ = validate_module_type_indices(module_funcs) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_globals : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      {
        type_: { val_type: Ref(TypeIndex(1), true), mutable: false },
        init: { instrs: [RefNull(Func)] },
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
  let _ = validate_module_type_indices(module_globals) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module type results" {
  let module_results : @core.Module = {
    types: [Func({ params: [], results: [I32] })],
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
  validate_module_type_indices(module_results)
}

///|
test "validate module start function errors" {
  let module_empty : @core.Module = {
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
    start: Some(0U),
    imports: [],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_start_function(
    module_empty,
    get_import_counts(module_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_params : @core.Module = {
    types: [Func({ params: [I32], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: Some(0U),
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_start_function(
    module_params,
    get_import_counts(module_params),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_results : @core.Module = {
    types: [Func({ params: [], results: [I32] })],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: Some(0U),
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_start_function(
    module_results,
    get_import_counts(module_results),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module memory limit errors" {
  let module_min_max : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [
      { limits: { min: 10UL, max: Some(5UL) }, shared: false, memory64: false },
    ],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_memory_limits(module_min_max) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_max : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [
      {
        limits: { min: 0UL, max: Some(70000UL) },
        shared: false,
        memory64: false,
      },
    ],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_memory_limits(module_max) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_none : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [
      { limits: { min: 70000UL, max: None }, shared: false, memory64: false },
    ],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_memory_limits(module_none) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module imported memory limit errors" {
  let module_min_max : @core.Module = {
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
        name: Bytes::from_array([b'm']),
        desc: Mem({
          limits: { min: 10UL, max: Some(5UL) },
          shared: false,
          memory64: false,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_imported_memory_limits(module_min_max) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_max : @core.Module = {
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
        name: Bytes::from_array([b'm']),
        desc: Mem({
          limits: { min: 0UL, max: Some(70000UL) },
          shared: false,
          memory64: false,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_imported_memory_limits(module_max) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_none : @core.Module = {
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
        name: Bytes::from_array([b'm']),
        desc: Mem({
          limits: { min: 70000UL, max: None },
          shared: false,
          memory64: false,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_imported_memory_limits(module_none) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module table errors" {
  let module_no_init : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: None,
        nullable: false,
        table64: false,
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
  let mut saw_error = false
  let _ = validate_module_tables(
    module_no_init,
    get_import_counts(module_no_init),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_bad_limits : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 5UL, max: Some(1UL) },
        init: None,
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_bad_limits,
    get_import_counts(module_bad_limits),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_oversize : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 4294967296UL, max: None },
        init: None,
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_oversize,
    get_import_counts(module_oversize),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_table64 : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 4294967296UL, max: None },
        init: None,
        nullable: true,
        table64: true,
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
  saw_error = false
  let _ = validate_module_tables(
    module_table64,
    get_import_counts(module_table64),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, false)
  let module_bad_init_len : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [] }),
        nullable: false,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_bad_init_len,
    get_import_counts(module_bad_init_len),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_null : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefNull(Func)] }),
        nullable: false,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(module_null, get_import_counts(module_null)) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_non_ref : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [I32Const(0U)] }),
        nullable: false,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_non_ref,
    get_import_counts(module_non_ref),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_nullable_empty : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [] }),
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_nullable_empty,
    get_import_counts(module_nullable_empty),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_nullable_numeric : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [I32Const(0U)] }),
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_nullable_numeric,
    get_import_counts(module_nullable_numeric),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_nullable_typed : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefNull(TypeIndex(0))] }),
        nullable: true,
        table64: false,
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
  validate_module_tables(
    module_nullable_typed,
    get_import_counts(module_nullable_typed),
  )
  let module_typed_init : @core.Module = {
    types: [Func({ params: [], results: [] })],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [
      {
        elem_type: TypeIndex(0),
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefFunc(0U)] }),
        nullable: false,
        table64: false,
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
    codes: [{ locals: [], body: test_empty_expr(), compiled: None, max_stack_height: 0 }],
  }
  validate_module_tables(
    module_typed_init,
    get_import_counts(module_typed_init),
  )
  let module_nullable_extern_ok : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Extern,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefNull(NoExtern)] }),
        nullable: true,
        table64: false,
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
  validate_module_tables(
    module_nullable_extern_ok,
    get_import_counts(module_nullable_extern_ok),
  )
  let module_nullable_extern_bad : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Extern,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefNull(Func)] }),
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_nullable_extern_bad,
    get_import_counts(module_nullable_extern_bad),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_nullable : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [
      {
        elem_type: Func,
        limits: { min: 0UL, max: None },
        init: Some({ instrs: [RefNull(Extern)] }),
        nullable: true,
        table64: false,
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
  saw_error = false
  let _ = validate_module_tables(
    module_nullable,
    get_import_counts(module_nullable),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_import_table : @core.Module = {
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
          limits: { min: 10UL, max: Some(5UL) },
          init: None,
          nullable: true,
          table64: false,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_tables(
    module_import_table,
    get_import_counts(module_import_table),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module element segment errors" {
  let module_table : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [
      {
        table_idx: 1U,
        offset: test_empty_expr(),
        init: [],
        is_active: true,
        is_declarative: false,
        elem_type: Func,
        elem_nullable: true,
        explicit_table: false,
      },
    ],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_element_segments(
    module_table,
    get_import_counts(module_table),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_func : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [
      {
        table_idx: 0U,
        offset: test_empty_expr(),
        init: [{ instrs: [RefFunc(0U)] }],
        is_active: false,
        is_declarative: false,
        elem_type: Func,
        elem_nullable: true,
        explicit_table: false,
      },
    ],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_element_segments(
    module_func,
    get_import_counts(module_func),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module data segment errors" {
  let module_mem : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [
      {
        mem_idx: 1U,
        offset: test_empty_expr(),
        init: Bytes::from_array([]).sub(),
        is_active: true,
      },
    ],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_data_segments(
    module_mem,
    get_import_counts(module_mem),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_offset : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [{ limits: { min: 0UL, max: None }, shared: false, memory64: false }],
    globals: [
      {
        type_: { val_type: I32, mutable: true },
        init: { instrs: [I32Const(0U)] },
      },
    ],
    tags: [],
    elems: [],
    datas: [
      {
        mem_idx: 0U,
        offset: { instrs: [GlobalGet(0U)] },
        init: Bytes::from_array([]).sub(),
        is_active: true,
      },
    ],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_data_segments(
    module_offset,
    get_import_counts(module_offset),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module exports errors" {
  let dup_name = Bytes::from_array([b'x'])
  let module_dup : @core.Module = {
    types: [Func({ params: [], results: [] })],
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
    exports: [
      { name: dup_name, desc: Func(0U) },
      { name: dup_name, desc: Func(0U) },
    ],
    codes: [],
  }
  let mut saw_duplicate = false
  let _ = validate_module_exports(module_dup, get_import_counts(module_dup)) catch {
    DuplicateExport(_) => {
      saw_duplicate = true
      ()
    }
    _ => {
      saw_duplicate = false
      ()
    }
  }
  assert_eq(saw_duplicate, true)
  let mut saw_error = false
  let module_mem : @core.Module = {
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
    imports: [],
    exports: [{ name: Bytes::from_array([b'm']), desc: Mem(0U) }],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_exports(module_mem, get_import_counts(module_mem)) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_table_export : @core.Module = {
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
    imports: [],
    exports: [{ name: Bytes::from_array([b't']), desc: Table(0U) }],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_exports(
    module_table_export,
    get_import_counts(module_table_export),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_global_export : @core.Module = {
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
    imports: [],
    exports: [{ name: Bytes::from_array([b'g']), desc: Global(0U) }],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_exports(
    module_global_export,
    get_import_counts(module_global_export),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_func_export : @core.Module = {
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
    imports: [],
    exports: [{ name: Bytes::from_array([b'f']), desc: Func(1U) }],
    codes: [],
  }
  saw_error = false
  let _ = validate_module_exports(
    module_func_export,
    get_import_counts(module_func_export),
  ) catch {
    UnknownExportedFunction(_) => {
      saw_error = true
      ()
    }
    _ => {
      saw_error = false
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module global initializers" {
  let module_ok : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
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
  validate_module_global_initializers(module_ok, get_import_counts(module_ok))
  let module_empty_init : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      { type_: { val_type: I32, mutable: false }, init: test_empty_expr() },
    ],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  let mut saw_error = false
  let _ = validate_module_global_initializers(
    module_empty_init,
    get_import_counts(module_empty_init),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_mismatch : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      {
        type_: { val_type: I64, mutable: false },
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
  let _ = validate_module_global_initializers(
    module_mismatch,
    get_import_counts(module_mismatch),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "validate module function bodies" {
  let func_type : @core.TypeDef = Func({ params: [], results: [] })
  let code = test_make_code([], [])
  let module_funcs : @core.Module = {
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
    exports: [],
    codes: [code],
  }
  validate_module_function_bodies(module_funcs, get_import_counts(module_funcs))
}
