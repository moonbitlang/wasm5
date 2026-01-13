#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <limits.h>
#include <stdio.h>

// Debug flag - set to 1 to enable tracing
#define DEBUG_TRACE 0
#if DEBUG_TRACE
#define TRACE(...) fprintf(stderr, __VA_ARGS__)
#else
#define TRACE(...)
#endif

// Trap codes - must match MoonBit TrapCode enum values
#define TRAP_NONE                       0
#define TRAP_UNREACHABLE                1
#define TRAP_DIVISION_BY_ZERO           2
#define TRAP_INTEGER_OVERFLOW           3
#define TRAP_INVALID_CONVERSION         4
#define TRAP_OUT_OF_BOUNDS_MEMORY       5
#define TRAP_OUT_OF_BOUNDS_TABLE        6
#define TRAP_INDIRECT_CALL_TYPE_MISMATCH 7
#define TRAP_NULL_FUNCTION_REFERENCE    8
#define TRAP_STACK_OVERFLOW             9

// Macro to define getter function that returns op handler pointer
#define DEFINE_OP(name) uint64_t name(void) { return (uint64_t)op_##name; }

// CRuntime holds only cold fields - pc/sp/fp are passed as parameters for performance
typedef struct {
    uint64_t* code;    // Base of code array (for computing branch targets)
    uint8_t* mem;      // Linear memory
    uint64_t* globals; // Global variables array
} CRuntime;

// OpFn signature: hot fields (pc, sp, fp) passed as pointers for register allocation
typedef int (*OpFn)(CRuntime*, uint64_t*, uint64_t*, uint64_t*);

// Force tail call optimization for threaded code dispatch
#if defined(__clang__) || (defined(__GNUC__) && __GNUC__ >= 13)
#define MUSTTAIL __attribute__((musttail))
#else
#define MUSTTAIL
#endif

// NEXT: fetch next opcode and tail-call with updated pc
#define NEXT() do { \
    OpFn next = (OpFn)*pc++; \
    MUSTTAIL return next(crt, pc, sp, fp); \
} while(0)

#define TRAP(code) return (code)

// Stack size: 64K slots = 512KB
#define STACK_SIZE 65536

// Memory pages info (shared across calls within same instance)
static int* g_memory_pages = NULL;
static int g_memory_size = 0;

// Table and function metadata (for call_indirect)
static int* g_table = NULL;
static int g_table_size = 0;
static int* g_func_entries = NULL;
static int* g_func_num_locals = NULL;
static int g_num_funcs = 0;
static int g_num_imported_funcs = 0;

// Stack base for result extraction after execution
static uint64_t* g_stack_base = NULL;

// Internal execution helper - starts the tail-call chain
static int run(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    OpFn first = (OpFn)*pc++;
    return first(crt, pc, sp, fp);
}

// Execute threaded code starting at entry point
// Returns trap code (0 = success), stores results in result_out[0..num_results-1]
int execute(uint64_t* code, int entry, int num_locals, uint64_t* args, int num_args, uint64_t* result_out, int num_results, uint64_t* globals, uint8_t* mem, int mem_size, int* memory_pages, int* table, int table_size, int* func_entries, int* func_num_locals, int num_funcs, int num_imported_funcs) {
    // Allocate stack on heap to avoid C stack limits
    uint64_t* stack = (uint64_t*)malloc(STACK_SIZE * sizeof(uint64_t));
    if (!stack) {
        return TRAP_STACK_OVERFLOW;
    }

    // Initialize locals from args
    for (int i = 0; i < num_args; i++) {
        stack[i] = args[i];
    }
    // Zero remaining locals
    for (int i = num_args; i < num_locals; i++) {
        stack[i] = 0;
    }

    // Store memory info for ops
    g_memory_pages = memory_pages;
    g_memory_size = mem_size;

    // Store table and function metadata for call_indirect
    g_table = table;
    g_table_size = table_size;
    g_func_entries = func_entries;
    g_func_num_locals = func_num_locals;
    g_num_funcs = num_funcs;
    g_num_imported_funcs = num_imported_funcs;

    // Store stack base for result extraction
    g_stack_base = stack;

    // Set up CRuntime with cold fields only
    CRuntime crt;
    crt.code = code;
    crt.mem = mem;
    crt.globals = globals;

    // Set up hot state as pointers
    uint64_t* pc = code + entry;
    uint64_t* fp = stack;
    uint64_t* sp = stack + num_locals;

    // Start execution
    int trap = run(&crt, pc, sp, fp);

    // Store results (results are placed at stack[0..num_results-1] by end/return)
    if (result_out) {
        for (int i = 0; i < num_results; i++) {
            result_out[i] = stack[i];
        }
    }
    free(stack);

    // Reset global pointers to prevent dangling references to MoonBit-managed memory
    // (GC could free these arrays after execution, causing SIGSEGV on next access)
    g_memory_pages = NULL;
    g_memory_size = 0;
    g_table = NULL;
    g_table_size = 0;
    g_func_entries = NULL;
    g_func_num_locals = NULL;
    g_num_funcs = 0;
    g_num_imported_funcs = 0;
    g_stack_base = NULL;

    return trap;
}

