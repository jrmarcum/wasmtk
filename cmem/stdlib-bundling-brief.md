# wasmtk: On-Demand stdlib Bundling as an Alternative to `javyc`

**Purpose:** Implementation brief for the wasmtk team. Proposes a change that lets
`wasmbundle` merge stdlib capability modules into a `wasic` program on demand, so a
growing class of programs can use stdlib features (JSON, Date, Map, Set, RegExp,
eventually Promise) **without** embedding QuickJS via `javyc`.

**Status:** §3 allocator-unification pass shipped (2026-05-30). §5/§7-#3 **all five Tier-1
capabilities shipped**: shared-heap `modc` libraries **`Set<i32>`** and **`Map<i32,i32>`**
(2026-05-30), the **`Date`** leaf library (2026-05-31), **`JSON`** (parse + navigate, integer-
number v1, 2026-05-31 — first capability to take *string* input across the merge), and the
**`RegExp`** leaf matcher (backtracking; v1 = literals/`.`/classes/`\d\w\s`/`*+?`/`^$`, 2026-05-31)
— see §7-#3/§7c/§7d. **No Tier-1 capabilities remain.** Open: §7-#4 feature-level tree-shake
wiring, §7-#5 Promise/async, §7-#6 hybrid type-routing, §6/§7-#7 kernel-scope decision. Backend
on `wabt-ts@^1.3.0/compat` + `binaryen-ts@^1.3.2/compat`. Date surfaced+fixed two merge-path bugs
(§7b); JSON four more (§7c); RegExp surfaced an **open** merge bug (OOB-`charCodeAt` in a
non-short-circuit `&&`; worked around in the library) — §7d.

---

## 1. Background / what was established

- A `guessTheNumber` example was investigated. The `.wat` artifact (~1.8 KB, hand/AOT
  style, no engine) and the `.wasm` artifact (1,263,694 bytes) are **unrelated
  representations**, not a disassembly of each other. The `.wasm` is real
  statically-linked Javy: ~73% code = QuickJS engine (rquickjs 0.10.0), ~27% data =
  engine tables + embedded JS bytecode; 9 WASI imports; runs and plays correctly.
- This confirmed the size reality: Javy (`javyc`) ships ~1.26 MB to carry a general JS
  engine. `wasic` reproduces equivalent observable behavior for typed code in ~KB by
  hand-providing only the runtime touchpoints actually used.
- Javy also supports **dynamic linking** (engine as a separate ~plugin module, programs
  1–16 KB importing it). Relevant as a delegation option, but secondary to the plan below.

## 2. Core proposal

Author stdlib features (JSON, Date, Map, Set, RegExp) as `modc` libraries in the
existing `wasic` TS subset, and have `wasmbundle` merge only the ones a program
references. `wasmbundle`/`wasmmerge` already handles the two hard parts of merging:
symbol **prefix-mangling** (collision-free internal names) and **data-section
relocation** (non-overlapping static data).

## 3. The one missing piece: shared allocator + heap (NOT linking) — ✅ SHIPPED 2026-05-30

Each `wasic`/`modc` module ships its **own** bump allocator: `$__malloc` advancing a
module-local `$__heap_ptr`, heap seated just past that module's static data. After a
merge with prefix-mangling you get **two independent allocators over one linear
memory** (`$a__heap_ptr`, `$b__heap_ptr`), which will hand out overlapping addresses
and corrupt each other as soon as both allocate. Co-location (today's `wasmbundle`,
good for "ship N libraries as one file") is **not** the same as letting a `Map` built
in one merged unit and a `JSON.stringify` in another share one live heap.

**Why this is tractable:** the *value layout* is already shared for free, because every
capability is produced by the same `wasic` backend — same dynamic-array header
`[len i32][cap i32][elems]`, strings as ptr+len, 8-byte TypedArray header, struct field
offsets. A structure built by one module is already readable by another.

