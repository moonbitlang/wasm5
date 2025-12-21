///|
fn test_module_with_memory() -> @core.Module {
  @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [@core.MemType::{ limits: @core.Limits::{ min: 0U, max: None } }],
    globals: [],
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
  @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type,
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
}

///|
test "validate variable instruction errors" {
  let module_empty = test_empty_module()
  let func_type = @core.FuncType::{ params: [], results: [] }
  let code = test_make_code([], [])
  let ctx = ValidationCtx::new_with_locals(func_type, code)
  let mut saw_error = false
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code,
    ctx,
    get_import_counts(module_empty),
    @core.Instr::LocalGet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let code_uninit = test_make_code(
    [@core.ValType::Ref(@core.RefType::Func, false)],
    [],
  )
  let ctx_uninit = ValidationCtx::new_with_locals(func_type, code_uninit)
  saw_error = false
  let _ = validate_instruction_variable(
    module_empty,
    func_type,
    code_uninit,
    ctx_uninit,
    get_import_counts(module_empty),
    @core.Instr::LocalGet(0U),
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
    @core.Instr::GlobalGet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let module_global : @core.Module = @core.Module::{
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
  saw_error = false
  let ctx_set = ValidationCtx::new()
  let _ = validate_instruction_variable(
    module_global,
    func_type,
    code,
    ctx_set,
    get_import_counts(module_global),
    @core.Instr::GlobalSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let func_type_params = @core.FuncType::{
    params: [@core.ValType::I32],
    results: [],
  }
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
    @core.Instr::LocalGet(0U),
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
    @core.Instr::LocalSet(0U),
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
    @core.Instr::LocalTee(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_set_local = ValidationCtx::new()
  ctx_set_local.stack.push(@core.ValType::I32)
  let ok = validate_instruction_variable(
    module_empty,
    func_type_params,
    code_params,
    ctx_set_local,
    get_import_counts(module_empty),
    @core.Instr::LocalSet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_set_local.initialized_locals.length() > 0, true)
  let ctx_tee_local = ValidationCtx::new()
  ctx_tee_local.stack.push(@core.ValType::I32)
  let ok = validate_instruction_variable(
    module_empty,
    func_type_params,
    code_params,
    ctx_tee_local,
    get_import_counts(module_empty),
    @core.Instr::LocalTee(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_tee_local.initialized_locals.length() > 0, true)
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
          val_type: @core.ValType::I64,
          mutable: false,
        }),
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
    @core.Instr::GlobalGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_import_get.stack[0], @core.ValType::I64)
  let module_imported_mut : @core.Module = @core.Module::{
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
  let ctx_import_set = ValidationCtx::new()
  ctx_import_set.stack.push(@core.ValType::I32)
  let ok = validate_instruction_variable(
    module_imported_mut,
    func_type,
    code,
    ctx_import_set,
    get_import_counts(module_imported_mut),
    @core.Instr::GlobalSet(0U),
  )
  assert_eq(ok, true)
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
          mutable: true,
        }),
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
    @core.Instr::GlobalGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_scan_get.stack[0], @core.ValType::I32)
  let ctx_scan_set = ValidationCtx::new()
  ctx_scan_set.stack.push(@core.ValType::I32)
  let ok = validate_instruction_variable(
    module_import_scan,
    func_type,
    code,
    ctx_scan_set,
    get_import_counts(module_import_scan),
    @core.Instr::GlobalSet(0U),
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
    @core.Instr::GlobalSet(0U),
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
  ctx_non_numeric.stack.push(@core.ValType::FuncRef)
  ctx_non_numeric.stack.push(@core.ValType::FuncRef)
  ctx_non_numeric.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_non_numeric,
    @core.Instr::Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_incompatible = ValidationCtx::new()
  ctx_incompatible.stack.push(@core.ValType::I32)
  ctx_incompatible.stack.push(@core.ValType::I64)
  ctx_incompatible.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_incompatible,
    @core.Instr::Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_bad_arity = ValidationCtx::new()
  ctx_bad_arity.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_bad_arity,
    @core.Instr::SelectTyped([@core.ValType::I32, @core.ValType::I64]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_bad_type = ValidationCtx::new()
  ctx_bad_type.stack.push(@core.ValType::I64)
  ctx_bad_type.stack.push(@core.ValType::I64)
  ctx_bad_type.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_bad_type,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_drop = ValidationCtx::new()
  ctx_drop.stack.push(@core.ValType::I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_drop,
    @core.Instr::Drop,
  )
  assert_eq(ok, true)
  assert_eq(ctx_drop.stack.length(), 0)
  let mut saw_error = false
  let ctx_drop_empty = ValidationCtx::new()
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_drop_empty,
    @core.Instr::Drop,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  ctx_unreachable.stack.push(@core.ValType::I32)
  ctx_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_unreachable,
    @core.Instr::Select,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable.stack.length(), 1)
  saw_error = false
  let ctx_unreachable_bad = ValidationCtx::new()
  ctx_unreachable_bad.mark_unreachable()
  ctx_unreachable_bad.stack.push(@core.ValType::ExternRef)
  ctx_unreachable_bad.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_unreachable_bad,
    @core.Instr::Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_unreachable_empty = ValidationCtx::new()
  ctx_unreachable_empty.mark_unreachable()
  ctx_unreachable_empty.stack.push(@core.ValType::I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_unreachable_empty,
    @core.Instr::Select,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable_empty.stack[0], @core.ValType::I32)
  saw_error = false
  let ctx_missing = ValidationCtx::new()
  ctx_missing.stack.push(@core.ValType::I32)
  ctx_missing.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_missing,
    @core.Instr::Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_condition_only = ValidationCtx::new()
  ctx_condition_only.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_condition_only,
    @core.Instr::Select,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_typed_unreachable = ValidationCtx::new()
  ctx_typed_unreachable.mark_unreachable()
  ctx_typed_unreachable.stack.push(@core.ValType::I32)
  ctx_typed_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_typed_unreachable,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  )
  assert_eq(ok, true)
  assert_eq(ctx_typed_unreachable.stack.length(), 1)
  saw_error = false
  let ctx_typed_bad_val2 = ValidationCtx::new()
  ctx_typed_bad_val2.stack.push(@core.ValType::I32)
  ctx_typed_bad_val2.stack.push(@core.ValType::I64)
  ctx_typed_bad_val2.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_bad_val2,
    @core.Instr::SelectTyped([@core.ValType::I32]),
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
  ctx_typed_unreachable_bad.stack.push(@core.ValType::I64)
  ctx_typed_unreachable_bad.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_unreachable_bad,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_typed_missing = ValidationCtx::new()
  ctx_typed_missing.stack.push(@core.ValType::I32)
  ctx_typed_missing.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_missing,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_typed_condition_only = ValidationCtx::new()
  ctx_typed_condition_only.stack.push(@core.ValType::I32)
  let _ = validate_instruction_parametric(
    module_empty,
    ctx_typed_condition_only,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_typed_empty = ValidationCtx::new()
  ctx_typed_empty.mark_unreachable()
  ctx_typed_empty.stack.push(@core.ValType::I32)
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_typed_empty,
    @core.Instr::SelectTyped([@core.ValType::I32]),
  )
  assert_eq(ok, true)
  assert_eq(ctx_typed_empty.stack.length(), 1)
  let ctx_other = ValidationCtx::new()
  let ok = validate_instruction_parametric(
    module_empty,
    ctx_other,
    @core.Instr::I32Const(0U),
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
    @core.Instr::MemoryInit(0U),
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
    @core.Instr::DataDrop(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_align = ValidationCtx::new()
  ctx_align.stack.push(@core.ValType::I32)
  let _ = validate_instruction_memory(
    module_mem,
    ctx_align,
    counts,
    @core.Instr::I32Load(3U, 0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_load = ValidationCtx::new()
  ctx_load.stack.push(@core.ValType::I32)
  let ok = validate_instruction_memory(
    module_mem,
    ctx_load,
    counts,
    @core.Instr::I32Load(0U, 0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_load.stack.length(), 1)
  assert_eq(ctx_load.stack[0], @core.ValType::I32)
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
    @core.Instr::RefFunc(0U),
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
    @core.Instr::RefIsNull,
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
    @core.Instr::RefNull(@core.RefType::Extern),
  )
  assert_eq(ok, true)
  assert_eq(ctx_ref_null.stack.length(), 1)
  assert_eq(ctx_ref_null.stack[0], @core.ValType::ExternRef)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  let ok = validate_instruction_reference(
    module_empty,
    ctx_unreachable,
    counts,
    @core.Instr::RefIsNull,
  )
  assert_eq(ok, true)
  assert_eq(ctx_unreachable.stack.length(), 1)
}

///|
test "validate table instruction errors" {
  let module_table = test_module_with_table(@core.RefType::Func)
  let mut saw_error = false
  let ctx_set = ValidationCtx::new()
  ctx_set.stack.push(@core.ValType::I32)
  ctx_set.stack.push(@core.ValType::ExternRef)
  let _ = validate_instruction_table(
    module_table,
    ctx_set,
    @core.Instr::TableSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_grow = ValidationCtx::new()
  ctx_grow.stack.push(@core.ValType::I32)
  let _ = validate_instruction_table(
    module_table,
    ctx_grow,
    @core.Instr::TableGrow(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_get = ValidationCtx::new()
  ctx_get.stack.push(@core.ValType::I32)
  let ok = validate_instruction_table(
    module_table,
    ctx_get,
    @core.Instr::TableGet(0U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_get.stack[0], @core.ValType::FuncRef)
  let ctx_missing = ValidationCtx::new()
  ctx_missing.stack.push(@core.ValType::I32)
  let ok = validate_instruction_table(
    module_table,
    ctx_missing,
    @core.Instr::TableGet(9U),
  )
  assert_eq(ok, true)
  assert_eq(ctx_missing.stack[0], @core.ValType::FuncRef)
  let ctx_unreachable = ValidationCtx::new()
  ctx_unreachable.mark_unreachable()
  let ok = validate_instruction_table(
    module_table,
    ctx_unreachable,
    @core.Instr::TableSet(0U),
  )
  assert_eq(ok, true)
  let mut saw_error = false
  let ctx_empty = ValidationCtx::new()
  let _ = validate_instruction_table(
    module_table,
    ctx_empty,
    @core.Instr::TableSet(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_missing_table = ValidationCtx::new()
  ctx_missing_table.stack.push(@core.ValType::ExternRef)
  let _ = validate_instruction_table(
    module_table,
    ctx_missing_table,
    @core.Instr::TableSet(2U),
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
    @core.Instr::TableGrow(0U),
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_grow_mismatch = ValidationCtx::new()
  ctx_grow_mismatch.stack.push(@core.ValType::ExternRef)
  ctx_grow_mismatch.stack.push(@core.ValType::I32)
  let _ = validate_instruction_table(
    module_table,
    ctx_grow_mismatch,
    @core.Instr::TableGrow(0U),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let ctx_grow_default = ValidationCtx::new()
  ctx_grow_default.stack.push(@core.ValType::I32)
  ctx_grow_default.stack.push(@core.ValType::I32)
  let _ = validate_instruction_table(
    module_table,
    ctx_grow_default,
    @core.Instr::TableGrow(3U),
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
  let func_type = @core.FuncType::{
    params: [@core.ValType::I32],
    results: [@core.ValType::I32],
  }
  let module_funcs : @core.Module = @core.Module::{
    types: [func_type],
    funcs: [0U],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
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
  let counts = get_import_counts(module_funcs)
  let code = test_make_code([], [])
  let mut saw_error = false
  let _ = get_block_type(test_empty_module(), @core.BlockType::TypeIndex(1)) catch {
    _ => {
      saw_error = true
      ([], [])
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let _ = validate_tail_call_return_type(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [@core.ValType::I32] },
    @core.FuncType::{ params: [], results: [] },
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
    @core.FuncType::{ params: [], results: [@core.ValType::I64] },
    @core.FuncType::{ params: [], results: [@core.ValType::I32] },
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
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_block,
    @core.Instr::Block(@core.BlockType::Empty, []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_loop = ValidationCtx::new()
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_loop,
    @core.Instr::Loop(@core.BlockType::Empty, []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_if = ValidationCtx::new()
  ctx_if.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_if,
    @core.Instr::If(@core.BlockType::Empty, [], []),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  let ctx_br = ValidationCtx::new()
  ctx_br.push_control([], [@core.ValType::I32])
  ctx_br.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_br,
    @core.Instr::Br(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br.is_unreachable, true)
  let ctx_br_if = ValidationCtx::new()
  ctx_br_if.push_control([], [@core.ValType::I32])
  ctx_br_if.stack.push(@core.ValType::I32)
  ctx_br_if.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_br_if,
    @core.Instr::BrIf(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_if.stack.length(), 1)
  let ctx_br_table = ValidationCtx::new()
  ctx_br_table.push_control([], [@core.ValType::I32])
  ctx_br_table.stack.push(@core.ValType::I32)
  ctx_br_table.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_br_table,
    @core.Instr::BrTable([], 0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_table.is_unreachable, true)
  let ctx_br_on_null = ValidationCtx::new()
  ctx_br_on_null.stack.push(@core.ValType::FuncRef)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_br_on_null,
    @core.Instr::BrOnNull(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_br_on_null.stack[0],
    @core.ValType::Ref(@core.RefType::Func, false),
  )
  let ctx_br_on_non_null = ValidationCtx::new()
  ctx_br_on_non_null.stack.push(@core.ValType::FuncRef)
  let ok = validate_instruction_control(
    test_empty_module(),
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_br_on_non_null,
    @core.Instr::BrOnNonNull(0U),
    get_import_counts(test_empty_module()),
  )
  assert_eq(ok, true)
  assert_eq(ctx_br_on_non_null.stack.length(), 0)
  saw_error = false
  let ctx_return = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_funcs,
    @core.FuncType::{ params: [], results: [@core.ValType::I32] },
    code,
    ctx_return,
    @core.Instr::Return,
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_call = ValidationCtx::new()
  ctx_call.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_call,
    @core.Instr::Call(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call.stack.length(), 1)
  let ctx_call_indirect = ValidationCtx::new()
  ctx_call_indirect.stack.push(@core.ValType::I32)
  ctx_call_indirect.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_call_indirect,
    @core.Instr::CallIndirect(0U, 0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call_indirect.stack.length(), 1)
  let ctx_return_call = ValidationCtx::new()
  ctx_return_call.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{
      params: [@core.ValType::I32],
      results: [@core.ValType::I32],
    },
    code,
    ctx_return_call,
    @core.Instr::ReturnCall(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call.is_unreachable, true)
  let ctx_return_call_indirect = ValidationCtx::new()
  ctx_return_call_indirect.stack.push(@core.ValType::I32)
  ctx_return_call_indirect.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{
      params: [@core.ValType::I32],
      results: [@core.ValType::I32],
    },
    code,
    ctx_return_call_indirect,
    @core.Instr::ReturnCallIndirect(0U, 0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call_indirect.is_unreachable, true)
  let ctx_call_ref = ValidationCtx::new()
  ctx_call_ref.stack.push(@core.ValType::I32)
  ctx_call_ref.stack.push(@core.ValType::Ref(@core.RefType::TypeIndex(0), true))
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_call_ref,
    @core.Instr::CallRef(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_call_ref.stack.length(), 1)
  let ctx_return_call_ref = ValidationCtx::new()
  ctx_return_call_ref.stack.push(@core.ValType::I32)
  ctx_return_call_ref.stack.push(
    @core.ValType::Ref(@core.RefType::TypeIndex(0), true),
  )
  let ok = validate_instruction_control(
    module_funcs,
    @core.FuncType::{
      params: [@core.ValType::I32],
      results: [@core.ValType::I32],
    },
    code,
    ctx_return_call_ref,
    @core.Instr::ReturnCallRef(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_return_call_ref.is_unreachable, true)
}

///|
test "validate control block loop if branches" {
  let block_type = @core.FuncType::{
    params: [@core.ValType::I32],
    results: [@core.ValType::I64],
  }
  let module_block : @core.Module = @core.Module::{
    types: [block_type],
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
  let counts = get_import_counts(module_block)
  let code = test_make_code([], [])
  let empty_func = @core.FuncType::{ params: [], results: [] }
  let ctx_block = ValidationCtx::new()
  ctx_block.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_block,
    @core.Instr::Block(@core.BlockType::TypeIndex(0), [@core.Instr::Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_block.stack[0], @core.ValType::I64)
  let mut saw_error = false
  let ctx_block_mismatch = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_block_mismatch,
    @core.Instr::Block(@core.BlockType::Value(@core.ValType::I32), []),
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
    @core.Instr::Block(@core.BlockType::Value(@core.ValType::I32), [
      @core.Instr::I64Const(0UL),
    ]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_loop = ValidationCtx::new()
  ctx_loop.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_loop,
    @core.Instr::Loop(@core.BlockType::TypeIndex(0), [@core.Instr::Unreachable]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_loop.stack[0], @core.ValType::I64)
  saw_error = false
  let ctx_loop_mismatch = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_loop_mismatch,
    @core.Instr::Loop(@core.BlockType::Value(@core.ValType::I32), []),
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
    @core.Instr::Loop(@core.BlockType::Value(@core.ValType::I32), [
      @core.Instr::I64Const(0UL),
    ]),
    counts,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_if = ValidationCtx::new()
  ctx_if.stack.push(@core.ValType::I32)
  ctx_if.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if,
    @core.Instr::If(
      @core.BlockType::TypeIndex(0),
      [@core.Instr::Drop, @core.Instr::I64Const(0UL)],
      [@core.Instr::Unreachable],
    ),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_if.stack[0], @core.ValType::I64)
  saw_error = false
  let ctx_if_then = ValidationCtx::new()
  ctx_if_then.stack.push(@core.ValType::I32)
  ctx_if_then.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if_then,
    @core.Instr::If(@core.BlockType::Value(@core.ValType::I32), [], []),
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
  ctx_if_else.stack.push(@core.ValType::I32)
  ctx_if_else.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_block,
    empty_func,
    code,
    ctx_if_else,
    @core.Instr::If(
      @core.BlockType::Value(@core.ValType::I32),
      [@core.Instr::I32Const(0U)],
      [@core.Instr::I64Const(0UL)],
    ),
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
  let func_type_ret = @core.FuncType::{
    params: [],
    results: [@core.ValType::I32],
  }
  let mut saw_error = false
  let ctx_return_bad = ValidationCtx::new()
  ctx_return_bad.stack.push(@core.ValType::I64)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_return_bad,
    @core.Instr::Return,
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
  ctx_br_short.push_control([], [@core.ValType::I32])
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_short,
    @core.Instr::Br(0U),
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
  ctx_br_mismatch.push_control([], [@core.ValType::I32])
  ctx_br_mismatch.stack.push(@core.ValType::I64)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_mismatch,
    @core.Instr::Br(0U),
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
  ctx_br_unreachable.push_control([], [@core.ValType::I32, @core.ValType::I32])
  ctx_br_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_unreachable,
    @core.Instr::Br(0U),
    counts,
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_br_table_arity = ValidationCtx::new()
  ctx_br_table_arity.push_control([], [])
  ctx_br_table_arity.push_control([], [@core.ValType::I32])
  ctx_br_table_arity.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_arity,
    @core.Instr::BrTable([1U], 0U),
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
  ctx_br_table_short.push_control([], [@core.ValType::I32])
  ctx_br_table_short.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_short,
    @core.Instr::BrTable([], 0U),
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
  ctx_br_table_unreachable.push_control([], [
    @core.ValType::I32,
    @core.ValType::I32,
  ])
  ctx_br_table_unreachable.stack.push(@core.ValType::I32)
  ctx_br_table_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_unreachable,
    @core.Instr::BrTable([], 0U),
    counts,
  )
  assert_eq(ok, true)
  saw_error = false
  let ctx_br_table_mismatch = ValidationCtx::new()
  ctx_br_table_mismatch.push_control([], [@core.ValType::I32])
  ctx_br_table_mismatch.stack.push(@core.ValType::I64)
  ctx_br_table_mismatch.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_empty,
    func_type_ret,
    code,
    ctx_br_table_mismatch,
    @core.Instr::BrTable([], 0U),
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
    @core.Instr::BrOnNull(0U),
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
    @core.Instr::BrOnNonNull(0U),
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
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx_loop_result,
    @core.Instr::Loop(@core.BlockType::Value(@core.ValType::I32), [
      @core.Instr::I32Const(0U),
    ]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_loop_result.stack.length(), 1)
  assert_eq(ctx_loop_result.stack[0], @core.ValType::I32)
}

///|
test "validate control if branch coverage" {
  let block_type = @core.FuncType::{
    params: [@core.ValType::I32],
    results: [@core.ValType::I32],
  }
  let module_if : @core.Module = @core.Module::{
    types: [block_type],
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
  let counts = get_import_counts(module_if)
  let code = test_make_code([], [])
  let empty_func = @core.FuncType::{ params: [], results: [] }
  let ctx_then_unreachable = ValidationCtx::new()
  ctx_then_unreachable.stack.push(@core.ValType::I32)
  ctx_then_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_then_unreachable,
    @core.Instr::If(@core.BlockType::TypeIndex(0), [@core.Instr::Unreachable], [
      @core.Instr::Drop,
      @core.Instr::I32Const(0U),
    ]),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_then_unreachable.stack.length(), 1)
  let ctx_else_unreachable = ValidationCtx::new()
  ctx_else_unreachable.stack.push(@core.ValType::I32)
  ctx_else_unreachable.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_else_unreachable,
    @core.Instr::If(
      @core.BlockType::TypeIndex(0),
      [@core.Instr::Drop, @core.Instr::I32Const(1U)],
      [@core.Instr::Unreachable],
    ),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_else_unreachable.stack.length(), 1)
  let mut saw_error = false
  let ctx_else_mismatch = ValidationCtx::new()
  ctx_else_mismatch.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_else_mismatch,
    @core.Instr::If(
      @core.BlockType::Value(@core.ValType::I32),
      [@core.Instr::I32Const(0U)],
      [],
    ),
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
  ctx_then_mismatch.stack.push(@core.ValType::I32)
  ctx_then_mismatch.stack.push(@core.ValType::I32)
  let _ = validate_instruction_control(
    module_if,
    empty_func,
    code,
    ctx_then_mismatch,
    @core.Instr::If(
      @core.BlockType::TypeIndex(0),
      [@core.Instr::Drop, @core.Instr::I64Const(0UL)],
      [@core.Instr::Drop, @core.Instr::I32Const(0U)],
    ),
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
    @core.FuncType::{ params: [], results: [] },
    code,
    ctx,
    @core.Instr::I32Const(0U),
    counts,
  )
  assert_eq(ok, false)
}

///|
test "validate control br_on_null conversions" {
  let module_empty = test_empty_module()
  let counts = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let empty_func = @core.FuncType::{ params: [], results: [] }
  let ctx_ref_nullable = ValidationCtx::new()
  ctx_ref_nullable.stack.push(@core.ValType::Ref(@core.RefType::Func, true))
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_ref_nullable,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_ref_nullable.stack[0],
    @core.ValType::Ref(@core.RefType::Func, false),
  )
  let ctx_ref_nonnull = ValidationCtx::new()
  ctx_ref_nonnull.stack.push(@core.ValType::Ref(@core.RefType::Func, false))
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_ref_nonnull,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_ref_nonnull.stack[0],
    @core.ValType::Ref(@core.RefType::Func, false),
  )
  let ctx_extern = ValidationCtx::new()
  ctx_extern.stack.push(@core.ValType::ExternRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_extern,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_extern.stack[0],
    @core.ValType::Ref(@core.RefType::Extern, false),
  )
  let ctx_any = ValidationCtx::new()
  ctx_any.stack.push(@core.ValType::AnyRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_any,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_any.stack[0], @core.ValType::Ref(@core.RefType::Any, false))
  let ctx_null_func = ValidationCtx::new()
  ctx_null_func.stack.push(@core.ValType::NullFuncRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_func,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_null_func.stack[0],
    @core.ValType::Ref(@core.RefType::Func, false),
  )
  let ctx_null_extern = ValidationCtx::new()
  ctx_null_extern.stack.push(@core.ValType::NullExternRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_extern,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_null_extern.stack[0],
    @core.ValType::Ref(@core.RefType::Extern, false),
  )
  let ctx_null_any = ValidationCtx::new()
  ctx_null_any.stack.push(@core.ValType::NullRef)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_null_any,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(
    ctx_null_any.stack[0],
    @core.ValType::Ref(@core.RefType::Any, false),
  )
  let ctx_other = ValidationCtx::new()
  ctx_other.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_other,
    @core.Instr::BrOnNull(0U),
    counts,
  )
  assert_eq(ok, true)
  assert_eq(ctx_other.stack[0], @core.ValType::I32)
}

///|
test "validate control call errors" {
  let module_empty = test_empty_module()
  let counts_empty = get_import_counts(module_empty)
  let code = test_make_code([], [])
  let empty_func = @core.FuncType::{ params: [], results: [] }
  let mut saw_error = false
  let ctx_call_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_empty,
    empty_func,
    code,
    ctx_call_bad,
    @core.Instr::Call(0U),
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
    @core.Instr::CallIndirect(0U, 0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let module_import_table : @core.Module = @core.Module::{
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
        name: Bytes::from_array([b't']),
        desc: @core.ImportDesc::Table(@core.TableType::{
          elem_type: @core.RefType::Func,
          limits: @core.Limits::{ min: 0U, max: None },
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
  ctx_call_indirect.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_import_table,
    empty_func,
    code,
    ctx_call_indirect,
    @core.Instr::CallIndirect(0U, 0U),
    counts_import,
  )
  assert_eq(ok, true)
  let module_import_scan : @core.Module = @core.Module::{
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
        desc: @core.ImportDesc::Func(0U),
      },
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
    ],
    exports: [],
    codes: [],
  }
  let counts_scan = get_import_counts(module_import_scan)
  let ctx_call_indirect_scan = ValidationCtx::new()
  ctx_call_indirect_scan.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_import_scan,
    empty_func,
    code,
    ctx_call_indirect_scan,
    @core.Instr::CallIndirect(0U, 0U),
    counts_scan,
  )
  assert_eq(ok, true)
  let ctx_return_call_indirect_scan = ValidationCtx::new()
  ctx_return_call_indirect_scan.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_import_scan,
    empty_func,
    code,
    ctx_return_call_indirect_scan,
    @core.Instr::ReturnCallIndirect(0U, 0U),
    counts_scan,
  )
  assert_eq(ok, true)
  saw_error = false
  let module_table_bad : @core.Module = @core.Module::{
    types: [@core.FuncType::{ params: [], results: [] }],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Extern,
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
  let ctx_call_indirect_bad_table = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_bad,
    empty_func,
    code,
    ctx_call_indirect_bad_table,
    @core.Instr::CallIndirect(0U, 0U),
    get_import_counts(module_table_bad),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let module_table_no_types : @core.Module = @core.Module::{
    types: [],
    funcs: [],
    tables: [
      @core.TableType::{
        elem_type: @core.RefType::Func,
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
  let ctx_call_indirect_bad_type = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_table_no_types,
    empty_func,
    code,
    ctx_call_indirect_bad_type,
    @core.Instr::CallIndirect(0U, 0U),
    get_import_counts(module_table_no_types),
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  saw_error = false
  let module_return_call : @core.Module = @core.Module::{
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
  let ctx_return_call_bad = ValidationCtx::new()
  let _ = validate_instruction_control(
    module_return_call,
    empty_func,
    code,
    ctx_return_call_bad,
    @core.Instr::ReturnCall(0U),
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
    @core.Instr::ReturnCallIndirect(0U, 0U),
    counts_empty,
  ) catch {
    _ => {
      saw_error = true
      false
    }
  }
  assert_eq(saw_error, true)
  let ctx_return_call_indirect = ValidationCtx::new()
  ctx_return_call_indirect.stack.push(@core.ValType::I32)
  let ok = validate_instruction_control(
    module_import_table,
    empty_func,
    code,
    ctx_return_call_indirect,
    @core.Instr::ReturnCallIndirect(0U, 0U),
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
    @core.Instr::ReturnCallIndirect(0U, 0U),
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
    @core.Instr::ReturnCallIndirect(0U, 0U),
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
    @core.Instr::CallRef(0U),
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
    @core.Instr::ReturnCallRef(0U),
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
  let func_type = @core.FuncType::{ params: [], results: [] }
  let code = test_make_code([], [@core.Instr::I32Const(0U)])
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
  let func_type_param = @core.FuncType::{
    params: [@core.ValType::Ref(@core.RefType::TypeIndex(0), true)],
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
  let func_type_result = @core.FuncType::{
    params: [],
    results: [@core.ValType::I32],
  }
  let code_result = test_make_code([], [@core.Instr::I64Const(0UL)])
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
  let code_extra = test_make_code([], [
    @core.Instr::I32Const(0U),
    @core.Instr::I32Const(1U),
  ])
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
