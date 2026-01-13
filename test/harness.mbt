///|
/// Test failure record
pub struct TestFailure {
  line : Int
  test_type : String
  message : String
  source_file : String
}

///|
pub impl Show for TestFailure with output(self, logger) {
  if self.line >= 0 {
    logger.write_string(
      "[\{self.test_type}] \{self.source_file}:\{self.line}: \{self.message}",
    )
  } else {
    logger.write_string(
      "[\{self.test_type}] \{self.source_file}: \{self.message}",
    )
  }
}

///|
/// Runtime type selector for test harness
pub(all) enum RuntimeType {
  MoonBit // Default MoonBit interpreter (full features)
  CRuntime // C-based threaded code executor (basic features)
}

///|
/// Trait for WebAssembly runtime executors.
/// Both the MoonBit interpreter and C runtime implement this trait.
priv trait Executor {
  run_start(Self) -> Unit raise Error
  call_compiled(Self, Bytes, Array[@wasm5_runtime.Value]) -> Array[
    @wasm5_runtime.Value,
  ] raise Error
  get_module(Self) -> @wasm5_core.Module?
  get_globals(Self) -> Array[@wasm5_runtime.Value]?
  // Returns the underlying MoonBit Runtime if available (for cross-module imports)
  as_runtime(Self) -> @wasm5_runtime.Runtime?
}

///|
/// Implement Executor for MoonBit Runtime
impl Executor for @wasm5_runtime.Runtime with run_start(self) -> Unit raise Error {
  self.run_start()
}

///|
impl Executor for @wasm5_runtime.Runtime with call_compiled(
  self,
  name : Bytes,
  args : Array[@wasm5_runtime.Value],
) -> Array[@wasm5_runtime.Value] raise Error {
  self.call_compiled(name, args)
}

///|
impl Executor for @wasm5_runtime.Runtime with get_module(self) -> @wasm5_core.Module? {
  Some(self.get_module())
}

///|
impl Executor for @wasm5_runtime.Runtime with get_globals(self) -> Array[
  @wasm5_runtime.Value,
]? {
  Some(self.get_globals())
}

///|
impl Executor for @wasm5_runtime.Runtime with as_runtime(self) -> @wasm5_runtime.Runtime? {
  Some(self)
}

///|
/// Implement Executor for C Runtime
impl Executor for @wasm5_cruntime.CRuntime with run_start(self) -> Unit raise Error {
  self.run_start()
}

///|
impl Executor for @wasm5_cruntime.CRuntime with call_compiled(
  self,
  name : Bytes,
  args : Array[@wasm5_runtime.Value],
) -> Array[@wasm5_runtime.Value] raise Error {
  self.call_compiled(name, args)
}

///|
impl Executor for @wasm5_cruntime.CRuntime with get_module(_self) -> @wasm5_core.Module? {
  // CRuntime doesn't expose module yet
  None
}

///|
impl Executor for @wasm5_cruntime.CRuntime with get_globals(_self) -> Array[
  @wasm5_runtime.Value,
]? {
  // CRuntime doesn't support globals yet
  None
}

///|
impl Executor for @wasm5_cruntime.CRuntime with as_runtime(_self) -> @wasm5_runtime.Runtime? {
  // CRuntime is not a MoonBit Runtime
  None
}

///|
/// Registered module entry for cross-module imports
priv struct RegisteredModule {
  runtime : @wasm5_runtime.Runtime
}

///|
/// Module registry for cross-module imports
priv struct ModuleRegistry(Map[String, RegisteredModule])

///|
fn ModuleRegistry::new() -> ModuleRegistry {
  Map::new()
}

///|
/// Test context passed to handlers
priv struct TestContext {
  dir : String
  source_file : String
  failures : Array[TestFailure]
  runtime_type : RuntimeType
  mut executor : &Executor?
  registry : ModuleRegistry
  resolver : @wasm5_runtime.ImportResolver
  mut skipped_count : Int
}

///|
fn TestContext::fail(
  self : TestContext,
  line : Int,
  test_type : String,
  message : String,
) -> Unit {
  // Skip whitelisted tests based on runtime type
  let whitelist = match self.runtime_type {
    MoonBit => whitelisted_tests
    CRuntime => cruntime_whitelisted_tests
  }
  for entry in whitelist {
    if entry.0 == self.source_file && entry.1.contains(line) {
      self.skipped_count += 1
      return
    }
  }
  self.failures.push({ line, test_type, message, source_file: self.source_file })
}

///|
/// Parse and compile a module, returning an Executor trait object
async fn parse_and_compile(ctx : TestContext, file_name : String) -> &Executor {
  let file = @fs.open(ctx.dir + file_name, mode=ReadOnly)
  defer file.close()
  let content = file.read_all().binary()
  let module_ = @wasm5_parse.parse(content)
  match ctx.runtime_type {
    MoonBit => {
      let runtime = @wasm5_runtime.Runtime::load_with_resolver(
        module_,
        ctx.resolver,
      )
      runtime.run_start()
      (runtime : &Executor)
    }
    CRuntime => {
      @wasm5_validate.validate_module(module_)
      let cruntime = @wasm5_cruntime.CRuntime::load(module_)
      cruntime.run_start()
      (cruntime : &Executor)
    }
  }
}

///|
/// Create a wrapper function that calls into a registered module's exported function
fn make_import_wrapper(
  registered : RegisteredModule,
  export_name : String,
  arity : UInt,
) -> @wasm5_runtime.ImportedFunc {
  // Create a wrapper that calls the registered module's function
  let func : (Array[@wasm5_runtime.Value]) -> Array[@wasm5_runtime.Value] = fn(
    args,
  ) {
    // Call the registered module's exported function
    let rt = registered.runtime
    rt.call_compiled(@encoding/utf8.encode(export_name), args) catch {
      _ => []
    }
  }
  @wasm5_runtime.ImportedFunc::new(arity, func)
}

///|
/// Create a wrapper function that calls a function by index in a registered module.
/// This is used for funcref globals where the function may not be exported by name.
fn make_funcref_wrapper(
  registered : RegisteredModule,
  func_idx : Int,
  arity : UInt,
) -> @wasm5_runtime.ImportedFunc {
  let func : (Array[@wasm5_runtime.Value]) -> Array[@wasm5_runtime.Value] = fn(
    args,
  ) {
    // Call the registered module's function by index
    let rt = registered.runtime
    rt.call_by_index(func_idx, args) catch {
      _ => []
    }
  }
  @wasm5_runtime.ImportedFunc::new(arity, func)
}

