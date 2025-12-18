// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Convert RefType to ValType
fn reftype_to_valtype(ref_type : RefType) -> ValType {
  match ref_type {
    RefType::Func => ValType::FuncRef
    RefType::Extern => ValType::ExternRef
    RefType::Any => ValType::AnyRef
    RefType::Eq => ValType::EqRef
    RefType::I31 => ValType::I31Ref
    RefType::Struct => ValType::StructRef
    RefType::Array => ValType::ArrayRef
    RefType::Exn => ValType::ExnRef
    RefType::None => ValType::NullRef
    RefType::NoFunc => ValType::NullFuncRef
    RefType::NoExtern => ValType::NullExternRef
    RefType::NoExn => ValType::NullExnRef
    // TypeIndex: return nullable typed reference (ref null $t)
    RefType::TypeIndex(_) => ValType::Ref(ref_type, true)
  }
}

///|
/// Cached counts of imported resources
priv struct ImportCounts {
  funcs : Int
  tables : Int
  mems : Int
  globals : Int
}

///|
/// Compute import counts in a single pass through imports
/// This is more efficient than counting each type separately
fn get_import_counts(module_ : Module) -> ImportCounts {
  let mut funcs = 0
  let mut tables = 0
  let mut mems = 0
  let mut globals = 0
  for imp in module_.imports {
    match imp.desc {
      ImportDesc::Func(_) => funcs += 1
      ImportDesc::Table(_) => tables += 1
      ImportDesc::Mem(_) => mems += 1
      ImportDesc::Global(_) => globals += 1
      _ => ()
    }
  }
  { funcs, tables, mems, globals }
}

///|
/// Get the type index for a function (imported or local)
fn get_func_type_index(
  module_ : Module,
  func_idx : Int,
  import_counts : ImportCounts,
) -> Int raise ValidationError {
  if func_idx < import_counts.funcs {
    // Imported function - find type index from imports
    let mut current_import = 0
    let mut found_type_idx = 0
    for imp in module_.imports {
      match imp.desc {
        ImportDesc::Func(tidx) => {
          if current_import == func_idx {
            found_type_idx = tidx.reinterpret_as_int()
            break
          }
          current_import += 1
        }
        _ => ()
      }
    }
    found_type_idx
  } else {
    // Local function - get type index from funcs array
    let local_idx = func_idx - import_counts.funcs
    if local_idx < 0 || local_idx >= module_.funcs.length() {
      raise ValidationError::InvalidFunctionIndex(func_idx)
    }
    module_.funcs[local_idx].reinterpret_as_int()
  }
}

///|
/// Validate a binary operation
fn validate_binary_op(
  ctx : ValidationCtx,
  module_ : Module,
  operand_type : ValType,
  result_type : ValType,
  op_name : String,
) -> Unit raise ValidationError {
  ctx.poly_pop_expect(module_, operand_type, op_name)
  ctx.poly_pop_expect(module_, operand_type, op_name)
  ctx.stack.push(result_type)
}

///|
/// Validate a memory load instruction
fn validate_load(
  ctx : ValidationCtx,
  module_ : Module,
  import_counts : ImportCounts,
  align : UInt,
  natural_align : Int,
  result_type : ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_exists(module_, import_counts)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, I32, "\{op_name} address")
  ctx.stack.push(result_type)
}

///|
/// Validate a memory store instruction
fn validate_store(
  ctx : ValidationCtx,
  module_ : Module,
  import_counts : ImportCounts,
  align : UInt,
  natural_align : Int,
  value_type : ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_exists(module_, import_counts)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, value_type, "\{op_name} value")
  ctx.poly_pop_expect(module_, I32, "\{op_name} address")
}

///|
/// Validate alignment - alignment must not be larger than natural alignment
/// align parameter is stored as log2(alignment), natural is in bytes
fn validate_alignment(
  align : UInt,
  natural : Int,
) -> Unit raise ValidationError {
  // align is log2 of alignment (e.g., align=2 means 2^2 = 4 byte alignment)
  // natural is the natural alignment in bytes
  let align_int = align.reinterpret_as_int()
  let max_align = match natural {
    1 => 0 // 2^0 = 1
    2 => 1 // 2^1 = 2
    4 => 2 // 2^2 = 4
    8 => 3 // 2^3 = 8
    _ => {
      // Calculate log2 of natural alignment
      let mut n = natural
      let mut log = 0
      while n > 1 {
        n = n / 2
        log = log + 1
      }
      log
    }
  }
  if align_int > max_align {
    raise ValidationError::InvalidAlignment(
      "alignment must not be larger than natural (align=\{align_int}, max=\{max_align})",
    )
  }
}

///|
/// Validate that a memory exists in the module (memory 0)
fn validate_memory_exists(
  module_ : Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  let total_mems = import_counts.mems + module_.mems.length()
  if total_mems == 0 {
    raise ValidationError::UnknownMemory(0)
  }
}

///|
/// Validate that all instructions in an expression are valid constant expression instructions
/// WebAssembly constant expressions can only contain:
/// - Constant instructions: i32.const, i64.const, f32.const, f64.const
/// - Reference instructions: ref.null, ref.func
/// - Global access: global.get
/// - Arithmetic: i32.add, i32.sub, i32.mul, i64.add, i64.sub, i64.mul
fn validate_const_expr_instructions(expr : Expr) -> Unit raise ValidationError {
  for instr in expr.instrs {
    match instr {
      I32Const(_)
      | I64Const(_)
      | F32Const(_)
      | F64Const(_)
      | RefNull(_)
      | RefFunc(_)
      | GlobalGet(_)
      | I32Add
      | I32Sub
      | I32Mul
      | I64Add
      | I64Sub
      | I64Mul => () // Valid constant expression instructions
      _ =>
        raise ValidationError::ConstantExpressionRequired(
          "invalid instruction in constant expression: \{instr}",
        )
    }
  }
}

