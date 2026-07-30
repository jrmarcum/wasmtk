# Legacy `CLAUDE.md` archive (verbatim, 2026-07-30)

> **This is the historical archive, preserved verbatim.** The root `CLAUDE.md` was 228 KB and
> auto-loaded into EVERY session, which is why it was slimmed to a pointer file on 2026-07-30.
> Nothing was deleted: the entire prior contents are reproduced below, unedited.
>
> **This file is git-tracked and read ON DEMAND only** — never auto-loaded. Consult it when you
> need pre-2026-07-30 phase design notes that the curated `cmem/` topic files do not cover.
> The curated files (`compiler-bugs.md`, `design-decisions.md`, `architecture.md`, `roadmap.md`,
> `testing.md`) remain the source of truth; this is history, not policy.

---

# wasmtk — Claude Code Project Memory

> **⚠️ PORTABLE MEMORY HAS MOVED TO `cmem/` (2026-05-31).**
> The authoritative, **portable**, git-tracked project memory now lives in the **`cmem/`**
> folder at the repo root — start at [`cmem/INDEX.md`](cmem/INDEX.md). It is curated into small
> per-topic Markdown files for easy review/revision and, unlike THIS file, it travels with the
> repo (this `CLAUDE.md` is `.gitignore`d, so it is machine-local only and does NOT clone/copy
> to other machines or the USB the way `cmem/` does).
>
> **When saving new project memory, write it into the matching `cmem/` topic file** (and add a
> one-line pointer in `cmem/INDEX.md`). This `CLAUDE.md` remains as the exhaustive historical
> archive and is still auto-loaded by Claude Code each session, but `cmem/` is the source of
> truth being migrated to. Mirror anything important here into `cmem/` over time.
>
> **TRIGGER — "update the project memory" (binding contract; full text in `cmem/INDEX.md`):**
> when the owner says "update the project memory" (or any clear synonym), do BOTH: (1) revise all
> relevant `cmem/` files with the latest decisions/bugs/state and refresh their INDEX pointers;
> and (2) sync `README.md` ONLY where the change is user-relevant (capability surface, install,
> usage, examples, status), keeping README user-facing — internal decision logs / bug post-mortems
> stay in `cmem/`, never in README.
>
> **TRIGGER — "look for code issues" (binding contract; full text in `cmem/INDEX.md`):**
> when the owner says "look for code issues" (or a synonym — "code audit", "audit the code",
> "hunt for bugs"), perform a COMPREHENSIVE audit across BOTH tested AND untested code paths for:
> (1) **workarounds / temporary hacks** (still-needed vs. stale); (2) **dead code** (unused
> methods/fields/helpers, duplicates, orphaned exports — verify each with grep); (3) **bugs**
> (silently-wrong codegen, inverted logic, type-inference gaps, scanner off-by-ones); and
> (4) **fall-throughs** (the worst failure mode — unhandled input emitting a comment-stub + bare
> `0`/empty string instead of erroring; prefer converting silent-wrong to a hard `diagnostics`
> abort, guarding speculative probes with `quietEmit`). Fan out parallel read-only investigators
> per category for large files; report `file:line` + severity; fix the safe ones and keep the full
> suite green (OUTPUT-diff, not just exit codes). Goal: catch issues that won't surface in today's
> tests but will bite a future change.

This file is loaded automatically by Claude Code at every session start.
**Keep this file updated whenever new memories are saved** — but prefer `cmem/` for new content.

## Memory Portability Policy

**Authoritative project memory belongs in `cmem/`** (portable, git-tracked). This `CLAUDE.md`
is `.gitignore`d (machine-local) and serves as the auto-loaded archive. Do not save project
knowledge to the machine-specific store at `~/.claude/projects/.../memory/` — that location is
tied to a single machine and follows neither the repo nor the USB.

The machine-specific memory files for this project must only contain short pointer
stubs that reference sections in this file — never full content. If a new decision,
design note, phase plan, or architectural choice needs to be remembered, add it to
the appropriate section of this file and commit it with the code.

**Rule for Claude:** When asked to save a memory for this project, write it into
this `CLAUDE.md` file directly, then update (or confirm) the machine-specific stub
only as a cross-session index pointer. Never write authoritative project content to
`~/.claude/projects/.../memory/`.

---

## Project Overview

`wasmtk` is a polyglot WebAssembly toolkit for Deno. The primary focus of active
development is `wasic` — a direct TypeScript-to-WASM compiler that emits WAT,
assembles it via a pluggable WABT backend (`npm:wabt` or `jsr:@jrmarcum/wabt-ts/compat`),
and optimizes via a pluggable Binaryen backend (`npm:binaryen` or
`jsr:@jrmarcum/binaryen-ts/compat`) — see § "Pluggable wabt + binaryen backends"
for the deno.json switch. No embedded JavaScript runtime.

**Repository layout:**

```text
wasmtk/
├── main.ts              # CLI entry point (root, JSR entry)
├── deno.json            # Deno config, tasks, JSR exports
├── src/                 # All source modules
│   ├── wasic.ts         # TypeScript-to-WAT transpiler (WasicTranspiler)
│   ├── console_log.ts   # console.log/error/warn WAT emission + number-to-string helpers
│   ├── tsbundler.ts     # Multi-file import bundler (.ts and .wasm imports)
│   ├── wasmmerge.ts     # WAT-level merge of pre-compiled .wasm modules
│   ├── wasmbundle.ts    # CLI bundler for combining multiple .wasm files
│   ├── modc.ts          # Library-mode compilation (no _start, no WASI)
│   ├── javyc.ts         # TypeScript via Javy/QuickJS embedded runtime
│   ├── utils.ts         # WASM runner, WASI shims, CLI command handlers
│   ├── runner.ts        # Standalone WASM/WAT runner utilities
│   ├── args.ts          # CLI argument parsing helpers
│   └── wasm/            # Pre-compiled WASM library assets (Phase 38+)
└── tests/               # Test suite
    ├── wasi_tests.ts     # Full test suite runner (optional 2nd arg = basename regex filter, e.g. "^1_" for phase 1)
    └── wasm_wasi/        # All .ts test files (one per feature/phase)
```

**Key source files:**

| File | Role |
| --- | --- |
| `src/wasic.ts` | Main TypeScript-to-WAT transpiler (`WasicTranspiler` class) |
| `src/console_log.ts` | `console.log/error/warn` emission logic + `$__f64_to_str` / `$__i32_to_str` / `$__i64_to_str` WAT templates |
| `src/tsbundler.ts` | Multi-file import bundler (resolves `.ts` and `.wasm` imports) |
| `src/wasmmerge.ts` | WAT-level merge of pre-compiled `.wasm` modules |
| `src/wasmbundle.ts` | CLI bundler for merging multiple `.wasm` files |
| `src/modc.ts` | Library-mode compilation (no `_start`, no WASI) |
| `src/javyc.ts` | TypeScript via Javy/QuickJS embedded runtime |
| `main.ts` | CLI entry point |
| `src/utils.ts` | WASM runner / WASI shims |
| `src/wasm/` | Pre-compiled WASM library assets (Phase 38+; e.g. `mathlib.wasm`) |
| `tests/wasi_tests.ts` | Full test suite runner (optional 2nd arg: basename regex filter) |
| `tests/wasm_wasi/` | All `.ts` test files (one per feature/phase) |

---

## Compiler Phase Status

### Completed (phases 1–50 + sub-phases)

All phases 1–50 are complete plus 5e/5f/5g/5h/6d/12b/13b and all listed bug fixes.
**Historical baseline under npm:wabt + npm:binaryen: 446/446 PASS (270 wasic + Go-by-Example tests + 103 Phase 50 bindgen tests + 73 jstyper tests as of 2026-05-25). Stage 0 Canonical ABI alignment complete. Stage 0.5 dual JSR /compat migration complete. Stage 0.6 allocator unification in wasmmerge complete (2026-05-30).**
**Current result under dual JSR /compat (`jsr:@jrmarcum/wabt-ts@^1.3.2/compat` + `jsr:@jrmarcum/binaryen-ts@^1.3.3/compat`) with allocator unification + Stage 0.7 Set/Map/Date/JSON/RegExp capabilities (2026-06-02):** full `tests/wasm_wasi` suite **278/278** (incl. capability pipelines `18c`–`18g` = Set/Map/Date/JSON/RegExp, all PASS), `core_` **33/33**, jstyper **73/73**, bindgen **103/103** — curated current memory now lives in `cmem/` (see `cmem/capabilities.md`, `cmem/compiler-bugs.md`). RegExp surfaced a merge bug (OOB `charCodeAt` in a non-short-circuit `&&` loop condition) that is **now FIXED 2026-06-02** by making wasic short-circuit `&&`/`||` (the library workaround was removed; the natural form passes merged). One narrow OPEN bug remains — the single-physical-line brace `if {…}` form (does not affect the suite); see `cmem/compiler-bugs.md`. wabt-ts 1.3.0 (bumped from 1.2.9) fixed a folded-`(call)`-before-`(return)` encoder bug, recovering `15_panic` and `18_Multi-Scope`. **The 7 long-standing failures are now ALL FIXED (2026-06-02):** (a) `5e_MixedSignatures`, `19_NestedDU`, `19_VariantMax` — value-returning functions ending in a void `if/else` where all paths `return` left an empty stack at the implicit fallthru (V8 strict-validation reject); fixed in `wasic.ts` by rewriting the terminal void `if` into a value-producing `(if (result T) …)` (new `fixTerminalFallthru` + `tokenizeWat`/`parseWatNodes`/`serializeWat`/`watNodeToValue` helpers — appending `(unreachable)` does NOT work because Binaryen `-Oz` strips it). (b) `38_MathExpLog/Hyperbolic/Trig/Combined` — the "f64→i32 truncation" was a *symptom*: the real cause was **wabt-ts 1.3.0 parsing hex-float literals (`0x1.…p±N`) as 0** via JS `parseFloat`, so every merged-`mathlib` constant was 0 → garbage results → NaN/Inf trapped `$__f64_to_str`'s `i64.trunc_f64_s`. Fixed upstream in **wabt-ts 1.3.1** (`parseHexFloatValue` reconstructor; deno.json `^1.3.0`→`^1.3.1`). Two codegen bugs from earlier revisions were fixed 2026-05-30: (a) `return expr as unknown as i32` stray `f64.convert_i32_s`; (b) modc importing an unused `fd_write`. All 15 Stage-0.5 toolchain bugs (10 wabt-ts, 5 binaryen-ts) plus the 1.3.0 call-before-return, 1.3.2 merge-optimizer, and 1.3.1 hex-float fixes are landed — see § "Pluggable wabt + binaryen backends" for tables.
(`ExternalMapping_11b.ts` upgraded from `@expect-fail: compile` to a fully passing test in Phase 40.)

**Test file naming convention:** all files in `tests/wasm_wasi/` use the `NN_Label.ext` format (phase number first) so directory listings sort by phase. 1,012 files renamed from `Label_NN.ext` → `NN_Label.ext` on 2026-05-24; 22 orphan files assigned phase numbers; 250 duplicate unversioned build artifacts deleted. Runner (`wasi_tests.ts`) scans by glob — no hardcoded paths affected.

Phase 22 stress tests (added 2026-05-25 — enum value expression evaluation and heterogeneous enum edge cases):

- `22_NUmericEvaluationsAndFlagsShift.ts` — bit-flag enum with `Read = 1 << 0`, `Write = 1 << 1`, `Execute = 1 << 2`, `Admin = Write | Execute`, `MaxBits` (auto-increment from computed value `Admin = 6` → `7`); verifies enum-member RHS expressions are evaluated at compile time with prior-member references substituted; prints `Admin Flag Literal: 6`, `MaxBits Auto Literal: 7`, `Bitwise Mask Verification: 1`
- `22_HeterogeneousAndMixedStringEnum.ts` — mixed enum `DeployEnv { Dev = "DEVELOPMENT", Staging = "STAGING", Prod = "PRODUCTION", Local = 0 }`; `env: DeployEnv` function parameter compared with `=== DeployEnv.Prod` and `=== DeployEnv.Local`; verifies string members get synthetic integer tags so i32 comparisons disambiguate Prod from Local while `console.log(DeployEnv.Prod)` still prints `"PRODUCTION"`
- `22_EnumObjectMemberCompoundMap.ts` — `enum DeviceStatus { Offline, Initializing, Online, Maintenance }` used as a class field type; constructor `this.status = DeviceStatus.Offline`; method `updateStatus(next: DeviceStatus)`; verifies enum as a class field with correct read/write through `this.status`
- `22_CombinedStressTest.ts` — `const enum Threshold` + bigint literal arithmetic (`150n * 2n`) + `BigInt(Threshold.High)` cast; verifies const enum members are inlined in BigInt comparison context

**Phase 22 bug fixes (2026-05-25):**

1. **Enum value expression evaluation** (`wasic.ts` `parseEnums` ~line 2384): The old regex `/(\w+)\s*(?:=\s*(?:(-?\d+)|"([^"]*)"|'([^']*)')\s*)?\s*,?/g` only captured plain integer literals or string literals. For expressions like `Read = 1 << 0` it matched the leading `1` and treated the trailing `<< 0` as fake members — `Admin = Write | Execute` resolved to `Write | Execute = 2 | 3 = 3` (member indices, not values), and `MaxBits` auto-incremented from the wrong prior. Rewrote `parseEnums` to: (a) strip line/block comments, (b) split the body at top-level commas via depth-tracked scan, (c) parse each member as `name (= rhs)?`, (d) call new private helper `evalEnumExpr(rhs, resolved)` which substitutes already-resolved member identifiers with their numeric values, then evaluates the expression via `Function("\"use strict\"; return (${sub});")()` with `| 0` i32 coercion. Now supports `<<`, `>>`, `>>>`, `|`, `&`, `^`, `+`, `-`, `*`, `/`, `%`, parens, and references to any previously-defined member of the same enum.

2. **Heterogeneous enum comparison** (`wasic.ts` `parseEnums` third pass + `console_log.ts` `parseSingleArg` ~line 405): When an enum mixed string and numeric members, the string members previously had no `enumValues` entry. `emitExpr("DeployEnv.Prod")` fell through to the comment-stub fallback `(i32.const 0)`, so `env === DeployEnv.Prod` and `env === DeployEnv.Local` both compared against 0 — every `printEnvHeader` call took the first branch. Added a third pass in `parseEnums` that detects heterogeneity (both string and numeric members present in the same enum) and assigns synthetic integer tags to the string members starting at `max(numeric_values) + 1` (skipping over any explicit numeric values). The string value is still tracked in `enumStringValues` for display contexts. To preserve display semantics, `parseSingleArg` in `console_log.ts` now checks `enumStringLookup` BEFORE `enumLookup` — so `console.log(DeployEnv.Prod)` still prints `"PRODUCTION"` while `env === DeployEnv.Prod` resolves to a stable i32 tag comparison. Pure numeric and pure string enums are unaffected by the third pass.

Phase 21 stress tests (added 2026-05-25 — tuple destructuring and embedded tuple field edge cases):

- `21_HeterogeneousTypeOffset.ts` — `const record: [i32, f64, boolean] = [42, 3.14159, true]` then `const [id, value, active] = record`; verifies tuple destructure with mixed i32/f64/bool fields and natural alignment
- `21_SkippedElementsAndGaps.ts` — `const [coordX, , coordY] = coordinates` with positional gap (`, ,`); verifies that empty bindings advance the index without consuming a field slot — coordY must read index 2 (value `20`), not index 1 (`999`)
- `21_NestedCompoundTuple.ts` — `class NodeMetric { bounds: [i32, i32]; }` embedded tuple class field; constructor `this.bounds = [min, max]` writes inline; `const [lower, upper] = metric.bounds` destructures the embedded tuple via pointer arithmetic on the class layout

**Phase 21 bug fixes (2026-05-25):**

1. **Skipped elements (gaps) in destructuring lost positional index** (`wasic.ts` lines ~6300, ~6518, ~11128, ~11306, ~12325, ~12404): All four destructure paths used `.split(",").map(b => b.trim()).filter(Boolean)`, which removed empty-string bindings produced by `[a, , b]` syntax. The fix removes `.filter(Boolean)` and adds an `if (b === "") continue;` (or `idx++; continue;` in the array path) guard inside the loop. The positional index now advances over gaps while skipping the no-binding emission. Affects `arrDestructMatch`/`arrDestructPre`/`arrDestructPre2` (array source, dynamic/static `arrayVars`) and `tupleArrDestructStmt`/`tupleDestructPre`/`tupleDestructPre2` (tuple source, `structVars`).

2. **Embedded tuple fields in classes** (`wasic.ts` `parseClasses` ~line 2842): Class fields declared with tuple-literal type syntax (`bounds: [i32, i32]`) are now recognized via a new regex `(\[[^\]]+\])` tried before the existing `[\w\[\]]+` pattern. When matched, the field is recorded inline (not as a heap pointer) at `tdef.totalSize` bytes with `tupleTypeName` set on the `StructField`. Alignment uses the first tuple element's natural size. `StructField` interface gained `tupleTypeName?: string`.

3. **Constructor `this.bounds = [min, max]` writes per-element inline** (`wasic.ts` `thisWriteMatch` handler ~line 6946): When the assigned field has `tupleTypeName`, the RHS is parsed as a tuple literal and each element is emitted as `(i32.store offset=fieldOff+tf.offset (local.get $__self) val)`. Avoids the dynamic-array heap allocation that previously emitted an undeclared `$__arr_tmp` local.

4. **`const [a, b] = obj.field` destructure from a class's embedded tuple** (`wasic.ts` new `tupleFieldDestructStmt` ~line 6517 + new `tupleFieldDestructPre`/`tupleFieldDestructPre2` in both pre-scans ~lines 11128 and 12325): Detects `[bindings] = (\w+)\.(\w+)` where the receiver is in `classVars` and the named field has `tupleTypeName`. Emits per-field `(local.set $bind (loadOp offset=cf.offset+tf.offset baseWat))` reads from the class instance pointer. Pre-scans declare each binding local with the tuple field's WAT type. WAT syntax: `offset=N` must precede the address argument inside `i32.load`/`f64.load`/etc.

Phase 20 stress tests (added 2026-05-24 — array rest destructuring edge cases):

- `20_RestBufferSplitting.ts` — `const [alpha, beta, ...omega] = source` where `source: i32[] = [100, 200, 300, 400]`; verifies static array element extraction with correct 8-byte header offset; rest array correctly holds elements 2 and 3; `omega.length === 2`, `omega[0] === 300`, `omega[1] === 400`
- `20_EmptyRestAllocationAndSafety.ts` — `const [first, second, ...remainder] = smallPair` where `smallPair: i32[] = [55, 66]`; rest array is empty (length=0, capacity=8 baseline); verifies `.push(77)` correctly expands the empty rest array without heap corruption; post-push `remainder.length === 1`, `remainder[0] === 77`
- `20_NestedDestructuringAndOjectMix.ts` — `const [leadPoint, ...trailingPoints] = points` where `points: Coordinate[] = [{ x: 1, y: 10 }, ...]`; multi-line struct array literal in function body (joined by `parseFunctions` body-line joiner); `leadPoint.x` resolves via `structVars` registered in `arrDestructPre`; `trailingPoints[0].y` resolves via new `arr[idx].field` handler in both `structLookupFn` closures and `parseSingleArg`

**Phase 20 bug fixes (2026-05-24):**

1. **Static array element offset in destructuring** (`wasic.ts` line ~6313, ~6344): `arrDestructMatch` was loading from `srcInfo.ptr + idx * elemSize` (header address) instead of `srcInfo.ptr + 8 + idx * elemSize` (elements start at +8 past the 8-byte [length, capacity] header). Fixed by adding `+ 8` at both the simple-binding and rest-copy load sites.

2. **Multi-line array literal joining in function bodies** (`wasic.ts` `parseFunctions` body joining loop ~line 1504): Added a new branch after the `return function()` joiner: when a `var/let/const` declaration line has an unclosed `[`, subsequent lines are joined until brackets balance. This allows `const points: Coordinate[] = [\n  { x: 1, y: 10 },\n  ...` to be processed as a single line by the `arrPre` regex.

3. **`structTypeName` propagation in `arrDestructPre`** (`wasic.ts` ~line 11250): When the source array has `structTypeName` set (e.g. `points` is `Coordinate[]`), the pre-scan now: (a) registers simple bindings (e.g. `leadPoint`) in `structVars` with the struct def so `leadPoint.x` resolves, and (b) passes `structTypeName` through to the rest binding in `arrayVars` so `trailingPoints[0].y` can resolve via the struct array element field access path.

4. **`arr[idx].field` access in console.log** (`console_log.ts` `parseSingleArg` + `wasic.ts` both `structLookupFn` closures): Added a new pattern for `arr[idx].field` in `parseSingleArg` that calls `structLookup("arr[idx]", "field")` with the bracket form as the virtual varName. Both `structLookupFn` closures (console.log path at ~7599 and console.error path at ~7823) now handle `vn.match(/^(\w+)\[([^\]]*)\]$/)`: extracts array name + index, looks up `structTypeName` from `arrayVars`, computes `(i32.load elemAddr)` as the struct pointer, then loads the named field from that pointer.

Phase 19 stress tests (added 2026-05-24 — discriminated union and polymorphic array edge cases):

- `19_NestedDiscriminantUnions.ts` — multi-level DU nesting: outer `Message` DU (text/image/system) each containing an inner DU; `formatMessage(msg)` switch dispatches on outer tag then accesses inner tag/fields; verifies correct nested tag comparison and field access across two switch levels
- `19_PolyMorphicUnionArrayMutation.ts` — `Shape[]` array of mixed DU values (circle/rect/triangle); `scaleShapes(arr, factor)` mutates each element's radius/width/height by `factor` in-place; `sumAreas()` computes total area via per-variant formula; verifies element mutation and field reads after mutation
- `19_VariantMaximumMemoryAlignment.ts` — DU super-struct with all six field types (i32/f64 combinations); `maxAlignDu` type exercises maximum struct padding alignment; verifies all field offsets, `i32.load` vs `f64.load` dispatch, and that the struct layout correctly handles mixed-width fields

Phase 18 stress tests (added 2026-05-24 — multi-scope scale and WASM merge):

- `18_Multi-ScopeScaleAndMemoryLongevityTest.ts` — 350+ line stress test exercising: `Array.from({ length: N }, () => [])` 2D array init, `Array<{ namePtr: number; typeId: number; scopeId: number; addr: number }>` inline anonymous struct arrays, `const target = arr[i]` struct-variable registration, `variableRecords.push({ ...runtimeFields })` runtime struct literal emission, multi-scope symbol table with depth tracking, and a `wasm_import("18_symbol_table.wasm")` external module with mutable `$free_ptr` global; verifies zero delta between TypeScript and WASM output
- `18_WasmImportMerge.ts` — `@test-pipeline` pipeline test: runs `modc` on `18_MathLibrary_Modc.ts`, then `wasic` on `18_MainApplication_Wasic.ts` (which imports the `.wasm`), then `wasmbundle` to combine into `18_WasmBundle.wasm`, then `run`; verifies end-to-end Phase 18 bundle pipeline

Phase 16 stress tests (added 2026-05-24 — generic monomorphization edge cases):

- `16_NestedMonomorphization.ts` — two concrete monomorphized classes `BoxI32` / `BoxF64` (avoids unsupported generic `class Box<T>`); `sumBoxes` helpers use local temporaries (`const av: i32 = a.unwrap()`) to prevent greedy `dotCallExprMatch` from consuming method arguments; verifies independent concrete copies of `.unwrap()` and arithmetic over both types
- `16_GenericInterfaceMappingsAndClosures.ts` — non-capturing named function `addOffset` reads module-level global `const gOffset: i32 = 5`; passed as bare function reference to higher-order functions using the `funcTypeVars` call_indirect path; capturing closures avoided (bare table-index dispatch is incompatible with closure struct dispatch on the funcTypeVars path)
- `16_DeepGenericConstraintResolution.ts` — uses Phase 47 class inheritance: `class Item` (base, `weight: i32`, `getWeight(): i32`) → `class HeavyItem extends Item` with `super(weight)` and `override getWeight()` returning `this.weight * 2`; standalone concrete functions `inspectItem(item: Item)` and `inspectHeavy(item: HeavyItem)` replace unsupported `class Scale<T extends Measurable>`

**`expandGenerics` regex fix (2026-05-24, `src/wasic.ts` line 2153):** `restMatch` regex changed from `[\w<>, ]+?` to `[\w\[\]<>, ]+?` — adds `[` and `]` to the character class so generic functions with array return types (e.g. `function mapArray<T, U>(arr: T[], fn: (x: T) => U): U[]`) are correctly recognized during template extraction in `expandGenerics()`. Without this fix, any generic with an array return type was silently skipped; the call site was not rewritten and the raw TypeScript token was emitted as incorrect WAT (comparison operators instead of the intended function call).

Phase 15 stress tests (added 2026-05-22 — exception handling edge cases):

- `15_TestCase1-NestedEscalation.ts` — three-level nested try/catch escalation (success and failure paths); `trace` score accumulation via arithmetic on each level; prints `Final Trace Score: 17` (success) and `Final Trace Score: 12` (failure path with `Level 3 Failure`)
- `15_LexicalShadowing_Stress.ts` — `catch (e)` where `e` shadows an outer string variable `const e: string = "Outer String"`; inner catch re-throws; outer catch uses `outerError` and reads the shadowed `e`; verifies `Shadow Check: Outer String` (not `Inner Literal Error`)
- `15_IdiomaticCatch_Stress.ts` — `throw new Error("msg")` caught and converted via `e instanceof Error ? e.message : String(e)` and `String(e)`; verifies `Ternary Result: Structural Error Message` and `String Result: Error: Structural Error Message`

Phase 43 test files (added 2026-05-14):

- `BasicStringArrParam_43.ts` — `strIndexOf(arr: string[], v: string): i32` and `strIncludes(arr: string[], v: string): boolean`; verifies basic string array param + string scalar param; prints `2\n-1\ntrue\nfalse`
- `StringArrHigherOrder_43.ts` — `anyMatch`, `allMatch`, `countMatch` with `pred: (s: string) => boolean`; callbacks `startsWithA` and `isLong`; verifies `call_indirect` dispatch with string ptr+len pair; prints `true\nfalse\ntrue\nfalse\n2`
- `StringArrReturn_43.ts` — `strFilter(arr: string[], pred: (s: string) => boolean): string[]`; returns new dynamic string array; verifies `.length` and `rWords[0] === "red"` via `$__str_cmp`; prints `3\n4\ntrue`
- `Phase43Combined_43.ts` — all Phase 43 patterns together: `strIndexOf`, `strSome`, `strEvery`, `strFilter`; two callbacks `startsWithB` and `longerThan4`; prints `1\ntrue\nfalse\n3\n2\ntrue`

Phase 44 test files (added 2026-05-14):

- `defer_44.ts` — `Array<() => void>` deferred call queue; `defer(fn)` pushes closures via `deferred.push(fn)`; `runDeferred()` calls each via `deferred[i]()` in reverse; `deferred.length = 0` clears the queue; capturing closures `defer(() => console.log(n))` where `n` is a for-loop variable; prints `counting\ndone\n4\n3\n2\n1\n0`
- `exit_44.ts` — shows `throw`/deferred semantics; `defer(() => console.log("!"))` registered but never executed (no `runDeferred()` call); prints `exit status 3`

Phase 41 test files (added 2026-07-14):

- `BasicWitGen_41.ts` — exports `add`, `multiply`, `square`; verifies basic WIT export declarations with i32/f64 params/returns; prints `7`
- `WitReturnTypes_41.ts` — exports `getInt` (i32), `getFloat` (f64), `getFlag` (bool), `noReturn` (void); verifies all four WIT return type variants; prints `42`
- `WitWithExternalImports_41.ts` — `declare const host: { log(ptr: i32): void; getTime(): i32 }` + exports `logMessage`/`currentTime`; verifies WIT includes both `import` section (Phase 40 externals) and `export` section; prints `100`
- `Phase41Combined_41.ts` — `declare interface Allocator` + `declare const allocator` + four exports (`allocate`, `release`, `clamp`, `isPositive`); full combination of Phase 40 imports + Phase 41 WIT generation; prints `55`

Phase 39 test files (added 2026-07-14):

- `JstyperBasic_39.ts` — jstyper output pattern: i32 arithmetic (`add`, `multiply`, `square`); verifies wasic compiles explicit i32/f64 typed functions from JS-style bodies
- `JstyperF64_39.ts` — jstyper `number→f64` mapping: `area`, `perimeter`, `hypotenuse` all with f64 params/returns; verifies f64 arithmetic and `Math.sqrt` in converted functions
- `JstyperMixed_39.ts` — mixed i32/f64/bool functions: `clamp` (f64), `countDigits` (i32 with while loop and integer division `|0`), `inRange` (bool); covers branching and loops in converted bodies
- `Phase39Combined_39.ts` — full combination: `factorial` (i32 recursive), `isPrime` (i32 loop + bool), `average` (f64), `gcd` (i32 Euclidean), `lerp` (f64); verifies recursive functions, nested loops, and all numeric types in jstyper output

Phase 39 unit tests (in `tests/jstyper_tests.ts` — separate runner, 73/73 PASS):

- JS function parsing: regular functions, arrow expression bodies, arrow block bodies, nested braces
- `.d.ts` parsing: `export declare function`, `declare function`, `number`/`any` types
- Skeleton generation: `--dts-only` output format, zero-param functions, export vs non-export
- `generateTypedTs`: basic i32/f64, `number→f64` mapping, missing declaration warning
- any-policy modes: `skip` (function excluded + warning), `warn` (included with i32 + warning), `default` (included with i32, silent)
- File I/O: `--dry-run` (file not written), `--dts-only` (skeleton written), full pipeline (basicmath, numbertypes), `--any-policy=skip/warn` pipeline

