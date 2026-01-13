///|
/// Runtime for C-based threaded code execution.
pub struct CRuntime {
  module_ : @core.Module
  compiled : CompiledModule
  globals : FixedArray[UInt64] // Global variables
  memory : FixedArray[Byte] // Linear memory
  memory_pages : FixedArray[Int] // Current size in pages (single element array for FFI mutability)
  tables : FixedArray[FixedArray[Int]] // Tables of function indices
}

// Import Value type from core

///|
using @core {type Value}

///|
/// Convert TrapCode to RuntimeError using the error detail string approach
fn trap_to_error(trap : TrapCode) -> @runtime.RuntimeError {
  let detail = match trap {
    None => "unreachable" // Should not happen
    Unreachable => "unreachable"
    DivisionByZero => "division by zero"
    IntegerOverflow => "integer overflow"
    InvalidConversionToInteger => "integer overflow"
    OutOfBoundsMemoryAccess => "out of bounds memory access"
    OutOfBoundsTableAccess => "undefined element"
    IndirectCallTypeMismatch => "indirect call type mismatch"
    NullFunctionReference => "null function reference"
    StackOverflow => "stack overflow"
  }
  @runtime.RuntimeError::from_detail(detail)
}

///|
/// Load a module and compile it for C runtime execution.
pub fn CRuntime::load(module_ : @core.Module) -> CRuntime {
  let compiled = compile(module_)
  // Initialize globals from module
  let globals = init_globals(module_)
  // Initialize memory from module
  let (memory, memory_pages) = init_memory(module_)
  // Initialize tables from module
  let tables = init_tables(module_)
  { module_, compiled, globals, memory, memory_pages, tables }
}

///|
/// Page size in bytes (64KB)
let page_size : Int = 65536

///|
/// Initialize memory from module's memory section
fn init_memory(module_ : @core.Module) -> (FixedArray[Byte], FixedArray[Int]) {
  // Get initial memory size from first memory (if any)
  let initial_pages = if module_.mems.length() > 0 {
    module_.mems[0].limits.min.to_int()
  } else {
    0
  }
  // Allocate memory (at least 1 byte to avoid empty array)
  let size = initial_pages * page_size
  let memory = FixedArray::make(if size > 0 { size } else { 1 }, b'\x00')
  // Initialize active data segments
  for data in module_.datas {
    if data.is_active {
      let offset = eval_const_expr(data.offset).to_int()
      for i, b in data.init {
        if offset + i < memory.length() {
          memory[offset + i] = b
        }
      }
    }
  }
  // Use single-element array for memory_pages so it can be mutated by C
  let memory_pages_arr : FixedArray[Int] = [initial_pages]
  (memory, memory_pages_arr)
}

///|
/// Initialize globals from module's global section
fn init_globals(module_ : @core.Module) -> FixedArray[UInt64] {
  let num_globals = module_.globals.length()
  let globals = FixedArray::make(
    if num_globals > 0 {
      num_globals
    } else {
      1
    },
    0UL,
  )
  for i, g in module_.globals {
    // Evaluate init expression (assuming simple constant for now)
    let value = eval_const_expr(g.init)
    globals[i] = value
  }
  globals
}

///|
/// Initialize tables from module's table and elem sections
fn init_tables(module_ : @core.Module) -> FixedArray[FixedArray[Int]] {
  let num_tables = module_.tables.length()
  if num_tables == 0 {
    return [[-1]] // Return a dummy table to avoid empty array issues
  }
  // Allocate tables
  let tables : FixedArray[FixedArray[Int]] = FixedArray::make(num_tables, [-1])
  for i, table_type in module_.tables {
    let size = table_type.limits.min.to_int()
    // Initialize table with -1 (null/undefined)
    tables[i] = FixedArray::make(if size > 0 { size } else { 1 }, -1)
  }
  // Initialize from element segments
  for elem in module_.elems {
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx >= 0 && table_idx < tables.length() {
        let offset = eval_const_expr(elem.offset).to_int()
        let table = tables[table_idx]
        for i, init_expr in elem.init {
          if offset + i < table.length() {
            // Evaluate the init expression to get the function index
            let func_idx = eval_elem_expr(init_expr)
            table[offset + i] = func_idx
          }
        }
      }
    }
  }
  tables
}

///|
/// Evaluate an element init expression to get function index
fn eval_elem_expr(expr : @core.Expr) -> Int {
  for instr in expr.instrs {
    match instr {
      RefFunc(idx) => return idx.reinterpret_as_int()
      RefNull(_) => return -1 // null function reference
      _ => continue
    }
  }
  -1
}

