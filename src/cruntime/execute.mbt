///|
/// Execute threaded code (FFI binding)
#borrow(code, args)
extern "C" fn c_execute_ffi(
  code : FixedArray[UInt64],
  entry : Int,
  num_locals : Int,
  args : FixedArray[UInt64],
  num_args : Int,
) -> UInt64 = "execute"