Phase 36 test files (added 2026-05-04):

- `BasicConditionalType_36.ts` — generic conditional type `Toggle<T>` as variable annotation; `Toggle<i32>→f64`, `Toggle<f64>→i32`, `Toggle<string>→i32`
- `ConditionalTypeParams_36.ts` — conditional type `NumCond<T>` as function parameter type; `NumCond<i32>=f64` receives f64 arg, `NumCond<f64>=i32` receives i32 arg
- `ConditionalTypeNonGeneric_36.ts` — three non-generic conditional types evaluated at declaration time: true-branch (`i32 extends i32 → string`), false-branch (`string extends i32 → f64`), numeric (`f64 extends number → i32`); used as variable and function-param types
- `Phase36Combined_36.ts` — generic `AsFloat<T>` + two non-generic types (`AlwaysI32`, `AlwaysF64`); conditional types as variable annotation, function param, and return type; `area(w, h)` function with all-f64 signature derived from `AsFloat<i32>`

Phase 38 test files (added 2026-07-14):

- `MathTrig_38.ts` — sin, cos, tan, atan, atan2, asin, acos via external `mathlib.wasm`
- `MathExpLog_38.ts` — exp, log, log2, log10, cbrt, expm1, log1p via external `mathlib.wasm`
- `MathHyperbolic_38.ts` — sinh, cosh, tanh, asinh, acosh, atanh via external `mathlib.wasm`
- `MathRandom_38.ts` — Math.random() xorshift64 PRNG, verifies 5 values land in [0, 1)
- `Phase38Combined_38.ts` — Pythagorean identity, exp/log inverses, hyperbolic identity, all extended Math functions together; tests compound expressions with module-level f64 globals as arguments

Phase 37 test files (added 2026-07-14):

- `FlatArray_37.ts` — `flat()` on `i32[][]`: basic 3-row flatten, single-row, rows of length 1, dynamic rows with prior push
- `FlatMapArray_37.ts` — `flatMap(fn)` with `expand(v)→[v,v*2]`, singleton `wrap(v)→[v+10]`, triple `triple(v)→[v,v*2,v*3]`
- `Phase37Combined_37.ts` — `flat()` + `flatMap()` together; `flat()` result fed into `slice()`; `flatMap()` result fed into `map()`

Phase 35 test files (added 2026-05-03):

- `BasicTypeof_35.ts` — `typeof x === "number"` / `!== "string"` comparisons (compile-time constants), `const t: string = typeof x` assignment, `console.log(typeof x)` for i32/f64/string/bool variables
- `KeyofBasic_35.ts` — `key: keyof T` function params treated as `string`; `const k: keyof T = "field"` variable; string comparison on keyof variables; `matchWidth(key: keyof Config): bool` predicate
- `TypeofInConditions_35.ts` — `typeof` in nested function bodies, `console.log(typeof x)` directly, `storeTypes` pattern with two typeof assignments, else-branch when typeof is false
- `Phase35Combined_35.ts` — `keyof T` params + `typeof` comparisons + typeof-to-string assignment all together; `describeVar` prints all four type strings; `applySettings(key: keyof Settings, val: i32)`

Phase 34 test files (added 2026-05-02):

- `BasicTypePredicate_34.ts` — DU type predicates, `s is Shape` syntax, `bool` return, true/false in `console.log`, `if`/`else` usage with `!` negation
- `TypePredicateNarrowing_34.ts` — interface inheritance narrowing; `e is Player`, `e is Enemy`; `processEntity(e: Entity)` accesses derived-only fields after narrowing
- `TypePredicateFunc_34.ts` — three-way else-if chain with `isCar`/`isTruck`/`isBike` predicates; inherited and derived field access in each branch
- `Phase34Combined_34.ts` — DU predicates (`Expr`) plus interface hierarchy predicates (`Node/LeafNode/BranchNode`); combined in `main()`

Phase 33 test files (added 2026-05-01):

- `BasicIntersection_33.ts` — two-interface merge (`Nameable & Sizeable → Widget`), struct literal init, field access at top level
- `IntersectionFunc_33.ts` — intersection type as function parameter and field access in function body
- `IntersectionThreeWay_33.ts` — three-way merge (`HasA & HasB & HasC → ABC`), mixed i32/f64 fields, `as f64` cast in arithmetic
- `Phase33Combined_33.ts` — chained intersection (`Particle & Color → ColoredParticle`), base-typed function param with derived-type arg, two separate struct vars

Phase 32 test files (added 2026-04-30):

- `BasicDiscUnion_32.ts` — shape DU (circle/rect), switch narrowing, `area()`, `getRadius()`, per-field console.log
- `DiscUnionIfElse_32.ts` — event DU (click/keypress/scroll), if/else if narrowing, `isClick()` helper
- `DiscUnionMixed_32.ts` — value DU (int/float/pair), mixed i32/f64 fields, `as f64` casts on struct fields and compound expressions
- `Phase32Combined_32.ts` — Shape + Result + Move unions, switch and if/else narrowing, `isCircle()`, `isOk()`, `applyMove()`

Phase 31 test files (added 2026-04-29):

- `Int32Array_31.ts` — literal-length creation, element r/w, `.length`, `.byteLength`, `console.log(arr)`, literal-array creation, `.fill(val)`, `.fill(val, start)`, `.fill(val, start, end)`
- `Float64Array_31.ts` — literal-length creation, element r/w, `.byteLength`, `console.log(arr)`, literal-array creation, `.fill(val)`, `.fill(val, start, end)`
- `TypedArrayAdvanced_31.ts` — runtime length (`new Int32Array(n)`), Uint8Array creation/r/w, Uint8Array literal init, `.set(src)`, `.set(src, offset)`, function accepting `Int32Array` param
- `Phase31Combined_31.ts` — Int32Array + Float64Array + Uint8Array together, fill on both, arithmetic with TypedArray elements (`nums[0] + nums[1] + nums[2]`)

Phase 30 test files (added 2026-04-27):

- `Namespace_30.ts` — basic namespace with functions (add, multiply, square) and constants (PI, TWO); constant in arithmetic; call-as-statement
- `NamespaceAdvanced_30.ts` — two namespaces (Geometry, Stats); namespace constants in nested calls; multi-namespace interaction
- `InterfaceInheritance_30.ts` — `Player extends Entity`, `Enemy extends Entity`; inherited + own field access, mutation, base-typed function params
- `ShorthandProps_30.ts` — shorthand in function returns (`return { x, y }`) for both f64 and i32 struct types; field access on returned structs
- `Phase30Combined_30.ts` — all three Phase 30 features together (Vector namespace, Particle extends Base, Vec2 with shorthand props)

Phase 29 test files (added 2026-04-24):

- `ClassEnhancements_29.ts` — original combined test (string enum + static field + getter/setter)
- `StaticFields_29.ts` — static field init, constructor increments, f64 static field, reset via static method, direct write
- `GettersSetters_29.ts` — f64/i32 getter+setter pairs, computed getter, setter with clamping logic
- `StringEnums_29.ts` — string enum declaration, direct log, variable assignment, comparisons, mixed numeric+string enums
- `ClassEnhancementsCombined_29.ts` — all three Phase 29 features together across two classes

See `README.md` Completed Phases table for full detail per phase.
Summary of key milestones:

- Core language (functions, control flow, types, operators, enums, templates)
- Closures: first-class functions (5e), heap closures/factories (5f), named function-type aliases (5g), shared mutable captures with heap-boxing (5h)
- Arrays: static + dynamic, growth, methods (indexOf/includes/slice/forEach/map/filter/find/reduce), 2D arrays (6d), rest/spread (13)
- Extended array methods: every, some, findIndex, at, reverse, fill, join, sort (28)
- `flat()` / `flatMap(fn)`: one-level flatten of `T[][]`; map-then-flatten of `T[]` via named callback (37)
- String arrays as function parameters: `arr: string[]` params, `s: string` params in callbacks, `call_indirect` for `(s: string) => boolean` predicates, string array returns as i32 pointer (43)
- Function pointer arrays: `Array<() => void>` (and parameterized variants); `push(fn)` stores closure struct ptrs; `arr[i]()` dispatches via `call_indirect` trampoline; `arr.length = 0` truncation; module-level `Array<FuncType>` globals; capturing closures lifted from `startBodyLines` by second-pass `liftStartBodyArrows()` (44)
- `jstyper` CLI: `.js` + `.d.ts` → typed `.ts` for wasic; `--dts-only` skeleton generation; `--dry-run`; `--any-policy=skip|warn|default`; actionable multi-line error messages with corrected declaration suggestions (39)
- External interface mapping: `declare const`/`declare interface` → WASM `(import "env" ...)` declarations; env stub proxy in test runner (40)
- WIT file generation: automatic `.wit` written alongside `.wasm`; exports from `export function` declarations, imports from Phase 40 externals; WIT types (`s32`/`s64`/`f32`/`f64`/`bool`); `package local:name; world name { ... }` format (41)
- Class enhancements: static fields, getters/setters, string enums (29)
- Struct/object enhancements: `namespace` declarations, interface inheritance (`extends`), shorthand property notation (`{ x, y }`) (30)
- TypedArrays: Int8/Uint8/Int16/Uint16/Int32/Uint32/Float32/Float64 Array — construction, element r/w, `.length`/`.byteLength`, `.fill()`, `.set()`, TypedArray function params, `console.log` (31)
- Intersection types: `A & B [& C …]` merges all fields into a flat struct; chained intersections; base-typed function params with derived-type args (33)
- Type predicates: `param is Type` return annotations → `bool` WAT result; compile-time narrowing in `if`-branch scopes via `typePredicateFuncs` + `structVars` swap; works with DU types and interface inheritance; else-if chain narrowing via recursive `emitBlock` (34)
- `typeof` / `keyof T` (compile-time only): `typeof x === "number"` → `(i32.const 1/0)`; `const t: string = typeof x` → static string; `console.log(typeof x)` → literal text; `key: keyof T` in type positions → `string` (35)
- Simple conditional types: `type Name<T> = T extends U ? X : Y` (generic) and `type Name = A extends B ? X : Y` (non-generic); resolved entirely at compile time by `expandConditionalTypes()` source pre-pass; result type substituted at every use site before any parse pass (36)
- Structs/interfaces: fixed layout, destructuring, interface method dispatch (12b), tuples (23)
- Generics: monomorphization (14)
- Exception handling: throw/try/catch/finally with WASM exception proposal (15)
- Module system: named/default/namespace/re-exports (16)
- Math intrinsics: full set including `Math.round` (round-half-away-from-zero) (7a)
- String operations (11), Classes (9), Bump allocator (10a), Dynamic array growth (10c)
- Multi-file bundling (8), WASM import bundling (18), wasmbundle CLI (19/20)
- Type system: `never`, `void`, `readonly` (21), compile-time ops + `as` casts (22), tuples (23)
- Nullable types: `T | null` variables + returns, null checks, `console.log` of nullable (24)
- Nullish/logical ops: `??`, `??=`, `||=`, `&&=` for locals and module globals (25)
- `for...of` over static/dynamic/f64 arrays, break/continue, function-local; array destructuring with defaults (26)
- Extended string methods (trim/trimStart/trimEnd, charCodeAt, charAt, startsWith, endsWith, toUpperCase, toLowerCase, replace, replaceAll, padStart, padEnd, repeat, split→string[]) + Bun/Deno runtime shim `src/rt.ts` (27)
- wasic library mode / modc backend (17)
- asc (AssemblyScript) dependency removed (cleanup 2026-04-15)

### Phase 40 — External Interface Mapping via `declare const` / `declare interface` (2026-07-14)

Phase 40 test files (all 6 PASS — 5 new + 1 upgraded):

- `BasicExternalDecl_40.ts` — `declare const storage: { write(k, v): void; read(k): i32 }` inline object type; verifies two external methods (void + i32 return) compile to `(import "env" "storage_write" ...)` and `(import "env" "storage_read" ...)`
- `ExternalInterfaceType_40.ts` — `declare interface Logger { ... }` then `declare const logger: Logger`; verifies named interface + named binding pattern; two methods (void + i32 return)
- `MultiMethodExternal_40.ts` — three methods with mixed types (i32+i32→i32, f64+f64→f64, i32→i32) on a single `declare const ops`; verifies multiple method dispatch on one binding
- `ExternalReturnValue_40.ts` — three methods on `declare const sensor`: `readInt(): i32`, `readFloat(): f64`, `reset(): void`; all three WAT return type variants
- `Phase40Combined_40.ts` — two `declare interface` types (Display + Sensor) bound to two `declare const` variables; verifies multiple simultaneous external bindings with distinct signatures
- `ExternalMapping_11b.ts` — **upgraded** from `// @expect-fail: compile` (wasic rejected undefined `logger`) to fully passing; `declare const logger: { log(ptr: i32): void }` compiles to WASM import; top-level uses `console.log("ok")` to avoid calling the external method without a host

**`parseExternalInterfaceBody(body: string)`** — private helper on `WasicTranspiler`; parses method signatures from an interface body string using `/(\w+)\s*\(([^)]*)\)\s*:\s*([\w\[\]]+)/g`; calls `mapType()` on each param/return type; returns `Map<string, { params: WatType[]; result: WatType | null }>`.

**`parseExternalDeclarations()`** — called in `transpile()` after `expandNamespaces` and keyof normalization, before `parseEnums`. Three-pass parser:

1. `declare interface Name { ... }` → populate `externalInterfaceTypes` (map name → method map), then strip from source
2. `declare const varName: { ... }` (inline) → create synthetic interface name `__ext_varName`, populate `externalInterfaceTypes` + `externalBindings`, then strip from source
3. `declare const varName: InterfaceName` (named) → look up `externalInterfaceTypes.has(InterfaceName)`, populate `externalBindings`, then strip recognized bindings from source

**New data structures on `WasicTranspiler`:**

- `externalInterfaceTypes: Map<string, Map<string, { params, result }>>` — interface name → method name → signature
- `externalBindings: Map<string, string>` — variable name → interface name (synthetic or user-named)
- `usedExternalMethods: Map<string, { params, result }>` — `"$varName_method"` → signature; populated at call-site emission; drives WAT import generation

**Call-site emission (two contexts):**

- **Statement (`dotCallStmt`)**: after namespace check in `emitStatement`, checks `externalBindings.has(receiver)` → looks up method sig → records in `usedExternalMethods` → emits `(call $varName_method args)`, wrapped in `(drop ...)` when result is non-void
- **Expression (`dotCallExprMatch`)**: same logic in `emitExpr`, after namespace handler, returns `(call $varName_method args)` directly

**`emitWasiImports()` extension**: after WASI imports, iterates `usedExternalMethods` and emits one `(import "env" "varName_method" (func $varName_method (param ...) (result ...)?))` per entry. `fieldName = funcName.slice(1)` strips the leading `$`. Import field name and WAT function name are identical (modulo the `$` prefix), e.g. `logger_log`.

**Error message improvement**: when `dotCallStmt` encounters an undeclared receiver, the third error line now says: `If '${receiver}' is an external module, use: declare const ${receiver}: { ${methodName}(...): ReturnType }` — pointing directly to the Phase 40 syntax.

**Runner stub proxy** (`src/utils.ts` `runWasi`): the `env` import object is now a `Proxy` that returns a no-op stub `(..._args) => 0` for any key not explicitly defined in `envBase`. This allows WASM modules with `(import "env" "...")` declarations to instantiate and run in the test runner without a real host implementation.

**Known limitations** — Nested object types in method signatures are not supported (e.g. `declare const x: { method(a: { b: i32 }): void }`). Only the forms `declare const varName: { ... }` (inline) and `declare interface` + `declare const varName: InterfaceName` (named) are recognized. The `declare` keyword only has meaning inside `declare interface/const` forms — bare `declare function/module/class` is not handled.

### Phase 41 — WIT File Generation (2026-07-14)

**Overview**: After every successful `wasmtk wasic` or `wasmtk modc` compilation, a `.wit` file is written alongside the `.wasm` output. The file describes the module's complete interface: exports derived from `export function` declarations and imports derived from Phase 40 external bindings.

**`watTypeToWit(t: WatType | null): string | null`** — module-level helper in `wasic.ts`. Type mapping: `"i32"→"s32"`, `"i64"→"s64"`, `"f32"→"f32"`, `"f64"→"f64"`, `"bool"→"bool"`, `null→null` (void). String types map to `"s32"` (wasic uses a pointer-only ABI for strings in exports). Any other type falls through to `null` (excluded from WIT).

**`toKebabCase(s: string): string`** — module-level helper. Converts camelCase and snake_case identifiers to kebab-case for WIT naming compliance. Algorithm: insert `-` before any uppercase letter preceded by a lowercase letter or digit, then lowercase the whole string.

**`generateWit(moduleName: string): string`** — public method on `WasicTranspiler`; called in `compileWasiTs()` and `compileLibTs()` after `watToOptimisedWasm()` succeeds. Must be called after `transpile()` because `usedExternalMethods` is populated during WAT emission.

**WIT format produced:**

```wit
package local:module-name;

world module-name {
  import env-method-name: func(param: type, ...) -> type;
  ...
  export fn-name: func(param: type, ...) -> type;
  ...
}
```

**Import section** — iterates `usedExternalMethods` (populated by Phase 40 call-site emission). Each entry `"$varName_method"` → sig is emitted as `import varname-method: func(...)`. The function name (without `$`) is converted to kebab-case. Params/returns mapped via `watTypeToWit()`.

**Export section** — filters `this.functions` array: `f.exported === true`, `f.isClosureFactory !== true`, and name not in `INTERNAL` set (`_start`, `_initialize`). For each exported function: skips `__self` params (class instance pointer), maps remaining params via `watTypeToWit()`, maps return type, converts name to kebab-case. Functions where all param/return types map to `null` are still included (void functions).

**Compile pipeline integration** (`compileWasiTs` and `compileLibTs` in `wasic.ts`):

```typescript
const witPath = out.replace(/\.wasm$/, ".wit");
await rt.writeTextFile(witPath, transpiler.generateWit(name));
console.log(`   WIT:  ${witPath}`);
```

The `console.log` output line matches the style of the existing `WAT:  <path>` line.

**Known limitations** — String parameters are represented as `s32` (pointer only); WIT does not capture the length parameter of wasic's ptr+len string ABI. Closure factories and internal runtime functions are excluded, but other internal helpers with leading `$__` names that are accidentally marked exported would appear. Generic / template-instantiated function names appear as-is (monomorphized names with type suffixes).

**Types requiring `javyc` (out of scope for wasic):** `any`, `unknown`, `symbol`, `object` (generic),
`Map`/`Set`/`WeakMap`, `Promise`/`async`/`await`, generators, `for...in`, `JSON.parse/stringify`,
dynamic computed keys, prototype methods, regular expressions, recursive conditional types.

### Phase 43 — String Arrays as Function Parameters (2026-05-14)

Phase 43 test files (all 4 PASS):

- `BasicStringArrParam_43.ts` — `strIndexOf(arr: string[], v: string): i32` and `strIncludes(arr: string[], v: string): boolean`; string array param + string param; verifies indexOf returns correct index or -1
- `StringArrHigherOrder_43.ts` — `anyMatch`, `allMatch`, `countMatch` with `pred: (s: string) => boolean`; callbacks `startsWithA` and `isLong`; verifies higher-order string array functions with `call_indirect`
- `StringArrReturn_43.ts` — `strFilter(arr: string[], pred: (s: string) => boolean): string[]`; returns a new string array; verifies `.length` and element comparison on the result
- `Phase43Combined_43.ts` — `strIndexOf` + `strSome` + `strEvery` + `strFilter` all together; two callback functions; combined test of all Phase 43 patterns

**Memory layout for string arrays**: 8-byte header `[length i32 at +0, capacity i32 at +4]` followed by elements at `+8`; each element is 8 bytes: `[ptr i32 at +0, len i32 at +4]`. **Shift=3** (not shift=2) for string array element address calculation.

**`getOrCreateFuncType` expansion** — `"string"` params now expand to TWO `"i32"` values via `flatMap` (ptr + len). A callback `(s: string) => boolean` produces `$ftype_i32_i32_r_i32`.

**`emitFunction` param registration** (`wasic.ts` ~line 10040) — string array params (`arrayElemType === "string"`) are registered in `arrayVars` with `dynamic: true` and `isStringArr: true` so element access uses the 8-byte element layout.

**`bracketMatch` in `emitExpr`** — string arrays (`isStringArr || elemType === "string"`) use `shift=3` (8-byte elements). Returns the ptr word of the element (i32.load); callers that need both ptr+len use `emitStringPtrLen` instead.

**`emitStringPtrLen` extension** — handles `arr[idx]` when `arr` is a string array: emits `(i32.load elemAddr) (i32.load offset=4 elemAddr)` where `elemAddr = arr+8+idx*8`.

**`funcTypeVars` call-indirect** — `emitExpr` and `emitStatement` funcTypeVars paths now use `flatMap` + `emitStringPtrLen` for string-typed params: `if (pt === "string") return [this.emitStringPtrLen(a, locals)]`.

**`console_log.ts` string comparison** (`exprToWat`) — new handler added before the binOps loop: when either side of `===`/`!==`/`==`/`!=` is a string expression (literal, string variable, or string array element identified via `looksLikeString`), routes through `$__str_cmp`. Calls `_strCmpNeeded?.()` to signal wasic to emit the helper.

**`console_log.ts` string array element access** (`exprToWat`, `bracketM` handler) — added check for `ai.isStringArr || ai.elemType === "string"`: loads element ptr using `shift=3` addressing.

**Three new singleton callbacks in `console_log.ts`:**

- `setStrCmpNeededCallback(fn)` — called when `$__str_cmp` is emitted; wasic sets `needsStringHelpers = true`
- `setFuncTableLookup(fn)` — called when an identifier is not in locals/globals; wasic provides `(name) => getFuncTableIdx(name)` for function references passed as arguments
- Both set/cleared around each `parseConsoleLogArgs` call in wasic.ts

**Helper dependency fix** — `getStringExtHelperWat()` (`$__str_replace`, `$__str_split`) calls `$__str_indexof` from `getStringOpHelperWat()`. Condition updated: `if (this.needsStringOpHelpers || this.needsStrGatherHelper || this.needsStringExtHelpers)` to always emit `getStringOpHelperWat()` when ext helpers are needed.

**Known limitations** — `string[]` return type from functions is not yet implemented (functions return `string[]` as a plain `i32` pointer; callers must treat it as a dynamic string array). `s[0]` character access on string params (inside function bodies) is handled via `$__str_char_code_at` as before. String array sort, indexOf, includes etc. are not yet wired.

---

### Phase 44 — Function Pointer Arrays (`Array<FunctionType>`) (2026-05-14)

**Overview**: `Array<() => void>` (and parameterized variants) stores i32 values — either closure struct pointers (for capturing closures) or bare function table indices (for non-capturing functions). The array uses the same dynamic i32 array infrastructure as other `i32[]` arrays. `arr[i]()` dispatches via `call_indirect` through the trampoline mechanism already used by Phase 5f/5g closures.

**`isFuncPtrArr` field** — added to `ArrayInfo` (the type stored in `arrayVars` and `moduleArrayVars`): `isFuncPtrArr?: { params: WatType[]; result: WatType | null }`. When set, the array is a function pointer array; the value is the function signature (params + result of the stored function type).

**`Array<FuncType>` detection — three sites:**

1. **`detectModuleArrayGlobals()`** — regex `(?:const|let|var)\s+(\w+)\s*:\s*Array<((?:[^<>]|=>)*)>\s*=\s*\[\]` added BEFORE the existing `T[]` match. Uses `parseFuncTypeSig` to extract the function signature and sets `isFuncPtrArr`. The regex uses `((?:[^<>]|=>)*)` (not `[^>]+`) so that `=>` inside `Array<() => void>` does not terminate the match prematurely.

2. **`emitFunction` pre-scan** (~line 10402) — same regex detects local `Array<FuncType> = []` declarations. Registers in `arrayVars` with `isFuncPtrArr` and declares an `i32` local.

3. **`startBodyLines` pre-scan** (~line 11347) — same regex for module-level arrays. Reads existing entry from `moduleArrayVars` (populated by `detectModuleArrayGlobals`) and carries `isFuncPtrArr` into `arrayVars`.

**`liftStartBodyArrows()` — new second-pass arrow-lifting method** (added after `liftInlineArrows` in `wasic.ts`, called in `transpile()` after `parseTopLevel()`): `liftInlineArrows()` runs before `parseTopLevel()`, so `startBodyLines` is empty when it runs. `liftStartBodyArrows()` creates a synthetic `_start` `FuncDef` with `bodyLines = [...startBodyLines]` and passes it as `enclosingFn` to `substituteOneArrow`. This allows module-level capturing closures — e.g. `defer(() => console.log(n))` inside a for loop where `n` is the loop variable — to be lifted to factory/trampoline pairs with correct capture analysis.

**`emitStatement` additions:**

- **`Array<FuncType> = []` handler** (`funcArrLetMatch`) — matches `var/let/const name: Array<...> = []`; calls `emitDynArrayInit` to initialize the global dynamic array header.
- **`arr.length = N` handler** (`arrLenAssign`) — matches `name.length = expr`; emits `(i32.store (global/local.get $arr) valWat)` to write the length header word. Handles both module globals and function locals.
- **`arr[idx]()` call handler** (`funcPtrArrCallMatch`) — matches `name[idx]();`. When the array is a function pointer array (`isFuncPtrArr` is set), emits:

  ```wat
  (local.set $__fn_tmp (i32.load elemAddr))
  (call_indirect (type $ftype_i32_r_void) (local.get $__fn_tmp) (i32.load (local.get $__fn_tmp)))
  ```

  The element address uses shift=2 (i32 elements). `$__fn_tmp` holds the closure struct ptr; `i32.load($__fn_tmp)` reads the trampoline table index at offset 0 of the struct. The functype for `call_indirect` always includes `i32` (the closure ptr) as first param, followed by any non-i32 function params.

**`$__fn_tmp` local declaration** — added to both `emitFunction` post-loop pre-scan and `startBodyLines` post-loop pre-scan: declares `$__fn_tmp: i32` when the function body contains `name[...` referencing a function pointer array.

**`substituteOneArrow` bug fix** — for expression-body arrows (`() => expr`), the code previously called `inferInitType(expr, ...)` when `anonResult === null`. But `null` means both "explicitly void" (from `paramInfo.result = null`) and "no type info". JavaScript's `??` operator coalesces `null`, so `paramInfo?.result ?? fallback` evaluates `null ?? fallback = fallback` — losing the explicit void signal. Fix: changed condition from `if (anonResult === null)` to `if (anonResult === null && paramInfo === undefined)`. This ensures `inferInitType` is only called when there is genuinely no callee type information, not when the callee explicitly says `void`. Without this fix, `() => console.log(n)` generated `__anon_0` with `(result f64)` instead of `void`, causing a `call_indirect` type mismatch at runtime.

**Memory layout**: function pointer array elements are i32 values. For capturing closures, the stored i32 is the closure struct pointer (not the table index). The struct's first word (`i32.load ptr`) is the trampoline's table index. For non-capturing function references (bare `fn` passed as argument), the stored i32 is the table index directly — but `i32.load(tableIdx)` would read from WASM memory at that address, not from the table. **Note**: mixing bare table indices and closure struct pointers in the same array is not supported; the test cases use exclusively capturing closures.

**Known limitations** — `arr[i](args)` with non-void function types (args or return value) is emitted but the functype is calculated from `isFuncPtrArr.params` and `isFuncPtrArr.result`. Bare (non-capturing) function pointers pushed to a `Array<() => void>` would be read as struct pointers (causing wrong dispatch). Only capturing closures (where the stored value IS a struct pointer) are fully supported.

---

### Phase 29 bug fix — `structLookupFn` static field in `console.log` (2026-04-24)

**Rule:** Both `structLookupFn` closures in `wasic.ts` (one for `console.log`, one for `console.error`) must include a Phase 29 static field branch after the instance-var and getter checks but before the `structVars` fallback.

**Why:** `console.log("Count:", Rectangle.count)` was printing `0` instead of the live value because `structLookupFn("Rectangle", "count")` returned `undefined` — the function only checked `classVars` (instance vars) and `structVars` (plain structs), but never checked whether `vn` was a class name with a static field registered as a module global. The fix adds: if `classDefs.get(vn)` exists and `moduleGlobals.get("${vn}_${fn}")` exists, return `{ type: gType, watLoad: "(global.get $${vn}_${fn})" }`.

**How to apply:** If either `structLookupFn` is refactored in `wasic.ts`, ensure the static-field branch is preserved in both the `console.log` closure (~line 4860) and the `console.error` closure (~line 4960). The pattern is identical in both: check `classDefs.get(vn)` → check `moduleGlobals.get(globalKey)` → return global.get.

### Phase 30 — Namespace, Interface Inheritance, Shorthand Props (2026-04-27)

**`namespace` declarations** — Source-level transform via `expandNamespaces()` runs before any parse pass in `transpile()`. Finds `(?:export\s+)?namespace\s+Name\s*{...}` blocks, rewrites `export function f(...)` → `function Name_f(...)` and `export const C: T = val` → `const Name_C: T = val`, then flattens into top-level declarations. `namespaceDefs: Set<string>` tracks known namespace names. Call sites using dot notation (`Name.f(args)`, `Name.C`) are handled in `emitExpr` (`enumDotMatch` for constants, `dotCallExprMatch` for functions), `dotCallStmt` (as statement), and both `structLookupFn`/`dotCallLookupFn` closures. `parseTopLevel` skips original namespace blocks (already expanded). Error guard in `dotCallStmt` excludes known namespace names.

**Interface inheritance (`interface B extends A`)** — `parseStructs()` regex captures optional `extends BaseName` group. When building B extending A: look up A's struct in `structDefs`, prepend A's fields with their original offsets, start B's own field offset from A's `totalSize`. Guard prevents re-adding inherited fields.

