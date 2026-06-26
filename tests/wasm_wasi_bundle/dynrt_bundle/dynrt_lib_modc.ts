// wasmtk own dynamic runtime — #14, increment 1: the boxed-value + dynamic-object model.
//
// DECISION TRACE (roadmap §7-#7 / cmem/dynrt-design.md): wasmtk ships its OWN dynamic runtime
// (boxed values + property map + — later — an interpreter) rather than depending on javyc/QuickJS.
// This first increment delivers ONLY the value + object substrate that everything else lowers onto;
// there is no `eval`/interpreter and no prototype mutation yet. It is authored in the SAME wasic TS
// subset as the Tier-1 caps (Set/Map/Date/JSON/RegExp), so the allocator, strings, dynamic arrays
// and number formatting all come from wasic's own codegen for free — zero duplication (a shared
// `rtcore` + hand-WAT is the chosen path only when the interpreter increment needs it).
//
// Compiled with `wasmtk modc` (no _start / no WASI). A driver/host imports the exports and the
// wasmmerge allocator-unification pass (Stage 0.6) makes every $__malloc here resolve to the host
// module's shared bump cursor, so boxed values live on the ONE heap shared with the program.
//
// THE BOXED VALUE  (value = i32 handle = base pointer of a 4-slot Int32Array node)
// --------------------------------------------------------------------------------
//   node[0] tag : 0=undefined 1=null 2=boolean 3=number 4=string 5=array 6=object
//   node[1] a   : bool→0/1 · number→ptr to Float64Array(1) · string→Uint8Array byte buffer ptr ·
//                 array→i32[] of value handles · object→i32[] of value handles
//   node[2] b   : string→byte length (numbers/arrays/objects read their length LIVE, see below)
//   node[3] c   : object→i32[] of interleaved [keyPtr, keyLen] pairs (length = 2 * entryCount)
//
// Containers (array elems, object vals, object keys) reuse wasic's native dynamic `i32[]`: stored
// by pointer (`arr as unknown as i32`) and reconstructed for access (`ptr as unknown as i32[]`).
// Because `.push` can GROW (reallocate) the backing array, every mutator writes the (possibly new)
// pointer back into the owning node — the one structural difference from the immutable JSON tree.
//
// SCOPE (v1): undefined / null / boolean / number (real f64) / string / array / object; the dynamic
// operators `typeof`, `===` (dynStrictEq) and `+` (dynAdd — numeric add + string concat). Functions
// (tag 7), `eval`/`new Function`, prototype mutation, and string→number coercion are later
// increments. Strings are UTF-16-code-unit / ASCII-accurate (multi-byte is the documented gap, as
// elsewhere in wasic). Absent object keys return the sentinel -1 (the future wasic `any` lowering
// maps that to `undefined`).

type i32 = number;
type f64 = number;

// #14 Phase 2 (host→core callbacks): the ONE host import. When a host passes a JS function into the
// core as `any`, bindgen boxes it as a tag-7 cell with marker slot[1] = -2 and slot[2] = a host
// function-table index (see `dynMakeHostFn`); `dynApply` then calls back into the host through this
// import. Maps to `(import "env" "__host_call" (func (param i32 i32) (result i32)))`, preserved
// through the wasmmerge; the test runner stubs it (returns 0) and bindgen provides the real impl.
declare const __host: { call(fnIndex: i32, argsArr: i32): i32 };

// ── Tag constants (kept as literals at use sites; listed here for reference) ──────────────────
//   0 undefined · 1 null · 2 boolean · 3 number · 4 string · 5 array · 6 object

// ── Constructors ──────────────────────────────────────────────────────────────────────────────

/** The `undefined` value. */
/** @export */
export function dynUndefined(): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 0;
  return n as unknown as i32;
}

/** The `null` value. */
/** @export */
export function dynNull(): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 1;
  return n as unknown as i32;
}

/** A boolean value from 0 (false) / non-zero (true). */
/** @export */
export function dynBool(b: i32): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 2;
  n[1] = b === 0 ? 0 : 1;
  return n as unknown as i32;
}

/** A number value (real f64). */
/** @export */
export function dynNumber(x: f64): i32 {
  const fv: Float64Array = dynAlloc(16) as unknown as Float64Array; // 8 header + 1*8 (GC-recycled)
  fv[0] = x;
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 3;
  n[1] = fv as unknown as i32;
  return n as unknown as i32;
}

/** A string value (bytes copied from the wasic string). */
/** @export */
export function dynString(s: string): i32 {
  const len: i32 = s.length;
  const buf: Uint8Array = dynAlloc(8 + len) as unknown as Uint8Array; // 8 header + len (GC-recycled)
  let i: i32 = 0;
  while (i < len) {
    buf[i] = s.charCodeAt(i);
    i = i + 1;
  }
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 4;
  n[1] = buf as unknown as i32;
  n[2] = len;
  return n as unknown as i32;
}

// ── Self-managed growable i32 list (Set/Map idiom) ────────────────────────────────────────────
// A "list" is an Int32Array laid out as [len, cap, e0, e1, …]. We manage growth ourselves with a
// guaranteed nonzero starting capacity and correct doubling — wasic's native `[]`-then-`.push`
// path can't be used here: an empty `[]` literal lowers to a SHARED static zero-capacity array
// (every `dynArray()` would alias address 260) and `$__dynarr_push_i32` grows by `cap<<1`, which
// stays 0 from a 0 capacity (see cmem/dynrt-design.md / compiler-bugs.md "empty-array push gap").
const LIST_CAP0: i32 = 4;

function listNew(): i32 {
  const a: Int32Array = dynAlloc(8 + (LIST_CAP0 + 2) * 4) as unknown as Int32Array; // GC-recycled
  a[0] = 0; // len
  a[1] = LIST_CAP0; // cap
  return a as unknown as i32;
}

function listLen(lp: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  return a[0];
}

function listGet(lp: i32, i: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  return a[i + 2];
}

function listSet(lp: i32, i: i32, v: i32): void {
  const a: Int32Array = lp as unknown as Int32Array;
  a[i + 2] = v;
}

// Append; returns the (possibly reallocated) list pointer — caller must write it back.
function listPush(lp: i32, v: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  const len: i32 = a[0];
  const cap: i32 = a[1];
  if (len >= cap) {
    const ncap: i32 = cap * 2;
    const b: Int32Array = dynAlloc(8 + (ncap + 2) * 4) as unknown as Int32Array; // GC-recycled
    b[1] = ncap;
    let i: i32 = 0;
    while (i < len) {
      b[i + 2] = a[i + 2];
      i = i + 1;
    }
    b[len + 2] = v;
    b[0] = len + 1;
    return b as unknown as i32;
  }
  a[len + 2] = v;
  a[0] = len + 1;
  return lp;
}

// ── dynrt's own recycling allocator: HYBRID segregated buckets + batch coalescing (#14 GC track) ──
// Every dynrt allocation is `8 + n*elemSize` bytes (wasic TypedArray layout: 8-byte header then data);
// a value handle / view reads its slots at base+8, and a FREE block stores [size, next] in its first
// two view slots (base+8/+12), so every block is rounded UP to GC_MIN_BLOCK=16. The GC reclaims into
// the SAME pool it allocates from (no wasmmerge `$__free` dependency). Reused blocks are ZEROED
// (constructors rely on unset slots being 0 — e.g. a plain object's slot-2 parent link).
//
// THREE TIERS, balancing speed vs memory:
//  • SEGREGATED BUCKETS for the dominant exact sizes (16 number-payload, 24 4-slot cell, 28 5-slot
//    cell, 32 smallest list) — pure LIFO push/pop, O(1), can NEVER cycle. Number-heavy code lives
//    here and pays nothing.
//  • TIER 2 (`__dyn_free`) general pool for other/odd sizes — LIFO first-fit + split.
//  • BATCH DEFRAG (`defragFull`) — the ONLY place adjacency-coalescing happens: a snapshot pass
//    (gather → address merge-sort → merge adjacent → redistribute), so it never interleaves with
//    allocation (the re-entrancy that made coalesce-on-free cycle). Two triggers: a PROACTIVE
//    adaptive node-count threshold (×2 after each defrag → amortized O(1)/free), and an ON-DEMAND
//    pass gated by `__free_bytes >= request` (recover freed runs for a large request only when it
//    could plausibly help, else bump). See cmem/dynrt-design.md.
const GC_MIN_BLOCK: i32 = 16;
const GC_DEFRAG_BASE: i32 = 512; // proactive-defrag node threshold floor (adaptive ×2 after each pass)
let __bk16: i32 = 0; // segregated bucket heads (exact sizes)
let __bk24: i32 = 0;
let __bk28: i32 = 0;
let __bk32: i32 = 0;
let __dyn_free: i32 = 0; // Tier 2 general pool head
let __free_nodes: i32 = 0; // total free blocks across all lists (drives the proactive defrag)
let __free_bytes: i32 = 0; // total free bytes across all lists (gates the on-demand defrag)
let __defrag_threshold: i32 = 512; // = GC_DEFRAG_BASE (literal init so wasic treats it as mutable)
let __gc_threshold: i32 = 8192; // (unrelated: auto-collect threshold for the interpreter)

// Push a block onto its size-class list; maintains the free counters. No defrag trigger.
function rawPush(ptr: i32, sz: i32): void {
  const b: Int32Array = ptr as unknown as Int32Array;
  b[0] = sz;
  if (sz === 16) {
    b[1] = __bk16;
    __bk16 = ptr;
  } else if (sz === 24) {
    b[1] = __bk24;
    __bk24 = ptr;
  } else if (sz === 28) {
    b[1] = __bk28;
    __bk28 = ptr;
  } else if (sz === 32) {
    b[1] = __bk32;
    __bk32 = ptr;
  } else {
    b[1] = __dyn_free;
    __dyn_free = ptr;
  }
  __free_nodes = __free_nodes + 1;
  __free_bytes = __free_bytes + sz;
}

function dynFreeBlock(ptr: i32, size: i32): void {
  const sz: i32 = size < GC_MIN_BLOCK ? GC_MIN_BLOCK : size;
  rawPush(ptr, sz);
  if (__free_nodes > __defrag_threshold) {
    defragFull();
  }
}

// Zero a block's data region (size-8 bytes) — clears the stale [size,next] header + old contents.
function zeroBlock(ptr: i32, size: i32): void {
  const v: Int32Array = ptr as unknown as Int32Array;
  const words: i32 = (size - 8) >> 2;
  let i: i32 = 0;
  while (i < words) {
    v[i] = 0;
    i = i + 1;
  }
}

// Pop the head of an exact-size bucket, or 0 if empty (zeroed on return).
function bucketPop(size: i32): i32 {
  let head: i32 = 0;
  if (size === 16) head = __bk16;
  else if (size === 24) head = __bk24;
  else if (size === 28) head = __bk28;
  else if (size === 32) head = __bk32;
  if (head === 0) return 0;
  const hn: Int32Array = head as unknown as Int32Array;
  const next: i32 = hn[1];
  if (size === 16) __bk16 = next;
  else if (size === 24) __bk24 = next;
  else if (size === 28) __bk28 = next;
  else __bk32 = next;
  __free_nodes = __free_nodes - 1;
  __free_bytes = __free_bytes - size;
  zeroBlock(head, size);
  return head;
}

// First-fit the Tier 2 general pool for a block >= size, splitting the remainder. 0 if none fit.
function tier2Alloc(size: i32): i32 {
  let cur: i32 = __dyn_free;
  let prev: i32 = 0;
  while (cur !== 0) {
    const cn: Int32Array = cur as unknown as Int32Array;
    const blockSize: i32 = cn[0];
    if (blockSize >= size) {
      const next: i32 = cn[1];
      if (prev === 0) __dyn_free = next;
      else {
        const pn: Int32Array = prev as unknown as Int32Array;
        pn[1] = next;
      }
      __free_nodes = __free_nodes - 1;
      __free_bytes = __free_bytes - blockSize;
      const leftover: i32 = blockSize - size;
      if (leftover >= GC_MIN_BLOCK) {
        rawPush(cur + size, leftover); // recycle the leftover (counters re-incremented inside)
      }
      zeroBlock(cur, size);
      return cur;
    }
    prev = cur;
    cur = cn[1];
  }
  return 0;
}

function dynAlloc(req: i32): i32 {
  const size: i32 = req < GC_MIN_BLOCK ? GC_MIN_BLOCK : req;
  const fromBucket: i32 = bucketPop(size); // 1. exact-size bucket — O(1) hot path
  if (fromBucket !== 0) return fromBucket;
  const fromT2: i32 = tier2Alloc(size); // 2. Tier 2 first-fit + split
  if (fromT2 !== 0) return fromT2;
  if (__free_bytes >= size) { // 3. on-demand defrag — only if it could plausibly serve the request
    defragFull();
    const b2: i32 = bucketPop(size);
    if (b2 !== 0) return b2;
    const t2b: i32 = tier2Alloc(size);
    if (t2b !== 0) return t2b;
  }
  return __malloc(size); // 4. fresh bump (already-zero memory)
}

// ── Batch defrag (the only coalescing site) ───────────────────────────────────────────────────
// Cut a free-list into two halves (slow/fast walk); returns the 2nd half, terminates the 1st.
function listSplitHalf(head: i32): i32 {
  let slow: i32 = head;
  const h0: Int32Array = head as unknown as Int32Array;
  let fast: i32 = h0[1];
  while (fast !== 0) {
    const fn: Int32Array = fast as unknown as Int32Array;
    fast = fn[1];
    if (fast !== 0) {
      const sn: Int32Array = slow as unknown as Int32Array;
      slow = sn[1];
      const fn2: Int32Array = fast as unknown as Int32Array;
      fast = fn2[1];
    }
  }
  const sn2: Int32Array = slow as unknown as Int32Array;
  const mid: i32 = sn2[1];
  sn2[1] = 0;
  return mid;
}

// Iterative merge of two ascending-address free-lists (O(1) stack).
function listMergeAddr(a: i32, b: i32): i32 {
  let head: i32 = 0;
  let tail: i32 = 0;
  while (a !== 0 && b !== 0) {
    let pick: i32 = 0;
    if (a < b) {
      pick = a;
      const an: Int32Array = a as unknown as Int32Array;
      a = an[1];
    } else {
      pick = b;
      const bn: Int32Array = b as unknown as Int32Array;
      b = bn[1];
    }
    if (head === 0) {
      head = pick;
      tail = pick;
    } else {
      const tn: Int32Array = tail as unknown as Int32Array;
      tn[1] = pick;
      tail = pick;
    }
  }
  let rest: i32 = a;
  if (a === 0) rest = b;
  if (head === 0) return rest;
  const tn2: Int32Array = tail as unknown as Int32Array;
  tn2[1] = rest;
  return head;
}

// Merge-sort a free-list by ascending block address (O(n log n), O(log n) stack).
function mergeSortAddr(head: i32): i32 {
  if (head === 0) return 0;
  const hn: Int32Array = head as unknown as Int32Array;
  if (hn[1] === 0) return head;
  const mid: i32 = listSplitHalf(head);
  const left: i32 = mergeSortAddr(head);
  const right: i32 = mergeSortAddr(mid);
  return listMergeAddr(left, right);
}

// Move every node of the list at `head` onto the front of `acc`; returns the new `acc`.
function drainOnto(head: i32, acc: i32): i32 {
  let c: i32 = head;
  let a: i32 = acc;
  while (c !== 0) {
    const cn: Int32Array = c as unknown as Int32Array;
    const nx: i32 = cn[1];
    cn[1] = a;
    a = c;
    c = nx;
  }
  return a;
}

