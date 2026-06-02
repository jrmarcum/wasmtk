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
| 0 | Canonical ABI (`cabi_realloc`, out-param string returns) | ✅ 2026-05-19 |
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
**own dynamic runtime** (#7 decision). Both are large, dedicated efforts.

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

## TypeScript feature gaps compilable later (not scheduled)

Object spread `{...o, k:v}`, utility types (`Partial`/`Record`/…), destructuring in params,
`Number.parseInt`/`parseFloat`, `instanceof` for class/DU tags, `in` operator, nested destructuring.
Full analysis in CLAUDE.md § "TypeScript Feature Gap Analysis".
