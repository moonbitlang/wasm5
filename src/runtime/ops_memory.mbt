//   - Address 0xFFFFFFFF (u32 max) becomes -1 when reinterpreted as signed
//   - Without the addr < 0 check, this would cause an array index out of bounds
//     crash instead of a proper WebAssembly trap
//
// The check `addr < 0` catches these cases and returns MemoryOutOfBounds trap.
// =============================================================================

///|
fn op_i32_load(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u32_le(rt.ctx.memory, addr).to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i32_store(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u32_le(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

// Additional memory load operations

///|
fn op_i32_load8_s(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  let b = rt.ctx.memory[addr].to_int()
  // Sign extend from 8 bits
  let value = if b >= 128 { b - 256 } else { b }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint().to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i32_load8_u(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, rt.ctx.memory[addr].to_uint().to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i32_load16_s(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  let value16 = read_u16_le(rt.ctx.memory, addr).reinterpret_as_int()
  // Sign extend from 16 bits
  let value = if value16 >= 32768 { value16 - 65536 } else { value16 }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint().to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i32_load16_u(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u16_le(rt.ctx.memory, addr).to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u64_le(rt.ctx.memory, addr))
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_store(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u64_le(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_i64_load8_s(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  let b = rt.ctx.memory[addr].to_int64()
  // Sign extend from 8 bits
  let value = if b >= 128L { b - 256L } else { b }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load8_u(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 1UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, rt.ctx.memory[addr].to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load16_s(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  let value16 = read_u16_le(rt.ctx.memory, addr).to_int64()
  // Sign extend from 16 bits
  let value = if value16 >= 32768L { value16 - 65536L } else { value16 }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load16_u(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 2UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u16_le(rt.ctx.memory, addr).to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load32_s(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  let value32 = read_u32_le(rt.ctx.memory, addr).to_int64()
  // Sign extend from 32 bits
  let value = if value32 >= 0x80000000L {
    value32 - 0x100000000L
  } else {
    value32
  }
  rt.stack.unsafe_set(stack_top, value.reinterpret_as_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_i64_load32_u(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u32_le(rt.ctx.memory, addr).to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_f32_load(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 4UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u32_le(rt.ctx.memory, addr).to_uint64())
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_f64_load(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
  let offset = offset.reinterpret_as_uint().to_uint64()
  let stack_top = rt.sp - 1
  let base = rt.stack.unsafe_get(stack_top)
  let effective_addr = base + offset
  if effective_addr + 8UL >
    rt.ctx.memory.length().reinterpret_as_uint().to_uint64() {
    rt.ctx.error_detail = "out of bounds memory access"
    return { ..rt, sp: stack_top, status: Trap }
  }
  let addr = effective_addr.to_int()
  rt.stack.unsafe_set(stack_top, read_u64_le(rt.ctx.memory, addr))
  { ..rt, pc: rt.pc + 2 }
}

///|
fn op_f32_store(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u32_le(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_f64_store(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u64_le(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

// Narrow store operations

///|
fn op_i32_store8(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  rt.ctx.memory[addr] = (value & 0xFFU).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_i32_store16(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u16_le(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_i64_store8(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  rt.ctx.memory[addr] = (value & 0xFFUL).to_byte()
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_i64_store16(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u16_le_64(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_i64_store32(rt : Runtime) -> Runtime {
  let offset = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  let addr = effective_addr.to_int()
  write_u32_le_64(rt.ctx.memory, addr, value)
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
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
    Some(max) => max.to_int()
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

  // Copy memory (unsafe_blit handles overlapping regions correctly)
  if n > 0 {
    Array::unsafe_blit(rt.ctx.memory, dest, rt.ctx.memory, src, n)
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
  let data_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()
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
  if n > 0 {
    Array::unsafe_blit(rt.ctx.memory, dest, data, src, n)
  }
  { ..rt, sp: stack_top, pc: rt.pc + 2 }
}

///|
fn op_data_drop(rt : Runtime) -> Runtime {
  let data_idx = rt.ops.unsafe_get(rt.pc + 1).to_int()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.ctx.data_segments.length() {
    rt.ctx.error_detail = "unknown data segment"
    return { ..rt, status: Trap }
  }

  // Drop the data segment (make it empty)
  rt.ctx.data_segments[data_idx] = []
  { ..rt, pc: rt.pc + 2 }
}