**Proposed change — an allocator-unification pass in the merge:** ✅ implemented in
`src/wasmmerge.ts`, `src/wasic.ts`, and `src/wasmbundle.ts` on 2026-05-30. All three
sub-goals delivered:

1. ✅ Dedupe `$__malloc` to a single shared implementation across merged modules — a
   new `detectBumpAllocator()` helper in `wasmmerge.ts` semantically identifies the
   bump-allocator function form (single i32 param/result, one set/get on a single
   global, `local.get 0` + `i32.add` arithmetic, no loads/stores/calls). Detected
   functions are dropped from the merged output and their indices in `funcName` are
   redirected to the main module's `$__malloc`. `renameGlobalRefs()` extended to
   redirect the corresponding heap-ptr global ref to `$__heap_ptr`.
2. ✅ Point all merged modules at one shared `$__heap_ptr` global — same redirection
   pass handles it.
3. ✅ Seat the heap cursor past the **combined** static data (post-relocation) — a
   post-merge rewrite in `compileWasiTs` / `compileLibTs` (`src/wasic.ts`) sets
   `(global $__heap_ptr (mut i32) (i32.const dataOffset))` and grows the memory
   declaration to `max(2, ceil(dataOffset / 65536) + 1)` pages. `wasmbundle.ts` does
   the equivalent in the master WAT when any sub-merge dropped an allocator: it
   synthesizes the shared `$__heap_ptr` + `$__malloc` pair and recomputes pages.

`WatMergeResult` gained `droppedAllocator: boolean`. When true, the runtime emits a
notice: `allocator unified: dropped $__malloc + heap-ptr global; call sites
redirected to main module's $__malloc / $__heap_ptr.`

This single change converts `wasmbundle` from a packaging tool into a real on-demand
stdlib linker.

**Regression test:** `tests/wasm_wasi/18b_SharedHeapTwoLibraries.ts` — `@test-pipeline`
running `modc lib_a_modc.ts` + `modc lib_b_modc.ts` + `wasic main_wasic.ts` + `run`.
Both libraries allocate via `.push()` (which calls the wasic `$__dynarr_push_i32`
helper, which calls `$__malloc`); main asserts both libraries return the expected
length. PASSING under the dual JSR /compat stack.

**OPEN QUESTION resolved (2026-05-30):** pre-unification, `src/wasmmerge.ts` did NOT
unify — it prefix-mangled each imported module's `$__malloc` and `$__heap_ptr` along
with everything else, leaving each module with its own private allocator over the
shared linear memory. Mutable globals from imported modules were additionally
relocated to the page-2 boundary (131072) by the original Phase 18 patch, which
prevented immediate collisions between a single library and the main module — but
two libraries with the same global-index pattern would both have landed at 131072
and corrupted each other on first allocation. The unification pass closes this gap.

## 4. Architecture: two linking regimes (both already in the toolkit)

- **`wasmbundle` — single module / shared memory** (needs the allocator fix). Use for
  capabilities that must share **live values** with the program (e.g. a `Map` holding
  references the program also touches).
- **`modc` + `bindgen` — separate module / canonical-ABI marshaling** (string via
  `cabi_realloc` + TextEncoder, already implemented). Use for **value-in / value-out
  leaf** capabilities where copying across the boundary is fine (RegExp on a string,
  JSON of a serializable tree, Date math).

## 5. Feature tiering mapped onto existing tools

| Feature group | Path | Notes |
|---|---|---|
| JSON, Date, Map, Set | `modc` lib + `wasmbundle` (shared heap), or `modc`+`bindgen` (leaf) | Needs allocator unification for the shared-heap case; small per-feature runtime (Map/Set hashing, Date calendar math, JSON recursive walker over the wasic value layout) |
| RegExp | leaf capability module, merged when used | Self-contained; ideal `modc`/wasm module |
| Promise / async / await | **compiler work in `wasic`** (state-machine lowering + microtask module) | Not a bundling change. `hybrid` currently *excludes* async — this is exactly that gap |
| Full dynamic / `any` / open prototype mutation / `eval` | **keep `javyc`** (or build own runtime) | The irreducible kernel — see §6 |

