///|
fn validate_instruction_memory(
  module_ : @core.Module,
  ctx : ValidationCtx,
  import_counts : ImportCounts,
  instr : @core.Instr,
) -> Bool raise @core.ValidationError {
  match instr {
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
    @core.Instr::I32Load8S(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I32,
        "i32.load8_s",
      )
    @core.Instr::I32Load8U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I32,
        "i32.load8_u",
      )
    @core.Instr::I32Load16S(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I32,
        "i32.load16_s",
      )
    @core.Instr::I32Load16U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I32,
        "i32.load16_u",
      )
    @core.Instr::I64Load8S(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I64,
        "i64.load8_s",
      )
    @core.Instr::I64Load8U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        1,
        @core.ValType::I64,
        "i64.load8_u",
      )
    @core.Instr::I64Load16S(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I64,
        "i64.load16_s",
      )
    @core.Instr::I64Load16U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        2,
        @core.ValType::I64,
        "i64.load16_u",
      )
    @core.Instr::I64Load32S(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I64,
        "i64.load32_s",
      )
    @core.Instr::I64Load32U(align, _) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        4,
        @core.ValType::I64,
        "i64.load32_u",
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

    // Memory size and grow
    @core.Instr::MemorySize(_) => {
      validate_memory_exists(module_, import_counts)
      ctx.stack.push(@core.ValType::I32)
    }
    @core.Instr::MemoryGrow(_) => {
      validate_memory_exists(module_, import_counts)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.grow")
      ctx.stack.push(@core.ValType::I32)
    }

    // Bulk memory instructions
    @core.Instr::MemoryInit(data_idx) => {
      validate_memory_exists(module_, import_counts)
      // Validate data segment index
      if data_idx.reinterpret_as_int() < 0 ||
        data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise @core.ValidationError::TypeMismatch(
          "memory.init: data segment index out of range",
        )
      }
      // memory.init pops: n, src, dest (all i32)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.init dest")
    }
    @core.Instr::DataDrop(data_idx) =>
      // Validate data segment index
      if data_idx.reinterpret_as_int() < 0 ||
        data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise @core.ValidationError::TypeMismatch(
          "data.drop: data segment index out of range",
        )
      }
    @core.Instr::MemoryCopy => {
      validate_memory_exists(module_, import_counts)
      // memory.copy pops: n, src, dest (all i32)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy src")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.copy dest")
    }
    @core.Instr::MemoryFill => {
      validate_memory_exists(module_, import_counts)
      // memory.fill pops: n, val, dest (val is i32)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill n")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill val")
      ctx.poly_pop_expect(module_, @core.ValType::I32, "memory.fill dest")
    }
    _ => return false
  }
  true
}
