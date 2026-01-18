// Component Runtime Canonical ABI Implementation

///|
/// Context for canonical ABI encoding/decoding
priv struct CanonicalContext {
  runtime : @runtime.Runtime
  core_memories : Array[(Array[Byte], UInt64?)] // Reference to component's core_memories
  memory_idx : UInt?
  realloc_idx : UInt?
  post_return_idx : UInt?
  encoding : @core.StringEncoding
}

///|
fn CanonicalContext::new(
  runtime : @runtime.Runtime,
  core_memories : Array[(Array[Byte], UInt64?)],
  options : Array[@core.CanonOpt],
) -> CanonicalContext {
  let mut memory_idx : UInt? = None
  let mut realloc_idx : UInt? = None
  let mut post_return_idx : UInt? = None
  let mut encoding = @core.StringEncoding::Utf8
  for opt in options {
    match opt {
      @core.CanonOpt::Memory(idx) => memory_idx = Some(idx)
      @core.CanonOpt::Realloc(idx) => realloc_idx = Some(idx)
      @core.CanonOpt::PostReturn(idx) => post_return_idx = Some(idx)
      @core.CanonOpt::Utf8 => encoding = @core.StringEncoding::Utf8
      @core.CanonOpt::Utf16 => encoding = @core.StringEncoding::Utf16
      @core.CanonOpt::Latin1Utf16 =>
        encoding = @core.StringEncoding::Latin1Utf16
    }
  }
  CanonicalContext::{
    runtime,
    core_memories,
    memory_idx,
    realloc_idx,
    post_return_idx,
    encoding,
  }
}

///|
/// Call post-return function to clean up after lifting results
fn CanonicalContext::call_post_return(
  self : CanonicalContext,
  flat_results : Array[@runtime.Value],
) -> Unit raise ComponentRuntimeError {
  match self.post_return_idx {
    None => ()
    Some(func_idx) => {
      let module_ = self.runtime.get_module()
      let mut func_name : Bytes? = None
      for exp in module_.exports {
        match exp.desc {
          @core.ExportDesc::Func(idx) =>
            if idx == func_idx {
              func_name = Some(exp.name)
              break
            }
          _ => ()
        }
      }
      match func_name {
        None => raise ComponentRuntimeError("post-return function not found")
        Some(name) => {
          let _ = self.runtime.call_compiled(name, flat_results) catch {
            e => raise ComponentRuntimeError("post-return call failed: \{e}")
          }

        }
      }
    }
  }
}

///|
/// Get memory from the runtime context
/// Uses memory_idx to select from core_memories if specified,
/// otherwise falls back to the runtime's memory
fn CanonicalContext::get_memory(self : CanonicalContext) -> Array[Byte]? {
  match self.memory_idx {
    Some(idx) => {
      let mem_idx = idx.reinterpret_as_int()
      if mem_idx < self.core_memories.length() {
        Some(self.core_memories[mem_idx].0)
      } else {
        // Fallback to runtime's memory if index is out of bounds
        Some(self.runtime.ctx.memory)
      }
    }
    None => Some(self.runtime.ctx.memory)
  }
}

///|
/// Call realloc to allocate memory
fn CanonicalContext::realloc(
  self : CanonicalContext,
  old_ptr : Int,
  old_size : Int,
  align : Int,
  new_size : Int,
) -> Int raise ComponentRuntimeError {
  match self.realloc_idx {
    None => raise ComponentRuntimeError("realloc function not available")
    Some(func_idx) => {
      let args = [
        @runtime.Value::I32(old_ptr.reinterpret_as_uint()),
        @runtime.Value::I32(old_size.reinterpret_as_uint()),
        @runtime.Value::I32(align.reinterpret_as_uint()),
        @runtime.Value::I32(new_size.reinterpret_as_uint()),
      ]
      let module_ = self.runtime.get_module()
      let mut func_name : Bytes? = None
      let mut export_idx = 0
      for exp in module_.exports {
        match exp.desc {
          @core.ExportDesc::Func(idx) =>
            if idx == func_idx {
              func_name = Some(exp.name)
              break
            }
          _ => ()
        }
        export_idx = export_idx + 1
      }
      match func_name {
        None => raise ComponentRuntimeError("realloc function not found")
        Some(name) => {
          let (_, results) = self.runtime.call_compiled(name, args) catch {
            e => raise ComponentRuntimeError("realloc call failed: \{e}")
          }
          match results[0] {
            @runtime.Value::I32(ptr) => ptr.reinterpret_as_int()
            _ => raise ComponentRuntimeError("realloc returned invalid type")
          }
        }
      }
    }
  }
}

