///|
/// Runtime for C-based threaded code execution.
pub struct CRuntime {
  module_ : @core.Module
  compiled : CompiledModule
  globals : FixedArray[UInt64] // Global variables
  memory : FixedArray[Byte] // Linear memory (pre-allocated to max size)
  memory_pages : FixedArray[Int] // Current size in pages (single element array for FFI mutability)
  memory_max_size : Int // Maximum memory size in bytes (for memory.grow bounds)
  tables : FixedArray[FixedArray[Int]] // Tables of function indices
  // Flattened table data for C FFI
  tables_flat : FixedArray[Int] // All tables concatenated
  table_offsets : FixedArray[Int] // Offset of each table in tables_flat
  table_sizes : FixedArray[Int] // Current size of each table
  table_max_sizes : FixedArray[Int] // Max size (capacity) of each table for table.grow
  // Type information for call_indirect type checking
  func_type_idxs : FixedArray[Int] // Type index for each function (imported + local)
  type_param_counts : FixedArray[Int] // Primary signature hash for each type
  type_result_counts : FixedArray[Int] // Secondary signature hash for each type
  // Import function metadata for op_call_import
  import_num_params : FixedArray[Int] // Number of params for each imported function
  import_num_results : FixedArray[Int] // Number of results for each imported function
  import_handler_ids : FixedArray[Int] // Host handler id for each imported function
  // Cross-module import resolution for call_indirect
  import_context_ptrs : FixedArray[Int64] // Target context pointer for each import (-1 if not resolved)
  import_target_func_idxs : FixedArray[Int] // Target function index for each import
  // Data segments for bulk memory operations
  data_segments_flat : FixedArray[Byte] // All data segments concatenated
  data_segment_offsets : FixedArray[Int] // Offset of each segment in data_segments_flat
  data_segment_sizes : FixedArray[Int] // Size of each segment (mutable for data.drop)
  // Element segments for bulk table operations
  elem_segments_flat : FixedArray[Int] // All element segments flattened (func indices, -1 for null)
  elem_segment_offsets : FixedArray[Int] // Offset of each segment in elem_segments_flat
  elem_segment_sizes : FixedArray[Int] // Size of each segment
  elem_segment_dropped : FixedArray[Int] // Whether each segment has been dropped (0 or 1)
  // Cross-module call support: pointer to C-allocated CRuntimeContext
  mut context_ptr : Int64
  // Resolved imports for exported-import calls
  resolved_imports : Map[Int, ResolvedImport]
}

// Import Value type from core

///|
using @core {type Value}

///|
fn count_imported_funcs(module_ : @core.Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Func(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
fn get_func_type(module_ : @core.Module, type_idx : Int) -> @core.FuncType {
  match module_.types[type_idx] {
    Func(ft) => ft
    _ => { params: [], results: [] }
  }
}

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
    OutOfBoundsTableAccess => "undefined element" // For call_indirect index out of bounds
    IndirectCallTypeMismatch => "indirect call type mismatch"
    NullFunctionReference => "null function reference"
    StackOverflow => "stack overflow"
    UninitializedElement => "uninitialized element"
    TableBoundsAccess => "out of bounds table access" // For bulk table ops
    NullReference => "null reference"
  }
  @runtime.RuntimeError::from_detail(detail)
}

///|
/// Build import context arrays for cross-module calls
fn build_import_context_arrays(
  num_imported : Int,
  resolved_imports : Map[Int, ResolvedImport],
) -> (FixedArray[Int64], FixedArray[Int]) {
  let import_context_ptrs : FixedArray[Int64] = FixedArray::make(
    if num_imported > 0 {
      num_imported
    } else {
      1
    },
    -1L, // -1 means not resolved
  )
  let import_target_func_idxs : FixedArray[Int] = FixedArray::make(
    if num_imported > 0 {
      num_imported
    } else {
      1
    },
    -1,
  )
  for import_idx, resolved in resolved_imports {
    if import_idx >= 0 && import_idx < num_imported {
      import_context_ptrs[import_idx] = resolved.target_context_ptr
      import_target_func_idxs[import_idx] = resolved.target_func_idx
    }
  }
  (import_context_ptrs, import_target_func_idxs)
}

