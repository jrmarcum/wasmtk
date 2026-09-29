# wasic modularization plan

> **Plan of record (2026-07-09).** Decompose the `src/wasic.ts` monolith — **19,709 lines; one
> `WasicTranspiler` class with 231 methods over 134 shared mutable fields** (a classic god-object) —
> into logical sub-modules for maintainability, easier additions, and refactoring for execution
> speed. **Sequenced BEFORE wabt-ts Phase 8 (`wasm2ts`, the wasm→TypeScript transpiler)**, which is
> explicitly *"deferred pending wasmtk QA/QC"* — this modularization IS that QA/QC.
>
> Status as work lands: check off phases here; keep [roadmap.md](roadmap.md) and
> [architecture.md](architecture.md) in sync when the file layout actually changes.

## 🔒 H12 update (2026-09-28): the seams are the ones a future `ts2wasm` import crosses

Workspace letter H12 / divergence I11 (owner, 2026-09-20): `wasic` becomes binaryang's
**`./ts2wasm`** once it is "sufficiently capable and less buggy", and is then retired from wasmtk.
The bar, set by the owner: (a) this plan complete, (b) every wasic suite green on every engine in
the cross-check gate, (c) **no OPEN silent-wrong compiler entry** in `compiler-bugs.md`, (d)
binaryang's one front end done. **The scope of `ts2wasm` / `wasm2ts` is deliberately NOT written:
the owner opens it. This section designs wasmtk's seams only.** It supersedes the wabt-ts
"Phase 8 `wasm2ts`" framing below: wabt-ts is frozen, merged into binaryang.

**Re-measured 2026-09-28** (a Deno script over `src/wasic.ts`, not the July numbers):

- 20,691 lines. `class WasicTranspiler` is lines 1535–20156, i.e. **18,622 lines, 90%**.
- About 139 methods and 89 fields, by an indentation heuristic that undercounts multi-line
  signatures. The July "231 / 134" came from a different count.
- `console_log.ts` is 4,111 lines.
- **The class is already almost pure.** Everything that touches the host or the backend lives in
  the ~2,000 lines OUTSIDE it: 13 `rt.*` (file/process I/O), 36 `console.*`, 9 wabt, 4 binaryen,
  10 merge and 5 bundler sites. Inside it there was exactly ONE: an undeclared-receiver error that
  called `console.error` + **`rt.exit(1)`**, killing the host process (including `hybrid`/`dync`
  probe compiles). It is now a diagnostic, with regression test `22_UndeclaredReceiverDiagnostic`.
  **The core has 0 host sites.**

### The four layers (every extracted module belongs to exactly one)

| layer | what | today | fate |
| --- | --- | --- | --- |
| **CORE** | TS source text → `{ wat, wit, diagnostics }`. Pure: no file I/O, no process exit, no console, no backend calls | `WasicTranspiler` (prepass / parse / infer / emit / runtime WAT templates), `console_log.ts`'s emission, `varscope.ts` | **the `ts2wasm` seam**: moves as a unit under I11 |
| **FRONT EDGE** | gathers the source: reads imported `.ts`, resolves `wasmtk:<cap>` virtual imports, records `.wasm` imports | `tsbundler.ts` (`bundleImportsEx`), `jstyper.ts` | its OUTPUT must be pure data (source text + `{prefix, bytes, wit}` import descriptors), so the core never needs a file system |
| **BACK EDGE** | WAT → wasm: merge imported modules, post-merge fixups, assemble, `-Oz` | `mergeOneWasmImport` + the fixup regexes, `wasmmerge.ts`, `watToOptimisedWasm`, the mathlib auto-merge | **NOT the core**: H11 #1/#3 moves it onto binaryang's parser/IR. Keeping it out of the core means neither move blocks the other |
| **CLI EDGE** | path-based entry points and printing | `compileWasiTs` / `compileLibTs` / `compileWasi` / `compileWat`, `suggestNextStepOnAbort` | stays in wasmtk (the thin orchestrator in `projects.md`) |

### Rules for Phases 1–3 (in addition to "output-preserving" below)

1. **A core module never imports** `rt.ts`, `utils.ts`, `wasmmerge.ts`, `tsbundler.ts`, `wabt`,
   `binaryen-backend` or `@std/path`, and never calls `console.*` or exits. Errors are
   `diagnostics`. This is checkable by grep, so it becomes a gate (see below), not a convention.
2. **The core's entry is string-in / data-out.** Phase 3's facade exposes something like
   `transpile(source, options) → { wat, wit, diagnostics, warnings }`. The path-based functions
   become CLI-edge wrappers over it. The exact signature is NOT fixed here: that is `ts2wasm` scope.
3. **Back-edge code is extracted to its own modules (`src/wasic/link/…` or similar), never into the
   core tree**, even where it is regex-over-WAT that H11 will retire.
4. **`compiler-bugs.md` classifies every entry** (silent-wrong / loud, status, scope) with a tally
   at the top. The open-silent-wrong-in-the-compiler count is bar (c). A new entry without a class
   line is incomplete.

### The seam gate

A structural check that no core code touches the host. Today that means the `WasicTranspiler` body.
After Phase 1, it means every module under the core tree. `tests/wasic_seam_tests.ts` runs it
(added 2026-09-28). It must pass at every commit of Phases 1–3, next to the golden-WAT diff.

### Status (2026-09-28)

- ✅ Measurement, the one core seam fix, the seam gate.
- ✅ Bug classification: every `compiler-bugs.md` entry has a class line and the tally is at the
  top. **Bar (c) is met today: 0 open silent-wrong compiler entries.** The first tally said 2;
  both were reproduced, found broader than recorded, and fixed (`4aa36ce` string+number/bool
  concat; the escaped-quote literal pair). That is 0 KNOWN; Phase 0's audit loop is what makes it
  mean something.
- ✅ **Phase 0a DONE 2026-09-28: `tests/golden_wat_tests.ts`.** It compiles in-process (no
  per-file spawn) every corpus `.ts` plus every `@test-pipeline` `wasic`/`modc` step (in place, in
  order): **478 entries** (421 + 57), each frozen as ONE `.golden` file with `status` / `wat` /
  `wit` sections. Failures are frozen too (5). Record 16s, check 16s; the snapshot is 139 MB, local and
  gitignored (`tests/.golden/`).
  - **Proven four ways:** (1) a check straight after recording shows 0 differences
    (deterministic); (2) a planted golden edit is reported at its line; (3) a real one-line
    EMITTER change is caught at line 1 of every module; (4) the same on a pipeline (its `modc`
    lib, `wasic` main and test).
  - A check that compares NOTHING fails (a typo'd filter once printed ✅).
  - **Recorded on `main` @ `1e27793`, Deno 2.9.7, binaryang 1.6.0.**
- 🔄 **Phase 0b round 1 DONE 2026-09-28: 28 silent-wrong + 8 loud, all CONFIRMED by running**
  (compiler-bugs.md § "H12 Phase 0b, audit round 1"; repros in `scripts/phase0/round1/`, verifier
  `scripts/phase0/verify_repros.ts`). Bar (c) is at **29** (sw29 added by the owner's dq01 ruling). Next: fix them, then audit round 2.
  One owner question is open (`dq01`, unannotated integer literals → i32).
- ⏳ **Phase 0b–0d: the audit loop.** Run "look for code issues" over `wasic.ts` + `console_log.ts`
  until a full pass finds nothing new. Each fix is validated by a golden diff showing ONLY the
  intended change, then the full gate. 0d re-freezes the golden after the loop converges.

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