// Control operations

int op_wasm_unreachable(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)pc; (void)sp; (void)fp;
    TRAP(TRAP_UNREACHABLE);
}
DEFINE_OP(wasm_unreachable)

int op_nop(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    NEXT();
}
DEFINE_OP(nop)

// End of function - copy results and return (wasm3 style)
// Immediate: num_results
int op_end(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt;
    int num_results = (int)*pc;
    // Copy results from stack top to fp[0..num_results-1]
    for (int i = 0; i < num_results; i++) {
        fp[i] = sp[i - num_results];
    }
    return TRAP_NONE;
}
DEFINE_OP(end)

// Call a local function (wasm3 style - uses native C stack)
// Immediates: callee_pc, frame_offset
// frame_offset: offset from current fp to new frame (computed at compile time)
int op_call(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int callee_pc = (int)*pc++;
    int frame_offset = (int)*pc++;

    // Save caller pc (fp already saved implicitly via recursive call)
    uint64_t* caller_pc = pc;

    // New frame starts at fp + frame_offset (args already copied there by compiler)
    uint64_t* new_fp = fp + frame_offset;
    uint64_t* new_pc = crt->code + callee_pc;

    // Execute callee (recursive call using native C stack)
    int trap = run(crt, new_pc, sp, new_fp);

    if (trap != TRAP_NONE) {
        return trap;
    }

    // Restore caller pc, fp unchanged
    pc = caller_pc;
    NEXT();
}
DEFINE_OP(call)

// Function entry - set sp and zero non-arg locals
// Immediates: num_locals (for sp), first_local_to_zero, num_to_zero
int op_entry(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int num_locals = (int)*pc++;
    int first_local = (int)*pc++;
    int num_to_zero = (int)*pc++;
    // Set sp to start after locals
    sp = fp + num_locals;
    // Zero non-arg locals
    for (int i = 0; i < num_to_zero; i++) {
        fp[first_local + i] = 0;
    }
    NEXT();
}
DEFINE_OP(entry)

// Return from function
// Immediate: num_results
// Copies results from stack top to fp[0..num_results-1]
int op_wasm_return(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt;
    int num_results = (int)*pc;
    // Copy results from stack top to fp[0..num_results-1]
    for (int i = 0; i < num_results; i++) {
        fp[i] = sp[i - num_results];
        TRACE("return: result[%d] = %lld\n", i, (long long)fp[i]);
    }
    return TRAP_NONE;
}
DEFINE_OP(wasm_return)

// Copy between absolute slot positions (wasm3 style)
// fp[dst_slot] = fp[src_slot]
int op_copy_slot(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int src_slot = (int)*pc++;
    int dst_slot = (int)*pc++;
    uint64_t val = fp[src_slot];
    fp[dst_slot] = val;
    TRACE("copy_slot: slot[%d] -> slot[%d], val=%lld\n", src_slot, dst_slot, (long long)val);
    NEXT();
}
DEFINE_OP(copy_slot)

// Set stack pointer to absolute slot position
int op_set_sp(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int slot = (int)*pc++;
    TRACE("set_sp: sp = fp + %d (top value at slot %d = %lld)\n", slot, slot-1, (long long)(slot > 0 ? fp[slot-1] : 0));
    sp = fp + slot;
    NEXT();
}
DEFINE_OP(set_sp)

