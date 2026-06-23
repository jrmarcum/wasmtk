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
  a[0] = 0;          // len
  a[1] = LIST_CAP0;  // cap
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

// ── dynrt's own recycling allocator (#14 GC track, Part 5) ────────────────────────────────────
// Every dynrt allocation is `8 + n*elemSize` bytes (the wasic TypedArray layout: 8-byte header then
// data); a value handle / view reads its slots at base+8. `dynAlloc(size)` hands out such blocks,
// REUSING ones the collector returned via `dynFreeBlock` before bumping fresh from `__malloc`. This is
// a self-contained free list (head `__dyn_free`) so the GC reclaims into the SAME pool it allocates
// from — without depending on wasmmerge unifying the wasic `$__free`. A freed block stores its
// [size, next] in the first two view slots (base+8, base+12), so it must be >= 16 bytes; both dynAlloc
// AND dynFreeBlock round the size UP to 16 (`GC_MIN_BLOCK`), so EVERY block — including a short string
// or object key (Uint8Array < 16B) — is recyclable (a few wasted bytes, but no leak). Reused blocks
// are zeroed (constructors rely on unset slots being 0 — e.g. a plain object's slot-2 parent link).
const GC_MIN_BLOCK: i32 = 16;
let __dyn_free: i32 = 0; // free-list head (0 = empty)
let __gc_threshold: i32 = 8192; // auto-collect (at interpreter statement boundaries) once the registry exceeds this

function dynFreeBlock(ptr: i32, size: i32): void {
  const sz: i32 = size < GC_MIN_BLOCK ? GC_MIN_BLOCK : size; // match dynAlloc's rounding
  const b: Int32Array = ptr as unknown as Int32Array;
  b[0] = sz;
  b[1] = __dyn_free;
  __dyn_free = ptr;
}

function dynAlloc(req: i32): i32 {
  const size: i32 = req < GC_MIN_BLOCK ? GC_MIN_BLOCK : req; // every block is >= 16B → always recyclable
  let cur: i32 = __dyn_free;
  let prev: i32 = 0;
  while (cur !== 0) {
    const cn: Int32Array = cur as unknown as Int32Array;
    const blockSize: i32 = cn[0];
    if (blockSize >= size) {
      const next: i32 = cn[1];
      // unlink this block from the free list (read size + next BEFORE the zero-fill overwrites them)
      if (prev === 0) {
        __dyn_free = next;
      } else {
        const pn: Int32Array = prev as unknown as Int32Array;
        pn[1] = next;
      }
      // SPLIT: if the chosen block is larger than needed and the leftover can itself hold a free block
      // (>= 16B), carve the remainder off as its own free block at `cur + size` instead of losing those
      // bytes when this block is later freed at its smaller logical size (closes the size-mismatch leak).
      const leftover: i32 = blockSize - size;
      if (leftover >= GC_MIN_BLOCK) {
        dynFreeBlock(cur + size, leftover);
      }
      // zero the data region (size-8 bytes = (size-8)/4 i32 slots) — stale [size,next] + old contents
      const words: i32 = (size - 8) >> 2;
      let i: i32 = 0;
      while (i < words) {
        cn[i] = 0;
        i = i + 1;
      }
      return cur;
    }
    prev = cur;
    cur = cn[1];
  }
  // nothing reusable → fresh block from the bump allocator (WASM memory is already zero)
  return __malloc(size);
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

/** Number of blocks currently on dynrt's recycling free list (test/introspection hook). */
/** @export */
export function dynGcFreeCount(): i32 {
  let cur: i32 = __dyn_free;
  let count: i32 = 0;
  while (cur !== 0) {
    const cn: Int32Array = cur as unknown as Int32Array;
    cur = cn[1];
    count = count + 1;
  }
  return count;
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
  return 1;              // null / array / object → "object"
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
    if (x !== x) return 0;      // NaN is falsy
    return x === 0 ? 0 : 1;     // 0 and -0 are falsy
  }
  if (t === 4) return n[2] === 0 ? 0 : 1; // "" is falsy
  return 1;                                // array / object are truthy
}

/** JS ToNumber (v1: string/array/object → NaN). */
/** @export */
export function dynToNumber(v: i32): f64 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 1) return 0;          // null → 0
  if (t === 2) return n[1] === 0 ? 0 : 1; // bool → 0/1
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    return fv[0];
  }
  return Number.NaN;              // undefined / string / array / object → NaN (v1)
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

