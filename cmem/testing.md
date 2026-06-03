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

## Current pass counts (2026-06-02, wabt-ts 1.3.2 + binaryen-ts 1.3.3)

| Suite | Result |
| --- | --- |
| `tests/wasm_wasi` (full) | **278 / 278** (the 7 long-standing failures are now fixed — see compiler-bugs.md) |
| `bindgen_tests.ts` | **103 / 103** |
| `jstyper_tests.ts` | **73 / 73** |
| Capability pipelines `18c`–`18g` (Set/Map/Date/JSON/RegExp) + `18h` (virtual `wasmtk:` imports) | **6 / 6** |

The 7 previously-failing tests were fixed 2026-06-02: `5e_MixedSignatures`, `19_NestedDiscriminantUnions`,
`19_VariantMaximumMemoryAlignment` (value-fallthru codegen, fixed in wasic); `38_MathExpLog`,
`38_MathHyperbolic`, `38_MathTrig`, `38_Phase38Combined` (hex-float literals encoded as 0, fixed in
wabt-ts 1.3.1). See compiler-bugs.md.

Historical baseline under npm:wabt+npm:binaryen was 446/446 (2026-05-25); the per-phase historical
counts in README are a record of when each phase first went green, not a live invariant.

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
