#include <stdint.h>
#include <stdlib.h>
#include <string.h>
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
#define TRAP_OUT_OF_BOUNDS_TABLE        6  // "undefined element" - index out of bounds (call_indirect)
#define TRAP_INDIRECT_CALL_TYPE_MISMATCH 7
#define TRAP_NULL_FUNCTION_REFERENCE    8
#define TRAP_STACK_OVERFLOW             9
#define TRAP_UNINITIALIZED_ELEMENT      10 // "uninitialized element" - null entry in table
#define TRAP_TABLE_BOUNDS_ACCESS        11 // "out of bounds table access" - for bulk table ops
#define TRAP_NULL_REFERENCE             12 // "null reference" - for ref.as_non_null

// Memory bounds check helper - use 64-bit arithmetic to avoid overflow
#define CHECK_MEMORY(addr, size) \
    if ((uint64_t)(addr) + (uint64_t)(size) > (uint64_t)g_memory_size) { \
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY); \
    }

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
// Use __has_attribute to check if musttail is supported (works on Clang and GCC 13+)
#ifdef __has_attribute
#  if __has_attribute(musttail)
#    define MUSTTAIL __attribute__((musttail))
#  else
#    define MUSTTAIL
#  endif
#else
#  define MUSTTAIL
#endif

static int g_validate_code = 0;

// NEXT: fetch next opcode and tail-call with updated pc
#define NEXT() do { \
    if (g_validate_code && (uintptr_t)*pc < 4096) { \
        fprintf(stderr, "wasm5: invalid opcode pointer %llu at pc=%p index=%lld\\n", (unsigned long long)*pc, (void*)pc, (long long)(pc - crt->code)); \
        return TRAP_UNREACHABLE; \
    } \
    OpFn next = (OpFn)*pc++; \
    MUSTTAIL return next(crt, pc, sp, fp); \
} while(0)

#define TRAP(code) return (code)

// Stack size: 64K slots = 512KB
#define STACK_SIZE 65536

// Memory pages info (shared across calls within same instance)
static int* g_memory_pages = NULL;
static int g_memory_size = 0;
static int g_memory_max_size = 0;  // Maximum memory size (pre-allocated)

// Multiple tables support (for call_indirect and table ops)
static int* g_tables_flat = NULL;      // All tables concatenated
static int* g_table_offsets = NULL;    // Offset of each table in g_tables_flat
static int* g_table_sizes = NULL;      // Current size of each table
static int* g_table_max_sizes = NULL;  // Maximum size (capacity) of each table for table.grow
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

// Import function metadata (for op_call_import)
static int* g_import_num_params = NULL;    // Number of params for each imported function
static int* g_import_num_results = NULL;   // Number of results for each imported function
static int* g_import_handler_ids = NULL;   // Host handler id for each imported function
static uint8_t* g_output_buffer = NULL;    // Output buffer for spectest handlers
static int* g_output_length = NULL;        // Current output length
static int g_output_capacity = 0;          // Output buffer capacity
// Cross-module resolved imports (for call_indirect with imported functions)
static int64_t* g_import_context_ptrs = NULL;  // Target context pointer for each import (-1 if not resolved)
static int* g_import_target_func_idxs = NULL;  // Function index in target module for each import

// Data segments for bulk memory operations (memory.init, data.drop)
static uint8_t* g_data_segments_flat = NULL;   // All data segments concatenated
static int* g_data_segment_offsets = NULL;     // Offset of each segment in data_segments_flat
static int* g_data_segment_sizes = NULL;       // Size of each segment (mutable for data.drop)
static int g_num_data_segments = 0;

// Element segments for bulk table operations (table.init, elem.drop)
static int* g_elem_segments_flat = NULL;       // All element segments concatenated (func indices, -1 for null)
static int* g_elem_segment_offsets = NULL;     // Offset of each segment in elem_segments_flat
static int* g_elem_segment_sizes = NULL;       // Size of each segment (mutable for elem.drop)
static int* g_elem_segment_dropped = NULL;     // Whether each segment has been dropped
static int g_num_elem_segments = 0;
static int g_num_external_funcrefs = 0;

// Host import handler ids (kept in sync with runtime.mbt)
#define HOST_IMPORT_SPECTEST_PRINT 0
#define HOST_IMPORT_SPECTEST_PRINT_I32 1
#define HOST_IMPORT_SPECTEST_PRINT_I64 2
#define HOST_IMPORT_SPECTEST_PRINT_F32 3
#define HOST_IMPORT_SPECTEST_PRINT_F64 4
#define HOST_IMPORT_SPECTEST_PRINT_I32_F32 5
#define HOST_IMPORT_SPECTEST_PRINT_F64_F64 6
#define HOST_IMPORT_SPECTEST_PRINT_CHAR 7

// Stack base for result extraction after execution
static uint64_t* g_stack_base = NULL;

// ============================================================================
// Cross-module call support (context switching)
// ============================================================================

// CRuntimeContext captures all global state for save/restore during cross-module calls
typedef struct CRuntimeContext {
    uint64_t* code;
    uint64_t* globals;
    uint8_t* memory;
    int memory_size;
    int memory_max_size;
    int* memory_pages;
    int* tables_flat;
    int* table_offsets;
    int* table_sizes;
    int* table_max_sizes;
    int num_tables;
    int* func_entries;
    int* func_num_locals;
    int num_funcs;
    int num_imported_funcs;
    int* func_type_idxs;
    int* type_sig_hash1;
    int* type_sig_hash2;
    int num_types;
    int* import_num_params;
    int* import_num_results;
    int* import_handler_ids;
    uint8_t* output_buffer;
    int* output_length;
    int output_capacity;
    int64_t* import_context_ptrs;
    int* import_target_func_idxs;
    uint8_t* data_segments_flat;
    int* data_segment_offsets;
    int* data_segment_sizes;
    int num_data_segments;
    int* elem_segments_flat;
    int* elem_segment_offsets;
    int* elem_segment_sizes;
    int* elem_segment_dropped;
    int num_elem_segments;
    int num_external_funcrefs;
} CRuntimeContext;

// Maximum nesting depth for cross-module calls
#define MAX_CONTEXT_DEPTH 16
static CRuntimeContext g_saved_contexts[MAX_CONTEXT_DEPTH];
static int g_context_depth = 0;

// Save current global state to a context structure
static void save_context(CRuntimeContext* ctx, CRuntime* crt) {
    ctx->code = crt->code;
    ctx->globals = crt->globals;
    ctx->memory = crt->mem;
    ctx->memory_size = g_memory_size;
    ctx->memory_max_size = g_memory_max_size;
    ctx->memory_pages = g_memory_pages;
    ctx->tables_flat = g_tables_flat;
    ctx->table_offsets = g_table_offsets;
    ctx->table_sizes = g_table_sizes;
    ctx->table_max_sizes = g_table_max_sizes;
    ctx->num_tables = g_num_tables;
    ctx->func_entries = g_func_entries;
    ctx->func_num_locals = g_func_num_locals;
    ctx->num_funcs = g_num_funcs;
    ctx->num_imported_funcs = g_num_imported_funcs;
    ctx->func_type_idxs = g_func_type_idxs;
    ctx->type_sig_hash1 = g_type_sig_hash1;
    ctx->type_sig_hash2 = g_type_sig_hash2;
    ctx->num_types = g_num_types;
    ctx->import_num_params = g_import_num_params;
    ctx->import_num_results = g_import_num_results;
    ctx->import_handler_ids = g_import_handler_ids;
    ctx->output_buffer = g_output_buffer;
    ctx->output_length = g_output_length;
    ctx->output_capacity = g_output_capacity;
    ctx->import_context_ptrs = g_import_context_ptrs;
    ctx->import_target_func_idxs = g_import_target_func_idxs;
    ctx->data_segments_flat = g_data_segments_flat;
    ctx->data_segment_offsets = g_data_segment_offsets;
    ctx->data_segment_sizes = g_data_segment_sizes;
    ctx->num_data_segments = g_num_data_segments;
    ctx->elem_segments_flat = g_elem_segments_flat;
    ctx->elem_segment_offsets = g_elem_segment_offsets;
    ctx->elem_segment_sizes = g_elem_segment_sizes;
    ctx->elem_segment_dropped = g_elem_segment_dropped;
    ctx->num_elem_segments = g_num_elem_segments;
    ctx->num_external_funcrefs = g_num_external_funcrefs;
}

