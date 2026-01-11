///|
/// Execute threaded code
/// code: pointer to code array
/// entry: index into code where function starts
/// num_locals: number of locals (including params)
/// args: pointer to arguments array
/// num_args: number of arguments
#borrow(code, args)
extern "C" fn c_execute(
  code : FixedArray[UInt64],
  entry : Int,
  num_locals : Int,
  args : FixedArray[UInt64],
  num_args : Int,
) -> UInt64 = "execute"

///|
/// Call a compiled function by index
pub fn call(
  compiled : CompiledModule,
  func_idx : Int,
  args : Array[UInt64],
) -> UInt64 {
  let entry = compiled.func_entries[func_idx]
  let num_locals = compiled.func_num_locals[func_idx]
  let args_fixed = FixedArray::from_array(args)
  c_execute(compiled.code, entry, num_locals, args_fixed, args.length())
}

///|
/// Call a compiled function with no arguments
pub fn call0(compiled : CompiledModule, func_idx : Int) -> UInt64 {
  let entry = compiled.func_entries[func_idx]
  let num_locals = compiled.func_num_locals[func_idx]
  c_execute(compiled.code, entry, num_locals, [], 0)
}

///|
/// Call a compiled function with one i32 argument
pub fn call1_i32(
  compiled : CompiledModule,
  func_idx : Int,
  arg : Int,
) -> UInt64 {
  let entry = compiled.func_entries[func_idx]
  let num_locals = compiled.func_num_locals[func_idx]
  let args : FixedArray[UInt64] = [arg.reinterpret_as_uint().to_uint64()]
  c_execute(compiled.code, entry, num_locals, args, 1)
}

///|
/// Call a compiled function with two i32 arguments
pub fn call2_i32(
  compiled : CompiledModule,
  func_idx : Int,
  arg1 : Int,
  arg2 : Int,
) -> UInt64 {
  let entry = compiled.func_entries[func_idx]
  let num_locals = compiled.func_num_locals[func_idx]
  let args : FixedArray[UInt64] = [
    arg1.reinterpret_as_uint().to_uint64(),
    arg2.reinterpret_as_uint().to_uint64(),
  ]
  c_execute(compiled.code, entry, num_locals, args, 2)
}
