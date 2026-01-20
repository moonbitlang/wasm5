///|
/// Error pattern matching for test harness
/// Consolidates repetitive if/else chains into declarative patterns

///|
/// Pattern for matching RuntimeError::InvalidType messages
priv struct InvalidTypePattern {
  msg_patterns : Array[String] // All must be present in error message
  expected_pattern : String // Must be present in expected_error
}

///|
/// Patterns for InvalidType error matching
/// Each pattern maps specific error message substrings to expected test error text
let invalid_type_patterns : Array[InvalidTypePattern] = [
  {
    msg_patterns: ["table", "out of bounds"],
    expected_pattern: "out of bounds table access",
  },
  {
    msg_patterns: ["array", "out of bounds"],
    expected_pattern: "out of bounds array access",
  },
  { msg_patterns: ["undefined element"], expected_pattern: "undefined element" },
  {
    msg_patterns: ["uninitialized element"],
    expected_pattern: "uninitialized element",
  },
  {
    msg_patterns: ["indirect call type mismatch"],
    expected_pattern: "indirect call type mismatch",
  },
  {
    msg_patterns: ["null", "function reference"],
    expected_pattern: "null function reference",
  },
  {
    msg_patterns: ["null i31 reference"],
    expected_pattern: "null i31 reference",
  },
  {
    msg_patterns: ["null structure reference"],
    expected_pattern: "null structure reference",
  },
  {
    msg_patterns: ["null array reference"],
    expected_pattern: "null array reference",
  },
  { msg_patterns: ["cast failed"], expected_pattern: "cast failure" },
  { msg_patterns: ["null reference"], expected_pattern: "null reference" },
]

///|
/// Match an InvalidType error message against known patterns
fn match_invalid_type_pattern(msg : String) -> InvalidTypePattern? {
  for pattern in invalid_type_patterns {
    let mut all_match = true
    for p in pattern.msg_patterns {
      if not(msg.contains(p)) {
        all_match = false
        break
      }
    }
    if all_match {
      return Some(pattern)
    }
  }
  None
}

///|
/// Mapping from RuntimeError variants to expected error text patterns
priv struct TrapErrorMapping {
  error_name : String
  expected_patterns : Array[String] // Any of these in expected_error is OK
}

///|
/// Standard trap error mappings (non-InvalidType errors)
let trap_error_mappings : Array[TrapErrorMapping] = [
  { error_name: "DivisionByZero", expected_patterns: ["divide by zero"] },
  {
    error_name: "IntegerOverflow",
    expected_patterns: ["overflow", "invalid conversion"],
  },
  {
    error_name: "MemoryOutOfBounds",
    expected_patterns: ["out of bounds memory access"],
  },
  {
    error_name: "TableOutOfBounds",
    expected_patterns: ["out of bounds table access"],
  },
  { error_name: "Unreachable", expected_patterns: ["unreachable"] },
]

///|
/// Check if expected error matches any of the acceptable patterns
fn matches_any_pattern(expected : String, patterns : Array[String]) -> Bool {
  for p in patterns {
    if expected.contains(p) {
      return true
    }
  }
  false
}

///|
/// Get the trap error mapping for a given error name
fn get_trap_mapping(error_name : String) -> TrapErrorMapping? {
  for mapping in trap_error_mappings {
    if mapping.error_name == error_name {
      return Some(mapping)
    }
  }
  None
}

///|
/// Validation error pattern for data-driven matching
priv struct ValidationErrorPattern {
  error_type : String // The ValidationError variant name
  expected_patterns : Array[String] // Acceptable patterns in expected_error
  special_check : ((String, String) -> Bool)? // Optional special check (msg, expected) -> matches
}

