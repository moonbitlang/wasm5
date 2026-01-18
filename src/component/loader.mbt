// Unified WASM Runtime
// Auto-detects Module vs Component and provides unified execution interface

///|
pub suberror WasmError {
  ParseError(String)
  RuntimeError(String)
} derive(Show)

///|
/// Unified executable - either a core Module or a Component
pub(all) enum WasmExecutable {
  Module(@runtime.Runtime)
  Component(ComponentRuntime)
}

///|
/// Load a WASM binary (auto-detects Module vs Component)
pub fn load(bytes : Bytes) -> WasmExecutable raise WasmError {
  // Check magic bytes: \0asm
  guard bytes.length() >= 8 else {
    raise WasmError::ParseError("binary too short")
  }
  guard bytes[0] == b'\x00' &&
    bytes[1] == b'\x61' &&
    bytes[2] == b'\x73' &&
    bytes[3] == b'\x6D' else {
    raise WasmError::ParseError("invalid magic bytes")
  }

  // Check version and layer
  // Core module: version 1 (0x01 0x00 0x00 0x00)
  // Component: version 13 (0x0d 0x00) + layer 1 (0x01 0x00)
  let is_component = bytes[4] == b'\x0d' &&
    bytes[5] == b'\x00' &&
    bytes[6] == b'\x01' &&
    bytes[7] == b'\x00'
  if is_component {
    let component = @parse.parse_component(bytes) catch {
      e => raise WasmError::ParseError("component parse error: \{e}")
    }
    let rt = ComponentRuntime::new(component)
    rt.instantiate() catch {
      e => raise WasmError::RuntimeError("component instantiate error: \{e}")
    }
    WasmExecutable::Component(rt)
  } else {
    let module_ = @parse.parse(bytes) catch {
      e => raise WasmError::ParseError("module parse error: \{e}")
    }
    let rt = @runtime.Runtime::load(module_) catch {
      e => raise WasmError::RuntimeError("module load error: \{e}")
    }
    WasmExecutable::Module(rt)
  }
}

///|
/// Load a WASM binary with component import resolver
pub fn load_with_imports(
  bytes : Bytes,
  resolver : ComponentImportResolver,
) -> WasmExecutable raise WasmError {
  guard bytes.length() >= 8 else {
    raise WasmError::ParseError("binary too short")
  }
  guard bytes[0] == b'\x00' &&
    bytes[1] == b'\x61' &&
    bytes[2] == b'\x73' &&
    bytes[3] == b'\x6D' else {
    raise WasmError::ParseError("invalid magic bytes")
  }
  let is_component = bytes[4] == b'\x0d' &&
    bytes[5] == b'\x00' &&
    bytes[6] == b'\x01' &&
    bytes[7] == b'\x00'
  if is_component {
    let component = @parse.parse_component(bytes) catch {
      e => raise WasmError::ParseError("component parse error: \{e}")
    }
    let rt = ComponentRuntime::new_with_imports(component, resolver)
    rt.instantiate() catch {
      e => raise WasmError::RuntimeError("component instantiate error: \{e}")
    }
    WasmExecutable::Component(rt)
  } else {
    // For core modules, ignore component resolver
    let module_ = @parse.parse(bytes) catch {
      e => raise WasmError::ParseError("module parse error: \{e}")
    }
    let rt = @runtime.Runtime::load(module_) catch {
      e => raise WasmError::RuntimeError("module load error: \{e}")
    }
    WasmExecutable::Module(rt)
  }
}

