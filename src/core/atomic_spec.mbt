///|
pub(all) enum AtomicImmKind {
  None
  MemArg
  Fence
} derive(Show, Eq)

///|
pub(all) struct AtomicSpec {
  name : Bytes
  opcode : UInt
  imm : AtomicImmKind
}

///|
pub(all) enum AtomicStackEffect {
  Fence
  Notify
  Wait32
  Wait64
  Load(ValType, Int)
  Store(ValType, Int)
  Rmw(ValType, Int)
  Cmpxchg(ValType, Int)
} derive(Show)

///|
pub let atomic_specs : Array[AtomicSpec] = [
  { name: b"memory.atomic.notify", opcode: 0x00U, imm: MemArg },
  { name: b"memory.atomic.wait32", opcode: 0x01U, imm: MemArg },
  { name: b"memory.atomic.wait64", opcode: 0x02U, imm: MemArg },
  { name: b"atomic.fence", opcode: 0x03U, imm: Fence },
  { name: b"i32.atomic.load", opcode: 0x10U, imm: MemArg },
  { name: b"i64.atomic.load", opcode: 0x11U, imm: MemArg },
  { name: b"i32.atomic.load8_u", opcode: 0x12U, imm: MemArg },
  { name: b"i32.atomic.load16_u", opcode: 0x13U, imm: MemArg },
  { name: b"i64.atomic.load8_u", opcode: 0x14U, imm: MemArg },
  { name: b"i64.atomic.load16_u", opcode: 0x15U, imm: MemArg },
  { name: b"i64.atomic.load32_u", opcode: 0x16U, imm: MemArg },
  { name: b"i32.atomic.store", opcode: 0x17U, imm: MemArg },
  { name: b"i64.atomic.store", opcode: 0x18U, imm: MemArg },
  { name: b"i32.atomic.store8", opcode: 0x19U, imm: MemArg },
  { name: b"i32.atomic.store16", opcode: 0x1AU, imm: MemArg },
  { name: b"i64.atomic.store8", opcode: 0x1BU, imm: MemArg },
  { name: b"i64.atomic.store16", opcode: 0x1CU, imm: MemArg },
  { name: b"i64.atomic.store32", opcode: 0x1DU, imm: MemArg },
  { name: b"i32.atomic.rmw.add", opcode: 0x1EU, imm: MemArg },
  { name: b"i64.atomic.rmw.add", opcode: 0x1FU, imm: MemArg },
  { name: b"i32.atomic.rmw8.add_u", opcode: 0x20U, imm: MemArg },
  { name: b"i32.atomic.rmw16.add_u", opcode: 0x21U, imm: MemArg },
  { name: b"i64.atomic.rmw8.add_u", opcode: 0x22U, imm: MemArg },
  { name: b"i64.atomic.rmw16.add_u", opcode: 0x23U, imm: MemArg },
  { name: b"i64.atomic.rmw32.add_u", opcode: 0x24U, imm: MemArg },
  { name: b"i32.atomic.rmw.sub", opcode: 0x25U, imm: MemArg },
  { name: b"i64.atomic.rmw.sub", opcode: 0x26U, imm: MemArg },
  { name: b"i32.atomic.rmw8.sub_u", opcode: 0x27U, imm: MemArg },
  { name: b"i32.atomic.rmw16.sub_u", opcode: 0x28U, imm: MemArg },
  { name: b"i64.atomic.rmw8.sub_u", opcode: 0x29U, imm: MemArg },
  { name: b"i64.atomic.rmw16.sub_u", opcode: 0x2AU, imm: MemArg },
  { name: b"i64.atomic.rmw32.sub_u", opcode: 0x2BU, imm: MemArg },
  { name: b"i32.atomic.rmw.and", opcode: 0x2CU, imm: MemArg },
  { name: b"i64.atomic.rmw.and", opcode: 0x2DU, imm: MemArg },
  { name: b"i32.atomic.rmw8.and_u", opcode: 0x2EU, imm: MemArg },
  { name: b"i32.atomic.rmw16.and_u", opcode: 0x2FU, imm: MemArg },
  { name: b"i64.atomic.rmw8.and_u", opcode: 0x30U, imm: MemArg },
  { name: b"i64.atomic.rmw16.and_u", opcode: 0x31U, imm: MemArg },
  { name: b"i64.atomic.rmw32.and_u", opcode: 0x32U, imm: MemArg },
  { name: b"i32.atomic.rmw.or", opcode: 0x33U, imm: MemArg },
  { name: b"i64.atomic.rmw.or", opcode: 0x34U, imm: MemArg },
  { name: b"i32.atomic.rmw8.or_u", opcode: 0x35U, imm: MemArg },
  { name: b"i32.atomic.rmw16.or_u", opcode: 0x36U, imm: MemArg },
  { name: b"i64.atomic.rmw8.or_u", opcode: 0x37U, imm: MemArg },
  { name: b"i64.atomic.rmw16.or_u", opcode: 0x38U, imm: MemArg },
  { name: b"i64.atomic.rmw32.or_u", opcode: 0x39U, imm: MemArg },
  { name: b"i32.atomic.rmw.xor", opcode: 0x3AU, imm: MemArg },
  { name: b"i64.atomic.rmw.xor", opcode: 0x3BU, imm: MemArg },
  { name: b"i32.atomic.rmw8.xor_u", opcode: 0x3CU, imm: MemArg },
  { name: b"i32.atomic.rmw16.xor_u", opcode: 0x3DU, imm: MemArg },
  { name: b"i64.atomic.rmw8.xor_u", opcode: 0x3EU, imm: MemArg },
  { name: b"i64.atomic.rmw16.xor_u", opcode: 0x3FU, imm: MemArg },
  { name: b"i64.atomic.rmw32.xor_u", opcode: 0x40U, imm: MemArg },
  { name: b"i32.atomic.rmw.xchg", opcode: 0x41U, imm: MemArg },
  { name: b"i64.atomic.rmw.xchg", opcode: 0x42U, imm: MemArg },
  { name: b"i32.atomic.rmw8.xchg_u", opcode: 0x43U, imm: MemArg },
  { name: b"i32.atomic.rmw16.xchg_u", opcode: 0x44U, imm: MemArg },
  { name: b"i64.atomic.rmw8.xchg_u", opcode: 0x45U, imm: MemArg },
  { name: b"i64.atomic.rmw16.xchg_u", opcode: 0x46U, imm: MemArg },
  { name: b"i64.atomic.rmw32.xchg_u", opcode: 0x47U, imm: MemArg },
  { name: b"i32.atomic.rmw.cmpxchg", opcode: 0x48U, imm: MemArg },
  { name: b"i64.atomic.rmw.cmpxchg", opcode: 0x49U, imm: MemArg },
  { name: b"i32.atomic.rmw8.cmpxchg_u", opcode: 0x4AU, imm: MemArg },
  { name: b"i32.atomic.rmw16.cmpxchg_u", opcode: 0x4BU, imm: MemArg },
  { name: b"i64.atomic.rmw8.cmpxchg_u", opcode: 0x4CU, imm: MemArg },
  { name: b"i64.atomic.rmw16.cmpxchg_u", opcode: 0x4DU, imm: MemArg },
  { name: b"i64.atomic.rmw32.cmpxchg_u", opcode: 0x4EU, imm: MemArg },
]

