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
| `wast_tests` | `src/wast.ts` → `wabt` only | **any `wabt-ts` / `binaryen-ts` backend bump**, `src/wast.ts` |
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

## Current pass counts (2026-07-28, wabt-ts 1.3.5 + binaryen-ts 1.4.3)

> ### EVERY suite in the repo is green (2026-07-28) — full roster, all measured this session
>
> | Suite | Result |
> | --- | --- |
> | `tests/wasi/wasm_wasi` (`wasi_tests.ts`) | **410 / 410** — 407 + the Phase 33 intersection batch (3 owner stress tests), 2026-07-30. All three passed as written; the phase filter `"^33_"` was 7/7 |
> | `wast_tests.ts` | **41 files, 12444 passed, 0 failed**, 3466 skipped — ALL CLEAN |
> | `bindgen_tests.ts` | 142, 0 failed |
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
> build / asyncify write racing the OS file lock, NOT assertion failures. Run alone it is 12/12.
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

The full green pre-publish checklist (run before each release):

```bash
deno publish --dry-run --allow-dirty   # THE gate: type-check + slow-types + package — must pass
deno doc --lint <all 15 exports>       # clean — guards the JSR doc-coverage score (≥0.80 symbols)
deno lint main.ts src/                 # clean (18 files)
deno fmt  --check main.ts src/         # clean as of 2026-06-02 (see design-decisions.md)
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
