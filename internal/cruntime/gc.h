#ifndef WASM5_GC_H
#define WASM5_GC_H

#include <stddef.h>
#include <stdint.h>

#define GC_TYPE_ARRAY 1
#define GC_TYPE_STRUCT 2

typedef struct GcHeader {
    uint32_t type_idx;
    uint16_t obj_type;
    uint8_t mark;
    uint8_t age;
    struct GcHeader* gc_next;
} GcHeader;

typedef struct GcArray {
    GcHeader header;
    int32_t length;
    uint32_t _pad;
    uint64_t elements[];
} GcArray;

typedef struct GcStruct {
    GcHeader header;
    int32_t field_count;
    uint32_t _pad;
    uint64_t fields[];
} GcStruct;

void gc_init(void);
void gc_cleanup(void);

GcArray* gc_alloc_array(uint32_t type_idx, int32_t length);
GcStruct* gc_alloc_struct(uint32_t type_idx, int32_t field_count);
void gc_collect(void);

void gc_push_stack(uint64_t* base, size_t slots);
void gc_pop_stack(void);

void gc_set_globals(uint64_t* globals, int num_globals);

int gc_is_managed_ptr(uint64_t value);

uint64_t gc_alloc_array_const(uint32_t type_idx, int32_t length, uint64_t init_val);
uint64_t gc_alloc_array_from_values(uint32_t type_idx, int32_t length, const uint64_t* values);
uint64_t gc_alloc_struct_default(uint32_t type_idx, int32_t field_count);
uint64_t gc_alloc_struct_from_values(uint32_t type_idx, int32_t field_count, const uint64_t* values);

#endif
