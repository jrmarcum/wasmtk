// Shared-heap driver for the Map<i32, i32> stdlib capability (brief §5/§7-#3).
//
// Imports the modc-compiled Map library. After the Phase 18 merge + Stage 0.6 allocator
// unification, every $__malloc inside the Map library resolves to THIS module's bump
// cursor, so the hash table the library builds lives on the same heap this program uses
// for its own allocations — the headline "live values shared across merged units" case.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far
// out of bounds, trapping the module so the `run` step exits non-zero and the test fails.
// (A wasic uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)

type i32 = number;

import { mapNew, mapSet, mapGet, mapHas, mapSize } from "./map_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    // Force a WebAssembly trap (memory access out of bounds) → nonzero exit.
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

const m: i32 = mapNew();

// Basic insert + value retrieval.
mapSet(m, 10, 100);
mapSet(m, 20, 200);
mapSet(m, 30, 300);
console.log("size:", mapSize(m));
check(mapSize(m) === 3 ? 1 : 0);
console.log("get 20:", mapGet(m, 20, -1));
check(mapGet(m, 20, -1) === 200 ? 1 : 0);

// Update an existing key — count stays the same, value changes.
mapSet(m, 20, 222);
check(mapSize(m) === 3 ? 1 : 0);
check(mapGet(m, 20, -1) === 222 ? 1 : 0);
console.log("get 20 after update:", mapGet(m, 20, -1));

// Membership + fallback on absent key.
console.log("has 30:", mapHas(m, 30));
console.log("has 99:", mapHas(m, 99));
check(mapHas(m, 30));
check(mapHas(m, 99) === 0 ? 1 : 0);
check(mapGet(m, 99, -7) === -7 ? 1 : 0);

// Force multiple grows / rehashes (8 -> 16 -> 32 -> 64 ...), value = key * 2.
let i: i32 = 100;
while (i < 140) {
  mapSet(m, i, i * 2);
  i = i + 1;
}
console.log("size after grow:", mapSize(m));
check(mapSize(m) === 43 ? 1 : 0); // 3 originals + 40 new

// Values survive rehash with the correct key association.
check(mapGet(m, 10, -1) === 100 ? 1 : 0);   // original survived the grows
check(mapGet(m, 137, -1) === 274 ? 1 : 0);  // added during grow window, 137*2
check(mapGet(m, 20, -1) === 222 ? 1 : 0);   // updated value survived too
check(mapHas(m, 200) === 0 ? 1 : 0);

// Negative key.
mapSet(m, -5, -50);
mapSet(m, -5, -55); // update negative
check(mapGet(m, -5, 0) === -55 ? 1 : 0);
check(mapSize(m) === 44 ? 1 : 0);

console.log("get -5:", mapGet(m, -5, 0));
console.log("final size:", mapSize(m));
console.log("map ok");
