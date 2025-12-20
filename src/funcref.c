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
  // Scalars first (in source order)
  int32_t sp;           // mut sp : Int
  int32_t pc;           // mut pc : Int
  int32_t num_locals;   // mut num_locals : Int
  int32_t running;      // mut running : Bool
  int64_t memory_max;   // memory_max : UInt? (scalar, not reference!)

  // References after (in source order)
  void* module_;        // module_ : Module
  struct U64Array* ops; // ops : Array[UInt64]
  void* stack;          // stack : Array[Value]
  void* call_stack;     // call_stack : Array[CallFrame]
  void* memory;         // memory : Array[Byte]
  void* globals;        // globals : Array[Value]
  void* tables;         // tables : Array[RuntimeTable]
  void* imported_funcs; // imported_funcs : Array[ImportedFunc]
  void* data_segments;  // data_segments : Array[Array[Byte]]
  void* error_detail;   // error_detail : String
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