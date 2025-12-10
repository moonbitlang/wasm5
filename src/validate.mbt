// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Convert RefType to ValType
fn reftype_to_valtype(ref_type : RefType) -> ValType {
  match ref_type {
    RefType::Func => ValType::FuncRef
    RefType::Extern => ValType::ExternRef
    RefType::Any => ValType::AnyRef
    RefType::Eq => ValType::EqRef
    RefType::I31 => ValType::I31Ref
    RefType::Struct => ValType::StructRef
    RefType::Array => ValType::ArrayRef
    RefType::Exn => ValType::ExnRef
    RefType::None => ValType::NullRef
    RefType::NoFunc => ValType::NullFuncRef
    RefType::NoExtern => ValType::NullExternRef
    RefType::NoExn => ValType::NullExnRef
    RefType::TypeIndex(_) => ValType::FuncRef // Treat typed references as funcref for now
  }
}

///|
/// Validate alignment - alignment must not be larger than natural alignment
/// align parameter is stored as log2(alignment), natural is in bytes
fn validate_alignment(align : UInt, natural : Int) -> Unit raise ValidationError {
  // align is log2 of alignment (e.g., align=2 means 2^2 = 4 byte alignment)
  // natural is the natural alignment in bytes
  let align_int = align.reinterpret_as_int()
  let max_align = match natural {
    1 => 0 // 2^0 = 1
    2 => 1 // 2^1 = 2
    4 => 2 // 2^2 = 4
    8 => 3 // 2^3 = 8
    _ => {
      // Calculate log2 of natural alignment
      let mut n = natural
      let mut log = 0
      while n > 1 {
        n = n / 2
        log = log + 1
      }
      log
    }
  }
  if align_int > max_align {
    raise ValidationError::InvalidAlignment(
      "alignment must not be larger than natural (align=\{align_int}, max=\{max_align})",
    )
  }
}

///|
/// Check if t1 is a subtype of t2 (t1 <: t2)
/// WebAssembly GC type hierarchy:
/// - NullRef (none) <: all nullable reference types
/// - NullFuncRef (nofunc) <: FuncRef
/// - NullExternRef (noextern) <: ExternRef
/// - NullExnRef (noexn) <: ExnRef
/// - I31Ref, StructRef, ArrayRef <: EqRef <: AnyRef
/// - FuncRef <: AnyRef (in some proposals)
fn is_subtype(t1 : ValType, t2 : ValType) -> Bool {
  // Reflexive: every type is a subtype of itself
  if t1 == t2 {
    return true
  }

  match (t1, t2) {
    // Bottom types (null) are subtypes of their corresponding reference types
    (NullRef, AnyRef) | (NullRef, EqRef) | (NullRef, I31Ref) |
    (NullRef, StructRef) | (NullRef, ArrayRef) => true

    (NullFuncRef, FuncRef) => true
    (NullExternRef, ExternRef) => true
    (NullExnRef, ExnRef) => true

    // Reference type hierarchy
    (I31Ref, EqRef) | (I31Ref, AnyRef) => true
    (StructRef, EqRef) | (StructRef, AnyRef) => true
    (ArrayRef, EqRef) | (ArrayRef, AnyRef) => true
    (EqRef, AnyRef) => true

    // Some proposals allow funcref <: anyref
    (FuncRef, AnyRef) => true
    (ExnRef, AnyRef) => true

    // Non-reference types are not related by subtyping
    _ => false
  }
}

