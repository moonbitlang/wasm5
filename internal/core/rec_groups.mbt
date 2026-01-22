///|
/// Get rec group info for a type index: returns (group_index, position_in_group)
/// Returns (-1, -1) if type not found in any group
pub fn get_rec_group_info(module_ : Module, type_idx : Int) -> (Int, Int) {
  for i, group in module_.type_groups {
    for j, subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        return (i, j)
      }
    }
  }
  (-1, -1)
}

///|
/// Get all type indices in a rec group
pub fn get_rec_group_types(module_ : Module, group_idx : Int) -> Array[Int] {
  let result : Array[Int] = []
  if group_idx >= 0 && group_idx < module_.type_groups.length() {
    let group = module_.type_groups[group_idx]
    for subtype_def in group.subtypes {
      result.push(subtype_def.type_idx.reinterpret_as_int())
    }
  }
  result
}

///|
/// Check if a type index is within a given rec group
pub fn is_in_rec_group(types : Array[Int], type_idx : Int) -> Bool {
  for t in types {
    if t == type_idx {
      return true
    }
  }
  false
}

///|
/// Get the position of a type within its rec group
pub fn get_position_in_group(types : Array[Int], type_idx : Int) -> Int {
  for i, t in types {
    if t == type_idx {
      return i
    }
  }
  -1
}

///|
/// Check if a type index is final (cannot be extended)
pub fn is_type_final(module_ : Module, type_idx : Int) -> Bool {
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        return subtype_def.is_final
      }
    }
  }
  true // Default to final
}

///|
/// Get the list of supertypes for a type index
pub fn get_supertypes(module_ : Module, type_idx : Int) -> Array[Int] {
  let result : Array[Int] = []
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx.reinterpret_as_int() == type_idx {
        for sup in subtype_def.supertypes {
          result.push(sup.reinterpret_as_int())
        }
        return result
      }
    }
  }
  result
}

///|
/// Check if two rec groups are structurally equivalent
/// This handles the recursive type equivalence rules in WebAssembly GC
pub fn rec_groups_equivalent(
  module_ : Module,
  group1_idx : Int,
  group2_idx : Int,
  visited : Array[(Int, Int)],
) -> Bool {
  // Same group is equivalent
  if group1_idx == group2_idx {
    return true
  }
  // Check if we've already determined these groups are equivalent (cycle detection)
  for v in visited {
    if (v.0 == group1_idx && v.1 == group2_idx) ||
      (v.0 == group2_idx && v.1 == group1_idx) {
      return true
    }
  }
  let types1 = get_rec_group_types(module_, group1_idx)
  let types2 = get_rec_group_types(module_, group2_idx)
  // Groups must have same number of types
  if types1.length() != types2.length() {
    return false
  }
  // Mark as being compared to handle cycles
  visited.push((group1_idx, group2_idx))
  // Check each corresponding type
  for i in 0..<types1.length() {
    let t1 = types1[i]
    let t2 = types2[i]
    if not(
        types_equivalent_in_context(module_, t1, t2, types1, types2, visited),
      ) {
      return false
    }
  }
  true
}