///|
/// Build a CRuntime instance from a compiled module.
fn build_runtime(
  module_ : @core.Module,
  compiled : CompiledModule,
  resolved_imports : Map[Int, ResolvedImport],
  resolved_imported_globals : Map[Int, UInt64],
) -> CRuntime {
  // Initialize globals from module
  let globals = init_globals(module_, resolved_imported_globals)
  // Initialize memory from module (pre-allocated to max size)
  let (memory, memory_pages, memory_max_size) = init_memory(module_, globals)
  // Initialize tables from module (needs globals for element offset evaluation)
  let (tables, table_logical_sizes, table_max_sizes) = init_tables(
    module_, globals,
  )
  // Flatten tables for C FFI (pass sizes and max_sizes for allocation)
  let (tables_flat, table_offsets, table_sizes, table_max_sizes) = flatten_tables(
    tables, table_logical_sizes, table_max_sizes,
  )
  // Build type info for call_indirect type checking
  let (func_type_idxs, type_param_counts, type_result_counts) = build_type_info(
    module_,
  )
  // Build import function metadata for op_call_import
  let (import_num_params, import_num_results) = build_import_info(module_)
  let import_handler_ids = build_import_handlers(module_)
  // Flatten data segments for bulk memory operations
  let (data_segments_flat, data_segment_offsets, data_segment_sizes) = flatten_data_segments(
    module_,
  )
  // Flatten element segments for bulk table operations
  let (
    elem_segments_flat,
    elem_segment_offsets,
    elem_segment_sizes,
    elem_segment_dropped,
  ) = flatten_elem_segments(module_)
  let num_imported = count_imported_funcs(module_)
  let (import_context_ptrs, import_target_func_idxs) = build_import_context_arrays(
    num_imported, resolved_imports,
  )
  {
    module_,
    compiled,
    globals,
    memory,
    memory_pages,
    memory_max_size,
    tables,
    tables_flat,
    table_offsets,
    table_sizes,
    table_max_sizes,
    func_type_idxs,
    type_param_counts,
    type_result_counts,
    import_num_params,
    import_num_results,
    import_handler_ids,
    import_context_ptrs,
    import_target_func_idxs,
    data_segments_flat,
    data_segment_offsets,
    data_segment_sizes,
    elem_segments_flat,
    elem_segment_offsets,
    elem_segment_sizes,
    elem_segment_dropped,
    context_ptr: 0L, // Will be lazily created when needed for cross-module calls
    resolved_imports,
  }
}

///|
/// Load a module and compile it for C runtime execution.
pub fn CRuntime::load(module_ : @core.Module) -> CRuntime {
  let compiled = compile(module_)
  build_runtime(module_, compiled, {}, {})
}

///|
/// Load a module with resolved imports for cross-module calls.
pub fn CRuntime::load_with_imports(
  module_ : @core.Module,
  resolved_imports : Map[Int, ResolvedImport],
) -> CRuntime {
  let compiled = compile_with_imports(module_, resolved_imports)
  build_runtime(module_, compiled, resolved_imports, {})
}

///|
/// Load a module with resolved imports and imported globals.
pub fn CRuntime::load_with_imports_and_globals(
  module_ : @core.Module,
  resolved_imports : Map[Int, ResolvedImport],
  resolved_imported_globals : Map[Int, UInt64],
) -> CRuntime {
  let compiled = compile_with_imports(module_, resolved_imports)
  build_runtime(module_, compiled, resolved_imports, resolved_imported_globals)
}

///|
/// Get or create the CRuntimeContext pointer for cross-module calls.
/// The context is created lazily on first call and cached.
pub fn CRuntime::get_context_ptr(self : CRuntime) -> Int64 {
  if self.context_ptr == 0L {
    let num_funcs = self.compiled.func_entries.length()
    let num_imported_funcs = self.module_.imports
      .filter(fn(imp) { imp.desc is @core.ImportDesc::Func(_) })
      .length()
    // Current memory size is pages * 65536
    let current_mem_size = self.memory_pages[0] * page_size
    self.context_ptr = c_create_runtime_context(
      self.compiled.code,
      self.globals,
      self.memory,
      current_mem_size,
      self.memory_max_size,
      self.memory_pages,
      self.tables_flat,
      self.table_offsets,
      self.table_sizes,
      self.table_max_sizes,
      self.tables.length(),
      self.compiled.func_entries,
      self.compiled.func_num_locals,
      num_funcs,
      num_imported_funcs,
      self.func_type_idxs,
      self.type_param_counts,
      self.type_result_counts,
      self.module_.types.length(),
      self.import_num_params,
      self.import_num_results,
      self.import_handler_ids,
      self.import_context_ptrs,
      self.import_target_func_idxs,
      self.data_segments_flat,
      self.data_segment_offsets,
      self.data_segment_sizes,
      self.data_segment_sizes.length(),
      self.elem_segments_flat,
      self.elem_segment_offsets,
      self.elem_segment_sizes,
      self.elem_segment_dropped,
      self.elem_segment_sizes.length(),
    )
  }
  self.context_ptr
}