// Gather ALL free blocks, address-sort, merge physically-adjacent blocks, redistribute. A pure batch
// pass (snapshot → process), so it never interleaves with allocation — the failure mode that made
// coalesce-on-free cycle. Resets the adaptive threshold to ~2× the surviving node count.
function defragFull(): void {
  let all: i32 = 0;
  all = drainOnto(__bk16, all);
  all = drainOnto(__bk24, all);
  all = drainOnto(__bk28, all);
  all = drainOnto(__bk32, all);
  all = drainOnto(__dyn_free, all);
  __bk16 = 0;
  __bk24 = 0;
  __bk28 = 0;
  __bk32 = 0;
  __dyn_free = 0;
  __free_nodes = 0;
  __free_bytes = 0;
  all = mergeSortAddr(all);
  // merge adjacent: absorb every run of blocks where p's end === the next block's start
  let p: i32 = all;
  while (p !== 0) {
    const pn: Int32Array = p as unknown as Int32Array;
    let q: i32 = pn[1];
    let go: i32 = 1;
    while (go === 1 && q !== 0) {
      const qn: Int32Array = q as unknown as Int32Array;
      if (p + pn[0] === q) {
        pn[0] = pn[0] + qn[0];
        pn[1] = qn[1];
        q = pn[1];
      } else {
        go = 0;
      }
    }
    p = pn[1];
  }
  // redistribute (rawPush routes each block to its bucket / Tier 2 and rebuilds the counters)
  let r: i32 = all;
  while (r !== 0) {
    const rn: Int32Array = r as unknown as Int32Array;
    const rnext: i32 = rn[1];
    const rsz: i32 = rn[0];
    rawPush(r, rsz);
    r = rnext;
  }
  let nt: i32 = __free_nodes * 2;
  if (nt < GC_DEFRAG_BASE) {
    nt = GC_DEFRAG_BASE;
  }
  __defrag_threshold = nt;
}

/**
 * Free-list integrity check (dev/test hook). Walks all five lists with a cycle guard and verifies
 * every block is >= 16 bytes and the node/byte counters match the actual contents. Returns 0 = OK,
 * 1 = cycle, 2 = node-count mismatch, 3 = byte-count mismatch, 4 = undersized block.
 */
/** @export */
export function dynGcCheckHeap(): i32 {
  let nodes: i32 = 0;
  let bytes: i32 = 0;
  let cap: i32 = 100000000; // cycle guard
  let li: i32 = 0;
  while (li < 5) {
    let c: i32 = 0;
    if (li === 0) c = __bk16;
    else if (li === 1) c = __bk24;
    else if (li === 2) c = __bk28;
    else if (li === 3) c = __bk32;
    else c = __dyn_free;
    while (c !== 0) {
      if (cap <= 0) return 1;
      cap = cap - 1;
      const cn: Int32Array = c as unknown as Int32Array;
      if (cn[0] < GC_MIN_BLOCK) return 4;
      bytes = bytes + cn[0];
      nodes = nodes + 1;
      c = cn[1];
    }
    li = li + 1;
  }
  if (nodes !== __free_nodes) return 2;
  if (bytes !== __free_bytes) return 3;
  return 0;
}

// ── GC cell registry (#14 GC track, Part 3) ───────────────────────────────────────────────────
// Every boxed VALUE cell (the 4-slot [tag,a,b,c] nodes + the 5-slot user-function cell) is recorded
// in a registry list so a future mark-sweep (P4 mark / P5 sweep) can ENUMERATE all live allocations
// and reclaim the unmarked ones. Only value cells are registered — their payloads (Float64Array /
// Uint8Array / the container lists) are owned by a cell and reached THROUGH it, so the sweep will
// free them by reading the cell's fields (no separate registry entry). The registry list itself is
// allocated via listNew (NOT mkCell), so it never registers itself and is never collected.
let __gc_reg: i32 = 0; // registry list ptr (0 = not yet created)

function gcRegister(cellPtr: i32): void {
  if (__gc_reg === 0) {
    __gc_reg = listNew();
  }
  __gc_reg = listPush(__gc_reg, cellPtr);
}

// Allocate + register a 4-slot value cell; returns the cell pointer.
// NB: the raw `new Int32Array(4)` here is the ACTUAL allocation — it must NOT be routed back through
// mkCell (that would be infinite self-recursion; a replace-all once did exactly that).
// The registry append is INLINED (not a gcRegister/listPush call) on the common non-grow path: this
// is the hot allocation site reached at the DEEPEST point of interpreter recursion, and every extra
// WAT call frame here lowers the max recursion depth before V8's stack overflows. Only the rare grow
// path calls listPush.
function mkCell(): i32 {
  const p: i32 = dynAlloc(24); // 4-slot cell: 8-byte header + 4*4 (recycled by the GC)
  if (__gc_reg === 0) {
    __gc_reg = listNew();
  }
  const a: Int32Array = __gc_reg as unknown as Int32Array;
  const len: i32 = a[0];
  if (len >= a[1]) {
    // grow (rare): listPush copies into a fresh, larger array — recycle the old backing array instead
    // of leaking it (the registry's only doubling source; one-time once it reaches steady state).
    const oldReg: i32 = __gc_reg;
    const oldBytes: i32 = 8 + (a[1] + 2) * 4;
    __gc_reg = listPush(__gc_reg, p);
    dynFreeBlock(oldReg, oldBytes);
  } else {
    a[len + 2] = p;
    a[0] = len + 1;
  }
  return p;
}

// Allocate + register a 5-slot value cell (user-function); returns the cell pointer.
function mkCell5(): i32 {
  const p: i32 = dynAlloc(28); // 5-slot cell: 8-byte header + 5*4 (recycled by the GC)
  gcRegister(p);
  return p;
}

/** Number of value cells currently tracked by the GC registry (test/introspection hook). */
/** @export */
export function dynGcCellCount(): i32 {
  if (__gc_reg === 0) {
    return 0;
  }
  return listLen(__gc_reg);
}

// ── GC mark phase (#14 GC track, Part 4a) ─────────────────────────────────────────────────────
// The MARK BIT is bit 8 (256) of a cell's slot-0 tag — uniform across 4-slot and 5-slot cells, no
// extra storage. The real tag is bits 0..7 (values 0..7), so mark/sweep read `slot0 & 255`. The rest
// of the runtime NEVER sees the bit: a full collect() clears every survivor's mark before returning,
// so between collections all tags are clean and `dynTag`/`dynTypeof`/etc. need no masking.
const GC_MARK_BIT: i32 = 256;

function cellTag(c: i32): i32 {
  const n: Int32Array = c as unknown as Int32Array;
  return n[0] & 255;
}

function cellMarked(c: i32): i32 {
  const n: Int32Array = c as unknown as Int32Array;
  return (n[0] & GC_MARK_BIT) === 0 ? 0 : 1;
}

// Recursively mark `c` and everything reachable from it. The mark bit doubles as the visited set, so
// cycles terminate. Only CELLS are followed: array/object element handles (the list at slot a) and a
// user-function's body/params/defEnv cells. Number payloads (Float64Array) and string buffers
// (Uint8Array) and object key byte-pairs (slot c) are owned, non-cell allocations — not followed here
// (the sweep frees them by reading the owning cell).
function gcMark(c: i32): void {
  // 0 = null ptr, -1 = the "no env" sentinel (evalEnv / a top-level scope's parent link). Neither is
  // a real cell — guard both so we never dereference them.
  if (c === 0 || c === -1) {
    return;
  }
  if (cellMarked(c) === 1) {
    return;
  }
  const n: Int32Array = c as unknown as Int32Array;
  n[0] = n[0] | GC_MARK_BIT;
  const t: i32 = n[0] & 255;
  if (t === 5 || t === 6) {
    // array or object: slot a holds the list of element / value handles
    const lst: i32 = n[1];
    const len: i32 = listLen(lst);
    let i: i32 = 0;
    while (i < len) {
      gcMark(listGet(lst, i));
      i = i + 1;
    }
    // An ENV is a tag-6 object whose PARENT scope link lives in slot 2 (regular objects keep 0 there,
    // so this is a harmless no-op for them). Following it marks the whole lexical scope chain — so
    // marking an inner scope (or a closure's defining env) keeps every enclosing variable alive.
    if (t === 6) {
      gcMark(n[2]);
    }
  } else if (t === 7) {
    // user-function cell (marker -1 in slot 1): body box, params array, defining env are all cells
    if (n[1] === -1) {
      gcMark(n[2]);
      gcMark(n[3]);
      gcMark(n[4]);
    }
  }
}

/** Clear the mark bit on every registered cell (start a fresh mark, or finish a collection). */
/** @export */
export function dynGcMarkClear(): void {
  if (__gc_reg === 0) {
    return;
  }
  const len: i32 = listLen(__gc_reg);
  let i: i32 = 0;
  while (i < len) {
    const c: i32 = listGet(__gc_reg, i);
    const n: Int32Array = c as unknown as Int32Array;
    n[0] = n[0] & 255;
    i = i + 1;
  }
}

/** Mark `root` and everything reachable from it (test/introspection hook; P4b feeds the root set). */
/** @export */
export function dynGcMark(root: i32): void {
  gcMark(root);
}

/** Number of registered cells currently marked (test/introspection hook). */
/** @export */
export function dynGcMarkedCount(): i32 {
  if (__gc_reg === 0) {
    return 0;
  }
  const len: i32 = listLen(__gc_reg);
  let count: i32 = 0;
  let i: i32 = 0;
  while (i < len) {
    if (cellMarked(listGet(__gc_reg, i)) === 1) {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// ── GC roots: the interpreter shadow-stack (#14 GC track, Part 4b) ─────────────────────────────
// A precise collector must know every LIVE handle. wasic locals holding `any` handles aren't
// enumerable at runtime, but the INTERPRETER's live state is: it is exactly the chain of active
// scopes. `__gc_roots` is an explicit stack of those scope handles — `dynRun` pushes its scope on
// entry and pops on exit, so during a nested call the stack holds [driver-env, scope1, scope2, …]
// (every frame that will resume). Marking from every root (each an env, whose parent chain + bound
// values gcMark now follows) keeps all live interpreter state. A host/driver can also push its OWN
// top-level roots (the env it holds) via dynGcPushRoot so P5's collect() won't free them.
let __gc_roots: i32 = 0; // root-stack list ptr (0 = not yet created)

function gcPushRoot(h: i32): void {
  if (__gc_roots === 0) {
    __gc_roots = listNew();
  }
  __gc_roots = listPush(__gc_roots, h);
}

function gcPopRoot(): void {
  if (__gc_roots === 0) {
    return;
  }
  const a: Int32Array = __gc_roots as unknown as Int32Array;
  if (a[0] > 0) {
    a[0] = a[0] - 1; // pop = shrink the length; the slot is overwritten on the next push
  }
}

/** Push a root handle the collector must treat as live (host/driver top-level roots). */
/** @export */
export function dynGcPushRoot(h: i32): void {
  gcPushRoot(h);
}

/** Pop the most recently pushed root. */
/** @export */
export function dynGcPopRoot(): void {
  gcPopRoot();
}

/** Current depth of the GC root stack (test/introspection hook; 0 when no scope/root is active). */
/** @export */
export function dynGcRootCount(): i32 {
  if (__gc_roots === 0) {
    return 0;
  }
  return listLen(__gc_roots);
}

/** Clear all marks, then mark everything reachable from every root on the stack (the live set). */
/** @export */
export function dynGcMarkRoots(): void {
  dynGcMarkClear();
  // The interpreter's "registers" are live roots too: the current scope and the last/return values
  // (held in module globals, not on the scope stack). Marking them keeps a collection safe to run at
  // any interpreter point or right after a dynRun returns. (All guard 0/-1 internally.)
  gcMark(evalEnv);
  gcMark(lastValue);
  gcMark(evalReturnVal);
  if (__gc_roots === 0) {
    return;
  }
  const len: i32 = listLen(__gc_roots);
  let i: i32 = 0;
  while (i < len) {
    gcMark(listGet(__gc_roots, i));
    i = i + 1;
  }
  // HOST PINS (functions-as-`any`): handles the host holds across calls. The GC can't see host
  // locals, so a function value returned to the host (which can't be deep-copied like a number/object)
  // would be collected on the next call. Pinning records it here so it stays marked until released.
  if (__gc_pins !== 0) {
    const plen: i32 = listLen(__gc_pins);
    let pi: i32 = 0;
    while (pi < plen) {
      gcMark(listGet(__gc_pins, pi)); // gcMark guards 0 (released slot)
      pi = pi + 1;
    }
  }
}

// ── Host pin table (functions-as-`any`, #14 final item) ───────────────────────────────────────
// dynrt's GC is NON-MOVING, so pinning a handle just needs to keep it MARKED — pin/unpin record it
// in a slot list the marker also walks. The pin list itself is allocated via listNew (NOT mkCell),
// so it is never swept. Slots are reused (a released slot holds 0); `dynGcPin` returns a stable slot
// index the host passes to `dynGcUnpin`.
let __gc_pins: i32 = 0;

/** Pin a handle so it survives collections while the host holds it; returns its slot index. */
/** @export */
export function dynGcPin(h: i32): i32 {
  if (__gc_pins === 0) {
    __gc_pins = listNew();
  }
  const len: i32 = listLen(__gc_pins);
  let i: i32 = 0;
  while (i < len) {
    if (listGet(__gc_pins, i) === 0) {
      listSet(__gc_pins, i, h); // reuse a released slot
      return i;
    }
    i = i + 1;
  }
  __gc_pins = listPush(__gc_pins, h); // append a new slot
  return len;
}

/** Release a previously pinned slot — the handle becomes collectible again. */
/** @export */
export function dynGcUnpin(slot: i32): void {
  if (__gc_pins === 0) {
    return;
  }
  if (slot < 0 || slot >= listLen(__gc_pins)) {
    return;
  }
  listSet(__gc_pins, slot, 0);
}

// Return a self-managed list's backing block (8 + (cap+2)*4 bytes) to the recycle pool.
function freeList(lp: i32): void {
  const a: Int32Array = lp as unknown as Int32Array;
  dynFreeBlock(lp, 8 + (a[1] + 2) * 4);
}

// Free the non-cell PAYLOADS a garbage cell owns (called before the cell itself is freed, while its
// slots are still readable). Number→Float64Array, string→Uint8Array, array→element list, object→
// values list + keys list + each key byte-buffer. Referenced CELLS (array/object elements, an env's
// parent, a user-fn's body/params/env) are NOT freed here — they're registered and swept on their own.
function gcFreePayload(c: i32): void {
  const n: Int32Array = c as unknown as Int32Array;
  const t: i32 = n[0] & 255;
  if (t === 3) {
    dynFreeBlock(n[1], 16); // number payload
  } else if (t === 4) {
    dynFreeBlock(n[1], 8 + n[2]); // string bytes
  } else if (t === 5) {
    freeList(n[1]); // array element list
  } else if (t === 6) {
    freeList(n[1]); // object values list
    const keys: i32 = n[3];
    const klen: i32 = listLen(keys); // interleaved [keyPtr, keyLen] → 2 * entryCount
    let i: i32 = 0;
    while (i < klen) {
      dynFreeBlock(listGet(keys, i), 8 + listGet(keys, i + 1)); // each key's Uint8Array
      i = i + 2;
    }
    freeList(keys); // object keys list
  }
}

/**
 * Full mark-sweep collection (#14 GC track, Part 5). Mark from all roots, then sweep the registry:
 * every UNMARKED value cell is garbage → free its payloads + the cell into dynrt's recycle pool and
 * drop it from the registry (compacted in place); every marked cell survives with its mark cleared.
 * Returns the number of cells reclaimed. Reclaims CELLS (24/28 bytes) AND their payloads (the bulk),
 * so a long interpreter loop runs in bounded memory. Allocation-free, so safe to call between
 * interpreter operations (incl. the auto-trigger at statement boundaries); the roots cover all live
 * state — there are no un-rooted temporaries at a statement boundary.
 */
/** @export */
export function dynGcCollect(): i32 {
  dynGcMarkRoots();
  if (__gc_reg === 0) {
    return 0;
  }
  const reg: Int32Array = __gc_reg as unknown as Int32Array;
  const len: i32 = reg[0];
  let write: i32 = 0;
  let read: i32 = 0;
  let freed: i32 = 0;
  while (read < len) {
    const c: i32 = reg[read + 2];
    const cn: Int32Array = c as unknown as Int32Array;
    if ((cn[0] & GC_MARK_BIT) !== 0) {
      cn[0] = cn[0] & 255; // live: clear the mark, keep (compact toward the front)
      reg[write + 2] = c;
      write = write + 1;
    } else {
      // garbage: free its payloads FIRST (reads the cell's slots), then the cell. A 5-slot
      // user-function cell is 28 bytes, every other cell is 24 — read the size before dynFreeBlock
      // overwrites the first two slots with its [size, next] header.
      const sz: i32 = ((cn[0] & 255) === 7 && cn[1] === -1) ? 28 : 24;
      gcFreePayload(c);
      dynFreeBlock(c, sz);
      freed = freed + 1;
    }
    read = read + 1;
  }
  reg[0] = write;
  return freed;
}

/** Number of blocks currently free across all recycling lists (buckets + Tier 2) — test hook. */
/** @export */
export function dynGcFreeCount(): i32 {
  return __free_nodes;
}

// Auto-collect trigger (#14 GC track, Part 5b). Called at interpreter statement boundaries — a safe
// collection point: the previous statement is complete and the next has not begun, so every live
// value is reachable from a rooted scope (no un-rooted expression temporaries). Collects only when the
// registry has grown past `__gc_threshold`, then raises the threshold to 2× the surviving live set
// (min 8192) — the standard "grow the heap to amortize" heuristic, so a large live set doesn't force a
// collection on every statement, while transient garbage (deep recursion / long loops) is reclaimed.
function maybeCollect(): void {
  if (dynGcCellCount() > __gc_threshold) {
    dynGcCollect();
    const live: i32 = dynGcCellCount();
    const grown: i32 = live * 2;
    __gc_threshold = grown > 8192 ? grown : 8192;
  }
}

/** A fresh empty array. */
/** @export */
export function dynArray(): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 5;
  n[1] = listNew();
  return n as unknown as i32;
}

/** A fresh empty object. */
/** @export */
export function dynObject(): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 6;
  n[1] = listNew(); // values
  n[3] = listNew(); // interleaved [keyPtr, keyLen]
  return n as unknown as i32;
}

// ── Introspection ─────────────────────────────────────────────────────────────────────────────

/** Raw structural tag: 0=undefined 1=null 2=boolean 3=number 4=string 5=array 6=object. */
/** @export */
export function dynTag(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[0];
}

/**
 * JS `typeof` code: 0=undefined 1=object 2=boolean 3=number 4=string 5=function.
 * Note the JS quirk: typeof null / array / plain object are all "object" (→ 1).
 */
/** @export */
export function dynTypeof(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 0) return 0; // undefined
  if (t === 2) return 2; // boolean
  if (t === 3) return 3; // number
  if (t === 4) return 4; // string
  if (t === 7) return 5; // function
  return 1; // null / array / object → "object"
}

