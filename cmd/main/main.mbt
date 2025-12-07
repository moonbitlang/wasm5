///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => {
      let wasm_bytes = @fs.read_file(wasm_path).binary()
      let module_ = @wasm5.parse(wasm_bytes)
      let runtime = @wasm5.Runtime::load(module_)
      // Compile and run using the threaded interpreter
      runtime.compile()
      let results = runtime.call_compiled("_start", [])
      if results.length() > 0 {
        println("Result: \{results}")
      }
      println("WASM module executed successfully.")
    }
    _ => println("Usage: wasm5 run <wasm-file>")
  }
}
