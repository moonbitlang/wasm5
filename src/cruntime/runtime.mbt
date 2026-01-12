///|
/// Runtime for C-based threaded code execution.
pub struct CRuntime {
  module_ : @core.Module
  compiled : CompiledModule
  globals : FixedArray[UInt64] // Global variables
  // TODO: memory, tables
}

// Import Value type from core

///|
using @core {type Value}

///|
/// Convert TrapCode to RuntimeError using the error detail string approach
fn trap_to_error(trap : TrapCode) -> @runtime.RuntimeError {
  let detail = match trap {
    None => "unreachable" // Should not happen
    Unreachable => "unreachable"
    DivisionByZero => "division by zero"
    IntegerOverflow => "integer overflow"
    InvalidConversionToInteger => "integer overflow"
    OutOfBoundsMemoryAccess => "out of bounds memory access"
    OutOfBoundsTableAccess => "out of bounds table access"
    IndirectCallTypeMismatch => "indirect call type mismatch"
    NullFunctionReference => "null function reference"
    StackOverflow => "stack overflow"
  }
  @runtime.RuntimeError::from_detail(detail)
}

///|
/// Load a module and compile it for C runtime execution.
pub fn CRuntime::load(module_ : @core.Module) -> CRuntime {
  let compiled = compile(module_)
  // Initialize globals from module
  let globals = init_globals(module_)
  { module_, compiled, globals }
}

///|
/// Initialize globals from module's global section
fn init_globals(module_ : @core.Module) -> FixedArray[UInt64] {
  let num_globals = module_.globals.length()
  let globals = FixedArray::make(
    if num_globals > 0 {
      num_globals
    } else {
      1
    },
    0UL,
  )
  for i, g in module_.globals {
    // Evaluate init expression (assuming simple constant for now)
    let value = eval_const_expr(g.init)
    globals[i] = value
  }
  globals
}

///|
/// Evaluate a constant expression to get initial value
fn eval_const_expr(expr : @core.Expr) -> UInt64 {
  for instr in expr.instrs {
    match instr {
      I32Const(n) => return n.to_uint64()
      I64Const(n) => return n
      F32Const(f) => return f.reinterpret_as_uint().to_uint64()
      F64Const(f) => return f.reinterpret_as_uint64()
      GlobalGet(_) => return 0UL // TODO: handle global references
      RefNull(_) => return 0xFFFFFFFF_FFFFFFFFUL
      RefFunc(_) => return 0UL // TODO: handle func refs
      _ => continue
    }
  }
  0UL
}

///|
/// Run the start function if present.
pub fn CRuntime::run_start(self : CRuntime) -> Unit raise @runtime.RuntimeError {
  match self.module_.start {
    Some(start_idx) => {
      let num_imported = count_imported_funcs(self.module_)
      let local_idx = start_idx.reinterpret_as_int() - num_imported
      if local_idx >= 0 && local_idx < self.compiled.func_entries.length() {
        let entry = self.compiled.func_entries[local_idx]
        let num_locals = self.compiled.func_num_locals[local_idx]
        let result_out : FixedArray[UInt64] = [0]
        let trap_code = c_execute_ffi(
          self.compiled.code,
          entry,
          num_locals,
          [],
          0,
          result_out,
          0, // start function has no results
          self.globals,
        )
        let trap = trap_code_from_int(trap_code)
        if trap != TrapCode::None {
          raise trap_to_error(trap)
        }
      }
    }
    None => ()
  }
}

///|
/// Call an exported function by name.
pub fn CRuntime::call_compiled(
  self : CRuntime,
  name : Bytes,
  args : Array[Value],
) -> Array[Value] raise @runtime.RuntimeError {
  let name_str = @encoding/utf8.decode(name) catch { _ => return [] }
  match self.compiled.exports.get(name_str) {
    Some(func_idx) => {
      // Get function type for result conversion
      let num_imported = count_imported_funcs(self.module_)
      let abs_idx = num_imported + func_idx
      let type_idx = self.module_.funcs[abs_idx].reinterpret_as_int()
      let func_type = get_func_type(self.module_, type_idx)
      let num_results = func_type.results.length()

      // Convert args to UInt64
      let args_u64 : Array[UInt64] = []
      for arg in args {
        args_u64.push(value_to_u64(arg))
      }
      let entry = self.compiled.func_entries[func_idx]
      let num_locals = self.compiled.func_num_locals[func_idx]
      let args_fixed = FixedArray::from_array(args_u64)
      // Allocate result array with correct size (at least 1 to avoid empty array issues)
      let result_out : FixedArray[UInt64] = FixedArray::make(
        if num_results > 0 {
          num_results
        } else {
          1
        },
        0UL,
      )
      let trap_code = c_execute_ffi(
        self.compiled.code,
        entry,
        num_locals,
        args_fixed,
        args_u64.length(),
        result_out,
        num_results,
        self.globals,
      )

      // Check for trap
      let trap = trap_code_from_int(trap_code)
      if trap != TrapCode::None {
        raise trap_to_error(trap)
      }

      // Convert all results based on function type
      let results : Array[Value] = []
      for i in 0..<num_results {
        results.push(u64_to_value(result_out[i], func_type.results[i]))
      }
      results
    }
    None => []
  }
}

///|
fn value_to_u64(v : Value) -> UInt64 {
  match v {
    I32(n) => n.to_uint64()
    I64(n) => n
    F32(f) => f.reinterpret_as_uint().to_uint64()
    F64(f) => f.reinterpret_as_uint64()
    Ref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Ref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Funcref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Funcref(None) => 0xFFFFFFFF_FFFFFFFFUL
    Externref(Some(n)) => n.reinterpret_as_uint().to_uint64()
    Externref(None) => 0xFFFFFFFF_FFFFFFFFUL
  }
}

///|
fn u64_to_value(raw : UInt64, ty : @core.ValType) -> Value {
  match ty {
    I32 => Value::I32(raw.to_uint())
    I64 => Value::I64(raw)
    F32 => Value::F32(Float::reinterpret_from_uint(raw.to_uint()))
    F64 => Value::F64(raw.reinterpret_as_double())
    FuncRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Funcref(None)
      } else {
        Value::Funcref(Some(raw.to_uint().reinterpret_as_int()))
      }
    ExternRef =>
      if raw == 0xFFFFFFFF_FFFFFFFFUL {
        Value::Externref(None)
      } else {
        Value::Externref(Some(raw.to_uint().reinterpret_as_int()))
      }
    _ => Value::I64(raw)
  }
}
