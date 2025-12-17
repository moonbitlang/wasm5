#include <stdint.h>

#if defined(__clang__)
#define MUSTTAIL __attribute__((musttail))
#elif defined(__GNUC__) && __GNUC__ >= 12
#define MUSTTAIL [[gnu::musttail]]
#else
#define MUSTTAIL
#endif

struct MinstrsArray {
  int32_t $1;
  void** minstrs_fixed_array;

};

struct Runtime {
  int32_t pc;
  int32_t $5;
  int64_t $8;
  void* $0;
  struct MinstrsArray* minstrs_array;
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

struct WasmInstr {
  int32_t(* func_ref)(void*);
};

int32_t next_op(void* rt) {
  struct Runtime* r = (struct Runtime*)rt;
  struct MinstrsArray* i = r->minstrs_array;
  int32_t pc = r->pc;
  void** instr_arr = i->minstrs_fixed_array;
  void* op = (void*)instr_arr[pc];
  struct WasmInstr* wasm_instr = (struct WasmInstr*)op;
  int32_t(*func)(void*) = (int32_t(*)(void*))wasm_instr->func_ref;
  MUSTTAIL return func(rt);
}