///|
/// Lower a string to memory, returns (ptr, len)
/// Supports UTF-8, UTF-16, and Latin1+UTF-16 encodings based on self.encoding
fn CanonicalContext::lower_string(
  self : CanonicalContext,
  s : String,
) -> (Int, Int) raise ComponentRuntimeError {
  match self.encoding {
    @core.StringEncoding::Utf8 => {
      let bytes = string_to_utf8(s)
      let len = bytes.length()
      let ptr = self.realloc(0, 0, 1, len)
      match self.get_memory() {
        None => raise ComponentRuntimeError("memory not available")
        Some(memory) =>
          for i = 0; i < len; i = i + 1 {
            if ptr + i < memory.length() {
              memory[ptr + i] = bytes[i]
            } else {
              raise ComponentRuntimeError("memory write out of bounds")
            }
          }
      }
      (ptr, len)
    }
    @core.StringEncoding::Utf16 => {
      // UTF-16 encoding: each code unit is 2 bytes (little-endian)
      let code_units = string_to_utf16(s)
      let byte_len = code_units.length() * 2
      let ptr = self.realloc(0, 0, 2, byte_len)
      match self.get_memory() {
        None => raise ComponentRuntimeError("memory not available")
        Some(memory) =>
          for i, cu in code_units {
            let offset = ptr + i * 2
            if offset + 1 < memory.length() {
              // Little-endian
              memory[offset] = (cu & 0xFF).to_byte()
              memory[offset + 1] = ((cu >> 8) & 0xFF).to_byte()
            } else {
              raise ComponentRuntimeError("memory write out of bounds")
            }
          }
      }
      (ptr, code_units.length()) // len is in code units, not bytes
    }
    @core.StringEncoding::Latin1Utf16 => {
      // Latin1+UTF-16: use Latin1 if all chars fit in 0-255, otherwise UTF-16
      let mut can_use_latin1 = true
      for c in s {
        if c.to_uint() > 255 {
          can_use_latin1 = false
          break
        }
      }
      if can_use_latin1 {
        // Use Latin1: one byte per character
        let len = s.length()
        let ptr = self.realloc(0, 0, 1, len)
        match self.get_memory() {
          None => raise ComponentRuntimeError("memory not available")
          Some(memory) =>
            for i, c in s {
              if ptr + i < memory.length() {
                memory[ptr + i] = c.to_uint().to_byte()
              } else {
                raise ComponentRuntimeError("memory write out of bounds")
              }
            }
        }
        (ptr, len)
      } else {
        // Use UTF-16
        let code_units = string_to_utf16(s)
        let byte_len = code_units.length() * 2
        let ptr = self.realloc(0, 0, 2, byte_len)
        match self.get_memory() {
          None => raise ComponentRuntimeError("memory not available")
          Some(memory) =>
            for i, cu in code_units {
              let offset = ptr + i * 2
              if offset + 1 < memory.length() {
                memory[offset] = (cu & 0xFF).to_byte()
                memory[offset + 1] = ((cu >> 8) & 0xFF).to_byte()
              } else {
                raise ComponentRuntimeError("memory write out of bounds")
              }
            }
        }
        // Negative length indicates UTF-16 in Latin1+UTF-16 encoding
        (ptr, -code_units.length())
      }
    }
  }
}

