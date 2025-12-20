#include <stdint.h>

#if defined(__clang__)
#define MUSTTAIL __attribute__((musttail))
#elif defined(__GNUC__) && __GNUC__ >= 12
#define MUSTTAIL [[gnu::musttail]]
#else
#define MUSTTAIL
#endif

// Array[UInt64] representation
struct U64Array {
  int32_t length;
  uint64_t* data;
};

struct Runtime {
  int32_t pc;
  int32_t $5;
  int64_t $8;
  void* $0;
  struct U64Array* ops;  // Heterogeneous code stream (function pointers + immediates)
  void* $2;
  void* $3;
  void* $6;
  void* $7;
  void* $9;
  void* $10;
  void* $11;
  void* $12;
  void* $13;
};

int32_t next_op(void* rt) {
  struct Runtime* r = (struct Runtime*)rt;
  struct U64Array* ops_array = r->ops;
  int32_t pc = r->pc;
  uint64_t* ops = ops_array->data;

  // Read the function pointer directly as UInt64
  uint64_t func_bits = ops[pc];

  // Cast to function pointer
  int32_t(*func)(void*) = (int32_t(*)(void*))func_bits;

  MUSTTAIL return func(rt);
}

uint64_t funcref_to_u64(void* func_ref) {
  return (uint64_t)func_ref;
}

void* u64_to_funcref(uint64_t val) {
  return (void*)val;
}