`hybrid` is an embryonic auto-tiering engine: today it splits on manual `// @wasm`
annotations; the natural evolution is **TS-type-driven routing** — fully-typed functions
to `wasic` + merged capabilities, `any`-shaped functions to `javyc`. Types are the dial
that sets how much falls into the dynamic kernel.

## 6. Javy-independence verdict

After this change, **wasmtk can be fully standalone for everything `wasic` can
statically type** — which becomes most of what `javyc` covers today. It **cannot** serve
arbitrary JavaScript without an engine. The irreducible kernel that requires a runtime:

- **Runtime code generation from strings** — `eval` and `new Function` are the *same*
  irreducible capability (string → executable code at runtime), not two items.
  `new Function` is `eval` scoped to a function body (global scope only, no lexical
  capture). Cannot be AOT-compiled by definition: the source does not exist at compile
  time. NOTE: this is orthogonal to the class/closure machinery — classes model object
  *shapes*, not code generation, so they neither cover nor reduce this. The only
  `new Function` form that *could* be AOT-handled is an all-string-literal body, which
  is merely a verbose function declaration (already covered) — no capability, just an
  alias. Genuine uses (runtime expression/template/rule compilation, behavior hydration)
  are out of scope for a WASI target for the same reason `eval` is.
- Pervasive `any` over shapes unknown until runtime; reflection over runtime shapes.
- Open-ended / dynamic prototype mutation.

To be genuinely Javy-free, two routes for that kernel:
- **(a) Declare the kernel out of scope** → wasmtk is fully standalone with **no engine
  at all**, for a large-but-bounded TS subset. `javyc` can be dropped.
- **(b) Ship wasmtk's own dynamic-runtime module** → Javy-free, but this is building a
  small JS engine (boxed values + property maps + an interpreter/eval). Removes the
  *Javy* dependency, not the *engine* concept.

There is no route where static capability modules cover arbitrary JS.

**Framing for the decision:** per-artifact, `wasic` output is already Javy-free —
QuickJS only enters through `javyc`. This change does not remove an engine from existing
binaries; it shrinks the set of programs *forced* through `javyc` down to the kernel
above. "Standalone from Javy" vs "standalone from any JS engine" are different goals;
this change makes the former a scope decision rather than a technical blocker.

## 7. Work items

1. ✅ **Confirm** `wasmmerge` `$__malloc`/`$__heap_ptr` handling (read source). *(blocker
   for sizing)* — done 2026-05-30: pre-unification handling did not unify; see §3.
2. ✅ **Implement** the allocator-unification pass in the merge (dedupe malloc, single
   heap ptr, heap past combined data) — done 2026-05-30; regression test
   `18b_SharedHeapTwoLibraries` in place; full suite **262/271 PASS (96.7%)** under
   `wabt-ts/compat 1.2.9` + `binaryen-ts/compat 1.3.1` with the unification pass active.