///|
/// Free the CRuntimeContext if it was created.
pub fn CRuntime::free_context(self : CRuntime) -> Unit {
  if self.context_ptr != 0L {
    c_free_runtime_context(self.context_ptr)
    self.context_ptr = 0L
  }
}

///|
/// Get the underlying module.
pub fn CRuntime::get_module(self : CRuntime) -> @core.Module {
  self.module_
}

///|
/// Get the globals array from the runtime (decoded to Value).
pub fn CRuntime::get_globals(self : CRuntime) -> Array[Value] {
  let globals : Array[Value] = []
  let mut idx = 0
  for imp in self.module_.imports {
    match imp.desc {
      Global(gt) => {
        if idx >= 0 && idx < self.globals.length() {
          globals.push(u64_to_value(self.globals[idx], gt.val_type))
        }
        idx += 1
      }
      _ => ()
    }
  }
  for g in self.module_.globals {
    if idx >= 0 && idx < self.globals.length() {
      globals.push(u64_to_value(self.globals[idx], g.type_.val_type))
    }
    idx += 1
  }
  globals
}

///|
/// Flatten tables into a single array for C FFI
/// Returns (tables_flat, table_offsets, table_sizes, table_max_sizes)
fn flatten_tables(
  tables : FixedArray[FixedArray[Int]],
  logical_sizes : FixedArray[Int],
  max_sizes : FixedArray[Int],
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  let num_tables = tables.length()
  // Calculate total size and offsets
  let table_offsets : Array[Int] = []
  let mut total_size = 0
  for i in 0..<num_tables {
    table_offsets.push(total_size)
    // Use max size to determine total allocation
    let max_size = if i < max_sizes.length() { max_sizes[i] } else { 1 }
    total_size += max_size
  }
  // Flatten into single array (allocate to max capacity)
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
    // Copy elements up to the logical size
    let logical_size = if i < logical_sizes.length() {
      logical_sizes[i]
    } else {
      0
    }
    for j in 0..<logical_size {
      tables_flat[offset + j] = table[j]
    }
  }
  (
    tables_flat,
    FixedArray::from_array(table_offsets),
    logical_sizes, // Pass through logical sizes
    max_sizes,
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
/// Flatten element segments into a single int array for C FFI
/// Returns (elem_flat, offsets, sizes, dropped) where sizes tracks segment sizes
/// and dropped tracks whether each segment has been dropped (0 or 1)
fn flatten_elem_segments(
  module_ : @core.Module,
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  let num_segments = module_.elems.length()
  if num_segments == 0 {
    // Return minimal arrays to avoid empty array issues
    return (FixedArray::make(1, -1), [0], [0], [0])
  }
  // Calculate total size and offsets
  let segment_sizes : Array[Int] = []
  let segment_offsets : Array[Int] = []
  let segment_dropped : Array[Int] = []
  let mut total_size = 0
  for elem in module_.elems {
    segment_offsets.push(total_size)
    let size = elem.init.length()
    segment_sizes.push(size)
    // Active element segments are automatically dropped after instantiation
    segment_dropped.push(if elem.is_active { 1 } else { 0 })
    total_size += size
  }
  // Flatten into single int array
  let elem_flat : FixedArray[Int] = FixedArray::make(
    if total_size > 0 {
      total_size
    } else {
      1
    },
    -1,
  )
  for i, elem in module_.elems {
    let offset = segment_offsets[i]
    for j, init_expr in elem.init {
      // Evaluate the init expression to get the function index
      elem_flat[offset + j] = eval_elem_expr(init_expr)
    }
  }
  (
    elem_flat,
    FixedArray::from_array(segment_offsets),
    FixedArray::from_array(segment_sizes),
    FixedArray::from_array(segment_dropped),
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
  // Build func_type_idxs: type index for each function
  let func_type_idxs : Array[Int] = []
  // First, imported function types
  for imp in module_.imports {
    match imp.desc {
      Func(type_idx) => func_type_idxs.push(type_idx.reinterpret_as_int())
      _ => ()
    }
  }
  // Then, local function types (module.funcs contains only local functions)
  for i = 0; i < module_.funcs.length(); i = i + 1 {
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
        type_sig_hash2.push((ft.params.length() << 16) | ft.results.length())
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
/// Host import handler ids for C runtime
let host_import_none : Int = -1

///|
let host_import_spectest_print : Int = 0

///|
let host_import_spectest_print_i32 : Int = 1

///|
let host_import_spectest_print_i64 : Int = 2

///|
let host_import_spectest_print_f32 : Int = 3

///|
let host_import_spectest_print_f64 : Int = 4

///|
let host_import_spectest_print_i32_f32 : Int = 5

///|
let host_import_spectest_print_f64_f64 : Int = 6

///|
let host_import_spectest_print_char : Int = 7

///|
/// Build host import handler ids for imported functions
fn build_import_handlers(module_ : @core.Module) -> FixedArray[Int] {
  let handlers : Array[Int] = []
  for imp in module_.imports {
    match imp.desc {
      Func(_) => {
        let mut handler = host_import_none
        if imp.module_ == b"spectest" {
          if imp.name == b"print" {
            handler = host_import_spectest_print
          } else if imp.name == b"print_i32" {
            handler = host_import_spectest_print_i32
          } else if imp.name == b"print_i64" {
            handler = host_import_spectest_print_i64
          } else if imp.name == b"print_f32" {
            handler = host_import_spectest_print_f32
          } else if imp.name == b"print_f64" {
            handler = host_import_spectest_print_f64
          } else if imp.name == b"print_i32_f32" {
            handler = host_import_spectest_print_i32_f32
          } else if imp.name == b"print_f64_f64" {
            handler = host_import_spectest_print_f64_f64
          } else if imp.name == b"print_char" {
            handler = host_import_spectest_print_char
          }
        }
        handlers.push(handler)
      }
      _ => ()
    }
  }
  if handlers.length() == 0 {
    handlers.push(host_import_none)
  }
  FixedArray::from_array(handlers)
}

///|
/// Page size in bytes (64KB)
let page_size : Int = 65536

///|
/// Default max memory pages when no max is specified (1024 pages = 64MB)
/// Note: Memory is pre-allocated to max size, so this affects memory usage
/// WASM spec allows 65536 pages (4GB) but we use a smaller default for practicality
let default_memory_max_pages : Int = 1024

///|
/// Initialize memory from module's memory section
/// Returns (memory, memory_pages, max_size) where memory is pre-allocated to max size
fn init_memory(
  module_ : @core.Module,
  globals : FixedArray[UInt64],
) -> (FixedArray[Byte], FixedArray[Int], Int) {
  // Get initial and max memory size from first memory (if any)
  let initial_pages = if module_.mems.length() > 0 {
    module_.mems[0].limits.min.to_int()
  } else {
    0
  }
  let max_pages = if module_.mems.length() > 0 {
    match module_.mems[0].limits.max {
      Some(max) => max.to_int()
      None => default_memory_max_pages
    }
  } else {
    default_memory_max_pages
  }
  // Pre-allocate memory to max size (at least 1 byte to avoid empty array)
  let max_size = max_pages * page_size
  let memory = FixedArray::make(
    if max_size > 0 {
      max_size
    } else {
      1
    },
    b'\x00',
  )
  // Initialize active data segments (write to initial region only)
  for data in module_.datas {
    if data.is_active {
      let offset = eval_const_expr_with_globals(data.offset, globals).to_int()
      for i, b in data.init {
        let pos = offset + i
        let initial_size = initial_pages * page_size
        if pos < initial_size {
          memory[pos] = b
        }
      }
    }
  }
  // Use single-element array for memory_pages so it can be mutated by C
  let memory_pages_arr : FixedArray[Int] = [initial_pages]
  (memory, memory_pages_arr, max_size)
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
fn init_globals(
  module_ : @core.Module,
  resolved_imported_globals : Map[Int, UInt64],
) -> FixedArray[UInt64] {
  let num_imported = count_imported_globals(module_)
  let num_local = module_.globals.length()
  let total = num_imported + num_local
  let globals = FixedArray::make(if total > 0 { total } else { 1 }, 0UL)
  // First, initialize imported globals with default values (for spectest compatibility)
  let mut idx = 0
  for imp in module_.imports {
    match imp.desc {
      Global(gt) => {
        let value = match resolved_imported_globals.get(idx) {
          Some(import_value) => import_value
          None =>
            // Default values for spectest globals
            match gt.val_type {
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
/// Default max table size when no max is specified
/// This is a reasonable limit for our implementation
let default_table_max_size : Int = 65536

///|
/// Initialize tables from module's table and elem sections
/// Returns (tables, logical_sizes, max_sizes) where:
/// - tables: arrays allocated to max capacity (or at least 1)
/// - logical_sizes: the actual table sizes (limits.min)
/// - max_sizes: the max capacity for table.grow
fn init_tables(
  module_ : @core.Module,
  globals : FixedArray[UInt64],
) -> (FixedArray[FixedArray[Int]], FixedArray[Int], FixedArray[Int]) {
  let num_imported_tables = count_imported_tables(module_)
  let num_local_tables = module_.tables.length()
  let num_tables = num_imported_tables + num_local_tables
  if num_tables == 0 {
    // Return dummy table, sizes, and max_sizes to avoid empty array issues
    return ([[-1]], [0], [1])
  }
  // Allocate tables and track sizes
  let tables : FixedArray[FixedArray[Int]] = FixedArray::make(num_tables, [-1])
  let logical_sizes_arr : Array[Int] = []
  let max_sizes_arr : Array[Int] = []
  // Initialize imported tables (from import descriptors)
  let mut import_table_idx = 0
  for imp in module_.imports {
    match imp.desc {
      Table(table_type) => {
        let min_size = table_type.limits.min.to_int()
        // When no max is specified, use a default max to allow growth
        let max_size = match table_type.limits.max {
          Some(max) => max.to_int()
          None => default_table_max_size
        }
        // Allocate to max capacity (at least 1 to avoid empty arrays)
        let alloc_size = if max_size > 0 { max_size } else { 1 }
        // Initialize imported table with -1 (null/undefined)
        tables[import_table_idx] = FixedArray::make(alloc_size, -1)
        // Track logical size (actual table size from limits.min)
        logical_sizes_arr.push(min_size)
        max_sizes_arr.push(if max_size > 0 { max_size } else { 1 })
        import_table_idx += 1
      }
      _ => ()
    }
  }
  // Initialize local tables
  for i, table_type in module_.tables {
    let min_size = table_type.limits.min.to_int()
    // When no max is specified, use a default max to allow growth
    let max_size = match table_type.limits.max {
      Some(max) => max.to_int()
      None => default_table_max_size
    }
    // Allocate to max capacity (at least 1 to avoid empty arrays)
    let alloc_size = if max_size > 0 { max_size } else { 1 }
    // Initialize table with -1 (null/undefined)
    tables[num_imported_tables + i] = FixedArray::make(alloc_size, -1)
    // Track logical size (actual table size from limits.min)
    logical_sizes_arr.push(min_size)
    max_sizes_arr.push(if max_size > 0 { max_size } else { 1 })
  }
  // Initialize from element segments
  for elem in module_.elems {
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()
      if table_idx >= 0 && table_idx < tables.length() {
        let offset = eval_const_expr_with_globals(elem.offset, globals).to_int()
        let table = tables[table_idx]
        let logical_size = logical_sizes_arr[table_idx]
        for i, init_expr in elem.init {
          if offset + i < logical_size {
            // Evaluate the init expression to get the function index
            let func_idx = eval_elem_expr(init_expr)
            table[offset + i] = func_idx
          }
        }
      }
    }
  }
  (
    tables,
    FixedArray::from_array(logical_sizes_arr),
    FixedArray::from_array(max_sizes_arr),
  )
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
        // Current memory size is pages * 65536
        let current_mem_size = self.memory_pages[0] * page_size
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
          current_mem_size,
          self.memory_max_size,
          self.memory_pages,
          self.tables_flat,
          self.table_offsets,
          self.table_sizes,
          self.table_max_sizes,
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
          self.import_handler_ids,
          self.import_context_ptrs,
          self.import_target_func_idxs,
          self.data_segments_flat,
          self.data_segment_offsets,
          self.data_segment_sizes,
          self.module_.datas.length(),
          self.elem_segments_flat,
          self.elem_segment_offsets,
          self.elem_segment_sizes,
          self.elem_segment_dropped,
          self.module_.elems.length(),
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
/// Call an external function (in another CRuntime) via resolved import.
/// This is used for exported imports - functions that re-export an import.
fn call_external_function(
  resolved : ResolvedImport,
  args : Array[Value],
) -> Array[Value] raise @runtime.RuntimeError {
  // Convert args to UInt64
  let args_u64 : Array[UInt64] = []
  for arg in args {
    args_u64.push(value_to_u64(arg))
  }
  let args_fixed = FixedArray::from_array(args_u64)

  // Allocate result array
  let result_out : FixedArray[UInt64] = FixedArray::make(
    if resolved.num_results > 0 {
      resolved.num_results
    } else {
      1
    },
    0UL,
  )

  // Call via C FFI with context switching
  let trap_code = c_call_external_ffi(
    resolved.target_context_ptr,
    resolved.target_func_idx,
    args_fixed,
    resolved.num_params,
    result_out,
    resolved.num_results,
  )

  // Check for trap
  let trap = trap_code_from_int(trap_code)
  if trap != TrapCode::None {
    raise trap_to_error(trap)
  }

  // Convert results - we don't have type info, so use I32/I64 based on result count
  // This is a simplification; proper implementation would track types
  let results : Array[Value] = []
  for i in 0..<resolved.num_results {
    // Default to I32 for single results (most common case)
    let raw = result_out[i].reinterpret_as_int64().to_int()
    results.push(I32(raw.reinterpret_as_uint()))
  }
  results
}

///|
/// Call an exported function by name.
pub fn CRuntime::call_compiled(
  self : CRuntime,
  name : Bytes,
  args : Array[Value],
) -> Array[Value] raise @runtime.RuntimeError {
  let name_str = @utf8.decode(name) catch { _ => return [] }
  match self.compiled.exports.get(name_str) {
    Some(export_idx) => {
      let num_imported = count_imported_funcs(self.module_)
      // Check if this is an exported import (negative index)
      if export_idx < 0 {
        // Exported import: -(import_idx + 1) is stored
        let import_idx = -(export_idx + 1)
        // Look up resolved import
        match self.resolved_imports.get(import_idx) {
          Some(resolved) =>
            // Call through to the target module
            call_external_function(resolved, args)
          None =>
            // Unresolved import - shouldn't happen for properly linked modules
            raise @runtime.RuntimeError::from_detail("unresolved import")
        }
      } else {
        // Local function
        let func_idx = export_idx
        // Get function type for result conversion
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
        // Current memory size is pages * 65536
        let current_mem_size = self.memory_pages[0] * page_size
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
          current_mem_size,
          self.memory_max_size,
          self.memory_pages,
          self.tables_flat,
          self.table_offsets,
          self.table_sizes,
          self.table_max_sizes,
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
          self.import_handler_ids,
          self.import_context_ptrs,
          self.import_target_func_idxs,
          self.data_segments_flat,
          self.data_segment_offsets,
          self.data_segment_sizes,
          self.module_.datas.length(),
          self.elem_segments_flat,
          self.elem_segment_offsets,
          self.elem_segment_sizes,
          self.elem_segment_dropped,
          self.module_.elems.length(),
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
    // All reference types - use Ref(None) for null, Ref(Some) for non-null
    // This provides consistency with the test harness expectations
    FuncRef
    | ExternRef
    | AnyRef
    | EqRef
    | I31Ref
    | StructRef
    | ArrayRef
    | NullRef
    | NullFuncRef
    | NullExternRef
    | ExnRef
    | NullExnRef
    | Ref(_, _) =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Ref(None)
      } else {
        Value::Ref(Some(raw.to_uint().reinterpret_as_int()))
      }
    _ => Value::I64(raw)
  }
}
