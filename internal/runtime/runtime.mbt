// Re-export Value from core for backwards compatibility

///|
pub type Value = @core.Value

///|
/// Instance error types
pub suberror RuntimeError {
  DivisionByZero
  IntegerOverflow
  MemoryOutOfBounds
  TableOutOfBounds // Out of bounds table access
  InvalidType(String)
  FunctionNotFound(String)
  Unreachable // Unreachable instruction executed
  FunctionNotCompiled(String) // Function not compiled
  UnsupportedInitExpression(String) // Unsupported init expression
  StackOverflow // Stack capacity exceeded
} derive(Show)

///|
/// Create a RuntimeError from error_detail string.
/// The detail string should start with an error type prefix.
/// This function is public to allow other runtimes (e.g., CRuntime) to create errors.
pub fn RuntimeError::from_detail(detail : String) -> RuntimeError {
  if detail.has_prefix("division by zero") {
    RuntimeError::DivisionByZero
  } else if detail.has_prefix("integer overflow") {
    RuntimeError::IntegerOverflow
  } else if detail.has_prefix("out of bounds table access") {
    RuntimeError::TableOutOfBounds
  } else if detail.has_prefix("out of bounds memory access") {
    RuntimeError::MemoryOutOfBounds
  } else if detail.has_prefix("unreachable") {
    RuntimeError::Unreachable
  } else if detail.has_prefix("stack overflow") {
    RuntimeError::StackOverflow
  } else {
    RuntimeError::InvalidType(detail)
  }
}

///|
/// Table with its limits
struct RuntimeTable {
  data : Array[UInt64] // Table data (64-bit tagged refs, 0xFFFFFFFFFFFFFFFF = null)
  max : UInt64? // Maximum size limit (None = no limit)
  // External funcrefs for cross-module table sharing.
  // When a module stores its own funcrefs into an imported table,
  // wrappers are added here and negative indices stored in data.
  // Mapping: use funcref tag (0x4000...) with negative indices
  external_funcrefs : Array[HostFunc]
}

///|
/// Get table data length
pub fn RuntimeTable::data_length(self : RuntimeTable) -> Int {
  self.data.length()
}

///|
/// Get table element at index (returns 64-bit tagged ref)
pub fn RuntimeTable::get_data(self : RuntimeTable, idx : Int) -> UInt64 {
  self.data[idx]
}

///|
/// Set table element at index (value is 64-bit tagged ref)
pub fn RuntimeTable::set_data(
  self : RuntimeTable,
  idx : Int,
  value : UInt64,
) -> Unit {
  self.data[idx] = value
}

///|
/// Get external funcrefs length
pub fn RuntimeTable::external_funcrefs_length(self : RuntimeTable) -> Int {
  self.external_funcrefs.length()
}

///|
/// Add external funcref and return its index
pub fn RuntimeTable::add_external_funcref(
  self : RuntimeTable,
  func : HostFunc,
) -> Int {
  let idx = self.external_funcrefs.length()
  self.external_funcrefs.push(func)
  idx
}

///|
/// Create a new runtime table for host imports.
pub fn RuntimeTable::new(
  data : Array[UInt64],
  max? : UInt64? = None,
) -> RuntimeTable {
  { data, max, external_funcrefs: [] }
}

///|
pub struct HostFunc {
  arity : UInt
  func : (Array[Value]) -> Array[Value]
}

///|
/// Create a new HostFunc.
/// `arity` is optional and used mainly for tests and validation.
pub fn HostFunc::new(
  func : (Array[Value]) -> Array[Value],
  arity? : UInt = 0U,
) -> HostFunc {
  { arity, func }
}

///|
/// Imported memory with its limits
pub struct ImportedMemory {
  data : Array[Byte]
  max : UInt64? // Maximum size in pages (None = no limit)
}

///|
/// Create an imported memory with optional max pages.
pub fn ImportedMemory::new(
  data : Array[Byte],
  max? : UInt64? = None,
) -> ImportedMemory {
  { data, max }
}

///|
/// Import map for linking modules
/// Maps (module_name, field_name) to HostFunc, global Value, table, or memory
/// Using Bytes keys to match how WebAssembly module imports work
struct ImportsEntry {
  funcs : Map[Bytes, HostFunc]
  globals : Map[Bytes, Value]
  tables : Map[Bytes, RuntimeTable]
  memories : Map[Bytes, ImportedMemory]
  // Wrappers for funcref globals - used for cross-module funcref handling
  funcref_wrappers : Map[Bytes, HostFunc]
}

///|
pub struct Imports {
  modules : Map[Bytes, ImportsEntry]
}

///|
/// Create a new empty imports set
pub fn Imports::new() -> Imports {
  { modules: Map::new() }
}

///|
fn encode_import_name(name : String) -> Bytes {
  @utf8.encode(name)
}

///|
/// Add an imported function with String names.
pub fn Imports::func(
  self : Imports,
  module_ : String,
  name : String,
  func : HostFunc,
) -> Imports {
  self.add_func(encode_import_name(module_), encode_import_name(name), func)
  self
}

///|
/// Add an imported global with String names.
pub fn Imports::global(
  self : Imports,
  module_ : String,
  name : String,
  value : Value,
) -> Imports {
  self.add_global(encode_import_name(module_), encode_import_name(name), value)
  self
}

///|
/// Add an imported table with String names.
pub fn Imports::table(
  self : Imports,
  module_ : String,
  name : String,
  table : RuntimeTable,
) -> Imports {
  self.add_table(encode_import_name(module_), encode_import_name(name), table)
  self
}

///|
/// Add an imported memory with String names.
pub fn Imports::memory(
  self : Imports,
  module_ : String,
  name : String,
  memory : ImportedMemory,
) -> Imports {
  self.add_memory(encode_import_name(module_), encode_import_name(name), memory)
  self
}

