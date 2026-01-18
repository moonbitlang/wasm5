///|
/// Component validation context
/// Tracks type indices and other context needed for validation
pub(all) struct ComponentValidationContext {
  // Type indices
  mut types : Array[@core.ComponentTypeDef]
  mut core_types : Array[@core.CoreType]
  mut funcs : Array[UInt] // function type indices
  mut instances : Array[UInt] // instance type indices
  mut components : Array[UInt] // component type indices
  mut nested_components : Array[@core.Component] // actual nested component data
  mut modules : Array[UInt] // module type indices
  mut values : Array[@core.ComponentValType]

  // Core indices
  mut core_funcs : Array[UInt]
  mut core_instances : Array[UInt]
  mut core_modules : Array[UInt]
  mut core_module_exports : Array[Array[CoreExportInfo]] // exports for each core module
  mut core_module_imports : Array[Array[CoreImportInfo]] // imports for each core module
  mut core_tables : Array[UInt]
  mut core_memories : Array[UInt]
  mut core_globals : Array[UInt]
  mut core_tags : Array[UInt]

  // Instance export tracking
  mut core_instance_exports : Array[Array[CoreExportInfo]] // exports for each core instance
  mut instance_exports : Array[Array[ExportInfo]] // exports for each component instance

  // Resource tracking
  mut resources : Array[ResourceInfo]

  // Export name tracking for duplicate detection
  mut export_names : Array[String]

  // Import name tracking for duplicate detection
  mut import_names : Array[String]

  // Named type tracking for export restrictions
  // Type indices that have been exported with a name
  mut named_types : Array[UInt]

  // Component nesting depth for outer alias validation
  mut nesting_depth : UInt

  // Type size tracking for effective type size limit
  mut type_sizes : Array[UInt64] // size of each type definition
  mut component_sizes : Array[UInt64] // size of each component
  mut instance_sizes : Array[UInt64] // size of each instance

  // Collected errors
  mut errors : Array[ComponentValidationError]
}

///|
/// Resource info for tracking
pub(all) struct ResourceInfo {
  type_idx : UInt
  is_local : Bool
  name : String?
}

///|
/// Core export info for tracking what a core instance exports
pub(all) struct CoreExportInfo {
  name : String
  kind : CoreExportKind
  memory64 : Bool? // true if memory/table is 64-bit indexed
}

///|
/// Core import info for tracking what a core module imports
pub(all) struct CoreImportInfo {
  module_ : String
  name : String
  kind : CoreExportKind
  memory64 : Bool? // true if memory/table is 64-bit indexed
}

///|
/// Core export kind
pub(all) enum CoreExportKind {
  Func
  Table
  Memory
  Global
  Tag
} derive(Show, Eq)

///|
/// Component export info for tracking what a component instance exports
pub(all) struct ExportInfo {
  name : String
  kind : ExportKind
  type_idx : UInt? // type index if applicable
}

///|
/// Component export kind
pub(all) enum ExportKind {
  Func
  Type
  Instance
  Component
  Module
  Value
} derive(Show, Eq)

///|
/// Create a new validation context
pub fn ComponentValidationContext::new() -> ComponentValidationContext {
  {
    types: [],
    core_types: [],
    funcs: [],
    instances: [],
    components: [],
    nested_components: [],
    modules: [],
    values: [],
    core_funcs: [],
    core_instances: [],
    core_modules: [],
    core_module_exports: [],
    core_module_imports: [],
    core_tables: [],
    core_memories: [],
    core_globals: [],
    core_tags: [],
    core_instance_exports: [],
    instance_exports: [],
    resources: [],
    export_names: [],
    import_names: [],
    named_types: [],
    nesting_depth: 0U,
    type_sizes: [],
    component_sizes: [],
    instance_sizes: [],
    errors: [],
  }
}

///|
/// Add an error to the context
pub fn ComponentValidationContext::add_error(self : ComponentValidationContext, error : ComponentValidationError) -> Unit {
  self.errors.push(error)
}

///|
/// Check if validation passed (no errors)
pub fn ComponentValidationContext::is_valid(self : ComponentValidationContext) -> Bool {
  self.errors.is_empty()
}

///|
/// Get all errors
pub fn ComponentValidationContext::get_errors(self : ComponentValidationContext) -> Array[ComponentValidationError] {
  self.errors
}