// Load global state from a context structure
static void load_context(const CRuntimeContext* ctx, CRuntime* crt) {
    crt->code = ctx->code;
    crt->globals = ctx->globals;
    crt->mem = ctx->memory;
    g_memory_size = ctx->memory_size;
    g_memory_max_size = ctx->memory_max_size;
    g_memory_pages = ctx->memory_pages;
    g_tables_flat = ctx->tables_flat;
    g_table_offsets = ctx->table_offsets;
    g_table_sizes = ctx->table_sizes;
    g_table_max_sizes = ctx->table_max_sizes;
    g_num_tables = ctx->num_tables;
    g_func_entries = ctx->func_entries;
    g_func_num_locals = ctx->func_num_locals;
    g_num_funcs = ctx->num_funcs;
    g_num_imported_funcs = ctx->num_imported_funcs;
    g_func_type_idxs = ctx->func_type_idxs;
    g_type_sig_hash1 = ctx->type_sig_hash1;
    g_type_sig_hash2 = ctx->type_sig_hash2;
    g_num_types = ctx->num_types;
    g_import_num_params = ctx->import_num_params;
    g_import_num_results = ctx->import_num_results;
    g_import_handler_ids = ctx->import_handler_ids;
    g_output_buffer = ctx->output_buffer;
    g_output_length = ctx->output_length;
    g_output_capacity = ctx->output_capacity;
    g_import_context_ptrs = ctx->import_context_ptrs;
    g_import_target_func_idxs = ctx->import_target_func_idxs;
    g_data_segments_flat = ctx->data_segments_flat;
    g_data_segment_offsets = ctx->data_segment_offsets;
    g_data_segment_sizes = ctx->data_segment_sizes;
    g_num_data_segments = ctx->num_data_segments;
    g_elem_segments_flat = ctx->elem_segments_flat;
    g_elem_segment_offsets = ctx->elem_segment_offsets;
    g_elem_segment_sizes = ctx->elem_segment_sizes;
    g_elem_segment_dropped = ctx->elem_segment_dropped;
    g_num_elem_segments = ctx->num_elem_segments;
    g_num_external_funcrefs = ctx->num_external_funcrefs;
}

// Create a new context from module data (called from MoonBit)
// Returns pointer to heap-allocated context
CRuntimeContext* create_runtime_context(
    uint64_t* code, uint64_t* globals, uint8_t* memory, int memory_size,
    int memory_max_size, int* memory_pages, int* tables_flat, int* table_offsets, int* table_sizes,
    int* table_max_sizes, int num_tables, int* func_entries, int* func_num_locals,
    int num_funcs, int num_imported_funcs, int* func_type_idxs,
    int* type_sig_hash1, int* type_sig_hash2, int num_types,
    int* import_num_params, int* import_num_results, int* import_handler_ids,
    uint8_t* output_buffer, int* output_length, int output_capacity,
    int64_t* import_context_ptrs, int* import_target_func_idxs,
    uint8_t* data_segments_flat, int* data_segment_offsets, int* data_segment_sizes, int num_data_segments,
    int* elem_segments_flat, int* elem_segment_offsets, int* elem_segment_sizes,
    int* elem_segment_dropped, int num_elem_segments, int num_external_funcrefs
) {
    CRuntimeContext* ctx = (CRuntimeContext*)malloc(sizeof(CRuntimeContext));
    if (!ctx) return NULL;

    ctx->code = code;
    ctx->globals = globals;
    ctx->memory = memory;
    ctx->memory_size = memory_size;
    ctx->memory_max_size = memory_max_size;
    ctx->memory_pages = memory_pages;
    ctx->tables_flat = tables_flat;
    ctx->table_offsets = table_offsets;
    ctx->table_sizes = table_sizes;
    ctx->table_max_sizes = table_max_sizes;
    ctx->num_tables = num_tables;
    ctx->func_entries = func_entries;
    ctx->func_num_locals = func_num_locals;
    ctx->num_funcs = num_funcs;
    ctx->num_imported_funcs = num_imported_funcs;
    ctx->func_type_idxs = func_type_idxs;
    ctx->type_sig_hash1 = type_sig_hash1;
    ctx->type_sig_hash2 = type_sig_hash2;
    ctx->num_types = num_types;
    ctx->import_num_params = import_num_params;
    ctx->import_num_results = import_num_results;
    ctx->import_handler_ids = import_handler_ids;
    ctx->output_buffer = output_buffer;
    ctx->output_length = output_length;
    ctx->output_capacity = output_capacity;
    ctx->import_context_ptrs = import_context_ptrs;
    ctx->import_target_func_idxs = import_target_func_idxs;
    ctx->data_segments_flat = data_segments_flat;
    ctx->data_segment_offsets = data_segment_offsets;
    ctx->data_segment_sizes = data_segment_sizes;
    ctx->num_data_segments = num_data_segments;
    ctx->elem_segments_flat = elem_segments_flat;
    ctx->elem_segment_offsets = elem_segment_offsets;
    ctx->elem_segment_sizes = elem_segment_sizes;
    ctx->elem_segment_dropped = elem_segment_dropped;
    ctx->num_elem_segments = num_elem_segments;
    ctx->num_external_funcrefs = num_external_funcrefs;

    return ctx;
}

// Free a context (called from MoonBit)
void free_runtime_context(CRuntimeContext* ctx) {
    free(ctx);
}

// ============================================================================

// Internal execution helper - starts the tail-call chain
static int run(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    if (g_validate_code && (uintptr_t)*pc < 4096) {
        fprintf(stderr, "wasm5: invalid opcode pointer %llu at pc=%p index=%lld\n", (unsigned long long)*pc, (void*)pc, (long long)(pc - crt->code));
        return TRAP_UNREACHABLE;
    }
    OpFn first = (OpFn)*pc++;
    return first(crt, pc, sp, fp);
}

static void output_append(const char* data, int len) {
    if (!g_output_buffer || !g_output_length || g_output_capacity <= 0 || len <= 0) {
        return;
    }
    int out_len = *g_output_length;
    if (out_len < 0) {
        out_len = 0;
    }
    if (out_len >= g_output_capacity) {
        return;
    }
    int remaining = g_output_capacity - out_len;
    if (len > remaining) {
        len = remaining;
    }
    memcpy(g_output_buffer + out_len, data, (size_t)len);
    *g_output_length = out_len + len;
}

static float f32_from_u64(uint64_t v) {
    uint32_t u = (uint32_t)v;
    float f = 0.0f;
    memcpy(&f, &u, sizeof(f));
    return f;
}

static double f64_from_u64(uint64_t v) {
    double d = 0.0;
    memcpy(&d, &v, sizeof(d));
    return d;
}

