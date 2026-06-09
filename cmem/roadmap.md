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

### Phase 51 — Language hardening (GATES #5 async + own-runtime) — ✅ COMPLETE 2026-06-07

All four items done: 51.1 `instanceof`, 51.2 object spread, 51.3 destructuring (param + nested object +
nested tuple), 51.4 utility types. The async (#13) and own-runtime (#14) tracks are now unblocked.

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
2. **Object spread** `{...base, k: v}` — ✅ **DONE 2026-06-07** (test `51_ObjectSpread`, suite
   287→288). `const r: T = { ...src, k: v }` builds the struct at runtime: copies every target field
   from `src` by name (using the base's own offset/type; string fields copy both ptr+len words), then
   applies the named/shorthand overrides; unset fields stay zero. New `parseStructLiteralWithSpread`
   helper + `resolveStructBase`/`emitSpreadStructLiteral` in `src/wasic.ts`; `emitRuntimeStructLiteral`
   delegates when a spread is present (non-spread path unchanged). Both struct-let pre-scans (function +
   module) flag the var in `structSpreadVars` and register it with **ptr=-1** ("pointer lives in the
   local," so every field-read site reads via `local.get`); a `structSpreadMatch` emit branch (before
   the static struct-let handler) owns the assignment. Works for literal/runtime-var overrides, pure
   copy, mixed i32/f64 fields, function-local + module-level, and chained spread (spread of a spread).
   Known limits: single-physical-line literals only; string-field *overrides* still store ptr-only
   (pre-existing `emitRuntimeStructLiteral` limitation — copies are fine); spread in `return {...}` /
   call-arg position not wired (struct-let + array `push` contexts are).
3. **Destructuring in function params** `f({x, y}: Vec2)` — ✅ **DONE 2026-06-07** (test
   `51_ParamDestructuring`, suite 288→289). Source pre-pass `expandParamDestructuring()` rewrites a
   destructuring param `{ x, y }: Vec2` / `[a, b]: [i32,i32]` to a synthetic struct/tuple param
   `__pd_N: Type` and injects `const { x, y } = __pd_N;` / `const [a, b] = __pd_N;` at the top of the
   body — reusing the existing struct-param + `const {…}=obj` / `const […]=tup` machinery (no new emit
   path). Runs before `parseFunctions`. Also fixed `parseParams`' comma-split to be **bracket/brace-aware**
   (was paren-only, so a tuple-type param `[i32, i32]` split at the inner comma). Covers object params
   (incl. renamed `{a: lo}`), tuple params, destructured-alongside-normal params, struct-var args, and
   multiple destructured params. Known limits: named `function NAME(...)` declarations only (arrow/method
   params are a follow-up); inline tuple-literal *args* (`f([1,2])`) remain a separate pre-existing gap
   (pass a tuple var; struct-literal args work). **Nested destructuring** `const { a: { b }, c } = obj`
   — ✅ **DONE 2026-06-07** (test `51_NestedDestructuring`, suite 289→290). The object-destructure
   emit handler + pre-scan were rewritten from the `\{([^}]+)\}` regex to **balanced-brace detection +
   recursive helpers** (`emitDestructurePattern` / `collectDestructureLocals`): a binding whose value is
   itself a `{…}`/`[…]` pattern recurses into the nested struct/tuple field (pointer fields load the
   stored ptr; inline-tuple fields use the field address) — no temps, nested loads inline. Arbitrary
   depth + renames + Phase-48 zero-default fallback all work, incl. nested destructuring in a param
   (`f({a:{b}}: T)`, via the param pre-pass). **Nested tuple/array `const [[a, b], c] = t` — ✅ DONE
   2026-06-07** (test `51_NestedTuple`, suite 290→291). Made the tuple infra bracket-aware end-to-end:
   `tupleTypeName`/`makeTupleStructDef` now split bracket-aware and **embed a nested tuple element
   inline** (`tupleTypeName` field, natural-aligned, size = nested totalSize); tuple-literal construction
   (`const t: [[i32,i32],i32] = [[1,2],3]`) recurses via `emitTupleLiteralStores` (stores sub-elements at
   `baseOffset+field.offset`); tuple destructuring routes through the same recursive
   `emitDestructurePattern` as objects (balanced-bracket detection). Works for mixed f64/i32, nested tuple
   **params** (`f([[a,b],c]: [[i32,i32],i32])`), and preserves positional gaps. **Phase 51.3 COMPLETE.**
   **Process note:** the test runner judges by per-step **exit code, not output diff** — a broad codegen
   change can silently alter output while still "passing". Always output-verify (ts-run vs wasm-run) the
   tests your change touches; a gap-collapse bug here (`splitBraceAwareCommas` drops empty elements →
   `[a, , c]` read the wrong index) passed the suite but was caught by output-diffing `21_*`. Fixed with
   `splitBraceAwareCommasKeepEmpty`.
4. **Utility types** — ✅ **DONE 2026-06-07** (test `51_UtilityTypes`, suite 291→292). First batch
   shipped: **`Partial`/`Readonly`/`Required`/`NonNullable`** are pass-through (resolve to the inner
   type — all layout-identical in wasic's fixed-struct world; `NonNullable` also strips `| null`),
   done by `expandUtilityTypes()` (source text transform with balanced `<…>` extraction, BEFORE
   parseStructs, loops for nesting like `Partial<Readonly<T>>`). **`Pick`/`Omit`/`Record`** synthesize
   struct types via `expandStructUtilityTypes()` (AFTER parseStructs, needs the base def): `Pick`/`Omit`
   copy the base fields (subset / complement) PRESERVING offsets + totalSize so a base-typed value is
   layout-compatible; `Record<"a"|"b", V>` builds a fresh struct keyed by the literal-union (open-key
   `Record<string,V>` is a dynamic map → left unresolved). Both `type Alias = Pick<…>` (registered under
   the alias, decl stripped) and inline use sites (synth `Pick_T_K` name — MUST start uppercase so
   `[A-Z]\w*` struct-type detection fires) work. **Deferred (the "then" batch):**
   `Exclude`/`Extract`/`ReturnType`/`Parameters` (union/function-type ops, niche in wasic). **Bonus fix
   found via output-verification:** `console.log("x:", a.i + b.i)` on i32 **struct fields** (and 3-term
   `a+b+c` of i32 locals) emitted `f64.add` of i32 loads → compile error; fixed in `console_log.ts` by
   inferring the binary-op operand type from the LHS's **leading atom** (var / `var.field` via
   `structLookup` / `.length`), conservatively skipping `arr[i]`/`fn()`/`a.b.c` so f64 elements aren't
   mis-typed. Purely additive (no existing test could use the pattern — it didn't compile — so zero
   tracked-`.wat` changes). NOTE: a SEPARATE pre-existing bug remains — `console.log("x:", arr[i] + arr[j])`
   (array-element arithmetic) returns only the first element; out of scope here.

### Pre-Phase-52 correctness cleanup — 14 output-mismatch bugs (ALL FIXED 2026-06-08)

A pre-Phase-52 code audit + **test-runner hardening** (now diffs run-ts vs run-wasm OUTPUT, not just
exit codes — see testing.md / compiler-bugs.md "Runner-hardening audit") revealed **31** tests that
were green-but-wrong. **12 fixed** in that pass (two string-literal-masking scanner bugs), **5**
allowlisted as legitimate divergences, and the remaining **14 were ALL FIXED 2026-06-08** (clusters:
exceptions/error string payloads, string ops/formatting, struct-field mutation, for…of, class-array
literal — full root-cause list in compiler-bugs.md). A follow-up hazard audit (2026-06-08) fixed 4
more latent issues: brace-less single-line `for…of` (dropped body), `console.error` bool-array-method
formatting, the class-instance `ptr<0` sentinel, and extended the greedy-regex `parenDepthNeverNegative`
guards. Suite under the hardened runner: **293/293** (no open bugs), bindgen 103/103, jstyper 73/73.

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

**Goal:** unify the **TS/JS, Rust, Zig, Go** toolchains into one congruent wasm capability —
heterogeneous *producers* converging on the homogeneous middle/back end wasmtk already owns (WASI-P1
core-module output → bindgen ABI → binaryen-ts optimize → wasmmerge/wasmbundle link → wasmtk TS WASI
host). Adding a language = adding a producer, not a toolchain.

| Track | Scope | Status / gating |
| --- | --- | --- |
| **ABI forward-alignment (stay P1)** | Canonicalize the **in-memory boundary layout** + the **return convention** now (callee-allocated i32-ptr return + `cabi_post_<name>`; route all boundary allocs through `cabi_realloc`); keep P1 WASI imports behind a thin seam. Both P1-legal; makes future P2 a wrap, not a rewrite. | ⬜ **decided 2026-06-03**, not yet implemented. Independent of Phase 51; small near-term track. |
| **Go producer (TinyGo)** | `tinygo build` → wasm → shared optimize/host path. Library-first; stdlib `go` heavier fallback. | ✅ **v1 SHIPPED 2026-06-06, refined 2026-06-07** via `--lang=go` (path defaults to cwd): `init` (scaffold a **wasm library** by default; `--go-target=wasm` for a browser project), `modc` (**WASI reactor library** by default — `-buildmode=c-shared`: no `_start`, exports `//go:wasmexport` funcs, callable via `wasmtk mod`/bindgen; `--go-target=wasm` for a browser module + `wasm_exec.js`), `run` (build wasip1 command + run; **auto-detects** a `.go` file or a dir with `go.mod`, no flag needed). `--go-runtime=tinygo`(default)/`std`. `src/gowasic.ts`. **wasm-opt:** real `wasm-opt` → TinyGo full (incl. goroutines); else passthrough shim + `-scheduler=none` + **binaryen-ts `-Oz`** (no external binaryen; goroutine-free). **2026-06-07 changes:** `wasic --lang=go` REMOVED; `modc --lang=go` flipped browser→reactor-library (the formerly-deferred reactor/library item, now DONE — Go analog of TS `modc`); required a `_initialize` fix in `wasmtk mod`/`run` (reactor exports trap otherwise) + a `syscall/js`-in-library-build hint. Verified `modc --lang=go` lib → `wasmtk mod lib.wasm add 2 3` → 5. **Still deferred:** Go string/aggregate **bindgen** host marshalling (needs ABI forward-alignment — Go's layout ≠ Canonical ABI); a *mergeable* Go leaf (alloc-free `wasm-unknown`) is feasible but not auto-wired. Fixture: `tests/go_fixtures/hello.go` (not auto-run — needs TinyGo). |
| **asyncify pass in binaryen-ts** | Port binaryen's `--asyncify` pass into `@jrmarcum/binaryen-ts` so wasmtk can be TinyGo's `wasm-opt` for **goroutine** code too (no external binaryen at all). Today binaryen-ts has `-Oz` but NOT asyncify, so goroutine Go needs a real `wasm-opt` installed. | ⬜ **future (large)** — asyncify is one of binaryen's most complex whole-program passes (~1.5k LOC) with an exact ABI contract TinyGo depends on; do it properly upstream in binaryen-ts, not rushed. Unblocks goroutine Go on the binaryen-ts path. |
| **Zig producer** | `zig build-exe` (cleanest native path) | ✅ **SHIPPED 2026-06-07** (`src/zigwasic.ts`, `--lang=zig`): `init` (wasm-library scaffold), `modc` (freestanding library, `--export=<name>` scanned + binaryen-ts `-Oz`), `run` (`wasm32-wasi` on wasmtk's TS host; auto-detects `.zig`). Comptime-guarded scaffold `main` (Zig analyzes `main` even with `-fno-entry`). See [polyglot-producers.md](polyglot-producers.md). |
| **Rust producer** | Driver = **`rsxtk`** (owner's Rust WASM toolkit, crates.io `jrmarcum/rsxtk`). | ✅ **SHIPPED 2026-06-07** (`src/rustwasic.ts`, `--lang=rust`) — **delegates fully to rsxtk**: `init`/`initmod`/`modc`(→build wasm)/`build`(→build wasi)/`run`/`add`/`remove`/`list`/`fmt`/`clean`. Prereq `rustup target add wasm32-wasip1`. No WIT/bindgen yet (stays wasmtk's). Known rsxtk-side gap: `initmod` library + `build`/`mod` expects a `main` (rsxtk template lacks `[lib]`/crate-type — fix in rsxtk). `wasm32-wasip2` is the one native-P2 path — decide before mixing into a P1-merge flow. |
| **P2 producer (real components)** | Embed component-type section + emit/wrap via `wasm-tools component new`; migrate WASI P1→`wasi:cli`/`wasi:io`. | ⬜ **deferred** — only pays off vs. a *native component-runtime* consumer (Wasmtime/WasmEdge/WAMR/Spin); JS-runtime consumers transpile P2 back to core wasm anyway. P1-core + terminal adapter covers the goal. |

**Scope pin:** the congruent contract is **WASI Preview 1 / core modules**. Componentization is a
**terminal optional wrap** of the single merged module (`wasm-tools component new --adapt`), not a
merge-tier rewrite. wasmmerge merges P1 modules; never merge already-built *components* (use `wac`).

**Verified 2026-06-03:** wasmtk itself is NOT a P2 producer — it emits P1 core modules + sidecar
`.wit` + host-side bindgen ABI ("bucket (b)"). Canonical ABI is partial (`cabi_realloc` exported;
return side not canonical, no `cabi_post_return`). See [polyglot-producers.md](polyglot-producers.md)
for the raw evidence.

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
current priority; Stages 2–5 add Rust/Python/Go/JVM loaders, `wasmtk build`/`compose` via
pixi, registry + IDE integration.

## Out of scope without more WASM proposals

Goroutines/cooperative multitasking (needs stack-switching), shared memory + atomics (threads),
channels/select, `os.Exit` non-zero propagation (runner enhancement). And the irreducible dynamic
kernel — `eval`/`new Function`, pervasive `any`, open prototype mutation — stays in `javyc` unless
§7-#7 decides to build wasmtk's own dynamic runtime.

## TypeScript feature gaps compilable later (now scheduled — see "Prioritized execution order")

Utility types (`Partial`/`Record`/…), destructuring in params, `Number.parseInt`/`parseFloat`,
`in` operator, nested destructuring. As of 2026-06-03 these are no longer unscheduled — they are
sequenced into **Phases 51–53** above (foundational subset gates the async + own-runtime tracks).
Done so far: `instanceof` (51.1, 2026-06-05) and **object spread `{...o, k:v}` (51.2, 2026-06-07)**.
Full analysis in CLAUDE.md § "TypeScript Feature Gap Analysis".