**Shorthand property notation (`{ x, y }`)** — `return { x, y }` in function bodies: when no `:` separator found for a token, treat it as both key and value; emit per-field `storeOp` (f64.store vs i32.store). `structVarRuntimeInits: Map<string, Record<string, string>>` collects shorthand fields during pre-scan (both `emitFunction` body and `startBodyLines` pre-scan). `emitStatement` struct let match reads `structVarRuntimeInits` and emits runtime store instructions after `local.set $p (i32.const ptr)`.

**Bug fix — function-returned struct field access**: Structs returned from functions were registered only in `interfaceVars` but not `structVars`. Fixed in both pre-scan locations by also calling `structVars.set(varName, { def, ptr: -1 })`. Enables `const v: Vec2 = makeVec(3.0, 4.0); console.log(v.x)` to work correctly.

**Known limitation**: Mixing namespace i32-returning function calls with f64 arithmetic (e.g., `PI * someIntFn()`) causes Binaryen type assertion failure. Workaround: use float literals instead of i32-returning function calls in f64 arithmetic contexts.

### Phase 31 — TypedArrays (2026-04-29)

**Memory layout**: 8-byte header `[length i32 at +0, padding i32 at +4]` followed by typed data at `+8`; allocated via `$__malloc`. All TypedArray variables stored as plain `i32` WAT locals holding the base pointer.

**`getTypedArrayInfo(name)`** — helper function after `mapType()` in `wasic.ts` — returns `{elemType, loadOp, storeOp, shift, bytesPerElem}` for all eight TypedArray names. `shift` is the `i32.shl` exponent for address calculation: 0 for byte types, 1 for i16, 2 for i32/f32, 3 for f64/i64.

**`typedArrayVars: Map<string, {taType, elemType, loadOp, storeOp, shift, bytesPerElem, length}>`** — per-function map tracking TypedArray variable declarations. Reset at start of each `emitFunction` and `startBodyLines` call. TypedArray params (where `p.structType` is a TypedArray name) are registered here too.

**Pre-scan ordering**: TypedArray pre-scan runs BEFORE `newClassPre` since TypedArray names are PascalCase and `newClassPre` would match them as struct allocations.

**Construction — three forms:**

- `new Int32Array(3)` — literal length: emit `$__malloc((3+1)*4+8)`, store length at header, zero-fill body
- `new Int32Array(n)` — runtime length: same but length expression emitted as WAT
- `new Int32Array([1, 2, 3])` — literal array: allocate data segment + header in static data, use `memory.copy` to copy from data segment into heap allocation at runtime

**Element read/write**: address = `ptr + 8 + idx * bytesPerElem`. For shift=0 (Uint8Array, Int8Array), use `(i32.add (i32.add ptr (i32.const 8)) idx)` — no `i32.shl`. For shift>0 use `(i32.add (i32.add ptr (i32.const 8)) (i32.shl idx (i32.const shift)))`.

**`.fill()` and `.set()` helpers** — `emitTypedArrHelpers()` generates `$__ta_fill_T` and `$__ta_set_T` WAT functions on demand; `typedArrHelpers: Set<string>` tracks which are needed; `emitHelpers()` calls `emitTypedArrHelpers()` when set is non-empty.

**`ArrayLookup` extension in `console_log.ts`** — optional `shift?: number` and `customLoadOp?: string` fields added to the type. `arrayLookupFn` closures in `wasic.ts` check `typedArrayVars` and return these fields. Both bracket handlers (`parseSingleArg` and `exprToWat`) use `arrInfo.customLoadOp ?? defaultLoadOp` and `arrInfo.shift !== undefined ? arrInfo.shift : defaultShift`.

**`structLookupFn` extension** — both closures (console.log and console.error paths) check `typedArrayVars.get(vn)` for `.length` and `.byteLength` before falling through to struct/class checks. Returns `{type: "i32", watLoad: "(i32.load ptr)"}` for `.length` and `{type: "i32", watLoad: "(i32.mul (i32.load ptr) (i32.const bytesPerElem))"}` for `.byteLength`.

**`console.log` of TypedArray** — emits `["TypedArrayName(", i32expr(len), ") ", arrptr(ptr), "\n"]` LogSegments in `logMatch` (before `structFnCallMatch`). Reuses existing i32/f64 array print helpers (`$__write_i32arr_to_scratch`, `$__write_f64arr_to_scratch`) via the `arrptr` LogSegment mechanism.

**`$__write_f64arr_to_scratch`** — added to `getArrPrintHelperWat()` in `console_log.ts`; reads f64 elements at `arr_ptr+8+idx*8` (shift=3).

**Bug fix — `bracketMatch` greedy regex** (`wasic.ts` line ~3021): Changed `/^(\w+)\[(.+)\]$/` → `/^(\w+)\[([^\]]*)\]$/`. Prevents `emitExpr("nums[0] + nums[1] + nums[2]")` from greedily matching as `nums` with index `"0] + nums[1] + nums[2"`. Without this fix, compound TypedArray expressions like `nums[0] + nums[1] + nums[2]` produced a comment-stub `(;? 0] ;)` and evaluated to 0. The fix causes the regex to not match when `]` appears inside the index, so the expression falls through to the binary ops loop for correct recursive handling. This is a latent fix that also benefits plain array compound expressions.

### Phase 35 — `typeof` / `keyof T` (2026-05-03)

**`typeof` as a comparison expression** — `typeof x === "number"` (and `!==`, `==`, `!=`) is evaluated entirely at compile time in `emitExpr`. The new handler matches `/^typeof\s+(\w+)\s*(===|!==|==|!=)\s*["'](\w+)["']$/` (and the reversed form) before the binary ops table. It calls `resolveTypeofString(varN, locals)` to get the compile-time type string and emits `(i32.const 1)` or `(i32.const 0)`. The reversed form (`"typename" === typeof x`) is also matched.

**`resolveTypeofString(varName, locals)` private method** — returns the TypeScript runtime typeof string for a known variable. Mapping: `"string"→"string"`, `"bool"→"boolean"`, `"f64"/"f32"→"number"`, `"i64"→"bigint"`, `"i32"` with struct/TypedArray/array registration→`"object"`, plain `"i32"→"number"`, anything else→`"undefined"`. Also checks `moduleGlobals` if not in locals.

**`typeof x` as a value** — handled in three contexts:

1. **`emitExpr` standalone** — `/^typeof\s+(\w+)$/` → emits `(i32.const ptr)` where ptr points to the static type-name string in the data section. Used as a fallback for i32-context uses.
2. **`emitStringAssign`** — `/^typeof\s+(\w+)$/` as the RHS of a string assignment. Calls `resolveTypeofString`, allocates the type-name string, and emits `(local.set $name_ptr / $name_len)`. Handles `const t: string = typeof x` and `const t = typeof x`.
3. **`console_log.ts parseSingleArg`** — `/^typeof\s+(\w+)$/` token returns `[{ kind: "literal", text: typeStr }]`. Allows `console.log(typeof x)` to print the type name as a static string literal with no runtime overhead.

**`inferInitType` extension** — `/^typeof\s+\w+$/` now returns `"string"` early, so `const t = typeof x` (no type annotation) correctly infers `string` and routes to `emitStringAssign`.

**`keyof T` as a type annotation** — two mechanisms work together:

1. **`mapType` guard** — `/^keyof\s+\w+/` at the top of `mapType()` returns `"string"` for inline uses like `(param $key_ptr i32) (param $key_len i32)` — correct for function parameters already resolved by the source pre-pass.
2. **Source pre-pass in `transpile()`** — runs after `expandNamespaces()`. The regex `this.src.replace(/:\s*keyof\s+\w+/g, ": string")` rewrites every `: keyof T` type annotation to `: string` in the raw source before any parsing. A second regex strips `type Alias = keyof T` declarations. This ensures `const k: keyof Point = "x"` and `function f(key: keyof Person)` are seen by all parsers as plain string annotations.

**Known limitations** — `typeof x` in type-position (`param: typeof myVar`) is not implemented. `return typeof x` from a string-returning function returns only the pointer (length is lost). Named `keyof` aliases (`type PersonKey = keyof Person; const k: PersonKey = "x"`) do not resolve correctly after stripping (PersonKey becomes unknown and maps to i32). Only inline `keyof T` in type positions is fully supported.

### Phase 39 — jstyper: `.d.ts`-based JS import pre-processor (2026-07-14)

**Architecture** — `src/jstyper.ts` is a standalone module with no external dependencies (no `npm:typescript`). It uses regex-based parsing and brace-counting to extract JS function bodies and `.d.ts` typed signatures, then merges them into a typed `.ts` file that wasic can compile.

**`parseJsFunctions(src)`** — extracts all function definitions from JS source. Handles three forms: `(export)? function name(params) { body }`, `(export)? const name = (params) => { body }`, and `(export)? const name = (params) => expr` (expression body, auto-wrapped in `{ return ...; }`). Uses a brace-counting `extractBraceBlock()` with string-literal awareness (handles `"`, `'`, `` ` `` and `\\` escapes). Returns `JsFuncDef[]` with `name`, `params` (raw JS names), `body`, and `isExported`.

**`parseDtsFunctions(dts)`** — extracts typed declarations matching `(?:export\s+)?(?:declare\s+)?function\s+name\(params\)\s*:\s*returnType;`. Returns `DtsFuncDef[]` with `name`, typed `params[]`, and `returnType`. Params without `:` default to `any`.

**`generateSkeletonDts(fns)`** — `--dts-only` mode: produces a `number`-typed skeleton `.d.ts` with `@auto-generated by jstyper` header for hand-editing. Every param and return typed as `number`; exported functions use `export declare function`, non-exported use `declare function`.

**`generateTypedTs(jsFns, dtsFns, anyPolicy, dtsFile?)`** — merges JS bodies with `.d.ts` types. Type mapping: `number→f64`, `int→i32`, `float|double→f64`, `any` controlled by `anyPolicy`. Passes through `i32`, `i64`, `f32`, `f64`, `bool`, `boolean`, `string`, `void`, `never` unchanged. Unknown types pass through as-is. When `dtsFile` is provided (from `runJstyper`), diagnostic messages include the filename.

**`anyPolicy` modes:**

- `"skip"` — functions with any `any`-typed param or return are excluded entirely; warning names the specific param and shows the corrected declaration
- `"warn"` — `any` mapped to `i32`, warning emitted with corrected declaration suggestion
- `"default"` — `any` mapped to `i32` silently, no warnings

**Actionable diagnostic messages** — three warning/error classes, each multi-line with a "Fix:" block:

1. **Missing `.d.ts`** (fatal): `❌ jstyper: no type declarations found for 'file.js'\n  To generate a skeleton ...\n    wasmtk jstyper file.js --dts-only\n  Then edit file.d.ts — replace 'number' placeholders ...`
2. **Missing function declaration**: `'fn' has no declaration in file.d.ts — skipping\n  Fix: add to file.d.ts:\n    export declare function fn(a: <type>): <returnType>;\n  Valid WASM types: i32, i64, f32, f64, bool, string, void`
3. **`any` type**: `skipping/using-fallback 'fn' — param 'x' is typed 'any'\n  Fix: replace 'any' with a concrete type in file.d.ts:\n    export declare function fn(...): ...;\n  Valid WASM types: ...\n  Or use --any-policy=warn to include it as i32 for now.`

**`correctedDecl(dts)`** — helper that reconstructs the corrected declaration string with every `any` replaced by `i32`, used in all three diagnostic message classes.

**`WASM_TYPES_HINT`** — constant `"  Valid WASM types: i32, i64, f32, f64, bool, string, void"` shared across all messages.

**CLI flags** wired in `main.ts`: `--dts-only` (boolean), `--dry-run` (boolean), `--any-policy=skip|warn|default` (string, default `"warn"`), `-n/--name` (output path override).

**Test fixtures** in `tests/jstyper_fixtures/`:

- `basicmath.js` + `basicmath.d.ts` — `add(i32,i32):i32`, `multiply(f64,f64):f64`, `square(i32):i32`
- `numbertypes.js` + `numbertypes.d.ts` — `area/perimeter/hypotenuse` all typed `number` (→f64)
- `anypolicy.js` + `anypolicy.d.ts` — `safe` (typed), `hasAnyParam` (any param), `hasAnyReturn` (any return)

**`deno.json`** — `"./jstyper": "./src/jstyper.ts"` added to exports.

**Known limitations** — No automatic `.d.ts` generation via `tsc` (no `npm:typescript` dependency); the `--dts-only` skeleton uses `number` placeholders that must be hand-edited to precise WASM types. tsbundler transparent integration (auto-detecting `.js` imports during `wasmtk wasic`) is deferred to Phase 40 preparation. Arrow functions with single unparenthesised params (`x => x * 2`) are not parsed; params must use parentheses.

### Phase 38 — Extended Math via external `mathlib.wasm` (2026-07-14)

**Architecture**: `mathlib.wasm` is a standalone WASM module (21 exports) compiled from `src/wasm/mathlib.wat`. Its bytes are embedded in `src/wasm/mathlib_bytes.ts` as `MATHLIB_BYTES: Uint8Array`. `compileWasiTs` and `compileLibraryTs` in `utils.ts` call `mergeOneWasmImport(wat, MATHLIB_BYTES, "mathlib", dataOffset)` after the main WAT is assembled, when `transpiler.needsMathLib` is true. Binaryen then sees one fully-merged WAT and can dead-strip/inline freely. (Pre-wabt-ts, `mergeOneWasmImport` took a 5th `wabtMod` parameter — removed in the wabt-ts migration since `wat2wasm` / `wasm2wat` are stateless top-level functions.)

**Call naming**: wasic emits `(call $mathlib_sin arg)`, `(call $mathlib_random)` etc. `console_log.ts` does the same. The "mathlib" prefix is applied by `mergeWasmWat()` which renames all exported functions with the prefix.

**Global index relocation**: `renameGlobalRefs()` in `wasmmerge.ts` rewrites `global.get N` / `global.set N` in merged function bodies to `global.get $mathlib_globalN` — necessary because the RNG state global (`$__rng_state`, i64) gets a different index after the main module's globals are prepended.

**atan two-stage range reduction**: `$atan` in mathlib.wat uses two stages before the fdlibm aT[0..10] polynomial:

1. Complement: if z > 1, z = 1/z, comp=1 → adjusts final result as `pi/2 - r`
2. Mid-range: if z > tan(π/8) ≈ 0.4142, z = (z-1)/(z+1), mid=1 → adjusts as `pi/4 ± r`

Four cases for result: `(comp,mid)=(0,0)→r`, `(0,1)→pi/4+r`, `(1,0)→pi/2-r`, `(1,1)→pi/4-r`.
Formula: `r = z - z³*t` (subtract, not add). The aT coefficients are minimax for |z| ≤ tan(π/8).

**Greedy `Math.fn(...)` regex bug fix** (wasic.ts + console_log.ts): The regex `/^Math\.(\w+)\(([\s\S]*)\)$/` greedily matches the last `)` in compound expressions like `Math.sin(a) * Math.sin(a) + ...`. Both files now validate that the matched argsStr has no unmatched `)` at depth 0 (scan loop, fail on depth < 0). If unbalanced, the Math block is skipped and binary ops handle the expression correctly.

**`exprToWat` globals fix** (console_log.ts): `exprToWat` lacked a `globals?: Map<string, string>` parameter, so module-level f64 globals (like `const x: f64 = 2.5`) fell through to the comment-stub fallback when used as arguments to nested Math calls (e.g. `Math.exp(x)`). Added `globals` as 8th optional parameter, updated the identifier check to emit `(global.get $x)` for globals, and threaded `globals` through all 31 internal recursive call sites.

**To regenerate mathlib.wasm after editing mathlib.wat:**

1. `wasmtk convert src/wasm/mathlib.wat` → `src/wasm/mathlib.wasm`
2. `deno run --allow-read --allow-write scripts/gen_mathlib_bytes.ts` → `src/wasm/mathlib_bytes.ts`

### Phase 37 — `flat()` / `flatMap(fn)` (2026-07-14)

**`flat()`** — one-level flatten of a 2D dynamic array (`i32[][]` or `f64[][]`) into a 1D array of the same element type. Caller array must be `is2D: true` in `arrayVars`; the outer array stores i32 pointers (shift=2) to inner arrays of `elemType`.

**`flatMap(fn)`** — maps each element of a 1D array through a callback `fn: (elem) → i32` (where the i32 is a pointer to an inner dynamic array of `elemType`), then flattens one level. The callback is invoked via `call_indirect` with functype `(elemType) → i32`. Inner arrays are i32[] or f64[] depending on `elemType`.

**WAT helpers** — `$__dynarr_flat_i32`, `$__dynarr_flat_f64`, `$__dynarr_flatmap_i32`, `$__dynarr_flatmap_f64` emitted on demand by `emitDynArrHelpers()`.

**`flat_T` algorithm** — two-pass: (1) sum all inner lengths to compute `totalLen`; (2) allocate result array with capacity=`totalLen`; (3) copy inner elements into result via indexed stores. Both passes read outer ptrs via shift=2 (i32 load); inner elements use `elemType`'s shift/load/store.

**`flatmap_T` algorithm** — (1) allocate a raw temp array of `len*4` bytes (no header) to hold inner array ptrs; (2) for each outer element call `fn(elem)` via `call_indirect`, store the returned ptr in tmparr, accumulate `totalLen`; (3) allocate result; (4) copy from each inner array into result. A single-pass approach is avoided because it would require calling `fn` twice per element.

**Changes in `wasic.ts`:**

- `findDynamicArrays` regex: added `flat` and `flatMap` to the method list so source arrays are promoted to dynamic layout.
- `dynArrMethod` regex in `emitExpr`: added `flat` and `flatMap`.
- `flat` handler: checks `arrInfo.is2D`, adds `flat_${elemType}` to `dynArrHelpers`, returns `(call $__dynarr_flat_T ...)`.
- `flatMap` handler: registers functype `(elemType) → i32`, adds `flatmap_${elemType}` to `dynArrHelpers`, uses `getFuncTableIdx` for the callback, returns `(call $__dynarr_flatmap_T ...)`.

**Callback constraint**: for `flatMap`, the callback must be a named function (not an anonymous arrow); it is looked up by `getFuncTableIdx`. The callback's TypeScript return type must be `T[]` which maps to WAT `(result i32)` — the same as any array-returning function.

**Known limitations**: `flat(depth)` with depth > 1 is not implemented. `flatMap` on `f64[]` arrays is supported but the callback must return `f64[]` (i.e., `(f64) → i32` WAT type). Inline arrow callbacks are not supported for `flatMap`.

### Phase 36 — Simple Conditional Types (2026-05-04)

**`expandConditionalTypes(src: string): string`** — new private method on `WasicTranspiler`, inserted after `expandGenerics` and before `expandNamespaces` in `transpile()`. It is a pure source-level text transformation: the original source is never stored anywhere else.

**Detection regex** — `(?:export\s+)?type\s+(\w+)\s*(?:<(\w+)>)?\s*=\s*([\w\[\]]+)\s+extends\s+([\w\[\]]+)\s*\?\s*([\w\[\]]+)\s*:\s*([\w\[\]]+)\s*;?` captures: name, optional type-param, checkExpr, upper, trueType, falseType. Matches only when `extends … ? … :` appears in the RHS — so `type i32 = number` and intersection/DU/object type aliases are never affected.

**`extendsCheck(concrete, upper): boolean`** — conservative compile-time type compatibility:

- Same string → true
- Any of `[i32, i64, f32, f64, number]` extends `number` → true
- `bool` / `boolean` extends `bool` / `boolean` → true
- Everything else → false

**Non-generic form** (`type AlwaysI32 = f64 extends number ? i32 : string`) — condition evaluated once at declaration time; all bare occurrences of the type name in the remaining source are replaced with the resolved concrete type string via `replace(new RegExp(...), resolved)`.

**Generic form** (`type Toggle<T> = T extends i32 ? f64 : i32`) — declaration removed; every `Toggle<ConcreteType>` use site is rewritten by resolving the condition against the concrete argument. If the selected branch is the type parameter itself (passthrough pattern `type Id<T> = T extends null ? never : T`), the concrete type is substituted directly.

**Ordering** — runs AFTER `expandGenerics` so monomorphized call sites created by generic expansion are also resolved. Runs BEFORE `expandNamespaces`, `parseEnums`, `parseDiscriminatedUnions`, `parseStructs`, `parseFunctions`, and all other parse passes, so no downstream pass ever sees a conditional type declaration or use.

**Known limitations** — `infer` keyword is not supported. Nested conditional types (condition result is itself a conditional) require two passes and are not resolved. Conditional types that reference other conditional types by name in their branches are resolved only if the inner name was already processed (source-order dependency). Only single-identifier type names are matched in each position (no union/intersection types in the conditional branches).

### Phase 34 — Type Predicates (2026-05-02)

**`typePredicateFuncs: Map<string, { paramName: string; targetType: string }>`** — new field on `WasicTranspiler`. Maps function name to its predicate info (the annotated param name and the narrowing target type).

**`parseFunctions()` return type regex extended** — the regex now matches `[\w]+\s+is\s+[\w]+` as an additional alternative before the base `[\w]+(?:\[\])*...` pattern. When `rawResult` matches `/^(\w+)\s+is\s+(\w+)$/`, the function is registered in `typePredicateFuncs` and `rawResult` is replaced with `"bool"` so the WAT result type is `i32`.

**Type predicate narrowing in `emitBlock()`** — in the if-handler, after emitting `condExpr` and before calling `emitBlock(ifBody, ...)`, the condition is matched against `/^(\w+)\s*\(\s*(\w+)\s*\)$/` (single-arg predicate call pattern). If the callee is in `typePredicateFuncs`, the argument variable is narrowed: its current `structVars` entry is saved, then replaced with `{ def: targetDef, ptr: same-as-before }` (preserving the pointer — static address or -1 for function params). After `emitBlock(ifBody, ...)` returns, the original state is restored. Narrowing to class types works the same way via `classVars`.

**Else-if chain narrowing is free** — because else-if chains are transformed into a nested synthetic `["if (cond) {", body, "}"]` structure and processed via recursive `emitBlock`, each inner `if (isFoo(x))` is processed independently and receives its own narrowing scope automatically.

**Known limitation** — negated predicates (`!isFoo(x)`) do not narrow the then-branch (they correctly narrow nothing, since the result is the complement type). The else-branch of a predicate if also does not narrow (complement type narrowing is not implemented). Only the affirmative single-arg call pattern is supported.

### Phase 33 — Intersection Types (2026-05-01)

**`parseIntersectionTypes()`** — new parse pass in `wasic.ts`, inserted between `parseClasses()` and `parseNamedFuncTypeAliases()` in `transpile()`. Detects `type Name = A & B [& C …]` declarations where the RHS is two or more word-identifier type names separated by `&`. For each match, merges all `StructField` entries from each constituent `structDefs` entry in source order, applying natural alignment and skipping duplicate field names (first definition wins). Registers the merged `StructDef` in `structDefs` as the intersection type name. Processes matches in source order so chained intersections (e.g. `type D = C & E` where C is itself an intersection) resolve correctly in a single pass.

**Regex guard** — `/(?:export\s+)?type\s+(\w+)\s*=\s*([\w]+(?:\s*&\s*[\w]+)+)\s*;?/g` only matches when the RHS is purely `\w` identifiers with `&`. This excludes object types (`{}`), DUs (`|`), tuple types (`[]`), function types (`=>`), and primitive aliases (no `&`). An `if (this.structDefs.has(name)) continue;` guard prevents re-processing types already registered by `parseDiscriminatedUnions()` or `parseStructs()`.

**No other changes required** — intersection types register as ordinary `StructDef` entries, so all existing struct infrastructure (struct literal pre-scan, `allocStructData`, field access in `emitExpr`/`emitStatement`, `structLookupFn` in `console_log.ts`, function param `structType` dispatch in `emitFunction`) works unmodified.

**Chained intersection example** — `type Particle = Physical & Spatial; type ColoredParticle = Particle & Color;` — when the regex engine processes `ColoredParticle`, `Particle` is already in `structDefs` from the earlier iteration, so all four Physical fields plus all Spatial fields appear before the Color fields in `ColoredParticle`'s layout. Passing a `ColoredParticle` pointer to a function expecting `Particle` works correctly because the first N bytes of both layouts are identical.

### Phase 32 — Discriminated Union Types (2026-04-30)

**`DiscUnionVariant` / `DiscUnionDef` interfaces** — added in `wasic.ts` (before `StructDef`). `discUnionDefs: Map<string, DiscUnionDef>` field on `WasicTranspiler`. Discriminant string literals are mapped to integer tag indices (0, 1, 2…) at compile time.

**`parseDiscriminatedUnions()`** — new parse pass in `wasic.ts`, called before `parseStructs()` in `transpile()`. Detects multi-variant type aliases via regex, extracts the common discriminant field (the one whose value is a string literal in all variants), and builds a flat "super-struct" StructDef: discriminant at offset 0 as i32 (4 bytes), then all unique variant fields laid out sequentially with natural alignment. Registers in both `structDefs` and `discUnionDefs`.

**`parseStructs()` skip guard** — `if (this.structDefs.has(name)) continue;` skips any type already registered by `parseDiscriminatedUnions()`, preventing the type-alias regex from producing a partial (single-variant) struct.

**Pre-scan: string discriminant → integer tag** — in both `emitFunction` and `startBodyLines` pre-scans, when a struct literal init is for a DU type, the discriminant field's string value is converted to its tag index integer before `allocStructData` runs.

**`emitExpr` DU comparison** — handles `varName.disc === "lit"` (and `!==`, `==`, `!=`) before the general binary ops loop. Loads the discriminant via `(i32.load ptr)` and compares with `(i32.const tagIndex)`.

**Switch statement DU support** — detects `switch (varName.discField)` pattern, emits `(i32.load ptr)` for the switch value, converts string case labels to integer constants via `duSwitchDef.variants.find(v => v.tag === str).tagIndex`.

**`else if` chain support in `emitBlock`** — wasic previously had no support for `} else if (cond) {`. Added detection: when `extractBlock` returns a `} else if (...)` terminator, builds a synthetic lines array `["if (cond) {", body1, "} else if (cond2) {", body2, "}"]` and calls `emitBlock` recursively. This is a general fix that benefits any feature using `else if` chains.

**Bug fix — `as T` cast source type for struct fields** (`wasic.ts` ~line 2907): `srcType` determination now also checks struct field type via `structVars.get(varName)?.def.fields.find(f => f.name === fieldName)?.type`. Compound expressions default to `"i32"`. Without this fix, `val.n as f64` where `n: i32` emitted `(return (i32.load ...))` (no f64 conversion), causing a WASM type error in f64-returning functions.

**Bug fix — i32 arithmetic in console.log** (`console_log.ts`): `parseSingleArg` now checks if the leading identifier type is `"i32"` (or `"bool"`) and returns `i32expr` (not `f64expr`). The `exprToWat` binary ops loop also extended to recognize `lhsLocalType === "i32"` → use `i32op` (same pattern as existing i64 check). Without this fix, `console.log("y:", y + m.steps)` where `y: i32, m.steps: i32` emitted `f64.add` with i32 operands → WASM type error.

---

## Active Design Decisions

### Pluggable wabt + binaryen backends (deno.json as the single switch, 2026-05-28)

**Rule:** wasmtk supports two interchangeable backends for both the WABT and
Binaryen compiler dependencies. The choice of backend is made *exclusively* by
editing the `"wabt"` and `"binaryen"` specifiers in `deno.json`. No source-code
change is required to switch.

**Supported configurations:**

| Specifier | npm option (legacy) | JSR option (jrmarcum ecosystem) |
| --- | --- | --- |
| `"wabt"` | `npm:wabt@^1.0.36` | `jsr:@jrmarcum/wabt-ts@^1.3.1/compat` |
| `"binaryen"` | `npm:binaryen@^116.0.0` | `jsr:@jrmarcum/binaryen-ts@^1.3.2/compat` |

**Current `deno.json` (2026-06-02):** `"wabt": "jsr:@jrmarcum/wabt-ts@^1.3.1/compat"` +
`"binaryen": "jsr:@jrmarcum/binaryen-ts@^1.3.2/compat"`. wabt-ts was bumped 1.3.0 → 1.3.1
to pick up the hex-float-literal parse fix (mathlib constants no longer encoded as 0;
recovers all four `38_*` Math tests — see bug table below). It had earlier been bumped
1.2.9 → 1.3.0 for the folded-`(call)`-before-`(return)` encoder fix (see bug table below);
binaryen-ts was bumped 1.3.1 → 1.3.2 to pick up the doubly-merged-module optimizer fix
(see bug table below — this let the Stage 0.7 `skipBinaryenOpt` merge-path workaround be
removed).

Either column may be mixed with the other (e.g. npm:wabt + binaryen-ts/compat,
or wabt-ts/compat + npm:binaryen). All four combinations work because the
`/compat` subpath modules on both JSR packages deliberately mirror their
upstream npm shape:

- `wabt-ts/compat` exports a default async factory whose resolved value owns
  `parseWat(filename, src, features)` and `readWasm(buffer, opts)` — same names
  and same return shape (an object with `.toBinary({})` / `.toText({...})` /
  `.destroy()`) as `npm:wabt`.
- `binaryen-ts/compat` exports the upstream `npm:binaryen` namespace surface
  (`readBinary`, `Features`, `setShrinkLevel`, `setOptimizeLevel`,
  `getExportInfo`, `getFunctionInfo`, `expandType`, type-ID constants, and the
  `Module` class with `.optimize()` / `.emitBinary()` / `.dispose()` /
  `.setFeatures()`).

**Why the wabt case needed a /compat module on the JSR side but the binaryen
case also did:** the JSR-native shapes of both packages predate the wasmtk
migration. wabt-ts's native API is `wat2wasm(src, opts) → {binary, errors,
result}` / `wasm2wat(bytes, opts) → {text, errors, result}` — different
function names, different return shapes, and stateless instead of factory.
binaryen-ts's native API is `createModule(builder) → Module` with an
`ExprBuilder` fluent helper — totally different from `npm:binaryen`. Neither
JSR package can be a drop-in until it ships an explicit compat facade. Both
now do.

**Source-side wiring:** the import statements in `src/utils.ts`,
`src/wasic.ts`, and `src/wasmbundle.ts` use the upstream-npm shape:

```ts
import wabt from "wabt";                  // default-export async factory
import binaryen from "./binaryen.ts";     // namespace re-exported via wrapper
```

For wabt this is direct: both `npm:wabt` and `wabt-ts/compat` ship a default
export, so `import wabt from "wabt"` works against either without any wrapper.

For binaryen there's a one-line asymmetry: `npm:binaryen` uses a CommonJS
default export and `binaryen-ts/compat` is a pure ES namespace with no default.
`src/binaryen.ts` is a 3-line wrapper that papers over this:

```ts
import * as ns from "binaryen";
const lib: any = (ns as any).default ?? ns;
export default lib;
```

`(ns as any).default` is truthy under npm:binaryen (CJS interop) and undefined
under binaryen-ts/compat — the `??` picks whichever shape is loaded. Call sites
then do a normal `import binaryen from "./binaryen.ts"` default import and the
rest of the code (`binaryen.readBinary(...)`, `binaryen.Features.All`,
`mod.optimize()`, etc.) works identically against either backend.

**`mergeOneWasmImport` retains its `wabtMod` parameter** (re-introduced when
the source was rebased on the upstream-npm shape). All call sites in
`compileWasiTs` / `compileLibTs` pass the resolved factory result. Both
backends are stateful at this layer (factory + module instance), so the
parameter has consistent meaning regardless of which package is loaded.

**Why we picked the upstream-npm shape as canonical:** both compat modules
mirror it, so writing call sites against it gives us perfect portability with
no per-backend `if (isWabtTs) ... else ...` branches. The native JSR-native
shapes (`wat2wasm` / `createModule`) would have required wrapping for the npm
side. Mirroring upstream is the cheaper direction.

**Why both compat modules:** brings the wasmtk compiler toolchain into the
jrmarcum-owned JSR ecosystem (see cmem/vision.md § "Stage 0.5") while keeping
upstream npm as an always-available fallback for the lifetime of the
migration. Eliminates the Emscripten WASM blobs from the wasic compile path
when the JSR backends are selected; the entire WAT→binary→optimization
pipeline then runs in native TypeScript on Deno/Bun/Node.

**How to apply:** When writing new code in `src/utils.ts`, `src/wasic.ts`, or
`src/wasmbundle.ts` that touches WABT or Binaryen, use the upstream-npm shape
(`await wabt()` + `parseWat` / `readWasm`; `binaryen.readBinary(...)` +
`Module` methods). Do not import from `"wabt"` directly without going through
the existing factory-await pattern, and do not import binaryen by any path
other than `./binaryen.ts` — both compat modules require these shapes. When
adding a new caller for binaryen in a fresh file, import from
`./binaryen.ts`, not from `"binaryen"` directly.

**Bugs found and filed in wabt-ts during the migration rollout** (filed
against versions 1.0.3 → 1.1.8 of the native JSR API; all fixed by 1.1.8.
The 1.2.1 `/compat` facade sits on top of the now-stable pipeline):

| Bug | Form | First broken | Fixed in |
| --- | --- | --- | --- |
| Folded expression rejection (e.g. `(local.set $x (global.get $g))`) | parser | 1.0.3 | 1.0.4 |
| Type section omitted from emitted binary | encoder | 1.0.4 | 1.0.5 |
| `call $name` nested under `(drop ...)` / `(select ...)` resolved to wrong function index when imports present | name resolver | 1.0.5 | 1.0.6 |
| Inline `(export "name")` on `(tag ...)` declarations rejected | parser | 1.0.6 | 1.0.9 |
| f64 integer literal encoded as `MIN_VALUE × value` (exponent bias never applied) | encoder | 1.0.9 | 1.1.0 |
| Multi-value `(return val1 val2)` only pushed one value | encoder | 1.1.0 | 1.1.2 |
| All memory ops emitted `align=0` regardless of natural alignment | encoder | 1.1.0 | 1.1.2 |
| `(i32.store ADDR (call ...))` swapped ADDR / VAL emission order | encoder | 1.1.2 | 1.1.4 |
| Parenless folded opcodes `(local.set $x)`, `(drop)`, `(global.set $g)` etc. — multi-value receive idiom failed | encoder | 1.1.4 | 1.1.6 |
| `(br_if N (f64.cmp (global.get $name) ...))` mis-resolved `$name` to global index 0 | name resolver | 1.1.6 | 1.1.8 |
| `call_indirect (type $name)` resolved to type index 0 regardless of which named type was referenced | name resolver | 1.1.8 | 1.2.1 |
| `(try (do BODY1) (catch $tag BODY2))` lost the try/catch opcodes during encoding; do-body and catch-body concatenated into a plain block | encoder | up to 1.2.8 | 1.2.9 |
| A folded `(call ...)` statement followed by an explicit `(return ...)` in the same function is encoded **after** the `(return ...)` (dead code) — the call never executes, silently dropping its side effects | encoder | found 2026-05-30 (≤1.2.9) | 1.3.0 |
| Hex-float literals (`0x1.921fb54442d18p+2`) parsed as `0` — `parseF32/F64LiteralBits` used JS `parseFloat`, which can't read hex-float notation; every merged-`mathlib` constant (π, e, ln2, all polynomial coeffs) encoded as 0 → garbage Math.* results → NaN/Inf trap in `$__f64_to_str` | parser | found 2026-06-02 (≤1.3.0) | 1.3.1 |

**`(call ...)` before `(return ...)` ordering bug (found 2026-05-30, FIXED in wabt-ts 1.3.0):**
Reproducer saved at `C:\Users\Jmarcum\TMP\repro_wabt_call_return_ordering.ts` (run
`deno run --allow-read --allow-net` on it). Minimal case: a two-function module where
`test()` does `(call $wc (i32.const 16))` then `(return (i32.load (i32.const 24)))` and
`$wc` stores 555 at address 24 — returned **0** under `wabt-ts/compat ≤1.2.9`, **555** under
`npm:wabt` and now under `wabt-ts/compat 1.3.0`. Byte evidence (≤1.2.9): the `test` body
encoded as `… i32.load; return(0f); call(10 00); end` (call sunk past the return) vs the
correct `call(10 00); … i32.load; return; end`. Trigger was an **explicit `(return …)`**;
implicit fall-through was fine; arg count irrelevant. **Impact while open:** blocked the
shared-heap stdlib track (Set/Map need `op(handle); …; return` patterns that mutate shared
linear memory across a call boundary) and could silently drop any `sideEffectingCall();
return X;` shape; masked in the suite because that shape is rare there. **Resolution:** fixed
upstream in `jsr:@jrmarcum/wabt-ts@1.3.0/compat` (deno.json bumped from `^1.2.9` to `^1.3.0`
on 2026-05-30). Full numbered suite re-validated at 230/239 under 1.3.0 + binaryen-ts 1.3.1
(same 9 known wasic-side failures; no regression). The brief temporarily switched dev to
`npm:wabt` but reverted to the JSR backend once 1.3.0 landed.

**Bugs found and filed in binaryen-ts during the migration rollout** (filed
against versions 1.2.2 → 1.2.8; all fixed by 1.2.9):

| Bug | Form | Fixed in |
| --- | --- | --- |
| Single-branch `if BODY` (no else) round-tripped as `if {} else BODY` — semantics inverted | parser↔encoder | 1.2.6 |
| `RemoveUnusedModuleElements` pass mangled `(tag ...)` type-index and stripped tag exports | optimization pass | 1.2.6 |
| Element segment dropped entirely on bare `readBinary → emitBinary` round-trip — `call_indirect` table never populated | parser↔encoder | 1.2.7 |
| `CoalesceLocals` pass produced runtime "function signature mismatch" on modules with multi-value-returning helpers + exception tags + call_indirect | optimization pass | 1.2.8 |
| `catch` body wrapped in spurious `(block ...)` during round-trip; tag's runtime-pushed params landed in the catch frame but `local.set` instructions in the inner block ran with empty stack | parser↔encoder | 1.2.9 |
| Re-optimizing a doubly-merged module (wasmmerge splices already-`-Oz`'d stack-form library into the driver) miscompiles division-heavy integer functions — runtime returns garbage / out-of-bounds while the pre-binaryen wabt assembly is correct; laundering binaryen's output through wabt does NOT recover it (corruption is in `optimize()`, not encoding) | optimization pass | 1.3.2 (the `skipBinaryenOpt` merge-path workaround was removed once 1.3.2 landed — see § "Stage 0.7 — merge-path codegen fixes") |

**Wasic-side patch made during the rollout** (`src/wasic.ts` lines 13096,
13137, 13219, 13253; `src/wasmbundle.ts` line 196): the `.toText({ foldExprs:
false })` call sites that disassemble imported `.wasm` modules for the
wasmmerge pass now pass `inlineExport: false` explicitly. wabt-ts/compat's
default for `inlineExport` differs from `npm:wabt`'s (was implicitly false
under npm:wabt, defaults to true under wabt-ts/compat). Without the explicit
flag, exports get baked inline inside `(func ...)` declarations and
`wasmmerge.ts`'s standalone-export regex fails to find them — surfacing as
"Unknown function" errors during phase 18 / 38 WASM-import merge. When adding
a new `.toText(...)` call site in wasic/wasmbundle, always pass `inlineExport:
false` explicitly.

Reproducers from the migration session were saved under `/tmp/test_*.ts` and
`C:\Users\Jmarcum\TMP\repro_*.ts` (Windows). Consult conversation transcript
or git history if any regression re-appears.

**Validation under the dual /compat setup** (wabt-ts/compat 1.2.9 +
binaryen-ts/compat 1.2.9, 2026-05-28): **260/270 PASS (96.3%) full wasic test
suite.** 10 remaining failures: 9 wasic-side codegen issues that predate the
migration (`15_panic` — top-level throw emits `proc_exit + unreachable`
instead of WebAssembly exception; `18_Multi-Scope`, `19_NestedDU`,
`19_VariantMax` — wasic emits structures that wabt-ts/V8 strict validation
rejects; `38_MathExpLog`/`38_MathHyperbolic`/`38_MathTrig`/`38_Phase38Combined`
— f64→i32 truncation in mathlib call paths produces "float unrepresentable in
integer range" traps; `5e_MixedSignatures` — same fallthru-stack family as
15_recover) and 1 toolchain pass interaction (`15_recover`: binaryen-ts/compat
full `-Oz` pipeline produces a binary with 2 dangling stack values at function
fallthru; raw round-trip and individual passes are all clean). The migration
is substantively complete.

**Subsequent validation under 1.2.9 + 1.3.1 + Stage 0.6 allocator unification**
(2026-05-30): **263/272 PASS (96.7%)** full wasic suite. binaryen-ts 1.3.1
fixed the 15_recover pass-interaction bug noted above (no longer fails the
`optimize()` pipeline), and the new `18b_SharedHeapTwoLibraries` regression
test for allocator unification passes. The 9 remaining failures are all from
the wasic-side group above. The 10th wasic codegen bug — `return expr as
unknown as i32` emitting a stray `f64.convert_i32_s` on the return path — was
uncovered while developing the 18b test (worked around there by returning
`.length`) and is now **fixed 2026-05-30** with the new `22_DoubleCastErasure`
regression test; see § "Type-erasure casts (`as unknown` / `as any`) are
stripped up front". See § "Stage 0.6 — Allocator Unification" for the
unification pass details.

---

### Bun compatibility — `src/rt.ts` + `package.json` + `bunfig.toml` + `"nodeModulesDir": "none"` (2026-04-18)

**Rule:** All runtime I/O must go through `rt.*` (never `Deno.*` directly). Bun global install uses `bun install -g @jsr/jrmarcum__wasmtk` (JSR npm compat path, no `.npmrc` needed). Version kept in sync across `deno.json`, `package.json`, and `src/utils.ts VERSION`.

**Why:** JSR's npm compatibility layer (`npm.jsr.io`) does not translate the `bin` field from `deno.json` into the generated npm `package.json` — so `package.json` with a `bin` field is required for Bun to create the global `wasmtk` binary. `bunfig.toml` sets `@jsr` registry to `https://npm.jsr.io/` so Bun resolves `jsr:` specifiers. `"nodeModulesDir": "none"` in `deno.json` prevents Deno from switching to node_modules mode (which triggers junction creation failures on Windows) when `package.json` is present.