// Unconditional branch - just jump (stack already adjusted by preceding ops)
// Immediate: target_idx
int op_br(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int target_idx = (int)*pc;
    TRACE("br: jumping to pc=%d\n", target_idx);
    pc = crt->code + target_idx;
    NEXT();
}
DEFINE_OP(br)

// Conditional branch
// For taken branch: jumps to a resolution block that handles stack + final jump
// Immediates: taken_idx, not_taken_idx
int op_br_if(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int taken_idx = (int)*pc++;
    int not_taken_idx = (int)*pc++;
    int32_t cond = (int32_t)*--sp;
    TRACE("br_if: cond=%d, taken=%d, not_taken=%d, going to %d\n", cond, taken_idx, not_taken_idx, cond ? taken_idx : not_taken_idx);
    pc = crt->code + (cond ? taken_idx : not_taken_idx);
    NEXT();
}
DEFINE_OP(br_if)

// If statement
// Immediate: else_idx (code index for else branch)
int op_wasm_if(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int else_idx = (int)*pc++;
    int32_t cond = (int32_t)*--sp;
    if (!cond) {
        pc = crt->code + else_idx;
    }
    NEXT();
}
DEFINE_OP(wasm_if)

// Branch table - each entry points to a resolution block
// Immediates: num_labels, then (num_labels + 1) target indices
int op_br_table(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int num_labels = (int)*pc++;
    int32_t index = (int32_t)*--sp;

    // Clamp index to default (last entry)
    if (index < 0 || index >= num_labels) {
        index = num_labels;
    }

    int target_idx = (int)pc[index];
    pc = crt->code + target_idx;
    NEXT();
}
DEFINE_OP(br_table)

// Constants

int op_i32_const(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    uint64_t val = *pc++;
    *sp++ = val;
    TRACE("i32_const: pushed %lld at slot %lld\n", (long long)val, (long long)((sp - fp) - 1));
    NEXT();
}
DEFINE_OP(i32_const)

int op_i64_const(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    *sp++ = *pc++;  // Push immediate
    NEXT();
}
DEFINE_OP(i64_const)

int op_f32_const(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    *sp++ = *pc++;  // Push immediate (stored as uint64)
    NEXT();
}
DEFINE_OP(f32_const)

int op_f64_const(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    *sp++ = *pc++;  // Push immediate
    NEXT();
}
DEFINE_OP(f64_const)

// Local/Global access

int op_local_get(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int64_t idx = (int64_t)*pc++;
    uint64_t val = fp[idx];
    *sp++ = val;
    TRACE("local_get: local[%lld] = %lld, pushed to slot %lld\n", (long long)idx, (long long)val, (long long)((sp - fp) - 1));
    NEXT();
}
DEFINE_OP(local_get)

int op_local_set(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int64_t idx = (int64_t)*pc++;
    uint64_t val = *--sp;
    fp[idx] = val;
    TRACE("local_set: local[%lld] = %lld\n", (long long)idx, (long long)val);
    NEXT();
}
DEFINE_OP(local_set)

int op_local_tee(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int64_t idx = (int64_t)*pc++;
    fp[idx] = sp[-1];  // Don't pop
    NEXT();
}
DEFINE_OP(local_tee)

int op_global_get(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int idx = (int)*pc++;
    *sp++ = crt->globals[idx];
    NEXT();
}
DEFINE_OP(global_get)

int op_global_set(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int idx = (int)*pc++;
    crt->globals[idx] = *--sp;
    NEXT();
}
DEFINE_OP(global_set)

// i32 arithmetic

int op_i32_add(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    uint32_t result = a + b;
    sp[-1] = (uint64_t)result;
    TRACE("i32_add: %u + %u = %u\n", a, b, result);
    NEXT();
}
DEFINE_OP(i32_add)

int op_i32_sub(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a - b);
    NEXT();
}
DEFINE_OP(i32_sub)

int op_i32_mul(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a * b);
    NEXT();
}
DEFINE_OP(i32_mul)

int op_i32_div_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    if (b == -1 && a == INT32_MIN) TRAP(TRAP_INTEGER_OVERFLOW);
    --sp;
    sp[-1] = (uint64_t)(uint32_t)(a / b);
    NEXT();
}
DEFINE_OP(i32_div_s)

