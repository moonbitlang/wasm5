///|
/// WASI Test Runner
/// Tests WASI functions using preopened files for I/O verification

// Counter for unique temp file names
let wasi_temp_counter : Ref[Int] = { val: 0 }
// Counter for unique temp dir names

///|
let wasi_temp_dir_counter : Ref[Int] = { val: 0 }

///|
/// Generate unique temp file path
fn get_wasi_temp_path() -> String {
  wasi_temp_counter.val += 1
  "/tmp/wasi_test_\{wasi_temp_counter.val}.txt"
}

///|
/// Generate unique temp dir path
fn get_wasi_temp_dir() -> String {
  wasi_temp_dir_counter.val += 1
  "/tmp/wasi_test_dir_\{wasi_temp_dir_counter.val}"
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
  let exit_code = @process.run("wasm-tools", [
    "parse", wat_path, "-o", wasm_path,
  ])
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
  let content = data.text() catch { _ => wasi_bytes_to_string(data.binary()) }

  // Clean up temp file
  @fs.remove(temp_path)
  (content, exit_code)
}

///|
/// Helper: run WASI module with preopened file + directory
async fn run_wasi_with_preopen_dir(
  wasm : Bytes,
  initial_content : String,
) -> (String, Int) raise Error {
  // Create temp file (output)
  let temp_path = get_wasi_temp_path()

  // Create temp directory
  let temp_dir = get_wasi_temp_dir()
  let _ = @fs.mkdir(temp_dir, permission=0o755) catch { _ => () }

  // Write initial content to temp file
  if initial_content.length() > 0 {
    @fs.write_file(temp_path, initial_content, create=0o644, truncate=true)
  } else {
    let temp_file = @fs.create(temp_path, permission=0o644)
    temp_file.close()
  }

  // Open file and directory
  let preopen_file = @fs.open(temp_path, mode=ReadWrite)
  let preopen_dir = @fs.open(temp_dir, mode=ReadOnly)
  let host_fd = preopen_file.fd()
  let dir_fd = preopen_dir.fd()

  // Initialize WASI and add preopens
  @wasm5_cruntime.init_wasi()
  let wasi_fd_file = @wasm5_cruntime.wasi_add_preopen_file(host_fd)
  if wasi_fd_file < 0 {
    preopen_file.close()
    preopen_dir.close()
    @fs.remove(temp_path)
    @fs.rmdir(temp_dir, recursive=true)
    raise WasiTestError("Failed to add preopen file")
  }
  let wasi_fd_dir = @wasm5_cruntime.wasi_add_preopen_file(dir_fd)
  if wasi_fd_dir < 0 {
    preopen_file.close()
    preopen_dir.close()
    @fs.remove(temp_path)
    @fs.rmdir(temp_dir, recursive=true)
    raise WasiTestError("Failed to add preopen dir")
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

  // Close preopens and reset
  preopen_file.close()
  preopen_dir.close()
  @wasm5_cruntime.wasi_reset_preopens()

  // Read file contents
  let data = @fs.read_file(temp_path)
  let content = data.text() catch { _ => wasi_bytes_to_string(data.binary()) }

  // Clean up temp file/dir
  @fs.remove(temp_path)
  @fs.rmdir(temp_dir, recursive=true)
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
/// Test fd_read from preopened file (append read content)
async test "wasi/fd_read" {
  let wasm = compile_wasi_wat("test/wasi/fd_read.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "Hello")
  assert_eq(output, "HelloHello")
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
/// Test args_get - argv[0] should be "wasm5"
async test "wasi/args_get" {
  let wasm = compile_wasi_wat("test/wasi/args_get.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "wasm5")
}

///|
/// Test environ_sizes_get - should return 0 env vars
async test "wasi/environ_sizes_get" {
  let wasm = compile_wasi_wat("test/wasi/environ.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "0")
}

///|
/// Test environ_get - should return ok when env is empty
async test "wasi/environ_get" {
  let wasm = compile_wasi_wat("test/wasi/environ_get.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
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
/// Test fd_prestat_dir_name - fd 4 should return "<test>"
async test "wasi/fd_prestat_dir_name" {
  let wasm = compile_wasi_wat("test/wasi/fd_prestat_dir_name.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "<test>")
}

///|
/// Test fd_fdstat_get - fd 3 should return success
async test "wasi/fd_fdstat_get" {
  let wasm = compile_wasi_wat("test/wasi/fdstat.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_seek - seek to position in file
/// Writes "Hello", seeks to 0, writes "ok" -> result is "okllo"
async test "wasi/fd_seek" {
  let wasm = compile_wasi_wat("test/wasi/fd_seek.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "okllo") // "ok" overwrites first 2 chars of "Hello"
}

///|
/// Test fd_tell - get current file position
async test "wasi/fd_tell" {
  let wasm = compile_wasi_wat("test/wasi/fd_tell.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "Hellook")
}

///|
/// Test fd_filestat_get - get file stats
async test "wasi/fd_filestat_get" {
  let wasm = compile_wasi_wat("test/wasi/fd_filestat_get.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_sync - sync file to storage
async test "wasi/fd_sync" {
  let wasm = compile_wasi_wat("test/wasi/fd_sync.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "Hellook")
}

///|
/// Test fd_datasync - sync file data to storage
async test "wasi/fd_datasync" {
  let wasm = compile_wasi_wat("test/wasi/fd_datasync.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_fdstat_set_flags - should succeed
async test "wasi/fd_fdstat_set_flags" {
  let wasm = compile_wasi_wat("test/wasi/fd_fdstat_set_flags.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_fdstat_set_rights - should succeed
async test "wasi/fd_fdstat_set_rights" {
  let wasm = compile_wasi_wat("test/wasi/fd_fdstat_set_rights.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test sched_yield - yield CPU
async test "wasi/sched_yield" {
  let wasm = compile_wasi_wat("test/wasi/sched_yield.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test clock_res_get - get clock resolution
async test "wasi/clock_res_get" {
  let wasm = compile_wasi_wat("test/wasi/clock_res_get.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test clock_res_get rejects invalid clock_id
async test "wasi/clock_res_get_invalid" {
  let wasm = compile_wasi_wat("test/wasi/clock_res_get_invalid.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "28")
}

///|
/// Test fd_pread - read at offset without changing file position
/// Writes "Hello", pread verifies content, seeks to 0, writes "ok" -> "okllo"
async test "wasi/fd_pread" {
  let wasm = compile_wasi_wat("test/wasi/fd_pread.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "okllo")
}

///|
/// Test fd_pwrite - write at offset without changing file position
/// Writes "Hello", then pwrite "ok" at offset 0, resulting in "okllo"
async test "wasi/fd_pwrite" {
  let wasm = compile_wasi_wat("test/wasi/fd_pwrite.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "okllo")
}

///|
/// Test fd_write returns BADF for invalid fd
async test "wasi/fd_write_badf" {
  let wasm = compile_wasi_wat("test/wasi/fd_write_badf.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "8")
}

///|
/// Test fd_read returns BADF for invalid fd
async test "wasi/fd_read_badf" {
  let wasm = compile_wasi_wat("test/wasi/fd_read_badf.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "8")
}

///|
/// Test fd_pread returns BADF for invalid fd
async test "wasi/fd_pread_badf" {
  let wasm = compile_wasi_wat("test/wasi/fd_pread_badf.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "8")
}

///|
/// Test fd_pwrite returns BADF for invalid fd
async test "wasi/fd_pwrite_badf" {
  let wasm = compile_wasi_wat("test/wasi/fd_pwrite_badf.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "8")
}

///|
/// Test fd_seek rejects invalid whence
async test "wasi/fd_seek_invalid_whence" {
  let wasm = compile_wasi_wat("test/wasi/fd_seek_invalid_whence.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "28")
}

///|
/// Test fd_filestat_set_times - should succeed
async test "wasi/fd_filestat_set_times" {
  let wasm = compile_wasi_wat("test/wasi/fd_filestat_set_times.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_advise - should succeed
async test "wasi/fd_advise" {
  let wasm = compile_wasi_wat("test/wasi/fd_advise.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_allocate - should succeed
async test "wasi/fd_allocate" {
  let wasm = compile_wasi_wat("test/wasi/fd_allocate.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test fd_renumber - should move fd and invalidate old number
async test "wasi/fd_renumber" {
  let wasm = compile_wasi_wat("test/wasi/fd_renumber.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test proc_raise - should return NOSYS (52)
async test "wasi/proc_raise" {
  let wasm = compile_wasi_wat("test/wasi/proc_raise.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "52")
}

///|
/// Test fd_filestat_set_size - truncate file to specified size
/// Writes "Hello World" (11 bytes), truncates to 5, verifies size, writes "ok" -> "okllo"
async test "wasi/fd_filestat_set_size" {
  let wasm = compile_wasi_wat("test/wasi/fd_filestat_set_size.wat")
  let (output, _) = run_wasi_with_preopen(wasm, "")
  assert_eq(output, "okllo")
}

///|
/// Test path_open + fd_close using preopened directory
async test "wasi/path_open_fd_close" {
  let wasm = compile_wasi_wat("test/wasi/path_open_fd_close.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_filestat_get using preopened directory
async test "wasi/path_filestat_get" {
  let wasm = compile_wasi_wat("test/wasi/path_filestat_get.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_filestat_set_times
async test "wasi/path_filestat_set_times" {
  let wasm = compile_wasi_wat("test/wasi/path_filestat_set_times.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_create_directory + path_remove_directory
async test "wasi/path_create_remove_directory" {
  let wasm = compile_wasi_wat("test/wasi/path_create_remove_directory.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_unlink_file
async test "wasi/path_unlink_file" {
  let wasm = compile_wasi_wat("test/wasi/path_unlink_file.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_rename
async test "wasi/path_rename" {
  let wasm = compile_wasi_wat("test/wasi/path_rename.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_link
async test "wasi/path_link" {
  let wasm = compile_wasi_wat("test/wasi/path_link.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}

///|
/// Test path_symlink + path_readlink
async test "wasi/path_symlink_readlink" {
  let wasm = compile_wasi_wat("test/wasi/path_symlink_readlink.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "target.txt")
}

///|
/// Test fd_readdir using preopened directory
async test "wasi/fd_readdir" {
  let wasm = compile_wasi_wat("test/wasi/fd_readdir.wat")
  let (output, _) = run_wasi_with_preopen_dir(wasm, "")
  assert_eq(output, "ok")
}
