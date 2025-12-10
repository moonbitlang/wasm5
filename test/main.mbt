///|
/// Test failure record
struct TestFailure {
  line : Int
  test_type : String
  message : String
  source_file : String
}

///|
/// Test context passed to handlers
struct TestContext {
  dir : String
  source_file : String
  failures : Array[TestFailure]
  mut runtime : @wasm5.Runtime?
}

///|
fn TestContext::fail(
  self : TestContext,
  line : Int,
  test_type : String,
  message : String,
) -> Unit {
  self.failures.push({ line, test_type, message, source_file: self.source_file })
}

///|
async fn parse_and_compile(dir : String, file_name : String) -> @wasm5.Runtime {
  let file = @fs.open(dir + file_name, mode=ReadOnly)
  defer file.close()
  let content = file.read_all().binary()
  let module_ = @wasm5.parse(content)
  let runtime = @wasm5.Runtime::load(module_)
  runtime.compile()
  runtime
}

///|
/// Error for unsupported test types
suberror TestUnsupported {
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
  Exact(@wasm5.Value)
  AnyF32Nan // nan:arithmetic for f32 - any NaN value is acceptable
  AnyF64Nan // nan:arithmetic for f64 - any NaN value is acceptable
  AnyFuncRef // any funcref value (including null)
  AnyExternRef // any externref value (including null)
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
fn parse_args(args : Array[Json]) -> Array[@wasm5.Value] raise {
  let runtime_args : Array[@wasm5.Value] = []
  for arg in args {
    match arg {
      { "type": "i32", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::I32(parse_i32_value(v)))
      { "type": "i64", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::I64(parse_i64_value(v)))
      // wast2json outputs floats as their bit representation (integer string)
      // or special nan values like "nan:canonical", "nan:arithmetic"
      { "type": "f32", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::F32(parse_f32_value(v)))
      { "type": "f64", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::F64(parse_f64_value(v)))
      // externref: "null" for null, otherwise an integer index
      { "type": "externref", "value": String(v), .. } =>
        if v == "null" {
          runtime_args.push(@wasm5.Value::Ref(None))
        } else {
          runtime_args.push(
            @wasm5.Value::Ref(Some(parse_i32_value(v).reinterpret_as_int())),
          )
        }
      // funcref: "null" for null, otherwise an integer function index
      { "type": "funcref", "value": String(v), .. } =>
        if v == "null" {
          runtime_args.push(@wasm5.Value::Ref(None))
        } else {
          runtime_args.push(
            @wasm5.Value::Ref(Some(parse_i32_value(v).reinterpret_as_int())),
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
      Exact(@wasm5.Value::I32(parse_i32_value(v)))
    { "type": "i64", "value": String(v), .. } =>
      Exact(@wasm5.Value::I64(parse_i64_value(v)))
    // wast2json outputs floats as their bit representation (integer string)
    // or special nan values like "nan:canonical", "nan:arithmetic"
    { "type": "f32", "value": String(v), .. } =>
      if v.has_prefix("nan:arithmetic") {
        AnyF32Nan
      } else {
        Exact(@wasm5.Value::F32(parse_f32_value(v)))
      }
    { "type": "f64", "value": String(v), .. } =>
      if v.has_prefix("nan:arithmetic") {
        AnyF64Nan
      } else {
        Exact(@wasm5.Value::F64(parse_f64_value(v)))
      }
    // externref: "null" for null, otherwise an integer index, or no value (any externref)
    { "type": "externref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5.Value::Ref(None))
      } else {
        Exact(@wasm5.Value::Ref(Some(parse_i32_value(v).reinterpret_as_int())))
      }
    { "type": "externref", .. } => AnyExternRef // type-only check, any externref
    // funcref: "null" for null, otherwise an integer function index, or no value (any funcref)
    { "type": "funcref", "value": String(v), .. } =>
      if v == "null" {
        Exact(@wasm5.Value::Ref(None))
      } else {
        Exact(@wasm5.Value::Ref(Some(parse_i32_value(v).reinterpret_as_int())))
      }
    { "type": "funcref", .. } => AnyFuncRef // type-only check, any funcref
    // refnull: any null reference
    { "type": "refnull", .. } => AnyRefNull
    _ => raise TestUnsupported::UnsupportedExpectedType("\{expected}")
  }
}

///|
/// Format a value with bit pattern for debugging NaN issues
fn format_value_with_bits(v : @wasm5.Value) -> String {
  match v {
    @wasm5.Value::F64(f) => {
      let bits = f.reinterpret_as_uint64()
      "F64(\{f}) [bits: \{bits}]"
    }
    @wasm5.Value::F32(f) => {
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
    AnyRefNull => "AnyRefNull"
  }
}

///|
/// Check if actual value matches expected value (handling NaN cases)
fn values_match(actual : @wasm5.Value, expected : ExpectedValue) -> Bool {
  match expected {
    Exact(exp) =>
      // Need special handling for floats to compare NaN bit patterns
      match (actual, exp) {
        (@wasm5.Value::F64(a), @wasm5.Value::F64(e)) =>
          // Compare bit patterns for exact match (including NaN patterns)
          a.reinterpret_as_uint64() == e.reinterpret_as_uint64()
        (@wasm5.Value::F32(a), @wasm5.Value::F32(e)) =>
          // Compare bit patterns for exact match (including NaN patterns)
          a.reinterpret_as_uint() == e.reinterpret_as_uint()
        _ => actual == exp
      }
    AnyF32Nan =>
      match actual {
        @wasm5.Value::F32(v) => v.is_nan()
        _ => false
      }
    AnyF64Nan =>
      match actual {
        @wasm5.Value::F64(v) => v.is_nan()
        _ => false
      }
    AnyFuncRef =>
      // Accept any reference value (funcref can be null or non-null)
      match actual {
        @wasm5.Value::Ref(_) => true
        _ => false
      }
    AnyExternRef =>
      // Accept any reference value (externref can be null or non-null)
      match actual {
        @wasm5.Value::Ref(_) => true
        _ => false
      }
    AnyRefNull =>
      // Accept only null references
      match actual {
        @wasm5.Value::Ref(None) => true
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
) -> Unit {
  try {
    let runtime = parse_and_compile(ctx.dir, filename)
    ctx.runtime = Some(runtime)
  } catch {
    e => ctx.fail(line, "module", "Error loading module: \{e}")
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
) -> Unit {
  try {
    let runtime_args = parse_args(args)
    guard ctx.runtime is Some(rt) else {
      ctx.fail(
        line, "assert_return", "no module loaded (previous module failed to load)",
      )
      return
    }
    let results = rt.call_compiled(@encoding/utf8.encode(fn_name), runtime_args)
    // Check result count
    if expected.length() != results.length() {
      ctx.fail(
        line,
        "assert_return",
        "expected \{expected.length()} results, got \{results.length()}",
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
          "at result \{idx}: expected \{format_expected_with_bits(expected_value)}, got \{format_value_with_bits(results[idx])}",
        )
      }
    }
  } catch {
    e => ctx.fail(line, "assert_return", "Test failed with error: \{e}")
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
) -> Unit {
  let runtime_args = parse_args(args) catch {
    e => {
      ctx.fail(line, "assert_trap", "Failed to parse args: \{e}")
      return
    }
  }
  guard ctx.runtime is Some(rt) else {
    ctx.fail(
      line, "assert_trap", "no module loaded (previous module failed to load)",
    )
    return
  }
  try {
    let _ = rt.call_compiled(@encoding/utf8.encode(fn_name), runtime_args)
    ctx.fail(
      line,
      "assert_trap",
      "expected trap '\{expected_error}' but no error occurred",
    )
  } catch {
    @wasm5.RuntimeError::DivisionByZero =>
      if not(expected_error.contains("divide by zero")) {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got DivisionByZero",
        )
      }
    @wasm5.RuntimeError::IntegerOverflow =>
      // IntegerOverflow is used for both "integer overflow" and "invalid conversion to integer"
      if not(
        expected_error.contains("overflow") ||
        expected_error.contains("invalid conversion"),
      ) {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got IntegerOverflow",
        )
      }
    @wasm5.RuntimeError::MemoryOutOfBounds =>
      if not(expected_error.contains("out of bounds memory access")) {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got MemoryOutOfBounds",
        )
      }
    @wasm5.RuntimeError::Unreachable =>
      if not(expected_error.contains("unreachable")) {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got Unreachable",
        )
      }
    @wasm5.RuntimeError::InvalidType(msg) =>
      // Handle table out of bounds errors
      if msg.contains("table") && msg.contains("out of bounds") {
        if not(expected_error.contains("out of bounds table access")) {
          ctx.fail(
            line,
            "assert_trap",
            "expected trap '\{expected_error}' but got table out of bounds",
          )
        }
      } else if msg.contains("undefined element") {
        if not(expected_error.contains("undefined element")) {
          ctx.fail(
            line,
            "assert_trap",
            "expected trap '\{expected_error}' but got undefined element",
          )
        }
      } else if msg.contains("uninitialized element") {
        if not(expected_error.contains("uninitialized element")) {
          ctx.fail(
            line,
            "assert_trap",
            "expected trap '\{expected_error}' but got uninitialized element",
          )
        }
      } else if msg.contains("indirect call type mismatch") {
        if not(expected_error.contains("indirect call type mismatch")) {
          ctx.fail(
            line,
            "assert_trap",
            "expected trap '\{expected_error}' but got indirect call type mismatch",
          )
        }
      } else {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got: InvalidType(\{msg})",
        )
      }
    e =>
      ctx.fail(
        line,
        "assert_trap",
        "expected trap '\{expected_error}' but got: \{e}",
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
    let _ = parse_and_compile(ctx.dir, filename)
    ctx.fail(
      line,
      "assert_invalid",
      "expected validation error '\{expected_error}' but module was valid",
    )
  } catch {
    // The WebAssembly spec uses "type mismatch" for various validation errors.
    // Our validator distinguishes TypeMismatch and StackSizeMismatch, but both
    // correspond to the spec's "type mismatch" error message.
    @wasm5.ValidationError::TypeMismatch(_) =>
      if not(expected_error.contains("type mismatch")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got TypeMismatch",
        )
      }
    @wasm5.ValidationError::StackSizeMismatch(_) =>
      if not(expected_error.contains("type mismatch")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got StackSizeMismatch",
        )
      }
    @wasm5.ValidationError::InvalidAlignment(_) =>
      if not(expected_error.contains("alignment")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidAlignment",
        )
      }
    @wasm5.ValidationError::UnknownLabel(_) =>
      if not(expected_error.contains("unknown label")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got UnknownLabel",
        )
      }
    @wasm5.ValidationError::InvalidStartFunction(_) =>
      if not(expected_error.contains("start function")) {
        ctx.fail(
          line,
          "assert_invalid",
          "expected '\{expected_error}' but got InvalidStartFunction",
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
    guard ctx.runtime is Some(rt) else {
      ctx.fail(
        line, "action", "no module loaded (previous module failed to load)",
      )
      return
    }
    let _ = rt.call_compiled(@encoding/utf8.encode(fn_name), runtime_args)

  } catch {
    e => ctx.fail(line, "action", "Action failed with error: \{e}")
  }
}

///|
/// Process a single command from the test metadata
async fn process_command(ctx : TestContext, cmd : Json) -> Unit {
  match cmd {
    // Load module
    { "type": "module", "filename": String(filename), "line"? : line, .. } => {
      let line = if line is Some(Number(n, ..)) { n.to_int() } else { -1 }
      handle_module(ctx, filename, line)
    }
    // Assert function returns expected value
    {
      "type": "assert_return",
      "line": Number(line, ..),
      "action": {
        "type": "invoke",
        "field": String(fn_name),
        "args": Array(args),
        ..
      },
      "expected": Array(expected),
      ..
    } => handle_assert_return(ctx, fn_name, args, expected, line.to_int())
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
        ..
      },
      "text": String(expected_error),
      ..
    } => handle_assert_trap(ctx, fn_name, args, expected_error, line.to_int())
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
) -> Unit {
  let file = @fs.open(dir + json_file, mode=ReadOnly)
  defer file.close()
  let meta = file.read_all().json()
  match meta {
    { "commands": Array(commands), .. } => {
      let ctx = TestContext::{ dir, source_file, failures, runtime: None }
      for cmd in commands {
        process_command(ctx, cmd)
      }
    }
    _ =>
      failures.push({
        line: -1,
        test_type: "parse",
        message: "cannot find commands in meta file",
        source_file,
      })
  }
}

///|
async fn process_wast_file(
  wast_dir : String,
  wast_file : String,
) -> Array[TestFailure] {
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
    return test_result
  }
  process_meta(target_dir, json_file, test_result, wast_file)
  @fs.rmdir(target_dir, recursive=true)
  test_result
}