///|
/// Call a function on the executable
pub fn WasmExecutable::call(
  self : WasmExecutable,
  name : String,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise WasmError {
  match self {
    WasmExecutable::Module(rt) => {
      // Convert ComponentValue to core Value
      let core_args : Array[@runtime.Value] = []
      for arg in args {
        match arg {
          ComponentValue::S32(n) =>
            core_args.push(@runtime.Value::I32(n.reinterpret_as_uint()))
          ComponentValue::U32(n) => core_args.push(@runtime.Value::I32(n))
          ComponentValue::S64(n) =>
            core_args.push(@runtime.Value::I64(n.reinterpret_as_uint64()))
          ComponentValue::U64(n) => core_args.push(@runtime.Value::I64(n))
          ComponentValue::F32(n) => core_args.push(@runtime.Value::F32(n))
          ComponentValue::F64(n) => core_args.push(@runtime.Value::F64(n))
          _ =>
            raise WasmError::RuntimeError(
              "unsupported argument type for core module",
            )
        }
      }

      // Call
      let name_bytes = string_to_bytes(name)
      let results = rt.call_compiled(name_bytes, core_args) catch {
        e => raise WasmError::RuntimeError("call error: \{e}")
      }

      // Convert back to ComponentValue
      let comp_results : Array[ComponentValue] = []
      for result in results {
        match result {
          @runtime.Value::I32(n) =>
            comp_results.push(ComponentValue::S32(n.reinterpret_as_int()))
          @runtime.Value::I64(n) =>
            comp_results.push(ComponentValue::S64(n.reinterpret_as_int64()))
          @runtime.Value::F32(n) => comp_results.push(ComponentValue::F32(n))
          @runtime.Value::F64(n) => comp_results.push(ComponentValue::F64(n))
          _ =>
            raise WasmError::RuntimeError(
              "unsupported result type from core module",
            )
        }
      }
      comp_results
    }
    WasmExecutable::Component(rt) =>
      rt.call(name, args) catch {
        e => raise WasmError::RuntimeError("component call error: \{e}")
      }
  }
}

///|
/// Check if this is a component
pub fn WasmExecutable::is_component(self : WasmExecutable) -> Bool {
  match self {
    WasmExecutable::Component(_) => true
    WasmExecutable::Module(_) => false
  }
}

///|
/// Check if bytes represent a component (without full parsing)
pub fn is_component_binary(bytes : Bytes) -> Bool {
  bytes.length() >= 8 &&
  bytes[0] == b'\x00' &&
  bytes[1] == b'\x61' &&
  bytes[2] == b'\x73' &&
  bytes[3] == b'\x6D' &&
  bytes[4] == b'\x0d' &&
  bytes[5] == b'\x00' &&
  bytes[6] == b'\x01' &&
  bytes[7] == b'\x00'
}

// ============================================================================
// Unified Import Resolver - Links Modules and Components together
// ============================================================================

///|
/// A registered executable with its exports accessible for linking
pub struct LinkedExecutable {
  executable : WasmExecutable
  // Cached export info for quick lookup
  exports : Map[String, ExportInfo]
}

///|
/// Info about an exported item
pub enum ExportInfo {
  Func(Int) // function index (for calling)
}

///|
/// Unified import resolver that can link Modules and Components together
pub struct UnifiedImportResolver {
  // Named executables available for import
  executables : Map[String, LinkedExecutable]
  // Host functions (for both Module and Component)
  host_funcs : Map[String, Map[String, ImportedComponentFunc]]
}

///|
pub fn UnifiedImportResolver::new() -> UnifiedImportResolver {
  UnifiedImportResolver::{ executables: {}, host_funcs: {} }
}

///|
/// Register a host function
pub fn UnifiedImportResolver::add_host_func(
  self : UnifiedImportResolver,
  module_name : String,
  func_name : String,
  func : ImportedComponentFunc,
) -> Unit {
  match self.host_funcs.get(module_name) {
    Some(funcs) => funcs[func_name] = func
    None => {
      let funcs : Map[String, ImportedComponentFunc] = {}
      funcs[func_name] = func
      self.host_funcs[module_name] = funcs
    }
  }
}

///|
/// Register an already-loaded executable for linking
pub fn UnifiedImportResolver::register(
  self : UnifiedImportResolver,
  name : String,
  executable : WasmExecutable,
) -> Unit {
  let exports : Map[String, ExportInfo] = {}

  // Extract export info based on type
  match executable {
    WasmExecutable::Module(rt) => {
      let module_ = rt.get_module()
      for i, exp in module_.exports {
        let exp_name = bytes_to_string(exp.name)
        match exp.desc {
          @core.ExportDesc::Func(_) => exports[exp_name] = ExportInfo::Func(i)
          _ => () // TODO: memory, table, global
        }
      }
    }
    WasmExecutable::Component(rt) =>
      for name, kind in rt.exports {
        match kind {
          @core.ComponentExportKind::Func(idx) =>
            exports[name] = ExportInfo::Func(idx.reinterpret_as_int())
          _ => () // TODO: other export kinds
        }
      }
  }
  self.executables[name] = LinkedExecutable::{ executable, exports }
}

///|
/// Convert to a core Module ImportResolver
/// This allows a Module to import from registered Components/Modules
pub fn UnifiedImportResolver::to_module_resolver(
  self : UnifiedImportResolver,
) -> @runtime.ImportResolver {
  let resolver = @runtime.default_import_resolver()

  // Add host functions
  for module_name, funcs in self.host_funcs {
    for func_name, comp_func in funcs {
      let imported = @runtime.ImportedFunc::new(0U, fn(args) {
        // Convert core args to component values
        let comp_args : Array[ComponentValue] = []
        for arg in args {
          match arg {
            @runtime.Value::I32(n) =>
              comp_args.push(ComponentValue::S32(n.reinterpret_as_int()))
            @runtime.Value::I64(n) =>
              comp_args.push(ComponentValue::S64(n.reinterpret_as_int64()))
            @runtime.Value::F32(n) => comp_args.push(ComponentValue::F32(n))
            @runtime.Value::F64(n) => comp_args.push(ComponentValue::F64(n))
            _ => ()
          }
        }
        let comp_results = (comp_func.func)(comp_args)
        // Convert back to core values
        let core_results : Array[@runtime.Value] = []
        for result in comp_results {
          match result {
            ComponentValue::S32(n) =>
              core_results.push(@runtime.Value::I32(n.reinterpret_as_uint()))
            ComponentValue::U32(n) => core_results.push(@runtime.Value::I32(n))
            ComponentValue::S64(n) =>
              core_results.push(@runtime.Value::I64(n.reinterpret_as_uint64()))
            ComponentValue::U64(n) => core_results.push(@runtime.Value::I64(n))
            ComponentValue::F32(n) => core_results.push(@runtime.Value::F32(n))
            ComponentValue::F64(n) => core_results.push(@runtime.Value::F64(n))
            _ => ()
          }
        }
        core_results
      })
      resolver.add_func(
        string_to_bytes(module_name),
        string_to_bytes(func_name),
        imported,
      )
    }
  }

  // Add exports from registered executables
  for exec_name, linked in self.executables {
    match linked.executable {
      WasmExecutable::Module(source_rt) => {
        // Module -> Module: wrap exports as imported functions
        let module_ = source_rt.get_module()
        for exp in module_.exports {
          let exp_name = bytes_to_string(exp.name)
          match exp.desc {
            @core.ExportDesc::Func(_) => {
              let rt_ref = source_rt
              let func_name_bytes = exp.name
              let imported = @runtime.ImportedFunc::new(0U, fn(args) {
                rt_ref.call_compiled(func_name_bytes, args) catch {
                  _ => []
                }
              })
              resolver.add_func(
                string_to_bytes(exec_name),
                string_to_bytes(exp_name),
                imported,
              )
            }
            _ => ()
          }
        }
      }
      WasmExecutable::Component(comp_rt) =>
        // Component -> Module: wrap component exports as imported functions
        for exp_name, kind in comp_rt.exports {
          match kind {
            @core.ComponentExportKind::Func(_) => {
              let comp_rt_ref = comp_rt
              let name_ref = exp_name
              let imported = @runtime.ImportedFunc::new(0U, fn(args) {
                // Convert core args to component values
                let comp_args : Array[ComponentValue] = []
                for arg in args {
                  match arg {
                    @runtime.Value::I32(n) =>
                      comp_args.push(
                        ComponentValue::S32(n.reinterpret_as_int()),
                      )
                    @runtime.Value::I64(n) =>
                      comp_args.push(
                        ComponentValue::S64(n.reinterpret_as_int64()),
                      )
                    @runtime.Value::F32(n) =>
                      comp_args.push(ComponentValue::F32(n))
                    @runtime.Value::F64(n) =>
                      comp_args.push(ComponentValue::F64(n))
                    _ => ()
                  }
                }
                let comp_results = comp_rt_ref.call(name_ref, comp_args) catch {
                  _ => []
                }
                // Convert back to core values
                let core_results : Array[@runtime.Value] = []
                for result in comp_results {
                  match result {
                    ComponentValue::S32(n) =>
                      core_results.push(
                        @runtime.Value::I32(n.reinterpret_as_uint()),
                      )
                    ComponentValue::U32(n) =>
                      core_results.push(@runtime.Value::I32(n))
                    ComponentValue::S64(n) =>
                      core_results.push(
                        @runtime.Value::I64(n.reinterpret_as_uint64()),
                      )
                    ComponentValue::U64(n) =>
                      core_results.push(@runtime.Value::I64(n))
                    ComponentValue::F32(n) =>
                      core_results.push(@runtime.Value::F32(n))
                    ComponentValue::F64(n) =>
                      core_results.push(@runtime.Value::F64(n))
                    _ => ()
                  }
                }
                core_results
              })
              resolver.add_func(
                string_to_bytes(exec_name),
                string_to_bytes(exp_name),
                imported,
              )
            }
            _ => ()
          }
        }
    }
  }
  resolver
}

///|
/// Convert to a ComponentImportResolver
/// This allows a Component to import from registered Components/Modules
pub fn UnifiedImportResolver::to_component_resolver(
  self : UnifiedImportResolver,
) -> ComponentImportResolver {
  let resolver = ComponentImportResolver::new()

  // Add host functions (flattened name: "module:func" or just "func")
  for module_name, funcs in self.host_funcs {
    for func_name, comp_func in funcs {
      // Component imports use kebab-case names, often like "module:func"
      let full_name = if module_name.length() > 0 {
        "\{module_name}:\{func_name}"
      } else {
        func_name
      }
      resolver.add_func(full_name, comp_func)
    }
  }

  // Add exports from registered executables
  for exec_name, linked in self.executables {
    match linked.executable {
      WasmExecutable::Module(source_rt) => {
        // Module -> Component: wrap module exports as component functions
        let module_ = source_rt.get_module()
        for exp in module_.exports {
          let exp_name = bytes_to_string(exp.name)
          match exp.desc {
            @core.ExportDesc::Func(_) => {
              let rt_ref = source_rt
              let func_name_bytes = exp.name
              let full_name = "\{exec_name}:\{exp_name}"
              let comp_func = ImportedComponentFunc::{
                func: fn(args) {
                  // Convert component args to core values
                  let core_args : Array[@runtime.Value] = []
                  for arg in args {
                    match arg {
                      ComponentValue::S32(n) =>
                        core_args.push(
                          @runtime.Value::I32(n.reinterpret_as_uint()),
                        )
                      ComponentValue::U32(n) =>
                        core_args.push(@runtime.Value::I32(n))
                      ComponentValue::S64(n) =>
                        core_args.push(
                          @runtime.Value::I64(n.reinterpret_as_uint64()),
                        )
                      ComponentValue::U64(n) =>
                        core_args.push(@runtime.Value::I64(n))
                      ComponentValue::F32(n) =>
                        core_args.push(@runtime.Value::F32(n))
                      ComponentValue::F64(n) =>
                        core_args.push(@runtime.Value::F64(n))
                      _ => ()
                    }
                  }
                  let core_results = rt_ref.call_compiled(
                    func_name_bytes, core_args,
                  ) catch {
                    _ => []
                  }
                  // Convert back to component values
                  let comp_results : Array[ComponentValue] = []
                  for result in core_results {
                    match result {
                      @runtime.Value::I32(n) =>
                        comp_results.push(
                          ComponentValue::S32(n.reinterpret_as_int()),
                        )
                      @runtime.Value::I64(n) =>
                        comp_results.push(
                          ComponentValue::S64(n.reinterpret_as_int64()),
                        )
                      @runtime.Value::F32(n) =>
                        comp_results.push(ComponentValue::F32(n))
                      @runtime.Value::F64(n) =>
                        comp_results.push(ComponentValue::F64(n))
                      _ => ()
                    }
                  }
                  comp_results
                },
              }
              resolver.add_func(full_name, comp_func)
            }
            _ => ()
          }
        }
      }
      WasmExecutable::Component(comp_rt) =>
        // Component -> Component: wrap component exports
        for exp_name, kind in comp_rt.exports {
          match kind {
            @core.ComponentExportKind::Func(_) => {
              let comp_rt_ref = comp_rt
              let name_ref = exp_name
              let full_name = "\{exec_name}:\{exp_name}"
              let comp_func = ImportedComponentFunc::{
                func: fn(args) {
                  comp_rt_ref.call(name_ref, args) catch {
                    _ => []
                  }
                },
              }
              resolver.add_func(full_name, comp_func)
            }
            _ => ()
          }
        }
    }
  }
  resolver
}

///|
/// Load with unified import resolver (auto-detects Module vs Component)
pub fn load_with_unified_resolver(
  bytes : Bytes,
  resolver : UnifiedImportResolver,
) -> WasmExecutable raise WasmError {
  guard bytes.length() >= 8 else {
    raise WasmError::ParseError("binary too short")
  }
  guard bytes[0] == b'\x00' &&
    bytes[1] == b'\x61' &&
    bytes[2] == b'\x73' &&
    bytes[3] == b'\x6D' else {
    raise WasmError::ParseError("invalid magic bytes")
  }
  let is_component = bytes[4] == b'\x0d' &&
    bytes[5] == b'\x00' &&
    bytes[6] == b'\x01' &&
    bytes[7] == b'\x00'
  if is_component {
    let component = @parse.parse_component(bytes) catch {
      e => raise WasmError::ParseError("component parse error: \{e}")
    }
    let comp_resolver = resolver.to_component_resolver()
    let rt = ComponentRuntime::new_with_imports(component, comp_resolver)
    rt.instantiate() catch {
      e => raise WasmError::RuntimeError("component instantiate error: \{e}")
    }
    WasmExecutable::Component(rt)
  } else {
    let module_ = @parse.parse(bytes) catch {
      e => raise WasmError::ParseError("module parse error: \{e}")
    }
    let mod_resolver = resolver.to_module_resolver()
    let rt = @runtime.Runtime::load_with_resolver(module_, mod_resolver) catch {
      e => raise WasmError::RuntimeError("module load error: \{e}")
    }
    WasmExecutable::Module(rt)
  }
}