// Host import handlers (spectest formatting)
static void call_host_import(int handler_id, uint64_t* args, int num_params,
                             uint64_t* results, int num_results) {
    char buf[128];
    int n = -1;
    switch (handler_id) {
        case HOST_IMPORT_SPECTEST_PRINT:
            break;
        case HOST_IMPORT_SPECTEST_PRINT_I32: {
            int32_t val = (int32_t)(uint32_t)(num_params > 0 ? args[0] : 0);
            n = snprintf(buf, sizeof(buf), "%d : i32", val);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_I64: {
            int64_t val = (int64_t)(num_params > 0 ? args[0] : 0);
            n = snprintf(buf, sizeof(buf), "%lld : i64", (long long)val);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_F32: {
            float f = f32_from_u64(num_params > 0 ? args[0] : 0);
            n = snprintf(buf, sizeof(buf), "%.9g : f32", (double)f);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_F64: {
            double d = f64_from_u64(num_params > 0 ? args[0] : 0);
            n = snprintf(buf, sizeof(buf), "%.17g : f64", d);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_I32_F32: {
            int32_t val = (int32_t)(uint32_t)(num_params > 0 ? args[0] : 0);
            float f = f32_from_u64(num_params > 1 ? args[1] : 0);
            n = snprintf(buf, sizeof(buf), "%d : i32, %.9g : f32", val, (double)f);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_F64_F64: {
            double d0 = f64_from_u64(num_params > 0 ? args[0] : 0);
            double d1 = f64_from_u64(num_params > 1 ? args[1] : 0);
            n = snprintf(buf, sizeof(buf), "%.17g : f64, %.17g : f64", d0, d1);
            break;
        }
        case HOST_IMPORT_SPECTEST_PRINT_CHAR: {
            char c = (char)(uint8_t)(num_params > 0 ? args[0] : 0);
            output_append(&c, 1);
            output_append("\n", 1);
            break;
        }
        default:
            break;
    }
    if (n > 0) {
        if (n >= (int)sizeof(buf)) {
            n = (int)sizeof(buf) - 1;
        }
        output_append(buf, n);
        output_append("\n", 1);
    }
    for (int i = 0; i < num_results; i++) {
        results[i] = 0;
    }
}

// Execute threaded code starting at entry point
// Returns trap code (0 = success), stores results in result_out[0..num_results-1]
int execute(uint64_t* code, int entry, int num_locals, uint64_t* args, int num_args,
            uint64_t* result_out, int num_results, uint64_t* globals, uint8_t* mem, int mem_size,
            int mem_max_size, int* memory_pages, int* tables_flat, int* table_offsets, int* table_sizes, int* table_max_sizes, int num_tables,
            int* func_entries, int* func_num_locals, int num_funcs, int num_imported_funcs,
            int* func_type_idxs, int* type_sig_hash1, int* type_sig_hash2, int num_types,
            int* import_num_params, int* import_num_results, int* import_handler_ids,
            uint8_t* output_buffer, int* output_length, int output_capacity,
            int64_t* import_context_ptrs, int* import_target_func_idxs,
            uint8_t* data_segments_flat, int* data_segment_offsets, int* data_segment_sizes, int num_data_segments,
            int* elem_segments_flat, int* elem_segment_offsets, int* elem_segment_sizes, int* elem_segment_dropped, int num_elem_segments,
            int num_external_funcrefs) {
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
    g_memory_max_size = mem_max_size;

    // Store table data for call_indirect and table ops
    g_tables_flat = tables_flat;
    g_table_offsets = table_offsets;
    g_table_sizes = table_sizes;
    g_table_max_sizes = table_max_sizes;
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

    // Store import function metadata for op_call_import and call_indirect
    g_import_num_params = import_num_params;
    g_import_num_results = import_num_results;
    g_import_handler_ids = import_handler_ids;
    g_output_buffer = output_buffer;
    g_output_length = output_length;
    g_output_capacity = output_capacity;
    g_import_context_ptrs = import_context_ptrs;
    g_import_target_func_idxs = import_target_func_idxs;

    // Store data segment info for bulk memory operations
    g_data_segments_flat = data_segments_flat;
    g_data_segment_offsets = data_segment_offsets;
    g_data_segment_sizes = data_segment_sizes;
    g_num_data_segments = num_data_segments;

    // Store element segment info for bulk table operations
    g_elem_segments_flat = elem_segments_flat;
    g_elem_segment_offsets = elem_segment_offsets;
    g_elem_segment_sizes = elem_segment_sizes;
    g_elem_segment_dropped = elem_segment_dropped;
    g_num_elem_segments = num_elem_segments;
    g_num_external_funcrefs = num_external_funcrefs;

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

    g_validate_code = (getenv("WASM5_VALIDATE_CODE") != NULL);
    if (g_validate_code) {
        fprintf(stderr, "wasm5: entry=%d pc=%p opcode=%llu\n", entry, (void*)pc, (unsigned long long)*pc);
    }

    // Start execution
    int trap = run(&crt, pc, sp, fp);
    g_validate_code = 0;

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
    g_table_max_sizes = NULL;
    g_num_tables = 0;
    g_func_entries = NULL;
    g_func_num_locals = NULL;
    g_num_funcs = 0;
    g_num_imported_funcs = 0;
    g_func_type_idxs = NULL;
    g_type_sig_hash1 = NULL;
    g_type_sig_hash2 = NULL;
    g_num_types = 0;
    g_import_num_params = NULL;
    g_import_num_results = NULL;
    g_import_handler_ids = NULL;
    g_output_buffer = NULL;
    g_output_length = NULL;
    g_output_capacity = 0;
    g_import_context_ptrs = NULL;
    g_import_target_func_idxs = NULL;
    g_data_segments_flat = NULL;
    g_data_segment_offsets = NULL;
    g_data_segment_sizes = NULL;
    g_num_data_segments = 0;
    g_elem_segments_flat = NULL;
    g_elem_segment_offsets = NULL;
    g_elem_segment_sizes = NULL;
    g_elem_segment_dropped = NULL;
    g_num_elem_segments = 0;
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

// Call an imported function (spectest handlers)
// Immediates: import_idx, frame_offset
// The import_idx identifies which imported function to call
// For spectest: print functions are no-ops, they just consume args and return nothing
int op_call_import(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int import_idx = (int)*pc++;
    int frame_offset = (int)*pc++;

    // Get import function signature
    int num_params = 0;
    int num_results = 0;
    if (g_import_num_params && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        num_params = g_import_num_params[import_idx];
        num_results = g_import_num_results[import_idx];
    }

    // Resolved import: cross-module call
    if (g_import_context_ptrs && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        int64_t target_ctx_ptr = g_import_context_ptrs[import_idx];
        if (target_ctx_ptr >= 0) {
            CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
            int target_func_idx = g_import_target_func_idxs[import_idx];

            // Save caller pc for return
            uint64_t* caller_pc = pc;

            if (g_context_depth >= MAX_CONTEXT_DEPTH) {
                TRAP(TRAP_STACK_OVERFLOW);
            }

            save_context(&g_saved_contexts[g_context_depth++], crt);
            load_context(target_ctx, crt);

            int local_idx = target_func_idx - target_ctx->num_imported_funcs;
            if (local_idx < 0 || local_idx >= target_ctx->num_funcs) {
                load_context(&g_saved_contexts[--g_context_depth], crt);
                TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
            }

            int callee_pc = g_func_entries[local_idx];
            int callee_num_locals = g_func_num_locals[local_idx];

            // Args are located at fp + frame_offset
            uint64_t* args_ptr = fp + frame_offset;
            uint64_t* new_fp = args_ptr;
            uint64_t* callee_sp = args_ptr + num_params;
            int extra_locals = callee_num_locals - num_params;

            for (int i = 0; i < extra_locals; i++) {
                *callee_sp++ = 0;
            }

            int trap = run(crt, crt->code + callee_pc, callee_sp, new_fp);

            uint64_t results[16];
            int actual_results = num_results < 16 ? num_results : 16;
            for (int i = 0; i < actual_results; i++) {
                results[i] = new_fp[i];
            }

            load_context(&g_saved_contexts[--g_context_depth], crt);

            if (trap != TRAP_NONE) {
                return trap;
            }

            uint64_t* result_dst = fp + frame_offset;
            for (int i = 0; i < actual_results; i++) {
                result_dst[i] = results[i];
            }
            sp = result_dst + actual_results;
            pc = caller_pc;
            NEXT();
        }
    }

    int handler_id = -1;
    if (g_import_handler_ids && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        handler_id = g_import_handler_ids[import_idx];
    }
    if (handler_id >= 0) {
        uint64_t* args_ptr = fp + frame_offset;
        uint64_t results[16];
        int actual_results = num_results < 16 ? num_results : 16;
        call_host_import(handler_id, args_ptr, num_params, results, actual_results);
        uint64_t* result_dst = fp + frame_offset;
        for (int i = 0; i < actual_results; i++) {
            result_dst[i] = results[i];
        }
        sp = result_dst + actual_results;
        NEXT();
    }

    // Unresolved import (spectest) - consume args and push dummy results
    sp = fp + frame_offset;
    for (int i = 0; i < num_results; i++) {
        *sp++ = 0;
    }
    NEXT();
}
DEFINE_OP(call_import)

// Tail-call a local function
// Immediates: callee_pc, num_params, num_locals
// Stack: [..., args...] -> (reuse current frame)
int op_return_call(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int callee_pc = (int)*pc++;
    int num_params = (int)*pc++;
    int num_locals = (int)*pc++;
    (void)num_locals;

    uint64_t* args_start = sp - num_params;
    if (num_params > 0 && args_start > fp) {
        for (int i = 0; i < num_params; i++) {
            fp[i] = args_start[i];
        }
    }

    sp = fp + num_params;
    pc = crt->code + callee_pc;
    NEXT();
}
DEFINE_OP(return_call)

// Tail-call an imported function
// Immediate: import_idx
int op_return_call_import(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int import_idx = (int)*pc++;

    int num_params = 0;
    int num_results = 0;
    if (g_import_num_params && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        num_params = g_import_num_params[import_idx];
        num_results = g_import_num_results[import_idx];
    }

    if (g_import_context_ptrs && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        int64_t target_ctx_ptr = g_import_context_ptrs[import_idx];
        if (target_ctx_ptr >= 0) {
            CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
            int target_func_idx = g_import_target_func_idxs[import_idx];

            if (g_context_depth >= MAX_CONTEXT_DEPTH) {
                TRAP(TRAP_STACK_OVERFLOW);
            }

            save_context(&g_saved_contexts[g_context_depth++], crt);
            load_context(target_ctx, crt);

            int local_idx = target_func_idx - target_ctx->num_imported_funcs;
            if (local_idx < 0 || local_idx >= target_ctx->num_funcs) {
                load_context(&g_saved_contexts[--g_context_depth], crt);
                TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
            }

            int callee_pc = g_func_entries[local_idx];
            int callee_num_locals = g_func_num_locals[local_idx];

            uint64_t* args_ptr = sp - num_params;
            uint64_t* new_fp = args_ptr;
            uint64_t* callee_sp = args_ptr + num_params;
            int extra_locals = callee_num_locals - num_params;

            for (int i = 0; i < extra_locals; i++) {
                *callee_sp++ = 0;
            }

            int trap = run(crt, crt->code + callee_pc, callee_sp, new_fp);

            uint64_t results[16];
            int actual_results = num_results < 16 ? num_results : 16;
            for (int i = 0; i < actual_results; i++) {
                results[i] = new_fp[i];
            }

            load_context(&g_saved_contexts[--g_context_depth], crt);

            if (trap != TRAP_NONE) {
                return trap;
            }

            for (int i = 0; i < actual_results; i++) {
                fp[i] = results[i];
            }
            return TRAP_NONE;
        }
    }

    int handler_id = -1;
    if (g_import_handler_ids && import_idx >= 0 && import_idx < g_num_imported_funcs) {
        handler_id = g_import_handler_ids[import_idx];
    }
    if (handler_id >= 0) {
        uint64_t* args_ptr = sp - num_params;
        uint64_t results[16];
        int actual_results = num_results < 16 ? num_results : 16;
        call_host_import(handler_id, args_ptr, num_params, results, actual_results);
        for (int i = 0; i < actual_results; i++) {
            fp[i] = results[i];
        }
        return TRAP_NONE;
    }

    // Unresolved import (spectest) - push dummy results to fp
    for (int i = 0; i < num_results; i++) {
        fp[i] = 0;
    }
    return TRAP_NONE;
}
DEFINE_OP(return_call_import)

// Tail-call a function via table
// Immediates: type_idx, table_idx
// Stack: [..., args..., elem_idx] -> (reuse current frame)
int op_return_call_indirect(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int expected_type_idx = (int)*pc++;
    int table_idx = (int)*pc++;

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

    int external_base = g_num_imported_funcs + g_num_funcs;
    if (g_num_external_funcrefs > 0 && func_idx >= external_base) {
        int ext_idx = func_idx - external_base;
        if (ext_idx < 0 || ext_idx >= g_num_external_funcrefs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int import_idx = g_num_imported_funcs + ext_idx;
        int num_params = g_import_num_params ? g_import_num_params[import_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[import_idx] : 0;

        if (expected_type_idx >= 0 && expected_type_idx < g_num_types) {
            int expected_sig2 = g_type_sig_hash2[expected_type_idx];
            int expected_params = expected_sig2 >> 16;
            int expected_results = expected_sig2 & 0xFFFF;
            if (expected_params != num_params || expected_results != num_results) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }

        if (!g_import_context_ptrs || !g_import_target_func_idxs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int64_t target_ctx_ptr = g_import_context_ptrs[import_idx];
        if (target_ctx_ptr < 0) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
        int target_func_idx = g_import_target_func_idxs[import_idx];

        if (g_context_depth >= MAX_CONTEXT_DEPTH) {
            TRAP(TRAP_STACK_OVERFLOW);
        }

        save_context(&g_saved_contexts[g_context_depth++], crt);
        load_context(target_ctx, crt);

        int local_idx = target_func_idx - target_ctx->num_imported_funcs;
        if (local_idx < 0 || local_idx >= target_ctx->num_funcs) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
        }

        int callee_pc = g_func_entries[local_idx];
        int callee_num_locals = g_func_num_locals[local_idx];

        uint64_t* args_ptr = sp - num_params;
        uint64_t* new_fp = args_ptr;
        uint64_t* callee_sp = args_ptr + num_params;
        int extra_locals = callee_num_locals - num_params;

        for (int i = 0; i < extra_locals; i++) {
            *callee_sp++ = 0;
        }

        int trap = run(crt, crt->code + callee_pc, callee_sp, new_fp);

        uint64_t results[16];
        int actual_results = num_results < 16 ? num_results : 16;
        for (int i = 0; i < actual_results; i++) {
            results[i] = new_fp[i];
        }

        load_context(&g_saved_contexts[--g_context_depth], crt);

        if (trap != TRAP_NONE) {
            return trap;
        }

        for (int i = 0; i < actual_results; i++) {
            fp[i] = results[i];
        }
        return TRAP_NONE;
    }

    // Type check: compare expected type with actual function type using signature hashes
    if (func_idx < g_num_imported_funcs + g_num_funcs) {
        int actual_type_idx = g_func_type_idxs[func_idx];
        if (expected_type_idx >= 0 && expected_type_idx < g_num_types &&
            actual_type_idx >= 0 && actual_type_idx < g_num_types) {
            int expected_hash1 = g_type_sig_hash1[expected_type_idx];
            int expected_hash2 = g_type_sig_hash2[expected_type_idx];
            int actual_hash1 = g_type_sig_hash1[actual_type_idx];
            int actual_hash2 = g_type_sig_hash2[actual_type_idx];
            if (expected_hash1 != actual_hash1 || expected_hash2 != actual_hash2) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }
    }

    // Imported function
    if (func_idx < g_num_imported_funcs) {
        int num_params = g_import_num_params ? g_import_num_params[func_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[func_idx] : 0;

        if (g_import_context_ptrs && func_idx >= 0 && func_idx < g_num_imported_funcs) {
            int64_t target_ctx_ptr = g_import_context_ptrs[func_idx];
            if (target_ctx_ptr >= 0) {
                CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
                int target_func_idx = g_import_target_func_idxs[func_idx];

                if (g_context_depth >= MAX_CONTEXT_DEPTH) {
                    TRAP(TRAP_STACK_OVERFLOW);
                }

                save_context(&g_saved_contexts[g_context_depth++], crt);
                load_context(target_ctx, crt);

                int local_idx = target_func_idx - target_ctx->num_imported_funcs;
                if (local_idx < 0 || local_idx >= target_ctx->num_funcs) {
                    load_context(&g_saved_contexts[--g_context_depth], crt);
                    TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
                }

                int callee_pc = g_func_entries[local_idx];
                int callee_num_locals = g_func_num_locals[local_idx];

                uint64_t* args_ptr = sp - num_params;
                uint64_t* new_fp = args_ptr;
                uint64_t* callee_sp = args_ptr + num_params;
                int extra_locals = callee_num_locals - num_params;

                for (int i = 0; i < extra_locals; i++) {
                    *callee_sp++ = 0;
                }

                int trap = run(crt, crt->code + callee_pc, callee_sp, new_fp);

                uint64_t results[16];
                int actual_results = num_results < 16 ? num_results : 16;
                for (int i = 0; i < actual_results; i++) {
                    results[i] = new_fp[i];
                }

                load_context(&g_saved_contexts[--g_context_depth], crt);

                if (trap != TRAP_NONE) {
                    return trap;
                }

                for (int i = 0; i < actual_results; i++) {
                    fp[i] = results[i];
                }
                return TRAP_NONE;
            }
        }

        int handler_id = -1;
        if (g_import_handler_ids && func_idx >= 0 && func_idx < g_num_imported_funcs) {
            handler_id = g_import_handler_ids[func_idx];
        }
        if (handler_id >= 0) {
            uint64_t* args_ptr = sp - num_params;
            uint64_t results[16];
            int actual_results = num_results < 16 ? num_results : 16;
            call_host_import(handler_id, args_ptr, num_params, results, actual_results);
            for (int i = 0; i < actual_results; i++) {
                fp[i] = results[i];
            }
            return TRAP_NONE;
        }

        for (int i = 0; i < num_results; i++) {
            fp[i] = 0;
        }
        return TRAP_NONE;
    }

    // Local function
    int local_idx = func_idx - g_num_imported_funcs;
    if (local_idx < 0 || local_idx >= g_num_funcs) {
        TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
    }

    int callee_entry = g_func_entries[local_idx];

    int num_params = 0;
    int actual_type_idx = (func_idx >= 0 && func_idx < g_num_imported_funcs + g_num_funcs)
        ? g_func_type_idxs[func_idx]
        : -1;
    if (actual_type_idx >= 0 && actual_type_idx < g_num_types) {
        uint32_t sig2 = (uint32_t)g_type_sig_hash2[actual_type_idx];
        num_params = (int)(sig2 >> 16);
    } else if (expected_type_idx >= 0 && expected_type_idx < g_num_types) {
        uint32_t sig2 = (uint32_t)g_type_sig_hash2[expected_type_idx];
        num_params = (int)(sig2 >> 16);
    }

    uint64_t* args_start = sp - num_params;
    if (num_params > 0 && args_start > fp) {
        for (int i = 0; i < num_params; i++) {
            fp[i] = args_start[i];
        }
    }

    sp = fp + num_params;
    pc = crt->code + callee_entry;
    NEXT();
}
DEFINE_OP(return_call_indirect)

// Call a function in another module (cross-module call with context switching)
// Immediates: target_context_ptr (2 words for 64-bit pointer), func_idx, num_args, num_results
int op_call_external(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    // Read target context pointer (stored as single uint64_t)
    CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)*pc++;
    int func_idx = (int)*pc++;
    int num_args = (int)*pc++;
    int num_results = (int)*pc++;

    // Save caller pc for return
    uint64_t* caller_pc = pc;

    // Check context depth limit
    if (g_context_depth >= MAX_CONTEXT_DEPTH) {
        TRAP(TRAP_STACK_OVERFLOW);
    }

    // Save current context
    save_context(&g_saved_contexts[g_context_depth++], crt);

    // Load target context
    load_context(target_ctx, crt);

    // Get callee info from target module
    int callee_pc = g_func_entries[func_idx];
    int callee_num_locals = g_func_num_locals[func_idx];

    // Set up frame: args are at sp[-num_args..sp-1]
    // New frame starts where args are, locals extend beyond args
    uint64_t* new_fp = sp - num_args;
    int extra_locals = callee_num_locals - num_args;

    // Zero-initialize extra locals
    for (int i = 0; i < extra_locals; i++) {
        *sp++ = 0;
    }

    // Execute the function in target module
    int trap = run(crt, crt->code + callee_pc, sp, new_fp);

    // Save results before restoring context (results are at new_fp[0..num_results-1])
    uint64_t results[16];  // Assume max 16 results (reasonable limit)
    int actual_results = num_results < 16 ? num_results : 16;
    for (int i = 0; i < actual_results; i++) {
        results[i] = new_fp[i];
    }

    // Restore our context
    load_context(&g_saved_contexts[--g_context_depth], crt);

    if (trap != TRAP_NONE) {
        return trap;
    }

    // Place results where args were (standard calling convention)
    // sp - num_args is where args were, results go there
    // Then sp should be sp - num_args + num_results
    uint64_t* result_dst = sp - num_args;
    for (int i = 0; i < actual_results; i++) {
        result_dst[i] = results[i];
    }
    sp = sp - num_args + actual_results;

    // Continue execution with caller's pc and updated sp
    pc = caller_pc;
    NEXT();
}
DEFINE_OP(call_external)

// FFI function to call a function in another module from MoonBit
// Used for exported imports
int call_external_ffi(
    int64_t target_context_ptr,
    int func_idx,
    uint64_t* args,
    int num_args,
    uint64_t* result_out,
    int num_results
) {
    CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_context_ptr;

    // Allocate a temporary stack for this call
    uint64_t temp_stack[256];
    uint64_t* sp = temp_stack;
    uint64_t* fp = temp_stack;

    // Copy args to the stack
    for (int i = 0; i < num_args; i++) {
        *sp++ = args[i];
    }

    // Load target context (sets all global variables)
    CRuntime dummy_crt = {0};
    load_context(target_ctx, &dummy_crt);

    // Get callee info from target module (now using loaded globals)
    int callee_pc = target_ctx->func_entries[func_idx];
    int callee_num_locals = target_ctx->func_num_locals[func_idx];

    // Set up frame: args are already on stack, locals follow
    int extra_locals = callee_num_locals - num_args;
    for (int i = 0; i < extra_locals; i++) {
        *sp++ = 0;
    }

    // Execute the function using target context's code
    int trap = run(&dummy_crt, target_ctx->code + callee_pc, sp, fp);

    if (trap != TRAP_NONE) {
        return trap;
    }

    // Copy results from frame to output
    for (int i = 0; i < num_results; i++) {
        result_out[i] = fp[i];
    }

    return TRAP_NONE;
}

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
    (void)fp;
    ++pc;  // Skip mem_idx (assume 0)
    uint32_t delta = (uint32_t)sp[-1];
    int32_t old_pages = g_memory_pages ? *g_memory_pages : 0;

    // Calculate new size
    int64_t new_pages = (int64_t)old_pages + (int64_t)delta;
    int64_t new_size = new_pages * 65536;

    // Check if growth would exceed max size
    if (new_size > g_memory_max_size) {
        // Return -1 to indicate failure
        sp[-1] = (uint64_t)(uint32_t)-1;
        NEXT();
    }

    // Zero the new pages
    int old_size = old_pages * 65536;
    if (delta > 0 && crt->mem) {
        memset(crt->mem + old_size, 0, (size_t)(new_size - old_size));
    }

    // Update page count and memory size
    if (g_memory_pages) {
        *g_memory_pages = (int)new_pages;
    }
    g_memory_size = (int)new_size;

    // Return old page count (success)
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
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 4);
    uint32_t value = *(uint32_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;
    NEXT();
}
DEFINE_OP(i32_load)

int op_i32_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t value = (uint32_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 4);
    *(uint32_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i32_store)

// Narrow loads - sign/zero extend to i32
int op_i32_load8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 1);
    int8_t value = *(int8_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)(int32_t)value;  // Sign extend
    NEXT();
}
DEFINE_OP(i32_load8_s)

int op_i32_load8_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 1);
    uint8_t value = *(uint8_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i32_load8_u)

int op_i32_load16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 2);
    int16_t value = *(int16_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)(int32_t)value;  // Sign extend
    NEXT();
}
DEFINE_OP(i32_load16_s)

int op_i32_load16_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 2);
    uint16_t value = *(uint16_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i32_load16_u)

// Narrow stores - truncate from i32
int op_i32_store8(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint8_t value = (uint8_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 1);
    *(uint8_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i32_store8)

int op_i32_store16(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint16_t value = (uint16_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 2);
    *(uint16_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i32_store16)

// i64 loads
int op_i64_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 8);
    uint64_t value = *(uint64_t*)(crt->mem + (size_t)addr);
    sp[-1] = value;
    NEXT();
}
DEFINE_OP(i64_load)

int op_i64_load8_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 1);
    int8_t value = *(int8_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load8_s)

