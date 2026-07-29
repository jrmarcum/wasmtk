# Roadmap, phase status & vision

> **README roadmap-table convention (owner directive):** the README's `## wasmtk Toolkit Roadmap` →
> `### Feature Status` is ONE unified `| Complete | Phase | Feature | Highlights |` table.
> **Complete** is `✅` (shipped) or `⏳` (incomplete: to-do / planned / blocked). **All incomplete
> (`⏳`) rows are ALWAYS listed at the end of the table, after every `✅` row** — when adding a new
> item, put a `⏳` row at the bottom and flip it to `✅` (moving it up among the completed rows) once
> it fully ships. Highlights are full descriptions (no `…` truncation): a feature says what it does;
> a bug fix states the issue and the fix. Detail sections were collapsed into this table (2026-07);
> deep internals live in `cmem/`, worked examples in each command's README section.
>
> **ROW PLACEMENT — group by PHASE, not by date (owner directive 2026-07-28).** A new enhancement or
> bug-fix row goes **immediately beneath the phase row it belongs to**, so everything about a phase
> reads together. Do NOT append new dated rows to the end of the `✅` block — they are invisible
> there (this is exactly what went wrong on the 2026-07-28 stress-test batch: five correctly-dated
> rows were added at the bottom and the owner could not find them). The only global ordering rule
> that outranks this is the `⏳`-always-last rule above.
>
> **ROW LABELLING.** The **Phase** column carries the phase number, the kind of change, and the date:
> `NN (YYYY-MM-DD)` for the phase itself, `NN bug fix (YYYY-MM-DD)` / `NN enhancement (YYYY-MM-DD)`
> for a later change to that phase. Put the date in the **Phase** column, never buried in Highlights.
> End the Highlights with the regression/stress-test filename(s) that cover the change (e.g.
> ``Stress test `26_NestedForOfMatrix` ``) so the row points at its own proof.
>
> **This applies to every future stress-test batch.** When a batch surfaces bugs across several
> phases, the rows scatter — one under each affected phase — rather than clustering as a batch.
> The batch itself is recorded as a single unit in `compiler-bugs.md` (post-mortems) and
> `testing.md` (counts); the README only ever gets the per-phase, user-facing rows.

## Release status (2026-07-29) — v1.11.9: operator-precedence fix

**v1.11.9 — merged to `main` from `test/phase29-stress-2026-07-29` (commit `852c531`) and published
to JSR.** Backend unchanged (wabt-ts 1.3.5 + binaryen-ts 1.4.3). Pre-publish gate: `deno publish
--dry-run` clean, `deno doc --lint` clean across all 16 JSR entrypoints. Full regression gate: wasi
**395/395**, wast 41 files / 12444 assertions / 0 failed, every other suite 0 failures.

**This release is worth upgrading to promptly** — the headline fix changes the VALUE of ordinary
arithmetic that previously compiled and ran without any diagnostic.

3 owner Phase 29 stress tests (static fields / getters+setters / string enums) + 1 regression test.
Test 1 passed; the other two each exposed genuine bugs — **including the most consequential one of
the whole stress-test series**:

- **`*`, `/`, `%` were parsed RIGHT-associatively.** `a * b / c` became `a * (b / c)`, so
  `180 * 5 / 9` gave **0** instead of 100 and `180 * 5 % 9` gave **900** instead of 0. It surfaced
  only because a Fahrenheit→Celsius setter used `(f - 32) * 5 / 9`; nothing about classes was
  involved. Fixed in BOTH binary-op loops (`emitExpr` + `exprToWat`) — fixing one alone left
  `console.log` emitting mixed `i32.mul`/`f64.rem`.
- **Pure string enums had no usable value form** — only heterogeneous enums got synthetic tags, so
  `const a: LogLevel = LogLevel.Error` and `a === LogLevel.Error` aborted. Now tagged, plus a
  runtime `$__enum_str_<Enum>` ladder so printing a string-enum VARIABLE shows its text, not the tag.
- **Literal-led / paren-led arithmetic in `console.log`** (`1 + n`, `(n + 0) * 5`) emitted f64 ops
  over i32 operands and failed to instantiate — PRE-EXISTING, found while writing the regression
  test. Fixed in both the segment-kind and operand-type decisions.

Suite **391 → 395/395**; wast 12444/0; every other suite 0 failures. Post-mortems in
[compiler-bugs.md](compiler-bugs.md); three new invariant sections in
[design-decisions.md](design-decisions.md).

## Release status (2026-07-28) — v1.11.8: stress-test bug-fix release

**v1.11.8 — 10 compiler fixes, 16 new tests, published from the
`fix/stress-test-batch-2026-07-28` work.** The whole release came out of owner-supplied stress
tests across Phases 22/24/25/26/27/28: 14 stress programs + 2 regression tests, of which **8 stress
programs exposed genuine compiler bugs**. Backend unchanged (wabt-ts 1.3.5 + binaryen-ts 1.4.3).

Pre-publish gate: `deno publish --dry-run` clean; **`deno doc --lint` clean across all 16 JSR
entrypoints** — this required documenting `scaffoldZigProject` (`src/zigwasic.ts`), a PRE-EXISTING
missing-JSDoc that would have dropped the score below 100, the same failure mode that made v1.11.4
score 94. Full regression gate: wasi **391/391**, wast 41 files / 12444 assertions / 0 failed, and
bindgen, bundle 4/4, merge, go_merge, both dync, mod, varscope, wasmmerge_guard, hybrid, jstyper,
go_bindgen, go_asyncify all 0 failures.

Commits: `bfe0f5a` (stress batch, 6 fixes) → `9245c9d` (StructImport) → `3fb62af` (Phase 27 string
parity) → `d2c8aa1` (regression-gate policy) → `04c8cf0` (memory consolidation) → `05bc662`
(Phase 28 join + bracket-concat) → v1.11.8 bump.

**The 10 fixes:** `as`-cast source type for `**`/`Math.*`; `T | null` tuple/struct returns;
`$__nullable_ret_flag` declaration; `??` in console.log args; nullable MODULE globals (new
capability); nested `for…of` cursor aliasing; PascalCase struct-type gate (fixed `bundle_tests`
StructImport, the last standing red suite); Phase 27 `emitStringPtrLen` method parity;
`arr.join()` as a string value; console.log concat broken by `]`/`)` inside a literal.

14 owner-supplied stress tests across Phases 22/24/25/26/27/28 plus 2 regression tests. **10 genuine
compiler bugs found and fixed** in `src/wasic.ts` + `src/console_log.ts`. Suite **375 → 391/391**,
zero regressions — and **every other suite in the repo is green too**, including `bundle_tests`
(4/4) for the first time and `wast_tests` (12444 assertions, 0 failed). Full roster in
[testing.md](testing.md).