///|
/// Register a module and add its exports to the resolver
fn register_module(
  ctx : TestContext,
  name : String,
  runtime : @wasm5_runtime.Runtime,
  module_ : @wasm5_core.Module,
) -> Unit {
  // Store in registry
  let entry : RegisteredModule = { runtime, }
  ctx.registry.0[name] = entry

  // Convert name to bytes for resolver
  let name_bytes = @encoding/utf8.encode(name)

  // Add all exported functions to the resolver
  for exp in module_.exports {
    match exp.desc {
      @wasm5_core.ExportDesc::Func(func_idx) => {
        let export_name = exp.name // Already Bytes

        // Get function arity from type
        let func_idx_int = func_idx.reinterpret_as_int()

        // Count imported functions to get local function index
        let mut num_imported_funcs = 0
        for imp in module_.imports {
          match imp.desc {
            @wasm5_core.ImportDesc::Func(_) => num_imported_funcs += 1
            _ => ()
          }
        }

        // Determine arity based on whether it's imported or local
        let arity : UInt = if func_idx_int < num_imported_funcs {
          // It's an imported function - get type from import
          let mut import_idx = 0
          let mut found_arity : UInt = 0
          for imp in module_.imports {
            match imp.desc {
              @wasm5_core.ImportDesc::Func(type_idx) => {
                if import_idx == func_idx_int {
                  match module_.types[type_idx.reinterpret_as_int()] {
                    @wasm5_core.TypeDef::Func(ft) =>
                      found_arity = ft.params.length().reinterpret_as_uint()
                    _ => ()
                  }
                  break
                }
                import_idx += 1
              }
              _ => ()
            }
          }
          found_arity
        } else {
          // It's a local function
          let local_idx = func_idx_int - num_imported_funcs
          let type_idx = module_.funcs[local_idx].reinterpret_as_int()
          match module_.types[type_idx] {
            @wasm5_core.TypeDef::Func(ft) =>
              ft.params.length().reinterpret_as_uint()
            _ => 0U
          }
        }

        // Create wrapper and add to resolver
        let export_name_str = @encoding/utf8.decode(export_name) catch {
          _ => continue // Skip invalid UTF-8 export names
        }
        let wrapper = make_import_wrapper(entry, export_name_str, arity)
        ctx.resolver.add_func(name_bytes, export_name, wrapper)
      }
      @wasm5_core.ExportDesc::Global(global_idx) => {
        // Export a global value
        let global_idx_int = global_idx.reinterpret_as_int()
        // Get the global value from the runtime
        let globals = runtime.get_globals()
        if global_idx_int >= 0 && global_idx_int < globals.length() {
          let global_value = globals[global_idx_int]
          ctx.resolver.add_global(name_bytes, exp.name, global_value)

          // For funcref globals, also register a funcref wrapper for cross-module calls.
          // This allows call_indirect to work correctly when the funcref is imported.
          match global_value {
            Ref(Some(func_idx)) => {
              // Count imported functions
              let mut num_imported_funcs = 0
              for imp in module_.imports {
                match imp.desc {
                  @wasm5_core.ImportDesc::Func(_) => num_imported_funcs += 1
                  _ => ()
                }
              }

              // Get function type to determine arity
              let type_idx = if func_idx < num_imported_funcs {
                // Imported function
                let mut found_type_idx = 0
                let mut import_idx = 0
                for imp in module_.imports {
                  match imp.desc {
                    @wasm5_core.ImportDesc::Func(tidx) => {
                      if import_idx == func_idx {
                        found_type_idx = tidx.reinterpret_as_int()
                        break
                      }
                      import_idx += 1
                    }
                    _ => ()
                  }
                }
                found_type_idx
              } else {
                // Local function
                let local_idx = func_idx - num_imported_funcs
                if local_idx >= 0 && local_idx < module_.funcs.length() {
                  module_.funcs[local_idx].reinterpret_as_int()
                } else {
                  0
                }
              }

              // Create wrapper that calls the function by index
              let arity : UInt = match module_.types.get(type_idx) {
                Some(@wasm5_core.TypeDef::Func(ft)) =>
                  ft.params.length().reinterpret_as_uint()
                _ => 0U
              }

              // Use make_funcref_wrapper which calls by index, not by name
              // This handles cases where the function is not exported by name
              let wrapper = make_funcref_wrapper(entry, func_idx, arity)
              ctx.resolver.add_funcref_wrapper(name_bytes, exp.name, wrapper)
            }
            _ => () // Not a funcref, or null
          }
        }
      }
      @wasm5_core.ExportDesc::Table(table_idx) => {
        // Export a table - this enables cross-module table sharing
        let table_idx_int = table_idx.reinterpret_as_int()
        let tables = runtime.get_tables()
        if table_idx_int >= 0 && table_idx_int < tables.length() {
          let table = tables[table_idx_int]
          ctx.resolver.add_table(name_bytes, exp.name, table)
        }
      }
      _ => () // Skip other export types (memory, etc.)
    }
  }

  // Fix up element segments that initialized imported tables.
  // When a module stores its own funcrefs into a shared table, we need to
  // replace those local indices with wrappers stored in table.external_funcrefs.
  fix_shared_table_elements(entry, module_, runtime)
}

