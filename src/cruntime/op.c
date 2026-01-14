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
#define TRAP_OUT_OF_BOUNDS_TABLE        6  // "undefined element" - index out of bounds
#define TRAP_INDIRECT_CALL_TYPE_MISMATCH 7
#define TRAP_NULL_FUNCTION_REFERENCE    8
#define TRAP_STACK_OVERFLOW             9
#define TRAP_UNINITIALIZED_ELEMENT      10 // "uninitialized element" - null entry in table

// Macro to define getter function that returns op handler pointer
#define DEFINE_OP(name) uint64_t name(void) { return (uint64_t)op_##name; }

// ============================================================================
// Binary operation macros - reduce repetitive code for arithmetic/logical ops
// ============================================================================

// i32 binary op with unsigned operands (add, sub, mul, and, or, xor)
#define I32_BINARY_OP(name, expr) \
int op_i32_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    uint32_t b = (uint32_t)sp[-1]; \
    uint32_t a = (uint32_t)sp[-2]; \
    --sp; \
    sp[-1] = (uint64_t)(expr); \
    NEXT(); \
} \
DEFINE_OP(i32_##name)

// i32 comparison with unsigned operands
#define I32_CMP_OP(name, op) \
int op_i32_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    uint32_t b = (uint32_t)sp[-1]; \
    uint32_t a = (uint32_t)sp[-2]; \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(i32_##name)

// i32 comparison with signed operands
#define I32_CMP_OP_S(name, op) \
int op_i32_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    int32_t b = (int32_t)sp[-1]; \
    int32_t a = (int32_t)sp[-2]; \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(i32_##name)

// i64 binary op with simple expression
#define I64_BINARY_OP(name, expr) \
int op_i64_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    uint64_t b = sp[-1]; \
    uint64_t a = sp[-2]; \
    --sp; \
    sp[-1] = (expr); \
    NEXT(); \
} \
DEFINE_OP(i64_##name)

// i64 comparison with unsigned operands
#define I64_CMP_OP(name, op) \
int op_i64_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    uint64_t b = sp[-1]; \
    uint64_t a = sp[-2]; \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(i64_##name)

// i64 comparison with signed operands
#define I64_CMP_OP_S(name, op) \
int op_i64_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    int64_t b = (int64_t)sp[-1]; \
    int64_t a = (int64_t)sp[-2]; \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(i64_##name)

// f32 binary op
#define F32_BINARY_OP(name, op) \
int op_f32_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    float b = as_f32(sp[-1]); \
    float a = as_f32(sp[-2]); \
    --sp; \
    sp[-1] = from_f32(a op b); \
    NEXT(); \
} \
DEFINE_OP(f32_##name)

// f32 comparison
#define F32_CMP_OP(name, op) \
int op_f32_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    float b = as_f32(sp[-1]); \
    float a = as_f32(sp[-2]); \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(f32_##name)

// f64 binary op
#define F64_BINARY_OP(name, op) \
int op_f64_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    double b = as_f64(sp[-1]); \
    double a = as_f64(sp[-2]); \
    --sp; \
    sp[-1] = from_f64(a op b); \
    NEXT(); \
} \
DEFINE_OP(f64_##name)

// f64 comparison
#define F64_CMP_OP(name, op) \
int op_f64_##name(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) { \
    (void)crt; (void)fp; \
    double b = as_f64(sp[-1]); \
    double a = as_f64(sp[-2]); \
    --sp; \
    sp[-1] = (a op b ? 1 : 0); \
    NEXT(); \
} \
DEFINE_OP(f64_##name)

// ============================================================================

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

// Multiple tables support (for call_indirect)
static int* g_tables_flat = NULL;      // All tables concatenated
static int* g_table_offsets = NULL;    // Offset of each table in g_tables_flat
static int* g_table_sizes = NULL;      // Size of each table
static int g_num_tables = 0;

// Function metadata (for call_indirect)
static int* g_func_entries = NULL;
static int* g_func_num_locals = NULL;
static int g_num_funcs = 0;
static int g_num_imported_funcs = 0;

// Type information (for call_indirect type checking)
static int* g_func_type_idxs = NULL;       // Type index for each function
static int* g_type_sig_hash1 = NULL;       // Primary signature hash for each type
static int* g_type_sig_hash2 = NULL;       // Secondary signature hash for each type
static int g_num_types = 0;

// Stack base for result extraction after execution
static uint64_t* g_stack_base = NULL;

// Internal execution helper - starts the tail-call chain
static int run(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    OpFn first = (OpFn)*pc++;
    return first(crt, pc, sp, fp);
}

// Execute threaded code starting at entry point
// Returns trap code (0 = success), stores results in result_out[0..num_results-1]
int execute(uint64_t* code, int entry, int num_locals, uint64_t* args, int num_args,
            uint64_t* result_out, int num_results, uint64_t* globals, uint8_t* mem, int mem_size,
            int* memory_pages, int* tables_flat, int* table_offsets, int* table_sizes, int num_tables,
            int* func_entries, int* func_num_locals, int num_funcs, int num_imported_funcs,
            int* func_type_idxs, int* type_sig_hash1, int* type_sig_hash2, int num_types) {
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

    // Store table data for call_indirect
    g_tables_flat = tables_flat;
    g_table_offsets = table_offsets;
    g_table_sizes = table_sizes;
    g_num_tables = num_tables;

    // Store function metadata for call_indirect
    g_func_entries = func_entries;
    g_func_num_locals = func_num_locals;
    g_num_funcs = num_funcs;
    g_num_imported_funcs = num_imported_funcs;

    // Store type info for call_indirect type checking
    g_func_type_idxs = func_type_idxs;
    g_type_sig_hash1 = type_sig_hash1;
    g_type_sig_hash2 = type_sig_hash2;
    g_num_types = num_types;

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
    g_tables_flat = NULL;
    g_table_offsets = NULL;
    g_table_sizes = NULL;
    g_num_tables = 0;
    g_func_entries = NULL;
    g_func_num_locals = NULL;
    g_num_funcs = 0;
    g_num_imported_funcs = 0;
    g_func_type_idxs = NULL;
    g_type_sig_hash1 = NULL;
    g_type_sig_hash2 = NULL;
    g_num_types = 0;
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

// Function exit without copying - used by deferred blocks that already placed results at fp[0..n-1]
int op_func_exit(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)pc; (void)sp; (void)fp;
    return TRAP_NONE;
}
DEFINE_OP(func_exit)

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

// i32 arithmetic - simple binary ops use macros
I32_BINARY_OP(add, a + b)
I32_BINARY_OP(sub, a - b)
I32_BINARY_OP(mul, a * b)

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

I32_BINARY_OP(and, a & b)
I32_BINARY_OP(or, a | b)
I32_BINARY_OP(xor, a ^ b)
I32_BINARY_OP(shl, a << (b & 31))
I32_BINARY_OP(shr_u, a >> (b & 31))

// shr_s needs signed 'a' for arithmetic shift
int op_i32_shr_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t b = (uint32_t)sp[-1];
    int32_t a = (int32_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(uint32_t)(a >> (b & 31));
    NEXT();
}
DEFINE_OP(i32_shr_s)

// Rotations need special masking of b before use
I32_BINARY_OP(rotl, (a << (b & 31)) | (a >> (32 - (b & 31))))
I32_BINARY_OP(rotr, (a >> (b & 31)) | (a << (32 - (b & 31))))

// i32 comparison - eqz is unary, keep manual
int op_i32_eqz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint32_t a = (uint32_t)sp[-1];
    sp[-1] = (a == 0 ? 1 : 0);
    NEXT();
}
DEFINE_OP(i32_eqz)

// Binary comparisons use macros
I32_CMP_OP(eq, ==)
I32_CMP_OP(ne, !=)
I32_CMP_OP_S(lt_s, <)
I32_CMP_OP(lt_u, <)
I32_CMP_OP_S(gt_s, >)
I32_CMP_OP(gt_u, >)
I32_CMP_OP_S(le_s, <=)
I32_CMP_OP(le_u, <=)
I32_CMP_OP_S(ge_s, >=)
I32_CMP_OP(ge_u, >=)

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

// i64 arithmetic - simple binary ops use macros
I64_BINARY_OP(add, a + b)
I64_BINARY_OP(sub, a - b)
I64_BINARY_OP(mul, a * b)

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

I64_BINARY_OP(and, a & b)
I64_BINARY_OP(or, a | b)
I64_BINARY_OP(xor, a ^ b)
I64_BINARY_OP(shl, a << (b & 63))
I64_BINARY_OP(shr_u, a >> (b & 63))

// shr_s needs signed 'a' for arithmetic shift
int op_i64_shr_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    int64_t a = (int64_t)sp[-2];
    --sp;
    sp[-1] = (uint64_t)(a >> (b & 63));
    NEXT();
}
DEFINE_OP(i64_shr_s)

// Rotations need special masking
I64_BINARY_OP(rotl, (a << (b & 63)) | (a >> (64 - (b & 63))))
I64_BINARY_OP(rotr, (a >> (b & 63)) | (a << (64 - (b & 63))))

// i64 comparison - eqz is unary, keep manual
int op_i64_eqz(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t a = sp[-1];
    sp[-1] = (a == 0 ? 1 : 0);
    NEXT();
}
DEFINE_OP(i64_eqz)

// Binary comparisons use macros
I64_CMP_OP(eq, ==)
I64_CMP_OP(ne, !=)
I64_CMP_OP_S(lt_s, <)
I64_CMP_OP(lt_u, <)
I64_CMP_OP_S(gt_s, >)
I64_CMP_OP(gt_u, >)
I64_CMP_OP_S(le_s, <=)
I64_CMP_OP(le_u, <=)
I64_CMP_OP_S(ge_s, >=)
I64_CMP_OP(ge_u, >=)

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

// f32 arithmetic - simple binary ops use macros
F32_BINARY_OP(add, +)
F32_BINARY_OP(sub, -)
F32_BINARY_OP(mul, *)
F32_BINARY_OP(div, /)

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

// f32 comparison - use macros
F32_CMP_OP(eq, ==)
F32_CMP_OP(ne, !=)
F32_CMP_OP(lt, <)
F32_CMP_OP(gt, >)
F32_CMP_OP(le, <=)
F32_CMP_OP(ge, >=)

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

// f64 arithmetic - simple binary ops use macros
F64_BINARY_OP(add, +)
F64_BINARY_OP(sub, -)
F64_BINARY_OP(mul, *)
F64_BINARY_OP(div, /)

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

// f64 comparison - use macros
F64_CMP_OP(eq, ==)
F64_CMP_OP(ne, !=)
F64_CMP_OP(lt, <)
F64_CMP_OP(gt, >)
F64_CMP_OP(le, <=)
F64_CMP_OP(ge, >=)

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
    (void)fp;
    float a = as_f32(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 2147483648.0f || a < -2147483648.0f) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f32_s)

int op_i32_trunc_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    float a = as_f32(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 4294967296.0f || a <= -1.0f) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)(uint32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f32_u)

int op_i32_trunc_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    double a = as_f64(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    // Truncates toward zero, so -2147483648.9 → -2147483648 is valid
    if (a >= 2147483648.0 || a <= -2147483649.0) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}
DEFINE_OP(i32_trunc_f64_s)

int op_i32_trunc_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    double a = as_f64(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 4294967296.0 || a <= -1.0) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
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
    (void)fp;
    float a = as_f32(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 9223372036854775808.0f || a < -9223372036854775808.0f) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f32_s)

int op_i64_trunc_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    float a = as_f32(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 18446744073709551616.0f || a <= -1.0f) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f32_u)

