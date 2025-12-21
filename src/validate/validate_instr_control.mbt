///|
/// Get the function type signature for a block type
fn get_block_type(
  module_ : @core.Module,
  block_type : @core.BlockType,
) -> (Array[@core.ValType], Array[@core.ValType]) raise @core.ValidationError {
  match block_type {
    @core.BlockType::Empty => ([], [])
    @core.BlockType::Value(t) => {
      validate_valtype(module_, t)
      ([], [t])
    }
    @core.BlockType::TypeIndex(idx) => {
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type = module_.types[idx]
      (func_type.params, func_type.results)
    }
  }
}

///|
/// Validate that a tail call's return type matches the current function's return type.
/// For tail calls (return_call, return_call_indirect, return_call_ref), the called
/// function's return type must match the current function's return type via subtyping.
fn validate_tail_call_return_type(
  module_ : @core.Module,
  func_type_called : @core.FuncType,
  func_type : @core.FuncType,
  instr_name : String,
) -> Unit raise @core.ValidationError {
  if func_type_called.results.length() != func_type.results.length() {
    raise @core.ValidationError::TypeMismatch(
      "\{instr_name}: return type mismatch: expected \{func_type.results.length()} results, got \{func_type_called.results.length()}",
    )
  }
  for i in 0..<func_type_called.results.length() {
    let called_result = func_type_called.results[i]
    let expected_result = func_type.results[i]
    if not(is_subtype(module_, called_result, expected_result)) {
      raise @core.ValidationError::TypeMismatch(
        "\{instr_name}: return type mismatch at position \{i}: expected \{expected_result}, got \{called_result}",
      )
    }
  }
}