///|
/// Add a funcref wrapper with String names.
pub fn Imports::funcref_wrapper(
  self : Imports,
  module_ : String,
  name : String,
  wrapper : HostFunc,
) -> Imports {
  self.add_funcref_wrapper(
    encode_import_name(module_),
    encode_import_name(name),
    wrapper,
  )
  self
}

///|
/// Add an imported function to the imports (using Bytes names).
pub fn Imports::add_func(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
  func : HostFunc,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.funcs[name] = func
    None => {
      let entry : ImportsEntry = {
        funcs: Map::new(),
        globals: Map::new(),
        tables: Map::new(),
        memories: Map::new(),
        funcref_wrappers: Map::new(),
      }
      entry.funcs[name] = func
      self.modules[module_] = entry
    }
  }
}

///|
/// Add an imported global to the imports
pub fn Imports::add_global(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
  value : Value,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.globals[name] = value
    None => {
      let entry : ImportsEntry = {
        funcs: Map::new(),
        globals: Map::new(),
        tables: Map::new(),
        memories: Map::new(),
        funcref_wrappers: Map::new(),
      }
      entry.globals[name] = value
      self.modules[module_] = entry
    }
  }
}

///|
/// Look up an imported function
pub fn Imports::get_func(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
) -> HostFunc? {
  match self.modules.get(module_) {
    Some(entry) => entry.funcs.get(name)
    None => None
  }
}

///|
/// Look up an imported global
pub fn Imports::get_global(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
) -> Value? {
  match self.modules.get(module_) {
    Some(entry) => entry.globals.get(name)
    None => None
  }
}

///|
/// Add an imported table to the imports
pub fn Imports::add_table(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
  table : RuntimeTable,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.tables[name] = table
    None => {
      let entry : ImportsEntry = {
        funcs: Map::new(),
        globals: Map::new(),
        tables: Map::new(),
        memories: Map::new(),
        funcref_wrappers: Map::new(),
      }
      entry.tables[name] = table
      self.modules[module_] = entry
    }
  }
}

///|
/// Look up an imported table
pub fn Imports::get_table(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
) -> RuntimeTable? {
  match self.modules.get(module_) {
    Some(entry) => entry.tables.get(name)
    None => None
  }
}

///|
/// Add an imported memory to the imports
pub fn Imports::add_memory(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
  memory : ImportedMemory,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.memories[name] = memory
    None => {
      let entry : ImportsEntry = {
        funcs: Map::new(),
        globals: Map::new(),
        tables: Map::new(),
        memories: Map::new(),
        funcref_wrappers: Map::new(),
      }
      entry.memories[name] = memory
      self.modules[module_] = entry
    }
  }
}

///|
/// Look up an imported memory
pub fn Imports::get_memory(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
) -> ImportedMemory? {
  match self.modules.get(module_) {
    Some(entry) => entry.memories.get(name)
    None => None
  }
}

///|
/// Add a funcref wrapper to the imports.
/// This is used for cross-module funcref handling - when a module exports
/// a funcref global, we also register a wrapper that can call the function.
pub fn Imports::add_funcref_wrapper(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
  wrapper : HostFunc,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.funcref_wrappers[name] = wrapper
    None => {
      let entry : ImportsEntry = {
        funcs: Map::new(),
        globals: Map::new(),
        tables: Map::new(),
        memories: Map::new(),
        funcref_wrappers: Map::new(),
      }
      entry.funcref_wrappers[name] = wrapper
      self.modules[module_] = entry
    }
  }
}

///|
/// Look up a funcref wrapper
pub fn Imports::get_funcref_wrapper(
  self : Imports,
  module_ : Bytes,
  name : Bytes,
) -> HostFunc? {
  match self.modules.get(module_) {
    Some(entry) => entry.funcref_wrappers.get(name)
    None => None
  }
}

///|
/// Initial stack capacity (can grow as needed)
let initial_stack_capacity : Int = 1024

///|
/// Instance structure for WebAssembly execution.
/// This is a value type containing hot fields for fast access.
/// Cold data is accessed through the ctx reference.
pub struct Instance {
  ops : FixedArray[UInt64] // Compiled instructions (tagless: fn ptrs and immediates as UInt64)
  stack : FixedArray[UInt64] // Unified stack for locals and operand stack (tagless)
  mut sp : Int // Current top of stack (next push position)
  mut bp : Int // Base pointer: index of first local in unified stack
  mut num_locals : Int // Number of locals for current function
  mut pc : Int // Program counter
  ctx : RuntimeContext // Reference to cold data (module, memory, globals, etc.)
}

///|
fn code_to_ops(code : Array[Int64]) -> FixedArray[UInt64] {
  let ops = FixedArray::make(code.length(), 0UL)
  for i in 0..<code.length() {
    ops[i] = code[i].reinterpret_as_uint64()
  }
  ops
}

///|
/// Get the module from the runtime
pub fn Instance::get_module(self : Instance) -> @core.Module {
  self.ctx.module_
}

///|
/// Get the globals array from the runtime
pub fn Instance::get_globals(self : Instance) -> Array[Value] {
  self.ctx.globals
}

///|
/// Get the tables array from the runtime
pub fn Instance::get_tables(self : Instance) -> Array[RuntimeTable] {
  self.ctx.tables
}

///|
/// Get collected spectest output
pub fn Instance::get_output(self : Instance) -> Array[String] {
  self.ctx.output
}

///|
/// Clear collected spectest output
pub fn Instance::clear_output(self : Instance) -> Unit {
  self.ctx.output.clear()
}

///|
/// Typed function export.
pub struct Func {
  instance : Instance
  func_idx : Int
  func_type : @core.FuncType
}

///|
/// Typed memory export.
pub struct Memory {
  instance : Instance
  mem_idx : Int
}

///|
/// Typed table export.
pub struct Table {
  instance : Instance
  table_idx : Int
  table_type : @core.TableType
}

///|
/// Typed global export.
pub struct Global {
  instance : Instance
  global_idx : Int
  global_type : @core.GlobalType
}

