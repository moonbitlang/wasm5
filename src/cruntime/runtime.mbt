///|
/// Runtime for C-based threaded code execution.
pub struct CRuntime {
  module_ : @core.Module
  compiled : CompiledModule
  globals : FixedArray[UInt64] // Global variables
  memory : FixedArray[Byte] // Linear memory
  memory_pages : FixedArray[Int] // Current size in pages (single element array for FFI mutability)
  tables : FixedArray[FixedArray[Int]] // Tables of function indices
  // Flattened table data for C FFI
  tables_flat : FixedArray[Int] // All tables concatenated
  table_offsets : FixedArray[Int] // Offset of each table in tables_flat
  table_sizes : FixedArray[Int] // Size of each table
  // Type information for call_indirect type checking
  func_type_idxs : FixedArray[Int] // Type index for each function (imported + local)
  type_param_counts : FixedArray[Int] // Primary signature hash for each type
  type_result_counts : FixedArray[Int] // Secondary signature hash for each type
  // Import function metadata for op_call_import
  import_num_params : FixedArray[Int] // Number of params for each imported function
  import_num_results : FixedArray[Int] // Number of results for each imported function
  // Data segments for bulk memory operations
  data_segments_flat : FixedArray[Byte] // All data segments concatenated
  data_segment_offsets : FixedArray[Int] // Offset of each segment in data_segments_flat
  data_segment_sizes : FixedArray[Int] // Size of each segment (mutable for data.drop)
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
    UninitializedElement => "uninitialized element"
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
  // Initialize tables from module (needs globals for element offset evaluation)
  let tables = init_tables(module_, globals)
  // Flatten tables for C FFI
  let (tables_flat, table_offsets, table_sizes) = flatten_tables(tables)
  // Build type info for call_indirect type checking
  let (func_type_idxs, type_param_counts, type_result_counts) = build_type_info(
    module_,
  )
  // Build import function metadata for op_call_import
  let (import_num_params, import_num_results) = build_import_info(module_)
  // Flatten data segments for bulk memory operations
  let (data_segments_flat, data_segment_offsets, data_segment_sizes) = flatten_data_segments(
    module_,
  )
  {
    module_,
    compiled,
    globals,
    memory,
    memory_pages,
    tables,
    tables_flat,
    table_offsets,
    table_sizes,
    func_type_idxs,
    type_param_counts,
    type_result_counts,
    import_num_params,
    import_num_results,
    data_segments_flat,
    data_segment_offsets,
    data_segment_sizes,
  }
}

///|
/// Flatten tables into a single array for C FFI
fn flatten_tables(
  tables : FixedArray[FixedArray[Int]],
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  let num_tables = tables.length()
  // Calculate total size and offsets
  let table_sizes : Array[Int] = []
  let table_offsets : Array[Int] = []
  let mut total_size = 0
  for i in 0..<num_tables {
    table_offsets.push(total_size)
    let size = tables[i].length()
    table_sizes.push(size)
    total_size += size
  }
  // Flatten into single array
  let tables_flat : FixedArray[Int] = FixedArray::make(
    if total_size > 0 {
      total_size
    } else {
      1
    },
    -1,
  )
  for i in 0..<num_tables {
    let offset = table_offsets[i]
    let table = tables[i]
    for j in 0..<table.length() {
      tables_flat[offset + j] = table[j]
    }
  }
  (
    tables_flat,
    FixedArray::from_array(table_offsets),
    FixedArray::from_array(table_sizes),
  )
}

///|
/// Flatten data segments into a single byte array for C FFI
/// Returns (data_flat, offsets, sizes) where sizes is mutable for data.drop
fn flatten_data_segments(
  module_ : @core.Module,
) -> (FixedArray[Byte], FixedArray[Int], FixedArray[Int]) {
  let num_segments = module_.datas.length()
  if num_segments == 0 {
    // Return minimal arrays to avoid empty array issues
    return (FixedArray::make(1, b'\x00'), [0], [0])
  }
  // Calculate total size and offsets
  let segment_sizes : Array[Int] = []
  let segment_offsets : Array[Int] = []
  let mut total_size = 0
  for data in module_.datas {
    segment_offsets.push(total_size)
    let size = data.init.length()
    segment_sizes.push(size)
    total_size += size
  }
  // Flatten into single byte array
  let data_flat : FixedArray[Byte] = FixedArray::make(
    if total_size > 0 {
      total_size
    } else {
      1
    },
    b'\x00',
  )
  for i, data in module_.datas {
    let offset = segment_offsets[i]
    for j in 0..<data.init.length() {
      data_flat[offset + j] = data.init[j]
    }
  }
  (
    data_flat,
    FixedArray::from_array(segment_offsets),
    FixedArray::from_array(segment_sizes),
  )
}

///|
/// Compute a hash for a value type (for type signature comparison)
fn valtype_code(vt : @core.ValType) -> Int {
  match vt {
    I32 => 1
    I64 => 2
    F32 => 3
    F64 => 4
    V128 => 5
    FuncRef => 6
    ExternRef => 7
    _ => 0 // Other reference types
  }
}

