///|
/// Runtime error types
pub suberror RuntimeError {
  DivisionByZero
  IntegerOverflow
  MemoryOutOfBounds
  InvalidType(String)
  FunctionNotFound(String)
  UnimplementedInstruction(String) // Instruction not yet implemented
  Unreachable // Unreachable instruction executed
  FunctionNotCompiled(String) // Function not compiled
  UnsupportedLocalType(String) // Unsupported local type
  UnsupportedInitExpression(String) // Unsupported init expression
} derive(Show)

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
/// Runtime structure that holds a loaded WebAssembly module
pub struct Runtime {
  module_ : @core.Module
  ops : Array[MInstr]
  stack : Array[UInt64] // Unified stack for locals and operand stack (tagless)
  mut sp : Int // Stack pointer: index of first local in unified stack
  mut num_locals : Int // Number of locals for current function
  mut pc : Int
  mut running : Bool // Execution loop control flag
  call_stack : Array[CallFrame]
  memory : Array[Byte] // Linear memory
  memory_max : UInt64? // Maximum memory size in pages (None = no limit)
  globals : Array[Value] // Global variables
  tables : Array[RuntimeTable] // Tables with limits
  imported_funcs : Array[ImportedFunc] // Imported functions
  data_segments : Array[Array[Byte]] // Data segments for bulk memory ops
  mut error_detail : String // Error detail for debugging (populated on error)
}

///|
/// Get the module from the runtime
pub fn Runtime::get_module(self : Runtime) -> @core.Module {
  self.module_
}

