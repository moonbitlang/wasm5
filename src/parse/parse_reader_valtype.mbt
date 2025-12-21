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