///|
fn is_ref_value(value : Value) -> Bool {
  match value {
    Ref(_) | Funcref(_) | Externref(_) => true
    _ => false
  }
}

///|
fn is_null_ref(value : Value) -> Bool {
  match value {
    Ref(None) | Funcref(None) | Externref(None) => true
    _ => false
  }
}

///|
fn is_func_ref_type(val_type : @core.ValType) -> Bool {
  match val_type {
    FuncRef | NullFuncRef | Ref(@core.Func, _) | Ref(@core.NoFunc, _) => true
    _ => false
  }
}

///|
fn is_extern_ref_type(val_type : @core.ValType) -> Bool {
  match val_type {
    ExternRef | NullExternRef | Ref(@core.Extern, _) | Ref(@core.NoExtern, _) =>
      true
    _ => false
  }
}

///|
fn is_null_only_type(val_type : @core.ValType) -> Bool {
  match val_type {
    NullRef | NullFuncRef | NullExternRef | NullExnRef => true
    _ => false
  }
}

///|
fn is_non_nullable_ref_type(val_type : @core.ValType) -> Bool {
  match val_type {
    Ref(_, false) => true
    _ => false
  }
}

///|
fn check_value_type(value : Value, val_type : @core.ValType) -> Bool {
  match val_type {
    I32 =>
      match value {
        I32(_) => true
        _ => false
      }
    I64 =>
      match value {
        I64(_) => true
        _ => false
      }
    F32 =>
      match value {
        F32(_) => true
        _ => false
      }
    F64 =>
      match value {
        F64(_) => true
        _ => false
      }
    V128 =>
      match value {
        I32(_) => true
        _ => false
      }
    _ => {
      if not(is_ref_value(value)) {
        return false
      }
      if is_func_ref_type(val_type) {
        match value {
          Externref(_) => return false
          _ => ()
        }
      } else if is_extern_ref_type(val_type) {
        match value {
          Funcref(_) => return false
          _ => ()
        }
      } else {
        match value {
          Ref(_) => ()
          _ => return false
        }
      }
      if is_null_only_type(val_type) {
        return is_null_ref(value)
      }
      if is_non_nullable_ref_type(val_type) {
        return not(is_null_ref(value))
      }
      true
    }
  }
}

///|
fn require_value_type(
  value : Value,
  val_type : @core.ValType,
  context : String,
) -> Unit raise RuntimeError {
  if not(check_value_type(value, val_type)) {
    raise RuntimeError::InvalidType("\{context}: type mismatch")
  }
}

///|
fn get_func_type_for_index(
  module_ : @core.Module,
  func_idx : Int,
  num_imported_funcs : Int,
) -> @core.FuncType? {
  let type_idx = @core.get_func_type_idx(module_, func_idx, num_imported_funcs)
  if type_idx < 0 || type_idx >= module_.types.length() {
    return None
  }
  match module_.types[type_idx] {
    Func(ft) => Some(ft)
    _ => None
  }
}

///|
/// Get table type for index. Delegates to core implementation.
fn get_table_type_for_index(
  module_ : @core.Module,
  table_idx : Int,
) -> @core.TableType? {
  let num_imported = @core.count_imported_tables(module_)
  @core.get_table_type(module_, table_idx, num_imported)
}

///|
/// Get global type for index. Delegates to core implementation.
fn get_global_type_for_index(
  module_ : @core.Module,
  global_idx : Int,
) -> @core.GlobalType? {
  let num_imported = @core.count_imported_globals(module_)
  @core.get_global_type(module_, global_idx, num_imported)
}

///|
fn get_table_val_type(table_type : @core.TableType) -> @core.ValType {
  match table_type.elem_type {
    @core.Func | @core.NoFunc =>
      if table_type.nullable {
        FuncRef
      } else {
        Ref(@core.Func, false)
      }
    @core.Extern | @core.NoExtern =>
      if table_type.nullable {
        ExternRef
      } else {
        Ref(@core.Extern, false)
      }
    _ => Ref(table_type.elem_type, table_type.nullable)
  }
}

///|
fn encode_tagged_ref(idx : Int, tag : UInt64) -> UInt64 {
  let raw = idx.to_int64().reinterpret_as_uint64()
  let masked = raw & 0x3FFFFFFFFFFFFFFFUL
  masked | tag
}

///|
fn encode_table_value(
  value : Value,
  table_type : @core.TableType,
) -> UInt64 raise RuntimeError {
  if not(is_ref_value(value)) {
    raise RuntimeError::InvalidType("table.set: expected reference value")
  }
  if not(table_type.nullable) && is_null_ref(value) {
    raise RuntimeError::InvalidType("table.set: null for non-nullable table")
  }
  match table_type.elem_type {
    @core.Func | @core.NoFunc =>
      match value {
        Ref(Some(idx)) | Funcref(Some(idx)) =>
          encode_tagged_ref(idx, 0x4000000000000000UL)
        Ref(None) | Funcref(None) => 0xFFFFFFFFFFFFFFFFUL
        Externref(_) =>
          raise RuntimeError::InvalidType("table.set: expected funcref")
        _ => raise RuntimeError::InvalidType("table.set: expected funcref")
      }
    @core.Extern | @core.NoExtern =>
      match value {
        Ref(Some(idx)) | Externref(Some(idx)) =>
          encode_tagged_ref(idx, 0x2000000000000000UL)
        Ref(None) | Externref(None) => 0xFFFFFFFFFFFFFFFFUL
        Funcref(_) =>
          raise RuntimeError::InvalidType("table.set: expected externref")
        _ => raise RuntimeError::InvalidType("table.set: expected externref")
      }
    _ =>
      match value {
        Ref(Some(idx)) => idx.to_int64().reinterpret_as_uint64()
        Ref(None) => 0xFFFFFFFFFFFFFFFFUL
        _ => raise RuntimeError::InvalidType("table.set: expected reference")
      }
  }
}