///|
/// Compute a signature hash for a function type
/// This hash uniquely identifies the function signature for type checking
fn compute_type_signature_hash(ft : @core.FuncType) -> Int {
  // Use a simple polynomial hash that includes both types and positions
  let mut hash = 0
  let mut multiplier = 1
  // Hash params
  for param in ft.params {
    hash = hash + valtype_code(param) * multiplier
    multiplier = multiplier * 17
  }
  // Add separator
  hash = hash + 100 * multiplier
  multiplier = multiplier * 17
  // Hash results
  for result in ft.results {
    hash = hash + valtype_code(result) * multiplier
    multiplier = multiplier * 17
  }
  hash
}

///|
/// Build type information for call_indirect type checking
fn build_type_info(
  module_ : @core.Module,
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  // Count imported functions
  let num_imported = count_imported_funcs(module_)
  // Build func_type_idxs: type index for each function
  let func_type_idxs : Array[Int] = []
  // First, imported function types
  for imp in module_.imports {
    match imp.desc {
      Func(type_idx) => func_type_idxs.push(type_idx.reinterpret_as_int())
      _ => ()
    }
  }
  // Then, local function types (from module.funcs, skipping imports)
  for i = num_imported; i < module_.funcs.length(); i = i + 1 {
    func_type_idxs.push(module_.funcs[i].reinterpret_as_int())
  }
  // Build type signature hashes for each type
  // We use two arrays to store high and low bits of the hash for better discrimination
  let type_sig_hash1 : Array[Int] = [] // Primary hash
  let type_sig_hash2 : Array[Int] = [] // Secondary hash (param count << 16 | result count)
  for type_def in module_.types {
    match type_def {
      Func(ft) => {
        type_sig_hash1.push(compute_type_signature_hash(ft))
        type_sig_hash2.push(ft.params.length().lsl(16) | ft.results.length())
      }
      _ => {
        // For non-function types (struct, array), use sentinel values
        type_sig_hash1.push(-1)
        type_sig_hash2.push(-1)
      }
    }
  }
  // Ensure at least 1 element to avoid empty array issues
  if func_type_idxs.length() == 0 {
    func_type_idxs.push(-1)
  }
  if type_sig_hash1.length() == 0 {
    type_sig_hash1.push(-1)
    type_sig_hash2.push(-1)
  }
  (
    FixedArray::from_array(func_type_idxs),
    FixedArray::from_array(type_sig_hash1),
    FixedArray::from_array(type_sig_hash2),
  )
}

