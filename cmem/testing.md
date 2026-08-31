# Testing

## Running the suites

```bash
# Full wasm_wasi suite (phase tests + Go-by-Example + capability pipelines)
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts

# Optional 2nd arg = regex filter on file basenames (scope to one phase/feature):
deno run ... tests/wasi_tests.ts tests/wasi/wasm_wasi "^15_"       # phase 15
deno run ... tests/wasi_tests.ts tests/wasi/wasm_wasi "^18[c-g]_"  # all 5 capability pipelines

# Separate runners:
deno run ... tests/bindgen_tests.ts     # bindgen unit + integration
deno run ... tests/jstyper_tests.ts     # jstyper unit

# ⚠️ TWO suites are Deno.test-based and need `deno test`, NOT `deno run`:
deno test --no-check --allow-read --allow-write --allow-run --allow-env \
  tests/hybrid_tests.ts tests/wasmmerge_guard_tests.ts     # expect 12 passed (10 + 2)
```

**`deno run` on those two exits 0 having executed NOTHING** — no output, no failures, a silent pass.
Every other `tests/*_tests.ts` is a self-driving script with its own summary block; only
`hybrid_tests.ts` and `wasmmerge_guard_tests.ts` register `Deno.test(...)` cases (verify with
`grep -l "Deno.test(" tests/*_tests.ts`). `--no-check` is required: `hybrid_tests.ts:69` has a
pre-existing `new Set(...)` inference error that fails type-checking but not the tests. (Found
2026-07-30 — the Phase 19 gate ran them with `deno run` and got two empty results that looked green.)

**CRITICAL:** the runner invokes the **globally installed** `wasmtk` (`WASMTK_BIN = "wasmtk"`).
After editing anything in `src/` or `deno.json` you MUST reinstall before the suite reflects it.
**Always reinstall via the `install` task** — it is the single source of truth for the permission
flag set, so the launcher can never drift:

```bash
deno task install
```

The task (in `deno.json`) expands to:

```bash
deno install -g --allow-run --allow-read --allow-write --allow-env --allow-ffi --allow-net \
  --config deno.json --force -n wasmtk main.ts
```

⚠️ Do NOT hand-write the `deno install` line — **`--allow-ffi` is required**. If it is omitted, the
installed launcher prompts interactively (`Deno requests ffi access … [y/n/A]`) on every `wasmtk`
invocation, which stalls the whole test run. (Regression history: a documented reinstall command
here once omitted `--allow-ffi`; fixed 2026-06-08 by deferring to `deno task install`.)

## Which suites to run for a given change (owner policy, 2026-07-28)

**Rule: when a BUG IS FOUND/FIXED, run the ENTIRE suite set — including `wast_tests` — to catch
overlapping regressions.** Skip suites only when the change is *provably* outside their reach; the
map below is the evidence for that call. "Outlier" is relative to WHICH FILE changed, never absolute.

**Corollary — no bug, no `src/` change, no full suite (owner directive 2026-07-30).** The gate is
triggered by a CHANGE, not by the act of running a batch. When every new stress test passes as
written and nothing under `src/` was edited, the phase filter is the complete gate — **stop there.**
New `.ts` files in `tests/wasi/wasm_wasi/` are inert with respect to the rest of the corpus: each
test compiles and runs in isolation, so they cannot perturb another test's result. Spending >10
minutes to re-confirm 400 untouched tests buys nothing. (Recorded after the Phase 31 TypedArray
batch, where all three tests passed first try and a full run was started needlessly.)

**A change to `src/wasic.ts` / `src/console_log.ts` (the compiler) reaches:**

| Suite | Why it is reached |
| --- | --- |
| `wasi_tests` | drives `wasic` / `modc` / `run` |
| `bundle_tests` | `wasic` on multi-file projects |
| `bindgen_tests` | `modc` = wasic library mode |
| `merge_tests` | `wasic` + `modc` |
| **`go_merge_tests`** | **compiles a TypeScript driver with `wasic` (`tests/go_merge_tests.ts:70`)** — only the merged *leaf* is Go, so this is NOT a Go-only suite |
| `dync_conformance_tests`, `dync_cross_runtime_tests` | `src/dync.ts` imports `compileWasiTs` from `wasic.ts`, so every dync program is wasic-compiled |

**Independent of wasic codegen (safe to skip for a pure-wasic change) — each with its OWN trigger:**

| Suite | Exercises | Its own trigger |
| --- | --- | --- |
| `hybrid_tests` | `src/hybrid.ts` parser/scanners (unit) | `src/hybrid.ts` |
| `jstyper_tests` | `src/jstyper.ts` (unit; emits `.ts`, never compiles) | `src/jstyper.ts` |
| `wast_tests` | `src/wast.ts` → `wabt` only | **any `binaryang` backend bump** (one package since 2026-08-27 — a bump moves the assembler AND the optimiser together), `src/wast.ts`. A bump makes this gate go RED by design — `GAINED COVERAGE` and/or `failures N → M` — see next-work.md |
| `engine_cross_check_tests` | the built `.wasm` corpus → standalone engines | **any codegen change** (`src/wasic.ts`, `src/console_log.ts`), any backend bump, any WASI-ABI change. Run it after `wasi_tests` regenerates the corpus |
| `varscope_tests` | `src/varscope.ts` | `src/varscope.ts` |
| `wasmmerge_guard_tests` | `src/wasmmerge.ts` | `src/wasmmerge.ts` — **and wasic merge-path changes**, which call into it |
| `mod_tests` | loads 36 **committed** `.wasm` fixtures under `tests/module/wasm_mod/`; no compile step | the loader, `src/utils.ts` |
| `go_bindgen_tests`, `go_asyncify_tests` | `--lang=go` → `gowasic` (+ `bindgen.ts`) | `src/gowasic.ts`, `src/bindgen.ts` |

**Verify, don't assume.** The quickest check of what a suite actually drives:

```bash
grep -ohE '"(wasic|modc|dync|bindgen|run)"' tests/<suite>.ts | sort -u   # CLI verbs it shells out to
grep -ohE '^import .*from "\.\./src/[a-z_]+\.ts"' tests/<suite>.ts       # src modules it unit-tests
```

`go_merge_tests` was mis-classified as a Go-only outlier until this grep showed the `wasic` call.

## Current pass counts (2026-08-31, **v2.0.2 released**, binaryang **1.5.3** — fully gated, nothing moved from 1.5.2)

