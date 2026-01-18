// Component Runtime Function Call

///|
/// Call an exported component function by name
pub fn ComponentRuntime::call(
  self : ComponentRuntime,
  name : String,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let kind = match self.exports.get(name) {
    Some(k) => k
    None => raise ComponentRuntimeError("export not found: \{name}")
  }
  match kind {
    @core.ComponentExportKind::Func(func_idx) => self.call_func(func_idx, args)
    _ => raise ComponentRuntimeError("export is not a function: \{name}")
  }
}

///|
fn ComponentRuntime::call_func(
  self : ComponentRuntime,
  func_idx : UInt,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  guard func_idx.reinterpret_as_int() < self.funcs.length() else {
    raise ComponentRuntimeError("invalid function index: \{func_idx}")
  }
  let func = self.funcs[func_idx.reinterpret_as_int()]

  // Get function name for error messages
  let get_func_name_str = fn() -> String {
    match func {
      ComponentFunc::Lifted(_, name, _, _) => bytes_to_string(name)
      ComponentFunc::Imported(name, _) => bytes_to_string(name)
    }
  }
  match func {
    ComponentFunc::Lifted(instance_idx, func_name, type_idx, options) => {
      // Get the function type for type-informed lifting, resolving TypeIndex references
      let result_types : Array[@core.ComponentResult]? = if type_idx.reinterpret_as_int() <
        self.types.length() {
        match self.types[type_idx.reinterpret_as_int()] {
          @core.ComponentTypeDef::Func(func_type) => {
            // Resolve TypeIndex references in result types
            let resolved : Array[@core.ComponentResult] = []
            for res in func_type.results {
              resolved.push(self.resolve_result_type(res))
            }
            Some(resolved)
          }
          _ => None
        }
      } else {
        None
      }
      guard instance_idx.reinterpret_as_int() < self.core_instances.length() else {
        raise ComponentRuntimeError(
          "invalid core instance index for function '\{get_func_name_str()}'",
        )
      }
      let instance_entry = self.core_instances[instance_idx.reinterpret_as_int()]

      // Extract the real runtime from CoreInstanceEntry
      let instance : @runtime.Runtime = match instance_entry {
        CoreInstanceEntry::Real(rt) => rt
        CoreInstanceEntry::Virtual(_) =>
          raise ComponentRuntimeError(
            "cannot call lifted function '\{get_func_name_str()}' from virtual instance",
          )
      }

      // Check if we have memory/realloc options for string/list support
      let has_memory = options
        .iter()
        .any(fn(opt) {
          match opt {
            @core.CanonOpt::Memory(_) => true
            _ => false
          }
        })

      // Convert component values to core WASM values (lowering)
      let core_args = if has_memory {
        self.lower_values_with_context(args, instance, options)
      } else {
        self.lower_values(args)
      }

      // Call the core function
      let core_results : Array[@runtime.Value] = instance.call_compiled(
        func_name, core_args,
      ) catch {
        e =>
          raise ComponentRuntimeError(
            "core function '\{get_func_name_str()}' call failed: \{e}",
          )
      }

      // Convert core WASM values to component values (lifting)
      // Always use type-informed lifting when type information is available
      let lifted_results = if has_memory || result_types is Some(_) {
        self.lift_values_with_context(
          core_results.copy(),
          instance,
          options,
          result_types,
        )
      } else {
        self.lift_values(core_results.copy())
      }

      // Call post-return function if specified (to clean up allocated memory)
      if has_memory {
        let ctx = CanonicalContext::new(instance, self.core_memories, options)
        ctx.call_post_return(core_results)
      }
      lifted_results
    }
    ComponentFunc::Imported(_, imported_func) =>
      // Call the imported function directly
      (imported_func.func)(args)
  }
}

