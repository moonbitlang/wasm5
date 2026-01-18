// Component Runtime Instantiation

///|
/// Instantiate the component (process all sections)
pub fn ComponentRuntime::instantiate(
  self : ComponentRuntime,
) -> Unit raise ComponentRuntimeError {
  for section in self.component.sections {
    self.process_section(section)
  }
}

///|
fn ComponentRuntime::process_section(
  self : ComponentRuntime,
  section : @core.ComponentSection,
) -> Unit raise ComponentRuntimeError {
  match section {
    @core.ComponentSection::CoreModule(module_) =>
      self.core_modules.push(module_)
    @core.ComponentSection::CoreInstance(instance) =>
      self.process_core_instance(instance)
    @core.ComponentSection::CoreType(core_type) =>
      self.core_types.push(core_type)
    @core.ComponentSection::Type(type_def) => self.types.push(type_def)
    @core.ComponentSection::Canon(canon) => self.process_canon(canon)
    @core.ComponentSection::Export(exp) => {
      let name = bytes_to_string(exp.name)
      self.exports[name] = exp.kind
    }
    @core.ComponentSection::Alias(alias_decl) => self.process_alias(alias_decl)
    @core.ComponentSection::Import(import_decl) =>
      self.process_import(import_decl)
    @core.ComponentSection::Instance(instance) =>
      self.process_component_instance(instance)
    @core.ComponentSection::Component(nested_component) =>
      // Add nested component to the component index space
      self.components.push(nested_component)
    @core.ComponentSection::Start(start) => self.process_start(start)
    @core.ComponentSection::Custom(_) =>
      // Skip custom sections
      ()
  }
}

///|
fn ComponentRuntime::process_core_instance(
  self : ComponentRuntime,
  instance : @core.CoreInstance,
) -> Unit raise ComponentRuntimeError {
  match instance {
    @core.CoreInstance::Instantiate(module_idx, args) => {
      guard module_idx.reinterpret_as_int() < self.core_modules.length() else {
        raise ComponentRuntimeError("invalid module index")
      }
      let module_ = self.core_modules[module_idx.reinterpret_as_int()]

      // Build import resolver from args
      let resolver = @runtime.ImportResolver::new()
      for arg in args {
        match arg {
          @core.CoreInstantiateArg::Instance(import_name, instance_idx) => {
            // Get exports from the referenced instance and add to resolver
            guard instance_idx.reinterpret_as_int() <
              self.core_instances.length() else {
              raise ComponentRuntimeError(
                "invalid instance index in instantiate arg",
              )
            }
            let source_instance = self.core_instances[instance_idx.reinterpret_as_int()]
            let import_name_str = bytes_to_string(import_name)
            // Add all exports from source instance as imports under import_name
            self.link_instance_exports(
              resolver, import_name_str, source_instance,
            )
          }
        }
      }

      // Instantiate the module
      let rt = @runtime.Runtime::load_with_resolver(module_, resolver) catch {
        e => raise ComponentRuntimeError("failed to instantiate module: \{e}")
      }
      self.core_instances.push(CoreInstanceEntry::Real(rt))
    }
    @core.CoreInstance::FromExports(core_exports) => {
      // Create a virtual instance from exports
      let export_map : Map[String, VirtualCoreExport] = {}
      for core_export in core_exports {
        let name = bytes_to_string(core_export.name)
        match core_export.kind {
          @core.CoreExportKind::Func(idx) =>
            export_map[name] = VirtualCoreExport::Func(idx)
          @core.CoreExportKind::Memory(idx) => {
            // Get memory from core_memories index space
            let mem_idx = idx.reinterpret_as_int()
            if mem_idx < self.core_memories.length() {
              let (data, max) = self.core_memories[mem_idx]
              export_map[name] = VirtualCoreExport::Memory(data, max)
            }
          }
          @core.CoreExportKind::Table(idx) => {
            // Get table from core_tables index space
            let table_idx = idx.reinterpret_as_int()
            if table_idx < self.core_tables.length() {
              export_map[name] = VirtualCoreExport::Table(
                self.core_tables[table_idx],
              )
            }
          }
          @core.CoreExportKind::Global(idx) => {
            // Get global from core_globals index space
            let global_idx = idx.reinterpret_as_int()
            if global_idx < self.core_globals.length() {
              export_map[name] = VirtualCoreExport::Global(
                self.core_globals[global_idx],
              )
            }
          }
          @core.CoreExportKind::Tag(idx) =>
            // Store tag index for exception handling
            export_map[name] = VirtualCoreExport::Tag(idx)
        }
      }
      self.core_instances.push(CoreInstanceEntry::Virtual(export_map))
    }
  }
}

