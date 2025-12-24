///|
pub suberror EncodeError {
  Unsupported(String)
} derive(Show)

///|
pub fn encode(module_ : @core.Module) -> Bytes raise EncodeError {
  let out : Array[Byte] = []
  append_bytes(out, [
    0x00U.to_byte(),
    0x61U.to_byte(),
    0x73U.to_byte(),
    0x6dU.to_byte(),
  ])
  append_bytes(out, [
    0x01U.to_byte(),
    0x00U.to_byte(),
    0x00U.to_byte(),
    0x00U.to_byte(),
  ])
  let sections : Array[SectionEntry] = []
  add_section(
    sections,
    @core.SectionId::Type,
    1U,
    encode_type_section(module_.types, module_.type_groups),
  )
  add_section(
    sections,
    @core.SectionId::Import,
    2U,
    encode_import_section(module_.imports),
  )
  add_section(
    sections,
    @core.SectionId::Func,
    3U,
    encode_function_section(module_.funcs),
  )
  add_section(
    sections,
    @core.SectionId::Table,
    4U,
    encode_table_section(module_.tables),
  )
  add_section(
    sections,
    @core.SectionId::Memory,
    5U,
    encode_memory_section(module_.mems),
  )
  add_section(
    sections,
    @core.SectionId::Global,
    6U,
    encode_global_section(module_.globals),
  )
  add_section(
    sections,
    @core.SectionId::Tag,
    13U,
    encode_tag_section(module_.tags),
  )
  add_section(
    sections,
    @core.SectionId::Export,
    7U,
    encode_export_section(module_.exports),
  )
  add_section(
    sections,
    @core.SectionId::Start,
    8U,
    encode_start_section(module_.start),
  )
  add_section(
    sections,
    @core.SectionId::Elem,
    9U,
    encode_element_section(module_.elems),
  )
  add_section(
    sections,
    @core.SectionId::DataCount,
    12U,
    encode_data_count_section(module_),
  )
  add_section(
    sections,
    @core.SectionId::Code,
    10U,
    encode_code_section(module_.codes),
  )
  add_section(
    sections,
    @core.SectionId::Data,
    11U,
    encode_data_section(module_.datas),
  )
  emit_sections_with_customs(out, sections, module_.customs)
  Bytes::from_array(out)
}

///|
fn push_section(out : Array[Byte], id : UInt, payload : Array[Byte]) -> Unit {
  guard payload.length() > 0 else { return }
  out.push(id.to_byte())
  append_bytes(out, encode_u32_leb128(payload.length().reinterpret_as_uint()))
  append_bytes(out, payload)
}

///|
priv struct SectionEntry {
  kind : @core.SectionId
  id : UInt
  payload : Array[Byte]
}

///|
fn add_section(
  sections : Array[SectionEntry],
  kind : @core.SectionId,
  id : UInt,
  payload : Array[Byte],
) -> Unit {
  if payload.length() > 0 {
    sections.push({ kind, id, payload })
  }
}

///|
fn emit_sections_with_customs(
  out : Array[Byte],
  sections : Array[SectionEntry],
  customs : Array[@core.CustomSection],
) -> Unit {
  let order = section_order()
  let present_positions : Array[Int?] = Array::make(order.length(), None)
  for i in 0..<sections.length() {
    let kind = sections[i].kind
    let order_index = section_index(kind, order)
    present_positions[order_index] = Some(i)
  }
  let slots : Array[Array[@core.CustomSection]] = []
  for _ in 0..<(sections.length() + 1) {
    slots.push([])
  }
  for custom in customs {
    let slot = custom_slot(
      custom.placement,
      present_positions,
      order,
      sections.length(),
    )
    slots[slot].push(custom)
  }
  for i in 0..<slots.length() {
    for custom in slots[i] {
      push_section(out, 0U, encode_custom_payload(custom))
    }
    if i < sections.length() {
      let section = sections[i]
      push_section(out, section.id, section.payload)
    }
  }
}

///|
fn section_order() -> Array[@core.SectionId] {
  [
    @core.SectionId::Type,
    @core.SectionId::Import,
    @core.SectionId::Func,
    @core.SectionId::Table,
    @core.SectionId::Memory,
    @core.SectionId::Global,
    @core.SectionId::Tag,
    @core.SectionId::Export,
    @core.SectionId::Start,
    @core.SectionId::Elem,
    @core.SectionId::DataCount,
    @core.SectionId::Code,
    @core.SectionId::Data,
  ]
}

///|
fn section_index(kind : @core.SectionId, order : Array[@core.SectionId]) -> Int {
  for i in 0..<order.length() {
    if order[i] == kind {
      return i
    }
  }
  0
}

///|
fn custom_slot(
  placement : @core.CustomPlacement,
  present_positions : Array[Int?],
  order : Array[@core.SectionId],
  section_count : Int,
) -> Int {
  match placement {
    @core.CustomPlacement::Start => 0
    @core.CustomPlacement::End => section_count
    @core.CustomPlacement::Before(target) =>
      slot_before_after(target, false, present_positions, order)
    @core.CustomPlacement::After(target) =>
      slot_before_after(target, true, present_positions, order)
  }
}

///|
fn slot_before_after(
  target : @core.SectionId,
  after : Bool,
  present_positions : Array[Int?],
  order : Array[@core.SectionId],
) -> Int {
  let target_index = section_index(target, order)
  match present_positions[target_index] {
    Some(pos) => if after { pos + 1 } else { pos }
    None => slot_after_last_before(target_index, present_positions)
  }
}

///|
fn slot_after_last_before(
  target_index : Int,
  present_positions : Array[Int?],
) -> Int {
  let mut slot = 0
  for i in 0..<target_index {
    match present_positions[i] {
      Some(pos) => slot = pos + 1
      None => ()
    }
  }
  slot
}

///|
fn encode_custom_payload(custom : @core.CustomSection) -> Array[Byte] {
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(custom.name.length().reinterpret_as_uint()),
  )
  append_bytesview(payload, custom.name.sub())
  append_bytesview(payload, custom.data.sub())
  payload
}

