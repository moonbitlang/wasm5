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
/// Parse error types
pub suberror ParseError {
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
} derive(Show)

///|
/// Validation error types
pub suberror ValidationError {
  TypeMismatch(String)
  InvalidFunctionIndex(Int)
  InvalidTypeIndex(Int)
  InvalidLocalIndex(Int)
  InvalidGlobalIndex(Int)
  UnknownGlobal(Int) // Global not available in current context (e.g., local global in table init)
  StackSizeMismatch(String)
  InvalidResultArity(String)
  InvalidAlignment(String)
  UnknownLabel(Int)
  InvalidStartFunction(String)
  UnknownMemory(Int)
  InvalidMemorySize(String)
  ImmutableGlobal(Int)
  DuplicateExport(String)
  UnknownExportedFunction(Int)
  UnknownExportedMemory(Int)
  UnknownExportedTable(Int)
  UnknownExportedGlobal(Int)
  InvalidTableSize(String)
  UnknownTable(Int)
  ConstantExpressionRequired(String)
  UninitializedLocal(Int) // Local with non-defaultable type used before initialization
  UnknownType(Int) // Type index in ref type doesn't exist
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
  max : UInt? // Maximum size limit (None = no limit)
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
/// Import resolver for linking modules
/// Maps (module_name, field_name) to ImportedFunc or global Value
/// Using Bytes keys to match how WebAssembly module imports work
struct ImportResolverEntry {
  funcs : Map[Bytes, ImportedFunc]
  globals : Map[Bytes, Value]
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
/// Runtime structure that holds a loaded WebAssembly module
pub struct Runtime {
  module_ : Module
  ops : Array[MInstr]
  stack : Array[Value]
  mut locals : Array[Value]
  mut pc : Int
  mut running : Bool // Execution loop control flag
  call_stack : Array[CallFrame]
  memory : Array[Byte] // Linear memory
  memory_max : UInt? // Maximum memory size in pages (None = no limit)
  globals : Array[Value] // Global variables
  tables : Array[RuntimeTable] // Tables with limits
  imported_funcs : Array[ImportedFunc] // Imported functions
  data_segments : Array[Array[Byte]] // Data segments for bulk memory ops
  mut error_detail : String // Error detail for debugging (populated on error)
}

///|
/// Get the module from the runtime
pub fn Runtime::get_module(self : Runtime) -> Module {
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
  resolver
}

///|
/// Load a WebAssembly module into the runtime (using default import resolver)
pub fn Runtime::load(m : Module) -> Runtime raise RuntimeError {
  Runtime::load_with_resolver(m, default_import_resolver())
}

///|
/// Load a WebAssembly module into the runtime with a custom import resolver
pub fn Runtime::load_with_resolver(
  m : Module,
  resolver : ImportResolver,
) -> Runtime raise RuntimeError {
  // Initialize memory
  // Read memory limits from module definition
  let mut memory_min_pages : UInt = 0
  let mut memory_max_pages : UInt? = None

  // Check for imported memory first, then local memory
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Mem(mem_type) => {
        memory_min_pages = mem_type.limits.min
        memory_max_pages = mem_type.limits.max
        break // Only one memory allowed in MVP
      }
      _ => ()
    }
  }

  // If no imported memory, check for local memory
  if memory_min_pages == 0 && m.mems.length() > 0 {
    memory_min_pages = m.mems[0].limits.min
    memory_max_pages = m.mems[0].limits.max
  }

  // Initialize memory with minimum size
  let memory_size = memory_min_pages.reinterpret_as_int() * 65536
  let memory = Array::make(memory_size, b'\x00')
  // Initialize globals
  // First, add imported globals - try to get from resolver, otherwise use default values
  let globals : Array[Value] = []
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Global(gt) => {
        // Try to get the global value from the resolver
        let value = match resolver.get_global(imp.module_, imp.name) {
          Some(v) => v
          None =>
            // Fall back to default values (for spectest)
            match gt.val_type {
              ValType::I32 => Value::I32(666U) // spectest global_i32 = 666
              ValType::I64 => Value::I64(666UL) // spectest global_i64 = 666
              ValType::F32 => Value::F32(666.6)
              ValType::F64 => Value::F64(666.6)
              ValType::FuncRef => Value::Ref(None)
              ValType::ExternRef => Value::Ref(None)
              _ => Value::I32(0U)
            }
        }
        globals.push(value)
      }
      _ => ()
    }
  }
  // Then add local globals
  for i = 0; i < m.globals.length(); i = i + 1 {
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
    for i = 0; i < data.init.length(); i = i + 1 {
      let addr = offset + i
      if addr >= 0 && addr < memory.length() {
        memory[addr] = data.init[i]
      }
    }
  }
  // Initialize tables
  let tables : Array[RuntimeTable] = []
  for table in m.tables {
    let table_size = table.limits.min.reinterpret_as_int()
    // Initialize table with null references
    let table_data : Array[Int?] = Array::make(table_size, None)
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
        // Copy function indices into table
        let table = tables[table_idx]
        for i = 0; i < elem.init.length(); i = i + 1 {
          let addr = offset + i
          if addr >= 0 && addr < table.data.length() {
            table.data[addr] = Some(elem.init[i].reinterpret_as_int())
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
    for i = 0; i < data.init.length(); i = i + 1 {
      segment.push(data.init[i])
    }
    data_segments.push(segment)
  }
  Runtime::{
    module_: m,
    ops: [],
    stack: [],
    locals: [],
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
fn eval_const_expr(
  expr : Expr,
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
