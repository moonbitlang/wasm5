///|
/// Check if a field type is a valid subtype of another field type
fn is_field_type_subtype(
  m : @core.Module,
  sub_field : @core.FieldType,
  super_field : @core.FieldType,
) -> Bool {
  // If supertype is mutable, subtype must also be mutable
  // (can't have immutable subtype of mutable field)
  if super_field.mutable && not(sub_field.mutable) {
    return false
  }
  // If subtype is mutable, supertype must also be mutable
  // (can't have mutable subtype of immutable field)
  if sub_field.mutable && not(super_field.mutable) {
    return false
  }
  // Check storage types with appropriate variance
  is_storage_type_subtype(
    m,
    sub_field.storage,
    super_field.storage,
    super_field.mutable,
  )
}

///|
/// Check if a type definition is a valid subtype of another type definition
fn is_typedef_subtype(
  m : @core.Module,
  sub_type : @core.TypeDef,
  super_type : @core.TypeDef,
) -> Bool {
  match (sub_type, super_type) {
    (Func(sub_func), Func(super_func)) => {
      // Function subtyping: contravariant params, covariant results
      // Subtype can have fewer parameters (take more general args)
      // Subtype can have more results (return more specific values)
      // For WebAssembly GC: params must match exactly, results must match exactly
      // (Full contravariant/covariant is optional in spec)
      if sub_func.params.length() != super_func.params.length() {
        return false
      }
      if sub_func.results.length() != super_func.results.length() {
        return false
      }
      // Contravariant parameters: supertype param must be subtype of subtype param
      for i = 0; i < sub_func.params.length(); i = i + 1 {
        if not(is_subtype(m, super_func.params[i], sub_func.params[i])) {
          return false
        }
      }
      // Covariant results: subtype result must be subtype of supertype result
      for i = 0; i < sub_func.results.length(); i = i + 1 {
        if not(is_subtype(m, sub_func.results[i], super_func.results[i])) {
          return false
        }
      }
      true
    }
    (Struct(sub_struct), Struct(super_struct)) => {
      // Struct subtyping: subtype must have at least as many fields
      // Each supertype field must match corresponding subtype field
      if sub_struct.fields.length() < super_struct.fields.length() {
        return false
      }
      for i = 0; i < super_struct.fields.length(); i = i + 1 {
        if not(
            is_field_type_subtype(
              m,
              sub_struct.fields[i],
              super_struct.fields[i],
            ),
          ) {
          return false
        }
      }
      true
    }
    (Array(sub_arr), Array(super_arr)) =>
      // Array subtyping: element types must match
      is_field_type_subtype(m, sub_arr.element, super_arr.element)
    _ => false // Different kinds cannot be subtypes
  }
}

///|
/// Check if a type at the given index is final (cannot be subtyped)
/// A type is final if:
/// - It has no SubTypeDef in type_groups (implicitly final), OR
/// - Its SubTypeDef has is_final=true
fn is_type_final(m : @core.Module, type_idx : Int) -> Bool {
  let tidx = type_idx.reinterpret_as_uint()
  // Search through all type groups for this type's subtype definition
  for group in m.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx == tidx {
        return subtype_def.is_final
      }
    }
  }
  // Type not found in any SubTypeDef - implicitly final
  true
}

///|
/// Validate a type reference considering forward reference constraints.
/// A type reference to index `ref_idx` is valid if:
/// - `ref_idx` is less than the start of the current rec group (already defined), OR
/// - `ref_idx` is within the current rec group (forward reference within group allowed)
fn validate_type_ref_in_context(
  m : @core.Module,
  ref_idx : Int,
  group_start : Int,
  group_end : Int,
) -> Unit raise ValidationError {
  if ref_idx < 0 || ref_idx >= m.types.length() {
    raise ValidationError::UnknownType(ref_idx)
  }
  // Forward reference check: if ref_idx >= group_start, it must be within the group
  if ref_idx >= group_start && ref_idx > group_end {
    raise ValidationError::UnknownType(ref_idx)
  }
}

