// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Convert @core.RefType to @core.ValType
fn reftype_to_valtype(ref_type : @core.RefType) -> @core.ValType {
  match ref_type {
    @core.RefType::Func => @core.ValType::FuncRef
    @core.RefType::Extern => @core.ValType::ExternRef
    @core.RefType::Any => @core.ValType::AnyRef
    @core.RefType::Eq => @core.ValType::EqRef
    @core.RefType::I31 => @core.ValType::I31Ref
    @core.RefType::Struct => @core.ValType::StructRef
    @core.RefType::Array => @core.ValType::ArrayRef
    @core.RefType::Exn => @core.ValType::ExnRef
    @core.RefType::None => @core.ValType::NullRef
    @core.RefType::NoFunc => @core.ValType::NullFuncRef
    @core.RefType::NoExtern => @core.ValType::NullExternRef
    @core.RefType::NoExn => @core.ValType::NullExnRef
    // @core.RefType::TypeIndex: return nullable typed reference (ref null $t)
    @core.RefType::TypeIndex(_) => @core.ValType::Ref(ref_type, true)
  }
}

///|
/// Cached counts of imported resources
priv struct ImportCounts {
  funcs : Int
  tables : Int
  mems : Int
  globals : Int
}

///|
/// Compute import counts in a single pass through imports
/// This is more efficient than counting each type separately
fn get_import_counts(module_ : @core.Module) -> ImportCounts {
  let mut funcs = 0
  let mut tables = 0
  let mut mems = 0
  let mut globals = 0
  for imp in module_.imports {
    match imp.desc {
      @core.ImportDesc::Func(_) => funcs += 1
      @core.ImportDesc::Table(_) => tables += 1
      @core.ImportDesc::Mem(_) => mems += 1
      @core.ImportDesc::Global(_) => globals += 1
      _ => ()
    }
  }
  { funcs, tables, mems, globals }
}

///|
/// Get the type index for a function (imported or local)
fn get_func_type_index(
  module_ : @core.Module,
  func_idx : Int,
  import_counts : ImportCounts,
) -> Int raise @core.ValidationError {
  if func_idx < import_counts.funcs {
    // Imported function - find type index from imports
    let mut current_import = 0
    let mut found_type_idx = 0
    for imp in module_.imports {
      match imp.desc {
        @core.ImportDesc::Func(tidx) => {
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
    // Local function - get type index from funcs array
    let local_idx = func_idx - import_counts.funcs
    if local_idx < 0 || local_idx >= module_.funcs.length() {
      raise @core.ValidationError::InvalidFunctionIndex(func_idx)
    }
    module_.funcs[local_idx].reinterpret_as_int()
  }
}

///|
/// Validate a binary operation
fn validate_binary_op(
  ctx : ValidationCtx,
  module_ : @core.Module,
  operand_type : @core.ValType,
  result_type : @core.ValType,
  op_name : String,
) -> Unit raise @core.ValidationError {
  ctx.poly_pop_expect(module_, operand_type, op_name)
  ctx.poly_pop_expect(module_, operand_type, op_name)
  ctx.stack.push(result_type)
}

///|
/// Validate a memory load instruction
fn validate_load(
  ctx : ValidationCtx,
  module_ : @core.Module,
  import_counts : ImportCounts,
  align : UInt,
  natural_align : Int,
  result_type : @core.ValType,
  op_name : String,
) -> Unit raise @core.ValidationError {
  validate_memory_exists(module_, import_counts)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, @core.ValType::I32, "\{op_name} address")
  ctx.stack.push(result_type)
}

///|
/// Validate a memory store instruction
fn validate_store(
  ctx : ValidationCtx,
  module_ : @core.Module,
  import_counts : ImportCounts,
  align : UInt,
  natural_align : Int,
  value_type : @core.ValType,
  op_name : String,
) -> Unit raise @core.ValidationError {
  validate_memory_exists(module_, import_counts)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, value_type, "\{op_name} value")
  ctx.poly_pop_expect(module_, @core.ValType::I32, "\{op_name} address")
}

///|
/// Validate alignment - alignment must not be larger than natural alignment
/// align parameter is stored as log2(alignment), natural is in bytes
fn validate_alignment(
  align : UInt,
  natural : Int,
) -> Unit raise @core.ValidationError {
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
    raise @core.ValidationError::InvalidAlignment(
      "alignment must not be larger than natural (align=\{align_int}, max=\{max_align})",
    )
  }
}