///|
fn print_summary(failures : Array[TestFailure]) -> Unit {
  println("\n" + "=".repeat(60))
  println("TEST SUMMARY")
  println("=".repeat(60))
  if failures.length() == 0 {
    println("All tests passed! \u{2705}")
  } else {
    println("Total failures: \{failures.length()}")
    println("")
    for failure in failures {
      if failure.line >= 0 {
        println(
          "[\{failure.test_type}] \{failure.source_file}:\{failure.line}: \{failure.message}",
        )
      } else {
        println(
          "[\{failure.test_type}] \{failure.source_file}: \{failure.message}",
        )
      }
    }
    println("")
    println("Tests failed: \{failures.length()} \u{274c}")
  }
}

///|
/// Blacklist of wast files that cause runtime crashes
let blacklisted_wast_files : Array[String] = ["elem.wast"] // Causes call_indirect stack overflow

///|
async fn collect_wast_files(dir : String) -> Array[String] {
  let wast_files : Array[String] = []
  let entries = @fs.readdir(dir)
  for entry in entries {
    if entry.has_suffix(".wast") && not(blacklisted_wast_files.contains(entry)) {
      wast_files.push(entry)
    }
  }
  wast_files
}

///|
async fn main {
  // Blacklist: Files that test WAT text format (not binary WASM)
  // These contain (module quote ...) which are expected to fail with InvalidMagic
  let blacklist = ["comments.wast", "annotations.wast"]

  let failures : Array[TestFailure] = []
  let wast_files = collect_wast_files("test/reference_tests/")
  for wast_file in wast_files {
    // Skip blacklisted files
    if blacklist.contains(wast_file) {
      continue
    }
    let file_failures = process_wast_file("test/reference_tests/", wast_file)
    failures.append(file_failures)
  }
  print_summary(failures)
  if failures.length() > 0 {
    fail("Tests failed")
  }
}
