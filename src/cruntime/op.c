#include <stdint.h>
#include <stdlib.h>
#include <math.h>

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

// i64 arithmetic

void op_i64_add(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a + b;
    NEXT();
}

uint64_t i64_add(void) { return (uint64_t)op_i64_add; }

void op_i64_sub(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a - b;
    NEXT();
}

uint64_t i64_sub(void) { return (uint64_t)op_i64_sub; }

void op_i64_mul(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a * b;
    NEXT();
}

uint64_t i64_mul(void) { return (uint64_t)op_i64_mul; }

void op_i64_div_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) { crt->running = 0; return; }
    crt->sp[-1] = (uint64_t)(a / b);
    NEXT();
}

uint64_t i64_div_s(void) { return (uint64_t)op_i64_div_s; }

void op_i64_div_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    if (b == 0) { crt->running = 0; return; }
    crt->sp[-1] = a / b;
    NEXT();
}

uint64_t i64_div_u(void) { return (uint64_t)op_i64_div_u; }

void op_i64_rem_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    if (b == 0) { crt->running = 0; return; }
    crt->sp[-1] = (uint64_t)(a % b);
    NEXT();
}

uint64_t i64_rem_s(void) { return (uint64_t)op_i64_rem_s; }

void op_i64_rem_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    if (b == 0) { crt->running = 0; return; }
    crt->sp[-1] = a % b;
    NEXT();
}

uint64_t i64_rem_u(void) { return (uint64_t)op_i64_rem_u; }

void op_i64_and(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a & b;
    NEXT();
}

uint64_t i64_and(void) { return (uint64_t)op_i64_and; }

void op_i64_or(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a | b;
    NEXT();
}

uint64_t i64_or(void) { return (uint64_t)op_i64_or; }

void op_i64_xor(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a ^ b;
    NEXT();
}

uint64_t i64_xor(void) { return (uint64_t)op_i64_xor; }

void op_i64_shl(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a << (b & 63);
    NEXT();
}

uint64_t i64_shl(void) { return (uint64_t)op_i64_shl; }

void op_i64_shr_s(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (uint64_t)(a >> (b & 63));
    NEXT();
}

uint64_t i64_shr_s(void) { return (uint64_t)op_i64_shr_s; }

void op_i64_shr_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = a >> (b & 63);
    NEXT();
}

uint64_t i64_shr_u(void) { return (uint64_t)op_i64_shr_u; }

void op_i64_rotl(CRuntime* crt) {
    uint64_t b = crt->sp[-1] & 63;
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a << b) | (a >> (64 - b));
    NEXT();
}

uint64_t i64_rotl(void) { return (uint64_t)op_i64_rotl; }

void op_i64_rotr(CRuntime* crt) {
    uint64_t b = crt->sp[-1] & 63;
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a >> b) | (a << (64 - b));
    NEXT();
}

uint64_t i64_rotr(void) { return (uint64_t)op_i64_rotr; }

// i64 comparison

void op_i64_eqz(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = (a == 0 ? 1 : 0);
    NEXT();
}

uint64_t i64_eqz(void) { return (uint64_t)op_i64_eqz; }

void op_i64_eq(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a == b ? 1 : 0);
    NEXT();
}

uint64_t i64_eq(void) { return (uint64_t)op_i64_eq; }

void op_i64_ne(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a != b ? 1 : 0);
    NEXT();
}

uint64_t i64_ne(void) { return (uint64_t)op_i64_ne; }

void op_i64_lt_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a < b ? 1 : 0);
    NEXT();
}

uint64_t i64_lt_s(void) { return (uint64_t)op_i64_lt_s; }

void op_i64_lt_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a < b ? 1 : 0);
    NEXT();
}

uint64_t i64_lt_u(void) { return (uint64_t)op_i64_lt_u; }

void op_i64_gt_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a > b ? 1 : 0);
    NEXT();
}

uint64_t i64_gt_s(void) { return (uint64_t)op_i64_gt_s; }

void op_i64_gt_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a > b ? 1 : 0);
    NEXT();
}

uint64_t i64_gt_u(void) { return (uint64_t)op_i64_gt_u; }

void op_i64_le_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}

uint64_t i64_le_s(void) { return (uint64_t)op_i64_le_s; }

void op_i64_le_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}

uint64_t i64_le_u(void) { return (uint64_t)op_i64_le_u; }

void op_i64_ge_s(CRuntime* crt) {
    int64_t b = (int64_t)crt->sp[-1];
    int64_t a = (int64_t)crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}

uint64_t i64_ge_s(void) { return (uint64_t)op_i64_ge_s; }

void op_i64_ge_u(CRuntime* crt) {
    uint64_t b = crt->sp[-1];
    uint64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}

uint64_t i64_ge_u(void) { return (uint64_t)op_i64_ge_u; }

// i64 unary