> ### EVERY suite in the repo is green (2026-07-30, re-measured on the v2.0.0 tree) — full roster
>
> | Suite | Result |
> | --- | --- |
> | `tests/wasi/wasm_wasi` (`wasi_tests.ts`) | **417 / 417** — 412 + the Phase 34 type-predicate batch (3 owner stress tests; 2 passed as written, 1 exposed the inline-target bug) + 2 regressions, 2026-07-30. Full suite RE-RUN: the fix changed `src/wasic.ts`, so the gate applied |
> | `wast_tests.ts` | **288 files, 37370 passing assertions** — ON BASELINE (re-recorded 2026-08-31 after `ref.null` support: +123 assertions across 16 files, 0 regressions), with **15 files pinned WITH failures** and **0 unrunnable**. On **binaryang 1.5.3** (was wabt-ts 1.4.1 before the 2026-08-27 merge; unchanged across 1.5.1 → 1.5.2 → 1.5.3). The +9264 passes are the 1.4.0/1.4.1 bump landing after the three malformations it exposed were fixed: an earlier 1.4.0 attempt was reverted when it took wasi to 378/417 and both dync suites to 0. **The gain is mostly recovered COVERAGE, not new correctness** — 14 of the 15 newly-pinned files went `unbuilt → 0`, so modules that could not previously be assembled now run and expose real conformance gaps (`ref_cast`, `ref_test`, `br_on_cast`, `table_grow`, … — GC/ref-types). Those failures were always there; they were invisible. See compiler-bugs.md |
> | `bindgen_tests.ts` | 142, 0 failed |
> | `engine_cross_check_tests.ts` | **376 modules × 3 engines = 1128 pairs, ALL ON BASELINE** — the multi-engine gate (2026-08-24). V8 vs wasmtime/wasmer/wazero, byte-identical stdout. Baseline `tests/engine_baseline.json`. **Re-recorded 2026-08-25 after the `try_table` migration: wasmtime 364 match / 12 reject / 0 differ** (was 354/22 — 10 modules flipped `reject → match` once EH stopped being legacy). The 37 `differ` on the very first run were the `fd_write` short-write bug, fixed the same day. **Re-recorded AGAIN 2026-08-27 when the `-Oz` skip was lifted: wasmer 363 match / 13 reject** (was 353/23 — 10 modules that wasmer REJECTED as raw wabt output load once binaryen has optimised them). wazero unchanged at 346/30. Verified ALL ON BASELINE again on binaryang 1.5.3 with `0 regressed, 0 improved` |
> | `go_merge_tests.ts` · `go_bindgen_tests.ts` · `go_asyncify_tests.ts` | **7 / 7 · 7 / 7 · 12 / 12** — green on **Go 1.26.7 + TinyGo 0.41.1**. TinyGo 0.41.1 caps at Go 1.26; a Go 1.27 install breaks all three (`requires go version 1.19 through 1.26`). Keep the pair in step — Go 1.27 is safe only once TinyGo **0.42.0** ships (support is on `dev`). See [next-work.md](next-work.md) |
> | `bundle_tests.ts` | **4 / 4** — `StructImport` fixed, no longer a standing failure |
> | `mod_tests.ts` · `merge_tests.ts` · `varscope_tests.ts` · `wasmmerge_guard_tests.ts` | 0 failed |
> | `hybrid_tests.ts` · `jstyper_tests.ts` | 0 failed |
> | `go_bindgen_tests.ts` · `go_merge_tests.ts` · `go_asyncify_tests.ts` | 0 failed — TinyGo IS installed, so these genuinely ran; they did NOT self-skip |
> | `dync_conformance_tests.ts` · `dync_cross_runtime_tests.ts` | 0 failed |
>
> **How 375 → 400:** +8 stress tests in the 22/24/25/26 batch
> (`22_ConstEnumFoldingAndExponentCast`, `24_NullableTupleReturnAndFlags`,
> `25_NullishOnlyNullFallback`, `25_LogicalAssignmentOperators`,
> `25_NullishShortCircuitSideEffects`, `26_ForOfBreakContinue`, `26_ArrayDestructuringDefaults`,
> `26_NestedForOfMatrix`) — 5 of which surfaced real compiler bugs; +1
> `12_LowercaseStructTypeName` (the `bundle_tests` StructImport fix); +3 Phase 27 string tests
> (`27_StringSplitAndForOf`, `27_StringTrimPadReplace`, `27_CharCodeAndSubstringQuery`) which
> surfaced the `emitStringPtrLen` parity gap; +3 Phase 28 array-method tests
> (`28_ArrayPredicatesAndAt`, `28_ArrayMutationsAndSort`, `28_ArrayJoin`) which surfaced
> `join`-has-no-string-value; +1 `27_ConsoleLogBracketConcat` (the `]`/`)`-in-literal concat bug
> that `28_ArrayJoin` exposed as a side-discovery); **+3 Phase 29 class tests
> (`29_StaticFieldsAndGlobals`, `29_GettersAndSetters`, `29_StringEnumDispatch`) +1
> `22_MultiplicativeAssociativity`** — the getter/setter test exposed that `*`/`/`/`%` were parsed
> RIGHT-associatively (`180 * 5 / 9` gave 0), the single most consequential bug of the series;
> **+3 Phase 30 tests (`30_NamespaceConstAndFunction`, `30_InterfaceInheritanceExtends`,
> `30_ShorthandPropertyReturn`) +1 `30_NamespaceInternalRefs`** — the namespace test exposed that
> unqualified references to a namespace's own members were never rewritten, and probing that
> surfaced (and fixed) string-typed namespace members: **+1 `30_NamespaceStringMembers`**.
> All post-mortems in compiler-bugs.md.
>
> **412 → 417 (2026-07-30):** +3 Phase 34 type-predicate stress tests
> (`34_TypePredicateBasicNarrowing`, `34_TypePredicateElseIfChains`,
> `34_DiscUnionPredicateInlineTarget`) +2 regressions (`34_InlinePredicateTargetNarrowing`,
> `34_InlinePredicateUnresolvable` — `@expect-fail: compile`). Tests 1–2 passed as written; test 3
> writes the predicate target as an INLINE object type (`g is { type: "sphere"; r: f64 }`), which
> the function-header regex did not admit — so the predicate function was never parsed and the call
> died with a misleading "Unknown function". Fixing that exposed a second bug underneath: an inline
> target resolves to no registered type, so narrowing was skipped and a hierarchy field read printed
> `0` instead of `5`. See compiler-bugs.md § "Phase 34 inline predicate target".
>
> **410 → 412 (2026-07-30):** +2 Phase 33 regressions for the base-prefix guard —
> `33_IntersectionBasePrefixGuard` (`@expect-fail: compile`; the reversed-order shape that used to
> print `1.6` instead of `6`) and `33_IntersectionPrefixOk` (the four prefix-compatible shapes the
> guard must NOT reject). `src/wasic.ts` + `src/console_log.ts` changed, so the full gate applied.
>
> **407 → 410 (2026-07-30):** +3 Phase 33 intersection-type stress tests
> (`33_IntersectionMixedTypeMerge`, `33_ChainedIntersectionIntDivide`,
> `33_IntersectionBasePointerParam`). All three passed as written, every printed value matching the
> owner's inline `// Expected:` annotations, so the `"^33_"` filter (7/7) was the whole gate. **A
> follow-up probe on test 3's mechanic did surface a bug** — base-pointer passing is only sound when
> the base interface is the FIRST constituent of the intersection; see compiler-bugs.md § "Phase 33
> intersection base-prefix".
>
> **403 → 407 (2026-07-30):** +3 Phase 19 discriminated-union stress tests
> (`19_DiscUnionSuperStructLayout`, `19_SwitchCaseVariantDispatch`, `19_ElseIfNarrowingFieldCast`)
> +1 regression `19_UnionSharedFieldWidening`. Test 3 exposed that a field name shared by two
> variants took the FIRST variant's type — `val: i32 | f64` laid out as 4-byte i32, truncating
> `25.5` to `25` on store and emitting `i32.load` into an `(result f64)` function (invalid WASM).
> Fixed by resolving/widening shared fields instead of skipping them. See compiler-bugs.md.
>
> **400 → 403 (2026-07-30):** +3 Phase 31 TypedArray stress tests
> (`31_TypedArraySubWordAccess`, `31_TypedArrayLiteralInitializer`, `31_TypedArrayFillAndSet`).
> **The first batch of the series to surface NO bug** — all three passed as written, every printed
> value matching the owner's inline expectations. See compiler-bugs.md § "Phase 31 TypedArray
> stress batch" for what they cover and why the phase was already solid.
>
> ⚠️ **Do NOT run the Go suites concurrently with other suites on Windows.** Running
> `go_asyncify_tests` alongside the full wasi suite produced 4 spurious failures — all `os error 32`
> ("file is being used by another process") on `tests/go_fixtures/**/main.wasm`, i.e. the TinyGo
> build / asyncify write racing the OS file lock, NOT assertion failures.
>
> 🔁 **CORRECTION 2026-08-31 — "run alone it is 12/12" is NOT reliable.** Measured back-to-back with
> nothing else running: run 1 **11/1** (`nested (re-entrant suspend)`, `os error 32` on
> `writefile … nested/main.wasm`), run 2 **12/12**, same inputs. Concurrency with *other suites* is
> not the only trigger — a **preceding run of this same suite** is enough, because handles from the
> prior run's spawned processes are still closing. Practical rule: **let the machine settle between
> Go-suite runs, and re-run once before believing an `os error 32` failure.** It is an OS race, never
> an assertion failure — the tell is `os error 32` in the message and a passing assertion count
> everywhere else.
>
> ⚠️ **This can fail a release gate.** If a publish run trips it, re-run rather than investigating
> the Go producer. A retry-with-backoff around the asyncify write in `src/gowasic.ts` would remove it
> for good; deliberately NOT done inside a release batch — see [next-work.md](next-work.md).
>
> **Runner note:** a full `tests/wasi/wasm_wasi` pass now exceeds 10 minutes on this machine; run it
> backgrounded or with a raised timeout. Beware the shell idiom `… ; grep -c "FAILED"` as the last
> command — `grep -c` exits **1** when the count is 0, so a perfectly green run reports a non-zero
> script exit. Check the runner's own `EXIT=` / summary block, not the trailing pipeline status.

