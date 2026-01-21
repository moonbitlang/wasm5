// Component Model Types
// Based on WebAssembly Component Model specification

// =============================================================================
// Primitive Value Types
// =============================================================================

///|
pub(all) enum PrimitiveType {
  Bool
  S8
  U8
  S16
  U16
  S32
  U32
  S64
  U64
  F32
  F64
  Char
  String
} derive(Show, Eq)

// =============================================================================
// Component Value Types
// =============================================================================

///|
pub(all) enum ComponentValType {
  Primitive(PrimitiveType)
  // Indexed types (reference to type section)
  TypeIndex(UInt)
  // Inline compound types
  List(ComponentValType)
  Record(Array[RecordField])
  Variant(Array[VariantCase])
  Tuple(Array[ComponentValType])
  Flags(Array[Bytes]) // field names
  Enum(Array[Bytes]) // case names
  Option(ComponentValType)
  Result(ComponentValType?, ComponentValType?) // ok type, error type
  Own(UInt) // resource type index
  Borrow(UInt) // resource type index
  // Async types (0x64-0x67)
  ErrorContext // 0x64
  Future(ComponentValType?) // 0x65
  Stream(ComponentValType?) // 0x66
  FixedSizeList(ComponentValType, UInt) // 0x67 - element type, length
} derive(Show, Eq)

