#include <stdint.h>
#include <stdlib.h>

typedef struct {
    uint64_t* pc;      // Program counter into code array
    uint64_t* sp;      // Stack pointer (points to next push slot)
    uint64_t* fp;      // Frame pointer (start of locals)
    uint8_t* mem;      // Linear memory
    int running;       // 1 = running, 0 = stopped
} CRuntime;

typedef void (*OpFn)(CRuntime*);

#define NEXT() ((OpFn)*crt->pc++)(crt)

// Execute threaded code starting at entry point
// Returns the top of stack value (result), or 0 if stack is empty
uint64_t execute(uint64_t* code, int entry, int num_locals, uint64_t* args, int num_args) {
    // Allocate stack: locals + operand space
    uint64_t stack[256];  // Fixed size for now

    // Initialize locals from args
    for (int i = 0; i < num_args; i++) {
        stack[i] = args[i];
    }
    // Zero remaining locals
    for (int i = num_args; i < num_locals; i++) {
        stack[i] = 0;
    }

    CRuntime crt;
    crt.pc = code + entry;
    crt.fp = stack;
    crt.sp = stack + num_locals;  // Operand stack starts after locals
    crt.mem = NULL;
    crt.running = 1;

    // Start execution by calling first opcode
    ((OpFn)*crt.pc++)(&crt);

    // Return result (top of stack, or 0 if empty)
    if (crt.sp > stack + num_locals) {
        return crt.sp[-1];
    }
    return 0;
}

// Control operations

void op_wasm_unreachable(CRuntime* crt) {
    // Trap - stop execution
    crt->running = 0;
}

uint64_t wasm_unreachable(void) {
    return (uint64_t)op_wasm_unreachable;
}

void op_nop(CRuntime* crt) {
    NEXT();
}

uint64_t nop(void) {
    return (uint64_t)op_nop;
}

void op_end(CRuntime* crt) {
    // End of function - stop execution
    crt->running = 0;
}

uint64_t end(void) {
    return (uint64_t)op_end;
}

void op_wasm_return(CRuntime* crt) {
    // Return - stop execution (simplified for now)
    crt->running = 0;
}

uint64_t wasm_return(void) {
    return (uint64_t)op_wasm_return;
}

// Constants

void op_i32_const(CRuntime* crt) {
    *crt->sp++ = *crt->pc++;  // Push immediate
    NEXT();
}

uint64_t i32_const(void) {
    return (uint64_t)op_i32_const;
}

void op_i64_const(CRuntime* crt) {
    *crt->sp++ = *crt->pc++;  // Push immediate
    NEXT();
}

uint64_t i64_const(void) {
    return (uint64_t)op_i64_const;
}

void op_f32_const(CRuntime* crt) {
    *crt->sp++ = *crt->pc++;  // Push immediate (stored as uint64)
    NEXT();
}

uint64_t f32_const(void) {
    return (uint64_t)op_f32_const;
}

void op_f64_const(CRuntime* crt) {
    *crt->sp++ = *crt->pc++;  // Push immediate
    NEXT();
}

uint64_t f64_const(void) {
    return (uint64_t)op_f64_const;
}

// Local/Global access

void op_local_get(CRuntime* crt) {
    int64_t idx = (int64_t)*crt->pc++;
    *crt->sp++ = crt->fp[idx];
    NEXT();
}

uint64_t local_get(void) {
    return (uint64_t)op_local_get;
}

void op_local_set(CRuntime* crt) {
    int64_t idx = (int64_t)*crt->pc++;
    crt->fp[idx] = *--crt->sp;
    NEXT();
}

uint64_t local_set(void) {
    return (uint64_t)op_local_set;
}

void op_local_tee(CRuntime* crt) {
    int64_t idx = (int64_t)*crt->pc++;
    crt->fp[idx] = crt->sp[-1];  // Don't pop
    NEXT();
}

uint64_t local_tee(void) {
    return (uint64_t)op_local_tee;
}

void op_global_get(CRuntime* crt) {
    // TODO: implement with globals array
    crt->pc++;  // Skip index for now
    *crt->sp++ = 0;
    NEXT();
}

uint64_t global_get(void) {
    return (uint64_t)op_global_get;
}

void op_global_set(CRuntime* crt) {
    // TODO: implement with globals array
    crt->pc++;  // Skip index
    crt->sp--;  // Pop value
    NEXT();
}

uint64_t global_set(void) {
    return (uint64_t)op_global_set;
}

// i32 arithmetic

void op_i32_add(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a + b);
    NEXT();
}

uint64_t i32_add(void) {
    return (uint64_t)op_i32_add;
}

void op_i32_sub(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a - b);
    NEXT();
}

uint64_t i32_sub(void) {
    return (uint64_t)op_i32_sub;
}

void op_i32_mul(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a * b);
    NEXT();
}

uint64_t i32_mul(void) {
    return (uint64_t)op_i32_mul;
}

void op_i32_div_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) {
        crt->running = 0;  // Trap
        return;
    }
    crt->sp[-1] = (uint64_t)(uint32_t)(a / b);
    NEXT();
}

