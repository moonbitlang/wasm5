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