///|
fn ComponentRuntime::process_component_instance(
  self : ComponentRuntime,
  instance : @core.ComponentInstance,
) -> Unit raise ComponentRuntimeError {
  match instance {
    @core.ComponentInstance::Instantiate(component_idx, args) => {
      // Instantiate a nested component
      guard component_idx.reinterpret_as_int() < self.components.length() else {
        raise ComponentRuntimeError("invalid component index: \{component_idx}")
      }
      let nested_component = self.components[component_idx.reinterpret_as_int()]

      // Create import resolver for the nested component from args
      let nested_resolver = ComponentImportResolver::new()
      for arg in args {
        match arg {
          @core.InstantiateArg::Instance(name, instance_idx) => {
            // Link instance exports to the nested component's imports
            let name_str = bytes_to_string(name)
            guard instance_idx.reinterpret_as_int() <
              self.component_instances.length() else {
              raise ComponentRuntimeError(
                "invalid instance index in instantiate arg: \{instance_idx}",
              )
            }
            let source_instance = self.component_instances[instance_idx.reinterpret_as_int()]
            // Copy exported functions to the nested resolver
            match source_instance {
              ComponentInstanceEntry::Instantiated(rt) =>
                // Copy all exports from the source runtime
                for export_name, kind in rt.exports {
                  match kind {
                    @core.ComponentExportKind::Func(func_idx) => {
                      // Create a wrapper function that calls the source runtime
                      let rt_ref = rt
                      let idx = func_idx
                      nested_resolver.add_func(name_str + ":" + export_name, ImportedComponentFunc::{
                        func: fn(call_args) {
                          rt_ref.call_func(idx, call_args) catch {
                            _ => []
                          }
                        },
                      })
                    }
                    _ => ()
                  }
                }
              ComponentInstanceEntry::VirtualComponent(export_map) =>
                // Virtual instance - copy the export map for the named import
                for export_name, kind in export_map {
                  match kind {
                    @core.ComponentExportKind::Func(func_idx) => {
                      // Look up the function in the parent's func space
                      let self_ref = self
                      let idx = func_idx
                      nested_resolver.add_func(name_str + ":" + export_name, ImportedComponentFunc::{
                        func: fn(call_args) {
                          self_ref.call_func(idx, call_args) catch {
                            _ => []
                          }
                        },
                      })
                    }
                    _ => ()
                  }
                }
            }
          }
          // Core sorts - used for core module linking
          @core.InstantiateArg::CoreFunc(_, _)
          | @core.InstantiateArg::CoreTable(_, _)
          | @core.InstantiateArg::CoreMemory(_, _)
          | @core.InstantiateArg::CoreGlobal(_, _)
          | @core.InstantiateArg::CoreType(_, _)
          | @core.InstantiateArg::CoreModule(_, _)
          | @core.InstantiateArg::CoreInstance(_, _) =>
            // Core args for component instantiation - typically used for core module linking
            ()
          // Component sorts (other than Instance which is handled above)
          @core.InstantiateArg::Func(_, _)
          | @core.InstantiateArg::Value(_, _)
          | @core.InstantiateArg::Type(_, _)
          | @core.InstantiateArg::Component(_, _) =>
            // Other component args - TODO: implement as needed
            ()
        }
      }

      // Create and instantiate the nested runtime (with parent reference for outer aliases)
      let nested_rt = ComponentRuntime::new_with_parent(
        nested_component, nested_resolver, self,
      )
      nested_rt.instantiate()
      self.component_instances.push(
        ComponentInstanceEntry::Instantiated(nested_rt),
      )
    }
    @core.ComponentInstance::FromExports(exports) => {
      // Create a virtual component instance from exports
      let export_map : Map[String, @core.ComponentExportKind] = {}
      for component_export in exports {
        let name = bytes_to_string(component_export.name)
        export_map[name] = component_export.kind
      }
      self.component_instances.push(
        ComponentInstanceEntry::VirtualComponent(export_map),
      )
    }
  }
}

