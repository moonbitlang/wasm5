///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => run_wasm(wasm_path)
    [_, "crun", wasm_path] => run_wasm_c(wasm_path)
    [_, "crun", wasm_path, func_idx] =>
      run_wasm_c_func(wasm_path, Some(try_parse_int(func_idx)))
    _ => {
      println("Usage: wasm5 <command> <wasm-file> [func-idx]")
      println("Commands:")
      println("  run   - Run with MoonBit runtime")
      println("  crun  - Run with C runtime")
    }
  }
}

///|
fn try_parse_int(s : String) -> Int {
  @strconv.parse_int(s) catch {
    _ => 0
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
async fn run_wasm_c(wasm_path : String) -> Unit {
  run_wasm_c_func(wasm_path, None)
}

///|
async fn run_wasm_c_func(wasm_path : String, func_idx : Int?) -> Unit {
  let wasm_bytes = @fs.read_file(wasm_path).binary()
  let module_ = @wasm5_parse.parse(wasm_bytes)

  // Compile to threaded code for C runtime
  let compiled = @wasm5_cruntime.compile(module_)
  println("Compiled \{compiled.func_entries.length()} functions")
  let idx = func_idx.unwrap_or(0)
  if idx < compiled.func_entries.length() {
    println("Calling function \{idx}...")
    let result = @wasm5_cruntime.call0(compiled, idx)
    println("Result: \{result}")

    // Also test with arguments if function 0
    if idx == 0 {
      println("Testing add(10, 32)...")
      let result2 = @wasm5_cruntime.call2_i32(compiled, 0, 10, 32)
      println("Result: \{result2}")
    }
  } else {
    println("Function index \{idx} out of range")
  }
}
