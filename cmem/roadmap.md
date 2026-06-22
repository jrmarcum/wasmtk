# Roadmap, phase status & vision

## Release status (2026-06-22)

**Version 1.8.0 is PUBLISHED to JSR** (`@jrmarcum/wasmtk@1.8.0` is `latest`). This is the release that
ships the **full v1 `async`/Promise surface** for the `wasic` compiler (#13 track, sub-phases
13.1a–13.5; design + log in [async-design.md](async-design.md), user-facing notes in `CHANGELOG.md`):
`async`/`await`, `Promise.resolve`/`reject`, `.then`/`.catch`/`.finally`, `Promise.all`/`allSettled`,
plus the `hybrid` async lift — all standalone, no embedded JS runtime. At the 1.8.0 tag the suite is
**317/317** (8 async tests `54_*`–`61_*`), bindgen 104/104, jstyper 73/73. (The async track was
committed post-1.7.0 and is now released as 1.8.0; what was previously "NOT yet published" is shipped.)

The **JSR package score is 100%** (`total: 18`), carried forward from v1.7.0. The two gaps that had
dropped it to 94 were fixed at 1.7.0 and remain fixed:
- **`hasProvenance: true`** — provenance now works. It had been silently `false` across v1.6.2–v1.6.5
  even though every Action run succeeded; the committed `publish.yml` was always provenance-correct
  (`id-token: write` + clean `deno publish` + `v*` tag trigger, byte-identical at the tags), so the
  cause was environmental (org/enterprise Actions OIDC policy gating the id-token), not the YAML. A
  diagnostic step ("Check OIDC availability") was added before `deno publish` to surface a missing
  OIDC token in the run log; the 1.7.0 run published with provenance.
- **Docs: `percentageDocumentedSymbols` 0.79 → 0.97** (≥0.80 threshold cleared). Commit `e64595f`
  added JSDoc to the 57 `missing-jsdoc` symbols across 9 files, exported the 3 producer result types
  (`GoResult`/`ZigResult`/`RustResult`) to clear 5 `private-type-ref` errors, and gave `DATA_BASE` an
  explicit type. `deno doc --lint` is now clean across all 15 entrypoints — keep it clean on future
  edits to hold the score.

Prior release **v1.7.0** (2026-06-15, suite 309/309) shipped `Number.parseInt`/`parseFloat`,
declaration-order-independent multi-level interface inheritance, and the Canonical ABI return-side
forward-alignment (callee-allocated string returns + `cabi_post_<name>`). Release mechanism unchanged:
`deno task publish` (sync-version → commit → tag `vX.Y.Z` → push → `publish.yml` Action runs
`deno publish` with provenance).

## Compiler phase status

All **50 phases complete** plus sub-phases 5e/5f/5g/5h/6d/12b/13b. Full per-phase implementation
detail lives in `README.md` ("Completed Phases") and the legacy `CLAUDE.md`. Summary of milestones:

- Core language (functions, control flow, types, operators, enums, templates).
- Closures: first-class fns (5e), heap closures/factories (5f), named fn-type aliases (5g),
  shared mutable captures with heap-boxing (5h).
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

| Stage | Scope | Status |
| --- | --- | --- |
| 0 | Canonical ABI **calling-convention alignment** — `cabi_realloc` export, (ptr,len) string params, and (2026-06-15) **canonical callee-allocated string returns + `cabi_post_<name>`**. Only the container is deferred (P1 core + sidecar WIT, not an embedded component). See [polyglot-producers.md](polyglot-producers.md) / [architecture.md](architecture.md) | ✅ 2026-05-19; return-side forward-aligned 2026-06-15 |
| 0.5 | Dual JSR `/compat` backend migration (wabt-ts + binaryen-ts) | ✅ |
| 0.6 | Allocator unification in wasmmerge (shared heap across merged libs) | ✅ 2026-05-30 |
| 0.7 | Tier-1 stdlib capability libs (Set/Map/Date/JSON/RegExp) | ✅ 2026-05-30/31 — see capabilities.md |

## stdlib-bundling brief — remaining work items (§7)

| # | Item | Status |
| --- | --- | --- |
| 1 | Confirm wasmmerge malloc/heap handling | ✅ |
| 2 | Implement allocator-unification pass | ✅ |
| 3 | Author Tier-1 caps (Set, Map, Date, JSON, RegExp) | ✅ **all 5 done** |
| 4 | Wire capability selection (feature-level tree-shake — bundle only referenced caps) | ✅ 2026-06-02 — embedded caps + virtual `wasmtk:<cap>` import, auto-merge only referenced |
| 5 | Promise/async: microtask runtime; lift `hybrid` async exclusion | ✅ COMPLETE 2026-06-15 — #13 13.1a–13.5 (eager microtask runtime, not state-machine; suite 317/317) |
| 6 | Evolve `hybrid` from `// @wasm` annotations → TS-type-driven routing | ✅ 2026-06-02 — `--auto` mode routes fully-typed fns to wasic, dynamic to host |
| 7 | Decide the §6 kernel scope question (drop `javyc` vs ship own dynamic runtime) | ✅ DECIDED 2026-06-02 — **build wasmtk's own dynamic runtime** (see below) |

