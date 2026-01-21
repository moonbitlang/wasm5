///|
let spectest_output : Array[String] = []

///|
fn push_output(s : String) -> Unit {
  spectest_output.push(s)
}

///|
pub fn get_spectest_output() -> Array[String] {
  spectest_output
}

///|
pub fn clear_spectest_output() -> Unit {
  spectest_output.clear()
}

///|
fn spectest_print(args : Array[Value]) -> Array[Value] {
  guard args is []
  []
}

///|
fn spectest_print_i32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [I32(v)]
  push_output("\{v.reinterpret_as_int()} : i32")
  []
}

///|
fn spectest_print_i64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [I64(v)]
  push_output("\{v.reinterpret_as_int64()} : i64")
  []
}

///|
fn spectest_print_f32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [F32(v)]
  push_output("\{v} : f32")
  []
}

///|
fn spectest_print_f64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [F64(v)]
  push_output("\{v} : f64")
  []
}

///|
fn spectest_print_i32_f32(args : Array[Value]) -> Array[Value] {
  guard args.length() == 2
  guard args is [I32(iv), F32(fv)]
  push_output("\{iv.reinterpret_as_int()} : i32, \{fv} : f32")
  []
}

///|
fn spectest_print_f64_f64(args : Array[Value]) -> Array[Value] {
  guard args.length() == 2
  guard args is [F64(fv1), F64(fv2)]
  push_output("\{fv1} : f64, \{fv2} : f64")
  []
}

///|
fn spectest_print_char(args : Array[Value]) -> Array[Value] {
  guard args.length() == 1
  guard args is [I32(v)]
  let c = v.reinterpret_as_int().unsafe_to_char()
  push_output("\{c}")
  []
}