// ── Typed accessors (assert nothing; caller is expected to check the tag) ─────────────────────

/** The f64 value of a number box. */
/** @export */
export function dynNumberValue(v: i32): f64 {
  const n: Int32Array = v as unknown as Int32Array;
  const p: i32 = n[1];
  const fv: Float64Array = p as unknown as Float64Array;
  return fv[0];
}

/** The 0/1 value of a boolean box. */
/** @export */
export function dynBoolValue(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[1];
}

/** Byte length of a string box. */
/** @export */
export function dynStrLen(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[2];
}

/**
 * Raw byte pointer of a string box's UTF-8 data — for unboxing an `any` string back to a wasic
 * `string` (ptr+len): `ptr = dynStrBytes(v)`, `len = dynStrLen(v)`. The string box stores a
 * Uint8Array base in slot 1; the data starts 8 bytes past it (the TypedArray header).
 */
/** @export */
export function dynStrBytes(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const bufPtr: i32 = n[1];
  return bufPtr + 8;
}

/** Byte (char code) at index `i` of a string box. */
/** @export */
export function dynStrCharAt(v: i32, i: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const p: i32 = n[1];
  const buf: Uint8Array = p as unknown as Uint8Array;
  return buf[i];
}

// ── Coercions (JS ToBoolean / ToNumber) ───────────────────────────────────────────────────────

/** JS truthiness: 1 if truthy, else 0. */
/** @export */
export function dynToBool(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 0) return 0; // undefined
  if (t === 1) return 0; // null
  if (t === 2) return n[1];
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    const x: f64 = fv[0];
    if (x !== x) return 0; // NaN is falsy
    return x === 0 ? 0 : 1; // 0 and -0 are falsy
  }
  if (t === 4) return n[2] === 0 ? 0 : 1; // "" is falsy
  return 1; // array / object are truthy
}

/** JS ToNumber (v1: string/array/object → NaN). */
/** @export */
export function dynToNumber(v: i32): f64 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 1) return 0; // null → 0
  if (t === 2) return n[1] === 0 ? 0 : 1; // bool → 0/1
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    return fv[0];
  }
  return Number.NaN; // undefined / string / array / object → NaN (v1)
}

// ── Internal: reconstruct a wasic string from a string box's bytes ────────────────────────────
function boxToStr(v: i32): string {
  const n: Int32Array = v as unknown as Int32Array;
  const len: i32 = n[2];
  const p: i32 = n[1];
  const buf: Uint8Array = p as unknown as Uint8Array;
  let r: string = "";
  let i: i32 = 0;
  while (i < len) {
    r = r + String.fromCharCode(buf[i]);
    i = i + 1;
  }
  return r;
}

// ── Internal: JS ToString for the `+` concat path (array/object → "" in v1) ───────────────────
function stringForm(v: i32): string {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 4) return boxToStr(v);
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    const x: f64 = fv[0];
    return `${x}`;
  }
  if (t === 2) return n[1] === 0 ? "false" : "true";
  if (t === 1) return "null";
  if (t === 0) return "undefined";
  return ""; // array / object stringification deferred to a later increment
}

// ── Object ops ────────────────────────────────────────────────────────────────────────────────

// Index of `key` among an object's entries, or -1. `keys` list is interleaved [keyPtr, keyLen].
function objIndexOf(obj: i32, key: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const vlp: i32 = n[1];
  const klp: i32 = n[3];
  const count: i32 = listLen(vlp);
  const klen: i32 = key.length;
  let i: i32 = 0;
  while (i < count) {
    const kl: i32 = listGet(klp, i * 2 + 1);
    if (kl === klen) {
      const kptr: i32 = listGet(klp, i * 2);
      const kv: Uint8Array = kptr as unknown as Uint8Array;
      let eq: i32 = 1;
      let j: i32 = 0;
      while (j < kl) {
        if (kv[j] !== key.charCodeAt(j)) {
          eq = 0;
          j = kl;
        } else {
          j = j + 1;
        }
      }
      if (eq === 1) return i;
    }
    i = i + 1;
  }
  return -1;
}

/** Set `obj[key] = val` (overwrite if present, else append). */
/** @export */
export function dynSet(obj: i32, key: string, val: i32): void {
  const n: Int32Array = obj as unknown as Int32Array;
  const hit: i32 = objIndexOf(obj, key);
  if (hit !== -1) {
    listSet(n[1], hit, val); // overwrite value in place
    return;
  }
  // append: copy key bytes, push [keyPtr, keyLen] to the keys list and val to the values list
  const klen: i32 = key.length;
  const kbuf: Uint8Array = dynAlloc(8 + klen) as unknown as Uint8Array; // 8 header + klen (GC-recycled)
  let m: i32 = 0;
  while (m < klen) {
    kbuf[m] = key.charCodeAt(m);
    m = m + 1;
  }
  const kp0: i32 = kbuf as unknown as i32;
  let klp: i32 = n[3];
  klp = listPush(klp, kp0);
  klp = listPush(klp, klen);
  n[3] = klp;
  n[1] = listPush(n[1], val);
}

/** `obj[key]` → value handle, or -1 if absent. */
/** @export */
export function dynGet(obj: i32, key: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const hit: i32 = objIndexOf(obj, key);
  if (hit === -1) return -1;
  return listGet(n[1], hit);
}

/** 1 if `obj` has own `key`, else 0. */
/** @export */
export function dynHas(obj: i32, key: string): i32 {
  return objIndexOf(obj, key) === -1 ? 0 : 1;
}

/** Number of own entries on an object. */
/** @export */
export function dynObjLen(obj: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  return listLen(n[1]);
}

// #14 follow-up: object-entry enumeration by index — for the host to marshal an `any` object to a
// real JS object. Keys are stored interleaved [keyPtr, keyLen] in the keys list (slot 3); values in
// the values list (slot 1). `dynObjKeyPtr` returns the key's UTF-8 DATA pointer (+8 past the
// Uint8Array header, like dynStrBytes).

/** Byte pointer of the i-th own key's data. */
/** @export */
export function dynObjKeyPtr(obj: i32, i: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const kptr: i32 = listGet(n[3], i * 2);
  return kptr + 8;
}

/** Byte length of the i-th own key. */
/** @export */
export function dynObjKeyLen(obj: i32, i: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  return listGet(n[3], i * 2 + 1);
}

/** Value handle of the i-th own entry. */
/** @export */
export function dynObjValAt(obj: i32, i: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  return listGet(n[1], i);
}

// #14 2e.1 (for-in) — key `i` as a STRING VALUE (keys are stored as raw bytes; build a tag-4 string
// box by copying them, mirroring dynString).
function dynObjKeyVal(obj: i32, i: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const kbase: i32 = listGet(n[3], i * 2); // key buffer cell ptr
  const klen: i32 = listGet(n[3], i * 2 + 1);
  const src: Uint8Array = kbase as unknown as Uint8Array; // view: element m = key byte m
  const buf: Uint8Array = dynAlloc(8 + klen) as unknown as Uint8Array;
  let m: i32 = 0;
  while (m < klen) {
    buf[m] = src[m];
    m = m + 1;
  }
  const sn: Int32Array = mkCell() as unknown as Int32Array;
  sn[0] = 4; // string tag
  sn[1] = buf as unknown as i32;
  sn[2] = klen;
  return sn as unknown as i32;
}

// ── Array ops ─────────────────────────────────────────────────────────────────────────────────

/** Append `val` to an array. */
/** @export */
export function dynPush(arr: i32, val: i32): void {
  const n: Int32Array = arr as unknown as Int32Array;
  n[1] = listPush(n[1], val); // listPush may reallocate — write the new pointer back
}

/** Array length. */
/** @export */
export function dynArrLen(arr: i32): i32 {
  const n: Int32Array = arr as unknown as Int32Array;
  return listLen(n[1]);
}

/** Array element at index `i` (a value handle). */
/** @export */
export function dynArrGet(arr: i32, i: i32): i32 {
  const n: Int32Array = arr as unknown as Int32Array;
  return listGet(n[1], i);
}

// #14 2e.4 — set array element `i` (in-bounds overwrite; `i === length` appends, extending the array;
// sparse `i > length` and negative `i` are ignored in v1).
function dynArrSet(arr: i32, i: i32, val: i32): void {
  const n: Int32Array = arr as unknown as Int32Array;
  const len: i32 = listLen(n[1]);
  if (i >= 0 && i < len) {
    listSet(n[1], i, val);
  } else if (i === len) {
    n[1] = listPush(n[1], val);
  }
}

// #14 2e.4 — `container[idx] = val` for arrays (number index) and objects (string key); mirrors
// dynIndexValue's dispatch. Non-matching container/index kinds are no-ops in v1.
function dynIndexSet(container: i32, idxBox: i32, val: i32): void {
  const cn: Int32Array = container as unknown as Int32Array;
  const ct: i32 = cn[0];
  const it: i32 = dynTag(idxBox);
  if (ct === 5) { // array
    if (it === 3) {
      const idxf: f64 = dynNumberValue(idxBox);
      const ii: i32 = idxf as unknown as i32; // truncate toward zero
      dynArrSet(container, ii, val);
    }
  } else if (ct === 6) { // object
    if (it === 4) {
      const key: string = boxToStr(idxBox);
      dynSet(container, key, val);
    }
  }
}

// ── Operators ─────────────────────────────────────────────────────────────────────────────────

/** JS `===` (strict equality): primitives by value, objects/arrays by reference. */
/** @export */
export function dynStrictEq(a: i32, b: i32): i32 {
  const na: Int32Array = a as unknown as Int32Array;
  const nb: Int32Array = b as unknown as Int32Array;
  const ta: i32 = na[0];
  const tb: i32 = nb[0];
  if (ta !== tb) return 0;
  if (ta === 0) return 1; // undefined === undefined
  if (ta === 1) return 1; // null === null
  if (ta === 2) return na[1] === nb[1] ? 1 : 0;
  if (ta === 3) {
    const pa: i32 = na[1];
    const pb: i32 = nb[1];
    const fa: Float64Array = pa as unknown as Float64Array;
    const fb: Float64Array = pb as unknown as Float64Array;
    // NOTE: comparing Float64Array elements directly (`fa[0] === fb[0]`) mis-infers as i32 — route
    // through explicitly-typed f64 locals (a known wasic gap; see cmem/dynrt-design.md).
    const xa: f64 = fa[0];
    const xb: f64 = fb[0];
    return xa === xb ? 1 : 0; // NaN === NaN is false (f64.eq)
  }
  if (ta === 4) {
    const len: i32 = na[2];
    if (len !== nb[2]) return 0;
    const pa: i32 = na[1];
    const pb: i32 = nb[1];
    const va: Uint8Array = pa as unknown as Uint8Array;
    const vb: Uint8Array = pb as unknown as Uint8Array;
    let i: i32 = 0;
    while (i < len) {
      if (va[i] !== vb[i]) return 0;
      i = i + 1;
    }
    return 1;
  }
  // array / object: reference identity (same handle)
  return a === b ? 1 : 0;
}

/** JS `+`: string concat if either operand is a string, else numeric addition. */
/** @export */
export function dynAdd(a: i32, b: i32): i32 {
  const na: Int32Array = a as unknown as Int32Array;
  const nb: Int32Array = b as unknown as Int32Array;
  if (na[0] === 4 || nb[0] === 4) {
    // NOTE: `stringForm(a) + stringForm(b)` (concat of two string-returning CALLS) is not yet
    // supported by emitStringAssign — bind each to a string local first (a known wasic gap; see
    // cmem/dynrt-design.md / compiler-bugs.md). Remove this dance once the compiler handles it.
    const sa: string = stringForm(a);
    const sb: string = stringForm(b);
    const s: string = sa + sb;
    return dynString(s);
  }
  const an: f64 = dynToNumber(a);
  const bn: f64 = dynToNumber(b);
  return dynNumber(an + bn);
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2a — dynamic operators (used by dynEval; also the operator surface the future wasic
// `any` lowering will call for `-` `*` `/` `%` `< > <= >=` `-x` `!x`). Comparisons are numeric in
// v1 (string/lexicographic compare is a documented gap).
// ──────────────────────────────────────────────────────────────────────────────────────────────

/** Unary minus (`-x`). */
/** @export */
export function dynNeg(v: i32): i32 {
  const a: f64 = dynToNumber(v);
  return dynNumber(0 - a);
}

/** Logical NOT (`!x`). */
/** @export */
export function dynNot(v: i32): i32 {
  return dynBool(dynToBool(v) === 0 ? 1 : 0);
}

/** Numeric subtraction (`-`). */
/** @export */
export function dynSub(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a - b);
}

/** Numeric multiplication (`*`). */
/** @export */
export function dynMul(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a * b);
}