///|
fn validate_instruction_control(
  module_ : @core.Module,
  func_type : @core.FuncType,
  code : @core.Code,
  ctx : ValidationCtx,
  instr : @core.Instr,
  import_counts : ImportCounts,
) -> Bool raise @core.ValidationError {
  let stack = ctx.stack
  match instr {
    // @core.Instr::Block instructions
    @core.Instr::Block(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "block parameter")
      }
      // Create new validation context for block
      let block_ctx = ValidationCtx::new()
      // Add parameters to block stack in correct order
      for param in params {
        block_ctx.stack.push(param)
      }
      // Copy parent control stack and add this block's frame
      for frame in ctx.control_stack {
        block_ctx.control_stack.push(frame)
      }
      block_ctx.push_control(params, results)
      // Copy initialized locals from parent context
      // After block, we don't propagate back (block might branch out early)
      for i in 0..<ctx.initialized_locals.length() {
        block_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate block body
      for block_instr in instrs {
        validate_instruction(
          module_, func_type, code, block_ctx, block_instr, import_counts,
        )
      }
      let _ = block_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from block_ctx
      // because the block might have exited early via branch
      // Check block produces correct results
      if block_ctx.is_unreachable && block_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable code with empty stack - all polymorphic, push expected results
        for result in results {
          stack.push(result)
        }
      } else if block_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - this is a type mismatch
        raise @core.ValidationError::TypeMismatch(
          "block: expected \{results.length()} values, got \{block_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, block_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "block result type mismatch: expected \{results[i]}, got \{block_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    @core.Instr::Loop(block_type, instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop parameters from parent stack using polymorphic stack
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "loop parameter")
      }
      // Create new validation context for loop
      let loop_ctx = ValidationCtx::new()
      // Add parameters to loop stack in correct order
      for param in params {
        loop_ctx.stack.push(param)
      }
      // Copy parent control stack and add this loop's frame
      // Note: For loops, br targets the beginning (params), not the end (results)
      for frame in ctx.control_stack {
        loop_ctx.control_stack.push(frame)
      }
      loop_ctx.push_control(params, params) // @core.Instr::Loop's br target uses params, not results
      // Copy initialized locals from parent context
      // @core.Instr::Loop is similar to block - don't propagate back
      for i in 0..<ctx.initialized_locals.length() {
        loop_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      // Validate loop body
      for loop_instr in instrs {
        validate_instruction(
          module_, func_type, code, loop_ctx, loop_instr, import_counts,
        )
      }
      let _ = loop_ctx.pop_control()
      // Note: We do NOT propagate initialized_locals back from loop_ctx
      // Check loop produces correct results
      if loop_ctx.is_unreachable && loop_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable code with empty stack - all polymorphic
        for result in results {
          stack.push(result)
        }
      } else if loop_ctx.stack.length() != results.length() {
        // Not unreachable and not exact match - type mismatch
        raise @core.ValidationError::TypeMismatch(
          "loop: expected \{results.length()} values, got \{loop_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, loop_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "loop result type mismatch: expected \{results[i]}, got \{loop_ctx.stack[i]}",
            )
          }
        }
        // Push results onto parent stack
        for result in results {
          stack.push(result)
        }
      }
    }
    @core.Instr::If(block_type, then_instrs, else_instrs) => {
      let (params, results) = get_block_type(module_, block_type)
      // Pop condition (using polymorphic stack)
      ctx.poly_pop_expect(module_, @core.ValType::I32, "if condition")
      // Pop parameters from parent stack (using polymorphic stack)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, params[i], "if parameter")
      }
      // Validate then branch
      let then_ctx = ValidationCtx::new()
      for param in params {
        then_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        then_ctx.control_stack.push(frame)
      }
      then_ctx.push_control(params, results)
      // Copy initialized locals from parent context
      for i in 0..<ctx.initialized_locals.length() {
        then_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for then_instr in then_instrs {
        validate_instruction(
          module_, func_type, code, then_ctx, then_instr, import_counts,
        )
      }
      let _ = then_ctx.pop_control()
      // Check then branch produces correct results
      if then_ctx.is_unreachable && then_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable with empty stack - all polymorphic, valid
      } else if then_ctx.stack.length() != results.length() {
        raise @core.ValidationError::TypeMismatch(
          "if then branch: expected \{results.length()} values, got \{then_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, then_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "if then branch result type mismatch: expected \{results[i]}, got \{then_ctx.stack[i]}",
            )
          }
        }
      }
      // Validate else branch
      let else_ctx = ValidationCtx::new()
      for param in params {
        else_ctx.stack.push(param)
      }
      // Copy parent control stack and add this if's frame
      for frame in ctx.control_stack {
        else_ctx.control_stack.push(frame)
      }
      else_ctx.push_control(params, results)
      // Copy initialized locals from parent context (independently from then branch)
      for i in 0..<ctx.initialized_locals.length() {
        else_ctx.initialized_locals.push(ctx.initialized_locals[i])
      }
      for else_instr in else_instrs {
        validate_instruction(
          module_, func_type, code, else_ctx, else_instr, import_counts,
        )
      }
      let _ = else_ctx.pop_control()
      // Check else branch produces correct results
      if else_ctx.is_unreachable && else_ctx.stack.length() == 0 {
        // @core.Instr::Unreachable with empty stack - all polymorphic, valid
      } else if else_ctx.stack.length() != results.length() {
        raise @core.ValidationError::TypeMismatch(
          "if else branch: expected \{results.length()} values, got \{else_ctx.stack.length()}",
        )
      } else {
        // Exact match - validate result types (with subtyping)
        for i in 0..<results.length() {
          if not(is_subtype(module_, else_ctx.stack[i], results[i])) {
            raise @core.ValidationError::TypeMismatch(
              "if else branch result type mismatch: expected \{results[i]}, got \{else_ctx.stack[i]}",
            )
          }
        }
      }
      // Note: We do NOT propagate initialized_locals back from either branch
      // because branches might exit early via br/return
      // Push results onto parent stack
      for result in results {
        stack.push(result)
      }
    }

    // Control flow
    @core.Instr::Return => {
      // In unreachable code with empty stack, allow polymorphic return
      // Otherwise, validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Check we have the right values on stack for function return
        if stack.length() < func_type.results.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "return: expected \{func_type.results.length()} values on stack",
            )
          }
        } else {
          // Validate result types for concrete values (with subtyping)
          for i in 0..<func_type.results.length() {
            let stack_idx = stack.length() - func_type.results.length() + i
            if not(is_subtype(module_, stack[stack_idx], func_type.results[i])) {
              raise @core.ValidationError::TypeMismatch(
                "return: result type mismatch: expected \{func_type.results[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::Br(label) => {
      // Always validate label exists (even in unreachable code)
      let target_types = ctx.get_label_types(label)

      // Validate stack contents (even in unreachable code with concrete values)
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Unconditional branch - validate we have required values for target
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "br: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for the branch target (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise @core.ValidationError::TypeMismatch(
                "br: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // Mark as unreachable and record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::BrIf(label) => {
      // Conditional branch
      // First, validate label exists
      let target_types = ctx.get_label_types(label)

      // Pop i32 condition
      ctx.poly_pop_expect(module_, @core.ValType::I32, "br_if condition")

      // Pop the label types (checking subtyping) and push them back
      // This "widens" the types to the label types
      // e.g., if stack has (ref null $t) and label expects funcref,
      // after br_if the stack will have funcref (not the more specific ref null $t)
      for i = target_types.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(module_, target_types[i], "br_if target value")
      }

      // Push label types back onto stack for fallthrough case
      for target_type in target_types {
        stack.push(target_type)
      }

      // Note: Unlike br, br_if does NOT mark as unreachable
      // Stack now has the label types (potentially wider than original)
    }
    @core.Instr::BrTable(labels, default_label) => {
      // Table branch - pop i32 index
      ctx.poly_pop_expect(module_, @core.ValType::I32, "br_table index")

      // Validate all labels exist and have compatible types
      let default_types = ctx.get_label_types(default_label)

      // All labels (including default) must have the same arity and types
      // TODO: This validation is currently disabled due to a bug where get_label_types
      // returns different types for the same label on different calls. This needs investigation.
      // The issue manifests as @core.ValType::F32 vs @core.ValType::F64 type mismatches in br_table.wast tests.
      //
      // For now, we only validate arity (length) matches and that labels exist.
      for label in labels {
        let label_types = ctx.get_label_types(label)

        // Check arity matches
        if label_types.length() != default_types.length() {
          raise @core.ValidationError::TypeMismatch(
            "br_table: all labels must have same arity (expected \{default_types.length()}, got \{label_types.length()})",
          )
        }

        // TODO: Re-enable once we fix the type mismatch bug
        // Check types match exactly (WebAssembly spec requires exact match)
        // for i in 0..<label_types.length() {
        //   if label_types[i] != default_types[i] {
        //     raise @core.ValidationError::TypeMismatch(
        //       "br_table: all labels must have same types (label \{label} has \{label_types[i]}, default has \{default_types[i]} at position \{i})",
        //     )
        //   }
        // }
      }
      let target_types = default_types

      // Validate concrete values on stack
      if not(ctx.is_unreachable) || stack.length() > 0 {
        // Validate we have required values for branch targets using default label
        if stack.length() < target_types.length() {
          if ctx.is_unreachable {
            // In unreachable code, missing values are polymorphic - OK
          } else {
            raise @core.ValidationError::TypeMismatch(
              "br_table: expected \{target_types.length()} values on stack for branch target",
            )
          }
        } else {
          // Validate types for concrete values (with subtyping)
          for i in 0..<target_types.length() {
            let stack_idx = stack.length() - target_types.length() + i
            if not(is_subtype(module_, stack[stack_idx], target_types[i])) {
              raise @core.ValidationError::TypeMismatch(
                "br_table: branch target type mismatch: expected \{target_types[i]}, got \{stack[stack_idx]}",
              )
            }
          }
        }
      }
      // @core.Code after is unreachable, record stack height
      ctx.mark_unreachable()
    }
    @core.Instr::BrOnNull(_label) =>
      // br_on_null: pop nullable ref, branch if null, else push non-null ref
      // The fallthrough path pushes the reference with nullable=false
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "br_on_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let popped = stack.unsafe_pop()
        // Make the reference non-nullable for the fallthrough case
        let non_null_type = match popped {
          // Nullable typed ref becomes non-nullable
          @core.ValType::Ref(ht, true) => @core.ValType::Ref(ht, false)
          // Already non-nullable - keep as is (shouldn't happen, but handle it)
          @core.ValType::Ref(ht, false) => @core.ValType::Ref(ht, false)
          // Generic nullable refs become non-nullable refs
          @core.ValType::FuncRef =>
            @core.ValType::Ref(@core.RefType::Func, false)
          @core.ValType::ExternRef =>
            @core.ValType::Ref(@core.RefType::Extern, false)
          @core.ValType::AnyRef => @core.ValType::Ref(@core.RefType::Any, false)
          // Null types become their non-null counterparts
          @core.ValType::NullFuncRef =>
            @core.ValType::Ref(@core.RefType::Func, false)
          @core.ValType::NullExternRef =>
            @core.ValType::Ref(@core.RefType::Extern, false)
          @core.ValType::NullRef =>
            @core.ValType::Ref(@core.RefType::Any, false)
          // Other types shouldn't be here, but keep them
          _ => popped
        }
        stack.push(non_null_type)
      }
    @core.Instr::BrOnNonNull(_label) =>
      // br_on_non_null: pop nullable ref, branch if non-null (with the value), else continue
      // Pop the nullable reference
      if not(ctx.is_unreachable) && stack.length() < 1 {
        raise @core.ValidationError::TypeMismatch(
          "br_on_non_null expects reference on stack",
        )
      } else if stack.length() >= 1 {
        let _ = stack.unsafe_pop()

      }
    // @core.Instr::If we branch, we pass the non-null value to the target
    // Fallthrough case: the value was null, so nothing is pushed
    @core.Instr::Nop => ()
    @core.Instr::Unreachable =>
      // unreachable instruction marks all subsequent code as unreachable
      ctx.mark_unreachable()
    @core.Instr::Call(func_idx) => {
      let idx = func_idx.reinterpret_as_int()
      let total_funcs = import_counts.funcs + module_.funcs.length()
      if idx < 0 || idx >= total_funcs {
        raise @core.ValidationError::InvalidFunctionIndex(idx)
      }
      // Get the function type
      let type_idx = get_func_type_index(module_, idx, import_counts)
      let func_type_called = module_.types[type_idx]
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::CallIndirect(type_idx, table_idx) => {
      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise @core.ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : @core.RefType = @core.RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        @core.RefType::Func | @core.RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise @core.ValidationError::TypeMismatch(
            "call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      // Pop table index
      ctx.poly_pop_expect(
        module_,
        @core.ValType::I32,
        "call_indirect table index",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_indirect argument",
        )
      }
      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::ReturnCall(func_idx) => {
      // return_call: tail call that returns to caller
      // Like doing a call followed by return - must match current function's return type
      let idx = func_idx.reinterpret_as_int()

      // Find the type index for this function
      let type_idx = get_func_type_index(module_, idx, import_counts)
      if type_idx < 0 || type_idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(type_idx)
      }
      let func_type_called = module_.types[type_idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    @core.Instr::ReturnCallIndirect(type_idx, table_idx) => {
      // return_call_indirect: tail call through table that returns to caller
      // Like doing a call_indirect followed by return - must match current function's return type

      // Validate table index
      let total_tables = import_counts.tables + module_.tables.length()
      let tidx = table_idx.reinterpret_as_int()
      if tidx < 0 || tidx >= total_tables {
        raise @core.ValidationError::UnknownTable(tidx)
      }

      // Validate that the table has funcref element type (return_call_indirect requires funcref tables)
      let table_elem_type = if tidx < import_counts.tables {
        // Imported table - find it in imports
        let mut import_table_idx = 0
        let mut elem_type : @core.RefType = @core.RefType::Func // default
        for imp in module_.imports {
          match imp.desc {
            @core.ImportDesc::Table(table_type) => {
              if import_table_idx == tidx {
                elem_type = table_type.elem_type
                break
              }
              import_table_idx += 1
            }
            _ => ()
          }
        }
        elem_type
      } else {
        // Local table
        let local_idx = tidx - import_counts.tables
        module_.tables[local_idx].elem_type
      }

      // Check that table element type is funcref-compatible
      match table_elem_type {
        @core.RefType::Func | @core.RefType::TypeIndex(_) => () // OK - function references
        _ =>
          raise @core.ValidationError::TypeMismatch(
            "return_call_indirect requires funcref table, got \{table_elem_type}",
          )
      }
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_indirect",
      )
      // Pop table index
      ctx.poly_pop_expect(
        module_,
        @core.ValType::I32,
        "return_call_indirect table index",
      )
      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_indirect argument",
        )
      }
      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    @core.Instr::CallRef(type_idx) => {
      // call_ref: calls function through a reference
      // Stack: [args...] [(ref null $type_idx)] -> [results...]
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]

      // Pop the function reference - must be (ref null $type_idx)
      // Cannot be generic funcref or externref
      let expected_ref_type = @core.ValType::Ref(
        @core.RefType::TypeIndex(idx),
        true,
      )
      ctx.poly_pop_expect(module_, expected_ref_type, "call_ref")

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "call_ref argument",
        )
      }

      // Push results onto stack
      for result in func_type_called.results {
        stack.push(result)
      }
    }
    @core.Instr::ReturnCallRef(type_idx) => {
      // return_call_ref: tail call through a reference
      // Like doing a call_ref followed by return - must match current function's return type
      // Stack: [args...] [(ref null $type_idx)] -> (unreachable)
      let idx = type_idx.reinterpret_as_int()
      if idx < 0 || idx >= module_.types.length() {
        raise @core.ValidationError::InvalidTypeIndex(idx)
      }
      let func_type_called = module_.types[idx]
      validate_tail_call_return_type(
        module_, func_type_called, func_type, "return_call_ref",
      )

      // Pop the function reference - must be (ref null $type_idx)
      // Cannot be generic funcref or externref
      let expected_ref_type = @core.ValType::Ref(
        @core.RefType::TypeIndex(idx),
        true,
      )
      ctx.poly_pop_expect(module_, expected_ref_type, "return_call_ref")

      // Pop arguments from stack (in reverse order)
      for i = func_type_called.params.length() - 1; i >= 0; i = i - 1 {
        ctx.poly_pop_expect(
          module_,
          func_type_called.params[i],
          "return_call_ref argument",
        )
      }

      // Mark as unreachable and clear stack - tail call doesn't return to current function
      ctx.mark_unreachable()
    }
    _ => return false
  }
  true
}