/** Call a function value with an args array (a value-model array of arg handles). */
/** @export */
export function dynApply(callee: i32, argsArr: i32): i32 {
  const cn: Int32Array = callee as unknown as Int32Array;
  if (cn[0] !== 7) return dynUndefined(); // not callable → undefined (guarded)
  const id: i32 = cn[1];
  const argc: i32 = dynArrLen(argsArr);
  if (id === -1) { // USER function (2d.2): run its body in a fresh scope linked to its defining env
    const bodyBox: i32 = cn[2];
    const paramsArr: i32 = cn[3];
    const defEnv: i32 = cn[4];
    const scope: i32 = dynObject();
    const sn: Int32Array = scope as unknown as Int32Array;
    sn[2] = defEnv; // parent link → outer names resolve (recursion + closures)
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

let evalPos: i32 = 0;   // read cursor into the eval source string
let evalEnv: i32 = -1;  // current environment object handle (names → values), or -1 for none
let evalLive: i32 = 1;  // 1 = evaluate effects; 0 = inside a short-circuited (dead) branch
let sideEffectCounter: i32 = 0; // observable side effect for the `inc()` builtin (short-circuit test)
let evalReturned: i32 = 0;  // set when a `return` statement executes; stops statement sequencing
let evalReturnVal: i32 = 0; // the value carried by the executed `return`
let lastValue: i32 = 0;     // value of the last executed expression statement (dynRun's result)

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
  if (t === 6) { // object
    const r: i32 = dynGet(obj, name);
    return r === -1 ? dynUndefined() : r;
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
  if (c >= 65 && c <= 90) return 1;  // A-Z
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
        if (e === 110) d = 10;      // \n
        else if (e === 116) d = 9;  // \t
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
  if (c === 40) { // '('
    evalPos = evalPos + 1;
    const v: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    return v;
  }
  if (c === 39 || c === 34) return parseStringLit(s); // ' or "
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
    if (strEq(name, "true") === 1) return dynBool(1);
    if (strEq(name, "false") === 1) return dynBool(0);
    if (strEq(name, "null") === 1) return dynNull();
    if (strEq(name, "undefined") === 1) return dynUndefined();
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
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 46) { // .name
      evalPos = evalPos + 1;
      evalSkipWs(s);
      const start: i32 = evalPos;
      let ch: i32 = evalPeek(s);
      while (isIdentChar(ch, 1) === 1) {
        evalPos = evalPos + 1;
        ch = evalPeek(s);
      }
      const name: string = s.slice(start, evalPos);
      v = dynMember(v, name);
    } else if (c === 91) { // [expr]
      evalPos = evalPos + 1;
      const idx: i32 = parseExpr(s);
      evalSkipWs(s);
      if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
      v = dynIndexValue(v, idx);
    } else if (c === 40) { // (args)  — call
      evalPos = evalPos + 1;
      // #14 GC P5b: the callee `v` and the args array (holding already-evaluated args) are live across
      // the parsing of further args AND the call — both can run user functions that trigger a
      // collection — so keep them rooted until the call returns.
      gcPushRoot(v);
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
      // branch, but still parse the args above so the cursor advances correctly.
      if (evalLive === 1) v = dynApply(v, argsArr);
      else v = dynUndefined();
      gcPopRoot(); // argsArr
      gcPopRoot(); // v
    } else {
      go = 0;
    }
  }
  return v;
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
// the 2c short-circuit machinery). `return` sets `evalReturned`, which stops sequencing. NO block
// scoping (all `let`/`const`/`var` land in the one env), NO `for`, NO member-assignment (`obj.x =`),
// NO user functions (`new Function` is 2d.2 — it adds parser-reentrancy save/restore on top of this).
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
      if (evalReturned === 1) looping = 0; // a `return` in the body ends the loop
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

// `function name(p0, p1, …) { body }` — the `function` keyword has already been consumed. Captures
// the body's SOURCE TEXT (depth-scanning to the matching `}`, string-literal aware) into a string
// box and binds a user function value (closing over the current env) under `name`.
function runFuncDecl(s: string): void {
  evalSkipWs(s);
  const name: string = readIdent(s);
  evalSkipWs(s);
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
  evalSkipWs(s);
  let bodyBox: i32 = dynString("");
  if (evalPeek(s) === 123) { // '{'
    evalPos = evalPos + 1;
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
    bodyBox = dynString(bodySrc);
    if (evalPeek(s) === 125) evalPos = evalPos + 1; // consume '}'
  }
  const f: i32 = makeUserFunc(paramsArr, bodyBox, evalEnv);
  if (evalLive === 1) dynSet(evalEnv, name, f);
}

// Execute one statement at the cursor.
function runStatement(s: string): void {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 123) { // '{' block
    evalPos = evalPos + 1;
    runStatements(s);
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
    if (strEq(word, "if") === 1) { runIf(s); return; }
    if (strEq(word, "while") === 1) { runWhile(s); return; }
    if (strEq(word, "return") === 1) { runReturn(s); return; }
    if (strEq(word, "function") === 1) { runFuncDecl(s); return; }
    // not a keyword: bare-identifier assignment `word = expr`, else an expression statement
    evalSkipWs(s);
    const nc: i32 = evalPeek(s);
    if (nc === 61 && evalPeek2(s) !== 61) { // '=' but not '=='
      evalPos = evalPos + 1; // consume '='
      const val: i32 = parseExpr(s);
      if (evalLive === 1) dynSet(evalEnv, word, val);
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
      if (evalReturned === 1) evalLive = 0; // statements after a `return` are parsed but not run
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
  lastValue = dynUndefined();
  runStatements(s);
  const result: i32 = evalReturned === 1 ? evalReturnVal : lastValue;
  gcPopRoot();
  return result;
}
