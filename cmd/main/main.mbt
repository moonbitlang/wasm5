///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => run_wasm(wasm_path)
    [_, "crun", wasm_path] => run_wasm_c(wasm_path, "_start")
    [_, "crun", wasm_path, export_name] => run_wasm_c(wasm_path, export_name)
    _ => {
      println("Usage: wasm5 <command> <wasm-file> [export-name]")
      println("Commands:")
      println("  run   - Run with MoonBit runtime (calls _start)")
      println("  crun  - Run with C runtime (calls _start or specified export)")
    }
  }
}

///|
async fn run_wasm(wasm_path : String) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_)
  runtime.run_start()
  let results = runtime.call_compiled(b"_start", [])
  if results.length() > 0 {
    println("Result: \{results}")
  }
}

///|
async fn run_wasm_c(wasm_path : String, export_name : String) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5_parse.parse(wasm_bytes)

  // Load and compile for C runtime
  let runtime = @wasm5_cruntime.CRuntime::load(module_)
  runtime.run_start()
  println("Calling '\{export_name}'...")
  let results = runtime.call_compiled(@encoding/utf8.encode(export_name), [])
  if results.length() > 0 {
    println("Result: \{results}")
  } else {
    println("No results (function may not exist or returns void)")
  }
}