///|
/// Validate a value type considering forward reference constraints
fn validate_valtype_in_context(
  m : @core.Module,
  val_type : @core.ValType,
  group_start : Int,
  group_end : Int,
) -> Unit raise ValidationError {
  match val_type {
    Ref(TypeIndex(idx), _) =>
      validate_type_ref_in_context(m, idx, group_start, group_end)
    _ => ()
  }
}

///|
/// Validate a storage type considering forward reference constraints
fn validate_storage_type_in_context(
  m : @core.Module,
  storage_type : @core.StorageType,
  group_start : Int,
  group_end : Int,
) -> Unit raise ValidationError {
  match storage_type {
    Val(val_type) =>
      validate_valtype_in_context(m, val_type, group_start, group_end)
    I8 | I16 => ()
  }
}

///|
/// Validate a type definition considering forward reference constraints
fn validate_typedef_in_context(
  m : @core.Module,
  type_def : @core.TypeDef,
  group_start : Int,
  group_end : Int,
) -> Unit raise ValidationError {
  match type_def {
    Func(func_type) => {
      for param in func_type.params {
        validate_valtype_in_context(m, param, group_start, group_end)
      }
      for result in func_type.results {
        validate_valtype_in_context(m, result, group_start, group_end)
      }
    }
    Struct(struct_type) =>
      for field in struct_type.fields {
        validate_storage_type_in_context(
          m,
          field.storage,
          group_start,
          group_end,
        )
      }
    Array(array_type) =>
      validate_storage_type_in_context(
        m,
        array_type.element.storage,
        group_start,
        group_end,
      )
  }
}

