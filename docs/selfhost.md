# wasm-gc Self-Hosting

This document summarizes the changes required to enable wasm5 (compiled with wasm-gc target) to parse, compile, and execute its own binary.

## Overview

wasm5 is a WebAssembly interpreter that can be built for two targets:

- **wasm (linear memory)**: Traditional WebAssembly. ~490KB
- **wasm-gc**: Uses GC proposal. ~310KB

For the wasm-gc build to interpret itself, proper handling of wasm-gc specific type system (struct/array type subtyping) was required.

## wasm-gc Instruction Coverage

### Struct Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `struct.new` | Create struct with field values |
| `struct.new_default` | Create struct with default values |
| `struct.get` | Get field value |
| `struct.get_s` | Get packed field (sign-extend) |
| `struct.get_u` | Get packed field (zero-extend) |
| `struct.set` | Set field value |

### Array Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `array.new` | Create array with value and length |
| `array.new_default` | Create array with default values |
| `array.new_fixed` | Create array from stack values |
| `array.new_data` | Create array from data segment |
| `array.new_elem` | Create array from element segment |
| `array.get` | Get element |
| `array.get_s` | Get packed element (sign-extend) |
| `array.get_u` | Get packed element (zero-extend) |
| `array.set` | Set element |
| `array.len` | Get array length |
| `array.fill` | Fill array range |
| `array.copy` | Copy between arrays |
| `array.init_data` | Initialize from data segment |
| `array.init_elem` | Initialize from element segment |

### i31 Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `ref.i31` | Create i31ref from i32 |
| `i31.get_s` | Extract signed i32 |
| `i31.get_u` | Extract unsigned i32 |

### Reference Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `ref.null` | Create null reference |
| `ref.is_null` | Test if null |
| `ref.eq` | Compare references |
| `ref.as_non_null` | Assert non-null |
| `ref.test` | Runtime type test |
| `ref.cast` | Runtime type cast |

### Branch Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `br_on_null` | Branch if null |
| `br_on_non_null` | Branch if non-null |
| `br_on_cast` | Branch on successful cast |
| `br_on_cast_fail` | Branch on failed cast |

### Conversion Operations (Complete)

| Instruction | Description |
|-------------|-------------|
| `any.convert_extern` | externref to anyref |
| `extern.convert_any` | anyref to externref |

## Required Changes for Self-Hosting

### 1. Pattern Match Order Fix for TypeIndex Subtyping

In `src/validate/validate_helpers.mbt`, the `is_subtype` function needed the `Ref(TypeIndex(...), ...)` pattern to match before more general patterns.

```moonbit
// Before: General pattern matches first, preventing TypeIndex handling
(Ref(ht1, false), Ref(ht2, true)) => ht1 == ht2
(Ref(TypeIndex(n1), nullable1), Ref(TypeIndex(n2), nullable2)) => ...

// After: TypeIndex pattern placed first
(Ref(TypeIndex(n1), nullable1), Ref(TypeIndex(n2), nullable2)) => ...
(Ref(ht1, false), Ref(ht2, true)) => ht1 == ht2
```

### 2. Explicit Supertype Declaration Search

The `is_type_index_subtype` function searches `module_.type_groups` to find explicit supertype declarations:

```moonbit
fn is_type_index_subtype(
  module_ : @core.Module,
  type_idx1 : Int,
  type_idx2 : Int,
) -> Bool {
  if type_idx1 == type_idx2 {
    return true
  }

  // Search type_groups for explicit supertype declarations
  for group in module_.type_groups {
    for subtype_def in group.subtypes {
      if subtype_def.type_idx == type_idx1 {
        for supertype in subtype_def.supertypes {
          if supertype == type_idx2 ||
             is_type_index_subtype(module_, supertype, type_idx2) {
            return true
          }
        }
      }
    }
  }

  // Also check structural subtyping
  ...
}
```

### 3. Structural Subtyping Implementation

In wasm-gc, structurally compatible types can be treated as subtypes even without explicit supertype declarations. The following functions were added:

#### Struct Type Subtyping

