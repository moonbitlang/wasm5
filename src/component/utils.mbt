// Component Runtime Utility Functions

///|
/// Convert Bytes to String (ASCII only, for export names etc.)
fn bytes_to_string(b : Bytes) -> String {
  let chars : Array[Char] = []
  for i = 0; i < b.length(); i = i + 1 {
    chars.push(b[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

///|
/// Convert String to Bytes (ASCII only, for function names etc.)
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// Convert a string to UTF-8 bytes (using @encoding/utf8)
fn string_to_utf8(s : String) -> Bytes {
  @encoding/utf8.encode(s)
}

///|
/// Convert UTF-8 bytes to a string (using @encoding/utf8)
fn utf8_to_string(bytes : Bytes) -> String {
  @encoding/utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
/// Convert a string to UTF-16 code units
fn string_to_utf16(s : String) -> Array[Int] {
  let code_units : Array[Int] = []
  for c in s {
    let cp = c.to_uint().reinterpret_as_int()
    if cp < 0x10000 {
      // BMP character - single code unit
      code_units.push(cp)
    } else {
      // Supplementary character - surrogate pair
      let adjusted = cp - 0x10000
      let high_surrogate = 0xD800 + (adjusted >> 10)
      let low_surrogate = 0xDC00 + (adjusted & 0x3FF)
      code_units.push(high_surrogate)
      code_units.push(low_surrogate)
    }
  }
  code_units
}

///|
/// Convert UTF-16 code units to a string
fn utf16_to_string(code_units : Array[Int]) -> String {
  let chars : Array[Char] = []
  let mut i = 0
  while i < code_units.length() {
    let cu = code_units[i]
    if cu >= 0xD800 && cu <= 0xDBFF && i + 1 < code_units.length() {
      // High surrogate - check for low surrogate
      let next = code_units[i + 1]
      if next >= 0xDC00 && next <= 0xDFFF {
        // Valid surrogate pair
        let high = cu - 0xD800
        let low = next - 0xDC00
        let cp = 0x10000 + (high << 10) + low
        chars.push(cp.unsafe_to_char())
        i = i + 2
        continue
      }
    }
    // Single code unit or invalid surrogate
    chars.push(cu.unsafe_to_char())
    i = i + 1
  }
  String::from_array(chars)
}

///|
/// Align a value to the given alignment
fn align_to(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}
