// Public API for the WebAssembly interpreter
// This module ties together types, parser, and runtime components

///|
/// Convert @core.RefType to @core.ValType
fn reftype_to_valtype(ref_type : @core.RefType) -> @core.ValType {
  match ref_type {
    Func => FuncRef
    Extern => ExternRef
    Any => AnyRef
    Eq => EqRef
    I31 => I31Ref
    Struct => StructRef
    Array => ArrayRef
    Exn => ExnRef
    None => NullRef
    NoFunc => NullFuncRef
    NoExtern => NullExternRef
    NoExn => NullExnRef
    // TypeIndex: return nullable typed reference (ref null $t)
    TypeIndex(_) => Ref(ref_type, true)
  }
}

///|
/// Cached counts of imported resources
priv struct ImportCounts {
  funcs : Int
  tables : Int
  mems : Int
  globals : Int
  tags : Int
}

///|
/// Compute import counts in a single pass through imports
/// This is more efficient than counting each type separately
fn get_import_counts(module_ : @core.Module) -> ImportCounts {
  let mut funcs = 0
  let mut tables = 0
  let mut mems = 0
  let mut globals = 0
  let mut tags = 0
  for imp in module_.imports {
    match imp.desc {
      Func(_) => funcs += 1
      Table(_) => tables += 1
      Mem(_) => mems += 1
      Global(_) => globals += 1
      Tag(_) => tags += 1
      _ => ()
    }
  }
  { funcs, tables, mems, globals, tags }
}

