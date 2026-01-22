///|
async fn main {
  let args = @env.args()
  // Parse CLI arguments following wasmi pattern:
  // wasm5 <WASM_FILE> --invoke <FUNC_NAME> [<FUNC_ARGS>...]
  let parsed = parse_args(args)
  match parsed {
    Some((wasm_path, func_name, func_args)) =>
      run_wasm(wasm_path, func_name, func_args)
    None => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("Usage: wasm5 <WASM_FILE> --invoke <FUNC_NAME> [<FUNC_ARGS>...]")
  println("")
  println("Execute a WebAssembly module and invoke an exported function.")
  println("")
  println("Arguments:")
  println("  <WASM_FILE>    Path to the WebAssembly binary file (.wasm)")
  println("  --invoke       Specify the exported function to call")
  println("  <FUNC_NAME>    Name of the exported function")
  println(
    "  <FUNC_ARGS>    Arguments to pass to the function (integers or floats)",
  )
  println("")
  println("Examples:")
  println("  wasm5 myprogram.wasm --invoke add 5 3")
  println("  wasm5 counter.wasm --invoke run 1000000")
}

///|
fn parse_args(args : Array[String]) -> (String, String, Array[String])? {
  // args[0] is the program name
  if args.length() < 4 {
    return None
  }
  let wasm_path = args[1]
  // Find --invoke flag
  let mut invoke_idx = -1
  for i in 2..<args.length() {
    if args[i] == "--invoke" {
      invoke_idx = i
      break
    }
  }
  if invoke_idx < 0 || invoke_idx + 1 >= args.length() {
    return None
  }
  let func_name = args[invoke_idx + 1]
  // Collect function arguments (everything after function name)
  let func_args : Array[String] = []
  for i = invoke_idx + 2; i < args.length(); i = i + 1 {
    func_args.push(args[i])
  }
  Some((wasm_path, func_name, func_args))
}

///|
fn parse_value(s : String, expected_type : @wasm5.ValType) -> @wasm5.Value? {
  match expected_type {
    I32 =>
      try {
        let n = @strconv.parse_int(s)
        Some(@wasm5.Value::I32(n.reinterpret_as_uint()))
      } catch {
        _ => None
      }
    I64 =>
      try {
        let n = @strconv.parse_int64(s)
        Some(@wasm5.Value::I64(n.reinterpret_as_uint64()))
      } catch {
        _ => None
      }
    F32 =>
      try {
        let f = @strconv.parse_double(s)
        Some(@wasm5.Value::F32(Float::from_double(f)))
      } catch {
        _ => None
      }
    F64 =>
      try {
        let f = @strconv.parse_double(s)
        Some(@wasm5.Value::F64(f))
      } catch {
        _ => None
      }
    _ => None // Reference types not supported via CLI
  }
}

///|
async fn run_wasm(
  wasm_path : String,
  func_name : String,
  arg_strings : Array[String],
) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5.parse(wasm_bytes)
  // Load and compile runtime
  let runtime = @wasm5.Instance::new(module_, @wasm5.Imports::spectest())
  runtime.run_start()
  // Find the function's type to parse arguments correctly
  let func_type = find_export_func_type(module_, func_name)
  match func_type {
    Some(ft) => {
      // Parse arguments according to function signature
      if arg_strings.length() != ft.params.length() {
        println(
          "Error: function '\{func_name}' expects \{ft.params.length()} arguments, got \{arg_strings.length()}",
        )
        return
      }
      let args : Array[@wasm5.Value] = []
      for i in 0..<arg_strings.length() {
        match parse_value(arg_strings[i], ft.params[i]) {
          Some(v) => args.push(v)
          None => {
            println(
              "Error: could not parse argument \{i + 1} '\{arg_strings[i]}' as \{ft.params[i]}",
            )
            return
          }
        }
      }
      let results = runtime.call_compiled(@utf8.encode(func_name), args)
      for line in runtime.get_output() {
        println(line)
      }
      runtime.clear_output()
      // Print results (one per line, just the value)
      for result in results {
        println(format_value(result))
      }
    }
    None =>
      println("Error: function '\{func_name}' not found in module exports")
  }
}

///|
fn format_value(v : @wasm5.Value) -> String {
  match v {
    I32(n) => n.reinterpret_as_int().to_string()
    I64(n) => n.reinterpret_as_int64().to_string()
    F32(f) => f.to_string()
    F64(f) => f.to_string()
    Ref(Some(n)) => "ref(\{n})"
    Ref(None) => "ref.null"
    Funcref(Some(n)) => "funcref(\{n})"
    Funcref(None) => "ref.null func"
    Externref(Some(n)) => "externref(\{n})"
    Externref(None) => "ref.null extern"
  }
}

///|
fn find_export_func_type(
  module_ : @wasm5.Module,
  name : String,
) -> @wasm5.FuncType? {
  // Find the export with the given name
  let name_bytes = @utf8.encode(name)
  for exp in module_.exports {
    if exp.name == name_bytes {
      match exp.desc {
        Func(func_idx) => {
          // Get the type index for this function
          let func_idx_int = func_idx.reinterpret_as_int()
          // Count imported functions
          let mut num_imported = 0
          for imp in module_.imports {
            match imp.desc {
              Func(_) => num_imported += 1
              _ => ()
            }
          }
          // Determine type index
          let type_idx = if func_idx_int < num_imported {
            // Imported function - find type from imports
            let mut import_func_idx = 0
            let mut found_type_idx = -1
            for imp in module_.imports {
              match imp.desc {
                Func(tidx) =>
                  if import_func_idx == func_idx_int {
                    found_type_idx = tidx.reinterpret_as_int()
                    break
                  } else {
                    import_func_idx += 1
                  }
                _ => ()
              }
            }
            found_type_idx
          } else {
            // Local function - index into funcs array (which only has local functions)
            let local_idx = func_idx_int - num_imported
            if local_idx >= 0 && local_idx < module_.funcs.length() {
              module_.funcs[local_idx].reinterpret_as_int()
            } else {
              -1
            }
          }
          if type_idx >= 0 && type_idx < module_.types.length() {
            match module_.types[type_idx] {
              Func(ft) => return Some(ft)
              _ => ()
            }
          }
        }
        _ => ()
      }
    }
  }
  None
}