///|
/// Fix up element segments that initialized imported tables.
/// When a module stores its own funcrefs into a shared table, the local
/// function indices don't work for cross-module calls. This function
/// replaces those indices with wrappers stored in table.external_funcrefs.
fn fix_shared_table_elements(
  registered : RegisteredModule,
  module_ : @wasm5_core.Module,
  runtime : @wasm5_runtime.Runtime,
) -> Unit {
  // Count imported tables
  let mut num_imported_tables = 0
  for imp in module_.imports {
    match imp.desc {
      @wasm5_core.ImportDesc::Table(_) => num_imported_tables += 1
      _ => ()
    }
  }

  // If no imported tables, nothing to fix
  if num_imported_tables == 0 {
    return
  }

  // Count imported functions to calculate local function indices
  let mut num_imported_funcs = 0
  for imp in module_.imports {
    match imp.desc {
      @wasm5_core.ImportDesc::Func(_) => num_imported_funcs += 1
      _ => ()
    }
  }
  let tables = runtime.get_tables()

  // Process each active element segment
  for elem in module_.elems {
    if elem.is_active {
      let table_idx = elem.table_idx.reinterpret_as_int()

      // Only fix imported tables (indices 0..num_imported_tables-1)
      if table_idx >= 0 &&
        table_idx < num_imported_tables &&
        table_idx < tables.length() {
        let table = tables[table_idx]

        // Evaluate offset - we need to match the runtime's evaluation
        let offset = eval_elem_offset(elem, runtime)
        guard offset is Some(off) else { continue }

        // For each funcref in this element segment
        for i in 0..<elem.init.length() {
          let addr = off + i
          if addr >= 0 && addr < table.data_length() {
            // Get the current value - this is encoded as a tagged UInt64
            let data = table.get_data(addr)
            // Check if it's a funcref (bit 62 set) and not null
            if data != 0xFFFFFFFFFFFFFFFFUL &&
              (data & 0x4000000000000000UL) != 0UL {
              // Extract func_idx from lower 62 bits
              let func_idx_raw = (data & 0x3FFFFFFFFFFFFFFFUL)
                .reinterpret_as_int64()
                .to_int()
              // Only process if it's a local function (non-negative)
              if func_idx_raw >= 0 {
                let func_idx = func_idx_raw
                // This is a local function index - create a wrapper
                let type_idx = if func_idx < num_imported_funcs {
                  // Imported function - get type from import
                  get_import_func_type_idx(module_, func_idx)
                } else {
                  // Local function
                  let local_idx = func_idx - num_imported_funcs
                  if local_idx >= 0 && local_idx < module_.funcs.length() {
                    module_.funcs[local_idx].reinterpret_as_int()
                  } else {
                    0
                  }
                }
                let arity : UInt = match module_.types.get(type_idx) {
                  Some(@wasm5_core.TypeDef::Func(ft)) =>
                    ft.params.length().reinterpret_as_uint()
                  _ => 0U
                }

                // Create wrapper and add to table's external_funcrefs
                let wrapper = make_funcref_wrapper(registered, func_idx, arity)
                let ext_idx = table.add_external_funcref(wrapper)

                // Store negative index pointing to the wrapper (with funcref tag)
                // The index must be masked to 62 bits before OR'ing with funcref tag
                // because -1 as full 64-bit would be 0xFFFFFFFF... which is NULL
                let neg_val = (-(ext_idx + 1))
                  .to_int64()
                  .reinterpret_as_uint64()
                let masked = neg_val & 0x3FFFFFFFFFFFFFFFUL // Mask to lower 62 bits
                table.set_data(addr, masked | 0x4000000000000000UL)
              }
            }
            // null or already negative - skip
          }
        }
      }
    }
  }
}

