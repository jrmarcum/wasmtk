# wasmtk: On-Demand stdlib Bundling as an Alternative to `javyc`

**Purpose:** Implementation brief for the wasmtk team. Proposes a change that lets
`wasmbundle` merge stdlib capability modules into a `wasic` program on demand, so a
growing class of programs can use stdlib features (JSON, Date, Map, Set, RegExp,
eventually Promise) **without** embedding QuickJS via `javyc`.

**Status:** §3 allocator-unification pass shipped (2026-05-30). §5 capability libraries
(JSON / Date / Map / Set / RegExp) are next. §6 kernel-scope decision and Promise/async
track remain open.

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
   first), Map, Set; plus a RegExp leaf module. *(next session)*
4. **Wire** capability selection: bundle only referenced capabilities (tree-shake at the
   feature level; `wasic` already does this for its own helpers via Binaryen `-Oz`).
5. **(Separate track)** Promise/async: state-machine lowering in `wasic` + microtask
   runtime module; lift the `hybrid` async exclusion.
6. **Evolve** `hybrid` from `// @wasm` annotations to TS-type-driven routing.
7. **Decide** the §6 scope question (drop the kernel vs own runtime) — determines whether
   `javyc` is eventually removed or retained as the dynamic-kernel fallback.

### 7a. Wasic codegen bug uncovered during §3 development

`return expr as unknown as i32` (the standard TypeScript double-cast idiom for
forcing through `any`) is currently mis-emitted by wasic: the return path ends with
a stray `f64.convert_i32_s` on what should be an i32 result, producing a
`(result i32)` declaration with an f64 value on the stack. Manifests as
`Compiling function #N failed: type error in return[0] (expected i32, got f64)` at
runtime. Worked around in `18b_SharedHeapTwoLibraries.ts` by returning `.length`
(which is natively i32) instead of casting the buffer pointer. Tracked separately
in the wasic todo list; not a blocker for the allocator-unification work but should
be fixed before the Tier-1 stdlib libraries are written since several of them will
want pointer-typed returns.
