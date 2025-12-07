///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => run_wasm(wasm_path, compile=false)
    [_, "run", "--compile", wasm_path] => run_wasm(wasm_path, compile=true)
    [_, "run", wasm_path, "--compile"] => run_wasm(wasm_path, compile=true)
    _ => {
      println("Usage: wasm5 run [--compile] <wasm-file>")
      println("")
      println("Options:")
      println("  --compile  Use threaded interpreter (faster, supports deep recursion)")
      println("             Without this flag, uses tree-walking interpreter")
    }
  }
}

///|
async fn run_wasm(wasm_path : String, compile~ : Bool) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5.parse(wasm_bytes)
  let runtime = @wasm5.Runtime::load(module_)
  if compile {
    // Threaded interpreter
    runtime.compile()
    let results = runtime.call_compiled("_start", [])
    if results.length() > 0 {
      println("Result: \{results}")
    }
  } else {
    // Tree-walking interpreter
    let results = runtime.call("_start", [])
    if results.length() > 0 {
      println("Result: \{results}")
    }
  }
  println("WASM module executed successfully.")
}