/** Numeric division (`/`). */
/** @export */
export function dynDiv(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a / b);
}

/** Remainder (`%`, JS truncated-toward-zero semantics). */
/** @export */
export function dynMod(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  const q: f64 = a / b;
  const t: f64 = q < 0 ? Math.ceil(q) : Math.floor(q);
  return dynNumber(a - b * t);
}

/** Less-than (`<`, numeric). */
/** @export */
export function dynLt(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a < b ? 1 : 0);
}

/** Greater-than (`>`, numeric). */
/** @export */
export function dynGt(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a > b ? 1 : 0);
}

/** Less-or-equal (`<=`, numeric). */
/** @export */
export function dynLe(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a <= b ? 1 : 0);
}

/** Greater-or-equal (`>=`, numeric). */
/** @export */
export function dynGe(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a >= b ? 1 : 0);
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2c — function VALUES (tag 7) + a calling convention.
//
// A function value is a boxed cell with tag 7 and a built-in id in slot a. Dispatch is a STATIC
// switch on that id (NOT a function table) — wasmmerge forbids `call_indirect` in a merged module,
// so the dynamic runtime cannot use an indirect-call table; built-ins keyed by id are the merge-safe
// way to expose callable values. User-defined functions / `new Function` (which need a parsed body)
// are increment 2d. Built-in ids: 0 abs, 1 sqrt, 2 floor, 3 ceil, 4 round, 5 min, 6 max, 7 len,
// 8 inc (the one side-effecting built-in — increments `sideEffectCounter` — so short-circuit is
// observable).
// ──────────────────────────────────────────────────────────────────────────────────────────────

/** A built-in function value with the given id (see the id table above). */
/** @export */
export function dynBuiltin(id: i32): i32 {
  const n: Int32Array = mkCell() as unknown as Int32Array;
  n[0] = 7;
  n[1] = id;
  return n as unknown as i32;
}

// A USER function value (increment 2d.2). Built-ins use a 4-slot cell with id ≥ 0 in slot 1; user
// functions use a 5-slot cell with the marker id -1 in slot 1, plus body / params / defining-env:
//   [7, -1, bodyStrBox, paramsArr(value-model array of param-name string boxes), defEnv]
// `defEnv` is the scope the function was DEFINED in — the call scope links to it as its parent so the
// body can see outer names (→ recursion + simple closures, via the `envLookup` chain).
function makeUserFunc(paramsArr: i32, bodyBox: i32, defEnv: i32): i32 {
  const n: Int32Array = mkCell5() as unknown as Int32Array;
  n[0] = 7;
  n[1] = -1;
  n[2] = bodyBox;
  n[3] = paramsArr;
  n[4] = defEnv;
  return n as unknown as i32;
}

/**
 * Build a user function value from strings — the `new Function` capability (runtime code from
 * strings). `paramsArr` is a value-model array of param-name string boxes; `bodyStr` is the body
 * source; `defEnv` is the scope the function closes over (use the env you will run it against).
 */
/** @export */
export function dynMakeFunc(paramsArr: i32, bodyStr: string, defEnv: i32): i32 {
  const bodyBox: i32 = dynString(bodyStr);
  return makeUserFunc(paramsArr, bodyBox, defEnv);
}

/**
 * Function PRODUCER for typed wasic source (`Function(params, body)` → here). `paramNames` is a
 * comma-separated parameter list ("" / "x" / "a, b"); `body` is the function body source. Splits the
 * names into a value-model array of string boxes and builds a user function closing over a fresh env.
 * This is the source-level door to a dynrt function value that can be returned as `any` and called
 * from a host (via the bindgen tag-7 proxy + pin table).
 */
/**
 * #14 Phase 2 — wrap a HOST function-table index as a callable dynrt value. bindgen calls this when a
 * JS function crosses INTO the core as `any`. The cell is tag 7 (function) with marker slot[1] = -2 and
 * slot[2] = the host index; `dynApply` routes such a value back to the host via the `__host.call`
 * import. Non-moving GC keeps the cell at a stable address; the index stays valid for the host's table.
 */
/** @export */
export function dynMakeHostFn(index: i32): i32 {
  const n: Int32Array = mkCell5() as unknown as Int32Array;
  n[0] = 7; // function tag
  n[1] = -2; // host-function marker (distinct from -1 = user fn, and from builtin ids)
  n[2] = index; // host function-table index
  n[3] = 0;
  n[4] = 0;
  return n as unknown as i32;
}

/** @export */
export function dynMakeFn(paramNames: string, body: string): i32 {
  const paramsArr: i32 = dynArray();
  const plen: i32 = paramNames.length;
  let start: i32 = 0;
  let i: i32 = 0;
  while (i <= plen) {
    if (i === plen || paramNames.charCodeAt(i) === 44) { // ',' or end of string
      let s: i32 = start;
      let e: i32 = i;
      while (s < e && paramNames.charCodeAt(s) === 32) s = s + 1; // trim leading spaces
      while (e > s && paramNames.charCodeAt(e - 1) === 32) e = e - 1; // trim trailing
      if (e > s) {
        const name: string = paramNames.slice(s, e);
        dynPush(paramsArr, dynString(name));
      }
      start = i + 1;
    }
    i = i + 1;
  }
  const env: i32 = dynObject();
  return dynMakeFunc(paramsArr, body, env);
}

// Resolve `name` by walking the scope chain (current env → parent → …); -1 if unbound. An env's
// parent is stored in slot 2 of the object cell (0 / -1 = no parent); host envs have no parent, a
// function's call scope links to the function's defining env.
function envLookup(env: i32, name: string): i32 {
  let e: i32 = env;
  while (e !== -1 && e !== 0) {
    const r: i32 = dynGet(e, name);
    if (r !== -1) return r;
    const en: Int32Array = e as unknown as Int32Array;
    e = en[2]; // parent link
  }
  return -1;
}

// #14 2e.7 — block scoping. A lexical scope is just an object whose slot-2 is the parent link (the
// same representation envLookup/dynApply already use). Each `{ }` block / loop / catch gets a fresh
// child scope so `let`/`const` declared inside it do not leak to the enclosing scope.
function childEnv(parent: i32): i32 {
  const e: i32 = dynObject();
  const en: Int32Array = e as unknown as Int32Array;
  en[2] = parent;
  return e;
}

// #14 2e.7 — assign to an EXISTING binding: walk the scope chain and update the scope that declares
// `name` in place, so an inner block assigning an outer variable mutates the outer one (not a shadow).
// If `name` is undeclared anywhere, define it in the topmost (global) scope — loose-JS semantics.
// (Declarations use `dynSet(evalEnv, …)` directly to bind in the CURRENT scope; this is for `x = v`.)
function envAssign(env: i32, name: string, val: i32): void {
  let e: i32 = env;
  let top: i32 = env;
  while (e !== -1 && e !== 0) {
    if (dynGet(e, name) !== -1) {
      dynSet(e, name, val);
      return;
    }
    top = e;
    const en: Int32Array = e as unknown as Int32Array;
    e = en[2];
  }
  if (top !== -1 && top !== 0) dynSet(top, name, val);
}

// #14 2e.7a — shallow-copy every own binding of `src` into a fresh child scope of `parent`. Used to
// give `for (let …)` a FRESH per-iteration binding of the loop variable(s): each iteration runs against
// a copy, so a closure created in the body captures THAT iteration's value (JS `let` loop semantics),
// not the single shared/final value. Key bytes are copied (not aliased) so the clone owns them; values
// are shared handles (same boxed value). No interpreter statement runs here, so no GC mid-copy.
function cloneEnvFlat(src: i32, parent: i32): i32 {
  const dst: i32 = childEnv(parent);
  const sn: Int32Array = src as unknown as Int32Array;
  const dn: Int32Array = dst as unknown as Int32Array;
  const cnt: i32 = listLen(sn[1]);
  let i: i32 = 0;
  while (i < cnt) {
    const kptr: i32 = listGet(sn[3], i * 2);
    const klen: i32 = listGet(sn[3], i * 2 + 1);
    const val: i32 = listGet(sn[1], i);
    const src8: Uint8Array = kptr as unknown as Uint8Array;
    const kbuf: Uint8Array = dynAlloc(8 + klen) as unknown as Uint8Array;
    let m: i32 = 0;
    while (m < klen) {
      kbuf[m] = src8[m];
      m = m + 1;
    }
    let klp: i32 = dn[3];
    klp = listPush(klp, kbuf as unknown as i32);
    klp = listPush(klp, klen);
    dn[3] = klp;
    dn[1] = listPush(dn[1], val);
    i = i + 1;
  }
  return dst;
}

/** Call a function value with an args array (a value-model array of arg handles). `this` is undefined. */
/** @export */
export function dynApply(callee: i32, argsArr: i32): i32 {
  return dynApplyThis(callee, argsArr, -1);
}

// #14 2f.1 — like dynApply but with an explicit `this` (thisVal === -1 ⇒ undefined `this`). A method
// call `obj.m(args)` passes the receiver as thisVal; it is bound as `this` in the call scope so the body
// resolves `this` / `this.field` via the normal scope-chain lookup. (Builtins/host ignore `this`.)
function dynApplyThis(callee: i32, argsArr: i32, thisVal: i32): i32 {
  const cn: Int32Array = callee as unknown as Int32Array;
  if (cn[0] !== 7) return dynUndefined(); // not callable → undefined (guarded)
  const id: i32 = cn[1];
  if (id === -2) { // #14 Phase 2: HOST function — call back into the host through the import
    return __host.call(cn[2], argsArr);
  }
  const argc: i32 = dynArrLen(argsArr);
  if (id === -1) { // USER function (2d.2): run its body in a fresh scope linked to its defining env
    const bodyBox: i32 = cn[2];
    const paramsArr: i32 = cn[3];
    const defEnv: i32 = cn[4];
    const scope: i32 = dynObject();
    const sn: Int32Array = scope as unknown as Int32Array;
    sn[2] = defEnv; // parent link → outer names resolve (recursion + closures)
    if (thisVal !== -1) dynSet(scope, "this", thisVal); // #14 2f.1 — bind `this` for a method call
    const pc: i32 = dynArrLen(paramsArr);
    let i: i32 = 0;
    while (i < pc) {
      const pnameBox: i32 = dynArrGet(paramsArr, i);
      const pname: string = boxToStr(pnameBox);
      const aval: i32 = i < argc ? dynArrGet(argsArr, i) : dynUndefined();
      dynSet(scope, pname, aval);
      i = i + 1;
    }
    const bodySrc: string = boxToStr(bodyBox);
    // dynRun resets the shared parser globals — save/restore them around the nested run so the
    // OUTER parse resumes correctly (the source string `s` is a param, so it stays on the stack).
    const savedPos: i32 = evalPos;
    const savedEnv: i32 = evalEnv;
    const savedLive: i32 = evalLive;
    const savedRet: i32 = evalReturned;
    const savedRetVal: i32 = evalReturnVal;
    const savedLast: i32 = lastValue;
    const result: i32 = dynRun(bodySrc, scope);
    evalPos = savedPos;
    evalEnv = savedEnv;
    evalLive = savedLive;
    evalReturned = savedRet;
    evalReturnVal = savedRetVal;
    lastValue = savedLast;
    return result;
  }
  if (id === 8) { // inc() — the observable side effect
    sideEffectCounter = sideEffectCounter + 1;
    // NOTE: `dynNumber(sideEffectCounter)` — passing an i32 GLOBAL directly as an f64 arg skips the
    // f64.convert (an i32 LOCAL coerces fine); bind to a local first (a known wasic gap; see
    // cmem/compiler-bugs.md).
    const sc: i32 = sideEffectCounter;
    return dynNumber(sc);
  }
  const a0: i32 = argc > 0 ? dynArrGet(argsArr, 0) : dynUndefined();
  if (id === 7) { // len(x) — string byte length or array length
    const t: i32 = dynTag(a0);
    if (t === 4) {
      const an: Int32Array = a0 as unknown as Int32Array;
      const bl: i32 = an[2]; // bind to a local so the i32→f64 arg coercion fires (see note above)
      return dynNumber(bl);
    }
    if (t === 5) {
      const al: i32 = dynArrLen(a0);
      return dynNumber(al);
    }
    return dynNumber(0);
  }
  const x: f64 = dynToNumber(a0);
  if (id === 0) return dynNumber(Math.abs(x));
  if (id === 1) return dynNumber(Math.sqrt(x));
  if (id === 2) return dynNumber(Math.floor(x));
  if (id === 3) return dynNumber(Math.ceil(x));
  if (id === 4) return dynNumber(Math.round(x));
  const a1: i32 = argc > 1 ? dynArrGet(argsArr, 1) : dynUndefined();
  const y: f64 = dynToNumber(a1);
  if (id === 5) return dynNumber(x < y ? x : y); // min
  if (id === 6) return dynNumber(x > y ? x : y); // max
  return dynUndefined();
}

// #14.3.3: fixed-arity call helpers so the wasic compiler can emit `x(args)` on an `any` value as a
// single expression (building the args array + dynApply inline). Args are already boxed handles.
// Arity > 3 is a documented gap.
/** @export */
export function dynCall0(fn: i32): i32 {
  const args: i32 = dynArray();
  return dynApply(fn, args);
}

/** @export */
export function dynCall1(fn: i32, a0: i32): i32 {
  const args: i32 = dynArray();
  dynPush(args, a0);
  return dynApply(fn, args);
}

/** @export */
export function dynCall2(fn: i32, a0: i32, a1: i32): i32 {
  const args: i32 = dynArray();
  dynPush(args, a0);
  dynPush(args, a1);
  return dynApply(fn, args);
}

/** @export */
export function dynCall3(fn: i32, a0: i32, a1: i32, a2: i32): i32 {
  const args: i32 = dynArray();
  dynPush(args, a0);
  dynPush(args, a1);
  dynPush(args, a2);
  return dynApply(fn, args);
}

/** A fresh environment object pre-populated with the built-in functions (abs/sqrt/…/inc). */
/** @export */
export function dynStdEnv(): i32 {
  const e: i32 = dynObject();
  dynSet(e, "abs", dynBuiltin(0));
  dynSet(e, "sqrt", dynBuiltin(1));
  dynSet(e, "floor", dynBuiltin(2));
  dynSet(e, "ceil", dynBuiltin(3));
  dynSet(e, "round", dynBuiltin(4));
  dynSet(e, "min", dynBuiltin(5));
  dynSet(e, "max", dynBuiltin(6));
  dynSet(e, "len", dynBuiltin(7));
  dynSet(e, "inc", dynBuiltin(8));
  return e;
}

/** Read the observable side-effect counter (incremented by each live `inc()` call). */
/** @export */
export function dynSideEffectCount(): i32 {
  return sideEffectCounter;
}

