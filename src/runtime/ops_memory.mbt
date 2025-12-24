//   - Address 0xFFFFFFFF (u32 max) becomes -1 when reinterpreted as signed
//   - Without the addr < 0 check, this would cause an array index out of bounds
//     crash instead of a proper WebAssembly trap
//
// The check `addr < 0` catches these cases and returns MemoryOutOfBounds trap.
// =============================================================================

///|
fn op_i32_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  // Use 64-bit arithmetic to detect overflow
  // Base address is treated as unsigned 32-bit value
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  push_i32(rt.stack, b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
  rt.pc += 1
  OK
}

///|
fn op_i32_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

// Additional memory load operations

///|
fn op_i32_load8_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.memory[addr].to_int()
  // Sign extend from 8 bits
  let value = if b >= 128 { b - 256 } else { b }
  push_i32(rt.stack, value.reinterpret_as_uint())
  rt.pc += 1
  OK
}

///|
fn op_i32_load8_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  push_i32(rt.stack, rt.memory[addr].to_uint())
  rt.pc += 1
  OK
}

///|
fn op_i32_load16_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int()
  let b1 = rt.memory[addr + 1].to_int()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768 { value16 - 65536 } else { value16 }
  push_i32(rt.stack, value.reinterpret_as_uint())
  rt.pc += 1
  OK
}

///|
fn op_i32_load16_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  push_i32(rt.stack, b0 | (b1 << 8))
  rt.pc += 1
  OK
}

///|
fn op_i64_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  push_i64(
    rt.stack,
    b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56),
  )
  rt.pc += 1
  OK
}

///|
fn op_i64_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_load8_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b = rt.memory[addr].to_int64()
  // Sign extend from 8 bits
  let value = if b >= 128L { b - 256L } else { b }
  push_i64(rt.stack, value.reinterpret_as_uint64())
  rt.pc += 1
  OK
}

///|
fn op_i64_load8_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  push_i64(rt.stack, rt.memory[addr].to_uint64())
  rt.pc += 1
  OK
}

///|
fn op_i64_load16_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768L { value16 - 65536L } else { value16 }
  push_i64(rt.stack, value.reinterpret_as_uint64())
  rt.pc += 1
  OK
}

///|
fn op_i64_load16_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  push_i64(rt.stack, b0 | (b1 << 8))
  rt.pc += 1
  OK
}

///|
fn op_i64_load32_s(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let b2 = rt.memory[addr + 2].to_int64()
  let b3 = rt.memory[addr + 3].to_int64()
  let value32 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  // Sign extend from 32 bits
  let value = if value32 >= 0x80000000L {
    value32 - 0x100000000L
  } else {
    value32
  }
  push_i64(rt.stack, value.reinterpret_as_uint64())
  rt.pc += 1
  OK
}

///|
fn op_i64_load32_u(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  push_i64(rt.stack, b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
  rt.pc += 1
  OK
}

///|
fn op_f32_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  push_f32(rt.stack, Float::reinterpret_from_uint(bits))
  rt.pc += 1
  OK
}

///|
fn op_f64_load(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  push_f64(rt.stack, bits.reinterpret_as_double())
  rt.pc += 1
  OK
}

