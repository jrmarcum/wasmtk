# wasmtk own dynamic runtime (#14) — design + implementation log

**Roadmap #14 / stdlib-bundling brief §6/§7-#7.** DECISION (project owner, 2026-06-02): rather than
declaring the irreducible dynamic kernel out of scope or depending on `javyc`/QuickJS long-term,
wasmtk **ships its own dynamic runtime** — boxed values + a property map + (later) an interpreter for
`eval`/`new Function`. `javyc` stays the interim fallback until this lands. This is the largest single
remaining track; it is gated behind Phase 51 (complete), so it is unblocked. The kernel it must cover:
runtime code-gen from strings (`eval`/`new Function`), pervasive `any` over runtime-unknown shapes,
and open-ended prototype mutation (brief §6).

## Locked architecture decisions (owner, 2026-06-22)

1. **First increment = the value + object model** (the substrate everything else lowers onto). NO
   interpreter / `eval`, NO prototype mutation yet.
2. **Value representation = a tagged heap cell** addressed by an **i32 handle** (not NaN-boxing) — it
   integrates directly with the existing shared-heap allocator, ptr+len strings, dynamic-array
   headers, and `Int32Array`/`Float64Array`/`Uint8Array` view idioms.
3. **Authoring = the wasic TS subset now, extract a shared `rtcore` + go hand-WAT later.** Writing the
   runtime in the same subset as the Tier-1 caps means the allocator, strings, dynamic arrays and
   number formatting all come from wasic's own codegen — **zero duplication**. Hand-WAT would
   duplicate `$__malloc`/`$__str_*`/`$__*_to_str`/dynarr/hashmap. The chosen plan: author in the
   subset now; when the **interpreter** increment actually needs hand-WAT control, extract a single
   mergeable `rtcore` module (move wasic's currently-inlined helpers into it so BOTH wasic output and
   the hand-WAT runtime import it — also shrinks multi-cap bundles) and go hand-WAT against it. So
   `rtcore` is a deliberately deferred, interpreter-stage refactor, not increment-1 work.
4. **Opt-in = runtime-only first.** No wasic `any` type yet — the runtime is built/tested standalone
   (a driver calls its ops directly, like the cap drivers). Wiring a wasic `any` type that lowers to a
   boxed-value handle (and auto-merging the runtime when `any`/dynamic features are used) is a later
   increment once the runtime is proven.

## Increment 1 — value + object model (SHIPPED 2026-06-22)

Delivered exactly like the Tier-1 caps: a shared-heap `modc` library + a self-checking driver +
an `@test-pipeline`. After the Phase 18 merge + Stage 0.6 allocator unification, the library's
`$__malloc` resolves to the driver's bump cursor, so boxed values live on the ONE shared heap.

- Library: `tests/wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts`
- Driver:  `tests/wasm_wasi_bundle/dynrt_bundle/main_wasic.ts`
- Pipeline test: `tests/wasm_wasi/18j_DynRuntimeValueModel.ts` (modc → wasic → run). **PASS.**

**Boxed value** = i32 handle = base ptr of a 4-slot `Int32Array` node `[tag, a, b, c]`:

| tag | type | a | b | c |
| --- | --- | --- | --- | --- |
| 0 | undefined | — | — | — |
| 1 | null | — | — | — |
| 2 | boolean | 0/1 | — | — |
| 3 | number (real f64) | ptr → `Float64Array(1)` | — | — |
| 4 | string | `Uint8Array` byte-buffer ptr | byte length | — |
| 5 | array | list ptr (see below) | — | — |
| 6 | object | values list ptr | — | keys list ptr (interleaved `[keyPtr, keyLen]`) |

