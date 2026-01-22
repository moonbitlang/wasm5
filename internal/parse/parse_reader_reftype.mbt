// Parse reference type

///|
/// Read a reftype and return both the type and whether it's nullable
/// Returns (@core.RefType, nullable: Bool)
fn Parser::read_reftype_with_nullability(
  self : Parser,
) -> (@core.RefType, Bool) raise ParseError {
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
            raise ParseError::InvalidFormat(
              "invalid reftype: 0x\{byte.to_string()}",
            )
          }
      }
  }
}