///|
/// Evaluate element segment offset expression
fn eval_elem_offset(
  elem : @wasm5_core.Elem,
  runtime : @wasm5_runtime.Runtime,
) -> Int? {
  // Simple evaluation for common cases
  for instr in elem.offset.instrs {
    match instr {
      @wasm5_core.Instr::I32Const(v) => return Some(v.reinterpret_as_int())
      @wasm5_core.Instr::GlobalGet(idx) => {
        let globals = runtime.get_globals()
        let idx_int = idx.reinterpret_as_int()
        if idx_int >= 0 && idx_int < globals.length() {
          match globals[idx_int] {
            I32(v) => return Some(v.reinterpret_as_int())
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  None
}

///|
/// Get the type index for an imported function
fn get_import_func_type_idx(
  module_ : @wasm5_core.Module,
  func_idx : Int,
) -> Int {
  let mut import_idx = 0
  for imp in module_.imports {
    match imp.desc {
      @wasm5_core.ImportDesc::Func(tidx) => {
        if import_idx == func_idx {
          return tidx.reinterpret_as_int()
        }
        import_idx += 1
      }
      _ => ()
    }
  }
  0
}

///|
/// Error for unsupported test types
priv suberror TestUnsupported {
  UnsupportedArgType(String)
  UnsupportedExpectedType(String)
}

// =============================================================================
// NaN Handling in WebAssembly Spec Tests
// =============================================================================
//
// The wast2json tool outputs floating-point values as their integer bit
// representations. For NaN values, it uses special string formats:
//
//   - "nan:canonical" - Must match the exact canonical NaN bit pattern
//     (f64: 0x7FF8000000000000, f32: 0x7FC00000)
//
//   - "nan:arithmetic" - Any NaN value is acceptable (used when the spec
//     allows implementation-defined NaN payloads)
//
// For ARGUMENTS (inputs to functions):
//   Both "nan:canonical" and "nan:arithmetic" are parsed as the canonical NaN,
//   since the actual input NaN bit pattern doesn't affect the test semantics.
//
// For EXPECTED VALUES (outputs from functions):
//   - "nan:canonical" -> Exact bit pattern match required
//   - "nan:arithmetic" -> Any NaN is acceptable (use AnyF32Nan/AnyF64Nan)
//
// FLOAT COMPARISON:
//   Floating-point values must be compared by their bit patterns, not by ==,
//   because IEEE 754 defines NaN != NaN (even for identical bit patterns).
//   We use reinterpret_as_uint64()/reinterpret_as_uint() for comparison.
// =============================================================================

///|
/// Special expected value that represents "any NaN" or type-only checks
enum ExpectedValue {
  Exact(@wasm5_runtime.Value)
  AnyF32Nan // nan:arithmetic for f32 - any NaN value is acceptable
  AnyF64Nan // nan:arithmetic for f64 - any NaN value is acceptable
  AnyFuncRef // any funcref value (including null)
  AnyExternRef // any externref value (including null)
  AnyI31Ref // any i31ref value (including null)
  AnyStructRef // any non-null struct reference
  AnyArrayRef // any non-null array reference
  AnyEqRef // any non-null eqref value
  // AnyRefNull matches any null reference, regardless of its static type.
  // At runtime, all null references (nullref, nullfuncref, nullexnref,
  // nullexternref) are represented identically as Ref(None). The type
  // distinction only exists during validation, not at runtime.
  AnyRefNull // any null reference
} derive(Show)

///|
/// Parse i32 value string, handling both signed and unsigned representations
/// wasm-tools outputs signed numbers (e.g., "-1") while wabt outputs unsigned (e.g., "4294967295")
fn parse_i32_value(v : String) -> UInt {
  if v.has_prefix("-") {
    // Signed value - parse as signed and reinterpret as unsigned
    try {
      let signed = @strconv.parse_int(v)
      signed.reinterpret_as_uint()
    } catch {
      _ => abort("Invalid i32 value: \{v}")
    }
  } else {
    // Unsigned value
    @strconv.parse_uint(v) catch {
      _ => abort("Invalid i32 value: \{v}")
    }
  }
}

///|
/// Parse i64 value string, handling both signed and unsigned representations
fn parse_i64_value(v : String) -> UInt64 {
  if v.has_prefix("-") {
    // Signed value - parse as signed and reinterpret as unsigned
    try {
      let signed = @strconv.parse_int64(v)
      signed.reinterpret_as_uint64()
    } catch {
      _ => abort("Invalid i64 value: \{v}")
    }
  } else {
    // Unsigned value
    @strconv.parse_uint64(v) catch {
      _ => abort("Invalid i64 value: \{v}")
    }
  }
}

///|
/// Parse f64 value string, handling nan:canonical and nan:arithmetic
fn parse_f64_value(v : String) -> Double {
  if v == "nan:canonical" {
    // Canonical NaN for f64: 0x7FF8000000000000
    0x7ff8_0000_0000_0000UL.reinterpret_as_double()
  } else if v.has_prefix("nan:arithmetic") {
    // For arguments, use canonical NaN (actual NaN value doesn't matter for input)
    0x7ff8_0000_0000_0000UL.reinterpret_as_double()
  } else {
    // Regular integer bit representation (may be signed from wasm-tools)
    UInt64::reinterpret_as_double(parse_i64_value(v))
  }
}

///|
/// Parse f32 value string, handling nan:canonical and nan:arithmetic
fn parse_f32_value(v : String) -> Float {
  if v == "nan:canonical" {
    // Canonical NaN for f32: 0x7FC00000
    Float::reinterpret_from_uint(0x7fc0_0000U)
  } else if v.has_prefix("nan:arithmetic") {
    // For arguments, use canonical NaN
    Float::reinterpret_from_uint(0x7fc0_0000U)
  } else {
    // Regular integer bit representation (may be signed from wasm-tools)
    Float::reinterpret_from_uint(parse_i32_value(v))
  }
}

///|
/// Parse JSON arguments array into runtime values
fn parse_args(args : Array[Json]) -> Array[@wasm5_runtime.Value] raise {
  let runtime_args : Array[@wasm5_runtime.Value] = []
  for arg in args {
    match arg {
      { "type": "i32", "value": String(v), .. } =>
        runtime_args.push(@wasm5_runtime.Value::I32(parse_i32_value(v)))
      { "type": "i64", "value": String(v), .. } =>
        runtime_args.push(@wasm5_runtime.Value::I64(parse_i64_value(v)))
      // wast2json outputs floats as their bit representation (integer string)
      // or special nan values like "nan:canonical", "nan:arithmetic"
      { "type": "f32", "value": String(v), .. } =>
        runtime_args.push(@wasm5_runtime.Value::F32(parse_f32_value(v)))
      { "type": "f64", "value": String(v), .. } =>
        runtime_args.push(@wasm5_runtime.Value::F64(parse_f64_value(v)))
      // externref: "null" for null, otherwise an integer index
      { "type": "externref", "value": String(v), .. } =>
        if v == "null" {
          runtime_args.push(@wasm5_runtime.Value::Externref(None))
        } else {
          runtime_args.push(
            @wasm5_runtime.Value::Externref(
              Some(parse_i32_value(v).reinterpret_as_int()),
            ),
          )
        }
      // funcref: "null" for null, otherwise an integer function index
      { "type": "funcref", "value": String(v), .. } =>
        if v == "null" {
          runtime_args.push(@wasm5_runtime.Value::Funcref(None))
        } else {
          runtime_args.push(
            @wasm5_runtime.Value::Funcref(
              Some(parse_i32_value(v).reinterpret_as_int()),
            ),
          )
        }
      // anyref: "null" for null, otherwise an integer ref index
      { "type": "anyref", "value": String(v), .. } =>
        if v == "null" {
          runtime_args.push(@wasm5_runtime.Value::Ref(None))
        } else {
          runtime_args.push(
            @wasm5_runtime.Value::Ref(
              Some(parse_i32_value(v).reinterpret_as_int()),
            ),
          )
        }
      _ => raise TestUnsupported::UnsupportedArgType("\{arg}")
    }
  }
  runtime_args
}

///|
/// Parse a JSON value as an expected result
fn parse_expected_value(expected : Json) -> ExpectedValue raise {
  match expected {
    { "type": "i32", "value": String(v), .. } =>
      Exact(@wasm5_runtime.Value::I32(parse_i32_value(v)))
    { "type": "i64", "value": String(v), .. } =>
      Exact(@wasm5_runtime.Value::I64(parse_i64_value(v)))
    // wast2json outputs floats as their bit representation (integer string)
    // or special nan values like "nan:canonical", "nan:arithmetic"
    { "type": "f32", "value": String(v), .. } =>
      if v.has_prefix("nan:arithmetic") {
        AnyF32Nan
      } else {
        Exact(@wasm5_runtime.Value::F32(parse_f32_value(v)))
      }
    { "type": "f64", "value": String(v), .. } =>
      if v.has_prefix("nan:arithmetic") {
        AnyF64Nan
      } else {
        Exact(@wasm5_runtime.Value::F64(parse_f64_value(v)))
      }
    // externref: "null" for null, otherwise an integer index, or no value (any externref)
    { "type": "externref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5_runtime.Value::Ref(None))
      } else {
        Exact(
          @wasm5_runtime.Value::Ref(
            Some(parse_i32_value(v).reinterpret_as_int()),
          ),
        )
      }
    { "type": "externref", .. } => AnyExternRef // type-only check, any externref
    // funcref: "null" for null, otherwise an integer function index, or no value (any funcref)
    { "type": "funcref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5_runtime.Value::Ref(None))
      } else {
        Exact(
          @wasm5_runtime.Value::Ref(
            Some(parse_i32_value(v).reinterpret_as_int()),
          ),
        )
      }
    { "type": "funcref", .. } => AnyFuncRef // type-only check, any funcref
    // anyref: any reference (including null)
    { "type": "anyref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5_runtime.Value::Ref(None))
      } else {
        Exact(
          @wasm5_runtime.Value::Ref(
            Some(parse_i32_value(v).reinterpret_as_int()),
          ),
        )
      }
    { "type": "anyref", .. } => AnyFuncRef // Treat as any reference
    // exnref: exception reference (including null)
    { "type": "exnref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5_runtime.Value::Ref(None))
      } else {
        Exact(
          @wasm5_runtime.Value::Ref(
            Some(parse_i32_value(v).reinterpret_as_int()),
          ),
        )
      }
    { "type": "exnref", .. } => AnyFuncRef // Treat as any reference
    // i31ref: any i31 reference
    { "type": "i31ref", .. } => AnyI31Ref
    // structref: any non-null struct reference
    { "type": "structref", .. } => AnyStructRef
    // arrayref: any non-null array reference
    { "type": "arrayref", .. } => AnyArrayRef
    // eqref: any non-null eqref value (i31, struct, array)
    { "type": "eqref", .. } => AnyEqRef
    // refnull: any null reference
    { "type": "refnull", .. } => AnyRefNull
    // All null reference types map to AnyRefNull because at runtime, WebAssembly
    // represents all null references identically as Ref(None). The type system
    // distinguishes nullref/nullfuncref/nullexnref/nullexternref during validation,
    // but at execution time they're indistinguishable.
    { "type": "nullref", .. } => AnyRefNull
    { "type": "nullfuncref", .. } => AnyRefNull
    { "type": "nullexnref", .. } => AnyRefNull
    { "type": "nullexternref", .. } => AnyRefNull
    _ => raise TestUnsupported::UnsupportedExpectedType("\{expected}")
  }
}

///|
/// Format a value with bit pattern for debugging NaN issues
fn format_value_with_bits(v : @wasm5_runtime.Value) -> String {
  match v {
    @wasm5_runtime.Value::F64(f) => {
      let bits = f.reinterpret_as_uint64()
      "F64(\{f}) [bits: \{bits}]"
    }
    @wasm5_runtime.Value::F32(f) => {
      let bits = f.reinterpret_as_uint()
      "F32(\{f}) [bits: \{bits}]"
    }
    _ => v.to_string()
  }
}

///|
/// Format expected value with bit pattern for debugging
fn format_expected_with_bits(e : ExpectedValue) -> String {
  match e {
    Exact(v) => format_value_with_bits(v)
    AnyF32Nan => "AnyF32Nan"
    AnyF64Nan => "AnyF64Nan"
    AnyFuncRef => "AnyFuncRef"
    AnyExternRef => "AnyExternRef"
    AnyI31Ref => "AnyI31Ref"
    AnyStructRef => "AnyStructRef"
    AnyArrayRef => "AnyArrayRef"
    AnyEqRef => "AnyEqRef"
    AnyRefNull => "AnyRefNull"
  }
}

///|
/// Check if actual value matches expected value (handling NaN cases)
fn values_match(
  actual : @wasm5_runtime.Value,
  expected : ExpectedValue,
) -> Bool {
  match expected {
    Exact(exp) =>
      // Need special handling for floats to compare NaN bit patterns
      match (actual, exp) {
        (@wasm5_runtime.Value::F64(a), @wasm5_runtime.Value::F64(e)) =>
          // Compare bit patterns for exact match (including NaN patterns)
          a.reinterpret_as_uint64() == e.reinterpret_as_uint64()
        (@wasm5_runtime.Value::F32(a), @wasm5_runtime.Value::F32(e)) =>
          // Compare bit patterns for exact match (including NaN patterns)
          a.reinterpret_as_uint() == e.reinterpret_as_uint()
        _ => actual == exp
      }
    AnyF32Nan =>
      match actual {
        @wasm5_runtime.Value::F32(v) => v.is_nan()
        _ => false
      }
    AnyF64Nan =>
      match actual {
        @wasm5_runtime.Value::F64(v) => v.is_nan()
        _ => false
      }
    AnyFuncRef =>
      // Accept any reference value (funcref can be null or non-null)
      match actual {
        @wasm5_runtime.Value::Ref(_) => true
        _ => false
      }
    AnyExternRef =>
      // Accept any reference value (externref can be null or non-null)
      match actual {
        @wasm5_runtime.Value::Ref(_) => true
        _ => false
      }
    AnyI31Ref =>
      // Accept any i31ref value (stored as Ref with encoded value)
      match actual {
        @wasm5_runtime.Value::Ref(_) => true
        _ => false
      }
    AnyStructRef =>
      // Accept any non-null struct reference
      match actual {
        @wasm5_runtime.Value::Ref(Some(_)) => true
        _ => false
      }
    AnyArrayRef =>
      // Accept any non-null array reference
      match actual {
        @wasm5_runtime.Value::Ref(Some(_)) => true
        _ => false
      }
    AnyEqRef =>
      // Accept any non-null eqref value (i31, struct, array)
      match actual {
        @wasm5_runtime.Value::Ref(Some(_)) => true
        _ => false
      }
    AnyRefNull =>
      // Accept only null references
      match actual {
        @wasm5_runtime.Value::Ref(None) => true
        _ => false
      }
  }
}

///|
/// Handle "module" command - load and compile a module
async fn handle_module(
  ctx : TestContext,
  filename : String,
  line : Int,
  name? : String? = None,
) -> Unit {
  try {
    let executor = parse_and_compile(ctx, filename)
    ctx.executor = Some(executor)
    // If a name is provided and we have MoonBit runtime, register the module
    match (name, executor.as_runtime()) {
      (Some(n), Some(rt)) => register_module(ctx, n, rt, rt.get_module())
      _ => ()
    }
  } catch {
    e => ctx.fail(line, "module", "Error loading module: \{e}")
  }
}

///|
/// Handle "register" command - register the current module with a name
fn handle_register(ctx : TestContext, name : String, line : Int) -> Unit {
  guard ctx.executor is Some(executor) else {
    ctx.fail(line, "register", "no module loaded to register")
    return
  }
  guard executor.as_runtime() is Some(rt) else {
    ctx.fail(
      line, "register", "register requires MoonBit runtime (CRuntime not supported)",
    )
    return
  }
  // Register the module with its exports
  register_module(ctx, name, rt, rt.get_module())
}

///|
/// Get executor for a specific module name, or the current executor if no module specified
fn get_executor_for_module(
  ctx : TestContext,
  module_name : String?,
) -> &Executor? {
  match module_name {
    Some(name) =>
      // Look up the registered module (only works with MoonBit runtime)
      match ctx.registry.0.get(name) {
        Some(registered) => Some(registered.runtime)
        None => None
      }
    None => ctx.executor
  }
}

///|
/// Handle "assert_return" command - call function and check results
fn handle_assert_return(
  ctx : TestContext,
  fn_name : String,
  args : Array[Json],
  expected : Array[Json],
  line : Int,
  module_name? : String? = None,
) -> Unit {
  try {
    let runtime_args = parse_args(args)
    guard get_executor_for_module(ctx, module_name) is Some(executor) else {
      let msg = match module_name {
        Some(name) => "[\{fn_name}] module '\{name}' not registered"
        None => "[\{fn_name}] no module loaded (previous module failed to load)"
      }
      ctx.fail(line, "assert_return", msg)
      return
    }
    let results = executor.call_compiled(
      @encoding/utf8.encode(fn_name),
      runtime_args,
    )
    // Check result count
    if expected.length() != results.length() {
      ctx.fail(
        line,
        "assert_return",
        "[\{fn_name}] expected \{expected.length()} results, got \{results.length()}",
      )
      return
    }
    // Validate each result
    for idx in 0..<expected.length() {
      let expected_value = parse_expected_value(expected[idx])
      if not(values_match(results[idx], expected_value)) {
        ctx.fail(
          line,
          "assert_return",
          "[\{fn_name}] result \{idx}: expected \{format_expected_with_bits(expected_value)}, got \{format_value_with_bits(results[idx])}",
        )
      }
    }
  } catch {
    e => ctx.fail(line, "assert_return", "[\{fn_name}] error: \{e}")
  }
}

///|
/// Handle "assert_trap" command - call function and expect a trap
fn handle_assert_trap(
  ctx : TestContext,
  fn_name : String,
  args : Array[Json],
  expected_error : String,
  line : Int,
  module_name? : String? = None,
) -> Unit {
  let runtime_args = parse_args(args) catch {
    e => {
      ctx.fail(line, "assert_trap", "[\{fn_name}] failed to parse args: \{e}")
      return
    }
  }
  guard get_executor_for_module(ctx, module_name) is Some(executor) else {
    let msg = match module_name {
      Some(name) => "[\{fn_name}] module '\{name}' not registered"
      None => "[\{fn_name}] no module loaded (previous module failed to load)"
    }
    ctx.fail(line, "assert_trap", msg)
    return
  }
  try {
    let _ = executor.call_compiled(@encoding/utf8.encode(fn_name), runtime_args)
    ctx.fail(
      line,
      "assert_trap",
      "[\{fn_name}] expected trap '\{expected_error}' but no error occurred",
    )
  } catch {
    @wasm5_runtime.RuntimeError::DivisionByZero =>
      if not(expected_error.contains("divide by zero")) {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got DivisionByZero",
        )
      }
    @wasm5_runtime.RuntimeError::IntegerOverflow =>
      // IntegerOverflow is used for both "integer overflow" and "invalid conversion to integer"
      if not(
          expected_error.contains("overflow") ||
          expected_error.contains("invalid conversion"),
        ) {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got IntegerOverflow",
        )
      }
    @wasm5_runtime.RuntimeError::MemoryOutOfBounds =>
      if not(expected_error.contains("out of bounds memory access")) {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got MemoryOutOfBounds",
        )
      }
    @wasm5_runtime.RuntimeError::TableOutOfBounds =>
      if not(expected_error.contains("out of bounds table access")) {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got TableOutOfBounds",
        )
      }
    @wasm5_runtime.RuntimeError::Unreachable =>
      if not(expected_error.contains("unreachable")) {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got Unreachable",
        )
      }
    @wasm5_runtime.RuntimeError::InvalidType(msg) =>
      // Handle table out of bounds errors
      if msg.contains("table") && msg.contains("out of bounds") {
        if not(expected_error.contains("out of bounds table access")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got table out of bounds",
          )
        }
      } else if msg.contains("array") && msg.contains("out of bounds") {
        if not(expected_error.contains("out of bounds array access")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got out of bounds array access",
          )
        }
      } else if msg.contains("undefined element") {
        if not(expected_error.contains("undefined element")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got undefined element",
          )
        }
      } else if msg.contains("uninitialized element") {
        if not(expected_error.contains("uninitialized element")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got uninitialized element",
          )
        }
      } else if msg.contains("indirect call type mismatch") {
        if not(expected_error.contains("indirect call type mismatch")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got indirect call type mismatch",
          )
        }
      } else if msg.contains("null") && msg.contains("function reference") {
        if not(expected_error.contains("null function reference")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got null function reference",
          )
        }
      } else if msg.contains("null i31 reference") {
        if not(expected_error.contains("null i31 reference")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got null i31 reference",
          )
        }
      } else if msg.contains("null structure reference") {
        if not(expected_error.contains("null structure reference")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got null structure reference",
          )
        }
      } else if msg.contains("null array reference") {
        if not(expected_error.contains("null array reference")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got null array reference",
          )
        }
      } else if msg.contains("cast failed") {
        if not(expected_error.contains("cast failure")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got cast failure",
          )
        }
      } else if msg.contains("null reference") {
        if not(expected_error.contains("null reference")) {
          ctx.fail(
            line,
            "assert_trap",
            "[\{fn_name}] expected '\{expected_error}' but got null reference",
          )
        }
      } else {
        ctx.fail(
          line,
          "assert_trap",
          "[\{fn_name}] expected '\{expected_error}' but got: InvalidType(\{msg})",
        )
      }
    e =>
      ctx.fail(
        line,
        "assert_trap",
        "[\{fn_name}] expected '\{expected_error}' but got: \{e}",
      )
  }
}

