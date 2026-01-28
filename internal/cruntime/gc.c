#include "gc.h"

#include <stdlib.h>
#include <string.h>

#define GC_COLLECT_THRESHOLD 512
#define GC_PTRSET_TOMBSTONE ((uintptr_t)1)
#define GC_PTRSET_MIN_CAP 1024

#define REF_NULL 0xFFFFFFFFFFFFFFFFULL
#define FUNCREF_TAG 0x4000000000000000ULL

typedef struct GcStackRange {
    uint64_t* base;
    size_t slots;
    struct GcStackRange* prev;
} GcStackRange;

typedef struct {
    uintptr_t* slots;
    size_t cap;
    size_t size;
} GcPtrSet;

typedef struct {
    GcHeader* all_objects;
    size_t num_objects;
    size_t alloc_since_gc;
    size_t collect_threshold;
    int initialized;
    int disable_collect;

    GcPtrSet ptrs;
    GcStackRange* stacks;

    uint64_t* globals;
    int num_globals;
} GcHeap;

static GcHeap g_gc_heap;

static size_t hash_ptr(uintptr_t p) {
    p >>= 3;
    p ^= p >> 33;
    p *= 0xff51afd7ed558ccdULL;
    p ^= p >> 33;
    p *= 0xc4ceb9fe1a85ec53ULL;
    p ^= p >> 33;
    return (size_t)p;
}

static void ptrset_init(GcPtrSet* set, size_t cap) {
    size_t pow2 = GC_PTRSET_MIN_CAP;
    while (pow2 < cap) {
        pow2 <<= 1;
    }
    set->slots = (uintptr_t*)calloc(pow2, sizeof(uintptr_t));
    set->cap = set->slots ? pow2 : 0;
    set->size = 0;
}

static void ptrset_cleanup(GcPtrSet* set) {
    free(set->slots);
    set->slots = NULL;
    set->cap = 0;
    set->size = 0;
}

static int ptrset_grow(GcPtrSet* set) {
    size_t new_cap = set->cap ? set->cap << 1 : GC_PTRSET_MIN_CAP;
    uintptr_t* new_slots = (uintptr_t*)calloc(new_cap, sizeof(uintptr_t));
    if (!new_slots) {
        return 0;
    }
    for (size_t i = 0; i < set->cap; i++) {
        uintptr_t key = set->slots[i];
        if (key && key != GC_PTRSET_TOMBSTONE) {
            size_t idx = hash_ptr(key) & (new_cap - 1);
            while (new_slots[idx]) {
                idx = (idx + 1) & (new_cap - 1);
            }
            new_slots[idx] = key;
        }
    }
    free(set->slots);
    set->slots = new_slots;
    set->cap = new_cap;
    return 1;
}

static int ptrset_add(GcPtrSet* set, uintptr_t key) {
    if (key == 0) {
        return 0;
    }
    if (set->cap == 0) {
        ptrset_init(set, GC_PTRSET_MIN_CAP);
        if (set->cap == 0) {
            return 0;
        }
    }
    if ((set->size + 1) * 10 >= set->cap * 7) {
        if (!ptrset_grow(set)) {
            return 0;
        }
    }
    size_t idx = hash_ptr(key) & (set->cap - 1);
    size_t first_tombstone = (size_t)-1;
    while (set->slots[idx]) {
        if (set->slots[idx] == key) {
            return 1;
        }
        if (set->slots[idx] == GC_PTRSET_TOMBSTONE && first_tombstone == (size_t)-1) {
            first_tombstone = idx;
        }
        idx = (idx + 1) & (set->cap - 1);
    }
    if (first_tombstone != (size_t)-1) {
        idx = first_tombstone;
    }
    set->slots[idx] = key;
    set->size++;
    return 1;
}

static int ptrset_contains(const GcPtrSet* set, uintptr_t key) {
    if (key == 0 || set->cap == 0) {
        return 0;
    }
    size_t idx = hash_ptr(key) & (set->cap - 1);
    while (set->slots[idx]) {
        if (set->slots[idx] == key) {
            return 1;
        }
        idx = (idx + 1) & (set->cap - 1);
    }
    return 0;
}

static void ptrset_remove(GcPtrSet* set, uintptr_t key) {
    if (key == 0 || set->cap == 0) {
        return;
    }
    size_t idx = hash_ptr(key) & (set->cap - 1);
    while (set->slots[idx]) {
        if (set->slots[idx] == key) {
            set->slots[idx] = GC_PTRSET_TOMBSTONE;
            if (set->size > 0) {
                set->size--;
            }
            return;
        }
        idx = (idx + 1) & (set->cap - 1);
    }
}

void gc_init(void) {
    if (g_gc_heap.initialized) {
        return;
    }
    memset(&g_gc_heap, 0, sizeof(g_gc_heap));
    g_gc_heap.collect_threshold = GC_COLLECT_THRESHOLD;
    g_gc_heap.initialized = 1;
    ptrset_init(&g_gc_heap.ptrs, GC_PTRSET_MIN_CAP);
    if (g_gc_heap.ptrs.cap == 0) {
        g_gc_heap.disable_collect = 1;
    }
}

void gc_cleanup(void) {
    GcHeader* obj = g_gc_heap.all_objects;
    while (obj) {
        GcHeader* next = obj->gc_next;
        free(obj);
        obj = next;
    }
    ptrset_cleanup(&g_gc_heap.ptrs);

    while (g_gc_heap.stacks) {
        GcStackRange* next = g_gc_heap.stacks->prev;
        free(g_gc_heap.stacks);
        g_gc_heap.stacks = next;
    }

    memset(&g_gc_heap, 0, sizeof(g_gc_heap));
}