void op_i64_clz(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = (a == 0 ? 64 : __builtin_clzll(a));
    NEXT();
}

uint64_t i64_clz(void) { return (uint64_t)op_i64_clz; }

void op_i64_ctz(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = (a == 0 ? 64 : __builtin_ctzll(a));
    NEXT();
}

uint64_t i64_ctz(void) { return (uint64_t)op_i64_ctz; }

void op_i64_popcnt(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = __builtin_popcountll(a);
    NEXT();
}

uint64_t i64_popcnt(void) { return (uint64_t)op_i64_popcnt; }

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

// f32 arithmetic

void op_f32_add(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(a + b);
    NEXT();
}

uint64_t f32_add(void) { return (uint64_t)op_f32_add; }

void op_f32_sub(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(a - b);
    NEXT();
}

uint64_t f32_sub(void) { return (uint64_t)op_f32_sub; }

void op_f32_mul(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(a * b);
    NEXT();
}

uint64_t f32_mul(void) { return (uint64_t)op_f32_mul; }

void op_f32_div(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(a / b);
    NEXT();
}

uint64_t f32_div(void) { return (uint64_t)op_f32_div; }

void op_f32_min(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(fminf(a, b));
    NEXT();
}

uint64_t f32_min(void) { return (uint64_t)op_f32_min; }

void op_f32_max(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(fmaxf(a, b));
    NEXT();
}

uint64_t f32_max(void) { return (uint64_t)op_f32_max; }

void op_f32_copysign(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f32(copysignf(a, b));
    NEXT();
}

uint64_t f32_copysign(void) { return (uint64_t)op_f32_copysign; }

// f32 comparison

void op_f32_eq(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a == b ? 1 : 0);
    NEXT();
}

uint64_t f32_eq(void) { return (uint64_t)op_f32_eq; }

void op_f32_ne(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a != b ? 1 : 0);
    NEXT();
}

uint64_t f32_ne(void) { return (uint64_t)op_f32_ne; }

void op_f32_lt(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a < b ? 1 : 0);
    NEXT();
}

uint64_t f32_lt(void) { return (uint64_t)op_f32_lt; }

void op_f32_gt(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a > b ? 1 : 0);
    NEXT();
}

uint64_t f32_gt(void) { return (uint64_t)op_f32_gt; }

void op_f32_le(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}

uint64_t f32_le(void) { return (uint64_t)op_f32_le; }

void op_f32_ge(CRuntime* crt) {
    float b = as_f32(crt->sp[-1]);
    float a = as_f32(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}

uint64_t f32_ge(void) { return (uint64_t)op_f32_ge; }

// f32 unary

void op_f32_abs(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(fabsf(a));
    NEXT();
}

uint64_t f32_abs(void) { return (uint64_t)op_f32_abs; }

void op_f32_neg(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(-a);
    NEXT();
}

uint64_t f32_neg(void) { return (uint64_t)op_f32_neg; }

void op_f32_ceil(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(ceilf(a));
    NEXT();
}

uint64_t f32_ceil(void) { return (uint64_t)op_f32_ceil; }

void op_f32_floor(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(floorf(a));
    NEXT();
}

uint64_t f32_floor(void) { return (uint64_t)op_f32_floor; }

void op_f32_trunc(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(truncf(a));
    NEXT();
}

uint64_t f32_trunc(void) { return (uint64_t)op_f32_trunc; }

void op_f32_nearest(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(rintf(a));
    NEXT();
}

uint64_t f32_nearest(void) { return (uint64_t)op_f32_nearest; }

void op_f32_sqrt(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f32(sqrtf(a));
    NEXT();
}

uint64_t f32_sqrt(void) { return (uint64_t)op_f32_sqrt; }

// f64 arithmetic

void op_f64_add(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(a + b);
    NEXT();
}

uint64_t f64_add(void) { return (uint64_t)op_f64_add; }

void op_f64_sub(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(a - b);
    NEXT();
}

uint64_t f64_sub(void) { return (uint64_t)op_f64_sub; }

void op_f64_mul(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(a * b);
    NEXT();
}

uint64_t f64_mul(void) { return (uint64_t)op_f64_mul; }

void op_f64_div(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(a / b);
    NEXT();
}

uint64_t f64_div(void) { return (uint64_t)op_f64_div; }

void op_f64_min(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(fmin(a, b));
    NEXT();
}

uint64_t f64_min(void) { return (uint64_t)op_f64_min; }

void op_f64_max(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(fmax(a, b));
    NEXT();
}

uint64_t f64_max(void) { return (uint64_t)op_f64_max; }

void op_f64_copysign(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = from_f64(copysign(a, b));
    NEXT();
}

uint64_t f64_copysign(void) { return (uint64_t)op_f64_copysign; }

// f64 comparison

void op_f64_eq(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a == b ? 1 : 0);
    NEXT();
}