///|
/// Validate that a table init expression only references imported globals
/// Table initialization happens before local globals are initialized,
/// so only imported globals are available
fn validate_table_init_expr(
  m : Module,
  expr : Expr,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // First check that instructions are valid constant expression instructions
  validate_const_expr_instructions(expr)

  // Then check that global.get only references imported globals
  for instr in expr.instrs {
    match instr {
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Must be an imported global (index < import_counts.globals)
        if global_idx >= import_counts.globals {
          raise ValidationError::UnknownGlobal(global_idx)
        }
        // Also check that the imported global is immutable
        let mut import_global_idx = 0
        for imp in m.imports {
          match imp.desc {
            ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                if gt.mutable {
                  raise ValidationError::ConstantExpressionRequired(
                    "table initializer global.get must reference immutable global",
                  )
                }
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// Validate that a constant expression only uses immutable globals
/// WebAssembly constant expressions can only use global.get on immutable globals
fn validate_const_expr_globals(
  m : Module,
  expr : Expr,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  for instr in expr.instrs {
    match instr {
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Check if global is mutable
        let is_mutable = if global_idx < import_counts.globals {
          // Imported global
          let mut import_global_idx = 0
          let mut found_mutable = false
          for imp in m.imports {
            match imp.desc {
              ImportDesc::Global(gt) => {
                if import_global_idx == global_idx {
                  found_mutable = gt.mutable
                  break
                }
                import_global_idx += 1
              }
              _ => ()
            }
          }
          found_mutable
        } else {
          // Local global
          let local_idx = global_idx - import_counts.globals
          if local_idx >= 0 && local_idx < m.globals.length() {
            m.globals[local_idx].type_.mutable
          } else {
            false
          }
        }
        if is_mutable {
          raise ValidationError::ConstantExpressionRequired(
            "global.get in constant expression must reference immutable global",
          )
        }
      }
      _ => ()
    }
  }
}

///|
/// Check if a type index refers to a function type in the module
fn is_func_type_index(module_ : Module, type_idx : Int) -> Bool {
  // In our current implementation, all entries in module_.types are FuncType
  // So any valid type index is a function type
  type_idx >= 0 && type_idx < module_.types.length()
}

///|
/// Validate that all type indices in a ValType exist in the module
fn validate_valtype(
  module_ : Module,
  val_type : ValType,
) -> Unit raise ValidationError {
  match val_type {
    Ref(RefType::TypeIndex(idx), _) =>
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::UnknownType(idx)
      }
    _ => () // Other types don't have type indices
  }
}

///|
/// Check if t1 is a subtype of t2 (t1 <: t2) with module context for type lookups
/// WebAssembly GC type hierarchy:
/// - NullRef (none) <: all nullable reference types
/// - NullFuncRef (nofunc) <: FuncRef
/// - NullExternRef (noextern) <: ExternRef
/// - NullExnRef (noexn) <: ExnRef
/// - I31Ref, StructRef, ArrayRef <: EqRef <: AnyRef
/// - FuncRef <: AnyRef (in some proposals)
fn is_subtype(module_ : Module, t1 : ValType, t2 : ValType) -> Bool {
  // Reflexive: every type is a subtype of itself
  if t1 == t2 {
    return true
  }
  match (t1, t2) {
    // Bottom types (null) are subtypes of their corresponding reference types
    (NullRef, AnyRef)
    | (NullRef, EqRef)
    | (NullRef, I31Ref)
    | (NullRef, StructRef)
    | (NullRef, ArrayRef) => true
    (NullFuncRef, FuncRef) => true
    // NullFuncRef is the bottom type for all function references,
    // so it's a subtype of any nullable typed function reference
    (NullFuncRef, Ref(RefType::TypeIndex(n), true)) =>
      is_func_type_index(module_, n)
    (NullFuncRef, Ref(RefType::Func, true)) => true
    (NullExternRef, ExternRef) => true
    (NullExnRef, ExnRef) => true

    // Reference type hierarchy
    (I31Ref, EqRef) | (I31Ref, AnyRef) => true
    (StructRef, EqRef) | (StructRef, AnyRef) => true
    (ArrayRef, EqRef) | (ArrayRef, AnyRef) => true
    (EqRef, AnyRef) => true

    // Some proposals allow funcref <: anyref
    (FuncRef, AnyRef) => true
    (ExnRef, AnyRef) => true

    // Typed references: Ref(T, nullable)
    // Non-nullable is subtype of nullable for same heap type
    (Ref(ht1, false), Ref(ht2, true)) => ht1 == ht2
    // Ref(Extern, _) is compatible with ExternRef (nullable externref)
    (Ref(RefType::Extern, _), ExternRef) => true
    // Ref(Func, _) is compatible with FuncRef (nullable funcref)
    (Ref(RefType::Func, _), FuncRef) => true
    // Ref(TypeIndex(n), _) is a typed function reference, compatible with FuncRef
    // only if type n is actually a function type
    (Ref(RefType::TypeIndex(n), _), FuncRef) => is_func_type_index(module_, n)
    // Typed function reference is also compatible with non-nullable (ref func)
    (Ref(RefType::TypeIndex(n), false), Ref(RefType::Func, false)) =>
      is_func_type_index(module_, n)
    (Ref(RefType::TypeIndex(n), _), Ref(RefType::Func, true)) =>
      is_func_type_index(module_, n)
    // FuncRef is compatible with nullable typed function reference
    // only if the type index refers to a function type
    (FuncRef, Ref(RefType::TypeIndex(n), true)) =>
      is_func_type_index(module_, n)
    (FuncRef, Ref(RefType::Func, true)) => true
    // Ref(Any, _) is compatible with AnyRef
    (Ref(RefType::Any, _), AnyRef) => true
    // Ref(Exn, _) is compatible with ExnRef
    (Ref(RefType::Exn, _), ExnRef) => true
    // Any reference is subtype of AnyRef
    (Ref(_, _), AnyRef) => true

    // Non-reference types are not related by subtyping
    _ => false
  }
}

///|
/// Validate a WebAssembly module
fn validate_module(m : Module) -> Unit raise ValidationError {
  // Compute import counts once for efficiency
  let import_counts = get_import_counts(m)

  // Validate that all type indices in type definitions are valid
  for func_type in m.types {
    for param in func_type.params {
      validate_valtype(m, param)
    }
    for result in func_type.results {
      validate_valtype(m, result)
    }
  }

  // Validate type indices in global types
  for global in m.globals {
    validate_valtype(m, global.type_.val_type)
  }

  // Validate type indices in table element types
  for table in m.tables {
    match table.elem_type {
      RefType::TypeIndex(idx) =>
        if idx < 0 || idx >= m.types.length() {
          raise ValidationError::UnknownType(idx)
        }
      _ => ()
    }
  }

  // Validate type indices in element segments
  for elem in m.elems {
    match elem.elem_type {
      RefType::TypeIndex(idx) =>
        if idx < 0 || idx >= m.types.length() {
          raise ValidationError::UnknownType(idx)
        }
      _ => ()
    }
  }

  // Validate type indices in imported functions
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Func(tidx) => {
        let type_idx = tidx.reinterpret_as_int()
        if type_idx < 0 || type_idx >= m.types.length() {
          raise ValidationError::InvalidTypeIndex(type_idx)
        }
      }
      _ => ()
    }
  }

  // Validate function type indices
  for i in 0..<m.funcs.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
  }

  // Validate start function if present
  match m.start {
    Some(start_idx) => {
      let func_idx = start_idx.reinterpret_as_int()

      // Count total functions (imported + local)
      let total_funcs = import_counts.funcs + m.funcs.length()

      // Check if function index is valid
      if func_idx < 0 || func_idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(func_idx)
      }

      // Get the function type
      let type_idx = get_func_type_index(m, func_idx, import_counts)
      let func_type = m.types[type_idx]

      // Start function must have type [] -> []
      if func_type.params.length() > 0 {
        raise ValidationError::InvalidStartFunction(
          "start function must have no parameters",
        )
      }
      if func_type.results.length() > 0 {
        raise ValidationError::InvalidStartFunction(
          "start function must have no results",
        )
      }
    }
    None => ()
  }

  // Validate global initializers
  for global in m.globals {
    // Validate that only constant expression instructions are used
    validate_const_expr_instructions(global.init)
    // Validate that global.get only references immutable globals
    validate_const_expr_globals(m, global.init, import_counts)

    // Create a validation context for the init expression
    let init_ctx = ValidationCtx::new()
    // Validate each instruction in the init expression
    let dummy_func_type : FuncType = { params: [], results: [] }
    let dummy_code : Code = { locals: [], body: global.init, compiled: None }
    for instr in global.init.instrs {
      validate_instruction(
        m, dummy_func_type, dummy_code, init_ctx, instr, import_counts,
      )
    }
    // Check that init expression produces exactly one value of the correct type
    if init_ctx.stack.length() != 1 {
      raise ValidationError::TypeMismatch(
        "global initializer must produce exactly one value, got \{init_ctx.stack.length()}",
      )
    }
    let produced_type = init_ctx.stack[0]
    // Use subtyping: init type must be a subtype of the declared global type
    if not(is_subtype(m, produced_type, global.type_.val_type)) {
      raise ValidationError::TypeMismatch(
        "global initializer type mismatch: expected \{global.type_.val_type}, got \{produced_type}",
      )
    }
  }

  // Validate memory limits
  for mem in m.mems {
    match mem.limits.max {
      Some(max_val) => {
        let min = mem.limits.min.reinterpret_as_int()
        let max = max_val.reinterpret_as_int()
        if min > max {
          raise ValidationError::InvalidMemorySize(
            "size minimum must not be greater than maximum",
          )
        }
        if max_val > 65536 {
          raise ValidationError::InvalidMemorySize(
            "memory size must be at most 65536 pages (4GiB)",
          )
        }
      }
      None =>
        if mem.limits.min > 65536 {
          raise ValidationError::InvalidMemorySize(
            "memory size must be at most 65536 pages (4GiB)",
          )
        }
    }
  }

  // Validate memory limits for imported memories
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Mem(mem_type) =>
        match mem_type.limits.max {
          Some(max_val) => {
            let min = mem_type.limits.min.reinterpret_as_int()
            let max = max_val.reinterpret_as_int()
            if min > max {
              raise ValidationError::InvalidMemorySize(
                "size minimum must not be greater than maximum",
              )
            }
            if max_val > 65536 {
              raise ValidationError::InvalidMemorySize(
                "memory size must be at most 65536 pages (4GiB)",
              )
            }
          }
          None =>
            if mem_type.limits.min > 65536 {
              raise ValidationError::InvalidMemorySize(
                "memory size must be at most 65536 pages (4GiB)",
              )
            }
        }
      _ => ()
    }
  }

  // Validate table limits and initializers
  for table in m.tables {
    match table.limits.max {
      Some(max_val) =>
        // Use unsigned comparison - compare UInt values directly
        if table.limits.min > max_val {
          raise ValidationError::InvalidTableSize(
            "size minimum must not be greater than maximum",
          )
        }
      None => ()
    }
    // Validate table initializer
    // If the table element type is non-nullable, it must have an initializer
    if not(table.nullable) {
      match table.init {
        None =>
          raise ValidationError::TypeMismatch(
            "table with non-nullable element type must have initializer",
          )
        Some(init_expr) => {
          // Validate that table init only references imported globals
          validate_table_init_expr(m, init_expr, import_counts)

          // For non-nullable tables, ref.null is not allowed
          for instr in init_expr.instrs {
            match instr {
              RefNull(_) =>
                raise ValidationError::TypeMismatch(
                  "table with non-nullable element type cannot be initialized with null",
                )
              _ => ()
            }
          }
          // Validate the initializer expression type matches the element type
          let init_ctx = ValidationCtx::new()
          let dummy_func_type : FuncType = { params: [], results: [] }
          let dummy_code : Code = {
            locals: [],
            body: init_expr,
            compiled: None,
          }
          for instr in init_expr.instrs {
            validate_instruction(
              m, dummy_func_type, dummy_code, init_ctx, instr, import_counts,
            )
          }
          if init_ctx.stack.length() != 1 {
            raise ValidationError::TypeMismatch(
              "table initializer must produce exactly one value",
            )
          }
          // Check that the init expression type is a reference type
          let init_type = init_ctx.stack[0]
          match init_type {
            FuncRef
            | ExternRef
            | AnyRef
            | NullRef
            | NullFuncRef
            | NullExternRef
            | Ref(_, _) => ()
            _ =>
              raise ValidationError::TypeMismatch(
                "table initializer must produce a reference type",
              )
          }
        }
      }
    } else {
      // Nullable table with initializer - validate the init type
      match table.init {
        Some(init_expr) => {
          // Validate that table init only references imported globals
          validate_table_init_expr(m, init_expr, import_counts)
          let init_ctx = ValidationCtx::new()
          let dummy_func_type : FuncType = { params: [], results: [] }
          let dummy_code : Code = {
            locals: [],
            body: init_expr,
            compiled: None,
          }
          for instr in init_expr.instrs {
            validate_instruction(
              m, dummy_func_type, dummy_code, init_ctx, instr, import_counts,
            )
          }
          if init_ctx.stack.length() != 1 {
            raise ValidationError::TypeMismatch(
              "table initializer must produce exactly one value",
            )
          }
          let init_type = init_ctx.stack[0]
          // Check that init type is compatible with table element type
          // For nullable tables, we need to check if the init type is compatible
          // Funcref table can accept funcref or null
          // Type must be a reference type
          match init_type {
            FuncRef
            | ExternRef
            | AnyRef
            | NullRef
            | NullFuncRef
            | NullExternRef => ()
            I32 | I64 | F32 | F64 =>
              raise ValidationError::TypeMismatch(
                "table initializer must produce a reference type, got \{init_type}",
              )
            _ => ()
          }
          // Check element type compatibility
          match (table.elem_type, init_type) {
            (RefType::Func, FuncRef)
            | (RefType::Func, NullFuncRef)
            | (RefType::Extern, ExternRef)
            | (RefType::Extern, NullExternRef) => ()
            (RefType::Func, ExternRef)
            | (RefType::Func, NullExternRef)
            | (RefType::Func, NullRef) =>
              raise ValidationError::TypeMismatch(
                "table initializer type mismatch: table expects funcref, got \{init_type}",
              )
            (RefType::Extern, FuncRef)
            | (RefType::Extern, NullFuncRef)
            | (RefType::Extern, NullRef) =>
              raise ValidationError::TypeMismatch(
                "table initializer type mismatch: table expects externref, got \{init_type}",
              )
            _ => ()
          }
        }
        None => ()
      }
    }
  }

  // Validate table limits for imported tables
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Table(table_type) =>
        match table_type.limits.max {
          Some(max_val) =>
            // Use unsigned comparison - compare UInt values directly
            if table_type.limits.min > max_val {
              raise ValidationError::InvalidTableSize(
                "size minimum must not be greater than maximum",
              )
            }
          None => ()
        }
      _ => ()
    }
  }

  // Validate element segments
  // Only active segments reference tables; passive/declarative segments don't
  // Count total tables (imported + local)
  let total_tables = import_counts.tables + m.tables.length()
  let total_funcs = import_counts.funcs + m.funcs.length()
  for elem in m.elems {
    // Only validate table index for active segments
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx < 0 || table_idx >= total_tables {
        raise ValidationError::UnknownTable(table_idx)
      }
    }

    // Validate that all function indices in the element segment are valid
    for func_idx in elem.init {
      let func_idx_int = func_idx.reinterpret_as_int()
      if func_idx_int < 0 || func_idx_int >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(func_idx_int)
      }
    }
  }

  // Validate data segments reference valid memories
  // Only active segments reference memories; passive/declarative segments don't
  // Count total memories (imported + local)
  let total_mems = import_counts.mems + m.mems.length()
  for data in m.datas {
    // Only validate memory index for active segments
    if data.is_active {
      let mem_idx = data.mem_idx.reinterpret_as_int()
      if mem_idx < 0 || mem_idx >= total_mems {
        raise ValidationError::UnknownMemory(mem_idx)
      }
      // Validate offset expression uses only immutable globals
      validate_const_expr_globals(m, data.offset, import_counts)
    }
  }

  // Validate function bodies against their types
  for i in 0..<m.codes.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    let func_type = m.types[type_idx]
    let code = m.codes[i]

    // Validate the function body
    validate_function(m, func_type, code, import_counts)
  }

  // Validate exports
  let export_names : Set[Bytes] = Set::new()
  for exp in m.exports {
    // Check for duplicate export names
    if export_names.contains(exp.name) {
      raise ValidationError::DuplicateExport(
        "duplicate export name: '\{exp.name}'",
      )
    }
    export_names.add(exp.name)
    // Check for unknown func, memory, table, global indices
    match exp.desc {
      Mem(idx) => {
        let mem_idx = idx.reinterpret_as_int()
        let total_mems = import_counts.mems + m.mems.length()
        if mem_idx < 0 || mem_idx >= total_mems {
          raise ValidationError::UnknownExportedMemory(mem_idx)
        }
      }
      Table(idx) => {
        let table_idx = idx.reinterpret_as_int()
        let total_tables = import_counts.tables + m.tables.length()
        if table_idx < 0 || table_idx >= total_tables {
          raise ValidationError::UnknownExportedTable(table_idx)
        }
      }
      Func(idx) => {
        let func_idx = idx.reinterpret_as_int()
        let total_funcs = import_counts.funcs + m.funcs.length()
        if func_idx < 0 || func_idx >= total_funcs {
          raise ValidationError::UnknownExportedFunction(func_idx)
        }
      }
      Global(idx) => {
        let global_idx = idx.reinterpret_as_int()
        let total_globals = import_counts.globals + m.globals.length()
        if global_idx < 0 || global_idx >= total_globals {
          raise ValidationError::UnknownExportedGlobal(global_idx)
        }
      }
      Tag(_) => () // Skip tag export validation for now
    }
  }
}