3. **Author** Tier-1 capability libraries as `modc` modules: JSON, Date (UTC/offset
   first), Map, Set; plus a RegExp leaf module.
   - ✅ **`Set<i32>` shipped 2026-05-30** — `tests/wasm_wasi_bundle/set_bundle/set_lib_modc.ts`
     (open-addressing hash table; handle = i32 ptr to a 4-slot `Int32Array` header
     `[count, cap, keysPtr, usedPtr]` + two `Int32Array(cap)` bucket arrays; linear probing
     on `key & (cap-1)`; ×2 grow + rehash at load factor 0.5; exports
     `setNew`/`setAdd`/`setHas`/`setSize`). Shared-heap driver `main_wasic.ts` +
     `@test-pipeline` `tests/wasm_wasi/18c_SetCapabilityLibrary.ts` (PASS). Required two
     wasic-side fixes: TypedArray-view-over-pointer **writes** (`const v: Int32Array = ptr
     as unknown as Int32Array; v[i] = x`) and imported-function signature resolution from
     inline `(param …)` headers in `wasmmerge`. A pre-existing modc bug (string-returning
     library functions imported an unused `fd_write`) was fixed alongside (bindgen
     99/103 → 103/103).
   - ✅ **`Map<i32,i32>` shipped 2026-05-30** —
     `tests/wasm_wasi_bundle/map_bundle/map_lib_modc.ts`. Reuses the Set hash core (same
     linear probing + ×2 grow/rehash) and adds a parallel values array; handle = i32 ptr to
     a 5-slot `Int32Array` header `[count, cap, keysPtr, valsPtr, usedPtr]` + three
     `Int32Array(cap)` bucket arrays. Exports `mapNew`/`mapSet`/`mapGet`/`mapHas`/`mapSize`;
     `mapSet` updates in place on an existing key (count stable), `mapGet` takes a caller
     `fallback` for absent keys. Shared-heap driver `main_wasic.ts` + `@test-pipeline`
     `tests/wasm_wasi/18d_MapCapabilityLibrary.ts` (PASS). Required no new compiler fixes —
     built entirely on the wasic features the Set capability established (TypedArray view
     over pointer, type-erasure casts, inline-param import signature resolution).
   - ✅ **`Date` shipped 2026-05-30** (first *leaf* capability) —
     `tests/wasm_wasi_bundle/date_bundle/date_lib_modc.ts`. Pure UTC integer calendar math,
     no heap allocation and no mutable state (allocator unification is a no-op here), so the
     merge is a straight function splice — the "leaf capability merged when used" path from
     §5. Uses Howard Hinnant's exact-integer civil↔days algorithms (valid across the whole
     proleptic Gregorian calendar, incl. pre-epoch / negative day counts). Exports
     `isLeapYear`, `daysInMonth`, `daysFromCivil`, `weekdayFromDays`, `yearFromDays`,
     `monthFromDays`, `dayFromDays`. Self-checking driver `main_wasic.ts` + `@test-pipeline`
     `tests/wasm_wasi/18e_DateCapabilityLibrary.ts` (PASS). Surfaced + fixed two merge-path
     compiler bugs — see §7b.
   - ✅ **`JSON` shipped 2026-05-31** (parse + navigate; first capability with *string* input
     across the merge) — `tests/wasm_wasi_bundle/json_bundle/json_lib_modc.ts`. Shared-heap:
     a wasic program (no native JSON) gains `JSON.parse` + navigation by merging this lib; the
     value tree lives on the driver's heap. Each handle = base ptr of a 4-slot `Int32Array`
     node `[tag, a, b, c]` (tag 0=null 1=bool 2=number(int) 3=string 4=array 5=object);
     containers reuse wasic's native dynamic `i32[]` (stored/reconstructed by ptr), string
     values are decoded into `Uint8Array` buffers. Recursive-descent parser with a module-level
     cursor. Exports `jsonParse`/`jsonType`/`jsonInt`/`jsonBool`/`jsonArrayLen`/`jsonArrayGet`/
     `jsonObjectLen`/`jsonStrLen`/`jsonStrCharAt`/`jsonStrEq`/`jsonGet`/`jsonHas`. Self-checking
     driver `main_wasic.ts` + `@test-pipeline` `tests/wasm_wasi/18f_JsonCapabilityLibrary.ts`
     (PASS). v1 scope: null/bool/integer-number/string/array/object + basic escapes; floats and
     `\uXXXX` are the v2 gap. **Surfaced + fixed four compiler bugs — see §7c.**
   - ✅ **`RegExp` shipped 2026-05-31** (fifth/final Tier-1; leaf) —
     `tests/wasm_wasi_bundle/regex_bundle/regex_lib_modc.ts`. A classic Kernighan/Pike recursive
     backtracking matcher, index-based over two `(string, index)` pairs threaded through the
     recursion (no heap; straight function splice). Exports `reTest(p,t)` / `reSearch(p,t)` (start
     index, sets `reEnd()`) / `reEnd()`. v1: literals, `.`, classes `[...]` (ranges, negation,
     `\d \w \s`), escapes `\d \w \s \D \W \S \n \t \r`, quantifiers `* + ?` (greedy + backtrack),
     anchors `^ $`; v2 gap: `|`, groups/captures, `{n,m}`, lazy, backreferences. Self-checking
     driver + `@test-pipeline` `tests/wasm_wasi/18g_RegexCapabilityLibrary.ts` (PASS). **Surfaced
     an OPEN merge bug** (OOB `charCodeAt` in a non-short-circuit `&&` loop condition mis-encoded
     by the splice; correct standalone, traps merged) — worked around in the library by never
     calling `charCodeAt` on an unchecked index. See §7d.
   - **All Tier-1 capabilities complete.**
