// Parse reference type

///|
/// Read a reftype and return both the type and whether it's nullable
/// Returns (@core.RefType, nullable: Bool)
fn Parser::read_reftype_with_nullability(
  self : Parser,
) -> (@core.RefType, Bool) raise {
  match self.view() {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    [0x63, .. rest_after_prefix] =>
      match rest_after_prefix {
        [heap_type_byte, .. rest_after_heap] =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              self.update_view(rest_after_heap)
              (ref_type, true) // 0x63 means nullable
            }
            None => {
              self.update_view(rest_after_prefix)
              let type_idx = self.read_i32_leb128()
              (TypeIndex(type_idx), true) // 0x63 means nullable
            }
          }
        _ => raise ParseError::UnexpectedEof
      }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    [0x64, .. rest_after_prefix] =>
      match rest_after_prefix {
        [heap_type_byte, .. rest_after_heap] =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              self.update_view(rest_after_heap)
              (ref_type, false) // 0x64 means non-nullable
            }
            None => {
              self.update_view(rest_after_prefix)
              let type_idx = self.read_i32_leb128()
              (TypeIndex(type_idx), false) // 0x64 means non-nullable
            }
          }
        _ => raise ParseError::UnexpectedEof
      }
    [byte, .. rest] =>
      match opcode_to_heap_type(byte) {
        // Standard nullable reference types
        Some(ref_type) => {
          self.update_view(rest)
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
    _ => raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_reftype(self : Parser) -> @core.RefType raise {
  match self.view() {
    // GC proposal: (ref null <heaptype>) - nullable typed reference
    [0x63, .. rest_after_prefix] =>
      match rest_after_prefix {
        [heap_type_byte, .. rest_after_heap] =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              self.update_view(rest_after_heap)
              ref_type
            }
            None => {
              self.update_view(rest_after_prefix)
              let type_idx = self.read_i32_leb128()
              TypeIndex(type_idx)
            }
          }
        _ => raise ParseError::UnexpectedEof
      }
    // GC proposal: (ref <heaptype>) - non-null typed reference
    [0x64, .. rest_after_prefix] =>
      match rest_after_prefix {
        [heap_type_byte, .. rest_after_heap] =>
          match opcode_to_heap_type(heap_type_byte) {
            Some(ref_type) => {
              self.update_view(rest_after_heap)
              ref_type
            }
            None => {
              self.update_view(rest_after_prefix)
              let type_idx = self.read_i32_leb128()
              TypeIndex(type_idx)
            }
          }
        _ => raise ParseError::UnexpectedEof
      }
    [byte, .. rest] =>
      match opcode_to_heap_type(byte) {
        Some(ref_type) => {
          self.update_view(rest)
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
            self.update_view(rest)
            Func
          } else {
            raise @validate.ValidationError::TypeMismatch(
              "invalid reference type: 0x\{byte.to_string()}",
            )
          }
      }
    _ => raise ParseError::UnexpectedEof
  }
}