///|
pub(all) struct RecordField {
  name : Bytes
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct VariantCase {
  name : Bytes
  type_ : ComponentValType? // optional payload
  refines : UInt? // optional refinement index
} derive(Show, Eq)

// =============================================================================
// Component Function Types
// =============================================================================

///|
pub(all) struct ComponentParam {
  name : Bytes
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct ComponentResult {
  name : Bytes? // optional name for named results
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct ComponentFuncType {
  params : Array[ComponentParam]
  results : Array[ComponentResult]
} derive(Show, Eq)

// =============================================================================
// Type Definitions
// =============================================================================

///|
pub(all) enum ComponentTypeDef {
  Defined(ComponentValType)
  Func(ComponentFuncType)
  Component(ComponentType)
  Instance(InstanceType)
  Resource(ResourceType)
}

///|
pub(all) struct ResourceType {
  rep : ValType // representation type
  dtor : UInt? // optional destructor function index
} derive(Show, Eq)

// =============================================================================
// Instance Types
// =============================================================================

///|
pub(all) enum InstanceTypeDecl {
  CoreType(CoreType)
  Type(ComponentTypeDef)
  Alias(Alias)
  Import(ComponentImportDecl)
  Export(ComponentExportDecl)
}

///|
pub(all) struct InstanceType {
  decls : Array[InstanceTypeDecl]
}

// =============================================================================
// Component Types
// =============================================================================

///|
pub(all) enum ComponentTypeDecl {
  CoreType(CoreType)
  Type(ComponentTypeDef)
  Alias(Alias)
  Import(ComponentImportDecl)
  Export(ComponentExportDecl)
}

///|
pub(all) struct ComponentType {
  decls : Array[ComponentTypeDecl]
}

// =============================================================================
// Core Types (embedded in component)
// =============================================================================

///|
pub(all) enum CoreType {
  Func(FuncType)
  Module(ModuleType)
}

///|
pub(all) enum ModuleTypeDecl {
  Type(TypeDef)
  Import(Import)
  Alias(CoreAlias)
  Export(Bytes, ImportDesc) // name, desc (uses ImportDesc since exports contain inline types in module types)
}

///|
pub(all) struct ModuleType {
  decls : Array[ModuleTypeDecl]
}

// =============================================================================
// Aliases
// =============================================================================

///|
pub(all) enum AliasTarget {
  Export(UInt, Bytes) // instance index, name
  CoreExport(UInt, Bytes) // core instance index, name
  Outer(UInt, UInt) // count, index
} derive(Show, Eq)

///|
pub(all) enum AliasKind {
  CoreModule
  CoreType
  CoreTable
  CoreFunc
  CoreMemory
  CoreGlobal
  CoreTag
  Type
  Component
  Instance
  Func
  Value
} derive(Show, Eq)

///|
pub(all) struct Alias {
  kind : AliasKind
  target : AliasTarget
} derive(Show, Eq)

///|
pub(all) struct CoreAlias {
  kind : AliasKind
  target : AliasTarget
} derive(Show, Eq)

// =============================================================================
// Import/Export Declarations
// =============================================================================

///|
pub(all) enum ExternKind {
  Module
  Func
  Value
  Type
  Instance
  Component
} derive(Show, Eq)

///|
pub(all) enum ComponentExternDesc {
  Module(UInt) // type index
  Func(UInt) // type index
  Value(ComponentValType)
  Type(TypeBounds)
  Instance(UInt) // type index
  Component(UInt) // type index
} derive(Show, Eq)

///|
pub(all) enum TypeBounds {
  Eq(UInt) // type index
  SubResource // sub resource bound
} derive(Show, Eq)

///|
pub(all) struct ComponentImportDecl {
  name : Bytes
  url : Bytes? // optional URL
  desc : ComponentExternDesc
} derive(Show, Eq)

///|
pub(all) struct ComponentExportDecl {
  name : Bytes
  url : Bytes? // optional URL
  desc : ComponentExternDesc
} derive(Show, Eq)

// =============================================================================
// Canonical Functions
// =============================================================================

///|
pub(all) enum StringEncoding {
  Utf8
  Utf16
  Latin1Utf16
} derive(Show, Eq)

///|
pub(all) enum CanonOpt {
  Utf8
  Utf16
  Latin1Utf16
  Memory(UInt) // memory index
  Realloc(UInt) // function index
  PostReturn(UInt) // function index
} derive(Show, Eq)

///|
pub(all) enum Canon {
  Lift(UInt, Array[CanonOpt], UInt) // core func index, options, func type index
  Lower(UInt, Array[CanonOpt]) // component func index, options
  ResourceNew(UInt) // resource type index
  ResourceDrop(UInt) // resource type index
  ResourceRep(UInt) // resource type index
} derive(Show, Eq)

// =============================================================================
// Instances
// =============================================================================

///|
pub(all) enum InstantiateArg {
  // Core sorts (0x00 + core:sort)
  CoreFunc(Bytes, UInt) // name, core func index
  CoreTable(Bytes, UInt) // name, core table index
  CoreMemory(Bytes, UInt) // name, core memory index
  CoreGlobal(Bytes, UInt) // name, core global index
  CoreType(Bytes, UInt) // name, core type index
  CoreModule(Bytes, UInt) // name, core module index
  CoreInstance(Bytes, UInt) // name, core instance index
  // Component sorts (0x01-0x05)
  Func(Bytes, UInt) // name, func index
  Value(Bytes, UInt) // name, value index
  Type(Bytes, UInt) // name, type index
  Component(Bytes, UInt) // name, component index
  Instance(Bytes, UInt) // name, instance index
} derive(Show, Eq)

///|
pub(all) enum CoreInstantiateArg {
  Instance(Bytes, UInt) // import name, core instance index
} derive(Show, Eq)

///|
pub(all) enum ComponentInstance {
  Instantiate(UInt, Array[InstantiateArg]) // component index, args
  FromExports(Array[ComponentExport])
} derive(Show, Eq)

///|
pub(all) enum CoreInstance {
  Instantiate(UInt, Array[CoreInstantiateArg]) // module index, args
  FromExports(Array[CoreExport])
} derive(Show, Eq)

// =============================================================================
// Exports
// =============================================================================

///|
pub(all) enum ComponentExportKind {
  Module(UInt)
  Func(UInt)
  Value(UInt)
  Type(UInt)
  Instance(UInt)
  Component(UInt)
} derive(Show, Eq)

///|
pub(all) struct ComponentExport {
  name : Bytes
  kind : ComponentExportKind
  extern_type : ComponentExternDesc? // optional type annotation
} derive(Show, Eq)

///|
pub(all) enum CoreExportKind {
  Func(UInt)
  Table(UInt)
  Memory(UInt)
  Global(UInt)
  Tag(UInt)
} derive(Show, Eq)

///|
pub(all) struct CoreExport {
  name : Bytes
  kind : CoreExportKind
} derive(Show, Eq)

// =============================================================================
// Imports
// =============================================================================

///|
pub(all) struct ComponentImport {
  name : Bytes
  url : Bytes? // optional URL
  desc : ComponentExternDesc
} derive(Show, Eq)

// =============================================================================
// Start Function
// =============================================================================

///|
pub(all) struct ComponentStart {
  func_idx : UInt
  args : Array[UInt] // value indices
  results : UInt // number of results
} derive(Show, Eq)

// =============================================================================
// Component Structure
// =============================================================================

///|
pub(all) enum ComponentSection {
  CoreModule(Module) // section 0
  CoreInstance(CoreInstance) // section 1
  CoreType(CoreType) // section 2
  Component(Component) // section 3 (recursive)
  Instance(ComponentInstance) // section 4
  Alias(Alias) // section 5
  Type(ComponentTypeDef) // section 6
  Canon(Canon) // section 7
  Start(ComponentStart) // section 8
  Import(ComponentImport) // section 9
  Export(ComponentExport) // section 10
  Custom(CustomSection)
}

///|
pub(all) struct Component {
  sections : Array[ComponentSection]
}
