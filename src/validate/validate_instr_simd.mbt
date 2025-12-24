///|
fn validate_instruction_simd(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
  import_counts : ImportCounts,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    Simd(simd) => {
      let spec = match @core.simd_spec_by_opcode(simd.opcode) {
        Some(value) => value
        None =>
          raise ValidationError::TypeMismatch(
            "unknown simd opcode: \{simd.opcode}",
          )
      }
      match @core.simd_stack_effect(spec.name) {
        Const => stack.push(V128)
        Load => {
          validate_memory_exists(module_, import_counts)
          ctx.poly_pop_expect(module_, I32, "v128.load address")
          stack.push(V128)
        }
        Store => {
          validate_memory_exists(module_, import_counts)
          ctx.poly_pop_expect(module_, V128, "v128.store value")
          ctx.poly_pop_expect(module_, I32, "v128.store address")
        }
        LoadLane => {
          validate_memory_exists(module_, import_counts)
          ctx.poly_pop_expect(module_, V128, "v128.load_lane vector")
          ctx.poly_pop_expect(module_, I32, "v128.load_lane address")
          stack.push(V128)
        }
        StoreLane => {
          validate_memory_exists(module_, import_counts)
          ctx.poly_pop_expect(module_, V128, "v128.store_lane vector")
          ctx.poly_pop_expect(module_, I32, "v128.store_lane address")
        }
        Unary => {
          ctx.poly_pop_expect(module_, V128, "simd operand")
          stack.push(V128)
        }
        Binary => {
          ctx.poly_pop_expect(module_, V128, "simd rhs")
          ctx.poly_pop_expect(module_, V128, "simd lhs")
          stack.push(V128)
        }
        Ternary => {
          ctx.poly_pop_expect(module_, V128, "simd mask")
          ctx.poly_pop_expect(module_, V128, "simd rhs")
          ctx.poly_pop_expect(module_, V128, "simd lhs")
          stack.push(V128)
        }
        Shift => {
          ctx.poly_pop_expect(module_, I32, "simd shift")
          ctx.poly_pop_expect(module_, V128, "simd vector")
          stack.push(V128)
        }
        ToI32 => {
          ctx.poly_pop_expect(module_, V128, "simd operand")
          stack.push(I32)
        }
        Splat(t) => {
          ctx.poly_pop_expect(module_, t, "simd splat")
          stack.push(V128)
        }
        Extract(t) => {
          ctx.poly_pop_expect(module_, V128, "simd extract")
          stack.push(t)
        }
        Replace(t) => {
          ctx.poly_pop_expect(module_, t, "simd replace")
          ctx.poly_pop_expect(module_, V128, "simd vector")
          stack.push(V128)
        }
      }
      true
    }
    _ => false
  }
}