/** Reset the observable side-effect counter to 0. */
/** @export */
export function dynResetSideEffects(): void {
  sideEffectCounter = 0;
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2a — `eval` of a pure expression language → boxed value.
//
// A recursive-descent, DIRECT-eval parser (no separate AST) over a module-level cursor `evalPos`,
// mirroring the JSON parser's shape. Grammar (low→high precedence): ternary `?:`, `||`, `&&`,
// equality `=== !== == !=` (`==`/`!=` treated as strict in v1), relational `< > <= >=`, additive
// `+ -`, multiplicative `* / %`, unary `- ! +`, primary (number/string/bool/null/undefined literal
// or parenthesised expr). Because v1 expressions have NO side effects (no variables, calls, or
// assignments yet), `&&`/`||`/`?:` evaluate both sides and select — observationally identical to
// short-circuit. Real short-circuit arrives with 2b (variables + calls). Identifiers other than the
// keywords, member access, and calls are 2b+. See cmem/dynrt-design.md.
// ──────────────────────────────────────────────────────────────────────────────────────────────

let evalPos: i32 = 0; // read cursor into the eval source string
let evalEnv: i32 = -1; // current environment object handle (names → values), or -1 for none
let evalLive: i32 = 1; // 1 = evaluate effects; 0 = inside a short-circuited (dead) branch
let sideEffectCounter: i32 = 0; // observable side effect for the `inc()` builtin (short-circuit test)
let evalReturned: i32 = 0; // set when a `return` statement executes; stops statement sequencing
let evalReturnVal: i32 = 0; // the value carried by the executed `return`
let lastValue: i32 = 0; // value of the last executed expression statement (dynRun's result)
// #14 Route A 2e.1 — loop control flow. Like evalReturned, these stop statement sequencing inside the
// loop body; the enclosing loop checks + clears them (break stops the loop; continue skips to the next
// iteration). They never escape a loop (a loop clears them before returning to its caller).
let evalBroke: i32 = 0; // set by `break`
let evalContinued: i32 = 0; // set by `continue`
// #14 2e.6 — exception control. `throw` sets evalThrew=1 + evalThrowVal; it propagates up (stopping
// statement sequencing + loops, like evalReturned) until a `try`/`catch` clears it. Unlike a return,
// a throw is NOT consumed by a function call boundary (dynApply) — it unwinds through callers.
let evalThrew: i32 = 0;
let evalThrowVal: i32 = 0;

// Compare two wasic strings byte-for-byte (avoids relying on `===` over reconstructed substrings).
function strEq(a: string, b: string): i32 {
  if (a.length !== b.length) return 0;
  let i: i32 = 0;
  while (i < a.length) {
    if (a.charCodeAt(i) !== b.charCodeAt(i)) return 0;
    i = i + 1;
  }
  return 1;
}

// `obj.name` — TOTAL (guarded): object property (undefined if absent), array/string `.length`,
// undefined for anything else. Never dereferences a non-container, so `undefined.x` → undefined
// rather than a trap (a forgiving runtime; this also removes the only trap motivation for
// short-circuit in 2b, so real short-circuit lands with calls in the next sub-increment).
// (#14.3.3: exported so the wasic compiler can emit `x.foo` on an `any` value.)
/** @export */
export function dynMember(obj: i32, name: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 6) { // object — own props, then the prototype chain (#14 2f.1: slot 2 = __proto__)
    let o: i32 = obj;
    while (o !== 0) {
      const on: Int32Array = o as unknown as Int32Array;
      if (on[0] !== 6) break; // a non-object proto link terminates the chain
      const r: i32 = dynGet(o, name);
      if (r !== -1) return r;
      o = on[2]; // walk to __proto__
    }
    return dynUndefined();
  }
  if (t === 5) { // array
    if (strEq(name, "length") === 1) {
      const ln: i32 = dynArrLen(obj);
      return dynNumber(ln);
    }
    return dynUndefined();
  }
  if (t === 4) { // string
    if (strEq(name, "length") === 1) {
      const sl: i32 = n[2];
      return dynNumber(sl);
    }
    return dynUndefined();
  }
  return dynUndefined();
}

// `container[idx]` — array element by numeric index, or object property by string key. Guarded.
// (#14.3.3: exported so the wasic compiler can emit `x[i]` on an `any` value.)
/** @export */
export function dynIndexValue(container: i32, idxBox: i32): i32 {
  const cn: Int32Array = container as unknown as Int32Array;
  const ct: i32 = cn[0];
  const it: i32 = dynTag(idxBox);
  if (ct === 5) { // array
    if (it === 3) {
      const idxf: f64 = dynNumberValue(idxBox);
      const ii: i32 = idxf as unknown as i32; // truncate toward zero
      const len: i32 = dynArrLen(container);
      if (ii < 0 || ii >= len) return dynUndefined();
      return dynArrGet(container, ii);
    }
    return dynUndefined();
  }
  if (ct === 6) { // object
    if (it === 4) {
      const key: string = boxToStr(idxBox);
      const r: i32 = dynGet(container, key);
      return r === -1 ? dynUndefined() : r;
    }
    return dynUndefined();
  }
  return dynUndefined();
}

// Is `c` a valid identifier-start (A-Za-z_$) or, when `cont` is 1, also a digit?
function isIdentChar(c: i32, cont: i32): i32 {
  if (c >= 65 && c <= 90) return 1; // A-Z
  if (c >= 97 && c <= 122) return 1; // a-z
  if (c === 95 || c === 36) return 1; // _ $
  if (cont === 1 && c >= 48 && c <= 57) return 1; // 0-9
  return 0;
}

function evalSkipWs(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    if (evalPos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(evalPos);
      if (c === 32 || c === 9 || c === 10 || c === 13) {
        evalPos = evalPos + 1;
      } else {
        go = 0;
      }
    }
  }
}

function evalPeek(s: string): i32 {
  if (evalPos >= s.length) return -1;
  return s.charCodeAt(evalPos);
}

function evalPeek2(s: string): i32 {
  if (evalPos + 1 >= s.length) return -1;
  return s.charCodeAt(evalPos + 1);
}

function parseNumLit(s: string): i32 {
  const start: i32 = evalPos;
  let c: i32 = evalPeek(s);
  while (c >= 48 && c <= 57) {
    evalPos = evalPos + 1;
    c = evalPeek(s);
  }
  if (c === 46) { // '.'
    evalPos = evalPos + 1;
    c = evalPeek(s);
    while (c >= 48 && c <= 57) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
  }
  if (c === 101 || c === 69) { // 'e' / 'E'
    evalPos = evalPos + 1;
    c = evalPeek(s);
    if (c === 43 || c === 45) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
    while (c >= 48 && c <= 57) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
  }
  const tok: string = s.slice(start, evalPos);
  return dynNumber(parseFloat(tok));
}

function parseStringLit(s: string): i32 {
  const quote: i32 = evalPeek(s);
  evalPos = evalPos + 1; // skip opening quote
  let r: string = "";
  let go: i32 = 1;
  while (go === 1) {
    if (evalPos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(evalPos);
      if (c === quote) {
        evalPos = evalPos + 1;
        go = 0;
      } else if (c === 92) { // backslash escape
        evalPos = evalPos + 1;
        const e: i32 = s.charCodeAt(evalPos);
        let d: i32 = e;
        if (e === 110) d = 10; // \n
        else if (e === 116) d = 9; // \t
        else if (e === 114) d = 13; // \r
        r = r + String.fromCharCode(d);
        evalPos = evalPos + 1;
      } else {
        r = r + String.fromCharCode(c);
        evalPos = evalPos + 1;
      }
    }
  }
  return dynString(r);
}

function parsePrimary(s: string): i32 {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 40) { // '(' — parenthesized expr OR an arrow param list (#14 2e.3)
    if (isArrowAhead(s) === 1) {
      const ap: i32 = parseParams(s); // consumes `(...)`
      evalSkipWs(s);
      if (evalPeek(s) === 61 && evalPeek2(s) === 62) evalPos = evalPos + 2; // '=>'
      return makeUserFunc(ap, parseArrowBody(s), evalEnv);
    }
    evalPos = evalPos + 1;
    const v: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    return v;
  }
  if (c === 39 || c === 34) return parseStringLit(s); // ' or "
  if (c === 91) { // '[' — array literal (#14 2e.2)
    evalPos = evalPos + 1;
    const arr: i32 = dynArray();
    evalSkipWs(s);
    let go: i32 = evalPeek(s) === 93 ? 0 : 1; // empty []
    while (go === 1) {
      evalSkipWs(s);
      // #14 2e.5 spread: `...arr` splices that array's elements into this literal
      let isSpread: i32 = 0;
      if (evalPeek(s) === 46 && evalPeek2(s) === 46) {
        if (evalPos + 2 < s.length) {
          if (s.charCodeAt(evalPos + 2) === 46) isSpread = 1;
        }
      }
      if (isSpread === 1) {
        evalPos = evalPos + 3; // consume '...'
        const spreadArr: i32 = parseExpr(s);
        const sn: Int32Array = spreadArr as unknown as Int32Array;
        if (sn[0] === 5) { // array
          const slen: i32 = dynArrLen(spreadArr);
          let si: i32 = 0;
          while (si < slen) {
            dynPush(arr, dynArrGet(spreadArr, si));
            si = si + 1;
          }
        }
      } else {
        dynPush(arr, parseExpr(s));
      }
      evalSkipWs(s);
      if (evalPeek(s) === 44) {
        evalPos = evalPos + 1; // ','
        evalSkipWs(s);
        if (evalPeek(s) === 93) go = 0; // trailing comma
      } else {
        go = 0;
      }
    }
    evalSkipWs(s);
    if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
    return arr;
  }
  if (c === 123) { // '{' — object literal (#14 2e.2). At expression position `{` is always an object;
    evalPos = evalPos + 1; // statement-level `{` is handled as a block before reaching parseExpr.
    const obj: i32 = dynObject();
    evalSkipWs(s);
    let go: i32 = evalPeek(s) === 125 ? 0 : 1; // empty {}
    while (go === 1) {
      evalSkipWs(s);
      let key: string = "";
      const kc: i32 = evalPeek(s);
      if (kc === 39 || kc === 34) {
        key = boxToStr(parseStringLit(s)); // "quoted" key
      } else {
        key = readIdent(s); // bare identifier key
      }
      evalSkipWs(s);
      let val: i32 = 0;
      if (evalPeek(s) === 58) { // ':'
        evalPos = evalPos + 1;
        val = parseExpr(s);
      } else if (evalPeek(s) === 40) { // '(' → shorthand method `{ m(params) { body } }` (#14 2f.1)
        const mp: i32 = parseParams(s);
        evalSkipWs(s);
        val = makeUserFunc(mp, parseBlockBody(s), evalEnv);
      } else { // shorthand { x } → resolve x from the env
        val = evalEnv === -1 ? dynUndefined() : envLookup(evalEnv, key);
        if (val === -1) val = dynUndefined();
      }
      dynSet(obj, key, val);
      evalSkipWs(s);
      if (evalPeek(s) === 44) {
        evalPos = evalPos + 1; // ','
        evalSkipWs(s);
        if (evalPeek(s) === 125) go = 0; // trailing comma
      } else {
        go = 0;
      }
    }
    evalSkipWs(s);
    if (evalPeek(s) === 125) evalPos = evalPos + 1; // '}'
    return obj;
  }
  if (c === 96) { // '`' — template literal (#14 2e.2). Text parts are sliced raw (escape processing is
    evalPos = evalPos + 1; // a v1 gap); `${expr}` parts coerce to string via dynAdd (JS `+` semantics).
    let result: i32 = dynString("");
    let textStart: i32 = evalPos;
    let tgo: i32 = 1;
    while (tgo === 1) {
      const tc: i32 = evalPeek(s);
      if (tc === -1) {
        tgo = 0;
      } else if (tc === 96) { // closing '`'
        result = dynAdd(result, dynString(s.slice(textStart, evalPos)));
        evalPos = evalPos + 1;
        tgo = 0;
      } else if (tc === 36 && evalPeek2(s) === 123) { // '${'
        result = dynAdd(result, dynString(s.slice(textStart, evalPos)));
        evalPos = evalPos + 2;
        const ev: i32 = parseExpr(s);
        result = dynAdd(result, ev); // string + value → string
        evalSkipWs(s);
        if (evalPeek(s) === 125) evalPos = evalPos + 1; // '}'
        textStart = evalPos;
      } else {
        evalPos = evalPos + 1;
      }
    }
    return result;
  }
  if (c >= 48 && c <= 57) return parseNumLit(s);
  if (c === 46) return parseNumLit(s); // .5
  if (isIdentChar(c, 0) === 1) {
    // identifier / keyword: read the full [A-Za-z_$][A-Za-z0-9_$]* run, then dispatch
    const start: i32 = evalPos;
    let ch: i32 = c;
    while (isIdentChar(ch, 1) === 1) {
      evalPos = evalPos + 1;
      ch = evalPeek(s);
    }
    const name: string = s.slice(start, evalPos);
    if (strEq(name, "function") === 1) return parseFuncExpr(s); // #14 2e.3 function expression
    if (strEq(name, "true") === 1) return dynBool(1);
    if (strEq(name, "false") === 1) return dynBool(0);
    if (strEq(name, "null") === 1) return dynNull();
    if (strEq(name, "undefined") === 1) return dynUndefined();
    if (strEq(name, "Object") === 1) { // #14 2f.1 — Object.create(proto): new object with __proto__=proto
      const save: i32 = evalPos;
      evalSkipWs(s);
      if (evalPeek(s) === 46) { // '.'
        evalPos = evalPos + 1;
        const meth: string = readIdent(s);
        evalSkipWs(s);
        if (strEq(meth, "create") === 1 && evalPeek(s) === 40) {
          evalPos = evalPos + 1; // '('
          const proto: i32 = parseExpr(s);
          evalSkipWs(s);
          if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
          const o: i32 = dynObject();
          const on: Int32Array = o as unknown as Int32Array;
          const pn: Int32Array = proto as unknown as Int32Array;
          if (pn[0] === 6) on[2] = proto; // link the prototype (only when proto is an object)
          return o;
        }
      }
      evalPos = save; // not Object.create(…) — fall through to normal resolution
    }
    // #14 2e.3 — single-param arrow `name => body`
    evalSkipWs(s);
    if (evalPeek(s) === 61 && evalPeek2(s) === 62) {
      evalPos = evalPos + 2; // '=>'
      const ap: i32 = dynArray();
      dynPush(ap, dynString(name));
      return makeUserFunc(ap, parseArrowBody(s), evalEnv);
    }
    // a bare identifier → resolve via the scope chain (current env → parent → …)
    if (evalEnv === -1) return dynUndefined();
    const v: i32 = envLookup(evalEnv, name);
    return v === -1 ? dynUndefined() : v;
  }
  return dynUndefined(); // unrecognised → undefined (v1)
}

