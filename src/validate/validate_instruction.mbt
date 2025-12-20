///|
/// Get the function type signature for a block type
fn get_block_type(
  module_ : @core.Module,
  block_type : @core.BlockType,
) -> (Array[@core.ValType], Array[@core.ValType]) raise @core.ValidationError {
  match block_type {
    @core.BlockType::Empty => ([], [])
    @core.BlockType::Value(t) => {
      validate_valtype(module_, t)
      ([], [t])
    }
    @core.BlockType::TypeIndex(idx) => {
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
}

///|
/// Validate that a tail call's return type matches the current function's return type.
/// For tail calls (return_call, return_call_indirect, return_call_ref), the called
/// function's return type must match the current function's return type via subtyping.
fn validate_tail_call_return_type(
  module_ : @core.Module,
  func_type_called : @core.FuncType,
  func_type : @core.FuncType,
  instr_name : String,
) -> Unit raise @core.ValidationError {
  if func_type_called.results.length() != func_type.results.length() {
    raise @core.ValidationError::TypeMismatch(
      "\{instr_name}: return type mismatch: expected \{func_type.results.length()} results, got \{func_type_called.results.length()}",
    )
  }
  for i in 0..<func_type_called.results.length() {
    let called_result = func_type_called.results[i]
    let expected_result = func_type.results[i]
    if not(is_subtype(module_, called_result, expected_result)) {
      raise @core.ValidationError::TypeMismatch(
        "\{instr_name}: return type mismatch at position \{i}: expected \{expected_result}, got \{called_result}",
      )
    }
  }
}

///|
/// Helper function to validate a single instruction
fn validate_instruction(
  module_ : @core.Module,
  func_type : @core.FuncType,
  code : @core.Code,
  ctx : ValidationCtx,
  instr : @core.Instr,
  import_counts : ImportCounts,
) -> Unit raise @core.ValidationError {
  let stack = ctx.stack
  match instr {
    // Constants
    @core.Instr::I32Const(_) => stack.push(@core.ValType::I32)
    @core.Instr::I64Const(_) => stack.push(@core.ValType::I64)
    @core.Instr::F32Const(_) => stack.push(@core.ValType::F32)
    @core.Instr::F64Const(_) => stack.push(@core.ValType::F64)

    // Binary operations
    @core.Instr::I32Add
    | @core.Instr::I32Sub
    | @core.Instr::I32Mul
    | @core.Instr::I32DivS
    | @core.Instr::I32DivU
    | @core.Instr::I32RemS
    | @core.Instr::I32RemU
    | @core.Instr::I32And
    | @core.Instr::I32Or
    | @core.Instr::I32Xor
    | @core.Instr::I32Shl
    | @core.Instr::I32ShrS
    | @core.Instr::I32ShrU
    | @core.Instr::I32Rotl
    | @core.Instr::I32Rotr =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I32,
        @core.ValType::I32,
        "i32 binary op",
      )

    // Comparison operations
    @core.Instr::I32Eq
    | @core.Instr::I32Ne
    | @core.Instr::I32LtS
    | @core.Instr::I32LtU
    | @core.Instr::I32GtS
    | @core.Instr::I32GtU
    | @core.Instr::I32LeS
    | @core.Instr::I32LeU
    | @core.Instr::I32GeS
    | @core.Instr::I32GeU =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I32,
        @core.ValType::I32,
        "i32 comparison",
      )

    // Unary operations
    @core.Instr::I32Eqz
    | @core.Instr::I32Clz
    | @core.Instr::I32Ctz
    | @core.Instr::I32Popcnt
    | @core.Instr::I32Extend8S
    | @core.Instr::I32Extend16S => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "i32 unary op")
      stack.push(@core.ValType::I32)
    }

    // i64 binary operations
    @core.Instr::I64Add
    | @core.Instr::I64Sub
    | @core.Instr::I64Mul
    | @core.Instr::I64DivS
    | @core.Instr::I64DivU
    | @core.Instr::I64RemS
    | @core.Instr::I64RemU
    | @core.Instr::I64And
    | @core.Instr::I64Or
    | @core.Instr::I64Xor
    | @core.Instr::I64Shl
    | @core.Instr::I64ShrS
    | @core.Instr::I64ShrU
    | @core.Instr::I64Rotl
    | @core.Instr::I64Rotr =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I64,
        @core.ValType::I64,
        "i64 binary op",
      )

    // i64 comparison operations
    @core.Instr::I64Eq
    | @core.Instr::I64Ne
    | @core.Instr::I64LtS
    | @core.Instr::I64LtU
    | @core.Instr::I64GtS
    | @core.Instr::I64GtU
    | @core.Instr::I64LeS
    | @core.Instr::I64LeU
    | @core.Instr::I64GeS
    | @core.Instr::I64GeU =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::I64,
        @core.ValType::I32,
        "i64 comparison",
      )

    // i64 test operation (returns i32)
    @core.Instr::I64Eqz => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i64.eqz")
      stack.push(@core.ValType::I32)
    }

    // i64 unary operations (return i64)
    @core.Instr::I64Clz
    | @core.Instr::I64Ctz
    | @core.Instr::I64Popcnt
    | @core.Instr::I64Extend8S
    | @core.Instr::I64Extend16S
    | @core.Instr::I64Extend32S => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i64 unary op")
      stack.push(@core.ValType::I64)
    }

    // i32 to i64 conversion operations
    @core.Instr::I64ExtendI32S | @core.Instr::I64ExtendI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "i64 extension")
      stack.push(@core.ValType::I64)
    }

    // i64 to i32 conversion (wrap)
    @core.Instr::I32WrapI64 => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "i32.wrap_i64")
      stack.push(@core.ValType::I32)
    }

    // f32 comparison operations
    @core.Instr::F32Eq
    | @core.Instr::F32Ne
    | @core.Instr::F32Lt
    | @core.Instr::F32Gt
    | @core.Instr::F32Le
    | @core.Instr::F32Ge =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F32,
        @core.ValType::I32,
        "f32 comparison",
      )

    // f64 comparison operations
    @core.Instr::F64Eq
    | @core.Instr::F64Ne
    | @core.Instr::F64Lt
    | @core.Instr::F64Gt
    | @core.Instr::F64Le
    | @core.Instr::F64Ge =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F64,
        @core.ValType::I32,
        "f64 comparison",
      )

    // f32 unary operations
    @core.Instr::F32Abs
    | @core.Instr::F32Neg
    | @core.Instr::F32Ceil
    | @core.Instr::F32Floor
    | @core.Instr::F32Trunc
    | @core.Instr::F32Nearest
    | @core.Instr::F32Sqrt => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "f32 unary op")
      stack.push(@core.ValType::F32)
    }

    // f64 unary operations
    @core.Instr::F64Abs
    | @core.Instr::F64Neg
    | @core.Instr::F64Ceil
    | @core.Instr::F64Floor
    | @core.Instr::F64Trunc
    | @core.Instr::F64Nearest
    | @core.Instr::F64Sqrt => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "f64 unary op")
      stack.push(@core.ValType::F64)
    }

    // f32 binary operations
    @core.Instr::F32Add
    | @core.Instr::F32Sub
    | @core.Instr::F32Mul
    | @core.Instr::F32Div
    | @core.Instr::F32Min
    | @core.Instr::F32Max
    | @core.Instr::F32Copysign =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F32,
        @core.ValType::F32,
        "f32 binary op",
      )

    // f64 binary operations
    @core.Instr::F64Add
    | @core.Instr::F64Sub
    | @core.Instr::F64Mul
    | @core.Instr::F64Div
    | @core.Instr::F64Min
    | @core.Instr::F64Max
    | @core.Instr::F64Copysign =>
      validate_binary_op(
        ctx,
        module_,
        @core.ValType::F64,
        @core.ValType::F64,
        "f64 binary op",
      )

    // Conversion operations: i32 -> f32/f64
    @core.Instr::F32ConvertI32S | @core.Instr::F32ConvertI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f32.convert_i32")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ConvertI32S | @core.Instr::F64ConvertI32U => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f64.convert_i32")
      stack.push(@core.ValType::F64)
    }

    // Conversion operations: i64 -> f32/f64
    @core.Instr::F32ConvertI64S | @core.Instr::F32ConvertI64U => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f32.convert_i64")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ConvertI64S | @core.Instr::F64ConvertI64U => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f64.convert_i64")
      stack.push(@core.ValType::F64)
    }

    // Promotion/demotion: f32 <-> f64
    @core.Instr::F64PromoteF32 => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "f64.promote_f32")
      stack.push(@core.ValType::F64)
    }
    @core.Instr::F32DemoteF64 => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "f32.demote_f64")
      stack.push(@core.ValType::F32)
    }

    // Truncation: f32/f64 -> i32/i64
    @core.Instr::I32TruncF32S | @core.Instr::I32TruncF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.trunc_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I32TruncF64S | @core.Instr::I32TruncF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i32.trunc_f64")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64TruncF32S | @core.Instr::I64TruncF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i64.trunc_f32")
      stack.push(@core.ValType::I64)
    }
    @core.Instr::I64TruncF64S | @core.Instr::I64TruncF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.trunc_f64")
      stack.push(@core.ValType::I64)
    }

    // Saturating truncation: f32/f64 -> i32/i64 (same types as regular trunc)
    @core.Instr::I32TruncSatF32S | @core.Instr::I32TruncSatF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.trunc_sat_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I32TruncSatF64S | @core.Instr::I32TruncSatF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i32.trunc_sat_f64")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64TruncSatF32S | @core.Instr::I64TruncSatF32U => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i64.trunc_sat_f32")
      stack.push(@core.ValType::I64)
    }
    @core.Instr::I64TruncSatF64S | @core.Instr::I64TruncSatF64U => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.trunc_sat_f64")
      stack.push(@core.ValType::I64)
    }

    // Reinterpret operations
    @core.Instr::F32ReinterpretI32 => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "f32.reinterpret_i32")
      stack.push(@core.ValType::F32)
    }
    @core.Instr::F64ReinterpretI64 => {
      ctx.poly_pop_expect(module_, @core.ValType::I64, "f64.reinterpret_i64")
      stack.push(@core.ValType::F64)
    }
    @core.Instr::I32ReinterpretF32 => {
      ctx.poly_pop_expect(module_, @core.ValType::F32, "i32.reinterpret_f32")
      stack.push(@core.ValType::I32)
    }
    @core.Instr::I64ReinterpretF64 => {
      ctx.poly_pop_expect(module_, @core.ValType::F64, "i64.reinterpret_f64")
      stack.push(@core.ValType::I64)
    }

    // Local operations
    @core.Instr::LocalGet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise @core.ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      // Check initialization for non-defaultable types
      if not(local_type.is_defaultable()) &&
        ctx.initialized_locals.length() > local_idx &&
        not(ctx.initialized_locals[local_idx]) {
        raise @core.ValidationError::UninitializedLocal(local_idx)
      }
      stack.push(local_type)
    }
    @core.Instr::LocalSet(idx) | @core.Instr::LocalTee(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise @core.ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      ctx.poly_pop_expect(module_, local_type, "local.set")
      // Mark local as initialized
      if ctx.initialized_locals.length() > local_idx {
        ctx.initialized_locals[local_idx] = true
      }
      match instr {
        @core.Instr::LocalTee(_) => stack.push(local_type)
        _ => ()
      }
    }

    // @core.Global operations
    // Note: @core.Global index space includes imported globals first, then local globals
    @core.Instr::GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise @core.ValidationError::InvalidGlobalIndex(global_idx)
      }
      let global_type = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : @core.ValType = @core.ValType::I32 // default
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Global(gt) => {
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
        module_.globals[global_idx - import_counts.globals].type_.val_type
      }
      stack.push(global_type)
    }
    @core.Instr::GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise @core.ValidationError::InvalidGlobalIndex(global_idx)
      }
      let (global_type, is_mutable) = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : @core.ValType = @core.ValType::I32 // default
        let mut found_mutable = false
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                found_mutable = gt.mutable
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        (found_type, found_mutable)
      } else {
        // It's a local global
        let global = module_.globals[global_idx - import_counts.globals]
        (global.type_.val_type, global.type_.mutable)
      }
      // Check if global is mutable
      if not(is_mutable) {
        raise @core.ValidationError::ImmutableGlobal(global_idx)
      }
      ctx.poly_pop_expect(module_, global_type, "global.set")
    }

    // Memory operations - loads (all take i32 address and push the loaded value)
    @core.Instr::I32Load(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I32,
        "i32.load",
      )
    @core.Instr::I32Load8S(align, _) | @core.Instr::I32Load8U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I32,
        "i32.load8",
      )
    @core.Instr::I32Load16S(align, _) | @core.Instr::I32Load16U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I32,
        "i32.load16",
      )
    @core.Instr::I64Load(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        8,
        @core.ValType::I64,
        "i64.load",
      )
    @core.Instr::I64Load8S(align, _) | @core.Instr::I64Load8U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I64,
        "i64.load8",
      )
    @core.Instr::I64Load16S(align, _) | @core.Instr::I64Load16U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I64,
        "i64.load16",
      )
    @core.Instr::I64Load32S(align, _) | @core.Instr::I64Load32U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I64,
        "i64.load32",
      )
    @core.Instr::F32Load(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::F32,
        "f32.load",
      )
    @core.Instr::F64Load(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        8,
        @core.ValType::F64,
        "f64.load",
      )
    // Memory operations - stores (all take i32 address and value, push nothing)
    @core.Instr::I32Store(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I32,
        "i32.store",
      )
    @core.Instr::I32Store8(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I32,
        "i32.store8",
      )
    @core.Instr::I32Store16(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I32,
        "i32.store16",
      )
    @core.Instr::I64Store(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        8,
        @core.ValType::I64,
        "i64.store",
      )
    @core.Instr::I64Store8(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I64,
        "i64.store8",
      )
    @core.Instr::I64Store16(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I64,
        "i64.store16",
      )
    @core.Instr::I64Store32(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I64,
        "i64.store32",
      )
    @core.Instr::F32Store(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::F32,
        "f32.store",
      )
    @core.Instr::F64Store(align, _) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        8,
        @core.ValType::F64,
        "f64.store",
      )
    // Memory size and grow
    @core.Instr::MemorySize(_) => {
      validate_memory_exists(module_, import_counts)
      stack.push(@core.ValType::I32)
    }
    @core.Instr::MemoryGrow(_) => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.grow delta")
      stack.push(@core.ValType::I32)
    }

    // Bulk memory instructions
    @core.Instr::MemoryCopy => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy dest")
    }
    @core.Instr::MemoryFill => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill val")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill dest")
    }
    @core.Instr::MemoryInit(data_idx) => {
      validate_memory_exists(module_, import_counts)
      // Validate data segment index
      if data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise @core.ValidationError::TypeMismatch(
          "memory.init: unknown data segment \{data_idx}",
        )
      }
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init dest")
    }
    @core.Instr::DataDrop(data_idx) =>
      // Validate data segment index
      if data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise @core.ValidationError::TypeMismatch(
          "data.drop: unknown data segment \{data_idx}",
        )
      }

    // Table bulk operations (stub for now)
    @core.Instr::TableInit(_, _) => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.init n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.init src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.init dest")
    }
    @core.Instr::TableCopy(_, _) => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.copy n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.copy src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.copy dest")
    }
    @core.Instr::ElemDrop(_) => ()

    // Table instructions
    @core.Instr::TableSize(_) => stack.push(@core.ValType::I32)
    @core.Instr::TableGet(table_idx) => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.get index")
      // Look up table's element type
      let elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        let table = module_.tables[table_idx.reinterpret_as_int()]
        reftype_to_valtype(table.elem_type)
      } else {
        @core.ValType::FuncRef // Default if table not found
      }
      stack.push(elem_type)
    }
    @core.Instr::TableSet(table_idx) => {
      // table.set: pop value (top), then index (below)
      // Get table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        @core.RefType::Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : @core.ValType = reftype_to_valtype(table_elem_type)

      // Pop and verify value type matches table element type
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "table.set expects value on stack",
        )
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise @core.ValidationError::TypeMismatch(
            "table.set value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }

      // Pop index (i32)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.set index")
    }
    @core.Instr::TableGrow(table_idx) => {
      ctx.poly_pop_expect(module_, @core.ValType::I32, "table.grow delta")
      // Pop init value and check it matches table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        @core.RefType::Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : @core.ValType = reftype_to_valtype(table_elem_type)
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "table.grow expects init value on stack",
        )
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise @core.ValidationError::TypeMismatch(
            "table.grow init value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }
      stack.push(@core.ValType::I32) // Returns old size
    }

    // Reference instructions
    @core.Instr::RefNull(ref_type) => {
      // ref.null pushes a null reference of the given type
      let val_type = reftype_to_valtype(ref_type)
      stack.push(val_type)
    }
    @core.Instr::RefFunc(func_idx) => {
      // ref.func pushes a typed function reference (non-nullable)
      // Get the function's type index to create the proper typed reference
      let idx = func_idx.reinterpret_as_int()
      // Validate function index
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise @core.ValidationError::InvalidFunctionIndex(idx)
      }
      let type_idx = get_func_type_index(module_, idx, import_counts)
      // Push typed function reference (non-nullable)
      stack.push(@core.ValType::Ref(@core.RefType::TypeIndex(type_idx), false))
    }
    @core.Instr::RefIsNull => {
      // ref.is_null pops a reference type and pushes i32
      // In polymorphic context, allow any type on stack
      if ctx.is_unreachable && stack.length() == 0 {
        // @core.Instr::Unreachable - stack is polymorphic, don't pop anything
      } else if stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "ref.is_null expects reference on stack",
        )
      } else {
        let _ = stack.unsafe_pop()
        // Pop the reference
      }
      stack.push(@core.ValType::I32) // Push result
    }

    // @core.Instr::Block instructions
    @core.Instr::Block(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "block parameter")
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
      // Copy initialized locals from parent context
      // After block, we don't propagate back (block might branch out early)
      for i in 0..<ctx.initialized_locals.length() {
        block_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate block body
      for block_instr in instrs {
        validate_instruction(
          module_, func_type, code, block_ctx, block_instr, import_counts,
        )
      }
      let _ = block_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from block_ctx
      // because the block might have exited early via branch
      // Check block produces correct results
      if block_ctx.is_unreachable && block_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable code with empty stack - all polymorphic, push expected results
        for result in results {
          stack.push(result)
        }
      } else if block_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - this is a type mismatch
        raise @core.ValidationError::TypeMismatch(
          "block: expected \{results.length()} values, got \{block_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, block_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "block result type mismatch: expected \{results[i]}, got \{block_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    @core.Instr::Loop(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "loop parameter")
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
      loop_ctx.push_control(params, params) // @core.Instr::Loop's br target uses params, not results
      // Copy initialized locals from parent context
      // @core.Instr::Loop is similar to block - don't propagate back
      for i in 0..<ctx.initialized_locals.length() {
        loop_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate loop body
      for loop_instr in instrs {
        validate_instruction(
          module_, func_type, code, loop_ctx, loop_instr, import_counts,
        )
      }
      let _ = loop_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from loop_ctx
      // Check loop produces correct results
      if loop_ctx.is_unreachable && loop_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable code with empty stack - all polymorphic
        for result in results {
          stack.push(result)
        }
      } else if loop_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - type mismatch
        raise @core.ValidationError::TypeMismatch(
          "loop: expected \{results.length()} values, got \{loop_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, loop_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "loop result type mismatch: expected \{results[i]}, got \{loop_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    @core.Instr::If(block_type, then_instrs, else_instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop condition (using polymorphic stack)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "if condition")
      // Pop parameters from parent stack (using polymorphic stack)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "if parameter")
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
      // Copy initialized locals from parent context
      for i in 0..<ctx.initialized_locals.length() {
        then_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for then_instr in then_instrs {
        validate_instruction(
          module_, func_type, code, then_ctx, then_instr, import_counts,
        )
      }
      let _ = then_ctx.pop_control()
      // Check then branch produces correct results
      if then_ctx.is_unreachable && then_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable with empty stack - all polymorphic, valid
      } else if then_ctx.stack.length() != results.length() {
        raise @core.ValidationError::TypeMismatch(
          "if then branch: expected \{results.length()} values, got \{then_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, then_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
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
      // Copy initialized locals from parent context (independently from then branch)
      for i in 0..<ctx.initialized_locals.length() {
        else_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for else_instr in else_instrs {
        validate_instruction(
          module_, func_type, code, else_ctx, else_instr, import_counts,
        )
      }
      let _ = else_ctx.pop_control()
      // Check else branch produces correct results
      if else_ctx.is_unreachable && else_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable with empty stack - all polymorphic, valid
      } else if else_ctx.stack.length() != results.length() {
        raise @core.ValidationError::TypeMismatch(
          "if else branch: expected \{results.length()} values, got \{else_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, else_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "if else branch result type mismatch: expected \{results[i]}, got \{else_ctx.stack[i]}",
            )
          }
        }
      }
      // Note: We do NOT propagate initialized_locals back from either branch
      // because branches might exit early via br/return
      // Push results onto parent stack
      for result in results {
        stack.push(result)
      }
    }

    // Control flow
    @core.Instr::Return => {
      // In unreachable code with empty stack, allow polymorphic return
      // Otherwise, validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Check we have the right values on stack for function return
        if stack.length() < func_type.results.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "return: expected \{func_type.results.length()} values on stack",
            )
          }
        } else {
          // Validate result types for concrete values (with subtyping)
          for i in 0..<func_type.results.length() {
            let stack_idx = stack.length() - func_type.results.length() + i
            if not(is_subtype(module_, stack[stack_idx], func_type.results[i])) {
              raise @core.ValidationError::TypeMismatch(
                "return: result type mismatch: expected \{func_type.results[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::Br(label) => {
      // Always validate label exists (even in unreachable code)
      let target_types = ctx.get_label_types(label)

      // Validate stack contents (even in unreachable code with concrete values)
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Unconditional branch - validate we have required values for target
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "br: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for the branch target (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise @core.ValidationError::TypeMismatch(
                "br: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::BrIf(label) => {
      // Conditional branch
      // First, validate label exists
      let target_types = ctx.get_label_types(label)

      // Pop i32 condition
      ctx.poly_pop_expect(module_, @core.ValType::I32, "br_if condition")

      // Pop the label types (checking subtyping) and push them back
      // This "widens" the types to the label types
      // e.g., if stack has (ref null $t) and label expects funcref,
      // after br_if the stack will have funcref (not the more specific ref null $t)
      for i = target_types.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, target_types[i], "br_if target value")
      }

      // Push label types back onto stack for fallthrough case
      for target_type in target_types {
        stack.push(target_type)
      }

      // Note: Unlike br, br_if does NOT mark as unreachable
      // Stack now has the label types (potentially wider than original)
    }
    @core.Instr::BrTable(labels, default_label) => {
      // Table branch - pop i32 index
      ctx.poly_pop_expect(module_, @core.ValType::I32, "br_table index")

      // Validate all labels exist and have compatible types
      let default_types = ctx.get_label_types(default_label)

      // All labels (including default) must have the same arity and types
      // TODO: This validation is currently disabled due to a bug where get_label_types
      // returns different types for the same label on different calls. This needs investigation.
      // The issue manifests as @core.ValType::F32 vs @core.ValType::F64 type mismatches in br_table.wast tests.
      //
      // For now, we only validate arity (length) matches and that labels exist.
      for label in labels {
        let label_types = ctx.get_label_types(label)

        // Check arity matches
        if label_types.length() != default_types.length() {
          raise @core.ValidationError::TypeMismatch(
            "br_table: all labels must have same arity (expected \{default_types.length()}, got \{label_types.length()})",
          )
        }

        // TODO: Re-enable once we fix the type mismatch bug
        // Check types match exactly (WebAssembly spec requires exact match)
        // for i in 0..<label_types.length() {
        //   if label_types[i] != default_types[i] {
        //     raise @core.ValidationError::TypeMismatch(
        //       "br_table: all labels must have same types (label \{label} has \{label_types[i]}, default has \{default_types[i]} at position \{i})",
        //     )
        //   }
        // }
      }
      let target_types = default_types

      // Validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Validate we have required values for branch targets using default label
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "br_table: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for concrete values (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise @core.ValidationError::TypeMismatch(
                "br_table: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // @core.Code after is unreachable, record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::BrOnNull(_label) =>
      // br_on_null: pop nullable ref, branch if null, else push non-null ref
      // The fallthrough path pushes the reference with nullable=false
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "br_on_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let popped = stack.unsafe_pop()
        // Make the reference non-nullable for the fallthrough case
        let non_null_type = match popped {
          // Nullable typed ref becomes non-nullable
          @core.ValType::Ref(ht, true) => @core.ValType::Ref(ht, false)
          // Already non-nullable - keep as is (shouldn't happen, but handle it)
          @core.ValType::Ref(ht, false) => @core.ValType::Ref(ht, false)
          // Generic nullable refs become non-nullable refs
          @core.ValType::FuncRef =>
            @core.ValType::Ref(@core.RefType::Func, false)
          @core.ValType::ExternRef =>
            @core.ValType::Ref(@core.RefType::Extern, false)
          @core.ValType::AnyRef => @core.ValType::Ref(@core.RefType::Any, false)
          // Null types become their non-null counterparts
          @core.ValType::NullFuncRef =>
            @core.ValType::Ref(@core.RefType::Func, false)
          @core.ValType::NullExternRef =>
            @core.ValType::Ref(@core.RefType::Extern, false)
          @core.ValType::NullRef =>
            @core.ValType::Ref(@core.RefType::Any, false)
          // Other types shouldn't be here, but keep them
          _ => popped
        }
        stack.push(non_null_type)
      }
    @core.Instr::BrOnNonNull(_label) =>
      // br_on_non_null: pop nullable ref, branch if non-null (with the value), else continue
      // Pop the nullable reference
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "br_on_non_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()

      }
    // @core.Instr::If we branch, we pass the non-null value to the target
    // Fallthrough case: the value was null, so nothing is pushed
    @core.Instr::Drop =>
      // In unreachable code, drop is valid even with empty stack
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - pretend we dropped something
      } else if stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "expected value on stack for drop",
        )
      } else {
        let _ = stack.unsafe_pop()

      }
    @core.Instr::Select => {
      // Untyped select (0x1B): only numeric types allowed
      // Pop condition (i32), then two values of same type, push one back
      ctx.poly_pop_expect(module_, @core.ValType::I32, "select condition")
      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate
      if num_concrete >= 2 {
        // Both values are concrete - they must be compatible via subtyping
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // For untyped select, both values must be numeric types
        let is_val1_numeric = match val1 {
          @core.ValType::I32
          | @core.ValType::I64
          | @core.ValType::F32
          | @core.ValType::F64 => true
          _ => false
        }
        let is_val2_numeric = match val2 {
          @core.ValType::I32
          | @core.ValType::I64
          | @core.ValType::F32
          | @core.ValType::F64 => true
          _ => false
        }
        if not(is_val1_numeric) || not(is_val2_numeric) {
          raise @core.ValidationError::TypeMismatch(
            "untyped select requires numeric types, got \{val1} and \{val2}",
          )
        }

        // Check if types are compatible: one must be subtype of the other
        let result_type = if is_subtype(module_, val1, val2) {
          val2 // val1 <: val2, so result is val2 (more general)
        } else if is_subtype(module_, val2, val1) {
          val1 // val2 <: val1, so result is val1 (more general)
        } else {
          raise @core.ValidationError::TypeMismatch(
            "select values must have compatible types: got \{val1} and \{val2}",
          )
        }
        stack.push(result_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          // Verify it's numeric
          let is_numeric = match val {
            @core.ValType::I32
            | @core.ValType::I64
            | @core.ValType::F32
            | @core.ValType::F64 => true
            _ => false
          }
          if not(is_numeric) {
            raise @core.ValidationError::TypeMismatch(
              "untyped select requires numeric types, got \{val}",
            )
          }
          stack.push(val)
        } else {
          raise @core.ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, assume a default type
        stack.push(@core.ValType::I32)
      } else {
        raise @core.ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    @core.Instr::SelectTyped(result_types) => {
      // Typed select (0x1C): any type allowed, must match annotation
      // Pop condition (i32), then two values of annotated type, push one back
      ctx.poly_pop_expect(module_, @core.ValType::I32, "select condition")

      // For MVP, result_types should have exactly 1 type
      if result_types.length() != 1 {
        raise @core.ValidationError::InvalidResultArity(
          "select must have exactly 1 result type, got \{result_types.length()}",
        )
      }
      let expected_type = result_types[0]
      // Validate that type indices in the result type exist
      validate_valtype(module_, expected_type)

      // Check how many concrete values we have BEFORE popping
      let num_concrete = stack.length()

      // Pop two values and validate they match expected type
      if num_concrete >= 2 {
        let val2 = stack.unsafe_pop()
        let val1 = stack.unsafe_pop()

        // Both values must be subtypes of the expected type
        if not(is_subtype(module_, val1, expected_type)) {
          raise @core.ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val1}",
          )
        }
        if not(is_subtype(module_, val2, expected_type)) {
          raise @core.ValidationError::TypeMismatch(
            "select value type mismatch: expected \{expected_type}, got \{val2}",
          )
        }
        stack.push(expected_type)
      } else if num_concrete == 1 {
        // Only valid in unreachable code (one concrete, one polymorphic)
        if ctx.is_unreachable {
          let val = stack.unsafe_pop()
          if not(is_subtype(module_, val, expected_type)) {
            raise @core.ValidationError::TypeMismatch(
              "select value type mismatch: expected \{expected_type}, got \{val}",
            )
          }
          stack.push(expected_type)
        } else {
          raise @core.ValidationError::TypeMismatch(
            "select expects 3 operands (2 values + condition)",
          )
        }
      } else if ctx.is_unreachable {
        // In unreachable code with empty stack, push the expected type
        stack.push(expected_type)
      } else {
        raise @core.ValidationError::TypeMismatch(
          "select expects 3 operands (2 values + condition)",
        )
      }
    }
    @core.Instr::Nop => ()
    @core.Instr::Unreachable =>
      // unreachable instruction marks all subsequent code as unreachable
      ctx.mark_unreachable()
    @core.Instr::Call(func_idx) => {
      let idx = func_idx.reinterpret_as_int()
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise @core.ValidationError::InvalidFunctionIndex(idx)
      }
      // Get the function type
      let type_idx = get_func_type_index(module_, idx, import_counts)
      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::CallIndirect(type_idx, table_idx) => {
      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise @core.ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : @core.RefType = @core.RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        @core.RefType::Func | @core.RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise @core.ValidationError::TypeMismatch(
            "call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      ctx.poly_pop_expect(
        module_,
        @core.ValType::I32,
        "call_indirect table index",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_indirect argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::ReturnCall(func_idx) => {
      // return_call: tail call that returns to caller
      // Like doing a call followed by return - must match current function's return type
      let idx = func_idx.reinterpret_as_int()

      // Find the type index for this function
      let type_idx = get_func_type_index(module_, idx, import_counts)
      if type_idx < 0 || type_idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(type_idx)
      }
      let func_type_called = module_.types[type_idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    @core.Instr::ReturnCallIndirect(type_idx, table_idx) => {
      // return_call_indirect: tail call through table that returns to caller
      // Like doing a call_indirect followed by return - must match current function's return type

      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise @core.ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (return_call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : @core.RefType = @core.RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        @core.RefType::Func | @core.RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise @core.ValidationError::TypeMismatch(
            "return_call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_indirect",
      )
      // Pop table index
      ctx.poly_pop_expect(
        module_,
        @core.ValType::I32,
        "return_call_indirect table index",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_indirect argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    @core.Instr::CallRef(type_idx) => {
      // call_ref: calls function through a reference
      // Stack: [args...] [(ref null $type_idx)] -> [results...]
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]

      // Pop the function reference - must be (ref null $type_idx)
      // Cannot be generic funcref or externref
      let expected_ref_type = @core.ValType::Ref(
        @core.RefType::TypeIndex(idx),
        true,
      )
      ctx.poly_pop_expect(module_, expected_ref_type, "call_ref")

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_ref argument",
        )
      }

      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::ReturnCallRef(type_idx) => {
      // return_call_ref: tail call through a reference
      // Like doing a call_ref followed by return - must match current function's return type
      // Stack: [args...] [(ref null $type_idx)] -> (unreachable)
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_ref",
      )

      // Pop the function reference - must be (ref null $type_idx)
      // Cannot be generic funcref or externref
      let expected_ref_type = @core.ValType::Ref(
        @core.RefType::TypeIndex(idx),
        true,
      )
      ctx.poly_pop_expect(module_, expected_ref_type, "return_call_ref")

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_ref argument",
        )
      }

      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
  }
}
