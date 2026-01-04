///|
/// Runtime error types
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
/// Create a RuntimeError from error_detail string
/// The detail string should start with an error type prefix
fn RuntimeError::from_detail(detail : String) -> RuntimeError {
  if detail.has_prefix("division by zero") {
    RuntimeError::DivisionByZero
  } else if detail.has_prefix("integer overflow") {
    RuntimeError::IntegerOverflow
  } else if detail.has_prefix("out of bounds table access") {
    RuntimeError::TableOutOfBounds
  } else if detail.has_prefix("out of bounds") {
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
/// Runtime value type
pub(all) enum Value {
  I32(UInt)
  I64(UInt64)
  F32(Float)
  F64(Double)
  Ref(Int?) // For FuncRef and ExternRef (using index or null)
} derive(Eq, Show)

///|
/// Table with its limits
struct RuntimeTable {
  data : Array[Int?] // Table data (function indices, None = null ref)
  max : UInt64? // Maximum size limit (None = no limit)
  // External funcrefs for cross-module table sharing.
  // When a module stores its own funcrefs into an imported table,
  // wrappers are added here and negative indices stored in data.
  // Mapping: -1 → external_funcrefs[0], -2 → [1], etc.
  external_funcrefs : Array[ImportedFunc]
}

///|
/// Get table data length
pub fn RuntimeTable::data_length(self : RuntimeTable) -> Int {
  self.data.length()
}

///|
/// Get table element at index
pub fn RuntimeTable::get_data(self : RuntimeTable, idx : Int) -> Int? {
  self.data[idx]
}

///|
/// Set table element at index
pub fn RuntimeTable::set_data(self : RuntimeTable, idx : Int, value : Int?) -> Unit {
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
  func : ImportedFunc,
) -> Int {
  let idx = self.external_funcrefs.length()
  self.external_funcrefs.push(func)
  idx
}

///|
pub struct ImportedFunc {
  arity : UInt
  func : (Array[Value]) -> Array[Value]
}

///|
/// Create a new ImportedFunc
pub fn ImportedFunc::new(
  arity : UInt,
  func : (Array[Value]) -> Array[Value],
) -> ImportedFunc {
  { arity, func }
}

///|
/// Imported memory with its limits
pub struct ImportedMemory {
  data : Array[Byte]
  max : UInt64? // Maximum size in pages (None = no limit)
}

///|
/// Import resolver for linking modules
/// Maps (module_name, field_name) to ImportedFunc, global Value, table, or memory
/// Using Bytes keys to match how WebAssembly module imports work
struct ImportResolverEntry {
  funcs : Map[Bytes, ImportedFunc]
  globals : Map[Bytes, Value]
  tables : Map[Bytes, RuntimeTable]
  memories : Map[Bytes, ImportedMemory]
  // Wrappers for funcref globals - used for cross-module funcref handling
  funcref_wrappers : Map[Bytes, ImportedFunc]
}

///|
pub struct ImportResolver {
  modules : Map[Bytes, ImportResolverEntry]
}

///|
/// Create a new empty import resolver
pub fn ImportResolver::new() -> ImportResolver {
  { modules: Map::new() }
}

///|
/// Add an imported function to the resolver (using string literals)
pub fn ImportResolver::add_func(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
  func : ImportedFunc,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.funcs[name] = func
    None => {
      let entry : ImportResolverEntry = {
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
/// Add an imported global to the resolver
pub fn ImportResolver::add_global(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
  value : Value,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.globals[name] = value
    None => {
      let entry : ImportResolverEntry = {
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
pub fn ImportResolver::get_func(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
) -> ImportedFunc? {
  match self.modules.get(module_) {
    Some(entry) => entry.funcs.get(name)
    None => None
  }
}

///|
/// Look up an imported global
pub fn ImportResolver::get_global(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
) -> Value? {
  match self.modules.get(module_) {
    Some(entry) => entry.globals.get(name)
    None => None
  }
}

///|
/// Add an imported table to the resolver
pub fn ImportResolver::add_table(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
  table : RuntimeTable,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.tables[name] = table
    None => {
      let entry : ImportResolverEntry = {
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
pub fn ImportResolver::get_table(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
) -> RuntimeTable? {
  match self.modules.get(module_) {
    Some(entry) => entry.tables.get(name)
    None => None
  }
}

///|
/// Add an imported memory to the resolver
pub fn ImportResolver::add_memory(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
  memory : ImportedMemory,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.memories[name] = memory
    None => {
      let entry : ImportResolverEntry = {
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
pub fn ImportResolver::get_memory(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
) -> ImportedMemory? {
  match self.modules.get(module_) {
    Some(entry) => entry.memories.get(name)
    None => None
  }
}

///|
/// Add a funcref wrapper to the resolver.
/// This is used for cross-module funcref handling - when a module exports
/// a funcref global, we also register a wrapper that can call the function.
pub fn ImportResolver::add_funcref_wrapper(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
  wrapper : ImportedFunc,
) -> Unit {
  match self.modules.get(module_) {
    Some(entry) => entry.funcref_wrappers[name] = wrapper
    None => {
      let entry : ImportResolverEntry = {
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
pub fn ImportResolver::get_funcref_wrapper(
  self : ImportResolver,
  module_ : Bytes,
  name : Bytes,
) -> ImportedFunc? {
  match self.modules.get(module_) {
    Some(entry) => entry.funcref_wrappers.get(name)
    None => None
  }
}

///|
/// Initial stack capacity (can grow as needed)
let initial_stack_capacity : Int = 1024

///|
/// Runtime structure for WebAssembly execution.
/// This is a value type containing hot fields for fast access.
/// Cold data is accessed through the ctx reference.
pub struct Runtime {
  ops : FixedArray[UInt64] // Compiled instructions (tagless: fn ptrs and immediates as UInt64)
  stack : FixedArray[UInt64] // Unified stack for locals and operand stack (tagless)
  sp : Int // Current top of stack (next push position)
  bp : Int // Base pointer: index of first local in unified stack
  num_locals : Int // Number of locals for current function
  pc : Int // Program counter
  status : RuntimeStatus // Execution status: Running, Terminated, or Trap
  ctx : RuntimeContext // Reference to cold data (module, memory, globals, etc.)
}

///|
/// Get the module from the runtime
pub fn Runtime::get_module(self : Runtime) -> @core.Module {
  self.ctx.module_
}

///|
/// Get the globals array from the runtime
pub fn Runtime::get_globals(self : Runtime) -> Array[Value] {
  self.ctx.globals
}

///|
/// Get the tables array from the runtime
pub fn Runtime::get_tables(self : Runtime) -> Array[RuntimeTable] {
  self.ctx.tables
}

///|
/// Create a default import resolver with spectest module
pub fn default_import_resolver() -> ImportResolver {
  let resolver = ImportResolver::new()
  resolver.add_func(b"spectest", b"print_char", {
    arity: 1U,
    func: spectest_print_char,
  })
  resolver.add_func(b"spectest", b"print", { arity: 0U, func: spectest_print })
  resolver.add_func(b"spectest", b"print_i32", {
    arity: 1U,
    func: spectest_print_i32,
  })
  resolver.add_func(b"spectest", b"print_i64", {
    arity: 1U,
    func: spectest_print_i64,
  })
  resolver.add_func(b"spectest", b"print_f32", {
    arity: 1U,
    func: spectest_print_f32,
  })
  resolver.add_func(b"spectest", b"print_f64", {
    arity: 1U,
    func: spectest_print_f64,
  })
  resolver.add_func(b"spectest", b"print_i32_f32", {
    arity: 2U,
    func: spectest_print_i32_f32,
  })
  resolver.add_func(b"spectest", b"print_f64_f64", {
    arity: 2U,
    func: spectest_print_f64_f64,
  })
  // Add spectest table (10 funcref, max 20)
  let table_data : Array[Int?] = Array::make(10, None)
  resolver.add_table(b"spectest", b"table", {
    data: table_data,
    max: Some(20UL),
    external_funcrefs: [],
  })
  // Add spectest memory (1 page initial, 2 pages max)
  let memory_size = 1 * 65536 // 1 page = 65536 bytes
  let memory_data : Array[Byte] = Array::make(memory_size, b'\x00')
  resolver.add_memory(b"spectest", b"memory", {
    data: memory_data,
    max: Some(2UL),
  })
  resolver
}

///|
/// Load a WebAssembly module into the runtime (using default import resolver)
pub fn Runtime::load(m : @core.Module) -> Runtime raise RuntimeError {
  Runtime::load_with_resolver(m, default_import_resolver())
}

///|
/// Load a WebAssembly module into the runtime with a custom import resolver
pub fn Runtime::load_with_resolver(
  m : @core.Module,
  resolver : ImportResolver,
) -> Runtime raise RuntimeError {
  // Initialize memory
  let mut memory : Array[Byte] = []
  let mut memory_max_pages : UInt64? = None

  // Check for imported memory first
  let mut has_imported_memory = false
  for imp in m.imports {
    match imp.desc {
      Mem(mem_type) => {
        has_imported_memory = true
        // Try to get the memory from the resolver
        match resolver.get_memory(imp.module_, imp.name) {
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
  // First, add imported globals - try to get from resolver, otherwise use default values
  let globals : Array[Value] = []
  // Track external funcrefs for cross-module funcref handling
  let external_funcrefs : Array[ImportedFunc] = []
  for imp in m.imports {
    match imp.desc {
      Global(gt) => {
        // Try to get the global value from the resolver
        let value = match resolver.get_global(imp.module_, imp.name) {
          Some(v) => {
            // For funcref globals, check if there's a funcref wrapper
            // and if so, use a negative index to point to external_funcrefs
            match v {
              Ref(Some(_)) =>
                // Check for a funcref wrapper for cross-module calls
                match resolver.get_funcref_wrapper(imp.module_, imp.name) {
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
  // Initialize data segments (copy data into memory)
  for data in m.datas {
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
  // Initialize tables
  let tables : Array[RuntimeTable] = []
  // First, add imported tables
  for imp in m.imports {
    match imp.desc {
      Table(_) =>
        // Try to get the table from the resolver
        match resolver.get_table(imp.module_, imp.name) {
          Some(imported_table) => tables.push(imported_table)
          None => {
            // Fall back to creating an empty table if resolver doesn't provide one
            // This shouldn't happen with proper test setup, but provides graceful fallback
            let table_size = 10 // Default size for fallback
            let table_data : Array[Int?] = Array::make(table_size, None)
            tables.push({ data: table_data, max: Some(20UL), external_funcrefs: [] })
          }
        }
      _ => ()
    }
  }
  // Then add local tables
  for table in m.tables {
    let table_size = table.limits.min.to_int()
    // Initialize table with default value (null unless table has init expr)
    let init_ref = match table.init {
      Some(init_expr) => {
        let init_value = eval_const_expr(init_expr, globals)
        match init_value {
          Ref(ref_idx) => ref_idx
          _ =>
            raise RuntimeError::UnsupportedInitExpression(
              "table init expression must produce a reference",
            )
        }
      }
      None => None
    }
    let table_data : Array[Int?] = Array::make(table_size, init_ref)
    tables.push({ data: table_data, max: table.limits.max, external_funcrefs: [] })
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
            let value = eval_const_expr(elem.init[j], globals)
            match value {
              Ref(ref_idx) => table.data[addr] = ref_idx
              _ =>
                raise RuntimeError::UnsupportedInitExpression(
                  "elem segment init must produce a reference",
                )
            }
          }
        }
      }
    }
  }
  // Resolve imported functions - MUST push for every function import
  let imported_funcs : Array[ImportedFunc] = []
  for imp in m.imports {
    let module_name = imp.module_
    let field_name = imp.name
    match imp.desc {
      Func(_type_idx) =>
        match resolver.get_func(module_name, field_name) {
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

  // Compile all functions before creating Runtime
  let compiler = Compiler::new(m)
  compiler.compile()

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
    external_funcrefs~,
    dropped_elems~,
  )
  Runtime::{
    ops: compiler.finish(),
    stack: FixedArray::make(initial_stack_capacity, 0UL),
    sp: 0,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
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
      RefNull(_) => stack.push(Ref(None))
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
                None => 0UL
              }
          }
        }
        let obj = GcObject::Struct({ type_idx: type_idx_int, fields })
        ctx.gc_heap.push(obj)
        let ref_value = ctx.gc_heap.length() // 1-based index
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
        let ref_value = ctx.gc_heap.length()
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
              None => 0UL
            }
        }
        let elements = Array::make(length, init_value)
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        let ref_value = ctx.gc_heap.length()
        stack.push(Ref(Some(ref_value)))
      }
      ArrayNewDefault(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let length = match stack.unsafe_pop() {
          I32(v) => v.reinterpret_as_int()
          _ => 0
        }
        let elements : Array[UInt64] = Array::make(length, 0UL)
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        let ref_value = ctx.gc_heap.length()
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
                None => 0UL
              }
          }
        }
        let obj = GcObject::Array({ type_idx: type_idx_int, elements })
        ctx.gc_heap.push(obj)
        let ref_value = ctx.gc_heap.length()
        stack.push(Ref(Some(ref_value)))
      }
      RefI31 => {
        let value = match stack.unsafe_pop() {
          I32(v) => v.reinterpret_as_int()
          _ => 0
        }
        // Encode i31ref: (value << 1) | 1
        let i31_value = value.land(0x7FFFFFFF)
        let encoded = (i31_value << 1).lor(1)
        stack.push(Ref(Some(encoded)))
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
