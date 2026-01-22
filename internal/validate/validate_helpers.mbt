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
/// Use ImportCounts from core module
type ImportCounts = @core.ImportCounts

///|
/// Compute import counts in a single pass through imports.
/// Delegates to core implementation.
fn get_import_counts(module_ : @core.Module) -> ImportCounts {
  @core.get_import_counts(module_)
}

///|
/// Get the type index for a function (imported or local).
/// Raises ValidationError for invalid function indices.
fn get_func_type_index(
  module_ : @core.Module,
  func_idx : Int,
  import_counts : ImportCounts,
) -> Int raise ValidationError {
  let type_idx = @core.get_func_type_idx(module_, func_idx, import_counts.funcs)
  if type_idx < 0 {
    raise ValidationError::InvalidFunctionIndex(func_idx)
  }
  type_idx
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
  addr_type : @core.ValType,
  natural_align : Int,
  result_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_index(module_, import_counts, mem_idx)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, addr_type, "\{op_name} address")
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
  addr_type : @core.ValType,
  natural_align : Int,
  value_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  validate_memory_index(module_, import_counts, mem_idx)
  validate_alignment(align, natural_align)
  ctx.poly_pop_expect(module_, value_type, "\{op_name} value")
  ctx.poly_pop_expect(module_, addr_type, "\{op_name} address")
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
/// Get memory type for index. Delegates to core implementation.
/// Raises ValidationError for invalid memory indices.
fn get_memtype(
  module_ : @core.Module,
  import_counts : ImportCounts,
  mem_idx : UInt,
) -> @core.MemType raise ValidationError {
  let idx = mem_idx.reinterpret_as_int()
  match @core.get_mem_type(module_, idx, import_counts.mems) {
    Some(mem_type) => mem_type
    None => raise ValidationError::UnknownMemory(idx)
  }
}

///|
fn memory_addr_type(mem_type : @core.MemType) -> @core.ValType {
  if mem_type.memory64 {
    I64
  } else {
    I32
  }
}

///|
fn validate_load_mem(
  ctx : ValidationCtx,
  module_ : @core.Module,
  import_counts : ImportCounts,
  align : UInt,
  mem_idx : UInt,
  natural_align : Int,
  result_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  let mem_type = get_memtype(module_, import_counts, mem_idx)
  let addr_type = memory_addr_type(mem_type)
  validate_load(
    ctx, module_, import_counts, align, mem_idx, addr_type, natural_align, result_type,
    op_name,
  )
}

///|
fn validate_store_mem(
  ctx : ValidationCtx,
  module_ : @core.Module,
  import_counts : ImportCounts,
  align : UInt,
  mem_idx : UInt,
  natural_align : Int,
  value_type : @core.ValType,
  op_name : String,
) -> Unit raise ValidationError {
  let mem_type = get_memtype(module_, import_counts, mem_idx)
  let addr_type = memory_addr_type(mem_type)
  validate_store(
    ctx, module_, import_counts, align, mem_idx, addr_type, natural_align, value_type,
    op_name,
  )
}

///|
/// Get table type for index. Delegates to core implementation.
/// Raises ValidationError for invalid table indices.
fn get_table_type(
  module_ : @core.Module,
  import_counts : ImportCounts,
  table_idx : UInt,
) -> @core.TableType raise ValidationError {
  let idx = table_idx.reinterpret_as_int()
  match @core.get_table_type(module_, idx, import_counts.tables) {
    Some(table_type) => table_type
    None => raise ValidationError::UnknownTable(idx)
  }
}

///|
fn table_index_type(table_type : @core.TableType) -> @core.ValType {
  if table_type.table64 {
    I64
  } else {
    I32
  }
}