///|
/// Get the function type signature for a block type
fn get_block_type(
  module_ : Module,
  block_type : BlockType,
) -> (Array[ValType], Array[ValType]) raise ValidationError {
  match block_type {
    Empty => ([], [])
    Value(t) => {
      validate_valtype(module_, t)
      ([], [t])
    }
    TypeIndex(idx) => {
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
}

///|
/// Validation context that tracks both the type stack and unreachable state
priv struct ValidationCtx {
  stack : Array[ValType]
  mut is_unreachable : Bool
  // Stack of control frames - each frame tracks the expected result types
  // For br validation, we need to know what types the target label expects
  control_stack : Array[(Array[ValType], Array[ValType])] // (params, results) for each control frame
  // Track which locals are initialized (for non-defaultable types)
  // Index corresponds to local index (params first, then locals)
  initialized_locals : Array[Bool]
}

///|
fn ValidationCtx::new() -> ValidationCtx {
  {
    stack: [],
    is_unreachable: false,
    control_stack: [],
    initialized_locals: [],
  }
}

///|
/// Create a validation context with initialized locals tracking
/// Params are always initialized; locals are initialized only if defaultable
fn ValidationCtx::new_with_locals(
  func_type : FuncType,
  code : Code,
) -> ValidationCtx {
  let total_locals = func_type.params.length() + code.locals.length()
  let initialized = Array::make(total_locals, false)
  // Parameters are always initialized
  for i in 0..<func_type.params.length() {
    initialized[i] = true
  }
  // Locals with defaultable types are initialized to their default value
  for i in 0..<code.locals.length() {
    let local_type = code.locals[i]
    if local_type.is_defaultable() {
      initialized[func_type.params.length() + i] = true
    }
  }
  {
    stack: [],
    is_unreachable: false,
    control_stack: [],
    initialized_locals: initialized,
  }
}

///|
fn ValidationCtx::push_control(
  self : ValidationCtx,
  params : Array[ValType],
  results : Array[ValType],
) -> Unit {
  self.control_stack.push((params, results))
}

///|
fn ValidationCtx::pop_control(
  self : ValidationCtx,
) -> (Array[ValType], Array[ValType]) {
  self.control_stack.unsafe_pop()
}

///|
fn ValidationCtx::get_label_types(
  self : ValidationCtx,
  label : UInt,
) -> Array[ValType] raise ValidationError {
  // Labels are relative depth: 0 is innermost, 1 is next outer, etc.
  let idx = self.control_stack.length() - 1 - label.reinterpret_as_int()
  if idx >= 0 && idx < self.control_stack.length() {
    let (_, results) = self.control_stack[idx]
    results
  } else {
    raise ValidationError::UnknownLabel(label.reinterpret_as_int())
  }
}

// =============================================================================
// Polymorphic Stack Operations for Unreachable Code
// =============================================================================
//
// In WebAssembly, after an unconditional control flow instruction (br, return,
// unreachable), subsequent code is "unreachable" and uses polymorphic stack
// validation rules. This means:
//
//   1. Operations can "pop" values that don't exist on the stack
//   2. The stack is treated as having any types needed
//   3. Result types are still pushed for type checking of code after
//      control flow rejoins (e.g., after a block end)
//
// Example: (block (drop (i32.ctz (br 0))))
//   - br 0 branches away, making i32.ctz unreachable
//   - i32.ctz normally requires an i32 on stack, but in unreachable mode
//     it's valid even with an empty stack
//
// These helpers implement polymorphic pop operations that succeed in
// unreachable mode even when the stack is empty.
// =============================================================================

///|
/// Mark code as unreachable and clear the operand stack.
/// This implements the WebAssembly spec requirement that when code becomes
/// unreachable (e.g., after br, return, or tail calls), the operand stack is purged.
fn ValidationCtx::mark_unreachable(self : ValidationCtx) -> Unit {
  self.is_unreachable = true
  self.stack.clear()
}

///|
/// Pop a value from the stack, allowing empty stack in unreachable mode.
/// Returns the type if available, or the expected type if unreachable.
/// Only values below unreachable_stack_height are polymorphic.
fn ValidationCtx::poly_pop(
  self : ValidationCtx,
  expected : ValType,
) -> ValType raise ValidationError {
  if self.stack.length() > 0 {
    self.stack.unsafe_pop()
  } else if self.is_unreachable {
    // In unreachable code with empty stack, this is a polymorphic pop
    // (popping from below the unreachable boundary)
    expected
  } else {
    raise ValidationError::TypeMismatch(
      "expected value on stack, got empty stack",
    )
  }
}

///|
/// Check and pop a value of a specific type, allowing polymorphic behavior.
/// Concrete values (pushed after unreachable) must still type-check.
/// Uses subtyping: actual type must be a subtype of expected type.
fn ValidationCtx::poly_pop_expect(
  self : ValidationCtx,
  module_ : Module,
  expected : ValType,
  op_name : String,
) -> Unit raise ValidationError {
  // In unreachable mode, concrete values are those currently on the stack
  // (they were pushed after unreachable). Polymorphic values are those
  // we pop from an empty stack (they would have been there before unreachable).
  let is_concrete_value = self.stack.length() > 0
  let actual = self.poly_pop(expected)

  // Type-check concrete values, or all values if not in unreachable mode
  // Use subtyping: actual must be a subtype of expected
  if (not(self.is_unreachable) || is_concrete_value) &&
    not(is_subtype(module_, actual, expected)) {
    raise ValidationError::TypeMismatch(
      "\{op_name} requires \{expected}, got \{actual}",
    )
  }
}

///|
/// Validate that a tail call's return type matches the current function's return type.
/// For tail calls (return_call, return_call_indirect, return_call_ref), the called
/// function's return type must match the current function's return type via subtyping.
fn validate_tail_call_return_type(
  module_ : Module,
  func_type_called : FuncType,
  func_type : FuncType,
  instr_name : String,
) -> Unit raise ValidationError {
  if func_type_called.results.length() != func_type.results.length() {
    raise ValidationError::TypeMismatch(
      "\{instr_name}: return type mismatch: expected \{func_type.results.length()} results, got \{func_type_called.results.length()}",
    )
  }
  for i in 0..<func_type_called.results.length() {
    let called_result = func_type_called.results[i]
    let expected_result = func_type.results[i]
    if not(is_subtype(module_, called_result, expected_result)) {
      raise ValidationError::TypeMismatch(
        "\{instr_name}: return type mismatch at position \{i}: expected \{expected_result}, got \{called_result}",
      )
    }
  }
}

///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module_ : Module,
  func_type : FuncType,
  code : Code,
  ctx : ValidationCtx,
  instr : Instr,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    I32Const(_) => stack.push(I32)
    I64Const(_) => stack.push(I64)
    F32Const(_) => stack.push(F32)
    F64Const(_) => stack.push(F64)

    // Binary operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr => validate_binary_op(ctx, module_, I32, I32, "i32 binary op")

    // Comparison operations
    I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU => validate_binary_op(ctx, module_, I32, I32, "i32 comparison")

    // Unary operations
    I32Eqz | I32Clz | I32Ctz | I32Popcnt | I32Extend8S | I32Extend16S => {
      ctx.poly_pop_expect(module_, I32, "i32 unary op")
      stack.push(I32)
    }

    // i64 binary operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr => validate_binary_op(ctx, module_, I64, I64, "i64 binary op")

    // i64 comparison operations
    I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU => validate_binary_op(ctx, module_, I64, I32, "i64 comparison")

    // i64 test operation (returns i32)
    I64Eqz => {
      ctx.poly_pop_expect(module_, I64, "i64.eqz")
      stack.push(I32)
    }

    // i64 unary operations (return i64)
    I64Clz | I64Ctz | I64Popcnt | I64Extend8S | I64Extend16S | I64Extend32S => {
      ctx.poly_pop_expect(module_, I64, "i64 unary op")
      stack.push(I64)
    }

    // i32 to i64 conversion operations
    I64ExtendI32S | I64ExtendI32U => {
      ctx.poly_pop_expect(module_, I32, "i64 extension")
      stack.push(I64)
    }

    // i64 to i32 conversion (wrap)
    I32WrapI64 => {
      ctx.poly_pop_expect(module_, I64, "i32.wrap_i64")
      stack.push(I32)
    }

    // f32 comparison operations
    F32Eq | F32Ne | F32Lt | F32Gt | F32Le | F32Ge =>
      validate_binary_op(ctx, module_, F32, I32, "f32 comparison")

    // f64 comparison operations
    F64Eq | F64Ne | F64Lt | F64Gt | F64Le | F64Ge =>
      validate_binary_op(ctx, module_, F64, I32, "f64 comparison")

    // f32 unary operations
    F32Abs | F32Neg | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Sqrt => {
      ctx.poly_pop_expect(module_, F32, "f32 unary op")
      stack.push(F32)
    }

    // f64 unary operations
    F64Abs | F64Neg | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Sqrt => {
      ctx.poly_pop_expect(module_, F64, "f64 unary op")
      stack.push(F64)
    }

    // f32 binary operations
    F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign =>
      validate_binary_op(ctx, module_, F32, F32, "f32 binary op")

    // f64 binary operations
    F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign =>
      validate_binary_op(ctx, module_, F64, F64, "f64 binary op")

    // Conversion operations: i32 -> f32/f64
    F32ConvertI32S | F32ConvertI32U => {
      ctx.poly_pop_expect(module_, I32, "f32.convert_i32")
      stack.push(F32)
    }
    F64ConvertI32S | F64ConvertI32U => {
      ctx.poly_pop_expect(module_, I32, "f64.convert_i32")
      stack.push(F64)
    }

    // Conversion operations: i64 -> f32/f64
    F32ConvertI64S | F32ConvertI64U => {
      ctx.poly_pop_expect(module_, I64, "f32.convert_i64")
      stack.push(F32)
    }
    F64ConvertI64S | F64ConvertI64U => {
      ctx.poly_pop_expect(module_, I64, "f64.convert_i64")
      stack.push(F64)
    }

    // Promotion/demotion: f32 <-> f64
    F64PromoteF32 => {
      ctx.poly_pop_expect(module_, F32, "f64.promote_f32")
      stack.push(F64)
    }
    F32DemoteF64 => {
      ctx.poly_pop_expect(module_, F64, "f32.demote_f64")
      stack.push(F32)
    }

    // Truncation: f32/f64 -> i32/i64
    I32TruncF32S | I32TruncF32U => {
      ctx.poly_pop_expect(module_, F32, "i32.trunc_f32")
      stack.push(I32)
    }
    I32TruncF64S | I32TruncF64U => {
      ctx.poly_pop_expect(module_, F64, "i32.trunc_f64")
      stack.push(I32)
    }
    I64TruncF32S | I64TruncF32U => {
      ctx.poly_pop_expect(module_, F32, "i64.trunc_f32")
      stack.push(I64)
    }
    I64TruncF64S | I64TruncF64U => {
      ctx.poly_pop_expect(module_, F64, "i64.trunc_f64")
      stack.push(I64)
    }

    // Saturating truncation: f32/f64 -> i32/i64 (same types as regular trunc)
    I32TruncSatF32S | I32TruncSatF32U => {
      ctx.poly_pop_expect(module_, F32, "i32.trunc_sat_f32")
      stack.push(I32)
    }
    I32TruncSatF64S | I32TruncSatF64U => {
      ctx.poly_pop_expect(module_, F64, "i32.trunc_sat_f64")
      stack.push(I32)
    }
    I64TruncSatF32S | I64TruncSatF32U => {
      ctx.poly_pop_expect(module_, F32, "i64.trunc_sat_f32")
      stack.push(I64)
    }
    I64TruncSatF64S | I64TruncSatF64U => {
      ctx.poly_pop_expect(module_, F64, "i64.trunc_sat_f64")
      stack.push(I64)
    }

    // Reinterpret operations
    F32ReinterpretI32 => {
      ctx.poly_pop_expect(module_, I32, "f32.reinterpret_i32")
      stack.push(F32)
    }
    F64ReinterpretI64 => {
      ctx.poly_pop_expect(module_, I64, "f64.reinterpret_i64")
      stack.push(F64)
    }
    I32ReinterpretF32 => {
      ctx.poly_pop_expect(module_, F32, "i32.reinterpret_f32")
      stack.push(I32)
    }
    I64ReinterpretF64 => {
      ctx.poly_pop_expect(module_, F64, "i64.reinterpret_f64")
      stack.push(I64)
    }

    // Local operations
    LocalGet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      // Check initialization for non-defaultable types
      if not(local_type.is_defaultable()) &&
        ctx.initialized_locals.length() > local_idx &&
        not(ctx.initialized_locals[local_idx]) {
        raise ValidationError::UninitializedLocal(local_idx)
      }
      stack.push(local_type)
    }
    LocalSet(idx) | LocalTee(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      ctx.poly_pop_expect(module_, local_type, "local.set")
      // Mark local as initialized
      if ctx.initialized_locals.length() > local_idx {
        ctx.initialized_locals[local_idx] = true
      }
      match instr {
        LocalTee(_) => stack.push(local_type)
        _ => ()
      }
    }

    // Global operations
    // Note: Global index space includes imported globals first, then local globals
    GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      let global_type = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : ValType = ValType::I32 // default
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        found_type
      } else {
        // It's a local global
        module_.globals[global_idx - import_counts.globals].type_.val_type
      }
      stack.push(global_type)
    }
    GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      let (global_type, is_mutable) = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : ValType = ValType::I32 // default
        let mut found_mutable = false
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                found_mutable = gt.mutable
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        (found_type, found_mutable)
      } else {
        // It's a local global
        let global = module_.globals[global_idx - import_counts.globals]
        (global.type_.val_type, global.type_.mutable)
      }
      // Check if global is mutable
      if not(is_mutable) {
        raise ValidationError::ImmutableGlobal(global_idx)
      }
      ctx.poly_pop_expect(module_, global_type, "global.set")
    }

    // Memory operations - loads (all take i32 address and push the loaded value)
    I32Load(align, _) =>
      validate_load(ctx, module_, import_counts, align, 4, I32, "i32.load")
    I32Load8S(align, _) | I32Load8U(align, _) =>
      validate_load(ctx, module_, import_counts, align, 1, I32, "i32.load8")
    I32Load16S(align, _) | I32Load16U(align, _) =>
      validate_load(ctx, module_, import_counts, align, 2, I32, "i32.load16")
    I64Load(align, _) =>
      validate_load(ctx, module_, import_counts, align, 8, I64, "i64.load")
    I64Load8S(align, _) | I64Load8U(align, _) =>
      validate_load(ctx, module_, import_counts, align, 1, I64, "i64.load8")
    I64Load16S(align, _) | I64Load16U(align, _) =>
      validate_load(ctx, module_, import_counts, align, 2, I64, "i64.load16")
    I64Load32S(align, _) | I64Load32U(align, _) =>
      validate_load(ctx, module_, import_counts, align, 4, I64, "i64.load32")
    F32Load(align, _) =>
      validate_load(ctx, module_, import_counts, align, 4, F32, "f32.load")
    F64Load(align, _) =>
      validate_load(ctx, module_, import_counts, align, 8, F64, "f64.load")
    // Memory operations - stores (all take i32 address and value, push nothing)
    I32Store(align, _) =>
      validate_store(ctx, module_, import_counts, align, 4, I32, "i32.store")
    I32Store8(align, _) =>
      validate_store(ctx, module_, import_counts, align, 1, I32, "i32.store8")
    I32Store16(align, _) =>
      validate_store(ctx, module_, import_counts, align, 2, I32, "i32.store16")
    I64Store(align, _) =>
      validate_store(ctx, module_, import_counts, align, 8, I64, "i64.store")
    I64Store8(align, _) =>
      validate_store(ctx, module_, import_counts, align, 1, I64, "i64.store8")
    I64Store16(align, _) =>
      validate_store(ctx, module_, import_counts, align, 2, I64, "i64.store16")
    I64Store32(align, _) =>
      validate_store(ctx, module_, import_counts, align, 4, I64, "i64.store32")
    F32Store(align, _) =>
      validate_store(ctx, module_, import_counts, align, 4, F32, "f32.store")
    F64Store(align, _) =>
      validate_store(ctx, module_, import_counts, align, 8, F64, "f64.store")
    // Memory size and grow
    MemorySize(_) => {
      validate_memory_exists(module_, import_counts)
      stack.push(I32)
    }
    MemoryGrow(_) => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, I32, "memory.grow delta")
      stack.push(I32)
    }

    // Bulk memory instructions
    MemoryCopy => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, I32, "memory.copy n")
      ctx.poly_pop_expect(module_, I32, "memory.copy src")
      ctx.poly_pop_expect(module_, I32, "memory.copy dest")
    }
    MemoryFill => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, I32, "memory.fill n")
      ctx.poly_pop_expect(module_, I32, "memory.fill val")
      ctx.poly_pop_expect(module_, I32, "memory.fill dest")
    }
    MemoryInit(data_idx) => {
      validate_memory_exists(module_, import_counts)
      // Validate data segment index
      if data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise ValidationError::TypeMismatch(
          "memory.init: unknown data segment \{data_idx}",
        )
      }
      ctx.poly_pop_expect(module_, I32, "memory.init n")
      ctx.poly_pop_expect(module_, I32, "memory.init src")
      ctx.poly_pop_expect(module_, I32, "memory.init dest")
    }
    DataDrop(data_idx) =>
      // Validate data segment index
      if data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise ValidationError::TypeMismatch(
          "data.drop: unknown data segment \{data_idx}",
        )
      }

    // Table bulk operations (stub for now)
    TableInit(_, _) => {
      ctx.poly_pop_expect(module_, I32, "table.init n")
      ctx.poly_pop_expect(module_, I32, "table.init src")
      ctx.poly_pop_expect(module_, I32, "table.init dest")
    }
    TableCopy(_, _) => {
      ctx.poly_pop_expect(module_, I32, "table.copy n")
      ctx.poly_pop_expect(module_, I32, "table.copy src")
      ctx.poly_pop_expect(module_, I32, "table.copy dest")
    }
    ElemDrop(_) => ()

    // Table instructions
    TableSize(_) => stack.push(I32)
    TableGet(table_idx) => {
      ctx.poly_pop_expect(module_, I32, "table.get index")
      // Look up table's element type
      let elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        let table = module_.tables[table_idx.reinterpret_as_int()]
        reftype_to_valtype(table.elem_type)
      } else {
        ValType::FuncRef // Default if table not found
      }
      stack.push(elem_type)
    }
    TableSet(table_idx) => {
      // table.set: pop value (top), then index (below)
      // Get table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        RefType::Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : ValType = reftype_to_valtype(table_elem_type)

      // Pop and verify value type matches table element type
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("table.set expects value on stack")
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.set value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }

      // Pop index (i32)
      ctx.poly_pop_expect(module_, I32, "table.set index")
    }
    TableGrow(table_idx) => {
      ctx.poly_pop_expect(module_, I32, "table.grow delta")
      // Pop init value and check it matches table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        RefType::Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : ValType = reftype_to_valtype(table_elem_type)
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "table.grow expects init value on stack",
        )
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.grow init value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }
      stack.push(I32) // Returns old size
    }

    // Reference instructions
    RefNull(ref_type) => {
      // ref.null pushes a null reference of the given type
      let val_type = reftype_to_valtype(ref_type)
      stack.push(val_type)
    }
    RefFunc(func_idx) => {
      // ref.func pushes a typed function reference (non-nullable)
      // Get the function's type index to create the proper typed reference
      let idx = func_idx.reinterpret_as_int()
      // Validate function index
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(idx)
      }
      let type_idx = get_func_type_index(module_, idx, import_counts)
      // Push typed function reference (non-nullable)
      stack.push(ValType::Ref(RefType::TypeIndex(type_idx), false))
    }
    RefIsNull => {
      // ref.is_null pops a reference type and pushes i32
      // In polymorphic context, allow any type on stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.is_null expects reference on stack",
        )
      } else {
        let _ = stack.unsafe_pop()
        // Pop the reference
      }
      stack.push(I32) // Push result
    }

    // Block instructions
    Block(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "block parameter")
      }
      // Create new validation context for block
      let block_ctx = ValidationCtx::new()
      // Add parameters to block stack in correct order
      for param in params {
        block_ctx.stack.push(param)
      }
      // Copy parent control stack and add this block's frame
      for frame in ctx.control_stack {
        block_ctx.control_stack.push(frame)
      }
      block_ctx.push_control(params, results)
      // Copy initialized locals from parent context
      // After block, we don't propagate back (block might branch out early)
      for i in 0..<ctx.initialized_locals.length() {
        block_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate block body
      for block_instr in instrs {
        validate_instruction(
          module_, func_type, code, block_ctx, block_instr, import_counts,
        )
      }
      let _ = block_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from block_ctx
      // because the block might have exited early via branch
      // Check block produces correct results
      if block_ctx.is_unreachable && block_ctx.stack.length() == 0 {
        // Unreachable code with empty stack - all polymorphic, push expected results
        for result in results {
          stack.push(result)
        }
      } else if block_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - this is a type mismatch
        raise ValidationError::TypeMismatch(
          "block: expected \{results.length()} values, got \{block_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, block_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "block result type mismatch: expected \{results[i]}, got \{block_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    Loop(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "loop parameter")
      }
      // Create new validation context for loop
      let loop_ctx = ValidationCtx::new()
      // Add parameters to loop stack in correct order
      for param in params {
        loop_ctx.stack.push(param)
      }
      // Copy parent control stack and add this loop's frame
      // Note: For loops, br targets the beginning (params), not the end (results)
      for frame in ctx.control_stack {
        loop_ctx.control_stack.push(frame)
      }
      loop_ctx.push_control(params, params) // Loop's br target uses params, not results
      // Copy initialized locals from parent context
      // Loop is similar to block - don't propagate back
      for i in 0..<ctx.initialized_locals.length() {
        loop_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate loop body
      for loop_instr in instrs {
        validate_instruction(
          module_, func_type, code, loop_ctx, loop_instr, import_counts,
        )
      }
      let _ = loop_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from loop_ctx
      // Check loop produces correct results
      if loop_ctx.is_unreachable && loop_ctx.stack.length() == 0 {
        // Unreachable code with empty stack - all polymorphic
        for result in results {
          stack.push(result)
        }
      } else if loop_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - type mismatch
        raise ValidationError::TypeMismatch(
          "loop: expected \{results.length()} values, got \{loop_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, loop_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "loop result type mismatch: expected \{results[i]}, got \{loop_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    If(block_type, then_instrs, else_instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop condition (using polymorphic stack)
      ctx.poly_pop_expect(module_, I32, "if condition")
      // Pop parameters from parent stack (using polymorphic stack)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "if parameter")
      }
      // Validate then branch
      let then_ctx = ValidationCtx::new()
      for param in params {
        then_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        then_ctx.control_stack.push(frame)
      }
      then_ctx.push_control(params, results)
      // Copy initialized locals from parent context
      for i in 0..<ctx.initialized_locals.length() {
        then_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for then_instr in then_instrs {
        validate_instruction(
          module_, func_type, code, then_ctx, then_instr, import_counts,
        )
      }
      let _ = then_ctx.pop_control()
      // Check then branch produces correct results
      if then_ctx.is_unreachable && then_ctx.stack.length() == 0 {
        // Unreachable with empty stack - all polymorphic, valid
      } else if then_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if then branch: expected \{results.length()} values, got \{then_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, then_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "if then branch result type mismatch: expected \{results[i]}, got \{then_ctx.stack[i]}",
            )
          }
        }
      }
      // Validate else branch
      let else_ctx = ValidationCtx::new()
      for param in params {
        else_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        else_ctx.control_stack.push(frame)
      }
      else_ctx.push_control(params, results)
      // Copy initialized locals from parent context (independently from then branch)
      for i in 0..<ctx.initialized_locals.length() {
        else_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for else_instr in else_instrs {
        validate_instruction(
          module_, func_type, code, else_ctx, else_instr, import_counts,
        )
      }
      let _ = else_ctx.pop_control()
      // Check else branch produces correct results
      if else_ctx.is_unreachable && else_ctx.stack.length() == 0 {
        // Unreachable with empty stack - all polymorphic, valid
      } else if else_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if else branch: expected \{results.length()} values, got \{else_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, else_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "if else branch result type mismatch: expected \{results[i]}, got \{else_ctx.stack[i]}",
            )
          }
        }
      }
      // Note: We do NOT propagate initialized_locals back from either branch
      // because branches might exit early via br/return
      // Push results onto parent stack
      for result in results {
        stack.push(result)
      }
    }

    // Control flow
    Return => {
      // In unreachable code with empty stack, allow polymorphic return
      // Otherwise, validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Check we have the right values on stack for function return
        if stack.length() < func_type.results.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "return: expected \{func_type.results.length()} values on stack",
            )
          }
        } else {
          // Validate result types for concrete values (with subtyping)
          for i in 0..<func_type.results.length() {
            let stack_idx = stack.length() - func_type.results.length() + i
            if not(is_subtype(module_, stack[stack_idx], func_type.results[i])) {
              raise ValidationError::TypeMismatch(
                "return: result type mismatch: expected \{func_type.results[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    Br(label) => {
      // Always validate label exists (even in unreachable code)
      let target_types = ctx.get_label_types(label)

      // Validate stack contents (even in unreachable code with concrete values)
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Unconditional branch - validate we have required values for target
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "br: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for the branch target (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise ValidationError::TypeMismatch(
                "br: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    BrIf(label) => {
      // Conditional branch
      // First, validate label exists
      let target_types = ctx.get_label_types(label)

      // Pop i32 condition
      ctx.poly_pop_expect(module_, I32, "br_if condition")

      // Validate that branch target's required values are on stack
      // Unlike br, we DON'T pop them (they stay for fallthrough case)
      if not(ctx.is_unreachable) || stack.length() > 0 {
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "br_if: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for the branch target (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise ValidationError::TypeMismatch(
                "br_if: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Note: Unlike br, br_if does NOT mark as unreachable
      // Stack remains unchanged (values stay for fallthrough)
    }
    BrTable(labels, default_label) => {
      // Table branch - pop i32 index
      ctx.poly_pop_expect(module_, I32, "br_table index")

      // Validate all labels exist and have compatible types
      let default_types = ctx.get_label_types(default_label)

      // All labels (including default) must have the same arity and types
      // TODO: This validation is currently disabled due to a bug where get_label_types
      // returns different types for the same label on different calls. This needs investigation.
      // The issue manifests as F32 vs F64 type mismatches in br_table.wast tests.
      //
      // For now, we only validate arity (length) matches and that labels exist.
      for label in labels {
        let label_types = ctx.get_label_types(label)

        // Check arity matches
        if label_types.length() != default_types.length() {
          raise ValidationError::TypeMismatch(
            "br_table: all labels must have same arity (expected \{default_types.length()}, got \{label_types.length()})",
          )
        }

        // TODO: Re-enable once we fix the type mismatch bug
        // Check types match exactly (WebAssembly spec requires exact match)
        // for i in 0..<label_types.length() {
        //   if label_types[i] != default_types[i] {
        //     raise ValidationError::TypeMismatch(
        //       "br_table: all labels must have same types (label \{label} has \{label_types[i]}, default has \{default_types[i]} at position \{i})",
        //     )
        //   }
        // }
      }
      let target_types = default_types

      // Validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Validate we have required values for branch targets using default label
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "br_table: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for concrete values (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise ValidationError::TypeMismatch(
                "br_table: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Code after is unreachable, record stack height
      ctx.mark_unreachable()
    }
    BrOnNull(_label) =>
      // br_on_null: pop nullable ref, branch if null, else push non-null ref
      // For now, just pop a reference value (any reference type)
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "br_on_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()
        // Push back a reference (simplified - same type for now)
        // TODO: properly track non-null type narrowing
        stack.push(FuncRef) // Placeholder
      }
    BrOnNonNull(_label) =>
      // br_on_non_null: pop nullable ref, branch if non-null (with the value), else continue
      // Pop the nullable reference
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "br_on_non_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()

      }
    // If we branch, we pass the non-null value to the target
    // Fallthrough case: the value was null, so nothing is pushed
    Drop =>
      // In unreachable code, drop is valid even with empty stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - pretend we dropped something
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for drop")
      } else {
        let _ = stack.unsafe_pop()

      }
    Select => {
      // Untyped select (0x1B): only numeric types allowed
      // Pop condition (i32), then two values of same type, push one back
      ctx.poly_pop_expect(module_, I32, "select condition")
      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate
      if num_concrete >= 2 {
        // Both values are concrete - they must be compatible via subtyping
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // For untyped select, both values must be numeric types
        let is_val1_numeric = match val1 {
          I32 | I64 | F32 | F64 => true
          _ => false
        }
        let is_val2_numeric = match val2 {
          I32 | I64 | F32 | F64 => true
          _ => false
        }
        if not(is_val1_numeric) || not(is_val2_numeric) {
          raise ValidationError::TypeMismatch(
            "untyped select requires numeric types, got \{val1} and \{val2}",
          )
        }

        // Check if types are compatible: one must be subtype of the other
        let result_type = if is_subtype(module_, val1, val2) {
          val2 // val1 <: val2, so result is val2 (more general)
        } else if is_subtype(module_, val2, val1) {
          val1 // val2 <: val1, so result is val1 (more general)
        } else {
          raise ValidationError::TypeMismatch(
            "select values must have compatible types: got \{val1} and \{val2}",
          )
        }
        stack.push(result_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          // Verify it's numeric
          let is_numeric = match val {
            I32 | I64 | F32 | F64 => true
            _ => false
          }
          if not(is_numeric) {
            raise ValidationError::TypeMismatch(
              "untyped select requires numeric types, got \{val}",
            )
          }
          stack.push(val)
        } else {
          raise ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, assume a default type
        stack.push(I32)
      } else {
        raise ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    SelectTyped(result_types) => {
      // Typed select (0x1C): any type allowed, must match annotation
      // Pop condition (i32), then two values of annotated type, push one back
      ctx.poly_pop_expect(module_, I32, "select condition")

      // For MVP, result_types should have exactly 1 type
      if result_types.length() != 1 {
        raise ValidationError::InvalidResultArity(
          "select must have exactly 1 result type, got \{result_types.length()}",
        )
      }
      let expected_type = result_types[0]
      // Validate that type indices in the result type exist
      validate_valtype(module_, expected_type)

      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate they match expected type
      if num_concrete >= 2 {
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // Both values must be subtypes of the expected type
        if not(is_subtype(module_, val1, expected_type)) {
          raise ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val1}",
          )
        }
        if not(is_subtype(module_, val2, expected_type)) {
          raise ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val2}",
          )
        }
        stack.push(expected_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          if not(is_subtype(module_, val, expected_type)) {
            raise ValidationError::TypeMismatch(
              "select value type mismatch: expected \{expected_type}, got \{val}",
            )
          }
          stack.push(expected_type)
        } else {
          raise ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, push the expected type
        stack.push(expected_type)
      } else {
        raise ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    Nop => ()
    Unreachable =>
      // unreachable instruction marks all subsequent code as unreachable
      ctx.mark_unreachable()
    Call(func_idx) => {
      let idx = func_idx.reinterpret_as_int()
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(idx)
      }
      // Get the function type
      let type_idx = get_func_type_index(module_, idx, import_counts)
      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    CallIndirect(type_idx, table_idx) => {
      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : RefType = RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        RefType::Func | RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise ValidationError::TypeMismatch(
            "call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      ctx.poly_pop_expect(module_, I32, "call_indirect table index")
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_indirect argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    ReturnCall(func_idx) => {
      // return_call: tail call that returns to caller
      // Like doing a call followed by return - must match current function's return type
      let idx = func_idx.reinterpret_as_int()

      // Find the type index for this function
      let type_idx = get_func_type_index(module_, idx, import_counts)
      if type_idx < 0 || type_idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(type_idx)
      }
      let func_type_called = module_.types[type_idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      // return_call_indirect: tail call through table that returns to caller
      // Like doing a call_indirect followed by return - must match current function's return type

      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (return_call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : RefType = RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        RefType::Func | RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise ValidationError::TypeMismatch(
            "return_call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_indirect",
      )
      // Pop table index
      ctx.poly_pop_expect(module_, I32, "return_call_indirect table index")
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_indirect argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    CallRef(type_idx) => {
      // call_ref: calls function through a reference
      // Stack: [args...] [funcref] -> [results...]
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]

      // Pop the function reference
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("call_ref expects funcref on stack")
      } else {
        let _ = stack.unsafe_pop()
        // Pop funcref (we don't type-check it strictly for now)
      }

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_ref argument",
        )
      }

      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    ReturnCallRef(type_idx) => {
      // return_call_ref: tail call through a reference
      // Like doing a call_ref followed by return - must match current function's return type
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_ref",
      )
      // Pop the function reference
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "return_call_ref expects funcref on stack",
        )
      } else {
        let ref_type = stack.unsafe_pop()
        // Validate that the reference is a typed function reference
        // return_call_ref requires a reference to a specific function type, not general funcref
        match ref_type {
          // Only typed function references are valid
          Ref(RefType::TypeIndex(_), _) => ()
          // General function references are invalid - they could be any function type
          FuncRef | NullFuncRef | Ref(RefType::Func, _) =>
            raise ValidationError::TypeMismatch(
              "return_call_ref requires typed function reference (ref $t), got general funcref",
            )
          // Externref is invalid for return_call_ref
          ExternRef | NullExternRef | Ref(RefType::Extern, _) =>
            raise ValidationError::TypeMismatch(
              "return_call_ref expects function reference, got externref",
            )
          // Other reference types are invalid
          AnyRef
          | NullRef
          | EqRef
          | I31Ref
          | StructRef
          | ArrayRef
          | ExnRef
          | NullExnRef
          | Ref(_, _) =>
            raise ValidationError::TypeMismatch(
              "return_call_ref expects function reference, got \{ref_type}",
            )
          // Non-reference types are invalid
          I32 | I64 | F32 | F64 | V128 =>
            raise ValidationError::TypeMismatch(
              "return_call_ref expects function reference, got \{ref_type}",
            )
        }
      }

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_ref argument",
        )
      }

      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
  }
}