///|
/// Validate a WebAssembly module
fn validate_module(m : Module) -> Unit raise ValidationError {
  // Validate function type indices
  for i = 0; i < m.funcs.length(); i = i + 1 {
    let type_idx = m.funcs[i].reinterpret_as_int()
    if type_idx < 0 || type_idx >= m.types.length() {
      raise ValidationError::InvalidTypeIndex(type_idx)
    }
  }

  // Validate start function if present
  match m.start {
    Some(start_idx) => {
      let func_idx = start_idx.reinterpret_as_int()

      // Count total functions (imported + local)
      let mut num_imported_funcs = 0
      for imp in m.imports {
        match imp.desc {
          ImportDesc::Func(_) => num_imported_funcs += 1
          _ => ()
        }
      }
      let total_funcs = num_imported_funcs + m.funcs.length()

      // Check if function index is valid
      if func_idx < 0 || func_idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(func_idx)
      }

      // Get the function type
      let type_idx = if func_idx < num_imported_funcs {
        // Imported function
        let mut current_import = 0
        let mut found_type_idx = 0
        for imp in m.imports {
          match imp.desc {
            ImportDesc::Func(tidx) => {
              if current_import == func_idx {
                found_type_idx = tidx.reinterpret_as_int()
                break
              }
              current_import += 1
            }
            _ => ()
          }
        }
        found_type_idx
      } else {
        // Local function
        m.funcs[func_idx - num_imported_funcs].reinterpret_as_int()
      }

      let func_type = m.types[type_idx]

      // Start function must have type [] -> []
      if func_type.params.length() > 0 {
        raise ValidationError::InvalidStartFunction(
          "start function must have no parameters",
        )
      }
      if func_type.results.length() > 0 {
        raise ValidationError::InvalidStartFunction(
          "start function must have no results",
        )
      }
    }
    None => ()
  }

  // Validate memory limits
  for mem in m.mems {
    match mem.limits.max {
      Some(max_val) => {
        let min = mem.limits.min.reinterpret_as_int()
        let max = max_val.reinterpret_as_int()
        if min > max {
          raise ValidationError::InvalidMemorySize(
            "size minimum must not be greater than maximum",
          )
        }
        if max_val > 65536 {
          raise ValidationError::InvalidMemorySize("memory size must be at most 65536 pages (4GiB)")
        }
      }
      None => {
        if mem.limits.min > 65536 {
          raise ValidationError::InvalidMemorySize("memory size must be at most 65536 pages (4GiB)")
        }
      }
    }
  }

  // Validate memory limits for imported memories
  for imp in m.imports {
    match imp.desc {
      ImportDesc::Mem(mem_type) => {
        match mem_type.limits.max {
          Some(max_val) => {
            let min = mem_type.limits.min.reinterpret_as_int()
            let max = max_val.reinterpret_as_int()
            if min > max {
              raise ValidationError::InvalidMemorySize(
                "size minimum must not be greater than maximum",
              )
            }
            if max_val > 65536 {
              raise ValidationError::InvalidMemorySize("memory size must be at most 65536 pages (4GiB)")
            }
          }
          None => {
            if mem_type.limits.min > 65536 {
              raise ValidationError::InvalidMemorySize("memory size must be at most 65536 pages (4GiB)")
            }
          }
        }
      }
      _ => ()
    }
  }

  // Validate function bodies against their types
  for i = 0; i < m.codes.length(); i = i + 1 {
    let type_idx = m.funcs[i].reinterpret_as_int()
    let func_type = m.types[type_idx]
    let code = m.codes[i]

    // Validate the function body
    validate_function(m, func_type, code)
  }
}