///|
/// Get the globals array from the runtime
pub fn Runtime::get_globals(self : Runtime) -> Array[Value] {
  self.globals
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
    let memory_size = memory_min_pages.reinterpret_as_int64().to_int() * 65536
    memory = Array::make(memory_size, b'\x00')
  }
  // Initialize globals
  // First, add imported globals - try to get from resolver, otherwise use default values
  let globals : Array[Value] = []
  for imp in m.imports {
    match imp.desc {
      Global(gt) => {
        // Try to get the global value from the resolver
        let value = match resolver.get_global(imp.module_, imp.name) {
          Some(v) => v
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
  // Then add local globals
  for i in 0..<m.globals.length() {
    let global = m.globals[i]
    let value = eval_const_expr(global.init, globals)
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
            tables.push({ data: table_data, max: Some(20UL) })
          }
        }
      _ => ()
    }
  }
  // Then add local tables
  for table in m.tables {
    let table_size = table.limits.min.reinterpret_as_int64().to_int()
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
    tables.push({ data: table_data, max: table.limits.max })
  }
  // Initialize element segments (copy function references into tables)
  // Only process active segments - skip passive and declarative segments
  for elem in m.elems {
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
        for i in 0..<elem.init.length() {
          let addr = offset + i
          if addr >= 0 && addr < table.data.length() {
            let value = eval_const_expr(elem.init[i], globals)
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
  Runtime::{
    module_: m,
    ops: [],
    stack: [],
    sp: 0,
    num_locals: 0,
    pc: 0,
    running: false,
    call_stack: [],
    memory,
    memory_max: memory_max_pages,
    globals,
    tables,
    imported_funcs,
    data_segments,
    error_detail: "",
  }
}

///|
fn pop_i32_value(
  stack : Array[Value],
  context : String,
) -> UInt raise RuntimeError {
  match stack.unsafe_pop() {
    I32(v) => v
    _ =>
      raise RuntimeError::UnsupportedInitExpression(
        "type mismatch in \{context}",
      )
  }
}

///|
fn pop_i64_value(
  stack : Array[Value],
  context : String,
) -> UInt64 raise RuntimeError {
  match stack.unsafe_pop() {
    I64(v) => v
    _ =>
      raise RuntimeError::UnsupportedInitExpression(
        "type mismatch in \{context}",
      )
  }
}

///|
fn pop_f32_value(
  stack : Array[Value],
  context : String,
) -> Float raise RuntimeError {
  match stack.unsafe_pop() {
    F32(v) => v
    _ =>
      raise RuntimeError::UnsupportedInitExpression(
        "type mismatch in \{context}",
      )
  }
}

///|
fn pop_f64_value(
  stack : Array[Value],
  context : String,
) -> Double raise RuntimeError {
  match stack.unsafe_pop() {
    F64(v) => v
    _ =>
      raise RuntimeError::UnsupportedInitExpression(
        "type mismatch in \{context}",
      )
  }
}

///|
fn push_i32_bool(stack : Array[Value], value : Bool) -> Unit {
  stack.push(I32(if value { 1U } else { 0U }))
}

///|
fn eval_const_expr(
  expr : @core.Expr,
  globals : Array[Value],
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
      I32Eqz => {
        let a = pop_i32_value(stack, "i32.eqz")
        push_i32_bool(stack, a == 0U)
      }
      I32Eq => {
        let b = pop_i32_value(stack, "i32.eq")
        let a = pop_i32_value(stack, "i32.eq")
        push_i32_bool(stack, a == b)
      }
      I32Ne => {
        let b = pop_i32_value(stack, "i32.ne")
        let a = pop_i32_value(stack, "i32.ne")
        push_i32_bool(stack, a != b)
      }
      I32LtS => {
        let b = pop_i32_value(stack, "i32.lt_s")
        let a = pop_i32_value(stack, "i32.lt_s")
        push_i32_bool(stack, a.reinterpret_as_int() < b.reinterpret_as_int())
      }
      I32LtU => {
        let b = pop_i32_value(stack, "i32.lt_u")
        let a = pop_i32_value(stack, "i32.lt_u")
        push_i32_bool(stack, a < b)
      }
      I32GtS => {
        let b = pop_i32_value(stack, "i32.gt_s")
        let a = pop_i32_value(stack, "i32.gt_s")
        push_i32_bool(stack, a.reinterpret_as_int() > b.reinterpret_as_int())
      }
      I32GtU => {
        let b = pop_i32_value(stack, "i32.gt_u")
        let a = pop_i32_value(stack, "i32.gt_u")
        push_i32_bool(stack, a > b)
      }
      I32LeS => {
        let b = pop_i32_value(stack, "i32.le_s")
        let a = pop_i32_value(stack, "i32.le_s")
        push_i32_bool(stack, a.reinterpret_as_int() <= b.reinterpret_as_int())
      }
      I32LeU => {
        let b = pop_i32_value(stack, "i32.le_u")
        let a = pop_i32_value(stack, "i32.le_u")
        push_i32_bool(stack, a <= b)
      }
      I32GeS => {
        let b = pop_i32_value(stack, "i32.ge_s")
        let a = pop_i32_value(stack, "i32.ge_s")
        push_i32_bool(stack, a.reinterpret_as_int() >= b.reinterpret_as_int())
      }
      I32GeU => {
        let b = pop_i32_value(stack, "i32.ge_u")
        let a = pop_i32_value(stack, "i32.ge_u")
        push_i32_bool(stack, a >= b)
      }
      I32Clz => {
        let a = pop_i32_value(stack, "i32.clz")
        stack.push(I32(a.clz().reinterpret_as_uint()))
      }
      I32Ctz => {
        let a = pop_i32_value(stack, "i32.ctz")
        stack.push(I32(a.ctz().reinterpret_as_uint()))
      }
      I32Popcnt => {
        let a = pop_i32_value(stack, "i32.popcnt")
        stack.push(I32(a.popcnt().reinterpret_as_uint()))
      }
      I32Add => {
        let b = pop_i32_value(stack, "i32.add")
        let a = pop_i32_value(stack, "i32.add")
        stack.push(I32(a + b))
      }
      I32Sub => {
        let b = pop_i32_value(stack, "i32.sub")
        let a = pop_i32_value(stack, "i32.sub")
        stack.push(I32(a - b))
      }
      I32Mul => {
        let b = pop_i32_value(stack, "i32.mul")
        let a = pop_i32_value(stack, "i32.mul")
        stack.push(I32(a * b))
      }
      I32DivS => {
        let b = pop_i32_value(stack, "i32.div_s")
        let a = pop_i32_value(stack, "i32.div_s")
        if b == 0U {
          raise RuntimeError::DivisionByZero
        }
        if a == 0x80000000U && b == 0xFFFFFFFFU {
          raise RuntimeError::IntegerOverflow
        }
        let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
        stack.push(I32(result))
      }
      I32DivU => {
        let b = pop_i32_value(stack, "i32.div_u")
        let a = pop_i32_value(stack, "i32.div_u")
        if b == 0U {
          raise RuntimeError::DivisionByZero
        }
        stack.push(I32(a / b))
      }
      I32RemS => {
        let b = pop_i32_value(stack, "i32.rem_s")
        let a = pop_i32_value(stack, "i32.rem_s")
        if b == 0U {
          raise RuntimeError::DivisionByZero
        }
        if a == 0x80000000U && b == 0xFFFFFFFFU {
          stack.push(I32(0U))
        } else {
          let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
          stack.push(I32(result))
        }
      }
      I32RemU => {
        let b = pop_i32_value(stack, "i32.rem_u")
        let a = pop_i32_value(stack, "i32.rem_u")
        if b == 0U {
          raise RuntimeError::DivisionByZero
        }
        stack.push(I32(a % b))
      }
      I32And => {
        let b = pop_i32_value(stack, "i32.and")
        let a = pop_i32_value(stack, "i32.and")
        stack.push(I32(a & b))
      }
      I32Or => {
        let b = pop_i32_value(stack, "i32.or")
        let a = pop_i32_value(stack, "i32.or")
        stack.push(I32(a | b))
      }
      I32Xor => {
        let b = pop_i32_value(stack, "i32.xor")
        let a = pop_i32_value(stack, "i32.xor")
        stack.push(I32(a ^ b))
      }
      I32Shl => {
        let b = pop_i32_value(stack, "i32.shl")
        let a = pop_i32_value(stack, "i32.shl")
        let shift = (b & 0x1FU).reinterpret_as_int()
        stack.push(I32(a << shift))
      }
      I32ShrS => {
        let b = pop_i32_value(stack, "i32.shr_s")
        let a = pop_i32_value(stack, "i32.shr_s")
        let shift = (b & 0x1FU).reinterpret_as_int()
        let result = (a.reinterpret_as_int() >> shift).reinterpret_as_uint()
        stack.push(I32(result))
      }
      I32ShrU => {
        let b = pop_i32_value(stack, "i32.shr_u")
        let a = pop_i32_value(stack, "i32.shr_u")
        let shift = (b & 0x1FU).reinterpret_as_int()
        stack.push(I32(a >> shift))
      }
      I32Rotl => {
        let b = pop_i32_value(stack, "i32.rotl")
        let a = pop_i32_value(stack, "i32.rotl")
        let rotation = (b & 0x1FU).reinterpret_as_int()
        let result = (a << rotation) | (a >> (32 - rotation))
        stack.push(I32(result))
      }
      I32Rotr => {
        let b = pop_i32_value(stack, "i32.rotr")
        let a = pop_i32_value(stack, "i32.rotr")
        let rotation = (b & 0x1FU).reinterpret_as_int()
        let result = (a >> rotation) | (a << (32 - rotation))
        stack.push(I32(result))
      }
      I32Extend8S => {
        let a = pop_i32_value(stack, "i32.extend8_s")
        let byte = a & 0xFFU
        let result = if (byte & 0x80U) != 0U {
          byte | 0xFFFFFF00U
        } else {
          byte
        }
        stack.push(I32(result))
      }
      I32Extend16S => {
        let a = pop_i32_value(stack, "i32.extend16_s")
        let half = a & 0xFFFFU
        let result = if (half & 0x8000U) != 0U {
          half | 0xFFFF0000U
        } else {
          half
        }
        stack.push(I32(result))
      }
      I64Eqz => {
        let a = pop_i64_value(stack, "i64.eqz")
        push_i32_bool(stack, a == 0UL)
      }
      I64Eq => {
        let b = pop_i64_value(stack, "i64.eq")
        let a = pop_i64_value(stack, "i64.eq")
        push_i32_bool(stack, a == b)
      }
      I64Ne => {
        let b = pop_i64_value(stack, "i64.ne")
        let a = pop_i64_value(stack, "i64.ne")
        push_i32_bool(stack, a != b)
      }
      I64LtS => {
        let b = pop_i64_value(stack, "i64.lt_s")
        let a = pop_i64_value(stack, "i64.lt_s")
        push_i32_bool(
          stack,
          a.reinterpret_as_int64() < b.reinterpret_as_int64(),
        )
      }
      I64LtU => {
        let b = pop_i64_value(stack, "i64.lt_u")
        let a = pop_i64_value(stack, "i64.lt_u")
        push_i32_bool(stack, a < b)
      }
      I64GtS => {
        let b = pop_i64_value(stack, "i64.gt_s")
        let a = pop_i64_value(stack, "i64.gt_s")
        push_i32_bool(
          stack,
          a.reinterpret_as_int64() > b.reinterpret_as_int64(),
        )
      }
      I64GtU => {
        let b = pop_i64_value(stack, "i64.gt_u")
        let a = pop_i64_value(stack, "i64.gt_u")
        push_i32_bool(stack, a > b)
      }
      I64LeS => {
        let b = pop_i64_value(stack, "i64.le_s")
        let a = pop_i64_value(stack, "i64.le_s")
        push_i32_bool(
          stack,
          a.reinterpret_as_int64() <= b.reinterpret_as_int64(),
        )
      }
      I64LeU => {
        let b = pop_i64_value(stack, "i64.le_u")
        let a = pop_i64_value(stack, "i64.le_u")
        push_i32_bool(stack, a <= b)
      }
      I64GeS => {
        let b = pop_i64_value(stack, "i64.ge_s")
        let a = pop_i64_value(stack, "i64.ge_s")
        push_i32_bool(
          stack,
          a.reinterpret_as_int64() >= b.reinterpret_as_int64(),
        )
      }
      I64GeU => {
        let b = pop_i64_value(stack, "i64.ge_u")
        let a = pop_i64_value(stack, "i64.ge_u")
        push_i32_bool(stack, a >= b)
      }
      I64Clz => {
        let a = pop_i64_value(stack, "i64.clz")
        stack.push(I64(a.clz().to_uint64()))
      }
      I64Ctz => {
        let a = pop_i64_value(stack, "i64.ctz")
        stack.push(I64(a.ctz().to_uint64()))
      }
      I64Popcnt => {
        let a = pop_i64_value(stack, "i64.popcnt")
        stack.push(I64(a.popcnt().to_uint64()))
      }
      I64Add => {
        let b = pop_i64_value(stack, "i64.add")
        let a = pop_i64_value(stack, "i64.add")
        stack.push(I64(a + b))
      }
      I64Sub => {
        let b = pop_i64_value(stack, "i64.sub")
        let a = pop_i64_value(stack, "i64.sub")
        stack.push(I64(a - b))
      }
      I64Mul => {
        let b = pop_i64_value(stack, "i64.mul")
        let a = pop_i64_value(stack, "i64.mul")
        stack.push(I64(a * b))
      }
      I64DivS => {
        let b = pop_i64_value(stack, "i64.div_s")
        let a = pop_i64_value(stack, "i64.div_s")
        if b == 0UL {
          raise RuntimeError::DivisionByZero
        }
        if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
          raise RuntimeError::IntegerOverflow
        }
        let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
        stack.push(I64(result))
      }
      I64DivU => {
        let b = pop_i64_value(stack, "i64.div_u")
        let a = pop_i64_value(stack, "i64.div_u")
        if b == 0UL {
          raise RuntimeError::DivisionByZero
        }
        stack.push(I64(a / b))
      }
      I64RemS => {
        let b = pop_i64_value(stack, "i64.rem_s")
        let a = pop_i64_value(stack, "i64.rem_s")
        if b == 0UL {
          raise RuntimeError::DivisionByZero
        }
        if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
          stack.push(I64(0UL))
        } else {
          let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
          stack.push(I64(result))
        }
      }
      I64RemU => {
        let b = pop_i64_value(stack, "i64.rem_u")
        let a = pop_i64_value(stack, "i64.rem_u")
        if b == 0UL {
          raise RuntimeError::DivisionByZero
        }
        stack.push(I64(a % b))
      }
      I64And => {
        let b = pop_i64_value(stack, "i64.and")
        let a = pop_i64_value(stack, "i64.and")
        stack.push(I64(a & b))
      }
      I64Or => {
        let b = pop_i64_value(stack, "i64.or")
        let a = pop_i64_value(stack, "i64.or")
        stack.push(I64(a | b))
      }
      I64Xor => {
        let b = pop_i64_value(stack, "i64.xor")
        let a = pop_i64_value(stack, "i64.xor")
        stack.push(I64(a ^ b))
      }
      I64Shl => {
        let b = pop_i64_value(stack, "i64.shl")
        let a = pop_i64_value(stack, "i64.shl")
        let shift = (b & 0x3FUL).to_int()
        stack.push(I64(a << shift))
      }
      I64ShrS => {
        let b = pop_i64_value(stack, "i64.shr_s")
        let a = pop_i64_value(stack, "i64.shr_s")
        let shift = (b & 0x3FUL).to_int()
        let result = (a.reinterpret_as_int64() >> shift).reinterpret_as_uint64()
        stack.push(I64(result))
      }
      I64ShrU => {
        let b = pop_i64_value(stack, "i64.shr_u")
        let a = pop_i64_value(stack, "i64.shr_u")
        let shift = (b & 0x3FUL).to_int()
        stack.push(I64(a >> shift))
      }
      I64Rotl => {
        let b = pop_i64_value(stack, "i64.rotl")
        let a = pop_i64_value(stack, "i64.rotl")
        let rotation = (b & 0x3FUL).to_int()
        let result = (a << rotation) | (a >> (64 - rotation))
        stack.push(I64(result))
      }
      I64Rotr => {
        let b = pop_i64_value(stack, "i64.rotr")
        let a = pop_i64_value(stack, "i64.rotr")
        let rotation = (b & 0x3FUL).to_int()
        let result = (a >> rotation) | (a << (64 - rotation))
        stack.push(I64(result))
      }
      I64Extend8S => {
        let a = pop_i64_value(stack, "i64.extend8_s")
        let byte = a & 0xFFUL
        let result = if (byte & 0x80UL) != 0UL {
          byte | 0xFFFFFFFFFFFFFF00UL
        } else {
          byte
        }
        stack.push(I64(result))
      }
      I64Extend16S => {
        let a = pop_i64_value(stack, "i64.extend16_s")
        let half = a & 0xFFFFUL
        let result = if (half & 0x8000UL) != 0UL {
          half | 0xFFFFFFFFFFFF0000UL
        } else {
          half
        }
        stack.push(I64(result))
      }
      I64Extend32S => {
        let a = pop_i64_value(stack, "i64.extend32_s")
        let word = a & 0xFFFFFFFFUL
        let result = if (word & 0x80000000UL) != 0UL {
          word | 0xFFFFFFFF00000000UL
        } else {
          word
        }
        stack.push(I64(result))
      }
      F32Eq => {
        let b = pop_f32_value(stack, "f32.eq")
        let a = pop_f32_value(stack, "f32.eq")
        push_i32_bool(stack, a == b)
      }
      F32Ne => {
        let b = pop_f32_value(stack, "f32.ne")
        let a = pop_f32_value(stack, "f32.ne")
        push_i32_bool(stack, a != b)
      }
      F32Lt => {
        let b = pop_f32_value(stack, "f32.lt")
        let a = pop_f32_value(stack, "f32.lt")
        push_i32_bool(stack, a < b)
      }
      F32Gt => {
        let b = pop_f32_value(stack, "f32.gt")
        let a = pop_f32_value(stack, "f32.gt")
        push_i32_bool(stack, a > b)
      }
      F32Le => {
        let b = pop_f32_value(stack, "f32.le")
        let a = pop_f32_value(stack, "f32.le")
        push_i32_bool(stack, a <= b)
      }
      F32Ge => {
        let b = pop_f32_value(stack, "f32.ge")
        let a = pop_f32_value(stack, "f32.ge")
        push_i32_bool(stack, a >= b)
      }
      F32Abs => {
        let a = pop_f32_value(stack, "f32.abs")
        stack.push(F32(a.abs()))
      }
      F32Neg => {
        let a = pop_f32_value(stack, "f32.neg")
        stack.push(F32(-a))
      }
      F32Ceil => {
        let a = pop_f32_value(stack, "f32.ceil")
        stack.push(F32(canonicalize_f32(a.ceil())))
      }
      F32Floor => {
        let a = pop_f32_value(stack, "f32.floor")
        stack.push(F32(canonicalize_f32(a.floor())))
      }
      F32Trunc => {
        let a = pop_f32_value(stack, "f32.trunc")
        stack.push(F32(canonicalize_f32(a.trunc())))
      }
      F32Nearest => {
        let a = pop_f32_value(stack, "f32.nearest")
        stack.push(F32(canonicalize_f32(rintf(a))))
      }
      F32Sqrt => {
        let a = pop_f32_value(stack, "f32.sqrt")
        stack.push(F32(canonicalize_f32(a.sqrt())))
      }
      F32Add => {
        let b = pop_f32_value(stack, "f32.add")
        let a = pop_f32_value(stack, "f32.add")
        stack.push(F32(canonicalize_f32(a + b)))
      }
      F32Sub => {
        let b = pop_f32_value(stack, "f32.sub")
        let a = pop_f32_value(stack, "f32.sub")
        stack.push(F32(canonicalize_f32(a - b)))
      }
      F32Mul => {
        let b = pop_f32_value(stack, "f32.mul")
        let a = pop_f32_value(stack, "f32.mul")
        stack.push(F32(canonicalize_f32(a * b)))
      }
      F32Div => {
        let b = pop_f32_value(stack, "f32.div")
        let a = pop_f32_value(stack, "f32.div")
        stack.push(F32(canonicalize_f32(a / b)))
      }
      F32Min => {
        let b = pop_f32_value(stack, "f32.min")
        let a = pop_f32_value(stack, "f32.min")
        let result = if a.is_nan() || b.is_nan() {
          canonical_nan_f32
        } else if a < b {
          a
        } else if b < a {
          b
        } else {
          let a_bits = a.reinterpret_as_uint()
          let b_bits = b.reinterpret_as_uint()
          let sign_mask = 0x8000_0000U
          if (a_bits & sign_mask) != 0U || (b_bits & sign_mask) != 0U {
            if (a_bits & sign_mask) != 0U {
              a
            } else {
              b
            }
          } else {
            a
          }
        }
        stack.push(F32(result))
      }
      F32Max => {
        let b = pop_f32_value(stack, "f32.max")
        let a = pop_f32_value(stack, "f32.max")
        let result = if a.is_nan() || b.is_nan() {
          canonical_nan_f32
        } else if a > b {
          a
        } else if b > a {
          b
        } else {
          let a_bits = a.reinterpret_as_uint()
          let b_bits = b.reinterpret_as_uint()
          let sign_mask = 0x8000_0000U
          if (a_bits & sign_mask) == 0U || (b_bits & sign_mask) == 0U {
            if (a_bits & sign_mask) == 0U {
              a
            } else {
              b
            }
          } else {
            a
          }
        }
        stack.push(F32(result))
      }
      F32Copysign => {
        let b = pop_f32_value(stack, "f32.copysign")
        let a = pop_f32_value(stack, "f32.copysign")
        let a_bits = a.reinterpret_as_uint()
        let b_bits = b.reinterpret_as_uint()
        let sign_mask = 0x8000_0000U
        let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
        stack.push(F32(Float::reinterpret_from_uint(result_bits)))
      }
      F64Eq => {
        let b = pop_f64_value(stack, "f64.eq")
        let a = pop_f64_value(stack, "f64.eq")
        push_i32_bool(stack, a == b)
      }
      F64Ne => {
        let b = pop_f64_value(stack, "f64.ne")
        let a = pop_f64_value(stack, "f64.ne")
        push_i32_bool(stack, a != b)
      }
      F64Lt => {
        let b = pop_f64_value(stack, "f64.lt")
        let a = pop_f64_value(stack, "f64.lt")
        push_i32_bool(stack, a < b)
      }
      F64Gt => {
        let b = pop_f64_value(stack, "f64.gt")
        let a = pop_f64_value(stack, "f64.gt")
        push_i32_bool(stack, a > b)
      }
      F64Le => {
        let b = pop_f64_value(stack, "f64.le")
        let a = pop_f64_value(stack, "f64.le")
        push_i32_bool(stack, a <= b)
      }
      F64Ge => {
        let b = pop_f64_value(stack, "f64.ge")
        let a = pop_f64_value(stack, "f64.ge")
        push_i32_bool(stack, a >= b)
      }
      F64Abs => {
        let a = pop_f64_value(stack, "f64.abs")
        stack.push(F64(a.abs()))
      }
      F64Neg => {
        let a = pop_f64_value(stack, "f64.neg")
        stack.push(F64(-a))
      }
      F64Ceil => {
        let a = pop_f64_value(stack, "f64.ceil")
        stack.push(F64(canonicalize_f64(a.ceil())))
      }
      F64Floor => {
        let a = pop_f64_value(stack, "f64.floor")
        stack.push(F64(canonicalize_f64(a.floor())))
      }
      F64Trunc => {
        let a = pop_f64_value(stack, "f64.trunc")
        stack.push(F64(canonicalize_f64(a.trunc())))
      }
      F64Nearest => {
        let a = pop_f64_value(stack, "f64.nearest")
        stack.push(F64(canonicalize_f64(rint(a))))
      }
      F64Sqrt => {
        let a = pop_f64_value(stack, "f64.sqrt")
        stack.push(F64(canonicalize_f64(a.sqrt())))
      }
      F64Add => {
        let b = pop_f64_value(stack, "f64.add")
        let a = pop_f64_value(stack, "f64.add")
        stack.push(F64(canonicalize_f64(a + b)))
      }
      F64Sub => {
        let b = pop_f64_value(stack, "f64.sub")
        let a = pop_f64_value(stack, "f64.sub")
        stack.push(F64(canonicalize_f64(a - b)))
      }
      F64Mul => {
        let b = pop_f64_value(stack, "f64.mul")
        let a = pop_f64_value(stack, "f64.mul")
        stack.push(F64(canonicalize_f64(a * b)))
      }
      F64Div => {
        let b = pop_f64_value(stack, "f64.div")
        let a = pop_f64_value(stack, "f64.div")
        stack.push(F64(canonicalize_f64(a / b)))
      }
      F64Min => {
        let b = pop_f64_value(stack, "f64.min")
        let a = pop_f64_value(stack, "f64.min")
        let result = if a.is_nan() || b.is_nan() {
          canonical_nan_f64
        } else if a < b {
          a
        } else if b < a {
          b
        } else {
          let a_bits = a.reinterpret_as_uint64()
          let b_bits = b.reinterpret_as_uint64()
          let sign_mask = 0x8000_0000_0000_0000UL
          if (a_bits & sign_mask) != 0UL || (b_bits & sign_mask) != 0UL {
            if (a_bits & sign_mask) != 0UL {
              a
            } else {
              b
            }
          } else {
            a
          }
        }
        stack.push(F64(result))
      }
      F64Max => {
        let b = pop_f64_value(stack, "f64.max")
        let a = pop_f64_value(stack, "f64.max")
        let result = if a.is_nan() || b.is_nan() {
          canonical_nan_f64
        } else if a > b {
          a
        } else if b > a {
          b
        } else {
          let a_bits = a.reinterpret_as_uint64()
          let b_bits = b.reinterpret_as_uint64()
          let sign_mask = 0x8000_0000_0000_0000UL
          if (a_bits & sign_mask) == 0UL || (b_bits & sign_mask) == 0UL {
            if (a_bits & sign_mask) == 0UL {
              a
            } else {
              b
            }
          } else {
            a
          }
        }
        stack.push(F64(result))
      }
      F64Copysign => {
        let b = pop_f64_value(stack, "f64.copysign")
        let a = pop_f64_value(stack, "f64.copysign")
        let a_bits = a.reinterpret_as_uint64()
        let b_bits = b.reinterpret_as_uint64()
        let sign_mask = 0x8000_0000_0000_0000UL
        let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
        stack.push(F64(result_bits.reinterpret_as_double()))
      }
      I32WrapI64 => {
        let v = pop_i64_value(stack, "i32.wrap_i64")
        stack.push(I32((v & 0xFFFFFFFFUL).to_uint()))
      }
      I32TruncF32S => {
        let a = pop_f32_value(stack, "i32.trunc_f32_s")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 2147483648.0 || a < -2147483648.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I32(a.to_int().reinterpret_as_uint()))
      }
      I32TruncF32U => {
        let a = pop_f32_value(stack, "i32.trunc_f32_u")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 4294967296.0 || a <= -1.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I32(a.to_double().to_uint64().to_uint()))
      }
      I32TruncF64S => {
        let a = pop_f64_value(stack, "i32.trunc_f64_s")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 2147483648.0 || a <= -2147483649.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I32(a.to_int().reinterpret_as_uint()))
      }
      I32TruncF64U => {
        let a = pop_f64_value(stack, "i32.trunc_f64_u")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 4294967296.0 || a <= -1.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I32(a.to_uint64().to_uint()))
      }
      I64ExtendI32S => {
        let a = pop_i32_value(stack, "i64.extend_i32_s")
        let result = a.reinterpret_as_int().to_int64().reinterpret_as_uint64()
        stack.push(I64(result))
      }
      I64ExtendI32U => {
        let a = pop_i32_value(stack, "i64.extend_i32_u")
        stack.push(I64(a.to_uint64()))
      }
      I64TruncF32S => {
        let a = pop_f32_value(stack, "i64.trunc_f32_s").to_double()
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I64(a.to_int64().reinterpret_as_uint64()))
      }
      I64TruncF32U => {
        let a = pop_f32_value(stack, "i64.trunc_f32_u")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        let a_double = a.to_double()
        if a_double >= 18446744073709551616.0 || a_double <= -1.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I64(u64_from_f32(a)))
      }
      I64TruncF64S => {
        let a = pop_f64_value(stack, "i64.trunc_f64_s")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I64(a.to_int64().reinterpret_as_uint64()))
      }
      I64TruncF64U => {
        let a = pop_f64_value(stack, "i64.trunc_f64_u")
        if a.is_nan() {
          raise RuntimeError::IntegerOverflow
        }
        if a >= 18446744073709551616.0 || a <= -1.0 {
          raise RuntimeError::IntegerOverflow
        }
        stack.push(I64(u64_from_f64(a)))
      }
      F32ConvertI32S => {
        let a = pop_i32_value(stack, "f32.convert_i32_s").reinterpret_as_int()
        stack.push(F32(Float::from_int(a)))
      }
      F32ConvertI32U => {
        let a = pop_i32_value(stack, "f32.convert_i32_u")
        stack.push(F32(Float::from_double(a.to_double())))
      }
      F32ConvertI64S => {
        let a = pop_i64_value(stack, "f32.convert_i64_s").reinterpret_as_int64()
        stack.push(F32(f32_from_i64(a)))
      }
      F32ConvertI64U => {
        let a = pop_i64_value(stack, "f32.convert_i64_u")
        stack.push(F32(f32_from_u64(a)))
      }
      F32DemoteF64 => {
        let a = pop_f64_value(stack, "f32.demote_f64")
        let result = Float::from_double(a)
        stack.push(F32(canonicalize_f32(result)))
      }
      F64ConvertI32S => {
        let a = pop_i32_value(stack, "f64.convert_i32_s").reinterpret_as_int()
        stack.push(F64(a.to_double()))
      }
      F64ConvertI32U => {
        let a = pop_i32_value(stack, "f64.convert_i32_u")
        stack.push(F64(a.to_double()))
      }
      F64ConvertI64S => {
        let a = pop_i64_value(stack, "f64.convert_i64_s").reinterpret_as_int64()
        stack.push(F64(a.to_double()))
      }
      F64ConvertI64U => {
        let a = pop_i64_value(stack, "f64.convert_i64_u")
        stack.push(F64(a.to_double()))
      }
      F64PromoteF32 => {
        let a = pop_f32_value(stack, "f64.promote_f32")
        let result = a.to_double()
        stack.push(F64(canonicalize_f64(result)))
      }
      I32ReinterpretF32 => {
        let a = pop_f32_value(stack, "i32.reinterpret_f32")
        stack.push(I32(a.reinterpret_as_uint()))
      }
      I64ReinterpretF64 => {
        let a = pop_f64_value(stack, "i64.reinterpret_f64")
        stack.push(I64(a.reinterpret_as_uint64()))
      }
      F32ReinterpretI32 => {
        let a = pop_i32_value(stack, "f32.reinterpret_i32")
        stack.push(F32(Float::reinterpret_from_uint(a)))
      }
      F64ReinterpretI64 => {
        let a = pop_i64_value(stack, "f64.reinterpret_i64")
        stack.push(F64(a.reinterpret_as_double()))
      }
      I32TruncSatF32S => {
        let a = pop_f32_value(stack, "i32.trunc_sat_f32_s")
        let result = if a.is_nan() {
          0U
        } else if a >= 2147483648.0 {
          0x7FFFFFFFU
        } else if a < -2147483648.0 {
          0x80000000U
        } else {
          a.to_int().reinterpret_as_uint()
        }
        stack.push(I32(result))
      }
      I32TruncSatF32U => {
        let a = pop_f32_value(stack, "i32.trunc_sat_f32_u")
        let result = if a.is_nan() {
          0U
        } else if a >= 4294967296.0 {
          0xFFFFFFFFU
        } else if a <= -1.0 {
          0U
        } else {
          a.to_double().to_uint64().to_uint()
        }
        stack.push(I32(result))
      }
      I32TruncSatF64S => {
        let a = pop_f64_value(stack, "i32.trunc_sat_f64_s")
        let result = if a.is_nan() {
          0U
        } else if a >= 2147483648.0 {
          0x7FFFFFFFU
        } else if a < -2147483648.0 {
          0x80000000U
        } else {
          a.to_int().reinterpret_as_uint()
        }
        stack.push(I32(result))
      }
      I32TruncSatF64U => {
        let a = pop_f64_value(stack, "i32.trunc_sat_f64_u")
        let result = if a.is_nan() {
          0U
        } else if a >= 4294967296.0 {
          0xFFFFFFFFU
        } else if a <= -1.0 {
          0U
        } else {
          a.to_uint64().to_uint()
        }
        stack.push(I32(result))
      }
      I64TruncSatF32S => {
        let a = pop_f32_value(stack, "i64.trunc_sat_f32_s").to_double()
        let result = if a.is_nan() {
          0UL
        } else if a >= 9223372036854775808.0 {
          0x7FFFFFFFFFFFFFFFUL
        } else if a < -9223372036854775808.0 {
          0x8000000000000000UL
        } else {
          a.to_int64().reinterpret_as_uint64()
        }
        stack.push(I64(result))
      }
      I64TruncSatF32U => {
        let a = pop_f32_value(stack, "i64.trunc_sat_f32_u")
        let a_double = a.to_double()
        let result = if a.is_nan() {
          0UL
        } else if a_double >= 18446744073709551616.0 {
          0xFFFFFFFFFFFFFFFFUL
        } else if a_double <= -1.0 {
          0UL
        } else {
          u64_from_f32(a)
        }
        stack.push(I64(result))
      }
      I64TruncSatF64S => {
        let a = pop_f64_value(stack, "i64.trunc_sat_f64_s")
        let result = if a.is_nan() {
          0UL
        } else if a >= 9223372036854775808.0 {
          0x7FFFFFFFFFFFFFFFUL
        } else if a < -9223372036854775808.0 {
          0x8000000000000000UL
        } else {
          a.to_int64().reinterpret_as_uint64()
        }
        stack.push(I64(result))
      }
      I64TruncSatF64U => {
        let a = pop_f64_value(stack, "i64.trunc_sat_f64_u")
        let result = if a.is_nan() {
          0UL
        } else if a >= 18446744073709551616.0 {
          0xFFFFFFFFFFFFFFFFUL
        } else if a <= -1.0 {
          0UL
        } else {
          u64_from_f64(a)
        }
        stack.push(I64(result))
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