///|
fn ComponentRuntime::link_instance_exports(
  self : ComponentRuntime,
  resolver : @runtime.ImportResolver,
  import_name : String,
  source : CoreInstanceEntry,
) -> Unit {
  match source {
    CoreInstanceEntry::Real(runtime) => {
      // Link exports from a real runtime instance
      let module_ = runtime.get_module()
      for exp in module_.exports {
        let export_name = bytes_to_string(exp.name)
        match exp.desc {
          @core.ExportDesc::Func(_) => {
            // Create wrapper that calls the source runtime
            let runtime_ref = runtime
            let func_name = exp.name
            let imported = @runtime.ImportedFunc::new(
              0U, // arity not used in current implementation
              fn(args) {
                runtime_ref.call_compiled(func_name, args) catch {
                  _ => []
                }
              },
            )
            resolver.add_func(
              string_to_bytes(import_name),
              string_to_bytes(export_name),
              imported,
            )
          }
          @core.ExportDesc::Mem(_) => {
            // Export memory from the runtime
            let imported_memory = @runtime.ImportedMemory::new(
              runtime.ctx.memory,
              runtime.ctx.memory_max,
            )
            resolver.add_memory(
              string_to_bytes(import_name),
              string_to_bytes(export_name),
              imported_memory,
            )
          }
          @core.ExportDesc::Table(idx) => {
            // Export table from the runtime
            let table_idx = idx.reinterpret_as_int()
            if table_idx < runtime.ctx.tables.length() {
              let table = runtime.ctx.tables[table_idx]
              resolver.add_table(
                string_to_bytes(import_name),
                string_to_bytes(export_name),
                table,
              )
            }
          }
          @core.ExportDesc::Global(idx) => {
            // Export global from the runtime
            let global_idx = idx.reinterpret_as_int()
            if global_idx < runtime.ctx.globals.length() {
              let global_value = runtime.ctx.globals[global_idx]
              resolver.add_global(
                string_to_bytes(import_name),
                string_to_bytes(export_name),
                global_value,
              )
            }
          }
          @core.ExportDesc::Tag(_) =>
            // Tags are for exception handling, not supported yet
            ()
        }
      }
    }
    CoreInstanceEntry::Virtual(export_map) =>
      // Link exports from a virtual instance
      for name, exp in export_map {
        match exp {
          VirtualCoreExport::Func(core_func_idx) => {
            // Get the core func
            let idx = core_func_idx.reinterpret_as_int()
            if idx < self.core_funcs.length() {
              match self.core_funcs[idx] {
                CoreFunc::Lowered(comp_func_idx, options) => {
                  // Create wrapper that calls the component function
                  let self_ref = self
                  let func_idx = comp_func_idx
                  let lower_options = options
                  let imported = @runtime.ImportedFunc::new(0U, fn(args) {
                    // Check if we have memory options for String/List support
                    let has_memory = lower_options
                      .iter()
                      .any(fn(opt) {
                        match opt {
                          @core.CanonOpt::Memory(_) => true
                          _ => false
                        }
                      })

                    // Convert core args to component values
                    let comp_args : Array[ComponentValue] = []
                    if has_memory && self_ref.core_memories.length() > 0 {
                      // With memory support, we can handle String/List (ptr, len pairs)
                      let mut i = 0
                      while i < args.length() {
                        match args[i] {
                          @runtime.Value::I32(n) => {
                            // Check if this might be a string (ptr, len pair)
                            if i + 1 < args.length() {
                              match args[i + 1] {
                                @runtime.Value::I32(len) => {
                                  // Could be a string - try to read from memory
                                  let ptr = n.reinterpret_as_int()
                                  let str_len = len.reinterpret_as_int()
                                  if ptr >= 0 && str_len >= 0 && str_len < 65536 {
                                    // Reasonable string length - try to lift as string
                                    let mem = self_ref.core_memories[0].0
                                    if ptr + str_len <= mem.length() {
                                      let bytes : Array[Byte] = []
                                      for j = 0; j < str_len; j = j + 1 {
                                        bytes.push(mem[ptr + j])
                                      }
                                      comp_args.push(
                                        ComponentValue::String(
                                          utf8_to_string(
                                            Bytes::from_array(bytes),
                                          ),
                                        ),
                                      )
                                      i = i + 2
                                      continue
                                    }
                                  }
                                }
                                _ => ()
                              }
                            }
                            // Not a string - treat as i32
                            comp_args.push(
                              ComponentValue::S32(n.reinterpret_as_int()),
                            )
                          }
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
                        i = i + 1
                      }
                    } else {
                      // Simple conversion without memory support
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
                    }
                    let comp_results = self_ref.call_func(func_idx, comp_args) catch {
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
                        ComponentValue::Bool(b) =>
                          core_results.push(
                            @runtime.Value::I32(if b { 1U } else { 0U }),
                          )
                        ComponentValue::String(s) =>
                          // For string results, we need to write to memory and return (ptr, len)
                          if has_memory && self_ref.core_memories.length() > 0 {
                            let bytes = string_to_utf8(s)
                            let len = bytes.length()
                            let mem = self_ref.core_memories[0].0
                            // Simple allocation: append to end of used memory
                            // TODO: Use realloc from options for proper allocation
                            let ptr = mem.length()
                            for b in bytes {
                              mem.push(b)
                            }
                            core_results.push(
                              @runtime.Value::I32(ptr.reinterpret_as_uint()),
                            )
                            core_results.push(
                              @runtime.Value::I32(len.reinterpret_as_uint()),
                            )
                          }
                        _ => ()
                      }
                    }
                    core_results
                  })
                  resolver.add_func(
                    string_to_bytes(import_name),
                    string_to_bytes(name),
                    imported,
                  )
                }
                CoreFunc::Aliased(_, _) =>
                  // TODO: Handle aliased functions in virtual instances
                  ()
                CoreFunc::ResourceNew(type_idx) => {
                  // resource.new: (rep: i32) -> handle: i32
                  let self_ref = self
                  let res_type = type_idx
                  let imported = @runtime.ImportedFunc::new(
                    1U, // one argument (rep)
                    fn(args) {
                      match args[0] {
                        @runtime.Value::I32(rep) => {
                          let handle = self_ref.resource_new(res_type, rep)
                          [@runtime.Value::I32(handle)]
                        }
                        _ => []
                      }
                    },
                  )
                  resolver.add_func(
                    string_to_bytes(import_name),
                    string_to_bytes(name),
                    imported,
                  )
                }
                CoreFunc::ResourceDrop(type_idx) => {
                  // resource.drop: (handle: i32) -> ()
                  let self_ref = self
                  let _ = type_idx
                  let imported = @runtime.ImportedFunc::new(
                    1U, // one argument (handle)
                    fn(args) {
                      match args[0] {
                        @runtime.Value::I32(handle) => {
                          let _ = self_ref.resource_drop(handle) catch {
                            _ => None
                          }
                          []
                        }
                        _ => []
                      }
                    },
                  )
                  resolver.add_func(
                    string_to_bytes(import_name),
                    string_to_bytes(name),
                    imported,
                  )
                }
                CoreFunc::ResourceRep(type_idx) => {
                  // resource.rep: (handle: i32) -> rep: i32
                  let self_ref = self
                  let _ = type_idx
                  let imported = @runtime.ImportedFunc::new(
                    1U, // one argument (handle)
                    fn(args) {
                      match args[0] {
                        @runtime.Value::I32(handle) => {
                          let rep = self_ref.resource_rep(handle) catch {
                            _ => 0U
                          }
                          [@runtime.Value::I32(rep)]
                        }
                        _ => []
                      }
                    },
                  )
                  resolver.add_func(
                    string_to_bytes(import_name),
                    string_to_bytes(name),
                    imported,
                  )
                }
              }
            }
          }
          VirtualCoreExport::Memory(data, max) => {
            // Export memory from virtual instance
            let imported_memory = @runtime.ImportedMemory::new(data, max)
            resolver.add_memory(
              string_to_bytes(import_name),
              string_to_bytes(name),
              imported_memory,
            )
          }
          VirtualCoreExport::Table(table) =>
            // Export table from virtual instance
            resolver.add_table(
              string_to_bytes(import_name),
              string_to_bytes(name),
              table,
            )
          VirtualCoreExport::Global(value) =>
            // Export global from virtual instance
            resolver.add_global(
              string_to_bytes(import_name),
              string_to_bytes(name),
              value,
            )
          VirtualCoreExport::Tag(_) =>
            // Tags are for exception handling, not fully supported yet
            ()
        }
      }
  }
}

