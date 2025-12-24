///|
fn validate_instruction_atomic(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
  import_counts : ImportCounts,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    Atomic(atomic_instr) => {
      let spec = match @core.atomic_spec_by_opcode(atomic_instr.opcode) {
        Some(value) => value
        None =>
          raise ValidationError::TypeMismatch(
            "unknown atomic opcode: \{atomic_instr.opcode}",
          )
      }
      fn expect_memarg(
        imm : @core.AtomicImmediate,
      ) -> (UInt, UInt) raise ValidationError {
        match imm {
          MemArg(value_align, _, value_mem_idx) => (value_align, value_mem_idx)
          _ =>
            raise ValidationError::TypeMismatch(
              "atomic instruction expects memarg",
            )
        }
      }

      match @core.atomic_stack_effect(spec.name) {
        Fence =>
          match atomic_instr.imm {
            Fence(flags) =>
              if flags != 0U {
                raise ValidationError::TypeMismatch(
                  "atomic.fence reserved byte must be 0",
                )
              }
            _ =>
              raise ValidationError::TypeMismatch(
                "atomic.fence expects fence immediate",
              )
          }
        Notify => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, 4)
          ctx.poly_pop_expect(module_, I32, "memory.atomic.notify count")
          ctx.poly_pop_expect(module_, I32, "memory.atomic.notify address")
          stack.push(I32)
        }
        Wait32 => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, 4)
          ctx.poly_pop_expect(module_, I64, "memory.atomic.wait32 timeout")
          ctx.poly_pop_expect(module_, I32, "memory.atomic.wait32 expected")
          ctx.poly_pop_expect(module_, I32, "memory.atomic.wait32 address")
          stack.push(I32)
        }
        Wait64 => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, 8)
          ctx.poly_pop_expect(module_, I64, "memory.atomic.wait64 timeout")
          ctx.poly_pop_expect(module_, I64, "memory.atomic.wait64 expected")
          ctx.poly_pop_expect(module_, I32, "memory.atomic.wait64 address")
          stack.push(I32)
        }
        Load(val_type, size) => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, size)
          ctx.poly_pop_expect(module_, I32, "atomic.load address")
          stack.push(val_type)
        }
        Store(val_type, size) => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, size)
          ctx.poly_pop_expect(module_, val_type, "atomic.store value")
          ctx.poly_pop_expect(module_, I32, "atomic.store address")
        }
        Rmw(val_type, size) => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, size)
          ctx.poly_pop_expect(module_, val_type, "atomic.rmw value")
          ctx.poly_pop_expect(module_, I32, "atomic.rmw address")
          stack.push(val_type)
        }
        Cmpxchg(val_type, size) => {
          let (align, mem_idx) = expect_memarg(atomic_instr.imm)
          validate_memory_index(module_, import_counts, mem_idx)
          validate_alignment(align, size)
          ctx.poly_pop_expect(module_, val_type, "atomic.cmpxchg replacement")
          ctx.poly_pop_expect(module_, val_type, "atomic.cmpxchg expected")
          ctx.poly_pop_expect(module_, I32, "atomic.cmpxchg address")
          stack.push(val_type)
        }
      }
      true
    }
    _ => false
  }
}
