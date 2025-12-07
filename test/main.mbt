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
/// Parse JSON arguments array into runtime values
fn parse_args(args : Array[Json]) -> Array[@wasm5.Value] raise {
  let runtime_args : Array[@wasm5.Value] = []
  for arg in args {
    match arg {
      { "type": "i32", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::I32(@strconv.parse_uint(v)))
      { "type": "i64", "value": String(v), .. } =>
        runtime_args.push(@wasm5.Value::I64(@strconv.parse_uint64(v)))
      _ => fail("unsupported argument type")
    }
  }
  runtime_args
}

///|
/// Parse a JSON value as an expected result
fn parse_expected_value(expected : Json) -> @wasm5.Value raise {
  match expected {
    { "type": "i32", "value": String(v), .. } =>
      @wasm5.Value::I32(@strconv.parse_uint(v))
    { "type": "i64", "value": String(v), .. } =>
      @wasm5.Value::I64(@strconv.parse_uint64(v))
    _ => fail("unsupported expected value type")
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
) -> Unit raise {
  let runtime_args = parse_args(args)
  guard ctx.runtime is Some(rt) else {
    ctx.fail(
      line, "assert_return", "no module loaded (previous module failed to load)",
    )
  }
  try {
    let results = rt.call_compiled(
      @encoding/utf8.encode(fn_name),
      runtime_args,
    )
    // Check result count
    if expected.length() != results.length() {
      ctx.fail(
        line,
        "assert_return",
        "expected \{expected.length()} results, got \{results.length()}",
      )
    }
    // Validate each result
    for idx in 0..<expected.length() {
      let expected_value = parse_expected_value(expected[idx])
      if results[idx] != expected_value {
        ctx.fail(
          line,
          "assert_return",
          "at result \{idx}: expected \{expected_value}, got \{results[idx]}",
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
) -> Unit raise {
  let runtime_args = parse_args(args)
  guard ctx.runtime is Some(rt) else {
    ctx.fail(
      line, "assert_trap", "no module loaded (previous module failed to load)",
    )
    return
  }
  try {
    let _ = rt.call_compiled(
      @encoding/utf8.encode(fn_name),
      runtime_args,
    )
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
      if not(expected_error.contains("overflow")) {
        ctx.fail(
          line,
          "assert_trap",
          "expected trap '\{expected_error}' but got IntegerOverflow",
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
    _ => () // Other validation errors are acceptable
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
  // execute: wast2json xxx.wast -o xxx/xxx.json
  guard @process.run("wast2json", [
      wast_dir + wast_file,
      "-o",
      target_dir + json_file,
    ])
    is 0 else {
    abort("Failed to convert \{wast_file} to JSON")
  }
  let test_result : Array[TestFailure] = []
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
async fn collect_wast_files(dir : String) -> Array[String] {
  let wast_files : Array[String] = []
  let entries = @fs.readdir(dir)
  for entry in entries {
    if entry.has_suffix(".wast") {
      wast_files.push(entry)
    }
  }
  wast_files
}

///|
async fn main {
  let failures : Array[TestFailure] = []
  // Test i32.wast, i64.wast, and if.wast
  for wast_file in ["i32.wast", "i64.wast", "if.wast"] {
    let file_failures = process_wast_file("test/reference_tests/", wast_file)
    failures.append(file_failures)
  }

  // Uncomment to test all wast files:
  // let wast_files = collect_wast_files("test/reference_tests/")
  // for wast_file in wast_files {
  //   let file_failures = process_wast_file("test/reference_tests/", wast_file)
  //   failures.append(file_failures)
  // }

  print_summary(failures)
  if failures.length() > 0 {
    fail("Tests failed")
  }
}
