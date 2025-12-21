///|
test "validate helper ref type conversions" {
  assert_eq(reftype_to_valtype(@core.RefType::Extern), @core.ValType::ExternRef)
  assert_eq(reftype_to_valtype(@core.RefType::Any), @core.ValType::AnyRef)
  assert_eq(reftype_to_valtype(@core.RefType::Eq), @core.ValType::EqRef)
  assert_eq(reftype_to_valtype(@core.RefType::I31), @core.ValType::I31Ref)
  assert_eq(reftype_to_valtype(@core.RefType::Struct), @core.ValType::StructRef)
  assert_eq(reftype_to_valtype(@core.RefType::Array), @core.ValType::ArrayRef)
  assert_eq(reftype_to_valtype(@core.RefType::Exn), @core.ValType::ExnRef)
  assert_eq(reftype_to_valtype(@core.RefType::None), @core.ValType::NullRef)
  assert_eq(
    reftype_to_valtype(@core.RefType::NoFunc),
    @core.ValType::NullFuncRef,
  )
  assert_eq(
    reftype_to_valtype(@core.RefType::NoExtern),
    @core.ValType::NullExternRef,
  )
  assert_eq(reftype_to_valtype(@core.RefType::NoExn), @core.ValType::NullExnRef)
  assert_eq(
    reftype_to_valtype(@core.RefType::TypeIndex(3)),
    @core.ValType::Ref(@core.RefType::TypeIndex(3), true),
  )
}