///|
/// Validate that a memory exists in the module (memory 0)
fn validate_memory_exists(
  module_ : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise @core.ValidationError {
  let total_mems = import_counts.mems + module_.mems.length()
  if total_mems == 0 {
    raise @core.ValidationError::UnknownMemory(0)
  }
}

///|
/// Validate that all instructions in an expression are valid constant expression instructions
/// WebAssembly constant expressions can only contain:
/// - Constant instructions: i32.const, i64.const, f32.const, f64.const
/// - Reference instructions: ref.null, ref.func
/// - @core.Global access: global.get
/// - Arithmetic: i32.add, i32.sub, i32.mul, i64.add, i64.sub, i64.mul
fn validate_const_expr_instructions(
  expr : @core.Expr,
) -> Unit raise @core.ValidationError {
  for instr in expr.instrs {
    match instr {
      @core.Instr::I32Const(_)
      | @core.Instr::I64Const(_)
      | @core.Instr::F32Const(_)
      | @core.Instr::F64Const(_)
      | @core.Instr::RefNull(_)
      | @core.Instr::RefFunc(_)
      | @core.Instr::GlobalGet(_)
      | @core.Instr::I32Add
      | @core.Instr::I32Sub
      | @core.Instr::I32Mul
      | @core.Instr::I64Add
      | @core.Instr::I64Sub
      | @core.Instr::I64Mul => () // Valid constant expression instructions
      _ =>
        raise @core.ValidationError::ConstantExpressionRequired(
          "invalid instruction in constant expression: \{instr}",
        )
    }
  }
}

///|
/// Validate that a table init expression only references imported globals
/// Table initialization happens before local globals are initialized,
/// so only imported globals are available
fn validate_table_init_expr(
  m : @core.Module,
  expr : @core.Expr,
  import_counts : ImportCounts,
) -> Unit raise @core.ValidationError {
  // First check that instructions are valid constant expression instructions
  validate_const_expr_instructions(expr)

  // Then check that global.get only references imported globals
  for instr in expr.instrs {
    match instr {
      @core.Instr::GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Must be an imported global (index < import_counts.globals)
        if global_idx >= import_counts.globals {
          raise @core.ValidationError::UnknownGlobal(global_idx)
        }
        // Also check that the imported global is immutable
        let mut import_global_idx = 0
        for imp in m.imports {
          match imp.desc {
            @core.ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                if gt.mutable {
                  raise @core.ValidationError::ConstantExpressionRequired(
                    "table initializer global.get must reference immutable global",
                  )
                }
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// Validate that a constant expression only uses immutable globals
/// WebAssembly constant expressions can only use global.get on immutable globals
fn validate_const_expr_globals(
  m : @core.Module,
  expr : @core.Expr,
  import_counts : ImportCounts,
) -> Unit raise @core.ValidationError {
  for instr in expr.instrs {
    match instr {
      @core.Instr::GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Check if global is mutable
        let is_mutable = if global_idx < import_counts.globals {
          // Imported global
          let mut import_global_idx = 0
          let mut found_mutable = false
          for imp in m.imports {
            match imp.desc {
              @core.ImportDesc::Global(gt) => {
                if import_global_idx == global_idx {
                  found_mutable = gt.mutable
                  break
                }
                import_global_idx += 1
              }
              _ => ()
            }
          }
          found_mutable
        } else {
          // Local global
          let local_idx = global_idx - import_counts.globals
          if local_idx >= 0 && local_idx < m.globals.length() {
            m.globals[local_idx].type_.mutable
          } else {
            false
          }
        }
        if is_mutable {
          raise @core.ValidationError::ConstantExpressionRequired(
            "global.get in constant expression must reference immutable global",
          )
        }
      }
      _ => ()
    }
  }
}

///|
/// Check if a type index refers to a function type in the module
fn is_func_type_index(module_ : @core.Module, type_idx : Int) -> Bool {
  // In our current implementation, all entries in module_.types are @core.FuncType
  // So any valid type index is a function type
  type_idx >= 0 && type_idx < module_.types.length()
}

///|
/// Validate that all type indices in a @core.ValType exist in the module
fn validate_valtype(
  module_ : @core.Module,
  val_type : @core.ValType,
) -> Unit raise @core.ValidationError {
  match val_type {
    @core.ValType::Ref(@core.RefType::TypeIndex(idx), _) =>
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::UnknownType(idx)
      }
    _ => () // Other types don't have type indices
  }
}

///|
/// Check if t1 is a subtype of t2 (t1 <: t2) with module context for type lookups
/// WebAssembly GC type hierarchy:
/// - @core.ValType::NullRef (none) <: all nullable reference types
/// - @core.ValType::NullFuncRef (nofunc) <: @core.ValType::FuncRef
/// - @core.ValType::NullExternRef (noextern) <: @core.ValType::ExternRef
/// - @core.ValType::NullExnRef (noexn) <: @core.ValType::ExnRef
/// - @core.ValType::I31Ref, @core.ValType::StructRef, @core.ValType::ArrayRef <: @core.ValType::EqRef <: @core.ValType::AnyRef
/// - @core.ValType::FuncRef <: @core.ValType::AnyRef (in some proposals)
fn is_subtype(
  module_ : @core.Module,
  t1 : @core.ValType,
  t2 : @core.ValType,
) -> Bool {
  // Reflexive: every type is a subtype of itself
  if t1 == t2 {
    return true
  }
  match (t1, t2) {
    // Bottom types (null) are subtypes of their corresponding reference types
    (@core.ValType::NullRef, @core.ValType::AnyRef)
    | (@core.ValType::NullRef, @core.ValType::EqRef)
    | (@core.ValType::NullRef, @core.ValType::I31Ref)
    | (@core.ValType::NullRef, @core.ValType::StructRef)
    | (@core.ValType::NullRef, @core.ValType::ArrayRef) => true
    (@core.ValType::NullFuncRef, @core.ValType::FuncRef) => true
    // @core.ValType::NullFuncRef is the bottom type for all function references,
    // so it's a subtype of any nullable typed function reference
    (
      @core.ValType::NullFuncRef,
      @core.ValType::Ref(@core.RefType::TypeIndex(n), true),
    ) => is_func_type_index(module_, n)
    (@core.ValType::NullFuncRef, @core.ValType::Ref(@core.RefType::Func, true)) =>
      true
    (@core.ValType::NullExternRef, @core.ValType::ExternRef) => true
    (@core.ValType::NullExnRef, @core.ValType::ExnRef) => true

    // Reference type hierarchy
    (@core.ValType::I31Ref, @core.ValType::EqRef)
    | (@core.ValType::I31Ref, @core.ValType::AnyRef) => true
    (@core.ValType::StructRef, @core.ValType::EqRef)
    | (@core.ValType::StructRef, @core.ValType::AnyRef) => true
    (@core.ValType::ArrayRef, @core.ValType::EqRef)
    | (@core.ValType::ArrayRef, @core.ValType::AnyRef) => true
    (@core.ValType::EqRef, @core.ValType::AnyRef) => true

    // Some proposals allow funcref <: anyref
    (@core.ValType::FuncRef, @core.ValType::AnyRef) => true
    (@core.ValType::ExnRef, @core.ValType::AnyRef) => true

    // Typed references: @core.ValType::Ref(T, nullable)
    // Non-nullable is subtype of nullable for same heap type
    (@core.ValType::Ref(ht1, false), @core.ValType::Ref(ht2, true)) =>
      ht1 == ht2
    // @core.ValType::Ref(Extern, _) is compatible with @core.ValType::ExternRef (nullable externref)
    (@core.ValType::Ref(@core.RefType::Extern, _), @core.ValType::ExternRef) =>
      true
    // @core.ValType::Ref(Func, _) is compatible with @core.ValType::FuncRef (nullable funcref)
    (@core.ValType::Ref(@core.RefType::Func, _), @core.ValType::FuncRef) => true
    // @core.ValType::Ref(@core.RefType::TypeIndex(n), _) is a typed function reference, compatible with @core.ValType::FuncRef
    // only if type n is actually a function type
    (@core.ValType::Ref(@core.RefType::TypeIndex(n), _), @core.ValType::FuncRef) =>
      is_func_type_index(module_, n)
    // Typed function reference is also compatible with non-nullable (ref func)
    (
      @core.ValType::Ref(@core.RefType::TypeIndex(n), false),
      @core.ValType::Ref(@core.RefType::Func, false),
    ) => is_func_type_index(module_, n)
    (
      @core.ValType::Ref(@core.RefType::TypeIndex(n), _),
      @core.ValType::Ref(@core.RefType::Func, true),
    ) => is_func_type_index(module_, n)
    // NOTE: @core.ValType::FuncRef is NOT a subtype of typed function references
    // General funcref cannot be used where specific typed reference is required
    // (@core.ValType::FuncRef, @core.ValType::Ref(@core.RefType::TypeIndex(n), true)) => false
    (@core.ValType::FuncRef, @core.ValType::Ref(@core.RefType::Func, true)) =>
      true
    // @core.ValType::Ref(Any, _) is compatible with @core.ValType::AnyRef
    (@core.ValType::Ref(@core.RefType::Any, _), @core.ValType::AnyRef) => true
    // @core.ValType::Ref(Exn, _) is compatible with @core.ValType::ExnRef
    (@core.ValType::Ref(@core.RefType::Exn, _), @core.ValType::ExnRef) => true
    // Any reference is subtype of @core.ValType::AnyRef
    (@core.ValType::Ref(_, _), @core.ValType::AnyRef) => true

    // Non-reference types are not related by subtyping
    _ => false
  }
}