///|
/// Lower component values with CanonicalContext (supports String/List)
fn ComponentRuntime::lower_values_with_context(
  self : ComponentRuntime,
  values : Array[ComponentValue],
  instance : @runtime.Runtime,
  options : Array[@core.CanonOpt],
) -> Array[@runtime.Value] raise ComponentRuntimeError {
  let ctx = CanonicalContext::new(instance, self.core_memories, options)
  let result : Array[@runtime.Value] = []
  for value in values {
    match value {
      ComponentValue::Bool(b) =>
        result.push(@runtime.Value::I32(if b { 1U } else { 0U }))
      ComponentValue::S8(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U8(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::S16(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U16(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::S32(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U32(n) => result.push(@runtime.Value::I32(n))
      ComponentValue::S64(n) =>
        result.push(@runtime.Value::I64(n.reinterpret_as_uint64()))
      ComponentValue::U64(n) => result.push(@runtime.Value::I64(n))
      ComponentValue::F32(n) => result.push(@runtime.Value::F32(n))
      ComponentValue::F64(n) => result.push(@runtime.Value::F64(n))
      ComponentValue::Char(c) => result.push(@runtime.Value::I32(c.to_uint()))
      ComponentValue::String(s) => {
        // Lower string to memory: returns (ptr, len)
        let (ptr, len) = ctx.lower_string(s)
        result.push(@runtime.Value::I32(ptr.reinterpret_as_uint()))
        result.push(@runtime.Value::I32(len.reinterpret_as_uint()))
      }
      ComponentValue::List(items) => {
        // Infer element type from list contents
        let elem_type = if items.length() > 0 {
          infer_type_from_value(items[0])
        } else {
          @core.ComponentValType::Primitive(@core.PrimitiveType::S32)
        }
        // Lower list to memory: returns (ptr, len)
        let (ptr, len) = ctx.lower_list(items, elem_type)
        result.push(@runtime.Value::I32(ptr.reinterpret_as_uint()))
        result.push(@runtime.Value::I32(len.reinterpret_as_uint()))
      }
      ComponentValue::Record(fields) =>
        for field in fields {
          let (_, field_value) = field
          let lowered = self.lower_values_with_context(
            [field_value],
            instance,
            options,
          )
          for v in lowered {
            result.push(v)
          }
        }
      ComponentValue::Tuple(elems) =>
        for elem in elems {
          let lowered = self.lower_values_with_context(
            [elem],
            instance,
            options,
          )
          for v in lowered {
            result.push(v)
          }
        }
      ComponentValue::OptionNone => result.push(@runtime.Value::I32(0))
      ComponentValue::OptionSome(value) => {
        result.push(@runtime.Value::I32(1))
        let lowered = self.lower_values_with_context([value], instance, options)
        for v in lowered {
          result.push(v)
        }
      }
      ComponentValue::ResultOk(value) => {
        result.push(@runtime.Value::I32(0))
        match value {
          Some(v) => {
            let lowered = self.lower_values_with_context([v], instance, options)
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::ResultErr(value) => {
        result.push(@runtime.Value::I32(1))
        match value {
          Some(v) => {
            let lowered = self.lower_values_with_context([v], instance, options)
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::Variant(discriminant, _, payload) => {
        result.push(@runtime.Value::I32(discriminant.reinterpret_as_uint()))
        match payload {
          Some(v) => {
            let lowered = self.lower_values_with_context([v], instance, options)
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::Enum(discriminant, _) =>
        result.push(@runtime.Value::I32(discriminant.reinterpret_as_uint()))
      ComponentValue::Flags(set_flags) => {
        let mut bits = 0U
        for i, _ in set_flags {
          bits = bits | (1U << i)
        }
        result.push(@runtime.Value::I32(bits))
      }
      ComponentValue::Own(_, handle) => result.push(@runtime.Value::I32(handle))
      ComponentValue::Borrow(_, handle) =>
        result.push(@runtime.Value::I32(handle))
    }
  }
  result
}

///|
/// Lower component values to core WASM values
fn ComponentRuntime::lower_values(
  self : ComponentRuntime,
  values : Array[ComponentValue],
) -> Array[@runtime.Value] raise ComponentRuntimeError {
  let _ = self
  let result : Array[@runtime.Value] = []
  for value in values {
    match value {
      ComponentValue::Bool(b) =>
        result.push(@runtime.Value::I32(if b { 1U } else { 0U }))
      ComponentValue::S8(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U8(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::S16(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U16(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::S32(n) =>
        result.push(@runtime.Value::I32(n.reinterpret_as_uint()))
      ComponentValue::U32(n) => result.push(@runtime.Value::I32(n))
      ComponentValue::S64(n) =>
        result.push(@runtime.Value::I64(n.reinterpret_as_uint64()))
      ComponentValue::U64(n) => result.push(@runtime.Value::I64(n))
      ComponentValue::F32(n) => result.push(@runtime.Value::F32(n))
      ComponentValue::F64(n) => result.push(@runtime.Value::F64(n))
      ComponentValue::Char(c) => result.push(@runtime.Value::I32(c.to_uint()))
      ComponentValue::String(_) =>
        raise ComponentRuntimeError(
          "string lowering requires memory/realloc - use CanonicalContext",
        )
      ComponentValue::List(_) =>
        raise ComponentRuntimeError(
          "list lowering requires memory/realloc - use CanonicalContext",
        )
      ComponentValue::Record(fields) =>
        for field in fields {
          let (_, field_value) = field
          let lowered = self.lower_values([field_value])
          for v in lowered {
            result.push(v)
          }
        }
      ComponentValue::Tuple(elems) =>
        for elem in elems {
          let lowered = self.lower_values([elem])
          for v in lowered {
            result.push(v)
          }
        }
      ComponentValue::OptionNone => result.push(@runtime.Value::I32(0))
      ComponentValue::OptionSome(v) => {
        result.push(@runtime.Value::I32(1))
        let lowered = self.lower_values([v])
        for lv in lowered {
          result.push(lv)
        }
      }
      ComponentValue::ResultOk(v) => {
        result.push(@runtime.Value::I32(0))
        match v {
          Some(val) => {
            let lowered = self.lower_values([val])
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::ResultErr(v) => {
        result.push(@runtime.Value::I32(1))
        match v {
          Some(val) => {
            let lowered = self.lower_values([val])
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::Variant(discriminant, _, payload) => {
        result.push(@runtime.Value::I32(discriminant.reinterpret_as_uint()))
        match payload {
          Some(v) => {
            let lowered = self.lower_values([v])
            for lv in lowered {
              result.push(lv)
            }
          }
          None => ()
        }
      }
      ComponentValue::Enum(discriminant, _) =>
        result.push(@runtime.Value::I32(discriminant.reinterpret_as_uint()))
      ComponentValue::Flags(set_flags) => {
        let mut bits = 0U
        for i, _ in set_flags {
          bits = bits | (1U << i)
        }
        result.push(@runtime.Value::I32(bits))
      }
      ComponentValue::Own(_, handle) => result.push(@runtime.Value::I32(handle))
      ComponentValue::Borrow(_, handle) =>
        result.push(@runtime.Value::I32(handle))
    }
  }
  result
}

///|
/// Lift core WASM values to component values
fn ComponentRuntime::lift_values(
  self : ComponentRuntime,
  values : Array[@runtime.Value],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let _ = self
  let result : Array[ComponentValue] = []
  for value in values {
    match value {
      @runtime.Value::I32(n) =>
        result.push(ComponentValue::S32(n.reinterpret_as_int()))
      @runtime.Value::I64(n) =>
        result.push(ComponentValue::S64(n.reinterpret_as_int64()))
      @runtime.Value::F32(n) => result.push(ComponentValue::F32(n))
      @runtime.Value::F64(n) => result.push(ComponentValue::F64(n))
      @runtime.Value::Ref(_)
      | @runtime.Value::Funcref(_)
      | @runtime.Value::Externref(_) =>
        raise ComponentRuntimeError(
          "ref values not supported in component model",
        )
    }
  }
  result
}

///|
/// Lift core WASM values with CanonicalContext (supports String/List results)
fn ComponentRuntime::lift_values_with_context(
  self : ComponentRuntime,
  values : Array[@runtime.Value],
  instance : @runtime.Runtime,
  options : Array[@core.CanonOpt],
  result_types : Array[@core.ComponentResult]?,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let ctx = CanonicalContext::new(instance, self.core_memories, options)
  let result : Array[ComponentValue] = []

  // If we have type information, use it for accurate lifting
  match result_types {
    Some(types) => {
      let mut value_idx = 0
      for res_type in types {
        if value_idx >= values.length() {
          break
        }
        let (lifted, consumed) = lift_value_with_type(
          ctx,
          values,
          value_idx,
          res_type.type_,
        )
        result.push(lifted)
        value_idx = value_idx + consumed
      }
      return result
    }
    None => ()
  }

  // Fallback: heuristic-based lifting (legacy behavior)
  if values.length() == 2 {
    match (values[0], values[1]) {
      (@runtime.Value::I32(ptr), @runtime.Value::I32(len)) => {
        let s = ctx.lift_string(
          ptr.reinterpret_as_int(),
          len.reinterpret_as_int(),
        )
        result.push(ComponentValue::String(s))
        return result
      }
      _ => ()
    }
  }

  // Fallback to simple lifting
  for value in values {
    match value {
      @runtime.Value::I32(n) =>
        result.push(ComponentValue::S32(n.reinterpret_as_int()))
      @runtime.Value::I64(n) =>
        result.push(ComponentValue::S64(n.reinterpret_as_int64()))
      @runtime.Value::F32(n) => result.push(ComponentValue::F32(n))
      @runtime.Value::F64(n) => result.push(ComponentValue::F64(n))
      @runtime.Value::Ref(_)
      | @runtime.Value::Funcref(_)
      | @runtime.Value::Externref(_) =>
        raise ComponentRuntimeError(
          "ref values not supported in component model",
        )
    }
  }
  result
}

///|
/// Lift a single value based on its type, returns (lifted_value, consumed_count)
fn lift_value_with_type(
  ctx : CanonicalContext,
  values : Array[@runtime.Value],
  start_idx : Int,
  type_ : @core.ComponentValType,
) -> (ComponentValue, Int) raise ComponentRuntimeError {
  match type_ {
    @core.ComponentValType::Primitive(prim) =>
      match prim {
        @core.PrimitiveType::Bool => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::Bool(n != 0), 1)
        }
        @core.PrimitiveType::S8 => {
          let n = get_i32_at(values, start_idx)
          (
            ComponentValue::S8(
              ((n & 0xFF).reinterpret_as_int() & 0x7F) -
              (n & 0x80).reinterpret_as_int(),
            ),
            1,
          )
        }
        @core.PrimitiveType::U8 => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::U8((n & 0xFF).reinterpret_as_int()), 1)
        }
        @core.PrimitiveType::S16 => {
          let n = get_i32_at(values, start_idx)
          let raw = (n & 0xFFFF).reinterpret_as_int()
          let signed = if raw >= 0x8000 { raw - 0x10000 } else { raw }
          (ComponentValue::S16(signed), 1)
        }
        @core.PrimitiveType::U16 => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::U16((n & 0xFFFF).reinterpret_as_int()), 1)
        }
        @core.PrimitiveType::S32 => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::S32(n.reinterpret_as_int()), 1)
        }
        @core.PrimitiveType::U32 => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::U32(n), 1)
        }
        @core.PrimitiveType::S64 => {
          let n = get_i64_at(values, start_idx)
          (ComponentValue::S64(n.reinterpret_as_int64()), 1)
        }
        @core.PrimitiveType::U64 => {
          let n = get_i64_at(values, start_idx)
          (ComponentValue::U64(n), 1)
        }
        @core.PrimitiveType::F32 => {
          let n = get_f32_at(values, start_idx)
          (ComponentValue::F32(n), 1)
        }
        @core.PrimitiveType::F64 => {
          let n = get_f64_at(values, start_idx)
          (ComponentValue::F64(n), 1)
        }
        @core.PrimitiveType::Char => {
          let n = get_i32_at(values, start_idx)
          (ComponentValue::Char(n.reinterpret_as_int().unsafe_to_char()), 1)
        }
        @core.PrimitiveType::String => {
          let ptr = get_i32_at(values, start_idx)
          let len = get_i32_at(values, start_idx + 1)
          let s = ctx.lift_string(
            ptr.reinterpret_as_int(),
            len.reinterpret_as_int(),
          )
          (ComponentValue::String(s), 2)
        }
      }
    @core.ComponentValType::List(elem_type) => {
      let ptr = get_i32_at(values, start_idx)
      let len = get_i32_at(values, start_idx + 1)
      let items = ctx.lift_list(
        ptr.reinterpret_as_int(),
        len.reinterpret_as_int(),
        elem_type,
      )
      (ComponentValue::List(items), 2)
    }
    @core.ComponentValType::Record(fields) => {
      let result_fields : Array[(String, ComponentValue)] = []
      let mut consumed = 0
      for field in fields {
        let (field_value, field_consumed) = lift_value_with_type(
          ctx,
          values,
          start_idx + consumed,
          field.type_,
        )
        result_fields.push((bytes_to_string(field.name), field_value))
        consumed = consumed + field_consumed
      }
      (ComponentValue::Record(result_fields), consumed)
    }
    @core.ComponentValType::Tuple(elem_types) => {
      let result_elems : Array[ComponentValue] = []
      let mut consumed = 0
      for elem_type in elem_types {
        let (elem_value, elem_consumed) = lift_value_with_type(
          ctx,
          values,
          start_idx + consumed,
          elem_type,
        )
        result_elems.push(elem_value)
        consumed = consumed + elem_consumed
      }
      (ComponentValue::Tuple(result_elems), consumed)
    }
    @core.ComponentValType::Option(inner_type) => {
      let discriminant = get_i32_at(values, start_idx)
      if discriminant == 0 {
        (ComponentValue::OptionNone, 1)
      } else {
        let (inner_value, inner_consumed) = lift_value_with_type(
          ctx,
          values,
          start_idx + 1,
          inner_type,
        )
        (ComponentValue::OptionSome(inner_value), 1 + inner_consumed)
      }
    }
    @core.ComponentValType::Result(ok_type, err_type) => {
      let discriminant = get_i32_at(values, start_idx)
      if discriminant == 0 {
        match ok_type {
          Some(t) => {
            let (ok_value, ok_consumed) = lift_value_with_type(
              ctx,
              values,
              start_idx + 1,
              t,
            )
            (ComponentValue::ResultOk(Some(ok_value)), 1 + ok_consumed)
          }
          None => (ComponentValue::ResultOk(None), 1)
        }
      } else {
        match err_type {
          Some(t) => {
            let (err_value, err_consumed) = lift_value_with_type(
              ctx,
              values,
              start_idx + 1,
              t,
            )
            (ComponentValue::ResultErr(Some(err_value)), 1 + err_consumed)
          }
          None => (ComponentValue::ResultErr(None), 1)
        }
      }
    }
    @core.ComponentValType::Variant(cases) => {
      let discriminant = get_i32_at(values, start_idx).reinterpret_as_int()
      if discriminant >= 0 && discriminant < cases.length() {
        let case_ = cases[discriminant]
        let case_name = bytes_to_string(case_.name)
        match case_.type_ {
          Some(payload_type) => {
            let (payload_value, payload_consumed) = lift_value_with_type(
              ctx,
              values,
              start_idx + 1,
              payload_type,
            )
            (
              ComponentValue::Variant(
                discriminant,
                case_name,
                Some(payload_value),
              ),
              1 + payload_consumed,
            )
          }
          None => (ComponentValue::Variant(discriminant, case_name, None), 1)
        }
      } else {
        raise ComponentRuntimeError(
          "invalid variant discriminant: \{discriminant}",
        )
      }
    }
    @core.ComponentValType::Enum(case_names) => {
      let discriminant = get_i32_at(values, start_idx).reinterpret_as_int()
      if discriminant >= 0 && discriminant < case_names.length() {
        let case_name = bytes_to_string(case_names[discriminant])
        (ComponentValue::Enum(discriminant, case_name), 1)
      } else {
        raise ComponentRuntimeError(
          "invalid enum discriminant: \{discriminant}",
        )
      }
    }
    @core.ComponentValType::Flags(flag_names) => {
      let bits = get_i32_at(values, start_idx)
      let set_flags : Array[String] = []
      for i, name in flag_names {
        if (bits & (1U << i)) != 0 {
          set_flags.push(bytes_to_string(name))
        }
      }
      (ComponentValue::Flags(set_flags), 1)
    }
    @core.ComponentValType::TypeIndex(idx) =>
      raise ComponentRuntimeError(
        "unresolved TypeIndex(\{idx}) - should have been resolved before lifting",
      )
    @core.ComponentValType::Own(type_idx) => {
      let handle = get_i32_at(values, start_idx)
      (ComponentValue::Own(type_idx, handle), 1)
    }
    @core.ComponentValType::Borrow(type_idx) => {
      let handle = get_i32_at(values, start_idx)
      (ComponentValue::Borrow(type_idx, handle), 1)
    }
    // Async types - not yet fully implemented
    @core.ComponentValType::Stream(_)
    | @core.ComponentValType::Future(_)
    | @core.ComponentValType::ErrorContext
    | @core.ComponentValType::FixedSizeList(_, _) =>
      raise ComponentRuntimeError(
        "async types (stream/future/error-context/fixed-size list) not yet implemented",
      )
  }
}

///|
fn get_i32_at(
  values : Array[@runtime.Value],
  idx : Int,
) -> UInt raise ComponentRuntimeError {
  if idx >= values.length() {
    raise ComponentRuntimeError("index out of bounds for value lift")
  }
  match values[idx] {
    @runtime.Value::I32(n) => n
    _ => raise ComponentRuntimeError("expected i32 value")
  }
}

///|
fn get_i64_at(
  values : Array[@runtime.Value],
  idx : Int,
) -> UInt64 raise ComponentRuntimeError {
  if idx >= values.length() {
    raise ComponentRuntimeError("index out of bounds for value lift")
  }
  match values[idx] {
    @runtime.Value::I64(n) => n
    _ => raise ComponentRuntimeError("expected i64 value")
  }
}

///|
fn get_f32_at(
  values : Array[@runtime.Value],
  idx : Int,
) -> Float raise ComponentRuntimeError {
  if idx >= values.length() {
    raise ComponentRuntimeError("index out of bounds for value lift")
  }
  match values[idx] {
    @runtime.Value::F32(n) => n
    _ => raise ComponentRuntimeError("expected f32 value")
  }
}

///|
fn get_f64_at(
  values : Array[@runtime.Value],
  idx : Int,
) -> Double raise ComponentRuntimeError {
  if idx >= values.length() {
    raise ComponentRuntimeError("index out of bounds for value lift")
  }
  match values[idx] {
    @runtime.Value::F64(n) => n
    _ => raise ComponentRuntimeError("expected f64 value")
  }
}