**§7-#7 decision (2026-06-02, project owner):** wasmtk will **ship its own dynamic-runtime module**
to cover the irreducible kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation)
rather than declaring it out of scope or relying on `javyc` long-term. This is a **major new track**
on the order of #5 async — a small boxed-value + property-map + interpreter runtime — and is NOT
implemented yet; `javyc` (QuickJS) remains the interim dynamic fallback until the own-runtime lands.
`hybrid --auto` (#6) currently routes dynamic-shaped functions to `javyc`; that target will migrate
to the own-runtime once it exists.

**#5 Promise/async is COMPLETE** (2026-06-15 — #13 13.1a–13.5; eager microtask runtime + `hybrid`
lift; suite 317/317). The remaining large track is the **own dynamic runtime** (#7 decision) — gated
behind Phase 51 language hardening (now done), so unblocked.

## Prioritized execution order (set 2026-06-03)

**Principle (project owner, 2026-06-03):** the never-scheduled language-completeness gaps take
**precedence over the big tracks**, because #5 async and the own dynamic runtime *lower onto* the
existing codegen (struct layout, field access, type inference, narrowing, tag dispatch). Completing
the foundational gaps first — with cheap, standalone repros — hardens exactly those paths so a later
bug is debugged once, not while also debugging a state-machine/interpreter transform. Ordered
foundation-depth first, then by effort (quick wins first). Each item ships with its own regression
test. (The **ecosystem loader** track is the exception — it consumes the compiled `.wasm`/`.wit`/ABI,
not TS syntax, so it is orthogonal and ungated.)

### Phase 51 — Language hardening (GATES #5 async + own-runtime) — ✅ COMPLETE 2026-06-07

All four items done: 51.1 `instanceof`, 51.2 object spread, 51.3 destructuring (param + nested object +
nested tuple), 51.4 utility types. The async (#13) and own-runtime (#14) tracks are now unblocked.

1. **`instanceof`** — ✅ **DONE 2026-06-05** (class tags). Runtime tag check when the module has
   inheritance (`tag(obj) ∈ {target + all subclasses}` via `findSubclasses`, read from offset 0);
   compile-time const from the var's tracked class when there is no inheritance (no tag header).
   `if (x instanceof Sub)` narrows x to Sub in the then-branch (reuses the Phase-34 narrow machinery
   in `emitBlock`); `console.log(x instanceof C)` works via a `setInstanceofResolver` bridge in
   `console_log.ts`. Tests `51_BasicInstanceof`/`51_InstanceofNarrowing`/`51_InstanceofNoInheritance`/
   `51_Phase51Combined` (suite 279→283). DU-tag `instanceof` not added — TS DUs aren't classes, so
   `instanceof` doesn't apply; class hierarchies are the real use. Two PRE-EXISTING construction
   gaps were surfaced AND **fixed 2026-06-05** (tests `51_ModuleLevelClassInstance` +
   `51_ClassInstanceArrayLiteral`, suite 283→285): (a) module-level class instances are now tracked
   in `classVars` (new `newClassPre` in the startBodyLines pre-scan) so field access / method
   dispatch / instanceof work at module scope; (b) `const a: C[] = [new C(…), …]` is desugared to
   `const a: C[] = []; a.push(new C(…));…` (new `expandClassInstanceArrayLiterals` source pre-pass)
   so each element is constructed with its ctor + class tag. See compiler-bugs.md / design-decisions.md.
   A third gap surfaced here — single-PHYSICAL-line class/constructor bodies, e.g.
   `class C { v: i32; constructor(x: i32) { this.v = x; } }` all on one line — was ALSO **fixed
   2026-06-05** (test `51_SingleLineClassBody`, suite 285→286): `parseClasses` now splits class members
   with a depth/string-aware `splitClassMemberLines` (so fields sharing a line with methods are parsed)
   and splits single-physical-line method bodies via `splitStmts`.
2. **Object spread** `{...base, k: v}` — ✅ **DONE 2026-06-07** (test `51_ObjectSpread`, suite
   287→288). `const r: T = { ...src, k: v }` builds the struct at runtime: copies every target field
   from `src` by name (using the base's own offset/type; string fields copy both ptr+len words), then
   applies the named/shorthand overrides; unset fields stay zero. New `parseStructLiteralWithSpread`
   helper + `resolveStructBase`/`emitSpreadStructLiteral` in `src/wasic.ts`; `emitRuntimeStructLiteral`
   delegates when a spread is present (non-spread path unchanged). Both struct-let pre-scans (function +
   module) flag the var in `structSpreadVars` and register it with **ptr=-1** ("pointer lives in the
   local," so every field-read site reads via `local.get`); a `structSpreadMatch` emit branch (before
   the static struct-let handler) owns the assignment. Works for literal/runtime-var overrides, pure
   copy, mixed i32/f64 fields, function-local + module-level, and chained spread (spread of a spread).
   Known limits: single-physical-line literals only; string-field *overrides* still store ptr-only
   (pre-existing `emitRuntimeStructLiteral` limitation — copies are fine); spread in `return {...}` /
   call-arg position not wired (struct-let + array `push` contexts are).
3. **Destructuring in function params** `f({x, y}: Vec2)` — ✅ **DONE 2026-06-07** (test
   `51_ParamDestructuring`, suite 288→289). Source pre-pass `expandParamDestructuring()` rewrites a
   destructuring param `{ x, y }: Vec2` / `[a, b]: [i32,i32]` to a synthetic struct/tuple param
   `__pd_N: Type` and injects `const { x, y } = __pd_N;` / `const [a, b] = __pd_N;` at the top of the
   body — reusing the existing struct-param + `const {…}=obj` / `const […]=tup` machinery (no new emit
   path). Runs before `parseFunctions`. Also fixed `parseParams`' comma-split to be **bracket/brace-aware**
   (was paren-only, so a tuple-type param `[i32, i32]` split at the inner comma). Covers object params
   (incl. renamed `{a: lo}`), tuple params, destructured-alongside-normal params, struct-var args, and
   multiple destructured params. Known limits: named `function NAME(...)` declarations only (arrow/method
   params are a follow-up); inline tuple-literal *args* (`f([1,2])`) remain a separate pre-existing gap
   (pass a tuple var; struct-literal args work). **Nested destructuring** `const { a: { b }, c } = obj`
   — ✅ **DONE 2026-06-07** (test `51_NestedDestructuring`, suite 289→290). The object-destructure
   emit handler + pre-scan were rewritten from the `\{([^}]+)\}` regex to **balanced-brace detection +
   recursive helpers** (`emitDestructurePattern` / `collectDestructureLocals`): a binding whose value is
   itself a `{…}`/`[…]` pattern recurses into the nested struct/tuple field (pointer fields load the
   stored ptr; inline-tuple fields use the field address) — no temps, nested loads inline. Arbitrary
   depth + renames + Phase-48 zero-default fallback all work, incl. nested destructuring in a param
   (`f({a:{b}}: T)`, via the param pre-pass). **Nested tuple/array `const [[a, b], c] = t` — ✅ DONE
   2026-06-07** (test `51_NestedTuple`, suite 290→291). Made the tuple infra bracket-aware end-to-end:
   `tupleTypeName`/`makeTupleStructDef` now split bracket-aware and **embed a nested tuple element
   inline** (`tupleTypeName` field, natural-aligned, size = nested totalSize); tuple-literal construction
   (`const t: [[i32,i32],i32] = [[1,2],3]`) recurses via `emitTupleLiteralStores` (stores sub-elements at
   `baseOffset+field.offset`); tuple destructuring routes through the same recursive
   `emitDestructurePattern` as objects (balanced-bracket detection). Works for mixed f64/i32, nested tuple
   **params** (`f([[a,b],c]: [[i32,i32],i32])`), and preserves positional gaps. **Phase 51.3 COMPLETE.**
   **Process note:** the test runner judges by per-step **exit code, not output diff** — a broad codegen
   change can silently alter output while still "passing". Always output-verify (ts-run vs wasm-run) the
   tests your change touches; a gap-collapse bug here (`splitBraceAwareCommas` drops empty elements →
   `[a, , c]` read the wrong index) passed the suite but was caught by output-diffing `21_*`. Fixed with
   `splitBraceAwareCommasKeepEmpty`.
4. **Utility types** — ✅ **DONE 2026-06-07** (test `51_UtilityTypes`, suite 291→292). First batch
   shipped: **`Partial`/`Readonly`/`Required`/`NonNullable`** are pass-through (resolve to the inner
   type — all layout-identical in wasic's fixed-struct world; `NonNullable` also strips `| null`),
   done by `expandUtilityTypes()` (source text transform with balanced `<…>` extraction, BEFORE
   parseStructs, loops for nesting like `Partial<Readonly<T>>`). **`Pick`/`Omit`/`Record`** synthesize
   struct types via `expandStructUtilityTypes()` (AFTER parseStructs, needs the base def): `Pick`/`Omit`
   copy the base fields (subset / complement) PRESERVING offsets + totalSize so a base-typed value is
   layout-compatible; `Record<"a"|"b", V>` builds a fresh struct keyed by the literal-union (open-key
   `Record<string,V>` is a dynamic map → left unresolved). Both `type Alias = Pick<…>` (registered under
   the alias, decl stripped) and inline use sites (synth `Pick_T_K` name — MUST start uppercase so
   `[A-Z]\w*` struct-type detection fires) work. **Deferred (the "then" batch):**
   `Exclude`/`Extract`/`ReturnType`/`Parameters` (union/function-type ops, niche in wasic). **Bonus fix
   found via output-verification:** `console.log("x:", a.i + b.i)` on i32 **struct fields** (and 3-term
   `a+b+c` of i32 locals) emitted `f64.add` of i32 loads → compile error; fixed in `console_log.ts` by
   inferring the binary-op operand type from the LHS's **leading atom** (var / `var.field` via
   `structLookup` / `.length`), conservatively skipping `arr[i]`/`fn()`/`a.b.c` so f64 elements aren't
   mis-typed. Purely additive (no existing test could use the pattern — it didn't compile — so zero
   tracked-`.wat` changes). NOTE: a SEPARATE pre-existing bug remains — `console.log("x:", arr[i] + arr[j])`
   (array-element arithmetic) returns only the first element; out of scope here.

### Pre-Phase-52 correctness cleanup — 14 output-mismatch bugs (ALL FIXED 2026-06-08)

A pre-Phase-52 code audit + **test-runner hardening** (now diffs run-ts vs run-wasm OUTPUT, not just
exit codes — see testing.md / compiler-bugs.md "Runner-hardening audit") revealed **31** tests that
were green-but-wrong. **12 fixed** in that pass (two string-literal-masking scanner bugs), **5**
allowlisted as legitimate divergences, and the remaining **14 were ALL FIXED 2026-06-08** (clusters:
exceptions/error string payloads, string ops/formatting, struct-field mutation, for…of, class-array
literal — full root-cause list in compiler-bugs.md). A follow-up hazard audit (2026-06-08) fixed 4
more latent issues: brace-less single-line `for…of` (dropped body), `console.error` bool-array-method
formatting, the class-instance `ptr<0` sentinel, and extended the greedy-regex `parenDepthNeverNegative`
guards. Suite under the hardened runner: **299/299** (no open bugs), bindgen 103/103, jstyper 73/73.

### Phase 52 — Leaf conveniences (NO downstream risk) — ✅ COMPLETE 2026-06-11

All five shipped (suite 299→305, all output-verified ts-run == wasm-run; bindgen 103/103,
jstyper 73/73). Tests `52_VoidExpr` / `52_ChainedAssignment` / `52_InOperator` / `52_ArrayFromOf` /
`52_StringFromCodePoint` / `52_Phase52Combined`. All in `src/wasic.ts` unless noted.

5. **`void expr;`** → evaluate for side effects, discard. Statement handler at the top of
   `emitStatement`: a void/string-returning call is re-emitted as a plain call statement (the call
   still runs; a string result has no single droppable value); a numeric result is `(drop …)`; a
   non-call expr is `(drop (emitExpr …))`.
6. **Chained assignment `a = b = c = 0`** — `emitStatement` detects ≥2 top-level plain `=` (skipping
   `==`/`===`/`=>`/`!=`/`<=`/`>=`/compound), requires every target to be a bare identifier, then lowers
   to `c = 0; b = c; a = b` (rightmost first) reusing the normal assignment emitter (handles
   locals/globals/strings/types for free). Declaration-form chains (`let a = b = 0`) intentionally bail.
7. **`"field" in obj`** — closed-world compile-time `1`/`0` in `emitExpr` (via `findDepth0Keyword(" in ")`
   + new `structHasField` resolving struct/class fields from `structVars`/`classVars`). Returns null →
   falls through when the type/key is unknown. Print direct in `console.log` not wired (route via a
   `boolean` local or an `if` condition — both go through `emitExpr`).
8. **`Array.from([…])` / `Array.of(…)`** — source pre-pass `expandArrayFromOf` (string-aware balanced
   scan, runs right after the `Array.from({length})` 2D sentinel) rewrites them to plain array literals
   (`[…]`); recurses so nested forms expand. `Array.from` of anything other than a literal array is left
   untouched. **`Array.isArray(x)`** — `emitExpr` closed-world const: `1` iff x ∈
   arrayVars/moduleArrayVars/typedArrayVars, else `0`.
9. **`String.fromCodePoint(...)`** — UTF-8 encodes code point(s). Constant args → static data string
   (`allocStringDecoded`, no unescape; via new `constCodePoint` validator covering decimal/hex in the
   valid Unicode range). Single runtime arg → new `$__str_from_codepoint` WAT helper (1–4 byte UTF-8,
   multi-value ptr,len). Wired into `emitStringAssign`, the concat path, `isStringExpr`, and the two
   `$__str_op` prologue temp-pair detectors. Bonus: console_log.ts `dotLenMatch` now handles string
   `.length` (UTF-8 byte length) for local strings / module string consts / string globals — a
   pre-existing gap that also affected `fromCharCode` strings. NOTE multi-byte: wasic `.length` is
   UTF-8 byte count, TS `.length` is UTF-16 units (the test only `.length`-checks ASCII).

### Phase 53 — Standalone built-ins — ✅ COMPLETE 2026-06-15

10. **`Number.parseInt(s, radix)` / `Number.parseFloat(s)` (+ bare `parseInt`/`parseFloat`)** — ✅ DONE.
    Two self-contained WAT helpers (`$__parse_int` / `$__parse_float`) take a string `(ptr,len)` →
    f64 with JS semantics: skip leading whitespace + optional sign, stop at the first invalid char,
    `nan` on no leading digits. `parseInt` honors radix (default 10; `0x` prefix auto-detected when
    radix is 16 or omitted); `parseFloat` reads sign/integer/fraction/`e`-exponent. `emitExpr` handler
    after the Phase-48 `Number.*` block; `inferInitType` maps the call to f64. Direct
    `console.log(parseInt(...))` routes via a local (assign-then-log), matching the Phase-52
    `in`-operator precedent. Test `53_NumberParse`.
11. **Multi-level interface inheritance (>2 deep)** — ✅ DONE. Root cause was NOT offset math but
    declaration ORDER: `parseStructs` built interfaces in a single source-order pass, so a forward
    `extends` reference (derived declared before its base) silently dropped inherited fields. Refactor:
    collect all interface/object-type decls first, then build in dependency order to a fixpoint (new
    `buildStructDef` helper); in-order chains of any depth already worked. Test `53_InterfaceInheritance`.

### Big tracks (the "last items")

12. **Ecosystem — `universalWasmLoader` (polyglot loaders)** — **substantially DONE; updated
    2026-06-22; full detail + publishing matrix in [vision.md](vision.md).** Repos live under
    `D:\Programs\_ProgramExamples\Example_Programs\GithubProjects\universalWasmLoader\` (each its own
    git repo, on `main`, with its own portable `cmem/`). **`SPEC.md` is at 3.0.0** (canonical
    callee-allocated string returns + `cabi_post_<name>`). **ALL TEN ports are implemented on SPEC
    3.0.0 — NO stubs remain (updated 2026-06-22):** `-js` (reference — **PUBLISHED
    `@jrmarcum/universal-wasm-loader@1.0.8`, JSR score 100, provenance true**), `-v` (vlang — **PUBLISHED
    to VPM**), `-zig` (**PUBLISHED to zigistry**), `-py` (**PUBLISHED to PyPI**; string tests pass),
    `-rs` (`cargo test` 24/24), `-jvm` (`gradlew test` 24/24), `-dart` (web-first `dart:js_interop`;
    `dart test -p chrome` 7/7), `-c` (header + vcpkg `ports/` + tests), `-go` (wazero, 7/7; commit
    `c7d9bb0`), `-dotnet` (Wasmtime, 7/7; commit `98dcf2f`). **PUBLISHED so far = 4** (`-js`, `-v`,
    `-zig`, `-py`). **The remaining #12 gap is PUBLISHING the other 6:** `-rs`→crates.io (awaiting
    `CARGO_REGISTRY_TOKEN`), `-go`→pkg.go.dev (needs a `vX.Y.Z` tag), `-dart`→pub.dev, `-dotnet`→NuGet,
    `-jvm`→Maven Central (local tags `v0.1.0`–`v0.1.2` exist but it is NOT live yet — pending
    `io.github.jrmarcum` namespace verification + GPG/Sonatype secrets), `-c`→vcpkg port. Each of
    `-rs`/`-py`/`-jvm`/`-dart` already has **`run:`-only publish CI
    + a bump mechanism** (pending owner registry secrets — see vision.md matrix). **Runtime + WASI
    strategy decided 2026-06-15** (in vision.md → "Loader runtime + WASI strategy"): native ports use
    **wasmtime** (`-go` was decided as wasmtime-go but **shipped on wazero**; Zig/`-c` = wasmtime C API;
    `-dotnet` = Wasmtime NuGet) with built-in WASI; web ports (`-js`, `-dart`-web) host `WebAssembly` +
    hand-rolled shim; `-jvm` keeps Chicory + `chicory-wasi`; `-dart` dual-backend (web now / native
    `dart:ffi`→wasmtime later). **SPEC §10 loader
    capabilities (`_initialize` call + minimal WASI-P1 shim) IMPLEMENTED in `-js` 2026-06-15** (suite
    24→26; lets I/O-using `modc`
    libraries load in a host with no native WASI) — propagation to `-rs`/`-py`/`-jvm`/`-dart` pending.
    Orthogonal / ungated.
    **CI note:** these repos' org allows only `jrmarcum`-owned Actions → publish workflows MUST be
    `run:`-only (third-party `uses:` → `startup_failure`).
13. **#5 Promise/async — ✅ COMPLETE 2026-06-15 (13.1a–13.5; suite 317/317).** Eager microtask runtime
    + `hybrid` async lift; Approach B (state-machine) is a future option, not needed for v1.
    **Design doc + full implementation log → [async-design.md](async-design.md)** — Approach A
    (microtask-drain) for v1, expand
    to B later; settled value laid out as Canonical ABI `result<T,E>` (max forward-compat) + opaque
    handle; runtime = **inline WAT helpers** (`needsPromiseRuntime`), NOT a merged capability (the
    `wasmmerge` `call_indirect` guard forbids a callback-bearing merged module) — locked "never
    introspects callbacks" invariant keeps B drop-in; warn-on-unhandled-rejection; mode-scoped
    deadlock trap. v1 scope = async/await +
    resolve/reject + then/catch/finally + all/allSettled, standalone WASI; 5 sub-phases (13.1–13.5).
    **Sub-phases 13.1a + 13.2 + 13.3a + 13.3b + 13.1b + 13.4 (all + allSettled) + 13.5 IMPLEMENTED
    2026-06-15** (suite 309→**317**, output-verified, zero regressions; the entire #13 async track is
    COMPLETE): 13.1a = `async`/`await` + `Promise.resolve`,
    async-fn-returns-promise (i32/f64), inline runtime, canonical `result<T,E>` (test `54_AsyncBasic`);
    13.2 = `.then(namedCb)` + microtask queue (FIFO linked list) + drain, per-call-site `call_indirect`
    trampolines, correct ordering/FIFO/chained/f64/`await`-of-`.then` (test `55_AsyncThen`); 13.3a =
    `Promise.reject` + rejection→exception (rejected `await` re-throws, caught by `try/catch`) +
    async-body-throw caught free via the eager model (test `56_AsyncReject`); 13.3b = `.catch`/`.finally`
    rejection reactions + `.then(onF,onR)` via a **dual-path** trampoline (`genReactionTrampoline` reads
    `src.disc`: fulfilled→passthrough/`onF`, rejected→`onR(reason:string)`/propagate; `.finally` runs on
    both paths) (test `57_AsyncCatch`); 13.1b = promise-holding-var inner-type tracking (`const p = f();
    await p`/`p.then`, i32+f64+aliasing — test `58_AsyncPromiseVar`) + **capturing-closure callbacks** for
    `.then`/`.finally` via an **env-bearing reaction record** (functype migrated to `(env,src,result)`;
    closure dispatched by `call_indirect` through the closure ptr — test `59_AsyncClosureCb`); 13.4 =
    **`Promise.all` + `Promise.allSettled`** (array-literal arg, i32/f64) via per-call-site combinators
    (`all` drains+builds `T[]`/first-rejection-wins — test `60_AsyncAll`; `allSettled` never rejects,
    builds a synth-`__settled_<T>` struct array of `{status,value,reason}` — test `61_AsyncAllSettled`);
    13.5 = **lift the `hybrid` async exclusion** (`src/hybrid.ts`) — route async fns into the wasic core
    via an internal `f__impl` + a sync unwrapping wrapper `f` (`return await f__impl`), validated by
    `tests/hybrid_fixtures/async_hybrid.ts`. **#13 async track is now COMPLETE** (entire v1 Promise API
    surface + hybrid integration). Full detail in [async-design.md](async-design.md).
14. **Own dynamic runtime** (§7-#7) — boxed values + property map + interpreter for the irreducible
    kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation). Gated behind Phase 51
    (done) → unblocked. `javyc` (QuickJS) is the interim fallback until it lands. **Design + full log
    → [dynrt-design.md](dynrt-design.md).** Locked architecture (owner 2026-06-22): value+object model
    first; **tagged heap cell (i32 handle)**; authored in the **wasic TS subset now** (zero
    duplication — reuses wasic's allocator/strings/arrays/num-fmt), extract a shared `rtcore` + go
    hand-WAT only at the interpreter increment; **runtime-only first** (no wasic `any` yet).
    **Increment 1 — value + object model — SHIPPED 2026-06-22** as a shared-heap `modc` capability
    (`tests/wasm_wasi_bundle/dynrt_bundle/` + pipeline test `18j`): boxed value = 4-slot `Int32Array`
    node `[tag,a,b,c]` (undefined/null/bool/number-as-f64/string/array/object), self-managed
    `Int32Array` growable lists for containers, ~23 exports incl. `dynTypeof`/`dynStrictEq`
    (`===`)/`dynAdd` (`+`). Surfaced 3 wasic gaps (worked around in the lib, logged in
    compiler-bugs.md): str-concat-of-two-calls, Float64Array-elem comparison mis-infers i32, and
    **empty-`[]` is a shared static cap-0 array whose cap-0 grow is broken** (the latter hardens any
    future reconstruct-then-`push`). **Increment 1b — virtual `wasmtk:dynrt` import + tree-shake —
    SHIPPED 2026-06-22** (embedded in `src/wasm/caps_bytes.ts` as a 6th registry entry via
    `gen_caps_bytes.ts`; the `tsbundler` resolver is generic so no resolver change; no `modc` step;
    pipeline test `18k`). **Increment 2a — `eval` of a pure expression language — SHIPPED 2026-06-22**
    (test `18l`): a recursive-descent direct-eval parser authored in the subset (authoring decision
    resolved — continue in the subset, no `rtcore`/hand-WAT needed yet); full operator precedence +
    parens + unary + ternary + string concat → boxed value; added the dynamic operators
    `dynSub/Mul/Div/Mod/Neg/Not/Lt/Gt/Le/Ge`; `parseFloat` works in modc; NO new compiler gaps.
    **Increment 2b — variables + environment + member/index access — SHIPPED 2026-06-22** (test `18m`):
    `dynEvalEnv(s, env)` resolves bare identifiers against an env object; postfix `.prop`/`["key"]`/
    `[i]` (computed index) + `.length`; TOTAL/guarded member access (`undefined.x` → undefined, no
    trap); robust identifier tokenisation; no new compiler gaps. **Scope split (rationale recorded):**
    calls + REAL short-circuit moved to 2c — short-circuit is only observable/testable with
    side-effecting operands (calls), and guarded member access makes 2b trap-safe without it.
    **Increment 2c — function values (tag 7) + calls + REAL short-circuit — SHIPPED 2026-06-22** (test
    `18n`): function values dispatch via a STATIC switch on a built-in id (NOT a function table —
    wasmmerge forbids `call_indirect` in a merged module), `dynStdEnv()` ships abs/sqrt/floor/ceil/
    round/min/max/len + the side-effecting `inc`; `dynApply` dispatcher; calls in `parsePostfix`
    (`f(args)`, any arity, nested); real short-circuit via an `evalLive` skip-parse flag guarding the
    call dispatch (the only side-effecting op), proven observable via the `inc()` counter. Surfaced 1
    wasic gap (i32 global / typed-array element as an f64 call-arg skips the `f64.convert` — bind to a
    local; logged in compiler-bugs.md). **Increment 2d.1 — statements + control flow (`dynRun`) —
    SHIPPED 2026-06-22** (test `18o`): a statement interpreter over the expression evaluator —
    let/const/var + bare-identifier assignment (mutate the env via `dynSet`), if/else, while, `{ }`
    blocks, expression statements, return; control flow uses the DIRECT-eval re-parse trick (while
    re-sets the cursor to the condition start each iteration; dead branches reuse the 2c `evalLive`
    skip-parse) so no AST is needed; ran factorial / fibonacci(10)=55 / nested loops / early return /
    builtin calls in statements. **Authoring decision held — STILL in the subset (no wall → no
    `rtcore`/hand-WAT needed); NO new compiler gaps.** **Increment 2d.2 — user-defined functions +
    `new Function` — SHIPPED 2026-06-22 (COMPLETES interpreter increment 2)** (test `18p`): user
    function values (5-slot cell = body + params + defining env), in-source `function name(params){…}`
    declarations (body source captured by a brace scan) + `dynMakeFunc(params, bodyStr, env)` (the
    `new Function` = runtime-code-from-strings capability); a call runs the body via `dynRun` in a
    fresh scope whose parent is the defining env, so RECURSION + closures work via an `envLookup` scope
    chain; the hard part — parser reentrancy — is handled by saving/restoring the shared parser
    globals around the nested `dynRun`. Still authored in the subset (the `rtcore`/hand-WAT path was
    never forced). Known limitation: deep recursion is heap-bound (bump allocator, no GC — `fib(10)`
    overflows ~2 pages; `fib(8)` used). **#14 interpreter (2a–2d.2) DONE — the §6 `eval`/`new Function`
    kernel is covered, entirely in the wasic subset.** **Increment 3 STARTED (first wasic-COMPILER
    change of the track): 3.1 — wasic `any` type + auto-merge — SHIPPED 2026-06-22** (test `18q`):
    `mapType("any")→i32` (boxed handle; no test used `any` so safe); the bundler auto-injects a
    synthetic `wasmtk:dynrt` import on `any`/`eval` usage (reuses the virtual-cap merge; `any`-free
    programs unaffected); implicit boxing of literal `: any =` initialisers (source pre-pass) +
    `as`-unboxing via an `anyVars` side-set; new dynrt export `dynStrBytes`. Wiring lesson: the bundler
    rewrites explicit `dynX`→`dynrt_dynX`, so compiler-INTRODUCED calls must be pre-prefixed `dynrt_`.
    **3.2 — operators on `any` — SHIPPED 2026-06-22** (test `18q`): a guarded block in `emitExpr`'s
    binary-op loop routes to dynrt ONLY when an operand is a simple `any` var (else the existing typed
    paths run untouched — the safety invariant for the hottest path); `boxAnyOperand` helper boxes the
    other operand; arithmetic `+ - * / %` → `dynrt_dynAdd/…` (an `any` handle), comparisons → raw i32
    0/1 (work in conditions), `&&`/`||` → truthiness short-circuit, string concat dispatches via
    `dynAdd`. Full suite stayed green (zero impact on non-`any` code). **3.3 — member/index/call on
    `any` + bare `eval` — SHIPPED 2026-06-22** (test `18q`): a guarded any-dispatch block in `emitExpr`
    routes `x.foo`→`dynrt_dynMember`, `x[i]`→`dynrt_dynIndexValue`, `x(args)`→`dynrt_dynCall0/1/2/3`
    (the library now EXPORTS `dynMember`/`dynIndexValue` + new fixed-arity `dynCall0-3` helpers — wasic
    can't build an args array inline); bare `eval(...)` rewritten to `dynrt_dynEval`. All results are
    `any` handles; single-level forms (chained `x.a.b`/`x.a()` use an intermediate var). **Remaining
    for #14:** 3.4 hybrid `--auto` migration (route dynamic-shaped fns to dynrt, host fallback); + an
    optional memory pass to lift the heap-bound-recursion limit.

**Gating summary:** 51 → (13, 14). 52 + 53 COMPLETE; ABI forward-alignment (return side) COMPLETE
2026-06-15; **#13 async track COMPLETE + PUBLISHED as v1.8.0 (2026-06-22)** (13.1a–13.5: full v1
Promise API surface + hybrid lift; suite 317/317; README async surface documented — see lines ~197/
834/1010 of README.md and `CHANGELOG.md`); **#12 loaders substantially DONE — updated 2026-06-22**
(`-js` published; `-v` published to VPM; `-c`/`-zig`/`-py`/`-rs`/`-jvm`/`-dart` implemented on
SPEC-3.0.0; **all 10 ports now implemented — no stubs remain**; **4 published** (`-js`, `-v`, `-zig`,
`-py`), the other 6 are built-but-unpublished — see vision.md). The remaining work is **#14 own dynamic
runtime**, the deferred **P2 container** (embed component type — a wrap), and finishing **#12**
(PUBLISHING the 6 remaining built ports to their registries, SPEC §10 loader-cap propagation, and owner
registry secrets).

## Congruent polyglot-producer goal + ABI posture (added 2026-06-03 — full detail in [polyglot-producers.md](polyglot-producers.md))

**Goal:** unify the **TS/JS, Rust, Zig, Go** toolchains into one congruent wasm capability —
heterogeneous *producers* converging on the homogeneous middle/back end wasmtk already owns (WASI-P1
core-module output → bindgen ABI → binaryen-ts optimize → wasmmerge/wasmbundle link → wasmtk TS WASI
host). Adding a language = adding a producer, not a toolchain.

| Track | Scope | Status / gating |
| --- | --- | --- |
| **ABI forward-alignment (stay P1)** | Canonicalize the **in-memory boundary layout** + the **return convention** now (callee-allocated i32-ptr return + `cabi_post_<name>`; route all boundary allocs through `cabi_realloc`); keep P1 WASI imports behind a thin seam. Both P1-legal; makes future P2 a wrap, not a rewrite. | ✅ **return-side IMPLEMENTED 2026-06-15** (wasic `$fn__cabi` shim now returns the i32 ptr + emits `cabi_post_<name>`; bindgen host reads-then-posts; bindgen 104/104, `strings_50` end-to-end). In-memory layout already canonical for shipped types. Only the P2 container remains deferred. |
| **Go producer (TinyGo)** | `tinygo build` → wasm → shared optimize/host path. Library-first; stdlib `go` heavier fallback. | ✅ **v1 SHIPPED 2026-06-06, refined 2026-06-07** via `--lang=go` (path defaults to cwd): `init` (scaffold a **wasm library** by default; `--go-target=wasm` for a browser project), `modc` (**WASI reactor library** by default — `-buildmode=c-shared`: no `_start`, exports `//go:wasmexport` funcs, callable via `wasmtk mod`/bindgen; `--go-target=wasm` for a browser module + `wasm_exec.js`), `run` (build wasip1 command + run; **auto-detects** a `.go` file or a dir with `go.mod`, no flag needed). `--go-runtime=tinygo`(default)/`std`. `src/gowasic.ts`. **wasm-opt:** real `wasm-opt` → TinyGo full (incl. goroutines); else passthrough shim + `-scheduler=none` + **binaryen-ts `-Oz`** (no external binaryen; goroutine-free). **2026-06-07 changes:** `wasic --lang=go` REMOVED; `modc --lang=go` flipped browser→reactor-library (the formerly-deferred reactor/library item, now DONE — Go analog of TS `modc`); required a `_initialize` fix in `wasmtk mod`/`run` (reactor exports trap otherwise) + a `syscall/js`-in-library-build hint. Verified `modc --lang=go` lib → `wasmtk mod lib.wasm add 2 3` → 5. **Still deferred:** Go string/aggregate **bindgen** host marshalling (needs ABI forward-alignment — Go's layout ≠ Canonical ABI); a *mergeable* Go leaf (alloc-free `wasm-unknown`) is feasible but not auto-wired. Fixture: `tests/go_fixtures/hello.go` (not auto-run — needs TinyGo). |
| **asyncify pass in binaryen-ts** | Port binaryen's `--asyncify` pass into `@jrmarcum/binaryen-ts` so wasmtk can be TinyGo's `wasm-opt` for **goroutine** code too (no external binaryen at all). Today binaryen-ts has `-Oz` but NOT asyncify, so goroutine Go needs a real `wasm-opt` installed. | ⬜ **future (large)** — asyncify is one of binaryen's most complex whole-program passes (~1.5k LOC) with an exact ABI contract TinyGo depends on; do it properly upstream in binaryen-ts, not rushed. Unblocks goroutine Go on the binaryen-ts path. |
| **Zig producer** | `zig build-exe` (cleanest native path) | ✅ **SHIPPED 2026-06-07** (`src/zigwasic.ts`, `--lang=zig`): `init` (wasm-library scaffold), `modc` (freestanding library, `--export=<name>` scanned + binaryen-ts `-Oz`), `run` (`wasm32-wasi` on wasmtk's TS host; auto-detects `.zig`). Comptime-guarded scaffold `main` (Zig analyzes `main` even with `-fno-entry`). See [polyglot-producers.md](polyglot-producers.md). |
| **Rust producer** | Driver = **`rsxtk`** (owner's Rust WASM toolkit, crates.io `jrmarcum/rsxtk`). | ✅ **SHIPPED 2026-06-07** (`src/rustwasic.ts`, `--lang=rust`) — **delegates fully to rsxtk**: `init`/`initmod`/`modc`(→build wasm)/`build`(→build wasi)/`run`/`add`/`remove`/`list`/`fmt`/`clean`. Prereq `rustup target add wasm32-wasip1`. No WIT/bindgen yet (stays wasmtk's). Known rsxtk-side gap: `initmod` library + `build`/`mod` expects a `main` (rsxtk template lacks `[lib]`/crate-type — fix in rsxtk). `wasm32-wasip2` is the one native-P2 path — decide before mixing into a P1-merge flow. |
| **P2 producer (real components)** | Embed component-type section + emit/wrap via `wasm-tools component new`; migrate WASI P1→`wasi:cli`/`wasi:io`. | ⬜ **deferred** — only pays off vs. a *native component-runtime* consumer (Wasmtime/WasmEdge/WAMR/Spin); JS-runtime consumers transpile P2 back to core wasm anyway. P1-core + terminal adapter covers the goal. |

**Scope pin:** the congruent contract is **WASI Preview 1 / core modules**. Componentization is a
**terminal optional wrap** of the single merged module (`wasm-tools component new --adapt`), not a
merge-tier rewrite. wasmmerge merges P1 modules; never merge already-built *components* (use `wac`).

**Verified 2026-06-03:** wasmtk itself is NOT a P2 producer — it emits P1 core modules + sidecar
`.wit` + host-side bindgen ABI ("bucket (b)"). Canonical ABI calling convention is now aligned on
both param and return sides (`cabi_realloc` + callee-allocated returns + `cabi_post_<name>`, 2026-06-15);
only the P2 container is deferred. See [polyglot-producers.md](polyglot-producers.md)
for the raw evidence.

## "TypeScript as a DLL" vision

Compile TS business logic to `.wasm` libraries and load them from a TS host like C uses a DLL.

| C / DLL | wasic |
| --- | --- |
| `.c` → `.dll`/`.so` | `.ts` → `.wasm` via `modc` |
| `.h` header | `.wit` (Phase 41, auto-generated) |
| import lib (`.lib`) | `.bindings.ts` (Phase 50 `bindgen`) |
| `LoadLibrary`/`GetProcAddress` | `loadModule()` from the binding |

Prefer `modc` over `wasic` for consumer-facing modules. The DLL model is complete end-to-end.

## Polyglot ecosystem vision (full detail in [vision.md](vision.md))

WASM as the universal binary, WIT as the universal interface contract; any language → component;
components compose regardless of source language; pixi manages toolchains, wasmtk manages WASM.
Staged: Stage 1 `universalWasmLoader` (JS/TS reference loader + SPEC.md + InstancePool) is the
current priority; Stages 2–5 add Rust/Python/Go/JVM loaders, `wasmtk build`/`compose` via
pixi, registry + IDE integration.

## Out of scope without more WASM proposals

Goroutines/cooperative multitasking (needs stack-switching), shared memory + atomics (threads),
channels/select, `os.Exit` non-zero propagation (runner enhancement). And the irreducible dynamic
kernel — `eval`/`new Function`, pervasive `any`, open prototype mutation — stays in `javyc` unless
§7-#7 decides to build wasmtk's own dynamic runtime.

## TypeScript feature gaps compilable later (now scheduled — see "Prioritized execution order")

Utility types (`Partial`/`Record`/…), destructuring in params, `Number.parseInt`/`parseFloat`,
`in` operator, nested destructuring. As of 2026-06-03 these are no longer unscheduled — they are
sequenced into **Phases 51–53** above (foundational subset gates the async + own-runtime tracks).
Done so far: **Phase 51 COMPLETE** (`instanceof` + object spread + param/nested destructuring +
utility types) and **Phase 52 COMPLETE 2026-06-11** (`void` / chained assignment / `in` /
`Array.from`-`of`-`isArray` / `String.fromCodePoint`). A **pre-publish hardening pass (2026-06-12)**
then made the emitter's terminal "give-up" fallbacks record a diagnostic (abort) instead of silently
emitting `0`/`""` — which surfaced + FIXED a real latent bug (brace-less / single-line-braced `else`
chains after a single-line `if` were dropped; regression `15_ElseChainForms`), plus `instanceof
<built-in>` and dead-code/orphaned-module removal, then a console.log comparison fix pass
(findTopLevelOp paren-tail bug + string ===/!== operands + member-target chained assignment).
Suite **309/309**, bindgen 104/104,
jstyper 73/73. **Phase 53 COMPLETE 2026-06-15** (`Number.parseInt`/`parseFloat` + bare forms;
multi-level interface inheritance, declaration-order independent). **ABI forward-alignment
(return side) COMPLETE 2026-06-15.** **#12 loaders substantially DONE — updated 2026-06-22:** all 10
ports (`-js`/`-rs`/`-py`/`-jvm`/`-dart`/`-c`/`-zig`/`-v`/`-go`/`-dotnet`) implemented on SPEC-3.0.0,
**no stubs remain**; **4 published** (`-js`→JSR, `-v`→VPM, `-zig`→zigistry, `-py`→PyPI); the other 6
are built-but-unpublished (awaiting registry pushes/tags/secrets — e.g. `-jvm` has local tags
`v0.1.0`–`v0.1.2` but isn't live on Maven Central yet). **#13 async COMPLETE + PUBLISHED as wasmtk
v1.8.0 (2026-06-22; suite 317/317).** Remaining: #14 own runtime, the deferred P2 container, and
finishing #12 (publish the 6 remaining built ports + SPEC §10 loader capabilities + owner registry
secrets). Full analysis in CLAUDE.md § "TypeScript Feature Gap Analysis".
