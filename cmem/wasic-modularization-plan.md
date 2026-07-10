# wasic modularization plan

> **Plan of record (2026-07-09).** Decompose the `src/wasic.ts` monolith — **19,709 lines; one
> `WasicTranspiler` class with 231 methods over 134 shared mutable fields** (a classic god-object) —
> into logical sub-modules for maintainability, easier additions, and refactoring for execution
> speed. **Sequenced BEFORE wabt-ts Phase 8 (`wasm2ts`, the wasm→TypeScript transpiler)**, which is
> explicitly *"deferred pending wasmtk QA/QC"* — this modularization IS that QA/QC.
>
> Status as work lands: check off phases here; keep [roadmap.md](roadmap.md) and
> [architecture.md](architecture.md) in sync when the file layout actually changes.

## Why now — sequencing before `wasm2ts`

wabt-ts's `wasm2ts` (`src/writer/ts-writer.ts`, wabt-ts `cmem/tasks.md` Phase 8) generates TypeScript
that targets **wasic's supported subset**. Doing wasic's modularization first is the right order:

1. **`wasm2ts` needs a referenceable contract.** Once wasic's type system + feature surface are
   extracted into modules (`types.ts`, `maptype.ts`, the emit layer), the supported subset becomes an
   explicit, importable contract `wasm2ts` can target — and the round-trip (wasm → TS → wasm) can be
   validated against a clean emit layer instead of an 18K black box.
2. **The deferred output-mismatch backlog is hidden by the monolith.** ~14 known-open output-mismatch
   edge cases + 4 dynrt-worked-around gaps were deferred to a "scoped cleanup" precisely because they
   are hard to fix inside 18K lines. Clean seams + a golden-WAT harness make them tractable.
3. **Refactoring after `wasm2ts` exists is harder** — you'd have two consumers of wasic's internals.

## Guiding discipline (applies to EVERY phase)

- **Output-preserving.** No phase may change emitted WAT **except** the intentional corrections in
  Phase 0. Validate with the **golden-WAT harness** (byte diff of the emitted `.wat` for every
  fixture), NOT just exit codes — the project's standing "OUTPUT-diff, not just exit codes" rule.
- **One concern per commit.** Each commit gated on: full suite green (wasi 375/375 + `bindgen` +
  `jstyper` + `go_*`) **AND** zero golden-WAT diff (in Phase 0: only the intended correction).
- **Reversible at any point.** A move that fails the golden diff is reverted, not patched forward.

---

## Phase 0 — "look for code issues" audit + fix, run to ZERO (HARD GATE)

Run the binding **"look for code issues"** contract (CLAUDE.md / `cmem/INDEX.md`) scoped to
`src/wasic.ts` + `src/console_log.ts` **before any restructuring**, so we modularize clean, correct
code — not a monolith of accreted workarounds. Establish the safety net here too, since the audit
fixes deliberately change output and need validation.

> **This is a HARD GATE and an ITERATIVE loop — not a single pass.** Owner directive (2026-07-09):
> **run "look for code issues" repeatedly — audit → fix → re-audit — until a full pass surfaces
> NOTHING new. No later phase (1, 2, 3, or any other work) begins until an entire audit pass comes
> back clean.** Each round: run the fan-out audit, fix the safe findings (validated by golden-WAT
> diff + green suite), log the unsafe ones with reasons, then audit AGAIN. Convergence = one complete
> pass with zero new actionable findings. Record each round's outcome (findings fixed / deferred)
> below or in `cmem/compiler-bugs.md` so the loop's progress is auditable.

- **0a — Golden-WAT harness (build first).** Emit `.wat` for every test fixture
  (`tests/wasm_wasi/**`, bindgen/jstyper/go fixtures) via the wasic/modc path and store the exact
  output as golden files (in the scratchpad or a git-ignored `tests/.golden/`). A small runner diffs
  fresh output against golden and reports the first byte-level divergence per file. This is the tool
  every later step is gated on.
- **0b — Comprehensive audit** (fan out parallel read-only investigators per category over the large
  files; report `file:line` + severity):
  - **Workarounds / temporary hacks** — still-needed vs stale (e.g. `skipBinaryenOpt`-style relics,
    version-gated shims now on newer backends, `quietEmit` probes).
  - **Dead code** — unused methods / fields / helpers / duplicate branches / orphaned exports. With
    **231 methods + 134 fields**, this is a large surface; grep-verify each candidate before removal.
  - **Bugs** — silently-wrong codegen, inverted logic, type-inference gaps, scanner off-by-ones.
    **Known candidates to pull from the backlog:** the ~14 deferred output-mismatch bugs
    (`cmem/compiler-bugs.md` "14 KNOWN-OPEN output-mismatch bugs") + the 4 dynrt-worked-around wasic
    gaps + the single-physical-line brace `if {…}` edge (`cmem/compiler-bugs.md`).
  - **Fall-throughs** — the worst mode: unhandled input emitting a comment-stub + bare `0`/`""`
    instead of erroring. Convert silent-wrong → a hard `diagnostics` abort; guard speculative probes
    with `quietEmit`.
- **0c — Fix the safe ones.** Each fix validated by the golden-WAT diff showing **only** the intended
  correction, and the full suite staying green. Anything risky or ambiguous is logged in
  `cmem/compiler-bugs.md` with a reason, not force-fixed.
- **0d — Re-freeze the golden baseline.** After the fixes, regenerate the golden files. This
  now-correct, byte-exact reference is **frozen** and guards Phases 1–3 (which must reproduce it
  exactly).

**Deliverable (reached only after the loop CONVERGES — a full audit pass with zero new findings):**
clean, correct `wasic` + a frozen byte-exact golden-WAT reference + an updated `cmem/compiler-bugs.md`
(fixed items closed, any residual openly documented). Only then does restructuring (Phase 1) begin.