///|
/// Get a function export by name.
pub fn Instance::get_func(self : Instance, name : String) -> Func? {
  let name_bytes = encode_import_name(name)
  for exp in self.ctx.module_.exports {
    if exp.name == name_bytes {
      match exp.desc {
        Func(idx) => {
          let func_idx = idx.reinterpret_as_int()
          let func_type = match
            get_func_type_for_index(
              self.ctx.module_,
              func_idx,
              self.ctx.num_imported_funcs,
            ) {
            Some(ft) => ft
            None => return None
          }
          return Some({ instance: self, func_idx, func_type })
        }
        _ => return None
      }
    }
  }
  None
}

///|
/// Get a memory export by name.
pub fn Instance::get_memory(self : Instance, name : String) -> Memory? {
  let name_bytes = encode_import_name(name)
  for exp in self.ctx.module_.exports {
    if exp.name == name_bytes {
      match exp.desc {
        Mem(idx) => {
          let mem_idx = idx.reinterpret_as_int()
          let total_mems = @core.count_imported_mems(self.ctx.module_) +
            self.ctx.module_.mems.length()
          if mem_idx < 0 || mem_idx >= total_mems || mem_idx != 0 {
            return None
          }
          return Some({ instance: self, mem_idx })
        }
        _ => return None
      }
    }
  }
  None
}

///|
/// Get a table export by name.
pub fn Instance::get_table(self : Instance, name : String) -> Table? {
  let name_bytes = encode_import_name(name)
  for exp in self.ctx.module_.exports {
    if exp.name == name_bytes {
      match exp.desc {
        Table(idx) => {
          let table_idx = idx.reinterpret_as_int()
          let table_type = match
            get_table_type_for_index(self.ctx.module_, table_idx) {
            Some(found) => found
            None => return None
          }
          return Some({ instance: self, table_idx, table_type })
        }
        _ => return None
      }
    }
  }
  None
}

///|
/// Get a global export by name.
pub fn Instance::get_global(self : Instance, name : String) -> Global? {
  let name_bytes = encode_import_name(name)
  for exp in self.ctx.module_.exports {
    if exp.name == name_bytes {
      match exp.desc {
        Global(idx) => {
          let global_idx = idx.reinterpret_as_int()
          let global_type = match
            get_global_type_for_index(self.ctx.module_, global_idx) {
            Some(found) => found
            None => return None
          }
          return Some({ instance: self, global_idx, global_type })
        }
        _ => return None
      }
    }
  }
  None
}

///|
/// Call a typed function export.
pub fn Func::call(
  self : Func,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  if args.length() != self.func_type.params.length() {
    raise RuntimeError::InvalidType("func.call: arity mismatch")
  }
  for i in 0..<args.length() {
    require_value_type(args[i], self.func_type.params[i], "func.call")
  }
  self.instance.call_by_index(self.func_idx, args)
}

///|
/// Get the function type.
pub fn Func::type_(self : Func) -> @core.FuncType {
  self.func_type
}

///|
/// Read memory bytes.
pub fn Memory::read(
  self : Memory,
  offset : Int,
  len : Int,
) -> Bytes raise RuntimeError {
  if self.mem_idx != 0 {
    raise RuntimeError::InvalidType("memory.read: unsupported memory index")
  }
  let memory = self.instance.ctx.memory
  if offset < 0 ||
    len < 0 ||
    offset > memory.length() ||
    memory.length() - offset < len {
    raise RuntimeError::MemoryOutOfBounds
  }
  let out : Array[Byte] = Array::make(len, b'\x00')
  for i in 0..<len {
    out[i] = memory[offset + i]
  }
  Bytes::from_array(out)
}

///|
/// Write bytes into memory.
pub fn Memory::write(
  self : Memory,
  offset : Int,
  data : Bytes,
) -> Unit raise RuntimeError {
  if self.mem_idx != 0 {
    raise RuntimeError::InvalidType("memory.write: unsupported memory index")
  }
  let memory = self.instance.ctx.memory
  let len = data.length()
  if offset < 0 ||
    len < 0 ||
    offset > memory.length() ||
    memory.length() - offset < len {
    raise RuntimeError::MemoryOutOfBounds
  }
  for i in 0..<len {
    memory[offset + i] = data[i]
  }
}

///|
/// Get memory size in pages.
pub fn Memory::size(self : Memory) -> Int {
  if self.mem_idx != 0 {
    return 0
  }
  self.instance.ctx.memory.length() / wasm_page_size
}

///|
/// Grow memory by the given number of pages, returning previous size.
pub fn Memory::grow(self : Memory, pages : Int) -> Int raise RuntimeError {
  if self.mem_idx != 0 {
    raise RuntimeError::InvalidType("memory.grow: unsupported memory index")
  }
  let memory = self.instance.ctx.memory
  let old_size_pages = memory.length() / wasm_page_size
  if pages < 0 {
    raise RuntimeError::MemoryOutOfBounds
  }
  let new_size_pages = old_size_pages + pages
  let max_pages = match self.instance.ctx.memory_max {
    Some(max) => max.to_int()
    None => 65536
  }
  if new_size_pages > max_pages {
    raise RuntimeError::MemoryOutOfBounds
  }
  let bytes_to_add = pages * wasm_page_size
  for i = 0; i < bytes_to_add; i = i + 1 {
    memory.push(b'\x00')
  }
  old_size_pages
}

///|
/// Get a table element by index.
pub fn Table::get(self : Table, idx : Int) -> Value? raise RuntimeError {
  if self.table_idx < 0 || self.table_idx >= self.instance.ctx.tables.length() {
    raise RuntimeError::TableOutOfBounds
  }
  let table = self.instance.ctx.tables[self.table_idx].data
  if idx < 0 || idx >= table.length() {
    raise RuntimeError::TableOutOfBounds
  }
  let raw = table[idx]
  if raw == 0xFFFFFFFFFFFFFFFFUL {
    None
  } else {
    let val_type = get_table_val_type(self.table_type)
    Some(stack_to_value(raw, val_type))
  }
}