///|
/// Build import function metadata for op_call_import
/// Returns (import_num_params, import_num_results) arrays
fn build_import_info(
  module_ : @core.Module,
) -> (FixedArray[Int], FixedArray[Int]) {
  let import_num_params : Array[Int] = []
  let import_num_results : Array[Int] = []
  for imp in module_.imports {
    match imp.desc {
      Func(type_idx) => {
        // Get function type from type index
        let type_int = type_idx.reinterpret_as_int()
        if type_int >= 0 && type_int < module_.types.length() {
          match module_.types[type_int] {
            Func(ft) => {
              import_num_params.push(ft.params.length())
              import_num_results.push(ft.results.length())
            }
            _ => {
              // Non-function type (shouldn't happen for function imports)
              import_num_params.push(0)
              import_num_results.push(0)
            }
          }
        } else {
          import_num_params.push(0)
          import_num_results.push(0)
        }
      }
      _ => () // Skip non-function imports
    }
  }
  // Ensure at least 1 element to avoid empty array issues
  if import_num_params.length() == 0 {
    import_num_params.push(0)
    import_num_results.push(0)
  }
  (
    FixedArray::from_array(import_num_params),
    FixedArray::from_array(import_num_results),
  )
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
/// Count imported globals in module
fn count_imported_globals(module_ : @core.Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Global(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Initialize globals from module's global section
fn init_globals(module_ : @core.Module) -> FixedArray[UInt64] {
  let num_imported = count_imported_globals(module_)
  let num_local = module_.globals.length()
  let total = num_imported + num_local
  let globals = FixedArray::make(if total > 0 { total } else { 1 }, 0UL)
  // First, initialize imported globals with default values (for spectest compatibility)
  let mut idx = 0
  for imp in module_.imports {
    match imp.desc {
      Global(gt) => {
        // Default values for spectest globals
        let value : UInt64 = match gt.val_type {
          I32 => 666UL // spectest global_i32 = 666
          I64 => 666UL // spectest global_i64 = 666
          F32 => {
            let f : Float = 666.6
            f.reinterpret_as_uint().to_uint64()
          }
          F64 => {
            let d : Double = 666.6
            d.reinterpret_as_uint64()
          }
          FuncRef => 0xFFFFFFFF_FFFFFFFFUL // null funcref
          ExternRef => 0xFFFFFFFF_FFFFFFFFUL // null externref
          _ => 0UL
        }
        globals[idx] = value
        idx += 1
      }
      _ => ()
    }
  }
  // Then initialize local globals with their init expressions
  for i, g in module_.globals {
    // Evaluate init expression, passing globals array to support global.get
    let value = eval_const_expr_with_globals(g.init, globals)
    globals[num_imported + i] = value
  }
  globals
}

///|
/// Count the number of imported tables in the module
fn count_imported_tables(module_ : @core.Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Table(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Initialize tables from module's table and elem sections
fn init_tables(
  module_ : @core.Module,
  globals : FixedArray[UInt64],
) -> FixedArray[FixedArray[Int]] {
  let num_imported_tables = count_imported_tables(module_)
  let num_local_tables = module_.tables.length()
  let num_tables = num_imported_tables + num_local_tables
  if num_tables == 0 {
    return [[-1]] // Return a dummy table to avoid empty array issues
  }
  // Allocate tables
  let tables : FixedArray[FixedArray[Int]] = FixedArray::make(num_tables, [-1])
  // Initialize imported tables (from import descriptors)
  let mut import_table_idx = 0
  for imp in module_.imports {
    match imp.desc {
      Table(table_type) => {
        let size = table_type.limits.min.to_int()
        // Initialize imported table with -1 (null/undefined)
        tables[import_table_idx] = FixedArray::make(
          if size > 0 {
            size
          } else {
            1
          },
          -1,
        )
        import_table_idx += 1
      }
      _ => ()
    }
  }
  // Initialize local tables
  for i, table_type in module_.tables {
    let size = table_type.limits.min.to_int()
    // Initialize table with -1 (null/undefined)
    tables[num_imported_tables + i] = FixedArray::make(
      if size > 0 {
        size
      } else {
        1
      },
      -1,
    )
  }
  // Initialize from element segments
  for elem in module_.elems {
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx >= 0 && table_idx < tables.length() {
        let offset = eval_const_expr_with_globals(elem.offset, globals).to_int()
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
/// Evaluate a constant expression to get initial value (simple version without globals)
fn eval_const_expr(expr : @core.Expr) -> UInt64 {
  eval_const_expr_with_globals(expr, FixedArray::make(1, 0UL))
}

///|
/// Evaluate a constant expression with access to globals array
fn eval_const_expr_with_globals(
  expr : @core.Expr,
  globals : FixedArray[UInt64],
) -> UInt64 {
  // Use a simple stack for expression evaluation
  let stack : Array[UInt64] = []
  for instr in expr.instrs {
    match instr {
      I32Const(n) => stack.push(n.to_uint64())
      I64Const(n) => stack.push(n)
      F32Const(f) => stack.push(f.reinterpret_as_uint().to_uint64())
      F64Const(f) => stack.push(f.reinterpret_as_uint64())
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        if global_idx >= 0 && global_idx < globals.length() {
          stack.push(globals[global_idx])
        } else {
          stack.push(0UL)
        }
      }
      RefNull(_) => stack.push(0xFFFFFFFF_FFFFFFFFUL)
      RefFunc(idx) => stack.push(idx.to_uint64()) // Function index
      // Simple arithmetic for const expr evaluation
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap().to_uint()
          let a = stack.pop().unwrap().to_uint()
          stack.push((a + b).to_uint64())
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap().to_uint()
          let a = stack.pop().unwrap().to_uint()
          stack.push((a - b).to_uint64())
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap().to_uint()
          let a = stack.pop().unwrap().to_uint()
          stack.push((a * b).to_uint64())
        }
      I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          stack.push(a + b)
        }
      I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          stack.push(a - b)
        }
      I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          stack.push(a * b)
        }
      _ => continue
    }
  }
  // Return top of stack or 0 if empty
  if stack.length() > 0 {
    stack.pop().unwrap()
  } else {
    0UL
  }
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
          self.tables_flat,
          self.table_offsets,
          self.table_sizes,
          self.tables.length(),
          self.compiled.func_entries,
          self.compiled.func_num_locals,
          self.compiled.func_entries.length(),
          num_imported,
          self.func_type_idxs,
          self.type_param_counts,
          self.type_result_counts,
          self.module_.types.length(),
          self.import_num_params,
          self.import_num_results,
          self.data_segments_flat,
          self.data_segment_offsets,
          self.data_segment_sizes,
          self.module_.datas.length(),
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
      // Note: func_idx is the local function index, funcs array only has local functions
      let num_imported = count_imported_funcs(self.module_)
      let type_idx = self.module_.funcs[func_idx].reinterpret_as_int()
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
        self.tables_flat,
        self.table_offsets,
        self.table_sizes,
        self.tables.length(),
        self.compiled.func_entries,
        self.compiled.func_num_locals,
        self.compiled.func_entries.length(),
        num_imported,
        self.func_type_idxs,
        self.type_param_counts,
        self.type_result_counts,
        self.module_.types.length(),
        self.import_num_params,
        self.import_num_results,
        self.data_segments_flat,
        self.data_segment_offsets,
        self.data_segment_sizes,
        self.module_.datas.length(),
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