int op_i32_div_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    sp[-1] = (uint64_t)(a / b);
    NEXT();
}
DEFINE_OP(i32_div_u)

int op_i32_rem_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    // Note: INT32_MIN % -1 is defined as 0 in WebAssembly (no trap)
    sp[-1] = (b == -1) ? 0 : (uint64_t)(uint32_t)(a % b);
    NEXT();
}
DEFINE_OP(i32_rem_s)

int op_i32_rem_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    sp[-1] = (uint64_t)(a % b);
    NEXT();
}
DEFINE_OP(i32_rem_u)

int op_i32_and(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a & b);
    NEXT();
}
DEFINE_OP(i32_and)

int op_i32_or(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a | b);
    NEXT();
}
DEFINE_OP(i32_or)

int op_i32_xor(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a ^ b);
    NEXT();
}
DEFINE_OP(i32_xor)

int op_i32_shl(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a << (b & 31));
    NEXT();
}
DEFINE_OP(i32_shl)

int op_i32_shr_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(uint32_t)(a >> (b & 31));
    NEXT();
}
DEFINE_OP(i32_shr_s)

int op_i32_shr_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a >> (b & 31));
    NEXT();
}
DEFINE_OP(i32_shr_u)

int op_i32_rotl(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1] & 31;
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)((a << b) | (a >> (32 - b)));
    NEXT();
}
DEFINE_OP(i32_rotl)

int op_i32_rotr(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1] & 31;
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)((a >> b) | (a << (32 - b)));
    NEXT();
}
DEFINE_OP(i32_rotr)

// i32 comparison

int op_i32_eqz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (uint64_t)(a == 0 ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_eqz)

int op_i32_eq(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a == b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_eq)

int op_i32_ne(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a != b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_ne)

int op_i32_lt_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_lt_s)

int op_i32_lt_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_lt_u)

int op_i32_gt_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_gt_s)

int op_i32_gt_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_gt_u)

int op_i32_le_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_le_s)

int op_i32_le_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_le_u)

int op_i32_ge_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t b = (int32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_ge_s)

int op_i32_ge_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    uint32_t a = (uint32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_ge_u)

// i32 unary

int op_i32_clz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (uint64_t)(a == 0 ? 32 : __builtin_clz(a));
    NEXT();
}
DEFINE_OP(i32_clz)

int op_i32_ctz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (uint64_t)(a == 0 ? 32 : __builtin_ctz(a));
    NEXT();
}
DEFINE_OP(i32_ctz)

int op_i32_popcnt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (uint64_t)__builtin_popcount(a);
    NEXT();
}
DEFINE_OP(i32_popcnt)

// i64 arithmetic

int op_i64_add(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a + b;
    NEXT();
}
DEFINE_OP(i64_add)

int op_i64_sub(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a - b;
    NEXT();
}
DEFINE_OP(i64_sub)

int op_i64_mul(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a * b;
    NEXT();
}
DEFINE_OP(i64_mul)

int op_i64_div_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    if (b == -1 && a == INT64_MIN) TRAP(TRAP_INTEGER_OVERFLOW);
    --sp;
    sp[-1] = (uint64_t)(a / b);
    NEXT();
}
DEFINE_OP(i64_div_s)

int op_i64_div_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    sp[-1] = a / b;
    NEXT();
}
DEFINE_OP(i64_div_u)

int op_i64_rem_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    // Note: INT64_MIN % -1 is defined as 0 in WebAssembly (no trap)
    sp[-1] = (b == -1) ? 0 : (uint64_t)(a % b);
    NEXT();
}
DEFINE_OP(i64_rem_s)

int op_i64_rem_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    if (b == 0) TRAP(TRAP_DIVISION_BY_ZERO);
    --sp;
    sp[-1] = a % b;
    NEXT();
}
DEFINE_OP(i64_rem_u)

int op_i64_and(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a & b;
    NEXT();
}
DEFINE_OP(i64_and)

int op_i64_or(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a | b;
    NEXT();
}
DEFINE_OP(i64_or)

int op_i64_xor(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a ^ b;
    NEXT();
}
DEFINE_OP(i64_xor)

int op_i64_shl(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a << (b & 63);
    NEXT();
}
DEFINE_OP(i64_shl)

int op_i64_shr_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a >> (b & 63));
    NEXT();
}
DEFINE_OP(i64_shr_s)

