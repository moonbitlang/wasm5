// Parse reference type

///|
/// Read a reftype and return both the type and whether it's nullable
/// Returns (@core.RefType, nullable: Bool)
fn Parser::read_reftype_with_nullability(
  self : Parser,
) -> (@core.RefType, Bool) raise {
  match self.peek_byte() {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    Some(0x63) => {
      let _ = self.next_byte()
      match self.peek_byte() {
        Some(heap_type_byte) =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              let _ = self.next_byte()
              (ref_type, true) // 0x63 means nullable
            }
            None => {
              let type_idx = self.read_i32_leb128()
              (TypeIndex(type_idx), true) // 0x63 means nullable
            }
          }
        None => raise ParseError::UnexpectedEof
      }
    }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    Some(0x64) => {
      let _ = self.next_byte()
      match self.peek_byte() {
        Some(heap_type_byte) =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              let _ = self.next_byte()
              (ref_type, false) // 0x64 means non-nullable
            }
            None => {
              let type_idx = self.read_i32_leb128()
              (TypeIndex(type_idx), false) // 0x64 means non-nullable
            }
          }
        None => raise ParseError::UnexpectedEof
      }
    }
    Some(byte) =>
      match opcode_to_heap_type(byte) {
        // Standard nullable reference types
        Some(ref_type) => {
          let _ = self.next_byte()
          (ref_type, true)
        }
        None =>
          // If the byte looks like a type index, try parsing it as such
          if byte < 0x40 {
            let type_idx = self.read_i32_leb128()
            (TypeIndex(type_idx), true) // Default to nullable
          } else {
            raise @validate.ValidationError::TypeMismatch(
              "invalid reftype: 0x\{byte.to_string()}",
            )
          }
      }
    None => raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_reftype(self : Parser) -> @core.RefType raise {
  match self.peek_byte() {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    Some(0x63) => {
      let _ = self.next_byte()
      match self.peek_byte() {
        Some(heap_type_byte) =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              let _ = self.next_byte()
              ref_type
            }
            None => {
              let type_idx = self.read_i32_leb128()
              TypeIndex(type_idx)
            }
          }
        None => raise ParseError::UnexpectedEof
      }
    }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    Some(0x64) => {
      let _ = self.next_byte()
      match self.peek_byte() {
        Some(heap_type_byte) =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              let _ = self.next_byte()
              ref_type
            }
            None => {
              let type_idx = self.read_i32_leb128()
              TypeIndex(type_idx)
            }
          }
        None => raise ParseError::UnexpectedEof
      }
    }
    Some(byte) =>
      match opcode_to_heap_type(byte) {
        Some(ref_type) => {
          let _ = self.next_byte()
          ref_type
        }
        None =>
          // If we get here and the byte looks like it could be a type index,
          // try parsing it as such
          if byte < 0x40 {
            // Looks like a small type index - read as signed LEB128
            let type_idx = self.read_i32_leb128()
            TypeIndex(type_idx)
          } else if byte == 0x40 {
            // 0x40 is empty/void - treat as funcref for compatibility
            // This might appear in some edge cases
            let _ = self.next_byte()
            Func
          } else {
            raise @validate.ValidationError::TypeMismatch(
              "invalid reference type: 0x\{byte.to_string()}",
            )
          }
      }
    None => raise ParseError::UnexpectedEof
  }
}