---

## Phase 1 — Extract the stateless code (big, safe wins; zero `this`)

Pure functions / constants with no `WasicTranspiler` state — moved as ordinary modules. Lowest risk.

- `src/wasic/types.ts` — the interfaces (`FuncParam`, `StructField`, `StructDef`, `DiscUnionDef`,
  `ClassDef`, `FuncDef`, `WasicResult`, `WatType`, …).
- `src/wasic/wat-sexpr.ts` — `tokenizeWat` / `parseWatNodes` / `serializeWat` / `watNodeToValue` /
  `fixTerminalFallthru` (already near-standalone).
- `src/wasic/wit.ts` — `watTypeToWit` / `toKebabCase` / `generateWit` support (Phase 41).
- `src/wasic/runtime/` — the WAT template generators (mostly pure string builders, a large clean
  chunk): `mem.ts` (`$__malloc` / `cabi_realloc`), `strings.ts` (`getStringHelperWat` /
  `…OpHelperWat` / `…ExtHelperWat`), `arrays.ts` (dynarray helpers), `typed-arrays.ts`
  (`emitTypedArrHelpers`), `math.ts` (`emitMathHelpers`), `numparse.ts` (`emitNumParserHelpers`),
  `promise.ts` (`getPromiseRuntimeWat`), `exceptions.ts`.
- `src/wasic/maptype.ts` — `mapType` + pure type helpers (take `structDefs`/enum maps as args).

## Phase 2 — Relocate the stateful clusters (near-zero-risk pattern)

134 shared fields mean the stateful methods can't be pure functions without a big rewrite. Use the
**`this`-parameter + prototype-wiring** pattern so the moved code is byte-identical internally:

```ts
// src/wasic/emit/expr.ts
export function emitExpr(this: WasicTranspiler, expr: string, /* … */): string { /* body unchanged: this.field stays this.field */ }

// src/wasic.ts
import { emitExpr } from "./wasic/emit/expr.ts";
WasicTranspiler.prototype.emitExpr = emitExpr;
```

Because every `this.field` / `this.method()` inside the moved body is **unchanged**, the emitted WAT
cannot change from the move itself — the golden diff proves it per commit. Split by concern:

- `src/wasic/prepass.ts` — `expand*` (generics, conditional/utility/fn-utility types, namespaces,
  param destructuring, array-from/of, class-instance array literals).
- `src/wasic/parse/` — `parseEnums` / `parseStructs` / `parseClasses` / `parseDiscriminatedUnions` /
  `parseIntersectionTypes` / `parseNamedFuncTypeAliases` / `parseFunctions` / `parseTopLevel` /
  `parseModuleGlobals` / `parseParams` / `parseArrowFunctions` / `parseExternalDeclarations`.
- `src/wasic/emit/` — the biggest group (~40 methods), sub-split: `expr.ts`, `statement.ts`,
  `function.ts`, `block.ts`, `string.ts`, `array.ts`, `struct.ts`, `class.ts`, `imports.ts`,
  `helpers.ts` (the `emitHelpers` orchestrator).
- `src/wasic/infer.ts` — `inferInitType` / `inferExprType` / `inferChainElemType`.

## Phase 3 — Thin facade

`src/wasic.ts` becomes the entry: the `WasicTranspiler` class (state fields + constructor), the
`transpile()` / `toWat()` / `watToOptimisedWasm()` orchestration, the prototype wiring block, and the
public `compileWasiTs` / `compileLibTs` / `compileWat` functions. Target: a few hundred lines.

## Optional later (not required for the wasm2ts unblock)

- Migrate the 134 fields to an explicit `TranspilerCtx` object (fully idiomatic; converts the
  `this`-param functions to `ctx`-param — mechanical once the seams exist).
- Split `src/console_log.ts` (3,800 lines) the same way (segment/number-to-string emission + the
  singleton allocator callbacks).

---

## Module map (grounded in the 231 methods / 134 fields)

| New module                     | Holds                                                                 | `this`-dep |
| ------------------------------ | --------------------------------------------------------------------- | ---------- |
| `src/wasic.ts` (facade)        | class + fields + `transpile`/`toWat`/pipeline + prototype wiring       | —          |
| `src/wasic/types.ts`           | all interfaces + `WatType`                                             | none       |
| `src/wasic/wat-sexpr.ts`       | s-expr tokenize/parse/serialize + `fixTerminalFallthru`                | none       |
| `src/wasic/wit.ts`             | WIT generation                                                        | none       |
| `src/wasic/maptype.ts`         | `mapType` + pure type helpers                                         | args       |
| `src/wasic/runtime/*.ts`       | WAT template generators (mem/strings/arrays/typed-arrays/math/…)       | none/flags |
| `src/wasic/prepass.ts`         | `expand*` source→source passes                                        | `this`     |
| `src/wasic/parse/*.ts`         | `parse*` passes                                                       | `this`     |
| `src/wasic/emit/*.ts`          | `emit*` (expr/statement/function/string/array/struct/class/imports)   | `this`     |
| `src/wasic/infer.ts`           | `infer*`                                                              | `this`     |

## Success criteria

- `src/wasic.ts` reduced from ~19.7K lines to a few-hundred-line facade; no module > ~2–3K lines.
- Full suite green throughout (wasi 375/375, bindgen, jstyper, go), **zero golden-WAT diff** across
  Phases 1–3.
- `deno doc --lint` clean on any new exported surface (hold the JSR score; new files get an
  `@module` tag — see the wast.ts lesson in [next-work.md](next-work.md)).
- The extracted `types.ts` / `maptype.ts` / emit layer are importable as the "supported subset"
  contract that wabt-ts `wasm2ts` builds against.