// Postfix member / index access: `expr.name`, `expr["key"]`, `arr[i]` (binds tighter than unary).
function parsePostfix(s: string): i32 {
  let v: i32 = parsePrimary(s);
  let go: i32 = 1;
  let recv: i32 = -1; // #14 2f.1: the receiver of the most recent member access → `this` for a method call
  let optDead: i32 = 0; // #14 2e.5: set once an optional `?.` hits a null/undefined receiver — the rest
  while (go === 1) { //                of the chain then short-circuits to undefined (still parsed).
    evalSkipWs(s);
    let c: i32 = evalPeek(s);
    let handled: i32 = 0;
    if (c === 63 && evalPeek2(s) === 46) { // `?.` optional chaining
      evalPos = evalPos + 2;
      if (optDead === 0) {
        const vn: Int32Array = v as unknown as Int32Array;
        const vt: i32 = vn[0];
        if (vt === 0 || vt === 1) optDead = 1; // null/undefined receiver → kill the chain
      }
      evalSkipWs(s);
      const ac: i32 = evalPeek(s); // access kind after `?.`: '[' (index) / ident (member) — inline.
      if (ac === 91) { // `?.[k]` optional index
        evalPos = evalPos + 1; // '['
        const oidx: i32 = parseExpr(s);
        evalSkipWs(s);
        if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
        recv = v;
        v = optDead === 1 ? dynUndefined() : dynIndexValue(v, oidx);
      } else { // `?.name` optional member
        const start: i32 = evalPos;
        let ch: i32 = evalPeek(s);
        while (isIdentChar(ch, 1) === 1) {
          evalPos = evalPos + 1;
          ch = evalPeek(s);
        }
        const name: string = s.slice(start, evalPos);
        recv = v;
        v = optDead === 1 ? dynUndefined() : dynMember(v, name);
      }
      handled = 1; // optional access done — keep looping for any further chain
    }
    if (handled === 1) {
      // `?.name` already applied above — fall back to the loop for any further access
    } else if (c === 46) { // .name
      evalPos = evalPos + 1;
      evalSkipWs(s);
      const start: i32 = evalPos;
      let ch: i32 = evalPeek(s);
      while (isIdentChar(ch, 1) === 1) {
        evalPos = evalPos + 1;
        ch = evalPeek(s);
      }
      const name: string = s.slice(start, evalPos);
      recv = v; // #14 2f.1 — receiver for a following `obj.name(args)` method call
      v = optDead === 1 ? dynUndefined() : dynMember(v, name);
    } else if (c === 91) { // [expr]
      evalPos = evalPos + 1;
      const idx: i32 = parseExpr(s);
      evalSkipWs(s);
      if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
      recv = v;
      v = optDead === 1 ? dynUndefined() : dynIndexValue(v, idx);
    } else if (c === 40) { // (args)  — call
      evalPos = evalPos + 1;
      // #14 GC P5b: the callee `v` and the args array (holding already-evaluated args) are live across
      // the parsing of further args AND the call — both can run user functions that trigger a
      // collection — so keep them rooted until the call returns.
      gcPushRoot(v);
      const hasRecv: i32 = recv !== -1 ? 1 : 0; // #14 2f.1 — method call → bind the receiver as `this`
      if (hasRecv === 1) gcPushRoot(recv);
      const argsArr: i32 = dynArray();
      gcPushRoot(argsArr);
      evalSkipWs(s);
      if (evalPeek(s) === 41) {
        evalPos = evalPos + 1; // ()
      } else {
        let more: i32 = 1;
        while (more === 1) {
          const a: i32 = parseExpr(s);
          dynPush(argsArr, a);
          evalSkipWs(s);
          const cc: i32 = evalPeek(s);
          if (cc === 44) {
            evalPos = evalPos + 1; // ','
          } else {
            if (cc === 41) evalPos = evalPos + 1; // ')'
            more = 0;
          }
        }
      }
      // The CALL is the only side-effecting op: skip the dispatch in a dead (short-circuited)
      // branch or a killed optional chain, but still parse the args above so the cursor advances.
      if (evalLive === 1 && optDead === 0) {
        if (hasRecv === 1) v = dynApplyThis(v, argsArr, recv);
        else v = dynApply(v, argsArr);
      } else {
        v = dynUndefined();
      }
      gcPopRoot(); // argsArr
      if (hasRecv === 1) gcPopRoot(); // recv
      gcPopRoot(); // v
      recv = -1; // a call result is not itself a receiver until a further member access
    } else {
      go = 0;
    }
  }
  return v;
}

// #14 2e.5 — `typeof v` as a string value. typeof null === "object" (the JS quirk); array/object → object.
function dynTypeofStr(v: i32): i32 {
  const vn: Int32Array = v as unknown as Int32Array;
  const t: i32 = vn[0];
  if (t === 0) return dynString("undefined");
  if (t === 2) return dynString("boolean");
  if (t === 3) return dynString("number");
  if (t === 4) return dynString("string");
  if (t === 7) return dynString("function");
  return dynString("object"); // null (1) / array (5) / object (6)
}

function parseUnary(s: string): i32 {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 45) { // -x
    evalPos = evalPos + 1;
    return dynNeg(parseUnary(s));
  }
  if (c === 33) { // !x
    evalPos = evalPos + 1;
    return dynNot(parseUnary(s));
  }
  if (c === 43) { // +x → ToNumber
    evalPos = evalPos + 1;
    const v: i32 = parseUnary(s);
    return dynNumber(dynToNumber(v));
  }
  if (c === 116) { // 't' — maybe the `typeof` operator (#14 2e.5)
    const save: i32 = evalPos;
    const w: string = readIdent(s);
    if (strEq(w, "typeof") === 1) return dynTypeofStr(parseUnary(s));
    evalPos = save; // not typeof — restore and fall through
  }
  return parsePostfix(s);
}

function parseMul(s: string): i32 {
  let left: i32 = parseUnary(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 42 || c === 47 || c === 37) { // * / %
      evalPos = evalPos + 1;
      gcPushRoot(left); // keep the accumulated operand alive across the right-operand parse — which
      const r: i32 = parseUnary(s); // may run a user function → nested collection (#14 GC Part 5b)
      gcPopRoot();
      if (c === 42) {
        left = dynMul(left, r);
      } else if (c === 47) {
        left = dynDiv(left, r);
      } else {
        left = dynMod(left, r);
      }
    } else {
      go = 0;
    }
  }
  return left;
}

function parseAdd(s: string): i32 {
  let left: i32 = parseMul(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 43 || c === 45) { // + -
      evalPos = evalPos + 1;
      gcPushRoot(left); // protect the accumulated operand across the right-operand parse (#14 GC P5b)
      const r: i32 = parseMul(s);
      gcPopRoot();
      if (c === 43) {
        left = dynAdd(left, r);
      } else {
        left = dynSub(left, r);
      }
    } else {
      go = 0;
    }
  }
  return left;
}

function parseRel(s: string): i32 {
  let left: i32 = parseAdd(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    const c2: i32 = evalPeek2(s);
    if (c === 60 || c === 62) { // < <= > >=
      const isLt: i32 = c === 60 ? 1 : 0;
      const orEq: i32 = c2 === 61 ? 1 : 0;
      evalPos = orEq === 1 ? evalPos + 2 : evalPos + 1;
      gcPushRoot(left); // protect the accumulated operand across the right-operand parse (#14 GC P5b)
      const r: i32 = parseAdd(s);
      gcPopRoot();
      if (isLt === 1) {
        left = orEq === 1 ? dynLe(left, r) : dynLt(left, r);
      } else {
        left = orEq === 1 ? dynGe(left, r) : dynGt(left, r);
      }
    } else {
      go = 0;
    }
  }
  return left;
}

function parseEq(s: string): i32 {
  let left: i32 = parseRel(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    const c2: i32 = evalPeek2(s);
    if (c === 61 && c2 === 61) { // == or ===
      evalPos = evalPos + 2;
      if (evalPeek(s) === 61) evalPos = evalPos + 1; // consume the 3rd '='
      gcPushRoot(left); // #14 GC P5b: protect left across the right-operand parse
      const right: i32 = parseRel(s);
      gcPopRoot();
      left = dynBool(dynStrictEq(left, right));
    } else if (c === 33 && c2 === 61) { // != or !==
      evalPos = evalPos + 2;
      if (evalPeek(s) === 61) evalPos = evalPos + 1; // consume the 3rd '='
      gcPushRoot(left); // #14 GC P5b: protect left across the right-operand parse
      const right: i32 = parseRel(s);
      gcPopRoot();
      left = dynBool(dynStrictEq(left, right) === 0 ? 1 : 0);
    } else {
      go = 0;
    }
  }
  return left;
}

function parseAnd(s: string): i32 {
  let left: i32 = parseEq(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    if (evalPeek(s) === 38 && evalPeek2(s) === 38) { // &&
      evalPos = evalPos + 2;
      // a && b → b if truthy(a) else a. Right is dead (no effects) when left is falsy.
      const takeRight: i32 = dynToBool(left);
      const saved: i32 = evalLive;
      if (takeRight === 0) evalLive = 0;
      gcPushRoot(left); // #14 GC P5b: protect left across the right-operand parse
      const right: i32 = parseEq(s);
      gcPopRoot();
      evalLive = saved;
      if (takeRight === 1) left = right;
    } else {
      go = 0;
    }
  }
  return left;
}

function parseOr(s: string): i32 {
  let left: i32 = parseAnd(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    if (evalPeek(s) === 124 && evalPeek2(s) === 124) { // ||
      evalPos = evalPos + 2;
      // a || b → a if truthy(a) else b. Right is dead when left is truthy.
      const leftTruthy: i32 = dynToBool(left);
      const saved: i32 = evalLive;
      if (leftTruthy === 1) evalLive = 0;
      gcPushRoot(left); // #14 GC P5b: protect left across the right-operand parse
      const right: i32 = parseAnd(s);
      gcPopRoot();
      evalLive = saved;
      if (leftTruthy === 0) left = right;
    } else if (evalPeek(s) === 63 && evalPeek2(s) === 63) { // ?? nullish coalescing (#14 2e.5)
      evalPos = evalPos + 2;
      // a ?? b → a unless a is null/undefined, then b. Right is dead when left is non-nullish.
      const ln: Int32Array = left as unknown as Int32Array;
      const lt: i32 = ln[0];
      const leftNullish: i32 = (lt === 0 || lt === 1) ? 1 : 0;
      const saved: i32 = evalLive;
      if (leftNullish === 0) evalLive = 0;
      gcPushRoot(left);
      const right: i32 = parseAnd(s);
      gcPopRoot();
      evalLive = saved;
      if (leftNullish === 1) left = right;
    } else {
      go = 0;
    }
  }
  return left;
}

function parseExpr(s: string): i32 {
  const cond: i32 = parseOr(s);
  evalSkipWs(s);
  if (evalPeek(s) === 63) { // ? :
    evalPos = evalPos + 1;
    const c: i32 = dynToBool(cond);
    const saved: i32 = evalLive;
    // then-branch dead when cond is falsy
    if (c === 0) evalLive = 0;
    const thenV: i32 = parseExpr(s);
    evalLive = saved;
    evalSkipWs(s);
    if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
    // else-branch dead when cond is truthy
    if (c === 1) evalLive = 0;
    gcPushRoot(thenV); // #14 GC P5b: protect the then-value across the else-branch parse
    const elseV: i32 = parseExpr(s);
    gcPopRoot();
    evalLive = saved;
    return c === 1 ? thenV : elseV;
  }
  return cond;
}

/** Evaluate a JS expression string with no environment → boxed value handle. */
/** @export */
export function dynEval(s: string): i32 {
  evalPos = 0;
  evalEnv = -1;
  evalLive = 1;
  return parseExpr(s);
}

/**
 * Evaluate a JS expression string against an environment object (`env`: names → boxed values), so
 * the expression may reference variables and navigate them with `.prop` / `[i]` / `["key"]`.
 */