int op_i64_trunc_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    double a = as_f64(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 9223372036854775808.0 || a < -9223372036854775808.0) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f64_s)

int op_i64_trunc_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    double a = as_f64(sp[-1]);
    if (isnan(a)) {
        TRAP(TRAP_INVALID_CONVERSION);
    }
    if (a >= 18446744073709551616.0 || a <= -1.0) {
        TRAP(TRAP_INTEGER_OVERFLOW);
    }
    sp[-1] = (uint64_t)a;
    NEXT();
}
DEFINE_OP(i64_trunc_f64_u)

// Saturating truncation operations (clamp instead of trap)

int op_i32_trunc_sat_f32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    int32_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 2147483648.0f) {
        result = 0x7FFFFFFF;  // INT32_MAX
    } else if (a < -2147483648.0f) {
        result = 0x80000000;  // INT32_MIN
    } else {
        result = (int32_t)a;
    }
    sp[-1] = (uint64_t)(uint32_t)result;
    NEXT();
}
DEFINE_OP(i32_trunc_sat_f32_s)

int op_i32_trunc_sat_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    uint32_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 4294967296.0f) {
        result = 0xFFFFFFFF;  // UINT32_MAX
    } else if (a <= -1.0f) {
        result = 0;
    } else {
        result = (uint32_t)a;
    }
    sp[-1] = (uint64_t)result;
    NEXT();
}
DEFINE_OP(i32_trunc_sat_f32_u)