///|
/// Check if two types are equivalent in the context of their rec groups
pub fn types_equivalent_in_context(
  module_ : Module,
  type_idx1 : Int,
  type_idx2 : Int,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  if type_idx1 < 0 ||
    type_idx1 >= module_.types.length() ||
    type_idx2 < 0 ||
    type_idx2 >= module_.types.length() {
    return false
  }
  // Check structural type match
  match (module_.types[type_idx1], module_.types[type_idx2]) {
    (Func(f1), Func(f2)) => {
      // Check finality
      if is_type_final(module_, type_idx1) != is_type_final(module_, type_idx2) {
        return false
      }
      // Check params and results, handling recursive references
      if f1.params.length() != f2.params.length() ||
        f1.results.length() != f2.results.length() {
        return false
      }
      for i in 0..<f1.params.length() {
        if not(
            valtypes_equivalent_in_context(
              module_,
              f1.params[i],
              f2.params[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      for i in 0..<f1.results.length() {
        if not(
            valtypes_equivalent_in_context(
              module_,
              f1.results[i],
              f2.results[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      // Check supertypes are equivalent
      let supers1 = get_supertypes(module_, type_idx1)
      let supers2 = get_supertypes(module_, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              module_,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    (Struct(s1), Struct(s2)) => {
      if is_type_final(module_, type_idx1) != is_type_final(module_, type_idx2) {
        return false
      }
      if s1.fields.length() != s2.fields.length() {
        return false
      }
      for i in 0..<s1.fields.length() {
        if s1.fields[i].mutable != s2.fields[i].mutable {
          return false
        }
        if not(
            storage_types_equivalent_in_context(
              module_,
              s1.fields[i].storage,
              s2.fields[i].storage,
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      let supers1 = get_supertypes(module_, type_idx1)
      let supers2 = get_supertypes(module_, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              module_,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    (Array(a1), Array(a2)) => {
      if is_type_final(module_, type_idx1) != is_type_final(module_, type_idx2) {
        return false
      }
      if a1.element.mutable != a2.element.mutable {
        return false
      }
      if not(
          storage_types_equivalent_in_context(
            module_,
            a1.element.storage,
            a2.element.storage,
            group1_types,
            group2_types,
            visited,
          ),
        ) {
        return false
      }
      let supers1 = get_supertypes(module_, type_idx1)
      let supers2 = get_supertypes(module_, type_idx2)
      if supers1.length() != supers2.length() {
        return false
      }
      for i in 0..<supers1.length() {
        if not(
            type_refs_equivalent_in_context(
              module_,
              supers1[i],
              supers2[i],
              group1_types,
              group2_types,
              visited,
            ),
          ) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Check if two type references are equivalent considering rec group context
pub fn type_refs_equivalent_in_context(
  module_ : Module,
  ref1 : Int,
  ref2 : Int,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  let in_group1 = is_in_rec_group(group1_types, ref1)
  let in_group2 = is_in_rec_group(group2_types, ref2)
  if in_group1 && in_group2 {
    // Both are internal references - must be at same position
    let pos1 = get_position_in_group(group1_types, ref1)
    let pos2 = get_position_in_group(group2_types, ref2)
    pos1 == pos2
  } else if not(in_group1) && not(in_group2) {
    // Both are external references - must point to equivalent types
    if ref1 == ref2 {
      return true
    }
    let (g1, _) = get_rec_group_info(module_, ref1)
    let (g2, _) = get_rec_group_info(module_, ref2)
    rec_groups_equivalent(module_, g1, g2, visited)
  } else {
    // One internal, one external - not equivalent
    false
  }
}

///|
/// Check if two value types are equivalent in rec group context
pub fn valtypes_equivalent_in_context(
  module_ : Module,
  vt1 : ValType,
  vt2 : ValType,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  match (vt1, vt2) {
    (Ref(TypeIndex(idx1), n1), Ref(TypeIndex(idx2), n2)) =>
      n1 == n2 &&
      type_refs_equivalent_in_context(
        module_, idx1, idx2, group1_types, group2_types, visited,
      )
    _ => vt1 == vt2
  }
}

///|
/// Check if two storage types are equivalent in rec group context
pub fn storage_types_equivalent_in_context(
  module_ : Module,
  st1 : StorageType,
  st2 : StorageType,
  group1_types : Array[Int],
  group2_types : Array[Int],
  visited : Array[(Int, Int)],
) -> Bool {
  match (st1, st2) {
    (Val(vt1), Val(vt2)) =>
      valtypes_equivalent_in_context(
        module_, vt1, vt2, group1_types, group2_types, visited,
      )
    _ => st1 == st2
  }
}

///|
/// Check if two GC types are equivalent considering rec group membership
pub fn gc_types_equivalent(
  module_ : Module,
  type_idx1 : Int,
  type_idx2 : Int,
) -> Bool {
  if type_idx1 == type_idx2 {
    return true
  }
  let (group1_idx, _) = get_rec_group_info(module_, type_idx1)
  let (group2_idx, _) = get_rec_group_info(module_, type_idx2)
  let visited : Array[(Int, Int)] = []
  rec_groups_equivalent(module_, group1_idx, group2_idx, visited)
}
