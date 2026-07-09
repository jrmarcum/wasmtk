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
```

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

## Current pass counts (2026-07-08, wabt-ts 1.3.5 + binaryen-ts 1.4.0)

| Suite                                                                                           | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/wasi/wasm_wasi` (full, HARDENED output-diff runner)                                      | **375 / 375** (+`67_TrigCorrectlyRounded` 2026-07-01 — mathlib `sin`/`cos`/`tan` are now IEEE-754 **correctly-rounded** double-double (validated bit-for-bit vs a BigInt CR oracle through the full pipeline); the 23 printed values are correctly-rounded doubles that for these args also equal V8's `Math.*`, so wasm==ts. See compiler-bugs.md issue 5 + design-decisions.md. +`66_Dragon4Formatting` 2026-07-01 — report issue 6: `$__f64_to_str` rewritten as pure Dragon4 (Burger-Dybvig), 100% byte-exact f64→string vs V8 incl. subnormals/max/scientific + fixes the old formatter's TRAP on `                                                                                                                                                                                                                                                                                                                                                                                 |
| `bindgen_tests.ts`                                                                              | **142 / 142** (functions-as-`any` both directions: core→host `testIntegrationFnAny` `getDoubler()(21)=42` + proxy-robustness assertions; **#14 Phase 2 host→core `testIntegrationHostFn`** — `applyTwice(n=>n+1,10)=12` / `combine((a,b)=>a*b,6,7)=42` via the `env.__host_call` import + host-fn table; **+4 SPEC §10 loader assertions 2026-07-08** — the generated loader always ships a minimal WASI-P1 shim + calls `_initialize`, so a WASI-importing library (TinyGo reactor, or a `modc` lib that `console.log`s) instantiates; **+7 kebab-round-trip assertions 2026-07-08** — `testIntegrationKebab` (fixture `kebabcase_50`, exports `readID`/`toHTML`) proves the generated loader's `_ex()` resolver binds capital-heavy exports the lossy WIT kebab↔camel round-trip can't reconstruct (fails pre-fix with `exp["readId"] is not a function`). See `go_bindgen_tests.ts` + polyglot-producers.md § "Go string/aggregate bindgen" + compiler-bugs.md § "Code-audit sweep".) |
| `go_bindgen_tests.ts` (TinyGo-gated; skips if absent)                                           | **7 / 7** — Go→bindgen integration: `wasmtk modc --lang=go tests/go_fixtures/strlib` → `wasmtk bindgen strlib.wit` → drive the generated loader: `greet`/`strLen` round-trip incl. UTF-8. Proves TinyGo string libraries are consumable by bindgen over the **canonical** ABI unchanged (Go strings are UTF-8 (ptr,len); a `//go:linkname cabi_realloc` wrapper + `cabi_post_<name>` matches wasic's shape).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `go_asyncify_tests.ts` (new 2026-07-08; TinyGo-gated)                                           | **3 / 3** — GOROUTINE Go with NO external binaryen: `WASMTK_GO_BINARYEN_ASYNCIFY=1 wasmtk run tests/go_fixtures/goroutines/main.go` (a `go worker(...)` + buffered-channel worker-pool) builds `-scheduler=asyncify` + passthrough shim, then `binaryenAsyncify` (binaryen-ts ≥ 1.4.1 Asyncify import-mode + `-Oz`) resolves the in-wasm `asyncify.*` imports → prints `sum: 30`. Asserts the in-house asyncify path was used (report label) + correct output.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `jstyper_tests.ts`                                                                              | **73 / 73**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `hybrid_tests.ts` (new 2026-07-08)                                                              | **8 / 8** — unit tests for the context-aware `hybrid` scanners: `findCloseBrace`/`rewriteWasmCalls` must not be fooled by a `}`/quote/regex inside a string/comment/regex, must rewrite a routed call inside a template `${…}` interpolation, must NOT rewrite an object method shorthand, and must inject `loadModule` after a MULTI-LINE import. See design-decisions.md § "hybrid call-rewriting … MUST be context-aware".                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `dync_conformance_tests.ts` (#14 2h Javy-parity gate)                                           | **3 / 3** — for each fixture in `tests/wasi/wasm_wasi_dync/` (demo1/2/3), `wasmtk dync`→`.wasm`→`run` stdout must byte-match a `deno run` JS baseline. Proves the OWN dynamic runtime is a drop-in `javyc` replacement (no Javy/QuickJS). Caught the `Math.min`/`max` 2-arg bug (now variadic). Out of scope: interactive `prompt` + ESM import/export of other modules.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
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
