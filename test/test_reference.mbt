///|
/// Test failure record
struct TestFailure {
  line : Int
  test_type : String
  message : String
  source_file : String
}

///|
async fn parse_wasm_file(dir : String, file_name : String) -> @wasm5.Module {
  let file = @fs.open(dir + file_name, mode=ReadOnly)
  defer file.close()
  let content = file.read_all().binary()
  @wasm5.parse(content)
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
      let mut runtime = None
      for cmd in commands {
        match cmd {
          {
            "type": "module",
            "filename": String(filename),
            "line": Number(i, ..),
            ..
          } =>
            try {
              let module_ = parse_wasm_file(dir, filename)
              runtime = Some(@wasm5.Runtime::load(module_))
            } catch {
              @wasm5.ValidationError::TypeMismatch(msg) =>
                failures.push({
                  line: i.to_int(),
                  test_type: "module",
                  message: "Validation error: \{msg}",
                  source_file,
                })
              e =>
                failures.push({
                  line: i.to_int(),
                  test_type: "module",
                  message: "Error loading module: \{e}",
                  source_file,
                })
            }
          { "type": "module", "filename": String(filename), .. } =>
            try {
              let module_ = parse_wasm_file(dir, filename)
              runtime = Some(@wasm5.Runtime::load(module_))
            } catch {
              @wasm5.ValidationError::TypeMismatch(msg) =>
                failures.push({
                  line: -1,
                  test_type: "module",
                  message: "Validation error: \{msg}",
                  source_file,
                })
              e =>
                failures.push({
                  line: -1,
                  test_type: "module",
                  message: "Error loading module: \{e}",
                  source_file,
                })
            }
          {
            "type": "assert_return",
            "line": Number(i, ..),
            "action": action,
            "expected": Array(expected),
            ..
          } =>
            match action {
              {
                "type": "invoke",
                "field": String(fn_name),
                "args": Array(args),
                ..
              } => {
                let runtime_args = []
                let mut arg_error = false
                for arg in args {
                  match arg {
                    { "type": "i32", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I32(@strconv.parse_uint(v)),
                      )
                    { "type": "i64", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I64(@strconv.parse_uint64(v)),
                      )
                    _ => {
                      failures.push({
                        line: i.to_int(),
                        test_type: "assert_return",
                        message: "unsupported argument type",
                        source_file,
                      })
                      arg_error = true
                    }
                  }
                }
                if arg_error {
                  continue
                }
                match runtime {
                  None => {
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_return",
                      message: "no module loaded (previous module failed to load)",
                      source_file,
                    })
                    continue
                  }
                  Some(rt) => {
                    try {
                      let results = rt.call(
                        @encoding/utf8.encode(fn_name),
                        FixedArray::from_array(runtime_args),
                      )
                  // Check expected results
                  if expected.length() != results.length() {
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_return",
                      message: "expected \{expected.length()} results, got \{results.length()}",
                      source_file,
                    })
                    continue
                  }
                  // Validate each result
                  let mut has_error = false
                  for idx = 0; idx < expected.length(); idx = idx + 1 {
                    match expected[idx] {
                      { "type": "i32", "value": String(expected_str), .. } => {
                        let expected_value = @wasm5.Value::I32(
                          @strconv.parse_uint(expected_str),
                        )
                        if results[idx] != expected_value {
                          failures.push({
                            line: i.to_int(),
                            test_type: "assert_return",
                            message: "at result \{idx}: expected \{expected_value}, got \{results[idx]}",
                            source_file,
                          })
                          has_error = true
                          break
                        }
                      }
                      { "type": "i64", "value": String(expected_str), .. } => {
                        let expected_value = @wasm5.Value::I64(
                          @strconv.parse_uint64(expected_str),
                        )
                        if results[idx] != expected_value {
                          failures.push({
                            line: i.to_int(),
                            test_type: "assert_return",
                            message: "at result \{idx}: expected \{expected_value}, got \{results[idx]}",
                            source_file,
                          })
                          has_error = true
                          break
                        }
                      }
                      _ => {
                        failures.push({
                          line: i.to_int(),
                          test_type: "assert_return",
                          message: "unsupported expected result type",
                          source_file,
                        })
                        has_error = true
                        break
                      }
                    }
                  }
                  if has_error {
                    continue
                  }
                } catch {
                  @wasm5.RuntimeError::UnimplementedInstruction(msg) =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_return",
                      message: "Unimplemented: \{msg}",
                      source_file,
                    })
                  e =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_return",
                      message: "Test failed with error: \{e}",
                      source_file,
                    })
                }
                  }
                }
              }
              _ =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_return",
                  message: "unsupported action type: \{action}",
                  source_file,
                })
            }
          {
            "type": "assert_trap",
            "line": Number(i, ..),
            "action": action,
            "text": String(expected_error),
            ..
          } =>
            match action {
              {
                "type": "invoke",
                "field": String(fn_name),
                "args": Array(args),
                ..
              } => {
                let runtime_args = []
                let mut arg_error = false
                for arg in args {
                  match arg {
                    { "type": "i32", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I32(@strconv.parse_uint(v)),
                      )
                    { "type": "i64", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I64(@strconv.parse_uint64(v)),
                      )
                    _ => {
                      failures.push({
                        line: i.to_int(),
                        test_type: "assert_trap",
                        message: "unsupported argument type",
                        source_file,
                      })
                      arg_error = true
                    }
                  }
                }
                if arg_error {
                  continue
                }
                match runtime {
                  None => {
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "no module loaded (previous module failed to load)",
                      source_file,
                    })
                    continue
                  }
                  Some(rt) => {
                    try {
                      let _result = rt.call(
                        @encoding/utf8.encode(fn_name),
                        FixedArray::from_array(runtime_args),
                      )
                      failures.push({
                        line: i.to_int(),
                        test_type: "assert_trap",
                        message: "expected trap '\{expected_error}' but no error occurred",
                        source_file,
                      })
                    } catch {
                  @wasm5.RuntimeError::DivisionByZero =>
                    if not(expected_error.contains("divide by zero")) {
                      failures.push({
                        line: i.to_int(),
                        test_type: "assert_trap",
                        message: "expected trap '\{expected_error}' but got DivisionByZero",
                        source_file,
                      })
                    }
                  @wasm5.RuntimeError::IntegerOverflow =>
                    if not(expected_error.contains("overflow")) {
                      failures.push({
                        line: i.to_int(),
                        test_type: "assert_trap",
                        message: "expected trap '\{expected_error}' but got IntegerOverflow",
                        source_file,
                      })
                    }
                  @wasm5.RuntimeError::StackUnderflow =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "expected trap '\{expected_error}' but got StackUnderflow",
                      source_file,
                    })
                  @wasm5.RuntimeError::MemoryOutOfBounds =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "expected trap '\{expected_error}' but got MemoryOutOfBounds",
                      source_file,
                    })
                  @wasm5.RuntimeError::InvalidType(msg) =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "expected trap '\{expected_error}' but got InvalidType: \{msg}",
                      source_file,
                    })
                  @wasm5.RuntimeError::FunctionNotFound(name) =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "expected trap '\{expected_error}' but got FunctionNotFound: \{name}",
                      source_file,
                    })
                  @wasm5.RuntimeError::UnimplementedInstruction(msg) =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "Unimplemented: \{msg}",
                      source_file,
                    })
                  e =>
                    failures.push({
                      line: i.to_int(),
                      test_type: "assert_trap",
                      message: "expected trap '\{expected_error}' but got unexpected error: \{e}",
                      source_file,
                    })
                }
                    }
                  }
              }
              _ =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_trap",
                  message: "unsupported action type: \{action}",
                  source_file,
                })
            }
          {
            "type": "assert_invalid",
            "line": Number(i, ..),
            "filename": String(filename),
            "text": String(expected_error),
            ..
          } =>
            try {
              let _module = parse_wasm_file(dir, filename)
              failures.push({
                line: i.to_int(),
                test_type: "assert_invalid",
                message: "expected validation error '\{expected_error}' but module was valid",
                source_file,
              })
            } catch {
              @wasm5.ValidationError::TypeMismatch(_) =>
                if not(expected_error.contains("type mismatch")) {
                  failures.push({
                    line: i.to_int(),
                    test_type: "assert_invalid",
                    message: "expected '\{expected_error}' but got TypeMismatch",
                    source_file,
                  })
                }
              @wasm5.ValidationError::InvalidFunctionIndex(_) =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_invalid",
                  message: "expected '\{expected_error}' but got InvalidFunctionIndex",
                  source_file,
                })
              @wasm5.ValidationError::InvalidTypeIndex(_) =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_invalid",
                  message: "expected '\{expected_error}' but got InvalidTypeIndex",
                  source_file,
                })
              @wasm5.ValidationError::InvalidLocalIndex(_) =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_invalid",
                  message: "expected '\{expected_error}' but got InvalidLocalIndex",
                  source_file,
                })
              @wasm5.ValidationError::InvalidGlobalIndex(_) =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_invalid",
                  message: "expected '\{expected_error}' but got InvalidGlobalIndex",
                  source_file,
                })
              @wasm5.ValidationError::StackSizeMismatch(_) =>
                if not(expected_error.contains("type mismatch")) {
                  failures.push({
                    line: i.to_int(),
                    test_type: "assert_invalid",
                    message: "expected '\{expected_error}' but got StackSizeMismatch",
                    source_file,
                  })
                }
              e =>
                failures.push({
                  line: i.to_int(),
                  test_type: "assert_invalid",
                  message: "expected validation error '\{expected_error}' but got: \{e}",
                  source_file,
                })
            }
          { "type": "assert_malformed", "line": Number(_i, ..), .. } =>
            // Silently skip assert_malformed tests (WAT parser not implemented)
            ()
          { "type": String(other), .. } =>
            failures.push({
              line: -1,
              test_type: "unknown",
              message: "unknown command type: \{other}",
              source_file,
            })
          _ =>
            failures.push({
              line: -1,
              test_type: "unknown",
              message: "unknown command: \{cmd}",
              source_file,
            })
        }
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
async fn main {
  let failures : Array[TestFailure] = []
  let i32_dir = "test/reference_tests/i32/"
  process_meta(i32_dir, "i32.json", failures, "i32.wast")
  let i64_dir = "test/reference_tests/i64/"
  process_meta(i64_dir, "i64.json", failures, "i64.wast")
  let if_dir = "test/reference_tests/if/"
  process_meta(if_dir, "if.json", failures, "if.wast")

  // Print summary
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
    fail("Tests failed")
  }
}