///|
test "validate helper counts and type lookup" {
  let func_type0 : @core.FuncType = @core.FuncType::{ params: [], results: [] }
  let func_type1 : @core.FuncType = @core.FuncType::{
    params: [@core.ValType::I32],
    results: [@core.ValType::I32],
  }
  let table_type : @core.TableType = @core.TableType::{
    elem_type: @core.RefType::Func,
    limits: @core.Limits::{ min: 0U, max: None },
    init: None,
    nullable: true,
  }
  let mem_type : @core.MemType = @core.MemType::{
    limits: @core.Limits::{ min: 0U, max: None },
  }
  let global_type : @core.GlobalType = @core.GlobalType::{
    val_type: @core.ValType::I32,
    mutable: false,
  }
  let imports : Array[@core.Import] = [
    @core.Import::{
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'f']),
      desc: @core.ImportDesc::Func(1U),
    },
    @core.Import::{
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b't']),
      desc: @core.ImportDesc::Table(table_type),
    },
    @core.Import::{
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'm']),
      desc: @core.ImportDesc::Mem(mem_type),
    },
    @core.Import::{
      module_: Bytes::from_array([b'm']),
      name: Bytes::from_array([b'g']),
      desc: @core.ImportDesc::Global(global_type),
    },
  ]
  let module_ : @core.Module = @core.Module::{
    types: [func_type0, func_type1],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
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
  let func_type : @core.FuncType = @core.FuncType::{ params: [], results: [] }
  let table_type : @core.TableType = @core.TableType::{
    elem_type: @core.RefType::Func,
    limits: @core.Limits::{ min: 0U, max: None },
    init: None,
    nullable: true,
  }
  let module_ : @core.Module = @core.Module::{
    types: [func_type],
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
        desc: @core.ImportDesc::Table(table_type),
      },
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'f']),
        desc: @core.ImportDesc::Func(0U),
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
  let valid_expr = @core.Expr::{
    instrs: [
      @core.Instr::I32Const(0U),
      @core.Instr::I32Const(1U),
      @core.Instr::I32Add,
    ],
  }
  validate_const_expr_instructions(valid_expr)
  let mut saw_error = false
  let _ = validate_const_expr_instructions(@core.Expr::{
    instrs: [@core.Instr::Nop],
  }) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_empty = test_empty_module()
  let expr_global = @core.Expr::{ instrs: [@core.Instr::GlobalGet(0U)] }
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
  let module_imported : @core.Module = @core.Module::{
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
        name: Bytes::from_array([b'g']),
        desc: @core.ImportDesc::Global(@core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: true,
        }),
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
  let module_scan : @core.Module = @core.Module::{
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
          limits: @core.Limits::{ min: 0U, max: None },
          init: None,
          nullable: true,
        }),
      },
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: @core.ImportDesc::Global(@core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: false,
        }),
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
  let module_local : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [
      @core.Global::{
        type_: @core.GlobalType::{ val_type: @core.ValType::I32, mutable: true },
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
  let module_import_const : @core.Module = @core.Module::{
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
        name: Bytes::from_array([b'g']),
        desc: @core.ImportDesc::Global(@core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: false,
        }),
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
  let module_import_scan : @core.Module = @core.Module::{
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
        name: Bytes::from_array([b'f']),
        desc: @core.ImportDesc::Func(0U),
      },
      @core.Import::{
        module_: Bytes::from_array([b'i']),
        name: Bytes::from_array([b'g']),
        desc: @core.ImportDesc::Global(@core.GlobalType::{
          val_type: @core.ValType::I32,
          mutable: false,
        }),
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
  let module_missing : @core.Module = @core.Module::{
    types: [],
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
  validate_const_expr_globals(
    module_missing,
    expr_global,
    get_import_counts(module_missing),
  )
}

///|
test "validate valtype and subtype" {
  let module_empty = test_empty_module()
  let mut saw_error = false
  let _ = validate_valtype(
    module_empty,
    @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  let module_types : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
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
  assert_eq(
    is_subtype(module_types, @core.ValType::NullRef, @core.ValType::AnyRef),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::NullFuncRef,
      @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::TypeIndex(0), false),
      @core.ValType::Ref(@core.RefType::Func, false),
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::FuncRef,
      @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
    ),
    false,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::Extern, false),
      @core.ValType::ExternRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::Any, false),
      @core.ValType::AnyRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::NullFuncRef, @core.ValType::FuncRef),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::NullExternRef,
      @core.ValType::ExternRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::NullExnRef, @core.ValType::ExnRef),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::NullFuncRef,
      @core.ValType::Ref(@core.RefType::Func, true),
    ),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::I31Ref, @core.ValType::EqRef),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::StructRef, @core.ValType::AnyRef),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::ArrayRef, @core.ValType::EqRef),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::EqRef, @core.ValType::AnyRef),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::FuncRef, @core.ValType::AnyRef),
    true,
  )
  assert_eq(
    is_subtype(module_types, @core.ValType::ExnRef, @core.ValType::AnyRef),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::Func, false),
      @core.ValType::FuncRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
      @core.ValType::FuncRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
      @core.ValType::Ref(@core.RefType::Func, true),
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::FuncRef,
      @core.ValType::Ref(@core.RefType::Func, true),
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::Exn, false),
      @core.ValType::ExnRef,
    ),
    true,
  )
  assert_eq(
    is_subtype(
      module_types,
      @core.ValType::Ref(@core.RefType::Struct, false),
      @core.ValType::AnyRef,
    ),
    true,
  )
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
  let _ = validate_memory_exists(module_empty, get_import_counts(module_empty)) catch {
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
  let _ = ctx.poly_pop_expect(module_empty, @core.ValType::I32, "pop") catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
  ctx.stack.push(@core.ValType::I64)
  ctx.mark_unreachable()
  ctx.stack.push(@core.ValType::I64)
  ctx.poly_pop_expect(module_empty, @core.ValType::I64, "pop ok")
  assert_eq(ctx.stack.length(), 0)
  let func_type = @core.FuncType::{ params: [@core.ValType::I32], results: [] }
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
  ctx_mismatch.stack.push(@core.ValType::I64)
  let _ = ctx_mismatch.poly_pop_expect(
    module_empty,
    @core.ValType::I32,
    "mismatch",
  ) catch {
    _ => {
      saw_error = true
      ()
    }
  }
  assert_eq(saw_error, true)
}
