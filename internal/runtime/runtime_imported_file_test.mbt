///|
async test "runtime parse imported wasm file with host side effects" {
  let file = @fs.open("test/simple/import_side_effect.wasm", mode=ReadOnly)
  defer file.close()
  let bytes = file.read_all().binary()
  let module_ = @parse.parse(bytes)
  let resolver = @runtime.Imports::new()
  let calls : Array[UInt32] = []
  resolver.add_func(
    b"host",
    b"log",
    @runtime.HostFunc::new(
      fn(args) {
        if args.length() == 1 {
          match args[0] {
            @runtime.Value::I32(v) => calls.push(v)
            _ => ()
          }
        }
        []
      },
      arity=1U,
    ),
  )
  resolver.add_global(b"host", b"g", @runtime.Value::I32(42U))
  let rt = @runtime.Instance::new(module_, resolver)
  rt.run_start()
  let results = rt.call_compiled(b"run", [])
  assert_eq(results.length(), 0)
  @debug.assert_eq(calls, [42U])
}