**How to apply:** To bump the version, edit `version` in `deno.json` only — then run `deno task update-version` (or just run `deno task install` / `deno task publish`, which call it automatically). `scripts/sync-version.ts` propagates the new version to `package.json` and the `VERSION` constant in `src/utils.ts`. Do not add `dependencies` to `package.json` — Bun reads `deno.json` for the import map at runtime. Do not use `nodeModulesDir: "auto"` — it causes Windows junction failures.

### `tsbundle` outputs `.ts`, not `.js` (2026-05-24)

**Rule:** `wasmtk tsbundle <file.ts>` inlines all relative `.ts` imports into a single flat
TypeScript file using `bundleImports()` from `src/tsbundler.ts`. It does NOT transpile to
JavaScript. Default output: `file.bundled.ts`. Override with `-o`.

**Why:** The original `bundleTs` in `utils.ts` used `deno bundle` which transpiles TypeScript
to JavaScript (`.js`). This was incorrect — `tsbundler.ts` is a TypeScript import inliner
described as a *"pre-pass for the TypeScript-to-WASM compiler"*; the output must remain
TypeScript so it can be fed to `wasic`. Additionally, `deno bundle` has been deprecated in
recent Deno versions. The fix replaces the subprocess call with a direct `bundleImports()`
call and changes the default output extension from `.js` to `.bundled.ts`.

**How to apply:** Do not revert `bundleTs` in `utils.ts` to use `deno bundle` or any
JavaScript-emitting bundler. The default output path must use `.bundled.ts` (not `.ts`) to
avoid accidentally overwriting the entry-point source file when `-o` is not specified.

### `$__f64_to_str` — ×1e15 + shortest-round-trip pass (2026-04-15, improved 2026-05-01)

**Rule:** `$__f64_to_str` in `console_log.ts` uses a two-step algorithm:

1. **×1e15 step** — `f64.nearest(frac × 1e15)` → i64 gives up to 15 fractional digits.
2. **Shortest-round-trip loop** — starting from 15 digits, repeatedly strip the last digit
   and check if `f64(ipart) + f64(trial) / f64(10^k)` still equals the original value via
   `f64.eq`. Stop when stripping changes the round-trip result. A new `$__pow10_f64` WAT
   helper supplies exact f64 powers of 10 for n in [0, 15] (all exactly representable).

**Why:** The ×1e15 step occasionally introduced a spurious trailing digit (e.g.
`78.539816339744831` vs the correct `78.53981633974483`) because `frac × 1e15` in IEEE 754
can round 1 ULP away from the true 15-digit value. The shortening pass strips such artifacts.
Powers of 10 in [1, 1e15] are exact in f64 (≤ 50 significant bits), so reconstruction
arithmetic never introduces a false positive — a value is only stripped if it genuinely
round-trips. Grisu2 (~800B–1.2KB) and Ryu (~6–32KB) were considered; the shortening loop
achieves the same improvement for common cases at ~200–300 bytes of additional WAT.

**How to apply:** Do NOT revert to ×1e6 or remove the shortening loop unless explicitly
asked. One known remaining delta: `Math.SQRT2` prints `1.414213562373095` (WASM, 15 decimal
places) vs `1.4142135623730951` (JavaScript, 17 significant digits) — this requires MORE
digits than ×1e15 can produce and is not fixable by the shortening pass. The user has
accepted this as a known and understood limitation.

### `Math.round` — floor(x + 0.5), not `f64.nearest` (2026-04-15)

**Rule:** `Math.round` must emit `(f64.floor (f64.add x (f64.const 0.5)))`.

**Why:** WASM's `f64.nearest` uses IEEE 754 round-to-nearest-even (banker's rounding),
which gives `Math.round(2.5) = 2` instead of JavaScript's correct `3`. The fix is in
TWO places: `wasic.ts` (F64_UNARY table, now a special case before the table) and
`console_log.ts` (`exprToWat` Math handler, line ~588).

**How to apply:** If `Math.round` ever reverts to `f64.nearest` (e.g. during a refactor
of the F64_UNARY table), both files must be updated together.

### `applyRenames` lookbehind must be `(?<![\w.])` (2026-04-15)

**Rule:** In `tsbundler.ts`, the `applyRenames` regex lookbehind is `(?<![\w.])`, not `(?<!\w)`.

**Why:** `.` is not a word character, so `(?<!\w)` matches inside method calls like
`console.log(...)` when a renamed export is named `log`. This silenced the function body.
The dot exclusion prevents method-name collisions while standalone call sites still rename.

### `arr.find()` sentinel → `undefined` in console.log (2026-04-15)

**Rule:** Variables assigned from `.find()` calls must print `undefined` when not found.

**Why:** WASM uses `-1` (i32) or `NaN` (f64) as not-found sentinels (can't represent
`undefined`). Without a check, `console.log(notFound)` printed the raw sentinel.
`findResultVars: Set<string>` in `wasic.ts` tracks `.find()` variables; the console.log
handler wraps prints with a sentinel check.

### `@expect-fail` test marker (2026-04-15)

**Rule:** Negative tests use `// @expect-fail: compile` (or `run-ts`, `run-wasm`) in
the first 10 lines of the test file. `run_wasi_tests.ts` treats failure-as-expected as PASSED.

`ExternalMapping_11b.ts` was the reference negative test for undefined receivers. It is now a **passing** Phase 40 test — `declare const logger: { log(ptr: i32): void }` makes the compiler recognize `logger` as an external binding rather than an undefined identifier. Do not revert its `@expect-fail: compile` annotation.

### undefined dot-call receivers → compile error (2026-04-15)

**Rule:** `receiver.method(args)` where `receiver` is not a known class/interface/var
must exit with `❌ wasic: 'receiver' is not defined` (not silent drop).

**Why:** Previously the statement was silently dropped — WASM compiled but omitted the call.
The fix is in `dotCallStmt` block of `emitStatement` in `wasic.ts`.

### `WebAssembly.Exception` in runner must not crash (2026-04-14)

**Rule:** Uncaught WASM throw from `_start` must print `error: Uncaught (in Wasm) Error: <msg>`
to stderr and exit cleanly (code 0), not crash with exit code 1.

**Why:** `run-ts` exits 0 for unhandled TS throw (Deno discards subprocess exit code).
WASM run must match. Fix: `utils.ts` inner catch guards `err instanceof WebAssembly.Exception`,
decodes via `instance.exports.__exn_tag`, writes to stderr, returns cleanly.

### `console.log(fn())` where `fn()` returns `i32[]` (2026-04-14)

**Rule:** `FuncLookup` must expose `resultTsName` alongside `result`; `parseSingleArg`
checks `resultTsName` for `[]` suffix → `arrptr` LogSegment → `$__write_i32arr_to_scratch`.

**Why:** WAT result type for array-returning functions is always `i32` (heap pointer).
Without `resultTsName`, `console.log(getScores())` printed `260` instead of `[ 95, 88, 72 ]`.

### `console.log(Math.*)` must skip dotCallLookup (2026-04-14)

**Rule:** In `parseSingleArg` (`console_log.ts`), `dotCallLookup` must be guarded with
`!token.startsWith("Math.")` — all `Math.*` tokens fall through to the dedicated handler.

**Why:** `dotCallLookup` routed `Math.abs(-4.5)` through `emitExpr(..., "i32")` first,
producing invalid WAT like `(call $__i32_abs (i32.const -4.5))`.

### `as` cast / `findDepth0Keyword` bug patterns (2026-04-14)

- `findDepth0Keyword` must start scan at `expr.length - 1` (not `expr.length - needle.length`).
- Paren-group stripping must verify the outer `(` is balanced with the final `)` by walking the string.
- These guard `as` casts inside compound expressions like `(b * b) + (a as f64) + (c as f64)`.

### Value-fallthru rewrite — terminal void `if/else` that always returns (2026-06-02)

**Rule:** In `emitFunction` (`src/wasic.ts`), after the body is emitted, a value-returning
function (`watResult !== null`) whose last top-level WAT s-expr is a STATEMENT-level (void) `if`
is passed through `fixTerminalFallthru(body, rt)`, which rewrites that terminal void `if` into a
value-producing `(if (result rt) cond (then … X) (else … Y))` by turning each branch's trailing
`(return X)` into a bare value `X` (recursing through nested all-returning `if`s). Implemented with
module-level helpers `tokenizeWat` / `parseWatNodes` / `serializeWat` / `watNodeToValue` /
`watBranchToValue`.

