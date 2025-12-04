///|
async fn parse_wasm_file(dir : String, file_name : String) -> @wasm5.Module {
  let file = @fs.open(dir + file_name, mode=ReadOnly)
  defer file.close()
  let content = file.read_all().binary()
  @wasm5.parse(content)
}

///|
async fn process_meta(dir : String, json_file : String) -> Unit {
  let file = @fs.open(dir + json_file, mode=ReadOnly)
  defer file.close()
  let meta = file.read_all().json()
  match meta {
    { "commands": Array(commands), .. } => {
      let mut runtime = None
      for cmd in commands {
        match cmd {
          { "type": "module", "filename": String(filename), .. } => {
            let module_ = parse_wasm_file(dir, filename)
            runtime = Some(@wasm5.Runtime::load(module_))
          }
          {
            "type": "assert_return",
            "line": Number(i, ..),
            "action": action,
            "expected": Array(expected),
            ..
          } => {
            println("Processing assert_return at line \{i}")
            match action {
              {
                "type": "invoke",
                "field": String(fn_name),
                "args": Array(args),
                ..
              } => {
                let runtime_args = []
                for arg in args {
                  match arg {
                    { "type": "i32", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I32(@strconv.parse_uint(v)),
                      )
                    _ => fail("unsupported argument type")
                  }
                }
                let result = runtime
                  .unwrap()
                  .call(
                    @encoding/utf8.encode(fn_name),
                    FixedArray::from_array(runtime_args),
                  )
                match expected {
                  [{ "type": "i32", "value": String(expected), .. }] => {
                    let expected_value = @wasm5.Value::I32(
                      @strconv.parse_uint(expected),
                    )
                    if result == expected_value {
                      println("Test passed")
                    } else {
                      fail(
                        "Test failed: expected \{expected_value}, got \{result}",
                      )
                    }
                  }
                  _ => fail("unsupported expected result type")
                }
              }
              _ => fail("unsupported action type: \{action}")
            }
          }
          {
            "type": "assert_trap",
            "line": Number(i, ..),
            "action": action,
            "text": String(expected_error),
            ..
          } => {
            println("Processing assert_trap at line \{i}")
            match action {
              {
                "type": "invoke",
                "field": String(fn_name),
                "args": Array(args),
                ..
              } => {
                let runtime_args = []
                for arg in args {
                  match arg {
                    { "type": "i32", "value": String(v), .. } =>
                      runtime_args.push(
                        @wasm5.Value::I32(@strconv.parse_uint(v)),
                      )
                    _ => fail("unsupported argument type")
                  }
                }
                try {
                  let _result = runtime
                    .unwrap()
                    .call(
                      @encoding/utf8.encode(fn_name),
                      FixedArray::from_array(runtime_args),
                    )
                  fail("Test failed: expected trap '\{expected_error}' but no error occurred")
                } catch {
                  @wasm5.RuntimeError::DivisionByZero => {
                    if expected_error.contains("divide by zero") {
                      println("Test passed: trap '\{expected_error}'")
                    } else {
                      fail("Test failed: expected trap '\{expected_error}' but got DivisionByZero")
                    }
                  }
                  @wasm5.RuntimeError::IntegerOverflow => {
                    if expected_error.contains("overflow") {
                      println("Test passed: trap '\{expected_error}'")
                    } else {
                      fail("Test failed: expected trap '\{expected_error}' but got IntegerOverflow")
                    }
                  }
                  @wasm5.RuntimeError::StackUnderflow =>
                    fail("Test failed: expected trap '\{expected_error}' but got StackUnderflow")
                  @wasm5.RuntimeError::MemoryOutOfBounds =>
                    fail("Test failed: expected trap '\{expected_error}' but got MemoryOutOfBounds")
                  @wasm5.RuntimeError::InvalidType(msg) =>
                    fail("Test failed: expected trap '\{expected_error}' but got InvalidType: \{msg}")
                  @wasm5.RuntimeError::FunctionNotFound(name) =>
                    fail("Test failed: expected trap '\{expected_error}' but got FunctionNotFound: \{name}")
                  e => fail("Test failed: expected trap '\{expected_error}' but got unexpected error: \{e}")
                }
              }
              _ => fail("unsupported action type: \{action}")
            }
          }
          {
            "type": "assert_invalid",
            "line": Number(i, ..),
            "filename": String(filename),
            "text": String(expected_error),
            ..
          } => {
            println("Processing assert_invalid at line \{i}")
            try {
              let _module = parse_wasm_file(dir, filename)
              fail("Test failed: expected validation error '\{expected_error}' but module was valid")
            } catch {
              @wasm5.ValidationError::TypeMismatch(_) => {
                if expected_error.contains("type mismatch") {
                  println("Test passed: validation error '\{expected_error}'")
                } else {
                  fail("Test failed: expected '\{expected_error}' but got TypeMismatch")
                }
              }
              @wasm5.ValidationError::InvalidFunctionIndex(_) =>
                fail("Test failed: expected '\{expected_error}' but got InvalidFunctionIndex")
              @wasm5.ValidationError::InvalidTypeIndex(_) =>
                fail("Test failed: expected '\{expected_error}' but got InvalidTypeIndex")
              @wasm5.ValidationError::InvalidLocalIndex(_) =>
                fail("Test failed: expected '\{expected_error}' but got InvalidLocalIndex")
              @wasm5.ValidationError::InvalidGlobalIndex(_) =>
                fail("Test failed: expected '\{expected_error}' but got InvalidGlobalIndex")
              @wasm5.ValidationError::StackSizeMismatch(_) => {
                if expected_error.contains("type mismatch") {
                  println("Test passed: validation error '\{expected_error}'")
                } else {
                  fail("Test failed: expected '\{expected_error}' but got StackSizeMismatch")
                }
              }
              e => fail("Test failed: expected validation error '\{expected_error}' but got: \{e}")
            }
          }
          {
            "type": "assert_malformed",
            "line": Number(i, ..),
            ..
          } => {
            println("Skipping assert_malformed at line \{i} (WAT parser not implemented)")
          }
          { "type": String(other), .. } =>
            fail("unknown command type: \{other}")
          _ => fail("unknown command: \{cmd}")
        }
      }
    }
    _ => fail("cannot find commands in meta file")
  }
}

///|
async fn main {
  let dir = "test/reference_tests/i32/"
  process_meta(dir, "i32.json")
}