4. **Wire** capability selection: bundle only referenced capabilities (tree-shake at the
   feature level; `wasic` already does this for its own helpers via Binaryen `-Oz`).
5. **(Separate track)** Promise/async: state-machine lowering in `wasic` + microtask
   runtime module; lift the `hybrid` async exclusion.
6. **Evolve** `hybrid` from `// @wasm` annotations to TS-type-driven routing.
7. **Decide** the §6 scope question (drop the kernel vs own runtime) — determines whether
   `javyc` is eventually removed or retained as the dynamic-kernel fallback.

### 7a. Wasic codegen bug uncovered during §3 development — ✅ FIXED 2026-05-30

`return expr as unknown as i32` (the standard TypeScript double-cast idiom for
forcing through `any`) was mis-emitted by wasic: the return path ended with a stray
`f64.convert_i32_s` on what should be an i32 result, producing a `(result i32)`
declaration with an f64 value on the stack. Manifested as
`Compiling function #N failed: type error in return[0] (expected i32, got f64)` at
runtime.

**Root cause:** the `as` handler in `emitExpr` (`src/wasic.ts`) scans right-to-left,
so `buf as unknown as i32` recursed into the intermediate `buf as unknown`. The
intermediate target `unknown` reached `mapType("unknown")`, which falls through to
`f64`, so the i32 pointer was cast i32→f64 before the outer `as i32` saw it.

**Fix:** strip pure type-erasure casts (`as unknown` / `as any`) up front in
`emitExpr`, reducing `expr as unknown as T` → `expr as T` and `expr as unknown` →
`expr`. The now-simple inner operand lets the normal single-cast path infer the
correct source type. Regression test: `tests/wasm_wasi/22_DoubleCastErasure.ts`
(i32 + f64 double-cast, `as any` variant, bare `as unknown`; zero TS↔WASM delta).
The Tier-1 stdlib libraries can now use pointer-typed `as unknown as i32` returns
directly.

### 7b. Two merge-path codegen bugs uncovered during Date development — ✅ FIXED 2026-05-31

The `Date` capability is the first merged library whose functions are dense
**integer arithmetic over large constants** (719468, 146097, 365, 153, …). That
shape exposed two latent bugs in the merge pipeline that the bitwise/small-constant
Set/Map libraries never tripped. Both are fixed; the Date pipeline
(`18e_DateCapabilityLibrary.ts`) passes and the full `tests/wasm_wasi` suite is
**268/275** with the same 7 pre-existing wasic-codegen failures and **no
regressions**.

1. **`wasmmerge` relocated arithmetic constants as if they were data pointers.**
   `relocateDataPtrs` (`src/wasmmerge.ts`) blindly shifted **every** `i32.const >=
   260` by the data-relocation delta — a documented conservative heuristic. Date's
   `isLeapYear` divides by `400`; after the merge that became `400 + dataOffset`
   (e.g. `668`), so `year % 668` made `isLeapYear(2000)` return 0. **Fix:** compute
   the merged module's own static-data extent `[dataLo, dataHi)` from its `(data …)`
   segments (new `dataStringByteLength` helper counts `\XX`/`\c` escapes) and
   relocate only constants that fall inside it. Genuine static-data pointers live in
   that range by construction; arithmetic literals do not. A pure leaf with no data
   segments (Date, Set, Map) has an empty range → nothing relocated. This is a strict
   improvement over the blanket threshold (the residual heuristic risk — an
   arithmetic constant that *coincidentally* lands inside a string-bearing library's
   data range — is far narrower and could later be made exact with context-sensitive
   load/store-address relocation).