///|
pub fn atomic_spec_by_name(name : Bytes) -> AtomicSpec? {
  for spec in atomic_specs {
    if spec.name == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn atomic_spec_by_opcode(opcode : UInt) -> AtomicSpec? {
  for spec in atomic_specs {
    if spec.opcode == opcode {
      return Some(spec)
    }
  }
  None
}

///|
pub fn atomic_stack_effect(name : Bytes) -> AtomicStackEffect {
  if name == b"atomic.fence" {
    return AtomicStackEffect::Fence
  }
  if name == b"memory.atomic.notify" {
    return AtomicStackEffect::Notify
  }
  if name == b"memory.atomic.wait32" {
    return AtomicStackEffect::Wait32
  }
  if name == b"memory.atomic.wait64" {
    return AtomicStackEffect::Wait64
  }
  if bytes_contains(name, b".load") {
    return AtomicStackEffect::Load(atomic_val_type(name), atomic_mem_size(name))
  }
  if bytes_contains(name, b".store") {
    return AtomicStackEffect::Store(
      atomic_val_type(name),
      atomic_mem_size(name),
    )
  }
  if bytes_contains(name, b"cmpxchg") {
    return AtomicStackEffect::Cmpxchg(
      atomic_val_type(name),
      atomic_mem_size(name),
    )
  }
  if bytes_contains(name, b".rmw") {
    return AtomicStackEffect::Rmw(atomic_val_type(name), atomic_mem_size(name))
  }
  AtomicStackEffect::Fence
}

///|
fn atomic_val_type(name : Bytes) -> ValType {
  if bytes_starts_with(name, b"i64.") {
    return I64
  }
  I32
}

///|
fn atomic_mem_size(name : Bytes) -> Int {
  if name == b"memory.atomic.wait64" {
    return 8
  }
  if name == b"memory.atomic.wait32" || name == b"memory.atomic.notify" {
    return 4
  }
  if bytes_contains(name, b"load8") ||
    bytes_contains(name, b"store8") ||
    bytes_contains(name, b"rmw8.") {
    return 1
  }
  if bytes_contains(name, b"load16") ||
    bytes_contains(name, b"store16") ||
    bytes_contains(name, b"rmw16.") {
    return 2
  }
  if bytes_contains(name, b"load32") ||
    bytes_contains(name, b"store32") ||
    bytes_contains(name, b"rmw32.") {
    return 4
  }
  if bytes_starts_with(name, b"i64.") {
    return 8
  }
  4
}

///|
