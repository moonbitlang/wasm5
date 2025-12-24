///|
fn validate_instruction_memory(
  module_ : @core.Module,
  ctx : ValidationCtx,
  import_counts : ImportCounts,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  match instr {
    // Memory operations - loads (all take i32 address and push the loaded value)
    I32Load(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        I32,
        "i32.load",
      )
    I64Load(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        8,
        I64,
        "i64.load",
      )
    F32Load(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        F32,
        "f32.load",
      )
    F64Load(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        8,
        F64,
        "f64.load",
      )
    I32Load8S(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I32,
        "i32.load8_s",
      )
    I32Load8U(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I32,
        "i32.load8_u",
      )
    I32Load16S(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I32,
        "i32.load16_s",
      )
    I32Load16U(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I32,
        "i32.load16_u",
      )
    I64Load8S(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I64,
        "i64.load8_s",
      )
    I64Load8U(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I64,
        "i64.load8_u",
      )
    I64Load16S(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I64,
        "i64.load16_s",
      )
    I64Load16U(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I64,
        "i64.load16_u",
      )
    I64Load32S(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        I64,
        "i64.load32_s",
      )
    I64Load32U(align, _, mem_idx) =>
      validate_load(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        I64,
        "i64.load32_u",
      )

    // Memory operations - stores (all take i32 address and value, push nothing)
    I32Store(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        I32,
        "i32.store",
      )
    I64Store(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        8,
        I64,
        "i64.store",
      )
    F32Store(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        F32,
        "f32.store",
      )
    F64Store(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        8,
        F64,
        "f64.store",
      )
    I32Store8(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I32,
        "i32.store8",
      )
    I32Store16(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I32,
        "i32.store16",
      )
    I64Store8(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        1,
        I64,
        "i64.store8",
      )
    I64Store16(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        2,
        I64,
        "i64.store16",
      )
    I64Store32(align, _, mem_idx) =>
      validate_store(
        ctx,
        module_,
        import_counts,
        align,
        mem_idx,
        4,
        I64,
        "i64.store32",
      )

    // Memory size and grow
    MemorySize(mem_idx) => {
      validate_memory_index(module_, import_counts, mem_idx)
      ctx.stack.push(I32)
    }
    MemoryGrow(mem_idx) => {
      validate_memory_index(module_, import_counts, mem_idx)
      ctx.poly_pop_expect(module_, I32, "memory.grow")
      ctx.stack.push(I32)
    }

    // Bulk memory instructions
    MemoryInit(data_idx, mem_idx) => {
      validate_memory_index(module_, import_counts, mem_idx)
      // Validate data segment index
      if data_idx.reinterpret_as_int() < 0 ||
        data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise ValidationError::TypeMismatch(
          "memory.init: data segment index out of range",
        )
      }
      // memory.init pops: n, src, dest (all i32)
      ctx.poly_pop_expect(module_, I32, "memory.init n")
      ctx.poly_pop_expect(module_, I32, "memory.init src")
      ctx.poly_pop_expect(module_, I32, "memory.init dest")
    }
    DataDrop(data_idx) =>
      // Validate data segment index
      if data_idx.reinterpret_as_int() < 0 ||
        data_idx.reinterpret_as_int() >= module_.datas.length() {
        raise ValidationError::TypeMismatch(
          "data.drop: data segment index out of range",
        )
      }
    MemoryCopy(dst_idx, src_idx) => {
      validate_memory_index(module_, import_counts, dst_idx)
      validate_memory_index(module_, import_counts, src_idx)
      // memory.copy pops: n, src, dest (all i32)
      ctx.poly_pop_expect(module_, I32, "memory.copy n")
      ctx.poly_pop_expect(module_, I32, "memory.copy src")
      ctx.poly_pop_expect(module_, I32, "memory.copy dest")
    }
    MemoryFill(mem_idx) => {
      validate_memory_index(module_, import_counts, mem_idx)
      // memory.fill pops: n, val, dest (val is i32)
      ctx.poly_pop_expect(module_, I32, "memory.fill n")
      ctx.poly_pop_expect(module_, I32, "memory.fill val")
      ctx.poly_pop_expect(module_, I32, "memory.fill dest")
    }
    _ => return false
  }
  true
}