int op_i64_load8_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 1);
    uint8_t value = *(uint8_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i64_load8_u)

int op_i64_load16_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 2);
    int16_t value = *(int16_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load16_s)

int op_i64_load16_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 2);
    uint16_t value = *(uint16_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i64_load16_u)

int op_i64_load32_s(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 4);
    int32_t value = *(int32_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)(int64_t)value;  // Sign extend to i64
    NEXT();
}
DEFINE_OP(i64_load32_s)

int op_i64_load32_u(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 4);
    uint32_t value = *(uint32_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Zero extend
    NEXT();
}
DEFINE_OP(i64_load32_u)

// i64 stores
int op_i64_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t value = sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 8);
    *(uint64_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i64_store)

int op_i64_store8(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint8_t value = (uint8_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 1);
    *(uint8_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i64_store8)

int op_i64_store16(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint16_t value = (uint16_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 2);
    *(uint16_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i64_store16)

int op_i64_store32(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t value = (uint32_t)sp[-1];
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 4);
    *(uint32_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(i64_store32)

// f32 load/store
int op_f32_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 4);
    uint32_t value = *(uint32_t*)(crt->mem + (size_t)addr);
    sp[-1] = (uint64_t)value;  // Store f32 bits in lower 32 bits
    NEXT();
}
DEFINE_OP(f32_load)

int op_f32_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint32_t value = (uint32_t)sp[-1];  // f32 bits in lower 32 bits
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 4);
    *(uint32_t*)(crt->mem + (size_t)addr) = value;
    NEXT();
}
DEFINE_OP(f32_store)

