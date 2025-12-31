///|
/// Benchmark tests for wasm5

///|
/// fib.wasm binary - calculates fib(100)
fn get_fib_wasm() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x10\x03\x60\x01\x7f\x01\x7f\x60\x03\x7f\x7f\x7f\x01\x7f\x60\x00\x00\x02\x01\x00\x03\x03\x02\x00\x02\x04\x05\x01\x70\x01\x00\x00\x05\x03\x01\x00\x01\x06\x01\x00\x07\x0a\x01\x06\x5f\x73\x74\x61\x72\x74\x00\x01\x09\x06\x01\x00\x41\x00\x0b\x00\x0c\x01\x00\x0a\x40\x02\x32\x01\x05\x7f\x20\x00\x41\x00\x41\x01\x03\x01\x21\x03\x21\x02\x22\x01\x41\x00\x46\x04\x7f\x20\x02\x05\x20\x01\x41\x01\x6b\x21\x04\x20\x02\x20\x03\x6a\x21\x05\x20\x04\x20\x03\x20\x05\x0c\x01\x0b\x0b\x0b\x0b\x01\x01\x7f\x41\xe4\x00\x10\x00\x21\x00\x0b\x0b\x01\x00"
}

///|
/// Simple add module - minimal WASM for fast benchmarks
fn get_add_wasm() -> Bytes {
  // (module
  //   (func (export "add") (param i32 i32) (result i32)
  //     local.get 0
  //     local.get 1
  //     i32.add))
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x07\x01\x60\x02\x7f\x7f\x01\x7f\x03\x02\x01\x00\x07\x07\x01\x03\x61\x64\x64\x00\x00\x0a\x09\x01\x07\x00\x20\x00\x20\x01\x6a\x0b"
}

///|
test "bench_parse" (b : @bench.T) {
  let wasm_bytes = get_fib_wasm()
  b.bench(
    name="parse_fib",
    fn() {
      try {
        b.keep(@wasm5_parse.parse(wasm_bytes))
      } catch {
        _ => ()
      }
    },
  )
}

///|
test "bench_load" (b : @bench.T) {
  let wasm_bytes = get_fib_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  b.bench(
    name="load_fib",
    fn() {
      try {
        b.keep(@wasm5_runtime.Runtime::load(module_))
      } catch {
        _ => ()
      }
    },
  )
}

///|
test "bench_compile" (b : @bench.T) {
  let wasm_bytes = get_fib_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_)
  b.bench(
    name="compile_fib",
    fn() {
      try {
        b.keep(runtime.compile())
      } catch {
        _ => ()
      }
    },
  )
}

///|
test "bench_execute_fib" (b : @bench.T) {
  let wasm_bytes = get_fib_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="execute_fib100",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled("_start", [])
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

///|
test "bench_full_pipeline" (b : @bench.T) {
  let wasm_bytes = get_fib_wasm()
  b.bench(
    name="full_pipeline_fib",
    fn() {
      try {
        let module_ = @wasm5_parse.parse(wasm_bytes)
        let runtime = @wasm5_runtime.Runtime::load(module_).compile()
        let (rt, _) = runtime.call_compiled("_start", [])
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

///|
test "bench_add_simple" (b : @bench.T) {
  let wasm_bytes = get_add_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="execute_add",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled(
          "add",
          [@wasm5_runtime.Value::I32(1), @wasm5_runtime.Value::I32(2)],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}
