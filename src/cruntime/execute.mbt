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
/// Call a compiled function by export name.
/// This is the only public invocation API.
/// Returns the function result, or None if export not found.
pub fn call(
  compiled : CompiledModule,
  export_name : String,
  args : Array[UInt64],
) -> UInt64? {
  match compiled.exports.get(export_name) {
    Some(func_idx) => {
      let entry = compiled.func_entries[func_idx]
      let num_locals = compiled.func_num_locals[func_idx]
      let args_fixed = FixedArray::from_array(args)
      Some(
        c_execute(compiled.code, entry, num_locals, args_fixed, args.length()),
      )
    }
    None => None
  }
}
