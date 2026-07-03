// Phase 18.5 stress test — library A (compiled via modc)
//
// Allocates a dynamic i32[] at runtime via push() and returns its length.
// The whole point is the runtime push(): each call to the wasic-emitted
// `$__dynarr_push_i32` helper inside this library calls `$__malloc`, which
// — after allocator unification in wasmmerge — resolves to the main
// module's shared `$__malloc`.
//
// Before the unification pass, the library shipped its own `$__malloc` and
// `$__heap_ptr`. With two such libraries merged, both private heap pointers
// were seeded at the page-2 boundary (131072) and handed out overlapping
// addresses on the first allocation.

type i32 = number;

/** @export */
export function makeBufferA(size: i32): i32 {
  const buf: i32[] = [];
  let i: i32 = 0;
  while (i < size) {
    buf.push(0xAA + i);
    i = i + 1;
  }
  return buf.length;
}