/** @export */
export function dynEvalEnv(s: string, env: i32): i32 {
  evalPos = 0;
  evalEnv = env;
  evalLive = 1;
  return parseExpr(s);
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2d.1 — STATEMENTS + control flow (`dynRun`).
//
// A statement interpreter layered on the 2a–2c expression evaluator. Declarations and assignments
// mutate the (single, flat) environment object via `dynSet`. Control flow uses the same DIRECT-eval
// re-parse trick: `while` re-sets `evalPos` to the condition start each iteration and re-parses the
// condition + body (so it costs O(body × iterations) to parse, but needs no AST); dead branches of
// `if`/`while` are parsed with `evalLive = 0` (execute nothing, just advance the cursor — reusing
// the 2c short-circuit machinery). `return` sets `evalReturned`, which stops sequencing.
// (2d.1 had NO block scoping — all decls landed in one env; #14 2e.7 added lexical scoping: each
// `{ }` block / loop / catch runs in a fresh child scope, and `x = v` walks the chain via `envAssign`.)
// ──────────────────────────────────────────────────────────────────────────────────────────────

// Read an identifier run at the cursor, advancing past it; returns the name.
function readIdent(s: string): string {
  const start: i32 = evalPos;
  let ch: i32 = evalPeek(s);
  while (isIdentChar(ch, 1) === 1) {
    evalPos = evalPos + 1;
    ch = evalPeek(s);
  }
  return s.slice(start, evalPos);
}

// `let`/`const`/`var name [= expr];` — the keyword has already been consumed.
function runDecl(s: string): void {
  evalSkipWs(s);
  const name: string = readIdent(s);
  evalSkipWs(s);
  let val: i32 = dynUndefined();
  if (evalPeek(s) === 61) { // '='
    evalPos = evalPos + 1;
    val = parseExpr(s);
  }
  if (evalLive === 1) dynSet(evalEnv, name, val);
  evalSkipWs(s);
  if (evalPeek(s) === 59) evalPos = evalPos + 1; // ';'
}

// `return [expr];` — the keyword has already been consumed.
function runReturn(s: string): void {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  let val: i32 = dynUndefined();
  if (c !== 59 && c !== 125 && c !== -1) { // not ';' '}' EOF
    val = parseExpr(s);
  }
  if (evalLive === 1) {
    evalReturnVal = val;
    evalReturned = 1;
  }
  evalSkipWs(s);
  if (evalPeek(s) === 59) evalPos = evalPos + 1;
}

// `if (cond) stmt [else stmt]` — the `if` keyword has already been consumed.
function runIf(s: string): void {
  const outer: i32 = evalLive;
  evalSkipWs(s);
  if (evalPeek(s) === 40) evalPos = evalPos + 1; // '('
  const cond: i32 = parseExpr(s);
  evalSkipWs(s);
  if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
  const ct: i32 = (outer === 1 && dynToBool(cond) === 1) ? 1 : 0;
  evalLive = (outer === 1 && ct === 1) ? 1 : 0;
  runStatement(s); // then
  evalLive = outer;
  evalSkipWs(s);
  if (isIdentChar(evalPeek(s), 0) === 1) {
    const es: i32 = evalPos;
    const w: string = readIdent(s);
    if (strEq(w, "else") === 1) {
      evalLive = (outer === 1 && ct === 0) ? 1 : 0;
      runStatement(s); // else
      evalLive = outer;
    } else {
      evalPos = es; // not `else` — rewind
    }
  }
}

// `while (cond) stmt` — the `while` keyword has already been consumed.
function runWhile(s: string): void {
  const outer: i32 = evalLive;
  evalSkipWs(s);
  if (evalPeek(s) === 40) evalPos = evalPos + 1; // '('
  const condStart: i32 = evalPos;
  let looping: i32 = 1;
  let iters: i32 = 0;
  while (looping === 1) {
    evalPos = condStart;
    const cond: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    const run: i32 = (outer === 1 && dynToBool(cond) === 1) ? 1 : 0;
    if (run === 1) {
      evalLive = 1;
      runStatement(s); // body, live
      evalLive = outer;
      if (evalReturned === 1 || evalThrew === 1) {
        looping = 0; // a `return` in the body ends the loop
      } else if (evalBroke === 1) {
        evalBroke = 0; // `break` — clear + stop
        looping = 0;
      } else if (evalContinued === 1) {
        evalContinued = 0; // `continue` — clear + fall through to re-test the condition
      }
      iters = iters + 1;
      if (iters > 100000000) looping = 0; // safety cap against a runaway loop
    } else {
      evalLive = 0;
      runStatement(s); // body, dead — advance the cursor past it, then stop
      evalLive = outer;
      looping = 0;
    }
  }
}

// #14 2e.1 — `do { body } while (cond);`. Re-parses the body + the trailing `while (cond)` each
// iteration (same cursor-reset model as runWhile). The body runs at least once.
function runDoWhile(s: string): void {
  const outer: i32 = evalLive;
  evalSkipWs(s);
  const bodyStart: i32 = evalPos;
  let looping: i32 = 1;
  let iters: i32 = 0;
  while (looping === 1) {
    evalPos = bodyStart;
    evalLive = outer;
    runStatement(s); // body
    evalLive = outer;
    // trailing `while ( cond )` — re-parse it so the cursor lands past the whole statement
    evalSkipWs(s);
    if (isIdentChar(evalPeek(s), 0) === 1) readIdent(s); // 'while'
    evalSkipWs(s);
    if (evalPeek(s) === 40) evalPos = evalPos + 1; // '('
    const cond: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    evalSkipWs(s);
    if (evalPeek(s) === 59) evalPos = evalPos + 1; // optional ';'
    if (outer === 0) {
      looping = 0;
    } else if (evalReturned === 1 || evalThrew === 1) {
      looping = 0;
    } else if (evalBroke === 1) {
      evalBroke = 0;
      looping = 0;
    } else {
      if (evalContinued === 1) evalContinued = 0;
      looping = dynToBool(cond) === 1 ? 1 : 0;
    }
    iters = iters + 1;
    if (iters > 100000000) looping = 0;
  }
}

// #14 2e.1 — `for (...)`. Detects `for (decl? x of iterable)` (for-of) vs C-style `for (init; cond;
// update)` by reading the header; dispatches to the matching runner.
function runFor(s: string): void {
  const outer: i32 = evalLive;
  // #14 2e.7 — the loop variable (and any C-style init decl) is scoped to the loop, not leaked.
  const parentEnv: i32 = evalEnv;
  const loopEnv: i32 = childEnv(parentEnv);
  evalEnv = loopEnv;
  gcPushRoot(loopEnv);
  evalSkipWs(s);
  if (evalPeek(s) === 40) evalPos = evalPos + 1; // '('
  const save: i32 = evalPos;
  evalSkipWs(s);
  let kind: i32 = 0; // 0 = C-style, 1 = for-of, 2 = for-in
  let loopVar: string = "";
  let perIter: i32 = 0; // #14 2e.7a — 1 when the loop var is let/const → a fresh binding per iteration
  if (isIdentChar(evalPeek(s), 0) === 1) {
    const w1: string = readIdent(s);
    let nameWord: string = w1;
    if (strEq(w1, "const") === 1 || strEq(w1, "let") === 1 || strEq(w1, "var") === 1) {
      if (strEq(w1, "var") !== 1) perIter = 1; // let/const are per-iteration; `var` stays shared
      evalSkipWs(s);
      nameWord = readIdent(s);
    }
    evalSkipWs(s);
    if (isIdentChar(evalPeek(s), 0) === 1) {
      const w2: string = readIdent(s);
      if (strEq(w2, "of") === 1) {
        kind = 1;
        loopVar = nameWord;
      } else if (strEq(w2, "in") === 1) {
        kind = 2;
        loopVar = nameWord;
      }
    }
  }
  if (kind === 1) {
    runForOf(s, loopVar, outer, perIter);
  } else if (kind === 2) {
    runForIn(s, loopVar, outer, perIter);
  } else {
    evalPos = save;
    runForClassic(s, outer, perIter);
  }
  gcPopRoot();
  evalEnv = parentEnv; // #14 2e.7 — drop the loop scope (loop var no longer visible)
}

// `for (const k in obj) body` — iterate an object's keys (tag 6), binding `k` to each key string.
function runForIn(s: string, loopVar: string, outer: i32, perIter: i32): void {
  const loopEnv2: i32 = evalEnv; // #14 2e.7a — parent for per-iteration binding envs
  const obj: i32 = parseExpr(s); // the object (cursor was just past `in`)
  evalSkipWs(s);
  if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
  const bodyStart: i32 = evalPos;
  let len: i32 = 0;
  const ov: Int32Array = obj as unknown as Int32Array;
  if (outer === 1 && ov[0] === 6) len = dynObjLen(obj); // tag 6 = object
  let looping: i32 = (outer === 1 && len > 0) ? 1 : 0;
  if (looping === 0) {
    evalLive = 0;
    evalPos = bodyStart;
    runStatement(s); // dead body — advance past it
    evalLive = outer;
    return;
  }
  let i: i32 = 0;
  while (looping === 1) {
    let bindEnv: i32 = loopEnv2; // shared (perIter=0) → bind in the loop env, as before
    if (perIter === 1) bindEnv = childEnv(loopEnv2); // fresh binding this iteration
    dynSet(bindEnv, loopVar, dynObjKeyVal(obj, i)); // bind the key string
    evalEnv = bindEnv;
    evalPos = bodyStart;
    evalLive = 1;
    runStatement(s);
    evalLive = outer;
    evalEnv = loopEnv2;
    if (evalReturned === 1 || evalThrew === 1) {
      looping = 0;
    } else if (evalBroke === 1) {
      evalBroke = 0;
      looping = 0;
    } else {
      if (evalContinued === 1) evalContinued = 0;
      i = i + 1;
      if (i >= len) looping = 0;
    }
  }
}

// `for (const x of arr) body` — iterate an array value (tag 5). With a let/const loop var (perIter=1)
// each iteration gets a FRESH binding (so a closure in the body captures that element); `var` shares.
function runForOf(s: string, loopVar: string, outer: i32, perIter: i32): void {
  const loopEnv2: i32 = evalEnv; // #14 2e.7a — parent for per-iteration binding envs
  const arr: i32 = parseExpr(s); // the iterable (cursor was just past `of`)
  evalSkipWs(s);
  if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
  const bodyStart: i32 = evalPos;
  let len: i32 = 0;
  const av: Int32Array = arr as unknown as Int32Array;
  if (outer === 1 && av[0] === 5) len = dynArrLen(arr); // tag 5 = array
  let looping: i32 = (outer === 1 && len > 0) ? 1 : 0;
  if (looping === 0) {
    evalLive = 0;
    evalPos = bodyStart;
    runStatement(s); // dead body — advance the cursor past it
    evalLive = outer;
    return;
  }
  let i: i32 = 0;
  while (looping === 1) {
    let bindEnv: i32 = loopEnv2; // shared (perIter=0) → bind in the loop env, as before
    if (perIter === 1) bindEnv = childEnv(loopEnv2); // fresh binding this iteration
    dynSet(bindEnv, loopVar, dynArrGet(arr, i));
    evalEnv = bindEnv;
    evalPos = bodyStart;
    evalLive = 1;
    runStatement(s);
    evalLive = outer;
    evalEnv = loopEnv2;
    if (evalReturned === 1 || evalThrew === 1) {
      looping = 0;
    } else if (evalBroke === 1) {
      evalBroke = 0;
      looping = 0;
    } else {
      if (evalContinued === 1) evalContinued = 0;
      i = i + 1;
      if (i >= len) looping = 0;
    }
  }
}

// C-style `for (init; cond; update) body`. The cursor is at the init clause. Re-parses cond/update/
// body each iteration (cursor-reset). init + update reuse runStatement (which handles assignment /
// `++` / `+=` / bare expr); cond is a bare expression; any clause may be empty.
function runForClassic(s: string, outer: i32, perIter: i32): void {
  const loopEnv2: i32 = evalEnv; // init declares the loop var(s) here
  const len2: Int32Array = loopEnv2 as unknown as Int32Array;
  const parent2: i32 = len2[2]; // the loop's enclosing scope (per-iteration clones chain to it)
  evalLive = outer;
  runStatement(s); // init (consumes its own ';')
  const condStart: i32 = evalPos;
  // #14 2e.7a — with let/const (perIter), cond+body run against a fresh copy of the loop vars each
  // iteration, and the update runs against the NEXT copy — so a closure made in the body keeps the
  // value it saw (JS `let` loop semantics) instead of the shared/final value.
  let curEnv: i32 = loopEnv2;
  if (perIter === 1) curEnv = cloneEnvFlat(loopEnv2, parent2);
  let looping: i32 = 1;
  let iters: i32 = 0;
  while (looping === 1) {
    evalEnv = curEnv;
    evalPos = condStart;
    evalSkipWs(s);
    let condTrue: i32 = 1; // empty cond → true
    if (evalPeek(s) !== 59) condTrue = dynToBool(parseExpr(s));
    evalSkipWs(s);
    if (evalPeek(s) === 59) evalPos = evalPos + 1; // ';' after cond
    const updateStart: i32 = evalPos;
    // skip the update (dead) to locate the body start
    evalLive = 0;
    if (evalPeek(s) !== 41) runStatement(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    const bodyStart: i32 = evalPos;
    const run: i32 = (outer === 1 && condTrue === 1) ? 1 : 0;
    if (run === 1) {
      evalEnv = curEnv;
      evalPos = bodyStart;
      evalLive = 1;
      runStatement(s); // body, live (captures curEnv)
      evalLive = outer;
      if (evalReturned === 1 || evalThrew === 1) {
        looping = 0;
      } else if (evalBroke === 1) {
        evalBroke = 0;
        looping = 0;
      } else {
        if (evalContinued === 1) evalContinued = 0;
        let nextEnv: i32 = curEnv;
        if (perIter === 1) nextEnv = cloneEnvFlat(curEnv, parent2); // fresh env for the next iteration
        evalEnv = nextEnv;
        evalPos = updateStart; // run the update, live (mutates the NEXT env)
        evalLive = outer;
        if (evalPeek(s) !== 41) runStatement(s);
        evalLive = outer;
        curEnv = nextEnv;
      }
      iters = iters + 1;
      if (iters > 100000000) looping = 0;
    } else {
      evalEnv = curEnv;
      evalPos = bodyStart;
      evalLive = 0;
      runStatement(s); // dead body — advance past it
      evalLive = outer;
      looping = 0;
    }
  }
  evalEnv = loopEnv2; // restore (runFor resets to the enclosing scope after)
}

// #14 2e.1 — `switch (disc) { case v: … default: … }`. Two passes over the body: (1) DEAD scan the
// labels, evaluating each `case` expr `=== disc` to find the matching case's body start (and the
// default's); (2) execute LIVE from that start with FALL-THROUGH (later case/default labels are
// skipped, statements run) until `break`/`return` or `}`. `break` exits the switch only.
function runSwitch(s: string): void {
  const outer: i32 = evalLive;
  evalSkipWs(s);
  if (evalPeek(s) === 40) evalPos = evalPos + 1; // '('
  const disc: i32 = parseExpr(s);
  evalSkipWs(s);
  if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
  evalSkipWs(s);
  if (evalPeek(s) === 123) evalPos = evalPos + 1; // '{'
  let matchStart: i32 = -1;
  let defaultStart: i32 = -1;
  let scanning: i32 = 1;
  while (scanning === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 125 || c === -1) {
      scanning = 0;
    } else if (isIdentChar(c, 0) === 1) {
      const save: i32 = evalPos;
      const w: string = readIdent(s);
      if (strEq(w, "case") === 1) {
        if (matchStart === -1) {
          const cv: i32 = parseExpr(s);
          evalSkipWs(s);
          if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
          if (dynStrictEq(disc, cv) === 1) matchStart = evalPos; // dynStrictEq returns raw i32 1/0
        } else {
          const sl: i32 = evalLive; // already matched — skip the case expr dead
          evalLive = 0;
          parseExpr(s);
          evalLive = sl;
          evalSkipWs(s);
          if (evalPeek(s) === 58) evalPos = evalPos + 1;
        }
        skipSwitchSegment(s);
      } else if (strEq(w, "default") === 1) {
        evalSkipWs(s);
        if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
        defaultStart = evalPos;
        skipSwitchSegment(s);
      } else {
        evalPos = save;
        skipSwitchSegment(s); // stray statement before a label — skip dead
      }
    } else {
      scanning = 0;
    }
  }
  const switchEnd: i32 = evalPos; // at '}'
  let startPos: i32 = matchStart;
  if (startPos === -1) startPos = defaultStart;
  if (outer === 1 && startPos !== -1) {
    evalPos = startPos;
    evalLive = 1;
    execSwitchBody(s);
    evalLive = outer;
  }
  evalPos = switchEnd; // cursor past the whole body, regardless of where pass 2 stopped
  evalSkipWs(s);
  if (evalPeek(s) === 125) evalPos = evalPos + 1; // '}'
  if (evalBroke === 1) evalBroke = 0; // `break` exits the switch only — clear it
}

// Skip statements (DEAD) until the next case/default label or '}'; leaves the label for the caller.
function skipSwitchSegment(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 125 || c === -1) {
      go = 0;
    } else if (isIdentChar(c, 0) === 1) {
      const save: i32 = evalPos;
      const w: string = readIdent(s);
      if (strEq(w, "case") === 1 || strEq(w, "default") === 1) {
        evalPos = save; // leave the label
        go = 0;
      } else {
        evalPos = save;
        const sl: i32 = evalLive;
        evalLive = 0;
        runStatement(s);
        evalLive = sl;
      }
    } else {
      const sl: i32 = evalLive;
      evalLive = 0;
      runStatement(s);
      evalLive = sl;
    }
  }
}

// Execute statements (LIVE) with fall-through: skip case/default labels, run everything else, until
// `break`/`return`/`continue` or '}'.
function execSwitchBody(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 125 || c === -1) {
      go = 0;
    } else if (isIdentChar(c, 0) === 1) {
      const save: i32 = evalPos;
      const w: string = readIdent(s);
      if (strEq(w, "case") === 1) {
        const sl: i32 = evalLive;
        evalLive = 0;
        parseExpr(s); // skip the case expr (dead)
        evalLive = sl;
        evalSkipWs(s);
        if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
      } else if (strEq(w, "default") === 1) {
        evalSkipWs(s);
        if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
      } else {
        evalPos = save;
        runStatement(s);
      }
    } else {
      runStatement(s);
    }
    if (evalBroke === 1) go = 0; // break — runSwitch clears it
    if (evalReturned === 1) go = 0;
    if (evalThrew === 1) go = 0; // #14 2e.6: a throw exits the switch (and unwinds)
    if (evalContinued === 1) go = 0; // continue propagates to the enclosing loop
  }
}

// #14 2e.6 — `try { … } [catch (e) { … }] [finally { … }]`. Runs the try block; if it threw and a
// catch is present, clears the throw, binds `e`, runs the catch; runs finally last (it overrides any
// in-flight throw/return). `throw` sets evalThrew, which unwinds until caught here.
function runTry(s: string): void {
  const outer: i32 = evalLive;
  evalSkipWs(s);
  evalLive = outer;
  runStatement(s); // the `{ … }` try block
  evalLive = outer;

  // optional `catch (e)`
  evalSkipWs(s);
  let hasCatch: i32 = 0;
  const saveCatch: i32 = evalPos;
  if (isIdentChar(evalPeek(s), 0) === 1) {
    const w: string = readIdent(s);
    if (strEq(w, "catch") === 1) hasCatch = 1;
    else evalPos = saveCatch;
  }
  if (hasCatch === 1) {
    let catchVar: string = "";
    evalSkipWs(s);
    if (evalPeek(s) === 40) { // '(e)'
      evalPos = evalPos + 1;
      evalSkipWs(s);
      catchVar = readIdent(s);
      evalSkipWs(s);
      if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    }
    evalSkipWs(s);
    if (evalThrew === 1 && outer === 1) {
      const tv: i32 = evalThrowVal;
      evalThrew = 0; // caught
      // #14 2e.7 — bind `e` in a FRESH catch scope so it does not leak past the catch block.
      const catchParent: i32 = evalEnv;
      const catchEnv: i32 = childEnv(catchParent);
      if (catchVar.length > 0) dynSet(catchEnv, catchVar, tv);
      evalEnv = catchEnv;
      gcPushRoot(catchEnv);
      evalLive = 1;
      runStatement(s); // catch block
      gcPopRoot();
      evalEnv = catchParent;
      evalLive = outer;
    } else {
      evalLive = 0;
      runStatement(s); // dead — advance past the catch block
      evalLive = outer;
    }
  }

  // optional `finally`
  evalSkipWs(s);
  let hasFinally: i32 = 0;
  const saveFin: i32 = evalPos;
  if (isIdentChar(evalPeek(s), 0) === 1) {
    const w2: string = readIdent(s);
    if (strEq(w2, "finally") === 1) hasFinally = 1;
    else evalPos = saveFin;
  }
  if (hasFinally === 1) {
    // save in-flight control from try/catch; run finally with it cleared; restore unless finally
    // produced its own control flow (which then wins, per JS).
    const sThrew: i32 = evalThrew;
    const sThrowVal: i32 = evalThrowVal;
    const sRet: i32 = evalReturned;
    const sRetVal: i32 = evalReturnVal;
    const sBroke: i32 = evalBroke;
    const sCont: i32 = evalContinued;
    evalThrew = 0;
    evalReturned = 0;
    evalBroke = 0;
    evalContinued = 0;
    evalSkipWs(s);
    evalLive = outer;
    runStatement(s); // finally block
    evalLive = outer;
    if (evalThrew === 0 && evalReturned === 0 && evalBroke === 0 && evalContinued === 0) {
      evalThrew = sThrew;
      evalThrowVal = sThrowVal;
      evalReturned = sRet;
      evalReturnVal = sRetVal;
      evalBroke = sBroke;
      evalContinued = sCont;
    }
  }
}