uint64_t f64_eq(void) { return (uint64_t)op_f64_eq; }

void op_f64_ne(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a != b ? 1 : 0);
    NEXT();
}

uint64_t f64_ne(void) { return (uint64_t)op_f64_ne; }

void op_f64_lt(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a < b ? 1 : 0);
    NEXT();
}

uint64_t f64_lt(void) { return (uint64_t)op_f64_lt; }

void op_f64_gt(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a > b ? 1 : 0);
    NEXT();
}

uint64_t f64_gt(void) { return (uint64_t)op_f64_gt; }

void op_f64_le(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a <= b ? 1 : 0);
    NEXT();
}

uint64_t f64_le(void) { return (uint64_t)op_f64_le; }

void op_f64_ge(CRuntime* crt) {
    double b = as_f64(crt->sp[-1]);
    double a = as_f64(crt->sp[-2]);
    crt->sp--;
    crt->sp[-1] = (a >= b ? 1 : 0);
    NEXT();
}

uint64_t f64_ge(void) { return (uint64_t)op_f64_ge; }

// f64 unary

void op_f64_abs(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(fabs(a));
    NEXT();
}

uint64_t f64_abs(void) { return (uint64_t)op_f64_abs; }

void op_f64_neg(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(-a);
    NEXT();
}

uint64_t f64_neg(void) { return (uint64_t)op_f64_neg; }

void op_f64_ceil(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(ceil(a));
    NEXT();
}

uint64_t f64_ceil(void) { return (uint64_t)op_f64_ceil; }

void op_f64_floor(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(floor(a));
    NEXT();
}

uint64_t f64_floor(void) { return (uint64_t)op_f64_floor; }

void op_f64_trunc(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(trunc(a));
    NEXT();
}

uint64_t f64_trunc(void) { return (uint64_t)op_f64_trunc; }

void op_f64_nearest(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(rint(a));
    NEXT();
}

uint64_t f64_nearest(void) { return (uint64_t)op_f64_nearest; }

void op_f64_sqrt(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f64(sqrt(a));
    NEXT();
}

uint64_t f64_sqrt(void) { return (uint64_t)op_f64_sqrt; }

// Conversions

void op_i32_wrap_i64(CRuntime* crt) {
    crt->sp[-1] = (uint32_t)crt->sp[-1];
    NEXT();
}

uint64_t i32_wrap_i64(void) { return (uint64_t)op_i32_wrap_i64; }

void op_i32_trunc_f32_s(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}

uint64_t i32_trunc_f32_s(void) { return (uint64_t)op_i32_trunc_f32_s; }

void op_i32_trunc_f32_u(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(uint32_t)a;
    NEXT();
}

uint64_t i32_trunc_f32_u(void) { return (uint64_t)op_i32_trunc_f32_u; }

void op_i32_trunc_f64_s(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}

uint64_t i32_trunc_f64_s(void) { return (uint64_t)op_i32_trunc_f64_s; }

void op_i32_trunc_f64_u(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(uint32_t)a;
    NEXT();
}

uint64_t i32_trunc_f64_u(void) { return (uint64_t)op_i32_trunc_f64_u; }

