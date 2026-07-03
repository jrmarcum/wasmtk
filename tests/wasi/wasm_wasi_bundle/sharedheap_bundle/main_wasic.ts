// Phase 18.5 stress test — main app for shared-heap allocator unification
//
// Calls both library A and library B. Each library compiles its own bump-
// allocator-using helper internally via `.push()`. With unification, both
// calls go through the master module's `$__malloc` over the shared
// `$__heap_ptr`. Test passes if both library calls return the expected
// length and the program exits cleanly — proving no out-of-bounds memory
// access from overlapping private heaps.

type i32 = number;

import { makeBufferA } from "./lib_a_modc.wasm";
import { makeBufferB } from "./lib_b_modc.wasm";

const SIZE: i32 = 4;

const lenA: i32 = makeBufferA(SIZE);
const lenB: i32 = makeBufferB(SIZE);

console.log("lenA:", lenA);
console.log("lenB:", lenB);