///|
fn op_f32_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_f32().reinterpret_as_uint()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_f64_store(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_f64().reinterpret_as_uint64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 8UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

// Narrow store operations

///|
fn op_i32_store8(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i32_store16(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i32()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store8(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 1UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store16(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 2UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

///|
fn op_i64_store32(rt : Runtime) -> RetCode {
  let offset = rt.read_imm_idx().reinterpret_as_uint().to_uint64()
  let value = rt.pop_i64()
  let base = rt.pop_i32().to_uint64()
  let effective_addr = base + offset
  if effective_addr + 4UL > rt.memory.length().reinterpret_as_uint().to_uint64() {
    return MemoryOutOfBounds
  }
  let addr = effective_addr.reinterpret_as_int64().to_int()
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.pc += 1
  OK
}

// Memory size and grow operations
// WebAssembly memory is measured in pages of 64KB (65536 bytes)

///|
let wasm_page_size : Int = 65536

///|
fn op_memory_size(rt : Runtime) -> RetCode {
  // Return current memory size in pages
  let size_in_pages = rt.memory.length() / wasm_page_size
  push_i32(rt.stack, size_in_pages.reinterpret_as_uint())
  rt.pc += 1
  OK
}

///|
fn op_memory_grow(rt : Runtime) -> RetCode {
  let delta_pages = rt.pop_i32().reinterpret_as_int()
  let old_size_pages = rt.memory.length() / wasm_page_size

  // Check for overflow or negative delta
  if delta_pages < 0 {
    push_i32(rt.stack, 0xFFFFFFFFU) // -1 indicates failure
    rt.pc += 1
    return OK
  }
  let new_size_pages = old_size_pages + delta_pages

  // Check against maximum memory limit from module definition
  // If no max is defined, WebAssembly spec allows up to 65536 pages (4GB)
  let max_pages = match rt.memory_max {
    Some(max) => max.reinterpret_as_int()
    None => 65536 // No limit specified in module
  }
  if new_size_pages > max_pages {
    push_i32(rt.stack, 0xFFFFFFFFU) // -1 indicates failure
    rt.pc += 1
    return OK
  }

  // Grow the memory by appending zero bytes
  let bytes_to_add = delta_pages * wasm_page_size
  for i = 0; i < bytes_to_add; i = i + 1 {
    rt.memory.push(b'\x00')
  }

  // Return old size in pages (success)
  push_i32(rt.stack, old_size_pages.reinterpret_as_uint())
  rt.pc += 1
  OK
}

// =============================================================================
// Bulk memory operations
// =============================================================================

///|
fn op_memory_copy(rt : Runtime) -> RetCode {
  let n = rt.pop_i32().reinterpret_as_int()
  let src = rt.pop_i32().reinterpret_as_int()
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > rt.memory.length() ||
    dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Handle overlapping regions correctly
  if n > 0 {
    if dest <= src {
      // Copy forward
      for i = 0; i < n; i = i + 1 {
        rt.memory[dest + i] = rt.memory[src + i]
      }
    } else {
      // Copy backward (for overlapping regions where dest > src)
      for i = n - 1; i >= 0; i = i - 1 {
        rt.memory[dest + i] = rt.memory[src + i]
      }
    }
  }
  rt.pc += 1
  OK
}

///|
fn op_memory_fill(rt : Runtime) -> RetCode {
  let n = rt.pop_i32().reinterpret_as_int()
  let val = rt.pop_i32().reinterpret_as_int() & 0xFF // Truncate to byte
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check bounds
  if dest < 0 || n < 0 || dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Fill memory
  let byte_val = val.to_byte()
  for i = 0; i < n; i = i + 1 {
    rt.memory[dest + i] = byte_val
  }
  rt.pc += 1
  OK
}

///|
fn op_memory_init(rt : Runtime) -> RetCode {
  let data_idx = rt.read_imm_idx()
  let n = rt.pop_i32().reinterpret_as_int()
  let src = rt.pop_i32().reinterpret_as_int()
  let dest = rt.pop_i32().reinterpret_as_int()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.data_segments.length() {
    rt.error_detail = "unknown data segment"
    return InvalidType
  }
  let data = rt.data_segments[data_idx]

  // Check bounds
  if src < 0 ||
    dest < 0 ||
    n < 0 ||
    src + n > data.length() ||
    dest + n > rt.memory.length() {
    return MemoryOutOfBounds
  }

  // Copy from data segment to memory
  for i = 0; i < n; i = i + 1 {
    rt.memory[dest + i] = data[src + i]
  }
  rt.pc += 1
  OK
}

///|
fn op_data_drop(rt : Runtime) -> RetCode {
  let data_idx = rt.read_imm_idx()

  // Check data segment index
  if data_idx < 0 || data_idx >= rt.data_segments.length() {
    rt.error_detail = "unknown data segment"
    return InvalidType
  }

  // Drop the data segment (make it empty)
  rt.data_segments[data_idx] = []
  rt.pc += 1
  OK
}