int op_i32_trunc_sat_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    int32_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 2147483648.0) {
        result = 0x7FFFFFFF;  // INT32_MAX
    } else if (a < -2147483648.0) {
        result = 0x80000000;  // INT32_MIN
    } else {
        result = (int32_t)a;
    }
    sp[-1] = (uint64_t)(uint32_t)result;
    NEXT();
}
DEFINE_OP(i32_trunc_sat_f64_s)

int op_i32_trunc_sat_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    uint32_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 4294967296.0) {
        result = 0xFFFFFFFF;  // UINT32_MAX
    } else if (a <= -1.0) {
        result = 0;
    } else {
        result = (uint32_t)a;
    }
    sp[-1] = (uint64_t)result;
    NEXT();
}
DEFINE_OP(i32_trunc_sat_f64_u)

int op_i64_trunc_sat_f32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    int64_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 9223372036854775808.0f) {
        result = 0x7FFFFFFFFFFFFFFF;  // INT64_MAX
    } else if (a < -9223372036854775808.0f) {
        result = 0x8000000000000000;  // INT64_MIN
    } else {
        result = (int64_t)a;
    }
    sp[-1] = (uint64_t)result;
    NEXT();
}
DEFINE_OP(i64_trunc_sat_f32_s)

int op_i64_trunc_sat_f32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    float a = as_f32(sp[-1]);
    uint64_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 18446744073709551616.0f) {
        result = 0xFFFFFFFFFFFFFFFF;  // UINT64_MAX
    } else if (a <= -1.0f) {
        result = 0;
    } else {
        result = (uint64_t)a;
    }
    sp[-1] = result;
    NEXT();
}
DEFINE_OP(i64_trunc_sat_f32_u)

