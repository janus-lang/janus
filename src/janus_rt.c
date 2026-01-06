// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Minimal Viable Runtime (MVR)
// The "First Breath" - Allows LLVM IR to communicate with the host OS.
//
// This is a TEMPORARY shim. In future releases, we will replace libc
// with our own syscall layer for maximum sovereignty.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// String API
int janus_string_len(const char* str) {
    if (!str) return 0;
    return (int)strlen(str);
}

char* janus_string_concat(const char* s1, const char* s2) {
    if (!s1) s1 = "";
    if (!s2) s2 = "";
    
    size_t len1 = strlen(s1);
    size_t len2 = strlen(s2);
    
    char* result = (char*)malloc(len1 + len2 + 1);
    // In MVR we don't handle OOM explicitly yet
    
    strcpy(result, s1);
    strcat(result, s2);
    
    return result;
}

// Exposed symbol for LLVM to call.
// Function signature matches the expected Janus 'print(string)' lowering.
// For :min 0.2.0, we assume string is a raw pointer (i8*).
//
// IMPORTANT: This function MUST match the signature declared in LLVM IR:
//   declare void @janus_print(ptr)
//
// In LLVM 18+, 'i8*' is represented as 'ptr' (op// Basic string printing
void janus_print(const char *str) {
    if (str) {
        printf("%s", str);
    } else {
        printf("(null)");
    }
}

void janus_println(const char *str) {
    if (str) {
        printf("%s\n", str);
    } else {
        printf("(null)\n");
    }
}

// Panic (runtime error)
void janus_panic(const char* msg) {
    if (msg) {
        fprintf(stderr, "PANIC: %s\n", msg);
    } else {
        fprintf(stderr, "PANIC: <unknown>\n");
    }
    exit(1);
}

// Integer printing (i32)
void janus_print_int(int val) {
    printf("%d\n", val);
}

// --- Allocator Interface ---

typedef struct JanusAllocatorVTable {
    void* (*alloc)(void* ctx, size_t size);
    void (*free)(void* ctx, void* ptr);
} JanusAllocatorVTable;

typedef struct JanusAllocator {
    void* ctx;
    const JanusAllocatorVTable* vtable;
} JanusAllocator;

// Default Allocator Implementation (Malloc wrapper)
void* janus_malloc_alloc(void* ctx, size_t size) {
    (void)ctx;
    return malloc(size);
}

void janus_malloc_free(void* ctx, void* ptr) {
    (void)ctx;
    free(ptr);
}

const JanusAllocatorVTable CACHED_MALLOC_VTABLE = {
    .alloc = janus_malloc_alloc,
    .free = janus_malloc_free
};

static JanusAllocator DEFAULT_ALLOCATOR = {
    .ctx = NULL,
    .vtable = &CACHED_MALLOC_VTABLE
};

// Expose default allocator to Janus
JanusAllocator* janus_default_allocator() {
    return &DEFAULT_ALLOCATOR;
}

// Array creation
// Now requires a valid Allocator handle
void* std_array_create(size_t size, JanusAllocator* allocator) {
    if (!allocator || !allocator->vtable || !allocator->vtable->alloc) {
        janus_panic("std_array_create called with invalid allocator");
        return NULL;
    }
    
    // Allocate array memory: size * 4 (assume i32 elements for MVR)
    // Note: This logic assumes i32. In future, element size must be passed.
    return allocator->vtable->alloc(allocator->ctx, size * 4);
}
