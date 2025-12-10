///|
async fn main {
  let exit_code = @process.run("wasm-tools", [
    "parse", "./cmd/run-wat/w.wat", "-o", "./cmd/run-wat/w.wasm",
  ])
  guard exit_code == 0 else {
    println("Failed to convert WAT to WASM.")
    return
  }
  let wasm_bytes = @fs.read_file("./cmd/run-wat/w.wasm").binary()
  let module_ = @wasm5.parse(wasm_bytes)
  let runtime = @wasm5.Runtime::load(module_)
  runtime.compile()
  // "nested-block-value" (i32.const 1)) (i32.const 9)
  let results = runtime.call_compiled("nested-block-value", [
    @wasm5.Value::I32(1),
    @wasm5.Value::I32(9),
  ])
  if results.length() > 0 {
    println("Result: \{results}")
  }
  @fs.remove("./cmd/run-wat/w.wasm")
  println("WASM module executed successfully.")
}