// f64 load/store
int op_f64_load(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t addr = (uint64_t)(uint32_t)sp[-1] + (uint64_t)offset;
    CHECK_MEMORY(addr, 8);
    uint64_t value = *(uint64_t*)(crt->mem + (size_t)addr);
    sp[-1] = value;  // f64 bits
    NEXT();
}
DEFINE_OP(f64_load)

int op_f64_store(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t offset = (uint32_t)*pc++;
    ++pc;  // Skip mem_idx
    uint64_t value = sp[-1];  // f64 bits
    uint64_t addr = (uint64_t)(uint32_t)sp[-2] + (uint64_t)offset;
    sp -= 2;
    CHECK_MEMORY(addr, 8);
    *(uint64_t*)(crt->mem + (size_t)addr) = value;
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

    int external_base = g_num_imported_funcs + g_num_funcs;
    if (g_num_external_funcrefs > 0 && func_idx >= external_base) {
        int ext_idx = func_idx - external_base;
        if (ext_idx < 0 || ext_idx >= g_num_external_funcrefs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int import_idx = g_num_imported_funcs + ext_idx;
        int num_params = g_import_num_params ? g_import_num_params[import_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[import_idx] : 0;

        if (expected_type_idx >= 0 && expected_type_idx < g_num_types) {
            int expected_sig2 = g_type_sig_hash2[expected_type_idx];
            int expected_params = expected_sig2 >> 16;
            int expected_results = expected_sig2 & 0xFFFF;
            if (expected_params != num_params || expected_results != num_results) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }

        if (!g_import_context_ptrs || !g_import_target_func_idxs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int64_t target_ctx_ptr = g_import_context_ptrs[import_idx];
        if (target_ctx_ptr < 0) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }

        int target_func_idx = g_import_target_func_idxs[import_idx];
        uint64_t* args_ptr = fp + frame_offset;

        CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
        if (g_context_depth >= MAX_CONTEXT_DEPTH) {
            TRAP(TRAP_STACK_OVERFLOW);
        }
        save_context(&g_saved_contexts[g_context_depth++], crt);
        load_context(target_ctx, crt);

        int local_target_idx = target_func_idx - target_ctx->num_imported_funcs;
        if (local_target_idx < 0 || local_target_idx >= target_ctx->num_funcs) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
        }

        int callee_entry = target_ctx->func_entries[local_target_idx];
        int callee_num_locals = target_ctx->func_num_locals[local_target_idx];

        uint64_t* callee_stack = (uint64_t*)malloc(STACK_SIZE * sizeof(uint64_t));
        if (!callee_stack) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_STACK_OVERFLOW);
        }

        for (int i = 0; i < num_params; i++) {
            callee_stack[i] = args_ptr[i];
        }
        for (int i = num_params; i < callee_num_locals; i++) {
            callee_stack[i] = 0;
        }

        uint64_t* callee_pc = target_ctx->code + callee_entry;
        uint64_t* callee_fp = callee_stack;
        uint64_t* callee_sp = callee_stack + callee_num_locals;

        int trap = run(crt, callee_pc, callee_sp, callee_fp);

        for (int i = 0; i < num_results; i++) {
            args_ptr[i] = callee_stack[i];
        }

        free(callee_stack);

        load_context(&g_saved_contexts[--g_context_depth], crt);

        if (trap != TRAP_NONE) {
            return trap;
        }

        NEXT();
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

    // Check if this is an imported function (host or cross-module)
    if (func_idx < g_num_imported_funcs) {
        int handler_id = -1;
        if (g_import_handler_ids && func_idx >= 0 && func_idx < g_num_imported_funcs) {
            handler_id = g_import_handler_ids[func_idx];
        }
        if (handler_id >= 0) {
            int num_params = g_import_num_params ? g_import_num_params[func_idx] : 0;
            int num_results = g_import_num_results ? g_import_num_results[func_idx] : 0;
            uint64_t* args_ptr = fp + frame_offset;
            uint64_t results[16];
            int actual_results = num_results < 16 ? num_results : 16;
            call_host_import(handler_id, args_ptr, num_params, results, actual_results);
            for (int i = 0; i < actual_results; i++) {
                args_ptr[i] = results[i];
            }
            sp = args_ptr + actual_results;
            NEXT();
        }

        // This is an imported function - need to do cross-module call
        // Check if we have resolved import info
        if (g_import_context_ptrs == NULL || g_import_target_func_idxs == NULL) {
            // No cross-module support - treat as undefined
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }

        int64_t target_ctx_ptr = g_import_context_ptrs[func_idx];
        if (target_ctx_ptr <= 0) {
            // Import not resolved
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }

        // Get import metadata
        int num_params = g_import_num_params ? g_import_num_params[func_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[func_idx] : 0;
        int target_func_idx = g_import_target_func_idxs[func_idx];

        // Args are at fp + frame_offset
        uint64_t* args_ptr = fp + frame_offset;

        // Call the external function using context switching
        CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;

        // Save current context
        if (g_context_depth >= MAX_CONTEXT_DEPTH) {
            TRAP(TRAP_STACK_OVERFLOW);
        }
        save_context(&g_saved_contexts[g_context_depth++], crt);

        // Load target context
        load_context(target_ctx, crt);

        // Get target function info
        int local_target_idx = target_func_idx - target_ctx->num_imported_funcs;
        if (local_target_idx < 0 || local_target_idx >= target_ctx->num_funcs) {
            // Restore context before trap
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
        }

        int callee_entry = target_ctx->func_entries[local_target_idx];
        int callee_num_locals = target_ctx->func_num_locals[local_target_idx];

        // Allocate frame for callee
        uint64_t* callee_stack = (uint64_t*)malloc(STACK_SIZE * sizeof(uint64_t));
        if (!callee_stack) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_STACK_OVERFLOW);
        }

        // Copy args to callee stack
        for (int i = 0; i < num_params; i++) {
            callee_stack[i] = args_ptr[i];
        }
        // Zero remaining locals
        for (int i = num_params; i < callee_num_locals; i++) {
            callee_stack[i] = 0;
        }

        // Execute callee
        uint64_t* callee_pc = target_ctx->code + callee_entry;
        uint64_t* callee_fp = callee_stack;
        uint64_t* callee_sp = callee_stack + callee_num_locals;

        int trap = run(crt, callee_pc, callee_sp, callee_fp);

        // Copy results back to our args location (results at callee_stack[0..num_results-1])
        for (int i = 0; i < num_results; i++) {
            args_ptr[i] = callee_stack[i];
        }

        free(callee_stack);

        // Restore our context
        load_context(&g_saved_contexts[--g_context_depth], crt);

        if (trap != TRAP_NONE) {
            return trap;
        }

        NEXT();
    }

    // Local function call
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

