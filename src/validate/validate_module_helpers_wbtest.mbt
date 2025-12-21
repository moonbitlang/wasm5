///|
test "validate module type index errors" {
  let module_table : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::TypeIndex(1),
        limits: @core.Limits::{ min: 0U, max: None },
        init: None,
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_elem : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [
      @core.Elem::{
        table_idx: 0U,
        offset: test_empty_expr(),
        init: [],
        is_active: false,
        elem_type: @core.RefType::TypeIndex(1),
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
  let module_import : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'f']),
        desc: @core.ImportDesc::Func(1U),
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
  let module_funcs : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [1U],
    tables: [],
    mems: [],
    globals: [],
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
  let module_globals : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{
          val_type: @core.ValType::Ref(@core.RefType::TypeIndex(1), true),
          mutable: false,
        },
        init: @core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::Func)],
        },
      },
    ],
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
  let module_results : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [@core.ValType::I32] }],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
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
  let module_empty : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
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
  let module_params : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [@core.ValType::I32], results: [] }],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
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
  let module_results : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [@core.ValType::I32] }],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
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
  let module_min_max : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [@core.MemType::{ limits: @core.Limits::{ min: 10U, max: Some(5U) } }],
    globals: [],
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
  let module_max : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [
      @core.MemType::{ limits: @core.Limits::{ min: 0U, max: Some(70000U) } },
    ],
    globals: [],
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
  let module_none : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [@core.MemType::{ limits: @core.Limits::{ min: 70000U, max: None } }],
    globals: [],
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
  let module_min_max : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'm']),
        desc: @core.ImportDesc::Mem(@core.MemType::{
          limits: @core.Limits::{ min: 10U, max: Some(5U) },
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
  let module_max : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'm']),
        desc: @core.ImportDesc::Mem(@core.MemType::{
          limits: @core.Limits::{ min: 0U, max: Some(70000U) },
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
  let module_none : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'm']),
        desc: @core.ImportDesc::Mem(@core.MemType::{
          limits: @core.Limits::{ min: 70000U, max: None },
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
  let module_no_init : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: None,
        nullable: false,
      },
    ],
    mems: [],
    globals: [],
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
  let module_bad_limits : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 5U, max: Some(1U) },
        init: None,
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_bad_init_len : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{ instrs: [] }),
        nullable: false,
      },
    ],
    mems: [],
    globals: [],
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
  let module_null : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::Func)],
        }),
        nullable: false,
      },
    ],
    mems: [],
    globals: [],
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
  let module_non_ref : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{ instrs: [@core.Instr::I32Const(0U)] }),
        nullable: false,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable_empty : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{ instrs: [] }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable_numeric : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{ instrs: [@core.Instr::I32Const(0U)] }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable_typed : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::TypeIndex(0))],
        }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable_extern_ok : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Extern,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::NoExtern)],
        }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable_extern_bad : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Extern,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::Func)],
        }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_nullable : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
        limits: @core.Limits::{ min: 0U, max: None },
        init: Some(@core.Expr::{
          instrs: [@core.Instr::RefNull(@core.RefType::Extern)],
        }),
        nullable: true,
      },
    ],
    mems: [],
    globals: [],
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
  let module_import_table : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b't']),
        desc: @core.ImportDesc::Table(@core.TableType::{
          elem_type: @core.RefType::Func,
          limits: @core.Limits::{ min: 10U, max: Some(5U) },
          init: None,
          nullable: true,
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
  let module_table : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [
      @core.Elem::{
        table_idx: 1U,
        offset: test_empty_expr(),
        init: [],
        is_active: true,
        elem_type: @core.RefType::Func,
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
  let module_func : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [
      @core.Elem::{
        table_idx: 0U,
        offset: test_empty_expr(),
        init: [0U],
        is_active: false,
        elem_type: @core.RefType::Func,
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
  let module_mem : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [
      @core.Data::{
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
  let module_offset : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [@core.MemType::{ limits: @core.Limits::{ min: 0U, max: None } }],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{ val_type: @core.ValType::I32, mutable: true },
        init: @core.Expr::{ instrs: [@core.Instr::I32Const(0U)] },
      },
    ],
    elems: [],
    datas: [
      @core.Data::{
        mem_idx: 0U,
        offset: @core.Expr::{ instrs: [@core.Instr::GlobalGet(0U)] },
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
  let module_dup : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @core.Export::{ name: dup_name, desc: @core.ExportDesc::Func(0U) },
      @core.Export::{ name: dup_name, desc: @core.ExportDesc::Func(0U) },
    ],
    codes: [],
  }
  let mut saw_duplicate = false
  let _ = validate_module_exports(module_dup, get_import_counts(module_dup)) catch {
    @core.ValidationError::DuplicateExport(_) => {
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
  let module_mem : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @core.Export::{
        name: Bytes::from_array([b'm']),
        desc: @core.ExportDesc::Mem(0U),
      },
    ],
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
  let module_table_export : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @core.Export::{
        name: Bytes::from_array([b't']),
        desc: @core.ExportDesc::Table(0U),
      },
    ],
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
  let module_global_export : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @core.Export::{
        name: Bytes::from_array([b'g']),
        desc: @core.ExportDesc::Global(0U),
      },
    ],
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
}

///|
test "validate module global initializers" {
  let module_ok : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: false,
        },
        init: @core.Expr::{ instrs: [@core.Instr::I32Const(0U)] },
      },
    ],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  validate_module_global_initializers(module_ok, get_import_counts(module_ok))
  let module_empty_init : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: false,
        },
        init: test_empty_expr(),
      },
    ],
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
  let module_mismatch : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{
          val_type: @core.ValType::I64,
          mutable: false,
        },
        init: @core.Expr::{ instrs: [@core.Instr::I32Const(0U)] },
      },
    ],
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
  let func_type = @core.FuncType::{ params: [], results: [] }
  let code = test_make_code([], [])
  let module_funcs : @core.Module = @core.Module::{
    types: [func_type],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [code],
  }
  validate_module_function_bodies(module_funcs, get_import_counts(module_funcs))
}
