///|
async test "runtime parse imported wasm file with host side effects" {
  let file = @fs.open("test/simple/import_side_effect.wasm", mode=ReadOnly)
  defer file.close()
  let bytes = file.read_all().binary()
  let module_ = @parse.parse(bytes)
  let resolver = ImportResolver::new()
  let calls : Array[UInt] = []
  resolver.add_func(
    b"host",
    b"log",
    ImportedFunc::new(1U, fn(args) {
      if args.length() == 1 {
        match args[0] {
          Value::I32(v) => calls.push(v)
          _ => ()
        }
      }
      []
    }),
  )
  resolver.add_global(b"host", b"g", Value::I32(42U))
  let rt = Runtime::load_with_resolver(module_, resolver)
  rt.compile()
  let results = rt.call_compiled(b"run", [])
  assert_eq(results.length(), 0)
  assert_eq(calls, [42U])
}