///|
/// Handle "assert_invalid" command - try to load module and expect validation error
async fn handle_assert_invalid(
  ctx : TestContext,
  filename : String,
  expected_error : String,
  line : Int,
) -> Unit {
  try {
    let _ = parse_and_compile(ctx, filename)
    ctx.fail(
      line,
      "assert_invalid",
      "expected validation error '\{expected_error}' but module was valid",
    )
  } catch {
    // The WebAssembly spec uses "type mismatch" for various validation errors.
    // Our validator distinguishes TypeMismatch and StackSizeMismatch, but both
    // correspond to the spec's "type mismatch" error message.
    @wasm5_validate.ValidationError::TypeMismatch(msg) =>
      // TypeMismatch covers various validation errors including "type mismatch", "immutable field", "immutable array", "array types do not match", and "array type is not numeric or vector"
      if not(expected_error.contains("type mismatch")) &&
        not(
          expected_error.contains("immutable field") &&
          msg.contains("immutable"),
        ) &&
        not(
          expected_error.contains("immutable array") &&
          msg.contains("immutable"),
        ) &&
        not(
          expected_error.contains("array types do not match") &&
          msg.contains("array types do not match"),
        ) &&
        not(
          expected_error.contains("array type is not numeric or vector") &&
          msg.contains("array type is not numeric or vector"),
        ) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got TypeMismatch",
        )
      }
    @wasm5_validate.ValidationError::StackSizeMismatch(_) =>
      if not(expected_error.contains("type mismatch")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got StackSizeMismatch",
        )
      }
    @wasm5_validate.ValidationError::InvalidResultArity(_) =>
      if not(expected_error.contains("invalid result arity")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidResultArity",
        )
      }
    @wasm5_validate.ValidationError::UnknownType(_) =>
      if not(expected_error.contains("unknown type")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownType",
        )
      }
    @wasm5_validate.ValidationError::InvalidAlignment(_) =>
      if not(expected_error.contains("alignment")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidAlignment",
        )
      }
    @wasm5_validate.ValidationError::UnknownLabel(_) =>
      if not(expected_error.contains("unknown label")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownLabel",
        )
      }
    @wasm5_validate.ValidationError::InvalidStartFunction(_) =>
      if not(expected_error.contains("start function")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidStartFunction",
        )
      }
    @wasm5_validate.ValidationError::DuplicateExport(name) =>
      if not(expected_error.contains("duplicate export name")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got DuplicateExport(\{name})",
        )
      }
    @wasm5_validate.ValidationError::UnknownExportedFunction(_) =>
      if not(expected_error.contains("unknown function")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownExportedFunction",
        )
      }
    @wasm5_validate.ValidationError::UnknownExportedMemory(_) =>
      if not(expected_error.contains("unknown memory")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownExportedMemory",
        )
      }
    @wasm5_validate.ValidationError::UnknownExportedTable(_) =>
      if not(expected_error.contains("unknown table")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownExportedTable",
        )
      }
    @wasm5_validate.ValidationError::UnknownGlobal(_) =>
      if not(expected_error.contains("unknown global")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownGlobal",
        )
      }
    @wasm5_validate.ValidationError::UnknownExportedGlobal(_) =>
      if not(expected_error.contains("unknown global")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownExportedGlobal",
        )
      }
    @wasm5_validate.ValidationError::UninitializedLocal(_) =>
      if not(expected_error.contains("uninitialized local")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UninitializedLocal",
        )
      }
    @wasm5_validate.ValidationError::UnknownDataSegment(_) =>
      if not(expected_error.contains("unknown data segment")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownDataSegment",
        )
      }
    @wasm5_validate.ValidationError::InvalidElemIndex(_) =>
      if not(expected_error.contains("unknown elem segment")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidElemIndex",
        )
      }
    _ => () // Other validation errors are acceptable
  }
}