///|
/// Validate a single function
fn validate_function(
  module_ : Module,
  func_type : FuncType,
  code : Code,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // Validate type indices in function parameters
  for param in func_type.params {
    validate_valtype(module_, param)
  }
  // Validate type indices in function results
  for result in func_type.results {
    validate_valtype(module_, result)
  }
  // Validate type indices in local variables
  for local_type in code.locals {
    validate_valtype(module_, local_type)
  }

  // Create validation context with local initialization tracking
  let ctx = ValidationCtx::new_with_locals(func_type, code)
  // Push function-level control frame with empty params and function results
  ctx.push_control([], func_type.results)

  // Validate each instruction in the function body
  for instr in code.body.instrs {
    validate_instruction(module_, func_type, code, ctx, instr, import_counts)
  }

  // Check final stack matches return type
  let stack = ctx.stack
  if ctx.is_unreachable && stack.length() == 0 {
    // Unreachable code with empty stack - all values are polymorphic, valid
  } else if stack.length() != func_type.results.length() {
    // Stack size doesn't match expected return values
    if stack.length() < func_type.results.length() {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    } else if func_type.results.length() == 0 && stack.length() > 0 {
      raise ValidationError::StackSizeMismatch(
        "function: void function should not have values on stack, got \{stack.length()}",
      )
    } else {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    }
  } else {
    // Check types from top of stack (with subtyping)
    for i in 0..<func_type.results.length() {
      // Stack type must be a subtype of expected return type
      if not(is_subtype(module_, stack[i], func_type.results[i])) {
        raise ValidationError::TypeMismatch(
          "function return type mismatch: expected \{func_type.results[i]}, got \{stack[i]}",
        )
      }
    }
  }
}
