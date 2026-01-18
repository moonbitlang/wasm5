///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path, func_name, .. rest_args] =>
      run_unified(wasm_path, func_name, rest_args)
    [_, "run", wasm_path] => run_unified(wasm_path, "_start", [])
    // Keep run-component for backwards compatibility
    [_, "run-component", component_path, func_name, .. rest_args] =>
      run_unified(component_path, func_name, rest_args)
    [_, "run-component", component_path] =>
      run_unified(component_path, "_start", [])
    _ => {
      println("Usage:")
      println("  wasm5 run <wasm-file> [func-name] [args...]")
      println("")
      println("Automatically detects Module vs Component binary format.")
      println("Default function: _start")
    }
  }
}

///|
async fn run_unified(
  wasm_path : String,
  func_name : String,
  args : ArrayView[String],
) -> Unit {
  // Read binary
  let wasm_bytes = @fs.read_file(wasm_path).binary()

  // Load (auto-detect Module vs Component)
  let executable = @component.load(wasm_bytes) catch {
    e => {
      println("Error loading: \{e}")
      return
    }
  }

  // Show what type was loaded
  let type_str = if executable.is_component() { "Component" } else { "Module" }
  println("Loaded: \{type_str}")

  // Parse arguments as S32 integers
  let comp_args : Array[@component.ComponentValue] = []
  for arg in args {
    let n = @strconv.parse_int(arg) catch {
      _ => {
        println("Error: argument '\{arg}' is not a valid integer")
        return
      }
    }
    comp_args.push(@component.ComponentValue::S32(n))
  }

  // Call the function
  let results = executable.call(func_name, comp_args) catch {
    e => {
      println("Error calling '\{func_name}': \{e}")
      return
    }
  }

  // Print results
  if results.length() > 0 {
    println("Result: \{results}")
  }
}
