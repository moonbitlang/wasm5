// Component Runtime Resource Management

///|
/// Create a new resource handle (resource.new)
/// Takes a representation value (i32) and returns a handle
pub fn ComponentRuntime::resource_new(
  self : ComponentRuntime,
  type_idx : UInt,
  rep : UInt,
) -> UInt {
  // Look up destructor from type definition
  let dtor : UInt? = {
    let idx = type_idx.reinterpret_as_int()
    if idx < self.types.length() {
      match self.types[idx] {
        @core.ComponentTypeDef::Resource(res_type) => res_type.dtor
        _ => None
      }
    } else {
      None
    }
  }
  let handle = self.next_resource_handle
  self.next_resource_handle = self.next_resource_handle + 1U
  let entry = ResourceEntry::{ type_idx, rep, owned: true, dtor }
  // Extend array if needed
  while self.resources.length() <= handle.reinterpret_as_int() {
    self.resources.push(None)
  }
  self.resources[handle.reinterpret_as_int()] = Some(entry)
  handle
}

///|
/// Drop a resource handle (resource.drop)
/// Returns the representation value if it was owned, or None if already dropped
pub fn ComponentRuntime::resource_drop(
  self : ComponentRuntime,
  handle : UInt,
) -> UInt? raise ComponentRuntimeError {
  let idx = handle.reinterpret_as_int()
  if idx >= self.resources.length() {
    raise ComponentRuntimeError("invalid resource handle: \{handle}")
  }
  match self.resources[idx] {
    None => raise ComponentRuntimeError("resource already dropped: \{handle}")
    Some(entry) =>
      if entry.owned {
        // Call destructor if present
        match entry.dtor {
          Some(dtor_idx) =>
            // Call the destructor with the representation value
            self.call_destructor(dtor_idx, entry.rep)
          None => ()
        }
        self.resources[idx] = None
        Some(entry.rep)
      } else {
        // Borrowed handle - just clear it, don't return rep
        self.resources[idx] = None
        None
      }
  }
}

///|
/// Call a destructor function with the representation value
fn ComponentRuntime::call_destructor(
  self : ComponentRuntime,
  dtor_idx : UInt,
  rep : UInt,
) -> Unit {
  // The destructor is a core function that takes rep as an i32 argument
  let core_func_idx = dtor_idx.reinterpret_as_int()
  if core_func_idx < self.core_funcs.length() {
    match self.core_funcs[core_func_idx] {
      CoreFunc::Aliased(instance_idx, func_name) => {
        let inst_idx = instance_idx.reinterpret_as_int()
        if inst_idx < self.core_instances.length() {
          match self.core_instances[inst_idx] {
            CoreInstanceEntry::Real(runtime) => {
              // Call the destructor function
              let _ = try {
                let _ = runtime.compile()
                let _ = runtime.call_compiled(func_name, [
                  @runtime.Value::I32(rep),
                ])

              } catch {
                _ => ()
              }

            }
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// Get the representation of a resource (resource.rep)
pub fn ComponentRuntime::resource_rep(
  self : ComponentRuntime,
  handle : UInt,
) -> UInt raise ComponentRuntimeError {
  let idx = handle.reinterpret_as_int()
  if idx >= self.resources.length() {
    raise ComponentRuntimeError("invalid resource handle: \{handle}")
  }
  match self.resources[idx] {
    None => raise ComponentRuntimeError("resource already dropped: \{handle}")
    Some(entry) => entry.rep
  }
}

///|
/// Create a borrowed handle from an owned handle
pub fn ComponentRuntime::resource_borrow(
  self : ComponentRuntime,
  owned_handle : UInt,
) -> UInt raise ComponentRuntimeError {
  let idx = owned_handle.reinterpret_as_int()
  if idx >= self.resources.length() {
    raise ComponentRuntimeError("invalid resource handle: \{owned_handle}")
  }
  match self.resources[idx] {
    None =>
      raise ComponentRuntimeError("resource already dropped: \{owned_handle}")
    Some(entry) => {
      // Create a new borrowed handle pointing to the same rep
      let borrow_handle = self.next_resource_handle
      self.next_resource_handle = self.next_resource_handle + 1U
      let borrow_entry = ResourceEntry::{
        type_idx: entry.type_idx,
        rep: entry.rep,
        owned: false,
        dtor: None,
      }
      while self.resources.length() <= borrow_handle.reinterpret_as_int() {
        self.resources.push(None)
      }
      self.resources[borrow_handle.reinterpret_as_int()] = Some(borrow_entry)
      borrow_handle
    }
  }
}