///|
fn ComponentRuntime::process_canon(
  self : ComponentRuntime,
  canon : @core.Canon,
) -> Unit raise ComponentRuntimeError {
  match canon {
    @core.Canon::Lift(core_func_idx, options, func_type_idx) => {
      // Find which core instance and function name this refers to
      let core_func = self.resolve_core_func(core_func_idx)
      match core_func {
        CoreFunc::Aliased(instance_idx, func_name) =>
          self.funcs.push(
            ComponentFunc::Lifted(
              instance_idx, func_name, func_type_idx, options,
            ),
          )
        CoreFunc::Lowered(_, _) =>
          raise ComponentRuntimeError("cannot lift a lowered function")
        CoreFunc::ResourceNew(_)
        | CoreFunc::ResourceDrop(_)
        | CoreFunc::ResourceRep(_) =>
          raise ComponentRuntimeError("cannot lift a resource operation")
      }
    }
    @core.Canon::Lower(func_idx, options) =>
      // Add lowered function to core func index space
      self.core_funcs.push(CoreFunc::Lowered(func_idx, options))
    @core.Canon::ResourceNew(type_idx) =>
      // Add resource.new to core func index space
      self.core_funcs.push(CoreFunc::ResourceNew(type_idx))
    @core.Canon::ResourceDrop(type_idx) =>
      // Add resource.drop to core func index space
      self.core_funcs.push(CoreFunc::ResourceDrop(type_idx))
    @core.Canon::ResourceRep(type_idx) =>
      // Add resource.rep to core func index space
      self.core_funcs.push(CoreFunc::ResourceRep(type_idx))
  }
}