static int gc_is_ptr(uint64_t val) {
    if (val == 0 || val == REF_NULL) {
        return 0;
    }
    if (val & FUNCREF_TAG) {
        return 0;
    }
    if ((val & (sizeof(void*) - 1)) != 0) {
        return 0;
    }
    return ptrset_contains(&g_gc_heap.ptrs, (uintptr_t)val);
}

int gc_is_managed_ptr(uint64_t value) {
    if (!g_gc_heap.initialized) {
        return 0;
    }
    return gc_is_ptr(value);
}

void gc_push_stack(uint64_t* base, size_t slots) {
    if (!g_gc_heap.initialized) {
        gc_init();
    }
    GcStackRange* range = (GcStackRange*)malloc(sizeof(GcStackRange));
    if (!range) {
        g_gc_heap.disable_collect = 1;
        return;
    }
    range->base = base;
    range->slots = slots;
    range->prev = g_gc_heap.stacks;
    g_gc_heap.stacks = range;
}

void gc_pop_stack(void) {
    if (!g_gc_heap.stacks) {
        return;
    }
    GcStackRange* top = g_gc_heap.stacks;
    g_gc_heap.stacks = top->prev;
    free(top);
}

void gc_set_globals(uint64_t* globals, int num_globals) {
    if (!g_gc_heap.initialized) {
        gc_init();
    }
    g_gc_heap.globals = globals;
    g_gc_heap.num_globals = num_globals;
}

GcArray* gc_alloc_array(uint32_t type_idx, int32_t length) {
    if (!g_gc_heap.initialized) {
        gc_init();
    }
    if (length < 0) {
        return NULL;
    }
    if (!g_gc_heap.disable_collect &&
        g_gc_heap.alloc_since_gc >= g_gc_heap.collect_threshold) {
        gc_collect();
    }

    size_t size = sizeof(GcArray) + (size_t)length * sizeof(uint64_t);
    GcArray* arr = (GcArray*)calloc(1, size);
    if (!arr) {
        return NULL;
    }

    arr->header.type_idx = type_idx;
    arr->header.obj_type = GC_TYPE_ARRAY;
    arr->header.mark = 0;
    arr->header.age = 0;
    arr->header.gc_next = g_gc_heap.all_objects;
    g_gc_heap.all_objects = &arr->header;

    arr->length = length;
    g_gc_heap.num_objects++;
    g_gc_heap.alloc_since_gc++;

    if (!ptrset_add(&g_gc_heap.ptrs, (uintptr_t)arr)) {
        g_gc_heap.disable_collect = 1;
    }

    return arr;
}

static void gc_mark_object(GcHeader* obj, GcHeader** stack, size_t* top, size_t cap) {
    if (!obj || obj->mark) {
        return;
    }
    obj->mark = 1;
    stack[(*top)++] = obj;

    while (*top > 0) {
        GcHeader* cur = stack[--(*top)];
        if (cur->obj_type == GC_TYPE_ARRAY) {
            GcArray* arr = (GcArray*)cur;
            for (int32_t i = 0; i < arr->length; i++) {
                uint64_t val = arr->elements[i];
                if (gc_is_ptr(val)) {
                    GcHeader* child = (GcHeader*)val;
                    if (!child->mark) {
                        child->mark = 1;
                        stack[(*top)++] = child;
                    }
                }
            }
        }
    }
}

static void gc_mark_roots(GcHeader** stack, size_t* top, size_t cap) {
    for (GcStackRange* range = g_gc_heap.stacks; range; range = range->prev) {
        if (!range->base || range->slots == 0) {
            continue;
        }
        uint64_t* end = range->base + range->slots;
        for (uint64_t* p = range->base; p < end; p++) {
            uint64_t val = *p;
            if (gc_is_ptr(val)) {
                gc_mark_object((GcHeader*)val, stack, top, cap);
            }
        }
    }

    if (g_gc_heap.globals && g_gc_heap.num_globals > 0) {
        for (int i = 0; i < g_gc_heap.num_globals; i++) {
            uint64_t val = g_gc_heap.globals[i];
            if (gc_is_ptr(val)) {
                gc_mark_object((GcHeader*)val, stack, top, cap);
            }
        }
    }
}

static void gc_sweep(void) {
    GcHeader** cur = &g_gc_heap.all_objects;
    while (*cur) {
        GcHeader* obj = *cur;
        if (obj->mark) {
            obj->mark = 0;
            if (obj->age < 255) {
                obj->age++;
            }
            cur = &obj->gc_next;
        } else {
            *cur = obj->gc_next;
            g_gc_heap.num_objects--;
            ptrset_remove(&g_gc_heap.ptrs, (uintptr_t)obj);
            free(obj);
        }
    }
}

void gc_collect(void) {
    if (!g_gc_heap.initialized || g_gc_heap.disable_collect) {
        return;
    }
    if (g_gc_heap.num_objects == 0) {
        g_gc_heap.alloc_since_gc = 0;
        return;
    }

    size_t cap = g_gc_heap.num_objects;
    GcHeader** stack = (GcHeader**)malloc(sizeof(GcHeader*) * cap);
    if (!stack) {
        return;
    }
    size_t top = 0;

    gc_mark_roots(stack, &top, cap);
    if (top < cap) {
        gc_sweep();
    }

    free(stack);

    g_gc_heap.alloc_since_gc = 0;
    if (g_gc_heap.num_objects > g_gc_heap.collect_threshold / 2) {
        g_gc_heap.collect_threshold *= 2;
    }
}