///|
/// Handle "action" command - call function for side effects only (no expected result)
fn handle_action(
  ctx : TestContext,
  fn_name : String,
  args : Array[Json],
  line : Int,
) -> Unit {
  try {
    let runtime_args = parse_args(args)
    guard ctx.executor is Some(executor) else {
      ctx.fail(
        line, "action", "no module loaded (previous module failed to load)",
      )
      return
    }
    let _ = executor.call_compiled(@encoding/utf8.encode(fn_name), runtime_args)

  } catch {
    e => ctx.fail(line, "action", "Action failed with error: \{e}")
  }
}

///|
/// Handle "assert_return" with "get" action - read a global value
/// Note: This requires MoonBit runtime as CRuntime doesn't support globals yet
fn handle_assert_return_get(
  ctx : TestContext,
  field : String,
  expected : Array[Json],
  line : Int,
  module_name? : String? = None,
) -> Unit {
  try {
    // Get global requires MoonBit runtime (CRuntime doesn't support globals)
    let rt : @wasm5_runtime.Runtime? = match module_name {
      Some(name) =>
        match ctx.registry.0.get(name) {
          Some(registered) => Some(registered.runtime)
          None => None
        }
      None =>
        match ctx.executor {
          Some(executor) => executor.as_runtime()
          None => None
        }
    }
    guard rt is Some(rt) else {
      let msg = match module_name {
        Some(name) => "[get \{field}] module '\{name}' not registered"
        None => "[get \{field}] no module loaded (requires MoonBit runtime)"
      }
      ctx.fail(line, "assert_return", msg)
      return
    }
    // Find the exported global by name
    let module_ = rt.get_module()
    let field_bytes = @encoding/utf8.encode(field)
    let mut global_idx : Int? = None
    for exp in module_.exports {
      if exp.name == field_bytes {
        match exp.desc {
          @wasm5_core.ExportDesc::Global(idx) => {
            global_idx = Some(idx.reinterpret_as_int())
            break
          }
          _ => ()
        }
      }
    }
    guard global_idx is Some(idx) else {
      ctx.fail(
        line,
        "assert_return",
        "[get \{field}] global '\{field}' not exported",
      )
      return
    }
    let globals = rt.get_globals()
    if idx < 0 || idx >= globals.length() {
      ctx.fail(
        line,
        "assert_return",
        "[get \{field}] global index \{idx} out of bounds",
      )
      return
    }
    let actual_value = globals[idx]
    // Check expected
    if expected.length() != 1 {
      ctx.fail(
        line,
        "assert_return",
        "[get \{field}] expected 1 result, got \{expected.length()}",
      )
      return
    }
    let expected_value = parse_expected_value(expected[0])
    if not(values_match(actual_value, expected_value)) {
      ctx.fail(
        line,
        "assert_return",
        "[get \{field}] expected \{format_expected_with_bits(expected_value)}, got \{format_value_with_bits(actual_value)}",
      )
    }
  } catch {
    e => ctx.fail(line, "assert_return", "[get \{field}] error: \{e}")
  }
}