New capability: **nullable module-level globals** (`let g: T | null` at module scope, with `g ??= v`
from inside a function) — previously a hard *unsupported statement* abort. Fixes: `expr as T` no
longer mis-types `**`/`Math.*` sources (this also repaired the common `Math.floor(x) as i32`
idiom); nested `for…of` no longer shares one cursor (a 3×2 matrix summed to 3 instead of 21); `??`
now works inside `console.log` args; `T | null` functions can return tuple/struct literals;
`$__nullable_ret_flag` is declared whenever it is referenced. Full post-mortems (including a
self-inflicted mid-fix regression and its root cause) in
[compiler-bugs.md](compiler-bugs.md) § "Stress-test batch (2026-07-28)"; the new
must-not-revert invariants are in [design-decisions.md](design-decisions.md) § "Nullable (`T |
null`) + cast invariants".

**`bundle_tests.ts` `StructImport` — the one long-standing red suite — is now FIXED (2026-07-28).**
It was pre-existing (verified on a clean tree), then researched and fixed in this same working
tree: struct-type annotations were gated on PascalCase spelling, so every `tsbundler`-mangled
imported type (`Vec2` in `vec.ts` → `vec_Vec2`) was rejected and multi-file struct imports could
not compile. Now gated on the `structDefs`/`classDefs` registry. Regression
`12_LowercaseStructTypeName`.

**Phase 27 string-method parity gap FIXED (2026-07-28).** Three more owner stress tests (string
`split` + `for…of`, trim/pad/replace, charCode/startsWith/endsWith) — two passed as-written; the
third exposed that `emitStringPtrLen` implemented only a SUBSET of the Phase 27 methods that
`emitStringAssign` had. `trim`/`charAt`/`repeat`/`replace`/`replaceAll` worked when assigned to a
variable and **silently emitted `0`** used inline (`console.log(s.repeat(3))` → `0`); string-literal
receivers failed the same way for `slice`/`.at`/case. Fixed by one generic handler that resolves the
receiver recursively (the existing `padStart` pattern) plus a `stringReceiverParts()` helper for the
cases needing ptr/len separately. No new WAT runtime — every helper already returned multi-value.
Post-mortem in [compiler-bugs.md](compiler-bugs.md); the parity invariant is now recorded in
[design-decisions.md](design-decisions.md) § "String methods: `emitStringPtrLen` must stay at PARITY
with `emitStringAssign`".

**Phase 28 `join` + console.log bracket-concat FIXED (2026-07-28).** Three Phase 28 array-method
stress tests; two passed as-written. `28_ArrayJoin` showed `join` had **no string value** — it lived
only in `console_log.ts` as a scratch-buffer `joinarr` segment, so `const s: string = arr.join("-")`
aborted. Fixed with `$__dynarr_join_str_i32`/`_f64` wrappers over the existing scratch writer plus a
handler in `emitStringPtrLen` (which `emitStringAssign` falls back through, so assignment, concat
and comparison were all fixed at one site). Testing that surfaced a **second, unrelated** bug:
`console_log.ts`'s `findTopLevelOp` counted `()`/`[]` without skipping string literals, so a closing
`]`/`)` inside a literal hid the top-level `+` and `console.log(w + "]")` silently printed `0` — the
same bug class already fixed on the wasic side but never mirrored into console_log. Regression
`27_ConsoleLogBracketConcat`; post-mortems in [compiler-bugs.md](compiler-bugs.md).

**Process decision — regression-gate policy (owner, 2026-07-28).** When a bug is found/fixed, run
the ENTIRE suite set **including `wast_tests`**; skip a suite only when the change is provably
outside its reach, justified from the impact map in [testing.md](testing.md) § "Which suites to run
for a given change". Grepping each runner corrected two intuitive-but-wrong assumptions:
`go_merge_tests` is **not** a Go-only outlier (it compiles a TypeScript driver with `wasic`), and
both `dync_*` suites are wasic-dependent (`src/dync.ts` imports `compileWasiTs`). Genuine outliers
for a pure-wasic change are `hybrid_tests`, `jstyper_tests`, `wast_tests`, `varscope_tests`,
`wasmmerge_guard_tests`, `mod_tests`, `go_bindgen_tests`, `go_asyncify_tests` — each with its own
separate trigger, so "outlier" is relative to which FILE changed, never absolute.

## Release status (2026-07-28) — v1.11.7 (JSR score 100)

> Latest: **v1.11.7** (producer/dync/README pass — see "### v1.11.7 (2026-07-28)" below). The
> v1.11.5 detail that follows is retained as history.

**v1.11.5 released to JSR** (score 100). On backend **wabt-ts 1.3.5 + binaryen-ts 1.4.3**.
Regression gate green: wasi **375/375**, `go_merge` 7/7, `go_bindgen` 7/7, **`go_asyncify` 12/12**
(now incl. `nested`), `hybrid` 10/10. The "B-items" backlog from `next-work.md` (B3/B4/B5) is done;
B6 stays deferred (no consumer). (v1.11.4 shipped the same code but scored 94 — `src/wast.ts` lacked
an `@module` tag so JSR's `allEntrypointsDocs` was false; v1.11.5 added it, restoring 100. JSR
provenance is absent since ≥v1.11.3 — a GitHub org OIDC-policy infra issue, not a code fix; see
next-work.md "Published state".)

### v1.11.7 (2026-07-28) — producer/dync/README pass

**v1.11.6** shipped dync pure-WASI portability + `wasmtk wasic`→dync abort guidance (see
[dynrt-design.md](dynrt-design.md)). **v1.11.7 PUBLISHED to JSR** — a large producer/dync/README pass
(files: `main.ts`, `src/gowasic.ts`, `src/zigwasic.ts`, `src/wasic.ts`, `src/dync.ts`, `README.md`,
`CHANGELOG.md`, `cmem/*`):

- **Producer verbs unified across go/zig/rust** (Rust model): `init`=WASI program, `initmod`=wasm
  library, `build`=program→`.wasm`, `modc`=library→`.wasm`, `run`=build+run. **`--lang` is now
  optional for run/build/modc** (auto-detected from `.go`/`.zig`/`.rs` or `go.mod`/`Cargo.toml`);
  **add/remove/list/fmt/clean no longer need `--lang=rust`**. **Go browser scaffold REMOVED**
  (`--go-target=wasm` errors → universal wasm loader; `--go-target=wasm-unknown` leaf kept). `run
  <dir>` with no project → clear error. Full detail: [polyglot-producers.md](polyglot-producers.md)
  § "UPDATED 2026-07-28".
- **dync no longer writes the empty `.wit`**; merge notices `⚠️`→`ℹ️`. **Correction recorded:**
  Go/Zig/Rust do NOT auto-emit `.wit` (only TypeScript does; Go bindgen uses a hand-written one).
- **README restructured**: Compiler Options → Choosing → Programmatic API → Producers & Backends →
  **Utility Options** (new: mod/info/wasm2js/convert alongside wasmbundle/jstyper/bindgen/wast/run) →
  Roadmap. Added wasic/modc/dync/hybrid **Limitations** notes. **Roadmap collapsed into ONE unified
  `Complete | Phase | Feature | Highlights` table** (`✅`/`⏳`; **all `⏳` rows always last** — see the
  README-table convention note at the top of this file); detail sections removed (examples live in
  each command section, internals in `cmem/`). New gate `tests/dync_cross_runtime_tests.ts`.
- Suites green throughout: wasi 375/375, go_merge 7/7, go_bindgen 7/7, go_asyncify 12/12,
  dync_conformance 3/3, dync_cross_runtime 3/3, bindgen 142, jstyper 73. **Published as v1.11.7.**

1. **Nested goroutines now run in-house — the headline.** A goroutine that suspends *inside* another
   suspending goroutine (`inner.Wait()`) used to trap `memory access out of bounds`. Root cause was
   **NOT asyncify** — it was a **binaryen-ts binary-DECODER reorder bug (WT-2k, fixed in 1.4.3)**:
   TinyGo's goroutine trampoline keeps the caller's `$__stack_pointer` (`global.get`) on the operand
   stack across `global.set $sp; call…` then restores it; the decoder reordered that `global.get`
   past the `global.set` → a `global.set(global.get)` self-assign that corrupted the shadow stack.
   The decoder now spills such reordered values to a temp local. Found by bisecting the merged module
   to `tinygo_launch` + a pure `readBinary→emitBinary` repro. **The earlier "memory-grow ordering"
   theory was a red herring** (a runtime trace proved our asyncify matched `wasm-opt` byte-for-byte).
   `nested/` re-enabled in the forced in-house list. binaryen-ts 1.4.2 also added **liveness-minimized
   asyncify saving** (frames smaller than `wasm-opt`). See [polyglot-producers.md](polyglot-producers.md)
   § "NESTED SUSPENSION — found then FIXED" + binaryen-ts `cmem/correctness.md` § "WT-2k".
2. **B3 — broadened goroutine coverage.** `go_asyncify_tests.ts` is table-driven over the full
   surface: worker-pool (`sum: 30`), `select`, `time.Sleep`, `WaitGroup`+`Mutex`, 3-stage pipeline,
   nested — 12/12.
3. **Standard-Go merge guard.** `wasmmerge` now rejects a `memory.grow`-carrying module (std-Go's
   full runtime) at MODULE level, before the per-function `call_indirect` guard, with a clear
   "STANDARD Go … build a MERGEABLE leaf with TinyGo `--go-target=wasm-unknown`" message; `gowasic`
   rejects `--go-runtime=std --go-target=wasm-unknown`. Go-free regression `wasmmerge_guard_tests.ts`.
4. **B5 — hybrid nested-backtick.** `skipLiteral` descends into `${…}` so a nested backtick template
   no longer truncates a `@wasm` body or defeats call-rewriting.
5. **Backend bumped** binaryen-ts 1.4.1 → 1.4.3; `deno.json` pins `^1.4.3`.

## Release status (2026-07-08) — v1.11.3

**v1.11.3 released to JSR.** First publish since v1.11.2 (2026-07-03); on backend **wabt-ts 1.3.5 +
binaryen-ts 1.4.1**. Suite **375/375**, bindgen **142**, go_bindgen 7/7, go_asyncify 3/3, jstyper
73/73. Landed since v1.11.2:

1. **Goroutine Go with NO external binaryen** — the headline. binaryen-ts 1.4.1 added the **in-wasm
   `asyncify.*`-import mode** to its Asyncify pass (TinyGo's scheduler imports
   `asyncify.start_unwind`/… and drives its own unwind/rewind; the pass removes those imports and
   wires the calls to the synthesized control functions). wasmtk's `--lang=go` no-wasm-opt branch
   now builds `-scheduler=asyncify` + a passthrough shim, then `binaryenAsyncify` (binaryen-ts
   Asyncify + `-Oz`) → **goroutines run with zero external binaryen**.
   `WASMTK_GO_BINARYEN_ASYNCIFY=1` forces this path. Validated e2e (`tests/go_asyncify_tests.ts`,
   TinyGo-gated): a channel worker-pool → `sum: 30`. See
   [polyglot-producers.md](polyglot-producers.md) + binaryen-ts `cmem/passes.md` § "In-wasm
   asyncify-import mode".
2. **Go string/aggregate bindgen — SHIPPED** (canonical vs wasmtime; the only fix was SPEC §10 in
   the bindgen loader — a minimal WASI-P1 shim + `_initialize`). `bindgen` 131→135→142, `go_bindgen`
   7/7.
3. **Three-pass code-audit sweep** (see [compiler-bugs.md](compiler-bugs.md) § "Code-audit sweep"):
   fixed a binaryen-ts `call_indirect` eval-order miscompile + a dropped-`unreachable` in Flatten;
   the lossy WIT kebab↔camel round-trip breaking capital-heavy exports (`parseHTML`) in the merge
   overlay + bindgen; the `hybrid` scanners are now regex/template-aware; + fail-loud/robustness
   conversions (asyncify memory-ensure / import-globals / multi-memory / lists; WIT unknown-type
   throws; gowasic runtime-agnostic shim). New `tests/hybrid_tests.ts` (8) + `kebabcase_50` bindgen
   fixture.
4. **Backend bumped** binaryen-ts 1.3.9 → 1.4.0 → 1.4.1 (audit fixes in 1.4.0; the asyncify import
   mode in 1.4.1); wabt-ts stays 1.3.5.

## Release status (2026-07-02) — v1.11.2

**v1.11.2 released to JSR.** Four landed changes since v1.11.1, on a bumped backend (**wabt-ts
1.3.5** + binaryen-ts 1.3.5). Suite **375/375**, bindgen 131/131, jstyper 73/73, wast gate 41
files/12444/0 fail:

1. **mathlib correctly-rounded sweep — COMPLETE.** Every `mathlib` elementary function is now
   IEEE-754 correctly-rounded via double-double: `sin/cos/tan`, `exp`, `log/log2/log10`, `cbrt`,
   `atan`, `asin/acos/atan2`, `sinh/cosh/tanh/expm1`, `asinh/acosh/atanh/log1p`, and **`pow`**
   (moved into mathlib as a full `exp(y·log|x|)` CR impl, routed from `Math.pow`/`**`). Each
   validated bit-for-bit vs an independent BigInt oracle through the full pipeline. See
   [math-cr-sweep.md](math-cr-sweep.md). (`pow` surfaced the constraint that a **mergeable
   capability lib must not use a mathlib-routed `Math.*`** — dynrt's `Math.pow` was made
   self-contained; see [compiler-bugs.md](compiler-bugs.md).)
2. **`.wast` spec-script runner + `wasmtk wast`** (`src/wast.ts`, gate `tests/wast_tests.ts`). Runs
   the official WASM spec conformance testsuite (in-repo at
   `tests/module/wasm_wast/testsuite-main/`); 12178 curated core assertions pass clean. Surfaced **3
   real wabt-ts backend bugs — ALL FIXED across wabt-ts 1.3.4 + 1.3.5 (2026-07-02):** br_if/br_table
   with a branch value (1.3.4), over-precise hex-float truncation (1.3.4), decimal→f32
   double-rounding (Bug C, 1.3.5). The gate grew 31→40→41 files (now incl.
   br/br_if/br_table/labels/block/nop/local_get/conversions/func/float_exprs/**const**), **12444
   assertions, 0 fail**; suite 375/375 on 1.3.5. Also made 2 runner correctness fixes while
   re-validating (void export → `[]`; NaN-payload arg skipped — can't cross the JS boundary). Report
   (resolved): `scripts/wabt-ts-bug-report.md`. See [architecture.md](architecture.md) `wast` row +
   [testing.md](testing.md).
3. **Test folders reorganized into 3 by runtime-consumption model** (2026-07-02): `tests/wasi/`
   (runnable WASI programs: `wasm_wasi`, `wasm_wasi_dync`, `wasm_wasi_bundle`), `tests/module/`
   (invokeable modules: `wasm_mod`, `bindgen_fixtures`, `wasm_wast`), `tests/hybrid/`
   (`hybrid_fixtures`). `jstyper_fixtures`/ `go_fixtures` stay as producer inputs. All 8 runners +
   `gen_caps_bytes` + `.gitignore` + docs rewired; original dir names kept as siblings so the `18*`
   `../wasm_wasi_bundle/…` @step paths still resolve.
4. **Generated build outputs untracked** (`.gitignore` extended to `tests/wasi/wasm_wasi_bundle/**`,
   `tests/module/bindgen_fixtures/*`, `tests/wasi/wasm_wasi_dync/*` — same policy as
   `tests/wasi/wasm_wasi/`). Verified by a clean regeneration (deleted all outputs → suites rebuilt
   them → 375/375). These outputs + `src/wasm/mathlib.wasm` double as **cross-runtime validation
   fixtures**: always regenerate with a green suite before validating another wasm runtime so you
   compare against current-compiler output. See [testing.md](testing.md).

## Release status (2026-06-30)

**Version 1.11.1 is PUBLISHED to JSR** (`@jrmarcum/wasmtk@1.11.1` is `latest`). **1.11.1 COMPLETES
the Route A javyc-retirement track — `javyc` is now DELETED.** This is **2h, the cutover**: (a) the
dynrt interpreter gained **console I/O** — `console.log`/`error`/`warn` in eval source print to
stdout via a new `env.__host_print` import (`runWasi` + the bindgen loader implement it); this also
surfaced + fixed an interpreter HANG (`evalSkipWs` had no comment handling and looped on a
multi-byte UTF-8 char in a comment — now skips `//` + `/* */`). (b) A new **`wasmtk dync <file>`**
command — the `javyc` replacement — compiles an ENTIRE dynamic TS/JS file to a self-contained WASI
module by base64-embedding its source and running it through the embedded `wasmtk:dynrt`
(`dynRunB64`), **no external Javy/QuickJS**. (c) A **conformance gate**
(`tests/dync_conformance_tests.ts`) output-diffs `dync` vs a `deno run` JS baseline (demo1/2/3,
**3/3**; caught + fixed a `Math.min`/`max` variadic bug). (d) **Deletion** of `src/javyc.ts`, the
`javyc` command + `./javyc` export, `tests/wasi_javy_tests.ts`, and all Javy download/detect/convert
code in `utils.ts`. Suite **360/360** (+`18zz`), bindgen 131/131, jstyper 73/73. **Out of scope
(documented):** interactive `prompt` and ESM import/export of other modules. With 2h done, **the
dynrt own-runtime track is functionally complete** — `wasic` (`any`/`eval`) and `dync` (whole-file
dynamic) both route to wasmtk's own runtime; the interim `javyc` fallback is gone.

**2026-07-27 — `dync` is now PURE-WASI portable + `wasic` guides to `dync`-or-fix (no silent
fallback).** (1) **Portability:** `wasmtk dync` output previously imported the wasmtk-only
`env.__host_print` + `env.__host_call`, so it ran only under wasmtk. `internalizeDynrtHostImports`
(in `compileWasiTs`, before final assembly) now rewrites those into internal definitions —
`__host_print`→inline WASI `fd_write(1,…)`, `__host_call`→`unreachable` trap — so the module imports
ONLY `wasi_snapshot_preview1` and runs unchanged on wasmtime/wasmer/wazero (byte-identical stdout,
9/9). Keyed on the reserved dynrt import names and scoped to the WASI-executable path only, so bindgen
libraries (`compileLibTs`) keep their `env.*` imports for the host loader. New standing gate
`tests/dync_cross_runtime_tests.ts` (3/3). (2) **wasic↔dync UX:** on a `wasmtk wasic` abort, the CLI
now classifies the diagnostics and prints the right next step — `wasmtk dync <file>` for a dynamic
feature, or "fix this first" for a genuine undefined-name error (dync would fail on it too). Decision:
KEEP both engines, NO silent auto-fallback (avoids the interpreter-size cliff + masking wasic gaps).
(3) Merge notices reclassified `⚠️`→`ℹ️` (informational, not warnings; `⚠️` reserved for real
warnings). Suites green: wasi 375/375, dync_conformance 3/3, bindgen 142/142. Full write-up in
[dynrt-design.md](dynrt-design.md).

**Version 1.11.0** (2026-06-30) was the async + remaining-ES6 batch (two increments): **2e.10**
async/await + Promise in eval source — a **SYNCHRONOUS** model (the re-parse interpreter has no
event loop): an `async
function` (id=-4) runs to completion and wraps its result in a settled
Promise (rejected if it throws), `await` unwraps a settled promise (throws on rejected → integrates
with 2e.6 try/catch), `.then`/`.catch`/ `.finally` run callbacks immediately,
`Promise.resolve`/`reject`/`all` (`18zx`); and **2e.11** the remaining common ES6 surface —
`instanceof` (walks the instance `__proto__` chain for the class prototype), object spread
`{ ...o }` + call spread `f(...args)`, array/object destructuring (`const
[a, , c] = …` incl.
holes/missing, `const { x, y: z } = …` incl. rename), and class expressions (`const C
= class {…}`,
anonymous + `extends`; `runClassDecl` refactored into a shared `buildClass` helper) (`18zy`). Both
increments are purely interpreter-side (no wasic compiler change). At the 1.11.0 tag:
`tests/wasi/wasm_wasi` suite **359/359**, bindgen 131/131, jstyper 73/73. With 2e.11 the dynrt
interpreter's ES6 syntactic surface was essentially complete (2h — the removal — followed in
1.11.1).

**Version 1.10.9** (2026-06-26) was the STDLIB + generators batch — the dynrt interpreter gained the
JS standard-library surface plus generators: **2f.2** Array methods (push/pop/shift/unshift/indexOf/
lastIndexOf/includes/at/join/slice/concat/reverse/sort +
map/filter/forEach/reduce/find/findIndex/some/ every — `18zq`); **2f.3** String methods
(charAt/charCodeAt/case/trim/slice/indexOf/includes/startsWith/ endsWith/repeat/pad/concat/split —
`18zr`); **2f.4** Object + Math statics (`18zs`); **2f.5** JSON parse+stringify (`18zt` — JSON ⊂ the
interpreter's literal grammar, so parse re-enters `parseExpr`); **2f.6** Map + Set (`18zu`);
**2f.7** RegExp (`new RegExp` + a backtracking matcher — `18zv`); and **2e.9** generators
(`function*`/`yield` via eager collection; `.next()`/`for…of`; finite generators — `18zw`). The
stdlib bridges (Array/String/Object/Math/JSON/Map/Set/RegExp) are all implemented natively in the
value model — NOT the i32-handle capability libs (those are i32-keyed; dynrt collections hold
arbitrary boxed values). At the 1.10.9 tag: `tests/wasi/wasm_wasi` suite **357/357**, bindgen
131/131, jstyper 73/73. JSR score 100% (provenance `true`, docs clean — keep `deno doc --lint` clean
to hold it).

**Version 1.10.8** (2026-06-26) was a big OOP batch (five increments): **2e.7a** per-iteration
`let`, **2e.7b** the `var`→`let` consumption gate (establishes ES6 as the base preferred consumption
format), **2f.1** `this`+prototype, **2e.8** classes (+ a string-blind `parseClasses` fix),
**2e.8a** class completion (extends/super/static/fields/getters/setters). **Earlier in the 1.10.x
line:** 1.10.1–1.10.5 (control flow / literals / function-exprs+arrows / member-index assignment /
operators), 1.10.6 (exception handling), 1.10.7 (lexical block scoping), 1.10.0 (bidirectional
functions-as-`any`).

**Version 1.9.0** (2026-06-24) shipped the **COMPLETE #14 own dynamic runtime** — value model → JS
interpreter (`eval`/`new Function`) → wasic `any` integration → host↔core marshalling
(numbers/strings/ bools/objects/arrays **and functions**) → bounded-memory **mark-sweep GC** →
**hybrid recycling allocator** → **functions-as-`any`** (the `Function(params, body)` producer + a
callable, pinned host proxy), verified end-to-end (`getDoubler()(21)=42`).

**Version 1.8.0** (2026-06-22) shipped the **full v1 `async`/Promise surface** for the `wasic`
compiler (#13 track, sub-phases 13.1a–13.5; design + log in [async-design.md](async-design.md),
user-facing notes in `CHANGELOG.md`): `async`/`await`, `Promise.resolve`/`reject`,
`.then`/`.catch`/`.finally`, `Promise.all`/`allSettled`, plus the `hybrid` async lift — all
standalone, no embedded JS runtime. At the 1.8.0 tag the suite is **317/317** (8 async tests
`54_*`–`61_*`), bindgen 104/104, jstyper 73/73. (The async track was committed post-1.7.0 and is now
released as 1.8.0; what was previously "NOT yet published" is shipped.)

The **JSR package score is 100%** (`total: 18`), carried forward from v1.7.0. The two gaps that had
dropped it to 94 were fixed at 1.7.0 and remain fixed:

- **`hasProvenance: true`** — provenance now works. It had been silently `false` across
  v1.6.2–v1.6.5 even though every Action run succeeded; the committed `publish.yml` was always
  provenance-correct (`id-token: write` + clean `deno publish` + `v*` tag trigger, byte-identical at
  the tags), so the cause was environmental (org/enterprise Actions OIDC policy gating the
  id-token), not the YAML. A diagnostic step ("Check OIDC availability") was added before
  `deno publish` to surface a missing OIDC token in the run log; the 1.7.0 run published with
  provenance.
- **Docs: `percentageDocumentedSymbols` 0.79 → 0.97** (≥0.80 threshold cleared). Commit `e64595f`
  added JSDoc to the 57 `missing-jsdoc` symbols across 9 files, exported the 3 producer result types
  (`GoResult`/`ZigResult`/`RustResult`) to clear 5 `private-type-ref` errors, and gave `DATA_BASE`
  an explicit type. `deno doc --lint` is now clean across all 15 entrypoints — keep it clean on
  future edits to hold the score.

Prior release **v1.7.0** (2026-06-15, suite 309/309) shipped `Number.parseInt`/`parseFloat`,
declaration-order-independent multi-level interface inheritance, and the Canonical ABI return-side
forward-alignment (callee-allocated string returns + `cabi_post_<name>`). Release mechanism
unchanged: `deno task publish` (sync-version → commit → tag `vX.Y.Z` → push → `publish.yml` Action
runs `deno publish` with provenance).

## Compiler phase status

All **50 phases complete** plus sub-phases 5e/5f/5g/5h/6d/12b/13b. Full per-phase implementation
detail lives in `README.md` ("Completed Phases") and the legacy `CLAUDE.md`. Summary of milestones:

- Core language (functions, control flow, types, operators, enums, templates).
- Closures: first-class fns (5e), heap closures/factories (5f), named fn-type aliases (5g), shared
  mutable captures with heap-boxing (5h).
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

| Stage | Scope                                                                                                                                                                                                                                                                                                                                                            | Status                                                |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 0     | Canonical ABI **calling-convention alignment** — `cabi_realloc` export, (ptr,len) string params, and (2026-06-15) **canonical callee-allocated string returns + `cabi_post_<name>`**. Only the container is deferred (P1 core + sidecar WIT, not an embedded component). See [polyglot-producers.md](polyglot-producers.md) / [architecture.md](architecture.md) | ✅ 2026-05-19; return-side forward-aligned 2026-06-15 |
| 0.5   | Dual JSR `/compat` backend migration (wabt-ts + binaryen-ts)                                                                                                                                                                                                                                                                                                     | ✅                                                    |
| 0.6   | Allocator unification in wasmmerge (shared heap across merged libs)                                                                                                                                                                                                                                                                                              | ✅ 2026-05-30                                         |
| 0.7   | Tier-1 stdlib capability libs (Set/Map/Date/JSON/RegExp)                                                                                                                                                                                                                                                                                                         | ✅ 2026-05-30/31 — see capabilities.md                |

## stdlib-bundling brief — remaining work items (§7)

| # | Item                                                                               | Status                                                                                              |
| - | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 1 | Confirm wasmmerge malloc/heap handling                                             | ✅                                                                                                  |
| 2 | Implement allocator-unification pass                                               | ✅                                                                                                  |
| 3 | Author Tier-1 caps (Set, Map, Date, JSON, RegExp)                                  | ✅ **all 5 done**                                                                                   |
| 4 | Wire capability selection (feature-level tree-shake — bundle only referenced caps) | ✅ 2026-06-02 — embedded caps + virtual `wasmtk:<cap>` import, auto-merge only referenced           |
| 5 | Promise/async: microtask runtime; lift `hybrid` async exclusion                    | ✅ COMPLETE 2026-06-15 — #13 13.1a–13.5 (eager microtask runtime, not state-machine; suite 317/317) |
| 6 | Evolve `hybrid` from `// @wasm` annotations → TS-type-driven routing               | ✅ 2026-06-02 — `--auto` mode routes fully-typed fns to wasic, dynamic to host                      |
| 7 | Decide the §6 kernel scope question (drop `javyc` vs ship own dynamic runtime)     | ✅ DECIDED 2026-06-02 — **build wasmtk's own dynamic runtime** (see below)                          |

