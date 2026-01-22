///|
fn validate_instruction_table(
  module_ : @core.Module,
  ctx : ValidationCtx,
  import_counts : ImportCounts,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    // Table bulk operations (index type depends on table64)
    TableInit(table_idx, elem_idx) => {
      let table_type = get_table_type(module_, import_counts, table_idx)
      let idx_type = table_index_type(table_type)
      ctx.poly_pop_expect(module_, idx_type, "table.init n")
      ctx.poly_pop_expect(module_, idx_type, "table.init src")
      ctx.poly_pop_expect(module_, idx_type, "table.init dest")

      // Check element segment exists and its type is compatible with table
      let elem_idx_int = elem_idx.reinterpret_as_int()
      if elem_idx_int < 0 || elem_idx_int >= module_.elems.length() {
        raise ValidationError::InvalidElemIndex(elem_idx_int)
      }
      let elem = module_.elems[elem_idx_int]
      let elem_type = @core.ValType::Ref(elem.elem_type, elem.elem_nullable)
      let table_elem_type = @core.ValType::Ref(
        table_type.elem_type,
        table_type.nullable,
      )
      guard is_subtype(module_, elem_type, table_elem_type) else {
        raise ValidationError::TypeMismatch(
          "table.init: element segment type \{elem_type} is not compatible with table element type \{table_elem_type}",
        )
      }
    }
    TableCopy(dst_idx, src_idx) => {
      let dst_type = get_table_type(module_, import_counts, dst_idx)
      let src_type = get_table_type(module_, import_counts, src_idx)
      guard dst_type.table64 == src_type.table64 else {
        raise ValidationError::TypeMismatch(
          "table.copy requires matching table index types",
        )
      }
      // Check that source element type is subtype of destination element type
      let src_elem = @core.ValType::Ref(src_type.elem_type, src_type.nullable)
      let dst_elem = @core.ValType::Ref(dst_type.elem_type, dst_type.nullable)
      guard is_subtype(module_, src_elem, dst_elem) else {
        raise ValidationError::TypeMismatch(
          "table.copy: source element type is not compatible with destination",
        )
      }
      let idx_type = table_index_type(dst_type)
      ctx.poly_pop_expect(module_, idx_type, "table.copy n")
      ctx.poly_pop_expect(module_, idx_type, "table.copy src")
      ctx.poly_pop_expect(module_, idx_type, "table.copy dest")
    }
    TableFill(table_idx) => {
      let table_type = get_table_type(module_, import_counts, table_idx)
      let idx_type = table_index_type(table_type)
      ctx.poly_pop_expect(module_, idx_type, "table.fill n")
      let table_elem_type = table_type.elem_type
      let expected_type : @core.ValType = reftype_to_valtype(table_elem_type)
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("table.fill expects value on stack")
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.fill value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }
      ctx.poly_pop_expect(module_, idx_type, "table.fill dest")
    }
    ElemDrop(elem_idx) => {
      let elem_idx_int = elem_idx.reinterpret_as_int()
      if elem_idx_int < 0 || elem_idx_int >= module_.elems.length() {
        raise ValidationError::InvalidElemIndex(elem_idx_int)
      }
    }

    // Table instructions
    TableSize(table_idx) => {
      let table_type = get_table_type(module_, import_counts, table_idx)
      stack.push(table_index_type(table_type))
    }
    TableGet(table_idx) => {
      let table_type = get_table_type(module_, import_counts, table_idx)
      let idx_type = table_index_type(table_type)
      ctx.poly_pop_expect(module_, idx_type, "table.get index")
      stack.push(reftype_to_valtype(table_type.elem_type))
    }
    TableSet(table_idx) => {
      // table.set: pop value (top), then index (below)
      // Get table's element type
      let table_type = get_table_type(module_, import_counts, table_idx)
      let idx_type = table_index_type(table_type)
      let expected_type : @core.ValType = reftype_to_valtype(
        table_type.elem_type,
      )

      // Pop and verify value type matches table element type
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch("table.set expects value on stack")
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.set value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }

      // Pop index
      ctx.poly_pop_expect(module_, idx_type, "table.set index")
    }
    TableGrow(table_idx) => {
      let table_type = get_table_type(module_, import_counts, table_idx)
      let idx_type = table_index_type(table_type)
      ctx.poly_pop_expect(module_, idx_type, "table.grow delta")
      // Pop init value and check it matches table's element type
      let expected_type : @core.ValType = reftype_to_valtype(
        table_type.elem_type,
      )
      if ctx.is_unreachable && stack.length() == 0 {
        // Polymorphic - allow
      } else if stack.length() < 1 {
        raise ValidationError::TypeMismatch(
          "table.grow expects init value on stack",
        )
      } else {
        let actual_type = stack.unsafe_pop()
        if not(is_subtype(module_, actual_type, expected_type)) {
          raise ValidationError::TypeMismatch(
            "table.grow init value type mismatch: expected \{expected_type}, got \{actual_type}",
          )
        }
      }
      stack.push(idx_type) // Returns old size
    }
    _ => return false
  }
  true
}
