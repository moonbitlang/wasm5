// Component Runtime Type Definitions

///|
/// Value that can be passed to/from component functions
pub(all) enum ComponentValue {
  Bool(Bool)
  S8(Int)
  U8(Int)
  S16(Int)
  U16(Int)
  S32(Int)
  U32(UInt)
  S64(Int64)
  U64(UInt64)
  F32(Float)
  F64(Double)
  Char(Char)
  String(String)
  List(Array[ComponentValue])
  Record(Array[(String, ComponentValue)]) // field name -> value
  Tuple(Array[ComponentValue])
  Variant(Int, String, ComponentValue?) // discriminant, case name, optional payload
  Flags(Array[String]) // set flag names
  Enum(Int, String) // discriminant, case name
  OptionNone // option.none
  OptionSome(ComponentValue) // option.some(value)
  ResultOk(ComponentValue?) // result.ok(value?)
  ResultErr(ComponentValue?) // result.err(value?)
  Own(UInt, UInt) // resource_type_idx, handle
  Borrow(UInt, UInt) // resource_type_idx, handle
} derive(Show, Eq)

///|
/// A resource entry in the resource table
struct ResourceEntry {
  type_idx : UInt // resource type index
  rep : UInt // representation value (i32)
  owned : Bool // true if this is an owned handle
  dtor : UInt? // optional destructor function index
} derive(Show, Eq)

///|
/// A component-level function (either lifted from core or imported)
enum ComponentFunc {
  /// Lifted from core function via canon.lift
  Lifted(UInt, Bytes, UInt, Array[@core.CanonOpt]) // instance_idx, func_name, type_idx, options
  /// Imported from host
  Imported(Bytes, ImportedComponentFunc) // import name, host function
}

///|
/// An imported component function provided by the host
pub(all) struct ImportedComponentFunc {
  func : (Array[ComponentValue]) -> Array[ComponentValue]
}

///|
/// A core-level function reference
enum CoreFunc {
  /// Aliased from core instance export
  Aliased(UInt, Bytes) // instance_idx, func_name
  /// Lowered from component function via canon.lower
  Lowered(UInt, Array[@core.CanonOpt]) // component_func_idx, options
  /// Resource.new intrinsic: rep -> handle
  ResourceNew(UInt) // resource_type_idx
  /// Resource.drop intrinsic: handle -> ()
  ResourceDrop(UInt) // resource_type_idx
  /// Resource.rep intrinsic: handle -> rep
  ResourceRep(UInt) // resource_type_idx
}

///|
/// A virtual export kind in a core instance
#warnings("-unused_field")
priv enum VirtualCoreExport {
  /// Core function index
  Func(UInt)
  /// Memory reference (data array and max pages)
  Memory(Array[Byte], UInt64?)
  /// Table reference
  Table(@runtime.RuntimeTable)
  /// Global value
  Global(@runtime.Value)
  /// Tag index (for exception handling)
  Tag(UInt)
}

///|
/// A core instance (either real or virtual from exports)
enum CoreInstanceEntry {
  /// Real runtime instance
  Real(@runtime.Runtime)
  /// Virtual instance from exports (maps name -> export)
  Virtual(Map[String, VirtualCoreExport])
}

///|
/// A component instance entry
enum ComponentInstanceEntry {
  /// Instantiated from a nested component
  Instantiated(ComponentRuntime)
  /// Virtual instance from exports (maps name -> export kind)
  VirtualComponent(Map[String, @core.ComponentExportKind])
}

///|
/// Import resolver for component imports
pub struct ComponentImportResolver {
  // Array of (name, func) pairs to support multiple functions with the same name
  funcs : Array[(String, ImportedComponentFunc)]
  // Track which functions have been consumed during resolution
  mut func_index : Int
  values : Map[String, ComponentValue]
  instances : Map[String, ComponentRuntime]
}

///|
pub fn ComponentImportResolver::new() -> ComponentImportResolver {
  ComponentImportResolver::{
    funcs: [],
    func_index: 0,
    values: {},
    instances: {},
  }
}

///|
pub fn ComponentImportResolver::add_func(
  self : ComponentImportResolver,
  name : String,
  func : ImportedComponentFunc,
) -> Unit {
  self.funcs.push((name, func))
}

///|
/// Get the next function matching the given name.
/// This consumes the function from the resolver (advances the index).
pub fn ComponentImportResolver::get_func(
  self : ComponentImportResolver,
  name : String,
) -> ImportedComponentFunc? {
  // Find the next function with the matching name starting from func_index
  for i in self.func_index..<self.funcs.length() {
    let (func_name, func) = self.funcs[i]
    if func_name == name {
      self.func_index = i + 1
      return Some(func)
    }
  }
  None
}

///|
pub fn ComponentImportResolver::add_value(
  self : ComponentImportResolver,
  name : String,
  value : ComponentValue,
) -> Unit {
  self.values[name] = value
}

///|
pub fn ComponentImportResolver::add_instance(
  self : ComponentImportResolver,
  name : String,
  instance : ComponentRuntime,
) -> Unit {
  self.instances[name] = instance
}