int op_i64_shr_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = a >> (b & 63);
    NEXT();
}
DEFINE_OP(i64_shr_u)

int op_i64_rotl(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1] & 63;
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a << b) | (a >> (64 - b));
    NEXT();
}
DEFINE_OP(i64_rotl)

int op_i64_rotr(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1] & 63;
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a >> b) | (a << (64 - b));
    NEXT();
}
DEFINE_OP(i64_rotr)

// i64 comparison

int op_i64_eqz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = (a == 0 ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_eqz)

int op_i64_eq(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a == b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_eq)

int op_i64_ne(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a != b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_ne)

int op_i64_lt_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_lt_s)

int op_i64_lt_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_lt_u)

int op_i64_gt_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_gt_s)

int op_i64_gt_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_gt_u)

int op_i64_le_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_le_s)

int op_i64_le_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_le_u)

int op_i64_ge_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t b = (int64_t)sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_ge_s)

int op_i64_ge_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_ge_u)

// i64 unary

int op_i64_clz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = (a == 0 ? 64 : __builtin_clzll(a));
    NEXT();
}
DEFINE_OP(i64_clz)

int op_i64_ctz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = (a == 0 ? 64 : __builtin_ctzll(a));
    NEXT();
}
DEFINE_OP(i64_ctz)

int op_i64_popcnt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = __builtin_popcountll(a);
    NEXT();
}
DEFINE_OP(i64_popcnt)

// f32 helpers
static inline float as_f32(uint64_t v) {
    union { uint32_t i; float f; } u = { .i = (uint32_t)v };
    return u.f;
}

static inline uint64_t from_f32(float f) {
    union { float f; uint32_t i; } u = { .f = f };
    return u.i;
}

// f64 helpers
static inline double as_f64(uint64_t v) {
    union { uint64_t i; double f; } u = { .i = v };
    return u.f;
}

static inline uint64_t from_f64(double f) {
    union { double f; uint64_t i; } u = { .f = f };
    return u.i;
}

// Canonical NaN values (per WebAssembly spec)
#define CANONICAL_NAN_F32 0x7FC00000U
#define CANONICAL_NAN_F64 0x7FF8000000000000ULL
#define F32_SIGN_MASK 0x80000000U
#define F64_SIGN_MASK 0x8000000000000000ULL

// f32 arithmetic

int op_f32_add(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = from_f32(a + b);
    NEXT();
}
DEFINE_OP(f32_add)

int op_f32_sub(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = from_f32(a - b);
    NEXT();
}
DEFINE_OP(f32_sub)

int op_f32_mul(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = from_f32(a * b);
    NEXT();
}
DEFINE_OP(f32_mul)

int op_f32_div(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = from_f32(a / b);
    NEXT();
}
DEFINE_OP(f32_div)

int op_f32_min(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    // WebAssembly spec: if either operand is NaN, return canonical NaN
    if (isnan(a) || isnan(b)) {
        sp[-1] = CANONICAL_NAN_F32;
    } else if (a < b) {
        sp[-1] = from_f32(a);
    } else if (b < a) {
        sp[-1] = from_f32(b);
    } else {
        // a == b: handle signed zeros (-0.0 < +0.0 for min)
        uint32_t a_bits = (uint32_t)from_f32(a);
        uint32_t b_bits = (uint32_t)from_f32(b);
        if ((a_bits & F32_SIGN_MASK) || (b_bits & F32_SIGN_MASK)) {
            // Return negative zero if either is negative
            sp[-1] = (a_bits & F32_SIGN_MASK) ? from_f32(a) : from_f32(b);
        } else {
            sp[-1] = from_f32(a);
        }
    }
    NEXT();
}
DEFINE_OP(f32_min)

int op_f32_max(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    // WebAssembly spec: if either operand is NaN, return canonical NaN
    if (isnan(a) || isnan(b)) {
        sp[-1] = CANONICAL_NAN_F32;
    } else if (a > b) {
        sp[-1] = from_f32(a);
    } else if (b > a) {
        sp[-1] = from_f32(b);
    } else {
        // a == b: handle signed zeros (+0.0 > -0.0 for max)
        uint32_t a_bits = (uint32_t)from_f32(a);
        uint32_t b_bits = (uint32_t)from_f32(b);
        if (!(a_bits & F32_SIGN_MASK) || !(b_bits & F32_SIGN_MASK)) {
            // Return positive zero if either is positive
            sp[-1] = !(a_bits & F32_SIGN_MASK) ? from_f32(a) : from_f32(b);
        } else {
            sp[-1] = from_f32(a);
        }
    }
    NEXT();
}
DEFINE_OP(f32_max)