///|
/// Get the function type signature for a block type
fn get_block_type(
  module_ : Module,
  block_type : BlockType,
) -> (Array[ValType], Array[ValType]) raise ValidationError {
  match block_type {
    Empty => ([], [])
    Value(t) => ([], [t])
    TypeIndex(idx) => {
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
}

///|
/// Validation context that tracks both the type stack and unreachable state
struct ValidationCtx {
  stack : Array[ValType]
  mut is_unreachable : Bool
  mut unreachable_stack_height : Int // Stack height when entering unreachable mode
  // Stack of control frames - each frame tracks the expected result types
  // For br validation, we need to know what types the target label expects
  control_stack : Array[(Array[ValType], Array[ValType])] // (params, results) for each control frame
}

///|
fn ValidationCtx::new() -> ValidationCtx {
  { stack: [], is_unreachable: false, unreachable_stack_height: 0, control_stack: [] }
}

///|
fn ValidationCtx::push_control(
  self : ValidationCtx,
  params : Array[ValType],
  results : Array[ValType],
) -> Unit {
  self.control_stack.push((params, results))
}

///|
fn ValidationCtx::pop_control(
  self : ValidationCtx,
) -> (Array[ValType], Array[ValType]) {
  self.control_stack.unsafe_pop()
}

///|
fn ValidationCtx::get_label_types(
  self : ValidationCtx,
  label : UInt,
) -> Array[ValType] raise ValidationError {
  // Labels are relative depth: 0 is innermost, 1 is next outer, etc.
  let idx = self.control_stack.length() - 1 - label.reinterpret_as_int()
  if idx >= 0 && idx < self.control_stack.length() {
    let (_, results) = self.control_stack[idx]
    results
  } else {
    raise ValidationError::UnknownLabel(label.reinterpret_as_int())
  }
}

// =============================================================================
// Polymorphic Stack Operations for Unreachable Code
// =============================================================================
//
// In WebAssembly, after an unconditional control flow instruction (br, return,
// unreachable), subsequent code is "unreachable" and uses polymorphic stack
// validation rules. This means:
//
//   1. Operations can "pop" values that don't exist on the stack
//   2. The stack is treated as having any types needed
//   3. Result types are still pushed for type checking of code after
//      control flow rejoins (e.g., after a block end)
//
// Example: (block (drop (i32.ctz (br 0))))
//   - br 0 branches away, making i32.ctz unreachable
//   - i32.ctz normally requires an i32 on stack, but in unreachable mode
//     it's valid even with an empty stack
//
// These helpers implement polymorphic pop operations that succeed in
// unreachable mode even when the stack is empty.
// =============================================================================

///|
/// Pop a value from the stack, allowing empty stack in unreachable mode.
/// Returns the type if available, or the expected type if unreachable.
/// Only values below unreachable_stack_height are polymorphic.
fn ValidationCtx::poly_pop(
  self : ValidationCtx,
  expected : ValType,
) -> ValType raise ValidationError {
  if self.stack.length() > 0 {
    self.stack.unsafe_pop()
  } else if self.is_unreachable {
    // In unreachable code with empty stack, this is a polymorphic pop
    // (popping from below the unreachable boundary)
    expected
  } else {
    raise ValidationError::TypeMismatch(
      "expected value on stack, got empty stack",
    )
  }
}

///|
/// Check and pop a value of a specific type, allowing polymorphic behavior.
/// Concrete values (pushed after unreachable) must still type-check.
fn ValidationCtx::poly_pop_expect(
  self : ValidationCtx,
  expected : ValType,
  op_name : String,
) -> Unit raise ValidationError {
  // In unreachable mode, concrete values are those currently on the stack
  // (they were pushed after unreachable). Polymorphic values are those
  // we pop from an empty stack (they would have been there before unreachable).
  let is_concrete_value = self.stack.length() > 0

  let actual = self.poly_pop(expected)

  // Type-check concrete values, or all values if not in unreachable mode
  if (not(self.is_unreachable) || is_concrete_value) && actual != expected {
    raise ValidationError::TypeMismatch(
      "\{op_name} requires \{expected}, got \{actual}",
    )
  }
}

///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module_ : Module,
  func_type : FuncType,
  code : Code,
  ctx : ValidationCtx,
  instr : Instr,
) -> Unit raise ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    I32Const(_) => stack.push(I32)
    I64Const(_) => stack.push(I64)
    F32Const(_) => stack.push(F32)
    F64Const(_) => stack.push(F64)

    // Binary operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr => {
      ctx.poly_pop_expect(I32, "i32 binary op")
      ctx.poly_pop_expect(I32, "i32 binary op")
      stack.push(I32)
    }

    // Comparison operations
    I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU => {
      ctx.poly_pop_expect(I32, "i32 comparison")
      ctx.poly_pop_expect(I32, "i32 comparison")
      stack.push(I32)
    }

    // Unary operations
    I32Eqz | I32Clz | I32Ctz | I32Popcnt | I32Extend8S | I32Extend16S => {
      ctx.poly_pop_expect(I32, "i32 unary op")
      stack.push(I32)
    }

    // i64 binary operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr => {
      ctx.poly_pop_expect(I64, "i64 binary op")
      ctx.poly_pop_expect(I64, "i64 binary op")
      stack.push(I64)
    }

    // i64 comparison operations
    I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU => {
      ctx.poly_pop_expect(I64, "i64 comparison")
      ctx.poly_pop_expect(I64, "i64 comparison")
      stack.push(I32)
    }

    // i64 test operation (returns i32)
    I64Eqz => {
      ctx.poly_pop_expect(I64, "i64.eqz")
      stack.push(I32)
    }

    // i64 unary operations (return i64)
    I64Clz | I64Ctz | I64Popcnt | I64Extend8S | I64Extend16S | I64Extend32S => {
      ctx.poly_pop_expect(I64, "i64 unary op")
      stack.push(I64)
    }

    // i32 to i64 conversion operations
    I64ExtendI32S | I64ExtendI32U => {
      ctx.poly_pop_expect(I32, "i64 extension")
      stack.push(I64)
    }

    // i64 to i32 conversion (wrap)
    I32WrapI64 => {
      ctx.poly_pop_expect(I64, "i32.wrap_i64")
      stack.push(I32)
    }

    // f32 comparison operations
    F32Eq | F32Ne | F32Lt | F32Gt | F32Le | F32Ge => {
      ctx.poly_pop_expect(F32, "f32 comparison")
      ctx.poly_pop_expect(F32, "f32 comparison")
      stack.push(I32)
    }

    // f64 comparison operations
    F64Eq | F64Ne | F64Lt | F64Gt | F64Le | F64Ge => {
      ctx.poly_pop_expect(F64, "f64 comparison")
      ctx.poly_pop_expect(F64, "f64 comparison")
      stack.push(I32)
    }

    // f32 unary operations
    F32Abs | F32Neg | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Sqrt => {
      ctx.poly_pop_expect(F32, "f32 unary op")
      stack.push(F32)
    }

    // f64 unary operations
    F64Abs | F64Neg | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Sqrt => {
      ctx.poly_pop_expect(F64, "f64 unary op")
      stack.push(F64)
    }

    // f32 binary operations
    F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign => {
      ctx.poly_pop_expect(F32, "f32 binary op")
      ctx.poly_pop_expect(F32, "f32 binary op")
      stack.push(F32)
    }

    // f64 binary operations
    F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign => {
      ctx.poly_pop_expect(F64, "f64 binary op")
      ctx.poly_pop_expect(F64, "f64 binary op")
      stack.push(F64)
    }

    // Conversion operations: i32 -> f32/f64
    F32ConvertI32S | F32ConvertI32U => {
      ctx.poly_pop_expect(I32, "f32.convert_i32")
      stack.push(F32)
    }
    F64ConvertI32S | F64ConvertI32U => {
      ctx.poly_pop_expect(I32, "f64.convert_i32")
      stack.push(F64)
    }

    // Conversion operations: i64 -> f32/f64
    F32ConvertI64S | F32ConvertI64U => {
      ctx.poly_pop_expect(I64, "f32.convert_i64")
      stack.push(F32)
    }
    F64ConvertI64S | F64ConvertI64U => {
      ctx.poly_pop_expect(I64, "f64.convert_i64")
      stack.push(F64)
    }

    // Promotion/demotion: f32 <-> f64
    F64PromoteF32 => {
      ctx.poly_pop_expect(F32, "f64.promote_f32")
      stack.push(F64)
    }
    F32DemoteF64 => {
      ctx.poly_pop_expect(F64, "f32.demote_f64")
      stack.push(F32)
    }

    // Truncation: f32/f64 -> i32/i64
    I32TruncF32S | I32TruncF32U => {
      ctx.poly_pop_expect(F32, "i32.trunc_f32")
      stack.push(I32)
    }
    I32TruncF64S | I32TruncF64U => {
      ctx.poly_pop_expect(F64, "i32.trunc_f64")
      stack.push(I32)
    }
    I64TruncF32S | I64TruncF32U => {
      ctx.poly_pop_expect(F32, "i64.trunc_f32")
      stack.push(I64)
    }
    I64TruncF64S | I64TruncF64U => {
      ctx.poly_pop_expect(F64, "i64.trunc_f64")
      stack.push(I64)
    }

    // Saturating truncation: f32/f64 -> i32/i64 (same types as regular trunc)
    I32TruncSatF32S | I32TruncSatF32U => {
      ctx.poly_pop_expect(F32, "i32.trunc_sat_f32")
      stack.push(I32)
    }
    I32TruncSatF64S | I32TruncSatF64U => {
      ctx.poly_pop_expect(F64, "i32.trunc_sat_f64")
      stack.push(I32)
    }
    I64TruncSatF32S | I64TruncSatF32U => {
      ctx.poly_pop_expect(F32, "i64.trunc_sat_f32")
      stack.push(I64)
    }
    I64TruncSatF64S | I64TruncSatF64U => {
      ctx.poly_pop_expect(F64, "i64.trunc_sat_f64")
      stack.push(I64)
    }

    // Reinterpret operations
    F32ReinterpretI32 => {
      ctx.poly_pop_expect(I32, "f32.reinterpret_i32")
      stack.push(F32)
    }
    F64ReinterpretI64 => {
      ctx.poly_pop_expect(I64, "f64.reinterpret_i64")
      stack.push(F64)
    }
    I32ReinterpretF32 => {
      ctx.poly_pop_expect(F32, "i32.reinterpret_f32")
      stack.push(I32)
    }
    I64ReinterpretF64 => {
      ctx.poly_pop_expect(F64, "i64.reinterpret_f64")
      stack.push(I64)
    }

    // Local operations
    LocalGet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      stack.push(local_type)
    }
    LocalSet(idx) | LocalTee(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      ctx.poly_pop_expect(local_type, "local.set")
      match instr {
        LocalTee(_) => stack.push(local_type)
        _ => ()
      }
    }

    // Global operations
    // Note: Global index space includes imported globals first, then local globals
    GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      // Count imported globals
      let mut num_imported_globals = 0
      for imp in module_.imports {
        match imp.desc {
          ImportDesc::Global(_) => num_imported_globals += 1
          _ => ()
        }
      }
      let total_globals = num_imported_globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      let global_type = if global_idx < num_imported_globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : ValType = ValType::I32 // default
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        found_type
      } else {
        // It's a local global
        module_.globals[global_idx - num_imported_globals].type_.val_type
      }
      stack.push(global_type)
    }
    GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      // Count imported globals
      let mut num_imported_globals = 0
      for imp in module_.imports {
        match imp.desc {
          ImportDesc::Global(_) => num_imported_globals += 1
          _ => ()
        }
      }
      let total_globals = num_imported_globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise ValidationError::InvalidGlobalIndex(global_idx)
      }
      let global_type = if global_idx < num_imported_globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : ValType = ValType::I32 // default
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        found_type
      } else {
        // It's a local global
        module_.globals[global_idx - num_imported_globals].type_.val_type
      }
      ctx.poly_pop_expect(global_type, "global.set")
    }

    // Memory operations - loads (all take i32 address and push the loaded value)
    I32Load(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(I32, "i32.load address")
      stack.push(I32)
    }
    I32Load8S(align, _) | I32Load8U(align, _) => {
      validate_alignment(align, 1)
      ctx.poly_pop_expect(I32, "i32.load8 address")
      stack.push(I32)
    }
    I32Load16S(align, _) | I32Load16U(align, _) => {
      validate_alignment(align, 2)
      ctx.poly_pop_expect(I32, "i32.load16 address")
      stack.push(I32)
    }
    I64Load(align, _) => {
      validate_alignment(align, 8)
      ctx.poly_pop_expect(I32, "i64.load address")
      stack.push(I64)
    }
    I64Load8S(align, _) | I64Load8U(align, _) => {
      validate_alignment(align, 1)
      ctx.poly_pop_expect(I32, "i64.load8 address")
      stack.push(I64)
    }
    I64Load16S(align, _) | I64Load16U(align, _) => {
      validate_alignment(align, 2)
      ctx.poly_pop_expect(I32, "i64.load16 address")
      stack.push(I64)
    }
    I64Load32S(align, _) | I64Load32U(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(I32, "i64.load32 address")
      stack.push(I64)
    }
    F32Load(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(I32, "f32.load address")
      stack.push(F32)
    }
    F64Load(align, _) => {
      validate_alignment(align, 8)
      ctx.poly_pop_expect(I32, "f64.load address")
      stack.push(F64)
    }
    // Memory operations - stores (all take i32 address and value, push nothing)
    I32Store(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(I32, "i32.store value")
      ctx.poly_pop_expect(I32, "i32.store address")
    }
    I32Store8(align, _) => {
      validate_alignment(align, 1)
      ctx.poly_pop_expect(I32, "i32.store8 value")
      ctx.poly_pop_expect(I32, "i32.store8 address")
    }
    I32Store16(align, _) => {
      validate_alignment(align, 2)
      ctx.poly_pop_expect(I32, "i32.store16 value")
      ctx.poly_pop_expect(I32, "i32.store16 address")
    }
    I64Store(align, _) => {
      validate_alignment(align, 8)
      ctx.poly_pop_expect(I64, "i64.store value")
      ctx.poly_pop_expect(I32, "i64.store address")
    }
    I64Store8(align, _) => {
      validate_alignment(align, 1)
      ctx.poly_pop_expect(I64, "i64.store8 value")
      ctx.poly_pop_expect(I32, "i64.store8 address")
    }
    I64Store16(align, _) => {
      validate_alignment(align, 2)
      ctx.poly_pop_expect(I64, "i64.store16 value")
      ctx.poly_pop_expect(I32, "i64.store16 address")
    }
    I64Store32(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(I64, "i64.store32 value")
      ctx.poly_pop_expect(I32, "i64.store32 address")
    }
    F32Store(align, _) => {
      validate_alignment(align, 4)
      ctx.poly_pop_expect(F32, "f32.store value")
      ctx.poly_pop_expect(I32, "f32.store address")
    }
    F64Store(align, _) => {
      validate_alignment(align, 8)
      ctx.poly_pop_expect(F64, "f64.store value")
      ctx.poly_pop_expect(I32, "f64.store address")
    }
    // Memory size and grow
    MemorySize(_) => stack.push(I32)
    MemoryGrow(_) => {
      ctx.poly_pop_expect(I32, "memory.grow delta")
      stack.push(I32)
    }

    // Table instructions
    TableSize(_) => stack.push(I32)
    TableGet(table_idx) => {
      ctx.poly_pop_expect(I32, "table.get index")
      // Look up table's element type
      let elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        let table = module_.tables[table_idx.reinterpret_as_int()]
        reftype_to_valtype(table.elem_type)
      } else {
        ValType::FuncRef // Default if table not found
      }
      stack.push(elem_type)
    }
    TableSet(_) => {
      // Pop funcref value, then i32 index
      // For now, we accept any ref type (simplified validation)
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("table.set expects value on stack")
      } else {
        let _ = stack.unsafe_pop()
        // Pop the ref value
      }
      ctx.poly_pop_expect(I32, "table.set index")
    }
    TableGrow(table_idx) => {
      ctx.poly_pop_expect(I32, "table.grow delta")
      // Pop init value and check it matches table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        RefType::Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : ValType = reftype_to_valtype(table_elem_type)
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "table.grow expects init value on stack",
        )
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.grow init value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }
      stack.push(I32) // Returns old size
    }

    // Reference instructions
    RefNull(ref_type) => {
      // ref.null pushes a null reference of the given type
      let val_type = reftype_to_valtype(ref_type)
      stack.push(val_type)
    }
    RefFunc(_) =>
      // ref.func pushes a funcref
      stack.push(ValType::FuncRef)
    RefIsNull => {
      // ref.is_null pops a reference type and pushes i32
      // In polymorphic context, allow any type on stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "ref.is_null expects reference on stack",
        )
      } else {
        let _ = stack.unsafe_pop()
        // Pop the reference
      }
      stack.push(I32) // Push result
    }

    // Block instructions
    Block(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(params[i], "block parameter")
      }
      // Create new validation context for block
      let block_ctx = ValidationCtx::new()
      // Add parameters to block stack in correct order
      for param in params {
        block_ctx.stack.push(param)
      }
      // Copy parent control stack and add this block's frame
      for frame in ctx.control_stack {
        block_ctx.control_stack.push(frame)
      }
      block_ctx.push_control(params, results)
      // Validate block body
      for block_instr in instrs {
        validate_instruction(module_, func_type, code, block_ctx, block_instr)
      }
      let _ = block_ctx.pop_control()
      // Check block produces correct results
      if block_ctx.is_unreachable && block_ctx.stack.length() == 0 {
        // Unreachable code with empty stack - all polymorphic, push expected results
        for result in results {
          stack.push(result)
        }
      } else if block_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - this is a type mismatch
        raise ValidationError::TypeMismatch(
          "block: expected \{results.length()} values, got \{block_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i = 0; i < results.length(); i = i + 1 {
          if not(is_subtype(block_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch("block result type mismatch: expected \{results[i]}, got \{block_ctx.stack[i]}")
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    Loop(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(params[i], "loop parameter")
      }
      // Create new validation context for loop
      let loop_ctx = ValidationCtx::new()
      // Add parameters to loop stack in correct order
      for param in params {
        loop_ctx.stack.push(param)
      }
      // Copy parent control stack and add this loop's frame
      // Note: For loops, br targets the beginning (params), not the end (results)
      for frame in ctx.control_stack {
        loop_ctx.control_stack.push(frame)
      }
      loop_ctx.push_control(params, params) // Loop's br target uses params, not results
      // Validate loop body
      for loop_instr in instrs {
        validate_instruction(module_, func_type, code, loop_ctx, loop_instr)
      }
      let _ = loop_ctx.pop_control()
      // Check loop produces correct results
      if loop_ctx.is_unreachable && loop_ctx.stack.length() == 0 {
        // Unreachable code with empty stack - all polymorphic
        for result in results {
          stack.push(result)
        }
      } else if loop_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - type mismatch
        raise ValidationError::TypeMismatch(
          "loop: expected \{results.length()} values, got \{loop_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i = 0; i < results.length(); i = i + 1 {
          if not(is_subtype(loop_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch("loop result type mismatch: expected \{results[i]}, got \{loop_ctx.stack[i]}")
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    If(block_type, then_instrs, else_instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop condition (using polymorphic stack)
      ctx.poly_pop_expect(I32, "if condition")
      // Pop parameters from parent stack (using polymorphic stack)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(params[i], "if parameter")
      }
      // Validate then branch
      let then_ctx = ValidationCtx::new()
      for param in params {
        then_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        then_ctx.control_stack.push(frame)
      }
      then_ctx.push_control(params, results)
      for then_instr in then_instrs {
        validate_instruction(module_, func_type, code, then_ctx, then_instr)
      }
      let _ = then_ctx.pop_control()
      // Check then branch produces correct results
      if then_ctx.is_unreachable && then_ctx.stack.length() == 0 {
        // Unreachable with empty stack - all polymorphic, valid
      } else if then_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if then branch: expected \{results.length()} values, got \{then_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i = 0; i < results.length(); i = i + 1 {
          if not(is_subtype(then_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "if then branch result type mismatch: expected \{results[i]}, got \{then_ctx.stack[i]}",
            )
          }
        }
      }
      // Validate else branch
      let else_ctx = ValidationCtx::new()
      for param in params {
        else_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        else_ctx.control_stack.push(frame)
      }
      else_ctx.push_control(params, results)
      for else_instr in else_instrs {
        validate_instruction(module_, func_type, code, else_ctx, else_instr)
      }
      let _ = else_ctx.pop_control()
      // Check else branch produces correct results
      if else_ctx.is_unreachable && else_ctx.stack.length() == 0 {
        // Unreachable with empty stack - all polymorphic, valid
      } else if else_ctx.stack.length() != results.length() {
        raise ValidationError::TypeMismatch(
          "if else branch: expected \{results.length()} values, got \{else_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i = 0; i < results.length(); i = i + 1 {
          if not(is_subtype(else_ctx.stack[i], results[i])) {
            raise ValidationError::TypeMismatch(
              "if else branch result type mismatch: expected \{results[i]}, got \{else_ctx.stack[i]}",
            )
          }
        }
      }
      // Push results onto parent stack
      for result in results {
        stack.push(result)
      }
    }

    // Control flow
    Return => {
      // In unreachable code with empty stack, allow polymorphic return
      // Otherwise, validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Check we have the right values on stack for function return
        if stack.length() < func_type.results.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "return: expected \{func_type.results.length()} values on stack",
            )
          }
        } else {
          // Validate result types for concrete values (with subtyping)
          for i = 0; i < func_type.results.length(); i = i + 1 {
            let stack_idx = stack.length() - func_type.results.length() + i
            if not(is_subtype(stack[stack_idx], func_type.results[i])) {
              raise ValidationError::TypeMismatch("return: result type mismatch: expected \{func_type.results[i]}, got \{stack[stack_idx]}")
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
      stack.clear()
    }
    Br(label) => {
      // Always validate label exists (even in unreachable code)
      let target_types = ctx.get_label_types(label)

      // Validate stack contents (even in unreachable code with concrete values)
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Unconditional branch - validate we have required values for target
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "br: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for the branch target (with subtyping)
          for i = 0; i < target_types.length(); i = i + 1 {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(stack[stack_idx], target_types[i])) {
              raise ValidationError::TypeMismatch(
                "br: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
      stack.clear()
    }
    BrIf(_label) =>
      // Conditional branch - pop i32 condition
      ctx.poly_pop_expect(I32, "br_if condition")
    // Stack continues after (not unreachable)
    BrTable(labels, default_label) => {
      // Table branch - pop i32 index
      ctx.poly_pop_expect(I32, "br_table index")

      // Validate all labels exist (even in unreachable code)
      for label in labels {
        let _ = ctx.get_label_types(label)
      }
      let target_types = ctx.get_label_types(default_label)

      // Validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Validate we have required values for branch targets using default label
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise ValidationError::TypeMismatch(
              "br_table: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for concrete values (with subtyping)
          for i = 0; i < target_types.length(); i = i + 1 {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(stack[stack_idx], target_types[i])) {
              raise ValidationError::TypeMismatch(
                "br_table: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Code after is unreachable, record stack height
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
      stack.clear()
    }
    BrOnNull(_label) => {
      // br_on_null: pop nullable ref, branch if null, else push non-null ref
      // For now, just pop a reference value (any reference type)
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise ValidationError::TypeMismatch("br_on_null expects reference on stack")
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()
        // Push back a reference (simplified - same type for now)
        // TODO: properly track non-null type narrowing
        stack.push(FuncRef) // Placeholder
      }
    }
    BrOnNonNull(label) => {
      // br_on_non_null: pop nullable ref, branch if non-null (with the value), else continue
      // Pop the nullable reference
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise ValidationError::TypeMismatch("br_on_non_null expects reference on stack")
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()
      }
      // If we branch, we pass the non-null value to the target
      // Fallthrough case: the value was null, so nothing is pushed
    }
    Drop =>
      // In unreachable code, drop is valid even with empty stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - pretend we dropped something
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("expected value on stack for drop")
      } else {
        let _ = stack.unsafe_pop()

      }
    Select => {
      // Note: We can't distinguish between plain select (0x1B) and typed select (0x1C)
      // at validation time since the parser treats them the same. So we allow all types.
      // Pop condition (i32), then two values of same type, push one back
      ctx.poly_pop_expect(I32, "select condition")
      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate
      if num_concrete >= 2 {
        // Both values are concrete - they must match
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()
        if val1 != val2 {
          raise ValidationError::TypeMismatch(
            "select values must have same type: got \{val1} and \{val2}",
          )
        }
        stack.push(val1)
      } else if num_concrete == 1 {
        // One concrete, one polymorphic
        let val = stack.unsafe_pop()
        stack.push(val)
      } else {
        // Both polymorphic (stack is empty)
        if ctx.is_unreachable {
          // In unreachable code, assume a default type
          stack.push(I32)
        } else {
          raise ValidationError::TypeMismatch("select expects 2 values on stack")
        }
      }
    }
    Nop => ()
    Unreachable => {
      // unreachable instruction marks all subsequent code as unreachable
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
      stack.clear()
    }
    Call(func_idx) => {
      let idx = func_idx.reinterpret_as_int()
      // Count imported functions first
      let mut num_imported_funcs = 0
      for imp in module_.imports {
        match imp.desc {
          ImportDesc::Func(_) => num_imported_funcs += 1
          _ => ()
        }
      }
      let total_funcs = num_imported_funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise ValidationError::InvalidFunctionIndex(idx)
      }
      // Get the function type
      let type_idx = if idx < num_imported_funcs {
        // It's an imported function - find the type index from imports
        let mut import_func_idx = 0
        let mut found_type_idx = 0
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Func(t) => {
              if import_func_idx == idx {
                found_type_idx = t.reinterpret_as_int()
                break
              }
              import_func_idx += 1
            }
            _ => ()
          }
        }
        found_type_idx
      } else {
        // It's a local function
        module_.funcs[idx - num_imported_funcs].reinterpret_as_int()
      }
      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(func_type_called.params[i], "call argument")
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    CallIndirect(type_idx, _table_idx) => {
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      ctx.poly_pop_expect(I32, "call_indirect table index")
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          func_type_called.params[i],
          "call_indirect argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    ReturnCall(func_idx) => {
      // return_call: tail call that returns to caller
      // Reuse the same logic as Call, but mark as unreachable
      let idx = func_idx.reinterpret_as_int()

      // Find the type index for this function
      // First count imported functions
      let mut num_imported_funcs = 0
      for imp in module_.imports {
        match imp.desc {
          ImportDesc::Func(_) => num_imported_funcs += 1
          _ => ()
        }
      }

      let type_idx = if idx < num_imported_funcs {
        // It's an imported function - find its type
        let mut import_func_idx = 0
        let mut found_type_idx = 0
        for imp in module_.imports {
          match imp.desc {
            ImportDesc::Func(t) => {
              if import_func_idx == idx {
                found_type_idx = t.reinterpret_as_int()
                break
              }
              import_func_idx += 1
            }
            _ => ()
          }
        }
        found_type_idx
      } else {
        // It's a local function
        let local_idx = idx - num_imported_funcs
        if local_idx < 0 || local_idx >= module_.funcs.length() {
          raise ValidationError::InvalidFunctionIndex(idx)
        }
        module_.funcs[local_idx].reinterpret_as_int()
      }

      if type_idx < 0 || type_idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(type_idx)
      }

      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(func_type_called.params[i], "return_call argument")
      }
      // Mark as unreachable - this is a tail call that doesn't return to current function
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
    }
    ReturnCallIndirect(type_idx, _table_idx) => {
      // return_call_indirect: tail call through table that returns to caller
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      ctx.poly_pop_expect(I32, "return_call_indirect table index")
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          func_type_called.params[i],
          "return_call_indirect argument",
        )
      }
      // For tail calls, just mark as unreachable without modifying stack
      // The called function's signature should match current function's return type
      // This will be validated at the end of the function
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
    }
    CallRef(type_idx) => {
      // call_ref: calls function through a reference
      // Stack: [args...] [funcref] -> [results...]
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]

      // Pop the function reference
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("call_ref expects funcref on stack")
      } else {
        let _ = stack.unsafe_pop() // Pop funcref (we don't type-check it strictly for now)
      }

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(func_type_called.params[i], "call_ref argument")
      }

      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    ReturnCallRef(type_idx) => {
      // return_call_ref: tail call through a reference
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]

      // Pop the function reference
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("return_call_ref expects funcref on stack")
      } else {
        let _ = stack.unsafe_pop() // Pop funcref
      }

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(func_type_called.params[i], "return_call_ref argument")
      }

      // Mark as unreachable - this is a tail call
      ctx.is_unreachable = true
      ctx.unreachable_stack_height = stack.length()
    }
  }
}