///|
fn ComponentRuntime::resolve_core_func(
  self : ComponentRuntime,
  core_func_idx : UInt,
) -> CoreFunc raise ComponentRuntimeError {
  // Core func index space is built from aliases and canon.lower
  let idx = core_func_idx.reinterpret_as_int()
  if idx < self.core_funcs.length() {
    return self.core_funcs[idx]
  }
  raise ComponentRuntimeError(
    "could not resolve core func index \{core_func_idx}",
  )
}

///|
fn ComponentRuntime::process_alias(
  self : ComponentRuntime,
  alias_def : @core.Alias,
) -> Unit raise ComponentRuntimeError {
  match alias_def.target {
    @core.AliasTarget::CoreExport(instance_idx, name) =>
      match alias_def.kind {
        @core.AliasKind::CoreFunc =>
          // Add to core func index space
          self.core_funcs.push(CoreFunc::Aliased(instance_idx, name))
        @core.AliasKind::CoreMemory => {
          // Add to core memory index space
          let inst_idx = instance_idx.reinterpret_as_int()
          guard inst_idx < self.core_instances.length() else {
            raise ComponentRuntimeError(
              "invalid core instance index for memory alias: \{instance_idx}",
            )
          }
          let name_str = bytes_to_string(name)
          match self.core_instances[inst_idx] {
            CoreInstanceEntry::Real(runtime) =>
              // Get memory from real runtime
              self.core_memories.push(
                (runtime.ctx.memory, runtime.ctx.memory_max),
              )
            CoreInstanceEntry::Virtual(export_map) =>
              // Get memory from virtual instance
              match export_map.get(name_str) {
                Some(VirtualCoreExport::Memory(data, max)) =>
                  self.core_memories.push((data, max))
                _ =>
                  raise ComponentRuntimeError(
                    "memory not found in virtual instance: \{name_str}",
                  )
              }
          }
        }
        @core.AliasKind::CoreTable => {
          // Add to core table index space
          let inst_idx = instance_idx.reinterpret_as_int()
          guard inst_idx < self.core_instances.length() else {
            raise ComponentRuntimeError(
              "invalid core instance index for table alias: \{instance_idx}",
            )
          }
          let name_str = bytes_to_string(name)
          match self.core_instances[inst_idx] {
            CoreInstanceEntry::Real(runtime) => {
              // Get table by looking up the export
              let module_ = runtime.get_module()
              for exp in module_.exports {
                if bytes_to_string(exp.name) == name_str {
                  match exp.desc {
                    @core.ExportDesc::Table(idx) => {
                      let table_idx = idx.reinterpret_as_int()
                      if table_idx < runtime.ctx.tables.length() {
                        self.core_tables.push(runtime.ctx.tables[table_idx])
                      }
                    }
                    _ => ()
                  }
                  break
                }
              }
            }
            CoreInstanceEntry::Virtual(export_map) =>
              match export_map.get(name_str) {
                Some(VirtualCoreExport::Table(table)) =>
                  self.core_tables.push(table)
                _ =>
                  raise ComponentRuntimeError(
                    "table not found in virtual instance: \{name_str}",
                  )
              }
          }
        }
        @core.AliasKind::CoreGlobal => {
          // Add to core global index space
          let inst_idx = instance_idx.reinterpret_as_int()
          guard inst_idx < self.core_instances.length() else {
            raise ComponentRuntimeError(
              "invalid core instance index for global alias: \{instance_idx}",
            )
          }
          let name_str = bytes_to_string(name)
          match self.core_instances[inst_idx] {
            CoreInstanceEntry::Real(runtime) => {
              // Get global by looking up the export
              let module_ = runtime.get_module()
              for exp in module_.exports {
                if bytes_to_string(exp.name) == name_str {
                  match exp.desc {
                    @core.ExportDesc::Global(idx) => {
                      let global_idx = idx.reinterpret_as_int()
                      if global_idx < runtime.ctx.globals.length() {
                        self.core_globals.push(runtime.ctx.globals[global_idx])
                      }
                    }
                    _ => ()
                  }
                  break
                }
              }
            }
            CoreInstanceEntry::Virtual(export_map) =>
              match export_map.get(name_str) {
                Some(VirtualCoreExport::Global(value)) =>
                  self.core_globals.push(value)
                _ =>
                  raise ComponentRuntimeError(
                    "global not found in virtual instance: \{name_str}",
                  )
              }
          }
        }
        _ =>
          // Other alias kinds
          ()
      }
    @core.AliasTarget::Export(instance_idx, name) => {
      // Component instance export alias
      let idx = instance_idx.reinterpret_as_int()
      guard idx < self.component_instances.length() else {
        raise ComponentRuntimeError(
          "invalid component instance index in alias: \{instance_idx}",
        )
      }
      let instance = self.component_instances[idx]
      let name_str = bytes_to_string(name)
      match alias_def.kind {
        @core.AliasKind::Func =>
          // Alias a function from a component instance
          match instance {
            ComponentInstanceEntry::Instantiated(rt) =>
              // Look up the export in the nested runtime
              match rt.exports.get(name_str) {
                Some(@core.ComponentExportKind::Func(func_idx)) => {
                  // Create a wrapper that calls the nested runtime's function
                  let rt_ref = rt
                  let idx = func_idx
                  self.funcs.push(
                    ComponentFunc::Imported(name, ImportedComponentFunc::{
                      func: fn(args) {
                        rt_ref.call_func(idx, args) catch {
                          _ => []
                        }
                      },
                    }),
                  )
                }
                _ =>
                  raise ComponentRuntimeError(
                    "function export not found in instance: \{name_str}",
                  )
              }
            ComponentInstanceEntry::VirtualComponent(export_map) =>
              match export_map.get(name_str) {
                Some(@core.ComponentExportKind::Func(func_idx)) => {
                  // Reference function from parent's func space
                  let self_ref = self
                  let idx = func_idx
                  self.funcs.push(
                    ComponentFunc::Imported(name, ImportedComponentFunc::{
                      func: fn(args) {
                        self_ref.call_func(idx, args) catch {
                          _ => []
                        }
                      },
                    }),
                  )
                }
                _ =>
                  raise ComponentRuntimeError(
                    "function export not found in virtual instance: \{name_str}",
                  )
              }
          }
        @core.AliasKind::Type =>
          // Alias a type from a component instance
          // Types are resolved at compile time, so we may not need runtime handling
          ()
        @core.AliasKind::Instance =>
          // Alias an instance from a component instance
          match instance {
            ComponentInstanceEntry::Instantiated(rt) =>
              match rt.exports.get(name_str) {
                Some(@core.ComponentExportKind::Instance(nested_idx)) =>
                  // Copy the nested instance to our instance space
                  if nested_idx.reinterpret_as_int() <
                    rt.component_instances.length() {
                    let nested_instance = rt.component_instances[nested_idx.reinterpret_as_int()]
                    self.component_instances.push(nested_instance)
                  }
                _ => ()
              }
            ComponentInstanceEntry::VirtualComponent(_) => ()
          }
        @core.AliasKind::Component =>
          // Alias a component from a component instance
          match instance {
            ComponentInstanceEntry::Instantiated(rt) =>
              match rt.exports.get(name_str) {
                Some(@core.ComponentExportKind::Component(comp_idx)) =>
                  if comp_idx.reinterpret_as_int() < rt.components.length() {
                    let nested_comp = rt.components[comp_idx.reinterpret_as_int()]
                    self.components.push(nested_comp)
                  }
                _ => ()
              }
            ComponentInstanceEntry::VirtualComponent(_) => ()
          }
        _ => ()
      }
    }
    @core.AliasTarget::Outer(count, idx) => {
      // Outer alias (to enclosing component)
      // Navigate up 'count' levels in the parent chain
      let mut ancestor : ComponentRuntime? = Some(self)
      for _ in 0..<count.reinterpret_as_int() {
        match ancestor {
          Some(rt) => ancestor = rt.parent
          None => break
        }
      }
      match ancestor {
        Some(parent_rt) => {
          let idx_int = idx.reinterpret_as_int()
          match alias_def.kind {
            @core.AliasKind::CoreModule =>
              // Copy a core module from parent
              if idx_int < parent_rt.core_modules.length() {
                self.core_modules.push(parent_rt.core_modules[idx_int])
              }
            @core.AliasKind::CoreType =>
              // Copy a core type from parent
              if idx_int < parent_rt.core_types.length() {
                self.core_types.push(parent_rt.core_types[idx_int])
              }
            @core.AliasKind::Type =>
              // Copy a component type from parent
              if idx_int < parent_rt.types.length() {
                self.types.push(parent_rt.types[idx_int])
              }
            @core.AliasKind::Func =>
              // Alias a function from parent
              if idx_int < parent_rt.funcs.length() {
                self.funcs.push(parent_rt.funcs[idx_int])
              }
            @core.AliasKind::Component =>
              // Copy a component from parent
              if idx_int < parent_rt.components.length() {
                self.components.push(parent_rt.components[idx_int])
              }
            _ =>
              // Other alias kinds are less common for outer aliases
              ()
          }
        }
        None =>
          // No parent at this level - ignore the alias
          // This can happen if the component wasn't instantiated as a nested component
          ()
      }
    }
  }
}

