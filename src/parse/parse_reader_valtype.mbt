// Parse value type

///|
/// Helper function to map heap type opcodes to @core.RefType
/// Returns Some(@core.RefType) for known opcodes, None otherwise
fn opcode_to_heap_type(byte : Byte) -> @core.RefType? {
  match byte {
    0x70 => Some(Func)
    0x6F => Some(Extern)
    0x6E => Some(Any)
    0x6D => Some(Eq)
    0x6C => Some(I31)
    0x6B => Some(Struct)
    0x6A => Some(Array)
    0x69 => Some(Exn)
    0x71 => Some(None)
    0x72 => Some(NoExtern)
    0x73 => Some(NoFunc)
    0x74 => Some(NoExn)
    _ => Option::None
  }
}

///|
/// Read a heap type (used after 0x63/0x64 prefix)
/// Heap types can be abstract heap types (0x70, 0x6F, etc.) or type indices
fn Parser::read_heap_type(self : Parser) -> @core.RefType raise ParseError {
  let byte = self.read_byte()
  match opcode_to_heap_type(byte) {
    Some(ref_type) => ref_type
    None => {
      // It's a type index encoded as LEB128
      self.pos = self.pos - 1
      let type_idx = self.read_i32_leb128()
      TypeIndex(type_idx)
    }
  }
}

///|
fn Parser::read_valtype(self : Parser) -> @core.ValType raise {
  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128
    // GC proposal: (ref null $t) - nullable typed reference
    0x63 => {
      let heap_type = self.read_heap_type()
      Ref(heap_type, true) // nullable = true
    }
    // GC proposal: (ref $t) - non-null typed reference
    0x64 => {
      let heap_type = self.read_heap_type()
      Ref(heap_type, false) // nullable = false
    }
    _ =>
      match opcode_to_heap_type(byte) {
        Some(Func) => FuncRef
        Some(Extern) => ExternRef
        Some(Any) => AnyRef
        Some(Eq) => EqRef
        Some(I31) => I31Ref
        Some(Struct) => StructRef
        Some(Array) => ArrayRef
        Some(Exn) => ExnRef
        Some(None) => NullRef
        Some(NoExtern) => NullExternRef
        Some(NoFunc) => NullFuncRef
        Some(NoExn) => NullExnRef
        Some(TypeIndex(_)) | None =>
          raise @validate.ValidationError::TypeMismatch(
            "invalid value type: 0x\{byte.to_string()}",
          )
      }
  }
}