```moonbit
fn is_struct_subtype(
  module_ : @core.Module,
  struct1 : @core.StructType,
  struct2 : @core.StructType,
) -> Bool {
  // struct2's fields must be a prefix of struct1's fields
  if struct2.fields.length() > struct1.fields.length() {
    return false
  }

  for i in 0..<struct2.fields.length() {
    let f1 = struct1.fields[i]
    let f2 = struct2.fields[i]

    // Mutability must match exactly
    if f1.mutable != f2.mutable {
      return false
    }

    // Check field type subtyping
    if not(is_storage_type_subtype(module_, f1.storage, f2.storage, f1.mutable)) {
      return false
    }
  }
  true
}
```

#### Array Type Subtyping

```moonbit
fn is_array_subtype(
  module_ : @core.Module,
  arr1 : @core.ArrayType,
  arr2 : @core.ArrayType,
) -> Bool {
  if arr1.element.mutable != arr2.element.mutable {
    return false
  }
  is_storage_type_subtype(module_, arr1.element.storage, arr2.element.storage, arr1.element.mutable)
}
```

#### Function Type Subtyping

```moonbit
fn is_func_type_subtype(
  module_ : @core.Module,
  func1 : @core.FuncType,
  func2 : @core.FuncType,
) -> Bool {
  // Parameters are contravariant
  for i in 0..<func1.params.length() {
    if not(is_subtype(module_, func2.params[i], func1.params[i])) {
      return false
    }
  }
  // Results are covariant
  for i in 0..<func1.results.length() {
    if not(is_subtype(module_, func1.results[i], func2.results[i])) {
      return false
    }
  }
  true
}
```

### 4. NullRef as Subtype of TypeIndex References

`NullRef` is recognized as a subtype of nullable struct/array typed references:

```moonbit
(NullRef, Ref(TypeIndex(n), true)) =>
  is_struct_type_index(module_, n) || is_array_type_index(module_, n)
```

### 5. Runtime Type Checking for ref.test/ref.cast

Runtime type checking was implemented to support `ref.test`, `ref.cast`, `br_on_cast`, and `br_on_cast_fail`:

```moonbit
fn gc_ref_matches_type(
  rt : Runtime,
  ref_value : UInt64,
  target_type : Int,
  target_nullable : Bool,
) -> Bool {
  // Check for null reference
  if ref_value == 0UL {
    return target_nullable
  }

  // Check for i31ref (encoded with lowest bit set)
  if ref_value.land(1UL) == 1UL {
    return target_type == -4 || target_type == -3 || target_type == -2
  }

  // Get GC object and check type compatibility
  match gc_get_object(rt, ref_value.to_int()) {
    Some(Struct(s)) =>
      if target_type >= 0 {
        gc_is_type_subtype(rt, s.type_idx, target_type)
      } else {
        target_type == -5 || target_type == -3 || target_type == -2
      }
    Some(Array(a)) =>
      if target_type >= 0 {
        gc_is_type_subtype(rt, a.type_idx, target_type)
      } else {
        target_type == -6 || target_type == -3 || target_type == -2
      }
    _ => false
  }
}
```

## Testing

### Cross-Target Test

wasm-gc build interprets linear wasm:

```bash
node --stack-size=8192 test/selfhost/test_wasm_gc_cross.mjs
```

### Recursive Self-Hosting Test

wasm-gc build interprets itself:

```bash
node --stack-size=8192 test/selfhost/test_wasm_gc_recursive.mjs
```

## Related Files

- `src/validate/validate_helpers.mbt` - Validation-time subtype checking
- `src/runtime/ops_gc.mbt` - GC instruction runtime implementation
- `src/runtime/compile_emit.mbt` - GC instruction compilation
- `test/selfhost/` - Self-hosting test scripts

## Type Encoding

Abstract heap types are encoded as negative numbers for runtime type checking:

| Code | Type |
|------|------|
| -2 | any |
| -3 | eq |
| -4 | i31 |
| -5 | struct |
| -6 | array |
| -7 | func |
| -8 | extern |
| >= 0 | TypeIndex |
