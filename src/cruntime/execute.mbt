///|
/// Execute threaded code (FFI binding)
/// Returns trap code (0 = success), stores result in result_out[0]
#borrow(code, args, result_out)
extern "C" fn c_execute_ffi(
  code : FixedArray[UInt64],
  entry : Int,
  num_locals : Int,
  args : FixedArray[UInt64],
  num_args : Int,
  result_out : FixedArray[UInt64],
) -> Int = "execute"

///|
/// Convert trap code integer to TrapCode enum
fn trap_code_from_int(code : Int) -> TrapCode {
  match code {
    0 => TrapCode::None
    1 => TrapCode::Unreachable
    2 => TrapCode::DivisionByZero
    3 => TrapCode::IntegerOverflow
    4 => TrapCode::InvalidConversionToInteger
    5 => TrapCode::OutOfBoundsMemoryAccess
    6 => TrapCode::OutOfBoundsTableAccess
    7 => TrapCode::IndirectCallTypeMismatch
    8 => TrapCode::NullFunctionReference
    9 => TrapCode::StackOverflow
    _ => TrapCode::Unreachable // Unknown trap code
  }
}