// =============================================================================
// Bulk memory operations
// =============================================================================

// memory.copy - copy memory region (handles overlapping regions)
// Stack: [dest, src, n] -> []
int op_memory_copy(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t n = (uint32_t)sp[-1];
    uint32_t src = (uint32_t)sp[-2];
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Check bounds for both source and destination
    if ((uint64_t)src + n > (uint64_t)g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }
    if ((uint64_t)dest + n > (uint64_t)g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }

    // Use memmove to handle overlapping regions correctly
    if (n > 0) {
        memmove(crt->mem + dest, crt->mem + src, n);
    }
    NEXT();
}
DEFINE_OP(memory_copy)

// memory.fill - fill memory region with a byte value
// Stack: [dest, val, n] -> []
int op_memory_fill(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    uint32_t n = (uint32_t)sp[-1];
    uint8_t val = (uint8_t)sp[-2];  // Truncate to byte
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Check bounds
    if ((uint64_t)dest + n > (uint64_t)g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }

    // Fill memory
    if (n > 0) {
        memset(crt->mem + dest, val, n);
    }
    NEXT();
}
DEFINE_OP(memory_fill)

// memory.init - initialize memory from data segment
// Immediate: data_idx
// Stack: [dest, src, n] -> []
int op_memory_init(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)fp;
    int data_idx = (int)*pc++;
    uint32_t n = (uint32_t)sp[-1];
    uint32_t src = (uint32_t)sp[-2];
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Check data segment index
    if (data_idx < 0 || data_idx >= g_num_data_segments) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);  // "unknown data segment"
    }

    // Get data segment info
    int seg_offset = g_data_segment_offsets[data_idx];
    int seg_size = g_data_segment_sizes[data_idx];

    // Check bounds for data segment read
    if ((uint64_t)src + n > (uint64_t)seg_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }

    // Check bounds for memory write
    if ((uint64_t)dest + n > (uint64_t)g_memory_size) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);
    }

    // Copy from data segment to memory
    if (n > 0) {
        memcpy(crt->mem + dest, g_data_segments_flat + seg_offset + src, n);
    }
    NEXT();
}
DEFINE_OP(memory_init)

// data.drop - drop a data segment (make it unusable for memory.init)
// Immediate: data_idx
// Stack: [] -> []
int op_data_drop(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)sp; (void)fp;
    int data_idx = (int)*pc++;

    // Check data segment index
    if (data_idx < 0 || data_idx >= g_num_data_segments) {
        TRAP(TRAP_OUT_OF_BOUNDS_MEMORY);  // "unknown data segment"
    }

    // Drop the segment by setting its size to 0
    g_data_segment_sizes[data_idx] = 0;
    NEXT();
}
DEFINE_OP(data_drop)

// =============================================================================
// Bulk table operations
// =============================================================================

// table.copy - copy elements between tables (or within same table)
// Immediates: dst_table_idx, src_table_idx
// Stack: [dest, src, n] -> []
int op_table_copy(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int dst_table_idx = (int)*pc++;
    int src_table_idx = (int)*pc++;

    uint32_t n = (uint32_t)sp[-1];
    uint32_t src = (uint32_t)sp[-2];
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Validate table indices
    if (dst_table_idx < 0 || dst_table_idx >= g_num_tables ||
        src_table_idx < 0 || src_table_idx >= g_num_tables) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int dst_offset = g_table_offsets[dst_table_idx];
    int dst_size = g_table_sizes[dst_table_idx];
    int src_offset = g_table_offsets[src_table_idx];
    int src_size = g_table_sizes[src_table_idx];

    // Bounds check
    if ((uint64_t)src + n > (uint64_t)src_size ||
        (uint64_t)dest + n > (uint64_t)dst_size) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    // Copy with proper overlap handling
    if (dst_table_idx == src_table_idx && dest > src && dest < src + n) {
        // Overlapping, dest > src: copy backwards
        for (int i = n - 1; i >= 0; i--) {
            g_tables_flat[dst_offset + dest + i] = g_tables_flat[src_offset + src + i];
        }
    } else {
        // Non-overlapping or src >= dest: copy forwards
        for (uint32_t i = 0; i < n; i++) {
            g_tables_flat[dst_offset + dest + i] = g_tables_flat[src_offset + src + i];
        }
    }
    NEXT();
}
DEFINE_OP(table_copy)