///|
/// Set a table element by index.
pub fn Table::set(
  self : Table,
  idx : Int,
  value : Value,
) -> Unit raise RuntimeError {
  if self.table_idx < 0 || self.table_idx >= self.instance.ctx.tables.length() {
    raise RuntimeError::TableOutOfBounds
  }
  let table = self.instance.ctx.tables[self.table_idx].data
  if idx < 0 || idx >= table.length() {
    raise RuntimeError::TableOutOfBounds
  }
  let raw = encode_table_value(value, self.table_type)
  table[idx] = raw
}

///|
/// Get the table size.
pub fn Table::size(self : Table) -> Int {
  if self.table_idx < 0 || self.table_idx >= self.instance.ctx.tables.length() {
    return 0
  }
  self.instance.ctx.tables[self.table_idx].data.length()
}

///|
/// Get a global value.
pub fn Global::get(self : Global) -> Value {
  if self.global_idx < 0 ||
    self.global_idx >= self.instance.ctx.globals.length() {
    return Value::I32(0U)
  }
  self.instance.ctx.globals[self.global_idx]
}

///|
/// Set a global value.
pub fn Global::set(self : Global, value : Value) -> Unit raise RuntimeError {
  if not(self.global_type.mutable) {
    raise RuntimeError::InvalidType("global.set: immutable global")
  }
  require_value_type(value, self.global_type.val_type, "global.set")
  if self.global_idx < 0 ||
    self.global_idx >= self.instance.ctx.globals.length() {
    raise RuntimeError::InvalidType("global.set: index out of bounds")
  }
  self.instance.ctx.globals[self.global_idx] = value
}

///|
/// Create an imports set with the standard spectest module.
pub fn Imports::spectest() -> Imports {
  // Add spectest table (10 funcref, max 20)
  let table_data : Array[UInt64] = Array::make(10, 0xFFFFFFFFFFFFFFFFUL)
  // Add spectest memory (1 page initial, 2 pages max)
  let memory_size = 1 * 65536 // 1 page = 65536 bytes
  let memory_data : Array[Byte] = Array::make(memory_size, b'\x00')
  Imports::new()
  .func("spectest", "print_char", HostFunc::new(spectest_print_char, arity=1U))
  .func("spectest", "print", HostFunc::new(spectest_print))
  .func("spectest", "print_i32", HostFunc::new(spectest_print_i32, arity=1U))
  .func("spectest", "print_i64", HostFunc::new(spectest_print_i64, arity=1U))
  .func("spectest", "print_f32", HostFunc::new(spectest_print_f32, arity=1U))
  .func("spectest", "print_f64", HostFunc::new(spectest_print_f64, arity=1U))
  .func(
    "spectest",
    "print_i32_f32",
    HostFunc::new(spectest_print_i32_f32, arity=2U),
  )
  .func(
    "spectest",
    "print_f64_f64",
    HostFunc::new(spectest_print_f64_f64, arity=2U),
  )
  .table("spectest", "table", RuntimeTable::new(table_data, max=Some(20UL)))
  .memory("spectest", "memory", ImportedMemory::new(memory_data, max=Some(2UL)))
}

