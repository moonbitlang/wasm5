///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => run_wasm(wasm_path)
    [_, "crun", wasm_path, export_name] => run_wasm_c(wasm_path, export_name)
    _ => {
      println("Usage: wasm5 <command> <wasm-file> [export-name]")
      println("Commands:")
      println("  run   - Run with MoonBit runtime")
      println("  crun  - Run with C runtime (requires export name)")
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

  // Compile to threaded code for C runtime
  let compiled = @wasm5_cruntime.compile(module_)
  println("Compiled \{compiled.func_entries.length()} functions")
  println("Exports: \{compiled.exports.keys().collect()}")
  println("Calling '\{export_name}'...")
  match @wasm5_cruntime.call(compiled, export_name, []) {
    Some(result) => println("Result: \{result}")
    None => println("Export '\{export_name}' not found")
  }
}
