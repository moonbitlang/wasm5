///|
/// Comprehensive benchmark tests for wasm5

// =============================================================================
// WASM Binaries
// =============================================================================

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
/// Loop counter - counts from 0 to N
/// (module
///   (func (export "count") (param $n i32) (result i32)
///     (local $i i32)
///     (local.set $i (i32.const 0))
///     (block $break
///       (loop $continue
///         (br_if $break (i32.ge_u (local.get $i) (local.get $n)))
///         (local.set $i (i32.add (local.get $i) (i32.const 1)))
///         (br $continue)))
///     (local.get $i)))
fn get_loop_wasm() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x06\x01\x60\x01\x7f\x01\x7f\x03\x02\x01\x00\x07\x09\x01\x05\x63\x6f\x75\x6e\x74\x00\x00\x0a\x1b\x01\x19\x01\x01\x7f\x41\x00\x21\x01\x02\x40\x03\x40\x20\x01\x20\x00\x4f\x0d\x01\x20\x01\x41\x01\x6a\x21\x01\x0c\x00\x0b\x0b\x20\x01\x0b"
}

///|
/// Factorial function - calculates n!
/// (module
///   (func (export "factorial") (param $n i32) (result i32)
///     (if (result i32) (i32.le_s (local.get $n) (i32.const 1))
///       (then (i32.const 1))
///       (else (i32.mul (local.get $n)
///               (call 0 (i32.sub (local.get $n) (i32.const 1))))))))
fn get_factorial_wasm() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x06\x01\x60\x01\x7f\x01\x7f\x03\x02\x01\x00\x07\x0d\x01\x09\x66\x61\x63\x74\x6f\x72\x69\x61\x6c\x00\x00\x0a\x14\x01\x12\x00\x20\x00\x41\x01\x4c\x04\x7f\x41\x01\x05\x20\x00\x20\x00\x41\x01\x6b\x10\x00\x6c\x0b\x0b"
}

///|
/// Float arithmetic - various f64 operations
/// (module
///   (func (export "float_ops") (param $a f64) (param $b f64) (result f64)
///     (f64.sqrt (f64.add (f64.mul (local.get $a) (local.get $a))
///                        (f64.mul (local.get $b) (local.get $b))))))
fn get_float_ops_wasm() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x07\x01\x60\x02\x7c\x7c\x01\x7c\x03\x02\x01\x00\x07\x0d\x01\x09\x66\x6c\x6f\x61\x74\x5f\x6f\x70\x73\x00\x00\x0a\x13\x01\x11\x00\x20\x00\x20\x00\xa2\x20\x01\x20\x01\xa2\xa0\x9f\x0b"
}

///|
/// i64 operations - 64-bit integer arithmetic
/// (module
///   (func (export "i64_ops") (param $a i64) (param $b i64) (result i64)
///     (i64.add (i64.mul (local.get $a) (local.get $b))
///              (i64.sub (local.get $a) (local.get $b)))))
fn get_i64_ops_wasm() -> Bytes {
  b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x07\x01\x60\x02\x7e\x7e\x01\x7e\x03\x02\x01\x00\x07\x0b\x01\x07\x69\x36\x34\x5f\x6f\x70\x73\x00\x00\x0a\x0e\x01\x0c\x00\x20\x00\x20\x01\x7e\x20\x00\x20\x01\x7d\x7c\x0b"
}


// =============================================================================
// Benchmark Tests - Parse
// =============================================================================

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
test "bench_parse_simple" (b : @bench.T) {
  let wasm_bytes = get_add_wasm()
  b.bench(
    name="parse_add",
    fn() {
      try {
        b.keep(@wasm5_parse.parse(wasm_bytes))
      } catch {
        _ => ()
      }
    },
  )
}

// =============================================================================
// Benchmark Tests - Load and Compile
// =============================================================================

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

// =============================================================================
// Benchmark Tests - Execution (Core)
// =============================================================================

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

// =============================================================================
// Benchmark Tests - Loops and Control Flow
// =============================================================================

///|
test "bench_loop_1000" (b : @bench.T) {
  let wasm_bytes = get_loop_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="loop_1000",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled(
          "count",
          [@wasm5_runtime.Value::I32(1000)],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

// nested_loop benchmark removed - WASM binary needs regeneration

// =============================================================================
// Benchmark Tests - Function Calls
// =============================================================================

///|
test "bench_factorial_10" (b : @bench.T) {
  let wasm_bytes = get_factorial_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="factorial_10",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled(
          "factorial",
          [@wasm5_runtime.Value::I32(10)],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

// multi_call benchmark removed - WASM binary needs regeneration

// =============================================================================
// Benchmark Tests - Integer Operations
// =============================================================================

///|
test "bench_i64_ops" (b : @bench.T) {
  let wasm_bytes = get_i64_ops_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="i64_ops",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled(
          "i64_ops",
          [
            @wasm5_runtime.Value::I64(123456789012345),
            @wasm5_runtime.Value::I64(987654321098765),
          ],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

// =============================================================================
// Benchmark Tests - Float Operations
// =============================================================================

///|
test "bench_float_ops" (b : @bench.T) {
  let wasm_bytes = get_float_ops_wasm()
  let module_ = @wasm5_parse.parse(wasm_bytes)
  let runtime = @wasm5_runtime.Runtime::load(module_).compile()
  b.bench(
    name="float_sqrt_hypot",
    fn() {
      try {
        let (rt, _) = runtime.call_compiled(
          "float_ops",
          [@wasm5_runtime.Value::F64(3.0), @wasm5_runtime.Value::F64(4.0)],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}

// =============================================================================
// Benchmark Tests - Memory Operations
// =============================================================================

// memory_sum benchmark removed - WASM binary needs regeneration

// =============================================================================
// Benchmark Tests - Full Pipeline
// =============================================================================

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
test "bench_full_pipeline_loop" (b : @bench.T) {
  let wasm_bytes = get_loop_wasm()
  b.bench(
    name="full_pipeline_loop",
    fn() {
      try {
        let module_ = @wasm5_parse.parse(wasm_bytes)
        let runtime = @wasm5_runtime.Runtime::load(module_).compile()
        let (rt, _) = runtime.call_compiled(
          "count",
          [@wasm5_runtime.Value::I32(100)],
        )
        b.keep(rt)
      } catch {
        _ => ()
      }
    },
  )
}