///|
/// Lift a string from memory
/// Supports UTF-8, UTF-16, and Latin1+UTF-16 encodings based on self.encoding
fn CanonicalContext::lift_string(
  self : CanonicalContext,
  ptr : Int,
  len : Int,
) -> String raise ComponentRuntimeError {
  match self.get_memory() {
    None => raise ComponentRuntimeError("memory not available")
    Some(memory) =>
      match self.encoding {
        @core.StringEncoding::Utf8 => {
          if ptr < 0 || ptr + len > memory.length() {
            raise ComponentRuntimeError(
              "string read out of bounds: ptr=\{ptr}, len=\{len}, mem_size=\{memory.length()}",
            )
          }
          let bytes : Array[Byte] = []
          for i = 0; i < len; i = i + 1 {
            bytes.push(memory[ptr + i])
          }
          utf8_to_string(Bytes::from_array(bytes))
        }
        @core.StringEncoding::Utf16 => {
          // len is in code units, byte length is len * 2
          let byte_len = len * 2
          if ptr < 0 || ptr + byte_len > memory.length() {
            raise ComponentRuntimeError(
              "string read out of bounds: ptr=\{ptr}, len=\{len}, mem_size=\{memory.length()}",
            )
          }
          let code_units : Array[Int] = []
          for i = 0; i < len; i = i + 1 {
            let offset = ptr + i * 2
            let lo = memory[offset].to_int()
            let hi = memory[offset + 1].to_int()
            code_units.push(lo | (hi << 8))
          }
          utf16_to_string(code_units)
        }
        @core.StringEncoding::Latin1Utf16 =>
          if len < 0 {
            // Negative length indicates UTF-16
            let actual_len = -len
            let byte_len = actual_len * 2
            if ptr < 0 || ptr + byte_len > memory.length() {
              raise ComponentRuntimeError("string read out of bounds")
            }
            let code_units : Array[Int] = []
            for i = 0; i < actual_len; i = i + 1 {
              let offset = ptr + i * 2
              let lo = memory[offset].to_int()
              let hi = memory[offset + 1].to_int()
              code_units.push(lo | (hi << 8))
            }
            utf16_to_string(code_units)
          } else {
            // Positive length indicates Latin1
            if ptr < 0 || ptr + len > memory.length() {
              raise ComponentRuntimeError("string read out of bounds")
            }
            let chars : Array[Char] = []
            for i = 0; i < len; i = i + 1 {
              chars.push(memory[ptr + i].to_int().unsafe_to_char())
            }
            String::from_array(chars)
          }
      }
  }
}

///|
/// Lower a list to memory, returns (ptr, len)
fn CanonicalContext::lower_list(
  self : CanonicalContext,
  values : Array[ComponentValue],
  elem_type : @core.ComponentValType,
) -> (Int, Int) raise ComponentRuntimeError {
  let len = values.length()
  if len == 0 {
    return (0, 0)
  }
  let (elem_size, elem_align) = get_type_layout(elem_type)
  let total_size = len * elem_size
  let ptr = self.realloc(0, 0, elem_align, total_size)
  for i, value in values {
    let offset = ptr + i * elem_size
    self.lower_value_to_memory(value, elem_type, offset)
  }
  (ptr, len)
}

///|
/// Lift a list from memory
fn CanonicalContext::lift_list(
  self : CanonicalContext,
  ptr : Int,
  len : Int,
  elem_type : @core.ComponentValType,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let result : Array[ComponentValue] = []
  if len == 0 {
    return result
  }
  let (elem_size, _) = get_type_layout(elem_type)
  for i = 0; i < len; i = i + 1 {
    let offset = ptr + i * elem_size
    let value = self.lift_value_from_memory(elem_type, offset)
    result.push(value)
  }
  result
}

