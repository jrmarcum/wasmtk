# Testing

## Running the suites

```bash
# Full wasm_wasi suite (phase tests + Go-by-Example + capability pipelines)
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts

# Optional 2nd arg = regex filter on file basenames (scope to one phase/feature):
deno run ... tests/wasi_tests.ts tests/wasm_wasi "^15_"       # phase 15
deno run ... tests/wasi_tests.ts tests/wasm_wasi "^18[c-g]_"  # all 5 capability pipelines

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
invocation, which stalls the whole test run. (Regression history: a documented reinstall command here
once omitted `--allow-ffi`; fixed 2026-06-08 by deferring to `deno task install`.)

## Current pass counts (2026-06-12, wabt-ts 1.3.2 + binaryen-ts 1.3.5)

| Suite | Result |
| --- | --- |
| `tests/wasm_wasi` (full, HARDENED output-diff runner) | **315 / 315** (+`54_AsyncBasic` + `55_AsyncThen` + `56_AsyncReject` + `57_AsyncCatch` + `58_AsyncPromiseVar` + `59_AsyncClosureCb` 2026-06-15 — #13 async sub-phases 13.1a (async/await + Promise.resolve) + 13.2 (.then + microtask queue) + 13.3a (Promise.reject + rejection→exception) + 13.3b (.catch/.finally rejection reactions + .then(onF,onR), dual-path trampoline) + 13.1b (promise-var inner-type tracking + capturing-closure callbacks via env-bearing reaction record); see async-design.md; +`53_NumberParse` + `53_InterfaceInheritance` 2026-06-15 — Phase 53; +`27_ConsoleLogStringCompare` 2026-06-12 — console.log string/numeric comparison fixes (findTopLevelOp paren-tail, string ===/!== resolver, != inversion, string .length operand); +`15_ElseChainForms` — brace-less/single-line-braced else-chain drop bug; see compiler-bugs.md. Earlier: 6 Phase 52 tests added 2026-06-11; the 14 output-mismatch bugs the 2026-06-07 runner-hardening surfaced are ALL FIXED 2026-06-08; 6 tests carry `// @allow-output-diff` for documented float-precision / zero-sentinel divergences, incl. `1_values`) |
| `bindgen_tests.ts` | **104 / 104** (+1 `cabi_post` assertion, 2026-06-15 ABI return-side forward-alignment) |
| `jstyper_tests.ts` | **73 / 73** |
| Capability pipelines `18c`–`18g` (Set/Map/Date/JSON/RegExp) + `18h` (virtual `wasmtk:` imports) | **6 / 6** |

The 7 previously-failing tests were fixed 2026-06-02: `5e_MixedSignatures`, `19_NestedDiscriminantUnions`,
`19_VariantMaximumMemoryAlignment` (value-fallthru codegen, fixed in wasic); `38_MathExpLog`,
`38_MathHyperbolic`, `38_MathTrig`, `38_Phase38Combined` (hex-float literals encoded as 0, fixed in
wabt-ts 1.3.1). See compiler-bugs.md.

Historical baseline under npm:wabt+npm:binaryen was 446/446 (2026-05-25); the per-phase historical
counts in README are a record of when each phase first went green, not a live invariant.

## CI / pre-publish gate

The only GitHub workflow is `.github/workflows/publish.yml`: it fires on a `v*` tag, runs a
**"Check OIDC availability"** diagnostic step (added 2026-06-15 — surfaces a gated GitHub OIDC token
in the run log) and then **`deno publish`** (with OIDC provenance), then creates a `release/<tag>`
branch + GitHub release. So the *enforced* CI gate is exactly what `deno publish` validates:
**type-check of all 15 `deno.json` exports + JSR "slow-types" check + package validation**. `deno fmt`
/ `deno lint` / `deno doc --lint` / the test suites are **not** gated by CI — but `deno doc --lint`
must be kept clean to hold the JSR doc-coverage score (see design-decisions.md), and provenance
requires the OIDC token to actually reach the runner (was environmentally gated through v1.6.5;
v1.7.0 published 2026-06-15 with `hasProvenance: true`, JSR score 100).

The full green pre-publish checklist (run before each release):

