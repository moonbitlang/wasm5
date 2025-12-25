///|
async fn ensure_dir(path : String) -> Unit {
  let _ = @fs.mkdir(path, permission=0o755) catch { _ => () }

}

///|
async fn wasm_tools_available() -> Bool {
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let ok_path = base_dir + "/.wasm_tools_ok"
  let missing_path = base_dir + "/.wasm_tools_missing"
  if @fs.exists(ok_path) {
    return true
  }
  if @fs.exists(missing_path) {
    return false
  }
  let exit_code = @process.run("wasm-tools", ["--version"]) catch {
    _ => {
      let missing_file = @fs.create(missing_path, permission=0o644)
      missing_file.close()
      return false
    }
  }
  if exit_code == 0 {
    let ok_file = @fs.create(ok_path, permission=0o644)
    ok_file.close()
    return true
  }
  let missing_file = @fs.create(missing_path, permission=0o644)
  missing_file.close()
  false
}

///|
fn empty_module() -> @core.Module {
  {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
}

///|
async fn assert_wat_matches(name : String, wat : String) -> Unit {
  guard wasm_tools_available() else { return }
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let dir = base_dir + "/" + name + "/"
  ensure_dir(dir)
  let wat_path = dir + "input.wat"
  let ours_path = dir + "ours.wasm"
  let ours_stripped_path = dir + "ours_stripped.wasm"
  let ref_path = dir + "ref.wasm"
  let ref_stripped_path = dir + "ref_stripped.wasm"
  let wat_file = @fs.create(wat_path, permission=0o644)
  defer wat_file.close()
  wat_file.write(wat)
  let ours = wat_to_wasm(wat)
  let ours_file = @fs.create(ours_path, permission=0o644)
  defer ours_file.close()
  ours_file.write(ours)
  let ours_strip = @process.run("wasm-tools", [
    "strip", "--all", ours_path, "-o", ours_stripped_path,
  ])
  assert_eq(ours_strip, 0)
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", ref_path])
  assert_eq(exit_code, 0)
  let strip_code = @process.run("wasm-tools", [
    "strip", "--all", ref_path, "-o", ref_stripped_path,
  ])
  assert_eq(strip_code, 0)
  let ours_stripped_file = @fs.open(ours_stripped_path, mode=ReadOnly)
  defer ours_stripped_file.close()
  let ours_bytes = ours_stripped_file.read_all().binary()
  let ref_file = @fs.open(ref_stripped_path, mode=ReadOnly)
  defer ref_file.close()
  let ref_bytes = ref_file.read_all().binary()
  assert_eq(ours_bytes, ref_bytes)
}

///|
async fn assert_wat_matches_custom(name : String, wat : String) -> Unit {
  guard wasm_tools_available() else { return }
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let dir = base_dir + "/" + name + "/"
  ensure_dir(dir)
  let wat_path = dir + "input.wat"
  let ours_path = dir + "ours.wasm"
  let ours_stripped_path = dir + "ours_stripped.wasm"
  let ref_path = dir + "ref.wasm"
  let ref_stripped_path = dir + "ref_stripped.wasm"
  let wat_file = @fs.create(wat_path, permission=0o644)
  defer wat_file.close()
  wat_file.write(wat)
  let ours = wat_to_wasm(wat)
  let ours_file = @fs.create(ours_path, permission=0o644)
  defer ours_file.close()
  ours_file.write(ours)
  let ours_strip = @process.run("wasm-tools", [
    "strip", "--delete", "^name$", ours_path, "-o", ours_stripped_path,
  ])
  assert_eq(ours_strip, 0)
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", ref_path])
  assert_eq(exit_code, 0)
  let strip_code = @process.run("wasm-tools", [
    "strip", "--delete", "^name$", ref_path, "-o", ref_stripped_path,
  ])
  assert_eq(strip_code, 0)
  let ours_stripped_file = @fs.open(ours_stripped_path, mode=ReadOnly)
  defer ours_stripped_file.close()
  let ours_bytes = ours_stripped_file.read_all().binary()
  let ref_file = @fs.open(ref_stripped_path, mode=ReadOnly)
  defer ref_file.close()
  let ref_bytes = ref_file.read_all().binary()
  assert_eq(ours_bytes, ref_bytes)
}

///|
async fn assert_wat_matches_with_names(name : String, wat : String) -> Unit {
  guard wasm_tools_available() else { return }
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let dir = base_dir + "/" + name + "/"
  ensure_dir(dir)
  let wat_path = dir + "input.wat"
  let ours_path = dir + "ours.wasm"
  let ref_path = dir + "ref.wasm"
  let wat_file = @fs.create(wat_path, permission=0o644)
  defer wat_file.close()
  wat_file.write(wat)
  let ours = wat_to_wasm(wat)
  let ours_file = @fs.create(ours_path, permission=0o644)
  defer ours_file.close()
  ours_file.write(ours)
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", ref_path])
  assert_eq(exit_code, 0)
  let ref_file = @fs.open(ref_path, mode=ReadOnly)
  defer ref_file.close()
  let ref_bytes = ref_file.read_all().binary()
  assert_eq(ours, ref_bytes)
}

///|
async fn assert_wasm_matches_wat(
  name : String,
  wat : String,
  wasm : Bytes,
) -> Unit {
  guard wasm_tools_available() else { return }
  let base_dir = "target/wat_tests"
  ensure_dir(base_dir)
  let dir = base_dir + "/" + name + "/"
  ensure_dir(dir)
  let wat_path = dir + "input.wat"
  let ours_path = dir + "ours.wasm"
  let ours_stripped_path = dir + "ours_stripped.wasm"
  let ref_path = dir + "ref.wasm"
  let ref_stripped_path = dir + "ref_stripped.wasm"
  let wat_file = @fs.create(wat_path, permission=0o644)
  defer wat_file.close()
  wat_file.write(wat)
  let ours_file = @fs.create(ours_path, permission=0o644)
  defer ours_file.close()
  ours_file.write(wasm)
  let ours_strip = @process.run("wasm-tools", [
    "strip", "--all", ours_path, "-o", ours_stripped_path,
  ])
  assert_eq(ours_strip, 0)
  let exit_code = @process.run("wasm-tools", ["parse", wat_path, "-o", ref_path])
  assert_eq(exit_code, 0)
  let strip_code = @process.run("wasm-tools", [
    "strip", "--all", ref_path, "-o", ref_stripped_path,
  ])
  assert_eq(strip_code, 0)
  let ours_stripped_file = @fs.open(ours_stripped_path, mode=ReadOnly)
  defer ours_stripped_file.close()
  let ours_bytes = ours_stripped_file.read_all().binary()
  let ref_file = @fs.open(ref_stripped_path, mode=ReadOnly)
  defer ref_file.close()
  let ref_bytes = ref_file.read_all().binary()
  assert_eq(ours_bytes, ref_bytes)
}

///|
async test "wat encoder matches wasm-tools for add" {
  let wat =
    #|(module (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))
  assert_wat_matches("add", wat)
}

///|
async test "wat encoder matches wasm-tools for imports" {
  let wat =
    #|(module (import "env" "inc" (func $inc (param i32) (result i32))) (global (export "g") i32 (i32.const 7)) (func (export "call") (param i32) (result i32) local.get 0 call $inc))
  assert_wat_matches("imports", wat)
}

///|
async test "wat encoder matches wasm-tools for memory/table imports" {
  let wat =
    #|(module (import "env" "tab" (table 1 3 funcref)) (import "env" "mem" (memory 1 2)) (func (export "msize") (result i32) memory.size) (func (export "tsize") (result i32) table.size))
  assert_wat_matches("import_mem_table", wat)
}

///|
async test "wat encoder matches wasm-tools for memory/table imports i32" {
  let wat =
    #|(module
    #|  (import "env" "tab" (table i32 1 3 funcref))
    #|  (import "env" "mem" (memory i32 1 2))
    #|  (func (export "msize") (result i32) memory.size)
    #|  (func (export "tsize") (result i32) table.size))
  assert_wat_matches("import_mem_table_i32", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64/table64 imports" {
  let wat =
    #|(module
    #|  (import "env" "tab" (table i64 1 funcref))
    #|  (import "env" "mem" (memory i64 1 2))
    #|  (func (export "msize") (result i64) memory.size)
    #|  (func (export "tsize") (result i64) table.size))
  assert_wat_matches("import_mem_table64", wat)
}

///|
async test "wat encoder matches wasm-tools for inline imports" {
  let wat =
    #|(module
    #|  (func $f (export "f") (import "env" "f") (param i32) (result i32))
    #|  (memory $m (export "mem") (import "env" "mem") 1)
    #|  (table $t (export "tab") (import "env" "tab") 1 funcref)
    #|  (global $g (export "g") (import "env" "g") (mut i32))
    #|  (tag $e (export "tag") (import "env" "tag") (param i32)))
  assert_wat_matches("inline_imports", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64/table64 definitions" {
  let wat =
    #|(module
    #|  (memory i64 1 2)
    #|  (table i64 1 funcref)
    #|  (func (export "msize") (result i64) memory.size)
    #|  (func (export "tsize") (result i64) table.size))
  assert_wat_matches("mem_table64", wat)
}

///|
async test "wat encoder matches wasm-tools for memory/table definitions i32" {
  let wat =
    #|(module
    #|  (memory i32 1 2)
    #|  (table i32 1 funcref)
    #|  (func (export "msize") (result i32) memory.size)
    #|  (func (export "tsize") (result i32) table.size))
  assert_wat_matches("mem_table_i32", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64 data offset" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (data (i64.const 0) "hi"))
  assert_wat_matches("mem64_data_offset", wat)
}

///|
async test "wat encoder matches wasm-tools for table64 elem offset" {
  let wat =
    #|(module
    #|  (table i64 1 funcref)
    #|  (elem (i64.const 0) funcref (ref.null func)))
  assert_wat_matches("table64_elem_offset", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64 data offset global" {
  let wat =
    #|(module
    #|  (import "env" "g" (global $g i64))
    #|  (memory i64 1)
    #|  (data (global.get $g) "hi"))
  assert_wat_matches("mem64_data_offset_global", wat)
}

///|
async test "wat encoder matches wasm-tools for table64 elem offset global" {
  let wat =
    #|(module
    #|  (import "env" "g" (global $g i64))
    #|  (table i64 1 funcref)
    #|  (elem (global.get $g) funcref (ref.null func)))
  assert_wat_matches("table64_elem_offset_global", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64 shared" {
  let wat =
    #|(module
    #|  (memory i64 1 2 shared)
    #|  (func (export "grow") (param i64) (result i64) local.get 0 memory.grow))
  assert_wat_matches("mem64_shared", wat)
}

///|
async test "wat encoder matches wasm-tools for memory64 inline data" {
  let wat =
    #|(module
    #|  (memory i64 (data "hi"))
    #|  (func (export "size") (result i64) memory.size))
  assert_wat_matches("mem64_inline_data", wat)
}

///|
async test "wat encoder matches wasm-tools for table64 inline elem" {
  let wat =
    #|(module
    #|  (func $f)
    #|  (func $g)
    #|  (table i64 funcref (elem $f $g))
    #|  (func (export "tsize") (result i64) table.size))
  assert_wat_matches("table64_inline_elem", wat)
}

///|
test "wat parser rejects i32 offset for memory64 data" {
  let wat =
    #|(module (memory i64 1) (data (i32.const 0) "hi"))
  let mut saw_error = false
  let _ = wat_to_module(wat) catch {
    _ => {
      saw_error = true
      empty_module()
    }
  }
  assert_eq(saw_error, true)
}

///|
test "wat parser rejects i32 offset for table64 elem" {
  let wat =
    #|(module (table i64 1 funcref) (elem (i32.const 0) funcref (ref.null func)))
  let mut saw_error = false
  let _ = wat_to_module(wat) catch {
    _ => {
      saw_error = true
      empty_module()
    }
  }
  assert_eq(saw_error, true)
}

///|
async test "wat encoder matches wasm-tools for data" {
  let wat =
    #|(module (memory (export "mem") 1) (data (i32.const 0) "hi"))
  assert_wat_matches("data", wat)
}

///|
async test "wat encoder matches wasm-tools for unicode string escapes" {
  let wat =
    #|(module (memory 1) (data (i32.const 0) "\u{1F600}\u{2603}"))
  assert_wat_matches("data_unicode_escape", wat)
}

///|
async test "wat encoder matches wasm-tools for inline memory data" {
  let wat =
    #|(module (memory (data "hi")))
  assert_wat_matches("inline_memory_data", wat)
}

///|
async test "wat encoder matches wasm-tools for inline memory data export" {
  let wat =
    #|(module (memory (export "mem") (data "hi")))
  assert_wat_matches("inline_memory_data_export", wat)
}

///|
async test "wat encoder matches wasm-tools for data concat" {
  let wat =
    #|(module (memory 1) (data (i32.const 0) "hi" " " "there"))
  assert_wat_matches("data_concat", wat)
}

///|
async test "wat encoder matches wasm-tools for local names" {
  let wat =
    #|(module (func (export "inc") (param $x i32) (result i32) local.get $x i32.const 1 i32.add))
  assert_wat_matches("local_names", wat)
}

///|
async test "wat encoder matches wasm-tools for global init get" {
  let wat =
    #|(module (import "env" "g" (global $g i32)) (global (export "h") i32 (global.get $g)))
  assert_wat_matches("global_init", wat)
}

///|
async test "wat encoder matches wasm-tools for ref globals" {
  let wat =
    #|(module (func $f (result i32) i32.const 0) (global (export "gnull") funcref (ref.null func)) (global (export "gfunc") funcref (ref.func $f)))
  assert_wat_matches("global_ref_init", wat)
}

///|
async test "wat encoder matches wasm-tools for mutable globals" {
  let wat =
    #|(module (global $g (mut i64) (i64.const 1)) (func (export "set") (param i64) local.get 0 global.set $g))
  assert_wat_matches("global_mut", wat)
}

///|
async test "wat encoder matches wasm-tools for data offset global" {
  let wat =
    #|(module (import "env" "g" (global $g i32)) (memory 1) (data (global.get $g) "hi"))
  assert_wat_matches("data_global", wat)
}

///|
async test "wat encoder matches wasm-tools for start section" {
  let wat =
    #|(module (func $start nop) (start $start))
  assert_wat_matches("start_section", wat)
}

///|
async test "wat encoder matches wasm-tools for float consts" {
  let wat =
    #|(module (func (export "f32") (result f32) f32.const 1.5) (func (export "f64") (result f64) f64.const -2.25))
  assert_wat_matches("float_consts", wat)
}

///|
async test "wat encoder matches wasm-tools for float nan/inf literals" {
  let wat =
    #|(module (func (export "f") (result f32 f64) f32.const nan:0x200000 f64.const -inf))
  assert_wat_matches("float_nan_inf", wat)
}

///|
async test "wat encoder matches wasm-tools for hex float literals" {
  let wat =
    #|(module (func (export "f") (result f32 f64) f32.const 0x1.8p+1 f64.const -0x1.0p-1))
  assert_wat_matches("float_hex", wat)
}

///|
async test "wat encoder matches wasm-tools for numeric literals" {
  let wat =
    #|(module (func (export "lit") (result i32 i64 i32 i64) i32.const 0x2a i64.const -0x2a i32.const 1_000 i64.const 0x1_000))
  assert_wat_matches("numeric_literals", wat)
}

///|
async test "wat encoder matches wasm-tools for numeric ops" {
  let wat =
    #|(module (func (export "i32_ops") (param i32 i32) (result i32) nop local.get 0 i32.eqz drop local.get 0 local.get 1 i32.eq drop local.get 0 local.get 1 i32.ne drop local.get 0 local.get 1 i32.lt_s drop local.get 0 local.get 1 i32.lt_u drop local.get 0 local.get 1 i32.gt_s drop local.get 0 local.get 1 i32.gt_u drop local.get 0 local.get 1 i32.le_s drop local.get 0 local.get 1 i32.le_u drop local.get 0 local.get 1 i32.ge_s drop local.get 0 local.get 1 i32.ge_u drop local.get 0 i32.clz drop local.get 0 i32.ctz drop local.get 0 i32.popcnt drop local.get 0 local.get 1 i32.add drop local.get 0 local.get 1 i32.sub drop local.get 0 local.get 1 i32.mul drop local.get 0 local.get 1 i32.div_s drop local.get 0 local.get 1 i32.div_u drop local.get 0 local.get 1 i32.rem_s drop local.get 0 local.get 1 i32.rem_u drop local.get 0 local.get 1 i32.and drop local.get 0 local.get 1 i32.or drop local.get 0 local.get 1 i32.xor drop local.get 0 local.get 1 i32.shl drop local.get 0 local.get 1 i32.shr_s drop local.get 0 local.get 1 i32.shr_u drop local.get 0 local.get 1 i32.rotl drop local.get 0 local.get 1 i32.rotr drop local.get 0 local.get 1 local.get 0 select drop i32.const 0) (func (export "i64_ops") (param i64 i64) (result i32) local.get 0 i64.eqz drop local.get 0 local.get 1 i64.eq drop local.get 0 local.get 1 i64.ne drop local.get 0 local.get 1 i64.lt_s drop local.get 0 local.get 1 i64.lt_u drop local.get 0 local.get 1 i64.gt_s drop local.get 0 local.get 1 i64.gt_u drop local.get 0 local.get 1 i64.le_s drop local.get 0 local.get 1 i64.le_u drop local.get 0 local.get 1 i64.ge_s drop local.get 0 local.get 1 i64.ge_u drop local.get 0 i64.clz drop local.get 0 i64.ctz drop local.get 0 i64.popcnt drop local.get 0 local.get 1 i64.add drop local.get 0 local.get 1 i64.sub drop local.get 0 local.get 1 i64.mul drop local.get 0 local.get 1 i64.div_s drop local.get 0 local.get 1 i64.div_u drop local.get 0 local.get 1 i64.rem_s drop local.get 0 local.get 1 i64.rem_u drop local.get 0 local.get 1 i64.and drop local.get 0 local.get 1 i64.or drop local.get 0 local.get 1 i64.xor drop local.get 0 local.get 1 i64.shl drop local.get 0 local.get 1 i64.shr_s drop local.get 0 local.get 1 i64.shr_u drop local.get 0 local.get 1 i64.rotl drop local.get 0 local.get 1 i64.rotr drop i32.const 0) (func (export "f32_ops") (param f32 f32) (result i32) local.get 0 local.get 1 f32.eq drop local.get 0 local.get 1 f32.ne drop local.get 0 local.get 1 f32.lt drop local.get 0 local.get 1 f32.gt drop local.get 0 local.get 1 f32.le drop local.get 0 local.get 1 f32.ge drop local.get 0 f32.abs drop local.get 0 f32.neg drop local.get 0 f32.ceil drop local.get 0 f32.floor drop local.get 0 f32.trunc drop local.get 0 f32.nearest drop local.get 0 f32.sqrt drop local.get 0 local.get 1 f32.add drop local.get 0 local.get 1 f32.sub drop local.get 0 local.get 1 f32.mul drop local.get 0 local.get 1 f32.div drop local.get 0 local.get 1 f32.min drop local.get 0 local.get 1 f32.max drop local.get 0 local.get 1 f32.copysign drop i32.const 0) (func (export "f64_ops") (param f64 f64) (result i32) local.get 0 local.get 1 f64.eq drop local.get 0 local.get 1 f64.ne drop local.get 0 local.get 1 f64.lt drop local.get 0 local.get 1 f64.gt drop local.get 0 local.get 1 f64.le drop local.get 0 local.get 1 f64.ge drop local.get 0 f64.abs drop local.get 0 f64.neg drop local.get 0 f64.ceil drop local.get 0 f64.floor drop local.get 0 f64.trunc drop local.get 0 f64.nearest drop local.get 0 f64.sqrt drop local.get 0 local.get 1 f64.add drop local.get 0 local.get 1 f64.sub drop local.get 0 local.get 1 f64.mul drop local.get 0 local.get 1 f64.div drop local.get 0 local.get 1 f64.min drop local.get 0 local.get 1 f64.max drop local.get 0 local.get 1 f64.copysign drop i32.const 0) (func (export "conv_ops") (param i32 i64 f32 f64) (result i32) local.get 1 i32.wrap_i64 drop local.get 2 i32.trunc_f32_s drop local.get 2 i32.trunc_f32_u drop local.get 3 i32.trunc_f64_s drop local.get 3 i32.trunc_f64_u drop local.get 0 i64.extend_i32_s drop local.get 0 i64.extend_i32_u drop local.get 2 i64.trunc_f32_s drop local.get 2 i64.trunc_f32_u drop local.get 3 i64.trunc_f64_s drop local.get 3 i64.trunc_f64_u drop local.get 0 f32.convert_i32_s drop local.get 0 f32.convert_i32_u drop local.get 1 f32.convert_i64_s drop local.get 1 f32.convert_i64_u drop local.get 3 f32.demote_f64 drop local.get 0 f64.convert_i32_s drop local.get 0 f64.convert_i32_u drop local.get 1 f64.convert_i64_s drop local.get 1 f64.convert_i64_u drop local.get 2 f64.promote_f32 drop local.get 2 i32.reinterpret_f32 drop local.get 3 i64.reinterpret_f64 drop local.get 0 f32.reinterpret_i32 drop local.get 1 f64.reinterpret_i64 drop local.get 0 i32.extend8_s drop local.get 0 i32.extend16_s drop local.get 1 i64.extend8_s drop local.get 1 i64.extend16_s drop local.get 1 i64.extend32_s drop local.get 2 i32.trunc_sat_f32_s drop local.get 2 i32.trunc_sat_f32_u drop local.get 3 i32.trunc_sat_f64_s drop local.get 3 i32.trunc_sat_f64_u drop local.get 2 i64.trunc_sat_f32_s drop local.get 2 i64.trunc_sat_f32_u drop local.get 3 i64.trunc_sat_f64_s drop local.get 3 i64.trunc_sat_f64_u drop i32.const 0))
  assert_wat_matches("numeric_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for memory ops" {
  let wat =
    #|(module (memory (export "mem") 1) (func (export "mem_ops") (result i32) i32.const 0 i32.const 42 i32.store offset=4 align=4 i32.const 0 i32.load offset=4 align=4 drop i32.const 8 i32.const 7 i32.store16 align=2 i32.const 8 i32.load16_u align=2 drop i32.const 12 i32.const 1 i32.store8 i32.const 12 i32.load8_s drop i32.const 16 i64.const 5 i64.store align=8 i32.const 16 i64.load align=8 drop i32.const 24 i64.const 9 i64.store32 i32.const 24 i64.load32_u drop memory.size drop i32.const 1 memory.grow drop i32.const 0 i32.const 8 i32.const 4 memory.copy i32.const 0 i32.const 0 i32.const 4 memory.fill i32.const 0))
  assert_wat_matches("memory_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for shared memory" {
  let wat =
    #|(module (memory 1 2 shared) (func (export "size") (result i32) memory.size))
  assert_wat_matches("shared_memory", wat)
}

///|
async test "wat encoder matches wasm-tools for shared memory i32" {
  let wat =
    #|(module
    #|  (memory i32 1 2 shared)
    #|  (func (export "size") (result i32) memory.size))
  assert_wat_matches("shared_memory_i32", wat)
}

///|
async test "wat encoder matches wasm-tools for multi-memory bulk ops" {
  let wat =
    #|(module (memory 1) (memory 1) (data "hi") (func (export "multi") memory.size 1 drop i32.const 0 memory.grow 1 drop i32.const 0 i32.const 0 i32.const 0 memory.copy 1 0 i32.const 0 i32.const 0 i32.const 0 memory.fill 1 i32.const 0 i32.const 0 i32.const 0 memory.init 1 0 data.drop 0 i32.const 0))
  assert_wat_matches("multi_memory_bulk", wat)
}

///|
async test "wat encoder matches wasm-tools for memarg literals" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (func (export "memarg")
    #|    i32.const 0
    #|    i32.load offset=0x10 align=4
    #|    drop
    #|    i32.const 0
    #|    i32.load offset=1_024 align=0x10
    #|    drop))
  assert_wat_matches("memarg_literals", wat)
}

///|
async test "wat encoder matches wasm-tools for memarg memory index" {
  let wat =
    #|(module
    #|  (memory $m0 1 1 shared)
    #|  (memory $m1 1 1 shared)
    #|  (func (export "memidx") (param i32) (result i32)
    #|    local.get 0
    #|    i32.load 1
    #|    drop
    #|    local.get 0
    #|    i32.load $m1 offset=4 align=4
    #|    drop
    #|    local.get 0
    #|    v128.load $m1
    #|    drop
    #|    local.get 0
    #|    i32.atomic.load $m1
    #|    drop
    #|    i32.const 0))
  assert_wat_matches("memarg_memidx", wat)
}

///|
async test "wat encoder matches wasm-tools for folded numeric exprs" {
  let wat =
    #|(module
    #|  (func (export "f") (result i32)
    #|    (i32.add (i32.const 7) (i32.mul (i32.const 2) (i32.const 3)))))
  assert_wat_matches("folded_numeric", wat)
}

///|
async test "wat encoder matches wasm-tools for folded if" {
  let wat =
    #|(module
    #|  (func (export "f") (result i32)
    #|    (if (result i32)
    #|      (i32.const 1)
    #|      (then (i32.const 2))
    #|      (else (i32.const 3)))))
  assert_wat_matches("folded_if", wat)
}

///|
async test "wat encoder matches wasm-tools for folded memarg" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (func (export "f") (result i32)
    #|    (i32.load offset=4 (i32.const 0))))
  assert_wat_matches("folded_memarg", wat)
}

///|
async test "wat encoder matches wasm-tools for folded call" {
  let wat =
    #|(module
    #|  (func $add (param i32 i32) (result i32) local.get 0 local.get 1 i32.add)
    #|  (func (export "call") (result i32)
    #|    (call $add (i32.const 2) (i32.const 3))))
  assert_wat_matches("folded_call", wat)
}

///|
async test "wat encoder matches wasm-tools for folded call_indirect" {
  let wat =
    #|(module
    #|  (type $t (func (param i32) (result i32)))
    #|  (table 1 funcref)
    #|  (func $f (type $t) (param i32) (result i32) local.get 0)
    #|  (elem (i32.const 0) $f)
    #|  (func (export "call") (param i32 i32) (result i32)
    #|    (call_indirect (type $t) (local.get 0) (local.get 1))))
  assert_wat_matches("folded_call_indirect", wat)
}

///|
async test "wat encoder matches wasm-tools for folded bulk/table ops" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (table 1 funcref)
    #|  (func $f)
    #|  (elem (i32.const 0) $f)
    #|  (data (i32.const 0) "hi")
    #|  (func (export "bulk") (result i32)
    #|    (memory.init 0 (i32.const 0) (i32.const 0) (i32.const 2))
    #|    (memory.copy (i32.const 0) (i32.const 1) (i32.const 1))
    #|    (memory.fill (i32.const 0) (i32.const 7) (i32.const 2))
    #|    data.drop 0
    #|    (table.init 0 (i32.const 0) (i32.const 0) (i32.const 1))
    #|    elem.drop 0
    #|    (table.copy 0 0 (i32.const 0) (i32.const 0) (i32.const 1))
    #|    i32.const 0))
  assert_wat_matches("folded_bulk_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for control flow" {
  let wat =
    #|(module (func (export "block_if") (param i32) (result i32) (block $out (result i32) i32.const 7 local.get 0 br_if $out i32.const 42)) (func (export "loop_br") (result i32) (block (result i32) (loop $top i32.const 9 br 1))) (func (export "if_else") (param i32) (result i32) local.get 0 (if (result i32) (then i32.const 1) (else i32.const 2))) (func (export "br_table") (param i32) (block local.get 0 br_table 0 0)))
  assert_wat_matches("control_flow", wat)
}

///|
async test "wat encoder matches wasm-tools for br_on_null" {
  let wat =
    #|(module (func (export "brs") (param funcref) (block $l local.get 0 br_on_null $l drop local.get 0 br_on_non_null $l drop)))
  assert_wat_matches("br_on_null", wat)
}

///|
async test "wat encoder matches wasm-tools for call_indirect" {
  let wat =
    #|(module (table 1 funcref) (func (export "call") (param i32 i32) (result i32) local.get 0 local.get 1 call_indirect (param i32) (result i32)))
  assert_wat_matches("call_indirect", wat)
}

///|
async test "wat encoder matches wasm-tools for call_indirect table list" {
  let wat =
    #|(module (type $t (func (param i32) (result i32))) (table $tab 1 funcref) (func $f (type $t) (param i32) (result i32) local.get 0) (elem (i32.const 0) $f) (func (export "call") (param i32 i32) (result i32) local.get 0 local.get 1 (call_indirect $tab (type $t))))
  assert_wat_matches("call_indirect_table_list", wat)
}

///|
async test "wat encoder matches wasm-tools for call_indirect table inline" {
  let wat =
    #|(module (table $tab 1 funcref) (func (export "call") (param i32 i32) (result i32) local.get 0 local.get 1 call_indirect $tab (param i32) (result i32)))
  assert_wat_matches("call_indirect_table_inline", wat)
}

///|
async test "wat encoder matches wasm-tools for call_indirect implicit typeuse" {
  let wat =
    #|(module
    #|  (type (func (param i32) (result i32)))
    #|  (table 1 funcref)
    #|  (func $f (param i32) (result i32) local.get 0)
    #|  (elem (i32.const 0) $f)
    #|  (func (export "call") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    call_indirect 0))
  assert_wat_matches("call_indirect_implicit_typeuse", wat)
}

///|
async test "wat encoder matches wasm-tools for return_call" {
  let wat =
    #|(module (func $f (result i32) i32.const 7) (func (export "call") (result i32) return_call $f))
  assert_wat_matches("return_call", wat)
}

///|
async test "wat encoder matches wasm-tools for return_call_indirect" {
  let wat =
    #|(module (type $t (func (param i32) (result i32))) (table $tab 1 funcref) (func $f (type $t) (param i32) (result i32) local.get 0) (elem (i32.const 0) $f) (func (export "call") (param i32) (result i32) local.get 0 i32.const 0 return_call_indirect $tab (type $t)))
  assert_wat_matches("return_call_indirect", wat)
}

///|
async test "wat encoder matches wasm-tools for return_call_indirect implicit typeuse" {
  let wat =
    #|(module
    #|  (type (func (param i32) (result i32)))
    #|  (table 1 funcref)
    #|  (func $f (param i32) (result i32) local.get 0)
    #|  (elem (i32.const 0) $f)
    #|  (func (export "call") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    return_call_indirect 0))
  assert_wat_matches("return_call_indirect_implicit_typeuse", wat)
}

///|
async test "wat encoder matches wasm-tools for return_call_indirect list" {
  let wat =
    #|(module (table $tab 1 funcref) (func (export "call") (param i32 i32) (result i32) local.get 0 local.get 1 (return_call_indirect $tab (param i32) (result i32))))
  assert_wat_matches("return_call_indirect_list", wat)
}

///|
async test "wat encoder matches wasm-tools for typeuse names" {
  let wat =
    #|(module (type $t (func (param i32) (result i32))) (table 1 funcref) (func (type $t) (param $x i32) (result i32) local.get $x) (func (export "call") (param i32 i32) (result i32) local.get 0 local.get 1 call_indirect (type $t)))
  assert_wat_matches("typeuse_names", wat)
}

///|
async test "wat encoder matches wasm-tools for table and ref ops" {
  let wat =
    #|(module (table 1 funcref) (elem (i32.const 0) 0) (func (export "table_ops") (param i32 funcref i32 i32 i32) (result i32) local.get 0 table.get drop local.get 0 local.get 1 table.set table.size drop local.get 2 local.get 1 table.grow drop local.get 3 local.get 4 local.get 0 table.init 0 local.get 3 local.get 4 local.get 0 table.copy elem.drop 0 ref.null func drop ref.func 0 drop i32.const 0))
  assert_wat_matches("table_ref_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for inline table elem" {
  let wat =
    #|(module (func $f) (table funcref (elem $f)))
  assert_wat_matches("inline_table_elem", wat)
}

///|
async test "wat encoder matches wasm-tools for inline table elem typed" {
  let wat =
    #|(module (func $f) (table (ref func) (elem $f)))
  assert_wat_matches("inline_table_elem_typed", wat)
}

///|
async test "wat encoder matches wasm-tools for inline table elem empty" {
  let wat =
    #|(module (table funcref (elem)))
  assert_wat_matches("inline_table_elem_empty", wat)
}

///|
async test "wat encoder matches wasm-tools for inline table elem exprs" {
  let wat =
    #|(module
    #|  (func $f)
    #|  (table funcref (elem (ref.null func) (ref.func $f))))
  assert_wat_matches("inline_table_elem_exprs", wat)
}

///|
async test "wat encoder matches wasm-tools for inline table elem items" {
  let wat =
    #|(module
    #|  (func $f)
    #|  (table funcref (elem (item (ref.func $f)) (ref.null func))))
  assert_wat_matches("inline_table_elem_items", wat)
}

///|
async test "wat encoder matches wasm-tools for table init expr" {
  let wat =
    #|(module (func $f (result i32) i32.const 0) (table 2 funcref (ref.func $f)))
  assert_wat_matches("table_init_expr", wat)
}

///|
async test "wat encoder matches wasm-tools for non-nullable table init" {
  let wat =
    #|(module (func $f) (table 1 (ref func) (ref.func $f)))
  assert_wat_matches("table_init_expr_nonnull", wat)
}

///|
async test "wat encoder matches wasm-tools for elem exprs active" {
  let wat =
    #|(module (table 2 funcref) (func $f (result i32) i32.const 0) (elem (i32.const 0) (ref null func) (ref.func $f) (ref.null func)))
  assert_wat_matches("elem_expr_active", wat)
}

///|
async test "wat encoder matches wasm-tools for elem exprs declarative" {
  let wat =
    #|(module (func $f (result i32) i32.const 0) (elem declare (ref null func) (ref.func $f) (ref.null func)))
  assert_wat_matches("elem_expr_decl", wat)
}

///|
async test "wat encoder matches wasm-tools for elem exprs reftype" {
  let wat =
    #|(module (table 1 externref) (elem (ref null extern) (ref.null extern)))
  assert_wat_matches("elem_expr_reftype", wat)
}

///|
async test "wat encoder matches wasm-tools for elem item exprs" {
  let wat =
    #|(module
    #|  (table 1 funcref)
    #|  (func $f)
    #|  (elem (i32.const 0) (ref null func) (item (ref.func $f)) (item (ref.null func))))
  assert_wat_matches("elem_item_exprs", wat)
}

///|
async test "wat encoder matches wasm-tools for data segments and memory.init" {
  let wat =
    #|(module (memory 1) (data $p "hi") (data (i32.const 0) "ok") (func (export "init") (param i32 i32 i32) local.get 0 local.get 1 local.get 2 memory.init $p data.drop $p))
  assert_wat_matches("data_memory_init", wat)
}

///|
async test "wat encoder matches wasm-tools for custom section end" {
  let wat =
    #|(module (@custom "foo" "a" "b"))
  assert_wat_matches_custom("custom_end", wat)
}

///|
async test "wat encoder matches wasm-tools for custom section after type" {
  let wat =
    #|(module (type (func)) (@custom "foo" (after type) "data") (func (type 0)))
  assert_wat_matches_custom("custom_after_type", wat)
}

///|
async test "wat encoder matches wasm-tools for custom section before code" {
  let wat =
    #|(module (memory 1) (data "hi") (@custom "foo" (before code) "data") (func (param i32 i32 i32) local.get 0 local.get 1 local.get 2 memory.init 0))
  assert_wat_matches_custom("custom_before_code", wat)
}

///|
async test "wat encoder matches wasm-tools for name section" {
  let wat =
    #|(module $m
    #|  (type $t (func (param i32) (result i32)))
    #|  (import "env" "f" (func $imp (type $t)))
    #|  (func $f (type $t) (param $x i32) (result i32) (local $y i32) local.get $x)
    #|  (table $tab 1 funcref)
    #|  (memory $mem 1)
    #|  (global $g i32 (i32.const 0))
    #|  (tag $tag (param i32))
    #|  (elem $e (i32.const 0) $f)
    #|  (data $d (i32.const 0) "hi")
    #|  (export "f" (func $f)))
  assert_wat_matches_with_names("name_section", wat)
}

///|
async test "wat encoder matches wasm-tools for label names" {
  let wat =
    #|(module
    #|  (func (export "labels") (param i32) (result i32)
    #|    (block $out (result i32)
    #|      (loop $loop
    #|        (if $if (result i32)
    #|          (then i32.const 1)
    #|          (else
    #|            (block $in
    #|              i32.const 2))))
    #|      i32.const 3)))
  assert_wat_matches_with_names("label_names", wat)
}

///|
async test "wat encoder matches wasm-tools for field names" {
  let wat =
    #|(module
    #|  (type (struct (field $x i32) (field (mut i64)) (field $z i32))))
  assert_wat_matches_with_names("field_names", wat)
}

///|
async test "wat encoder matches wasm-tools for rec type groups" {
  let wat =
    #|(module (rec (type $a (struct (field i32))) (type $b (struct (field (ref $a))))))
  assert_wat_matches("rec_type_group", wat)
}

///|
async test "wat encoder matches wasm-tools for rec single type" {
  let wat =
    #|(module (rec (type $a (struct (field i32)))))
  assert_wat_matches("rec_single_type", wat)
}

///|
async test "wat encoder matches wasm-tools for sub types" {
  let wat =
    #|(module (type $a (struct)) (type $b (sub $a (struct))) (type $c (sub final $a (struct))))
  assert_wat_matches("sub_types", wat)
}

///|
async test "wat encoder matches wasm-tools for sub types without supertypes" {
  let wat =
    #|(module (type $a (sub (struct))) (type $b (sub final (struct))))
  assert_wat_matches("sub_types_no_super", wat)
}

///|
async test "wat encoder matches wasm-tools for gc struct/array ops" {
  let wat =
    #|(module (type $s (struct (field i32) (field (mut i32)))) (type $sp (struct (field i8) (field (mut i16)))) (type $a16 (array (mut i16))) (type $a32 (array (mut i32))) (func (export "gc_ops") (param i32 i32 i32) (result i32) struct.new_default $s drop local.get 0 local.get 1 struct.new $s struct.get $s 0 drop local.get 0 local.get 1 struct.new $s local.get 2 struct.set $s 1 struct.new_default $sp struct.get_s $sp 0 drop struct.new_default $sp struct.get_u $sp 1 drop local.get 0 array.new_default $a16 array.len drop local.get 1 local.get 2 array.new_fixed $a16 2 drop local.get 1 local.get 0 array.new $a16 local.get 0 array.get_u $a16 drop local.get 1 local.get 0 array.new $a16 local.get 0 array.get_s $a16 drop local.get 1 local.get 0 array.new $a32 local.get 0 array.get $a32 drop local.get 1 local.get 0 array.new $a16 local.get 0 local.get 2 array.set $a16 local.get 1 local.get 0 array.new $a16 local.get 0 local.get 2 local.get 1 array.fill $a16 local.get 1 local.get 0 array.new $a16 local.get 0 local.get 1 local.get 0 array.new $a16 local.get 0 local.get 2 array.copy $a16 $a16 i32.const 0))
  assert_wat_matches("gc_struct_array_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for gc data/elem ops" {
  let wat =
    #|(module (type $a (array (mut i8))) (func $f (result i32) i32.const 0) (table $t 1 funcref) (elem $e (i32.const 0) $f) (data $d "hi") (func (export "gc_data") (param i32) (result i32) i32.const 0 local.get 0 array.new_data $a $d drop i32.const 0 local.get 0 array.new_elem $a $e drop local.get 0 array.new_default $a i32.const 0 i32.const 0 local.get 0 array.init_data $a $d local.get 0 array.new_default $a i32.const 0 i32.const 0 local.get 0 array.init_elem $a $e i32.const 0))
  assert_wat_matches("gc_data_elem_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for gc cast and i31 ops" {
  let wat =
    #|(module (type $s (struct (field i32))) (func (export "gc_casts") (param (ref null $s)) (result i32) (block (result (ref null $s)) local.get 0 br_on_cast 0 (ref $s) (ref null $s)) drop (block (result (ref null $s)) local.get 0 br_on_cast_fail 0 (ref $s) (ref null $s)) drop i32.const 7 ref.i31 i31.get_s drop i32.const 7 ref.i31 i31.get_u drop ref.null extern any.convert_extern drop ref.null any extern.convert_any drop i32.const 0))
  assert_wat_matches("gc_cast_i31_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for call_ref and return_call_ref" {
  let wat =
    #|(module (type $t (func (param i32) (result i32))) (table 1 funcref) (func $f (type $t) (param i32) (result i32) local.get 0) (elem (i32.const 0) $f) (func (export "call") (param i32) (result i32) local.get 0 ref.func $f call_ref $t) (func (export "tail") (param i32) (result i32) local.get 0 ref.func $f return_call_ref $t))
  assert_wat_matches("call_ref", wat)
}

///|
async test "wat encoder matches wasm-tools for ref types" {
  let wat =
    #|(module (type $t (func)) (func $f (type $t)) (table 1 (ref null $t)) (func (export "short") (param funcref externref anyref eqref i31ref structref arrayref exnref nullref nullfuncref nullexternref nullexnref)) (func (export "typed") (param (ref func) (ref extern) (ref any)) (result (ref $t) (ref null $t) (ref null func)) ref.func $f ref.null $t ref.null func))
  assert_wat_matches("ref_types", wat)
}

///|
async test "wat encoder matches wasm-tools for ref eq ops" {
  let wat =
    #|(module (func (export "eq") (param funcref funcref) (result i32) local.get 0 local.get 1 ref.eq) (func (export "asnn") (param funcref) (result funcref) local.get 0 ref.as_non_null))
  assert_wat_matches("ref_eq_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for ref.test and ref.cast" {
  let wat =
    #|(module (func (export "ref_test") (param anyref) (result i32) local.get 0 ref.test anyref) (func (export "ref_cast") (param anyref) (result anyref) local.get 0 ref.cast anyref))
  assert_wat_matches("ref_test_cast", wat)
}

///|
async test "wat encoder matches wasm-tools for block typeuse params" {
  let wat =
    #|(module (type $t (func (param i32 i64) (result i32))) (func (export "block_params") (param i32 i64) (result i32) local.get 0 local.get 1 (block (type $t) (param i32 i64) (result i32) drop drop i32.const 7)))
  assert_wat_matches("block_typeuse_params", wat)
}

///|
async test "wat encoder matches wasm-tools for multi-value blocks" {
  let wat =
    #|(module (func (export "multi") (result i64 i32) (block (result i64 i32) i64.const 1 i32.const 2)))
  assert_wat_matches("block_multi_value", wat)
}

///|
async test "wat encoder matches wasm-tools for typed select and ref.is_null" {
  let wat =
    #|(module (func (export "select_typed") (param i32 i32 i32) (result i32) local.get 0 local.get 1 local.get 2 select (result i32)) (func (export "ref_is_null") (param funcref) (result i32) local.get 0 ref.is_null))
  assert_wat_matches("select_ref_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for multi-name params and locals" {
  let wat =
    #|(module (func (export "sum") (param $x i32) (param $y i32) (result i32) local.get $x local.get $y i32.add) (func (export "locals") (param $x i32) (param $y i32) (result i32) (local $a i64) (local $b i64) local.get $x local.get $y i32.add drop local.get $a drop local.get $b drop i32.const 0))
  assert_wat_matches("multi_name_params", wat)
}

///|
async test "wat encoder matches wasm-tools for data offset list" {
  let wat =
    #|(module (memory (export "mem") 1) (data (offset (i32.const 0)) "hi") (data (memory 0) (offset (i32.const 4)) "ok"))
  assert_wat_matches("data_offset_list", wat)
}

///|
async test "wat encoder matches wasm-tools for data passive" {
  let wat =
    #|(module (memory 1) (data "hi") (func (export "init") (param i32 i32 i32) local.get 0 local.get 1 local.get 2 memory.init 0))
  assert_wat_matches("data_passive", wat)
}

///|
async test "wat encoder matches wasm-tools for elem offset list" {
  let wat =
    #|(module (table 1 funcref) (func $f) (elem (offset (i32.const 0)) func $f))
  assert_wat_matches("elem_offset_list", wat)
}

///|
async test "wat encoder matches wasm-tools for elem passive" {
  let wat =
    #|(module (func $f) (elem func $f))
  assert_wat_matches("elem_passive", wat)
}

///|
async test "wat encoder matches wasm-tools for table indexed ops" {
  let wat =
    #|(module (table $tab 2 funcref) (func $f) (elem (i32.const 0) $f) (func (export "ops") (param i32 funcref i32) (result i32) local.get 0 table.get $tab drop local.get 0 local.get 1 table.set $tab table.size $tab drop local.get 2 local.get 1 table.grow $tab drop i32.const 0))
  assert_wat_matches("table_indexed_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for table init/copy indexed" {
  let wat =
    #|(module (table $dst 2 funcref) (table $src 2 funcref) (func $f) (elem $e func $f) (func (export "init") (param i32 i32 i32) local.get 0 local.get 1 local.get 2 table.init $dst $e) (func (export "copy") (param i32 i32 i32) local.get 0 local.get 1 local.get 2 table.copy $dst $src))
  assert_wat_matches("table_init_copy_indexed", wat)
}

///|
async test "wat encoder matches wasm-tools for table.fill" {
  let wat =
    #|(module (table $t 4 funcref) (func (export "fill") (param i32 funcref i32) local.get 0 local.get 1 local.get 2 table.fill $t))
  assert_wat_matches("table_fill", wat)
}

///|
async test "wat encoder matches wasm-tools for memory indexed ops" {
  let wat =
    #|(module (memory 1) (data $d "hi") (data "ok") (func (export "bulk") (param i32 i32 i32) local.get 0 local.get 1 local.get 2 memory.init $d local.get 0 local.get 1 local.get 2 memory.copy 0 0 local.get 0 local.get 1 local.get 2 memory.fill 0) (func (export "size") (result i32) memory.size 0) (func (export "grow") (param i32) (result i32) local.get 0 memory.grow 0))
  assert_wat_matches("memory_indexed_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for list form table/memory ops" {
  let wat =
    #|(module (memory 1) (table $tab 1 funcref) (func (export "list_ops") (param i32 funcref i32) (result i32) local.get 0 (table.get $tab) drop local.get 0 local.get 1 (table.set $tab) (table.size $tab) drop local.get 1 local.get 2 (table.grow $tab) drop (memory.size 0) drop local.get 2 (memory.grow 0) drop i32.const 0))
  assert_wat_matches("list_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for elem table index 1" {
  let wat =
    #|(module (table 1 funcref) (table $tab1 1 funcref) (func $f) (elem (table $tab1) (offset (i32.const 0)) func $f))
  assert_wat_matches("elem_table_idx", wat)
}

///|
async test "wat encoder matches wasm-tools for br_table labels" {
  let wat =
    #|(module (func (export "brs") (param i32) (result i32) (block $out (block $in local.get 0 br_table $in $out)) i32.const 7))
  assert_wat_matches("br_table_labels", wat)
}

///|
async test "wat encoder matches wasm-tools for tag import and throw" {
  let wat =
    #|(module (type $t (func (param i32))) (import "env" "e" (tag $e (type $t))) (func (export "throw") (param i32) local.get 0 throw $e))
  assert_wat_matches("tag_import_throw", wat)
}

///|
async test "wat encoder matches wasm-tools for try_table" {
  let wat =
    #|(module (type $t (func (param i32))) (tag $e (export "e") (type $t)) (func (export "try") (param i32) (result i32) (block $out (result i32) (try_table (result i32) (catch $e $out) local.get 0 throw $e i32.const 7))))
  assert_wat_matches("try_table", wat)
}

///|
async test "wat encoder matches wasm-tools for simd ops" {
  let wat =
    #|(module (memory 1) (func (export "simd") (param i32) (result i32) (local v128) v128.const i8x16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 local.set 1 local.get 0 v128.load local.get 1 i8x16.shuffle 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 local.set 1 local.get 1 local.get 1 i16x8.add drop local.get 1 i32x4.extract_lane 2 drop i32.const 0))
  assert_wat_matches("simd_ops", wat)
}

///|
async test "wat encoder matches wasm-tools for atomic ops" {
  let wat =
    #|(module (memory 1) (func (export "atomic") (param i32 i32 i64) (result i32) atomic.fence local.get 0 i32.atomic.load drop local.get 0 local.get 1 i32.atomic.store local.get 0 local.get 1 i32.atomic.rmw.add drop local.get 0 local.get 1 local.get 1 i32.atomic.rmw.cmpxchg drop local.get 0 local.get 1 memory.atomic.notify drop local.get 0 local.get 1 local.get 2 memory.atomic.wait32 drop local.get 0 i64.atomic.load drop local.get 0 local.get 2 i64.atomic.store local.get 0 i64.const 0 local.get 2 memory.atomic.wait64 drop i32.const 0))
  assert_wat_matches("atomic_ops", wat)
}

///|
test "wast parser exposes script commands" {
  let wast =
    #|(script
    #|  (module (func (export "f") (result i32) i32.const 1))
    #|  (register "m")
    #|  (assert_return (invoke "f") (i32.const 1)))
  let commands = wast_to_script(wast)
  assert_eq(commands.length(), 3)
  match commands[0] {
    Module(_) => ()
    _ => abort("expected module command")
  }
  match commands[1] {
    Raw(List(items)) =>
      match items[0] {
        Atom(tag) => assert_eq(tag, b"register")
        _ => abort("expected register atom")
      }
    _ => abort("expected register command")
  }
  match commands[2] {
    Raw(List(items)) =>
      match items[0] {
        Atom(tag) => assert_eq(tag, b"assert_return")
        _ => abort("expected assert_return atom")
      }
    _ => abort("expected assert_return command")
  }
}

///|
async test "wast parser extracts modules from script" {
  let wast =
    #|(script
    #|  (module binary "\00asm\01\00\00\00")
    #|  (module quote "(func (export \"a\") (result i32) i32.const 1)")
    #|  (module (func (export "b") (result i32) i32.const 2))
    #|  (assert_return (invoke "b") (i32.const 2)))
  let wasms = wast_to_wasm(wast)
  assert_eq(wasms.length(), 3)
  let binary_wat =
    #|(module)
  assert_wasm_matches_wat("wast_binary", binary_wat, wasms[0])
  let quote_wat =
    #|(module (func (export "a") (result i32) i32.const 1))
  assert_wasm_matches_wat("wast_quote", quote_wat, wasms[1])
  let text_wat =
    #|(module (func (export "b") (result i32) i32.const 2))
  assert_wasm_matches_wat("wast_text", text_wat, wasms[2])
}

///|
async test "wast parser extracts modules from asserts" {
  let wast =
    #|(assert_invalid (module (func)) "msg")
  let wasms = wast_to_wasm(wast)
  assert_eq(wasms.length(), 1)
  let wat =
    #|(module (func))
  assert_wasm_matches_wat("wast_assert_module", wat, wasms[0])
}
