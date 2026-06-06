# Roadmap, phase status & vision

## Compiler phase status

All **50 phases complete** plus sub-phases 5e/5f/5g/5h/6d/12b/13b. Full per-phase implementation
detail lives in `README.md` ("Completed Phases") and the legacy `CLAUDE.md`. Summary of milestones:

- Core language (functions, control flow, types, operators, enums, templates).
- Closures: first-class fns (5e), heap closures/factories (5f), named fn-type aliases (5g),
  shared mutable captures with heap-boxing (5h).
- Arrays: static+dynamic, growth, full method set, 2D (6d), rest/spread, typed arrays (31).
- Structs/interfaces, destructuring, interface dispatch (12b), tuples (23), generics by
  monomorphization (14), exceptions (15), module system (16), class inheritance + vtable (47).
- Type system extras: never/void/readonly (21), `as` casts (22), nullable `T|null` (24), nullish/
  logical ops (25), `for…of` (26), intersection types (33), type predicates (34), `typeof`/`keyof`
  (35), simple conditional types (36).
- Strings: full method set + escape processing (46); string arrays as params (43); string-returning
  user fns (42). Math intrinsics incl. extended via merged `mathlib.wasm` (38).
- Tooling: multi-file bundling (8), WASM import bundling (18), wasmbundle CLI (19/20), modc lib mode
  (17), jstyper (39), external interface mapping (40), WIT generation (41), bindgen (50), hybrid.

## Stages beyond the phases

| Stage | Scope | Status |
| --- | --- | --- |
| 0 | Canonical ABI **alignment, partial** — `cabi_realloc` export + out-param string returns. NOTE: the realloc/param side is canonical-adjacent; the **return side is NOT yet canonical** (caller-allocated out-param, no `cabi_post_return`). Full forward-alignment is a pending decision — see [polyglot-producers.md](polyglot-producers.md) | ✅ 2026-05-19 (partial) |
| 0.5 | Dual JSR `/compat` backend migration (wabt-ts + binaryen-ts) | ✅ |
| 0.6 | Allocator unification in wasmmerge (shared heap across merged libs) | ✅ 2026-05-30 |
| 0.7 | Tier-1 stdlib capability libs (Set/Map/Date/JSON/RegExp) | ✅ 2026-05-30/31 — see capabilities.md |

## stdlib-bundling brief — remaining work items (§7)

| # | Item | Status |
| --- | --- | --- |
| 1 | Confirm wasmmerge malloc/heap handling | ✅ |
| 2 | Implement allocator-unification pass | ✅ |
| 3 | Author Tier-1 caps (Set, Map, Date, JSON, RegExp) | ✅ **all 5 done** |
| 4 | Wire capability selection (feature-level tree-shake — bundle only referenced caps) | ✅ 2026-06-02 — embedded caps + virtual `wasmtk:<cap>` import, auto-merge only referenced |
| 5 | Promise/async: state-machine lowering + microtask runtime; lift `hybrid` async exclusion | ⬜ deferred (major track) |
| 6 | Evolve `hybrid` from `// @wasm` annotations → TS-type-driven routing | ✅ 2026-06-02 — `--auto` mode routes fully-typed fns to wasic, dynamic to host |
| 7 | Decide the §6 kernel scope question (drop `javyc` vs ship own dynamic runtime) | ✅ DECIDED 2026-06-02 — **build wasmtk's own dynamic runtime** (see below) |

