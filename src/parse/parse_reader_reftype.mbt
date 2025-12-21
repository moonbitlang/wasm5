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
          (TypeIndex(type_idx), true) // 0x63 means nullable
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
          (TypeIndex(type_idx), false) // 0x64 means non-nullable
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
            (TypeIndex(type_idx), true) // Default to nullable
          } else {
            raise @validate.ValidationError::TypeMismatch(
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
          TypeIndex(type_idx)
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
          TypeIndex(type_idx)
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
            TypeIndex(type_idx)
          } else if byte == 0x40 {
            // 0x40 is empty/void - treat as funcref for compatibility
            // This might appear in some edge cases
            Func
          } else {
            raise @validate.ValidationError::TypeMismatch(
              "invalid reference type: 0x\{byte.to_string()}",
            )
          }
      }
  }
}
