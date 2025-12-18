#include <stdint.h>

float f32_from_i64(int64_t i) {
  return (float)(i);
}

float f32_from_u64(uint64_t i) {
  return (float)(i);
}

// Convert float to uint64 with proper truncation behavior
// Note: C casts truncate towards zero, matching WebAssembly semantics
uint64_t u64_from_f32(float f) {
  return (uint64_t)(f);
}

uint64_t u64_from_f64(double d) {
  return (uint64_t)(d);
}

