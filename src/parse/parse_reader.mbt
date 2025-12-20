///|
priv struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
fn Parser::new(bytes : Bytes) -> Parser {
  { bytes, pos: 0 }
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn Parser::read_byte(self : Parser) -> Byte raise @core.ParseError {
  if self.pos < self.bytes.length() {
    let byte = self.bytes.unsafe_get(self.pos)
    self.pos = self.pos + 1
    byte
  } else {
    raise @core.ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_bytes(
  self : Parser,
  n : UInt,
) -> BytesView raise @core.ParseError {
  let n_int = UInt::reinterpret_as_int(n)
  guard n_int >= 0 else {
    raise @core.ParseError::InvalidFormat("bytes length beyond Int max value")
  }
  if self.pos + n_int <= self.bytes.length() {
    let result = self.bytes[self.pos:self.pos + n_int]
    self.pos = self.pos + n_int
    result
  } else {
    raise @core.ParseError::UnexpectedEof
  }
}

// LEB128 decoding

///|
fn Parser::read_u32_leb128(self : Parser) -> UInt raise @core.ParseError {
  fn read_loop(shift : Int, result : UInt) -> UInt raise @core.ParseError {
    let byte = self.read_byte()
    // Check for overflow: shift >= 28 means we're on the 5th byte (bits 28-34)
    // For a valid u32, the 5th byte must have value <= 0x0F (only 4 bits used)
    // and no continuation bit (high bit must be 0)
    if shift >= 28 && byte > 0x0F {
      raise @core.ParseError::InvalidFormat(
        "LEB128 u32 overflow: value exceeds 32 bits",
      )
    }
    let value = byte.land(0x7f).to_uint() << shift
    let new_result = result | value
    if (byte & 0x80) == 0 {
      new_result
    } else {
      if shift >= 28 {
        // Continuation bit set on 5th byte - invalid
        raise @core.ParseError::InvalidFormat(
          "LEB128 u32 overflow: too many continuation bytes",
        )
      }
      read_loop(shift + 7, new_result)
    }
  }

  read_loop(0, 0)
}

///|
fn Parser::read_i32_leb128(self : Parser) -> Int raise @core.ParseError {
  let mut result = 0
  let mut shift = 0
  let mut byte = 0
  while true {
    byte = self.read_byte().to_int()
    result = result | ((byte & 0x7f) << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 35 {
      raise @core.ParseError::InvalidFormat("LEB128 i32 too long")
    }
  }

  // Sign extend: if the sign bit of the last 7-bit group is set
  // and we haven't filled all 32 bits, we need to sign extend
  if shift < 32 && (byte & 0x40) != 0 {
    // Set all bits from 'shift' to 31
    result = result | (-1 << shift)
  }
  result
}

///|
fn Parser::read_i64_leb128(self : Parser) -> Int64 raise @core.ParseError {
  let mut result = 0L
  let mut shift = 0
  let mut byte = 0
  while true {
    byte = self.read_byte().to_int()
    result = result | ((byte & 0x7f).to_int64() << shift)
    shift = shift + 7
    if (byte & 0x80) == 0 {
      break
    }
    if shift >= 70 {
      raise @core.ParseError::InvalidFormat("LEB128 i64 too long")
    }
  }

  // Sign extend: if the sign bit of the last 7-bit group is set
  // and we haven't filled all 64 bits, we need to sign extend
  if shift < 64 && (byte & 0x40) != 0 {
    // Set all bits from 'shift' to 63
    result = result | (-1L << shift)
  }
  result
}

///|
/// Parse memory argument (memarg) with multi-memory support
/// Returns (align, offset, memory_index)
/// In multi-memory proposal, the first byte encodes:
/// - bits 0-5: alignment (log2)
/// - bit 6: if set, memory index follows
/// If bit 6 is not set, memory index defaults to 0
fn Parser::read_memarg(
  self : Parser,
) -> (UInt, UInt, UInt) raise @core.ParseError {
  let flags_and_align = self.read_u32_leb128()
  let align = flags_and_align & 0x3F // bits 0-5
  let has_memory_index = (flags_and_align & 0x40) != 0 // bit 6
  let memory_idx = if has_memory_index { self.read_u32_leb128() } else { 0 }
  let offset = self.read_u32_leb128()
  (align, offset, memory_idx)
}

///|
fn Parser::read_f32(self : Parser) -> Float raise @core.ParseError {
  match self.bytes[self.pos:] {
    [u32le(bits), ..] => {
      self.pos = self.pos + 4
      Float::reinterpret_from_uint(bits)
    }
    _ => raise @core.ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_f64(self : Parser) -> Double raise @core.ParseError {
  match self.bytes[self.pos:] {
    [u64le(bits), ..] => {
      self.pos = self.pos + 8
      UInt64::reinterpret_as_double(bits)
    }
    _ => raise @core.ParseError::UnexpectedEof
  }
}

// Read name (length-prefixed UTF-8 string)

///|
fn Parser::read_name(self : Parser) -> Bytes raise @core.ParseError {
  let len = self.read_u32_leb128()
  let bytes = self.read_bytes(len)
  // For now, assume UTF-8 is valid
  bytes.to_bytes()
}

// Parse value type

///|
/// Helper function to map heap type opcodes to @core.RefType
/// Returns Some(@core.RefType) for known opcodes, None otherwise
fn opcode_to_heap_type(byte : Byte) -> @core.RefType? {
  match byte {
    0x70 => Some(@core.RefType::Func)
    0x6F => Some(@core.RefType::Extern)
    0x6E => Some(@core.RefType::Any)
    0x6D => Some(@core.RefType::Eq)
    0x6C => Some(@core.RefType::I31)
    0x6B => Some(@core.RefType::Struct)
    0x6A => Some(@core.RefType::Array)
    0x69 => Some(@core.RefType::Exn)
    0x71 => Some(@core.RefType::None)
    0x72 => Some(@core.RefType::NoExtern)
    0x73 => Some(@core.RefType::NoFunc)
    0x74 => Some(@core.RefType::NoExn)
    _ => Option::None
  }
}

///|
/// Read a heap type (used after 0x63/0x64 prefix)
/// Heap types can be abstract heap types (0x70, 0x6F, etc.) or type indices
fn Parser::read_heap_type(
  self : Parser,
) -> @core.RefType raise @core.ParseError {
  let byte = self.read_byte()
  match opcode_to_heap_type(byte) {
    Some(ref_type) => ref_type
    None => {
      // It's a type index encoded as LEB128
      self.pos = self.pos - 1
      let type_idx = self.read_i32_leb128()
      @core.RefType::TypeIndex(type_idx)
    }
  }
}

///|
fn Parser::read_valtype(self : Parser) -> @core.ValType raise {
  let byte = self.read_byte()
  match byte {
    0x7F => @core.ValType::I32
    0x7E => @core.ValType::I64
    0x7D => @core.ValType::F32
    0x7C => @core.ValType::F64
    0x7B => @core.ValType::V128
    // GC proposal: (ref null $t) - nullable typed reference
    0x63 => {
      let heap_type = self.read_heap_type()
      @core.ValType::Ref(heap_type, true) // nullable = true
    }
    // GC proposal: (ref $t) - non-null typed reference
    0x64 => {
      let heap_type = self.read_heap_type()
      @core.ValType::Ref(heap_type, false) // nullable = false
    }
    _ =>
      match opcode_to_heap_type(byte) {
        Some(@core.RefType::Func) => @core.ValType::FuncRef
        Some(@core.RefType::Extern) => @core.ValType::ExternRef
        Some(@core.RefType::Any) => @core.ValType::AnyRef
        Some(@core.RefType::Eq) => @core.ValType::EqRef
        Some(@core.RefType::I31) => @core.ValType::I31Ref
        Some(@core.RefType::Struct) => @core.ValType::StructRef
        Some(@core.RefType::Array) => @core.ValType::ArrayRef
        Some(@core.RefType::Exn) => @core.ValType::ExnRef
        Some(@core.RefType::None) => @core.ValType::NullRef
        Some(@core.RefType::NoExtern) => @core.ValType::NullExternRef
        Some(@core.RefType::NoFunc) => @core.ValType::NullFuncRef
        Some(@core.RefType::NoExn) => @core.ValType::NullExnRef
        Some(@core.RefType::TypeIndex(_)) | None =>
          raise @core.ValidationError::TypeMismatch(
            "invalid value type: 0x\{byte.to_string()}",
          )
      }
  }
}

// Parse reference type

///|
/// Read a reftype and return both the type and whether it's nullable
/// Returns (@core.RefType, nullable: Bool)
fn Parser::read_reftype_with_nullability(
  self : Parser,
) -> (@core.RefType, Bool) raise {
  let byte = self.read_byte()
  match byte {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    0x63 => {
      let heap_type_byte = self.read_byte()
      match opcode_to_heap_type(heap_type_byte) {
        Some(_) => {
          self.pos = self.pos - 1
          let (ref_type, _) = self.read_reftype_with_nullability()
          (ref_type, true) // 0x63 means nullable
        }
        None => {
          self.pos = self.pos - 1
          let type_idx = self.read_i32_leb128()
          (@core.RefType::TypeIndex(type_idx), true) // 0x63 means nullable
        }
      }
    }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    0x64 => {
      let heap_type_byte = self.read_byte()
      match opcode_to_heap_type(heap_type_byte) {
        Some(_) => {
          self.pos = self.pos - 1
          let (ref_type, _) = self.read_reftype_with_nullability()
          (ref_type, false) // 0x64 means non-nullable
        }
        None => {
          self.pos = self.pos - 1
          let type_idx = self.read_i32_leb128()
          (@core.RefType::TypeIndex(type_idx), false) // 0x64 means non-nullable
        }
      }
    }
    _ =>
      match opcode_to_heap_type(byte) {
        // Standard nullable reference types
        Some(ref_type) => (ref_type, true)
        None =>
          // If the byte looks like a type index, try parsing it as such
          if byte < 0x40 {
            self.pos = self.pos - 1
            let type_idx = self.read_i32_leb128()
            (@core.RefType::TypeIndex(type_idx), true) // Default to nullable
          } else {
            raise @core.ValidationError::TypeMismatch(
              "invalid reftype: 0x\{byte.to_string()}",
            )
          }
      }
  }
}

///|
fn Parser::read_reftype(self : Parser) -> @core.RefType raise {
  let byte = self.read_byte()
  match byte {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    0x63 => {
      // Read the heap type that follows
      let heap_type_byte = self.read_byte()
      match opcode_to_heap_type(heap_type_byte) {
        Some(_) => {
          // Known heap type - put byte back and parse it
          self.pos = self.pos - 1
          self.read_reftype()
        }
        None => {
          // It's a type index - put byte back and read as signed LEB128
          self.pos = self.pos - 1
          let type_idx = self.read_i32_leb128()
          @core.RefType::TypeIndex(type_idx)
        }
      }
    }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    0x64 => {
      // Read the heap type that follows (same logic as 0x63)
      let heap_type_byte = self.read_byte()
      match opcode_to_heap_type(heap_type_byte) {
        Some(_) => {
          // Known heap type - put byte back and parse it
          self.pos = self.pos - 1
          self.read_reftype()
        }
        None => {
          // It's a type index - put byte back and read as signed LEB128
          self.pos = self.pos - 1
          let type_idx = self.read_i32_leb128()
          @core.RefType::TypeIndex(type_idx)
        }
      }
    }
    _ =>
      match opcode_to_heap_type(byte) {
        Some(ref_type) => ref_type
        None =>
          // If we get here and the byte looks like it could be a type index,
          // try parsing it as such
          if byte < 0x40 {
            // Looks like a small type index - put it back and read as signed LEB128
            self.pos = self.pos - 1
            let type_idx = self.read_i32_leb128()
            @core.RefType::TypeIndex(type_idx)
          } else if byte == 0x40 {
            // 0x40 is empty/void - treat as funcref for compatibility
            // This might appear in some edge cases
            @core.RefType::Func
          } else {
            raise @core.ValidationError::TypeMismatch(
              "invalid reference type: 0x\{byte.to_string()}",
            )
          }
      }
  }
}

// Parse limits

///|
fn Parser::read_limits(self : Parser) -> @core.Limits raise @core.ParseError {
  let flags = self.read_byte()
  let min = self.read_u32_leb128()
  let max = if flags == 0x01 { Some(self.read_u32_leb128()) } else { None }
  { min, max }
}