///|
/// Process component import
fn ComponentRuntime::process_import(
  self : ComponentRuntime,
  import_decl : @core.ComponentImport,
) -> Unit raise ComponentRuntimeError {
  let name = bytes_to_string(import_decl.name)
  match import_decl.desc {
    @core.ComponentExternDesc::Func(_) =>
      // Look up the imported function from the resolver
      // Use get_func which supports multiple functions with the same name
      match self.import_resolver.get_func(name) {
        Some(imported_func) =>
          self.funcs.push(
            ComponentFunc::Imported(import_decl.name, imported_func),
          )
        None =>
          raise ComponentRuntimeError("function import not found: \{name}")
      }
    @core.ComponentExternDesc::Value(_val_type) =>
      // Look up the imported value from the resolver
      match self.import_resolver.values.get(name) {
        Some(value) =>
          // Add to value index space
          self.values.push(value)
        None => raise ComponentRuntimeError("value import not found: \{name}")
      }
    @core.ComponentExternDesc::Instance(_type_idx) =>
      // Look up the imported instance from the resolver
      match self.import_resolver.instances.get(name) {
        Some(instance) =>
          // Add to component instance space
          self.component_instances.push(
            ComponentInstanceEntry::Instantiated(instance),
          )
        None =>
          raise ComponentRuntimeError("instance import not found: \{name}")
      }
    @core.ComponentExternDesc::Type(_bounds) =>
      // Type imports are typically resolved at compile time
      // We just add a placeholder type definition
      // This allows components with type imports to instantiate
      self.types.push(
        @core.ComponentTypeDef::Defined(
          @core.ComponentValType::Primitive(@core.PrimitiveType::U32),
        ),
      )
    @core.ComponentExternDesc::Module(_type_idx) =>
      // Module imports are rare at top-level
      // For now, raise an error as they require special handling
      raise ComponentRuntimeError(
        "module import not supported at top-level: \{name}",
      )
    @core.ComponentExternDesc::Component(_type_idx) =>
      // Component imports are rare at top-level
      // For now, raise an error as they require special handling
      raise ComponentRuntimeError(
        "component import not supported at top-level: \{name}",
      )
  }
}

///|
/// Process start section - call a function during instantiation
fn ComponentRuntime::process_start(
  self : ComponentRuntime,
  start : @core.ComponentStart,
) -> Unit raise ComponentRuntimeError {
  // Build argument list from value indices
  let args : Array[ComponentValue] = []
  for arg_idx in start.args {
    let idx = arg_idx.reinterpret_as_int()
    guard idx < self.values.length() else {
      raise ComponentRuntimeError(
        "invalid value index in start args: \{arg_idx}",
      )
    }
    args.push(self.values[idx])
  }

  // Call the start function with the collected arguments
  // The results are stored back in the value index space if results > 0
  let results = self.call_func(start.func_idx, args)

  // Store results back into value index space
  for result in results {
    self.values.push(result)
  }
}