// `function name(p0, p1, …) { body }` — the `function` keyword has already been consumed. Captures
// the body's SOURCE TEXT (depth-scanning to the matching `}`, string-literal aware) into a string
// box and binds a user function value (closing over the current env) under `name`.
// Parse a `(p0, p1, …)` parameter list (cursor at `(`) → value-model array of name string boxes.
// If there is no `(`, returns an empty array (cursor unchanged).
function parseParams(s: string): i32 {
  const paramsArr: i32 = dynArray();
  if (evalPeek(s) === 40) { // '('
    evalPos = evalPos + 1;
    evalSkipWs(s);
    if (evalPeek(s) === 41) {
      evalPos = evalPos + 1; // ()
    } else {
      let more: i32 = 1;
      while (more === 1) {
        evalSkipWs(s);
        const pn: string = readIdent(s);
        dynPush(paramsArr, dynString(pn));
        evalSkipWs(s);
        const cc: i32 = evalPeek(s);
        if (cc === 44) {
          evalPos = evalPos + 1; // ','
        } else {
          if (cc === 41) evalPos = evalPos + 1; // ')'
          more = 0;
        }
      }
    }
  }
  return paramsArr;
}

// Capture a `{ … }` block's INNER source (cursor at `{`) into a string box, depth-scanning to the
// matching `}` (string-literal aware) and consuming the closing brace.
function parseBlockBody(s: string): i32 {
  evalPos = evalPos + 1; // '{'
  const bodyStart: i32 = evalPos;
  let depth: i32 = 1;
  let inStr: i32 = 0;
  let q: i32 = 0;
  let scanning: i32 = 1;
  while (scanning === 1 && evalPos < s.length) {
    const ch: i32 = s.charCodeAt(evalPos);
    if (inStr === 1) {
      if (ch === 92) {
        evalPos = evalPos + 2; // backslash: skip the escaped char
      } else if (ch === q) {
        inStr = 0;
        evalPos = evalPos + 1;
      } else {
        evalPos = evalPos + 1;
      }
    } else {
      if (ch === 39 || ch === 34) {
        inStr = 1;
        q = ch;
        evalPos = evalPos + 1;
      } else if (ch === 123) {
        depth = depth + 1;
        evalPos = evalPos + 1;
      } else if (ch === 125) {
        depth = depth - 1;
        if (depth === 0) scanning = 0; // leave evalPos AT the closing '}'
        else evalPos = evalPos + 1;
      } else {
        evalPos = evalPos + 1;
      }
    }
  }
  const bodySrc: string = s.slice(bodyStart, evalPos);
  if (evalPeek(s) === 125) evalPos = evalPos + 1; // consume '}'
  return dynString(bodySrc);
}

// #14 2e.3 — body after an arrow `=>` (cursor just past `=>`). Block body → its inner source; an
// expression body → the expr SOURCE captured by dead-parsing to find its extent (when the arrow is
// called, dynRun returns the last expression value, so a bare expr body works without a `return`).
function parseArrowBody(s: string): i32 {
  evalSkipWs(s);
  if (evalPeek(s) === 123) return parseBlockBody(s); // '{' block body
  const exprStart: i32 = evalPos;
  const sl: i32 = evalLive;
  evalLive = 0;
  parseExpr(s); // dead-parse to locate the expression boundary (stops at , ) ] } ; …)
  evalLive = sl;
  return dynString(s.slice(exprStart, evalPos));
}

// #14 2e.3 — anonymous function expression (cursor past the `function` keyword): optional name (ignored
// in v1 — no self-reference binding yet), `(params)`, `{ body }`. Closes over the current env.
function parseFuncExpr(s: string): i32 {
  evalSkipWs(s);
  if (isIdentChar(evalPeek(s), 0) === 1) readIdent(s); // optional name, skipped
  evalSkipWs(s);
  const paramsArr: i32 = parseParams(s);
  evalSkipWs(s);
  let bodyBox: i32 = dynString("");
  if (evalPeek(s) === 123) bodyBox = parseBlockBody(s);
  return makeUserFunc(paramsArr, bodyBox, evalEnv);
}

// #14 2e.3 — lookahead from a `(` to decide arrow-param-list vs parenthesized expr: scan to the
// matching `)` (string-aware), then check for `=>`. Restores the cursor. Returns 1 if an arrow.
function isArrowAhead(s: string): i32 {
  const save: i32 = evalPos;
  let depth: i32 = 0;
  let inStr: i32 = 0;
  let q: i32 = 0;
  let scanning: i32 = 1;
  while (scanning === 1 && evalPos < s.length) {
    const ch: i32 = s.charCodeAt(evalPos);
    if (inStr === 1) {
      if (ch === 92) {
        evalPos = evalPos + 2;
      } else if (ch === q) {
        inStr = 0;
        evalPos = evalPos + 1;
      } else {
        evalPos = evalPos + 1;
      }
    } else {
      if (ch === 39 || ch === 34) {
        inStr = 1;
        q = ch;
        evalPos = evalPos + 1;
      } else if (ch === 40) {
        depth = depth + 1;
        evalPos = evalPos + 1;
      } else if (ch === 41) {
        depth = depth - 1;
        evalPos = evalPos + 1;
        if (depth === 0) scanning = 0;
      } else {
        evalPos = evalPos + 1;
      }
    }
  }
  evalSkipWs(s);
  let found: i32 = 0;
  if (evalPeek(s) === 61 && evalPeek2(s) === 62) found = 1; // '=>'
  evalPos = save; // restore
  return found;
}

function runFuncDecl(s: string): void {
  evalSkipWs(s);
  const name: string = readIdent(s);
  evalSkipWs(s);
  const paramsArr: i32 = parseParams(s);
  evalSkipWs(s);
  let bodyBox: i32 = dynString("");
  if (evalPeek(s) === 123) bodyBox = parseBlockBody(s);
  const f: i32 = makeUserFunc(paramsArr, bodyBox, evalEnv);
  if (evalLive === 1) dynSet(evalEnv, name, f);
}

// Execute one statement at the cursor.
function runStatement(s: string): void {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 123) { // '{' block — #14 2e.7: a fresh lexical scope so let/const don't leak
    evalPos = evalPos + 1;
    const parentEnv: i32 = evalEnv;
    const blockEnv: i32 = childEnv(parentEnv);
    evalEnv = blockEnv;
    gcPushRoot(blockEnv); // survive a collection during the block (incl. across nested calls)
    runStatements(s);
    gcPopRoot();
    evalEnv = parentEnv;
    evalSkipWs(s);
    if (evalPeek(s) === 125) evalPos = evalPos + 1; // '}'
    return;
  }
  if (c === 59) { // empty ';'
    evalPos = evalPos + 1;
    return;
  }
  if (isIdentChar(c, 0) === 1) {
    const start: i32 = evalPos;
    const word: string = readIdent(s);
    if (strEq(word, "let") === 1 || strEq(word, "const") === 1 || strEq(word, "var") === 1) {
      runDecl(s);
      return;
    }
    if (strEq(word, "if") === 1) {
      runIf(s);
      return;
    }
    if (strEq(word, "while") === 1) {
      runWhile(s);
      return;
    }
    if (strEq(word, "do") === 1) {
      runDoWhile(s);
      return;
    }
    if (strEq(word, "for") === 1) {
      runFor(s);
      return;
    }
    if (strEq(word, "switch") === 1) {
      runSwitch(s);
      return;
    }
    if (strEq(word, "try") === 1) {
      runTry(s);
      return;
    }
    if (strEq(word, "throw") === 1) { // #14 2e.6
      const tv: i32 = parseExpr(s);
      if (evalLive === 1) {
        evalThrew = 1;
        evalThrowVal = tv;
      }
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if (strEq(word, "return") === 1) {
      runReturn(s);
      return;
    }
    if (strEq(word, "function") === 1) {
      runFuncDecl(s);
      return;
    }
    if (strEq(word, "break") === 1) { // #14 2e.1
      if (evalLive === 1) evalBroke = 1;
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if (strEq(word, "continue") === 1) {
      if (evalLive === 1) evalContinued = 1;
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    // not a keyword: bare-identifier assignment `word = expr`, else an expression statement
    evalSkipWs(s);
    const nc: i32 = evalPeek(s);
    if (nc === 61 && evalPeek2(s) !== 61 && evalPeek2(s) !== 62) { // '=' but not '==' or '=>'
      evalPos = evalPos + 1; // consume '='
      const val: i32 = parseExpr(s);
      if (evalLive === 1) envAssign(evalEnv, word, val); // #14 2e.7 — update declaring scope
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if (nc === 43 && evalPeek2(s) === 43) { // '++' (#14 2e.1 — postfix, statement form)
      evalPos = evalPos + 2;
      if (evalLive === 1) {
        const cur: i32 = envLookup(evalEnv, word);
        envAssign(evalEnv, word, dynAdd(cur, dynNumber(1)));
      }
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if (nc === 45 && evalPeek2(s) === 45) { // '--'
      evalPos = evalPos + 2;
      if (evalLive === 1) {
        const cur: i32 = envLookup(evalEnv, word);
        envAssign(evalEnv, word, dynSub(cur, dynNumber(1)));
      }
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if ((nc === 43 || nc === 45 || nc === 42 || nc === 47) && evalPeek2(s) === 61) {
      // compound assignment '+=' '-=' '*=' '/=' (#14 2e.1 — common in loop bodies/updates)
      const op: i32 = nc;
      evalPos = evalPos + 2; // consume operator + '='
      const rhs: i32 = parseExpr(s);
      if (evalLive === 1) {
        const cur: i32 = envLookup(evalEnv, word);
        let nv: i32 = cur;
        if (op === 43) nv = dynAdd(cur, rhs);
        else if (op === 45) nv = dynSub(cur, rhs);
        else if (op === 42) nv = dynMul(cur, rhs);
        else nv = dynDiv(cur, rhs);
        envAssign(evalEnv, word, nv);
      }
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    if (nc === 46 || nc === 91) {
      // #14 2e.4 — member/index path: `word.a.b = v` / `word[k] = v` (incl. `+=`-style), OR an
      // expression statement (e.g. `word.foo()`). Walk the path; navigate into all but the last
      // segment, then if the next token is an assignment operator, set; otherwise rewind + parse expr.
      let container: i32 = evalEnv === -1 ? dynUndefined() : envLookup(evalEnv, word);
      if (container === -1) container = dynUndefined();
      let isAssign: i32 = 0;
      let scanning: i32 = 1;
      while (scanning === 1) {
        evalSkipWs(s);
        const ac: i32 = evalPeek(s);
        let isDot: i32 = 0;
        let segKey: string = "";
        let segIdx: i32 = 0;
        if (ac === 46) { // '.name'
          evalPos = evalPos + 1;
          segKey = readIdent(s);
          isDot = 1;
        } else if (ac === 91) { // '[expr]'
          evalPos = evalPos + 1;
          segIdx = parseExpr(s);
          evalSkipWs(s);
          if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
        } else {
          scanning = 0;
        }
        if (scanning === 1) {
          evalSkipWs(s);
          const op0: i32 = evalPeek(s);
          const op1: i32 = evalPeek2(s);
          const plain: i32 = (op0 === 61 && op1 !== 61 && op1 !== 62) ? 1 : 0;
          // NOTE: kept as a single-line `if` (not a ternary) so `deno fmt` cannot wrap it past what
          // modc's body-line joiner parses — a wrapped multi-line ternary breaks the modc compile.
          let compound: i32 = 0;
          if ((op0 === 43 || op0 === 45 || op0 === 42 || op0 === 47) && op1 === 61) compound = 1;
          if (plain === 1 || compound === 1) {
            if (plain === 1) evalPos = evalPos + 1; // '='
            else evalPos = evalPos + 2; // 'op='
            const rhs: i32 = parseExpr(s);
            if (evalLive === 1) {
              let nv: i32 = rhs;
              if (compound === 1) {
                let cur: i32 = 0; // if/else (not a wrappable ternary) — see NOTE above
                if (isDot === 1) cur = dynMember(container, segKey);
                else cur = dynIndexValue(container, segIdx);
                if (op0 === 43) nv = dynAdd(cur, rhs);
                else if (op0 === 45) nv = dynSub(cur, rhs);
                else if (op0 === 42) nv = dynMul(cur, rhs);
                else nv = dynDiv(cur, rhs);
              }
              if (isDot === 1) dynSet(container, segKey, nv);
              else dynIndexSet(container, segIdx, nv);
            }
            isAssign = 1;
            scanning = 0;
          } else {
            if (isDot === 1) container = dynMember(container, segKey);
            else container = dynIndexValue(container, segIdx);
          }
        }
      }
      if (isAssign === 1) {
        evalSkipWs(s);
        if (evalPeek(s) === 59) evalPos = evalPos + 1;
        return;
      }
      // not an assignment (method call / member read) — rewind and parse as an expression statement
      evalPos = start;
      const ev: i32 = parseExpr(s);
      if (evalLive === 1) lastValue = ev;
      evalSkipWs(s);
      if (evalPeek(s) === 59) evalPos = evalPos + 1;
      return;
    }
    // expression statement starting with an identifier — rewind and parse from the start
    evalPos = start;
    const v: i32 = parseExpr(s);
    if (evalLive === 1) lastValue = v;
    evalSkipWs(s);
    if (evalPeek(s) === 59) evalPos = evalPos + 1;
    return;
  }
  // expression statement (literal / '(' / unary …)
  const v2: i32 = parseExpr(s);
  if (evalLive === 1) lastValue = v2;
  evalSkipWs(s);
  if (evalPeek(s) === 59) evalPos = evalPos + 1;
}

// Run statements until end-of-input or a closing `}`.
function runStatements(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === -1 || c === 125) { // EOF or '}'
      go = 0;
    } else {
      maybeCollect(); // statement boundary — safe to collect (all live values are rooted)
      const saved: i32 = evalLive;
      // statements after a return/break/continue/throw are parsed (to advance the cursor) but not run
      if (evalReturned === 1 || evalBroke === 1 || evalContinued === 1 || evalThrew === 1) {
        evalLive = 0;
      }
      runStatement(s);
      evalLive = saved;
    }
  }
}

/**
 * Run a sequence of JS statements against an environment object (mutated in place by declarations
 * and assignments). Returns the value carried by a `return`, else the last expression statement's
 * value, else `undefined`.
 */
/** @export */
export function dynRun(s: string, env: i32): i32 {
  // GC Part 4b: `env` is an active scope for this run's duration — push it as a root so a collection
  // triggered DURING this run (incl. nested calls, which each push their own scope) cannot free it or
  // anything reachable from it. Single exit → one balanced pop.
  gcPushRoot(env);
  evalPos = 0;
  evalEnv = env;
  evalLive = 1;
  evalReturned = 0;
  evalReturnVal = dynUndefined();
  evalThrew = 0; // #14 2e.6: fresh run — clears any leftover uncaught throw from a prior run
  lastValue = dynUndefined();
  runStatements(s);
  const result: i32 = evalReturned === 1 ? evalReturnVal : lastValue;
  gcPopRoot();
  return result;
}