///|
/// Lower a value to memory at given offset
fn CanonicalContext::lower_value_to_memory(
  self : CanonicalContext,
  value : ComponentValue,
  type_ : @core.ComponentValType,
  offset : Int,
) -> Unit raise ComponentRuntimeError {
  match self.get_memory() {
    None => raise ComponentRuntimeError("memory not available")
    Some(memory) =>
      match value {
        ComponentValue::Bool(b) =>
          memory[offset] = if b { b'\x01' } else { b'\x00' }
        ComponentValue::S8(n) | ComponentValue::U8(n) =>
          memory[offset] = n.to_byte()
        ComponentValue::S16(n) | ComponentValue::U16(n) =>
          @runtime.write_u16_le(memory, offset, n.reinterpret_as_uint())
        ComponentValue::S32(n) =>
          @runtime.write_u32_le(memory, offset, n.reinterpret_as_uint())
        ComponentValue::U32(u) => @runtime.write_u32_le(memory, offset, u)
        ComponentValue::S64(n) =>
          @runtime.write_u64_le(memory, offset, n.reinterpret_as_uint64())
        ComponentValue::U64(u) => @runtime.write_u64_le(memory, offset, u)
        ComponentValue::F32(f) =>
          @runtime.write_u32_le(memory, offset, f.reinterpret_as_uint())
        ComponentValue::F64(f) =>
          @runtime.write_u64_le(memory, offset, f.reinterpret_as_uint64())
        ComponentValue::Char(c) =>
          @runtime.write_u32_le(memory, offset, c.to_uint())
        ComponentValue::String(s) => {
          let (str_ptr, str_len) = self.lower_string(s)
          @runtime.write_u32_le(memory, offset, str_ptr.reinterpret_as_uint())
          @runtime.write_u32_le(
            memory,
            offset + 4,
            str_len.reinterpret_as_uint(),
          )
        }
        ComponentValue::List(items) =>
          match type_ {
            @core.ComponentValType::List(elem_type) => {
              let (list_ptr, list_len) = self.lower_list(items, elem_type)
              @runtime.write_u32_le(
                memory,
                offset,
                list_ptr.reinterpret_as_uint(),
              )
              @runtime.write_u32_le(
                memory,
                offset + 4,
                list_len.reinterpret_as_uint(),
              )
            }
            _ => raise ComponentRuntimeError("type mismatch for list")
          }
        ComponentValue::Record(_) | ComponentValue::Tuple(_) =>
          raise ComponentRuntimeError(
            "record/tuple should be flattened, not stored in memory",
          )
        ComponentValue::Variant(discriminant, _, payload) => {
          @runtime.write_u32_le(
            memory,
            offset,
            discriminant.reinterpret_as_uint(),
          )
          match payload {
            Some(payload_value) =>
              match type_ {
                @core.ComponentValType::Variant(cases) =>
                  if discriminant < cases.length() {
                    match cases[discriminant].type_ {
                      Some(payload_type) => {
                        let (_, payload_align) = get_type_layout(payload_type)
                        let payload_offset = align_to(4, payload_align)
                        self.lower_value_to_memory(
                          payload_value,
                          payload_type,
                          offset + payload_offset,
                        )
                      }
                      None => ()
                    }
                  }
                _ => ()
              }
            None => ()
          }
        }
        ComponentValue::OptionNone => @runtime.write_u32_le(memory, offset, 0U)
        ComponentValue::OptionSome(inner_value) => {
          @runtime.write_u32_le(memory, offset, 1U)
          match type_ {
            @core.ComponentValType::Option(inner_type) => {
              let (_, inner_align) = get_type_layout(inner_type)
              let payload_offset = align_to(4, inner_align)
              self.lower_value_to_memory(
                inner_value,
                inner_type,
                offset + payload_offset,
              )
            }
            _ => ()
          }
        }
        ComponentValue::ResultOk(ok_value) => {
          @runtime.write_u32_le(memory, offset, 0U)
          match ok_value {
            Some(v) =>
              match type_ {
                @core.ComponentValType::Result(Some(ok_type), _) => {
                  let (_, ok_align) = get_type_layout(ok_type)
                  let payload_offset = align_to(4, ok_align)
                  self.lower_value_to_memory(
                    v,
                    ok_type,
                    offset + payload_offset,
                  )
                }
                _ => ()
              }
            None => ()
          }
        }
        ComponentValue::ResultErr(err_value) => {
          @runtime.write_u32_le(memory, offset, 1U)
          match err_value {
            Some(v) =>
              match type_ {
                @core.ComponentValType::Result(_, Some(err_type)) => {
                  let (_, err_align) = get_type_layout(err_type)
                  let payload_offset = align_to(4, err_align)
                  self.lower_value_to_memory(
                    v,
                    err_type,
                    offset + payload_offset,
                  )
                }
                _ => ()
              }
            None => ()
          }
        }
        ComponentValue::Enum(discriminant, _) =>
          @runtime.write_u32_le(
            memory,
            offset,
            discriminant.reinterpret_as_uint(),
          )
        ComponentValue::Flags(set_flags) => {
          let mut bits = 0U
          for i, _ in set_flags {
            bits = bits | (1U << i)
          }
          @runtime.write_u32_le(memory, offset, bits)
        }
        ComponentValue::Own(_, handle) | ComponentValue::Borrow(_, handle) =>
          @runtime.write_u32_le(memory, offset, handle)
      }
  }
}

