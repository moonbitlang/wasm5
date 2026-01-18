///|
/// Validate that a name is in kebab-case
/// kebab-case: lowercase letters, digits, and hyphens, starting with letter
pub fn is_kebab_case(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  let chars = name.to_array()
  // First character must be lowercase letter
  if not(is_lowercase_letter(chars[0])) {
    return false
  }
  // Rest must be lowercase letters, digits, or hyphens
  // Cannot have consecutive hyphens or end with hyphen
  let mut prev_hyphen = false
  for i = 1; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '-' {
      if prev_hyphen {
        return false // consecutive hyphens
      }
      prev_hyphen = true
    } else if is_lowercase_letter(c) || is_digit(c) {
      prev_hyphen = false
    } else {
      return false // invalid character
    }
  }
  // Cannot end with hyphen
  not(prev_hyphen)
}

///|
fn is_lowercase_letter(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Convert a character to lowercase
fn char_to_lowercase(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// Convert a string to lowercase
pub fn to_lowercase(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s {
    sb.write_char(char_to_lowercase(c))
  }
  sb.to_string()
}

///|
/// Validate extern name format
/// Valid formats:
/// - plain kebab-case name
/// - interface name: namespace:package/interface@version
/// - url: https://...
pub fn is_valid_extern_name(name : Bytes) -> Bool {
  let s = bytes_to_string(name)
  if s.is_empty() {
    return false
  }
  // Check for URL format
  if s.has_prefix("https://") || s.has_prefix("http://") {
    return true
  }
  // Check for interface format (contains ':' and '/')
  if s.contains(":") && s.contains("/") {
    return validate_interface_name(s)
  }
  // Plain kebab-case name
  is_kebab_case(s)
}

///|
fn validate_interface_name(name : String) -> Bool {
  match validate_interface_name_detailed(name) {
    None => true
    Some(_) => false
  }
}

///|
/// Validate interface name and return detailed error message if invalid
pub fn validate_interface_name_detailed(name : String) -> String? {
  // Format: namespace:package/interface@version
  // or: namespace:package/interface
  let parts = split_string(name, ':')
  if parts.length() != 2 {
    if parts.length() > 2 {
      return Some("expected `/` after package name")
    }
    return Some("invalid interface name format")
  }
  let ns = parts[0]
  let rest = parts[1]
  if not(is_kebab_case(ns)) {
    return Some("namespace is not in kebab case")
  }
  // rest should be package/interface@version or package/interface
  let slash_parts = split_string(rest, '/')
  if slash_parts.length() < 2 {
    return Some("missing interface name after package")
  }
  if slash_parts.length() > 2 {
    // More than one slash after package - trailing characters
    let trailing = "/" + slash_parts[2]
    return Some("trailing characters found: `\{trailing}`")
  }
  let pkg = slash_parts[0]
  if not(is_kebab_case(pkg)) {
    return Some("package name is not in kebab case")
  }
  // interface@version or just interface
  let interface_part = slash_parts[1]
  let at_parts = split_string(interface_part, '@')
  let interface_name = at_parts[0]
  if not(is_kebab_case(interface_name)) {
    return Some("interface name is not in kebab case")
  }
  // Validate version if present
  if at_parts.length() > 1 {
    let version = at_parts[1]
    match validate_semver(version) {
      Some(err) => return Some(err)
      None => ()
    }
  }
  None
}

///|
/// Validate semver format: MAJOR.MINOR.PATCH[-prerelease][+build]
fn validate_semver(version : String) -> String? {
  if version.is_empty() {
    return Some("empty string")
  }
  let chars = version.to_array()
  let mut i = 0
  // Parse major version (must start with digit)
  if i >= chars.length() {
    return Some("unexpected end of input")
  }
  if not(is_digit(chars[i])) {
    return Some("unexpected character '\{chars[i]}'")
  }
  // Skip major number
  while i < chars.length() && is_digit(chars[i]) {
    i = i + 1
  }
  // Expect '.' or end
  if i >= chars.length() {
    return None // Just major is OK for simplified semver
  }
  if chars[i] != '.' && chars[i] != '-' && chars[i] != '+' {
    return Some("unexpected character '\{chars[i]}'")
  }
  if chars[i] == '.' {
    i = i + 1
    // Parse minor version
    if i >= chars.length() {
      return Some("unexpected end of input")
    }
    if not(is_digit(chars[i])) {
      return Some("unexpected character '\{chars[i]}'")
    }
    while i < chars.length() && is_digit(chars[i]) {
      i = i + 1
    }
    // Optionally parse patch
    if i < chars.length() && chars[i] == '.' {
      i = i + 1
      if i >= chars.length() {
        return Some("unexpected end of input")
      }
      if not(is_digit(chars[i])) {
        return Some("unexpected character '\{chars[i]}'")
      }
      while i < chars.length() && is_digit(chars[i]) {
        i = i + 1
      }
    }
  }
  // After version numbers, only - or + or end is allowed
  if i < chars.length() && chars[i] != '-' && chars[i] != '+' {
    return Some("unexpected character '\{chars[i]}'")
  }
  // Parse prerelease (-) or build metadata (+)
  if i < chars.length() {
    if chars[i] == '-' || chars[i] == '+' {
      i = i + 1
      if i >= chars.length() {
        return Some("empty identifier segment")
      }
      // Must have at least one character after - or +
      let start = i
      while i < chars.length() &&
            chars[i] != '-' &&
            chars[i] != '+' &&
            chars[i] != '.' {
        i = i + 1
      }
      if i == start {
        return Some("empty identifier segment")
      }
    }
  }
  None
}

///|
fn split_string(s : String, sep : Char) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for c in s {
    if c == sep {
      result.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  result.push(current.to_string())
  result
}

///|
fn bytes_to_string(b : Bytes) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < b.length(); i = i + 1 {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Check if name contains expected dot character for method/constructor names
pub fn has_dot_character(name : String) -> Bool {
  name.contains(".")
}

///|
/// Validate export name
/// Export names should be valid extern names
pub fn is_valid_export_name(name : Bytes) -> Bool {
  is_valid_extern_name(name)
}

///|
/// Validate import name
pub fn is_valid_import_name(name : Bytes) -> Bool {
  is_valid_extern_name(name)
}
