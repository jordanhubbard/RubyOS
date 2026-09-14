/*
 * malloc.c — Buddy allocator for CPython's bare-metal heap.
 *
 * Uses a static 512 MiB region linked into the kernel BSS. QEMU boots with
 * much more RAM than the early allocator originally used, and CPython's
 * free-threaded/mimalloc build needs a larger C heap during initialization.
 * Orders cover 32 bytes to 512 MiB in powers of two.
 * Protected by a spinlock so native AP workers and future pthreads can share
 * the C heap safely.
 *
 * Layout of each block:
 *   [block_header_t | .... user data .... ]
 *   header is 16 bytes, so minimum allocation = 32 bytes (order 0).
 */

#include "include/libc.h"
#include "include/spinlock.h"
#include <stdint.h>
#include <stddef.h>

#define HEAP_SIZE   (128 * 1024 * 1024)   // 128 MiB
#define MIN_ORDER   5                      // 2^5  = 32 bytes (includes header)
#define MAX_ORDER   27                     // 2^27 = 128 MiB
#define NUM_ORDERS  (MAX_ORDER - MIN_ORDER + 1)
#define MIN_BLOCK   (1u << MIN_ORDER)
#define MAGIC_FREE  0xFEEBDAED
#define MAGIC_USED  0xC0FFEEEE
#define MAGIC_ALIGNED UINT64_C(0x52554259414c4947)

// The heap region — in BSS so it doesn't bloat the ELF
static __attribute__((aligned(MIN_BLOCK)))
       char _heap[HEAP_SIZE];

typedef struct block_header {
    uint32_t magic;
    uint32_t order;          // 2^order = total block size (bytes)
    struct block_header *prev_free;
    struct block_header *next_free;
    uint64_t reserved;       // Keep returned storage 16-byte aligned on ARM64.
} block_header_t;

#define HEADER_SIZE  sizeof(block_header_t)
_Static_assert(HEADER_SIZE % 16 == 0, "malloc payload must be 16-byte aligned");

// Free lists — one per order
static block_header_t *free_lists[NUM_ORDERS];
static int heap_initialized = 0;
static spinlock_t heap_lock = SPINLOCK_INITIALIZER;

static inline int order_of(size_t size) {
    size_t s = size + HEADER_SIZE;
    int order = MIN_ORDER;
    while ((1u << order) < s && order <= MAX_ORDER)
        order++;
    return order;
}

static inline block_header_t *buddy_of(block_header_t *blk, int order) {
    uintptr_t offset = (uintptr_t)blk - (uintptr_t)_heap;
    uintptr_t buddy_offset = offset ^ (1u << order);
    if (buddy_offset >= HEAP_SIZE) return NULL;
    return (block_header_t *)(_heap + buddy_offset);
}

static void free_list_add(block_header_t *blk, int order) {
    int idx = order - MIN_ORDER;
    blk->prev_free = NULL;
    blk->next_free = free_lists[idx];
    if (free_lists[idx])
        free_lists[idx]->prev_free = blk;
    free_lists[idx] = blk;
}

static void free_list_remove(block_header_t *blk, int order) {
    int idx = order - MIN_ORDER;
    if (blk->prev_free)
        blk->prev_free->next_free = blk->next_free;
    else
        free_lists[idx] = blk->next_free;
    if (blk->next_free)
        blk->next_free->prev_free = blk->prev_free;
    blk->prev_free = blk->next_free = NULL;
}

static void heap_init(void) {
    // Mark entire heap as one MAX_ORDER free block
    for (int i = 0; i < NUM_ORDERS; i++)
        free_lists[i] = NULL;

    block_header_t *root = (block_header_t *)_heap;
    root->magic     = MAGIC_FREE;
    root->order     = MAX_ORDER;
    root->prev_free = NULL;
    root->next_free = NULL;
    free_lists[NUM_ORDERS - 1] = root;
    heap_initialized = 1;
}