int op_f32_copysign(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = from_f32(copysignf(a, b));
    NEXT();
}
DEFINE_OP(f32_copysign)

// f32 comparison

int op_f32_eq(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a == b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_eq)

int op_f32_ne(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a != b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_ne)

int op_f32_lt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_lt)

int op_f32_gt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_gt)

int op_f32_le(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_le)

int op_f32_ge(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float b = as_f32(sp[-1]);
    float a = as_f32(sp[-2]);
    --sp;
    sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f32_ge)

// f32 unary

int op_f32_abs(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(fabsf(a));
    NEXT();
}
DEFINE_OP(f32_abs)

int op_f32_neg(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(-a);
    NEXT();
}
DEFINE_OP(f32_neg)

int op_f32_ceil(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(ceilf(a));
    NEXT();
}
DEFINE_OP(f32_ceil)

int op_f32_floor(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(floorf(a));
    NEXT();
}
DEFINE_OP(f32_floor)

int op_f32_trunc(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(truncf(a));
    NEXT();
}
DEFINE_OP(f32_trunc)

int op_f32_nearest(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(rintf(a));
    NEXT();
}
DEFINE_OP(f32_nearest)

int op_f32_sqrt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f32(sqrtf(a));
    NEXT();
}
DEFINE_OP(f32_sqrt)

// f64 arithmetic

int op_f64_add(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = from_f64(a + b);
    NEXT();
}
DEFINE_OP(f64_add)

int op_f64_sub(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = from_f64(a - b);
    NEXT();
}
DEFINE_OP(f64_sub)

int op_f64_mul(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = from_f64(a * b);
    NEXT();
}
DEFINE_OP(f64_mul)

int op_f64_div(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = from_f64(a / b);
    NEXT();
}
DEFINE_OP(f64_div)

int op_f64_min(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    // WebAssembly spec: if either operand is NaN, return canonical NaN
    if (isnan(a) || isnan(b)) {
        sp[-1] = CANONICAL_NAN_F64;
    } else if (a < b) {
        sp[-1] = from_f64(a);
    } else if (b < a) {
        sp[-1] = from_f64(b);
    } else {
        // a == b: handle signed zeros (-0.0 < +0.0 for min)
        uint64_t a_bits = from_f64(a);
        uint64_t b_bits = from_f64(b);
        if ((a_bits & F64_SIGN_MASK) || (b_bits & F64_SIGN_MASK)) {
            // Return negative zero if either is negative
            sp[-1] = (a_bits & F64_SIGN_MASK) ? from_f64(a) : from_f64(b);
        } else {
            sp[-1] = from_f64(a);
        }
    }
    NEXT();
}
DEFINE_OP(f64_min)

int op_f64_max(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    // WebAssembly spec: if either operand is NaN, return canonical NaN
    if (isnan(a) || isnan(b)) {
        sp[-1] = CANONICAL_NAN_F64;
    } else if (a > b) {
        sp[-1] = from_f64(a);
    } else if (b > a) {
        sp[-1] = from_f64(b);
    } else {
        // a == b: handle signed zeros (+0.0 > -0.0 for max)
        uint64_t a_bits = from_f64(a);
        uint64_t b_bits = from_f64(b);
        if (!(a_bits & F64_SIGN_MASK) || !(b_bits & F64_SIGN_MASK)) {
            // Return positive zero if either is positive
            sp[-1] = !(a_bits & F64_SIGN_MASK) ? from_f64(a) : from_f64(b);
        } else {
            sp[-1] = from_f64(a);
        }
    }
    NEXT();
}
DEFINE_OP(f64_max)

int op_f64_copysign(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = from_f64(copysign(a, b));
    NEXT();
}
DEFINE_OP(f64_copysign)

// f64 comparison

int op_f64_eq(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a == b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_eq)

int op_f64_ne(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a != b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_ne)

int op_f64_lt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a < b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_lt)