// table.fill - fill table entries with a value
// Immediate: table_idx
// Stack: [dest, val, n] -> []
int op_table_fill(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int table_idx = (int)*pc++;

    uint32_t n = (uint32_t)sp[-1];
    int32_t val = (int32_t)sp[-2];  // Reference value (funcref index or -1 for null)
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int table_offset = g_table_offsets[table_idx];
    int table_size = g_table_sizes[table_idx];

    // Bounds check
    if ((uint64_t)dest + n > (uint64_t)table_size) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    // Fill table
    for (uint32_t i = 0; i < n; i++) {
        g_tables_flat[table_offset + dest + i] = val;
    }
    NEXT();
}
DEFINE_OP(table_fill)

// table.init - initialize table from element segment
// Immediates: elem_idx, table_idx
// Stack: [dest, src, n] -> []
int op_table_init(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int elem_idx = (int)*pc++;
    int table_idx = (int)*pc++;

    uint32_t n = (uint32_t)sp[-1];
    uint32_t src = (uint32_t)sp[-2];
    uint32_t dest = (uint32_t)sp[-3];
    sp -= 3;

    // Validate element segment index
    if (elem_idx < 0 || elem_idx >= g_num_elem_segments) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int elem_offset = g_elem_segment_offsets[elem_idx];
    // Dropped segments are treated as having size 0
    int elem_size = g_elem_segment_dropped[elem_idx] ? 0 : g_elem_segment_sizes[elem_idx];
    int table_offset = g_table_offsets[table_idx];
    int table_size = g_table_sizes[table_idx];

    // Bounds check (n=0 with dropped segment is OK, n>0 with dropped segment traps)
    if ((uint64_t)src + n > (uint64_t)elem_size ||
        (uint64_t)dest + n > (uint64_t)table_size) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    // Copy from element segment to table
    for (uint32_t i = 0; i < n; i++) {
        g_tables_flat[table_offset + dest + i] = g_elem_segments_flat[elem_offset + src + i];
    }
    NEXT();
}
DEFINE_OP(table_init)

// elem.drop - drop an element segment
// Immediate: elem_idx
// Stack: [] -> []
int op_elem_drop(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp; (void)sp;
    int elem_idx = (int)*pc++;

    // Validate element segment index
    if (elem_idx >= 0 && elem_idx < g_num_elem_segments) {
        // Mark segment as dropped
        g_elem_segment_dropped[elem_idx] = 1;
    }
    NEXT();
}
DEFINE_OP(elem_drop)

// =============================================================================
// Reference type operations
// =============================================================================

// Null reference constant: 0xFFFFFFFFFFFFFFFF
#define REF_NULL 0xFFFFFFFFFFFFFFFFULL
// Funcref tag: bit 62 set, lower bits are func_idx
#define FUNCREF_TAG 0x4000000000000000ULL

// ref.null - push a null reference
// Immediate: heap_type (ignored at runtime)
// Stack: [] -> [null_ref]
int op_ref_null(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    ++pc;  // Skip heap type immediate
    *sp++ = REF_NULL;
    NEXT();
}
DEFINE_OP(ref_null)

// ref.func - push a reference to a function
// Immediate: func_idx
// Stack: [] -> [funcref]
int op_ref_func(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int func_idx = (int)*pc++;
    // Tag with bit 62 for funcref
    *sp++ = FUNCREF_TAG | (uint64_t)func_idx;
    NEXT();
}
DEFINE_OP(ref_func)

// ref.is_null - test if reference is null
// Stack: [ref] -> [i32]
int op_ref_is_null(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t ref = sp[-1];
    sp[-1] = (ref == REF_NULL) ? 1 : 0;
    NEXT();
}
DEFINE_OP(ref_is_null)

// ref.eq - test if two references are equal
// Stack: [ref1, ref2] -> [i32]
int op_ref_eq(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t b = sp[-1];
    uint64_t a = sp[-2];
    --sp;
    sp[-1] = (a == b) ? 1 : 0;
    NEXT();
}
DEFINE_OP(ref_eq)

// ref.as_non_null - assert reference is non-null
// Stack: [ref] -> [ref]
// Traps if reference is null
int op_ref_as_non_null(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    uint64_t ref = sp[-1];
    if (ref == REF_NULL) {
        TRAP(TRAP_NULL_REFERENCE);
    }
    // Leave ref on stack unchanged
    NEXT();
}
DEFINE_OP(ref_as_non_null)

// br_on_null - branch if reference is null
// Immediate: target_pc
// Stack: [ref] -> [ref] (fall-through) or [] (branch)
// If null: consumes ref and branches
// If non-null: leaves ref on stack and continues
int op_br_on_null(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int target_pc = (int)*pc++;
    int not_taken_pc = (int)*pc++;
    uint64_t ref = sp[-1];
    if (ref == REF_NULL) {
        // Null: pop ref and branch
        --sp;
        pc = crt->code + target_pc;
    } else {
        // Non-null: keep ref and continue
        pc = crt->code + not_taken_pc;
    }
    NEXT();
}
DEFINE_OP(br_on_null)

// br_on_non_null - branch if reference is non-null
// Immediate: target_pc
// Stack: [ref] -> [] (fall-through) or [ref] (branch)
// If non-null: branches WITH the ref
// If null: consumes ref and continues
int op_br_on_non_null(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int target_pc = (int)*pc++;
    int not_taken_pc = (int)*pc++;
    uint64_t ref = sp[-1];
    if (ref != REF_NULL) {
        // Non-null: keep ref and branch
        pc = crt->code + target_pc;
    } else {
        // Null: pop ref and continue
        --sp;
        pc = crt->code + not_taken_pc;
    }
    NEXT();
}
DEFINE_OP(br_on_non_null)