**§7-#7 decision (2026-06-02, project owner) — ✅ DELIVERED (v1.9.0–v1.11.1):** wasmtk **shipped its
own dynamic-runtime module** to cover the irreducible kernel (`eval`/`new Function`, pervasive
`any`, open-prototype mutation) rather than declaring it out of scope or relying on `javyc`
long-term. The own runtime (the `wasmtk:dynrt` interpreter) is complete; **`javyc` (QuickJS) was
retired and DELETED in v1.11.1** (the whole-file entry is `wasmtk dync`). `hybrid --auto` (#6)
routes dynamic-shaped functions to the own runtime (its fallback is the HOST, never Javy). The
paragraph's original "not implemented yet / interim fallback" wording reflects the 2026-06-02 state.

**#5 Promise/async is COMPLETE** (2026-06-15 — #13 13.1a–13.5; eager microtask runtime + `hybrid`
lift; suite 317/317). The remaining large track is the **own dynamic runtime** (#7 decision) — gated
behind Phase 51 language hardening (now done), so unblocked.

## Prioritized execution order (set 2026-06-03)

**Principle (project owner, 2026-06-03):** the never-scheduled language-completeness gaps take
**precedence over the big tracks**, because #5 async and the own dynamic runtime _lower onto_ the
existing codegen (struct layout, field access, type inference, narrowing, tag dispatch). Completing
the foundational gaps first — with cheap, standalone repros — hardens exactly those paths so a later
bug is debugged once, not while also debugging a state-machine/interpreter transform. Ordered
foundation-depth first, then by effort (quick wins first). Each item ships with its own regression
test. (The **ecosystem loader** track is the exception — it consumes the compiled
`.wasm`/`.wit`/ABI, not TS syntax, so it is orthogonal and ungated.)

### Phase 51 — Language hardening (GATES #5 async + own-runtime) — ✅ COMPLETE 2026-06-07

All four items done: 51.1 `instanceof`, 51.2 object spread, 51.3 destructuring (param + nested
object + nested tuple), 51.4 utility types. The async (#13) and own-runtime (#14) tracks are now
unblocked.

1. **`instanceof`** — ✅ **DONE 2026-06-05** (class tags). Runtime tag check when the module has
   inheritance (`tag(obj) ∈ {target + all subclasses}` via `findSubclasses`, read from offset 0);
   compile-time const from the var's tracked class when there is no inheritance (no tag header).
   `if (x instanceof Sub)` narrows x to Sub in the then-branch (reuses the Phase-34 narrow machinery
   in `emitBlock`); `console.log(x instanceof C)` works via a `setInstanceofResolver` bridge in
   `console_log.ts`. Tests
   `51_BasicInstanceof`/`51_InstanceofNarrowing`/`51_InstanceofNoInheritance`/ `51_Phase51Combined`
   (suite 279→283). DU-tag `instanceof` not added — TS DUs aren't classes, so `instanceof` doesn't
   apply; class hierarchies are the real use. Two PRE-EXISTING construction gaps were surfaced AND
   **fixed 2026-06-05** (tests `51_ModuleLevelClassInstance` + `51_ClassInstanceArrayLiteral`, suite
   283→285): (a) module-level class instances are now tracked in `classVars` (new `newClassPre` in
   the startBodyLines pre-scan) so field access / method dispatch / instanceof work at module scope;
   (b) `const a: C[] = [new C(…), …]` is desugared to `const a: C[] = []; a.push(new C(…));…` (new
   `expandClassInstanceArrayLiterals` source pre-pass) so each element is constructed with its
   ctor + class tag. See compiler-bugs.md / design-decisions.md. A third gap surfaced here —
   single-PHYSICAL-line class/constructor bodies, e.g.
   `class C { v: i32; constructor(x: i32) { this.v = x; } }` all on one line — was ALSO **fixed
   2026-06-05** (test `51_SingleLineClassBody`, suite 285→286): `parseClasses` now splits class
   members with a depth/string-aware `splitClassMemberLines` (so fields sharing a line with methods
   are parsed) and splits single-physical-line method bodies via `splitStmts`.
2. **Object spread** `{...base, k: v}` — ✅ **DONE 2026-06-07** (test `51_ObjectSpread`, suite
   287→288). `const r: T = { ...src, k: v }` builds the struct at runtime: copies every target field
   from `src` by name (using the base's own offset/type; string fields copy both ptr+len words),
   then applies the named/shorthand overrides; unset fields stay zero. New
   `parseStructLiteralWithSpread` helper + `resolveStructBase`/`emitSpreadStructLiteral` in
   `src/wasic.ts`; `emitRuntimeStructLiteral` delegates when a spread is present (non-spread path
   unchanged). Both struct-let pre-scans (function + module) flag the var in `structSpreadVars` and
   register it with **ptr=-1** ("pointer lives in the local," so every field-read site reads via
   `local.get`); a `structSpreadMatch` emit branch (before the static struct-let handler) owns the
   assignment. Works for literal/runtime-var overrides, pure copy, mixed i32/f64 fields,
   function-local + module-level, and chained spread (spread of a spread). Known limits:
   single-physical-line literals only; string-field _overrides_ still store ptr-only (pre-existing
   `emitRuntimeStructLiteral` limitation — copies are fine); spread in `return {...}` / call-arg
   position not wired (struct-let + array `push` contexts are).
3. **Destructuring in function params** `f({x, y}: Vec2)` — ✅ **DONE 2026-06-07** (test
   `51_ParamDestructuring`, suite 288→289). Source pre-pass `expandParamDestructuring()` rewrites a
   destructuring param `{ x, y }: Vec2` / `[a, b]: [i32,i32]` to a synthetic struct/tuple param
   `__pd_N: Type` and injects `const { x, y } = __pd_N;` / `const [a, b] = __pd_N;` at the top of
   the body — reusing the existing struct-param + `const {…}=obj` / `const […]=tup` machinery (no
   new emit path). Runs before `parseFunctions`. Also fixed `parseParams`' comma-split to be
   **bracket/brace-aware** (was paren-only, so a tuple-type param `[i32, i32]` split at the inner
   comma). Covers object params (incl. renamed `{a: lo}`), tuple params,
   destructured-alongside-normal params, struct-var args, and multiple destructured params. Known
   limits: named `function NAME(...)` declarations only (arrow/method params are a follow-up);
   inline tuple-literal _args_ (`f([1,2])`) remain a separate pre-existing gap (pass a tuple var;
   struct-literal args work). **Nested destructuring** `const { a: { b }, c } = obj` — ✅ **DONE
   2026-06-07** (test `51_NestedDestructuring`, suite 289→290). The object-destructure emit
   handler + pre-scan were rewritten from the `\{([^}]+)\}` regex to **balanced-brace detection +
   recursive helpers** (`emitDestructurePattern` / `collectDestructureLocals`): a binding whose
   value is itself a `{…}`/`[…]` pattern recurses into the nested struct/tuple field (pointer fields
   load the stored ptr; inline-tuple fields use the field address) — no temps, nested loads inline.
   Arbitrary depth + renames + Phase-48 zero-default fallback all work, incl. nested destructuring
   in a param (`f({a:{b}}: T)`, via the param pre-pass). **Nested tuple/array
   `const [[a, b], c] = t` — ✅ DONE 2026-06-07** (test `51_NestedTuple`, suite 290→291). Made the
   tuple infra bracket-aware end-to-end: `tupleTypeName`/`makeTupleStructDef` now split
   bracket-aware and **embed a nested tuple element inline** (`tupleTypeName` field,
   natural-aligned, size = nested totalSize); tuple-literal construction
   (`const t: [[i32,i32],i32] = [[1,2],3]`) recurses via `emitTupleLiteralStores` (stores
   sub-elements at `baseOffset+field.offset`); tuple destructuring routes through the same recursive
   `emitDestructurePattern` as objects (balanced-bracket detection). Works for mixed f64/i32, nested
   tuple **params** (`f([[a,b],c]: [[i32,i32],i32])`), and preserves positional gaps. **Phase 51.3
   COMPLETE.** **Process note:** the test runner judges by per-step **exit code, not output diff** —
   a broad codegen change can silently alter output while still "passing". Always output-verify
   (ts-run vs wasm-run) the tests your change touches; a gap-collapse bug here
   (`splitBraceAwareCommas` drops empty elements → `[a, , c]` read the wrong index) passed the suite
   but was caught by output-diffing `21_*`. Fixed with `splitBraceAwareCommasKeepEmpty`.
4. **Utility types** — ✅ **DONE 2026-06-07** (test `51_UtilityTypes`, suite 291→292). First batch
   shipped: **`Partial`/`Readonly`/`Required`/`NonNullable`** are pass-through (resolve to the inner
   type — all layout-identical in wasic's fixed-struct world; `NonNullable` also strips `| null`),
   done by `expandUtilityTypes()` (source text transform with balanced `<…>` extraction, BEFORE
   parseStructs, loops for nesting like `Partial<Readonly<T>>`). **`Pick`/`Omit`/`Record`**
   synthesize struct types via `expandStructUtilityTypes()` (AFTER parseStructs, needs the base
   def): `Pick`/`Omit` copy the base fields (subset / complement) PRESERVING offsets + totalSize so
   a base-typed value is layout-compatible; `Record<"a"|"b", V>` builds a fresh struct keyed by the
   literal-union (open-key `Record<string,V>` is a dynamic map → left unresolved). Both
   `type Alias = Pick<…>` (registered under the alias, decl stripped) and inline use sites (synth
   `Pick_T_K` name — MUST start uppercase so `[A-Z]\w*` struct-type detection fires) work.
   **Deferred (the "then" batch):** `Exclude`/`Extract`/`ReturnType`/`Parameters`
   (union/function-type ops, niche in wasic). **Bonus fix found via output-verification:**
   `console.log("x:", a.i + b.i)` on i32 **struct fields** (and 3-term `a+b+c` of i32 locals)
   emitted `f64.add` of i32 loads → compile error; fixed in `console_log.ts` by inferring the
   binary-op operand type from the LHS's **leading atom** (var / `var.field` via `structLookup` /
   `.length`), conservatively skipping `arr[i]`/`fn()`/`a.b.c` so f64 elements aren't mis-typed.
   Purely additive (no existing test could use the pattern — it didn't compile — so zero
   tracked-`.wat` changes). NOTE: a SEPARATE pre-existing bug remains —
   `console.log("x:", arr[i] + arr[j])` (array-element arithmetic) returns only the first element;
   out of scope here.

### Pre-Phase-52 correctness cleanup — 14 output-mismatch bugs (ALL FIXED 2026-06-08)

A pre-Phase-52 code audit + **test-runner hardening** (now diffs run-ts vs run-wasm OUTPUT, not just
exit codes — see testing.md / compiler-bugs.md "Runner-hardening audit") revealed **31** tests that
were green-but-wrong. **12 fixed** in that pass (two string-literal-masking scanner bugs), **5**
allowlisted as legitimate divergences, and the remaining **14 were ALL FIXED 2026-06-08** (clusters:
exceptions/error string payloads, string ops/formatting, struct-field mutation, for…of, class-array
literal — full root-cause list in compiler-bugs.md). A follow-up hazard audit (2026-06-08) fixed 4
more latent issues: brace-less single-line `for…of` (dropped body), `console.error`
bool-array-method formatting, the class-instance `ptr<0` sentinel, and extended the greedy-regex
`parenDepthNeverNegative` guards. Suite under the hardened runner: **299/299** (no open bugs),
bindgen 103/103, jstyper 73/73.

### Phase 52 — Leaf conveniences (NO downstream risk) — ✅ COMPLETE 2026-06-11

All five shipped (suite 299→305, all output-verified ts-run == wasm-run; bindgen 103/103, jstyper
73/73). Tests `52_VoidExpr` / `52_ChainedAssignment` / `52_InOperator` / `52_ArrayFromOf` /
`52_StringFromCodePoint` / `52_Phase52Combined`. All in `src/wasic.ts` unless noted.

5. **`void expr;`** → evaluate for side effects, discard. Statement handler at the top of
   `emitStatement`: a void/string-returning call is re-emitted as a plain call statement (the call
   still runs; a string result has no single droppable value); a numeric result is `(drop …)`; a
   non-call expr is `(drop (emitExpr …))`.
6. **Chained assignment `a = b = c = 0`** — `emitStatement` detects ≥2 top-level plain `=` (skipping
   `==`/`===`/`=>`/`!=`/`<=`/`>=`/compound), requires every target to be a bare identifier, then
   lowers to `c = 0; b = c; a = b` (rightmost first) reusing the normal assignment emitter (handles
   locals/globals/strings/types for free). Declaration-form chains (`let a = b = 0`) intentionally
   bail.
7. **`"field" in obj`** — closed-world compile-time `1`/`0` in `emitExpr` (via
   `findDepth0Keyword(" in ")`
   - new `structHasField` resolving struct/class fields from `structVars`/`classVars`). Returns null
     → falls through when the type/key is unknown. Print direct in `console.log` not wired (route
     via a `boolean` local or an `if` condition — both go through `emitExpr`).
8. **`Array.from([…])` / `Array.of(…)`** — source pre-pass `expandArrayFromOf` (string-aware
   balanced scan, runs right after the `Array.from({length})` 2D sentinel) rewrites them to plain
   array literals (`[…]`); recurses so nested forms expand. `Array.from` of anything other than a
   literal array is left untouched. **`Array.isArray(x)`** — `emitExpr` closed-world const: `1` iff
   x ∈ arrayVars/moduleArrayVars/typedArrayVars, else `0`.
9. **`String.fromCodePoint(...)`** — UTF-8 encodes code point(s). Constant args → static data string
   (`allocStringDecoded`, no unescape; via new `constCodePoint` validator covering decimal/hex in
   the valid Unicode range). Single runtime arg → new `$__str_from_codepoint` WAT helper (1–4 byte
   UTF-8, multi-value ptr,len). Wired into `emitStringAssign`, the concat path, `isStringExpr`, and
   the two `$__str_op` prologue temp-pair detectors. Bonus: console_log.ts `dotLenMatch` now handles
   string `.length` (UTF-8 byte length) for local strings / module string consts / string globals —
   a pre-existing gap that also affected `fromCharCode` strings. NOTE multi-byte: wasic `.length` is
   UTF-8 byte count, TS `.length` is UTF-16 units (the test only `.length`-checks ASCII).

### Phase 53 — Standalone built-ins — ✅ COMPLETE 2026-06-15

10. **`Number.parseInt(s, radix)` / `Number.parseFloat(s)` (+ bare `parseInt`/`parseFloat`)** — ✅
    DONE. Two self-contained WAT helpers (`$__parse_int` / `$__parse_float`) take a string
    `(ptr,len)` → f64 with JS semantics: skip leading whitespace + optional sign, stop at the first
    invalid char, `nan` on no leading digits. `parseInt` honors radix (default 10; `0x` prefix
    auto-detected when radix is 16 or omitted); `parseFloat` reads
    sign/integer/fraction/`e`-exponent. `emitExpr` handler after the Phase-48 `Number.*` block;
    `inferInitType` maps the call to f64. Direct `console.log(parseInt(...))` routes via a local
    (assign-then-log), matching the Phase-52 `in`-operator precedent. Test `53_NumberParse`.
11. **Multi-level interface inheritance (>2 deep)** — ✅ DONE. Root cause was NOT offset math but
    declaration ORDER: `parseStructs` built interfaces in a single source-order pass, so a forward
    `extends` reference (derived declared before its base) silently dropped inherited fields.
    Refactor: collect all interface/object-type decls first, then build in dependency order to a
    fixpoint (new `buildStructDef` helper); in-order chains of any depth already worked. Test
    `53_InterfaceInheritance`.

### Big tracks (the "last items")

12. **Ecosystem — `universalWasmLoader` (polyglot loaders)** — **substantially DONE; updated
    2026-06-22; full detail + publishing matrix in [vision.md](vision.md).** Repos live under
    `D:\Programs\_ProgramExamples\Example_Programs\GithubProjects\universalWasmLoader\` (each its
    own git repo, on `main`, with its own portable `cmem/`). **`SPEC.md` is at 3.0.0** (canonical
    callee-allocated string returns + `cabi_post_<name>`). **ALL TEN ports are implemented on SPEC
    3.0.0 — NO stubs remain (updated 2026-06-22):** `-js` (reference — **PUBLISHED
    `@jrmarcum/universal-wasm-loader@1.0.8`, JSR score 100, provenance true**), `-v` (vlang —
    **PUBLISHED to VPM**), `-zig` (**PUBLISHED to zigistry**), `-py` (**PUBLISHED to PyPI**; string
    tests pass), `-rs` (`cargo test` 24/24), `-jvm` (`gradlew test` 24/24), `-dart` (web-first
    `dart:js_interop`; `dart test -p chrome` 7/7), `-c` (header + vcpkg `ports/` + tests), `-go`
    (wazero, 7/7; commit `c7d9bb0`), `-dotnet` (Wasmtime, 7/7; commit `98dcf2f`). **PUBLISHED so far
    = 4** (`-js`, `-v`, `-zig`, `-py`). **The remaining #12 gap is PUBLISHING the other 6:**
    `-rs`→crates.io (awaiting `CARGO_REGISTRY_TOKEN`), `-go`→pkg.go.dev (needs a `vX.Y.Z` tag),
    `-dart`→pub.dev, `-dotnet`→NuGet, `-jvm`→Maven Central (local tags `v0.1.0`–`v0.1.2` exist but
    it is NOT live yet — pending `io.github.jrmarcum` namespace verification + GPG/Sonatype
    secrets), `-c`→vcpkg port. Each of `-rs`/`-py`/`-jvm`/`-dart` already has **`run:`-only publish
    CI
    - a bump mechanism** (pending owner registry secrets — see vision.md matrix). **Runtime + WASI
      strategy decided 2026-06-15** (in vision.md → "Loader runtime + WASI strategy"): native ports
      use **wasmtime** (`-go` was decided as wasmtime-go but **shipped on wazero**; Zig/`-c` =
      wasmtime C API; `-dotnet` = Wasmtime NuGet) with built-in WASI; web ports (`-js`, `-dart`-web)
      host `WebAssembly` + hand-rolled shim; `-jvm` keeps Chicory + `chicory-wasi`; `-dart`
      dual-backend (web now / native `dart:ffi`→wasmtime later). **SPEC §10 loader capabilities
      (`_initialize` call + minimal WASI-P1 shim) IMPLEMENTED in `-js` 2026-06-15** (suite 24→26;
      lets I/O-using `modc` libraries load in a host with no native WASI). **NOW COMPLETE ACROSS ALL
      10 PORTS (2026-07-05).** The runtime-native ports already carried it: `-go` (wazero
      `wasi_snapshot_preview1.Instantiate`), `-dotnet` (`DefineWasi` + `SetWasiConfiguration`), and
      `-c`/`-zig`/`-v` (shared C header: `wasi_config_new` + `inherit_stdout/stderr` +
      `wasmtime_context_set_wasi`), all with a `_initialize` call. Propagated 2026-07-05 to the four
      that lacked it, each +2 §10 tests (all green): `-rs` (`cc8a5f7`) hand-rolls a `func_wrap`
      `wasi_snapshot_preview1` shim on `Linker<()>` (keeps `Store<()>`, no `wasmtime-wasi` dep) +
      `_initialize` via `get_typed_func::<(),()>`; `-jvm` (`1e1ecb8`) uses `chicory-wasi`
      `WasiPreview1` (`toHostFunctions()` merged with the env functions into one `ImportValues`) +
      `_initialize` via `instance.export("_initialize").apply()`; `-py` (`a51c8da`) uses
      wasmtime-py's built-in WASI (`linker.define_wasi()` + `WasiConfig().inherit_stdout/stderr` on
      the `Store`, WASI namespaces skipped in the no-op stub loop) + `_initialize`; `-dart`
      (`985039f`, the web port — can't use a runtime built-in) hand-rolls the shim in
      `lib/src/wasi.dart` from Dart closures via `.toJS` (web-safe i64 = two i32 words) +
      `_initialize` (`dart test -p chrome` 9/9). Orthogonal / ungated. **CI note:** these repos' org
      allows only `jrmarcum`-owned Actions → publish workflows MUST be `run:`-only (third-party
      `uses:` → `startup_failure`).
13. **#5 Promise/async — ✅ COMPLETE 2026-06-15 (13.1a–13.5; suite 317/317).** Eager microtask
    runtime
    - `hybrid` async lift; Approach B (state-machine) is a future option, not needed for v1.
      **Design doc + full implementation log → [async-design.md](async-design.md)** — Approach A
      (microtask-drain) for v1, expand to B later; settled value laid out as Canonical ABI
      `result<T,E>` (max forward-compat) + opaque handle; runtime = **inline WAT helpers**
      (`needsPromiseRuntime`), NOT a merged capability (the `wasmmerge` `call_indirect` guard
      forbids a callback-bearing merged module) — locked "never introspects callbacks" invariant
      keeps B drop-in; warn-on-unhandled-rejection; mode-scoped deadlock trap. v1 scope =
      async/await + resolve/reject + then/catch/finally + all/allSettled, standalone WASI; 5
      sub-phases (13.1–13.5). **Sub-phases 13.1a + 13.2 + 13.3a + 13.3b + 13.1b + 13.4 (all +
      allSettled) + 13.5 IMPLEMENTED 2026-06-15** (suite 309→**317**, output-verified, zero
      regressions; the entire #13 async track is COMPLETE): 13.1a = `async`/`await` +
      `Promise.resolve`, async-fn-returns-promise (i32/f64), inline runtime, canonical `result<T,E>`
      (test `54_AsyncBasic`); 13.2 = `.then(namedCb)` + microtask queue (FIFO linked list) + drain,
      per-call-site `call_indirect` trampolines, correct
      ordering/FIFO/chained/f64/`await`-of-`.then` (test `55_AsyncThen`); 13.3a = `Promise.reject` +
      rejection→exception (rejected `await` re-throws, caught by `try/catch`) + async-body-throw
      caught free via the eager model (test `56_AsyncReject`); 13.3b = `.catch`/`.finally` rejection
      reactions + `.then(onF,onR)` via a **dual-path** trampoline (`genReactionTrampoline` reads
      `src.disc`: fulfilled→passthrough/`onF`, rejected→`onR(reason:string)`/propagate; `.finally`
      runs on both paths) (test `57_AsyncCatch`); 13.1b = promise-holding-var inner-type tracking
      (`const p = f();
    await p`/`p.then`, i32+f64+aliasing — test `58_AsyncPromiseVar`) +
      **capturing-closure callbacks** for `.then`/`.finally` via an **env-bearing reaction record**
      (functype migrated to `(env,src,result)`; closure dispatched by `call_indirect` through the
      closure ptr — test `59_AsyncClosureCb`); 13.4 = **`Promise.all` + `Promise.allSettled`**
      (array-literal arg, i32/f64) via per-call-site combinators (`all` drains+builds
      `T[]`/first-rejection-wins — test `60_AsyncAll`; `allSettled` never rejects, builds a
      synth-`__settled_<T>` struct array of `{status,value,reason}` — test `61_AsyncAllSettled`);
      13.5 = **lift the `hybrid` async exclusion** (`src/hybrid.ts`) — route async fns into the
      wasic core via an internal `f__impl` + a sync unwrapping wrapper `f` (`return await f__impl`),
      validated by `tests/hybrid/hybrid_fixtures/async_hybrid.ts`. **#13 async track is now
      COMPLETE** (entire v1 Promise API surface + hybrid integration). Full detail in
      [async-design.md](async-design.md).
14. **Own dynamic runtime** (§7-#7) — boxed values + property map + interpreter for the irreducible
    kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation). Gated behind Phase 51
    (done) → unblocked. `javyc` (QuickJS) is the interim fallback until it lands. **Design + full
    log → [dynrt-design.md](dynrt-design.md).** Locked architecture (owner 2026-06-22): value+object
    model first; **tagged heap cell (i32 handle)**; authored in the **wasic TS subset now** (zero
    duplication — reuses wasic's allocator/strings/arrays/num-fmt), extract a shared `rtcore` + go
    hand-WAT only at the interpreter increment; **runtime-only first** (no wasic `any` yet).
    **Increment 1 — value + object model — SHIPPED 2026-06-22** as a shared-heap `modc` capability
    (`tests/wasi/wasm_wasi_bundle/dynrt_bundle/` + pipeline test `18j`): boxed value = 4-slot
    `Int32Array` node `[tag,a,b,c]` (undefined/null/bool/number-as-f64/string/array/object),
    self-managed `Int32Array` growable lists for containers, ~23 exports incl.
    `dynTypeof`/`dynStrictEq` (`===`)/`dynAdd` (`+`). Surfaced 3 wasic gaps (worked around in the
    lib, logged in compiler-bugs.md): str-concat-of-two-calls, Float64Array-elem comparison
    mis-infers i32, and **empty-`[]` is a shared static cap-0 array whose cap-0 grow is broken**
    (the latter hardens any future reconstruct-then-`push`). **Increment 1b — virtual `wasmtk:dynrt`
    import + tree-shake — SHIPPED 2026-06-22** (embedded in `src/wasm/caps_bytes.ts` as a 6th
    registry entry via `gen_caps_bytes.ts`; the `tsbundler` resolver is generic so no resolver
    change; no `modc` step; pipeline test `18k`). **Increment 2a — `eval` of a pure expression
    language — SHIPPED 2026-06-22** (test `18l`): a recursive-descent direct-eval parser authored in
    the subset (authoring decision resolved — continue in the subset, no `rtcore`/hand-WAT needed
    yet); full operator precedence + parens + unary + ternary + string concat → boxed value; added
    the dynamic operators `dynSub/Mul/Div/Mod/Neg/Not/Lt/Gt/Le/Ge`; `parseFloat` works in modc; NO
    new compiler gaps. **Increment 2b — variables + environment + member/index access — SHIPPED
    2026-06-22** (test `18m`): `dynEvalEnv(s, env)` resolves bare identifiers against an env object;
    postfix `.prop`/`["key"]`/ `[i]` (computed index) + `.length`; TOTAL/guarded member access
    (`undefined.x` → undefined, no trap); robust identifier tokenisation; no new compiler gaps.
    **Scope split (rationale recorded):** calls + REAL short-circuit moved to 2c — short-circuit is
    only observable/testable with side-effecting operands (calls), and guarded member access makes
    2b trap-safe without it. **Increment 2c — function values (tag 7) + calls + REAL short-circuit —
    SHIPPED 2026-06-22** (test `18n`): function values dispatch via a STATIC switch on a built-in id
    (NOT a function table — wasmmerge forbids `call_indirect` in a merged module), `dynStdEnv()`
    ships abs/sqrt/floor/ceil/ round/min/max/len + the side-effecting `inc`; `dynApply` dispatcher;
    calls in `parsePostfix` (`f(args)`, any arity, nested); real short-circuit via an `evalLive`
    skip-parse flag guarding the call dispatch (the only side-effecting op), proven observable via
    the `inc()` counter. Surfaced 1 wasic gap (i32 global / typed-array element as an f64 call-arg
    skips the `f64.convert` — bind to a local; logged in compiler-bugs.md). **Increment 2d.1 —
    statements + control flow (`dynRun`) — SHIPPED 2026-06-22** (test `18o`): a statement
    interpreter over the expression evaluator — let/const/var + bare-identifier assignment (mutate
    the env via `dynSet`), if/else, while, `{ }` blocks, expression statements, return; control flow
    uses the DIRECT-eval re-parse trick (while re-sets the cursor to the condition start each
    iteration; dead branches reuse the 2c `evalLive` skip-parse) so no AST is needed; ran factorial
    / fibonacci(10)=55 / nested loops / early return / builtin calls in statements. **Authoring
    decision held — STILL in the subset (no wall → no `rtcore`/hand-WAT needed); NO new compiler
    gaps.** **Increment 2d.2 — user-defined functions + `new Function` — SHIPPED 2026-06-22
    (COMPLETES interpreter increment 2)** (test `18p`): user function values (5-slot cell = body +
    params + defining env), in-source `function name(params){…}` declarations (body source captured
    by a brace scan) + `dynMakeFunc(params, bodyStr, env)` (the `new Function` =
    runtime-code-from-strings capability); a call runs the body via `dynRun` in a fresh scope whose
    parent is the defining env, so RECURSION + closures work via an `envLookup` scope chain; the
    hard part — parser reentrancy — is handled by saving/restoring the shared parser globals around
    the nested `dynRun`. Still authored in the subset (the `rtcore`/hand-WAT path was never forced).
    Known limitation: deep recursion is heap-bound (bump allocator, no GC — `fib(10)` overflows ~2
    pages; `fib(8)` used). **#14 interpreter (2a–2d.2) DONE — the §6 `eval`/`new Function` kernel is
    covered, entirely in the wasic subset.** **Increment 3 STARTED (first wasic-COMPILER change of
    the track): 3.1 — wasic `any` type + auto-merge — SHIPPED 2026-06-22** (test `18q`):
    `mapType("any")→i32` (boxed handle; no test used `any` so safe); the bundler auto-injects a
    synthetic `wasmtk:dynrt` import on `any`/`eval` usage (reuses the virtual-cap merge; `any`-free
    programs unaffected); implicit boxing of literal `: any =` initialisers (source pre-pass) +
    `as`-unboxing via an `anyVars` side-set; new dynrt export `dynStrBytes`. Wiring lesson: the
    bundler rewrites explicit `dynX`→`dynrt_dynX`, so compiler-INTRODUCED calls must be pre-prefixed
    `dynrt_`. **3.2 — operators on `any` — SHIPPED 2026-06-22** (test `18q`): a guarded block in
    `emitExpr`'s binary-op loop routes to dynrt ONLY when an operand is a simple `any` var (else the
    existing typed paths run untouched — the safety invariant for the hottest path); `boxAnyOperand`
    helper boxes the other operand; arithmetic `+ - * / %` → `dynrt_dynAdd/…` (an `any` handle),
    comparisons → raw i32 0/1 (work in conditions), `&&`/`||` → truthiness short-circuit, string
    concat dispatches via `dynAdd`. Full suite stayed green (zero impact on non-`any` code). **3.3 —
    member/index/call on `any` + bare `eval` — SHIPPED 2026-06-22** (test `18q`): a guarded
    any-dispatch block in `emitExpr` routes `x.foo`→`dynrt_dynMember`, `x[i]`→`dynrt_dynIndexValue`,
    `x(args)`→`dynrt_dynCall0/1/2/3` (the library now EXPORTS `dynMember`/`dynIndexValue` + new
    fixed-arity `dynCall0-3` helpers — wasic can't build an args array inline); bare `eval(...)`
    rewritten to `dynrt_dynEval`. All results are `any` handles; single-level forms (chained
    `x.a.b`/`x.a()` use an intermediate var). **3.4 — hybrid `--auto` migration — SHIPPED 2026-06-22
    (COMPLETES increment 3 + the #14 arc):** functions with a TYPED signature + a DYNAMIC
    (`any`/`eval`) body now compile to the wasic+dynrt core (their typed signature marshals to the
    host normally; `any`-signature functions stay in the host — boxed-handle marshalling is a
    follow-up); a **try-compile / fall-back-to-host** ladder (`runHybrid`: compile the full core; on
    failure keep the dynamic-bodied fns in the host and recompile the static remainder — failure
    detected by whether the core `.wit` was produced, since modc doesn't throw). Fixed a real bug
    found here: `compileLibTs` (modc) didn't handle embedded virtual-cap `entry.bytes`/`witText`
    like `compileWasiTs`, so auto-merged `wasmtk:dynrt` failed in the modc core compile — now fixed.
    Verified: `dynamic_hybrid` (eval+any body) routes → `evalScaled(8)=50`;
    `dynamic_fallback_hybrid` falls back to host; `math_hybrid` unchanged. **`hybrid --auto`'s
    dynamic target is now the own runtime, not `javyc`.** **#14 own-dynamic-runtime track — CORE
    COMPLETE.** **Follow-up — any-signature host↔core marshalling — SHIPPED 2026-06-22** (full
    detail in dynrt-design.md): a function with an `any` param/return is now callable from the host
    with real JS values (number/string/bool) — wasic tracks `any` sigs
    (`FuncParam.isAny`/`FuncDef.isAnyResult`; any-params added to `anyVars`), `generateWit` emits an
    `any` WIT marker, the core exports the dynrt box/unbox helpers (`injectDynrtMarshalExports`,
    both compile paths), and bindgen generates `_box`/`_unbox`. Verified end-to-end
    (`tests/wasi/wasm_wasi_bundle/anysig_bundle/`); bindgen 104/104. **Follow-up — hybrid fallback
    refinement — SHIPPED 2026-06-22**: per-function fallback (was all-or-nothing) — on core-compile
    failure, probe each dynamic fn against the static context and move ONLY the failing ones to host
    (`parseHybridFile` `excludeFns` + `probeCompiles` to a cleaned-up `_probe.*` module); safety
    ladders preserved. Verified `tests/hybrid/hybrid_fixtures/dynamic_partial_hybrid.ts`.
    **Follow-up — objects/arrays as `any` STRUCTURAL marshalling — SHIPPED 2026-06-22**:
    objects/arrays now cross the host boundary as real, recursively-converted JS objects/arrays (was
    opaque handles) — dynrt gained `dynObjKeyPtr`/`dynObjKeyLen`/`dynObjValAt`, the marshal-export +
    tsbundler auto-import lists gained the container accessors, and bindgen `_box`/`_unbox` recurse
    on the raw `dynTag` (5=array/6=object). Verified `tests/wasi/wasm_wasi_bundle/anysig_bundle/`
    (`makePoint`→`{x,y}`, `triple`→`[…]`, `sumArr([…])`→sum, `getX({…})`→field). **#14 memory/GC
    track — building a full mark-sweep GC in TESTED PARTS (owner 2026-06-22; the hard part is
    root-finding → an explicit shadow-stack in the mark phase). Part 1 — auto-grow `$__malloc` —
    SHIPPED 2026-06-22** (test `18r`): `memory.grow` by ceil(deficit/64KiB) pages when the bump ptr
    runs past the allocated pages, lifting the fixed ~2-page limit to WASM's multi-GiB limit →
    `fib(15)` (≈1973 interpreter calls) now runs (was overflowing at `fib(10)`); gated to
    executable/WASI modules (a merged lib's malloc is dropped+replaced by the host's, and
    `memory.grow` defeats `detectBumpAllocator` + the wabt-ts merge re-assembly). **Part 2 —
    free-list allocator — SHIPPED 2026-06-22** (test `18s`): `$__free(ptr,size)` links blocks ≥8B
    into a `$__free_list` (storing [size@0,next@4] in the block); `$__malloc` first-fits the list
    before bumping; no splitting v1; executable-only; dormant until the GC sweep calls free in P5;
    tested via new `__malloc`/`__free`/`__heapPtr` wasic intrinsics. **Part 3 — cell registry —
    SHIPPED 2026-06-22** (test `18t`): every value cell flows through `mkCell`/`mkCell5` → recorded
    in a registry list (`__gc_reg`) so P4/P5 can enumerate all allocations; `dynGcCellCount()` hook;
    append inlined to limit recursion-depth cost. Surfaced + fixed a latent wasmmerge bug (it
    clobbered ALL merged mutable globals to 131072, destroying `__gc_reg`'s 0-sentinel → corruption
    at ~3-4k cells; now gated to the non-allocator-unified case — see compiler-bugs.md). **Part 4
    root strategy DECIDED (owner): interpreter SHADOW-STACK** (precise, safe mid-interpretation;
    won't collect `any` handles in arbitrary wasic locals — documented scope). Split into P4a (mark
    mechanics) + P4b (wire shadow-stack). **Part 4a — mark phase — SHIPPED 2026-06-22** (test
    `18u`): `gcMark(root)` recursively marks reachable cells; mark bit = tag bit 8 (uniform, no
    extra storage, doubles as visited-set, cleared by collect()); follows array/object handles +
    user-fn body/params/env; exports `dynGcMarkClear`/`dynGcMark`/`dynGcMarkedCount`. **Part 4b —
    shadow-stack roots — SHIPPED 2026-06-23** (test `18v`): `dynRun` pushes/pops its scope on
    `__gc_roots`; `dynGcMarkRoots` marks from all roots; exports `dynGcPushRoot`/`dynGcPopRoot`/
    `dynGcRootCount`; companion fix — `gcMark` follows an env's parent link (object slot 2) + guards
    the -1 no-env sentinel, so marking one scope keeps the whole lexical chain + closure captures.
    **Part 5a — mark-sweep collect (cells) — SHIPPED 2026-06-23** (test `18w`): `dynGcCollect()` =
    mark-roots → sweep registry → reclaim unmarked cells + compact; dynrt now allocates cells
    through its OWN recycling free list (`dynAlloc`/`dynFreeBlock`/`__dyn_free`, reused blocks
    zeroed) so the GC reclaims into the same pool — NO wasmmerge `$__free` unification needed;
    `dynGcMarkRoots` also marks the interpreter registers; exports `dynGcCollect`/`dynGcFreeCount`.
    **Part 5b — payloads + auto-collect — SHIPPED 2026-06-23; GC TRACK COMPLETE** (test `18x`):
    constructor payload allocs now via `dynAlloc`
    - sweep frees them by tag; `maybeCollect` auto-collects at interpreter statement boundaries
      (adaptive threshold); the evaluator ROOTS mid-expression intermediates (across right-operand
      parses + calls) so recursion like `fib(n-1)+fib(n-2)` is safe. A 10000-iter loop allocating
      ~30000 cells runs in BOUNDED memory (5 live cells after a final collect). **#14 GC done
      (P1–P5b): dynrt runs long-lived dynamic code in bounded memory.** **GC polish SHIPPED
      2026-06-23:** both leaks FIXED — `dynAlloc`/ `dynFreeBlock` round to `GC_MIN_BLOCK=16`
      (short-string/key payloads <16B now recycle — the only growing leak), and `mkCell` frees the
      old registry array on grow. Remaining #14 odds-and-ends: functions-as-`any` stay opaque across
      the host boundary — FUNDAMENTAL (a function is code → must stay a handle, but host-held
      handles can't be rooted across collections → a proxy is use-after-free; deferred pending a
      host-pin mechanism). **Free-list SPLITTING SHIPPED 2026-06-23** (test `18y`): `dynAlloc`
      carves the leftover (≥16B) off an oversized reused block at `cur+size` (closes a slow
      size-mismatch leak; only bit mixed-size workloads). **Adjacency-coalescing SHIPPED 2026-06-23
      as a HYBRID allocator (test `18z`)**: coalesce-on-free hung (re-entrancy cycle), so re-done as
      segregated buckets (16/24/28/32, O(1)) + Tier-2 general (first-fit+split) + a BATCH
      `defragFull` (snapshot, no re-entrancy) triggered proactively (adaptive, amortized) +
      on-demand (free-bytes≥request). Integrity- verified (`dynGcCheckHeap`) through the stress that
      hung the first attempt. Balance: hot path never defrags; large/odd sizes get coalescing
      efficiency. See dynrt-design.md. **Functions-as-`any` — Phase 1 SHIPPED 2026-06-23 (the #14
      final item):** host PIN TABLE (`dynGcPin`/`dynGcUnpin`, marked by `dynGcMarkRoots`; non-moving
      GC) + bindgen `_unbox` tag-7 JS proxy (pins, calls back via `dynApply`, `.release()` +
      FinalizationRegistry); marshal-exports extended; tests `18za` + bindgen
      `testGenBindingsAnyFunction`. **PRODUCER + FULL END-TO-END SHIPPED 2026-06-23:**
      `Function(params, body)`/`new Function` lowers to a new dynrt `dynMakeFn` (auto-merge
      `usesFunction` trigger); modc `getDoubler(): any { return Function("x","return x*2;"); }` →
      bindgen → host `m.getDoubler()(21)` → 42 (bindgen `testIntegrationFnAny`, 119/119). Gotcha
      fixed: trigger matched `Function(` in a COMMENT → now strip comments before sniffing.
      **Core→host functions-as-`any` DONE end-to-end.** Phase 2 (host→core `__hostcall`) still
      deferred. `javyc` stays as the full-JS fallback — see dynrt-design.md.

**Gating summary:** 51 → (13, 14). 52 + 53 COMPLETE; ABI forward-alignment (return side) COMPLETE
2026-06-15; **#13 async track COMPLETE + PUBLISHED as v1.8.0 (2026-06-22)** (13.1a–13.5: full v1
Promise API surface + hybrid lift; suite 317/317; README async surface documented — see lines ~197/
834/1010 of README.md and `CHANGELOG.md`); **#12 loaders — COMPLETE 2026-06-24: all 10
universalWasmLoader ports IMPLEMENTED on SPEC-3.0.0 AND PUBLISHED to their registries** (`-js`→JSR,
`-v`→VPM, `-zig`→zigistry, `-py`→PyPI, `-rs`→crates.io, `-go`→pkg.go.dev, `-dart`→pub.dev,
`-dotnet`→NuGet, `-jvm`→Maven Central, `-c`→vcpkg) — see vision.md. (Remaining #12 polish: SPEC §10
loader-cap propagation, if still open.) **#14 own dynamic runtime — COMPLETE 2026-06-24, NO deferred
pieces.** The whole arc shipped (value model → interpreter → `any` integration → host↔core
marshalling incl. functions → bounded-memory mark-sweep GC → hybrid recycling allocator →
functions-as-`any` producer+proxy+pin, in v1.9.0) — and **Phase 2 (host→core callbacks) SHIPPED
2026-06-24**: a JS function passed INTO the core as `any` is called back via an `env.__host_call`
import (bindgen host-fn table + `dynMakeHostFn`); verified `applyTwice(n=>n+1,10)=12` /
`combine((a,b)=>a*b,6,7)=42` (bindgen `testIntegrationHostFn`). Surfaced+fixed a real wasmmerge bug
(non-WASI imports were spliced after function defs → malformed/OOB; see compiler-bugs.md).
**functions-as-`any` is now bidirectional.** Phase 2 is marshalling, so it does NOT retire `javyc`
(that's the separate Route A track). **`dynrt` is now the PRIMARY dynamic engine; `javyc` is the
FALLBACK.** **Retiring `javyc` from the codebase is a SEPARATE, larger track — FULLY SCOPED in
[dynrt-design.md](dynrt-design.md) "javyc retirement — scoped task breakdown":** `javyc` is now a
thin wrapper around the external Javy/QuickJS CLI whose ONLY wiring is the standalone `wasmtk
javyc`
command (hybrid `--auto` uses dynrt+host, not Javy). Two routes — **Route A (coverage):** grow
`dynrt` via **2e (language: for/for-of/switch/try-catch/arrow/object+array+template
literals/classes/ generators/async — ~10 increments) + 2f (dynamic stdlib + prototype/`this`;
several BRIDGE the existing JSON/Set/Map/RegExp capability libs — ~9 increments) + 2h
(full-dynamic-compile entry + a Javy-parity conformance gate + delete `src/javyc.ts`)** — comparable
in size to the #13 async track; **Route B (policy):** declare full-arbitrary-JS→WASM out of scope
and drop `wasmtk javyc` + the Javy dependency in one small PR (2h only). **The 2g GC prerequisite is
already DONE. ROUTE A CHOSEN (owner, 2026-06-24)** — build order starts at 2e.1 control flow (full
sequence in dynrt-design.md). The other remaining work is the deferred **P2 container** (embed
component type — a terminal wrap; **deferred WAITING FOR BROWSER-NATIVE WASI P2 / Component Model
support** — until browsers load components natively, P1-core stays the browser-compatible artifact
and a P2 wrap buys browser consumers nothing); **#12 loaders COMPLETE 2026-06-24 — all 10 ports
published** (SPEC §10 loader-cap propagation COMPLETE across all 10 ports 2026-07-05); **Go
bindgen** string/aggregate host marshalling **✅ SHIPPED 2026-07-08** (fully canonical vs wasmtime —
existing bindgen marshals TinyGo unchanged; the only fix was SPEC §10 in the bindgen loader), the
**asyncify pass in binaryen-ts + goroutine Go wiring** (✅ **COMPLETE end-to-end 2026-07-08** — the
pass's in-wasm asyncify-import mode shipped in binaryen-ts 1.4.1, and wasmtk's `--lang=go` now
builds goroutine code with `-scheduler=asyncify` + a passthrough shim + `binaryenAsyncify`
(binaryen-ts Asyncify+`-Oz`) → goroutines run with NO external binaryen;
`tests/go_asyncify_tests.ts` `sum: 30`), and the field-reshaping **utility-types** batch — ✅ **DONE
2026-07-08** (`Partial`/`Readonly`/`Required`/`NonNullable`/`Pick`/`Omit`/`Record` shipped in Phase
51.4; `ReturnType`/`Parameters` added via `expandFnUtilityTypes`; `Exclude`/`Extract` deferred — need
string-literal-union types; `51_UtilityTypes.ts`).

## Congruent polyglot-producer goal + ABI posture (added 2026-06-03 — full detail in [polyglot-producers.md](polyglot-producers.md))

**Goal:** unify the **TS/JS, Rust, Zig, Go** toolchains into one congruent wasm capability —
heterogeneous _producers_ converging on the homogeneous middle/back end wasmtk already owns (WASI-P1
core-module output → bindgen ABI → binaryen-ts optimize → wasmmerge/wasmbundle link → wasmtk TS WASI
host). Adding a language = adding a producer, not a toolchain.

| Track                               | Scope                                                                                                                                                                                                                                                                                   | Status / gating                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ABI forward-alignment (stay P1)** | Canonicalize the **in-memory boundary layout** + the **return convention** now (callee-allocated i32-ptr return + `cabi_post_<name>`; route all boundary allocs through `cabi_realloc`); keep P1 WASI imports behind a thin seam. Both P1-legal; makes future P2 a wrap, not a rewrite. | ✅ **return-side IMPLEMENTED 2026-06-15** (wasic `$fn__cabi` shim now returns the i32 ptr + emits `cabi_post_<name>`; bindgen host reads-then-posts; bindgen 104/104, `strings_50` end-to-end). In-memory layout already canonical for shipped types. Only the P2 container remains deferred.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **Go producer (TinyGo)**            | `tinygo build` → wasm → shared optimize/host path. Library-first; stdlib `go` heavier fallback.                                                                                                                                                                                         | ✅ **v1 SHIPPED 2026-06-06, refined 2026-06-07** via `--lang=go` (path defaults to cwd): `init` (scaffold a **wasm library** by default; `--go-target=wasm` for a browser project), `modc` (**WASI reactor library** by default — `-buildmode=c-shared`: no `_start`, exports `//go:wasmexport` funcs, callable via `wasmtk mod`/bindgen; `--go-target=wasm` for a browser module + `wasm_exec.js`), `run` (build wasip1 command + run; **auto-detects** a `.go` file or a dir with `go.mod`, no flag needed). `--go-runtime=tinygo`(default)/`std`. `src/gowasic.ts`. **wasm-opt:** real `wasm-opt` → TinyGo full (incl. goroutines); else (or `WASMTK_GO_BINARYEN_ASYNCIFY=1`) passthrough shim + `-scheduler=asyncify` + **`binaryenAsyncify` = binaryen-ts Asyncify+`-Oz`** → **goroutines work with NO external binaryen** (2026-07-08; binaryen-ts ≥ 1.4.1 in-wasm asyncify-import mode; `tests/go_asyncify_tests.ts`). **2026-06-07 changes:** `wasic --lang=go` REMOVED; `modc --lang=go` flipped browser→reactor-library (the formerly-deferred reactor/library item, now DONE — Go analog of TS `modc`); required a `_initialize` fix in `wasmtk mod`/`run` (reactor exports trap otherwise) + a `syscall/js`-in-library-build hint. Verified `modc --lang=go` lib → `wasmtk mod lib.wasm add 2 3` → 5. **Go string/aggregate bindgen — ✅ SHIPPED 2026-07-08** (the "Go's layout ≠ Canonical ABI" deferral was a mischaracterization). ABI-canonicity verdict: **fully canonical vs wasmtime** — Go strings are UTF-8 `(ptr,len)`; a TinyGo reactor + a one-line `//go:linkname cabi_realloc` wrapper produces the exact canonical string convention (params `(ptr,len)`; returns callee-allocated i32-ptr + `cabi_post`), so the existing language-agnostic bindgen marshals it unchanged. The one host-side gap was that bindgen's generated loader lacked SPEC §10 (WASI shim + `_initialize`) — **fixed in `src/bindgen.ts`** (additive; `bindgen` 131→135, `dync` 3/3). Verified e2e in `tests/go_bindgen_tests.ts` (TinyGo-gated). Fixtures: `tests/go_fixtures/strlib/` (canonical string lib) + `hello.go`. Full detail in [polyglot-producers.md](polyglot-producers.md) § "Go string/aggregate bindgen". **Mergeable Go leaf — ✅ SHIPPED 2026-07-08** (`modc --lang=go --go-target=wasm-unknown` → `buildGoLeaf`): TinyGo's freestanding `wasm-unknown` target has 0 imports + no `memory.grow` (no WASI/scheduler/allocator), so a pure-compute Go library `wasmmerge`s into a wasic/bundle build like a Zig `FixedBufferAllocator` leaf. `mergeOneWasmImport` calls the leaf's `_initialize` (TinyGo guards each export on a runtime-init flag at a fixed page-1 address → merged memory floored at 2 pages); caveat: the host must not use that page (fine for small hosts, else use reactor/bindgen). Verified `tests/go_merge_tests.ts` (7/7): `addi`/`muli`/`clampi` merged into a wasic program run correctly. |
| **asyncify pass in binaryen-ts**    | Port binaryen's `--asyncify` pass into `@jrmarcum/binaryen-ts` so wasmtk can be TinyGo's `wasm-opt` for **goroutine** code too (no external binaryen at all).                                                                                                                           | ✅ **THE PASS IS COMPLETE 2026-07-05** (binaryen-ts repo; **authoritative detail in binaryen-ts `cmem/passes.md` § "Asyncify"**). Faithful port of upstream `Asyncify.cpp` (2030 LOC) into native TS across 5 stages — **S1** runtime support (`2902fca`) / **S2** `analyzeModule` (`3b35d97`) / **S3a** a full `flatten` pass (`2e30ea4`, +`mapChildrenShallow` walk.ts fix) / **S3b** `flowInstrumentFunction` (`62a4573`, +`buildCallResultTypes` flatten fix) / **S4** `localsInstrumentFunction` + intrinsic lowering → RUNNABLE (`c446a3d`) / **S5** wire+register+CLI (`62f0fb0`). Registered `"Asyncify"` (opt-in); **runnable e2e that differentially matches `wasm-opt --asyncify` v130** (suspend/resume, locals survive rewind). Suite **379/379**. Along the way fixed 2 latent binaryen-ts bugs (walk one-level-mapper; flatten `Call.type===none`). **WASMTK-side wiring ✅ COMPLETE 2026-07-08:** (a) binaryen-ts published — 1.4.1 added the **in-wasm asyncify-import mode** (TinyGo imports `asyncify.start_unwind`/… and drives its own unwind/rewind; the pass removes those imports and wires the calls to the synthesized control functions); (b) `gowasic.ts` no-wasm-opt branch now builds `-scheduler=asyncify` + passthrough shim + `binaryenAsyncify` (binaryen-ts Asyncify+`-Oz`). Validated on real TinyGo goroutine output → `sum: 30` (`tests/go_asyncify_tests.ts`, TinyGo-gated). **Goroutine Go now runs with zero external binaryen.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **Zig producer**                    | `zig build-exe` (cleanest native path)                                                                                                                                                                                                                                                  | ✅ **SHIPPED 2026-06-07** (`src/zigwasic.ts`, `--lang=zig`): `init` (wasm-library scaffold), `modc` (freestanding library, `--export=<name>` scanned + binaryen-ts `-Oz`), `run` (`wasm32-wasi` on wasmtk's TS host; auto-detects `.zig`). Comptime-guarded scaffold `main` (Zig analyzes `main` even with `-fno-entry`). See [polyglot-producers.md](polyglot-producers.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **Rust producer**                   | Driver = **`rsxtk`** (owner's Rust WASM toolkit, crates.io `jrmarcum/rsxtk`).                                                                                                                                                                                                           | ✅ **SHIPPED 2026-06-07** (`src/rustwasic.ts`, `--lang=rust`) — **delegates fully to rsxtk**: `init`/`initmod`/`modc`(→build wasm)/`build`(→build wasi)/`run`/`add`/`remove`/`list`/`fmt`/`clean`. Prereq `rustup target add wasm32-wasip1`. No WIT/bindgen yet (stays wasmtk's). Known rsxtk-side gap: `initmod` library + `build`/`mod` expects a `main` (rsxtk template lacks `[lib]`/crate-type — fix in rsxtk). `wasm32-wasip2` is the one native-P2 path — decide before mixing into a P1-merge flow.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **P2 producer (real components)**   | Embed component-type section + emit/wrap via `wasm-tools component new`; migrate WASI P1→`wasi:cli`/`wasi:io`.                                                                                                                                                                          | ⬜ **DEFERRED — waiting for browser-native WASI P2 (Component Model) support.** Browsers load only _core_ modules; a P2 component must be `jco transpile`d back to core wasm + JS glue to run in a browser, so a P2 wrap buys browser consumers nothing today (they'd transpile it back to ≈ wasmtk's current output anyway). It only pays off for _native component-runtime_ consumers (Wasmtime/WasmEdge/WAMR/Spin). Until browsers run components natively, **P1-core + sidecar `.wit` + bindgen stays the primary (browser-compatible) artifact**, and the P2 container is a thin terminal wrap (ABI already forward-aligned) we revisit when browser P2 support lands.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

**Scope pin:** the congruent contract is **WASI Preview 1 / core modules**. Componentization is a
**terminal optional wrap** of the single merged module (`wasm-tools component new --adapt`), not a
merge-tier rewrite. wasmmerge merges P1 modules; never merge already-built _components_ (use `wac`).

**Verified 2026-06-03:** wasmtk itself is NOT a P2 producer — it emits P1 core modules + sidecar
`.wit` + host-side bindgen ABI ("bucket (b)"). Canonical ABI calling convention is now aligned on
both param and return sides (`cabi_realloc` + callee-allocated returns + `cabi_post_<name>`,
2026-06-15); only the P2 container is deferred. See [polyglot-producers.md](polyglot-producers.md)
for the raw evidence.

## "TypeScript as a DLL" vision

Compile TS business logic to `.wasm` libraries and load them from a TS host like C uses a DLL.

| C / DLL                        | wasic                               |
| ------------------------------ | ----------------------------------- |
| `.c` → `.dll`/`.so`            | `.ts` → `.wasm` via `modc`          |
| `.h` header                    | `.wit` (Phase 41, auto-generated)   |
| import lib (`.lib`)            | `.bindings.ts` (Phase 50 `bindgen`) |
| `LoadLibrary`/`GetProcAddress` | `loadModule()` from the binding     |

Prefer `modc` over `wasic` for consumer-facing modules. The DLL model is complete end-to-end.

## Polyglot ecosystem vision (full detail in [vision.md](vision.md))

WASM as the universal binary, WIT as the universal interface contract; any language → component;
components compose regardless of source language; pixi manages toolchains, wasmtk manages WASM.
Staged: Stage 1 `universalWasmLoader` (JS/TS reference loader + SPEC.md + InstancePool) is the
current priority; Stages 2–5 add Rust/Python/Go/JVM loaders, `wasmtk build`/`compose` via pixi,
registry + IDE integration.

## Out of scope without more WASM proposals

Goroutines/cooperative multitasking (needs stack-switching), shared memory + atomics (threads),
channels/select, `os.Exit` non-zero propagation (runner enhancement). And the irreducible dynamic
kernel — `eval`/`new Function`, pervasive `any`, open prototype mutation — stays in `javyc` unless
§7-#7 decides to build wasmtk's own dynamic runtime.

## TypeScript feature gaps compilable later (now scheduled — see "Prioritized execution order")

Utility types (`Partial`/`Record`/…), destructuring in params, `Number.parseInt`/`parseFloat`, `in`
operator, nested destructuring. As of 2026-06-03 these are no longer unscheduled — they are
sequenced into **Phases 51–53** above (foundational subset gates the async + own-runtime tracks).
Done so far: **Phase 51 COMPLETE** (`instanceof` + object spread + param/nested destructuring +
utility types) and **Phase 52 COMPLETE 2026-06-11** (`void` / chained assignment / `in` /
`Array.from`-`of`-`isArray` / `String.fromCodePoint`). A **pre-publish hardening pass (2026-06-12)**
then made the emitter's terminal "give-up" fallbacks record a diagnostic (abort) instead of silently
emitting `0`/`""` — which surfaced + FIXED a real latent bug (brace-less / single-line-braced `else`
chains after a single-line `if` were dropped; regression `15_ElseChainForms`), plus
`instanceof
<built-in>` and dead-code/orphaned-module removal, then a console.log comparison fix
pass (findTopLevelOp paren-tail bug + string ===/!== operands + member-target chained assignment).
Suite **309/309**, bindgen 104/104, jstyper 73/73. **Phase 53 COMPLETE 2026-06-15**
(`Number.parseInt`/`parseFloat` + bare forms; multi-level interface inheritance, declaration-order
independent). **ABI forward-alignment (return side) COMPLETE 2026-06-15.** **#12 loaders — COMPLETE
2026-06-24: all 10 universalWasmLoader ports
(`-js`/`-rs`/`-py`/`-jvm`/`-dart`/`-c`/`-zig`/`-v`/`-go`/`-dotnet`) implemented on SPEC-3.0.0 AND
PUBLISHED to their registries** (JSR / crates.io / PyPI / Maven Central / pub.dev / vcpkg / zigistry
/ VPM / pkg.go.dev / NuGet). **#13 async COMPLETE + PUBLISHED as wasmtk v1.8.0 (2026-06-22; suite
317/317). #14 own dynamic runtime COMPLETE + PUBLISHED (v1.9.0 + Phase 2 in v1.10.0).** Remaining:
the deferred P2 container (browser-native WASI P2 gating); ~~Go bindgen aggregate marshalling~~ (✅
SHIPPED 2026-07-08 — canonical; SPEC §10 bindgen-loader fix); ~~the binaryen-ts asyncify pass +
--lang=go wiring~~ (✅ COMPLETE 2026-07-08 — in-wasm asyncify-import mode in binaryen-ts 1.4.1 +
`gowasic` wiring → goroutine Go with no external binaryen; `tests/go_asyncify_tests.ts`); ~~the
optional utility-types batch~~ (✅ DONE 2026-07-08 — core + `ReturnType`/`Parameters`;
`Exclude`/`Extract` deferred); and the completed **Route A (javyc retirement — v1.11.1)**. Optional #12 polish (SPEC §10
loader-cap propagation) is now COMPLETE across all 10 loader ports (2026-07-05). Full analysis in
CLAUDE.md § "TypeScript Feature Gap Analysis".

**Code-audit sweep 2026-07-08 (three fan-out passes, all suites green — binaryen-ts 401/401, wasi
375/375, bindgen 142, go_bindgen 7/7, hybrid 8/8).** Alongside the Go-bindgen + backend-bump work, a
comprehensive audit of the fresh asyncify/Go/WIT/hybrid/bindgen surface (and this session's own
fixes) found + FIXED: a binaryen-ts `call_indirect` eval-order miscompile + a dropped-`unreachable`
in Flatten; the lossy WIT kebab↔camel round-trip breaking capital-heavy exports (`parseHTML`) in
both the merge overlay and bindgen; and the `hybrid` scanners not being regex/template-aware. Plus
robustness/fail-loud conversions: asyncify now ensures-a-memory / honors `import-globals` / rejects
multi-memory / accepts newline+legacy-alias lists; WIT types fail loud on unknown/aggregate; the
gowasic wasm-opt shim is runtime-agnostic (Bun-safe). New `tests/hybrid_tests.ts` + `kebabcase_50`
bindgen fixture + binaryen-ts asyncify option/memory tests. Details: compiler-bugs.md § "Code-audit
sweep (2026-07-08)", design-decisions.md (hybrid/producer/WIT invariants), binaryen-ts
`cmem/passes.md`.