uint64_t i32_div_s(void) {
    return (uint64_t)op_i32_div_s;
}

void op_i32_div_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) {
        crt->running = 0;  // Trap
        return;
    }
    crt->sp[-1] = (uint64_t)(a / b);
    NEXT();
}

uint64_t i32_div_u(void) {
    return (uint64_t)op_i32_div_u;
}

void op_i32_rem_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) {
        crt->running = 0;  // Trap
        return;
    }
    crt->sp[-1] = (uint64_t)(uint32_t)(a % b);
    NEXT();
}

uint64_t i32_rem_s(void) {
    return (uint64_t)op_i32_rem_s;
}

void op_i32_rem_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) {
        crt->running = 0;  // Trap
        return;
    }
    crt->sp[-1] = (uint64_t)(a % b);
    NEXT();
}

uint64_t i32_rem_u(void) {
    return (uint64_t)op_i32_rem_u;
}

void op_i32_and(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a & b);
    NEXT();
}

uint64_t i32_and(void) {
    return (uint64_t)op_i32_and;
}

void op_i32_or(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a | b);
    NEXT();
}

uint64_t i32_or(void) {
    return (uint64_t)op_i32_or;
}

void op_i32_xor(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a ^ b);
    NEXT();
}

uint64_t i32_xor(void) {
    return (uint64_t)op_i32_xor;
}

void op_i32_shl(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a << (b & 31));
    NEXT();
}

uint64_t i32_shl(void) {
    return (uint64_t)op_i32_shl;
}

void op_i32_shr_s(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(uint32_t)(a >> (b & 31));
    NEXT();
}

uint64_t i32_shr_s(void) {
    return (uint64_t)op_i32_shr_s;
}

void op_i32_shr_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a >> (b & 31));
    NEXT();
}

uint64_t i32_shr_u(void) {
    return (uint64_t)op_i32_shr_u;
}

void op_i32_rotl(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1] & 31;
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)((a << b) | (a >> (32 - b)));
    NEXT();
}

uint64_t i32_rotl(void) {
    return (uint64_t)op_i32_rotl;
}

void op_i32_rotr(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1] & 31;
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)((a >> b) | (a << (32 - b)));
    NEXT();
}

uint64_t i32_rotr(void) {
    return (uint64_t)op_i32_rotr;
}

// i32 comparison

void op_i32_eqz(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(a == 0 ? 1 : 0);
    NEXT();
}

uint64_t i32_eqz(void) {
    return (uint64_t)op_i32_eqz;
}

void op_i32_eq(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a == b ? 1 : 0);
    NEXT();
}

uint64_t i32_eq(void) {
    return (uint64_t)op_i32_eq;
}

void op_i32_ne(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a != b ? 1 : 0);
    NEXT();
}

uint64_t i32_ne(void) {
    return (uint64_t)op_i32_ne;
}

void op_i32_lt_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a < b ? 1 : 0);
    NEXT();
}

uint64_t i32_lt_s(void) {
    return (uint64_t)op_i32_lt_s;
}

void op_i32_lt_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a < b ? 1 : 0);
    NEXT();
}

uint64_t i32_lt_u(void) {
    return (uint64_t)op_i32_lt_u;
}

void op_i32_gt_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a > b ? 1 : 0);
    NEXT();
}

uint64_t i32_gt_s(void) {
    return (uint64_t)op_i32_gt_s;
}

void op_i32_gt_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a > b ? 1 : 0);
    NEXT();
}

uint64_t i32_gt_u(void) {
    return (uint64_t)op_i32_gt_u;
}

void op_i32_le_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a <= b ? 1 : 0);
    NEXT();
}

uint64_t i32_le_s(void) {
    return (uint64_t)op_i32_le_s;
}

void op_i32_le_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a <= b ? 1 : 0);
    NEXT();
}

uint64_t i32_le_u(void) {
    return (uint64_t)op_i32_le_u;
}

void op_i32_ge_s(CRuntime* crt) {
    int32_t b = (int32_t)crt->sp[-1];
    int32_t a = (int32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a >= b ? 1 : 0);
    NEXT();
}

uint64_t i32_ge_s(void) {
    return (uint64_t)op_i32_ge_s;
}

void op_i32_ge_u(CRuntime* crt) {
    uint32_t b = (uint32_t)crt->sp[-1];
    uint32_t a = (uint32_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a >= b ? 1 : 0);
    NEXT();
}

uint64_t i32_ge_u(void) {
    return (uint64_t)op_i32_ge_u;
}

// i32 unary

void op_i32_clz(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(a == 0 ? 32 : __builtin_clz(a));
    NEXT();
}

uint64_t i32_clz(void) {
    return (uint64_t)op_i32_clz;
}

void op_i32_ctz(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(a == 0 ? 32 : __builtin_ctz(a));
    NEXT();
}

uint64_t i32_ctz(void) {
    return (uint64_t)op_i32_ctz;
}

void op_i32_popcnt(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)__builtin_popcount(a);
    NEXT();
}

uint64_t i32_popcnt(void) {
    return (uint64_t)op_i32_popcnt;
}