///|
/// Lift a value from memory at given offset
fn CanonicalContext::lift_value_from_memory(
  self : CanonicalContext,
  type_ : @core.ComponentValType,
  offset : Int,
) -> ComponentValue raise ComponentRuntimeError {
  match self.get_memory() {
    None => raise ComponentRuntimeError("memory not available")
    Some(memory) =>
      match type_ {
        @core.ComponentValType::Primitive(@core.PrimitiveType::Bool) =>
          ComponentValue::Bool(memory[offset] != b'\x00')
        @core.ComponentValType::Primitive(@core.PrimitiveType::S8) =>
          ComponentValue::S8(memory[offset].to_int())
        @core.ComponentValType::Primitive(@core.PrimitiveType::U8) =>
          ComponentValue::U8(memory[offset].to_int())
        @core.ComponentValType::Primitive(@core.PrimitiveType::S16) =>
          ComponentValue::S16(
            @runtime.read_u16_le(memory, offset).reinterpret_as_int(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::U16) =>
          ComponentValue::U16(
            @runtime.read_u16_le(memory, offset).reinterpret_as_int(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::S32) =>
          ComponentValue::S32(
            @runtime.read_u32_le(memory, offset).reinterpret_as_int(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::U32) =>
          ComponentValue::U32(@runtime.read_u32_le(memory, offset))
        @core.ComponentValType::Primitive(@core.PrimitiveType::S64) =>
          ComponentValue::S64(
            @runtime.read_u64_le(memory, offset).reinterpret_as_int64(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::U64) =>
          ComponentValue::U64(@runtime.read_u64_le(memory, offset))
        @core.ComponentValType::Primitive(@core.PrimitiveType::F32) =>
          ComponentValue::F32(
            Float::reinterpret_from_uint(@runtime.read_u32_le(memory, offset)),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::F64) =>
          ComponentValue::F64(
            @runtime.read_u64_le(memory, offset).reinterpret_as_double(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::Char) =>
          ComponentValue::Char(
            @runtime.read_u32_le(memory, offset)
            .reinterpret_as_int()
            .unsafe_to_char(),
          )
        @core.ComponentValType::Primitive(@core.PrimitiveType::String) => {
          let ptr = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          let len = @runtime.read_u32_le(memory, offset + 4).reinterpret_as_int()
          let s = self.lift_string(ptr, len)
          ComponentValue::String(s)
        }
        @core.ComponentValType::List(elem_type) => {
          let ptr = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          let len = @runtime.read_u32_le(memory, offset + 4).reinterpret_as_int()
          let items = self.lift_list(ptr, len, elem_type)
          ComponentValue::List(items)
        }
        @core.ComponentValType::Record(fields) => {
          let result : Array[(String, ComponentValue)] = []
          let mut field_offset = offset
          for field in fields {
            let (size, align) = get_type_layout(field.type_)
            field_offset = align_to(field_offset, align)
            let value = self.lift_value_from_memory(field.type_, field_offset)
            result.push((bytes_to_string(field.name), value))
            field_offset = field_offset + size
          }
          ComponentValue::Record(result)
        }
        @core.ComponentValType::Tuple(types) => {
          let result : Array[ComponentValue] = []
          let mut elem_offset = offset
          for elem_type in types {
            let (size, align) = get_type_layout(elem_type)
            elem_offset = align_to(elem_offset, align)
            let value = self.lift_value_from_memory(elem_type, elem_offset)
            result.push(value)
            elem_offset = elem_offset + size
          }
          ComponentValue::Tuple(result)
        }
        @core.ComponentValType::Option(inner_type) => {
          let discriminant = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          if discriminant == 0 {
            ComponentValue::OptionNone
          } else {
            let (_, inner_align) = get_type_layout(inner_type)
            let payload_offset = align_to(4, inner_align)
            let inner_value = self.lift_value_from_memory(
              inner_type,
              offset + payload_offset,
            )
            ComponentValue::OptionSome(inner_value)
          }
        }
        @core.ComponentValType::Result(ok_type, err_type) => {
          let discriminant = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          if discriminant == 0 {
            match ok_type {
              Some(ot) => {
                let (_, ok_align) = get_type_layout(ot)
                let payload_offset = align_to(4, ok_align)
                let ok_value = self.lift_value_from_memory(
                  ot,
                  offset + payload_offset,
                )
                ComponentValue::ResultOk(Some(ok_value))
              }
              None => ComponentValue::ResultOk(None)
            }
          } else {
            match err_type {
              Some(et) => {
                let (_, err_align) = get_type_layout(et)
                let payload_offset = align_to(4, err_align)
                let err_value = self.lift_value_from_memory(
                  et,
                  offset + payload_offset,
                )
                ComponentValue::ResultErr(Some(err_value))
              }
              None => ComponentValue::ResultErr(None)
            }
          }
        }
        @core.ComponentValType::Variant(cases) => {
          let discriminant = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          if discriminant >= 0 && discriminant < cases.length() {
            let case = cases[discriminant]
            let case_name = bytes_to_string(case.name)
            match case.type_ {
              Some(payload_type) => {
                let (_, payload_align) = get_type_layout(payload_type)
                let payload_offset = align_to(4, payload_align)
                let payload_value = self.lift_value_from_memory(
                  payload_type,
                  offset + payload_offset,
                )
                ComponentValue::Variant(
                  discriminant,
                  case_name,
                  Some(payload_value),
                )
              }
              None => ComponentValue::Variant(discriminant, case_name, None)
            }
          } else {
            raise ComponentRuntimeError(
              "invalid variant discriminant: \{discriminant}",
            )
          }
        }
        @core.ComponentValType::Enum(cases) => {
          let discriminant = @runtime.read_u32_le(memory, offset).reinterpret_as_int()
          if discriminant >= 0 && discriminant < cases.length() {
            let case_name = bytes_to_string(cases[discriminant])
            ComponentValue::Enum(discriminant, case_name)
          } else {
            raise ComponentRuntimeError(
              "invalid enum discriminant: \{discriminant}",
            )
          }
        }
        @core.ComponentValType::Flags(flag_names) => {
          let num_i32s = (flag_names.length() + 31) / 32
          let set_flags : Array[String] = []
          for word_idx = 0; word_idx < num_i32s; word_idx = word_idx + 1 {
            let word_offset = offset + word_idx * 4
            let bits = @runtime.read_u32_le(memory, word_offset)
            for bit = 0; bit < 32; bit = bit + 1 {
              let flag_idx = word_idx * 32 + bit
              if flag_idx < flag_names.length() && (bits & (1U << bit)) != 0U {
                set_flags.push(bytes_to_string(flag_names[flag_idx]))
              }
            }
          }
          ComponentValue::Flags(set_flags)
        }
        _ => raise ComponentRuntimeError("unsupported type for memory lift")
      }
  }
}

///|
/// Get the size and alignment of a component value type
fn get_type_layout(type_ : @core.ComponentValType) -> (Int, Int) {
  match type_ {
    @core.ComponentValType::Primitive(prim) =>
      match prim {
        @core.PrimitiveType::Bool
        | @core.PrimitiveType::S8
        | @core.PrimitiveType::U8 => (1, 1)
        @core.PrimitiveType::S16 | @core.PrimitiveType::U16 => (2, 2)
        @core.PrimitiveType::S32
        | @core.PrimitiveType::U32
        | @core.PrimitiveType::F32
        | @core.PrimitiveType::Char => (4, 4)
        @core.PrimitiveType::S64
        | @core.PrimitiveType::U64
        | @core.PrimitiveType::F64 => (8, 8)
        @core.PrimitiveType::String => (8, 4)
      }
    @core.ComponentValType::List(_) => (8, 4)
    @core.ComponentValType::Record(fields) => {
      let mut size = 0
      let mut max_align = 1
      for field in fields {
        let (field_size, field_align) = get_type_layout(field.type_)
        if field_align > max_align {
          max_align = field_align
        }
        size = align_to(size, field_align) + field_size
      }
      (align_to(size, max_align), max_align)
    }
    @core.ComponentValType::Tuple(types) => {
      let mut size = 0
      let mut max_align = 1
      for elem_type in types {
        let (elem_size, elem_align) = get_type_layout(elem_type)
        if elem_align > max_align {
          max_align = elem_align
        }
        size = align_to(size, elem_align) + elem_size
      }
      (align_to(size, max_align), max_align)
    }
    @core.ComponentValType::Option(inner_type) => {
      let (inner_size, inner_align) = get_type_layout(inner_type)
      let max_align = if inner_align > 4 { inner_align } else { 4 }
      let payload_offset = align_to(4, inner_align)
      let total_size = payload_offset + inner_size
      (align_to(total_size, max_align), max_align)
    }
    @core.ComponentValType::Result(ok_type, err_type) => {
      let (ok_size, ok_align) = match ok_type {
        Some(t) => get_type_layout(t)
        None => (0, 1)
      }
      let (err_size, err_align) = match err_type {
        Some(t) => get_type_layout(t)
        None => (0, 1)
      }
      let payload_size = if ok_size > err_size { ok_size } else { err_size }
      let payload_align = if ok_align > err_align {
        ok_align
      } else {
        err_align
      }
      let max_align = if payload_align > 4 { payload_align } else { 4 }
      let payload_offset = align_to(4, payload_align)
      let total_size = payload_offset + payload_size
      (align_to(total_size, max_align), max_align)
    }
    @core.ComponentValType::Variant(cases) => {
      let mut max_payload_size = 0
      let mut max_payload_align = 1
      for case in cases {
        match case.type_ {
          Some(t) => {
            let (case_size, case_align) = get_type_layout(t)
            if case_size > max_payload_size {
              max_payload_size = case_size
            }
            if case_align > max_payload_align {
              max_payload_align = case_align
            }
          }
          None => ()
        }
      }
      let max_align = if max_payload_align > 4 { max_payload_align } else { 4 }
      let payload_offset = align_to(4, max_payload_align)
      let total_size = payload_offset + max_payload_size
      (align_to(total_size, max_align), max_align)
    }
    @core.ComponentValType::Enum(_) => (4, 4)
    @core.ComponentValType::Flags(flags) => {
      let num_i32s = (flags.length() + 31) / 32
      (num_i32s * 4, 4)
    }
    _ => (4, 4)
  }
}

///|
/// Infer ComponentValType from a ComponentValue
fn infer_type_from_value(value : ComponentValue) -> @core.ComponentValType {
  match value {
    ComponentValue::Bool(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::Bool)
    ComponentValue::S8(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::S8)
    ComponentValue::U8(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::U8)
    ComponentValue::S16(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::S16)
    ComponentValue::U16(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::U16)
    ComponentValue::S32(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::S32)
    ComponentValue::U32(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::U32)
    ComponentValue::S64(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::S64)
    ComponentValue::U64(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::U64)
    ComponentValue::F32(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::F32)
    ComponentValue::F64(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::F64)
    ComponentValue::Char(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::Char)
    ComponentValue::String(_) =>
      @core.ComponentValType::Primitive(@core.PrimitiveType::String)
    ComponentValue::List(items) =>
      if items.length() > 0 {
        @core.ComponentValType::List(infer_type_from_value(items[0]))
      } else {
        @core.ComponentValType::List(
          @core.ComponentValType::Primitive(@core.PrimitiveType::S32),
        )
      }
    ComponentValue::Record(fields) => {
      let field_types : Array[@core.RecordField] = []
      for field in fields {
        let (name, field_value) = field
        field_types.push({
          name: string_to_bytes(name),
          type_: infer_type_from_value(field_value),
        })
      }
      @core.ComponentValType::Record(field_types)
    }
    ComponentValue::Tuple(elems) => {
      let elem_types : Array[@core.ComponentValType] = []
      for elem in elems {
        elem_types.push(infer_type_from_value(elem))
      }
      @core.ComponentValType::Tuple(elem_types)
    }
    ComponentValue::OptionNone =>
      @core.ComponentValType::Option(
        @core.ComponentValType::Primitive(@core.PrimitiveType::S32),
      )
    ComponentValue::OptionSome(inner) =>
      @core.ComponentValType::Option(infer_type_from_value(inner))
    ComponentValue::ResultOk(value) => {
      let ok_type = match value {
        Some(v) => Some(infer_type_from_value(v))
        None => None
      }
      @core.ComponentValType::Result(ok_type, None)
    }
    ComponentValue::ResultErr(value) => {
      let err_type = match value {
        Some(v) => Some(infer_type_from_value(v))
        None => None
      }
      @core.ComponentValType::Result(None, err_type)
    }
    ComponentValue::Variant(_, case_name, payload) => {
      let payload_type = match payload {
        Some(v) => Some(infer_type_from_value(v))
        None => None
      }
      let case : @core.VariantCase = {
        name: string_to_bytes(case_name),
        type_: payload_type,
        refines: None,
      }
      @core.ComponentValType::Variant([case])
    }
    ComponentValue::Enum(_, case_name) =>
      @core.ComponentValType::Enum([string_to_bytes(case_name)])
    ComponentValue::Flags(set_flags) => {
      let names : Array[Bytes] = []
      for flag in set_flags {
        names.push(string_to_bytes(flag))
      }
      @core.ComponentValType::Flags(names)
    }
    ComponentValue::Own(type_idx, _) => @core.ComponentValType::Own(type_idx)
    ComponentValue::Borrow(type_idx, _) =>
      @core.ComponentValType::Borrow(type_idx)
  }
}