// call_ref - call function via typed funcref
// Immediate: type_idx, frame_offset
// Stack: [args..., funcref] -> [results...]
int op_call_ref(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int expected_type_idx = (int)*pc++;
    int frame_offset = (int)*pc++;

    // Pop funcref from stack
    uint64_t ref = *--sp;

    // Check for null
    if (ref == REF_NULL) {
        TRAP(TRAP_NULL_FUNCTION_REFERENCE);
    }

    // Extract function index from tagged reference
    int func_idx = (int)(ref & 0x3FFFFFFFFFFFFFFFULL);

    int external_base = g_num_imported_funcs + g_num_funcs;
    if (g_num_external_funcrefs > 0 && func_idx >= external_base) {
        int ext_idx = func_idx - external_base;
        if (ext_idx < 0 || ext_idx >= g_num_external_funcrefs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int import_idx = g_num_imported_funcs + ext_idx;
        int num_params = g_import_num_params ? g_import_num_params[import_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[import_idx] : 0;

        if (expected_type_idx >= 0 && expected_type_idx < g_num_types) {
            int expected_sig2 = g_type_sig_hash2[expected_type_idx];
            int expected_params = expected_sig2 >> 16;
            int expected_results = expected_sig2 & 0xFFFF;
            if (expected_params != num_params || expected_results != num_results) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }

        if (!g_import_context_ptrs || !g_import_target_func_idxs) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }
        int64_t target_ctx_ptr = g_import_context_ptrs[import_idx];
        if (target_ctx_ptr < 0) {
            TRAP(TRAP_UNINITIALIZED_ELEMENT);
        }

        CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
        int target_func_idx = g_import_target_func_idxs[import_idx];
        uint64_t* args_ptr = fp + frame_offset;
        uint64_t* caller_pc = pc;

        if (g_context_depth >= MAX_CONTEXT_DEPTH) {
            TRAP(TRAP_STACK_OVERFLOW);
        }
        save_context(&g_saved_contexts[g_context_depth++], crt);
        load_context(target_ctx, crt);

        int local_target_idx = target_func_idx - target_ctx->num_imported_funcs;
        if (local_target_idx < 0 || local_target_idx >= target_ctx->num_funcs) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
        }

        int callee_entry = target_ctx->func_entries[local_target_idx];
        int callee_num_locals = target_ctx->func_num_locals[local_target_idx];

        uint64_t* callee_stack = (uint64_t*)malloc(STACK_SIZE * sizeof(uint64_t));
        if (!callee_stack) {
            load_context(&g_saved_contexts[--g_context_depth], crt);
            TRAP(TRAP_STACK_OVERFLOW);
        }

        for (int i = 0; i < num_params; i++) {
            callee_stack[i] = args_ptr[i];
        }
        for (int i = num_params; i < callee_num_locals; i++) {
            callee_stack[i] = 0;
        }

        uint64_t* callee_pc = target_ctx->code + callee_entry;
        uint64_t* callee_fp = callee_stack;
        uint64_t* callee_sp = callee_stack + callee_num_locals;

        int trap = run(crt, callee_pc, callee_sp, callee_fp);

        for (int i = 0; i < num_results; i++) {
            args_ptr[i] = callee_stack[i];
        }

        free(callee_stack);
        load_context(&g_saved_contexts[--g_context_depth], crt);

        if (trap != TRAP_NONE) {
            return trap;
        }

        sp = args_ptr + num_results;
        pc = caller_pc;
        NEXT();
    }

    // Check if it's an imported function
    if (func_idx < g_num_imported_funcs) {
        // Imported function - trap (not supported yet)
        TRAP(TRAP_UNREACHABLE);
    }

    // Local function call
    int local_idx = func_idx - g_num_imported_funcs;
    if (local_idx < 0 || local_idx >= g_num_funcs) {
        TRAP(TRAP_UNREACHABLE);
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
DEFINE_OP(call_ref)

// return_call_ref - tail call function via typed funcref
// Immediate: type_idx
// Stack: [..., args..., funcref] -> (reuse current frame)
int op_return_call_ref(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    int expected_type_idx = (int)*pc++;

    // Pop funcref from stack
    uint64_t ref = *--sp;

    // Check for null
    if (ref == REF_NULL) {
        TRAP(TRAP_NULL_FUNCTION_REFERENCE);
    }

    // Extract function index from tagged reference
    int func_idx = (int)(ref & 0x3FFFFFFFFFFFFFFFULL);

    // Type check: compare expected type with actual function type using signature hashes
    if (func_idx < g_num_imported_funcs + g_num_funcs) {
        int actual_type_idx = g_func_type_idxs[func_idx];
        if (expected_type_idx >= 0 && expected_type_idx < g_num_types &&
            actual_type_idx >= 0 && actual_type_idx < g_num_types) {
            int expected_hash1 = g_type_sig_hash1[expected_type_idx];
            int expected_hash2 = g_type_sig_hash2[expected_type_idx];
            int actual_hash1 = g_type_sig_hash1[actual_type_idx];
            int actual_hash2 = g_type_sig_hash2[actual_type_idx];
            if (expected_hash1 != actual_hash1 || expected_hash2 != actual_hash2) {
                TRAP(TRAP_INDIRECT_CALL_TYPE_MISMATCH);
            }
        }
    }

    // Imported function
    if (func_idx < g_num_imported_funcs) {
        int num_params = g_import_num_params ? g_import_num_params[func_idx] : 0;
        int num_results = g_import_num_results ? g_import_num_results[func_idx] : 0;

        if (g_import_context_ptrs && func_idx >= 0 && func_idx < g_num_imported_funcs) {
            int64_t target_ctx_ptr = g_import_context_ptrs[func_idx];
            if (target_ctx_ptr >= 0) {
                CRuntimeContext* target_ctx = (CRuntimeContext*)(uintptr_t)target_ctx_ptr;
                int target_func_idx = g_import_target_func_idxs[func_idx];

                if (g_context_depth >= MAX_CONTEXT_DEPTH) {
                    TRAP(TRAP_STACK_OVERFLOW);
                }

                save_context(&g_saved_contexts[g_context_depth++], crt);
                load_context(target_ctx, crt);

                int local_idx = target_func_idx - target_ctx->num_imported_funcs;
                if (local_idx < 0 || local_idx >= target_ctx->num_funcs) {
                    load_context(&g_saved_contexts[--g_context_depth], crt);
                    TRAP(TRAP_OUT_OF_BOUNDS_TABLE);
                }

                int callee_pc = g_func_entries[local_idx];
                int callee_num_locals = g_func_num_locals[local_idx];

                uint64_t* args_ptr = sp - num_params;
                uint64_t* new_fp = args_ptr;
                uint64_t* callee_sp = args_ptr + num_params;
                int extra_locals = callee_num_locals - num_params;

                for (int i = 0; i < extra_locals; i++) {
                    *callee_sp++ = 0;
                }

                int trap = run(crt, crt->code + callee_pc, callee_sp, new_fp);

                uint64_t results[16];
                int actual_results = num_results < 16 ? num_results : 16;
                for (int i = 0; i < actual_results; i++) {
                    results[i] = new_fp[i];
                }

                load_context(&g_saved_contexts[--g_context_depth], crt);

                if (trap != TRAP_NONE) {
                    return trap;
                }

                for (int i = 0; i < actual_results; i++) {
                    fp[i] = results[i];
                }
                return TRAP_NONE;
            }
        }

        int handler_id = -1;
        if (g_import_handler_ids && func_idx >= 0 && func_idx < g_num_imported_funcs) {
            handler_id = g_import_handler_ids[func_idx];
        }
        if (handler_id >= 0) {
            uint64_t* args_ptr = sp - num_params;
            uint64_t results[16];
            int actual_results = num_results < 16 ? num_results : 16;
            call_host_import(handler_id, args_ptr, num_params, results, actual_results);
            for (int i = 0; i < actual_results; i++) {
                fp[i] = results[i];
            }
            return TRAP_NONE;
        }

        for (int i = 0; i < num_results; i++) {
            fp[i] = 0;
        }
        return TRAP_NONE;
    }

    // Local function call
    int local_idx = func_idx - g_num_imported_funcs;
    if (local_idx < 0 || local_idx >= g_num_funcs) {
        TRAP(TRAP_UNREACHABLE);
    }

    int callee_entry = g_func_entries[local_idx];

    int num_params = 0;
    if (expected_type_idx >= 0 && expected_type_idx < g_num_types) {
        uint32_t sig2 = (uint32_t)g_type_sig_hash2[expected_type_idx];
        num_params = (int)(sig2 >> 16);
    }

    uint64_t* args_start = sp - num_params;
    if (num_params > 0 && args_start > fp) {
        for (int i = 0; i < num_params; i++) {
            fp[i] = args_start[i];
        }
    }

    sp = fp + num_params;
    pc = crt->code + callee_entry;
    NEXT();
}
DEFINE_OP(return_call_ref)

// =============================================================================
// Table access operations
// =============================================================================

// table.get - get element from table
// Immediate: table_idx
// Stack: [i32] -> [ref]
int op_table_get(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int table_idx = (int)*pc++;
    int elem_idx = (int)sp[-1];

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int offset = g_table_offsets[table_idx];
    int size = g_table_sizes[table_idx];

    // Bounds check
    if (elem_idx < 0 || elem_idx >= size) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int func_idx = g_tables_flat[offset + elem_idx];

    // Convert to tagged reference
    if (func_idx == -1) {
        sp[-1] = REF_NULL;  // null
    } else {
        sp[-1] = FUNCREF_TAG | (uint64_t)func_idx;
    }
    NEXT();
}
DEFINE_OP(table_get)

// table.set - set element in table
// Immediate: table_idx
// Stack: [i32, ref] -> []
int op_table_set(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int table_idx = (int)*pc++;
    uint64_t ref = sp[-1];
    int elem_idx = (int)sp[-2];
    sp -= 2;

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    int offset = g_table_offsets[table_idx];
    int size = g_table_sizes[table_idx];

    // Bounds check
    if (elem_idx < 0 || elem_idx >= size) {
        TRAP(TRAP_TABLE_BOUNDS_ACCESS);
    }

    // Convert from tagged reference to func index
    int func_idx;
    if (ref == REF_NULL) {
        func_idx = -1;  // null
    } else {
        // Strip tag bits (use lower 62 bits)
        func_idx = (int)(ref & 0x3FFFFFFFFFFFFFFFULL);
    }

    g_tables_flat[offset + elem_idx] = func_idx;
    NEXT();
}
DEFINE_OP(table_set)

// table.size - get current size of table
// Immediate: table_idx
// Stack: [] -> [i32]
int op_table_size(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int table_idx = (int)*pc++;

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        *sp++ = 0;
        NEXT();
    }

    *sp++ = (uint64_t)g_table_sizes[table_idx];
    NEXT();
}
DEFINE_OP(table_size)

// table.grow - grow table by delta elements
// Immediate: table_idx
// Stack: [ref, i32] -> [i32]  (returns old size, or -1 on failure)
int op_table_grow(CRuntime* crt, uint64_t* pc, uint64_t* sp, uint64_t* fp) {
    (void)crt; (void)fp;
    int table_idx = (int)*pc++;
    int delta = (int)sp[-1];
    uint64_t init_ref = sp[-2];
    sp -= 2;

    // Validate table index
    if (table_idx < 0 || table_idx >= g_num_tables) {
        *sp++ = 0xFFFFFFFFULL;  // -1 (failure)
        NEXT();
    }

    int old_size = g_table_sizes[table_idx];
    int max_size = g_table_max_sizes ? g_table_max_sizes[table_idx] : old_size;
    int new_size = old_size + delta;

    // Check for overflow or exceeding max
    if (delta < 0 || new_size > max_size || new_size < old_size) {
        *sp++ = 0xFFFFFFFFULL;  // -1 (failure)
        NEXT();
    }

    // Convert from tagged reference to func index
    int func_idx;
    if (init_ref == REF_NULL) {
        func_idx = -1;
    } else {
        func_idx = (int)(init_ref & 0x3FFFFFFFFFFFFFFFULL);
    }

    // Initialize new elements
    int offset = g_table_offsets[table_idx];
    for (int i = old_size; i < new_size; i++) {
        g_tables_flat[offset + i] = func_idx;
    }

    g_table_sizes[table_idx] = new_size;
    *sp++ = (uint64_t)old_size;  // return old size
    NEXT();
}
DEFINE_OP(table_grow)
