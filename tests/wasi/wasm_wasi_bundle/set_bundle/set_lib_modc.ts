// Tier-1 stdlib capability — Set<i32> (open-addressing hash table) as a modc library.
//
// Part of the on-demand stdlib bundling track (wasmtk-stdlib-bundling-brief §5/§7-#3).
// Compiled with `wasmtk modc` (no _start / no WASI); a wasic program imports the exports
// and the wasmmerge allocator-unification pass (Stage 0.6) makes every $__malloc here
// resolve to the host module's shared bump cursor, so the Set lives on one shared heap.
//
// A "set handle" is an i32 pointer to a 4-slot Int32Array header:
//   [0] count    — number of distinct keys
//   [1] cap       — bucket capacity (power of two)
//   [2] keysPtr   — pointer to an Int32Array(cap) of bucket keys
//   [3] usedPtr   — pointer to an Int32Array(cap) of 0/1 occupancy flags
// Buckets use linear probing; the bucket index is `key & (cap - 1)`. Fresh bump-allocated
// memory is zero, so the `used` array starts all-empty without explicit zeroing.
//
// The Int32Array-view-over-pointer idiom (`ptr as unknown as Int32Array`) requires the
// wasic TypedArray-view-registration fix and the type-erasure-cast fix (both 2026-05-30).

type i32 = number;

const INITIAL_CAP: i32 = 8;

/** Allocate a zeroed Int32Array of `n` slots and return its base pointer. */
function allocSlots(n: i32): i32 {
  const a: Int32Array = new Int32Array(n);
  return a as unknown as i32;
}

/** Create an empty set; returns the handle (header pointer). */
/** @export */
export function setNew(): i32 {
  const header: Int32Array = new Int32Array(4);
  header[0] = 0;                       // count
  header[1] = INITIAL_CAP;             // cap
  header[2] = allocSlots(INITIAL_CAP); // keysPtr
  header[3] = allocSlots(INITIAL_CAP); // usedPtr
  return header as unknown as i32;
}

/** Double capacity and rehash every occupied bucket. The handle is unchanged. */
function setGrow(h: i32): void {
  const header: Int32Array = h as unknown as Int32Array;
  const oldCap: i32 = header[1];
  const oldKeys: Int32Array = header[2] as unknown as Int32Array;
  const oldUsed: Int32Array = header[3] as unknown as Int32Array;

  const newCap: i32 = oldCap * 2;
  const newKeysPtr: i32 = allocSlots(newCap);
  const newUsedPtr: i32 = allocSlots(newCap);
  const newKeys: Int32Array = newKeysPtr as unknown as Int32Array;
  const newUsed: Int32Array = newUsedPtr as unknown as Int32Array;

  const mask: i32 = newCap - 1;
  let i: i32 = 0;
  while (i < oldCap) {
    if (oldUsed[i] !== 0) {
      const k: i32 = oldKeys[i];
      let idx: i32 = k & mask;
      while (newUsed[idx] !== 0) {
        idx = (idx + 1) & mask;
      }
      newKeys[idx] = k;
      newUsed[idx] = 1;
    }
    i = i + 1;
  }

  header[1] = newCap;
  header[2] = newKeysPtr;
  header[3] = newUsedPtr;
}

/** Add `key` to the set (no-op if already present). */
/** @export */
export function setAdd(h: i32, key: i32): void {
  const pre: Int32Array = h as unknown as Int32Array;
  // Keep load factor below 0.5 so linear probing stays cheap.
  if ((pre[0] + 1) * 2 > pre[1]) {
    setGrow(h);
  }
  const header: Int32Array = h as unknown as Int32Array;
  const cap: i32 = header[1];
  const keys: Int32Array = header[2] as unknown as Int32Array;
  const used: Int32Array = header[3] as unknown as Int32Array;
  const mask: i32 = cap - 1;

  let idx: i32 = key & mask;
  while (used[idx] !== 0) {
    if (keys[idx] === key) {
      return; // already present
    }
    idx = (idx + 1) & mask;
  }
  keys[idx] = key;
  used[idx] = 1;
  header[0] = header[0] + 1;
}

/** Return 1 if `key` is in the set, else 0. */
/** @export */
export function setHas(h: i32, key: i32): i32 {
  const header: Int32Array = h as unknown as Int32Array;
  const cap: i32 = header[1];
  const keys: Int32Array = header[2] as unknown as Int32Array;
  const used: Int32Array = header[3] as unknown as Int32Array;
  const mask: i32 = cap - 1;

  let idx: i32 = key & mask;
  while (used[idx] !== 0) {
    if (keys[idx] === key) {
      return 1;
    }
    idx = (idx + 1) & mask;
  }
  return 0;
}

/** Number of distinct keys in the set. */
/** @export */
export function setSize(h: i32): i32 {
  const header: Int32Array = h as unknown as Int32Array;
  return header[0];
}
