///|
async fn main {
  let args = @env.args()
  match args {
    [_, "run", wasm_path] => {
      let wasm_bytes = @fs.read_file(wasm_path).binary()
      let module_ = @wasm5.parse(wasm_bytes)
      let runtime = @wasm5.Runtime::load(module_)
      runtime.call("_start", []) |> ignore
      println("WASM module executed successfully.")
    }
    _ => println("Usage: wasm5 run <wasm-file>")
  }
}