void *malloc(size_t size) {
    spin_lock(&heap_lock);
    if (!heap_initialized) heap_init();
    if (size == 0) {
        spin_unlock(&heap_lock);
        return NULL;
    }

    int need = order_of(size);
    if (need > MAX_ORDER) {
        spin_unlock(&heap_lock);
        return NULL;
    }

    // Find a free block of sufficient order
    int found = -1;
    for (int o = need; o <= MAX_ORDER; o++) {
        if (free_lists[o - MIN_ORDER]) { found = o; break; }
    }
    if (found < 0) {
        spin_unlock(&heap_lock);
        return NULL;   // out of memory
    }

    // Split down to the required order
    block_header_t *blk = free_lists[found - MIN_ORDER];
    free_list_remove(blk, found);

    while (found > need) {
        found--;
        // Split: upper half becomes a free buddy
        block_header_t *buddy = (block_header_t *)((char *)blk + (1u << found));
        buddy->magic     = MAGIC_FREE;
        buddy->order     = found;
        buddy->prev_free = buddy->next_free = NULL;
        free_list_add(buddy, found);
    }

    blk->magic = MAGIC_USED;
    blk->order = need;
    void *ptr = (void *)((char *)blk + HEADER_SIZE);
    spin_unlock(&heap_lock);
    return ptr;
}

#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
#endif
void free(void *ptr) {
    if (!ptr) return;
    spin_lock(&heap_lock);

    block_header_t *blk = (block_header_t *)((char *)ptr - HEADER_SIZE);
    if (blk->magic != MAGIC_USED) {
        typedef struct { uint64_t magic; void *raw; } aligned_header_t;
        aligned_header_t *aligned = (aligned_header_t *)ptr - 1;
        if (aligned->magic == MAGIC_ALIGNED) {
            ptr = aligned->raw;
            blk = (block_header_t *)((char *)ptr - HEADER_SIZE);
        }
    }
    if (blk->magic != MAGIC_USED) {
        spin_unlock(&heap_lock);
        return;   // double-free or corruption
    }
    blk->magic = MAGIC_FREE;

    int order = blk->order;

    // Coalesce with buddy while possible
    while (order < MAX_ORDER) {
        block_header_t *buddy = buddy_of(blk, order);
        if (!buddy || buddy->magic != MAGIC_FREE || (int)buddy->order != order)
            break;
        free_list_remove(buddy, order);
        // Lower address becomes the merged block
        if ((uintptr_t)buddy < (uintptr_t)blk) blk = buddy;
        order++;
        blk->order = order;
    }

    blk->magic = MAGIC_FREE;
    free_list_add(blk, order);
    spin_unlock(&heap_lock);
}
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

void *calloc(size_t n, size_t size) {
    size_t total = n * size;
    void *ptr = malloc(total);
    if (ptr) memset(ptr, 0, total);
    return ptr;
}

void *realloc(void *ptr, size_t size) {
    if (!ptr)  return malloc(size);
    if (!size) { free(ptr); return NULL; }

    block_header_t *hdr  = (block_header_t *)((char *)ptr - HEADER_SIZE);
    size_t old_usable = (1u << hdr->order) - HEADER_SIZE;

    if (size <= old_usable) return ptr;   // fits in current block

    void *new_ptr = malloc(size);
    if (!new_ptr) return NULL;
    memcpy(new_ptr, ptr, old_usable);
    free(ptr);
    return new_ptr;
}

void *aligned_alloc(size_t alignment, size_t size) {
    // For reasonable alignments (<= MIN_BLOCK) our allocator is already aligned.
    // Larger alignments require over-allocation + manual alignment.
    if (alignment <= MIN_BLOCK)
        return malloc(size);

    typedef struct { uint64_t magic; void *raw; } aligned_header_t;
    void *raw = malloc(size + alignment - 1 + sizeof(aligned_header_t));
    if (!raw) return NULL;
    uintptr_t addr = ((uintptr_t)raw + sizeof(aligned_header_t) + alignment - 1) & ~(alignment - 1);
    aligned_header_t *header = (aligned_header_t *)addr - 1;
    header->magic = MAGIC_ALIGNED;
    header->raw = raw;
    return (void *)addr;
}

// Statistics (useful for the kernel shell)
size_t malloc_free_bytes(void) {
    spin_lock(&heap_lock);
    if (!heap_initialized) heap_init();
    size_t total = 0;
    for (int o = MIN_ORDER; o <= MAX_ORDER; o++) {
        block_header_t *b = free_lists[o - MIN_ORDER];
        while (b) { total += (1u << o); b = b->next_free; }
    }
    spin_unlock(&heap_lock);
    return total;
}

size_t malloc_total_bytes(void) {
    return HEAP_SIZE;
}
