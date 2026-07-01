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

## Current pass counts (2026-06-22, wabt-ts 1.3.2 + binaryen-ts 1.3.5)

| Suite | Result |
| --- | --- |
| `tests/wasm_wasi` (full, HARDENED output-diff runner) | **360 / 360** (+`18zz_DynFullCompile` 2026-06-30 — #14 Route A 2h: the full-dynamic-compile entry `wasmtk dync` (the `javyc` replacement) — `@test-pipeline` (dync→run) compiling a whole dynamic program (closures + class + Array methods + for-loop + `console.log`) through wasmtk's OWN runtime (embedded `wasmtk:dynrt`), no Javy/QuickJS; the interpreter now PRINTS (console.log → `env.__host_print` → stdout) and `dync` base64-embeds the source so wasic's line-based scanner can't mis-parse it; byte-exact OUTPUT parity vs a `deno run` baseline is the separate gate `tests/dync_conformance_tests.ts` (demo1/2/3, 3/3). +`18zy_DynRuntimeEs6Misc` 2026-06-30 — #14 Route A 2e.11: the remaining ES6 surface in eval source — `instanceof` (walks the instance `__proto__` chain for the class prototype), object spread `{ ...o }` + call spread `f(...args)`, array/object destructuring (`const [a, , c] = …` incl. holes/missing, `const { x, y: z } = …` incl. rename), and class expressions (`const C = class {…}`, anonymous + `extends`); `runClassDecl` refactored into a shared `buildClass` helper (statement binds `__name`, parsePrimary returns the object); purely interpreter-side. +`18zx_DynRuntimeAsync` 2026-06-26 — #14 Route A 2e.10: async/await + Promise in eval source, SYNCHRONOUS model (no event loop) — `async function` wraps its result in a settled Promise, `await` unwraps (throws on rejected → integrates with try/catch), `.then`/`.catch`/`.finally` run callbacks immediately, `Promise.resolve`/`reject`/`all`; purely interpreter-side. +`18zw_DynRuntimeGenerators` 2026-06-26 — #14 Route A 2e.9: generators (`function*` / `yield`) in eval source via EAGER COLLECTION (the re-parse interpreter can't suspend) — calling a `function*` runs the body collecting yields into an array; the generator object serves them via `.next()` → `{value,done}` and `for…of`; finite generators only; covers next-sequence/done/empty/for-of/while-loops/params/computed+conditional/nested; purely interpreter-side. +`18zv_DynRuntimeRegExp` 2026-06-26 — #14 Route A 2f.7 (completes the f-series stdlib): RegExp in eval source — `new RegExp(pat)` + a compact backtracking matcher (literals, `.`, `*`/`+`/`?`, `^`/`$`, char classes `[…]`/ranges/negation, `\d\w\s`), `re.test` → bool, `re.exec`/`str.match(re)` → first match or null; purely interpreter-side. +`18zu_DynRuntimeMapSet` 2026-06-26 — #14 Route A 2f.6: Map + Set in eval source — `new Map()`/`new Set(iterable)` build a dynrt object with internal key/value arrays; Map set/get/has/delete/keys/values/forEach/size, Set add/has/delete/values/forEach/size; arbitrary boxed keys via === scan; methods dispatch in parsePostfix, `.size` via dynMember; chainable set/add; purely interpreter-side. +`18zt_DynRuntimeJson` 2026-06-26 — #14 Route A 2f.5: JSON in eval source — `JSON.parse(str)` (reuses the interpreter's own literal parser since JSON ⊂ the expression grammar → native dynrt values) + `JSON.stringify(value)` (recursive serialization); object/array/nested/scalars + parse∘stringify round-trips; special-cased in parsePrimary; purely interpreter-side. +`18zs_DynRuntimeObjectMath` 2026-06-26 — #14 Route A 2f.4: Object + Math namespace statics in eval source — `Math.floor`/`ceil`/`round`/`trunc`/`abs`/`sqrt`/`sign`/`min`/`max`/`pow` + `Math.PI`/`Math.E` (reusing the wasic f64 intrinsics), `Object.keys`/`values`/`entries`/`assign`; special-cased in parsePrimary as `NS.method(args)`; purely interpreter-side. +`18zr_DynRuntimeStringMethods` 2026-06-26 — #14 Route A 2f.3: built-in STRING METHODS in eval source — `charAt`/`charCodeAt`/`toUpperCase`/`toLowerCase`/`trim`/`slice`/`indexOf`/`includes`/`startsWith`/`endsWith`/`repeat`/`padStart`/`padEnd`/`concat`/`split`; `dynStringMethod` unboxes to a wasic string + reuses the compiler's own string ops, results re-box so methods chain; dispatched in parsePostfix for tag-4 receivers; purely interpreter-side. +`18zq_DynRuntimeArrayMethods` 2026-06-26 — #14 Route A 2f.2 (first stdlib increment): built-in ARRAY METHODS in eval source — `push`/`pop`/`shift`/`unshift`/`indexOf`/`lastIndexOf`/`includes`/`at`/`join`/`slice`/`concat`/`reverse`/`sort` (numeric default + comparator) + callback methods `map`/`filter`/`forEach`/`reduce`/`find`/`findIndex`/`some`/`every` (callback with element+index) + chaining (`filter().map()`); `dynArrayMethod` dispatched in parsePostfix when the receiver is an array and the member isn't a user function; purely interpreter-side. +`18zp_DynRuntimeClassExtends` 2026-06-26 — #14 Route A 2e.8a: CLASS COMPLETION — `extends` (prototype-chained inheritance), `super(args)` (base ctor, incl. 3-level chain), `super.method()` (overridden base method, this=instance), `static` methods+fields on the class object, instance fields (`x = expr;` → constructor preamble), getters/setters (`get x(){…}`/`set x(v){…}` via `__get_`/`__set_` markers + `dynMember` getter-fallback + `dynSetMember`); the class feature is now complete (only class EXPRESSIONS remain statement-only). +`18zo_DynRuntimeClasses` 2026-06-26 — #14 Route A 2e.8: CLASSES (`class Name { constructor(){…} method(){…} }` + `new Name(args)` → instance with prototype methods + `this`-bound constructor; independent instances, method-calls-sibling-via-`this`, no-ctor class; `runClassDecl`+`dynNew`+`new` operator on the 2f.1 foundation). ALSO the regression test for a general wasic fix: `parseClasses` was string-blind → a `class…{}` inside the driver's eval-source STRINGS was parsed as a real class; now detects over a `maskCode` code-only mask (see compiler-bugs.md). +`18zn_DynRuntimeThisPrototype` 2026-06-26 — #14 Route A 2f.1: `this` + prototype (object-model foundation for 2e.8 classes) — object-literal method shorthand `{ m(){…} }` + `m: function(){}`, `obj.m(args)` binds `this` to the receiver (read + write `this.field`), method-calls-method via `this.other()`, plain call → `this === undefined`, and `Object.create(proto)` with prototype-chain member lookup (own shadows inherited); `dynApplyThis` + `parsePostfix` recv tracking + slot-2 `__proto__`; purely interpreter-side; +`18zk_VarGateSafe`/`18zl_VarGateBlockEscape`/`18zm_VarGateLoopClosure` 2026-06-26 — #14 Route A 2e.7b: the `var`→`let` consumption gate (`src/varscope.ts`, FIRST wasic-compiler change in the 2e.x series) — provably-safe `var` auto-repaired to `let` (18zk compiles+runs), UNSAFE `var` hard-errors with line:col (18zl block-escape / 18zm loop-closure are `@expect-fail: compile`); code-only via maskCode (var-in-string untouched); also `tests/varscope_tests.ts` 12/12 standalone (every safe pattern rewrites, every unsafe pattern errors); +`18zj_DynRuntimePerIterationLet` 2026-06-26 — #14 Route A 2e.7a: PER-ITERATION `let` binding in eval source (`for (let i…)`/`for (const x of…)` give each iteration a fresh binding so a closure in the body captures that iteration's value 0,1,2 not the shared 3,3,3; `var` stays a single shared binding; covers classic-for/for-of/continue/body-let; new `cloneEnvFlat` + `perIter` flag); purely interpreter-side; +`18zi_DynRuntimeBlockScope` 2026-06-26 — #14 Route A 2e.7: lexical BLOCK SCOPING in eval source (each `{ }` block / `for` loop / `catch` runs in a fresh `childEnv`, `let`/`const` don't leak; bare assignment/`++`/`+=` walk the chain via `envAssign` to update the declaring scope not a shadow; fresh `catch (e)` scope); purely interpreter-side. ALSO fixed a latent process bug shipped in v1.10.6 source: `deno fmt` had wrapped 3 deeply-indented ternaries into multi-line form that modc can't parse (binary was fine — caps_bytes is pre-fmt) — converted to single-line if/else; see compiler-bugs.md; +`18zh_DynRuntimeTryCatch` 2026-06-26 — #14 Route A 2e.6: `throw`/`try`/`catch`/`finally` in eval source (binding + binding-less `catch {}`, `try/finally` no-catch, throw propagation through statements/loops/function CALLS, nested try/catch re-throw); new `evalThrew`/`evalThrowVal` control globals mirror `evalReturned` but are NOT consumed at the call boundary; purely interpreter-side, no wasic change; +`18zg_DynRuntimeOperators` 2026-06-24 — #14 Route A 2e.5: operators (`typeof`, `??`, `?.` optional chaining, array spread `[...a]`); also fixed a general wasic bug — the `?.`→`.` strip mis-firing inside string literals; +`18zf_DynRuntimeMemberAssign` 2026-06-24 — #14 Route A 2e.4: member/index assignment (`o.x=v`, `o[k]=v`, `arr[i]=v`, compound, nested, computed keys, in-loop); +`18ze_DynRuntimeFunctionExprs` 2026-06-24 — #14 Route A 2e.3: dynrt function expressions + arrow functions (block/expr body, single/multi/no param, higher-order, closures, nested); also fixed 2 wasic compiler bugs — arrow detection mis-firing on `=>` inside string literals); +`18zd_DynRuntimeLiterals` 2026-06-24 — #14 Route A 2e.2: array/object/template literals in eval source (+`for…of` over an inline array literal); +`18zc_DynRuntimeControlFlow` 2026-06-24 — #14 Route A 2e.1 (COMPLETE): dynrt interpreter control flow — C-style `for`, `for…of`, `for-in`, `do…while`, `switch` (fall-through), `break`/`continue`, `++`/`--`/`+=`; +`18zb_PrepassStringSafety` 2026-06-24 — audit regression: the `eval(`/`Function(` source pre-passes must rewrite ONLY real code (output-diff: a program that PRINTS `eval( … )`/`Function( … )` with no real dynamic code — strings survive AND dynrt is not spuriously merged); +`18za_FnAnyPinTable` 2026-06-23 — #14 final item functions-as-`any`: host pin table (`dynGcPin`/`dynGcUnpin`) — a pinned function survives collection + calls correctly; bindgen `_unbox` tag-7 JS proxy + `Function(params,body)` producer → dynMakeFn; full end-to-end `getDoubler()(21)=42`); +`18z_GcHybridAllocator` 2026-06-23 — #14 GC: hybrid allocator (segregated buckets + batch-defrag coalescing; integrity-verified through the stress that hung coalesce-on-free); +`18y_GcSplit` 2026-06-23 — #14 GC polish: free-list splitting (`dynAlloc` carves the leftover off an oversized reused block — closes a slow size-mismatch leak; mixed-size build/drop/collect cycles stay correct + bounded); +`18x_GcBoundedMemory` 2026-06-23 — #14 GC Part 5b (GC track COMPLETE): payload reclamation + auto-collect trigger + mid-expression intermediate rooting; a 10000-iter interpreter loop runs in bounded memory (~30000 cells allocated, 5 live after collect); +`18w_GcCollect` 2026-06-23 — #14 GC Part 5a: mark-sweep collect (`dynGcCollect` reclaims unmarked cells into dynrt's recycling free list; live survives; reuse verified); +`18v_GcShadowStack` 2026-06-23 — #14 GC Part 4b: interpreter shadow-stack (`dynRun` pushes/pops its scope as a GC root; `dynGcMarkRoots`; `gcMark` follows env parent slot-2; balance + driver-root + closure-chain verified); +`18u_GcMark` 2026-06-22 — #14 GC Part 4a: mark phase (`gcMark(root)` recursively marks reachable cells; mark bit = tag bit 8; reachability + orphan-exclusion verified); +`18t_GcCellRegistry` 2026-06-22 — #14 GC Part 3: cell registry (every value cell via `mkCell`/`mkCell5` → `__gc_reg`; `dynGcCellCount()` tracks 20004 cells; surfaced+fixed the wasmmerge mutable-global-clobber bug); +`18s_GcFreeList` 2026-06-22 — #14 GC Part 2: free-list allocator (`$__free` + `$__malloc` first-fit; reuse verified via `__malloc`/`__free`/`__heapPtr` intrinsics); +`18r_DynRuntimeDeepRecursion` 2026-06-22 — #14 GC Part 1: auto-grow `$__malloc` (`fib(15)` ≈1973 interpreter calls, was overflowing); +`18q_DynAnyFoundation` 2026-06-22 — #14.3.1–3.3: wasic `any` type + auto-merge of `wasmtk:dynrt` + implicit boxing / `as`-unboxing + operators (arith/compare/logical) + member/index/call (`x.foo`/`x[i]`/`x(args)`) + bare `eval` → all route to dynrt. (#14.3.4 hybrid `--auto` dynamic-body routing is verified by the `tests/hybrid_fixtures/dynamic_hybrid*` fixtures, run manually — not in the auto suite.); +`18p_DynRuntimeFunctions` 2026-06-22 — #14 increment 2d.2: user-defined functions + `new Function` (completes the interpreter); +`18o_DynRuntimeStatements` 2026-06-22 — #14 increment 2d.1: statements + control flow (`dynRun`: let/const/assignment, if/else, while, blocks, return); +`18n_DynRuntimeCalls` 2026-06-22 — #14 increment 2c: function values + calls + real short-circuit; +`18m_DynRuntimeEvalEnv` 2026-06-22 — #14 increment 2b: eval with variables + environment + member/index access; +`18l_DynRuntimeEval` 2026-06-22 — #14 increment 2a: `eval` of a pure expression language (recursive-descent direct-eval parser in the subset); +`18k_DynRuntimeVirtualImport` 2026-06-22 — #14 increment 1b: the dynamic runtime via the virtual `wasmtk:dynrt` import + tree-shake; +`18j_DynRuntimeValueModel` 2026-06-22 — #14 increment 1: boxed-value + dynamic-object model as a shared-heap `modc` capability; see dynrt-design.md. +`54_AsyncBasic` … `61_AsyncAllSettled` 2026-06-15 — #13 async sub-phases 13.1a (async/await + Promise.resolve) + 13.2 (.then + microtask queue) + 13.3a (Promise.reject + rejection→exception) + 13.3b (.catch/.finally rejection reactions + .then(onF,onR), dual-path trampoline) + 13.1b (promise-var inner-type tracking + capturing-closure callbacks via env-bearing reaction record) + 13.4 (Promise.all + allSettled — per-call-site combinators, array-literal arg, i32/f64); the entire v1 Promise API surface; see async-design.md; +`53_NumberParse` + `53_InterfaceInheritance` 2026-06-15 — Phase 53; +`27_ConsoleLogStringCompare` 2026-06-12 — console.log string/numeric comparison fixes (findTopLevelOp paren-tail, string ===/!== resolver, != inversion, string .length operand); +`15_ElseChainForms` — brace-less/single-line-braced else-chain drop bug; see compiler-bugs.md. Earlier: 6 Phase 52 tests added 2026-06-11; the 14 output-mismatch bugs the 2026-06-07 runner-hardening surfaced are ALL FIXED 2026-06-08; 6 tests carry `// @allow-output-diff` for documented float-precision / zero-sentinel divergences, incl. `1_values`) |
| `bindgen_tests.ts` | **131 / 131** (functions-as-`any` both directions: core→host `testIntegrationFnAny` `getDoubler()(21)=42` + proxy-robustness assertions; **#14 Phase 2 host→core `testIntegrationHostFn`** — `applyTwice(n=>n+1,10)=12` / `combine((a,b)=>a*b,6,7)=42` via the `env.__host_call` import + host-fn table) |
| `jstyper_tests.ts` | **73 / 73** |
| `dync_conformance_tests.ts` (#14 2h Javy-parity gate) | **3 / 3** — for each fixture in `tests/wasm_wasi_dync/` (demo1/2/3), `wasmtk dync`→`.wasm`→`run` stdout must byte-match a `deno run` JS baseline. Proves the OWN dynamic runtime is a drop-in `javyc` replacement (no Javy/QuickJS). Caught the `Math.min`/`max` 2-arg bug (now variadic). Out of scope: interactive `prompt` + ESM import/export of other modules. |
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
deno run -A tests/wasi_tests.ts        # 336/336 as of 2026-06-23 (+18j..18q dynrt runtime/any; +18r..18z GC track P1-P5b + polish + hybrid allocator COMPLETE: auto-grow / free-list / registry / mark / shadow-stack / collect / payloads+auto-collect (bounded memory); +54..61 async). HARDENED 2026-06-07: diffs run-ts vs run-wasm OUTPUT, not just exit codes. No open bugs; 6 tests legitimately diverge and carry `// @allow-output-diff`. A test FAILS on `output-mismatch` unless it opts out.
deno run -A tests/bindgen_tests.ts     # 119/119
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
