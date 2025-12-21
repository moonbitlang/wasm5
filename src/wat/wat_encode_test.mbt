///|
async fn ensure_dir(path : String) -> Unit {
  let _ = @fs.mkdir(path, permission=0o755) catch { _ => () }

}

///|
async fn assert_wat_matches(name : String, wat : String) -> Unit {
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let dir = base_dir + "/" + name + "/"
  ensure_dir(dir)
  let wat_path = dir + "input.wat"
  let ours_path = dir + "ours.wasm"
  let ref_path = dir + "ref.wasm"
  let ref_stripped_path = dir + "ref_stripped.wasm"
  let wat_file = @fs.create(wat_path, permission=0o644)
  defer wat_file.close()
  wat_file.write(wat)
  let ours = wat_to_wasm(wat)
  let ours_file = @fs.create(ours_path, permission=0o644)
  defer ours_file.close()
  ours_file.write(ours)
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", ref_path])
  assert_eq(exit_code, 0)
  let strip_code = @process.run("wasm-tools", [
    "strip", "--all", ref_path, "-o", ref_stripped_path,
  ])
  assert_eq(strip_code, 0)
  let ref_file = @fs.open(ref_stripped_path, mode=ReadOnly)
  defer ref_file.close()
  let ref_bytes = ref_file.read_all().binary()
  assert_eq(ours, ref_bytes)
}

///|
async test "wat encoder matches wasm-tools for add" {
  let wat = "(module (func (export \"add\") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))"
  assert_wat_matches("add", wat)
}

///|
async test "wat encoder matches wasm-tools for imports" {
  let wat = "(module (import \"env\" \"inc\" (func $inc (param i32) (result i32))) (global (export \"g\") i32 (i32.const 7)) (func (export \"call\") (param i32) (result i32) local.get 0 call $inc))"
  assert_wat_matches("imports", wat)
}

///|
async test "wat encoder matches wasm-tools for data" {
  let wat = "(module (memory (export \"mem\") 1) (data (i32.const 0) \"hi\"))"
  assert_wat_matches("data", wat)
}

///|
async test "wat encoder matches wasm-tools for local names" {
  let wat = "(module (func (export \"inc\") (param $x i32) (result i32) local.get $x i32.const 1 i32.add))"
  assert_wat_matches("local_names", wat)
}

///|
async test "wat encoder matches wasm-tools for global init get" {
  let wat = "(module (import \"env\" \"g\" (global $g i32)) (global (export \"h\") i32 (global.get $g)))"
  assert_wat_matches("global_init", wat)
}

///|
async test "wat encoder matches wasm-tools for data offset global" {
  let wat = "(module (import \"env\" \"g\" (global $g i32)) (memory 1) (data (global.get $g) \"hi\"))"
  assert_wat_matches("data_global", wat)
}

///|
async test "wat encoder matches wasm-tools for float consts" {
  let wat = "(module (func (export \"f32\") (result f32) f32.const 1.5) (func (export \"f64\") (result f64) f64.const -2.25))"
  assert_wat_matches("float_consts", wat)
}
