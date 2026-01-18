// Component Runtime Main Structure

///|
/// Component Runtime state
pub struct ComponentRuntime {
  component : @core.Component
  import_resolver : ComponentImportResolver
  // Parent component (for outer aliases)
  parent : ComponentRuntime?
  // Index spaces
  core_modules : Array[@core.Module]
  core_instances : Array[CoreInstanceEntry]
  core_types : Array[@core.CoreType]
  core_funcs : Array[CoreFunc] // Core function index space
  core_memories : Array[(Array[Byte], UInt64?)] // Core memory index space (data, max_pages)
  core_tables : Array[@runtime.RuntimeTable] // Core table index space
  core_globals : Array[@runtime.Value] // Core global index space
  types : Array[@core.ComponentTypeDef]
  funcs : Array[ComponentFunc] // Component-level function index space
  values : Array[ComponentValue] // Value index space for start function args
  // Component-level index spaces
  components : Array[@core.Component] // Nested components
  component_instances : Array[ComponentInstanceEntry] // Component instances
  // Export map: name -> (kind, index)
  exports : Map[String, @core.ComponentExportKind]
  // Resource table: maps handle -> ResourceEntry
  resources : Array[ResourceEntry?]
  // Next resource handle
  mut next_resource_handle : UInt
}

///|
pub fn ComponentRuntime::new(component : @core.Component) -> ComponentRuntime {
  ComponentRuntime::{
    component,
    import_resolver: ComponentImportResolver::new(),
    parent: None,
    core_modules: [],
    core_instances: [],
    core_types: [],
    core_funcs: [],
    core_memories: [],
    core_tables: [],
    core_globals: [],
    types: [],
    funcs: [],
    values: [],
    components: [],
    component_instances: [],
    exports: {},
    resources: [],
    next_resource_handle: 0U,
  }
}

///|
pub fn ComponentRuntime::new_with_imports(
  component : @core.Component,
  import_resolver : ComponentImportResolver,
) -> ComponentRuntime {
  ComponentRuntime::{
    component,
    import_resolver,
    parent: None,
    core_modules: [],
    core_instances: [],
    core_types: [],
    core_funcs: [],
    core_memories: [],
    core_tables: [],
    core_globals: [],
    types: [],
    funcs: [],
    values: [],
    components: [],
    component_instances: [],
    exports: {},
    resources: [],
    next_resource_handle: 0U,
  }
}

///|
/// Create a nested component runtime with a parent reference
fn ComponentRuntime::new_with_parent(
  component : @core.Component,
  import_resolver : ComponentImportResolver,
  parent : ComponentRuntime,
) -> ComponentRuntime {
  ComponentRuntime::{
    component,
    import_resolver,
    parent: Some(parent),
    core_modules: [],
    core_instances: [],
    core_types: [],
    core_funcs: [],
    core_memories: [],
    core_tables: [],
    core_globals: [],
    types: [],
    funcs: [],
    values: [],
    components: [],
    component_instances: [],
    exports: {},
    resources: [],
    next_resource_handle: 0U,
  }
}

///|
/// Resolve a ComponentValType, following TypeIndex references
pub fn ComponentRuntime::resolve_type(
  self : ComponentRuntime,
  type_ : @core.ComponentValType,
) -> @core.ComponentValType raise ComponentRuntimeError {
  match type_ {
    @core.ComponentValType::TypeIndex(idx) => {
      let idx_int = idx.reinterpret_as_int()
      if idx_int >= self.types.length() {
        raise ComponentRuntimeError("invalid type index: \{idx_int}")
      }
      match self.types[idx_int] {
        @core.ComponentTypeDef::Defined(inner_type) =>
          self.resolve_type(inner_type)
        @core.ComponentTypeDef::Func(_) =>
          raise ComponentRuntimeError(
            "cannot resolve function type as value type",
          )
        @core.ComponentTypeDef::Component(_) =>
          raise ComponentRuntimeError(
            "cannot resolve component type as value type",
          )
        @core.ComponentTypeDef::Instance(_) =>
          raise ComponentRuntimeError(
            "cannot resolve instance type as value type",
          )
        @core.ComponentTypeDef::Resource(_) =>
          // Resource types remain as TypeIndex for now - they'll be handled by resource operations
          type_
      }
    }
    // For compound types, recursively resolve inner types
    @core.ComponentValType::List(elem_type) =>
      @core.ComponentValType::List(self.resolve_type(elem_type))
    @core.ComponentValType::Record(fields) => {
      let resolved_fields : Array[@core.RecordField] = []
      for field in fields {
        resolved_fields.push({
          name: field.name,
          type_: self.resolve_type(field.type_),
        })
      }
      @core.ComponentValType::Record(resolved_fields)
    }
    @core.ComponentValType::Tuple(elem_types) => {
      let resolved : Array[@core.ComponentValType] = []
      for t in elem_types {
        resolved.push(self.resolve_type(t))
      }
      @core.ComponentValType::Tuple(resolved)
    }
    @core.ComponentValType::Variant(cases) => {
      let resolved_cases : Array[@core.VariantCase] = []
      for case_ in cases {
        let resolved_type = match case_.type_ {
          Some(t) => Some(self.resolve_type(t))
          None => None
        }
        resolved_cases.push({
          name: case_.name,
          type_: resolved_type,
          refines: case_.refines,
        })
      }
      @core.ComponentValType::Variant(resolved_cases)
    }
    @core.ComponentValType::Option(inner) =>
      @core.ComponentValType::Option(self.resolve_type(inner))
    @core.ComponentValType::Result(ok_type, err_type) => {
      let resolved_ok = match ok_type {
        Some(t) => Some(self.resolve_type(t))
        None => None
      }
      let resolved_err = match err_type {
        Some(t) => Some(self.resolve_type(t))
        None => None
      }
      @core.ComponentValType::Result(resolved_ok, resolved_err)
    }
    // Primitive types and resource handles don't need resolution
    _ => type_
  }
}

///|
/// Resolve a ComponentResult type
fn ComponentRuntime::resolve_result_type(
  self : ComponentRuntime,
  result : @core.ComponentResult,
) -> @core.ComponentResult raise ComponentRuntimeError {
  { name: result.name, type_: self.resolve_type(result.type_) }
}

///|
/// Get all function names in the function index space
/// Returns array of (index, name, kind) where kind is "lifted" or "imported"
pub fn ComponentRuntime::get_func_names(
  self : ComponentRuntime,
) -> Array[(Int, String, String)] {
  let result : Array[(Int, String, String)] = []
  for i, func in self.funcs {
    match func {
      ComponentFunc::Lifted(_, name, _, _) =>
        result.push((i, bytes_to_string(name), "lifted"))
      ComponentFunc::Imported(name, _) =>
        result.push((i, bytes_to_string(name), "imported"))
    }
  }
  result
}

///|
/// Get all export names
pub fn ComponentRuntime::get_export_names(
  self : ComponentRuntime,
) -> Array[String] {
  let result : Array[String] = []
  for name, _ in self.exports {
    result.push(name)
  }
  result
}

///|
/// Get function name by index (for error messages and debugging)
pub fn ComponentRuntime::get_func_name(
  self : ComponentRuntime,
  func_idx : UInt,
) -> String? {
  let idx = func_idx.reinterpret_as_int()
  if idx >= self.funcs.length() {
    return None
  }
  match self.funcs[idx] {
    ComponentFunc::Lifted(_, name, _, _) => Some(bytes_to_string(name))
    ComponentFunc::Imported(name, _) => Some(bytes_to_string(name))
  }
}
