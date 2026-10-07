#include <stdlib.h>
#include <stdatomic.h>
#include <pthread.h>
static _Atomic unsigned long allocations = 0;
static _Atomic int enabled = 0;
static _Atomic(pthread_t) owner;
// Count only the render/test thread; unrelated engine initialization is excluded.
static int counting(void) { return enabled && pthread_equal(pthread_self(), owner); }
void reset_allocations(void) { enabled = 0; owner = pthread_self(); allocations = 0; enabled = 1; }
unsigned long stop_allocations(void) { enabled = 0; return allocations; }
static void *count_malloc(size_t n) { if(counting()) allocations++; return malloc(n); }
static void *count_calloc(size_t n, size_t s) { if(counting()) allocations++; return calloc(n,s); }
static void *count_realloc(void *p, size_t n) { if(counting()) allocations++; return realloc(p,n); }
static int count_memalign(void **p,size_t a,size_t s) { if(counting()) allocations++; return posix_memalign(p,a,s); }
#define INTERPOSE(replacement, original) \
__attribute__((used)) static struct {const void *new_fn; const void *old_fn;} pair_##original \
__attribute__((section("__DATA,__interpose"))) = {(const void *)replacement,(const void *)original};
INTERPOSE(count_malloc,malloc)
INTERPOSE(count_calloc,calloc)
INTERPOSE(count_realloc,realloc)
INTERPOSE(count_memalign,posix_memalign)
void use_pointer(void *pointer) { __asm__ volatile("" : : "r"(pointer) : "memory"); }