///|
/// Evaluate a constant expression to get initial value
fn eval_const_expr(expr : @core.Expr) -> UInt64 {
  for instr in expr.instrs {
    match instr {
      I32Const(n) => return n.to_uint64()
      I64Const(n) => return n
      F32Const(f) => return f.reinterpret_as_uint().to_uint64()
      F64Const(f) => return f.reinterpret_as_uint64()
      GlobalGet(_) => return 0UL // TODO: handle global references
      RefNull(_) => return 0xFFFFFFFF_FFFFFFFFUL
      RefFunc(_) => return 0UL // TODO: handle func refs
      _ => continue
    }
  }
  0UL
}

///|
/// Run the start function if present.
pub fn CRuntime::run_start(self : CRuntime) -> Unit raise @runtime.RuntimeError {
  match self.module_.start {
    Some(start_idx) => {
      let num_imported = count_imported_funcs(self.module_)
      let local_idx = start_idx.reinterpret_as_int() - num_imported
      if local_idx >= 0 && local_idx < self.compiled.func_entries.length() {
        let entry = self.compiled.func_entries[local_idx]
        let num_locals = self.compiled.func_num_locals[local_idx]
        let result_out : FixedArray[UInt64] = [0]
        let table = self.tables[0]
        let trap_code = c_execute_ffi(
          self.compiled.code,
          entry,
          num_locals,
          [],
          0,
          result_out,
          0, // start function has no results
          self.globals,
          self.memory,
          self.memory.length(),
          self.memory_pages,
          table,
          table.length(),
          self.compiled.func_entries,
          self.compiled.func_num_locals,
          self.compiled.func_entries.length(),
          num_imported,
        )
        let trap = trap_code_from_int(trap_code)
        if trap != TrapCode::None {
          raise trap_to_error(trap)
        }
      }
    }
    None => ()
  }
}

///|
/// Call an exported function by name.
pub fn CRuntime::call_compiled(
  self : CRuntime,
  name : Bytes,
  args : Array[Value],
) -> Array[Value] raise @runtime.RuntimeError {
  let name_str = @encoding/utf8.decode(name) catch { _ => return [] }
  match self.compiled.exports.get(name_str) {
    Some(func_idx) => {
      // Get function type for result conversion
      let num_imported = count_imported_funcs(self.module_)
      let abs_idx = num_imported + func_idx
      let type_idx = self.module_.funcs[abs_idx].reinterpret_as_int()
      let func_type = get_func_type(self.module_, type_idx)
      let num_results = func_type.results.length()

      // Convert args to UInt64
      let args_u64 : Array[UInt64] = []
      for arg in args {
        args_u64.push(value_to_u64(arg))
      }
      let entry = self.compiled.func_entries[func_idx]
      let num_locals = self.compiled.func_num_locals[func_idx]
      let args_fixed = FixedArray::from_array(args_u64)
      // Allocate result array with correct size (at least 1 to avoid empty array issues)
      let result_out : FixedArray[UInt64] = FixedArray::make(
        if num_results > 0 {
          num_results
        } else {
          1
        },
        0UL,
      )
      let table = self.tables[0]
      let trap_code = c_execute_ffi(
        self.compiled.code,
        entry,
        num_locals,
        args_fixed,
        args_u64.length(),
        result_out,
        num_results,
        self.globals,
        self.memory,
        self.memory.length(),
        self.memory_pages,
        table,
        table.length(),
        self.compiled.func_entries,
        self.compiled.func_num_locals,
        self.compiled.func_entries.length(),
        num_imported,
      )
      // Check for trap
      let trap = trap_code_from_int(trap_code)
      if trap != TrapCode::None {
        raise trap_to_error(trap)
      }

      // Convert all results based on function type
      let results : Array[Value] = []
      for i in 0..<num_results {
        results.push(u64_to_value(result_out[i], func_type.results[i]))
      }
      results
    }
    None => []
  }
}

///|
fn value_to_u64(v : Value) -> UInt64 {
  match v {
    I32(n) => n.to_uint64()
    I64(n) => n
    F32(f) => f.reinterpret_as_uint().to_uint64()
    F64(f) => f.reinterpret_as_uint64()
    Ref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Ref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Funcref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Funcref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Externref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Externref(None) => 0xFFFFFFFF_FFFFFFFFUL
  }
}

///|
fn u64_to_value(raw : UInt64, ty : @core.ValType) -> Value {
  match ty {
    I32 => Value::I32(raw.to_uint())
    I64 => Value::I64(raw)
    F32 => Value::F32(Float::reinterpret_from_uint(raw.to_uint()))
    F64 => Value::F64(raw.reinterpret_as_double())
    FuncRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Funcref(None)
      } else {
        Value::Funcref(Some(raw.to_uint().reinterpret_as_int()))
      }
    ExternRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Externref(None)
      } else {
        Value::Externref(Some(raw.to_uint().reinterpret_as_int()))
      }
    _ => Value::I64(raw)
  }
}