///|
fn validate_module_type_indices(m : @core.Module) -> Unit raise ValidationError {
  // Validate type definitions with proper forward reference checking.
  // Forward references are only allowed within the same rec group.
  for group in m.type_groups {
    // Find the range of type indices in this group
    let mut group_start = m.types.length()
    let mut group_end = -1
    for subtype_def in group.subtypes {
      let idx = subtype_def.type_idx.reinterpret_as_int()
      if idx < group_start {
        group_start = idx
      }
      if idx > group_end {
        group_end = idx
      }
    }

    // Validate each type in the group with the group's bounds
    for subtype_def in group.subtypes {
      let type_idx = subtype_def.type_idx.reinterpret_as_int()
      let type_def = m.types[type_idx]
      validate_typedef_in_context(m, type_def, group_start, group_end)
    }
  }

  // Validate subtype declarations in type_groups
  // Check that supertypes exist, are not final, and type definitions are compatible
  for group in m.type_groups {
    for subtype_def in group.subtypes {
      let sub_idx = subtype_def.type_idx.reinterpret_as_int()
      let sub_type = m.types[sub_idx]
      for supertype_idx in subtype_def.supertypes {
        let super_idx = supertype_idx.reinterpret_as_int()
        // Check supertype index is valid
        if super_idx < 0 || super_idx >= m.types.length() {
          raise ValidationError::UnknownType(super_idx)
        }
        // Check supertype is not final
        if is_type_final(m, super_idx) {
          raise ValidationError::InvalidSubtype(
            "sub type: cannot extend final type",
          )
        }
        // Check that type definition is a valid subtype (kind match + content)
        let super_type = m.types[super_idx]
        if not(is_typedef_subtype(m, sub_type, super_type)) {
          raise ValidationError::InvalidSubtype("sub type")
        }
      }
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
        match m.types[type_idx] {
          Func(_) => ()
          _ =>
            raise ValidationError::TypeMismatch(
              "function type index must refer to func type",
            )
        }
      }
      Tag(tidx) => {
        let type_idx = tidx.reinterpret_as_int()
        if type_idx < 0 || type_idx >= m.types.length() {
          raise ValidationError::InvalidTypeIndex(type_idx)
        }
        match m.types[type_idx] {
          Func(func_type) =>
            if func_type.results.length() > 0 {
              raise ValidationError::TypeMismatch(
                "tag type must not have results",
              )
            }
          _ =>
            raise ValidationError::TypeMismatch(
              "tag type index must refer to func type",
            )
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
    match m.types[type_idx] {
      Func(func_type) =>
        if func_type.results.length() > 0 {
          raise ValidationError::TypeMismatch("tag type must not have results")
        }
      _ =>
        raise ValidationError::TypeMismatch(
          "tag type index must refer to func type",
        )
    }
  }

  // Validate function type indices
  for i in 0..<m.funcs.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
    match m.types[type_idx] {
      Func(_) => ()
      _ =>
        raise ValidationError::TypeMismatch(
          "function type index must refer to func type",
        )
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
      let func_type = match m.types[type_idx] {
        Func(ft) => ft
        _ =>
          raise ValidationError::TypeMismatch(
            "start function type must refer to func type",
          )
      }

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
/// Get a set of all function indices in the module (for constant expression validation)
/// In constant expressions, ref.func can reference any function since that's where
/// functions get "declared" for later use in function bodies.
fn all_function_indices(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Set[Int] {
  let all_funcs : Set[Int] = Set::new()
  let total_funcs = import_counts.funcs + m.funcs.length()
  for i in 0..<total_funcs {
    all_funcs.add(i)
  }
  all_funcs
}

///|
fn validate_module_global_initializers(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // For constant expressions, all functions are considered "declared"
  // since ref.func in constant expressions is what creates declarations
  let all_funcs = all_function_indices(m, import_counts)

  // Validate global initializers
  for i, global in m.globals {
    // Validate that only constant expression instructions are used
    validate_const_expr_instructions(global.init)
    // Validate that global.get only references immutable globals that are defined before this one
    // The max global index for the i-th local global is import_counts.globals + i
    validate_const_expr_globals(
      m,
      global.init,
      import_counts,
      max_global_idx=Some(import_counts.globals + i),
    )

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
      max_stack_height: 0,
    }
    for instr in global.init.instrs {
      validate_instruction(
        m, dummy_func_type, dummy_code, init_ctx, instr, import_counts, all_funcs,
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
/// Validate table limits for a single table type.
/// Checks min/max relationship and 32-bit size limits for non-table64 tables.
fn validate_table_type_limits(
  table_type : @core.TableType,
) -> Unit raise ValidationError {
  match table_type.limits.max {
    Some(max_val) => {
      if table_type.limits.min > max_val {
        raise ValidationError::InvalidTableSize(
          "size minimum must not be greater than maximum",
        )
      }
      if not(table_type.table64) && max_val > 0xFFFF_FFFFUL {
        raise ValidationError::InvalidTableSize(
          "table size must fit in 32-bit limits",
        )
      }
    }
    None => ()
  }
  if not(table_type.table64) && table_type.limits.min > 0xFFFF_FFFFUL {
    raise ValidationError::InvalidTableSize(
      "table size must fit in 32-bit limits",
    )
  }
}

///|
/// Validate memory limits for a single memory type.
/// Checks shared memory requirements, min/max relationship, and size limits.
fn validate_mem_type_limits(
  mem_type : @core.MemType,
) -> Unit raise ValidationError {
  if mem_type.shared && mem_type.limits.max is None {
    raise ValidationError::InvalidMemorySize("shared memory requires maximum")
  }
  match mem_type.limits.max {
    Some(max_val) => {
      if mem_type.limits.min > max_val {
        raise ValidationError::InvalidMemorySize(
          "size minimum must not be greater than maximum",
        )
      }
      if not(mem_type.memory64) && max_val > 65536UL {
        raise ValidationError::InvalidMemorySize(
          "memory size must be at most 65536 pages (4GiB)",
        )
      }
    }
    None =>
      if not(mem_type.memory64) && mem_type.limits.min > 65536UL {
        raise ValidationError::InvalidMemorySize(
          "memory size must be at most 65536 pages (4GiB)",
        )
      }
  }
}

///|
fn validate_module_memory_limits(
  m : @core.Module,
) -> Unit raise ValidationError {
  for mem in m.mems {
    validate_mem_type_limits(mem)
  }
}

///|
fn validate_module_imported_memory_limits(
  m : @core.Module,
) -> Unit raise ValidationError {
  for imp in m.imports {
    match imp.desc {
      Mem(mem_type) => validate_mem_type_limits(mem_type)
      _ => ()
    }
  }
}

///|
fn validate_module_tables(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // For constant expressions, all functions are considered "declared"
  let all_funcs = all_function_indices(m, import_counts)

  // Validate table limits and initializers
  for table in m.tables {
    validate_table_type_limits(table)
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
            max_stack_height: 0,
          }
          for instr in init_expr.instrs {
            validate_instruction(
              m, dummy_func_type, dummy_code, init_ctx, instr, import_counts, all_funcs,
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
            max_stack_height: 0,
          }
          for instr in init_expr.instrs {
            validate_instruction(
              m, dummy_func_type, dummy_code, init_ctx, instr, import_counts, all_funcs,
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
      Table(table_type) => validate_table_type_limits(table_type)
      _ => ()
    }
  }
}

///|
/// Get global type and mutability. Delegates to core implementation.
/// Raises ValidationError for invalid global indices.
fn get_global_type_and_mutable(
  m : @core.Module,
  global_idx : Int,
  import_counts : ImportCounts,
) -> (@core.ValType, Bool) raise ValidationError {
  match @core.get_global_type(m, global_idx, import_counts.globals) {
    Some(gt) => (gt.val_type, gt.mutable)
    None => raise ValidationError::UnknownGlobal(global_idx)
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
  for elem in m.elems {
    // Only validate table index for active segments
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx < 0 || table_idx >= total_tables {
        raise ValidationError::UnknownTable(table_idx)
      }

      // Check that element segment type is compatible with table element type
      let table_type = get_table_type(m, import_counts, elem.table_idx)
      let elem_type = @core.ValType::Ref(elem.elem_type, elem.elem_nullable)
      let table_elem_type = @core.ValType::Ref(
        table_type.elem_type,
        table_type.nullable,
      )
      guard is_subtype(m, elem_type, table_elem_type) else {
        raise ValidationError::TypeMismatch(
          "element segment type \{elem_type} is not compatible with table element type \{table_elem_type}",
        )
      }

      // Validate offset expression and check it produces i32
      let offset_type = validate_const_expr_type(m, elem.offset, import_counts)
      if offset_type != I32 {
        raise ValidationError::TypeMismatch(
          "element segment offset must be i32",
        )
      }
    }

    // Validate element init expressions are constant references
    let expected_type = @core.ValType::Ref(elem.elem_type, elem.elem_nullable)
    for expr in elem.init {
      // Use the new comprehensive constant expression validator
      let expr_type = validate_elem_init_const_expr(
        m,
        expr,
        import_counts,
        elem.elem_nullable,
      )
      guard is_subtype(m, expr_type, expected_type) else {
        raise ValidationError::TypeMismatch(
          "elem init type mismatch: \{expr_type} vs \{expected_type}",
        )
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
      // Validate offset expression and check it produces i32
      let offset_type = validate_const_expr_type(m, data.offset, import_counts)
      if offset_type != I32 {
        raise ValidationError::TypeMismatch("data segment offset must be i32")
      }
    }
  }
}

///|
fn validate_module_function_bodies(
  m : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  // Collect declared functions (from elem segments, exports, global inits)
  // These are the only functions that can be used with ref.func
  let declared_funcs = collect_declared_funcs(m)

  // Validate function bodies against their types
  for i in 0..<m.codes.length() {
    let type_idx = m.funcs[i].reinterpret_as_int()
    let func_type = match m.types[type_idx] {
      Func(ft) => ft
      _ =>
        raise ValidationError::TypeMismatch(
          "function type index must refer to func type",
        )
    }
    let code = m.codes[i]

    // Validate the function body
    validate_function(m, func_type, code, import_counts, declared_funcs)
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
