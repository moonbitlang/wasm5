///|
/// Count imported functions in the module
pub fn count_imported_funcs(module_ : Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Func(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Count imported globals in the module
pub fn count_imported_globals(module_ : Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Global(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Count imported tables in the module
pub fn count_imported_tables(module_ : Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Table(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Count imported memories in the module
pub fn count_imported_mems(module_ : Module) -> Int {
  let mut count = 0
  for imp in module_.imports {
    match imp.desc {
      Mem(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Get function type from type index.
/// Returns an empty function type if the type index doesn't refer to a function type.
pub fn get_func_type(module_ : Module, type_idx : Int) -> FuncType {
  if type_idx < 0 || type_idx >= module_.types.length() {
    return { params: [], results: [] }
  }
  match module_.types[type_idx] {
    Func(ft) => ft
    _ => { params: [], results: [] }
  }
}

///|
/// Cached counts of imported resources.
/// Computing all counts in a single pass is more efficient than counting each type separately.
pub struct ImportCounts {
  funcs : Int
  tables : Int
  mems : Int
  globals : Int
  tags : Int
}

///|
/// Compute import counts in a single pass through imports.
pub fn get_import_counts(module_ : Module) -> ImportCounts {
  let mut funcs = 0
  let mut tables = 0
  let mut mems = 0
  let mut globals = 0
  let mut tags = 0
  for imp in module_.imports {
    match imp.desc {
      Func(_) => funcs += 1
      Table(_) => tables += 1
      Mem(_) => mems += 1
      Global(_) => globals += 1
      Tag(_) => tags += 1
    }
  }
  { funcs, tables, mems, globals, tags }
}

///|
/// Get the type index for a function (imported or local).
/// Returns -1 if the function index is invalid.
pub fn get_func_type_idx(
  module_ : Module,
  func_idx : Int,
  num_imported : Int,
) -> Int {
  if func_idx < num_imported {
    // Imported function - find type index from imports
    let mut import_idx = 0
    let mut type_idx = -1
    for imp in module_.imports {
      match imp.desc {
        Func(tidx) => {
          if import_idx == func_idx {
            type_idx = tidx.reinterpret_as_int()
            break
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    type_idx
  } else {
    // Local function - look up in module funcs
    let local_idx = func_idx - num_imported
    if local_idx >= 0 && local_idx < module_.funcs.length() {
      module_.funcs[local_idx].reinterpret_as_int()
    } else {
      -1
    }
  }
}

///|
/// Check if a type index refers to a function type in the module
pub fn is_func_type_index(module_ : Module, type_idx : Int) -> Bool {
  if type_idx < 0 || type_idx >= module_.types.length() {
    return false
  }
  match module_.types[type_idx] {
    Func(_) => true
    _ => false
  }
}

///|
/// Check if a type index refers to a struct type in the module
pub fn is_struct_type_index(module_ : Module, type_idx : Int) -> Bool {
  if type_idx < 0 || type_idx >= module_.types.length() {
    return false
  }
  match module_.types[type_idx] {
    Struct(_) => true
    _ => false
  }
}

///|
/// Check if a type index refers to an array type in the module
pub fn is_array_type_index(module_ : Module, type_idx : Int) -> Bool {
  if type_idx < 0 || type_idx >= module_.types.length() {
    return false
  }
  match module_.types[type_idx] {
    Array(_) => true
    _ => false
  }
}

///|
/// Get the table type for a table index (imported or local).
/// Returns None if the table index is invalid.
pub fn get_table_type(
  module_ : Module,
  table_idx : Int,
  num_imported_tables : Int,
) -> TableType? {
  if table_idx < num_imported_tables {
    // Imported table - find type from imports
    let mut import_idx = 0
    for imp in module_.imports {
      match imp.desc {
        Table(table_type) => {
          if import_idx == table_idx {
            return Some(table_type)
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    None
  } else {
    // Local table - look up in module tables
    let local_idx = table_idx - num_imported_tables
    if local_idx >= 0 && local_idx < module_.tables.length() {
      Some(module_.tables[local_idx])
    } else {
      None
    }
  }
}

///|
/// Get the global type for a global index (imported or local).
/// Returns None if the global index is invalid.
pub fn get_global_type(
  module_ : Module,
  global_idx : Int,
  num_imported_globals : Int,
) -> GlobalType? {
  if global_idx < num_imported_globals {
    // Imported global - find type from imports
    let mut import_idx = 0
    for imp in module_.imports {
      match imp.desc {
        Global(global_type) => {
          if import_idx == global_idx {
            return Some(global_type)
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    None
  } else {
    // Local global - look up in module globals
    let local_idx = global_idx - num_imported_globals
    if local_idx >= 0 && local_idx < module_.globals.length() {
      Some(module_.globals[local_idx].type_)
    } else {
      None
    }
  }
}

///|
/// Get the memory type for a memory index (imported or local).
/// Returns None if the memory index is invalid.
pub fn get_mem_type(
  module_ : Module,
  mem_idx : Int,
  num_imported_mems : Int,
) -> MemType? {
  if mem_idx < num_imported_mems {
    // Imported memory - find type from imports
    let mut import_idx = 0
    for imp in module_.imports {
      match imp.desc {
        Mem(mem_type) => {
          if import_idx == mem_idx {
            return Some(mem_type)
          }
          import_idx += 1
        }
        _ => ()
      }
    }
    None
  } else {
    // Local memory - look up in module mems
    let local_idx = mem_idx - num_imported_mems
    if local_idx >= 0 && local_idx < module_.mems.length() {
      Some(module_.mems[local_idx])
    } else {
      None
    }
  }
}