### Snapshot as of 2026-07-08 (wabt-ts 1.3.5 + binaryen-ts 1.4.0)

| Suite                                                                                           | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/wasi/wasm_wasi` (full, HARDENED output-diff runner)                                      | **375 / 375** (+`67_TrigCorrectlyRounded` 2026-07-01 — mathlib `sin`/`cos`/`tan` are now IEEE-754 **correctly-rounded** double-double (validated bit-for-bit vs a BigInt CR oracle through the full pipeline); the 23 printed values are correctly-rounded doubles that for these args also equal V8's `Math.*`, so wasm==ts. See compiler-bugs.md issue 5 + design-decisions.md. +`66_Dragon4Formatting` 2026-07-01 — report issue 6: `$__f64_to_str` rewritten as pure Dragon4 (Burger-Dybvig), 100% byte-exact f64→string vs V8 incl. subnormals/max/scientific + fixes the old formatter's TRAP on `                                                                                                                                                                                                                                                                                                                                                                                 |
| `bindgen_tests.ts`                                                                              | **142 / 142** (functions-as-`any` both directions: core→host `testIntegrationFnAny` `getDoubler()(21)=42` + proxy-robustness assertions; **#14 Phase 2 host→core `testIntegrationHostFn`** — `applyTwice(n=>n+1,10)=12` / `combine((a,b)=>a*b,6,7)=42` via the `env.__host_call` import + host-fn table; **+4 SPEC §10 loader assertions 2026-07-08** — the generated loader always ships a minimal WASI-P1 shim + calls `_initialize`, so a WASI-importing library (TinyGo reactor, or a `modc` lib that `console.log`s) instantiates; **+7 kebab-round-trip assertions 2026-07-08** — `testIntegrationKebab` (fixture `kebabcase_50`, exports `readID`/`toHTML`) proves the generated loader's `_ex()` resolver binds capital-heavy exports the lossy WIT kebab↔camel round-trip can't reconstruct (fails pre-fix with `exp["readId"] is not a function`). See `go_bindgen_tests.ts` + polyglot-producers.md § "Go string/aggregate bindgen" + compiler-bugs.md § "Code-audit sweep".) |
| `go_bindgen_tests.ts` (TinyGo-gated; skips if absent)                                           | **7 / 7** — Go→bindgen integration: `wasmtk modc --lang=go tests/go_fixtures/strlib` → `wasmtk bindgen strlib.wit` → drive the generated loader: `greet`/`strLen` round-trip incl. UTF-8. Proves TinyGo string libraries are consumable by bindgen over the **canonical** ABI unchanged (Go strings are UTF-8 (ptr,len); a `//go:linkname cabi_realloc` wrapper + `cabi_post_<name>` matches wasic's shape).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `go_merge_tests.ts` (new 2026-07-08; TinyGo-gated) | **7 / 7** — MERGEABLE Go leaf: `wasmtk modc --lang=go --go-target=wasm-unknown tests/go_fixtures/leaf/mathleaf.go` builds an alloc-free `wasm-unknown` leaf (0 imports, no `memory.grow`), then `wasmtk wasic use_mathleaf.ts` merges it (`import { addi, muli, clampi } from "./mathleaf.wasm"`) and `run` computes `addi(3,4)=7`/`muli(5,6)=30`/`clampi(42,0,10)=10`. Proves Go leaves `wasmmerge` like a Zig `FixedBufferAllocator` leaf (`mergeOneWasmImport` calls the leaf's `_initialize`). See polyglot-producers.md § "Mergeable Go leaf". |
| `go_asyncify_tests.ts` (TinyGo-gated; broadened 2026-07-09)                                     | **12 / 12** — GOROUTINE Go with NO external binaryen, forced via `WASMTK_GO_BINARYEN_ASYNCIFY=1`: table-driven over the full surface — worker-pool (`sum: 30`), `select` over unbuffered channels (`select-total: 300`), `time.Sleep` (`sleep-result: 42`), `sync.WaitGroup`+`Mutex`+closure+defer (`wg-counter: 45`), 3-stage fan-out pipeline (`pipeline-total: 55`), and **`nested/` — a goroutine that suspends INSIDE another suspending goroutine (`nested-sum: 36`)**. Each builds `-scheduler=asyncify` + passthrough shim, then `binaryenAsyncify` (binaryen-ts ≥ **1.4.3** Asyncify import-mode + `-Oz`). `nested/` was the reproducer for binaryen-ts **WT-2k** (a binary-DECODER reorder bug that miscompiled TinyGo's goroutine trampoline — NOT asyncify; fixed in 1.4.3). Asserts the in-house path was used + correct output.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `jstyper_tests.ts`                                                                              | **73 / 73**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `hybrid_tests.ts` (2026-07-08; +2 for B5 2026-07-09)                                            | **10 / 10** — unit tests for the context-aware `hybrid` scanners: `findCloseBrace`/`rewriteWasmCalls` must not be fooled by a `}`/quote/regex inside a string/comment/regex, must rewrite a routed call inside a template `${…}` interpolation, must NOT rewrite an object method shorthand, and must inject `loadModule` after a MULTI-LINE import. **+2 (B5, teeth-verified):** a **nested backtick template inside a `${…}` interpolation** — whose inner text holds a `}` — must not truncate a `@wasm` body (`skipLiteral` now descends into `${…}` via `findInterpEnd`), and a doubly-nested interpolation must not defeat call-rewriting. See design-decisions.md § "hybrid call-rewriting … MUST be context-aware".                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `wasmmerge_guard_tests.ts` (new 2026-07-09; Go-free)                                            | **2 / 2** — unit tests for the `wasmmerge` foreign-runtime guard: a hand-assembled module that calls `memory.grow` (stands in for STANDARD Go's full runtime / any growing allocator) is REJECTED with actionable guidance ("STANDARD Go … build a MERGEABLE leaf with TinyGo `--go-target=wasm-unknown`"), and NOT with the red-herring `call_indirect` "refactor to direct calls" message; an alloc-free leaf (no `memory.grow`) does NOT trip the guard. See polyglot-producers.md § "Ordering fix + std-Go coverage".                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `dync_conformance_tests.ts` (#14 2h Javy-parity gate)                                           | **3 / 3** — for each fixture in `tests/wasi/wasm_wasi_dync/` (demo1/2/3), `wasmtk dync`→`.wasm`→`run` stdout must byte-match a `deno run` JS baseline. Proves the OWN dynamic runtime is a drop-in `javyc` replacement (no Javy/QuickJS). Caught the `Math.min`/`max` 2-arg bug (now variadic). Out of scope: interactive `prompt` + ESM import/export of other modules.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `dync_cross_runtime_tests.ts` (pure-WASI portability gate, 2026-07-27; external runtimes skip-if-absent) | **3 / 3** — proves `wasmtk dync` output is PORTABLE. Per fixture in `tests/wasi/wasm_wasi_dync/`: compile, then (INVARIANT, always checked even in a runtime-free CI) the `.wasm` must import ONLY `wasi_snapshot_preview1`; then (EXECUTION, skip-if-absent like the TinyGo gates) under each of wasmtime/wasmer/wazero present, stdout must byte-match the `deno run` baseline. Guards `internalizeDynrtHostImports` (dropped the wasmtk-only `env.__host_print`/`__host_call` → inline WASI `fd_write` + `unreachable` trap). Run: `deno run --allow-read --allow-run --allow-write --allow-env tests/dync_cross_runtime_tests.ts`. |
| Capability pipelines `18c`–`18g` (Set/Map/Date/JSON/RegExp) + `18h` (virtual `wasmtk:` imports) | **6 / 6**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `wast_tests.ts` (`.wast` spec-runner regression gate, 2026-07-02, wabt-ts 1.3.5)                | **41 files, 12444 exec assertions pass / 0 fail** — the official WASM spec `.wast` core testsuite run clean through `wasmtk wast` (wabt assemble → host V8). Grew 31→40→41 as wabt-ts **1.3.4** (br_if/br_table-value + hex-float) and **1.3.5** (decimal→f32 double-rounding, Bug C) fixed all 3 findings — `const.wast` now in the gate. Run `deno run --allow-read --allow-net tests/wast_tests.ts`; `wasmtk wast tests/module/wasm_wast/testsuite-main` for the whole suite.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

The 7 previously-failing tests were fixed 2026-06-02: `5e_MixedSignatures`,
`19_NestedDiscriminantUnions`, `19_VariantMaximumMemoryAlignment` (value-fallthru codegen, fixed in
wasic); `38_MathExpLog`, `38_MathHyperbolic`, `38_MathTrig`, `38_Phase38Combined` (hex-float
literals encoded as 0, fixed in wabt-ts 1.3.1). See compiler-bugs.md.

Historical baseline under npm:wabt+npm:binaryen was 446/446 (2026-05-25); the per-phase historical
counts in README are a record of when each phase first went green, not a live invariant.

## `wast_tests` is a PER-FILE BASELINE gate (rebuilt 2026-08-20)

**288 files, 37370 passing assertions, 15 files pinned WITH failures, 0 unrunnable** (re-recorded
2026-08-31 after `ref.null` support landed; was 288 / 37247 on wabt-ts 1.4.1, and 287 / 27983 / 12
on 1.3.5) — up from 41 files / 12444, because the gate no
longer needs a hand-curated file list. Expected pass counts live in **`tests/wast_baseline.json`**
(tracked). Every baselined file must produce **exactly** its baseline: fewer → FAIL (coverage lost),
more → FAIL (baseline stale, re-record deliberately), any execution failure → FAIL as before.

**Why it changed.** The old gate asserted `failed === 0` plus one *global* floor
(`totalPass >= 10000` against ~12444). It could not see a single file losing coverage. When the
2026-08-20 corpus sync took `return_call.wast` from 44 passes to 12, the gate still printed
ALL CLEAN — the loss was caught by hand-measuring before/after, not by the gate. A module that fails
to assemble becomes SKIPs by design, so **silent coverage loss is indistinguishable from success**
unless something pins the per-file number. The corpus could have shed ~2400 more passes unnoticed.

- **A baseline of 0 is deliberate** — it pins a file the toolchain currently cannot assemble at all
  (e.g. `ref_null.wast`, 0 pass / 34 skip). When the backend learns to encode `ref.null`, the gate
  *says so* instead of absorbing the win silently.
- **7 files with genuine execution failures are excluded, not pinned** (`load1`, `linking`,
  `imports`, `annotations`, `type-equivalence`, `float_memory`, `linking0`). Pinning them would
  freeze real bugs in as expected. They are reported each run as "not in the baseline".
- **Re-record** (rewrites the tracked JSON — a reviewable act, not a side effect):
  ```bash
  deno run --allow-read --allow-write --allow-net --allow-run tests/wast_tests.ts --update-baseline
  ```
  Verified deterministic: two consecutive regenerations are byte-identical. `--allow-run` is
  required because the rescan chunks across subprocesses (see the memory limitation below).

## The `wast` runner leaks memory across files (OPEN, found 2026-08-20)

**`wasmtk wast <dir>` over the full 288-file corpus dies** with `Fatal JavaScript out of memory:
Ineffective mark-compacts near heap limit`. This is our bug, not the corpus's, and the directory
form is the one README documents.

> ✅ **FIXED — verified 2026-08-25. Everything in this bullet list is HISTORY; do not act on it.**
> A full 288-file directory run now completes in one process: `37247 passed, 102 failed, 27275
> skipped, 162 unbuilt modules`, no OOM, matching the chunked gate exactly. `exact.wast` reports
> `pass=20 fail=0 skip=16`. The causes were an infinite loop in our S-expr reader on a lone `;` and a
> wabt-ts `parseWat` blow-up on `(ref (exact any))` (fixed in wabt-ts 1.4.1) — **not** memory
> retention. See [compiler-bugs.md](compiler-bugs.md).

- Memory climbs to ~1.9 GB within the first handful of files and then creeps ~1–6 MB per file.
- **One file exhausts the heap on its own**: `proposals/custom-descriptors/exact.wast`.
- A partial fix landed 2026-08-20: `src/wast.ts` used to call `await wabt()` **per file**, creating a
  fresh WABT module that was never released; it is now a process-wide singleton (`getWabt()`). That
  was real, but **not sufficient** — the dir run still OOMs, so the bulk of the retention is
  elsewhere (most likely instantiated modules/memories, including the 64-bit memory tests).
- Consequences today: the 280-file gate *does* fit in one process; a 288-file rescan does not, which
  is why `--update-baseline` chunks across subprocesses and auto-discovers unrunnable files rather
  than carrying a hand-maintained skip list.
  - ⚠️ **The chunking stays regardless** — an OOM cannot be caught in-process, so a single-process
    full-corpus rescan is still one bad file away from losing every result. The fix removes the
    symptom, not the reason for the design.

## The multi-engine gate — `engine_cross_check_tests.ts` (added 2026-08-24)

**Why it exists.** Every oracle this project owned was V8: `wasi_tests.ts` executes on V8 and
`wasmtk wast` validates through host V8. One engine wearing two hats is one data point, not two, so a
defect only a DIFFERENT engine could see was structurally unreachable. That is not hypothetical — it
is how legacy EH stayed invisible at 417/417 for months, and the gate found a second, unrelated bug
(`fd_write` short writes) on its first full run. See [best-practices.md](best-practices.md) §3.

```bash
deno run --allow-read --allow-run --allow-env --allow-write tests/engine_cross_check_tests.ts
deno run … tests/engine_cross_check_tests.ts --filter "^15_"          # scope to a subset
deno run … tests/engine_cross_check_tests.ts --update-baseline        # re-record deliberately
```

Runs every built `.wasm` on V8 (`wasmtk run`) and on each engine present, comparing stdout
byte-for-byte. Per-module, per-engine expectations live in **`tests/engine_baseline.json`**; a module
that regresses fails, and one that IMPROVES fails too until re-recorded — same discipline as
`wast_tests`.

**Baseline as recorded 2026-08-24** (376 modules):

| engine | match | reject | differ |
| --- | --- | --- | --- |
| wasmtime 47.0.3 | **354** | 22 | **0** |
| wasmer 7.2.1 | 353 | 23 | 0 |
| wazero | 346 | 30 | 0 |

- **First recorded with 37 wasmtime-only `differ`** — all one bug, `fd_write` short writes, found by
  this gate's first run and **fixed the same day** ([compiler-bugs.md](compiler-bugs.md)). They
  matched on wasmer and wazero, which is what pinned the cause to a short-write path only wasmtime
  exercises. The fix produced `0 regressed, 37 improved`, the gate failed as designed until the
  baseline was re-recorded, and wasmtime `match` went 317 → 354.
- The **rejects** are dominated by legacy EH (wasmtime) and by wasmer/wazero having no EH at all.
- 🔁 **SUPERSEDED 2026-08-25 by the `try_table` migration — the baseline MUST be re-recorded.** Every
  module that threw now emits the standard exception proposal, so wasmtime loads modules it used to
  refuse and the gate reports them as `IMPROVED: reject → match — re-record` (observed on
  `15_TestCase1-NestedEscalation`, `15_recover`, `64_ReportModuleTryCatch`, `64_ReportThrowTemplate`,
  …). **This is the gate working, not breaking** — it is the "design the gate so an IMPROVEMENT also
  fails" rule in [best-practices.md](best-practices.md) paying out exactly as predicted.
  **RE-RECORDED TWICE.** 2026-08-25 (the `try_table` migration): wasmtime `match` **354 → 364**,
  `reject` **22 → 12**. Then **2026-08-27**, after the `-Oz` skip was lifted: **wasmer** `match`
  **353 → 363**, `reject` **23 → 13** — 10 modules that wasmer REJECTED as raw wabt output now load
  once binaryen has optimised them (the `15_*` family, `18_Multi-Scope…`, `56_AsyncReject`,
  `60_AsyncAll`, the `64_Report*` pair). wasmtime and wazero unchanged. **Shipping optimised output
  is a portability win, not only a size one** — worth remembering next time a skip looks free.
  Both re-records: `0 regressed`. Earlier detail: wasmtime `match` **354 → 364**, `reject`
  **22 → 12** — **10** modules flipped `reject → match` (the `15_*` EH family, `60_AsyncAll`, the
  `64_Report*` pair). The remaining 12 rejects are not EH-related. wasmer (353/23) and wazero
  (346/30) are unchanged, as expected: neither implements EH at all, so an EH change cannot move
  them.
  - ⚠️ **It is 10, not the 8 first reported — and the discrepancy is the lesson.** The first run
    executed BEFORE `wasi_tests` regenerated the corpus, so it graded artifacts built by the
    *previous* compiler and undercounted by two. **Order is load-bearing:
    `wasi_tests` → `engine_cross_check_tests` → `wast_tests`.** A cross-check gate reads a generated
    corpus; running it early produces a real-looking number that answers the wrong question.
- **Absent engines are skipped, never failed.** With no engine on PATH the gate exits 0 with a notice.

⚠️ **Invoke engines as `<engine> run <file>`.** Not cosmetic: wazero answers a bare path with
`invalid command`, which the gate would otherwise record as a legitimate `reject` for every module in
the corpus. This bit during development and is the repo-wide convention (see
`dync_cross_runtime_tests.ts`).

⚠️ **Regenerate the corpus before trusting a run** — the standing rule below. A stale `.wasm` makes
this gate compare against a compiler that no longer exists.

## Vendored spec testsuite — provenance and re-sync (2026-08-20)

`tests/module/wasm_wast/testsuite-main/` is a **verbatim vendored copy** of
[WebAssembly/testsuite](https://github.com/WebAssembly/testsuite) (the amalgamated mirror of
`WebAssembly/spec/test/core` plus the per-proposal repos). It is a tracked INPUT fixture — only the
`wast` runner reads it, so a corpus refresh reaches `wast_tests` and nothing else.

- **Synced 2026-08-20 to upstream `main` @ `65a43d2e9464b6967c98b23c8493765c4d124f4e`.** The tree is
  byte-identical to that commit; verify with a recursive diff against a fresh tarball before
  assuming drift. There are **no local-only files** — never hand-edit anything under
  `testsuite-main/`, or the next sync silently reverts it.
- **Re-sync:** download `https://codeload.github.com/WebAssembly/testsuite/tar.gz/refs/heads/main`,
  `cp -r` over the directory, then **measure per file** — a refresh legitimately adds AND retires
  assertions, so a bare total is not enough to tell a corpus change from a regression.
- **Line endings:** every `.wast` is LF in both the blob and the working tree, and `.gitattributes`
  pins only `*.ts`. With this machine's `core.autocrlf=true`, git warns that `.wast` would become
  CRLF on the next checkout. It has not bitten yet, but a CRLF working tree would break the
  byte-for-byte upstream diff above. If it ever does, add `*.wast text eol=lf` for the same reason
  `*.ts` is pinned (see design-decisions.md).

### `proposals/threads/` is frozen upstream — NOT stale here (checked 2026-08-20)

Recurring false alarm: `proposals/threads/{imports,memory}.wast` still assert `"multiple memories"`
and `"multiple tables"` are invalid, which contradicts the core files in the same checkout. **That
is upstream's own content, not local drift.** Upstream has not touched `proposals/threads/` since
**2020-04-11** (generated from `threads@980c1bca` against `spec@484180ba`), and the live
`WebAssembly/threads` repo — still active — _itself_ keeps the `"multiple memories"` assertions in
`test/core/{imports,memory}.wast`. Refreshing changes nothing. The only genuinely retired ones are
the 3 `"multiple tables"` assertions, fixed in the proposal repo but never propagated into the
testsuite mirror. **Do not "fix" this locally** — it is an upstream propagation gap to file there.

### Known wabt-ts gaps exposed by the 2026-08-20 sync

Not wasmtk bugs — the runner skips any module wabt cannot assemble, and its dependent actions with
it. Each cost passes without costing a single failure:

| File | Pass Δ | Cause |
| --- | --- | --- |
| File | Pass Δ | Cause | Status on wabt-ts 1.4.1 |
| --- | --- | --- | --- |
| `return_call.wast` | 44 → 12 | `ref.null $t` (concrete type index) at `:95` | ✅ **FIXED — now 45 pass / 0 fail**, one better than before the sync |
| `proposals/custom-page-sizes/memory_max*.wast` | 4 → 2 each | `(module definition …)` | ✅ **FIXED** — folded into the +9264 re-record |
| `ref_null.wast` (pre-existing, not from this sync) | 0 / 34 skip | `ref.null` cannot encode for **any** heap type | ✅ **FIXED 2026-08-31 — now 25 pass / 0 fail / 7 skip.** The 7 are V8 refusing to marshal `exnref`/`anyref`/user-defined heap types, classified as skips by `isJsBoundaryRefusal`. Earlier: ⚠️ **RE-ATTRIBUTED — the blocker was OURS.** Still 0 pass / 32 skip on binaryang 1.5.2, but **`unbuilt modules = 0`**: the modules assemble fine. `constType()` in `src/wast.ts` returns `null` for `ref.null` / `ref.func` / `ref.extern`, so our RUNNER skips every such assertion regardless of what the assembler can do. Upstream fixed their half (they report `ref.null` with a user-defined heap type was two defects stacked); our number did not move because we cannot marshal a reference VALUE. |

⚠️ **The original verdict on this table was wrong, and the way it was wrong is worth keeping.** It
read: *"Only the third is a wabt-ts bug; the first two match upstream wabt's own parser, so a wabt-ts
bump will not move them."* **1.4.1 moved both.** The reasoning — "upstream wabt behaves the same, so
this is parity, not a defect" — quietly assumed a downstream port cannot get ahead of its upstream.
It can, and this one did. **Confirming that a behaviour matches upstream tells you where the
behaviour came from, not whether anyone will fix it.** Re-measure such claims on every bump instead
of carrying them forward as settled. Full analysis in [compiler-bugs.md](compiler-bugs.md) §
"wabt-ts `ref.null` + parser gaps"; the report for the wabt-ts team is
`scripts/wabt-ts-bug-report.md`.

## The `-Oz` safety check for `try_table` — `scripts/check_try_table_oz.ts` (added 2026-08-27)

```bash
deno run -A scripts/check_try_table_oz.ts
```

Decides whether the binaryen skip for throwing modules in `src/wasic.ts` may be lifted. Assembles
`scripts/eh_try_table_live_local_fixture.wat` **once** and runs the result both sides of `-Oz` — one
variable, one comparison.

| exit | meaning |
| --- | --- |
| 0 | both sides 42 — the skip MAY be removed, then run the full gate |
| 1 | post-`-Oz` wrong — the skip stays |
| 2 | pre-`-Oz` wrong — the fixture or assembler broke; says NOTHING about `-Oz` |

**binaryang 1.5.1: pre-Oz 42, post-Oz 1 — broken.**
**binaryang 1.5.2: pre-Oz 42, post-Oz 42 — FIXED, and the skip was removed 2026-08-27** after this
checker AND `15_Exceptions` + `15_LexicalShadowing_Stress` AND the full gate all passed, in that
order. The checker stays as the deciding test if it ever needs reinstating.

⚠️ **Passing here is necessary, not sufficient.** The real acceptance gate is `15_Exceptions` +
`15_LexicalShadowing_Stress` in `wasi_tests`. That ordering is not pedantry: the FIRST version of
this fixture passed `-Oz` cleanly while both of those tests were failing, because it kept a local
live across the catch edge without ever **assigning it inside the try**. Only the assignment creates
the dead-store reasoning the optimiser gets wrong. A fixture built to catch a bug can still be built
to miss it.

## CI / pre-publish gate

The only GitHub workflow is `.github/workflows/publish.yml`: it fires on a `v*` tag, runs a **"Check
OIDC availability"** diagnostic step (added 2026-06-15 — surfaces a gated GitHub OIDC token in the
run log) and then **`deno publish`** (with OIDC provenance), then creates a `release/<tag>` branch +
GitHub release. So the _enforced_ CI gate is exactly what `deno publish` validates: **type-check of
all 15 `deno.json` exports + JSR "slow-types" check + package validation**. `deno fmt` / `deno lint`
/ `deno doc --lint` / the test suites are **not** gated by CI — but `deno doc --lint` must be kept
clean to hold the JSR doc-coverage score (see design-decisions.md), and provenance requires the OIDC
token to actually reach the runner (was environmentally gated through v1.6.5; v1.7.0 published
2026-06-15 with `hasProvenance: true`, JSR score 100).

🔴 **Provenance regressed AGAIN and is absent from v1.11.3 onward (found 2026-07-30).** Bisected via
`api.jsr.io/scopes/jrmarcum/packages/wasmtk/versions/<v>` → `rekorLogId`: **v1.11.2 is the last
version with one**, v1.11.3 the first without. **A green publish run is NOT evidence of provenance**
— the OIDC diagnostic step passed on all 10 affected releases (the v1.11.12 run emitted no
`::warning::` at all; its only annotation is an unrelated Node 20 notice, checked via the check-runs
annotations API). Only JSR's `rekorLogId` is evidence. A **"Verify provenance was recorded on JSR"**
step now runs LAST in `publish.yml` and fails the job when that field is null — **it fired correctly
on v2.0.0**, which is the first release to report its own missing provenance instead of passing
silently. **The Deno version was tested and RULED OUT:** v2.0.0 was published with `deno-version`
pinned to `v2.9.1` (the last version that ever produced provenance) and came out unattested anyway,
so the clean-looking 2.9.1/2.9.2 split was coincidental. The pin has been reverted to `v2.x`.
Remaining suspects are JSR-side and GitHub-side changes in the 2026-07-03 → 07-09 window; full
elimination list in design-decisions.md. Confirming from CI logs needs an authenticated `gh` (not
installed here — the Actions logs endpoint 403s unauthenticated).

**⚠️ `deno doc --lint` is NOT a doc-coverage check (measured 2026-07-30).** It passed clean on all
16 entrypoints while JSR reported `percentageDocumentedSymbols: 0.98039216`. It catches
`private-type-ref` / `missing-explicit-type` / missing JSDoc on a *declaration*, but it is blind to
two things that DO cost coverage — a re-exported symbol (`export { x } from …`, counted by JSR,
documented by `deno doc` only once per declaration) and a module whose `@module` tag is followed by
bare prose with no `@description` (renders an EMPTY module description). **To measure coverage for
real, parse the JSON**, which is what the checklist line below does:

```bash
# true documented-symbol coverage + any entrypoint missing a module description
deno doc --json <all 16 exports> | deno eval '
const d=JSON.parse(await new Response(Deno.stdin.readable).text()); let tot=0,un=0,nm=0;
for (const [f,v] of Object.entries(d.nodes)) { if(!(v.module_doc?.doc??"").trim()) nm++;
  for (const s of (v.symbols??[])) for (const dec of (s.declarations??[]))
    if(dec.declarationKind==="export"){tot++; if(!((dec.jsDoc?.doc??"").trim()))un++;} }
console.log("no module description:",nm," documented:",(tot-un)+"/"+tot);'
# expect: no module description: 0   documented: 100/100
```

ℹ️ **`deno-version` in `publish.yml` floats at `v2.x`, so CI publishes on whatever Deno is newest
that day.** It was briefly pinned to `v2.9.1` for the v2.0.0 release to test the provenance
hypothesis; that was **ruled out** and the pin reverted (see design-decisions.md). **If it is ever
pinned again, add a second dry-run under the pinned version to the checklist below** — otherwise
development happens forward on a newer Deno while CI publishes backward, and source using a newer
API would type-check locally then fail `deno publish` **in CI after the tag is already pushed**.
The one-time fetch is
`curl -L -o deno.zip https://github.com/denoland/deno/releases/download/vX.Y.Z/deno-x86_64-pc-windows-msvc.zip`.
Measured 2026-07-30 while the pin was in place: 2.9.1 and 2.9.4 both give `Success` on the dry-run
and **agree** on `deno fmt --check` (19 files), so formatting is not version-sensitive between them.

⚠️ **`deno.json` declares NO Deno floor**, so nothing in this project validates a minimum supported
version. A release can silently start requiring a newer Deno than a consumer has, and the first
signal would be a user report.

The full green pre-publish checklist (run before each release):

```bash
deno publish --dry-run --allow-dirty   # THE gate: type-check + slow-types + package — must pass
deno doc --lint <all 16 exports>       # clean — necessary but NOT sufficient, see the note above
deno doc --json <all 16 exports> | …   # the REAL coverage check — expect 100/100, 0 missing modules
deno lint main.ts src/                 # clean (21 files)
deno fmt  --check main.ts src/         # clean as of 2026-07-30 — kept stable by .gitattributes
                                       # (*.ts text eol=lf); src/wasm/ is fmt-excluded. NEVER run
                                       # bare `deno fmt`. See design-decisions.md.
deno run -A tests/wasi_tests.ts        # 336/336 as of 2026-06-23 (+18j..18q dynrt runtime/any; +18r..18z GC track P1-P5b + polish + hybrid allocator COMPLETE: auto-grow / free-list / registry / mark / shadow-stack / collect / payloads+auto-collect (bounded memory); +54..61 async). HARDENED 2026-06-07: diffs run-ts vs run-wasm OUTPUT, not just exit codes. No open bugs; 6 tests legitimately diverge and carry `// @allow-output-diff`. A test FAILS on `output-mismatch` unless it opts out.
deno run -A tests/bindgen_tests.ts     # 119/119
deno run -A tests/jstyper_tests.ts     # 73/73
```

Publish flow: **`deno task bump`** (`scripts/bump.ts`; patch default, or `bump minor`/`major`)
raises the `deno.json` version and propagates it to `package.json` + `src/utils.ts` — JSR rejects
re-publishing the same version (`1.6.2` was the last published; `bump` took it to `1.6.3`). Then
`deno task publish` → `scripts/publish.ts` re-syncs the version, commits `bump version to vX.Y.Z`,
tags it, and pushes; the tag triggers `publish.yml`.

## Runner does OUTPUT comparison (hardened 2026-06-07)

`wasi_tests.ts` runs each standard test as: compile → run-ts (native TS via `wasmtk run x.ts`) →
run-wasm (`wasmtk run x.wasm`) → **compare the two outputs**. It captures both stdouts and fails the
test with `output-mismatch` if they differ. BEFORE this, the runner only checked per-step **exit
codes**, so a test that compiled and ran (exit 0) "passed" even when the WASM output was wrong —
this masked dozens of real codegen bugs (see compiler-bugs.md "Runner-hardening audit"). **Lesson:**
a green suite no longer requires manual output-verification, but historically it did — don't trust
an old "NNN/NNN PASS" claim to mean correct output.

Opt-out marker `// @allow-output-diff[: reason]` (in the first 10 lines) skips the output comparison
for tests whose wasic semantics _legitimately_ differ from native TS — currently float-formatting
precision (`45_random-numbers`, `7a_MathIntrinsics`, `7a_constants`) and zero-sentinel destructuring
defaults (`48_ObjectDestructDefault`, `48_Phase48Combined`). `@test-pipeline` and `@modc-prereq`
tests skip the comparison (they self-check via traps / can't run-ts). Use the marker SPARINGLY —
only for a genuine, documented semantic divergence, never to paper over a bug.

## Test populations in `tests/wasi/wasm_wasi/`

| Population                                                         | Runner                               |
| ------------------------------------------------------------------ | ------------------------------------ |
| wasic phase tests (Phase 1–50 + sub-phases) + 103 bindgen fixtures | `wasi_tests.ts` / `bindgen_tests.ts` |
| Go-by-Example tests (imported)                                     | `wasi_tests.ts`                      |
| jstyper unit tests                                                 | `jstyper_tests.ts`                   |

**Not auto-run:** `tests/go_fixtures/hello.go` — the Go producer (`run` / `modc --lang=go`) fixture.
Excluded from the suites because building it needs the TinyGo/Go toolchain (not assumed on every
machine/CI). The **Zig and Rust producers** (`--lang=zig` / `--lang=rust`) are likewise not
auto-tested — they need the `zig` toolchain / `rsxtk` + `wasm32-wasip1`. Both were verified manually
end-to-end (2026-06-07): Zig `init`→`run`(PASS)/`modc`→`mod add 2 3`→5; Rust `init`→`run`("Hello
from rsxtk!")/`build`→`.wasm`/`add`/`list`/`clean`. Manual verify command is in the file header.

## Conventions

- **File naming:** `NN_Label.ext` (phase number first) so listings sort by phase.
- **Stress-test batches (owner workflow, 2026-07-28).** The owner supplies hand-written stress
  programs to probe a phase for latent bugs. Each lands in `tests/wasi/wasm_wasi/` as
  `NN_DescriptiveLabel.ts`, where `NN` is the phase whose feature is under test (pick the phase that
  owns the core mechanic — e.g. a nullable-return test crossing tuples and `??` is Phase 24, because
  nullable returns are the mechanic). Run the batch with the phase filter (`"^25_"`) first. **Escalate
  to the FULL suite only if the batch forced a `src/` fix** — a fix in shared codegen regresses other
  phases (the 2026-07-28 batch regressed two Phase 24/25 tests mid-fix). **If every test passed as
  written, the phase filter ends the batch** (see the corollary under "Which suites to run" above).
  Confirm any newly-failing adjacent suite against a clean tree
  (`git stash` + reinstall + re-run) before attributing it to the batch. Record the batch as ONE
  unit in `compiler-bugs.md`; update the counts here; and add **per-phase** rows to the README table
  — see the placement/labelling directive at the top of [roadmap.md](roadmap.md).
- **Generated artifacts are NOT tracked (2026-07-01):** the `.wasm`/`.wat`/`.wit` in
  `tests/wasi/wasm_wasi/` that pair 1:1 with a `.ts` are BUILD OUTPUTS (the runner regenerates them
  from the `.ts` on every run) and are `.gitignore`d — committing them had pushed the folder past
  GitHub's **1,000-file-per-directory** display cap (was 1,380 files → now ~402 tracked) and bloated
  the repo/pack (the `geometric-repack` errors). **When adding a NEW input fixture** (a `.wasm`/
  `.wat`/`.wit` with NO same-named `.ts` — e.g. an imported module like `18_symbol_table.wasm`, a
  `.wat`-runner source, or a prebuilt rust/zig output), add a `!tests/wasi/wasm_wasi/<name>`
  un-ignore line to `.gitignore`, else it won't be tracked and the test breaks on a fresh clone. A
  fresh clone has only the `.ts` + ~21 fixtures; the first suite run regenerates all outputs.
- **Extended 2026-07-02 to the bundle / bindgen / dync outputs:** `tests/wasi/wasm_wasi_bundle/**`,
  `tests/module/bindgen_fixtures/*`, `tests/wasi/wasm_wasi_dync/*` `.wasm`/`.wat`/`.wit` are ALSO
  `.gitignore`d — the `@test-pipeline` (modc→wasic→run steps), `bindgen_tests.ts`
  (`modc fixture -n …`), and the dync gate recompile them from their `.ts` every run. **Verified by
  clean regeneration** (deleted all 214, re-ran the suites → 375/375 + bindgen 131/131) so nothing
  among them was a silent INPUT. INPUT fixtures that tests READ are deliberately still tracked:
  `tests/module/wasm_mod/**` (mod_tests iterates the prebuilt `.wasm`), `tests/module/wasm_wast/**`
  (hand-authored WAT / Art-of-WebAssembly samples), and `tests/hybrid/hybrid_fixtures/**` (no test
  regenerates them). **These outputs double as cross-runtime validation fixtures** — always
  regenerate with a green suite before validating another wasm runtime against them, so you compare
  against current-compiler output (a stale committed binary would be a false positive). The
  canonical math fixtures (`src/wasm/mathlib.wasm` + `.wat`, `caps_bytes.ts`) stay tracked under
  `src/` and are the primary CR-math validation targets.
- **`@expect-fail: compile|run-ts|run-wasm`** in the first 10 lines → failure counts as PASS.
- **`@test-pipeline` + `@step <subcmd> <args…>`** (comment header) → run custom wasmtk sub-commands
  instead of the standard compile/run-ts/run-wasm flow; paths resolve relative to the test file.
  Used by the capability pipelines and Phase 18 bundle tests.
- **Self-checking driver pattern** (capability fixtures): a `guard: i32[] = [0]` + `check(cond)`
  that does `guard[5000000]` (OOB read → trap → nonzero exit) on failure. A passing `run` proves
  semantics. Do NOT use `throw` to fail a pipeline (wasic uncaught throw exits 0).
- **Integer division** in tests: `(a / b) | 0` to match TS float-`number` semantics (Binaryen -Oz
  elides the `| 0` no-op).

## Single-test quick loop

```bash
wasmtk wasic tests/wasi/wasm_wasi/MyTest.ts && wasmtk run tests/wasi/wasm_wasi/MyTest.wasm
# For a capability: wasmtk modc <lib> ; wasmtk wasic <driver> ; wasmtk run <driver>.wasm
```
