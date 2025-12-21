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
  match self.view() {
    [byte, .. rest] =>
      match opcode_to_heap_type(byte) {
        Some(ref_type) => {
          self.update_view(rest)
          ref_type
        }
        None => {
          // It's a type index encoded as LEB128
          let type_idx = self.read_i32_leb128()
          TypeIndex(type_idx)
        }
      }
    _ => raise ParseError::UnexpectedEof
  }
}

///|
fn Parser::read_valtype(self : Parser) -> @core.ValType raise {
  match self.view() {
    [byte, .. rest] =>
      match byte {
        0x7F => {
          self.update_view(rest)
          I32
        }
        0x7E => {
          self.update_view(rest)
          I64
        }
        0x7D => {
          self.update_view(rest)
          F32
        }
        0x7C => {
          self.update_view(rest)
          F64
        }
        0x7B => {
          self.update_view(rest)
          V128
        }
        // GC proposal: (ref null $t) - nullable typed reference
        0x63 => {
          self.update_view(rest)
          let heap_type = self.read_heap_type()
          Ref(heap_type, true) // nullable = true
        }
        // GC proposal: (ref $t) - non-null typed reference
        0x64 => {
          self.update_view(rest)
          let heap_type = self.read_heap_type()
          Ref(heap_type, false) // nullable = false
        }
        _ =>
          match opcode_to_heap_type(byte) {
            Some(Func) => {
              self.update_view(rest)
              FuncRef
            }
            Some(Extern) => {
              self.update_view(rest)
              ExternRef
            }
            Some(Any) => {
              self.update_view(rest)
              AnyRef
            }
            Some(Eq) => {
              self.update_view(rest)
              EqRef
            }
            Some(I31) => {
              self.update_view(rest)
              I31Ref
            }
            Some(Struct) => {
              self.update_view(rest)
              StructRef
            }
            Some(Array) => {
              self.update_view(rest)
              ArrayRef
            }
            Some(Exn) => {
              self.update_view(rest)
              ExnRef
            }
            Some(None) => {
              self.update_view(rest)
              NullRef
            }
            Some(NoExtern) => {
              self.update_view(rest)
              NullExternRef
            }
            Some(NoFunc) => {
              self.update_view(rest)
              NullFuncRef
            }
            Some(NoExn) => {
              self.update_view(rest)
              NullExnRef
            }
            Some(TypeIndex(_)) | None =>
              raise @validate.ValidationError::TypeMismatch(
                "invalid value type: 0x\{byte.to_string()}",
              )
          }
      }
    _ => raise ParseError::UnexpectedEof
  }
}
