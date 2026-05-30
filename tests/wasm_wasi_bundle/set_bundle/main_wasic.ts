// Shared-heap driver for the Set<i32> stdlib capability (brief §5/§7-#3).
//
// Imports the modc-compiled Set library. After the Phase 18 merge + Stage 0.6 allocator
// unification, every $__malloc inside the Set library resolves to THIS module's bump
// cursor, so the hash table the library builds lives on the same heap this program uses
// for its own allocations — the headline "live values shared across merged units" case.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far
// out of bounds, trapping the module so the `run` step exits non-zero and the test fails.
// (A wasic uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)

type i32 = number;

import { setNew, setAdd, setHas, setSize } from "./set_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    // Force a WebAssembly trap (memory access out of bounds) → nonzero exit.
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

const s: i32 = setNew();

// Basic insert + dedup.
setAdd(s, 10);
setAdd(s, 20);
setAdd(s, 30);
setAdd(s, 20); // duplicate
setAdd(s, 10); // duplicate
console.log("size:", setSize(s));
check(setSize(s) === 3 ? 1 : 0);

// Membership.
console.log("has 20:", setHas(s, 20));
console.log("has 99:", setHas(s, 99));
check(setHas(s, 20));
check(setHas(s, 99) === 0 ? 1 : 0);

// Force multiple grows / rehashes (8 -> 16 -> 32 -> 64 ...).
let i: i32 = 100;
while (i < 140) {
  setAdd(s, i);
  i = i + 1;
}
console.log("size after grow:", setSize(s));
check(setSize(s) === 43 ? 1 : 0); // 3 originals + 40 new

// Survivors after rehash + new members + a negative key.
check(setHas(s, 10));  // original survived the grows
check(setHas(s, 137)); // added during grow window
check(setHas(s, 200) === 0 ? 1 : 0);

setAdd(s, -5);
setAdd(s, -5); // dup negative
check(setHas(s, -5));
check(setSize(s) === 44 ? 1 : 0);

console.log("has -5:", setHas(s, -5));
console.log("final size:", setSize(s));
console.log("set ok");