///|
/// Validate a single function
fn validate_function(
  module_ : Module,
  func_type : FuncType,
  code : Code,
) -> Unit raise ValidationError {
  // Create validation context
  let ctx = ValidationCtx::new()
  // Push function-level control frame with empty params and function results
  ctx.push_control([], func_type.results)

  // Validate each instruction in the function body
  for instr in code.body.instrs {
    validate_instruction(module_, func_type, code, ctx, instr)
  }

  // Check final stack matches return type
  let stack = ctx.stack
  if ctx.is_unreachable && stack.length() == 0 {
    // Unreachable code with empty stack - all values are polymorphic, valid
  } else if stack.length() != func_type.results.length() {
    // Stack size doesn't match expected return values
    if stack.length() < func_type.results.length() {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    } else if func_type.results.length() == 0 && stack.length() > 0 {
      raise ValidationError::StackSizeMismatch(
        "function: void function should not have values on stack, got \{stack.length()}",
      )
    } else {
      raise ValidationError::StackSizeMismatch(
        "function: expected \{func_type.results.length()} return values, got \{stack.length()}",
      )
    }
  } else {
    // Check types from top of stack (with subtyping)
    for i = 0; i < func_type.results.length(); i = i + 1 {
      // Stack type must be a subtype of expected return type
      if not(is_subtype(stack[i], func_type.results[i])) {
        raise ValidationError::TypeMismatch("function return type mismatch: expected \{func_type.results[i]}, got \{stack[i]}")
      }
    }
  }
}