///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn append_bytesview(dst : Array[Byte], src : BytesView) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn append_u32_le(dst : Array[Byte], value : UInt) -> Unit {
  dst.push((value & 0xFFU).to_byte())
  dst.push(((value >> 8) & 0xFFU).to_byte())
  dst.push(((value >> 16) & 0xFFU).to_byte())
  dst.push(((value >> 24) & 0xFFU).to_byte())
}

///|
fn append_u64_le(dst : Array[Byte], value : UInt64) -> Unit {
  dst.push((value & 0xFFUL).to_byte())
  dst.push(((value >> 8) & 0xFFUL).to_byte())
  dst.push(((value >> 16) & 0xFFUL).to_byte())
  dst.push(((value >> 24) & 0xFFUL).to_byte())
  dst.push(((value >> 32) & 0xFFUL).to_byte())
  dst.push(((value >> 40) & 0xFFUL).to_byte())
  dst.push(((value >> 48) & 0xFFUL).to_byte())
  dst.push(((value >> 56) & 0xFFUL).to_byte())
}

///|
fn encode_type_section(
  types : Array[@core.TypeDef],
  type_groups : Array[@core.TypeGroup],
) -> Array[Byte] raise EncodeError {
  guard types.length() > 0 else { return [] }
  let groups : Array[@core.TypeGroup] = []
  if type_groups.length() > 0 {
    for group in type_groups {
      groups.push(group)
    }
  } else {
    for i in 0..<types.length() {
      groups.push(@core.TypeGroup::{
        subtypes: [
          @core.SubTypeDef::{
            type_idx: i.reinterpret_as_uint(),
            supertypes: [],
            is_final: true,
          },
        ],
        explicit: false,
      })
    }
  }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(groups.length().reinterpret_as_uint()),
  )
  for group in groups {
    if group.explicit || group.subtypes.length() > 1 {
      payload.push(0x4EU.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(group.subtypes.length().reinterpret_as_uint()),
      )
      for subtype in group.subtypes {
        encode_subtype(payload, subtype, types)
      }
    } else {
      let subtype = group.subtypes[0]
      encode_subtype(payload, subtype, types)
    }
  }
  payload
}

///|
fn encode_subtype(
  payload : Array[Byte],
  subtype : @core.SubTypeDef,
  types : Array[@core.TypeDef],
) -> Unit raise EncodeError {
  if subtype.supertypes.length() > 0 || not(subtype.is_final) {
    let tag = if subtype.is_final { 0x4FU } else { 0x50U }
    payload.push(tag.to_byte())
    append_bytes(
      payload,
      encode_u32_leb128(subtype.supertypes.length().reinterpret_as_uint()),
    )
    for supertype in subtype.supertypes {
      append_bytes(payload, encode_u32_leb128(supertype))
    }
  }
  let idx = subtype.type_idx.reinterpret_as_int()
  if idx < 0 || idx >= types.length() {
    raise EncodeError::Unsupported("invalid subtype index \{subtype.type_idx}")
  }
  encode_type_def(payload, types[idx])
}

///|
fn encode_type_def(
  payload : Array[Byte],
  type_def : @core.TypeDef,
) -> Unit raise EncodeError {
  match type_def {
    Func(func_type) => {
      payload.push(0x60U.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(func_type.params.length().reinterpret_as_uint()),
      )
      for param in func_type.params {
        append_bytes(payload, encode_valtype(param))
      }
      append_bytes(
        payload,
        encode_u32_leb128(func_type.results.length().reinterpret_as_uint()),
      )
      for result in func_type.results {
        append_bytes(payload, encode_valtype(result))
      }
    }
    Struct(struct_type) => {
      payload.push(0x5FU.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(struct_type.fields.length().reinterpret_as_uint()),
      )
      for field in struct_type.fields {
        append_bytes(payload, encode_storage_type(field.storage))
        payload.push(
          if field.mutable {
            0x01U.to_byte()
          } else {
            0x00U.to_byte()
          },
        )
      }
    }
    Array(array_type) => {
      payload.push(0x5EU.to_byte())
      append_bytes(payload, encode_storage_type(array_type.element.storage))
      payload.push(
        if array_type.element.mutable {
          0x01U.to_byte()
        } else {
          0x00U.to_byte()
        },
      )
    }
  }
}

///|
fn encode_import_section(
  imports : Array[@core.Import],
) -> Array[Byte] raise EncodeError {
  guard imports.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(imports.length().reinterpret_as_uint()),
  )
  for imp in imports {
    append_name(payload, imp.module_)
    append_name(payload, imp.name)
    match imp.desc {
      Func(type_idx) => {
        payload.push(0x00U.to_byte())
        append_bytes(payload, encode_u32_leb128(type_idx))
      }
      Table(table_type) => {
        payload.push(0x01U.to_byte())
        append_bytes(payload, encode_table_type(table_type))
      }
      Mem(mem_type) => {
        payload.push(0x02U.to_byte())
        append_bytes(payload, encode_memory_limits(mem_type))
      }
      Global(global_type) => {
        payload.push(0x03U.to_byte())
        append_bytes(payload, encode_valtype(global_type.val_type))
        payload.push(
          if global_type.mutable {
            0x01U.to_byte()
          } else {
            0x00U.to_byte()
          },
        )
      }
      Tag(type_idx) => {
        payload.push(0x04U.to_byte())
        payload.push(0x00U.to_byte())
        append_bytes(payload, encode_u32_leb128(type_idx))
      }
    }
  }
  payload
}

///|
fn encode_function_section(funcs : Array[UInt]) -> Array[Byte] {
  guard funcs.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(funcs.length().reinterpret_as_uint()))
  for idx in funcs {
    append_bytes(payload, encode_u32_leb128(idx))
  }
  payload
}

///|
fn encode_table_section(
  tables : Array[@core.TableType],
) -> Array[Byte] raise EncodeError {
  guard tables.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(tables.length().reinterpret_as_uint()),
  )
  for table_type in tables {
    append_bytes(payload, encode_table_type(table_type))
  }
  payload
}

///|
fn encode_memory_section(
  mems : Array[@core.MemType],
) -> Array[Byte] raise EncodeError {
  guard mems.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(mems.length().reinterpret_as_uint()))
  for mem_type in mems {
    append_bytes(payload, encode_memory_limits(mem_type))
  }
  payload
}