int op_i64_trunc_sat_f64_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    int64_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 9223372036854775808.0) {
        result = 0x7FFFFFFFFFFFFFFF;  // INT64_MAX
    } else if (a < -9223372036854775808.0) {
        result = 0x8000000000000000;  // INT64_MIN
    } else {
        result = (int64_t)a;
    }
    sp[-1] = (uint64_t)result;
    NEXT();
}
DEFINE_OP(i64_trunc_sat_f64_s)

int op_i64_trunc_sat_f64_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    double a = as_f64(sp[-1]);
    uint64_t result;
    if (isnan(a)) {
        result = 0;
    } else if (a >= 18446744073709551616.0) {
        result = 0xFFFFFFFFFFFFFFFF;  // UINT64_MAX
    } else if (a <= -1.0) {
        result = 0;
    } else {
        result = (uint64_t)a;
    }
    sp[-1] = result;
    NEXT();
}
DEFINE_OP(i64_trunc_sat_f64_u)

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

// i64 loads
int op_i64_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 8 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint64_t value = *(uint64_t*)(crt->mem + addr);
    sp[-1] = value;
    NEXT();
}
DEFINE_OP(i64_load)

int op_i64_load8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 1 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    int8_t value = *(int8_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load8_s)

int op_i64_load8_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
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
DEFINE_OP(i64_load8_u)

