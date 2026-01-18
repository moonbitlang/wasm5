// Little-endian memory read/write helpers

///|
pub fn read_u16_le(mem : Array[Byte], addr : Int) -> UInt {
  mem[addr].to_uint() | (mem[addr + 1].to_uint() << 8)
}

///|
pub fn read_u32_le(mem : Array[Byte], addr : Int) -> UInt {
  mem[addr].to_uint() |
  (mem[addr + 1].to_uint() << 8) |
  (mem[addr + 2].to_uint() << 16) |
  (mem[addr + 3].to_uint() << 24)
}

///|
pub fn read_u64_le(mem : Array[Byte], addr : Int) -> UInt64 {
  mem[addr].to_uint64() |
  (mem[addr + 1].to_uint64() << 8) |
  (mem[addr + 2].to_uint64() << 16) |
  (mem[addr + 3].to_uint64() << 24) |
  (mem[addr + 4].to_uint64() << 32) |
  (mem[addr + 5].to_uint64() << 40) |
  (mem[addr + 6].to_uint64() << 48) |
  (mem[addr + 7].to_uint64() << 56)
}

///|
pub fn write_u16_le(mem : Array[Byte], addr : Int, value : UInt) -> Unit {
  mem[addr] = (value & 0xFFU).to_byte()
  mem[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
}

///|
pub fn write_u16_le_64(mem : Array[Byte], addr : Int, value : UInt64) -> Unit {
  mem[addr] = (value & 0xFFUL).to_byte()
  mem[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
}

///|
pub fn write_u32_le_64(mem : Array[Byte], addr : Int, value : UInt64) -> Unit {
  mem[addr] = (value & 0xFFUL).to_byte()
  mem[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  mem[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  mem[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
}

///|
pub fn write_u32_le(mem : Array[Byte], addr : Int, value : UInt) -> Unit {
  mem[addr] = (value & 0xFFU).to_byte()
  mem[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  mem[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  mem[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
}

///|
pub fn write_u64_le(mem : Array[Byte], addr : Int, value : UInt64) -> Unit {
  mem[addr] = (value & 0xFFUL).to_byte()
  mem[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  mem[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  mem[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  mem[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  mem[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  mem[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  mem[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
}
