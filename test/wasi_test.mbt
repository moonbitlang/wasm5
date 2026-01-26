///|
/// WASI Test Runner
/// Tests WASI functions using preopened files for I/O verification

// Counter for unique temp file names
let wasi_temp_counter : Ref[Int] = { val: 0 }

///|
/// Generate unique temp file path
fn get_wasi_temp_path() -> String {
  wasi_temp_counter.val += 1
  "/tmp/wasi_test_\{wasi_temp_counter.val}.txt"
}

///|
/// Helper: compile WAT file to WASM bytes using wasm-tools
async fn compile_wasi_wat(wat_path : String) -> Bytes raise Error {
  let base = match wat_path.strip_suffix(".wat") {
    Some(s) => s.to_string()
    None => wat_path
  }
  let wasm_path = base + ".wasm"

  // Run wasm-tools wat2wasm
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", wasm_path])
  if exit_code != 0 {
    raise WasiTestError("Failed to compile WAT file: \{wat_path}")
  }

  // Read the compiled WASM
  let data = @fs.read_file(wasm_path)
  let wasm = data.binary()

  // Clean up the WASM file
  @fs.remove(wasm_path)

  wasm
}

///|
/// Helper: run WASI module with preopened file, return file contents after execution
async fn run_wasi_with_preopen(
  wasm : Bytes,
  initial_content : String,
) -> (String, Int) raise Error {
  // Create temp file
  let temp_path = get_wasi_temp_path()

  // Write initial content to temp file
  if initial_content.length() > 0 {
    @fs.write_file(temp_path, initial_content, create=0o644, truncate=true)
  } else {
    // Create empty file
    let temp_file = @fs.create(temp_path, permission=0o644)
    temp_file.close()
  }

  // Open file for read/write and get fd
  let preopen_file = @fs.open(temp_path, mode=ReadWrite)
  let host_fd = preopen_file.fd()

  // Initialize WASI and add preopen
  @wasm5_cruntime.init_wasi()
  let wasi_fd = @wasm5_cruntime.wasi_add_preopen_file(host_fd)
  if wasi_fd < 0 {
    preopen_file.close()
    @fs.remove(temp_path)
    raise WasiTestError("Failed to add preopen file")
  }

  // Parse and run the WASI module
  let module_ = @wasm5_parse.parse(wasm)
  @wasm5_validate.validate_module(module_)
  let runtime = @wasm5_cruntime.CRuntime::load(module_)

  // Try to run _start function
  let _ = runtime.call_compiled(b"_start", []) catch { _ => [] }

  // Get exit code
  let exit_code = if @wasm5_cruntime.wasi_has_exited() {
    @wasm5_cruntime.wasi_exit_code()
  } else {
    0
  }

  // Close preopen and reset
  preopen_file.close()
  @wasm5_cruntime.wasi_reset_preopens()

  // Read file contents
  let data = @fs.read_file(temp_path)
  let content = try {
    data.text()
  } catch {
    _ => wasi_bytes_to_string(data.binary())
  }

  // Clean up temp file
  @fs.remove(temp_path)

  (content, exit_code)
}

///|
/// Convert Bytes to String (assuming ASCII/UTF-8)
fn wasi_bytes_to_string(b : Bytes) -> String {
  let chars : Array[Char] = []
  for i in 0..<b.length() {
    chars.push(b[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

///|
/// WASI test error type
suberror WasiTestError {
  WasiTestError(String)
}

///|
/// Test fd_write to preopened file
async test "wasi/fd_write" {
  let wasm = compile_wasi_wat("test/wasi/fd_write.wat")
  let (output, exit_code) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "Hello, WASI!")
  assert_eq(exit_code, 0)
}

///|
/// Test proc_exit with code 42
async test "wasi/exit_42" {
  let wasm = compile_wasi_wat("test/wasi/exit.wat")
  let (_, exit_code) = run_wasi_with_preopen(wasm, "")
  assert_eq(exit_code, 42)
}

///|
/// Test proc_exit with code 0
async test "wasi/exit_zero" {
  let wasm = compile_wasi_wat("test/wasi/exit_zero.wat")
  let (_, exit_code) = run_wasi_with_preopen(wasm, "")
  assert_eq(exit_code, 0)
}

///|
/// Test args_sizes_get - argc should be 1 (just "wasm5")
async test "wasi/args_sizes_get" {
  let wasm = compile_wasi_wat("test/wasi/args.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "1")
}

///|
/// Test environ_sizes_get - should return 0 env vars
async test "wasi/environ_sizes_get" {
  let wasm = compile_wasi_wat("test/wasi/environ.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "0")
}

///|
/// Test clock_time_get - should return non-zero timestamp
async test "wasi/clock_time_get" {
  let wasm = compile_wasi_wat("test/wasi/clock.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test random_get - should fill buffer with non-zero bytes
async test "wasi/random_get" {
  let wasm = compile_wasi_wat("test/wasi/random.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_prestat_get - fd 3 should be a valid preopen
async test "wasi/fd_prestat_get" {
  let wasm = compile_wasi_wat("test/wasi/prestat.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_fdstat_get - fd 3 should return success
async test "wasi/fd_fdstat_get" {
  let wasm = compile_wasi_wat("test/wasi/fdstat.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}