int op_f64_gt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a > b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_gt)

int op_f64_le(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_le)

int op_f64_ge(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double b = as_f64(sp[-1]);
    double a = as_f64(sp[-2]);
    --sp;
    sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}
DEFINE_OP(f64_ge)

// f64 unary

int op_f64_abs(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(fabs(a));
    NEXT();
}
DEFINE_OP(f64_abs)

int op_f64_neg(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(-a);
    NEXT();
}
DEFINE_OP(f64_neg)

int op_f64_ceil(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(ceil(a));
    NEXT();
}
DEFINE_OP(f64_ceil)

int op_f64_floor(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(floor(a));
    NEXT();
}
DEFINE_OP(f64_floor)

int op_f64_trunc(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(trunc(a));
    NEXT();
}
DEFINE_OP(f64_trunc)

int op_f64_nearest(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(rint(a));
    NEXT();
}
DEFINE_OP(f64_nearest)

int op_f64_sqrt(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f64(sqrt(a));
    NEXT();
}
DEFINE_OP(f64_sqrt)

// Conversions

int op_i32_wrap_i64(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    sp[-1] = (uint32_t)sp[-1];
    NEXT();
}
DEFINE_OP(i32_wrap_i64)

int op_i32_trunc_f32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f32_s)

int op_i32_trunc_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = (uint64_t)(uint32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f32_u)

int op_i32_trunc_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f64_s)

int op_i32_trunc_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = (uint64_t)(uint32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f64_u)

int op_i64_extend_i32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t a = (int32_t)sp[-1];
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_extend_i32_s)

int op_i64_extend_i32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (uint64_t)a;
    NEXT();
}
DEFINE_OP(i64_extend_i32_u)

int op_i64_trunc_f32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f32_s)

int op_i64_trunc_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = (uint64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f32_u)

int op_i64_trunc_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f64_s)

int op_i64_trunc_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = (uint64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f64_u)

int op_f32_convert_i32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t a = (int32_t)sp[-1];
    sp[-1] = from_f32((float)a);
    NEXT();
}
DEFINE_OP(f32_convert_i32_s)

int op_f32_convert_i32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = from_f32((float)a);
    NEXT();
}
DEFINE_OP(f32_convert_i32_u)

int op_f32_convert_i64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t a = (int64_t)sp[-1];
    sp[-1] = from_f32((float)a);
    NEXT();
}
DEFINE_OP(f32_convert_i64_s)

int op_f32_convert_i64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = from_f32((float)a);
    NEXT();
}
DEFINE_OP(f32_convert_i64_u)

int op_f32_demote_f64(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    sp[-1] = from_f32((float)a);
    NEXT();
}
DEFINE_OP(f32_demote_f64)

int op_f64_convert_i32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t a = (int32_t)sp[-1];
    sp[-1] = from_f64((double)a);
    NEXT();
}
DEFINE_OP(f64_convert_i32_s)

int op_f64_convert_i32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = from_f64((double)a);
    NEXT();
}
DEFINE_OP(f64_convert_i32_u)

int op_f64_convert_i64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int64_t a = (int64_t)sp[-1];
    sp[-1] = from_f64((double)a);
    NEXT();
}
DEFINE_OP(f64_convert_i64_s)

int op_f64_convert_i64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = from_f64((double)a);
    NEXT();
}
DEFINE_OP(f64_convert_i64_u)

int op_f64_promote_f32(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    sp[-1] = from_f64((double)a);
    NEXT();
}
DEFINE_OP(f64_promote_f32)

int op_i32_reinterpret_f32(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    // Already stored as bits, just mask to 32 bits
    sp[-1] = sp[-1] & 0xFFFFFFFF;
    NEXT();
}
DEFINE_OP(i32_reinterpret_f32)

int op_i64_reinterpret_f64(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    // Already stored as bits, nothing to do
    NEXT();
}
DEFINE_OP(i64_reinterpret_f64)

int op_f32_reinterpret_i32(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    // Already stored as bits, nothing to do
    NEXT();
}
DEFINE_OP(f32_reinterpret_i32)

int op_f64_reinterpret_i64(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    // Already stored as bits, nothing to do
    NEXT();
}
DEFINE_OP(f64_reinterpret_i64)

// Sign extension