///|
/// Validate that all instructions in an expression are valid constant expression instructions
/// WebAssembly constant expressions can only contain:
/// - Constant instructions: i32.const, i64.const, f32.const, f64.const
/// - Reference instructions: ref.null, ref.func
/// - @core.Global access: global.get
/// - Arithmetic: i32.add, i32.sub, i32.mul, i64.add, i64.sub, i64.mul
/// - GC instructions: struct.new, struct.new_default, array.new, array.new_default, etc.
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
      | I64Mul
      // GC proposal constant expressions
      | StructNew(_)
      | StructNewDefault(_)
      | ArrayNew(_)
      | ArrayNewDefault(_)
      | ArrayNewFixed(_, _)
      | RefI31
      // Reference conversion instructions
      | ExternConvertAny
      | AnyConvertExtern => () // Valid constant expression instructions
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
/// Validate that a constant expression only uses immutable globals that are already defined.
/// WebAssembly constant expressions can only use global.get on immutable globals.
/// For global initializers, max_global_idx limits which globals can be referenced (no forward refs).
/// For data/elem segments, max_global_idx should be None (all globals are available).
fn validate_const_expr_globals(
  m : @core.Module,
  expr : @core.Expr,
  import_counts : ImportCounts,
  max_global_idx? : Int? = None,
) -> Unit raise ValidationError {
  let total_globals = import_counts.globals + m.globals.length()
  for instr in expr.instrs {
    match instr {
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        // Check if the global index is valid
        let max_allowed = match max_global_idx {
          Some(max) => max
          None => total_globals
        }
        if global_idx < 0 || global_idx >= max_allowed {
          raise ValidationError::UnknownGlobal(global_idx)
        }
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
/// Validate a constant expression and return its resulting type.
/// WebAssembly constant expressions may only use: i32.const, i64.const, f32.const,
/// f64.const, ref.null, ref.func, global.get (immutable), and v128.const.
/// Extended const also allows i32.add, i32.sub, i32.mul, i64.add, i64.sub, i64.mul.
fn validate_const_expr_type(
  m : @core.Module,
  expr : @core.Expr,
  import_counts : ImportCounts,
) -> @core.ValType raise ValidationError {
  let stack : Array[@core.ValType] = []
  for instr in expr.instrs {
    match instr {
      I32Const(_) => stack.push(I32)
      I64Const(_) => stack.push(I64)
      F32Const(_) => stack.push(F32)
      F64Const(_) => stack.push(F64)
      RefNull(rt) => stack.push(@core.ValType::Ref(rt, true))
      RefFunc(idx) => {
        // Validate function index exists
        let func_idx = idx.reinterpret_as_int()
        let total_funcs = import_counts.funcs + m.codes.length()
        if func_idx < 0 || func_idx >= total_funcs {
          raise ValidationError::InvalidFunctionIndex(func_idx)
        }
        stack.push(FuncRef)
      }
      GlobalGet(idx) => {
        let global_idx = idx.reinterpret_as_int()
        let total_globals = import_counts.globals + m.globals.length()
        if global_idx < 0 || global_idx >= total_globals {
          raise ValidationError::UnknownGlobal(global_idx)
        }
        // Check if global is mutable (not allowed in const expr)
        let global_type = if global_idx < import_counts.globals {
          // Imported global
          let mut import_global_idx = 0
          let mut found_type : @core.GlobalType? = None
          for imp in m.imports {
            match imp.desc {
              Global(gt) => {
                if import_global_idx == global_idx {
                  found_type = Some(gt)
                  break
                }
                import_global_idx += 1
              }
              _ => ()
            }
          }
          match found_type {
            Some(gt) => gt
            None => raise ValidationError::UnknownGlobal(global_idx)
          }
        } else {
          // Local global
          let local_idx = global_idx - import_counts.globals
          m.globals[local_idx].type_
        }
        if global_type.mutable {
          raise ValidationError::ConstantExpressionRequired(
            "global.get in constant expression must reference immutable global",
          )
        }
        stack.push(global_type.val_type)
      }
      // Extended const: arithmetic operations
      I32Add | I32Sub | I32Mul => {
        if stack.length() < 2 {
          raise ValidationError::TypeMismatch(
            "i32 binary op requires 2 operands",
          )
        }
        let b = stack.pop().unwrap()
        let a = stack.pop().unwrap()
        if a != I32 || b != I32 {
          raise ValidationError::TypeMismatch(
            "i32 binary op requires i32 operands",
          )
        }
        stack.push(I32)
      }
      I64Add | I64Sub | I64Mul => {
        if stack.length() < 2 {
          raise ValidationError::TypeMismatch(
            "i64 binary op requires 2 operands",
          )
        }
        let b = stack.pop().unwrap()
        let a = stack.pop().unwrap()
        if a != I64 || b != I64 {
          raise ValidationError::TypeMismatch(
            "i64 binary op requires i64 operands",
          )
        }
        stack.push(I64)
      }
      _ =>
        // Any other instruction is not allowed in constant expressions
        raise ValidationError::ConstantExpressionRequired(
          "instruction not allowed in constant expression",
        )
    }
  }
  // The result should be exactly one value on the stack
  if stack.length() != 1 {
    raise ValidationError::TypeMismatch(
      "constant expression must produce exactly one value",
    )
  }
  stack[0]
}

///|
/// Check if a type index refers to a function type in the module.
/// Delegates to core implementation.
fn is_func_type_index(module_ : @core.Module, type_idx : Int) -> Bool {
  @core.is_func_type_index(module_, type_idx)
}

///|
/// Check if a type index refers to a struct type in the module.
/// Delegates to core implementation.
fn is_struct_type_index(module_ : @core.Module, type_idx : Int) -> Bool {
  @core.is_struct_type_index(module_, type_idx)
}

///|
/// Check if a type index refers to an array type in the module.
/// Delegates to core implementation.
fn is_array_type_index(module_ : @core.Module, type_idx : Int) -> Bool {
  @core.is_array_type_index(module_, type_idx)
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
/// Check if type_idx1 is a declared subtype of type_idx2 via the type hierarchy
/// This searches the supertype chain in type_groups and also checks structural subtyping
fn is_type_index_subtype(
  module_ : @core.Module,
  type_idx1 : Int,
  type_idx2 : Int,
) -> Bool {
  // Same type is always a subtype of itself
  if type_idx1 == type_idx2 {
    return true
  }

  // Check if types are equivalent using rec group-aware equivalence
  if @core.gc_types_equivalent(module_, type_idx1, type_idx2) {
    return true
  }

  // Search through type_groups to find explicit supertype declarations
  // In WebAssembly GC, subtyping between defined types requires explicit declaration
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      let current_idx = subtype_def.type_idx.reinterpret_as_int()
      if current_idx == type_idx1 {
        // Check if type_idx2 is a direct supertype or equivalent to one
        for supertype in subtype_def.supertypes {
          let super_idx = supertype.reinterpret_as_int()
          if super_idx == type_idx2 ||
            @core.gc_types_equivalent(module_, super_idx, type_idx2) {
            return true
          }
          // Recursively check if the supertype is a subtype of type_idx2
          if is_type_index_subtype(module_, super_idx, type_idx2) {
            return true
          }
        }
      }
    }
  }
  // In WebAssembly GC, defined types only have subtype relationships through
  // explicit declarations, not through structural matching
  false
}

///|
/// Check if storage1 is a subtype of storage2
/// For mutable fields, types must be equal (invariant)
/// For immutable fields, types can be covariant
fn is_storage_type_subtype(
  module_ : @core.Module,
  storage1 : @core.StorageType,
  storage2 : @core.StorageType,
  mutable : Bool,
) -> Bool {
  match (storage1, storage2) {
    (Val(v1), Val(v2)) =>
      if mutable {
        // Mutable fields must have equal types
        v1 == v2
      } else {
        // Immutable fields can be covariant
        is_subtype(module_, v1, v2)
      }
    (I8, I8) | (I16, I16) => true
    _ => false
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
    // NullRef is also a subtype of any nullable typed struct/array reference
    (NullRef, Ref(TypeIndex(n), true)) =>
      is_struct_type_index(module_, n) || is_array_type_index(module_, n)
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

    // TypeIndex subtyping: check declared supertype hierarchy FIRST
    // (Must come before generic Ref pattern to match TypeIndex cases)
    // Ref(TypeIndex(n1), nullable1) <: Ref(TypeIndex(n2), nullable2)
    // if n1 is a declared subtype of n2 AND nullable1 <= nullable2
    (Ref(TypeIndex(n1), nullable1), Ref(TypeIndex(n2), nullable2)) =>
      // Non-nullable can be subtype of nullable, but not vice versa
      // If target is nullable, any source is OK; if target is non-nullable, source must be non-nullable
      (nullable2 || not(nullable1)) && is_type_index_subtype(module_, n1, n2)
    // TypeIndex -> abstract type cases MUST come before generic Ref pattern
    // Ref(TypeIndex(n), _) is a typed function reference, compatible with FuncRef
    // only if type n is actually a function type
    (Ref(TypeIndex(n), _), FuncRef) => is_func_type_index(module_, n)
    // Typed function reference is also compatible with (ref func) and (ref null func)
    (Ref(TypeIndex(n), false), Ref(Func, false)) =>
      is_func_type_index(module_, n)
    (Ref(TypeIndex(n), _), Ref(Func, true)) => is_func_type_index(module_, n)
    // Typed struct/array references are compatible with structref/arrayref
    (Ref(TypeIndex(n), _), StructRef) => is_struct_type_index(module_, n)
    (Ref(TypeIndex(n), _), ArrayRef) => is_array_type_index(module_, n)
    (Ref(TypeIndex(n), _), EqRef) =>
      is_struct_type_index(module_, n) || is_array_type_index(module_, n)
    (Ref(TypeIndex(n), false), Ref(Struct, false)) =>
      is_struct_type_index(module_, n)
    (Ref(TypeIndex(n), _), Ref(Struct, true)) =>
      is_struct_type_index(module_, n)
    (Ref(TypeIndex(n), false), Ref(Array, false)) =>
      is_array_type_index(module_, n)
    (Ref(TypeIndex(n), _), Ref(Array, true)) => is_array_type_index(module_, n)
    // Typed references: Ref(T, nullable)
    // Non-nullable is subtype of nullable for same heap type
    // (For non-TypeIndex heap types like Func, Extern, etc.)
    (Ref(ht1, false), Ref(ht2, true)) => ht1 == ht2
    // Ref(Extern, _) is compatible with ExternRef (nullable externref)
    (Ref(Extern, _), ExternRef) => true
    // Ref(Func, _) is compatible with FuncRef (nullable funcref)
    (Ref(Func, _), FuncRef) => true
    // Ref(I31, _) is compatible with i31ref
    (Ref(I31, _), I31Ref) => true
    // Ref(Struct, _) is compatible with structref
    (Ref(Struct, _), StructRef) => true
    // Ref(Array, _) is compatible with arrayref
    (Ref(Array, _), ArrayRef) => true
    // Ref(Eq, _) is compatible with eqref
    (Ref(Eq, _), EqRef) => true
    // i31ref/structref/arrayref are eqref
    (Ref(I31, _), EqRef) | (Ref(Struct, _), EqRef) | (Ref(Array, _), EqRef) =>
      true
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
    // I31/Struct/Array/Eq are subtypes of Any (for Ref types)
    (Ref(I31, nullable1), Ref(Any, nullable2)) => nullable2 || not(nullable1)
    (Ref(Struct, nullable1), Ref(Any, nullable2)) => nullable2 || not(nullable1)
    (Ref(Array, nullable1), Ref(Any, nullable2)) => nullable2 || not(nullable1)
    (Ref(Eq, nullable1), Ref(Any, nullable2)) => nullable2 || not(nullable1)
    // TypeIndex is subtype of Ref(Any, _) if it's a struct or array type
    (Ref(TypeIndex(n), nullable1), Ref(Any, nullable2)) =>
      (nullable2 || not(nullable1)) &&
      (is_struct_type_index(module_, n) || is_array_type_index(module_, n))

    // Non-reference types are not related by subtyping
    _ => false
  }
}

///|
/// Collect declared function indices from a module.
/// A function is "declared" if it appears in:
/// - An element segment (active or declarative)
/// - An export
/// - A global initializer containing ref.func
fn collect_declared_funcs(m : @core.Module) -> Set[Int] {
  let declared : Set[Int] = Set::new()

  // Collect from element segments
  for elem in m.elems {
    for init_expr in elem.init {
      for instr in init_expr.instrs {
        match instr {
          RefFunc(idx) => declared.add(idx.reinterpret_as_int())
          _ => ()
        }
      }
    }
  }

  // Collect from exports
  for exp in m.exports {
    match exp.desc {
      Func(idx) => declared.add(idx.reinterpret_as_int())
      _ => ()
    }
  }

  // Collect from global initializers
  for global in m.globals {
    for instr in global.init.instrs {
      match instr {
        RefFunc(idx) => declared.add(idx.reinterpret_as_int())
        _ => ()
      }
    }
  }

  // Collect from table initializers
  for table in m.tables {
    match table.init {
      Some(init_expr) =>
        for instr in init_expr.instrs {
          match instr {
            RefFunc(idx) => declared.add(idx.reinterpret_as_int())
            _ => ()
          }
        }
      None => ()
    }
  }
  declared
}

///|
/// Validate an element init constant expression and return its resulting type
/// This handles all valid constant expressions including GC instructions
fn validate_elem_init_const_expr(
  m : @core.Module,
  expr : @core.Expr,
  import_counts : ImportCounts,
  elem_nullable : Bool,
) -> @core.ValType raise ValidationError {
  // First validate all instructions are valid in constant expressions
  validate_const_expr_instructions(expr)

  // Stack-based type checking for the constant expression
  let stack : Array[@core.ValType] = []
  for instr in expr.instrs {
    match instr {
      I32Const(_) => stack.push(I32)
      I64Const(_) => stack.push(I64)
      F32Const(_) => stack.push(F32)
      F64Const(_) => stack.push(F64)
      RefNull(ref_type) => {
        guard elem_nullable else {
          raise ValidationError::TypeMismatch(
            "non-nullable elem cannot be initialized with ref.null",
          )
        }
        stack.push(@core.ValType::Ref(ref_type, true))
      }
      RefFunc(func_idx) => {
        let idx = func_idx.reinterpret_as_int()
        let total_funcs = import_counts.funcs + m.funcs.length()
        if idx < 0 || idx >= total_funcs {
          raise ValidationError::InvalidFunctionIndex(idx)
        }
        // Get the actual function type index for this function
        let type_idx = get_func_type_index(m, idx, import_counts)
        // RefFunc produces a non-null reference to the specific function type
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx), false),
        )
      }
      GlobalGet(global_idx) => {
        let gidx = global_idx.reinterpret_as_int()
        let (gtype, mutable) = get_global_type_and_mutable(
          m, gidx, import_counts,
        )
        guard not(mutable) else {
          raise ValidationError::ConstantExpressionRequired(
            "elem init global.get must reference immutable global",
          )
        }
        stack.push(gtype)
      }
      RefI31 => {
        // Pop i32, push i31ref
        guard stack.length() > 0 else {
          raise ValidationError::TypeMismatch("ref.i31 requires i32 on stack")
        }
        let _ = stack.unsafe_pop()
        stack.push(@core.ValType::Ref(@core.RefType::I31, false))
      }
      StructNew(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        if type_idx_int < 0 || type_idx_int >= m.types.length() {
          raise ValidationError::UnknownType(type_idx_int)
        }
        let num_fields = match m.types[type_idx_int] {
          Struct(s) => s.fields.length()
          _ =>
            raise ValidationError::TypeMismatch(
              "struct.new requires struct type",
            )
        }
        // Pop fields from stack
        for i = 0; i < num_fields; i = i + 1 {
          guard stack.length() > 0 else {
            raise ValidationError::TypeMismatch(
              "struct.new: not enough values on stack",
            )
          }
          let _ = stack.unsafe_pop()

        }
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx_int), false),
        )
      }
      StructNewDefault(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        if type_idx_int < 0 || type_idx_int >= m.types.length() {
          raise ValidationError::UnknownType(type_idx_int)
        }
        match m.types[type_idx_int] {
          Struct(_) => ()
          _ =>
            raise ValidationError::TypeMismatch(
              "struct.new_default requires struct type",
            )
        }
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx_int), false),
        )
      }
      ArrayNew(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        if type_idx_int < 0 || type_idx_int >= m.types.length() {
          raise ValidationError::UnknownType(type_idx_int)
        }
        match m.types[type_idx_int] {
          Array(_) => ()
          _ =>
            raise ValidationError::TypeMismatch("array.new requires array type")
        }
        // Pop length (i32) and init value
        guard stack.length() >= 2 else {
          raise ValidationError::TypeMismatch(
            "array.new requires init value and length",
          )
        }
        let _ = stack.unsafe_pop() // length
        let _ = stack.unsafe_pop() // init value
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx_int), false),
        )
      }
      ArrayNewDefault(type_idx) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        if type_idx_int < 0 || type_idx_int >= m.types.length() {
          raise ValidationError::UnknownType(type_idx_int)
        }
        match m.types[type_idx_int] {
          Array(_) => ()
          _ =>
            raise ValidationError::TypeMismatch(
              "array.new_default requires array type",
            )
        }
        // Pop length (i32)
        guard stack.length() >= 1 else {
          raise ValidationError::TypeMismatch(
            "array.new_default requires length",
          )
        }
        let _ = stack.unsafe_pop()
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx_int), false),
        )
      }
      ArrayNewFixed(type_idx, len) => {
        let type_idx_int = type_idx.reinterpret_as_int()
        let length = len.reinterpret_as_int()
        if type_idx_int < 0 || type_idx_int >= m.types.length() {
          raise ValidationError::UnknownType(type_idx_int)
        }
        match m.types[type_idx_int] {
          Array(_) => ()
          _ =>
            raise ValidationError::TypeMismatch(
              "array.new_fixed requires array type",
            )
        }
        // Pop 'length' elements from stack
        guard stack.length() >= length else {
          raise ValidationError::TypeMismatch(
            "array.new_fixed: not enough values on stack",
          )
        }
        for i = 0; i < length; i = i + 1 {
          let _ = stack.unsafe_pop()

        }
        stack.push(
          @core.ValType::Ref(@core.RefType::TypeIndex(type_idx_int), false),
        )
      }
      I32Add | I32Sub | I32Mul => {
        guard stack.length() >= 2 else {
          raise ValidationError::TypeMismatch(
            "i32 arithmetic requires 2 operands",
          )
        }
        let _ = stack.unsafe_pop()
        let _ = stack.unsafe_pop()
        stack.push(I32)
      }
      I64Add | I64Sub | I64Mul => {
        guard stack.length() >= 2 else {
          raise ValidationError::TypeMismatch(
            "i64 arithmetic requires 2 operands",
          )
        }
        let _ = stack.unsafe_pop()
        let _ = stack.unsafe_pop()
        stack.push(I64)
      }
      ExternConvertAny => {
        guard stack.length() >= 1 else {
          raise ValidationError::TypeMismatch(
            "extern.convert_any requires operand",
          )
        }
        let _ = stack.unsafe_pop()
        stack.push(ExternRef)
      }
      AnyConvertExtern => {
        guard stack.length() >= 1 else {
          raise ValidationError::TypeMismatch(
            "any.convert_extern requires operand",
          )
        }
        let _ = stack.unsafe_pop()
        stack.push(AnyRef)
      }
      _ =>
        raise ValidationError::ConstantExpressionRequired(
          "invalid instruction in elem init: \{instr}",
        )
    }
  }
  // Expression should produce exactly one value
  guard stack.length() == 1 else {
    raise ValidationError::TypeMismatch(
      "elem init expression must produce exactly one value, got \{stack.length()}",
    )
  }
  stack[0]
}
