// Type size limit constant (1 million)

///|
const TypeSizeLimitValue : UInt64 = 1000000UL

///|
/// Validate a Component
/// Returns None if valid, Some(error) if invalid
pub fn validate_component(
  component : @core.Component,
) -> ComponentValidationError? {
  // First check: effective type size limit
  let total_size = calculate_effective_type_size(component)
  if total_size > TypeSizeLimitValue {
    return Some(TypeSizeExceedsLimit)
  }
  let ctx = ComponentValidationContext::new()
  let _ = validate_sections_with_size(ctx, component.sections)
  if ctx.is_valid() {
    None
  } else {
    Some(ctx.errors[0])
  }
}

///|
/// Calculate effective type size of a component
/// Includes both component/instance sizes and type definition sizes
fn calculate_effective_type_size(component : @core.Component) -> UInt64 {
  let type_sizes : Array[UInt64] = []
  calculate_effective_type_size_with_context(component, [], type_sizes)
}

///|
/// Calculate effective type size with context for type and component sizes
fn calculate_effective_type_size_with_context(
  component : @core.Component,
  parent_component_sizes : Array[UInt64],
  type_sizes : Array[UInt64],
) -> UInt64 {
  // Track component sizes at this level
  let sibling_sizes : Array[UInt64] = []

  // First pass: calculate sizes of all nested components in order
  for section in component.sections {
    match section {
      @core.ComponentSection::Component(nested) => {
        let nested_size = calculate_effective_type_size_with_context(
          nested, sibling_sizes, type_sizes,
        )
        sibling_sizes.push(nested_size)
      }
      _ => ()
    }
  }

  // Build local component index mapping
  let local_component_sizes : Array[UInt64] = []
  for section in component.sections {
    match section {
      @core.ComponentSection::Alias(alias_section) =>
        match alias_section.target {
          @core.AliasTarget::Outer(count, idx) =>
            match alias_section.kind {
              @core.AliasKind::Component =>
                if count == 1U &&
                  idx < parent_component_sizes.length().reinterpret_as_uint() {
                  local_component_sizes.push(
                    parent_component_sizes[idx.reinterpret_as_int()],
                  )
                } else {
                  local_component_sizes.push(1UL)
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  for size in sibling_sizes {
    local_component_sizes.push(size)
  }

  // Calculate total size: types + instances + nested components
  let mut total_size : UInt64 = 0UL
  let mut has_content = false

  // Add type definition sizes
  for section in component.sections {
    match section {
      @core.ComponentSection::Type(type_def) => {
        has_content = true
        let type_size = calculate_type_def_size(type_def, type_sizes)
        type_sizes.push(type_size)
        total_size = total_size + type_size
        if total_size > TypeSizeLimitValue {
          return total_size
        }
      }
      _ => ()
    }
  }

  // Add instance sizes
  for section in component.sections {
    match section {
      @core.ComponentSection::Instance(instance) => {
        has_content = true
        let inst_size = match instance {
          @core.ComponentInstance::Instantiate(comp_idx, _) =>
            if comp_idx < local_component_sizes.length().reinterpret_as_uint() {
              local_component_sizes[comp_idx.reinterpret_as_int()]
            } else {
              1UL
            }
          @core.ComponentInstance::FromExports(exports) => {
            let len = exports.length().to_uint64()
            if len > 0UL {
              len
            } else {
              1UL
            }
          }
        }
        total_size = total_size + inst_size
        if total_size > TypeSizeLimitValue {
          return total_size
        }
      }
      _ => ()
    }
  }

  // Add nested component sizes
  for size in sibling_sizes {
    has_content = true
    total_size = total_size + size
    if total_size > TypeSizeLimitValue {
      return total_size
    }
  }
  if has_content {
    total_size
  } else {
    1UL
  }
}

///|
/// Calculate size of a type definition
fn calculate_type_def_size(
  type_def : @core.ComponentTypeDef,
  type_sizes : Array[UInt64],
) -> UInt64 {
  match type_def {
    @core.ComponentTypeDef::Defined(val_type) =>
      calculate_val_type_size(val_type, type_sizes)
    @core.ComponentTypeDef::Func(func_type) => {
      let mut size : UInt64 = 1UL
      for param in func_type.params {
        size = size + calculate_val_type_size(param.type_, type_sizes)
      }
      for result in func_type.results {
        size = size + calculate_val_type_size(result.type_, type_sizes)
      }
      size
    }
    @core.ComponentTypeDef::Component(_) => 1UL
    @core.ComponentTypeDef::Instance(_) => 1UL
    @core.ComponentTypeDef::Resource(_) => 1UL
  }
}

///|
/// Calculate size of a component value type
fn calculate_val_type_size(
  val_type : @core.ComponentValType,
  type_sizes : Array[UInt64],
) -> UInt64 {
  match val_type {
    // Primitive types: size = 1
    @core.ComponentValType::Primitive(_) => 1UL
    @core.ComponentValType::Own(_) => 1UL
    @core.ComponentValType::Borrow(_) => 1UL

    // Type index reference: look up computed size
    @core.ComponentValType::TypeIndex(idx) =>
      if idx < type_sizes.length().reinterpret_as_uint() {
        type_sizes[idx.reinterpret_as_int()]
      } else {
        1UL
      }

    // Composite types
    @core.ComponentValType::List(elem_type) =>
      1UL + calculate_val_type_size(elem_type, type_sizes)
    @core.ComponentValType::Option(inner_type) =>
      1UL + calculate_val_type_size(inner_type, type_sizes)
    @core.ComponentValType::Result(ok_type, err_type) => {
      let mut size : UInt64 = 1UL
      match ok_type {
        Some(t) => size = size + calculate_val_type_size(t, type_sizes)
        None => ()
      }
      match err_type {
        Some(t) => size = size + calculate_val_type_size(t, type_sizes)
        None => ()
      }
      size
    }
    @core.ComponentValType::Tuple(elems) => {
      let mut size : UInt64 = 0UL
      for elem in elems {
        size = size + calculate_val_type_size(elem, type_sizes)
      }
      if size == 0UL {
        1UL
      } else {
        size
      }
    }
    @core.ComponentValType::Record(fields) => {
      let mut size : UInt64 = 0UL
      for field in fields {
        size = size + calculate_val_type_size(field.type_, type_sizes)
      }
      if size == 0UL {
        1UL
      } else {
        size
      }
    }
    @core.ComponentValType::Variant(cases) => {
      let mut size : UInt64 = 0UL
      for case in cases {
        match case.type_ {
          Some(t) => size = size + calculate_val_type_size(t, type_sizes)
          None => size = size + 1UL
        }
      }
      if size == 0UL {
        1UL
      } else {
        size
      }
    }
    @core.ComponentValType::Flags(_) => 1UL
    @core.ComponentValType::Enum(_) => 1UL

    // Async types
    @core.ComponentValType::ErrorContext => 1UL
    @core.ComponentValType::Future(Some(inner_type)) =>
      1UL + calculate_val_type_size(inner_type, type_sizes)
    @core.ComponentValType::Future(None) => 1UL
    @core.ComponentValType::Stream(Some(inner_type)) =>
      1UL + calculate_val_type_size(inner_type, type_sizes)
    @core.ComponentValType::Stream(None) => 1UL
    @core.ComponentValType::FixedSizeList(elem_type, _) =>
      1UL + calculate_val_type_size(elem_type, type_sizes)
  }
}

///|
/// Validate a Component with parent's component sizes for outer alias resolution
fn validate_component_with_parent_sizes(
  component : @core.Component,
  parent_sizes : Array[UInt64],
) -> (ComponentValidationError?, UInt64) {
  let ctx = ComponentValidationContext::new()
  // Copy parent sizes for outer alias resolution
  for size in parent_sizes {
    ctx.component_sizes.push(size)
  }
  let size = validate_sections_with_size_and_parent(
    ctx,
    component.sections,
    parent_sizes,
  )
  if ctx.is_valid() {
    (None, size)
  } else {
    (Some(ctx.errors[0]), size)
  }
}

///|
/// Validate all sections in a component and return effective size
/// Size is based on the structural size of exported items
fn validate_sections_with_size(
  ctx : ComponentValidationContext,
  sections : Array[@core.ComponentSection],
) -> UInt64 {
  validate_sections_with_size_and_parent(ctx, sections, [])
}

///|
/// Validate all sections with parent component sizes for outer alias resolution
fn validate_sections_with_size_and_parent(
  ctx : ComponentValidationContext,
  sections : Array[@core.ComponentSection],
  parent_sizes : Array[UInt64],
) -> UInt64 {
  let mut export_size : UInt64 = 1UL // Base size of 1 for the component itself

  // Track locally defined component count (for proper indexing)
  let parent_component_count = parent_sizes.length()

  // First pass: process all Component sections to collect their export sizes
  for section in sections {
    match section {
      @core.ComponentSection::Component(nested) => {
        // Pass current accumulated component_sizes to nested validation
        let (err, component_export_size) = validate_component_with_parent_sizes(
          nested,
          ctx.component_sizes,
        )
        match err {
          Some(e) => ctx.add_error(e)
          None => ()
        }
        ctx.components.push(ctx.components.length().reinterpret_as_uint())
        ctx.nested_components.push(nested)
        // Store the EXPORT size of this component
        ctx.component_sizes.push(component_export_size)
        // Add to running total
        export_size = export_size + component_export_size
        if export_size > TypeSizeLimitValue {
          ctx.add_error(TypeSizeExceedsLimit)
          return export_size
        }
      }
      _ => ()
    }
  }

  // Second pass: process Alias sections to bring outer components into scope
  for section in sections {
    match section {
      @core.ComponentSection::Alias(alias_def) => {
        validate_alias(ctx, alias_def)
        // If this is an outer alias for a component, add its size
        match (alias_def.kind, alias_def.target) {
          (@core.AliasKind::Component, @core.AliasTarget::Outer(count, idx)) =>
            // Outer alias to a component
            // The referenced component is at parent_sizes[idx] if count == 1
            if count == 1U && idx < parent_sizes.length().reinterpret_as_uint() {
              let aliased_size = parent_sizes[idx.reinterpret_as_int()]
              ctx.component_sizes.push(aliased_size)
            } else {
              ctx.component_sizes.push(1UL) // Fallback
            }
          _ => ()
        }
      }
      _ => ()
    }
  }

  // Third pass: process instances and exports
  for section in sections {
    match section {
      @core.ComponentSection::Component(_) => () // Already processed in first pass
      @core.ComponentSection::Alias(_) => () // Already processed in second pass
      @core.ComponentSection::Instance(instance) => {
        validate_instance(ctx, instance)
        let instance_exports_info = collect_instance_exports(ctx, instance)
        ctx.instance_exports.push(instance_exports_info)
        ctx.instances.push(ctx.instances.length().reinterpret_as_uint())
        // Instance size = instantiated component's export size
        let instance_size = get_instance_size(ctx, instance)
        ctx.instance_sizes.push(instance_size)
        // Add instance size to export size (instances are part of the component's type)
        export_size = export_size + instance_size
        if export_size > TypeSizeLimitValue {
          ctx.add_error(TypeSizeExceedsLimit)
          return export_size
        }
      }
      @core.ComponentSection::Export(export_def) => {
        validate_export(ctx, export_def)
        // Exports contribute additional size
        let exp_size = get_export_size(ctx, export_def)
        export_size = export_size + exp_size
        if export_size > TypeSizeLimitValue {
          ctx.add_error(TypeSizeExceedsLimit)
          return export_size
        }
      }
      _ => {
        let _ = validate_section_with_size(ctx, section)

      }
    }
  }
  ignore(parent_component_count)
  export_size
}

///|
/// Get the effective size of an export
fn get_export_size(
  ctx : ComponentValidationContext,
  export_def : @core.ComponentExport,
) -> UInt64 {
  match export_def.kind {
    @core.ComponentExportKind::Instance(idx) =>
      // Instance export: size = the instance's size
      if idx < ctx.instance_sizes.length().reinterpret_as_uint() {
        ctx.instance_sizes[idx.reinterpret_as_int()]
      } else {
        1UL
      }
    @core.ComponentExportKind::Component(idx) =>
      // Component export: size = the component's size
      if idx < ctx.component_sizes.length().reinterpret_as_uint() {
        ctx.component_sizes[idx.reinterpret_as_int()]
      } else {
        1UL
      }
    _ => 1UL // Other exports have base size of 1
  }
}

///|
/// Validate a single section and return its effective size
fn validate_section_with_size(
  ctx : ComponentValidationContext,
  section : @core.ComponentSection,
) -> UInt64 {
  match section {
    @core.ComponentSection::CoreModule(core_module) => {
      ctx.core_modules.push(ctx.core_modules.length().reinterpret_as_uint())
      let module_exports = collect_core_module_exports(core_module)
      ctx.core_module_exports.push(module_exports)
      let module_imports = collect_core_module_imports(core_module)
      ctx.core_module_imports.push(module_imports)
      validate_core_module(ctx, core_module)
      1UL // Core modules have base size of 1
    }
    @core.ComponentSection::CoreInstance(instance) => {
      validate_core_instance(ctx, instance)
      let instance_exports = collect_core_instance_exports(ctx, instance)
      ctx.core_instance_exports.push(instance_exports)
      ctx.core_instances.push(ctx.core_instances.length().reinterpret_as_uint())
      1UL // Core instances have base size of 1
    }
    @core.ComponentSection::CoreType(core_type) => {
      validate_core_type(ctx, core_type)
      ctx.core_types.push(core_type)
      1UL // Core types have base size of 1
    }
    @core.ComponentSection::Component(_) =>
      // Component sections are processed in the first pass of validate_sections_with_size
      // Return 0 here as the size is already accounted for
      0UL
    @core.ComponentSection::Instance(instance) => {
      validate_instance(ctx, instance)
      let instance_exports_info = collect_instance_exports(ctx, instance)
      ctx.instance_exports.push(instance_exports_info)
      ctx.instances.push(ctx.instances.length().reinterpret_as_uint())
      // Calculate instance size based on instantiated component
      let instance_size = get_instance_size(ctx, instance)
      ctx.instance_sizes.push(instance_size)
      instance_size
    }
    @core.ComponentSection::Alias(alias_def) => {
      validate_alias(ctx, alias_def)
      1UL // Aliases have base size of 1
    }
    @core.ComponentSection::Type(type_def) => {
      validate_type_def(ctx, type_def)
      ctx.types.push(type_def)
      1UL // Types have base size of 1
    }
    @core.ComponentSection::Canon(canon) => {
      validate_canon(ctx, canon)
      1UL // Canon sections have base size of 1
    }
    @core.ComponentSection::Start(start) => {
      validate_start(ctx, start)
      1UL // Start sections have base size of 1
    }
    @core.ComponentSection::Import(import_def) => {
      validate_import(ctx, import_def)
      match import_def.desc {
        @core.ComponentExternDesc::Type(bounds) =>
          match bounds {
            @core.TypeBounds::SubResource => {
              let type_idx = ctx.types.length().reinterpret_as_uint()
              ctx.resources.push(ResourceInfo::{
                type_idx,
                is_local: false,
                name: None,
              })
              ctx.types.push(
                @core.ComponentTypeDef::Resource(@core.ResourceType::{
                  rep: @core.ValType::I32,
                  dtor: None,
                }),
              )
              ctx.named_types.push(type_idx)
            }
            @core.TypeBounds::Eq(ref_idx) =>
              if ref_idx < ctx.types.length().reinterpret_as_uint() {
                if not(check_type_exportable(ctx, ref_idx)) {
                  ctx.add_error(
                    TypeNotValidAsImport("type not valid to be used as import"),
                  )
                }
                ctx.named_types.push(ref_idx)
              }
          }
        _ => ()
      }
      1UL // Imports have base size of 1
    }
    @core.ComponentSection::Export(export_def) => {
      validate_export(ctx, export_def)
      1UL // Exports have base size of 1
    }
    @core.ComponentSection::Custom(_) => 0UL // Custom sections don't contribute to size
  }
}

///|
/// Get the effective size of an instance based on what it instantiates
fn get_instance_size(
  ctx : ComponentValidationContext,
  instance : @core.ComponentInstance,
) -> UInt64 {
  match instance {
    @core.ComponentInstance::Instantiate(component_idx, _args) =>
      // Get the size of the instantiated component
      if component_idx < ctx.component_sizes.length().reinterpret_as_uint() {
        ctx.component_sizes[component_idx.reinterpret_as_int()]
      } else {
        1UL // Fallback for out-of-bounds
      }
    @core.ComponentInstance::FromExports(exports) =>
      // Size is the number of exports
      exports.length().reinterpret_as_uint().to_uint64()
  }
}

///|
fn validate_core_instance(
  ctx : ComponentValidationContext,
  instance : @core.CoreInstance,
) -> Unit {
  match instance {
    @core.CoreInstance::Instantiate(module_idx, args) => {
      if module_idx >= ctx.core_modules.length().reinterpret_as_uint() {
        ctx.add_error(ModuleIndexOutOfBounds(module_idx))
      }
      // Validate instantiation arguments and check for duplicates
      let seen_names : Array[String] = []
      for arg in args {
        match arg {
          @core.CoreInstantiateArg::Instance(name, idx) => {
            if idx >= ctx.core_instances.length().reinterpret_as_uint() {
              ctx.add_error(CoreInstanceIndexOutOfBounds(idx))
            }
            let name_str = bytes_to_string(name)
            for prev in seen_names {
              if prev == name_str {
                ctx.add_error(
                  DuplicateName(
                    "duplicate module instantiation argument named `\{name_str}`",
                  ),
                )
              }
            }
            seen_names.push(name_str)

            // Check that instance exports match module's expected imports
            if module_idx <
              ctx.core_module_imports.length().reinterpret_as_uint() &&
              idx < ctx.core_instance_exports.length().reinterpret_as_uint() {
              let module_imports = ctx.core_module_imports[module_idx.reinterpret_as_int()]
              let instance_exports = ctx.core_instance_exports[idx.reinterpret_as_int()]
              // Check each import from this module name
              for imp in module_imports {
                if imp.module_ == name_str {
                  // Find matching export in instance
                  let mut found = false
                  let mut found_kind : CoreExportKind? = None
                  let mut found_memory64 : Bool? = None
                  for exp in instance_exports {
                    if exp.name == imp.name {
                      found = true
                      found_kind = Some(exp.kind)
                      found_memory64 = exp.memory64
                      break
                    }
                  }
                  if found {
                    match found_kind {
                      Some(exp_kind) =>
                        if exp_kind != imp.kind {
                          let expected = core_export_kind_to_string(imp.kind)
                          let actual = core_export_kind_to_string(exp_kind)
                          ctx.add_error(
                            ExportTypeMismatch(
                              "expected \{expected}, found \{actual}",
                            ),
                          )
                        } else {
                          // Kind matches, now check memory64/table64 if applicable
                          match (exp_kind, imp.memory64, found_memory64) {
                            (
                              CoreExportKind::Memory,
                              Some(imp_mem64),
                              Some(exp_mem64),
                            ) =>
                              if imp_mem64 != exp_mem64 {
                                ctx.add_error(
                                  ExportTypeMismatch(
                                    "mismatch in index type used for memories",
                                  ),
                                )
                              }
                            (
                              CoreExportKind::Table,
                              Some(imp_table64),
                              Some(exp_table64),
                            ) =>
                              if imp_table64 != exp_table64 {
                                ctx.add_error(
                                  ExportTypeMismatch(
                                    "mismatch in index type used for tables",
                                  ),
                                )
                              }
                            _ => ()
                          }
                        }
                      None => ()
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    @core.CoreInstance::FromExports(exports) =>
      // Validate each export in the inline core instance
      for export_def in exports {
        match export_def.kind {
          @core.CoreExportKind::Func(idx) =>
            if idx >= ctx.core_funcs.length().reinterpret_as_uint() {
              ctx.add_error(CoreFuncIndexOutOfBounds(idx))
            }
          @core.CoreExportKind::Table(idx) =>
            if idx >= ctx.core_tables.length().reinterpret_as_uint() {
              ctx.add_error(CoreTableIndexOutOfBounds(idx))
            }
          @core.CoreExportKind::Memory(idx) =>
            if idx >= ctx.core_memories.length().reinterpret_as_uint() {
              ctx.add_error(CoreMemoryIndexOutOfBounds(idx))
            }
          @core.CoreExportKind::Global(idx) =>
            if idx >= ctx.core_globals.length().reinterpret_as_uint() {
              ctx.add_error(CoreGlobalIndexOutOfBounds(idx))
            }
          @core.CoreExportKind::Tag(idx) =>
            if idx >= ctx.core_tags.length().reinterpret_as_uint() {
              ctx.add_error(CoreTagIndexOutOfBounds(idx))
            }
        }
      }
  }
}

///|
fn validate_core_module(
  ctx : ComponentValidationContext,
  core_module : @core.Module,
) -> Unit {
  // Check for duplicate import names (format: module:name)
  let import_names : Array[String] = []
  for import_item in core_module.imports {
    let mod_str = bytes_to_string(import_item.module_)
    let name_str = bytes_to_string(import_item.name)
    let full_name = "\{mod_str}:\{name_str}"
    for prev in import_names {
      if prev == full_name {
        ctx.add_error(DuplicateName("duplicate import name `\{full_name}`"))
      }
    }
    import_names.push(full_name)
  }
  // Check for duplicate export names
  let export_names : Array[String] = []
  for export_item in core_module.exports {
    let name_str = bytes_to_string(export_item.name)
    for prev in export_names {
      if prev == name_str {
        ctx.add_error(DuplicateExportName(name_str))
      }
    }
    export_names.push(name_str)
  }
}

///|
fn validate_core_type(
  ctx : ComponentValidationContext,
  core_type : @core.CoreType,
) -> Unit {
  match core_type {
    @core.CoreType::Module(module_type) =>
      validate_module_type(ctx, module_type)
    @core.CoreType::Func(_) => ()
  }
}

///|
fn validate_module_type(
  ctx : ComponentValidationContext,
  module_type : @core.ModuleType,
) -> Unit {
  // Track number of types defined within this module type
  let mut type_count : UInt = 0U
  // Track export names for duplicate detection
  let export_names : Array[String] = []
  // Track import names (module:name) for duplicate detection
  let import_names : Array[String] = []
  for decl in module_type.decls {
    match decl {
      @core.ModuleTypeDecl::Type(_) => type_count = type_count + 1U
      @core.ModuleTypeDecl::Import(import_item) => {
        // Check for duplicate import name (format: module:name)
        let mod_str = bytes_to_string(import_item.module_)
        let name_str = bytes_to_string(import_item.name)
        let full_name = "\{mod_str}:\{name_str}"
        for prev in import_names {
          if prev == full_name {
            ctx.add_error(DuplicateName("duplicate import name `\{full_name}`"))
          }
        }
        import_names.push(full_name)
        match import_item.desc {
          @core.ImportDesc::Func(type_idx) =>
            if type_idx >= type_count {
              ctx.add_error(TypeIndexOutOfBounds(type_idx))
            }
          @core.ImportDesc::Tag(type_idx) =>
            if type_idx >= type_count {
              ctx.add_error(TypeIndexOutOfBounds(type_idx))
            }
          @core.ImportDesc::Table(_) => ()
          @core.ImportDesc::Mem(mem_type) => {
            // Memory size limit: 65536 pages for 32-bit (4GB)
            let max_pages : UInt64 = 65536UL
            if mem_type.limits.min > max_pages {
              ctx.add_error(
                LimitsMismatch(
                  "memory size must be at most 65536 pages (4 GiB)",
                ),
              )
            }
            match mem_type.limits.max {
              Some(max) =>
                if max > max_pages {
                  ctx.add_error(
                    LimitsMismatch(
                      "memory size must be at most 65536 pages (4 GiB)",
                    ),
                  )
                }
              None => ()
            }
          }
          @core.ImportDesc::Global(_) => ()
        }
      }
      @core.ModuleTypeDecl::Alias(core_alias) =>
        // Validate core alias in module type context
        match core_alias.target {
          @core.AliasTarget::Outer(count, idx) =>
            // Outer alias count must not exceed nesting depth
            if count > ctx.nesting_depth {
              ctx.add_error(TypeIndexOutOfBounds(idx))
            }
          @core.AliasTarget::Export(_instance_idx, _name)
          | @core.AliasTarget::CoreExport(_instance_idx, _name) => ()
        }
      @core.ModuleTypeDecl::Export(name, desc) => {
        let name_str = bytes_to_string(name)
        // Check for duplicate export name
        for prev in export_names {
          if prev == name_str {
            ctx.add_error(DuplicateExportName(name_str))
          }
        }
        export_names.push(name_str)
        // Check type reference in export desc
        match desc {
          @core.ImportDesc::Func(type_idx) =>
            if type_idx >= type_count {
              ctx.add_error(TypeIndexOutOfBounds(type_idx))
            }
          @core.ImportDesc::Tag(type_idx) =>
            if type_idx >= type_count {
              ctx.add_error(TypeIndexOutOfBounds(type_idx))
            }
          @core.ImportDesc::Table(_)
          | @core.ImportDesc::Mem(_)
          | @core.ImportDesc::Global(_) => ()
        }
      }
    }
  }
}

///|
fn validate_instance(
  ctx : ComponentValidationContext,
  instance : @core.ComponentInstance,
) -> Unit {
  match instance {
    @core.ComponentInstance::Instantiate(component_idx, args) => {
      if component_idx >= ctx.components.length().reinterpret_as_uint() {
        ctx.add_error(ComponentIndexOutOfBounds(component_idx))
      }
      // Get the component being instantiated for type checking
      let target_component : @core.Component? = if component_idx <
        ctx.nested_components.length().reinterpret_as_uint() {
        Some(ctx.nested_components[component_idx.reinterpret_as_int()])
      } else {
        None
      }
      // Validate instantiation arguments and check for duplicates
      let seen_names : Array[String] = []
      for arg in args {
        // Extract name from argument
        let name = match arg {
          @core.InstantiateArg::CoreFunc(n, _)
          | @core.InstantiateArg::CoreTable(n, _)
          | @core.InstantiateArg::CoreMemory(n, _)
          | @core.InstantiateArg::CoreGlobal(n, _)
          | @core.InstantiateArg::CoreType(n, _)
          | @core.InstantiateArg::CoreModule(n, _)
          | @core.InstantiateArg::CoreInstance(n, _)
          | @core.InstantiateArg::Func(n, _)
          | @core.InstantiateArg::Value(n, _)
          | @core.InstantiateArg::Type(n, _)
          | @core.InstantiateArg::Component(n, _)
          | @core.InstantiateArg::Instance(n, _) => n
        }
        let name_str = bytes_to_string(name)
        for prev in seen_names {
          if prev == name_str {
            ctx.add_error(
              DuplicateName(
                "instantiation argument `\{name_str}` conflicts with previous argument `\{name_str}`",
              ),
            )
          }
        }
        seen_names.push(name_str)
        // Check if the argument kind matches what the component expects
        match target_component {
          Some(comp) =>
            match get_component_import_kind(comp, name) {
              Some(expected) =>
                if not(check_arg_matches_import(arg, expected)) {
                  let expected_kind = get_extern_desc_kind_name(expected)
                  let actual_kind = get_arg_kind_name(arg)
                  ctx.add_error(
                    TypeMismatch(
                      "expected \{expected_kind}, found \{actual_kind}",
                    ),
                  )
                } else {
                  // For Type arguments, also check type bounds (resource vs defined)
                  match (arg, expected) {
                    (
                      @core.InstantiateArg::Type(_, type_idx),
                      @core.ComponentExternDesc::Type(bounds),
                    ) =>
                      match
                        check_type_arg_matches(ctx, type_idx, bounds, comp) {
                        Some(err_msg) => ctx.add_error(TypeMismatch(err_msg))
                        None => ()
                      }
                    _ => ()
                  }
                }
              None => ()
            }
          None => ()
        }
        match arg {
          @core.InstantiateArg::CoreFunc(_name, idx) =>
            if idx >= ctx.core_funcs.length().reinterpret_as_uint() {
              ctx.add_error(CoreFuncIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreTable(_name, idx) =>
            if idx >= ctx.core_tables.length().reinterpret_as_uint() {
              ctx.add_error(CoreTableIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreMemory(_name, idx) =>
            if idx >= ctx.core_memories.length().reinterpret_as_uint() {
              ctx.add_error(CoreMemoryIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreGlobal(_name, idx) =>
            if idx >= ctx.core_globals.length().reinterpret_as_uint() {
              ctx.add_error(CoreGlobalIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreType(_name, idx) =>
            if idx >= ctx.core_types.length().reinterpret_as_uint() {
              ctx.add_error(CoreTypeIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreModule(_name, idx) =>
            if idx >= ctx.core_modules.length().reinterpret_as_uint() {
              ctx.add_error(ModuleIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::CoreInstance(_name, idx) =>
            if idx >= ctx.core_instances.length().reinterpret_as_uint() {
              ctx.add_error(CoreInstanceIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::Func(_name, idx) =>
            if idx >= ctx.funcs.length().reinterpret_as_uint() {
              ctx.add_error(FuncIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::Value(_name, idx) =>
            if idx >= ctx.values.length().reinterpret_as_uint() {
              ctx.add_error(ValueIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::Type(_name, idx) =>
            if idx >= ctx.types.length().reinterpret_as_uint() {
              ctx.add_error(TypeIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::Component(_name, idx) =>
            if idx >= ctx.components.length().reinterpret_as_uint() {
              ctx.add_error(ComponentIndexOutOfBounds(idx))
            }
          @core.InstantiateArg::Instance(_name, idx) =>
            if idx >= ctx.instances.length().reinterpret_as_uint() {
              ctx.add_error(InstanceIndexOutOfBounds(idx))
            }
        }
      }
      // Check that all component imports are satisfied
      match target_component {
        Some(comp) => {
          let required_imports = get_component_import_names(comp)
          for import_name in required_imports {
            let import_name_str = bytes_to_string(import_name)
            let mut found = false
            for provided in seen_names {
              if provided == import_name_str {
                found = true
                break
              }
            }
            if not(found) {
              ctx.add_error(
                MissingImport("missing import named `\{import_name_str}`"),
              )
            }
          }
        }
        None => ()
      }
    }
    @core.ComponentInstance::FromExports(exports) => {
      // Validate each export in the inline instance
      let export_names : Array[String] = []
      for export_def in exports {
        let name_str = bytes_to_string(export_def.name)
        if name_str.is_empty() {
          ctx.add_error(NameCannotBeEmpty)
        } else {
          // Check for duplicate export names
          for prev in export_names {
            if prev == name_str {
              ctx.add_error(
                DuplicateName(
                  "export name `\{name_str}` conflicts with previous name `\{name_str}`",
                ),
              )
            }
          }
          export_names.push(name_str)
          // Check for kebab-case (for plain names)
          if not(name_str.has_prefix("https://")) &&
            not(name_str.has_prefix("http://")) &&
            not(name_str.contains(":")) &&
            not(is_kebab_case(name_str)) {
            ctx.add_error(NotKebabCase("`\{name_str}` is not in kebab case"))
          }
        }
        // Validate export index
        match export_def.kind {
          @core.ComponentExportKind::Module(idx) =>
            if idx >= ctx.core_modules.length().reinterpret_as_uint() {
              ctx.add_error(ModuleIndexOutOfBounds(idx))
            }
          @core.ComponentExportKind::Func(idx) =>
            if idx >= ctx.funcs.length().reinterpret_as_uint() {
              ctx.add_error(FuncIndexOutOfBounds(idx))
            }
          @core.ComponentExportKind::Value(idx) =>
            if idx >= ctx.values.length().reinterpret_as_uint() {
              ctx.add_error(ValueIndexOutOfBounds(idx))
            }
          @core.ComponentExportKind::Type(idx) =>
            if idx >= ctx.types.length().reinterpret_as_uint() {
              ctx.add_error(TypeIndexOutOfBounds(idx))
            }
          @core.ComponentExportKind::Instance(idx) =>
            if idx >= ctx.instances.length().reinterpret_as_uint() {
              ctx.add_error(InstanceIndexOutOfBounds(idx))
            }
          @core.ComponentExportKind::Component(idx) =>
            if idx >= ctx.components.length().reinterpret_as_uint() {
              ctx.add_error(ComponentIndexOutOfBounds(idx))
            }
        }
      }
    }
  }
}

///|
fn validate_alias(
  ctx : ComponentValidationContext,
  alias_def : @core.Alias,
) -> Unit {
  match alias_def.target {
    @core.AliasTarget::Export(instance_idx, name) =>
      match alias_def.kind {
        @core.AliasKind::CoreModule
        | @core.AliasKind::CoreType
        | @core.AliasKind::CoreTable
        | @core.AliasKind::CoreFunc
        | @core.AliasKind::CoreMemory
        | @core.AliasKind::CoreGlobal
        | @core.AliasKind::CoreTag =>
          if instance_idx >= ctx.core_instances.length().reinterpret_as_uint() {
            ctx.add_error(CoreInstanceIndexOutOfBounds(instance_idx))
          }
        @core.AliasKind::Type
        | @core.AliasKind::Component
        | @core.AliasKind::Instance
        | @core.AliasKind::Func
        | @core.AliasKind::Value =>
          if instance_idx >= ctx.instances.length().reinterpret_as_uint() {
            ctx.add_error(InstanceIndexOutOfBounds(instance_idx))
          } else {
            // Check that the export exists
            let name_str = bytes_to_string(name)
            if not(has_instance_export(ctx, instance_idx, name_str)) {
              ctx.add_error(
                MissingExport(
                  "instance \{instance_idx} has no export named `\{name_str}`",
                ),
              )
            }
          }
      }
    @core.AliasTarget::CoreExport(instance_idx, name) =>
      if instance_idx >= ctx.core_instances.length().reinterpret_as_uint() {
        ctx.add_error(CoreInstanceIndexOutOfBounds(instance_idx))
      } else {
        // Check that the export exists and has the correct kind
        let name_str = bytes_to_string(name)
        let expected_kind = match alias_def.kind {
          @core.AliasKind::CoreFunc => Some(CoreExportKind::Func)
          @core.AliasKind::CoreTable => Some(CoreExportKind::Table)
          @core.AliasKind::CoreMemory => Some(CoreExportKind::Memory)
          @core.AliasKind::CoreGlobal => Some(CoreExportKind::Global)
          @core.AliasKind::CoreTag => Some(CoreExportKind::Tag)
          _ => None
        }
        match expected_kind {
          Some(expected) =>
            match get_core_instance_export_kind(ctx, instance_idx, name_str) {
              Some(actual) =>
                if actual != expected {
                  let actual_str = core_export_kind_to_string(actual)
                  let expected_str = core_export_kind_to_string(expected)
                  ctx.add_error(
                    ExportTypeMismatch(
                      "export `\{name_str}` for core instance \{instance_idx} is \{actual_str}, expected \{expected_str}",
                    ),
                  )
                }
              None =>
                ctx.add_error(
                  MissingExport(
                    "core instance \{instance_idx} has no export named `\{name_str}`",
                  ),
                )
            }
          None => ()
        }
      }
    @core.AliasTarget::Outer(count, idx) =>
      // Outer alias count must not exceed nesting depth
      if count > ctx.nesting_depth {
        // Trying to access an outer component that doesn't exist
        // Report as type index out of bounds (matching wasmparser behavior)
        ctx.add_error(TypeIndexOutOfBounds(idx))
      } else if count == 0U {
        // Count 0 means current component - check index bounds
        match alias_def.kind {
          @core.AliasKind::CoreType =>
            if idx >= ctx.core_types.length().reinterpret_as_uint() {
              ctx.add_error(CoreTypeIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreModule =>
            if idx >= ctx.core_modules.length().reinterpret_as_uint() {
              ctx.add_error(ModuleIndexOutOfBounds(idx))
            }
          @core.AliasKind::Type =>
            if idx >= ctx.types.length().reinterpret_as_uint() {
              ctx.add_error(TypeIndexOutOfBounds(idx))
            }
          @core.AliasKind::Component =>
            if idx >= ctx.components.length().reinterpret_as_uint() {
              ctx.add_error(ComponentIndexOutOfBounds(idx))
            }
          @core.AliasKind::Instance =>
            if idx >= ctx.instances.length().reinterpret_as_uint() {
              ctx.add_error(InstanceIndexOutOfBounds(idx))
            }
          @core.AliasKind::Func =>
            if idx >= ctx.funcs.length().reinterpret_as_uint() {
              ctx.add_error(FuncIndexOutOfBounds(idx))
            }
          @core.AliasKind::Value =>
            if idx >= ctx.values.length().reinterpret_as_uint() {
              ctx.add_error(ValueIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreFunc =>
            if idx >= ctx.core_funcs.length().reinterpret_as_uint() {
              ctx.add_error(CoreFuncIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreTable =>
            if idx >= ctx.core_tables.length().reinterpret_as_uint() {
              ctx.add_error(CoreTableIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreMemory =>
            if idx >= ctx.core_memories.length().reinterpret_as_uint() {
              ctx.add_error(CoreMemoryIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreGlobal =>
            if idx >= ctx.core_globals.length().reinterpret_as_uint() {
              ctx.add_error(CoreGlobalIndexOutOfBounds(idx))
            }
          @core.AliasKind::CoreTag => ()
        }
      }
  }
}

///|
fn validate_type_def(
  ctx : ComponentValidationContext,
  type_def : @core.ComponentTypeDef,
) -> Unit {
  match type_def {
    @core.ComponentTypeDef::Defined(valtype) => validate_valtype(ctx, valtype)
    @core.ComponentTypeDef::Func(func_type) =>
      validate_func_type(ctx, func_type)
    @core.ComponentTypeDef::Component(component_type) =>
      validate_component_type(ctx, component_type)
    @core.ComponentTypeDef::Instance(instance_type) =>
      validate_instance_type(ctx, instance_type)
    @core.ComponentTypeDef::Resource(resource) => {
      // Validate representation type (must be i32)
      match resource.rep {
        @core.ValType::I32 => ()
        _ =>
          ctx.add_error(
            InvalidRepresentation("resources can only be represented by `i32`"),
          )
      }
      // Validate destructor if present
      match resource.dtor {
        Some(dtor_idx) =>
          if dtor_idx >= ctx.core_funcs.length().reinterpret_as_uint() {
            ctx.add_error(CoreFuncIndexOutOfBounds(dtor_idx))
          }
        // TODO: Validate destructor signature (param i32, no results)
        None => ()
      }
      ctx.resources.push(ResourceInfo::{
        type_idx: ctx.types.length().reinterpret_as_uint(),
        is_local: true,
        name: None,
      })
    }
  }
}

///|
fn validate_valtype(
  ctx : ComponentValidationContext,
  vt : @core.ComponentValType,
) -> Unit {
  match vt {
    @core.ComponentValType::Primitive(_) => ()
    @core.ComponentValType::TypeIndex(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // TypeIndex used as a value type must reference a Defined type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Defined(_) => ()
          @core.ComponentTypeDef::Resource(_) => ()
          _ => ctx.add_error(NotADefinedType(type_idx))
        }
      }
    @core.ComponentValType::List(inner) => validate_valtype(ctx, inner)
    @core.ComponentValType::Record(fields) => {
      // Record must have at least one field
      if fields.is_empty() {
        ctx.add_error(TypeMismatch("record type must have at least one field"))
      }
      let seen_names : Array[String] = []
      for field in fields {
        validate_valtype(ctx, field.type_)
        let name_str = bytes_to_string(field.name)
        // Check for duplicate names (case-insensitive)
        let name_lower = to_lowercase(name_str)
        for prev in seen_names {
          if to_lowercase(prev) == name_lower {
            ctx.add_error(
              TypeMismatch(
                "record field name `\{name_str}` conflicts with previous field name `\{prev}`",
              ),
            )
          }
        }
        seen_names.push(name_str)
        // Check field name is not empty and is in kebab-case
        if name_str.is_empty() {
          ctx.add_error(NameCannotBeEmpty)
        } else if not(is_kebab_case(name_str)) {
          ctx.add_error(
            NotKebabCase("record field name `\{name_str}` is not in kebab case"),
          )
        }
      }
    }
    @core.ComponentValType::Variant(cases) => {
      // Variant must have at least one case
      if cases.is_empty() {
        ctx.add_error(TypeMismatch("variant type must have at least one case"))
      }
      let seen_names : Array[String] = []
      let mut case_idx : UInt = 0U
      for case_ in cases {
        match case_.type_ {
          Some(vt) => validate_valtype(ctx, vt)
          None => ()
        }
        // Check refines refers to a previously defined case
        match case_.refines {
          Some(refines_idx) =>
            if refines_idx >= case_idx {
              ctx.add_error(
                TypeMismatch(
                  "variant case can only refine a previously defined case",
                ),
              )
            }
          None => ()
        }
        let name_str = bytes_to_string(case_.name)
        // Check for duplicate names (case-insensitive)
        let name_lower = to_lowercase(name_str)
        for prev in seen_names {
          if to_lowercase(prev) == name_lower {
            ctx.add_error(
              TypeMismatch(
                "variant case name `\{name_str}` conflicts with previous case name `\{prev}`",
              ),
            )
          }
        }
        seen_names.push(name_str)
        // Check case name is not empty and is in kebab-case
        if name_str.is_empty() {
          ctx.add_error(NameCannotBeEmpty)
        } else if not(is_kebab_case(name_str)) {
          ctx.add_error(
            NotKebabCase("variant case name `\{name_str}` is not in kebab case"),
          )
        }
        case_idx = case_idx + 1U
      }
    }
    @core.ComponentValType::Tuple(vts) => {
      // Tuple must have at least one type
      if vts.is_empty() {
        ctx.add_error(TypeMismatch("tuple type must have at least one type"))
      }
      for inner in vts {
        validate_valtype(ctx, inner)
      }
    }
    @core.ComponentValType::Flags(flags) => {
      // Flags must have at least one entry
      if flags.is_empty() {
        ctx.add_error(TypeMismatch("flags must have at least one entry"))
      }
      // Cannot have more than 32 flags
      if flags.length() > 32 {
        ctx.add_error(TypeMismatch("cannot have more than 32 flags"))
      }
      // Check for empty flag names and case-insensitive duplicates
      let seen_names : Array[String] = []
      for flag in flags {
        let name_str = bytes_to_string(flag)
        if name_str.is_empty() {
          ctx.add_error(NameCannotBeEmpty)
        } else {
          // Check for case-insensitive duplicates
          let name_lower = to_lowercase(name_str)
          for prev in seen_names {
            if to_lowercase(prev) == name_lower {
              ctx.add_error(
                TypeMismatch(
                  "flag name `\{name_str}` conflicts with previous flag name `\{prev}`",
                ),
              )
            }
          }
          seen_names.push(name_str)
        }
      }
    }
    @core.ComponentValType::Enum(cases) => {
      // Enum must have at least one variant
      if cases.is_empty() {
        ctx.add_error(TypeMismatch("enum type must have at least one variant"))
      }
      // Check for empty case names and case-insensitive duplicates
      let seen_names : Array[String] = []
      for case_name in cases {
        let name_str = bytes_to_string(case_name)
        if name_str.is_empty() {
          ctx.add_error(NameCannotBeEmpty)
        } else {
          // Check for case-insensitive duplicates
          let name_lower = to_lowercase(name_str)
          for prev in seen_names {
            if to_lowercase(prev) == name_lower {
              ctx.add_error(
                TypeMismatch(
                  "enum case name `\{name_str}` conflicts with previous case name `\{prev}`",
                ),
              )
            }
          }
          seen_names.push(name_str)
          // Check case name is in kebab-case
          if not(is_kebab_case(name_str)) {
            ctx.add_error(
              NotKebabCase("enum tag name `\{name_str}` is not in kebab case"),
            )
          }
        }
      }
    }
    @core.ComponentValType::Option(inner) => validate_valtype(ctx, inner)
    @core.ComponentValType::Result(ok, err) => {
      match ok {
        Some(vt) => validate_valtype(ctx, vt)
        None => ()
      }
      match err {
        Some(vt) => validate_valtype(ctx, vt)
        None => ()
      }
    }
    @core.ComponentValType::Own(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // Own must reference a resource type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Resource(_) => ()
          _ => ctx.add_error(NotAResourceType(type_idx))
        }
      }
    @core.ComponentValType::Borrow(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // Borrow must reference a resource type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Resource(_) => ()
          _ => ctx.add_error(NotAResourceType(type_idx))
        }
      }
    @core.ComponentValType::Future(vt_opt) =>
      match vt_opt {
        Some(inner) => validate_valtype(ctx, inner)
        None => ()
      }
    @core.ComponentValType::Stream(vt_opt) =>
      match vt_opt {
        Some(inner) => validate_valtype(ctx, inner)
        None => ()
      }
    @core.ComponentValType::ErrorContext => ()
    @core.ComponentValType::FixedSizeList(inner, _len) =>
      validate_valtype(ctx, inner)
  }
}

///|
fn validate_func_type(
  ctx : ComponentValidationContext,
  func_type : @core.ComponentFuncType,
) -> Unit {
  for param in func_type.params {
    validate_valtype(ctx, param.type_)
    // Check parameter name
    let name_str = bytes_to_string(param.name)
    if name_str.is_empty() {
      ctx.add_error(NameCannotBeEmpty)
    } else if not(is_kebab_case(name_str)) {
      ctx.add_error(
        NotKebabCase(
          "function parameter name `\{name_str}` is not in kebab case",
        ),
      )
    }
  }
  for result in func_type.results {
    validate_valtype(ctx, result.type_)
    check_no_borrow_in_result(ctx, result.type_)
  }
}

///|
fn check_no_borrow_in_result(
  ctx : ComponentValidationContext,
  vt : @core.ComponentValType,
) -> Unit {
  match vt {
    @core.ComponentValType::Borrow(_) =>
      ctx.add_error(
        BorrowInResult("function result cannot contain a `borrow` type"),
      )
    @core.ComponentValType::TypeIndex(type_idx) =>
      if type_idx < ctx.types.length().reinterpret_as_uint() {
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Defined(inner) =>
            check_no_borrow_in_result(ctx, inner)
          _ => ()
        }
      }
    @core.ComponentValType::List(inner) => check_no_borrow_in_result(ctx, inner)
    @core.ComponentValType::Option(inner) =>
      check_no_borrow_in_result(ctx, inner)
    @core.ComponentValType::Result(ok, err) => {
      match ok {
        Some(inner) => check_no_borrow_in_result(ctx, inner)
        None => ()
      }
      match err {
        Some(inner) => check_no_borrow_in_result(ctx, inner)
        None => ()
      }
    }
    @core.ComponentValType::Tuple(vts) =>
      for inner in vts {
        check_no_borrow_in_result(ctx, inner)
      }
    @core.ComponentValType::Record(fields) =>
      for field in fields {
        check_no_borrow_in_result(ctx, field.type_)
      }
    @core.ComponentValType::Variant(cases) =>
      for case_ in cases {
        match case_.type_ {
          Some(inner) => check_no_borrow_in_result(ctx, inner)
          None => ()
        }
      }
    _ => ()
  }
}

///|
fn validate_component_type(
  ctx : ComponentValidationContext,
  component_type : @core.ComponentType,
) -> Unit {
  for decl in component_type.decls {
    match decl {
      @core.ComponentTypeDecl::CoreType(core_type) =>
        validate_core_type(ctx, core_type)
      @core.ComponentTypeDecl::Type(type_def) => {
        // Resources cannot be defined inside component types
        match type_def {
          @core.ComponentTypeDef::Resource(_) =>
            ctx.add_error(
              ResourceNotDefinedInComponent(
                "resources can only be defined within a concrete component",
              ),
            )
          _ => ()
        }
        validate_type_def(ctx, type_def)
      }
      @core.ComponentTypeDecl::Alias(alias_def) =>
        validate_alias(ctx, alias_def)
      @core.ComponentTypeDecl::Import(import_decl) =>
        validate_import_decl(ctx, import_decl)
      @core.ComponentTypeDecl::Export(export_decl) =>
        validate_export_decl(ctx, export_decl)
    }
  }
}

///|
fn validate_instance_type(
  ctx : ComponentValidationContext,
  instance_type : @core.InstanceType,
) -> Unit {
  for decl in instance_type.decls {
    match decl {
      @core.InstanceTypeDecl::CoreType(core_type) =>
        validate_core_type(ctx, core_type)
      @core.InstanceTypeDecl::Type(type_def) => {
        // Resources cannot be defined inside instance types
        match type_def {
          @core.ComponentTypeDef::Resource(_) =>
            ctx.add_error(
              ResourceNotDefinedInComponent(
                "resources can only be defined within a concrete component",
              ),
            )
          _ => ()
        }
        validate_type_def(ctx, type_def)
      }
      @core.InstanceTypeDecl::Alias(alias_def) => validate_alias(ctx, alias_def)
      @core.InstanceTypeDecl::Import(import_decl) =>
        validate_import_decl(ctx, import_decl)
      @core.InstanceTypeDecl::Export(export_decl) =>
        validate_export_decl(ctx, export_decl)
    }
  }
}

///|
fn validate_import_decl(
  ctx : ComponentValidationContext,
  decl : @core.ComponentImportDecl,
) -> Unit {
  let name_str = bytes_to_string(decl.name)
  if name_str.is_empty() {
    ctx.add_error(NameCannotBeEmpty)
  }
  validate_extern_desc(ctx, decl.desc)
}

///|
fn validate_export_decl(
  ctx : ComponentValidationContext,
  decl : @core.ComponentExportDecl,
) -> Unit {
  let name_str = bytes_to_string(decl.name)
  if name_str.is_empty() {
    ctx.add_error(NameCannotBeEmpty)
  }
  validate_extern_desc(ctx, decl.desc)
}

///|
fn validate_canon(
  ctx : ComponentValidationContext,
  canon : @core.Canon,
) -> Unit {
  match canon {
    @core.Canon::Lift(core_func_idx, options, type_idx) => {
      if core_func_idx >= ctx.core_funcs.length().reinterpret_as_uint() {
        ctx.add_error(CoreFuncIndexOutOfBounds(core_func_idx))
      }
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Func(_) => ()
          _ => ctx.add_error(NotAFunctionType(type_idx))
        }
      }
      validate_canon_options(ctx, options)
    }
    @core.Canon::Lower(func_idx, options) => {
      if func_idx >= ctx.funcs.length().reinterpret_as_uint() {
        ctx.add_error(FuncIndexOutOfBounds(func_idx))
      }
      validate_canon_options(ctx, options)
    }
    @core.Canon::ResourceNew(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Resource(_) => {
            // Check if it's a local resource
            let is_local = ctx.resources
              .iter()
              .any(fn(r) { r.type_idx == type_idx && r.is_local })
            if not(is_local) {
              ctx.add_error(NotALocalResource(type_idx))
            }
          }
          _ => ctx.add_error(NotAResourceType(type_idx))
        }
      }
    @core.Canon::ResourceRep(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Resource(_) => {
            // Check if it's a local resource
            let is_local = ctx.resources
              .iter()
              .any(fn(r) { r.type_idx == type_idx && r.is_local })
            if not(is_local) {
              ctx.add_error(NotALocalResource(type_idx))
            }
          }
          _ => ctx.add_error(NotAResourceType(type_idx))
        }
      }
    @core.Canon::ResourceDrop(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Resource(_) => ()
          _ => ctx.add_error(NotAResourceType(type_idx))
        }
      }
  }
}

///|
fn validate_canon_options(
  ctx : ComponentValidationContext,
  options : Array[@core.CanonOpt],
) -> Unit {
  for opt in options {
    match opt {
      @core.CanonOpt::Utf8
      | @core.CanonOpt::Utf16
      | @core.CanonOpt::Latin1Utf16 => ()
      @core.CanonOpt::Memory(_) => ()
      @core.CanonOpt::Realloc(_) => ()
      @core.CanonOpt::PostReturn(_) => ()
    }
  }
  let _ = ctx

}

///|
fn validate_start(
  ctx : ComponentValidationContext,
  start : @core.ComponentStart,
) -> Unit {
  if start.func_idx >= ctx.funcs.length().reinterpret_as_uint() {
    ctx.add_error(FuncIndexOutOfBounds(start.func_idx))
  }
}

///|
fn validate_import(
  ctx : ComponentValidationContext,
  import_def : @core.ComponentImport,
) -> Unit {
  let name_str = bytes_to_string(import_def.name)
  if name_str.is_empty() {
    ctx.add_error(NameCannotBeEmpty)
    // Check for interface name format and validate with detailed errors
  } else if name_str.contains(":") && name_str.contains("/") {
    match validate_interface_name_detailed(name_str) {
      Some(err) => ctx.add_error(InvalidImportName(err))
      None => ()
    }
  } else if not(name_str.has_prefix("https://")) &&
    not(name_str.has_prefix("http://")) &&
    not(is_kebab_case(name_str)) {
    ctx.add_error(InvalidImportName(name_str))
  }
  // Check for duplicate import name
  for prev in ctx.import_names {
    if prev == name_str {
      ctx.add_error(DuplicateName("duplicate import name `\{name_str}`"))
    }
  }
  ctx.import_names.push(name_str)
  validate_extern_desc(ctx, import_def.desc)
}

///|
fn validate_export(
  ctx : ComponentValidationContext,
  export_def : @core.ComponentExport,
) -> Unit {
  let name_str = bytes_to_string(export_def.name)
  if name_str.is_empty() {
    ctx.add_error(NameCannotBeEmpty)
    // Check for kebab-case (for plain names, not URLs or interface names)
  } else if not(is_valid_extern_name(export_def.name)) {
    ctx.add_error(InvalidExportName(name_str))
  } else if not(name_str.has_prefix("https://")) &&
    not(name_str.has_prefix("http://")) &&
    not(name_str.contains(":")) &&
    not(is_kebab_case(name_str)) {
    ctx.add_error(NotKebabCase("`\{name_str}` is not in kebab case"))
  }
  // Check for duplicate export name
  for prev in ctx.export_names {
    if prev == name_str {
      ctx.add_error(DuplicateExportName(name_str))
    }
  }
  ctx.export_names.push(name_str)
  match export_def.kind {
    @core.ComponentExportKind::Module(idx) =>
      if idx >= ctx.core_modules.length().reinterpret_as_uint() {
        ctx.add_error(ModuleIndexOutOfBounds(idx))
      }
    @core.ComponentExportKind::Func(idx) =>
      if idx >= ctx.funcs.length().reinterpret_as_uint() {
        ctx.add_error(FuncIndexOutOfBounds(idx))
      }
    @core.ComponentExportKind::Value(idx) =>
      if idx >= ctx.values.length().reinterpret_as_uint() {
        ctx.add_error(ValueIndexOutOfBounds(idx))
      }
    @core.ComponentExportKind::Type(idx) =>
      if idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(idx))
      } else {
        // Check that all referenced types that require naming are named
        if not(check_type_exportable(ctx, idx)) {
          ctx.add_error(
            TypeNotValidAsExport("type not valid to be used as export"),
          )
        }
        // Mark this type as named
        ctx.named_types.push(idx)
      }
    @core.ComponentExportKind::Component(idx) =>
      if idx >= ctx.components.length().reinterpret_as_uint() {
        ctx.add_error(ComponentIndexOutOfBounds(idx))
      }
    @core.ComponentExportKind::Instance(idx) =>
      if idx >= ctx.instances.length().reinterpret_as_uint() {
        ctx.add_error(InstanceIndexOutOfBounds(idx))
        // Check that all types the instance exports are valid for export
      } else if not(check_instance_exportable(ctx, idx)) {
        ctx.add_error(
          TypeNotValidAsExport("instance not valid to be used as export"),
        )
      }
  }
}

///|
/// Check if a type is exportable (all dependencies that require naming are named)
fn check_type_exportable(
  ctx : ComponentValidationContext,
  type_idx : UInt,
) -> Bool {
  let type_def = ctx.types[type_idx.reinterpret_as_int()]
  match type_def {
    @core.ComponentTypeDef::Defined(valtype) =>
      check_valtype_exportable(ctx, valtype)
    @core.ComponentTypeDef::Func(func_type) => {
      for param in func_type.params {
        if not(check_valtype_exportable(ctx, param.type_)) {
          return false
        }
      }
      for result in func_type.results {
        if not(check_valtype_exportable(ctx, result.type_)) {
          return false
        }
      }
      true
    }
    @core.ComponentTypeDef::Component(_) => true
    @core.ComponentTypeDef::Instance(_) => true
    @core.ComponentTypeDef::Resource(_) => true
  }
}

///|
/// Check if a valtype is exportable
fn check_valtype_exportable(
  ctx : ComponentValidationContext,
  vt : @core.ComponentValType,
) -> Bool {
  match vt {
    @core.ComponentValType::Primitive(_) => true
    @core.ComponentValType::TypeIndex(ref_idx) => {
      // Check if the referenced type requires naming
      if ref_idx >= ctx.types.length().reinterpret_as_uint() {
        return true // Already validated bounds elsewhere
      }
      let ref_type = ctx.types[ref_idx.reinterpret_as_int()]
      if requires_naming(ref_type) {
        // Check if it's been named (exported)
        ctx.named_types.iter().any(fn(idx) { idx == ref_idx })
      } else {
        // The referenced type doesn't require naming, but check its contents
        check_type_exportable(ctx, ref_idx)
      }
    }
    @core.ComponentValType::List(inner) => check_valtype_exportable(ctx, inner)
    @core.ComponentValType::Record(fields) => {
      for field in fields {
        if not(check_valtype_exportable(ctx, field.type_)) {
          return false
        }
      }
      true
    }
    @core.ComponentValType::Variant(cases) => {
      for case_ in cases {
        match case_.type_ {
          Some(inner) =>
            if not(check_valtype_exportable(ctx, inner)) {
              return false
            }
          None => ()
        }
      }
      true
    }
    @core.ComponentValType::Tuple(vts) => {
      for inner in vts {
        if not(check_valtype_exportable(ctx, inner)) {
          return false
        }
      }
      true
    }
    @core.ComponentValType::Flags(_) => true
    @core.ComponentValType::Enum(_) => true
    @core.ComponentValType::Option(inner) =>
      check_valtype_exportable(ctx, inner)
    @core.ComponentValType::Result(ok, err) => {
      match ok {
        Some(inner) =>
          if not(check_valtype_exportable(ctx, inner)) {
            return false
          }
        None => ()
      }
      match err {
        Some(inner) =>
          if not(check_valtype_exportable(ctx, inner)) {
            return false
          }
        None => ()
      }
      true
    }
    @core.ComponentValType::Own(ref_idx) => {
      // Own references a resource type - check if it's named
      if ref_idx >= ctx.types.length().reinterpret_as_uint() {
        return true
      }
      ctx.named_types.iter().any(fn(idx) { idx == ref_idx })
    }
    @core.ComponentValType::Borrow(ref_idx) => {
      // Borrow references a resource type - check if it's named
      if ref_idx >= ctx.types.length().reinterpret_as_uint() {
        return true
      }
      ctx.named_types.iter().any(fn(idx) { idx == ref_idx })
    }
    _ => true
  }
}

///|
/// Check if a type requires naming before it can be used in exports
fn requires_naming(type_def : @core.ComponentTypeDef) -> Bool {
  match type_def {
    @core.ComponentTypeDef::Defined(valtype) => requires_naming_valtype(valtype)
    @core.ComponentTypeDef::Resource(_) => true
    _ => false
  }
}

///|
/// Check if a valtype requires naming
fn requires_naming_valtype(vt : @core.ComponentValType) -> Bool {
  match vt {
    @core.ComponentValType::Record(_) => true
    @core.ComponentValType::Variant(_) => true
    @core.ComponentValType::Enum(_) => true
    @core.ComponentValType::Flags(_) => true
    _ => false
  }
}

///|
fn validate_extern_desc(
  ctx : ComponentValidationContext,
  desc : @core.ComponentExternDesc,
) -> Unit {
  match desc {
    @core.ComponentExternDesc::Module(type_idx) =>
      if type_idx >= ctx.core_types.length().reinterpret_as_uint() {
        ctx.add_error(CoreTypeIndexOutOfBounds(type_idx))
      } else {
        // Check that it's a module type
        match ctx.core_types[type_idx.reinterpret_as_int()] {
          @core.CoreType::Module(_) => ()
          _ => ctx.add_error(NotAModuleType(type_idx))
        }
      }
    @core.ComponentExternDesc::Func(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // Check that it's a function type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Func(_) =>
            // Check that the function type is valid for import/export
            if not(check_type_exportable(ctx, type_idx)) {
              ctx.add_error(
                FuncNotValidAsImport("func not valid to be used as import"),
              )
            }
          _ => ctx.add_error(NotAFunctionType(type_idx))
        }
      }
    @core.ComponentExternDesc::Value(vt) => validate_valtype(ctx, vt)
    @core.ComponentExternDesc::Type(bounds) =>
      match bounds {
        @core.TypeBounds::Eq(type_idx) =>
          if type_idx >= ctx.types.length().reinterpret_as_uint() {
            ctx.add_error(TypeIndexOutOfBounds(type_idx))
          }
        @core.TypeBounds::SubResource => ()
      }
    @core.ComponentExternDesc::Component(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // Check that it's a component type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Component(_) => ()
          _ => ctx.add_error(NotAComponentType(type_idx))
        }
      }
    @core.ComponentExternDesc::Instance(type_idx) =>
      if type_idx >= ctx.types.length().reinterpret_as_uint() {
        ctx.add_error(TypeIndexOutOfBounds(type_idx))
      } else {
        // Check that it's an instance type
        match ctx.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Instance(_) => ()
          _ => ctx.add_error(NotAnInstanceType(type_idx))
        }
      }
  }
}

///|
/// Get the expected import kind for a given name from a component's import list
/// Returns None if the import is not found
fn get_component_import_kind(
  component : @core.Component,
  name : Bytes,
) -> @core.ComponentExternDesc? {
  for section in component.sections {
    match section {
      @core.ComponentSection::Import(import_def) =>
        if import_def.name == name {
          return Some(import_def.desc)
        }
      _ => ()
    }
  }
  None
}

///|
/// Get the kind name from an instantiate argument for error messages
fn get_arg_kind_name(arg : @core.InstantiateArg) -> String {
  match arg {
    @core.InstantiateArg::CoreFunc(_, _) => "func"
    @core.InstantiateArg::CoreTable(_, _) => "table"
    @core.InstantiateArg::CoreMemory(_, _) => "memory"
    @core.InstantiateArg::CoreGlobal(_, _) => "global"
    @core.InstantiateArg::CoreType(_, _) => "type"
    @core.InstantiateArg::CoreModule(_, _) => "module"
    @core.InstantiateArg::CoreInstance(_, _) => "instance"
    @core.InstantiateArg::Func(_, _) => "func"
    @core.InstantiateArg::Value(_, _) => "value"
    @core.InstantiateArg::Type(_, _) => "type"
    @core.InstantiateArg::Component(_, _) => "component"
    @core.InstantiateArg::Instance(_, _) => "instance"
  }
}

///|
/// Get the expected kind name from a ComponentExternDesc for error messages
fn get_extern_desc_kind_name(desc : @core.ComponentExternDesc) -> String {
  match desc {
    @core.ComponentExternDesc::Module(_) => "module"
    @core.ComponentExternDesc::Func(_) => "func"
    @core.ComponentExternDesc::Value(_) => "value"
    @core.ComponentExternDesc::Type(_) => "type"
    @core.ComponentExternDesc::Instance(_) => "instance"
    @core.ComponentExternDesc::Component(_) => "component"
  }
}

///|
/// Check if the argument kind matches the expected import kind
fn check_arg_matches_import(
  arg : @core.InstantiateArg,
  expected : @core.ComponentExternDesc,
) -> Bool {
  match (arg, expected) {
    (@core.InstantiateArg::Func(_, _), @core.ComponentExternDesc::Func(_)) =>
      true
    (
      @core.InstantiateArg::Component(_, _),
      @core.ComponentExternDesc::Component(_),
    ) => true
    (
      @core.InstantiateArg::Instance(_, _),
      @core.ComponentExternDesc::Instance(_),
    ) => true
    (@core.InstantiateArg::Type(_, _), @core.ComponentExternDesc::Type(_)) =>
      true
    (@core.InstantiateArg::Value(_, _), @core.ComponentExternDesc::Value(_)) =>
      true
    (
      @core.InstantiateArg::CoreModule(_, _),
      @core.ComponentExternDesc::Module(_),
    ) => true
    _ => false
  }
}

///|
/// Check if a type argument matches the expected type bounds
/// Returns error message if mismatch, None if OK
/// ctx is the parent component context, nested_component is the component being instantiated
fn check_type_arg_matches(
  ctx : ComponentValidationContext,
  arg_type_idx : UInt,
  expected_bounds : @core.TypeBounds,
  nested_component : @core.Component,
) -> String? {
  // Get the actual type being provided (from parent context)
  let arg_type = if arg_type_idx < ctx.types.length().reinterpret_as_uint() {
    Some(ctx.types[arg_type_idx.reinterpret_as_int()])
  } else {
    None
  }
  match expected_bounds {
    @core.TypeBounds::SubResource =>
      // Expects a resource type
      match arg_type {
        Some(@core.ComponentTypeDef::Resource(_)) => None
        Some(_) => Some("expected resource, found defined type")
        None => None // Index error handled elsewhere
      }
    @core.TypeBounds::Eq(expected_idx) => {
      // Get the expected type from nested component's type space
      let expected_type = get_nested_component_type(
        nested_component, expected_idx,
      )
      match (expected_type, arg_type) {
        (
          Some(@core.ComponentTypeDef::Resource(_)),
          Some(@core.ComponentTypeDef::Resource(_)),
        ) => None
        (Some(@core.ComponentTypeDef::Resource(_)), Some(_)) =>
          Some("expected resource, found defined type")
        (
          Some(@core.ComponentTypeDef::Defined(_)),
          Some(@core.ComponentTypeDef::Resource(_)),
        ) => Some("expected defined type, found resource")
        _ => None
      }
    }
  }
}

///|
/// Get all import names from a component
fn get_component_import_names(component : @core.Component) -> Array[Bytes] {
  let names : Array[Bytes] = []
  for section in component.sections {
    match section {
      @core.ComponentSection::Import(import_def) => names.push(import_def.name)
      _ => ()
    }
  }
  names
}

///|
/// Get a type definition from a nested component by index
fn get_nested_component_type(
  component : @core.Component,
  idx : UInt,
) -> @core.ComponentTypeDef? {
  let mut type_count : UInt = 0U
  for section in component.sections {
    match section {
      @core.ComponentSection::Type(type_def) => {
        if type_count == idx {
          return Some(type_def)
        }
        type_count = type_count + 1U
      }
      @core.ComponentSection::Import(import_def) =>
        // Imports can add to the type space
        match import_def.desc {
          @core.ComponentExternDesc::Type(_) => {
            if type_count == idx {
              // For imported types, we return a placeholder
              return Some(
                @core.ComponentTypeDef::Defined(
                  @core.ComponentValType::Primitive(@core.PrimitiveType::U32),
                ),
              )
            }
            type_count = type_count + 1U
          }
          _ => ()
        }
      _ => ()
    }
  }
  None
}

///|
/// Collect exports from a core module
fn collect_core_module_exports(mod_ : @core.Module) -> Array[CoreExportInfo] {
  let exports : Array[CoreExportInfo] = []
  for export_item in mod_.exports {
    let name_str = bytes_to_string(export_item.name)
    let (kind, memory64) : (CoreExportKind, Bool?) = match export_item.desc {
      @core.ExportDesc::Func(_) => (CoreExportKind::Func, None)
      @core.ExportDesc::Table(idx) => {
        let table64 = if idx < mod_.tables.length().reinterpret_as_uint() {
          Some(mod_.tables[idx.reinterpret_as_int()].table64)
        } else {
          None
        }
        (CoreExportKind::Table, table64)
      }
      @core.ExportDesc::Mem(idx) => {
        let mem64 = if idx < mod_.mems.length().reinterpret_as_uint() {
          Some(mod_.mems[idx.reinterpret_as_int()].memory64)
        } else {
          None
        }
        (CoreExportKind::Memory, mem64)
      }
      @core.ExportDesc::Global(_) => (CoreExportKind::Global, None)
      @core.ExportDesc::Tag(_) => (CoreExportKind::Tag, None)
    }
    exports.push(CoreExportInfo::{ name: name_str, kind, memory64 })
  }
  exports
}

///|
/// Collect imports from a core module
fn collect_core_module_imports(mod_ : @core.Module) -> Array[CoreImportInfo] {
  let imports : Array[CoreImportInfo] = []
  for import_item in mod_.imports {
    let mod_str = bytes_to_string(import_item.module_)
    let name_str = bytes_to_string(import_item.name)
    let (kind, memory64) : (CoreExportKind, Bool?) = match import_item.desc {
      @core.ImportDesc::Func(_) => (CoreExportKind::Func, None)
      @core.ImportDesc::Table(table_type) =>
        (CoreExportKind::Table, Some(table_type.table64))
      @core.ImportDesc::Mem(mem_type) =>
        (CoreExportKind::Memory, Some(mem_type.memory64))
      @core.ImportDesc::Global(_) => (CoreExportKind::Global, None)
      @core.ImportDesc::Tag(_) => (CoreExportKind::Tag, None)
    }
    imports.push(CoreImportInfo::{
      module_: mod_str,
      name: name_str,
      kind,
      memory64,
    })
  }
  imports
}

///|
/// Collect exports from a core instance
fn collect_core_instance_exports(
  ctx : ComponentValidationContext,
  instance : @core.CoreInstance,
) -> Array[CoreExportInfo] {
  match instance {
    @core.CoreInstance::Instantiate(module_idx, _args) =>
      // Exports come from the module
      if module_idx < ctx.core_module_exports.length().reinterpret_as_uint() {
        // Copy the module's exports
        let module_exports = ctx.core_module_exports[module_idx.reinterpret_as_int()]
        let result : Array[CoreExportInfo] = []
        for exp in module_exports {
          result.push(exp)
        }
        result
      } else {
        []
      }
    @core.CoreInstance::FromExports(exports) => {
      // Explicitly listed exports
      let result : Array[CoreExportInfo] = []
      for export_def in exports {
        let name_str = bytes_to_string(export_def.name)
        let (kind, memory64) : (CoreExportKind, Bool?) = match export_def.kind {
          @core.CoreExportKind::Func(_) => (CoreExportKind::Func, None)
          @core.CoreExportKind::Table(idx) =>
            // Try to look up table64 from context
            (CoreExportKind::Table, get_core_table_memory64(ctx, idx))
          @core.CoreExportKind::Memory(idx) =>
            // Try to look up memory64 from context
            (CoreExportKind::Memory, get_core_memory_memory64(ctx, idx))
          @core.CoreExportKind::Global(_) => (CoreExportKind::Global, None)
          @core.CoreExportKind::Tag(_) => (CoreExportKind::Tag, None)
        }
        result.push(CoreExportInfo::{ name: name_str, kind, memory64 })
      }
      result
    }
  }
}

///|
/// Get the export kind from a core instance export
fn get_core_instance_export_kind(
  ctx : ComponentValidationContext,
  instance_idx : UInt,
  name : String,
) -> CoreExportKind? {
  if instance_idx < ctx.core_instance_exports.length().reinterpret_as_uint() {
    let exports = ctx.core_instance_exports[instance_idx.reinterpret_as_int()]
    for exp in exports {
      if exp.name == name {
        return Some(exp.kind)
      }
    }
  }
  None
}

///|
/// Collect exports from a component instance
fn collect_instance_exports(
  ctx : ComponentValidationContext,
  instance : @core.ComponentInstance,
) -> Array[ExportInfo] {
  match instance {
    @core.ComponentInstance::Instantiate(component_idx, _args) =>
      // Get exports from the component being instantiated
      if component_idx < ctx.nested_components.length().reinterpret_as_uint() {
        let comp = ctx.nested_components[component_idx.reinterpret_as_int()]
        collect_component_exports(comp)
      } else {
        []
      }
    @core.ComponentInstance::FromExports(exports) => {
      // Explicitly listed exports
      let result : Array[ExportInfo] = []
      for export_def in exports {
        let name_str = bytes_to_string(export_def.name)
        let (kind, type_idx) = match export_def.kind {
          @core.ComponentExportKind::Module(_) => (ExportKind::Module, None)
          @core.ComponentExportKind::Func(idx) => (ExportKind::Func, Some(idx))
          @core.ComponentExportKind::Value(_) => (ExportKind::Value, None)
          @core.ComponentExportKind::Type(idx) => (ExportKind::Type, Some(idx))
          @core.ComponentExportKind::Instance(_) => (ExportKind::Instance, None)
          @core.ComponentExportKind::Component(_) =>
            (ExportKind::Component, None)
        }
        result.push(ExportInfo::{ name: name_str, kind, type_idx })
      }
      result
    }
  }
}

///|
/// Collect exports from a component
fn collect_component_exports(component : @core.Component) -> Array[ExportInfo] {
  let result : Array[ExportInfo] = []
  for section in component.sections {
    match section {
      @core.ComponentSection::Export(export_def) => {
        let name_str = bytes_to_string(export_def.name)
        let (kind, type_idx) = match export_def.kind {
          @core.ComponentExportKind::Module(_) => (ExportKind::Module, None)
          @core.ComponentExportKind::Func(idx) => (ExportKind::Func, Some(idx))
          @core.ComponentExportKind::Value(_) => (ExportKind::Value, None)
          @core.ComponentExportKind::Type(idx) => (ExportKind::Type, Some(idx))
          @core.ComponentExportKind::Instance(_) => (ExportKind::Instance, None)
          @core.ComponentExportKind::Component(_) =>
            (ExportKind::Component, None)
        }
        result.push(ExportInfo::{ name: name_str, kind, type_idx })
      }
      _ => ()
    }
  }
  result
}

///|
/// Check if a component instance has an export with the given name
fn has_instance_export(
  ctx : ComponentValidationContext,
  instance_idx : UInt,
  name : String,
) -> Bool {
  if instance_idx < ctx.instance_exports.length().reinterpret_as_uint() {
    let exports = ctx.instance_exports[instance_idx.reinterpret_as_int()]
    for exp in exports {
      if exp.name == name {
        return true
      }
    }
  }
  false
}

///|
/// Check if an instance is valid to be exported
/// All types the instance exports must have their dependencies named
fn check_instance_exportable(
  ctx : ComponentValidationContext,
  instance_idx : UInt,
) -> Bool {
  if instance_idx >= ctx.instance_exports.length().reinterpret_as_uint() {
    return true // Index error handled elsewhere
  }
  let exports = ctx.instance_exports[instance_idx.reinterpret_as_int()]
  for exp in exports {
    match exp.kind {
      ExportKind::Type =>
        match exp.type_idx {
          Some(type_idx) =>
            if not(check_type_exportable(ctx, type_idx)) {
              return false
            }
          None => ()
        }
      _ => ()
    }
  }
  true
}

///|
/// Convert CoreExportKind to string for error messages
fn core_export_kind_to_string(kind : CoreExportKind) -> String {
  match kind {
    CoreExportKind::Func => "func"
    CoreExportKind::Table => "table"
    CoreExportKind::Memory => "memory"
    CoreExportKind::Global => "global"
    CoreExportKind::Tag => "tag"
  }
}

///|
/// Get memory64 flag for a core memory (used in FromExports case)
/// Returns None if the memory index is not tracked
fn get_core_memory_memory64(
  _ctx : ComponentValidationContext,
  _idx : UInt,
) -> Bool? {
  // TODO: Track individual core memory types if needed
  None
}

///|
/// Get table64 flag for a core table (used in FromExports case)
/// Returns None if the table index is not tracked
fn get_core_table_memory64(
  _ctx : ComponentValidationContext,
  _idx : UInt,
) -> Bool? {
  // TODO: Track individual core table types if needed
  None
}