**Why:** A function like `f(): i32 { if (c) { return A } else { return B } }` emits a void `if`
where both branches `return`, leaving the implicit function-end with an empty stack. wabt and
Binaryen accept this; **V8's strict validator rejects it** (`expected 1 elements on the stack for
fallthru, found 0`). Appending `(unreachable)` does NOT work — Binaryen `-Oz` strips the trailing
unreachable as dead code and re-emits the invalid void `if`. Making the `if` value-producing is the
form Binaryen preserves. Fixed `5e_MixedSignatures`, `19_NestedDiscriminantUnions`,
`19_VariantMaximumMemoryAlignment`.

**How to apply:** The rewrite is conservative — `watNodeToValue` only handles `(return X)` and a
void `if` with both `then` and `else` whose leaves recursively value; anything else returns null
and the body is left unchanged (so ill-typed/non-returning-path inputs are not mangled). Comments
and `"…"` data strings are skipped by `findLastTopLevelStart`. Do not replace this with an
`(unreachable)` suffix. NOTE (separate, still-OPEN): the single-physical-line brace form
`if (c) { return 1; } else { return -1; }` is a separate, still-open bug — `expandInlineBraceChain`
later addressed the original dropped-`else` symptom, but the expanded form still miscompiles
(f64/i32 return mis-type; inline-`if` fallthru). NOT this fallthru fix; the 3 fixed tests use the
multi-line form. Authoritative status: `cmem/compiler-bugs.md` § "OPEN (low priority) — single-line brace".

### Type-erasure casts (`as unknown` / `as any`) are stripped up front (2026-05-30)

**Rule:** In `emitExpr` (`src/wasic.ts`), before the Phase 22 ` as ` handler runs, strip
any `as unknown` / `as any` cast from the expression:

```typescript
if (/\bas\s+(?:unknown|any)\b/.test(expr)) {
  expr = expr.replace(/\s+as\s+(?:unknown|any)\b/g, " ").replace(/\s{2,}/g, " ").trim();
}
```

This reduces the double-cast idiom `expr as unknown as T` → `expr as T` and a bare
`expr as unknown` → `expr`.

**Why:** `unknown` and `any` have no WAT representation — `mapType("unknown")` falls
through to `f64`. The ` as ` handler scans right-to-left, so `buf as unknown as i32`
recursed into the intermediate `buf as unknown`, casting an i32 pointer i32→f64 before
the outer `as i32` ran. The result was a stray `(f64.convert_i32_s ...)` on an
`(result i32)` return path → `type error in return[0] (expected i32, got f64)` at
instantiate time. Stripping the erasure leaves a simple inner operand (`buf`) so the
single-cast path infers the correct source type from `locals`.

**How to apply:** Keep the strip BEFORE the ` as ` handler. The `\b` word boundaries in
the guard prevent false matches on identifiers ending in "as"/containing "any" (e.g.
`canvas`, `has`). Regression test: `tests/wasm_wasi/22_DoubleCastErasure.ts`. This
unblocks pointer-typed `as unknown as i32` returns for the Tier-1 stdlib libraries
(brief §7a).

### `throw` inside try/catch must use WASM exception instruction (2026-04-14)

**Rule:** Throws inside try/catch blocks must emit `(throw $__exn_tag ptr len)`, not `proc_exit`.

**Why:** `proc_exit` terminates the process before the catch can fire. The fix is in
`wasic.ts` throwMatch handler. `needsExceptionTag = true` ensures the tag is declared.

### `console.log(structFn())` must print fields, not pointer (2026-04-08)

**Rule:** When `console.log`'s sole argument is a call to a struct-returning function,
store the result to `$__struct_tmp` and emit field-load LogSegments, not `$__i32_to_str`.

**Why:** Struct pointers are `i32` in WAT — `resultTsName` (from `FuncDef`) is the
authoritative signal that the value is a struct, not a plain integer.

### Phase 24 — Nullable variables: two-local scheme (2026-04-17)

**Rule:** `const x: i32 | null = ...` declares TWO WAT locals: `$x` (value) and `$x__null`
(i32 flag: 1=null, 0=has-value). Nullable function returns use a module-level global
`$__nullable_ret_flag` (1=has-value, 0=null) as a side-channel: callee sets it, caller
reads it immediately after call. Pre-scans in both `emitFunction` and `startBodyLines`
detect `T | null` annotations via `parseNullableAnnotation()` and register both locals.

**Why:** Avoids heap boxing and multi-value WAT returns; WASM is single-threaded so the
global side-channel is safe. `nullableVarInnerType: Map<string, WatType>` in `WasicTranspiler`
is reset at the start of every `emitFunction` call.

**How to apply:** When extending nullable support, always check BOTH the `emitFunction`
pre-scan (line ~6317) AND the `startBodyLines` pre-scan (line ~6871) — they are parallel
and both must register `__null` locals. `console.log` of a nullable var is handled in
`emitStatement` logMatch via `nullableVarInnerType.has(logSingleArg)` check.

### Phase 25 — `??` operator must be handled before binary ops table (2026-04-17)

**Rule:** `??` is detected and emitted before the general binary ops table loop in
`emitExpr`. `findBinaryOp` guards prevent `||` / `&&` / `??` from matching `||=` / `&&=` / `??=`.
Logical assignment (`??=`, `||=`, `&&=`) is handled by a dedicated `logicalAssignMatch`
block in `emitStatement` that supports both locals AND module globals.

**Why:** `??` doesn't map to a single WAT instruction — it emits a WAT `(if (result T) nullFlag (then rhs) (else lhs))` block. The `||=` / `&&=` guard is critical because these
operators contain `||` / `&&` as prefixes, which the RTL binary-op scan would match first
without the `after === "="` guard.

### Phase 26 — `for...of` uses `$__forof_idx` local + `collectBlock` in `parseTopLevel` (2026-04-17)

**Rule:** `for...of` iterates via a shared `$__forof_idx` (i32) local registered in pre-scans of both `emitFunction` and `startBodyLines`. Access patterns differ: static arrays use `(i32.const ptr)` base + compile-time length; dynamic arrays use `(i32.load arr)` length + 8-byte header offset; array params (ptr=-1) use `(local.get $arr)` as base with `(i32.load arr)` for length.

**Why:** Module-level `for...of` required a `collectBlock` flag fix in `parseTopLevel` — without it, `depth` was never updated for pattern-4 lines, so the loop body was silently stripped. Array destructuring with defaults (`const [a = 10] = arr`) required extracting the binding name by splitting on `=` in both emission and pre-scan paths.

**How to apply:** When adding new module-level control flow (while, for...in, etc.), verify `parseTopLevel` correctly tracks brace depth and collects inner lines into `startBodyLines`. For `for...of` over array function params, use the `ptr === -1` branch (no header offset).

### `switch` on `f64`/`number` variables — use `f64.eq`/`f64.const` (2026-04-18)

**Rule:** In `wasic.ts` switch statement emission, detect the WAT type of the switch expression before emitting dispatch. If the expression resolves to `f64` (or `f32`) — via `locals.get` or `moduleGlobals.get` — emit `f64.eq` with `f64.const` case values instead of `i32.eq`/`i32.const`. The detected `switchType` also drives `emitExpr(v, locals, switchType)` for each case value.

**Why:** `const val: number = 2` declares a `f64` WAT local. The previous code always emitted `(i32.eq (local.get $val) (i32.const 1))`. Binaryen aborted with `Assertion failed: type == Type::f64` when the f64 local was passed to an i32.eq with an i32.const literal — type mismatch in the literal node.

**How to apply:** The `switchType` variable is local to the switch-statement block in `emitStatement`. Both the `emitExpr(switchExpr, ...)` call and the per-case `emitExpr(v, ...)` call must use `switchType`. i32.or is still correct for multi-value cases since both `i32.eq` and `f64.eq` return `i32`.

### `String(e)` and `instanceof Error` ternary in catch blocks (2026-04-18, extended 2026-05-22)

**Rule — `console_log.ts` (original, 2026-04-18):** In `parseSingleArg`, two patterns must be detected and converted to `strvar` (ptr+len) before the generic function-call handler runs:

1. `String(varName)` where `varName` has `locals.get(varName) === "string"` → `{ kind: "strvar", ptrLocal: "varName_ptr", lenLocal: "varName_len" }`
2. `VAR instanceof Error ? VAR.message : String(VAR)` where `VAR` is a string local → same `strvar`

**Why (original):** WASM catch blocks bind the exception payload as `$e_ptr`/`$e_len` locals (type "string" in the locals map). `String(e)` fell through to the function-call handler, which emitted `(call $String (local.get $e))` — `$String` and `$e` are both undefined. The instanceof ternary fell through to `exprToWat(..., "f64")` and produced unresolvable comment-stubbed WAT.

**How to apply (original):** Both checks must run before the `callMatch` regex in `parseSingleArg`. The instanceof ternary regex uses a backreference (`\1`) to ensure the same variable name appears in all three positions.

**Rule — `wasic.ts` `emitStringAssign` (extended, 2026-05-22):** When these patterns appear as the RHS of a `const`/`let` string assignment, `emitStringAssign` must handle them — `parseSingleArg` only covers `console.log` context:

1. **`VAR instanceof Error ? VAR.message : String(VAR)`** — detected by `/^(\w+)\s+instanceof\s+Error\s*\?\s*\1\.message\s*:\s*String\s*\(\s*\1\s*\)/` before the generic ternary handler. Since all wasic exceptions are plain strings, always simplifies to a direct ptr/len copy: `(local.set $msg_ptr (local.get $e_ptr)) / (local.set $msg_len (local.get $e_len))`. Produces the message text without "Error: " prefix (matching `e.message`).

2. **`String(catchVar)`** where `catchVar ∈ this.catchVarNames` — detected in the `String(n)` handler before the numeric path. Emits `(call $__str_concat "Error: " e_ptr e_len)` to match JavaScript's `Error.prototype.toString()` output: `"Error: <message>"`.

**`catchVarNames: Set<string>` and `catchVarShadows: Set<string>`** — two new fields on `WasicTranspiler`, reset at the start of each `emitFunction` / `startBodyLines` call:

- `catchVarNames` — populated in both pre-scans whenever `} catch (cv) {` is encountered; used by `String(cv)` in `emitStringAssign` to select the "Error: " prefix path
- `catchVarShadows` — populated when `cv` already exists in `locals` as "string"; used by the try/catch emission in `emitBlock` to select the alias local path (see below)

### Catch variable lexical scoping — shadow alias locals (2026-05-22)

**Rule:** When `catch (cv)` appears inside a function that already has a string variable named `cv` in scope, use a WAT alias local `$__catch_cv_ptr` / `$__catch_cv_len` for the catch payload instead of `$cv_ptr` / `$cv_len`. Rename all references to `cv` inside the catch body to `__catch_cv` before emission.

**Why:** WAT locals are function-wide — there is no block scoping. Before this fix, the inner catch block set `$e_ptr`/`$e_len` to the caught exception value, overwriting the outer string variable. After the inner catch re-threw, the outer catch accessed `$e_ptr`/`$e_len` and found the inner value ("Inner Literal Error") instead of the outer one ("Outer String"). This broke the TypeScript guarantee that a catch variable only shadows within its own catch block.

**Implementation (in `wasic.ts`):**

1. **Pre-scan** (`emitFunction` and `startBodyLines`): when `} catch (cv) {` is encountered and `locals.has(cv) && locals.get(cv) === "string"`, add `cv` to `catchVarShadows` and declare `[__catch_cv_ptr, i32]` / `[__catch_cv_len, i32]` as additional locals (do NOT re-declare `cv_ptr` / `cv_len` — they already exist for the outer variable).

2. **Emission** (`emitBlock`, try/catch handler): compute `catchShadowsOuter = this.catchVarShadows.has(catchVar)`. When true:
   - `internalCatchVar = "__catch_" + catchVar`
   - Patch catch body lines: `catchBody.map(l => l.replace(/\bcv\b/g, "__catch_cv"))`
   - Temporarily add `__catch_cv → "string"` to locals and stringVars for body emission
   - Emit `(local.set $__catch_cv_len)` / `(local.set $__catch_cv_ptr)` in the catch handler
   - Remove the alias from locals/stringVars after body emission

3. **Re-throw correctness**: `throw cv` in the catch body is renamed to `throw __catch_cv` by the regex patch, so it correctly re-throws the caught value (`$__catch_cv_ptr`/`$__catch_cv_len`) without corrupting the outer `cv`.

**How to apply:** Any future refactor of the try/catch emission path must preserve the `catchVarShadows` check. The outer `cv` locals are never written by the inner catch, so the outer scope reads the correct value even when a re-throw skips the restore.

### `_lhsFnResult` must use direct `^(\w+)\s*\(` match, not `_lhsLeadId` (2026-05-12)

**Rule:** In the binary operator type-inference block of `emitExpr` (`wasic.ts`), `_lhsFnResult` must be computed by matching `lhs.match(/^(\w+)\s*\(/)` directly, not by reusing `_lhsLeadId`.

```typescript
// Correct:
const _lhsFnName = lhs.match(/^(\w+)\s*\(/)?.[1];
const _lhsFnResult = _lhsFnName
  ? this.functions.find(f => f.name === _lhsFnName)?.result ?? null
  : null;
```

**Why:** `_lhsLeadId` is set to `undefined` when `lhs.includes(".")` is true — even when the dot appears inside the function arguments, not on the caller. For `intMin(tests[i].a, tests[i].b)`, `_lhsLeadId` was `undefined` because `tests[i].a` contains a dot. This caused `_lhsFnResult` to be `null` and the comparison type fell back to `"i32"` instead of `"f64"`, producing a WASM type error: `i32.ne[0] expected type i32, found call of type f64`.

**How to apply:** The `_lhsFnName` match extracts only the word before the first `(`, which never contains a dot — so it safely identifies the function name for direct calls like `funcName(obj.field, ...)` without false-matching struct dot-access expressions.

### `<<` operator — `findBinaryOp` must guard `before === "<"` (2026-05-12)

**Rule:** In `findBinaryOp` (`wasic.ts`), the `<` operator guard must check both sides:

```typescript
if (op === "<" && (after === "=" || after === "<" || before === "<")) continue;
```

**Why:** `findBinaryOp` scans right-to-left. In `(b0 & 3) << 4`, the scan finds the *second* `<` of `<<` first (the rightmost `<`). The old guard only skipped the *first* `<` (where `after === "<"`), not the second (where `before === "<"`). Result: `(b0 & 3) << 4` was misparsed as a double `i32.lt_s` chain. The `>` guard already had `before === ">"` for the same reason — the `<` guard was missing the symmetric check.

**How to apply:** If `findBinaryOp` guards are ever extended for other new operators (e.g. `**`), always add guards for both the first and last character of the multi-char operator.

### Single-line `if (cond) body` — use balanced-paren scan, not greedy regex (2026-05-12)

**Rule:** The `if`-statement detector in `emitBlock` must use a depth-tracked balanced-paren scan to find where the condition ends, not a greedy regex `(.+)`.

```typescript
// Correct approach (emitBlock, wasic.ts):
let ifMatch: string[] | null = null;
if (/^if\s*\(/.test(line)) {
  const openIdx = line.indexOf("(");
  let depth = 0, condEnd = -1;
  for (let j = openIdx; j < line.length; j++) {
    if (line[j] === "(") depth++;
    else if (line[j] === ")") { if (--depth === 0) { condEnd = j; break; } }
  }
  if (condEnd !== -1) {
    ifMatch = [line, line.slice(openIdx + 1, condEnd), line.slice(condEnd + 1).trim()];
  }
}
```

**Why:** The old regex `line.match(/^if\s*\((.+)\)\s+(\S.*)$/)` used greedy `.+` for the condition. For `if (i > 2) result += String.fromCharCode(...)`, it captured `i > 2) result += ...fromCharCode(...)` as the condition — up to the *last* `)` on the line. The body became just `;`. Balanced-paren extraction correctly stops at the first matching `)`.

**How to apply:** Any place wasic parses `keyword (expr) body` from a single line should use depth-counted scanning, not a greedy regex. This latent bug affects any single-line `if` whose body contains a function call.

### `String.fromCharCode(arg)` / `str.charAt(arg)` regex — use `.+` not `[^)]+` (2026-05-12)

**Rule:** Regexes that capture a function argument between `(` and `)` must use `.+` (with `$` anchor), not `[^)]+`.

**Why:** Index expressions like `(b0 >> 2) & 63` and `((b0 & 3) << 4) | ((b1 >> 4) & 15)` contain inner `)` characters. `[^)]+` stops at the first `)`, producing a partial-match fallthrough that silently generates a no-op. With `.+` and `$`, the greedy match finds the last `)` before the pattern end.

**How to apply:** Applies to `fccDirect` (in `emitStringAssign`), `fccCP`, and `caCP` (in `appendConcatPart`) in `wasic.ts`. Reserve `[^)]+` only when nesting is provably impossible (e.g. simple identifier or integer literal arguments).

### `String.fromCharCode` and `str.charAt(idx)` in string concat (2026-05-12)

**Rule:** Both `String.fromCharCode(n)` and `str.charAt(idx)` must be handled in:

1. `emitStringAssign` (direct assignment: `const c: string = String.fromCharCode(x)`)
2. `appendConcatPart` (as part of a `+` chain: `result += chars.charAt(idx)`)
3. `isStringExpr` (so the concat-flattener recognises them as string-producing expressions)
4. `emitFunction` and `startBodyLines` prologue (declare `$__str_op_ptr`/`$__str_op_len` temp pair when body contains these calls)

**Why:** `$__str_char_at` returns `(result i32 i32)` (ptr, len) — the multi-value return requires a temp pair to capture the result before feeding it to `$__str_concat`. Without temp-pair declaration, the locals are absent at WAT assembly time.

**How to apply:** All four sites must be updated together whenever a new "single-char string producer" (like a future `String.fromCodePoint`) is added. Check `$__str_op_ptr`/`$__str_op_len` are declared when any body line contains the new call.

### `str.slice()` regex — add `parenDepthNeverNegative` guard (2026-05-12)

**Rule:** Any regex of the form `/^(\w+)\.slice\s*\((.+)\)$/` must be followed by a `parenDepthNeverNegative(matchedArgs)` guard before using the matched args.

```typescript
function parenDepthNeverNegative(s: string): boolean {
  let d = 0;
  for (const ch of s) {
    if (ch === "(" || ch === "[") d++;
    else if (ch === ")" || ch === "]") { if (--d < 0) return false; }
  }
  return true;
}
```

**Why:** The greedy `.+` matches the last `)` on the line. For `s.slice(0, idx) + nw + s.slice(idx + old.length)`, group 2 captures `0, idx) + nw + s.slice(idx + old.length` — consuming past the first call's closing `)`. The `sliceArgs.length === 2` check does NOT catch this: `splitArgs` on the malformed string yields 2 elements because the stray `)` briefly pushes depth to -1 and then `s.slice(` brings it back to 0. Only `parenDepthNeverNegative` detects the intermediate negative depth.

**How to apply:** Apply this guard in every `.slice()` handler: `sliceAnyM` in `emitStringAssign`, `sliceSPLM` in `emitStringPtrLen`, and `sliceCP` in `appendConcatPart`.

### `str.indexOf(sub, pos)` 2-arg form needs `$__str_indexof_from` (2026-05-12)

**Rule:** When `splitArgs(rawArgs).length >= 2`, use `$__str_indexof_from` instead of `$__str_indexof`:

```typescript
if (argsArr.length >= 2) {
  const fromWat = this.emitExpr(argsArr[1].trim(), locals, "i32");
  wat = `(call $__str_indexof_from ... ${subPtrLen} ${fromWat})`;
} else {
  wat = `(call $__str_indexof ... ${subPtrLen})`;
}
```

`$__str_indexof_from` lives in `getStringOpHelperWat()` and takes an extra `(param $from i32)` — the outer loop starts at `max(0, from)` instead of 0.

**Why:** Without this, any `while` loop that advances a `pos` variable via `s.indexOf(sub, pos)` infinite-loops — indexOf always restarts from 0, so `pos` never advances past the first match. Affected patterns: `count`, `replaceAll`, `split`.

**How to apply:** Whenever adding a string method with an optional start-position arg, add a `_from` WAT variant and branch on `argsArr.length` at the call site.

### `str.slice()` positions must use `emitArrayIndex`, not `emitExpr(..., "i32")` (2026-05-12)

**Rule:** Always use `this.emitArrayIndex(expr, locals)` for slice start/end arguments — never `this.emitExpr(expr, locals, "i32")`.

**Why:** Slice positions are i32 in WAT but the TypeScript variable is typed `number` (→ `f64` in WAT). `emitExpr(..., "i32")` passes the `f64` value without truncation, causing a WASM type error. `emitArrayIndex` calls `inferExprType` and wraps with `(i32.trunc_f64_s ...)` when needed.

**How to apply:** Applies to `sliceSPLM` (in `emitStringPtrLen`), `sliceCP` (in `appendConcatPart`), and any future `.slice()` handler. The existing `sliceAnyM` in `emitStringAssign` already uses `emitArrayIndex` — match that pattern.

### `str.slice()` in string comparison — `emitStringPtrLen` multi-value return (2026-05-12)

**Rule:** To support `s.slice(0, prefix.length) === prefix`, add a `sliceSPLM` handler in `emitStringPtrLen` that returns the full `(call $__str_slice ptr len start end)` as a single expression. WASM multi-value semantics automatically splits the two return values into the two `(param i32)` slots of `$__str_cmp`.

Also update the `lhsType` determination in the binary op handler to detect `str.slice(...)` as type `"string"`:

```typescript
const _lhsSliceRecv = lhs.match(/^(\w+)\.slice\s*\(/)?.[1];
const _lhsIsStrSlice = _lhsSliceRecv !== undefined && locals.get(_lhsSliceRecv) === "string";
const lhsType = alwaysI32 ? "i32" : (_lhsIsStrSlice ? "string" : (_dotFieldType ?? ...));
```

**Why:** Without `_lhsIsStrSlice`, `lhs.includes(".")` caused `_lhsLeadId = undefined`, so `lhsType` fell through to `defaultType = "i32"` — the string comparison path was never taken.

### `str.slice()` in string concat — temp pair via `$__str_op_ptr/$__str_op_len` (2026-05-12)

**Rule:** In `appendConcatPart`, handle `str.slice()` with the same temp-pair pattern as `charAt`:

```typescript
stmts.push(`(call $__str_slice ${ptrW} ${lenW} ${startWat} ${endWat})`);
stmts.push(`(local.set $__str_op_len)`);
stmts.push(`(local.set $__str_op_ptr)`);
concatAppend(`(local.get $__str_op_ptr)`, `(local.get $__str_op_len)`);
```

The `$__str_op_ptr/$__str_op_len` prologue check must include `.slice(` alongside `String.fromCharCode(` and `.charAt(`:

```typescript
fn.bodyLines.some(l =>
  l.includes("String.fromCharCode(") || l.includes(".charAt(") || l.includes(".slice(")
)
```

**Why:** `splitTwoWatExprs` cannot split a multi-value call into two separate expressions, so the `emitStringPtrLen` fallback path cannot be used inside `appendConcatPart`. The temp-pair captures both return values before `$__str_concat` consumes them.

### Inline string array literals in `console.log` — `setStringArrayAllocator` singleton (2026-05-12)

**Rule:** When `["a", "b"]` appears as a function argument inside `console.log(fn(["a", "b"], ...))`, compile it via a module-level singleton in `console_log.ts`:

```typescript
let _strArrAlloc: ((elements: string[]) => number) | undefined = undefined;
export function setStringArrayAllocator(fn: ((elements: string[]) => number) | undefined): void {
  _strArrAlloc = fn;
}
```

In `wasic.ts`, wrap each `parseConsoleLogArgs` call:

```typescript
setStringArrayAllocator((elems) => this.allocArrayData(elems, "string"));
const segments = parseConsoleLogArgs(...);
setStringArrayAllocator(undefined);
```

In `exprToWat` in `console_log.ts`, detect string array literals and call `_strArrAlloc`.

**Why:** Threading a new callback through 35+ call sites in `console_log.ts` is impractical. The singleton is safe because wasic compilation is synchronous. The fix applies to both `console.log` and `console.error` `parseConsoleLogArgs` calls.

### String literal method calls in `console.log` — pre-compute at compile time (2026-05-12)

**Rule:** `"TEST".toLowerCase()` and `"test".toUpperCase()` on string literals must be pre-computed in `parseSingleArg` in `console_log.ts`, before the `callMatch` handler:

```typescript
const strLitMethodMatch = token.match(/^(["'])(.*?)\1\.(toLowerCase|toUpperCase)\s*\(\s*\)$/);
if (strLitMethodMatch) {
  const text = strLitMethodMatch[3] === "toLowerCase"
    ? strLitMethodMatch[2].toLowerCase()
    : strLitMethodMatch[2].toUpperCase();
  return [{ kind: "literal", text }];
}
```

**Why:** The dot-call handler (`/^(?:this|\w+)\./`) does not match `"string".method()` because the receiver starts with a quote, causing fallthrough to an unresolved stub. Pre-computing at compile time avoids needing a runtime helper for the trivial case.

### `isModuleGlobalArr` must check `arrayVars.ptr === -2`, not `moduleArrayVars.has()` (2026-05-12)

**Rule:** `isModuleGlobalArr(arrName)` must check:

```typescript
return this.moduleGlobals.has(arrName) && this.arrayVars.get(arrName)?.ptr === -2;
```

NOT the previous:

```typescript
return this.moduleArrayVars.has(arrName) && this.moduleGlobals.has(arrName);
```

**Why:** `emitFunction` seeds `arrayVars` from `moduleArrayVars` then overrides rest-parameter entries with `ptr: -1`. A function like `function sum(...nums: number[])` that has the same name as a module-level global `const nums: number[] = [...]` would cause `isModuleGlobalArr("nums")` to return `true` even inside `sum`'s body, because `moduleArrayVars` still holds the global entry. All `arrGetWat`/`arrSetWat` calls then emit `(global.get $nums)` instead of `(local.get $nums)`, producing wrong WAT (reads from the global rather than the parameter). The `-2` ptr sentinel is the definitive marker for a module-level global array: module-level declarations set `ptr: -2` in `moduleArrayVars.set(...)`, while function parameters always set `ptr: -1`. Checking the current `arrayVars` entry (which reflects any local override) rather than the frozen `moduleArrayVars` snapshot correctly handles shadowing.

**How to apply:** Any future refactor of the array-variable tracking maps must preserve the `-2` / `-1` sentinel distinction. Do not check `moduleArrayVars.has()` alone to decide whether to emit `global.get` — always check the live `arrayVars` entry's `ptr`.

### Spread calls (`fn(...arr)`) must check `moduleGlobals` for `global.get` vs `local.get` (2026-05-12)

**Rule:** All three spread-call emission sites in `wasic.ts` must choose between `global.get` and `local.get` based on whether the spread source is a module global:

```typescript
const arrGet = this.moduleGlobals.has(arrName) ? `(global.get $${arrName})` : `(local.get $${arrName})`;
```

The three sites are: the `spreadCallMatch` handler in `emitExpr` (pure spread expression `fn(...arr)`), the rest-var-call handler in `emitStatement` (`const r = fn(...arr)`), and the rest-call-stmt handler in `emitStatement` (`fn(...arr);` as a statement).

**Why:** `sum(...nums)` at module level — where `nums` is a module global — was emitting `(call $sum (local.get $nums))`. WAT assembly fails immediately with "undefined local variable `$nums`" since the `_start` function has no such local. The spread array must be accessed as `(global.get $nums)` when declared at module scope.

**How to apply:** These three sites must be kept in sync. If a fourth spread-call form is ever added, apply the same `moduleGlobals.has` check.

---

## Phase Design Notes

### Phase 5h — Shared Mutable Captures (COMPLETE)

Variables captured by 2+ closures AND mutated in a `return { ... }` object literal are
heap-boxed: `parseFunctions` detects `sharedMutableCaptures`; factory allocates a 4-byte
cell and stores initial value; each closure factory receives the cell pointer; reads emit
`(i32.load (local.get $ptr))`; `count++`/`count--`/`count += x`/`count = x` all emit
store-through-pointer. The standalone `count++` handler is separate from compound assignment
and must be patched independently.

### Phase 18 — WASM Import Bundling (COMPLETE)

Two detected forms: `import { fn } from "./path.wasm"` (ESM) and `wasm_import("./path.wasm")`
(universal-wasm-loader). Both support rename aliases. Pipeline: detect → pre-register
signatures into `WasicTranspiler.externalFuncs` → transpile → disassemble → strip entry-only
features → mangle → relocate data segments → deduplicate WASI → splice → Binaryen `-Oz`.
`iovBase`/`scratchBase` are instance variables (not constants) for collision-free merge.

### Phase 20 — Export Name Transparency (COMPLETE)

`mergeWasmWat` emits `(export "add" (func $mathlib_add))` — original name preserved, internal
mangling unchanged. `WatMergeResult.exportMap: Map<string, string>` added. `wasmbundle`
upgraded to 4-option conflict prompt: prefix / alias / exclude / stop. `bundle` CLI renamed
to `tsbundle`. `--alias file=name` and `--on-conflict=alias` flags added.

**wasmbundle bug fixes (2026-05-24):** Four bugs fixed to make the Phase 18 pipeline test (`modc → wasic → wasmbundle → run`) work:

1. **`getDataMaxEnd()` regex** (`src/wasmbundle.ts`): Old regex `/\(data\s+\(i32\.const\s+(\d+)\)...)/` did not match wabt's indexed format `(data (;0;) (i32.const N) "...")`. Fixed to `\(data\s+(?:\(;[^;]*;\)\s+)?\(i32\.const\s+(\d+)\)` — makes `(;N;)` optional. Without this fix, data segment sizes were always 0, no data relocation occurred, and both modules' data overlapped at offset 260.

2. **ENTRY_ONLY stripping in wasmbundle mode** (`src/wasmmerge.ts`): `mergeWasmWat` unconditionally stripped `_start` from `exportFuncMap` and `proc_exit` from `importMap`. This broke wasmbundle mode: `_start` was never emitted as an export (bundle had no entry point), and `proc_exit` lost its `funcName` entry so `call 0` in `_start`'s body remained as a numeric index — causing `parseWat failed` (raw numeric call targets are invalid in named WAT). Fix: added `const skipEntryStrip = exportOverrides !== undefined` — when wasmbundle passes `exportOverrides`, ENTRY_ONLY stripping is skipped so `_start` and `proc_exit` are preserved.

3. **`_start` in export overrides** (`src/wasmbundle.ts`): `extractExportNames` excluded ENTRY_ONLY names, so `_start` was never in `mod.exports` and never added to the `overrides` map. Fix: after `extractExportNames(wat)`, detect `_start` via regex on the raw WAT and push it into `exports` when present.

4. **Import order in master WAT** (`src/wasmbundle.ts`): Master WAT emitted `(memory N)` BEFORE the WASI import declarations, violating WAT spec (all imports must precede definitions). Fix: moved `(memory N)` after WASI imports. Also: added `(export "memory" (memory 0))` to the master WAT — the wasmtk runner accesses `exports.memory` to resolve WASI I/O; without this export, `memory.buffer` access threw a TypeError.

**`@test-pipeline` / `@step` annotation system** (`tests/wasi_tests.ts`): New comment-based descriptor format for pipeline tests. A file with `// @test-pipeline` at the top triggers custom command execution instead of the standard compile/run-ts/run-wasm flow. Each `// @step subCmd arg1 arg2 ...` line specifies a wasmtk sub-command to run; paths are resolved relative to the test file's directory. The pipeline test `tests/wasm_wasi/18_WasmImportMerge.ts` exercises the full 4-step Phase 18 bundle pipeline.

**Phase 18 stress test compiler fixes (2026-05-24):** Seven fixes to `src/wasic.ts` and `src/wasmmerge.ts` to support the `18_Multi-ScopeScaleAndMemoryLongevityTest.ts` pattern set:

1. **`Array.from({ length: N }, () => [])` source pre-pass** (`src/wasic.ts`): The pattern is replaced with the internal sentinel `__arr_from_2d__(N)` BEFORE `parseFunctions()` runs. Without this ordering, `liftInlineArrows()` operated on collected `bodyLines` that still contained `() => []`, lifting it to a spurious `$__anon_0` WAT function with wrong return type and missing `$__arr_tmp` local. Pre-pass placement: immediately before the `this.parseFunctions()` call in `transpile()`.

2. **`arr2DPre` sentinel matching** (`src/wasic.ts`, `emitFunction` and `startBodyLines` pre-scans): Both pre-scan sites updated to match `__arr_from_2d__(N)` as the RHS of a 2D array declaration and populate `arrayFromExpr` on the `ArrayInfo` entry, registering `__from_n` and `__from_i` locals for the runtime initialization loop.

3. **`Array<{ field: number; ... }>` anonymous struct fields — `number` → `i32`** (`src/wasic.ts`, `funcArrPreF` handler): When the inline anonymous struct type contains `number`-typed fields (e.g. `namePtr: number`, `typeId: number`, `addr: number`), those fields must map to `i32` (pointer/id semantics), not `f64`. Fix: `const ftype = (rawFtype === "number") ? "i32" : (mapType(rawFtype) as WatType)` in the anonymous-struct field parser.

4. **`const target = arr[i]` struct-variable registration** (`src/wasic.ts`, both pre-scans): When the RHS of a `const`/`let` declaration is `arrName[idx]` and `arrName` has a `structTypeName`, the target variable is registered in `structVars` so subsequent `target.field` accesses resolve field offsets. Without this, `const entry = variableRecords[j]; console.log(entry.namePtr)` failed to find the struct definition.

5. **`tryAllocStructLiteralPtr` runtime-variable rejection** (`src/wasic.ts`): The function now uses `parseDepth0FieldsWithShorthand` to detect all field values (including shorthand properties) and rejects the literal as non-static if any value fails `isCompileTimeConst()`. Previously, `parseDepth0Fields` silently ignored shorthand and non-constant fields; `parseFloat("depth")` returned `NaN`, `NaN || 0 = 0` — causing `allocStructData` to write zeros to a static slot and return that pointer, breaking runtime struct values. Now falls through to `emitRuntimeStructLiteral` correctly for any literal containing runtime variables.

6. **`bracket2DMatch` defaultType coercion** (`src/wasic.ts`): When a `f64[][]` element is read in an `i32` context (e.g. `const namePtr = nameMatrix[depth][v]` where `nameMatrix: f64[][]` but `namePtr` inferred as `i32`), wrap the `f64.load` with `(i32.trunc_f64_s ...)`. Safe for safe-integer-range values stored as f64. Applied via `if (elemType === "f64" && defaultType === "i32") return \`(i32.trunc_f64_s ${raw2D})\``.

7. **Mutable globals relocation in `wasmmerge.ts`** (`src/wasmmerge.ts` + `src/wasic.ts` merge call site): Imported WASM modules with `(mut i32)` globals (e.g. a bump allocator `$free_ptr`) had their initial value overwritten to `2 * 65536 = 131072` (page-2 boundary) to avoid collision with the main module's data/heap. `WatMergeResult` gains `hasMutableGlobals: boolean`; `mergeOneWasmImport` propagates it; `compileWasiTs` patches the main module's `(memory N)` to at least 3 pages when `hasMutableGlobals` is true.

**`tsbundle` implementation correction (2026-05-24):** The original `bundleTs` in `utils.ts`
used `deno bundle` (which transpiles TypeScript → JavaScript, output `.js`). This was wrong —
`tsbundle` is a TypeScript-to-TypeScript import inliner, not a transpiler. Fixed to call
`bundleImports()` from `src/tsbundler.ts` directly, which resolves and inlines relative `.ts`
imports while keeping the output as TypeScript. Default output path changed from `.js` to
`.bundled.ts` to avoid overwriting the source file. Help text updated from "single `.js` file"
to "single `.ts` file (inlines all imports)".

### Phase 28 — Extended Array Methods (COMPLETE)

Eight new methods on dynamic `i32[]` / `f64[]`: `every`, `some`, `findIndex`, `at`, `reverse`, `fill`, `join`, `sort`. Key design points:

- **`every`/`some`** return i32 1/0 from WAT helpers; `dotCallLookupFn` returns `type: "bool"` for these (and `includes`) on array receivers; `parseSingleArg` maps `bool` → `boolexpr` → `true`/`false` output.
- **`join`**: uses a new `joinarr` `LogSegment` kind; `getJoinHelperWat()` writes the joined string directly into the gather scratch buffer — no string-pair return needed; separator allocated in data section at compile time via `allocString`.
- **`sort`** / **`sortcmp`**: two separate helpers distinguished by presence of comparator arg; both use insertion sort.
- **`findResultVars` fix**: `T | undefined`-typed `.find()` results previously bypassed `findResultVars.add()` because `nullableLetMatch` returned early; fix adds the `findResultVars` registration inside the nullable handler when init expr is a `.find()` call.
- **Integer division in tests**: use `(a / b) | 0` when integer-division semantics must match TypeScript — TypeScript `type i32 = number` is float at runtime; `|0` coerces both runtimes to integer; Binaryen -Oz eliminates the `i32.or ... i32.const 0` as a no-op.
- **`arrptr`/`joinarr` per-iov path (2026-04-24)**: Both kinds must be handled explicitly in the per-iov emission path of `emitConsoleLog` in `console_log.ts`, not just in the gather path. Per-iov uses `iovLen` as the cursor address (initialized to 0) and `scratchBase` as the output buffer — identical helper call conventions to gather mode. Without this fix, TypeScript cannot narrow the final `else` in the numeric block (`seg.wat` doesn't exist on `joinarr`); more critically, any `console.log` that mixes a `boolexpr` segment with an array segment forces per-iov mode (since `boolexpr` is not gatherable), causing the array to hit the wrong `f64expr` branch at runtime.

### Phase 29 — Class Enhancements (COMPLETE)

Static fields, getters/setters, and string enums. Key design points:

- **Static fields**: `static count: i32 = 0` → registered as `ClassName_count` module global (mutable) in `parseClasses()`; read as `(global.get $ClassName_count)`, written as `(global.set $ClassName_count val)`; accessible as `ClassName.fieldName` in expression and statement contexts.
- **Getters**: `get prop(): T { }` → WAT function `ClassName_get_prop(__self: i32): T`; `obj.prop` dispatches to getter in `emitExpr`, `structLookupFn`, and `this.prop` inside methods.
- **Setters**: `set prop(val: T) { }` → WAT function `ClassName_set_prop(__self: i32, val: T): void`; `obj.prop = val` dispatches to setter in `emitStatement`.
- **String enums**: `enum Dir { Up = "up" }` → `enumStringValues: Map<string, string>`; assignment `const d: string = Dir.Up` handled in `emitStringAssign`; `console.log(Dir.Up)` emits `{ kind: "literal", text: "up" }` via `enumStringLookup` callback threaded through `parseConsoleLogArgs` / `parseSingleArg`.
- `ClassDef.methods` entries gained `isGetter?` / `isSetter?` flags; getter/setter WAT functions use `ClassName_get_prop` / `ClassName_set_prop` naming.
- `structLookupFn` in `wasic.ts` extended to detect getter properties (used by `console.log` of `obj.prop` without parens).

### Phase 39 — jstyper (PLANNED, sequenced last)

`.d.ts`-based architecture. Pipeline: resolve/generate `.d.ts` → parse declarations →
merge with `.js` bodies → emit `.ts` → feed into tsbundler. Integration hook in
`tsbundler.ts` between lines 319–321. New file: `jstyper.ts`. Adds `npm:typescript` to
`deno.json`. CLI: `wasmtk jstyper <file.js> [--dts-only] [--dry-run] [--any-policy skip|warn|default]`.
Manual refinement: hand-edit `.d.ts` to add precise WASM types (`number → i32`).

### ExternalMapping_11b — Negative Test Reference

`tests/wasm_wasi/ExternalMapping_11b.ts` was upgraded in Phase 40. It now uses `declare const logger: { log(ptr: i32): void }` and compiles successfully. The `@expect-fail: compile` annotation has been removed. The file serves as a reference for the Phase 40 external interface mapping syntax.

---

## Closure / Arrow Implementation Patterns

When extending arrow or closure support, always test and check:

1. **Block-body arrows at depth > 0** — `parseArrowFunctions` must skip expression-body
   arrows inside function bodies (`braceDepth > 0 && bodyStart !== "{"`)
2. **`: ReturnType` annotations before `=>`** — `substituteOneArrow` must scan left past
   the return type annotation to find the closing `)`
3. **`bool`/`string` in functype signatures** — `getOrCreateFuncType` must normalise
   pseudo-types to concrete WAT types (`bool→i32`, `string→i32`, `never→null`)
4. **`closureTypedVars` pre-population** — `prePopulateClosureTypedVars()` must run before
   any `emitFunction` call so inner functions see their factory's type
5. **`outerScope` regex** — must use `([\w\[\]]+)` not `(\w+)` to match array types like `i32[][]`
6. **`injectClosureCaptures` returns nearest enclosing scope** — scan all functions, keep last match
7. **Chained closure calls in `console_log.ts`** — both `parseSingleArg` AND `exprToWat` have
   parallel code paths that need updating alongside `emitExpr`/`emitStatement` in `wasic.ts`

---

## Running the Test Suite

```bash
# Run everything in tests/wasm_wasi/
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts

# Optional 2nd arg: regex filter on file basenames (added during wabt-ts migration to
# scope re-validation to one phase at a time). Examples:
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts tests/wasm_wasi "^1_"   # phase 1 only
deno run --allow-read --allow-write --allow-run --allow-env tests/wasi_tests.ts tests/wasm_wasi "^15_"  # phase 15 only
```

`wasi_tests.ts` runs all `.ts` files in `tests/wasm_wasi/` matching the optional filter
(no filter = all files). Both phase tests and Go-by-Example tests live in that folder.
The jstyper unit tests run separately via `tests/jstyper_tests.ts`.

**Two distinct test populations in `tests/wasm_wasi/`:**

| Population | Count | Runner |
| --- | --- | --- |
| wasic phase tests (Phase 1–50) | ~77 wasic + 103 bindgen | `wasi_tests.ts` + `bindgen_tests.ts` |
| Go-by-Example tests (imported externally) | 219 total | `wasi_tests.ts` |
| jstyper unit tests | 73 | `jstyper_tests.ts` |

**Last full-suite validation under npm:wabt (2026-05-25): 446/446 PASS** (270 wasic + Go-by-Example tests + 103 bindgen tests + 73 jstyper tests). Stage 0 Canonical ABI alignment complete. (+3 from Phase 21 stress tests, +3 from Phase 22 stress tests added 2026-05-25.)

**Under the dual JSR /compat setup (wabt-ts/compat 1.2.9 + binaryen-ts/compat 1.2.9, 2026-05-28):** full wasic test suite **260/270 PASS (96.3%)**. 10 remaining failures itemized in § "Pluggable wabt + binaryen backends" (9 wasic-side codegen issues + 1 binaryen-ts `-Oz` pipeline interaction). Use the per-phase filter form above to drill in: e.g. `"^15_"` for phase 15, `"^38_"` for phase 38.

**Under 1.2.9 + 1.3.1 + Stage 0.6 allocator unification (2026-05-30): 262/271 PASS (96.7%).** One extra pass over the prior 260/270 (binaryen-ts 1.3.1 fixed 15_recover) plus the new `18b_SharedHeapTwoLibraries` regression test for allocator unification. The 9 remaining failures are all wasic-side codegen issues from the migration-era list; a 10th wasic codegen bug (`return expr as unknown as i32` emits stray `f64.convert_i32_s`) was uncovered while developing the 18b test and is tracked separately. See § "Stage 0.6 — Allocator Unification in wasmmerge" for the unification pass details.

Phase 45 completed: `random-numbers_45.ts` fixed via 6 changes to `src/wasic.ts` (Math.imul, `>>>`, hex literals, closure capture assignment guard, Fix 3 with comparison guard, closure call result type).

String-return side-channel design (Phase 42 internally; Stage 0 changes the host-facing ABI):

- Internally: string-returning functions are `void` WAT functions; they set `$__str_ret_ptr` / `$__str_ret_len` module globals before returning. This is unchanged.
- Stage 0: these globals are **no longer exported** to the host. Instead, `toWat()` generates a `$fn__cabi` shim wrapper (exported as `"fn"`) for each exported string-returning function. The shim calls the internal `$fn`, then reads the globals and writes them to the caller-provided 8-byte return area.
- Host side (`bindgen.ts`): caller allocates `_r = _cabi_realloc(0, 0, 4, 8)`, passes `_r` as the trailing argument, reads `ptr = DataView.getInt32(_r, true)` and `len = DataView.getInt32(_r + 4, true)` after the call.

Individual test:

```bash
wasmtk wasic tests/wasm_wasi/MyTest.ts && wasmtk run tests/wasm_wasi/MyTest.wasm
```

---

### Phase 47 — Class Inheritance (2026-05-15)

Phase 47 test files (all 5 PASS):

- `BasicClassInheritance_47.ts` — `class Animal` (age: i32, weight: f64) → `class Dog extends Animal` (legs: i32); `super(a, w)` in Dog constructor; `describe()` method with `this.age`/`this.weight` in console.log; verifies inherited field layout, `this.field` in console.log inside methods, direct field access
- `SuperConstructor_47.ts` — three-level chain: `Vehicle → Car → SportsCar`; each level calls `super(...)` to chain up; mixed i32/f64 fields; direct field reads `sc.speed`, `sc.fuel`, `sc.doors`, `sc.turbo`
- `ClassMethodOverride_47.ts` — `Shape → Circle → ColoredCircle`; each level overrides `area(): i32` and `label(): void`; inherited field `x` from Shape; own fields `radius` (Circle) and `color` (ColoredCircle); all accessed via concrete-typed variables
- `VirtualDispatch_47.ts` — `const a1: Animal = new Dog(3)` → `a1.speak()` dispatches to `Dog_speak` because pre-scan tracks concrete type; `getAge()` inherited from Animal; verifies both base-typed dispatch and inherited-method resolution
- `Phase47Combined_47.ts` — two independent hierarchies (`Vehicle→Car→ElectricCar`, `Node→LeafNode→BranchNode`); super constructors, method overrides, base-typed dispatch, inherited methods all together

**Implementation — four changes to `src/wasic.ts`:**

**`parseClasses()` — regex + field inheritance + global shift:**

- Regex changed to `/(?:export\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?\s*\{/g` (capture group 2 = base name)
- `classInheritance: Map<string, string>` populated: `classInheritance.set(className, baseName)` when `m[2]` is non-empty
- Derived class field pre-population: before scanning own fields, if base name is set and parent `ClassDef` exists, copy all parent fields (with `{ ...pf }` clone) to `fields[]` and set `fieldOffset = parentCd.struct.totalSize`. Multi-level chains work automatically because parent classes are processed in source order before derived classes.
- After the while loop: if `classInheritance.size > 0`, set `classHeaderSize = 4`, assign integer tags (1, 2, …) to all classes in `classDefs`, then shift every field offset by `+4` and grow every `totalSize` by 4. All classes in a file with any inheritance get the header, ensuring uniform field addressing without per-class offset logic.

**`resolveMethodFunc(className, methodName): string | null`** — new private helper. Walks `classInheritance` chain: tries `${current}_${methodName}` in `this.functions`, falls through to parent if not found, returns `null` if exhausted. Called in five places: `this.method()` in `emitExpr`, `dotCallExprMatch` in `emitExpr`, `this.method()` in `dotCallStmt`, classVars instance method in `dotCallStmt`.

**`newClassPre` pre-scan** — changed `this.classDefs.get(typeName) ?? this.classDefs.get(ctorName)` to `this.classDefs.get(ctorName) ?? this.classDefs.get(typeName)`. This ensures `const a1: Animal = new Dog(3)` registers `classVar.className = "Dog"` (not "Animal"), giving virtual dispatch for free: every method call on `a1` resolves via `resolveMethodFunc("Dog", ...)`. Also passes `this.classTags.get(cd.name)` as `classTag` to `allocStructData` to write the 4-byte tag at offset 0 in the static data section.

**`super(args)` handler in `emitStatement`** — inserted before `callMatch`. Matches `/^super\s*\((.*)\)\s*;?$/` when `this.currentMethodClass` is set and `classInheritance.has(currentMethodClass)`. Emits `(call $ParentClass_constructor (local.get $__self) args...)`.

**`structLookupFn` `this` handler** — added at top of both `structLookupFn` closures in `emitStatement` (console.log and console.error paths). When `vn === "this"` and `currentMethodClass` is set, looks up the field by name in `classDefs.get(currentMethodClass).struct.fields` and emits `(loadOp (i32.add (local.get $__self) (i32.const offset)))`. This enables `console.log("Age:", this.age)` inside method bodies to resolve correctly.

**`super.method(args)` in non-constructor method bodies (2026-05-24)** — Two new handlers added:

- **`emitExpr`** (`superDotExprMatch`): matches `/^super\.(\w+)\s*\((.*)\)$/` when `currentMethodClass` is set; looks up parent via `classInheritance.get(currentMethodClass)`; calls `resolveMethodFunc(parent, method)` to walk the chain; emits `(call $ParentClass_method (local.get $__self) args...)`. Used when `super.method()` appears as a sub-expression (e.g. `return super.calculateBonus() + this.flatBonus`).
- **`emitStatement`** (`superMethodStmt`): matches the same pattern for statement-level `super.method();` calls; emits `(drop ...)` for non-void results.

**`arr[idx].method(args)` — runtime vtable dispatch (2026-05-24)** — `emitExpr` handler (`arrMethodCallRe`) added after the field-access handler:

1. Matches `/^(\w+)\[([^\]]+)\]\.(\w+)\s*\((.*)\)$/`
2. Checks `arrayVars` for `structTypeName` + `classDefs.has(structTypeName)`
3. Computes element pointer: `(i32.load base+8+idx*4)` — the i32 object pointer stored in the array
4. If `classHeaderSize === 0` (no inheritance in module): static dispatch to declared class method
5. If `classHeaderSize > 0` (inheritance present): calls `findSubclasses(baseClass)`, sorts by `classTags`, builds nested if-else chain checking `(i32.load objPtr)` (the class tag at offset 0) against each tag value; last class is the default (else branch)

**`findSubclasses(baseClass)` helper** — new private method added after `resolveMethodFunc`. Iterates `classDefs.keys()` and walks each class's `classInheritance` chain; returns all class names that are (or transitively extend) `baseClass`.

**Class tag bug fix** — `emitExpr` `new ClassName(args)` handler now passes `this.classTags.get(ctorClassName)` to `allocStructData`. Previously the tag was only written for the `const obj = new ...` assignment pattern (in the pre-scan at line 10768); inline `new` uses inside expressions like `arr.push(new Square(5))` left offset 0 as zero, causing vtable reads to always return tag 0 (no match). The runtime dispatch now reads the correct tag for all `new` expression forms.

**Phase 17 stress tests (added 2026-05-24) — exercising class inheritance features:**

- `17_ConstructorChainingAndFieldPrefixOffest.ts` — three-level super constructor chain (`NamedVector3D extends Vector3D extends Vector2D`); `printCoords()` accesses inherited fields `this.x`/`this.y`/`this.z`/`this.id` across all three levels; verifies `ID: 999 X: 11 Y: 22 Z: 33`
- `17_Cross-PolymorphicArrayStride.ts` — `const inventory: Shape[] = []` holds `new Square(5)`, `new Rectangle(4, 6)`, `new Shape(0)`; `inventory[i].getArea()` dispatches at runtime via class tag; verifies `Total Combined Area: 49`
- `17_DeepHierarchyCTable.ts` — three-level `ExecutiveAccount extends PremiumAccount extends Account`; `super.calculateBonus()` inside `ExecutiveAccount.calculateBonus()` calls `PremiumAccount_calculateBonus`; base-typed `acc2: Account = new PremiumAccount(...)` dispatches correctly; verifies `Base: 10, Premium: 30, Executive: 80`

**Known limitations (remaining):**

- `abstract` class and `abstract` method declarations are silently treated as no-ops.
- The `override` keyword modifier on method declarations is stripped silently.
- `instanceof` for class types is not implemented in this phase.
- Programs with no `extends` classes are unaffected: `classHeaderSize = 0`, no field offsets shift, no class tags.
- Runtime vtable dispatch repeats the element-pointer load expression for each tag comparison (no local temp); correct but verbose WAT for large hierarchies.

---

## Stage 0 — Canonical ABI Alignment ✅ COMPLETE (2026-05-19)

*Completed ahead of Stage 1. wasic now exports `cabi_realloc` instead of `__malloc`
and uses the out-parameter convention for string returns. 349/349 tests pass.*

- [x] Replace `__malloc` export with `cabi_realloc(ptr, old_size, align, new_size) → i32` in `wasic.ts` emitter
- [x] Update `bindgen.ts` to use `cabi_realloc` for string param encoding instead of `__malloc`
- [x] Change string return emission in `wasic.ts`: replace `$__str_ret_ptr`/`$__str_ret_len` globals with out-parameter convention (caller allocates 8-byte return area, callee writes ptr+len)
- [x] Update `bindgen.ts` string-return ABI: allocate 8-byte return area, pass pointer as last arg, read ptr+len after call
- [x] Update `utils.ts` test runner WASI shim to use canonical call convention for string returns
- [x] Verify WIT generation in `wasic.ts`: string params as `string`, string returns as single `string` return type (no regression from Phase 50)
- [x] Run full test suite and verify 360/360 PASS

**`$cabi_realloc` implementation** — added in `emitHelpers()` in `wasic.ts`, immediately after `$__malloc`. Uses the WAT `select` instruction:

```wat
(func $cabi_realloc (param $ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
  (select
    (call $__malloc (local.get $new_size))
    (local.get $ptr)
    (i32.eqz (local.get $ptr))
  )
)
```

When `ptr == 0` (fresh allocation): `i32.eqz` → 1 → `select` chooses `call $__malloc(new_size)`. When `ptr != 0` (realloc/pass-through): `select` chooses `ptr` unchanged. Bump allocator has no `free`, so realloc always returns the existing pointer.

**Shim wrapper approach for string-returning exports** — avoids changing hundreds of internal call sites. Internal string-returning functions (`$fn`) remain `void` WAT functions using the `$__str_ret_ptr`/`$__str_ret_len` globals side-channel. The export-facing ABI change is implemented entirely in `toWat()`:

1. `exportAttr` suppressed for exported string-returning functions — `$fn` is NOT given `(export "fn")`.
2. A `$fn__cabi` shim is generated and appended to the WAT after `funcWat`. The shim takes all original params plus a trailing `(param $__ret_area i32)`, calls `$fn`, then reads the globals and writes them into the return area:

```wat
(func $fn__cabi (export "fn") (param ...) (param $__ret_area i32)
  (call $fn ...)
  (i32.store (local.get $__ret_area) (global.get $__str_ret_ptr))
  (i32.store offset=4 (local.get $__ret_area) (global.get $__str_ret_len))
)
```

**`bindgen.ts` changes** — both `_writeStr` (string params) and string-return call sites use `_cabi_realloc` from `exp["cabi_realloc"]`. String-return sites allocate the return area with `_cabi_realloc(0, 0, 4, 8)` and read back via `DataView.getInt32(_r, true)` / `DataView.getInt32(_r + 4, true)`. No `__str_ret_ptr`/`__str_ret_len` globals access from the host.

**`utils.ts` test runner** — no changes required. The runner only calls `_start`, which is not a string-returning export. All internal string operations still use the globals side-channel unchanged.

---

## Stage 0.6 — Allocator Unification in wasmmerge ✅ COMPLETE (2026-05-30)

*Closes the last gap that prevented `wasmbundle` from acting as a real on-demand
linker for stdlib capability modules (see `cmem/stdlib-bundling-brief.md` §3).
Pre-unification, every `wasic` / `modc` module shipped its own bump allocator
(`$__malloc` over a module-local `$__heap_ptr`). When two such modules were
merged via `wasmmerge`, prefix-mangling produced two independent allocators over
one linear memory; both would have started handing out overlapping addresses on
the first allocation from either side. The Phase 18 mutable-globals-to-page-2
patch had been masking this for single-library merges; two libraries with the
same global-index pattern would both have landed at 131072 and corrupted each
other.*

**`src/wasmmerge.ts` — semantic bump-allocator detector + redirection:**

Module-level helper `detectBumpAllocator(funcForm: string): { heapPtrGlobalIdx: number } | null`:

1. Signature must be `(param i32) (result i32)` — exactly one of each
2. May declare any number of `i32` locals; rejects `f32`/`f64`/`i64` locals (filter
   out non-allocator helpers)
3. Must touch exactly one global, with both `global.get N` and `global.set N` for
   the same index N
4. Body must contain `local.get 0` AND `i32.add` (the size-add)
5. Must NOT contain any of: `call`, `call_indirect`, `i32.load`/`store`,
   `i64.load`/`store`, `f32.load`/`store`, `f64.load`/`store` (rejects real
   functions that happen to touch a global)

The detector is robust to Binaryen `-Oz` variants: at least three forms have been
observed in practice — (A) `local.set` of an extra local then `global.set`; (B)
`local.tee` reuse of param slot 0; (C) multiple dead-local `tee`s before the final
return. The semantic check (one global touch + add + no loads/stores/calls) accepts
all three without form-specific regex.

Pass 1 of `mergeWasmWat()` records `droppedMallocIdx` and `droppedHeapPtrGlobalIdx`
when the detector fires. After `funcName` is populated, the dropped index is
remapped: `funcName.set(droppedMallocIdx, "$__malloc")` so every `call N` inside
the merged module's other functions resolves to the master module's `$__malloc`.
`renameGlobalRefs()` extended to redirect `global.get/set droppedHeapPtrGlobalIdx`
to `$__heap_ptr` (the master's mutable global). Pass 2 skips the dropped function
and its corresponding `(global ...)` declaration entirely.

`WatMergeResult` gained `droppedAllocator: boolean`. The runtime emits a notice
when true: `allocator unified: dropped $__malloc + heap-ptr global; call sites
redirected to main module's $__malloc / $__heap_ptr.`

**`src/wasic.ts` — post-merge heap-cursor + memory-page rewrite:**

In `compileWasiTs` and `compileLibTs`, after the merge phase (when
`wasmImports.length > 0 || transpiler.needsMathLib`):

```ts
wat = wat.replace(
  /\(global \$__heap_ptr \(mut i32\) \(i32\.const \d+\)\)/,
  `(global $__heap_ptr (mut i32) (i32.const ${dataOffset}))`,
);
const requiredPages = Math.max(2, Math.ceil(dataOffset / 65536) + 1);
wat = wat.replace(
  /\(memory\s+\(export\s+"memory"\)\s+(\d+)\)/,
  (_full, nStr) => `(memory (export "memory") ${Math.max(requiredPages, parseInt(nStr))})`,
);
```

`dataOffset` is the post-relocation combined static-data size from all merged
modules; the master heap cursor is reseated past it and the memory declaration
is grown to fit (`Math.max(2, ...)` is the floor for the existing 1-page-extra
allocator margin from Phase 10a).

**`src/wasmbundle.ts` — master WAT synthesizes shared pair when needed:**

When `mergeWasmWat` reports `droppedAllocator: true` for any sub-merge,
`wasmbundle` tracks `anyDroppedAllocator` across the merge loop. When true, the
master WAT body adds:

```wat
(global $__heap_ptr (mut i32) (i32.const dataOffset))
(func $__malloc (param $size i32) (result i32)
  (local $ptr i32)
  (local.set $ptr (global.get $__heap_ptr))
  (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
  (local.get $ptr))
```

Pages are recomputed: `Math.max(1, Math.ceil(dataOffset / 65536) +
(anyDroppedAllocator ? 1 : 0))`. This lets `wasmbundle` merge two libraries that
both allocate via `.push()` — neither has an externally-visible `_start`, but
their internal helpers all call `$__malloc`, which now resolves to the
synthesized master allocator.

**Regression test:** `tests/wasm_wasi/18b_SharedHeapTwoLibraries.ts` — a
`@test-pipeline` running `modc lib_a_modc.ts` + `modc lib_b_modc.ts` + `wasic
main_wasic.ts` + `run`. Both libraries allocate via `.push()` (which calls the
wasic `$__dynarr_push_i32` helper, which calls `$__malloc`); main asserts both
libraries return the expected length. PASSING.

**Binaryen upgrade alongside this work:** `binaryen-ts/compat` bumped from
1.2.9 to 1.3.1. This fixed one prior wasic-side failure (`15_recover` no longer
fails the `optimize()` pipeline) and also resolved 11_StringOps / 46_TemplateEscapes
verification regressions in the toolchain. Full wasic suite under 1.2.9 +
1.3.1 + unification: **263/272 PASS (96.7%)**.

**Wasic codegen bug uncovered during this work — FIXED 2026-05-30:** `return
expr as unknown as i32` emitted a stray `f64.convert_i32_s` on the return path,
producing a `(result i32)` declaration with an f64 value on the stack and
manifesting as `Compiling function #N failed: type error in return[0] (expected
i32, got f64)` at runtime. Fixed by stripping type-erasure casts up front (see
§ "Type-erasure casts (`as unknown` / `as any`) are stripped up front"); the
`18b_SharedHeapTwoLibraries.ts` `.length` workaround is no longer required (left
in place since it still passes). The Tier-1 stdlib libraries (JSON / Date / Map /
Set / RegExp) can now use pointer-typed `as unknown as i32` returns directly.

**`detectBumpAllocator` ordering caveat:** the function-signature regex uses
`(?:\s+\(type\s+\d+\))?` to tolerate an optional `(type N)` annotation between
the index and the params (Binaryen sometimes emits this, sometimes not). The
trailing `\b` was originally present between `)` and the start of the params
group — this prevented the match when wabt emitted a newline immediately after,
because both `)` and `\n` are non-word characters and `\b` requires a word/non-word
transition. The fix removed the trailing `\b`.

---

## Stage 0.7 — Tier-1 stdlib capability libraries (brief §5 / §7-#3)

First three deliverables shipped: **`Set<i32>`** and **`Map<i32,i32>`** as shared-heap modc
capability libraries (2026-05-30), plus the **`Date`** leaf library (2026-05-31). Establishes
the pattern for the remaining Tier-1 capabilities (JSON, RegExp). Backend bumped to
**`jsr:@jrmarcum/wabt-ts@^1.3.0/compat`** (fixes the call-before-return encoder bug — see
§ "Pluggable wabt + binaryen backends" bug table).

**`Date` (third deliverable — first *leaf* capability):**

- `tests/wasm_wasi_bundle/date_bundle/date_lib_modc.ts` — UTC integer calendar math. Unlike
  Set/Map (shared-heap, hold live structures), Date is a **leaf**: pure value-in/value-out
  integer math, **no heap allocation and no mutable state**, so the wasmmerge allocator
  unification is a no-op and the merge is a straight function splice (the "leaf capability
  merged when used" path from brief §5). Uses Howard Hinnant's exact-integer civil↔days
  algorithms, valid across the whole proleptic Gregorian calendar including pre-epoch /
  negative day counts. Exports `isLeapYear`, `daysInMonth`, `daysFromCivil`,
  `weekdayFromDays`, `yearFromDays`, `monthFromDays`, `dayFromDays`.
- `tests/wasm_wasi_bundle/date_bundle/main_wasic.ts` — self-checking driver (trap-on-failure,
  same pattern as Set/Map); exercises leap-year rules (4/100/400), days-in-month, civil→days,
  weekday, and the day-count→civil round-trip incl. a leap day (2024-02-29) and a pre-epoch
  date (1969-12-31 → -1). **NOTE:** the `.wasm` import must be a **single-line** `import { … }
  from "./date_lib_modc.wasm"` — wasic's `.wasm`-import detector does not match multi-line
  import statements.
- `tests/wasm_wasi/18e_DateCapabilityLibrary.ts` — `@test-pipeline` (modc → wasic → run). PASS.
- **Surfaced + fixed two merge-path codegen bugs** (Date is the first merged library that is
  dense integer arithmetic over large constants; Set/Map were bitwise/small-constant). See
  § "Stage 0.7 — merge-path codegen fixes (2026-05-31)" below. Full `tests/wasm_wasi` suite
  after the fixes: **268/275** (same 7 pre-existing failures, no regressions).

**`Map<i32,i32>` (second deliverable):**

- `tests/wasm_wasi_bundle/map_bundle/map_lib_modc.ts` — the Map capability. Reuses the Set
  hash core (linear probing + ×2 grow/rehash at load factor 0.5) and adds a **parallel
  values array**. A handle is an i32 pointer to a **5-slot** `Int32Array` header
  `[count, cap, keysPtr, valsPtr, usedPtr]`; buckets are three `Int32Array(cap)` arrays
  (keys + values + 0/1 used flags) addressed by `key & (cap-1)`. Grows ×2 + rehashes (handle
  stays stable; child arrays reallocate; key→value association preserved across rehash).
  Exports `mapNew`/`mapSet`/`mapGet`/`mapHas`/`mapSize`. `mapSet` updates in place when the
  key already exists (count unchanged); `mapGet(h, key, fallback)` returns `fallback` for
  absent keys.
- `tests/wasm_wasi_bundle/map_bundle/main_wasic.ts` — self-checking shared-heap driver (same
  trap-on-failure pattern as the Set driver); exercises insert, retrieval, update-existing,
  membership, fallback, multi-grow rehash with correct value survival, and negative keys.
- `tests/wasm_wasi/18d_MapCapabilityLibrary.ts` — `@test-pipeline` (modc → wasic → run). PASS.
- **No new compiler fixes required** — built entirely on the wasic features the Set
  capability established (TypedArray view over a raw pointer with element writes,
  type-erasure `as unknown` casts, inline-param import signature resolution in wasmmerge).

**`Set<i32>` (first deliverable) — Files:**

- `tests/wasm_wasi_bundle/set_bundle/set_lib_modc.ts` — the Set capability. A handle is an
  i32 pointer to a 4-slot `Int32Array` header `[count, cap, keysPtr, usedPtr]`; buckets are
  two `Int32Array(cap)` arrays (keys + 0/1 used flags) addressed by `key & (cap-1)` with
  linear probing; grows ×2 at load factor 0.5 and rehashes (handle stays stable, only child
  arrays reallocate). Exports `setNew`/`setAdd`/`setHas`/`setSize`. Fresh bump-allocated
  memory is zero, so `used` starts empty without explicit zeroing.
- `tests/wasm_wasi_bundle/set_bundle/main_wasic.ts` — self-checking driver; imports the
  library, exercises insert/dedup/membership/multi-grow-rehash/negative keys over the
  **shared heap** (the library's `$__malloc` resolves to the main module's cursor via the
  Stage 0.6 unification pass). On any wrong result it reads far out of bounds → WASM trap →
  nonzero exit, so the `run` step's success proves Set semantics (a wasic uncaught `throw`
  exits 0 and cannot fail a pipeline).
- `tests/wasm_wasi/18c_SetCapabilityLibrary.ts` — `@test-pipeline` (modc → wasic → run). PASS.

**Two supporting compiler fixes (both 2026-05-30), required by the shared-heap pointer pattern:**

1. **TypedArray view over a raw pointer (`src/wasic.ts`).** `const v: Int32Array = ptr as
   unknown as Int32Array` is now registered as a typed-array view in `typedArrayVars` (a new
   cast-form pre-scan branch in both the `emitFunction` and `startBodyLines` pre-scans, after
   the `new TypedArray(...)` branch: `/^(?:var|let|const)\s+(\w+)\s*:\s*(Int8Array|…|Float64Array)\s*=\s*(?!new\s)/`).
   Before this, element **reads** through such a view happened to work via the generic
   i32-pointer fallback (shift=2, +8 — coincidentally Int32Array's layout) while element
   **writes** silently stubbed out (`(;; v[i] = x;;)`), because the write path had no
   equivalent fallback. This is the primitive that lets a modc library reconstruct a typed
   view of a heap structure from the i32 handle the host passes back. See also the
   type-erasure-cast fix (`as unknown`/`as any`) under Active Design Decisions.
2. **Imported-function signature resolution from inline params (`src/wasmmerge.ts`).**
   `mergeWasmWat` mapped func→signature only via an explicit `(func (;N;) (type T) …)`
   reference, but `wabt-ts 1.3.0` disassembles funcs with **inline** `(param i32 i32)
   (result …)` and no `(type T)`. Added a `funcInlineSig` fallback that parses params/result
   from the func header (first line) when no `(type T)` is present, used in the
   `ExternalFuncDef` build. Without it, imported-function params resolved to empty → the
   call-site `pt = fn.params[i]?.type ?? "f64"` default emitted f64 args
   (`f64.convert_i32_s …`) to i32-param imports → `call[0] expected i32, found f64` at
   instantiate. (18b passed before only because its single-arg calls didn't expose it.)

**Validation under wabt-ts 1.3.0 + binaryen-ts 1.3.1 (freshly reinstalled binary):**
numbered phase suite **233/240** (was 230/239 — `15_panic` and `18_Multi-Scope` now pass
thanks to the wabt-ts fix; `18c` added; 7 remaining are the known pre-existing wasic-codegen
failures: `19_NestedDU`, `19_VariantMax`, `38_Math×4`, `5e_MixedSignatures`); `core_` 33/33;
jstyper 73/73. **Reinstall note:** the test runner invokes the globally-installed `wasmtk`
(`WASMTK_BIN = "wasmtk"`), so after changing `src/` or `deno.json` you MUST
`deno install -g … --config deno.json --force -n wasmtk main.ts` before the suite reflects
your changes.

**Pre-existing bug fixed 2026-05-30 — modc imported an unused `fd_write`.** `allocString`
(`src/wasic.ts`) set `this.hasConsoleLog = true` as a side effect of allocating ANY string
literal into the data section, and `emitWasiImports` gates the
`(import "wasi_snapshot_preview1" "fd_write" …)` on `hasConsoleLog`. So a string-**returning**
modc library function with no `console` use at all (e.g. the `strings_50` bindgen fixture:
`greet`, `shout`) imported an unused `fd_write` that the non-WASI bindgen loader can't supply
→ the 4 `strings_50` integration assertions failed (`bindgen_tests.ts` was 99/103). **Fix:**
removed the `hasConsoleLog = true` from `allocString`. The flag is now set ONLY by the
`console.log`/`console.error`/`console.warn` statement handlers (the no-arg log at ~7554, the
`logMatch` handler at ~7567, the `errMatch` handler at ~7933) — which is correct because
those are the only paths that emit `fd_write` (`console_log.ts`'s `fd_write` emission only
runs through them). Audited: every `fd_write` emission site (4 in `wasic.ts`, 2 in
`console_log.ts` reached via `emitConsoleLog`) is downstream of an explicit `hasConsoleLog =
true`. `allocStringNoLog` (used for throw messages) is now functionally identical to
`allocString` and retained only for its existing call sites. Verified: `strings_50` modc
output has zero `fd_write`; a `console.log` program still imports it and prints correctly;
`bindgen_tests.ts` 103/103; numbered suite still 233/240 (same 7 known failures), `core_`
33/33 — no regression.

### Stage 0.7 — merge-path codegen fixes (2026-05-31)

The `Date` capability is the first **merged** library whose functions are dense integer
arithmetic over large constants (719468, 146097, 365, 153, …). That shape exposed two latent
merge-path bugs that the bitwise/small-constant Set/Map libraries never tripped. Both fixed;
Date pipeline (`18e`) passes; full `tests/wasm_wasi` suite **268/275** (same 7 pre-existing
failures: `19_NestedDU`, `19_VariantMax`, `38_Math×4`, `5e_MixedSignatures`; no regressions).

**Fix 1 — `wasmmerge` relocated arithmetic constants as if they were data pointers**
(`src/wasmmerge.ts`). `relocateDataPtrs` blindly shifted **every** `i32.const >= 260`
(`DATA_PTR_THRESHOLD`) by the data-relocation delta — a documented conservative heuristic.
Date's `isLeapYear` divides by `400`; after the merge that became `400 + dataOffset` (e.g.
`668`), so `year % 668` made `isLeapYear(2000)` return 0. **Fix:** compute the merged
module's own static-data extent `[dataLo, dataHi)` from its `(data …)` segments (new
module-level `dataStringByteLength(body)` helper counts `\XX` hex and `\c` named escapes as
1 byte each) and relocate only constants that fall inside it (`n >= dataLo && n < dataHi`).
Genuine static-data pointers live in that range by construction; arithmetic literals do not.
`dataLo` is floored at `DATA_PTR_THRESHOLD` so fixed low scratch addresses (iov/scratch at
0, 128, …) are never relocated. A pure leaf with no data segments (Date, Set, Map) has
`dataHi === 0` → `relocateDataPtrs` is a no-op. Strict improvement over the blanket
threshold; residual heuristic risk (an arithmetic constant coincidentally inside a
string-bearing library's data range) is far narrower and could later be made exact with
context-sensitive load/store-address relocation.

**Fix 2 — Binaryen miscompiled the doubly-merged module — ✅ fixed upstream in
binaryen-ts/compat 1.3.2 (deno.json bumped 1.3.1 → 1.3.2, 2026-05-31).** After wasmmerge
splices the already-`-Oz`'d, stack-form library back into the driver,
`compileWasiTs`/`compileLibTs` re-optimize the combined module with binaryen-ts/compat. Under
1.3.1, on Date's division-heavy `monthFromDays`/`dayFromDays`, `optimize()` produced a binary
that **misbehaved at runtime** (garbage / out-of-bounds), even though the pre-binaryen merged
WAT assembled by wabt alone ran correctly — and laundering binaryen's output back through wabt
did **not** recover it (so the corruption was in binaryen's optimization, not its byte
encoding; binaryen-ts/compat also does not expose `emitText`). It was briefly worked around
with a `skipBinaryenOpt` param on `watToOptimisedWasm` (ship wabt's direct assembly on the
merge path). **1.3.2 fixed the optimizer bug**, so the workaround was removed: the merge path
again runs the full Binaryen `-Oz` pass, and the Date pipeline + full suite pass with it
re-enabled.

**How to apply:** Do not revert the range-scoped relocation in `relocateDataPtrs` to the
blanket `>= DATA_PTR_THRESHOLD` form (Fix 1 is independent of the binaryen version and stays).
binaryen-ts/compat must remain at `>= 1.3.2`; reverting below it re-introduces the merge-path
optimizer miscompile (which has no wasmtk-side workaround anymore).

### Stage 0.7 — JSON capability (parse + navigate) + four compiler fixes (2026-05-31)

Fourth Tier-1 capability (brief §5/§7-#3), and the **first to take string input across the
merge boundary** — Set/Map are i32-only and Date is a pure-integer leaf. JSON is a
**shared-heap** capability: a wasic program (which has no native JSON) gains `JSON.parse` +
a navigation API by merging a modc library; the parsed value tree lives on the ONE heap the
driver shares (allocator unification, Stage 0.6).

**Files:**

- `tests/wasm_wasi_bundle/json_bundle/json_lib_modc.ts` — the capability. Each JSON value is an
  i32 handle = base ptr of a 4-slot `Int32Array` node `[tag, a, b, c]`: tag 0=null 1=bool
  2=number(int) 3=string 4=array 5=object. Containers reuse wasic's **native dynamic `i32[]`**
  (built, stored by ptr via `arr as unknown as i32`, reconstructed via `ptr as unknown as
  i32[]` for index/`.length`/`push`); string values are decoded into a **`Uint8Array`** buffer
  (ptr in `a`, byte len in `b`), so no raw `__malloc` and no raw string-ptr exposure is needed —
  everything stays inside the proven TypedArray-view-over-pointer / dynamic-array idioms.
  Recursive-descent parser threading the input `string s` into every parse fn, with a
  module-level mutable cursor `pos` and a `lastLen` side-channel (the subset can't return two
  values). Exports `jsonParse`, `jsonType`, `jsonInt`, `jsonBool`, `jsonArrayLen`,
  `jsonArrayGet`, `jsonObjectLen`, `jsonStrLen`, `jsonStrCharAt`, `jsonStrEq(node, t: string)`,
  `jsonGet(node, key: string)`, `jsonHas(node, key: string)`.
- `tests/wasm_wasi_bundle/json_bundle/main_wasic.ts` — self-checking shared-heap driver
  (trap-on-failure, same `check()` pattern as Set/Map). Parses one document exercising
  object/array/string/number(incl. negative)/bool/null, nested objects + arrays, key lookup
  (present + absent), membership, byte-accurate string equality + char access, and escape
  decoding. **NOTE:** the `.wasm` import and the JSON-document string must each be **single-line**
  (the `.wasm`-import detector doesn't match multi-line `import`; module-level string `+`
  concatenation is avoided). The document literal needs DOUBLE escaping: `\"` → a JSON quote,
  `\\n` → a JSON `\n` escape (a real backslash-n the parser then decodes).
- `tests/wasm_wasi/18f_JsonCapabilityLibrary.ts` — `@test-pipeline` (modc → wasic → run). PASS.

**SCOPE v1:** null / bool / **integer** numbers / strings / arrays / objects; string escapes
`\" \\ \/ \b \f \n \r \t`. Float numbers (the fractional/exponent tail is consumed but
truncated to the integer part) and `\uXXXX` (backslash dropped, hex digits pass through) are
the documented v2 gap — mirroring how Set<i32> / Map<i32,i32> scoped to integer keys first.

**Four compiler fixes surfaced by JSON (all 2026-05-31):**

1. **String args to merged imports — recover logical types from the sibling `.wit`**
   (`src/wasic.ts`). A modc `func(s: string)` compiles its string param to `(i32 i32)`
   (ptr+len) in the `.wasm`; `mergeWasmWat` therefore registered the import with params
   `[i32, i32]`, losing the "string" type, so a string ARGUMENT at the call site couldn't be
   expanded to ptr+len → `not enough arguments on the stack for call (need 2, got 1)`. Fix: the
   `.wit` (Phase 41) is the interface contract and preserves `s: string`, so before
   transpilation we read the sibling `.wit` and overlay the **logical** signature onto each
   `ExternalFuncDef`. New module-level helpers: `kebabToCamel`, `witTypeToWat`,
   `parseWitLogicalSigs(witSrc, prefix)` (regex over `export NAME: func(params) -> ret;`,
   keyed by `${prefix}_${camelName}`), `readWitLogicalSigs(wasmPath, prefix)` (reads
   `<wasm>.wit`, empty map if absent → numeric-only libs unaffected), and `applyWitSig(ef,
   sigs)` (overlays params/result; cast through `WasmWatType` since the field is numeric-typed
   but deliberately carries `"string"`/`"bool"` via cast). Wired into both `compileWasiTs` and
   `compileLibTs` right after `mergeWasmWat`. The existing call-arg paths already expand
   `p.type === "string"` → `emitStringPtrLen`, so no call-site change was needed; string params
   at any position (e.g. `jsonGet(node, key)`) work.

2. **Allocator-detector false-positive** (`src/wasmmerge.ts` `detectBumpAllocator`). A plain
   `global += param; return global` accumulator (e.g. the JSON parser's `advance`-style cursor,
   or any such helper) matched the bump-allocator structural gate — `(param i32)(result i32)`,
   one global get+set, `local.get 0` + `i32.add`, no loads/stores/calls — and was silently
   **dropped** during the merge (its call sites redirected to the real `$__malloc`), producing
   `undefined func`. A real `$__malloc` returns the **old** heap value, captured into a local
   BEFORE the `global.set`, so it reads the global exactly **once**; the accumulator reads it a
   **second** time to return the post-increment value. Fix: require the matched global's
   `global.get`/`global.set` to each occur **exactly once** (count occurrences, not just
   distinct indices) — every `-Oz` shape of `$__malloc` reads the heap ptr once; the
   accumulator reads twice and is now correctly rejected.

3. **Escaped-quote string literals** (`src/wasic.ts`, three sites). The regexes `"([^"]*)"` /
   `'([^']*)'` terminate at the first `\"`, so a literal containing escaped quotes (e.g. an
   embedded JSON document) either failed to match (falling to the empty `(i32.const 0)
   (i32.const 0)` / "string assignment from complex expression not yet supported") or was
   mis-extracted. Fixed to escape-aware `"((?:[^"\\]|\\.)*)"` (and the `'` variant) at:
   `emitStringPtrLen` (string ARG path, ~line 4391), `emitStringAssign` (local string
   assignment, ~line 3862), and the module-level string-const detection in `parseTopLevel`
   (`isStringLit`, ~line 2124). `allocString` → `unescapeString` already decodes the captured
   escapes to bytes. (The enum-value string-literal regex at ~line 2514 has the same latent
   shape but is off the JSON path and was left unchanged.) **Caveat:** string literal args
   passed *inside* `console.log(...)` go through a different emitter in `console_log.ts` (not
   `emitStringPtrLen`); that path still has the un-escaped regex, so escaped-quote literals
   should be passed via the main statement/expression paths (assign to a var, or as a non-log
   call argument), which the JSON driver does.

4. **`findBinaryOp` tail-depth + missing bracket counting** (`src/wasic.ts`). The scan started
   at `i = expr.length - op.length`, so the **last `op.length-1` characters were never counted
   for paren depth** — a RHS ending in a call (trailing `)`, e.g. `v[i] !== t.charCodeAt(i)`)
   left the closing `)` uncounted while its `(` was counted, driving depth negative so the
   operator was never found and the whole expression fell to the comment-stub fallback
   `(;? … ;) (i32.const 0)` (always-false). It also never counted brackets `[]` (unlike the
   sibling `findDepth0LTR`/`findDepth0Keyword`), so an operator inside `arr[i+1]` could match at
   the wrong place. Fix: scan the **full** string from the end for depth (counting `()` and
   `[]`), and only test for an op match at valid start positions (`i <= maxStart`). High blast
   radius (all binary-op parsing) — full suite re-validated with no regression (see below).

**Validation (2026-05-31, wabt-ts 1.3.0 + binaryen-ts 1.3.2):** full `tests/wasm_wasi`
**269/276** — the same **7** pre-existing wasic-codegen failures (`19_NestedDU`,
`19_VariantMax`, `38_Math×4`, `5e_MixedSignatures`), **no regression**, +1 for the new `18f`;
`bindgen` **103/103**; `jstyper` **73/73**. The four capability pipelines (`18c`–`18f`:
Set/Map/Date/JSON) all PASS.

---

## Planned Phases (Roadmap)

All 50 phases are now complete. **Historical baseline under npm:wabt + npm:binaryen: 446/446 PASS as of 2026-05-25** (270 wasic + Go-by-Example tests + 103 bindgen tests + 73 jstyper tests). **Current dual JSR /compat (wabt-ts/compat 1.3.2 + binaryen-ts/compat 1.3.3) with allocator unification + Stage 0.7 Set/Map/Date/JSON/RegExp capabilities (2026-06-02):** full `tests/wasm_wasi` suite **278/278**, `core_` 33/33, jstyper 73/73, **bindgen 103/103**. wabt-ts 1.3.0 recovered `15_panic` and `18_Multi-Scope` (call-before-return encoder fix); **the 7 long-standing failures are now ALL FIXED (2026-06-02):** `5e_MixedSignatures` + `19_*` via a wasic value-fallthru rewrite (terminal void `if/else` where all paths return → value-producing `(if (result T) …)`; see § "Value-fallthru rewrite"), and `38_*` mathlib via **wabt-ts 1.3.1** (hex-float literals were parsed as 0; the "f64→i32 truncation" was a downstream NaN/Inf symptom). **All five Tier-1 stdlib capability libraries are shipped** (`Set<i32>` + `Map<i32,i32>` + `Date` + `JSON` parse+navigate-integer-v1 + `RegExp` backtracking-matcher; Stage 0.7, 2026-05-30/31). **Brief §7 update (2026-06-02): #4 feature-level tree-shake ✅, #6 hybrid type-routing ✅, #7 kernel-scope DECIDED ✅** — #4 embeds the 5 caps (`src/wasm/caps_bytes.ts`) + resolves a virtual `wasmtk:<cap>` import that merges only referenced caps (test `18h`); #6 adds `wasmtk hybrid --auto` (route fully-typed fns to wasic, dynamic/async/any to the host); #7 decided to **build wasmtk's own dynamic runtime** (a major future track, not yet implemented — `javyc` stays the interim fallback). Remaining: **#5 Promise/async** and the **own-runtime build** (both large). Partially addressed 2026-06-02: `expandInlineBraceChain` stopped the single-line `if (c) { return 1 } else { return -1 }` brace form from dropping the `else`, but that form is **still an OPEN (low-priority) bug** — the expanded shape still miscompiles (f64/i32 return mis-type; inline-`if` fallthru); does not affect the 278/278 suite. RegExp's merge bug (OOB `charCodeAt` in a non-short-circuit `&&`) is **now FIXED 2026-06-02** by making wasic short-circuit `&&`/`||` (the library workaround was removed; the natural form passes merged) — see `cmem/compiler-bugs.md` / brief §7d. The DLL model is complete end-to-end. **Curated, portable project memory now lives in `cmem/`.**

**Phases 42–50 in this section are fully implemented** — their entries are preserved here as detailed design notes.

### Phase 42 — String-Returning User Functions + Nested Structs (2026-05-13)

Phase 42 test files (all 5 PASS):

- `BasicStringReturn_42.ts` — `greet(name: string): string`, `formatNum(n: i32): string`, `describe(label, n): string`; verifies string return in variable assignment, direct `console.log`, template literal body, and as argument to another call
- `ChainedFieldAccess_42.ts` — `seg.from.x`, `box.topLeft.y` two-level struct field access; nested struct pointer chasing in `emitExpr`
- `StructFieldArg_42.ts` — `describePoint(seg.from)` where `seg.from` is a nested struct field; `emitExpr` emits the i32 pointer to the nested struct loaded from the parent's field offset
- `Phase42Combined_42.ts` — all three Phase 42 patterns together
- `struct-embedding_42.ts` — previously failing Go-by-Example test; now passes with Phase 42 support

**String-return side-channel** — string-returning functions (`function f(): string`) compile to `void` WAT functions. On `return expr`, `emitStringPtrLen(expr)` stores the ptr+len into two mutable module-level globals `$__str_ret_ptr` (i32) and `$__str_ret_len` (i32). Call sites immediately read the globals after `(call $fn args)`. `needsStringRetGlobals` flag on `WasicTranspiler` gates emission of the two globals. Wired into: `emitStringAssign` (string variable init from function call), `parseSingleArg` in `console_log.ts` (returns `strexpr` segment), template literal emission, and binary-ops string-comparison path in `emitExpr`.

**Chained struct field access** — `seg.from.x` and `box.topLeft.y`: `emitExpr` detects `a.b.c` patterns, loads the intermediate struct pointer from the parent field via `i32.load`, then loads the leaf field from that pointer — two-level load chain.

**Nested struct literals** — `{ from: { x: 1.0, y: 2.0 }, to: { x: 7.0, y: 8.0 } }`: pre-scan and `allocStructData` parse inline nested struct initializers and recursively allocate sub-struct data in the WAT data section.

**Nested struct field as function argument** — `describePoint(seg.from)`: when the argument expression is a struct-typed field access, `emitExpr` emits the i32 pointer to the nested struct (loaded from the parent struct's field offset) as the call argument.

---

**Phase 43 — String Arrays as Function Parameters (2026-05-14, COMPLETE)** — see the full implementation notes in `## Compiler Phase Status` → `### Phase 43` above.

---

### Phase 45 — `Math.imul` + Unsigned Right Shift (`>>>`) (COMPLETE 2026-05-15)

**Target tests**: `random-numbers_45.ts` — **PASSING** (226/226 total)

**Implementation** — five fixes applied to `src/wasic.ts`:

1. **Assignment guard for mutable closure captures** — `emitStatement` compound-assignment regex now checks `locals.has(name) || currentClosureCaptureLayout.has(name)`, allowing `s = (s + 0x6D2B79F5) | 0` to work when `s` is a closure-captured variable not in `locals`.

2. **`>>>` unsigned right shift** — added to `binaryOps` table as `[">>>", "shr_u", "shr_u", true]` with `alwaysI32=true`. In the alwaysI32 promotion block, `>>>` uses `f64.convert_i32_u` (unsigned) instead of `f64.convert_i32_s` (signed) to correctly implement the `>>> 0` unsigned conversion idiom.

3. **f64→i32 truncation for arithmetic in i32 context** (Fix 3) — added at the end of the binary op emission block: when `baseType === "f64"` and `defaultType` is i32 AND the op is not a comparison (`!STRING_CMP_OPS.has(op)`), wrap with `(i32.trunc_f64_s ...)`. This handles f64 variables used as operands in i32-context arithmetic (e.g. complex sub-expressions inside bitwise ops). The comparison guard is critical — `f64.lt`/`f64.eq` etc. already return i32; without it, Binaryen aborts with type errors.

4. **`Math.imul` f64 context** — `Math.imul` handler wraps with `(f64.convert_i32_s ...)` when `defaultType` is f64. Always passes "i32" as `defaultType` to both arg `emitExpr` calls so f64 variables get `i32.trunc_f64_s` applied automatically via the identifier coercion at line ~4758.

5. **Closure call result type** — added `closureTypedVars` check in the `lhsType` chain: when `lhs` matches `funcName(...)` and `funcName` is in `closureTypedVars`, uses the closure's return type (not the i32 pointer type) for arithmetic type inference.

6. **Hex literal support** — added handler in `emitExpr` immediately after the decimal numeric literal check: `/^0[xX][0-9a-fA-F]+$/` → `parseInt(expr, 16)` → `(i32.const n)` / `(i64.const n)` / `(f64.const n)` based on `defaultType`. Without this, `0x6D2B79F5` fell through to the comment-stub fallback and the PRNG state never advanced.

**Critical design rule — Fix 3 comparison guard**: The `!STRING_CMP_OPS.has(op)` guard in Fix 3 is load-bearing. Without it, any `if (x < threshold)` where `x` is a f64 variable gets `(i32.trunc_f64_s (f64.lt ...))` which is invalid WAT (truncating an i32 result). This caused 45 test regressions when the guard was initially missing. `STRING_CMP_OPS` covers `===`, `!==`, `==`, `!=`, `<`, `>`, `<=`, `>=`.

---

### Phase 46 — String Escape Sequence Processing (2026-05-15)

Phase 46 test files (all 4 PASS):

- `BasicEscapeSeqs_46.ts` — all single-char escapes in double-quoted strings: `\n`, `\r`, `\t`, `\b`, `\f`, `\v`, `\0`, `\\`; length assertions confirm 1 byte per escape, not 2 raw chars; also tests multi-escape strings
- `TemplateEscapes_46.ts` — same escapes in template literals (backtick strings); escapes in text before AND after `${expr}` expressions; multi-escape template literal
- `HexUnicodeEscapes_46.ts` — `\xHH` hex escapes: length (1 byte per `\xHH`), value equality (`\x41 === "A"`), sequential hex chars (`\x61\x62\x63 === "abc"`), cross-check that `\x0A` and `\n` produce identical bytes
- `Phase46Combined_46.ts` — all escape categories together: single-char escapes, template literal escapes, hex escapes, cross-check `by_name === by_hex` for `\n` vs `\x0A`

**Root cause**: wasic read TypeScript source as raw text. When extracting `"\n"` from source, it stored two raw bytes (`\` + `n`) in the WAT data section instead of one byte (0x0A). Two separate code paths both needed fixing.

**`unescapeString(raw: string): string`** — new exported function in `src/console_log.ts`. Fast-path: returns `raw` unchanged if no `\` present. Otherwise walks character by character processing escape sequences:

| Source escape | Result |
| --- | --- |
| `\n` | 0x0A (newline) |
| `\r` | 0x0D (carriage return) |
| `\t` | 0x09 (tab) |
| `\b` | 0x08 (backspace) |
| `\f` | 0x0C (form feed) |
| `\v` | 0x0B (vertical tab) |
| `\0` | 0x00 (null) |
| `\\` | `\` |
| `\'` `\"` `` \` `` | literal quote |
| `\xHH` | byte with hex value HH |
| `\uHHHH` | UTF-8 encoding of U+HHHH |
| `\u{H…}` | UTF-8 encoding of variable-length code point |
| malformed `\x`/`\u` | passed through unchanged |

**Two fix locations:**

1. **`src/wasic.ts` — `allocString` and `allocStringNoLog`**: renamed param to `raw`, first line applies `unescapeString(raw)` to get `msg`; `dataMap` keyed by `msg` (unescaped form) so two raw spellings that unescape to the same bytes correctly share one data allocation. `unescapeString` imported from `./console_log.ts`.

2. **`src/console_log.ts` — `parseSingleArg` and `parseTemplateLiteral`**: `console.log` gather mode directly byte-encodes `{ kind: "literal", text }` segments WITHOUT going through `allocString` — so the gather path needed its own fix. `parseSingleArg` double-quote and single-quote handlers wrap the extracted content: `text: unescapeString(token.slice(1, -1))`. `parseTemplateLiteral` wraps both text-segment push calls: `text: unescapeString(body.slice(...))`.

**Safety**: `unescapeString` on compiler-internal strings (which already contain actual characters, not two-char sequences) is a no-op — the fast-path `!raw.includes("\\")` returns immediately since internal strings have real newlines/tabs/etc., not backslash-letter sequences.

---

### Phase 48 — Language Completeness: Number API, Operators, and Control Flow (2026-05-15)

Phase 48 test files (all 7 PASS):

- `NumberConstants_48.ts` — `Number.NaN`, `Number.POSITIVE_INFINITY`, `Number.NEGATIVE_INFINITY`, `Number.EPSILON`, `Number.MAX_SAFE_INTEGER`, `Number.MIN_SAFE_INTEGER`, `Number.MAX_VALUE`, `Number.MIN_VALUE`; comparison against 1e16; `isNaN()` predicate
- `NumberPredicates_48.ts` — `Number.isNaN(x)`, `Number.isFinite(x)`, `Number.isInteger(x)` with NaN/Infinity/finite/integer/float values; 10 bool outputs
- `SwitchFallthrough_48.ts` — `case 1: case 2: body` empty-body fallthrough; `case 3:` falls through to `case 4:`; default; mixed fallthrough and break
- `ObjectDestructDefault_48.ts` — `const { x = 1.0, y = 2.0 } = v` for f64 fields; `const { a = 10, b = 20 } = p` for i32 fields; renamed `const { a: qa = 100, b: qb = 200 } = q`; zero-sentinel semantics (default fires when field is 0)
- `LabeledContinue_48.ts` — `continue outer` in nested for-loops; `continue loop` in nested while-loops; verifies correct skip count (15, 4)
- `ExponentAssign_48.ts` — `x **= 3`, `y **= 0.5`, `z **= exp` (variable), `globalX **= 2` (module global); verifies 8, 2, 100, 9
- `Phase48Combined_48.ts` — classify function using Number predicates, switch fallthrough, labeled sum, object destructuring defaults, `**=`, Number constant comparisons

**`Number` constants** — `NUMBER_CONSTS` lookup map added in `emitExpr` (wasic.ts) and `exprToWat` (console_log.ts) before the `Math.*` handler. Maps `Number.NaN → (f64.const nan)`, `Number.POSITIVE_INFINITY → (f64.const inf)`, etc.

**`Number` predicates** — three predicates added in both `emitExpr` and `exprToWat`:

- `Number.isNaN(x)` → `(f64.ne argWat argWat)` (NaN is not equal to itself)
- `Number.isFinite(x)` → `(i32.and (f64.lt argWat (f64.const inf)) (f64.gt argWat (f64.const -inf)))`
- `Number.isInteger(x)` → `(f64.eq (f64.floor argWat) argWat)`

**`parseSingleArg` boolexpr ordering fix** — The boolexpr detection block (for `!`, `&&`, `||`, `===`, `!==`, `>`, `<`, `>=`, `<=`) was moved BEFORE the `Number.*` and `Math.*` handlers. Without this, `Number.MAX_SAFE_INTEGER > 1e16` was intercepted by the `Number.*` startsWith guard and returned as `f64expr`, causing `$__f64_to_str` to receive an `i32` return value of `f64.gt` — a WAT type mismatch. With the boolexpr block first, comparison expressions are correctly routed to `boolexpr` regardless of which side starts with `Number.` or `Math.`.

**`dotCallLookup` guard for `Number.*`** — Added `!token.startsWith("Number.")` alongside the existing `!token.startsWith("Math.")` guard in the dot-call handler. Without this, `Number.isNaN(nanVal)` in console.log hit `dotCallLookup` (which emits an i32 method call result) instead of the correct `Number.*` boolexpr path.

**Scientific notation literals** — Extended the numeric literal regex in `emitExpr` (`wasic.ts`) from `/^-?\d+(\.\d+)?$/` to `/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/` so `1e16`, `3.5e-4`, etc. are recognized. Same fix applied in `exprToWat` (`console_log.ts`) where a new third case handles scientific notation → `(f64.const ...)`. The `parseSingleArg` literal check also extended to include scientific notation, converting via `String(Number(token))` for normalized display.

**`**=` compound assignment** — new `expAssignMatch` handler in `emitStatement`, before the existing `compoundMatch` block. Uses `$__math_pow` via `this.mathHelpers.add("math_pow")`. Supports both local variables and module globals. Regex: `/^(\w+)\s*\*\*=\s*(.+?);?$/`.

**`$__math_pow` sqrt special case** — Added two early-return branches before the integer loop: `(if (f64.eq exp (f64.const 0.5)) (then (return (f64.sqrt base))))` and the -0.5 reciprocal case. Enables `y **= 0.5` (i.e., sqrt) without requiring the mathlib.

**Object destructuring with defaults** — `emitStatement` `destructMatch` block updated with a 4-form binding parser: `"field"`, `"field = default"`, `"field: local"`, `"field: local = default"`. When a default is present, emits `(if (result T) (eqz loadWat) (then defWat) (else loadWat))`. The `eqz` check uses `f64.eq loadWat (f64.const 0.0)` for f64 fields and `i32.eqz loadWat` for i32 fields. The pre-scan in `emitFunction` also strips `= default` when determining the local name to declare.

**Labeled continue** — already worked via existing `controlStack` infrastructure (verified by `LabeledContinue_48.ts` passing without any code changes). The `continueLabel` field was already populated for labeled loops.

**Switch fallthrough** — already worked via the existing "omit br when no break" mechanism (verified by `SwitchFallthrough_48.ts` passing without any code changes).

**Known limitations:**

- `Number.isNaN` / `Number.isFinite` emit the argument expression twice for simple variable reads (safe; no side effects). Complex expressions (function calls) would fire twice — not handled specially.
- Object destructuring defaults use zero-equality rather than TypeScript's `undefined` check — a field set to `0` will receive the default value.
- `$__math_pow` only handles integer exponents and the `0.5` / `-0.5` special cases; arbitrary fractional exponents other than `±0.5` are not supported.

---

### Phase 49 — Optional Chaining and Collection Method Completeness (2026-05-15)

Phase 49 test files (all 5 PASS):

- `OptionalChaining_49.ts` — `v?.x`, `v?.y` on non-nullable `Vec2` and `Point` structs; verifies `?.` is stripped to `.` at compile time; also tests a second non-nullable struct `v2` with different values
- `StringAt_49.ts` — `str.at(n)` with positive indices (`0`, `1`) and negative indices (`-1`, `-2`) on string literals; verifies inline pointer arithmetic `base_ptr + (n >= 0 ? n : len + n)` with `(i32.const 1)` length
- `ArrayConcat_49.ts` — `i32[]` concat (two arrays → new array of combined length), `f64[]` concat, concat with empty array; verifies element values and `.length` of result
- `ChainedMethods_49.ts` — `nums.filter(isPos).map(double)` and `nums.filter(isPos).map(triple)`; verifies chained calls where the intermediate result is not a named variable
- `Phase49Combined_49.ts` — all four features together: `s.at(0)`, `s.at(-1)`, `a.concat(b)`, `nums.filter(isPos).map(double)`, `pt?.x`, `pt?.y`

**`?.` optional chaining** — global pre-pass `this.src = this.src.replace(/\?\./g, ".")` at the very start of `transpile()`, before `expandGenerics`. Since all `?.` uses in wasic programs are on non-nullable types (all nullable variables use explicit `!== null` ternary checks per Phase 24), stripping `?.` → `.` is safe for the entire wasic source surface. The replacement runs before any parse pass so all downstream handlers see plain `.` notation.

**`String.prototype.at(index)`** — implemented WITHOUT calling `$__str_char_at` (which returns multi-value `(result i32 i32)` incompatible with `strexpr` kind). Instead, uses inline pointer arithmetic in three contexts:

- **`emitStringAssign`** (`strAtAssignMatch`): sets `varName_ptr = (i32.add base_ptr normIdx)`, `varName_len = (i32.const 1)`. `normIdx = (select n (len+n) (n>=0))`.
- **`emitStringPtrLen`** (`strAtSPLM`): returns `"(i32.add base_ptr normIdx) (i32.const 1)"` as a ptr+len pair.
- **`appendConcatPart`** (`strAtCP`): calls `concatAppend(ptrWat, "(i32.const 1)")`.
- **`parseSingleArg` in `console_log.ts`** (`strAtPSAMatch`): returns `[{ kind: "strexpr", ptrWat: "(i32.add base_ptr normIdx)", lenWat: "(i32.const 1)" }]`.

Prologue checks for `$__str_op_ptr`/`$__str_op_len` extended to include `.at(` alongside `.charAt(` and `.slice(`.

**`Array.prototype.concat(other)`** — added `concat` to `findDynamicArrays` regex, `detectModuleArrayGlobals` scan, and `dynArrMethod` dispatch regex. Handler: `this.dynArrHelpers.add("concat_T")`, then `(call $__dynarr_concat_T arrGetWat otherWat)`. The `$__dynarr_concat_T` helper already existed from Phase 13 spread literal support — no new WAT generation needed. Guard: `parenDepthNeverNegative(argsStr)` applied at top of `dynArrMethod` dispatch block.

**Chained array method calls** — two new private helpers + a chain dispatch block:

**`splitLastMethodCall(expr)`** — finds the outermost method call by scanning backward from the last `)` with balanced-paren counting, then finding the last `.` before the opening `(`. Returns `{ receiver, method, args }` or `null`.

**`inferChainElemType(expr, locals)`** — recursively infers the element type of a chained array expression. Base case: `arrayVars.get(expr)?.elemType`. Recursive case: calls itself on `receiver`, then maps through method type rules (`filter`/`slice`/`concat`/`reverse` → same type; `map` → callback return type from `functions` lookup).

**Chain dispatch block** (after `dynArrMethod` block in `emitExpr`): when `dynArrMethod` returns early (because `parenDepthNeverNegative` fails — the args contain unbalanced parens indicating a chain), `splitLastMethodCall` is called on the full expression. If the outer method is in `CHAINABLE` set and the receiver is NOT already in `arrayVars` (i.e. it's an intermediate expression), `inferChainElemType(receiver)` determines the element type, then `emitExpr(receiver, locals, "i32")` generates the inner call WAT, then the outer method is dispatched using the inferred elem type and the inner call result as the array pointer.

**`parenDepthNeverNegative` guard** — added at top of `dynArrMethod` dispatch block. When `argsStr` contains unbalanced parens (depth goes negative), the regex matched a chained expression greedily (e.g. `filter(isPos).map(double)` matched as `filter` with `argsStr = "isPos).map(double"`). The guard causes early exit from the `dynArrMethod` block, allowing the chain handler to take over.

**`getFuncTableIdx` safety** — the chain handler only calls `getFuncTableIdx(fnName)` after validating the name is a known function (found in `this.functions`). Passing a corrupt name like `"isPos).map(double"` would have corrupted the funcref table; the paren-depth guard prevents this.

**Known limitations:**

- `?.` on nullable struct variables (`Vec2 | null`) does not emit a runtime null check — the global `?.` strip treats all `?.` as non-nullable. Nullable struct field access still requires explicit `(p !== null) ? p.x : 0.0` ternary form.
- `arr.concat(b, c)` (multiple arguments) is not supported — only single-argument form.
- Chain dispatch supports `filter` and `map` as outer methods; `reduce` as outer in a chain is not yet wired (requires knowing the accumulator type from the callback signature).

---

### Phase 50 — `bindgen`: TypeScript Host Binding Generator (2026-05-18)

**Overview**: `wasmtk bindgen <module.wit>` reads a `.wit` file produced by Phase 41 and generates a self-contained TypeScript binding file (`module.bindings.ts`). The binding file exports a typed loader function that instantiates the WASM module and wraps every WIT export with correct ABI translation — numbers pass directly, strings are encoded/decoded through WASM linear memory, booleans are normalized. Completes the DLL model: write TypeScript → compile to `.wasm` via wasic → load from a TypeScript host with full type safety and no manual `WebAssembly` API.

**Test files** (all PASS):

- `bindgen_fixtures/math_50.ts` — `add(i32,i32):i32`, `multiply(f64,f64):f64`, `square(i32):i32`; numeric round-trip
- `bindgen_fixtures/booleans_50.ts` — `isPositive(f64):bool`, `inRange(f64,f64,f64):bool`, `isEven(i32):bool`; bool normalization
- `bindgen_fixtures/strings_50.ts` — `greet(string):string`, `shout(string):string`, `strLen(string):i32`; string param encoding + string-return side-channel
- `bindgen_fixtures/imports_50.ts` — `declare const env` external bindings + `scale`/`combine` exports; WIT import section + host callback wiring

**`src/bindgen.ts`** — new standalone module, no external dependencies. Exports:

- `WitType`, `WitParam`, `WitFunc`, `ParsedWit`, `BindgenOptions` — public types
- `parseWit(src: string): ParsedWit` — regex-based WIT parser extracting `packageName`, `worldName`, `imports[]`, `exports[]`
- `generateBindings(witSrc: string, opts: BindgenOptions): string` — produces complete TypeScript binding file
- `runBindgen(witPath, opts): Promise<void>` — CLI entry point

**`kebabToCamel(name)`** — converts WIT kebab-case names to camelCase for WASM export lookup (e.g. `is-positive` → `isPositive`). WASM exports use the original TypeScript camelCase function names, NOT underscored names.

**`kebabToWasmName(name)`** — converts to underscore format for Phase 40 `env` import keys (e.g. `env-mul` → `env_mul`). Used only for env import object keys in `genLoadModule`.

**`genLoadModule(parsed, runtime)`** — generates the async `loadModule` function body:

- Emits `env` object wiring when WIT has imports; each entry wraps the user callback with ABI adaptation
- Chooses the file-loading strategy based on `runtime`: Deno (`fetch`), Node (`node:fs`), Bun (`Bun.file().arrayBuffer()`)
- Conditionally emits `_malloc`/`_writeStr` helpers when exports have string params
- Conditionally emits `_strRetPtr`/`_strRetLen`/`_readStr` helpers when exports have string returns
- Emits a wrapper method per export with per-param/return ABI translation

**WIT string type change** — `watTypeToWit("string")` in `wasic.ts` now returns `"string"` (WIT-native type) instead of the previous `"s32"` (pointer representation). `generateWit()` emits `name: string` as a single parameter instead of `name-ptr: s32, name-len: s32` pair. This enables clean ABI mapping in bindgen without ptr/len heuristics.

**WASM exports for bindgen** — `toWat()` in `wasic.ts` conditionally appends (Stage 0 Canonical ABI):

- `(export "cabi_realloc" (func $cabi_realloc))` — when any exported function has a `string` parameter or `string` return; `$cabi_realloc` is a thin wrapper around `$__malloc` using a WAT `select` instruction: `select(call $__malloc(new_size), ptr, i32.eqz(ptr))`
- `$fn__cabi` shim wrappers — for each exported string-returning function, a `(func $fn__cabi (export "fn") ... (param $__ret_area i32))` is appended; it calls the internal `$fn` (which writes `$__str_ret_ptr`/`$__str_ret_len` globals), then stores `(global.get $__str_ret_ptr)` and `(global.get $__str_ret_len)` into the caller's return area. The original `$fn` is NOT directly exported.
- `__str_ret_ptr`/`__str_ret_len` globals are **not exported** (Stage 0 removed these exports; the shim approach bridges internally)

**`main.ts` wiring** — `case "bindgen"` with `-o` / `--runtime` flags and help text. `deno.json` adds `"./bindgen": "./src/bindgen.ts"` export.

**Test runner** — `tests/bindgen_tests.ts`: 102 assertions. 4 `parseWit` unit tests, 4 `generateBindings` unit tests (interface shape, bool conversions, string ABI, import section), 4 integration tests (compile fixture via `wasmtk modc` → generate binding → write host runner → run with Deno subprocess → check stdout), 1 CLI invocation test. Uses `toFileUrl()` from `jsr:@std/path` for Windows-compatible `file:///` import URLs in generated host runners.

**Known limitations:**

- `cabi_realloc` delegates to the bump allocator (no free); hosts making many string-param calls in a long-running process may eventually exhaust the heap.
- Struct/object returns appear as `number` (raw pointer into WASM linear memory).
- `--runtime node` and `--runtime bun` loaders are code-generated but not integration-tested.

---

## `hybrid` Command — TypeScript/WASM Split Compiler

`wasmtk hybrid <file.ts>` splits a single TypeScript file into a wasic-compiled WASM core module and a TypeScript runner. Functions annotated with `// @wasm` on the immediately preceding line are extracted and routed through the full `modc → bindgen` pipeline; everything else stays as TypeScript.

**Pipeline (five steps):**

1. Parse source → extract `// @wasm`-annotated functions + remaining source
2. Write `<base>_core.ts` containing the extracted functions (all with `export`)
3. `wasmtk modc` compiles `_core.ts` → `_core.wasm` + `_core.wit`
4. `wasmtk bindgen` reads `_core.wit` → `_core.bindings.ts`
5. Write `<base>_runner.ts`: remaining TypeScript + `import { loadModule }` + `const lib = await loadModule(...)` + call-site rewrites

**`src/hybrid.ts`** — new standalone module. Key exports:

- `parseHybridFile(src: string): ParseResult` — regex + brace-counting parser; returns `wasmFuncs[]`, `remainingSrc`, and `warnings[]`
- `generateCoreModule(wasmFuncs: WasmFunc[]): string` — emits the extracted functions as a wasic-compilable module
- `generateRunner(remainingSrc, wasmFuncNames, bindingsRelPath, wasmRelPath): string` — rewrites call sites and injects `loadModule` after the last `import` statement
- `runHybrid(inputPath, opts): Promise<void>` — orchestrates the full pipeline

**`parseHybridFile` rules:**

- `// @wasm` must be the exact content of the annotation line (no trailing text)
- Blank lines between annotation and function declaration are skipped
- Only named `function` declarations are supported; arrow functions and class methods are not
- Async functions: skipped with `⚠  hybrid: skipping 'name' — async functions cannot be compiled by wasic`
- Non-wasic parameter/return types (anything not in `i32|i64|f32|f64|bool|boolean|string|void|never|number` or simple `T[]`) produce a warning but do not stop extraction — wasic will report the error at compile time
- Extracted functions are ensured to have the `export` keyword

**Call-site rewriting in `generateRunner`:**

Regex: `(?<![."'\x60\w])funcName\s*\(` — negative lookbehind for `.`, `"`, `'`, backtick, and word chars. Bare calls are rewritten; method calls (`obj.funcName(`), string literals (`"funcName("`), and template expressions are not.

**Generated runner uses top-level `await`** (native in Deno ES modules). The `const lib = await loadModule(new URL("..._core.wasm", import.meta.url))` line is injected immediately after the last `import` statement in the remaining source.

**CLI wiring:** `case "hybrid"` in `main.ts`; `-o`/`--name` flag sets `outDir`. `deno.json` exports `"./hybrid": "./src/hybrid.ts"`.

**Test fixtures:** `tests/hybrid_fixtures/math_hybrid.ts` (i32/f64/bool functions + TypeScript caller), `tests/hybrid_fixtures/strings_hybrid.ts` (string param/return functions + TypeScript caller).

**Known limitations (prototype):**

- Shared mutable module-level state does not cross the WASM boundary — globals declared at the top level of the original file that are read/written by both `@wasm` and non-`@wasm` code will be duplicated (one copy in WASM linear memory, one in JS heap). Workaround: expose shared state as exported getter/setter functions.
- `// @wasm` annotated functions that call other `// @wasm` functions are fine (they all land in the core module); `@wasm` functions that call non-`@wasm` TypeScript functions need `declare const` Phase 40 import stubs added manually to the core module.
- Call-site rewriting is regex-based and does not parse the AST; pathological cases (e.g. `funcName` as a property key in an object literal `{ funcName: 1 }`) will be incorrectly rewritten. These are rare in practice.

---

## `bindgen` Lint Fix — removed unused `retConvert` variable

`src/bindgen.ts` `genLoadModule()` had an unused local `retConvert` computed inside the import-wiring loop. The variable was a leftover from an earlier draft; the actual env wrapper lines (185/187) duplicate its logic directly inline. Removed lines 179–183 of the original file.

---

## Future WASM Compatibility Limitations

The following TypeScript/Go patterns **cannot be implemented in WASI Preview 1** without additional WASM proposals. The Go-by-Example tests for these topics have been adapted to single-threaded equivalents and currently pass — this section documents the general feature class and what proposal would unblock it.

### Goroutines / Cooperative Multitasking

**Blocked by**: WASM Stack-Switching proposal (or Asyncify transform)

Go goroutines are green threads — lightweight cooperative coroutines. WASM execution is single-stack and single-threaded. The WASM Stack-Switching proposal (part of the roadmap toward WASI Preview 3) would add `cont.new`/`cont.resume`/`cont.suspend` instructions enabling coroutine-style suspension. Until that proposal reaches the WASM MVP, goroutines cannot be implemented natively.

Workarounds in scope today: Asyncify (Binaryen pass) can CPS-transform WASM to simulate suspension, but produces large binaries and requires a JavaScript host. Not suitable for standalone WASI modules.

### Shared Memory + Atomic Operations

**Blocked by**: WASM Threads proposal

Go's memory model assumes shared mutable state between goroutines, protected by mutexes and atomic operations. WASM's `SharedArrayBuffer`-backed memory and `i32.atomic.*` instructions (the Threads proposal) are required. These are available in browsers but WASI Preview 1 runners (wasmtime, wasmer) do not expose shared memory by default, and the `wasi_threads` snapshot is not yet standardized.

### Channel / Select Communication

**Blocked by**: Stack-Switching + Shared Memory (both above)

Go channels are rendezvous-based synchronization between goroutines. Implementing them requires the ability to suspend one goroutine (stack-switching) and resume it when a sender/receiver is ready. No WASI p1 primitive supports this.

### `os.Exit` with Non-Zero Status

**Blocked by**: WASI Preview 1 `proc_exit` behavior in runners

`proc_exit(n)` with n ≠ 0 terminates the WASM process and reports exit code n to the host. This works correctly in wasmtime/wasmer, but the wasic test runner (Deno's WASI shim) currently treats all exits as success for test comparison purposes. Full exit code propagation is a test runner enhancement, not a wasic compiler change.

---

## Project Vision — TypeScript as DLL

**Goal (established 2026-05-14):** Compile TypeScript business logic to `.wasm` libraries and load them from a TypeScript host the same way a C program uses a DLL — the `.wasm` is the shared library, the host is the application. No embedded JS runtime; everything maps to static WASM constructs.

**How to apply:** When discussing architecture or integration patterns, frame suggestions around this model. Prefer `modc` (library mode, Phase 17) over `wasic` (WASI executable mode) for modules intended to be consumed by a host. The `.wit` file (Phase 41) is the interface contract; the `.bindings.ts` file (Phase 50 `wasmtk bindgen`) is the import library.

### Analogy to C DLLs

| C / DLL world | wasic world |
| --- | --- |
| `.c` source → `.dll` / `.so` | `.ts` source → `.wasm` via `wasmtk modc` |
| `.h` header file | `.wit` file (Phase 41, auto-generated alongside `.wasm`) |
| Import library (`.lib`) | `.bindings.ts` (Phase 50 `wasmtk bindgen`) |
| `LoadLibrary` + `GetProcAddress` | `loadModule()` from the generated binding file |
| Calling convention (cdecl etc.) | wasic ABI: numerics direct; strings as `(ptr: i32, len: i32)` |

### Infrastructure Already in Place

- **`modc` library mode** (Phase 17) — compiles without `_start` / WASI entry; exports named functions directly
- **WIT generation** (Phase 41) — auto-writes `.wit` alongside `.wasm` describing every export and import
- **External bindings** (Phase 40) — `declare const host: { ... }` maps to `(import "env" ...)` WASM imports; the generated binding's `ModuleImports` interface is the host side of this

### What Phase 50 (`bindgen`) Delivers (COMPLETE)

`wasmtk bindgen <module.wit>` reads the WIT file and emits `module.bindings.ts`. The DLL model is now fully operational:

```typescript
import { loadModule } from "./math.bindings.ts";
const lib = await loadModule("./math.wasm");
console.log(lib.add(2, 3));      // number
console.log(lib.greet("world")); // string
console.log(lib.isEven(4));      // boolean
```

### ABI Details

- **Numeric params/returns** (`s32`/`s64`/`f32`/`f64`) — pass directly as JS numbers
- **String params** — `TextEncoder` → `cabi_realloc(0, 0, 1, len)` → write bytes → pass `(ptr, len)` as two WASM args; `cabi_realloc` auto-exported by wasic when any exported function has a string param
- **String returns** — Canonical ABI out-parameter: host allocates 8-byte return area via `cabi_realloc(0, 0, 4, 8)`, passes its address as trailing arg to the shim; shim writes `(ptr, len)` at offsets 0 and 4; host reads back via `DataView.getInt32`
- **Bool params** → `value ? 1 : 0`; **bool returns** → `result !== 0`
- **Struct returns** — not yet handled; appear as raw `number` (pointer into WASM linear memory)

### Instance Lifecycle Model (Bump Allocator Memory Strategy)

wasic uses a bump allocator (`$__malloc`) with no `free`. Allocations for string params, arrays, and structs accumulate for the lifetime of the WASM instance. This is intentional and correct for the primary DLL use case, but requires attention for server/loop use cases.

**Two supported patterns — both addressed in Stage 1 (`universalWasmLoader`):**

**Singleton** — `wasm_import(path, opts)` caches one instance after first load. Correct for CLI tools, apps that load a library at startup, numeric-only exports, any bounded-call scenario. Memory never meaningfully fills up.

**Pool** — `createPool(path, { size, ...opts })` holds `size` fresh WASM instances and cycles through them. Each checkout gets an instance with a fresh bump pointer; no memory-reset logic needed. Correct for servers handling many requests with string-param calls.

`InstancePool` API (to be implemented in `universalWasmLoader` Stage 1):

- `acquire(): Promise<T>` — checks out an instance; waits if all are busy
- `release(instance: T): void` — returns instance to pool
- `run<R>(fn: (lib: T) => R | Promise<R>): Promise<R>` — acquire + call + release
- `size: number` — total pool capacity
- `available: number` — idle instance count
- `destroy(): void` — tears down all instances

**`cabi_post_return`** (future, full Component Model): The WASM Component Model specifies a `cabi_post_return` function that a runtime calls after each lifted call to free string memory allocated during that call. This would eliminate the need for instance pooling. Deferred until wasic targets a full Component Model runtime (wasmtime with wit-bindgen); the pool pattern is the correct mitigation in the current direct-host model.

---

## Polyglot Ecosystem Vision

Full details, guiding principles, the ecosystem layer diagram, language support matrix, and per-project specs are in `cmem/vision.md` (the former root VISION.md, moved into cmem 2026-05-31; git-tracked/portable). This section captures the key architectural decisions needed for future sessions.

**Vision**: Build a polyglot application ecosystem where WASM is the universal binary format and WIT is the universal interface contract. Any language compiles to a WASM component. Components compose into complete applications regardless of source language. pixi manages toolchains; wasmtk manages WASM intelligence.

**Guiding decisions:**

- WIT is the universal interface contract; language behind a component is an implementation detail
- Canonical ABI is the transport standard (wasmtk Stage 0 complete — `cabi_realloc`, out-param string returns)
- TypeScript/JS (`universalWasmLoader`) is the reference loader implementation; all other language loaders must match its spec
- Progressive porting (swap component language behind same WIT) is a first-class workflow

### Staged Roadmap

| Stage | Scope | Status |
| --- | --- | --- |
| Stage 0 | Canonical ABI alignment in wasmtk (`cabi_realloc`, out-param string returns) | ✅ COMPLETE (2026-05-19) |
| Stage 1 | `universalWasmLoader` — WIT-aware loader + `SPEC.md` + `InstancePool` | **CURRENT PRIORITY** |
| Stage 2 | `universalWasmLoader-rs` (Rust, crates.io) + `universalWasmLoader-py` (Python, PyPI) | Planned |
| Stage 3 | `wasmtk build` + `wasmtk compose` — polyglot build orchestration via pixi; `[wasmtk]` in `pixi.toml` | Planned |
| Stage 4 | `wasmtk setup/port/activate`, additional loaders (Go, JVM, C header-only) | Planned |
| Stage 5 | Component registry, IDE integration, cross-component debug/profiler | Long-term |

**Stage 1 reference**: `src/bindgen.ts` (Phase 50) is the authoritative ABI implementation that Stage 1 replicates at runtime (reading WIT dynamically instead of code-generating). Key ABI: `cabi_realloc(0,0,4,8)` for the 8-byte string return area, `DataView.getInt32` at offsets 0/4 to read back ptr+len, `TextEncoder` + `cabi_realloc` for string params. `SPEC.md` lives in the `universalWasmLoader` repo.

**Stage 1 `InstancePool` API** (to implement in `universal-wasm-loader.js`):

```javascript
// Singleton (DLL pattern — default)
const lib = await wasm_import("./module.wasm");
lib.greet("world");

// Pool (server/loop pattern)
const pool = await createPool("./module.wasm", { size: 4 });
const result = await pool.run(lib => lib.greet("world"));  // acquire → call → release

// Manual acquire/release
const lib2 = await pool.acquire();
try { lib2.greet("world"); }
finally { pool.release(lib2); }
```

**Stage 3 `pixi.toml` `[wasmtk]` format** (see `cmem/vision.md` for full example):

```toml
[wasmtk.components]
api    = { language = "typescript", source = "src/api/",    wit = "interfaces/api.wit" }
engine = { language = "rust",       source = "src/engine/", wit = "interfaces/engine.wit" }

[wasmtk.composition]
engine -> api

[wasmtk.host]
runtime = "deno"
loader  = "universalWasmLoader"
```

**Repository map**:

| Repo | Role | Stage |
| --- | --- | --- |
| `jrmarcum/wasmtk` | TypeScript compiler + polyglot build CLI | Active |
| `jrmarcum/universalWasmLoader` | JS/TS loader + `SPEC.md` (reference impl) | Stage 1 |
| `jrmarcum/universalWasmLoader-rs` | Rust port (crates.io) | Stage 2 |
| `jrmarcum/universalWasmLoader-py` | Python port (PyPI) | Stage 2 |
| `jrmarcum/universalWasmLoader-go` | Go port | Stage 4 |
| `jrmarcum/universalWasmLoader-jvm` | Java/Kotlin port (Maven Central) | Stage 4 |
| `jrmarcum/universalWasmLoader-c` | Zig/V/Julia header-only | Stage 4 |

**Language support matrix** (full table in `cmem/vision.md`): TypeScript (wasic), Rust (`--lang=rust` → rsxtk), Python (componentize-py) are Tier 1. Go (`--lang=go` → TinyGo/std), Zig (`--lang=zig`) are Tier 2. Java/Kotlin (TeaVM/GraalVM), V, Julia (via wasmtime C API) are Tier 3. The Go/Rust/Zig producers shipped 2026-06-06/07 (`src/gowasic.ts` / `rustwasic.ts` / `zigwasic.ts`); bindgen for their output is deferred.

**Immediate next steps** (as of 2026-05-19):

1. Stage 1 — Enhance `universalWasmLoader` + write `SPEC.md` — **CURRENT PRIORITY**
2. Stage 2 — `universalWasmLoader-rs` then `universalWasmLoader-py` — validates the spec
3. Stage 3 — Build orchestration with pixi integration

---

## TypeScript Feature Gap Analysis

Completed 2026-05-14. Reference for future phase planning beyond Phase 50.

### Compilable to WASM — Not Yet Scheduled

These do not require a runtime and could be added to wasic in future phases:

#### Operators & Expressions

- Object spread `{...obj, field: val}` — for known struct types: emit field copies then set overrides; static layout makes this feasible
- `in` operator for known struct fields — always resolvable at compile time in the closed world; emit `(i32.const 1/0)`
- `void expr` — `(drop ...)` wrapper; rare but valid TypeScript
- Chained assignment `a = b = c = 0` — only single-target currently tracked
- `instanceof` for DU / class hierarchy tags — natural follow-on once Phase 47 class tags exist

#### Type System (compile-time expansions)

- TypeScript utility types — `Partial<T>`, `Readonly<T>`, `Pick<T,K>`, `Omit<T,K>`, `Record<K,V>`, `Exclude<T,U>`, `Extract<T,U>`, `NonNullable<T>`, `ReturnType<T>`, `Parameters<T>` — all pure source-level expansions; could be added similarly to how Phase 36 adds conditional types via `expandConditionalTypes()`

#### Built-ins

- `Array.from([1,2,3])` — equivalent to an array literal; trivial
- `Array.isArray(x)` — always `(i32.const 1)` for known array variables in wasic's closed world
- `Array.of(...items)` — same as an array literal
- `String.fromCodePoint(n)` — Unicode code-point variant of the existing `fromCharCode`
- `Number.parseInt(s, radix)` / `Number.parseFloat(s)` — needs WAT string-to-number parsing (non-trivial)

#### Destructuring

- Nested object destructuring `const { a: { b } } = obj` — only one level currently
- Destructuring in function parameters `function f({ x, y }: Vec2)` — parameters are positional today
- Nested array destructuring `const [[a, b], c] = arr`

#### Class / OOP

- `super.method()` from within a derived method body — implemented 2026-05-24 (Phase 47 extension)
- Multi-level interface inheritance beyond two levels deep — Phase 30 implements single-level; deeper chains may break offset calculations

### Requires a Runtime — javyc Territory (beyond existing javyc list)

- `for...in` — runtime property enumeration (already noted in CLAUDE.md javyc list)
- `Object.keys/values/entries` — dynamic property iteration
- `Object.assign`, `Object.freeze`, `Object.seal` — runtime mutation
- `instanceof` against arbitrary prototype chains — no prototype in wasic
- Iterator protocol / `Symbol.iterator` — custom iterables for `for...of`
- Tagged template literals `` fn`hello ${name}` `` — requires a `TemplateStringsArray` runtime object
- `arguments` object — legacy variadic access in non-arrow functions
- `eval()` / `Function` constructor — dynamic compilation
- `globalThis`, `import.meta` — environment globals
- `WeakRef`, `FinalizationRegistry` — GC interaction
- `Intl` API — locale runtime
- `Atomics`, `SharedArrayBuffer` — WASM Threads proposal required

### Most Impactful Unscheduled Gaps

In rough priority order for a real TypeScript developer:

1. **Object spread** `{...base, field: val}` — extremely common pattern; static layout makes it feasible
2. **TypeScript utility types** — `Partial<T>`, `Record<K,V>` etc.; compile-time expansion only
3. **Destructuring in function parameters** — `function f({ x, y }: Vec2)` is a common idiom for struct-typed params
4. **`Number.parseInt` / `Number.parseFloat`** — needed for any input-parsing code
5. **`instanceof`** — natural follow-on once Phase 47 class tags are in place
