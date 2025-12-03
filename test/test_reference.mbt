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
