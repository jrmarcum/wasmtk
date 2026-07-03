// GC Part 2 — free-list allocator: __free returns a block to the free list, __malloc first-fits it
// before bumping. Verifies a freed block is reused (and the bump cursor doesn't advance).
type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

const p1: i32 = __malloc(64);
const p2: i32 = __malloc(64);
const afterAlloc: i32 = __heapPtr();
check(p1 !== p2 ? 1 : 0);

// free p1, then allocate 64 again -> must reuse p1, no heap growth
__free(p1, 64);
const p3: i32 = __malloc(64);
check(p3 === p1 ? 1 : 0);
check(__heapPtr() === afterAlloc ? 1 : 0);

// free p3, allocate a SMALLER request -> 64-byte block still fits, reused
__free(p3, 64);
const p4: i32 = __malloc(32);
check(p4 === p3 ? 1 : 0);

// with the free list empty, a fresh allocation bumps (heap grows)
const p5: i32 = __malloc(48);
check(p5 !== p4 ? 1 : 0);
check(__heapPtr() > afterAlloc ? 1 : 0);

console.log("GC Part2 free-list: reuse verified");