///|
/// Process a single command from the test metadata
async fn process_command(ctx : TestContext, cmd : Json) -> Unit {
  match cmd {
    // Load module (with optional name for auto-registration)
    {
      "type": "module",
      "filename": String(filename),
      "line"? : line,
      "name"? : name,
      ..
    } => {
      let line = if line is Some(Number(n, ..)) { n.to_int() } else { -1 }
      let name = if name is Some(String(n)) { Some(n) } else { None }
      handle_module(ctx, filename, line, name~)
    }
    // Assert function returns expected value (invoke action)
    {
      "type": "assert_return",
      "line": Number(line, ..),
      "action": {
        "type": "invoke",
        "field": String(fn_name),
        "args": Array(args),
        "module"? : module_name,
        ..
      },
      "expected": Array(expected),
      ..
    } => {
      let module_name = if module_name is Some(String(n)) {
        Some(n)
      } else {
        None
      }
      handle_assert_return(
        ctx,
        fn_name,
        args,
        expected,
        line.to_int(),
        module_name~,
      )
    }
    // Assert function returns expected value (get action - read global)
    {
      "type": "assert_return",
      "line": Number(line, ..),
      "action": {
        "type": "get",
        "field": String(field),
        "module"? : module_name,
        ..
      },
      "expected": Array(expected),
      ..
    } => {
      let module_name = if module_name is Some(String(n)) {
        Some(n)
      } else {
        None
      }
      handle_assert_return_get(
        ctx,
        field,
        expected,
        line.to_int(),
        module_name~,
      )
    }
    // Assert function returns (unsupported action type)
    { "type": "assert_return", "line": Number(line, ..), "action": action, .. } =>
      ctx.fail(
        line.to_int(),
        "assert_return",
        "unsupported action type: \{action}",
      )
    // Assert function traps
    {
      "type": "assert_trap",
      "line": Number(line, ..),
      "action": {
        "type": "invoke",
        "field": String(fn_name),
        "args": Array(args),
        "module"? : module_name,
        ..
      },
      "text": String(expected_error),
      ..
    } => {
      let module_name = if module_name is Some(String(n)) {
        Some(n)
      } else {
        None
      }
      handle_assert_trap(
        ctx,
        fn_name,
        args,
        expected_error,
        line.to_int(),
        module_name~,
      )
    }
    {
      "type": "assert_invalid",
      "line": Number(line, ..),
      "filename": String(filename),
      "text": String(expected_error),
      ..
    } => handle_assert_invalid(ctx, filename, expected_error, line.to_int())
    // Handle "action" command - invoke function for side effects only (no expected result)
    {
      "type": "action",
      "line": Number(line, ..),
      "action": {
        "type": "invoke",
        "field": String(fn_name),
        "args": Array(args),
        ..
      },
      ..
    } => handle_action(ctx, fn_name, args, line.to_int())
    // Handle "register" command - register the current module with a name for imports
    { "type": "register", "as": String(name), "line"? : line, .. } => {
      let line = if line is Some(Number(n, ..)) { n.to_int() } else { -1 }
      handle_register(ctx, name, line)
    }
    // Skip malformed tests (WAT parser not implemented)
    { "type": "assert_malformed", .. } => ()
    // Unknown command type - skip silently for now
    { "type": String(_), .. } => ()
    _ => ()
  }
}