2. **Binaryen miscompiled the doubly-merged module — ✅ fixed upstream in
   binaryen-ts/compat 1.3.2 (2026-05-31).** After wasmmerge splices the already-`-Oz`'d,
   stack-form library back into the driver, `compileWasiTs` re-optimizes the combined
   module with binaryen-ts/compat. Under 1.3.1, on Date's division-heavy
   `monthFromDays`/`dayFromDays`, `optimize()` produced a binary that **misbehaved at
   runtime** (garbage / out-of-bounds), even though the pre-binaryen merged WAT —
   assembled by wabt alone — ran correctly, and laundering binaryen's output back
   through wabt did **not** recover it (so the corruption was in binaryen's
   optimization, not its byte encoding). It was briefly worked around with a
   `skipBinaryenOpt` flag on `watToOptimisedWasm` (ship wabt's direct assembly of the
   merged WAT on the merge path). **1.3.2 fixed the optimizer bug** (deno.json bumped
   1.3.1 → 1.3.2), so the workaround was removed — the merge path again runs full
   Binaryen `-Oz`, and the Date pipeline + full suite pass with it re-enabled. (Fix 1
   above is independent of the binaryen version and stays.)

### 7c. Four compiler bugs uncovered during JSON development — ✅ FIXED 2026-05-31

JSON is the first capability to take **string input across the merge boundary** (Set/Map are
i32-only; Date is a pure-integer leaf) and the first to build a **dynamic tagged value tree**.
That exercised four code paths the earlier capabilities never hit. All four are fixed; the
JSON pipeline (`18f_JsonCapabilityLibrary.ts`) passes and the full `tests/wasm_wasi` suite is
**269/276** — same 7 pre-existing wasic-codegen failures, no regressions — plus `bindgen`
103/103 and `jstyper` 73/73. (Detailed in cmem/capabilities.md (JSON).)

1. **String args to a merged import dropped to one stack value.** A modc `func(s: string)`
   compiles its string param to `(i32 i32)` (ptr+len), so `mergeWasmWat` registered the import
   with params `[i32, i32]` and the call site couldn't expand a string argument →
   `not enough arguments on the stack for call (need 2, got 1)`. **Fix:** the sibling `.wit`
   (Phase 41) preserves `s: string`, so `compileWasiTs`/`compileLibTs` now read it and overlay
   the **logical** signature onto each `ExternalFuncDef` before transpilation (new helpers
   `parseWitLogicalSigs`/`readWitLogicalSigs`/`applyWitSig`/`witTypeToWat`/`kebabToCamel`).
   Numeric-only libs (no `.wit` string params) are unaffected. This is what makes
   `jsonParse(s)`, `jsonGet(node, key)`, `jsonStrEq(node, t)` callable across the merge.

2. **Allocator-detector false-positive dropped a real function.** `detectBumpAllocator` matched
   any `(param i32)(result i32)` that touches one global with get+set + `i32.add` and no
   loads/stores/calls — which also describes a plain `global += param; return global`
   accumulator (a parser-cursor `advance`). The matched function was silently dropped during the
   merge → `undefined func`. **Fix:** a real `$__malloc` returns the *old* value (captured into
   a local before the `global.set`) so it reads the global **once**; the accumulator reads it
   **twice** (the second to return the new value). Require exactly one `global.get`/`global.set`
   occurrence — accepts every `-Oz` malloc shape, rejects the accumulator.