void op_i64_extend_i32_s(CRuntime* crt) {
    int32_t a = (int32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_extend_i32_s(void) { return (uint64_t)op_i64_extend_i32_s; }

void op_i64_extend_i32_u(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)a;
    NEXT();
}

uint64_t i64_extend_i32_u(void) { return (uint64_t)op_i64_extend_i32_u; }

void op_i64_trunc_f32_s(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_trunc_f32_s(void) { return (uint64_t)op_i64_trunc_f32_s; }

void op_i64_trunc_f32_u(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)a;
    NEXT();
}

uint64_t i64_trunc_f32_u(void) { return (uint64_t)op_i64_trunc_f32_u; }

void op_i64_trunc_f64_s(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_trunc_f64_s(void) { return (uint64_t)op_i64_trunc_f64_s; }

void op_i64_trunc_f64_u(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = (uint64_t)a;
    NEXT();
}

uint64_t i64_trunc_f64_u(void) { return (uint64_t)op_i64_trunc_f64_u; }

void op_f32_convert_i32_s(CRuntime* crt) {
    int32_t a = (int32_t)crt->sp[-1];
    crt->sp[-1] = from_f32((float)a);
    NEXT();
}

uint64_t f32_convert_i32_s(void) { return (uint64_t)op_f32_convert_i32_s; }

void op_f32_convert_i32_u(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = from_f32((float)a);
    NEXT();
}

uint64_t f32_convert_i32_u(void) { return (uint64_t)op_f32_convert_i32_u; }

void op_f32_convert_i64_s(CRuntime* crt) {
    int64_t a = (int64_t)crt->sp[-1];
    crt->sp[-1] = from_f32((float)a);
    NEXT();
}

uint64_t f32_convert_i64_s(void) { return (uint64_t)op_f32_convert_i64_s; }

void op_f32_convert_i64_u(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = from_f32((float)a);
    NEXT();
}

uint64_t f32_convert_i64_u(void) { return (uint64_t)op_f32_convert_i64_u; }

void op_f32_demote_f64(CRuntime* crt) {
    double a = as_f64(crt->sp[-1]);
    crt->sp[-1] = from_f32((float)a);
    NEXT();
}

uint64_t f32_demote_f64(void) { return (uint64_t)op_f32_demote_f64; }

void op_f64_convert_i32_s(CRuntime* crt) {
    int32_t a = (int32_t)crt->sp[-1];
    crt->sp[-1] = from_f64((double)a);
    NEXT();
}

uint64_t f64_convert_i32_s(void) { return (uint64_t)op_f64_convert_i32_s; }

void op_f64_convert_i32_u(CRuntime* crt) {
    uint32_t a = (uint32_t)crt->sp[-1];
    crt->sp[-1] = from_f64((double)a);
    NEXT();
}

uint64_t f64_convert_i32_u(void) { return (uint64_t)op_f64_convert_i32_u; }

void op_f64_convert_i64_s(CRuntime* crt) {
    int64_t a = (int64_t)crt->sp[-1];
    crt->sp[-1] = from_f64((double)a);
    NEXT();
}

uint64_t f64_convert_i64_s(void) { return (uint64_t)op_f64_convert_i64_s; }

void op_f64_convert_i64_u(CRuntime* crt) {
    uint64_t a = crt->sp[-1];
    crt->sp[-1] = from_f64((double)a);
    NEXT();
}

uint64_t f64_convert_i64_u(void) { return (uint64_t)op_f64_convert_i64_u; }

void op_f64_promote_f32(CRuntime* crt) {
    float a = as_f32(crt->sp[-1]);
    crt->sp[-1] = from_f64((double)a);
    NEXT();
}

uint64_t f64_promote_f32(void) { return (uint64_t)op_f64_promote_f32; }

void op_i32_reinterpret_f32(CRuntime* crt) {
    // Already stored as bits, just mask to 32 bits
    crt->sp[-1] = crt->sp[-1] & 0xFFFFFFFF;
    NEXT();
}

uint64_t i32_reinterpret_f32(void) { return (uint64_t)op_i32_reinterpret_f32; }

void op_i64_reinterpret_f64(CRuntime* crt) {
    // Already stored as bits, nothing to do
    NEXT();
}

uint64_t i64_reinterpret_f64(void) { return (uint64_t)op_i64_reinterpret_f64; }

void op_f32_reinterpret_i32(CRuntime* crt) {
    // Already stored as bits, nothing to do
    NEXT();
}

uint64_t f32_reinterpret_i32(void) { return (uint64_t)op_f32_reinterpret_i32; }

void op_f64_reinterpret_i64(CRuntime* crt) {
    // Already stored as bits, nothing to do
    NEXT();
}

uint64_t f64_reinterpret_i64(void) { return (uint64_t)op_f64_reinterpret_i64; }

// Sign extension

void op_i32_extend8_s(CRuntime* crt) {
    int8_t a = (int8_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}

uint64_t i32_extend8_s(void) { return (uint64_t)op_i32_extend8_s; }

void op_i32_extend16_s(CRuntime* crt) {
    int16_t a = (int16_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(uint32_t)(int32_t)a;
    NEXT();
}

uint64_t i32_extend16_s(void) { return (uint64_t)op_i32_extend16_s; }

void op_i64_extend8_s(CRuntime* crt) {
    int8_t a = (int8_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_extend8_s(void) { return (uint64_t)op_i64_extend8_s; }

void op_i64_extend16_s(CRuntime* crt) {
    int16_t a = (int16_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_extend16_s(void) { return (uint64_t)op_i64_extend16_s; }

void op_i64_extend32_s(CRuntime* crt) {
    int32_t a = (int32_t)crt->sp[-1];
    crt->sp[-1] = (uint64_t)(int64_t)a;
    NEXT();
}

uint64_t i64_extend32_s(void) { return (uint64_t)op_i64_extend32_s; }

// Stack operations

void op_wasm_drop(CRuntime* crt) {
    crt->sp--;
    NEXT();
}

uint64_t wasm_drop(void) { return (uint64_t)op_wasm_drop; }

void op_wasm_select(CRuntime* crt) {
    uint32_t c = (uint32_t)crt->sp[-1];
    uint64_t b = crt->sp[-2];
    uint64_t a = crt->sp[-3];
    crt->sp -= 2;
    crt->sp[-1] = c ? a : b;
    NEXT();
}

uint64_t wasm_select(void) { return (uint64_t)op_wasm_select; }
