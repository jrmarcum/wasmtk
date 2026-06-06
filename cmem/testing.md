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
After editing anything in `src/` or `deno.json` you MUST reinstall before the suite reflects it:

```bash
deno install -g --allow-read --allow-write --allow-run --allow-env --allow-net \
  --config deno.json --force -n wasmtk main.ts
```

## Current pass counts (2026-06-03, wabt-ts 1.3.2 + binaryen-ts 1.3.3)

| Suite | Result |
| --- | --- |
| `tests/wasm_wasi` (full) | **286 / 286** (Phase 51 2026-06-05: 4 `instanceof` tests + 3 class-gap tests `51_ModuleLevelClassInstance`/`51_ClassInstanceArrayLiteral`/`51_SingleLineClassBody`; single-line brace `if` form fixed 2026-06-03 added `48_SingleLineBraceIf`; see compiler-bugs.md) |
| `bindgen_tests.ts` | **103 / 103** |
| `jstyper_tests.ts` | **73 / 73** |
| Capability pipelines `18c`–`18g` (Set/Map/Date/JSON/RegExp) + `18h` (virtual `wasmtk:` imports) | **6 / 6** |

The 7 previously-failing tests were fixed 2026-06-02: `5e_MixedSignatures`, `19_NestedDiscriminantUnions`,
`19_VariantMaximumMemoryAlignment` (value-fallthru codegen, fixed in wasic); `38_MathExpLog`,
`38_MathHyperbolic`, `38_MathTrig`, `38_Phase38Combined` (hex-float literals encoded as 0, fixed in
wabt-ts 1.3.1). See compiler-bugs.md.

Historical baseline under npm:wabt+npm:binaryen was 446/446 (2026-05-25); the per-phase historical
counts in README are a record of when each phase first went green, not a live invariant.

## CI / pre-publish gate

The only GitHub workflow is `.github/workflows/publish.yml`: it fires on a `v*` tag and runs
**`deno publish`** (with OIDC provenance), then creates a `release/<tag>` branch + GitHub release.
So the *enforced* CI gate is exactly what `deno publish` validates: **type-check of all 14
`deno.json` exports + JSR "slow-types" check + package validation**. `deno fmt` / `deno lint` /
the test suites are **not** gated by CI.

The full green pre-publish checklist actually run (2026-06-02):

```bash
deno publish --dry-run --allow-dirty   # THE gate: type-check + slow-types + package — must pass
deno lint main.ts src/                 # clean (18 files)
deno fmt  --check main.ts src/         # clean as of 2026-06-02 (see design-decisions.md)
deno run -A tests/wasi_tests.ts        # 286/286
deno run -A tests/bindgen_tests.ts     # 103/103
deno run -A tests/jstyper_tests.ts     # 73/73
```

Publish flow: **`deno task bump`** (`scripts/bump.ts`; patch default, or `bump minor`/`major`) raises
the `deno.json` version and propagates it to `package.json` + `src/utils.ts` — JSR rejects
re-publishing the same version (`1.6.2` was the last published; `bump` took it to `1.6.3`). Then
`deno task publish` → `scripts/publish.ts` re-syncs the version, commits `bump version to vX.Y.Z`,
tags it, and pushes; the tag triggers `publish.yml`.

## Test populations in `tests/wasm_wasi/`

| Population | Runner |
| --- | --- |
| wasic phase tests (Phase 1–50 + sub-phases) + 103 bindgen fixtures | `wasi_tests.ts` / `bindgen_tests.ts` |
| Go-by-Example tests (imported) | `wasi_tests.ts` |
| jstyper unit tests | `jstyper_tests.ts` |

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
