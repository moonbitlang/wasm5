///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => run_wasm(wasm_path)
    _ => println("Usage: wasm5 run <wasm-file>")
  }
}

///|
async fn run_wasm(wasm_path : String) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_)
  runtime.compile()
  let results = runtime.call_compiled("_start", [])
  if results.length() > 0 {
    println("Result: \{results}")
  }
  // println("WASM module executed successfully.")
}
