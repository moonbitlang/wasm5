///|
fn validate_instruction_table(
  module_ : @core.Module,
  ctx : ValidationCtx,
  instr : @core.Instr,
) -> Bool raise ValidationError {
  let stack = ctx.stack
  match instr {
    // Table bulk operations (stub for now)
    TableInit(_, _) => {
      ctx.poly_pop_expect(module_, I32, "table.init n")
      ctx.poly_pop_expect(module_, I32, "table.init src")
      ctx.poly_pop_expect(module_, I32, "table.init dest")
    }
    TableCopy(_, _) => {
      ctx.poly_pop_expect(module_, I32, "table.copy n")
      ctx.poly_pop_expect(module_, I32, "table.copy src")
      ctx.poly_pop_expect(module_, I32, "table.copy dest")
    }
    TableFill(table_idx) => {
      ctx.poly_pop_expect(module_, I32, "table.fill n")
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        Func
      }
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
      ctx.poly_pop_expect(module_, I32, "table.fill dest")
    }
    ElemDrop(_) => ()

    // Table instructions
    TableSize(_) => stack.push(I32)
    TableGet(table_idx) => {
      ctx.poly_pop_expect(module_, I32, "table.get index")
      // Look up table's element type
      let elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        let table = module_.tables[table_idx.reinterpret_as_int()]
        reftype_to_valtype(table.elem_type)
      } else {
        FuncRef // Default if table not found
      }
      stack.push(elem_type)
    }
    TableSet(table_idx) => {
      // table.set: pop value (top), then index (below)
      // Get table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : @core.ValType = reftype_to_valtype(table_elem_type)

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

      // Pop index (i32)
      ctx.poly_pop_expect(module_, I32, "table.set index")
    }
    TableGrow(table_idx) => {
      ctx.poly_pop_expect(module_, I32, "table.grow delta")
      // Pop init value and check it matches table's element type
      let table_elem_type = if table_idx.reinterpret_as_int() <
        module_.tables.length() {
        module_.tables[table_idx.reinterpret_as_int()].elem_type
      } else {
        Func // Default, will be caught elsewhere if invalid
      }
      let expected_type : @core.ValType = reftype_to_valtype(table_elem_type)
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
      stack.push(I32) // Returns old size
    }
    _ => return false
  }
  true
}