**§7-#7 decision (2026-06-02, project owner):** wasmtk will **ship its own dynamic-runtime module**
to cover the irreducible kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation)
rather than declaring it out of scope or relying on `javyc` long-term. This is a **major new track**
on the order of #5 async — a small boxed-value + property-map + interpreter runtime — and is NOT
implemented yet; `javyc` (QuickJS) remains the interim dynamic fallback until the own-runtime lands.
`hybrid --auto` (#6) currently routes dynamic-shaped functions to `javyc`; that target will migrate
to the own-runtime once it exists.

Remaining open tracks: **#5 Promise/async** (state-machine lowering + microtask runtime) and the
**own dynamic runtime** (#7 decision). Both are large, dedicated efforts — and both are now
**gated behind Phase 51 language hardening** (see next section).

## Prioritized execution order (set 2026-06-03)

**Principle (project owner, 2026-06-03):** the never-scheduled language-completeness gaps take
**precedence over the big tracks**, because #5 async and the own dynamic runtime *lower onto* the
existing codegen (struct layout, field access, type inference, narrowing, tag dispatch). Completing
the foundational gaps first — with cheap, standalone repros — hardens exactly those paths so a later
bug is debugged once, not while also debugging a state-machine/interpreter transform. Ordered
foundation-depth first, then by effort (quick wins first). Each item ships with its own regression
test. (The **ecosystem loader** track is the exception — it consumes the compiled `.wasm`/`.wit`/ABI,
not TS syntax, so it is orthogonal and ungated.)

### Phase 51 — Language hardening (GATES #5 async + own-runtime)

1. **`instanceof`** — ✅ **DONE 2026-06-05** (class tags). Runtime tag check when the module has
   inheritance (`tag(obj) ∈ {target + all subclasses}` via `findSubclasses`, read from offset 0);
   compile-time const from the var's tracked class when there is no inheritance (no tag header).
   `if (x instanceof Sub)` narrows x to Sub in the then-branch (reuses the Phase-34 narrow machinery
   in `emitBlock`); `console.log(x instanceof C)` works via a `setInstanceofResolver` bridge in
   `console_log.ts`. Tests `51_BasicInstanceof`/`51_InstanceofNarrowing`/`51_InstanceofNoInheritance`/
   `51_Phase51Combined` (suite 279→283). DU-tag `instanceof` not added — TS DUs aren't classes, so
   `instanceof` doesn't apply; class hierarchies are the real use. Two PRE-EXISTING construction
   gaps were surfaced AND **fixed 2026-06-05** (tests `51_ModuleLevelClassInstance` +
   `51_ClassInstanceArrayLiteral`, suite 283→285): (a) module-level class instances are now tracked
   in `classVars` (new `newClassPre` in the startBodyLines pre-scan) so field access / method
   dispatch / instanceof work at module scope; (b) `const a: C[] = [new C(…), …]` is desugared to
   `const a: C[] = []; a.push(new C(…));…` (new `expandClassInstanceArrayLiterals` source pre-pass)
   so each element is constructed with its ctor + class tag. See compiler-bugs.md / design-decisions.md.
   A third gap surfaced here — single-PHYSICAL-line class/constructor bodies, e.g.
   `class C { v: i32; constructor(x: i32) { this.v = x; } }` all on one line — was ALSO **fixed
   2026-06-05** (test `51_SingleLineClassBody`, suite 285→286): `parseClasses` now splits class members
   with a depth/string-aware `splitClassMemberLines` (so fields sharing a line with methods are parsed)
   and splits single-physical-line method bodies via `splitStmts`.
2. **Object spread** `{...base, k: v}` — hardens struct field-copy + override codegen (high-frequency;
   central to struct handling).
3. **Destructuring in function params** `f({x, y}: Vec2)`, then **nested destructuring**
   (`{a:{b}}`, `[[a,b],c]`) — hardens binding/offset paths, built on the layout validated in #2.
4. **Utility types** — `Partial`/`Readonly`/`Record`/`Pick`/`Omit`/`NonNullable` first, then
   `Exclude`/`Extract`/`ReturnType`/`Parameters`. Source-level type-resolution hardening (Phase 36
   style); after the value-level struct work since some interact with struct shapes.

### Phase 52 — Leaf conveniences (NO downstream risk; opportunistic, never gating)

5. `void expr` → `(drop …)`; 6. chained assignment `a = b = c = 0`; 7. `in` operator (closed-world →
compile-time `1`/`0`); 8. `Array.from([…])` / `Array.of(…)` / `Array.isArray(x)`;
9. `String.fromCodePoint(n)`. Nothing builds on these, so they cannot introduce later bugs.

### Phase 53 — Standalone built-ins (user-value; schedule on demand, not foundational)

10. `Number.parseInt(s, radix)` / `Number.parseFloat(s)` — real WAT string→number parser.
11. Multi-level interface inheritance (>2 deep) — offset-calc fix.

### Big tracks (the "last items")

12. **Ecosystem Stage 1 — `universalWasmLoader`** (+ `SPEC.md` + `InstancePool`) — **orthogonal /
    ungated**; can run in parallel anytime (consumes ABI/WIT, not TS syntax).
13. **#5 Promise/async** — state-machine lowering + microtask runtime; lift `hybrid` async exclusion.
    **Gated behind Phase 51.**
14. **Own dynamic runtime** (§7-#7) — boxed values + property map + interpreter for the irreducible
    kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation). **Gated behind Phase
    51.** Largest single track; `javyc` (QuickJS) is the interim fallback until it lands.

**Gating summary:** 51 → (13, 14). 12 is parallel/ungated. 52 + 53 are opportunistic and block
nothing.

## Congruent polyglot-producer goal + ABI posture (added 2026-06-03 — full detail in [polyglot-producers.md](polyglot-producers.md))

**Goal:** unify the **TS/JS, C, C++, Rust, Zig, Go** toolchains into one congruent wasm capability —
heterogeneous *producers* converging on the homogeneous middle/back end wasmtk already owns (WASI-P1
core-module output → bindgen ABI → binaryen-ts optimize → wasmmerge/wasmbundle link → wasmtk TS WASI
host). Adding a language = adding a producer, not a toolchain.

| Track | Scope | Status / gating |
| --- | --- | --- |
| **ABI forward-alignment (stay P1)** | Canonicalize the **in-memory boundary layout** + the **return convention** now (callee-allocated i32-ptr return + `cabi_post_<name>`; route all boundary allocs through `cabi_realloc`); keep P1 WASI imports behind a thin seam. Both P1-legal; makes future P2 a wrap, not a rewrite. | ⬜ **decided 2026-06-03**, not yet implemented. Independent of Phase 51; small near-term track. |
| **Go producer (TinyGo)** | `tinygo build -target=wasip1` → WASI-P1 core module → shared optimize/host path; `wasmtk run` hosts it (wasmtime optional). Library = reactor exports (`//go:wasmexport`). WASI-first (browser `syscall/js` deferred); stdlib `GOOS=wasip1` heavier fallback. **ADR + scope approved 2026-06-03.** | ⬜ future producer track |
| **C/C++ producer (Zig)** | `zig cc`/`zig c++` (bundled clang + libc-from-source) → `wasm32-wasi`, then through the shared optimize/host path. **ADR: no TS reimplementation of emscripten.** | ⬜ future producer track |
| **Zig producer** | `zig build-exe -target wasm32-wasi` (cleanest native path) | ⬜ future producer track |
| **Rust producer** | Driver = **`rsxtk`** (owner's Rust WASM toolkit, crates.io `jrmarcum/rsxtk`) — builds Rust → `wasm32-wasip1` (+`.cwasm`) and runs via wasmtime; underneath `rustc wasm32-wasip1` (+ Zig as C cross-linker for C-dep crates). No WIT/bindgen yet (stays wasmtk's). `wasm32-wasip2` is the one native-P2 path — decide before mixing into a P1-merge flow. | ⬜ future producer track |
| **P2 producer (real components)** | Embed component-type section + emit/wrap via `wasm-tools component new`; migrate WASI P1→`wasi:cli`/`wasi:io`. | ⬜ **deferred** — only pays off vs. a *native component-runtime* consumer (Wasmtime/WasmEdge/WAMR/Spin); JS-runtime consumers transpile P2 back to core wasm anyway. P1-core + terminal adapter covers the goal. |

**Scope pin:** the congruent contract is **WASI Preview 1 / core modules**. Componentization is a
**terminal optional wrap** of the single merged module (`wasm-tools component new --adapt`), not a
merge-tier rewrite. wasmmerge merges P1 modules; never merge already-built *components* (use `wac`).

**Verified 2026-06-03:** wasmtk itself is NOT a P2 producer — it emits P1 core modules + sidecar
`.wit` + host-side bindgen ABI ("bucket (b)"). Canonical ABI is partial (`cabi_realloc` exported;
return side not canonical, no `cabi_post_return`). See [polyglot-producers.md](polyglot-producers.md)
for the raw evidence and the Zig ADR.

## "TypeScript as a DLL" vision

Compile TS business logic to `.wasm` libraries and load them from a TS host like C uses a DLL.

| C / DLL | wasic |
| --- | --- |
| `.c` → `.dll`/`.so` | `.ts` → `.wasm` via `modc` |
| `.h` header | `.wit` (Phase 41, auto-generated) |
| import lib (`.lib`) | `.bindings.ts` (Phase 50 `bindgen`) |
| `LoadLibrary`/`GetProcAddress` | `loadModule()` from the binding |

Prefer `modc` over `wasic` for consumer-facing modules. The DLL model is complete end-to-end.

## Polyglot ecosystem vision (full detail in [vision.md](vision.md))

WASM as the universal binary, WIT as the universal interface contract; any language → component;
components compose regardless of source language; pixi manages toolchains, wasmtk manages WASM.
Staged: Stage 1 `universalWasmLoader` (JS/TS reference loader + SPEC.md + InstancePool) is the
current priority; Stages 2–5 add Rust/Python/Go/JVM/.NET loaders, `wasmtk build`/`compose` via
pixi, registry + IDE integration.

## Out of scope without more WASM proposals

Goroutines/cooperative multitasking (needs stack-switching), shared memory + atomics (threads),
channels/select, `os.Exit` non-zero propagation (runner enhancement). And the irreducible dynamic
kernel — `eval`/`new Function`, pervasive `any`, open prototype mutation — stays in `javyc` unless
§7-#7 decides to build wasmtk's own dynamic runtime.

## TypeScript feature gaps compilable later (now scheduled — see "Prioritized execution order")

Object spread `{...o, k:v}`, utility types (`Partial`/`Record`/…), destructuring in params,
`Number.parseInt`/`parseFloat`, `instanceof` for class/DU tags, `in` operator, nested destructuring.
As of 2026-06-03 these are no longer unscheduled — they are sequenced into **Phases 51–53** above
(foundational subset gates the async + own-runtime tracks). Full analysis in CLAUDE.md
§ "TypeScript Feature Gap Analysis".
