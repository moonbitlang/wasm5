///|
fn validate_instruction_variable(
  module_ : @core.Module,
  func_type : @core.FuncType,
  code : @core.Code,
  ctx : ValidationCtx,
  import_counts : ImportCounts,
  instr : @core.Instr,
) -> Bool raise @errors.ValidationError {
  let stack = ctx.stack
  match instr {
    // Local operations
    LocalGet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise @errors.ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      // Check initialization for non-defaultable types
      if not(local_type.is_defaultable()) &&
        ctx.initialized_locals.length() > local_idx &&
        not(ctx.initialized_locals[local_idx]) {
        raise @errors.ValidationError::UninitializedLocal(local_idx)
      }
      stack.push(local_type)
    }
    LocalSet(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise @errors.ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      ctx.poly_pop_expect(module_, local_type, "local.set")
      // Mark local as initialized
      while ctx.initialized_locals.length() <= local_idx {
        ctx.initialized_locals.push(true)
      }
      ctx.initialized_locals[local_idx] = true
    }
    LocalTee(idx) => {
      let local_idx = idx.reinterpret_as_int()
      let total_locals = func_type.params.length() + code.locals.length()
      if local_idx < 0 || local_idx >= total_locals {
        raise @errors.ValidationError::InvalidLocalIndex(local_idx)
      }
      let local_type = if local_idx < func_type.params.length() {
        func_type.params[local_idx]
      } else {
        code.locals[local_idx - func_type.params.length()]
      }
      // local.tee pops then pushes the value, so we need to validate and then push back
      ctx.poly_pop_expect(module_, local_type, "local.tee")
      stack.push(local_type)
      // Mark local as initialized
      while ctx.initialized_locals.length() <= local_idx {
        ctx.initialized_locals.push(true)
      }
      ctx.initialized_locals[local_idx] = true
    }

    // @core.Global operations
    // Note: @core.Global index space includes imported globals first, then local globals
    GlobalGet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise @errors.ValidationError::InvalidGlobalIndex(global_idx)
      }
      let global_type = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : @core.ValType = I32 // default
        for imp in module_.imports {
          match imp.desc {
            Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        found_type
      } else {
        // It's a local global
        let local_idx = global_idx - import_counts.globals
        module_.globals[local_idx].type_.val_type
      }
      stack.push(global_type)
    }
    GlobalSet(idx) => {
      let global_idx = idx.reinterpret_as_int()
      let total_globals = import_counts.globals + module_.globals.length()
      if global_idx < 0 || global_idx >= total_globals {
        raise @errors.ValidationError::InvalidGlobalIndex(global_idx)
      }
      let (global_type, is_mutable) = if global_idx < import_counts.globals {
        // It's an imported global - find it in imports
        let mut import_global_idx = 0
        let mut found_type : @core.ValType = I32 // default
        let mut found_mutable = false
        for imp in module_.imports {
          match imp.desc {
            Global(gt) => {
              if import_global_idx == global_idx {
                found_type = gt.val_type
                found_mutable = gt.mutable
                break
              }
              import_global_idx += 1
            }
            _ => ()
          }
        }
        (found_type, found_mutable)
      } else {
        // It's a local global
        let local_idx = global_idx - import_counts.globals
        (
          module_.globals[local_idx].type_.val_type,
          module_.globals[local_idx].type_.mutable,
        )
      }
      // Check if global is mutable
      if not(is_mutable) {
        raise @errors.ValidationError::ImmutableGlobal(global_idx)
      }
      ctx.poly_pop_expect(module_, global_type, "global.set")
    }
    _ => return false
  }
  true
}