///|
/// Instantiate a WebAssembly module with explicit imports.
pub fn Instance::new(
  m : @core.Module,
  imports : Imports,
) -> Instance raise RuntimeError {
  // Initialize memory
  let mut memory : Array[Byte] = []
  let mut memory_max_pages : UInt64? = None

  // Check for imported memory first
  let mut has_imported_memory = false
  for imp in m.imports {
    match imp.desc {
      Mem(mem_type) => {
        has_imported_memory = true
        // Try to get the memory from the imports
        match imports.get_memory(imp.module_, imp.name) {
          Some(imported_mem) => {
            memory = imported_mem.data
            memory_max_pages = imported_mem.max
          }
          None => {
            // Fall back to creating memory with the specified limits
            let memory_size = mem_type.limits.min
              .reinterpret_as_int64()
              .to_int() *
              65536
            memory = Array::make(memory_size, b'\x00')
            memory_max_pages = mem_type.limits.max
          }
        }
        break // Only one memory allowed in MVP
      }
      _ => ()
    }
  }

  // If no imported memory, check for local memory
  if not(has_imported_memory) && m.mems.length() > 0 {
    let memory_min_pages = m.mems[0].limits.min
    memory_max_pages = m.mems[0].limits.max
    let memory_size = memory_min_pages.to_int() * 65536
    memory = Array::make(memory_size, b'\x00')
  }
  // Initialize globals
  // First, add imported globals - try to get from imports, otherwise use default values
  let globals : Array[Value] = []
  // Track external funcrefs for cross-module funcref handling
  let external_funcrefs : Array[HostFunc] = []
  for imp in m.imports {
    match imp.desc {
      Global(gt) => {
        // Try to get the global value from the imports
        let value = match imports.get_global(imp.module_, imp.name) {
          Some(v) =>
            // For funcref globals, check if there's a funcref wrapper
            // and if so, use a negative index to point to external_funcrefs
            match v {
              Ref(Some(_)) =>
                // Check for a funcref wrapper for cross-module calls
                match imports.get_funcref_wrapper(imp.module_, imp.name) {
                  Some(wrapper) => {
                    // Add wrapper to external_funcrefs and use negative index
                    // Mapping: -1 → [0], -2 → [1], etc.
                    let ext_idx = external_funcrefs.length()
                    external_funcrefs.push(wrapper)
                    Value::Ref(Some(-(ext_idx + 1)))
                  }
                  None => v
                }
              _ => v
            }
          None =>
            // Fall back to default values (for spectest)
            match gt.val_type {
              I32 => Value::I32(666U) // spectest global_i32 = 666
              I64 => Value::I64(666UL) // spectest global_i64 = 666
              F32 => Value::F32(666.6)
              F64 => Value::F64(666.6)
              FuncRef => Value::Ref(None)
              ExternRef => Value::Ref(None)
              _ => Value::I32(0U)
            }
        }
        globals.push(value)
      }
      _ => ()
    }
  }
  // Create GC heap for const expr evaluation (for globals that use GC instructions)
  let gc_heap : Array[GcObject] = []

  // Then add local globals
  for i in 0..<m.globals.length() {
    let global = m.globals[i]
    let value = eval_const_expr_with_gc(global.init, globals, gc_heap, m)
    globals.push(value)
  }
  // Initialize data segments (copy active data segments into memory)
  for data in m.datas {
    // Only copy active segments - passive segments are used with memory.init
    if data.is_active {
      // Evaluate offset expression to get the starting address
      let offset_value = eval_const_expr(data.offset, globals)
      let offset = match offset_value {
        I32(v) => v.reinterpret_as_int()
        _ =>
          raise RuntimeError::UnsupportedInitExpression(
            "data segment offset must be i32",
          )
      }
      // Copy data bytes into memory
      for i in 0..<data.init.length() {
        let addr = offset + i
        if addr >= 0 && addr < memory.length() {
          memory[addr] = data.init[i]
        }
      }
    }
  }
  // Initialize tables
  let tables : Array[RuntimeTable] = []
  // First, add imported tables
  for imp in m.imports {
    match imp.desc {
      Table(_) =>
        // Try to get the table from the imports
        match imports.get_table(imp.module_, imp.name) {
          Some(imported_table) => tables.push(imported_table)
          None => {
            // Fall back to creating an empty table if imports doesn't provide one
            // This shouldn't happen with proper test setup, but provides graceful fallback
            let table_size = 10 // Default size for fallback
            let table_data : Array[UInt64] = Array::make(
              table_size, 0xFFFFFFFFFFFFFFFFUL,
            )
            tables.push({
              data: table_data,
              max: Some(20UL),
              external_funcrefs: [],
            })
          }
        }
      _ => ()
    }
  }
  // Then add local tables
  for table in m.tables {
    let table_size = table.limits.min.to_int()
    // Initialize table with default value (null unless table has init expr)
    let init_ref : UInt64 = match table.init {
      Some(init_expr) => {
        let init_value = eval_const_expr(init_expr, globals)
        match init_value {
          Ref(Some(idx)) => idx.to_uint64() | 0x4000000000000000UL // funcref tag
          Ref(None) => 0xFFFFFFFFFFFFFFFFUL
          Funcref(Some(idx)) => idx.to_uint64() | 0x4000000000000000UL
          Funcref(None) => 0xFFFFFFFFFFFFFFFFUL
          Externref(Some(idx)) => idx.to_uint64() | 0x2000000000000000UL
          Externref(None) => 0xFFFFFFFFFFFFFFFFUL
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "table init expression must produce a reference",
            )
        }
      }
      None => 0xFFFFFFFFFFFFFFFFUL
    }
    let table_data : Array[UInt64] = Array::make(table_size, init_ref)
    tables.push({
      data: table_data,
      max: table.limits.max,
      external_funcrefs: [],
    })
  }
  // Initialize element segments (copy function references into tables)
  // Track which segments are dropped - active and declarative segments are dropped after instantiation
  let dropped_elems : Array[Bool] = []
  for i = 0; i < m.elems.length(); i = i + 1 {
    let elem = m.elems[i]
    // Active and declarative segments are dropped after instantiation
    dropped_elems.push(elem.is_active || elem.is_declarative)

    // Only process active segments - skip passive and declarative segments
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx >= 0 && table_idx < tables.length() {
        // Evaluate offset expression
        let offset_value = eval_const_expr(elem.offset, globals)
        let offset = match offset_value {
          I32(v) => v.reinterpret_as_int()
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "elem segment offset must be i32",
            )
        }
        // Copy element expressions into table
        let table = tables[table_idx]
        for j in 0..<elem.init.length() {
          let addr = offset + j
          if addr >= 0 && addr < table.data.length() {
            let value = eval_const_expr_with_gc(
              elem.init[j],
              globals,
              gc_heap,
              m,
            )
            // Convert reference value to table storage format
            // Check elem_type to determine how to encode the value:
            // - Func element type means Ref(Some(idx)) is a funcref -> add funcref tag
            // - Extern element type means Ref(Some(idx)) is an externref -> add externref tag
            // - Other types (i31, struct, array, etc.) are already properly encoded in Ref
            let ref_val : UInt64 = match value {
              Ref(Some(idx)) =>
                // Determine encoding based on elem_type
                match elem.elem_type {
                  @core.Func | @core.NoFunc => {
                    // Funcref - add funcref tag
                    // Must mask to 62 bits because negative indices (external funcrefs)
                    // would otherwise produce 0xFFFF... which equals NULL
                    let masked = idx.to_int64().reinterpret_as_uint64() &
                      0x3FFFFFFFFFFFFFFFUL
                    masked | 0x4000000000000000UL
                  }
                  @core.Extern | @core.NoExtern => {
                    // Externref - add externref tag
                    let masked = idx.to_int64().reinterpret_as_uint64() &
                      0x3FFFFFFFFFFFFFFFUL
                    masked | 0x2000000000000000UL
                  }
                  _ =>
                    // i31, struct, array, or other GC ref - already encoded
                    idx.to_int64().reinterpret_as_uint64()
                }
              Ref(None) => 0xFFFFFFFFFFFFFFFFUL
              Funcref(Some(idx)) => idx.to_uint64() | 0x4000000000000000UL
              Funcref(None) => 0xFFFFFFFFFFFFFFFFUL
              Externref(Some(idx)) => idx.to_uint64() | 0x2000000000000000UL
              Externref(None) => 0xFFFFFFFFFFFFFFFFUL
              _ =>
                raise RuntimeError::UnsupportedInitExpression(
                  "elem segment init must produce a reference",
                )
            }
            table.data[addr] = ref_val
          }
        }
      }
    }
  }
  // Resolve imported functions - MUST push for every function import
  let imported_funcs : Array[HostFunc] = []
  for imp in m.imports {
    let module_name = imp.module_
    let field_name = imp.name
    match imp.desc {
      Func(_type_idx) =>
        match imports.get_func(module_name, field_name) {
          Some(func) => imported_funcs.push(func)
          None =>
            raise RuntimeError::FunctionNotFound(
              "imported function not found: \{module_name}.\{field_name}",
            )
        }
      Table(_) | Mem(_) | Global(_) | Tag(_) => ()
    }
  }

  // Create data segments for bulk memory operations
  let data_segments : Array[Array[Byte]] = []
  for data in m.datas {
    let segment : Array[Byte] = []
    for i in 0..<data.init.length() {
      segment.push(data.init[i])
    }
    data_segments.push(segment)
  }
  clear_spectest_output()
  let output = get_spectest_output()

  // Compile module to universal IR
  let compiled = @compile.compile(m)

  // Create RuntimeContext with cold data (including gc_heap from const expr evaluation)
  let ctx = RuntimeContext::new_with_gc_heap(
    m,
    memory,
    memory_max_pages,
    globals,
    tables,
    imported_funcs,
    data_segments,
    gc_heap,
    output~,
    compiled~,
    external_funcrefs~,
    dropped_elems~,
  )
  Instance::{
    ops: code_to_ops(compiled.code),
    stack: FixedArray::make(initial_stack_capacity, 0UL),
    sp: 0,
    bp: 0,
    num_locals: 0,
    pc: 0,
    ctx,
  }
}

