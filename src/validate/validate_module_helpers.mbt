///|
fn validate_module_type_indices(m : @core.Module) -> Unit raise ValidationError {
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
      TypeIndex(idx) =>
        if idx < 0 || idx >= m.types.length() {
          raise ValidationError::UnknownType(idx)
        }
      _ => ()
    }
  }

  // Validate type indices in element segments
  for elem in m.elems {
    match elem.elem_type {
      TypeIndex(idx) =>
        if idx < 0 || idx >= m.types.length() {
          raise ValidationError::UnknownType(idx)
        }
      _ => ()
    }
  }

  // Validate type indices in imported functions and tags
  for imp in m.imports {
    match imp.desc {
      Func(tidx) => {
        let type_idx = tidx.reinterpret_as_int()
        if type_idx < 0 || type_idx >= m.types.length() {
          raise ValidationError::InvalidTypeIndex(type_idx)
        }
      }
      Tag(tidx) => {
        let type_idx = tidx.reinterpret_as_int()
        if type_idx < 0 || type_idx >= m.types.length() {
          raise ValidationError::InvalidTypeIndex(type_idx)
        }
        if m.types[type_idx].results.length() > 0 {
          raise ValidationError::TypeMismatch("tag type must not have results")
        }
      }
      _ => ()
    }
  }

  // Validate type indices in tags
  for tag in m.tags {
    let type_idx = tag.type_idx.reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
    if m.types[type_idx].results.length() > 0 {
      raise ValidationError::TypeMismatch("tag type must not have results")
    }
  }

  // Validate function type indices
  for i in 0..<m.funcs.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
  }
}

///|
fn validate_module_start_function(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
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
}

///|
fn validate_module_global_initializers(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // Validate global initializers
  for global in m.globals {
    // Validate that only constant expression instructions are used
    validate_const_expr_instructions(global.init)
    // Validate that global.get only references immutable globals
    validate_const_expr_globals(m, global.init, import_counts)

    // Create a validation context for the init expression
    let init_ctx = ValidationCtx::new()
    // Validate each instruction in the init expression
    let dummy_func_type : @core.FuncType = @core.FuncType::{
      params: [],
      results: [],
    }
    let dummy_code : @core.Code = @core.Code::{
      locals: [],
      body: global.init,
      compiled: None,
    }
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
}

///|
fn validate_module_memory_limits(
  m : @core.Module,
) -> Unit raise ValidationError {
  // Validate memory limits
  for mem in m.mems {
    if mem.shared && mem.limits.max is None {
      raise ValidationError::InvalidMemorySize("shared memory requires maximum")
    }
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
}

///|
fn validate_module_imported_memory_limits(
  m : @core.Module,
) -> Unit raise ValidationError {
  // Validate memory limits for imported memories
  for imp in m.imports {
    match imp.desc {
      Mem(mem_type) => {
        if mem_type.shared && mem_type.limits.max is None {
          raise ValidationError::InvalidMemorySize(
            "shared memory requires maximum",
          )
        }
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
      }
      _ => ()
    }
  }
}

///|
fn validate_module_tables(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
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
          let dummy_func_type : @core.FuncType = @core.FuncType::{
            params: [],
            results: [],
          }
          let dummy_code : @core.Code = @core.Code::{
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
          let dummy_func_type : @core.FuncType = @core.FuncType::{
            params: [],
            results: [],
          }
          let dummy_code : @core.Code = @core.Code::{
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
            (Func, FuncRef)
            | (Func, NullFuncRef)
            | (Extern, ExternRef)
            | (Extern, NullExternRef) => ()
            (Func, ExternRef) | (Func, NullExternRef) | (Func, NullRef) =>
              raise ValidationError::TypeMismatch(
                "table initializer type mismatch: table expects funcref, got \{init_type}",
              )
            (Extern, FuncRef) | (Extern, NullFuncRef) | (Extern, NullRef) =>
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
      Table(table_type) =>
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
}

///|
fn validate_module_element_segments(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
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
}

///|
fn validate_module_data_segments(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
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
}

///|
fn validate_module_function_bodies(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // Validate function bodies against their types
  for i in 0..<m.codes.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    let func_type = m.types[type_idx]
    let code = m.codes[i]

    // Validate the function body
    validate_function(m, func_type, code, import_counts)
  }
}

///|
fn validate_module_exports(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
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
      @core.Global(idx) => {
        let global_idx = idx.reinterpret_as_int()
        let total_globals = import_counts.globals + m.globals.length()
        if global_idx < 0 || global_idx >= total_globals {
          raise ValidationError::UnknownExportedGlobal(global_idx)
        }
      }
      Tag(idx) => {
        let tag_idx = idx.reinterpret_as_int()
        let total_tags = import_counts.tags + m.tags.length()
        if tag_idx < 0 || tag_idx >= total_tags {
          raise ValidationError::UnknownExportedTag(tag_idx)
        }
      }
    }
  }
}