///|
/// Get the type index for a function (imported or local)
fn get_func_type_index(
  module_ : @core.Module,
  func_idx : Int,
  import_counts : ImportCounts,
) -> Int raise ValidationError {
  if func_idx < import_counts.funcs {
    // Imported function - find type index from imports
    let mut current_import = 0
    let mut found_type_idx = 0
    for imp in module_.imports {
      match imp.desc {
        Func(tidx) => {
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
      raise ValidationError::InvalidFunctionIndex(func_idx)
    }
    module_.funcs[local_idx].reinterpret_as_int()
  }
}

///|
/// Get the type index for a tag (imported or local)
fn get_tag_type_index(
  module_ : @core.Module,
  tag_idx : Int,
  import_counts : ImportCounts,
) -> Int raise ValidationError {
  if tag_idx < import_counts.tags {
    // Imported tag - find type index from imports
    let mut current_import = 0
    let mut found_type_idx = 0
    for imp in module_.imports {
      match imp.desc {
        Tag(tidx) => {
          if current_import == tag_idx {
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
    let local_idx = tag_idx - import_counts.tags
    if local_idx < 0 || local_idx >= module_.tags.length() {
      raise ValidationError::UnknownTag(tag_idx)
    }
    module_.tags[local_idx].type_idx.reinterpret_as_int()
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
) -> Unit raise ValidationError {
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
  mem_idx : UInt,
  natural_align : Int,
  result_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_index(module_, import_counts, mem_idx)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, I32, "\{op_name} address")
  ctx.stack.push(result_type)
}

///|
/// Validate a memory store instruction
fn validate_store(
  ctx : ValidationCtx,
  module_ : @core.Module,
  import_counts : ImportCounts,
  align : UInt,
  mem_idx : UInt,
  natural_align : Int,
  value_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_index(module_, import_counts, mem_idx)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, value_type, "\{op_name} value")
  ctx.poly_pop_expect(module_, I32, "\{op_name} address")
}

///|
/// Validate alignment - alignment must not be larger than natural alignment
/// align parameter is stored as log2(alignment), natural is in bytes
fn validate_alignment(
  align : UInt,
  natural : Int,
) -> Unit raise ValidationError {
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
/// Validate that a memory exists in the module (memory 0)
fn validate_memory_exists(
  module_ : @core.Module,
  import_counts : ImportCounts,
) -> Unit raise ValidationError {
  validate_memory_index(module_, import_counts, 0U)
}

///|
fn validate_memory_index(
  module_ : @core.Module,
  import_counts : ImportCounts,
  mem_idx : UInt,
) -> Unit raise ValidationError {
  let total_mems = import_counts.mems + module_.mems.length()
  let idx = mem_idx.reinterpret_as_int()
  if idx < 0 || idx >= total_mems {
    raise ValidationError::UnknownMemory(idx)
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
) -> Unit raise ValidationError {
  for instr in expr.instrs {
    match instr {
      I32Const(_)
      | I64Const(_)
      | F32Const(_)
      | F64Const(_)
      | RefNull(_)
      | RefFunc(_)
      | GlobalGet(_)
      | I32Add
      | I32Sub
      | I32Mul
      | I64Add
      | I64Sub
      | I64Mul => () // Valid constant expression instructions
      _ =>
        raise ValidationError::ConstantExpressionRequired(
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
) -> Unit raise ValidationError {
  // First check that instructions are valid constant expression instructions
  validate_const_expr_instructions(expr)

  // Then check that global.get only references imported globals
  for instr in expr.instrs {
    match instr {
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Must be an imported global (index < import_counts.globals)
        if global_idx >= import_counts.globals {
          raise ValidationError::UnknownGlobal(global_idx)
        }
        // Also check that the imported global is immutable
        let mut import_global_idx = 0
        for imp in m.imports {
          match imp.desc {
            Global(gt) => {
              if import_global_idx == global_idx {
                if gt.mutable {
                  raise ValidationError::ConstantExpressionRequired(
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
) -> Unit raise ValidationError {
  for instr in expr.instrs {
    match instr {
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Check if global is mutable
        let is_mutable = if global_idx < import_counts.globals {
          // Imported global
          let mut import_global_idx = 0
          let mut found_mutable = false
          for imp in m.imports {
            match imp.desc {
              Global(gt) => {
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
          raise ValidationError::ConstantExpressionRequired(
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
) -> Unit raise ValidationError {
  match val_type {
    Ref(TypeIndex(idx), _) =>
      if idx < 0 || idx >= module_.types.length() {
        raise ValidationError::UnknownType(idx)
      }
    _ => () // Other types don't have type indices
  }
}

///|
/// Check if t1 is a subtype of t2 (t1 <: t2) with module context for type lookups
/// WebAssembly GC type hierarchy:
/// - NullRef (none) <: all nullable reference types
/// - NullFuncRef (nofunc) <: FuncRef
/// - NullExternRef (noextern) <: ExternRef
/// - NullExnRef (noexn) <: ExnRef
/// - I31Ref, StructRef, ArrayRef <: EqRef <: AnyRef
/// - FuncRef <: AnyRef (in some proposals)
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
    (NullRef, AnyRef)
    | (NullRef, EqRef)
    | (NullRef, I31Ref)
    | (NullRef, StructRef)
    | (NullRef, ArrayRef) => true
    (NullFuncRef, FuncRef) => true
    // NullFuncRef is the bottom type for all function references,
    // so it's a subtype of any nullable typed function reference
    (NullFuncRef, Ref(TypeIndex(n), true)) => is_func_type_index(module_, n)
    (NullFuncRef, Ref(Func, true)) => true
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

    // Typed references: Ref(T, nullable)
    // Non-nullable is subtype of nullable for same heap type
    (Ref(ht1, false), Ref(ht2, true)) => ht1 == ht2
    // Ref(Extern, _) is compatible with ExternRef (nullable externref)
    (Ref(Extern, _), ExternRef) => true
    // Ref(Func, _) is compatible with FuncRef (nullable funcref)
    (Ref(Func, _), FuncRef) => true
    // Ref(TypeIndex(n), _) is a typed function reference, compatible with FuncRef
    // only if type n is actually a function type
    (Ref(TypeIndex(n), _), FuncRef) => is_func_type_index(module_, n)
    // Typed function reference is also compatible with non-nullable (ref func)
    (Ref(TypeIndex(n), false), Ref(Func, false)) =>
      is_func_type_index(module_, n)
    (Ref(TypeIndex(n), _), Ref(Func, true)) => is_func_type_index(module_, n)
    // NOTE: FuncRef is NOT a subtype of typed function references
    // General funcref cannot be used where specific typed reference is required
    // (FuncRef, Ref(TypeIndex(n), true)) => false
    (FuncRef, Ref(Func, true)) => true
    // Ref(Any, _) is compatible with AnyRef
    (Ref(Any, _), AnyRef) => true
    // Ref(Exn, _) is compatible with ExnRef
    (Ref(Exn, _), ExnRef) => true
    // Any reference is subtype of AnyRef
    (Ref(_, _), AnyRef) => true

    // Non-reference types are not related by subtyping
    _ => false
  }
}