///|
/// Constant expression evaluator context - holds gc_heap for GC const exprs
priv struct ConstExprContext {
  gc_heap : Array[GcObject]
  module_ : @core.Module?
}

///|
fn eval_const_expr(
  expr : @core.Expr,
  globals : Array[Value],
) -> Value raise RuntimeError {
  // Create empty GC heap for simple cases that don't need it
  let ctx = ConstExprContext::{ gc_heap: [], module_: None }
  eval_const_expr_with_context(expr, globals, ctx)
}

///|
fn eval_const_expr_with_gc(
  expr : @core.Expr,
  globals : Array[Value],
  gc_heap : Array[GcObject],
  module_ : @core.Module,
) -> Value raise RuntimeError {
  let ctx = ConstExprContext::{ gc_heap, module_: Some(module_) }
  eval_const_expr_with_context(expr, globals, ctx)
}

///|
fn eval_const_expr_with_context(
  expr : @core.Expr,
  globals : Array[Value],
  ctx : ConstExprContext,
) -> Value raise RuntimeError {
  // Constant expression evaluator for init expressions
  // Supports multi-instruction expressions (e.g., arithmetic in global inits)
  if expr.instrs.length() == 0 {
    raise RuntimeError::UnsupportedInitExpression("empty init expression")
  }
  let stack : Array[Value] = []
  for instr in expr.instrs {
    match instr {
      I32Const(v) => stack.push(I32(v))
      I64Const(v) => stack.push(I64(v))
      F32Const(v) => stack.push(F32(v))
      F64Const(v) => stack.push(F64(v))
      RefNull(ref_type) =>
        match ref_type {
          @core.Func | @core.NoFunc => stack.push(Funcref(None))
          @core.Extern | @core.NoExtern => stack.push(Externref(None))
          _ => stack.push(Ref(None))
        }
      RefFunc(idx) => stack.push(Ref(Some(idx.reinterpret_as_int())))
      GlobalGet(idx) => {
        let idx_int = idx.reinterpret_as_int()
        guard idx_int >= 0 && idx_int < globals.length() else {
          raise RuntimeError::UnsupportedInitExpression(
            "global index out of bounds in init expression",
          )
        }
        stack.push(globals[idx_int])
      }
      // i32 arithmetic operations
      I32Add => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av + bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.add",
            )
        }
      }
      I32Sub => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av - bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.sub",
            )
        }
      }
      I32Mul => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I32(av), I32(bv)) => stack.push(I32(av * bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i32.mul",
            )
        }
      }
      // i64 arithmetic operations
      I64Add => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av + bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.add",
            )
        }
      }
      I64Sub => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av - bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.sub",
            )
        }
      }
      I64Mul => {
        let b = stack.unsafe_pop()
        let a = stack.unsafe_pop()
        match (a, b) {
          (I64(av), I64(bv)) => stack.push(I64(av * bv))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "type mismatch in i64.mul",
            )
        }
      }
      // GC instructions for constant expressions
      StructNew(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let num_fields = match ctx.module_ {
          Some(m) =>
            match m.types.get(type_idx_int) {
              Some(Struct(s)) => s.fields.length()
              _ => 0
            }
          None => 0
        }
        let fields : Array[UInt64] = Array::make(num_fields, 0UL)
        for i = num_fields - 1; i >= 0; i = i - 1 {
          match stack.unsafe_pop() {
            I32(v) => fields[i] = v.to_uint64()
            I64(v) => fields[i] = v
            F32(v) => fields[i] = v.reinterpret_as_uint().to_uint64()
            F64(v) => fields[i] = v.reinterpret_as_uint64()
            Ref(r) =>
              fields[i] = match r {
                Some(idx) => idx.to_uint64()
                None => 0xFFFFFFFFFFFFFFFFUL
              }
            Funcref(r) =>
              fields[i] = match r {
                Some(idx) => idx.to_uint64() | 0x4000000000000000UL
                None => 0xFFFFFFFFFFFFFFFFUL
              }
            Externref(r) =>
              fields[i] = match r {
                Some(idx) => idx.to_uint64() | 0x2000000000000000UL
                None => 0xFFFFFFFFFFFFFFFFUL
              }
          }
        }
        let obj = GcObject::Struct({ type_idx: type_idx_int, fields })
        ctx.gc_heap.push(obj)
        // Encode as (1-based-index << 1) to distinguish from i31refs
        let ref_value = ctx.gc_heap.length() << 1
        stack.push(Ref(Some(ref_value)))
      }
      StructNewDefault(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let num_fields = match ctx.module_ {
          Some(m) =>
            match m.types.get(type_idx_int) {
              Some(Struct(s)) => s.fields.length()
              _ => 0
            }
          None => 0
        }
        let fields : Array[UInt64] = Array::make(num_fields, 0UL)
        let obj = GcObject::Struct({ type_idx: type_idx_int, fields })
        ctx.gc_heap.push(obj)
        // Encode as (1-based-index << 1) to distinguish from i31refs
        let ref_value = ctx.gc_heap.length() << 1
        stack.push(Ref(Some(ref_value)))
      }
      ArrayNew(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let length = match stack.unsafe_pop() {
          I32(v) => v.reinterpret_as_int()
          _ => 0
        }
        let init_value = match stack.unsafe_pop() {
          I32(v) => v.to_uint64()
          I64(v) => v
          F32(v) => v.reinterpret_as_uint().to_uint64()
          F64(v) => v.reinterpret_as_uint64()
          Ref(r) =>
            match r {
              Some(idx) => idx.to_uint64()
              None => 0xFFFFFFFFFFFFFFFFUL
            }
          Funcref(r) =>
            match r {
              Some(idx) => idx.to_uint64() | 0x4000000000000000UL
              None => 0xFFFFFFFFFFFFFFFFUL
            }
          Externref(r) =>
            match r {
              Some(idx) => idx.to_uint64() | 0x2000000000000000UL
              None => 0xFFFFFFFFFFFFFFFFUL
            }
        }
        let elements = Array::make(length, init_value)
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        // Encode as (1-based-index << 1) to distinguish from i31refs
        let ref_value = ctx.gc_heap.length() << 1
        stack.push(Ref(Some(ref_value)))
      }
      ArrayNewDefault(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let length = match stack.unsafe_pop() {
          I32(v) => v.reinterpret_as_int()
          _ => 0
        }
        // Determine default value based on element type
        // Reference types default to null (0xFFFFFFFFFFFFFFFF)
        let default_value : UInt64 = match ctx.module_ {
          Some(m) =>
            if type_idx_int >= 0 && type_idx_int < m.types.length() {
              match m.types[type_idx_int] {
                Array(arr_type) =>
                  match arr_type.element.storage {
                    I8 | I16 => 0UL
                    Val(I32) | Val(I64) | Val(F32) | Val(F64) | Val(V128) => 0UL
                    Val(_) => 0xFFFFFFFFFFFFFFFFUL // Reference types: null
                  }
                _ => 0UL
              }
            } else {
              0UL
            }
          None => 0UL
        }
        let elements : Array[UInt64] = Array::make(length, default_value)
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        // Encode as (1-based-index << 1) to distinguish from i31refs
        let ref_value = ctx.gc_heap.length() << 1
        stack.push(Ref(Some(ref_value)))
      }
      ArrayNewFixed(type_idx, len) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let length = len.reinterpret_as_int()
        let elements : Array[UInt64] = Array::make(length, 0UL)
        for i = length - 1; i >= 0; i = i - 1 {
          match stack.unsafe_pop() {
            I32(v) => elements[i] = v.to_uint64()
            I64(v) => elements[i] = v
            F32(v) => elements[i] = v.reinterpret_as_uint().to_uint64()
            F64(v) => elements[i] = v.reinterpret_as_uint64()
            Ref(r) =>
              elements[i] = match r {
                Some(idx) => idx.to_uint64()
                None => 0xFFFFFFFFFFFFFFFFUL
              }
            Funcref(r) =>
              elements[i] = match r {
                Some(idx) => idx.to_uint64() | 0x4000000000000000UL
                None => 0xFFFFFFFFFFFFFFFFUL
              }
            Externref(r) =>
              elements[i] = match r {
                Some(idx) => idx.to_uint64() | 0x2000000000000000UL
                None => 0xFFFFFFFFFFFFFFFFUL
              }
          }
        }
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        // Encode as (1-based-index << 1) to distinguish from i31refs
        let ref_value = ctx.gc_heap.length() << 1
        stack.push(Ref(Some(ref_value)))
      }
      RefI31 => {
        let value = match stack.unsafe_pop() {
          I32(v) => v.reinterpret_as_int()
          _ => 0
        }
        // Encode i31ref: (value << 1) | 1
        let i31_value = value & 0x7FFFFFFF
        let encoded = (i31_value << 1) | 1
        stack.push(Ref(Some(encoded)))
      }
      // Reference conversion operations
      ExternConvertAny =>
        // Convert anyref to externref by adding externref tag
        match stack.unsafe_pop() {
          Ref(None) => stack.push(Externref(None)) // null stays null
          Ref(Some(ref_val)) => {
            // Add externref tag (bit 61)
            let tagged = ref_val.to_int64().reinterpret_as_uint64() |
              0x2000000000000000UL
            stack.push(Externref(Some(tagged.reinterpret_as_int64().to_int())))
          }
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "extern.convert_any expects reference on stack",
            )
        }
      AnyConvertExtern =>
        // Convert externref to anyref - value keeps its externref tag
        // so it can still be identified as an "internalized externref"
        match stack.unsafe_pop() {
          Externref(None) => stack.push(Ref(None)) // null stays null
          Externref(Some(ref_val)) =>
            // Keep the value as-is (it already has the externref tag from Externref encoding)
            // Just wrap it as Ref so it's typed as anyref
            stack.push(Ref(Some(ref_val)))
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "any.convert_extern expects reference on stack",
            )
        }
      _ =>
        raise RuntimeError::UnsupportedInitExpression(
          "unsupported init expression instruction: \{instr}",
        )
    }
  }
  guard stack.length() == 1 else {
    raise RuntimeError::UnsupportedInitExpression(
      "init expression should produce exactly one value",
    )
  }
  stack[0]
}
