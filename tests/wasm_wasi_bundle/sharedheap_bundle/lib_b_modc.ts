// Phase 18.5 stress test — library B (compiled via modc)
//
// Mirror image of lib_a_modc.ts with a different tag pattern. Together with
// library A this exercises the allocator-unification path — both `$__malloc`
// call sites inside the merged binary resolve to the master module's shared
// bump cursor.

type i32 = number;

/** @export */
export function makeBufferB(size: i32): i32 {
  const buf: i32[] = [];
  let i: i32 = 0;
  while (i < size) {
    buf.push(0xBB + i);
    i = i + 1;
  }
  return buf.length;
}