///|
fn encode_global_section(
  globals : Array[@core.Global],
) -> Array[Byte] raise EncodeError {
  guard globals.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(globals.length().reinterpret_as_uint()),
  )
  for global_ in globals {
    append_bytes(payload, encode_valtype(global_.type_.val_type))
    payload.push(
      if global_.type_.mutable {
        0x01U.to_byte()
      } else {
        0x00U.to_byte()
      },
    )
    append_bytes(payload, encode_expr(global_.init))
  }
  payload
}

///|
fn encode_tag_section(tags : Array[@core.Tag]) -> Array[Byte] {
  guard tags.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(tags.length().reinterpret_as_uint()))
  for tag in tags {
    payload.push(0x00U.to_byte())
    append_bytes(payload, encode_u32_leb128(tag.type_idx))
  }
  payload
}

///|
fn encode_export_section(
  exports : Array[@core.Export],
) -> Array[Byte] raise EncodeError {
  guard exports.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(exports.length().reinterpret_as_uint()),
  )
  for export_ in exports {
    append_name(payload, export_.name)
    match export_.desc {
      Func(idx) => {
        payload.push(0x00U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Table(idx) => {
        payload.push(0x01U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Mem(idx) => {
        payload.push(0x02U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Global(idx) => {
        payload.push(0x03U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
      Tag(idx) => {
        payload.push(0x04U.to_byte())
        append_bytes(payload, encode_u32_leb128(idx))
      }
    }
  }
  payload
}

///|
fn encode_start_section(start : UInt?) -> Array[Byte] {
  match start {
    Some(idx) => encode_u32_leb128(idx)
    None => []
  }
}

///|
fn encode_element_section(
  elems : Array[@core.Elem],
) -> Array[Byte] raise EncodeError {
  guard elems.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(elems.length().reinterpret_as_uint()))
  for elem in elems {
    let init_indices : Array[UInt] = []
    let mut can_use_indices = elem.elem_type == @core.RefType::Func &&
      elem.elem_nullable
    if can_use_indices {
      for expr in elem.init {
        match expr.instrs.get(0) {
          Some(RefFunc(idx)) =>
            if expr.instrs.length() == 1 {
              init_indices.push(idx)
            } else {
              can_use_indices = false
            }
          _ => can_use_indices = false
        }
        if not(can_use_indices) {
          break
        }
      }
    }
    let uses_exprs = not(can_use_indices)
    let mut flag = 0U
    let mut emit_table_idx = false
    let mut emit_elemkind = false
    let mut emit_reftype = false
    if uses_exprs {
      if elem.is_active {
        if elem.elem_type == @core.RefType::Func &&
          elem.elem_nullable &&
          elem.table_idx == 0U &&
          not(elem.explicit_table) {
          flag = 0x04U
        } else {
          flag = 0x06U
          emit_table_idx = true
          emit_reftype = true
        }
      } else if elem.is_declarative {
        flag = 0x07U
        emit_reftype = true
      } else {
        flag = 0x05U
        emit_reftype = true
      }
    } else if elem.is_active {
      if elem.table_idx == 0U && not(elem.explicit_table) {
        flag = 0x00U
      } else {
        flag = 0x02U
        emit_table_idx = true
        emit_elemkind = true
      }
    } else if elem.is_declarative {
      flag = 0x03U
      emit_elemkind = true
    } else {
      flag = 0x01U
      emit_elemkind = true
    }
    payload.push(flag.to_byte())
    if emit_table_idx {
      append_bytes(payload, encode_u32_leb128(elem.table_idx))
    }
    if elem.is_active {
      append_bytes(payload, encode_expr(elem.offset))
    }
    if emit_elemkind {
      payload.push(0x00U.to_byte())
    }
    if emit_reftype {
      append_bytes(payload, encode_reftype(elem.elem_type, elem.elem_nullable))
    }
    append_bytes(
      payload,
      encode_u32_leb128(elem.init.length().reinterpret_as_uint()),
    )
    if uses_exprs {
      for expr in elem.init {
        append_bytes(payload, encode_expr(expr))
      }
    } else {
      for idx in init_indices {
        append_bytes(payload, encode_u32_leb128(idx))
      }
    }
  }
  payload
}

///|
fn encode_code_section(
  codes : Array[@core.Code],
) -> Array[Byte] raise EncodeError {
  guard codes.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(codes.length().reinterpret_as_uint()))
  for code in codes {
    let body : Array[Byte] = []
    append_bytes(body, encode_locals(code.locals))
    append_bytes(body, encode_expr(code.body))
    append_bytes(
      payload,
      encode_u32_leb128(body.length().reinterpret_as_uint()),
    )
    append_bytes(payload, body)
  }
  payload
}

///|
fn encode_data_section(
  datas : Array[@core.Data],
) -> Array[Byte] raise EncodeError {
  guard datas.length() > 0 else { return [] }
  let payload : Array[Byte] = []
  append_bytes(payload, encode_u32_leb128(datas.length().reinterpret_as_uint()))
  for data in datas {
    if data.is_active {
      if data.mem_idx == 0U {
        payload.push(0x00U.to_byte())
      } else {
        payload.push(0x02U.to_byte())
        append_bytes(payload, encode_u32_leb128(data.mem_idx))
      }
      append_bytes(payload, encode_expr(data.offset))
      append_bytes(
        payload,
        encode_u32_leb128(data.init.length().reinterpret_as_uint()),
      )
      append_bytesview(payload, data.init)
    } else {
      payload.push(0x01U.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(data.init.length().reinterpret_as_uint()),
      )
      append_bytesview(payload, data.init)
    }
  }
  payload
}

///|
fn encode_data_count_section(module_ : @core.Module) -> Array[Byte] {
  if not(needs_data_count(module_)) {
    return []
  }
  let payload : Array[Byte] = []
  append_bytes(
    payload,
    encode_u32_leb128(module_.datas.length().reinterpret_as_uint()),
  )
  payload
}

///|
fn needs_data_count(module_ : @core.Module) -> Bool {
  for data in module_.datas {
    if not(data.is_active) {
      return true
    }
  }
  for code in module_.codes {
    if instrs_use_bulk_memory(code.body.instrs) {
      return true
    }
  }
  false
}

///|
fn instrs_use_bulk_memory(instrs : Array[@core.Instr]) -> Bool {
  for instr in instrs {
    if instr_uses_bulk_memory(instr) {
      return true
    }
  }
  false
}

///|
fn instr_uses_bulk_memory(instr : @core.Instr) -> Bool {
  match instr {
    MemoryInit(_, _) | DataDrop(_) => true
    Block(_, body) => instrs_use_bulk_memory(body)
    Loop(_, body) => instrs_use_bulk_memory(body)
    If(_, then_body, else_body) =>
      instrs_use_bulk_memory(then_body) || instrs_use_bulk_memory(else_body)
    _ => false
  }
}

///|
fn encode_limits(limits : @core.Limits) -> Array[Byte] {
  let payload : Array[Byte] = []
  match limits.max {
    Some(max) => {
      payload.push(0x01U.to_byte())
      append_bytes(payload, encode_u32_leb128(limits.min))
      append_bytes(payload, encode_u32_leb128(max))
    }
    None => {
      payload.push(0x00U.to_byte())
      append_bytes(payload, encode_u32_leb128(limits.min))
    }
  }
  payload
}

///|
fn encode_memory_limits(
  mem_type : @core.MemType,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match (mem_type.shared, mem_type.limits.max) {
    (true, Some(max)) => {
      payload.push(0x03U.to_byte())
      append_bytes(payload, encode_u32_leb128(mem_type.limits.min))
      append_bytes(payload, encode_u32_leb128(max))
    }
    (true, None) =>
      raise EncodeError::Unsupported("shared memory requires maximum")
    (false, Some(max)) => {
      payload.push(0x01U.to_byte())
      append_bytes(payload, encode_u32_leb128(mem_type.limits.min))
      append_bytes(payload, encode_u32_leb128(max))
    }
    (false, None) => {
      payload.push(0x00U.to_byte())
      append_bytes(payload, encode_u32_leb128(mem_type.limits.min))
    }
  }
  payload
}

///|
fn encode_locals(
  locals : Array[@core.ValType],
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  if locals.length() == 0 {
    append_bytes(payload, encode_u32_leb128(0U))
    return payload
  }
  let groups : Array[(UInt, @core.ValType)] = []
  let mut current = locals[0]
  let mut count = 1U
  for i in 1..<locals.length() {
    if locals[i] == current {
      count = count + 1U
    } else {
      groups.push((count, current))
      current = locals[i]
      count = 1U
    }
  }
  groups.push((count, current))
  append_bytes(
    payload,
    encode_u32_leb128(groups.length().reinterpret_as_uint()),
  )
  for i in 0..<groups.length() {
    let group = groups[i]
    let cnt = group.0
    let val_type = group.1
    append_bytes(payload, encode_u32_leb128(cnt))
    append_bytes(payload, encode_valtype(val_type))
  }
  payload
}

///|
fn encode_expr(expr : @core.Expr) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  for instr in expr.instrs {
    append_bytes(payload, encode_instr(instr))
  }
  payload.push(0x0BU.to_byte())
  payload
}

///|
fn encode_block_type(
  block_type : @core.BlockType,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match block_type {
    Empty => payload.push(0x40U.to_byte())
    Value(val_type) => append_bytes(payload, encode_valtype(val_type))
    TypeIndex(type_idx) => append_bytes(payload, encode_i32_leb128(type_idx))
  }
  payload
}

///|
fn encode_memarg(align : UInt, offset : UInt, memory_idx : UInt) -> Array[Byte] {
  let payload : Array[Byte] = []
  let flags = if memory_idx == 0U { align } else { align | 0x40U }
  append_bytes(payload, encode_u32_leb128(flags))
  if memory_idx != 0U {
    append_bytes(payload, encode_u32_leb128(memory_idx))
  }
  append_bytes(payload, encode_u32_leb128(offset))
  payload
}

///|
fn encode_table_type(
  table_type : @core.TableType,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match table_type.init {
    Some(init_expr) => {
      payload.push(0x40U.to_byte())
      payload.push(0x00U.to_byte())
      append_bytes(
        payload,
        encode_reftype(table_type.elem_type, table_type.nullable),
      )
      append_bytes(payload, encode_limits(table_type.limits))
      append_bytes(payload, encode_expr(init_expr))
    }
    None => {
      append_bytes(
        payload,
        encode_reftype(table_type.elem_type, table_type.nullable),
      )
      append_bytes(payload, encode_limits(table_type.limits))
    }
  }
  payload
}

///|
fn encode_simd_immediate(
  imm : @core.SimdImmediate,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match imm {
    None => ()
    MemArg(align, offset, memory_idx) =>
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    Lane(lane) => payload.push(lane.to_byte())
    MemArgLane(align, offset, memory_idx, lane) => {
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
      payload.push(lane.to_byte())
    }
    Shuffle(bytes) | V128Const(bytes) => {
      guard bytes.length() == 16 else {
        raise EncodeError::Unsupported(
          "simd immediate length \{bytes.length()}",
        )
      }
      for b in bytes {
        payload.push(b)
      }
    }
  }
  payload
}

///|
fn encode_atomic_immediate(
  imm : @core.AtomicImmediate,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match imm {
    None => ()
    MemArg(align, offset, memory_idx) =>
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    Fence(flags) => payload.push(flags.to_byte())
  }
  payload
}

///|
fn encode_instr(instr : @core.Instr) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match instr {
    Unreachable => payload.push(0x00U.to_byte())
    Nop => payload.push(0x01U.to_byte())
    Block(block_type, instrs) => {
      payload.push(0x02U.to_byte())
      append_bytes(payload, encode_block_type(block_type))
      for item in instrs {
        append_bytes(payload, encode_instr(item))
      }
      payload.push(0x0BU.to_byte())
    }
    Loop(block_type, instrs) => {
      payload.push(0x03U.to_byte())
      append_bytes(payload, encode_block_type(block_type))
      for item in instrs {
        append_bytes(payload, encode_instr(item))
      }
      payload.push(0x0BU.to_byte())
    }
    If(block_type, then_instrs, else_instrs) => {
      payload.push(0x04U.to_byte())
      append_bytes(payload, encode_block_type(block_type))
      for item in then_instrs {
        append_bytes(payload, encode_instr(item))
      }
      if else_instrs.length() > 0 {
        payload.push(0x05U.to_byte())
        for item in else_instrs {
          append_bytes(payload, encode_instr(item))
        }
      }
      payload.push(0x0BU.to_byte())
    }
    TryTable(block_type, catches, instrs) => {
      payload.push(0x1FU.to_byte())
      append_bytes(payload, encode_block_type(block_type))
      append_bytes(
        payload,
        encode_u32_leb128(catches.length().reinterpret_as_uint()),
      )
      for clause in catches {
        match clause {
          Catch(tag_idx, label_idx) => {
            payload.push(0x00U.to_byte())
            append_bytes(payload, encode_u32_leb128(tag_idx))
            append_bytes(payload, encode_u32_leb128(label_idx))
          }
          CatchRef(tag_idx, label_idx) => {
            payload.push(0x01U.to_byte())
            append_bytes(payload, encode_u32_leb128(tag_idx))
            append_bytes(payload, encode_u32_leb128(label_idx))
          }
          CatchAll(label_idx) => {
            payload.push(0x02U.to_byte())
            append_bytes(payload, encode_u32_leb128(label_idx))
          }
          CatchAllRef(label_idx) => {
            payload.push(0x03U.to_byte())
            append_bytes(payload, encode_u32_leb128(label_idx))
          }
        }
      }
      for item in instrs {
        append_bytes(payload, encode_instr(item))
      }
      payload.push(0x0BU.to_byte())
    }
    Br(idx) => {
      payload.push(0x0CU.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    BrIf(idx) => {
      payload.push(0x0DU.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    BrOnNull(idx) => {
      payload.push(0xD5U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    BrOnNonNull(idx) => {
      payload.push(0xD6U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    BrTable(targets, default_target) => {
      payload.push(0x0EU.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(targets.length().reinterpret_as_uint()),
      )
      for target in targets {
        append_bytes(payload, encode_u32_leb128(target))
      }
      append_bytes(payload, encode_u32_leb128(default_target))
    }
    Drop => payload.push(0x1AU.to_byte())
    Select => payload.push(0x1BU.to_byte())
    SelectTyped(types) => {
      payload.push(0x1CU.to_byte())
      append_bytes(
        payload,
        encode_u32_leb128(types.length().reinterpret_as_uint()),
      )
      for val_type in types {
        append_bytes(payload, encode_valtype(val_type))
      }
    }
    Return => payload.push(0x0FU.to_byte())
    Throw(idx) => {
      payload.push(0x08U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    Rethrow(idx) => {
      payload.push(0x09U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    Call(idx) => {
      payload.push(0x10U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    CallIndirect(type_idx, table_idx) => {
      payload.push(0x11U.to_byte())
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(table_idx))
    }
    ReturnCall(idx) => {
      payload.push(0x12U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      payload.push(0x13U.to_byte())
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(table_idx))
    }
    CallRef(type_idx) => {
      payload.push(0x14U.to_byte())
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ReturnCallRef(type_idx) => {
      payload.push(0x15U.to_byte())
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    Simd(simd) => {
      payload.push(0xFDU.to_byte())
      append_bytes(payload, encode_u32_leb128(simd.opcode))
      append_bytes(payload, encode_simd_immediate(simd.imm))
    }
    Atomic(atomic_instr) => {
      payload.push(0xFEU.to_byte())
      append_bytes(payload, encode_u32_leb128(atomic_instr.opcode))
      append_bytes(payload, encode_atomic_immediate(atomic_instr.imm))
    }
    RefNull(ref_type) => {
      payload.push(0xD0U.to_byte())
      append_bytes(payload, encode_heap_type(ref_type))
    }
    RefFunc(idx) => {
      payload.push(0xD2U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    TableGet(idx) => {
      payload.push(0x25U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    TableSet(idx) => {
      payload.push(0x26U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    TableSize(idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(16U))
      append_bytes(payload, encode_u32_leb128(idx))
    }
    TableGrow(idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(15U))
      append_bytes(payload, encode_u32_leb128(idx))
    }
    TableInit(table_idx, elem_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(12U))
      append_bytes(payload, encode_u32_leb128(elem_idx))
      append_bytes(payload, encode_u32_leb128(table_idx))
    }
    TableCopy(dst_idx, src_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(14U))
      append_bytes(payload, encode_u32_leb128(dst_idx))
      append_bytes(payload, encode_u32_leb128(src_idx))
    }
    TableFill(idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(17U))
      append_bytes(payload, encode_u32_leb128(idx))
    }
    ElemDrop(idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(13U))
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalGet(idx) => {
      payload.push(0x20U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalSet(idx) => {
      payload.push(0x21U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    LocalTee(idx) => {
      payload.push(0x22U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    GlobalGet(idx) => {
      payload.push(0x23U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    GlobalSet(idx) => {
      payload.push(0x24U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    I32Const(value) => {
      payload.push(0x41U.to_byte())
      append_bytes(payload, encode_i32_leb128(value.reinterpret_as_int()))
    }
    I64Const(value) => {
      payload.push(0x42U.to_byte())
      append_bytes(payload, encode_i64_leb128(value.reinterpret_as_int64()))
    }
    F32Const(value) => {
      payload.push(0x43U.to_byte())
      append_u32_le(payload, value.reinterpret_as_uint())
    }
    F64Const(value) => {
      payload.push(0x44U.to_byte())
      append_u64_le(payload, value.reinterpret_as_uint64())
    }
    I32Load(align, offset, memory_idx) => {
      payload.push(0x28U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load(align, offset, memory_idx) => {
      payload.push(0x29U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    F32Load(align, offset, memory_idx) => {
      payload.push(0x2AU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    F64Load(align, offset, memory_idx) => {
      payload.push(0x2BU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Load8S(align, offset, memory_idx) => {
      payload.push(0x2CU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Load8U(align, offset, memory_idx) => {
      payload.push(0x2DU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Load16S(align, offset, memory_idx) => {
      payload.push(0x2EU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Load16U(align, offset, memory_idx) => {
      payload.push(0x2FU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load8S(align, offset, memory_idx) => {
      payload.push(0x30U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load8U(align, offset, memory_idx) => {
      payload.push(0x31U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load16S(align, offset, memory_idx) => {
      payload.push(0x32U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load16U(align, offset, memory_idx) => {
      payload.push(0x33U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load32S(align, offset, memory_idx) => {
      payload.push(0x34U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Load32U(align, offset, memory_idx) => {
      payload.push(0x35U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Store(align, offset, memory_idx) => {
      payload.push(0x36U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Store(align, offset, memory_idx) => {
      payload.push(0x37U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    F32Store(align, offset, memory_idx) => {
      payload.push(0x38U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    F64Store(align, offset, memory_idx) => {
      payload.push(0x39U.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Store8(align, offset, memory_idx) => {
      payload.push(0x3AU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I32Store16(align, offset, memory_idx) => {
      payload.push(0x3BU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Store8(align, offset, memory_idx) => {
      payload.push(0x3CU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Store16(align, offset, memory_idx) => {
      payload.push(0x3DU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    I64Store32(align, offset, memory_idx) => {
      payload.push(0x3EU.to_byte())
      append_bytes(payload, encode_memarg(align, offset, memory_idx))
    }
    MemorySize(idx) => {
      payload.push(0x3FU.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    MemoryGrow(idx) => {
      payload.push(0x40U.to_byte())
      append_bytes(payload, encode_u32_leb128(idx))
    }
    RefIsNull => payload.push(0xD1U.to_byte())
    RefEq => payload.push(0xD3U.to_byte())
    RefAsNonNull => payload.push(0xD4U.to_byte())
    RefTest(ref_type, nullable) => {
      payload.push(0xFBU.to_byte())
      let opcode = if nullable { 0x15U } else { 0x14U }
      append_bytes(payload, encode_u32_leb128(opcode))
      append_bytes(payload, encode_heap_type(ref_type))
    }
    RefCast(ref_type, nullable) => {
      payload.push(0xFBU.to_byte())
      let opcode = if nullable { 0x17U } else { 0x16U }
      append_bytes(payload, encode_u32_leb128(opcode))
      append_bytes(payload, encode_heap_type(ref_type))
    }
    StructNew(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x00U))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    StructNewDefault(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x01U))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    StructGet(type_idx, field_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x02U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(field_idx))
    }
    StructGetS(type_idx, field_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x03U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(field_idx))
    }
    StructGetU(type_idx, field_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x04U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(field_idx))
    }
    StructSet(type_idx, field_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x05U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(field_idx))
    }
    ArrayNew(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x06U))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayNewDefault(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x07U))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayNewFixed(type_idx, len) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x08U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(len))
    }
    ArrayNewData(type_idx, data_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x09U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(data_idx))
    }
    ArrayNewElem(type_idx, elem_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0AU))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(elem_idx))
    }
    ArrayGet(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0BU))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayGetS(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0CU))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayGetU(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0DU))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArraySet(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0EU))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayLen => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x0FU))
    }
    ArrayFill(type_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x10U))
      append_bytes(payload, encode_u32_leb128(type_idx))
    }
    ArrayCopy(dst_type, src_type) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x11U))
      append_bytes(payload, encode_u32_leb128(dst_type))
      append_bytes(payload, encode_u32_leb128(src_type))
    }
    ArrayInitData(type_idx, data_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x12U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(data_idx))
    }
    ArrayInitElem(type_idx, elem_idx) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x13U))
      append_bytes(payload, encode_u32_leb128(type_idx))
      append_bytes(payload, encode_u32_leb128(elem_idx))
    }
    BrOnCast(label, target_type, target_nullable, source_type, source_nullable) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x18U))
      let mut flags = 0U
      if target_nullable {
        flags = flags | 0x01U
      }
      if source_nullable {
        flags = flags | 0x02U
      }
      payload.push(flags.to_byte())
      append_bytes(payload, encode_u32_leb128(label))
      append_bytes(payload, encode_heap_type(target_type))
      append_bytes(payload, encode_heap_type(source_type))
    }
    BrOnCastFail(
      label,
      target_type,
      target_nullable,
      source_type,
      source_nullable
    ) => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x19U))
      let mut flags = 0U
      if target_nullable {
        flags = flags | 0x01U
      }
      if source_nullable {
        flags = flags | 0x02U
      }
      payload.push(flags.to_byte())
      append_bytes(payload, encode_u32_leb128(label))
      append_bytes(payload, encode_heap_type(target_type))
      append_bytes(payload, encode_heap_type(source_type))
    }
    AnyConvertExtern => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x1AU))
    }
    ExternConvertAny => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x1BU))
    }
    RefI31 => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x1CU))
    }
    I31GetS => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x1DU))
    }
    I31GetU => {
      payload.push(0xFBU.to_byte())
      append_bytes(payload, encode_u32_leb128(0x1EU))
    }
    MemoryInit(data_idx, mem_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(8U))
      append_bytes(payload, encode_u32_leb128(data_idx))
      append_bytes(payload, encode_u32_leb128(mem_idx))
    }
    DataDrop(data_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(9U))
      append_bytes(payload, encode_u32_leb128(data_idx))
    }
    MemoryCopy(dst_idx, src_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(10U))
      append_bytes(payload, encode_u32_leb128(dst_idx))
      append_bytes(payload, encode_u32_leb128(src_idx))
    }
    MemoryFill(mem_idx) => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(11U))
      append_bytes(payload, encode_u32_leb128(mem_idx))
    }
    I32Eqz => payload.push(0x45U.to_byte())
    I32Eq => payload.push(0x46U.to_byte())
    I32Ne => payload.push(0x47U.to_byte())
    I32LtS => payload.push(0x48U.to_byte())
    I32LtU => payload.push(0x49U.to_byte())
    I32GtS => payload.push(0x4AU.to_byte())
    I32GtU => payload.push(0x4BU.to_byte())
    I32LeS => payload.push(0x4CU.to_byte())
    I32LeU => payload.push(0x4DU.to_byte())
    I32GeS => payload.push(0x4EU.to_byte())
    I32GeU => payload.push(0x4FU.to_byte())
    I64Eqz => payload.push(0x50U.to_byte())
    I64Eq => payload.push(0x51U.to_byte())
    I64Ne => payload.push(0x52U.to_byte())
    I64LtS => payload.push(0x53U.to_byte())
    I64LtU => payload.push(0x54U.to_byte())
    I64GtS => payload.push(0x55U.to_byte())
    I64GtU => payload.push(0x56U.to_byte())
    I64LeS => payload.push(0x57U.to_byte())
    I64LeU => payload.push(0x58U.to_byte())
    I64GeS => payload.push(0x59U.to_byte())
    I64GeU => payload.push(0x5AU.to_byte())
    F32Eq => payload.push(0x5BU.to_byte())
    F32Ne => payload.push(0x5CU.to_byte())
    F32Lt => payload.push(0x5DU.to_byte())
    F32Gt => payload.push(0x5EU.to_byte())
    F32Le => payload.push(0x5FU.to_byte())
    F32Ge => payload.push(0x60U.to_byte())
    F64Eq => payload.push(0x61U.to_byte())
    F64Ne => payload.push(0x62U.to_byte())
    F64Lt => payload.push(0x63U.to_byte())
    F64Gt => payload.push(0x64U.to_byte())
    F64Le => payload.push(0x65U.to_byte())
    F64Ge => payload.push(0x66U.to_byte())
    I32Clz => payload.push(0x67U.to_byte())
    I32Ctz => payload.push(0x68U.to_byte())
    I32Popcnt => payload.push(0x69U.to_byte())
    I32Add => payload.push(0x6AU.to_byte())
    I32Sub => payload.push(0x6BU.to_byte())
    I32Mul => payload.push(0x6CU.to_byte())
    I32DivS => payload.push(0x6DU.to_byte())
    I32DivU => payload.push(0x6EU.to_byte())
    I32RemS => payload.push(0x6FU.to_byte())
    I32RemU => payload.push(0x70U.to_byte())
    I32And => payload.push(0x71U.to_byte())
    I32Or => payload.push(0x72U.to_byte())
    I32Xor => payload.push(0x73U.to_byte())
    I32Shl => payload.push(0x74U.to_byte())
    I32ShrS => payload.push(0x75U.to_byte())
    I32ShrU => payload.push(0x76U.to_byte())
    I32Rotl => payload.push(0x77U.to_byte())
    I32Rotr => payload.push(0x78U.to_byte())
    I64Clz => payload.push(0x79U.to_byte())
    I64Ctz => payload.push(0x7AU.to_byte())
    I64Popcnt => payload.push(0x7BU.to_byte())
    I64Add => payload.push(0x7CU.to_byte())
    I64Sub => payload.push(0x7DU.to_byte())
    I64Mul => payload.push(0x7EU.to_byte())
    I64DivS => payload.push(0x7FU.to_byte())
    I64DivU => payload.push(0x80U.to_byte())
    I64RemS => payload.push(0x81U.to_byte())
    I64RemU => payload.push(0x82U.to_byte())
    I64And => payload.push(0x83U.to_byte())
    I64Or => payload.push(0x84U.to_byte())
    I64Xor => payload.push(0x85U.to_byte())
    I64Shl => payload.push(0x86U.to_byte())
    I64ShrS => payload.push(0x87U.to_byte())
    I64ShrU => payload.push(0x88U.to_byte())
    I64Rotl => payload.push(0x89U.to_byte())
    I64Rotr => payload.push(0x8AU.to_byte())
    F32Abs => payload.push(0x8BU.to_byte())
    F32Neg => payload.push(0x8CU.to_byte())
    F32Ceil => payload.push(0x8DU.to_byte())
    F32Floor => payload.push(0x8EU.to_byte())
    F32Trunc => payload.push(0x8FU.to_byte())
    F32Nearest => payload.push(0x90U.to_byte())
    F32Sqrt => payload.push(0x91U.to_byte())
    F32Add => payload.push(0x92U.to_byte())
    F32Sub => payload.push(0x93U.to_byte())
    F32Mul => payload.push(0x94U.to_byte())
    F32Div => payload.push(0x95U.to_byte())
    F32Min => payload.push(0x96U.to_byte())
    F32Max => payload.push(0x97U.to_byte())
    F32Copysign => payload.push(0x98U.to_byte())
    F64Abs => payload.push(0x99U.to_byte())
    F64Neg => payload.push(0x9AU.to_byte())
    F64Ceil => payload.push(0x9BU.to_byte())
    F64Floor => payload.push(0x9CU.to_byte())
    F64Trunc => payload.push(0x9DU.to_byte())
    F64Nearest => payload.push(0x9EU.to_byte())
    F64Sqrt => payload.push(0x9FU.to_byte())
    F64Add => payload.push(0xA0U.to_byte())
    F64Sub => payload.push(0xA1U.to_byte())
    F64Mul => payload.push(0xA2U.to_byte())
    F64Div => payload.push(0xA3U.to_byte())
    F64Min => payload.push(0xA4U.to_byte())
    F64Max => payload.push(0xA5U.to_byte())
    F64Copysign => payload.push(0xA6U.to_byte())
    I32WrapI64 => payload.push(0xA7U.to_byte())
    I32TruncF32S => payload.push(0xA8U.to_byte())
    I32TruncF32U => payload.push(0xA9U.to_byte())
    I32TruncF64S => payload.push(0xAAU.to_byte())
    I32TruncF64U => payload.push(0xABU.to_byte())
    I64ExtendI32S => payload.push(0xACU.to_byte())
    I64ExtendI32U => payload.push(0xADU.to_byte())
    I64TruncF32S => payload.push(0xAEU.to_byte())
    I64TruncF32U => payload.push(0xAFU.to_byte())
    I64TruncF64S => payload.push(0xB0U.to_byte())
    I64TruncF64U => payload.push(0xB1U.to_byte())
    F32ConvertI32S => payload.push(0xB2U.to_byte())
    F32ConvertI32U => payload.push(0xB3U.to_byte())
    F32ConvertI64S => payload.push(0xB4U.to_byte())
    F32ConvertI64U => payload.push(0xB5U.to_byte())
    F32DemoteF64 => payload.push(0xB6U.to_byte())
    F64ConvertI32S => payload.push(0xB7U.to_byte())
    F64ConvertI32U => payload.push(0xB8U.to_byte())
    F64ConvertI64S => payload.push(0xB9U.to_byte())
    F64ConvertI64U => payload.push(0xBAU.to_byte())
    F64PromoteF32 => payload.push(0xBBU.to_byte())
    I32ReinterpretF32 => payload.push(0xBCU.to_byte())
    I64ReinterpretF64 => payload.push(0xBDU.to_byte())
    F32ReinterpretI32 => payload.push(0xBEU.to_byte())
    F64ReinterpretI64 => payload.push(0xBFU.to_byte())
    I32Extend8S => payload.push(0xC0U.to_byte())
    I32Extend16S => payload.push(0xC1U.to_byte())
    I64Extend8S => payload.push(0xC2U.to_byte())
    I64Extend16S => payload.push(0xC3U.to_byte())
    I64Extend32S => payload.push(0xC4U.to_byte())
    I32TruncSatF32S => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(0U))
    }
    I32TruncSatF32U => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(1U))
    }
    I32TruncSatF64S => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(2U))
    }
    I32TruncSatF64U => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(3U))
    }
    I64TruncSatF32S => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(4U))
    }
    I64TruncSatF32U => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(5U))
    }
    I64TruncSatF64S => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(6U))
    }
    I64TruncSatF64U => {
      payload.push(0xFCU.to_byte())
      append_bytes(payload, encode_u32_leb128(7U))
    }
    _ => raise EncodeError::Unsupported("instruction \{instr}")
  }
  payload
}

///|
fn encode_valtype(val_type : @core.ValType) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match val_type {
    I32 => payload.push(0x7FU.to_byte())
    I64 => payload.push(0x7EU.to_byte())
    F32 => payload.push(0x7DU.to_byte())
    F64 => payload.push(0x7CU.to_byte())
    V128 => payload.push(0x7BU.to_byte())
    FuncRef => payload.push(0x70U.to_byte())
    ExternRef => payload.push(0x6FU.to_byte())
    AnyRef => payload.push(0x6EU.to_byte())
    EqRef => payload.push(0x6DU.to_byte())
    I31Ref => payload.push(0x6CU.to_byte())
    StructRef => payload.push(0x6BU.to_byte())
    ArrayRef => payload.push(0x6AU.to_byte())
    ExnRef => payload.push(0x69U.to_byte())
    NullRef => payload.push(0x71U.to_byte())
    NullExternRef => payload.push(0x72U.to_byte())
    NullFuncRef => payload.push(0x73U.to_byte())
    NullExnRef => payload.push(0x74U.to_byte())
    Ref(ref_type, nullable) =>
      append_bytes(payload, encode_reftype(ref_type, nullable))
    _ => raise EncodeError::Unsupported("valtype \{val_type}")
  }
  payload
}

///|
fn encode_storage_type(
  storage_type : @core.StorageType,
) -> Array[Byte] raise EncodeError {
  let payload : Array[Byte] = []
  match storage_type {
    I8 => payload.push(0x78U.to_byte())
    I16 => payload.push(0x77U.to_byte())
    Val(val_type) => append_bytes(payload, encode_valtype(val_type))
  }
  payload
}

///|
fn encode_reftype(ref_type : @core.RefType, nullable : Bool) -> Array[Byte] {
  let payload : Array[Byte] = []
  if nullable {
    match ref_type {
      Func => payload.push(0x70U.to_byte())
      Extern => payload.push(0x6FU.to_byte())
      Any => payload.push(0x6EU.to_byte())
      Eq => payload.push(0x6DU.to_byte())
      I31 => payload.push(0x6CU.to_byte())
      Struct => payload.push(0x6BU.to_byte())
      Array => payload.push(0x6AU.to_byte())
      Exn => payload.push(0x69U.to_byte())
      None => payload.push(0x71U.to_byte())
      NoExtern => payload.push(0x72U.to_byte())
      NoFunc => payload.push(0x73U.to_byte())
      NoExn => payload.push(0x74U.to_byte())
      TypeIndex(_) => {
        payload.push(0x63U.to_byte())
        append_bytes(payload, encode_heap_type(ref_type))
      }
    }
  } else {
    payload.push(0x64U.to_byte())
    append_bytes(payload, encode_heap_type(ref_type))
  }
  payload
}

///|
fn encode_heap_type(ref_type : @core.RefType) -> Array[Byte] {
  let payload : Array[Byte] = []
  match ref_type {
    Func => payload.push(0x70U.to_byte())
    Extern => payload.push(0x6FU.to_byte())
    Any => payload.push(0x6EU.to_byte())
    Eq => payload.push(0x6DU.to_byte())
    I31 => payload.push(0x6CU.to_byte())
    Struct => payload.push(0x6BU.to_byte())
    Array => payload.push(0x6AU.to_byte())
    Exn => payload.push(0x69U.to_byte())
    None => payload.push(0x71U.to_byte())
    NoExtern => payload.push(0x72U.to_byte())
    NoFunc => payload.push(0x73U.to_byte())
    NoExn => payload.push(0x74U.to_byte())
    TypeIndex(idx) => append_bytes(payload, encode_i32_leb128(idx))
  }
  payload
}

///|
fn append_name(dst : Array[Byte], name : Bytes) -> Unit {
  append_bytes(dst, encode_u32_leb128(name.length().reinterpret_as_uint()))
  for b in name {
    dst.push(b)
  }
}

///|
fn encode_u32_leb128(value : UInt) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let mut byte = (v & 0x7FU).to_byte()
    v = v >> 7
    if v != 0U {
      byte = (byte.to_uint() | 0x80U).to_byte()
      out.push(byte)
    } else {
      out.push(byte)
      break
    }
  }
  out
}

///|
fn encode_i32_leb128(value : Int) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let byte_val = v & 0x7F
    let byte = byte_val.reinterpret_as_uint().to_byte()
    let sign = (byte_val & 0x40) != 0
    v = v >> 7
    let done = (v == 0 && not(sign)) || (v == -1 && sign)
    if done {
      out.push(byte)
      break
    } else {
      out.push((byte.to_uint() | 0x80U).to_byte())
    }
  }
  out
}

///|
fn encode_i64_leb128(value : Int64) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let byte_val = v & 0x7FL
    let byte = byte_val.reinterpret_as_uint64().to_uint().to_byte()
    let sign = (byte_val & 0x40L) != 0L
    v = v >> 7
    let done = (v == 0L && not(sign)) || (v == -1L && sign)
    if done {
      out.push(byte)
      break
    } else {
      out.push((byte.to_uint() | 0x80U).to_byte())
    }
  }
  out
}
