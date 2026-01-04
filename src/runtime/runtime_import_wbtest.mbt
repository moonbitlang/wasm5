///|
test "import resolver add/get and module access" {
  let resolver = ImportResolver::new()
  match resolver.get_func(b"missing", b"f") {
    None => ()
    _ => abort("expected no func")
  }
  assert_eq(resolver.get_global(b"missing", b"g"), None)
  match resolver.get_table(b"missing", b"t") {
    None => ()
    _ => abort("expected no table")
  }
  match resolver.get_memory(b"missing", b"mem") {
    None => ()
    _ => abort("expected no memory")
  }
  let func = ImportedFunc::new(0U, fn(_args) { [] })
  resolver.add_func(b"m", b"f", func)
  resolver.add_global(b"m", b"g", Value::I32(1U))
  resolver.add_global(b"m", b"g2", Value::I64(2UL))
  let table = RuntimeTable::{ data: [0xFFFFFFFFFFFFFFFFUL, 0xFFFFFFFFFFFFFFFFUL], max: Some(2UL), external_funcrefs: [] }
  resolver.add_table(b"m", b"t", table)
  resolver.add_table(b"m", b"t2", table)
  let mem = ImportedMemory::{ data: Array::make(4, b'\x00'), max: None }
  resolver.add_memory(b"m", b"mem", mem)
  resolver.add_memory(b"m", b"mem2", mem)
  match resolver.get_func(b"m", b"f") {
    Some(f) => assert_eq(f.arity, 0U)
    None => abort("missing imported func")
  }
  match resolver.get_global(b"m", b"g") {
    Some(Value::I32(v)) => assert_eq(v, 1U)
    _ => abort("missing imported global")
  }
  match resolver.get_table(b"m", b"t") {
    Some(t) => assert_eq(t.data.length(), 2)
    None => abort("missing imported table")
  }
  match resolver.get_memory(b"m", b"mem") {
    Some(m) => assert_eq(m.data.length(), 4)
    None => abort("missing imported memory")
  }
  let rt = make_runtime([], [], 0)
  assert_eq(rt.get_module().funcs.length(), 0)
}

///|
test "spectest print helpers" {
  assert_eq(spectest_print([]), [])
  assert_eq(spectest_print_i32([Value::I32(12U)]), [])
  assert_eq(spectest_print_i64([Value::I64(24UL)]), [])
  assert_eq(spectest_print_f32([Value::F32(1.5)]), [])
  assert_eq(spectest_print_f64([Value::F64(2.5)]), [])
  assert_eq(spectest_print_i32_f32([Value::I32(3U), Value::F32(4.0)]), [])
  assert_eq(spectest_print_f64_f64([Value::F64(5.0), Value::F64(6.0)]), [])
  assert_eq(spectest_print_char([Value::I32(65U)]), [])
}