3. **Escaped-quote string literals matched as empty.** The literal regexes `"([^"]*)"` stop at
   the first `\"`, so a literal containing escaped quotes (an embedded JSON document) crossed as
   length 0 / hit "string assignment from complex expression not yet supported". **Fix:**
   escape-aware `"((?:[^"\]|\.)*)"` at the three statement/expression sites (`emitStringPtrLen`,
   `emitStringAssign`, module-const detection); `unescapeString` decodes the rest. (The
   `console.log`-argument emitter in `console_log.ts` still has the un-escaped form, so
   escaped-quote literals are passed via the main paths, which the driver does.)

4. **`findBinaryOp` missed operators whose RHS ends in a call.** The scan started at
   `expr.length - op.length`, never counting the last `op.length-1` chars for paren depth — a
   trailing `)` (e.g. `v[i] !== t.charCodeAt(i)`) drove depth negative so the operator was never
   found and the whole expression fell to the always-false comment-stub. (This silently broke
   the byte-comparison loops in `jsonStrEq`/`jsonGet`.) **Fix:** scan the full string from the
   end for depth (now also counting brackets `[]`, matching the sibling depth scanners) and only
   test op matches at valid start positions. High blast radius (all binary-op parsing) —
   re-validated with no regression.

### 7d. Open merge bug uncovered during RegExp development (2026-05-31)

RegExp is the second capability to take string input across the merge and the first whose hot
loop scans a string char-by-char with backtracking. That surfaced a **merge-only** bug that
remains **open** (worked around in the library, not yet fixed in the toolchain).

**Symptom.** A modc library that runs correctly **standalone** (verified by loading
`regex_lib_modc.wasm` directly in Deno) silently halts — WASM trap; the runner exits 0 with no
stderr — once `wasmbundle`/`wasmmerge` splices it into a host module.

**Isolated trigger.** A `while` loop whose condition is
`i < len && atomMatches(p, pi, s.charCodeAt(i)) === 1` — i.e. a function call wrapping
`charCodeAt`, nested in an `i32.and`, in the loop's `br_if`. wasic compiles `&&` to a
**non-short-circuit** `i32.and`, so `s.charCodeAt(i)` is evaluated even when `i == len` (an
out-of-bounds index). Bisected from the full matcher down to exactly this construct via a minimal
two-function probe.

**Ruled out.** Not an infinite loop (a `count < 1000` cap as the first `&&` operand did not stop
it → a trap, not a runaway). Not Binaryen (halts with Binaryen disabled on both `modc` and the
`wasic` merge step). Not the bounds check (the merged `$__str_char_code_at` WAT is fully intact:
`idx<0→-1`, `idx>=len→-1`, else load — so OOB returns -1 and does not load) and not a bad call
site (the merged call passes the correct `(t_ptr, t_len, idx)`). The corruption is introduced by
the **splice + wabt-ts reassembly** of the larger module (shifted function/type indices), in the
same family as the wabt-ts name/index-resolver bugs in the §7-era table — a `call` nested in an
`i32.and` inside a `loop` `br_if`. JSON did not trip it because its `&&`-with-`charCodeAt` lives
in `if`s with a single direct `charCodeAt`, not a nested call inside a `while` `br_if`.

**Workaround (shipped).** The RegExp matcher never calls `charCodeAt` on an unchecked index — every
fetch is guarded by an enclosing `if (i < len)` (helper `atomAt`). This is also the correct
defensive style; Set/Map/Date/JSON are unaffected.

**Proper fix (future).** Either (a) make wasic emit **short-circuit** `&&`/`||` (an `if`/`select`
skipping the RHS when the LHS is false) — more correct JS semantics, fixes the whole class, but
high blast radius (validate against the full suite); or (b) switch `deno.json` to `npm:wabt` and
re-run `18g` to confirm it is the wabt-ts assembler, then file/fix upstream like the other wabt-ts
encoder bugs. Tracked in `cmem/compiler-bugs.md` § "merge OOB-charCodeAt".