int op_i64_load16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 2 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    int16_t value = *(int16_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load16_s)

int op_i64_load16_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
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
DEFINE_OP(i64_load16_u)

int op_i64_load32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    int32_t value = *(int32_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load32_s)

int op_i64_load32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint32_t value = *(uint32_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i64_load32_u)

// i64 stores
int op_i64_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t value = sp[-1];
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 8 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint64_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(i64_store)

int op_i64_store8(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
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
DEFINE_OP(i64_store8)

int op_i64_store16(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
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
DEFINE_OP(i64_store16)

int op_i64_store32(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
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
DEFINE_OP(i64_store32)

// f32 load/store
int op_f32_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint32_t value = *(uint32_t*)(crt->mem + addr);
    sp[-1] = (uint64_t)value;  // Store f32 bits in lower 32 bits
    NEXT();
}
DEFINE_OP(f32_load)

int op_f32_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t value = (uint32_t)sp[-1];  // f32 bits in lower 32 bits
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 4 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint32_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(f32_store)

// f64 load/store
int op_f64_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t addr = (uint32_t)sp[-1] + offset;
    if (addr + 8 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    uint64_t value = *(uint64_t*)(crt->mem + addr);
    sp[-1] = value;  // f64 bits
    NEXT();
}
DEFINE_OP(f64_load)

int op_f64_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    ++pc;  // Skip align
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t value = sp[-1];  // f64 bits
    uint32_t addr = (uint32_t)sp[-2] + offset;
    sp -= 2;
    if (addr + 8 > g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    *(uint64_t*)(crt->mem + addr) = value;
    NEXT();
}
DEFINE_OP(f64_store)

// call_indirect - call function via table
// Immediates: type_idx, table_idx, frame_offset
// Stack: [..., args..., elem_idx] -> [..., results...]
int op_call_indirect(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int expected_type_idx = (int)*pc++;
    int table_idx = (int)*pc++;
    int frame_offset = (int)*pc++;

    // Pop element index from stack
    --sp;
    int32_t elem_idx = (int32_t)*sp;

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
    }

    // Get table bounds
    int table_offset = g_table_offsets[table_idx];
    int table_size = g_table_sizes[table_idx];

    // Check element index bounds
    if (elem_idx < 0 || elem_idx >= table_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);  // "undefined element"
    }

    // Get function index from table
    int func_idx = g_tables_flat[table_offset + elem_idx];

    // Check for null/uninitialized element (-1 means null)
    if (func_idx < 0) {
        TRAP(TRAP_UNINITIALIZED_ELEMENT);  // "uninitialized element"
    }

    // Type check: compare expected type with actual function type using signature hashes
    if (func_idx < g_num_imported_funcs + g_num_funcs) {
        int actual_type_idx = g_func_type_idxs[func_idx];
        if (expected_type_idx >= 0 && expected_type_idx < g_num_types &&
            actual_type_idx >= 0 && actual_type_idx < g_num_types) {
            // Compare both signature hashes - they encode actual types, not just counts
            int expected_hash1 = g_type_sig_hash1[expected_type_idx];
            int expected_hash2 = g_type_sig_hash2[expected_type_idx];
            int actual_hash1 = g_type_sig_hash1[actual_type_idx];
            int actual_hash2 = g_type_sig_hash2[actual_type_idx];
            if (expected_hash1 != actual_hash1 || expected_hash2 != actual_hash2) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }
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