///|
/// Patterns for validation error matching
let validation_error_patterns : Array[ValidationErrorPattern] = [
  {
    error_type: "TypeMismatch",
    expected_patterns: ["type mismatch"],
    special_check: Some(check_type_mismatch_special_cases),
  },
  {
    error_type: "StackSizeMismatch",
    expected_patterns: ["type mismatch"],
    special_check: None,
  },
  {
    error_type: "InvalidResultArity",
    expected_patterns: ["invalid result arity"],
    special_check: None,
  },
  {
    error_type: "UnknownType",
    expected_patterns: ["unknown type"],
    special_check: None,
  },
  {
    error_type: "InvalidAlignment",
    expected_patterns: ["alignment"],
    special_check: None,
  },
  {
    error_type: "UnknownLabel",
    expected_patterns: ["unknown label"],
    special_check: None,
  },
  {
    error_type: "InvalidStartFunction",
    expected_patterns: ["start function"],
    special_check: None,
  },
  {
    error_type: "DuplicateExport",
    expected_patterns: ["duplicate export name"],
    special_check: None,
  },
  {
    error_type: "UnknownExportedFunction",
    expected_patterns: ["unknown function"],
    special_check: None,
  },
  {
    error_type: "UnknownExportedMemory",
    expected_patterns: ["unknown memory"],
    special_check: None,
  },
  {
    error_type: "UnknownExportedTable",
    expected_patterns: ["unknown table"],
    special_check: None,
  },
  {
    error_type: "UnknownGlobal",
    expected_patterns: ["unknown global"],
    special_check: None,
  },
  {
    error_type: "UnknownExportedGlobal",
    expected_patterns: ["unknown global"],
    special_check: None,
  },
  {
    error_type: "UninitializedLocal",
    expected_patterns: ["uninitialized local"],
    special_check: None,
  },
  {
    error_type: "UnknownDataSegment",
    expected_patterns: ["unknown data segment"],
    special_check: None,
  },
  {
    error_type: "InvalidElemIndex",
    expected_patterns: ["unknown elem segment"],
    special_check: None,
  },
]

///|
/// Special case handling for TypeMismatch validation errors
/// TypeMismatch covers various validation errors including "type mismatch",
/// "immutable field", "immutable array", "array types do not match",
/// and "array type is not numeric or vector"
fn check_type_mismatch_special_cases(msg : String, expected : String) -> Bool {
  // Standard type mismatch
  if expected.contains("type mismatch") {
    return true
  }
  // Immutable field
  if expected.contains("immutable field") && msg.contains("immutable") {
    return true
  }
  // Immutable array
  if expected.contains("immutable array") && msg.contains("immutable") {
    return true
  }
  // Array types do not match
  if expected.contains("array types do not match") &&
    msg.contains("array types do not match") {
    return true
  }
  // Array type is not numeric or vector
  if expected.contains("array type is not numeric or vector") &&
    msg.contains("array type is not numeric or vector") {
    return true
  }
  false
}

///|
/// Get validation error pattern by error type name
fn get_validation_pattern(error_type : String) -> ValidationErrorPattern? {
  for pattern in validation_error_patterns {
    if pattern.error_type == error_type {
      return Some(pattern)
    }
  }
  None
}

///|
/// Check if a validation error matches the expected error text
fn check_validation_error_match(
  error_type : String,
  msg : String,
  expected : String,
) -> Bool {
  match get_validation_pattern(error_type) {
    Some(pattern) =>
      // Check special cases first if defined
      match pattern.special_check {
        Some(check) => check(msg, expected)
        None => matches_any_pattern(expected, pattern.expected_patterns)
      }
    None => true // Unknown error type - accept any match
  }
}

///|
/// Check trap error against expected and return failure message if mismatch
/// Returns None if match is OK, Some(message) if there's a mismatch
fn check_trap_error_mismatch(
  error_name : String,
  expected : String,
  msg? : String = "",
) -> String? {
  match get_trap_mapping(error_name) {
    Some(mapping) =>
      if not(matches_any_pattern(expected, mapping.expected_patterns)) {
        Some("expected '\{expected}' but got \{error_name}")
      } else {
        None
      }
    None =>
      // Handle InvalidType with pattern matching
      if error_name == "InvalidType" {
        match match_invalid_type_pattern(msg) {
          Some(pattern) =>
            if not(expected.contains(pattern.expected_pattern)) {
              Some("expected '\{expected}' but got \{pattern.expected_pattern}")
            } else {
              None
            }
          None =>
            // No pattern matched, report the raw error
            Some("expected '\{expected}' but got: InvalidType(\{msg})")
        }
      } else {
        Some("expected '\{expected}' but got: \{error_name}")
      }
  }
}

///|
/// Check validation error against expected and return failure message if mismatch
/// Returns None if match is OK, Some(message) if there's a mismatch
fn check_validation_error_mismatch(
  error_type : String,
  msg : String,
  expected : String,
) -> String? {
  if check_validation_error_match(error_type, msg, expected) {
    None
  } else {
    Some("expected '\{expected}' but got \{error_type}")
  }
}
