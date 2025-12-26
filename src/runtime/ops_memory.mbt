//   - Address 0xFFFFFFFF (u32 max) becomes -1 when reinterpreted as signed
//   - Without the addr < 0 check, this would cause an array index out of bounds
//     crash instead of a proper WebAssembly trap
//
// The check `addr < 0` catches these cases and returns MemoryOutOfBounds trap.
// =============================================================================

///|
fn op_i32_load(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint()
  let b1 = rt.ctx.memory[addr + 1].to_uint()
  let b2 = rt.ctx.memory[addr + 2].to_uint()
  let b3 = rt.ctx.memory[addr + 3].to_uint()
  rt.stack.unsafe_set(
    stack_top,
    (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).to_uint64(),
  )
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i32_store(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFU).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.ctx.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.ctx.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

// Additional memory load operations

///|
fn op_i32_load8_s(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.ctx.memory[addr].to_int()
  // Sign extend from 8 bits
  let value = if b >= 128 { b - 256 } else { b }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint().to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i32_load8_u(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.stack.unsafe_set(stack_top, rt.ctx.memory[addr].to_uint().to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i32_load16_s(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_int()
  let b1 = rt.ctx.memory[addr + 1].to_int()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768 { value16 - 65536 } else { value16 }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint().to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i32_load16_u(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint()
  let b1 = rt.ctx.memory[addr + 1].to_uint()
  rt.stack.unsafe_set(stack_top, (b0 | (b1 << 8)).to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint64()
  let b1 = rt.ctx.memory[addr + 1].to_uint64()
  let b2 = rt.ctx.memory[addr + 2].to_uint64()
  let b3 = rt.ctx.memory[addr + 3].to_uint64()
  let b4 = rt.ctx.memory[addr + 4].to_uint64()
  let b5 = rt.ctx.memory[addr + 5].to_uint64()
  let b6 = rt.ctx.memory[addr + 6].to_uint64()
  let b7 = rt.ctx.memory[addr + 7].to_uint64()
  rt.stack.unsafe_set(
    stack_top,
    b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56),
  )
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_store(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_i64_load8_s(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.ctx.memory[addr].to_int64()
  // Sign extend from 8 bits
  let value = if b >= 128L { b - 256L } else { b }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load8_u(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.stack.unsafe_set(stack_top, rt.ctx.memory[addr].to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load16_s(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_int64()
  let b1 = rt.ctx.memory[addr + 1].to_int64()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768L { value16 - 65536L } else { value16 }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load16_u(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint64()
  let b1 = rt.ctx.memory[addr + 1].to_uint64()
  rt.stack.unsafe_set(stack_top, b0 | (b1 << 8))
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load32_s(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_int64()
  let b1 = rt.ctx.memory[addr + 1].to_int64()
  let b2 = rt.ctx.memory[addr + 2].to_int64()
  let b3 = rt.ctx.memory[addr + 3].to_int64()
  let value32 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  // Sign extend from 32 bits
  let value = if value32 >= 0x80000000L {
    value32 - 0x100000000L
  } else {
    value32
  }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_i64_load32_u(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint64()
  let b1 = rt.ctx.memory[addr + 1].to_uint64()
  let b2 = rt.ctx.memory[addr + 2].to_uint64()
  let b3 = rt.ctx.memory[addr + 3].to_uint64()
  rt.stack.unsafe_set(stack_top, b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_f32_load(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint()
  let b1 = rt.ctx.memory[addr + 1].to_uint()
  let b2 = rt.ctx.memory[addr + 2].to_uint()
  let b3 = rt.ctx.memory[addr + 3].to_uint()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  rt.stack.unsafe_set(stack_top, bits.to_uint64())
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_f64_load(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.ctx.memory[addr].to_uint64()
  let b1 = rt.ctx.memory[addr + 1].to_uint64()
  let b2 = rt.ctx.memory[addr + 2].to_uint64()
  let b3 = rt.ctx.memory[addr + 3].to_uint64()
  let b4 = rt.ctx.memory[addr + 4].to_uint64()
  let b5 = rt.ctx.memory[addr + 5].to_uint64()
  let b6 = rt.ctx.memory[addr + 6].to_uint64()
  let b7 = rt.ctx.memory[addr + 7].to_uint64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  rt.stack.unsafe_set(stack_top, bits)
  { ..rt, pc: rt.pc + 1 }
}

///|
fn op_f32_store(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFU).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.ctx.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.ctx.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_f64_store(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

// Narrow store operations

///|
fn op_i32_store8(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFU).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_i32_store16(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1).to_uint()
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFU).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_i64_store8(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_i64_store16(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_i64_store32(rt : Runtime) -> Runtime {
  let { rt, value: offset } = read_imm_idx(rt)
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 2
  let value = rt.stack.unsafe_get(rt.sp - 1)
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.ctx.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

// Memory size and grow operations
// WebAssembly memory is measured in pages of 64KB (65536 bytes)

///|
let wasm_page_size : Int = 65536

///|
fn op_memory_size(rt : Runtime) -> Runtime {
  // Return current memory size in pages
  let size_in_pages = rt.ctx.memory.length() / wasm_page_size
  rt.stack.unsafe_set(rt.sp, size_in_pages.reinterpret_as_uint().to_uint64())
  { ..rt, sp: rt.sp + 1, pc: rt.pc + 1 }
}

///|
fn op_memory_grow(rt : Runtime) -> Runtime {
  let stack_top = rt.sp - 1
  let delta_pages = rt.stack
    .unsafe_get(stack_top)
    .to_uint()
    .reinterpret_as_int()
  let old_size_pages = rt.ctx.memory.length() / wasm_page_size

  // Check for overflow or negative delta
  if delta_pages < 0 {
    rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, pc: rt.pc + 1 }
  }
  let new_size_pages = old_size_pages + delta_pages

  // Check against maximum memory limit from module definition
  // If no max is defined, WebAssembly spec allows up to 65536 pages (4GB)
  let max_pages = match rt.ctx.memory_max {
    Some(max) => max.reinterpret_as_int64().to_int()
    None => 65536 // No limit specified in module
  }
  if new_size_pages > max_pages {
    rt.stack.unsafe_set(stack_top, 0xFFFFFFFFUL) // -1 indicates failure
    return { ..rt, pc: rt.pc + 1 }
  }

  // Grow the memory by appending zero bytes
  let bytes_to_add = delta_pages * wasm_page_size
  for i = 0; i < bytes_to_add; i = i + 1 {
    rt.ctx.memory.push(b'\x00')
  }

  // Return old size in pages (success)
  rt.stack.unsafe_set(
    stack_top,
    old_size_pages.reinterpret_as_uint().to_uint64(),
  )
  { ..rt, pc: rt.pc + 1 }
}

// =============================================================================
// Bulk memory operations
// =============================================================================

///|
fn op_memory_copy(rt : Runtime) -> Runtime {
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let src = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int()
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > rt.ctx.memory.length() ||
    dest + n > rt.ctx.memory.length() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Handle overlapping regions correctly
  if n > 0 {
    if dest <= src {
      // Copy forward
      for i = 0; i < n; i = i + 1 {
        rt.ctx.memory[dest + i] = rt.ctx.memory[src + i]
      }
    } else {
      // Copy backward (for overlapping regions where dest > src)
      for i = n - 1; i >= 0; i = i - 1 {
        rt.ctx.memory[dest + i] = rt.ctx.memory[src + i]
      }
    }
  }
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_memory_fill(rt : Runtime) -> Runtime {
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let val = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int() & 0xFF // Truncate to byte
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Check bounds
  if dest < 0 || n < 0 || dest + n > rt.ctx.memory.length() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Fill memory
  let byte_val = val.to_byte()
  for i = 0; i < n; i = i + 1 {
    rt.ctx.memory[dest + i] = byte_val
  }
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_memory_init(rt : Runtime) -> Runtime {
  let { rt, value: data_idx } = read_imm_idx(rt)
  let stack_top = rt.sp - 3
  let n = rt.stack.unsafe_get(rt.sp - 1).to_uint().reinterpret_as_int()
  let src = rt.stack.unsafe_get(rt.sp - 2).to_uint().reinterpret_as_int()
  let dest = rt.stack.unsafe_get(stack_top).to_uint().reinterpret_as_int()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "unknown data segment"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let data = rt.ctx.data_segments[data_idx]

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > data.length() ||
    dest + n > rt.ctx.memory.length() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }

  // Copy from data segment to memory
  for i = 0; i < n; i = i + 1 {
    rt.ctx.memory[dest + i] = data[src + i]
  }
  { ..rt, sp: stack_top, pc: rt.pc + 1 }
}

///|
fn op_data_drop(rt : Runtime) -> Runtime {
  let { rt, value: data_idx } = read_imm_idx(rt)

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "unknown data segment"
    return { ..rt, status: Trap }
  }

  // Drop the data segment (make it empty)
  rt.ctx.data_segments[data_idx] = []
  { ..rt, pc: rt.pc + 1 }
}