**Containers use a self-managed growable `Int32Array` list**, NOT wasic's native `[]`+`.push`
(see the empty-array gap below): a "list" is `Int32Array` laid out `[len, cap, e0, e1, …]` with
`listNew`/`listLen`/`listGet`/`listSet`/`listPush` (starting cap 4, doubling, copy-on-grow,
returns the possibly-realloc'd ptr which the owning node writes back). Objects keep parallel values
+ interleaved-keys lists with O(n) `objIndexOf` lookup (a hashmap is a perf follow-up, not v1).

**Exports (v1 surface, ~23):** constructors `dynUndefined/dynNull/dynBool/dynNumber/dynString/
dynArray/dynObject`; introspection `dynTag` (raw 0–6) / `dynTypeof` (JS code 0=undefined 1=object
2=boolean 3=number 4=string 5=function — null/array/object all → 1, the JS quirk); accessors
`dynNumberValue`(f64)/`dynBoolValue`/`dynStrLen`/`dynStrCharAt`; coercions `dynToBool` (ToBoolean,
NaN/0/""/null/undefined falsy) / `dynToNumber` (f64; string/array/object → NaN in v1); object
`dynSet`/`dynGet`(−1 if absent)/`dynHas`/`dynObjLen`; array `dynPush`/`dynArrLen`/`dynArrGet`;
operators `dynStrictEq` (`===`: primitives by value incl. NaN!==NaN, objects/arrays by handle
identity) and `dynAdd` (`+`: string concat if either operand is a string, else numeric add).

**v1 gaps (documented, deferred):** functions (tag 7) + `eval`/`new Function` (the interpreter
increment); prototype mutation; string→number coercion; array/object stringification in `dynAdd`
(→ `""`); a hashmap-backed property map; UTF-16/multi-byte string fidelity (ASCII-accurate, as
elsewhere in wasic). Absent object key returns sentinel −1 (the future wasic `any` lowering maps it
to `undefined`). The `wasmtk:dynrt` virtual-import + embedded-bytes tree-shake delivery (like the
caps' `18h`) is a follow-up — increment 1 uses the explicit `./dynrt_lib_modc.wasm` import pipeline.

## Compiler gaps surfaced (worked around in the library; candidates for a real wasic fix)

Like every Tier-1 cap, this increment surfaced wasic gaps. Both are worked around in the library and
recorded in `compiler-bugs.md`; each could later be fixed in `src/wasic.ts` and the workaround removed
(the RegExp `&&` precedent).

1. **Concat of two string-returning CALLS** — `stringForm(a) + stringForm(b)` aborted
   ("Unsupported expression"). `emitStringAssign` doesn't handle a `+` whose operands are both
   string-returning function calls. Workaround: bind each call to a `string` local first, then concat.
2. **`Float64Array` element in a comparison mis-infers as i32** — `fa[0] === fb[0]` emitted `i32.eq`
   over `f64.load` operands → instantiate-time type error. Float64Array element reads aren't tracked
   as f64 by the binary-op type inference (only when assigned to an explicitly-typed `f64` local).
   Workaround: route f64 array-element reads through `const x: f64 = fa[0]` before comparing.
3. **Empty-array `[]` is a SHARED static zero-capacity array; growth from cap 0 is broken** — the
   root cause of the first big bug. `const a: i32[] = []` lowers to a static data-segment array (every
   `dynArray()` returned the SAME ptr 260 until first grow), and `$__dynarr_push_i32` grows by
   `cap << 1`, which stays 0 from a 0 capacity — so pushes scribble past the allocation into the next
   `$__malloc` (killing element 0) and independent arrays alias. JSON dodged it by building arrays hot
   and reading immediately; a **mutable** runtime can't. Fix in the library: self-managed `Int32Array`
   lists (above). A real compiler fix would make `[]` heap-allocate with nonzero capacity and make the
   grow use `max(cap*2, MIN)` — this would also harden every future reconstruct-then-`push` user.

## Next increments (planned, not started)

- **1b (small):** `wasmtk:dynrt` virtual-import + embedded bytes (tree-shake delivery, like `18h`);
  optionally a hashmap-backed property map; f64-aware `dynToNumber(string)`.
- **2 — the interpreter:** a JS expression parser + tree-walking evaluator over boxed values for
  `eval`/`new Function`. This is where the **`rtcore` extraction + hand-WAT** decision (3 above)
  is revisited, since by then the exact shared-helper set is known.
- **3 — wasic `any` + auto-merge:** add an `any` type to wasic that lowers to a boxed-value handle;
  auto-merge the runtime when `any`/dynamic features are used; migrate `hybrid --auto`'s dynamic
  routing target off `javyc` onto the own-runtime.