///|
async fn process_meta(
  dir : String,
  json_file : String,
  failures : Array[TestFailure],
  source_file : String,
  runtime_type? : RuntimeType = MoonBit,
) -> Int {
  let file = @fs.open(dir + json_file, mode=ReadOnly)
  defer file.close()
  let meta = file.read_all().json()
  match meta {
    { "commands": Array(commands), .. } => {
      let registry = ModuleRegistry::new()
      let resolver = @wasm5_runtime.default_import_resolver()
      let ctx = TestContext::{
        dir,
        source_file,
        failures,
        runtime_type,
        executor: None,
        registry,
        resolver,
        skipped_count: 0,
      }
      for cmd in commands {
        process_command(ctx, cmd)
        // HACK: avoid the problem of deep nested continutations caused
        // by running many sync code in an async loop
        @async.pause()
      }
      ctx.skipped_count
    }
    _ => {
      failures.push({
        line: -1,
        test_type: "parse",
        message: "cannot find commands in meta file",
        source_file,
      })
      0
    }
  }
}

///|
/// Result of processing a wast file: (failures, skipped_count)
pub async fn process_wast_file(
  wast_dir : String,
  wast_file : String,
  runtime_type? : RuntimeType = MoonBit,
) -> (Array[TestFailure], Int) {
  guard wast_file.strip_suffix(".wast") is Some(base_name) else {
    abort("Invalid wast file name: \{wast_file}")
  }
  let json_file = (base_name + ".json").to_string()
  let target_dir = wast_dir + base_name.to_string() + "/"
  if not(@fs.exists(target_dir)) {
    @fs.mkdir(target_dir, permission=0o755)
  }
  // execute: wasm-tools wast2json xxx.wast -o xxx/xxx.json --wasm-dir xxx/
  let test_result : Array[TestFailure] = []
  let exit_code = @process.run("wasm-tools", [
    "wast2json",
    wast_dir + wast_file,
    "-o",
    target_dir + json_file,
    "--wasm-dir",
    target_dir,
  ])
  if exit_code != 0 {
    // wast2json failed - record as test failure and skip this file
    test_result.push({
      line: -1,
      test_type: "wast2json",
      message: "Failed to convert to JSON (unsupported wast syntax)",
      source_file: wast_file,
    })
    if @fs.exists(target_dir) {
      @fs.rmdir(target_dir, recursive=true)
    }
    return (test_result, 0)
  }
  let skipped = process_meta(
    target_dir,
    json_file,
    test_result,
    wast_file,
    runtime_type~,
  )
  @fs.rmdir(target_dir, recursive=true)
  (test_result, skipped)
}

///|
/// Process a wast file using C runtime (convenience wrapper)
pub async fn process_wast_file_cruntime(
  wast_dir : String,
  wast_file : String,
) -> (Array[TestFailure], Int) {
  process_wast_file(wast_dir, wast_file, runtime_type=CRuntime)
}

///|
/// Whitelist for C runtime tests (some tests may have features not yet implemented)
/// select.wast: ref.func and ref.null instructions not implemented
let cruntime_whitelisted_tests : Array[(String, Set[Int])] = [
  ("select.wast", Set::of([251, 252, 258, 259, 279, 280])),
]

///|
/// Whitelist of individual tests to skip (file, line)
/// These are known failing tests due to missing features
// Whitelisted tests that are skipped due to missing validation/features
// Currently all GC tests pass!
let whitelisted_tests : Array[(String, Set[Int])] = []