```bash
deno publish --dry-run --allow-dirty   # THE gate: type-check + slow-types + package — must pass
deno doc --lint <all 15 exports>       # clean — guards the JSR doc-coverage score (≥0.80 symbols)
deno lint main.ts src/                 # clean (18 files)
deno fmt  --check main.ts src/         # clean as of 2026-06-02 (see design-decisions.md)
deno run -A tests/wasi_tests.ts        # 315/315 as of 2026-06-15 (+54..59 async; #13 13.1a+13.2+13.3a+13.3b+13.1b). HARDENED 2026-06-07: diffs run-ts vs run-wasm OUTPUT, not just exit codes. No open bugs; 6 tests legitimately diverge and carry `// @allow-output-diff`. A test FAILS on `output-mismatch` unless it opts out.
deno run -A tests/bindgen_tests.ts     # 104/104
deno run -A tests/jstyper_tests.ts     # 73/73
```

Publish flow: **`deno task bump`** (`scripts/bump.ts`; patch default, or `bump minor`/`major`) raises
the `deno.json` version and propagates it to `package.json` + `src/utils.ts` — JSR rejects
re-publishing the same version (`1.6.2` was the last published; `bump` took it to `1.6.3`). Then
`deno task publish` → `scripts/publish.ts` re-syncs the version, commits `bump version to vX.Y.Z`,
tags it, and pushes; the tag triggers `publish.yml`.

## Runner does OUTPUT comparison (hardened 2026-06-07)

`wasi_tests.ts` runs each standard test as: compile → run-ts (native TS via `wasmtk run x.ts`) →
run-wasm (`wasmtk run x.wasm`) → **compare the two outputs**. It captures both stdouts and fails the
test with `output-mismatch` if they differ. BEFORE this, the runner only checked per-step **exit
codes**, so a test that compiled and ran (exit 0) "passed" even when the WASM output was wrong — this
masked dozens of real codegen bugs (see compiler-bugs.md "Runner-hardening audit"). **Lesson:** a
green suite no longer requires manual output-verification, but historically it did — don't trust an
old "NNN/NNN PASS" claim to mean correct output.

Opt-out marker `// @allow-output-diff[: reason]` (in the first 10 lines) skips the output comparison
for tests whose wasic semantics *legitimately* differ from native TS — currently float-formatting
precision (`45_random-numbers`, `7a_MathIntrinsics`, `7a_constants`) and zero-sentinel destructuring
defaults (`48_ObjectDestructDefault`, `48_Phase48Combined`). `@test-pipeline` and `@modc-prereq`
tests skip the comparison (they self-check via traps / can't run-ts). Use the marker SPARINGLY — only
for a genuine, documented semantic divergence, never to paper over a bug.

## Test populations in `tests/wasm_wasi/`

| Population | Runner |
| --- | --- |
| wasic phase tests (Phase 1–50 + sub-phases) + 103 bindgen fixtures | `wasi_tests.ts` / `bindgen_tests.ts` |
| Go-by-Example tests (imported) | `wasi_tests.ts` |
| jstyper unit tests | `jstyper_tests.ts` |

**Not auto-run:** `tests/go_fixtures/hello.go` — the Go producer (`run` / `modc --lang=go`) fixture.
Excluded from the suites because building it needs the TinyGo/Go toolchain (not assumed on every machine/CI).
The **Zig and Rust producers** (`--lang=zig` / `--lang=rust`) are likewise not auto-tested — they need
the `zig` toolchain / `rsxtk` + `wasm32-wasip1`. Both were verified manually end-to-end (2026-06-07):
Zig `init`→`run`(PASS)/`modc`→`mod add 2 3`→5; Rust `init`→`run`("Hello from rsxtk!")/`build`→`.wasm`/`add`/`list`/`clean`.
Manual verify command is in the file header.

## Conventions

- **File naming:** `NN_Label.ext` (phase number first) so listings sort by phase.
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
wasmtk wasic tests/wasm_wasi/MyTest.ts && wasmtk run tests/wasm_wasi/MyTest.wasm
# For a capability: wasmtk modc <lib> ; wasmtk wasic <driver> ; wasmtk run <driver>.wasm
```