int op_i32_extend8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int8_t a = (int8_t)sp[-1];
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_extend8_s)

int op_i32_extend16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int16_t a = (int16_t)sp[-1];
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_extend16_s)

int op_i64_extend8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int8_t a = (int8_t)sp[-1];
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_extend8_s)

int op_i64_extend16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int16_t a = (int16_t)sp[-1];
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_extend16_s)

int op_i64_extend32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int32_t a = (int32_t)sp[-1];
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_extend32_s)

// Stack operations

int op_wasm_drop(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    --sp;
    NEXT();
}
DEFINE_OP(wasm_drop)

int op_wasm_select(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t c = (uint32_t)sp[-1];
    uint64_t b = sp[-2];
    uint64_t a = sp[-3];
    sp -= 2;
    sp[-1] = c ? a : b;
    NEXT();
}
DEFINE_OP(wasm_select)

// Memory operations

int op_memory_grow(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    ++pc;  // Skip mem_idx (assume 0)
    uint32_t delta = (uint32_t)sp[-1];
    // Return current page count and update
    int32_t old_pages = g_memory_pages ? *g_memory_pages : 0;
    // For now, accept any growth (simplified - doesn't actually allocate)
    if (g_memory_pages) {
        *g_memory_pages = old_pages + delta;
    }
    sp[-1] = (uint64_t)(uint32_t)old_pages;
    NEXT();
}
DEFINE_OP(memory_grow)

int op_memory_size(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    ++pc;  // Skip mem_idx (assume 0)
    int32_t pages = g_memory_pages ? *g_memory_pages : 0;
    *sp++ = (uint64_t)(uint32_t)pages;
    NEXT();
}
DEFINE_OP(memory_size)

int op_i32_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint32_t value = *(uint32_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)value;
    NEXT();
}
DEFINE_OP(i32_load)

int op_i32_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t value = (uint32_t)sp[-1];
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint32_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(i32_store)

// Narrow loads - sign/zero extend to i32
int op_i32_load8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 1 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    int8_t value = *(int8_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)(int32_t)value;  // Sign extend
    NEXT();
}
DEFINE_OP(i32_load8_s)

int op_i32_load8_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 1 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint8_t value = *(uint8_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i32_load8_u)

int op_i32_load16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 2 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    int16_t value = *(int16_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)(int32_t)value;  // Sign extend
    NEXT();
}
DEFINE_OP(i32_load16_s)

int op_i32_load16_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 2 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint16_t value = *(uint16_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i32_load16_u)

// Narrow stores - truncate from i32
int op_i32_store8(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint8_t value = (uint8_t)sp[-1];
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 1 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint8_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(i32_store8)

int op_i32_store16(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint16_t value = (uint16_t)sp[-1];
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 2 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint16_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(i32_store16)

// call_indirect - call function via table
// Immediates: type_idx, table_idx, frame_offset
// Stack: [..., args..., elem_idx] -> [..., results...]
int op_call_indirect(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    ++pc;  // Skip type_idx (not needed for simplified impl)
    ++pc;  // Skip table_idx (assume 0)
    int frame_offset = (int)*pc++;

    // Pop element index from stack
    --sp;
    int32_t elem_idx = (int32_t)*sp;

    // Check table bounds
    if (elem_idx < 0 || elem_idx >= g_table_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
    }

    // Get function index from table
    int func_idx = g_table[elem_idx];

    // Check for null/undefined element (-1 means null)
    if (func_idx < 0) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
    }

    // Convert to local function index
    int local_idx = func_idx - g_num_imported_funcs;
    if (local_idx < 0 || local_idx >= g_num_funcs) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
    }

    // Get callee entry point
    int callee_entry = g_func_entries[local_idx];

    // Save caller pc (fp saved via new_fp calculation)
    uint64_t* caller_pc = pc;

    // New frame starts at fp + frame_offset (args already in place)
    uint64_t* new_fp = fp + frame_offset;
    uint64_t* new_pc = crt->code + callee_entry;

    // Execute callee (recursive call using native C stack)
    int trap = run(crt, new_pc, sp, new_fp);

    if (trap != TRAP_NONE) {
        return trap;
    }

    // Restore caller pc, fp unchanged
    pc = caller_pc;
    NEXT();
}
DEFINE_OP(call_indirect)
