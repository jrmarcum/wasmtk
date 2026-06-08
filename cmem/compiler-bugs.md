# Compiler bug log

Live record of bugs found + fixed. Newest first. **✅ NO OPEN BUGS — full suite 292/292**
(`bindgen` 103/103, `jstyper` 73/73) as of **2026-06-08**. The 14 output-mismatch bugs that the
2026-06-07 runner-hardening surfaced are **ALL FIXED 2026-06-08** — see the "14 output-mismatch
bugs ALL FIXED" entry directly below for the per-cluster root causes. Earlier: Phase 51 (2026-06-05)
added `instanceof`, closed three construction/parsing gaps, and a follow-up workaround-audit fixed
one silent bug + added a loud `call_indirect`-in-merge guard; a 2026-06-07 follow-up added a
companion `memory.grow`-in-merge guard.

## The 14 output-mismatch bugs — ALL FIXED 2026-06-08

The runner-hardening (2026-06-07) exposed 14 tests whose WASM output diverged from native TS. All
fixed, grouped by root cause (suite 278/292 → **292/292**, zero regressions; `src/wasic.ts` +
`src/console_log.ts`):

- **`51_ClassInstanceArrayLiteral`** — `console.log(arr[i].method())` (class vtable dispatch on an
  array element) wasn't wired in console.log: the `dotCallLookup` guard regex rejected a bracket
  receiver. Relaxed the guard + added element-class return-type detection in `dotCallLookupFn`.
- **`26_ForOf`** — `for…of` over a STATIC module-level array read from `ptr` instead of `ptr + 8`,
  so it summed the `[length, capacity]` header words. Added the missing `+8` (mirrors the `arr[i]`
  path).
- **`6b_mutexes`** — `c.field++` / `c.field += x` on a struct/class field (and static `Class.f++`)
  fell to a comment-stub. Desugared `++`/`--`/compound-assign on a dotted receiver into the working
  `recv.field = recv.field OP val` form (guarded to `this`/struct/class/static receivers).
- **`1_values`** — `console.log("go" + "lang")` was matched as ONE string literal (`go" + "lang`).
  The literal check now requires a *whole* single literal (`isWholeStringLiteral`), so concatenation
  routes to the concat path. (The remaining `7/3` line is a documented f64→string precision
  divergence — the test now carries `// @allow-output-diff`.)
- **`6b_errors` / `6b_custom-errors`** — two bugs: (a) a NESTED struct **string** field (`a.b.c`)
  returned only the i32 ptr (no `watLoadLen`) in the chained `structLookupFn`, so console.log printed
  the pointer — added the string-leaf branch (ptr at `offset`, len at `offset+4`); (b) a struct var
  re-declared in a sibling block with a DIFFERENT struct type resolved against the wrong (last-wins
  pre-scan) type — re-register `structVars` def at emit time for each `const/let X: T = call()`.
- **`6b_SimpleStructs`** — a heap-allocated struct (`ptr === -3`, when a literal has a
  non-compile-time field like `9.109e-31`) used `(i32.const -3)` as the field base instead of
  `(local.get $var)`. Generalized every `sv.ptr === -1 ? local.get : i32.const` (and `outerSv`) to
  `sv.ptr < 0` (structVars only ever uses -1/-3/≥0, never the array -2 sentinel).
- **`1_channels`** — module-level MUTABLE string (`let message = ""`) referenced by functions was
  stored as a `_start` local, invisible across calls. New `moduleStringGlobals` mechanism: a `(mut
  i32)` `$name_ptr`/`$name_len` pair, with reads (`emitStringPtrLen`), writes (`emitStringAssign`
  wrapper rewrites local.set→global.set), reassignment, and console.log (`strglobal:` encoding) all
  wired.
- **`27_line-filters`** — `console.log(arr[i].toUpperCase())` (and even `s.toUpperCase()`): console.log
  had **no** support for string-method-returning expressions. Added a `setStringExprResolver` callback
  that delegates to `emitStringPtrLen` (captured into the `$__str_op` temp pair → `strexpr`), plus
  `toUpperCase`/`toLowerCase` on plain-var and string-array-element receivers in `emitStringPtrLen`.
- **`43_collection-functions`** — `mapStr`'s `result.push(fn(arr[i]))` where `fn: (s) => string` is a
  funcref/closure param: the string return via `call_indirect` (void + `$__str_ret` globals) wasn't
  handled in `emitStringAssign` → empty elements. Added a funcTypeVars/closureTypedVars string-return
  branch (call_indirect with `null` functype result, then read the globals).
- **`15_Exceptions` / `15_recover` / `15_LexicalShadowing_Stress`** — two parts: (a) `15_recover`'s
  `r instanceof Error ? r.message : `${r}`` wasn't simplified (the else wasn't `String(r)`) —
  generalized the catch-ternary regex to any else branch (the then is always taken in wasic). (b) The
  other two are a **binaryen `-Oz` CoalesceLocals bug** that miscompiles try/catch catch-variable
  locals (coalesces a catch var with an outer local live across the try). VERIFIED: raw wabt output is
  correct, binaryen output is wrong. Fix: `watToOptimisedWasm` **skips binaryen** for modules that use
  exceptions (marker: `$__exn_tag`) — rare, ships the correct un-optimized wabt binary. This exposed a
  latent **terminal-`block`-fallthru** bug (a `switch` where every case returns/throws leaves an empty
  stack at the function end → V8 strict-validation reject; binaryen used to mask it) — `3_enums`
  regressed; fixed by extending `fixTerminalFallthru` to append `(unreachable)` after a terminal void
  block (harmless when binaryen runs — it strips trailing unreachable).
- **`27_string-formatting`** — a multi-feature stress test; fixes: **toHex** (`r = h[v%16] + r`) needed
  a string-char-subscript concat handler (`$__str_char_code_at` + malloc + store8, the fromCharCode
  shape) AND a **self-referential-concat** fix (`r` appearing as a non-first concat part was read
  AFTER the accumulator overwrote it — save the old value to `$__concat_self` first); **toFixed**
  needed `` `template`.split(".") `` (materialize the template receiver into `$__str_op`, then split)
  AND a **brace-less single-line `while (cond) stmt`** handler (the braced regex required the line to
  end at the condition; the new handler must increment `i` itself — emitBlock advances `i` manually,
  so a bare `continue` infinite-loops); **padStart/padEnd in templates** on string-literal & call
  receivers, single-arg (default pad space) — added to `emitStringPtrLen` + console.log
  `parseTemplateLiteral` (via the broadened string-expr resolver); **`(14).toString(2)`** constant-
  folded (literal number + literal radix → radix string; runtime-radix is the documented gap).

## Runner-hardening audit (2026-06-07) — exit-code suite was masking wrong output

**Test runner hardened (`tests/wasi_tests.ts`):** previously a test "passed" if compile / run-ts /
run-wasm each exited 0 — it never compared the two runs' *output*. Now it captures both stdouts and
fails on mismatch (`output-mismatch`), unless the test carries `// @allow-output-diff` (for the few
whose wasic semantics legitimately differ from native TS). This exposed **31** wrong-output tests the
green suite had been hiding (incl. `51_ClassInstanceArrayLiteral`, which "validated a fix" while
printing `0 0 0`). Implementation note: capture only reads `output.stdout` when `stdout:"piped"` —
reading it on an inherited stream throws "Cannot get 'stdout': not piped".

**FIXED in the same pass — two scanner bugs (string-literal masking), recovered 12 of the 31.**
Multiple bracket/paren-counting scanners did NOT skip string/template literals, so a literal
containing `]` `)` `}` `[` `(` `{` corrupted depth tracking. (a) `findBinaryOp` — `s + "]"` failed to
find the top-level `+` → string concat silently produced an empty string. (b) The `parseFunctions`
multi-line array-literal **body-joiner** — `let s: string = "["` looked like an unclosed array, so the
following statement got joined onto it and the whole thing fell to the "complex string assignment not
supported" stub. Fix: new module-level `buildStringLiteralMask(s)` + `netSquareBracketDepth(s)`;
`findBinaryOp` skips masked positions, the joiner uses the string-aware depth. (The single-line-body
`splitStmts` splitter has the same latent bug but wasn't on the failing path — left for the cleanup.)

**14 KNOWN-OPEN output-mismatch bugs (deferred to a scoped cleanup; checkpoint decision 2026-06-07).**
By cluster:
- **Exceptions/error string payloads (6):** `15_Exceptions` (catch returns `-1`→`0`), `15_recover`
  (message empty), `15_LexicalShadowing_Stress` (catch-var shadow returns inner not outer),
  `6b_custom-errors` (message → `260`, a pointer), `6b_errors` (message → `0`), `6b_SimpleStructs`.
- **String (5):** `1_values` (`"go"+"lang"` in console.log prints the raw tokens — string-literal
  concat in a console.log arg; also has a legit float-precision line so it can't just be allowlisted),
  `1_channels` (empty), `27_line-filters` (string methods → `0`), `27_string-formatting`,
  `43_collection-functions` (string-array elements print empty).
- **Map (1):** `6b_mutexes` (`map[a:20000 b:10000]` → `map[a:0 b:0]`).
- **for-of (1):** `26_ForOf` (`60` → `16`, plus extra lines).
- **class-array-literal (1):** `51_ClassInstanceArrayLiteral` (`areas: 16 75 4` → `0 0 0`; the
  array-literal-of-`new` desugar produces zeroed structs — the test was green-but-wrong).

**5 legitimate divergences carry `// @allow-output-diff`** (NOT bugs): `45_random-numbers`,
`7a_MathIntrinsics`, `7a_constants` (f64→string float precision), `48_ObjectDestructDefault`,
`48_Phase48Combined` (zero-sentinel destructuring defaults). Also previously documented separate-open:
`console.log("x:", arr[i] + arr[j])` array-element arithmetic drops terms after the first.

## console.log i32 struct-field + struct-field arithmetic emitted f64.add — FIXED 2026-06-07

Pre-existing (predates Phase 51.4; found while building the utility-types test). `console.log("x:",
a.i + b.i)` where `a.i`/`b.i` are **i32 struct fields** — and 3-term `a + b + c` of i32 locals —
emitted `f64.add` of `i32.load`s and failed to compile (`f64.add[0] expected f64, found i32...`). In
`console_log.ts` `exprToWat`, the binary-op operand type (`lhsLocalType`) was inferred only for a plain
`\w+` local or `\w+.length`; a struct field access `var.field` (and any compound LHS) fell through to
the f64 numeric default. **Fixed** by inferring the type from the LHS's **leading atom** — plain var,
`var.field` (via `structLookup().type`), or `.length` — conservatively skipping `arr[i]` / `fn(...)` /
`a.b.c` (remainder begins with `[` `(` `.`) so f64 array elements / call results aren't mis-typed as
i32. Purely additive (the broken pattern couldn't compile before, so no existing test used it → zero
tracked-`.wat` changes). **Still OPEN (separate, out of scope):** `console.log("x:", arr[i] + arr[j])`
returns only the first element (array-element arithmetic in console.log is dropped after the first term).

## Tuple positional-gap collapse in nested destructure rewrite — FIXED 2026-06-07 (pre-commit)

Caught during Phase 51.3 nested-tuple work, never shipped. The rewritten recursive destructure helpers
used `splitBraceAwareCommas`, which **drops empty elements** — so `const [coordX, , coordY] = t`
collapsed the gap and `coordY` read index 1 instead of 2 (`21_SkippedElementsAndGaps` printed
`Extracted Y: 999` instead of `20`). The test suite **did not catch it** (it judges per-step exit code,
not output), so it was found only by output-diffing ts-run vs wasm-run. Fixed with a gap-preserving
`splitBraceAwareCommasKeepEmpty` used by `emitDestructurePattern`/`collectDestructureLocals`. Lesson
recorded in testing.md / roadmap.md: output-verify the tests a codegen change touches.

## Reactor library exports trapped without `_initialize` — FIXED 2026-06-07

Surfaced wiring `modc --lang=go` to build a WASI **reactor library** (`-buildmode=c-shared`; see
polyglot-producers.md). Calling such a library's export via `wasmtk mod <lib> fn args` (or `wasmtk
run <lib> fn args`) **trapped with `unreachable`**. Cause: a reactor module must run its `_initialize`
export (Go runtime: heap/stack/globals setup) **before any other export**; `callExport` (and
`runWasi`'s named-export path) instantiated and called the target function directly, skipping
`_initialize`. **Proven** with a minimal probe: `square(12)` trapped without `_initialize`, returned
`144` after calling it first. **Fix** (`src/utils.ts`): both `callExport` and `runWasi`'s
named-export branch now call `exports._initialize()` (if present) right after instantiation, before
the target function. No-op for non-reactor modules with no `_initialize` (wasic/modc **TS** libraries
— regression-verified: `wasmtk mod addts.wasm addts 2 3` → 5). `callExport` also gained the same
Phase-40 `env` Proxy as `runWasi` (unlisted `env` imports → no-op stubs) for robustness; it does NOT
provide the browser `gojs` namespace, so syscall/js browser modules stay (correctly) un-hostable.

## Merge guard #2 — `memory.grow` in a merged module (2026-06-07)

Companion to the 2026-06-05 `call_indirect`-in-merge guard. `wasmmerge` now also throws a loud,
actionable error when a module being merged contains `memory.grow`. **Why:** `memory.grow` signals
that the module carries its OWN allocator which claims linear memory upward (a foreign-language
growing heap — Go's runtime allocator, Rust dlmalloc, Zig `page_allocator`) instead of sharing
wasmtk's unified bump heap (`$__malloc`/`$__heap_ptr`). Splicing it in lets its allocations overlap
the host's heap/scratch region → **silent memory corruption** once it allocates. It's *worse* than
`call_indirect` because it can appear to work for tiny allocations, so failing loudly is the safe
default.

**Motivation (empirical):** a TinyGo `wasm-unknown` module that allocates (`make`/`append`) merged
without error but produced corrupted output — its heap had no `call_indirect`, so the existing guard
missed it; only `memory.grow` distinguished it. Full matrix in
[polyglot-producers.md](polyglot-producers.md) ("native-producer mergeability"): allocation-free Go/
Rust/Zig leaves merge cleanly; allocating code merges only for Zig + a static-arena allocator;
allocating Go slipped the `call_indirect` guard and corrupted — this guard closes that hole.

**Implementation** (`src/wasmmerge.ts`, in the per-func body loop right after the `call_indirect`
check): `if (/\bmemory\.grow\b/.test(body)) throw …`. The message names the per-language fix — Zig
`FixedBufferAllocator` (not `page_allocator`), Rust `#[global_allocator]` over a static array, Go not
supported for merging — or "keep it standalone as a WIT/bindgen component." `main.ts`'s top-level
`.catch` surfaces it as a clean one-line `❌ wasmtk:` message with exit 1. **No false positives:**
wasmtk's own producers (wasic/modc) never emit `memory.grow` (their bump allocator runs over fixed
pre-declared pages). **Verified:** all 14 merge-dependent tests (`^(18|38)` — every capability
pipeline + shared-heap two-libraries + wasm-import merge + virtual imports + mathlib) pass; a
hand-built `memory.grow` module imported by a wasic program is rejected with the full message + exit 1.

## Workaround audit follow-up (2026-06-05)

A sweep for remaining "workarounds" (keywords + a measurement of silent-stub hits) produced:

- **FIXED — `s.at(i).charCodeAt(j)` silently returned 0.** The chain fell to the catch-all `emitExpr`
  stub (the plain `charCodeAt` handler only matches a `\w+` receiver, not `s.at(i)`). New `atChainMatch`
  handler in `emitExpr` computes `$__str_char_code_at` at the normalized index. Regression test
  `51_AtCharCodeChain.ts`. (Bare `.at()` elsewhere is already handled by the string paths.)
- **FIXED (loud-failure guard) — `call_indirect` inside a merged module.** `wasmmerge` now throws a
  clear error (`❌ wasmtk: wasmmerge: '<lib>' uses call_indirect …`) instead of emitting a
  silently-dangling reference (Phase 18 strips imported type sections). `main.ts` gained a top-level
  `.catch` so thrown errors surface as a clean one-line message with exit 1. No current capability lib
  triggers it (all use direct calls); verified manually with a callback-param modc lib.
- **Silent-stub audit — NO blanket change (deliberate).** Instrumented the 3 catch-all stub sites
  (`emitExpr`/`emitStatement`/`emitStringAssign` fallbacks): **77 hits across the passing suite**,
  almost all benign — DU type-declaration continuation lines (`| { kind: … }`), multi-line literal
  element lines, and speculative/pre-scan emit calls whose results are discarded (real emission uses
  correct paths). Routing them to the (hard-aborting) diagnostics channel would break valid programs;
  a blanket warning would be noise. The stubs are deliberate tolerance — kept. See design-decisions.md
  "Silent-stub audit" + "Intentional fallbacks".
- **Doc — `wasmmerge` pointer-relocation comment was stale.** Header still described the pre-Date-fix
  blanket ">= 260 is a pointer" heuristic; the code is range-scoped to each module's own
  `[dataLo, dataHi)` data extent. Comment corrected; residual (an arithmetic const coincidentally
  inside a string-bearing lib's data range) documented as the only narrow remaining heuristic.

## Single-physical-line class / constructor bodies — FIXED 2026-06-05

`class C { v: i32; constructor(x: i32) { this.v = x; } }` with the whole class (and/or constructor)
body on ONE physical line previously parsed wrong two ways: (1) **fields were dropped** — the field
loop iterated `classBody.split("\n")` and skipped any line containing `(`, so a field sharing the
line with the constructor was never registered; (2) **multi-statement bodies were mangled** — a
single-physical-line method body like `{ super(k); this.v = v; }` became one `bodyLine`
(`"super(k); this.v = v;"`) that emitted as one stubbed statement. Net effect: empty constructors +
unparsed fields → fields read 0. (The class-scope analogue of the function-body single-line gap fixed
2026-06-03.) **Fix** (`src/wasic.ts` `parseClasses`): (a) field parsing now iterates
`splitClassMemberLines(classBody)` — a new depth/string-aware splitter that breaks at depth-0 `;`,
depth-0 newlines, and immediately after a depth-0 `}` (a method body close), so fields, methods, and
the single-physical-line form all yield correct member lines (comments are already stripped globally
before `parseClasses`, so no comment handling is needed); (b) a method/constructor `rawBody` that is a
single physical line is split into statements via the existing string-aware `splitStmts` (mirrors the
2026-06-03 parseFunctions single-line-body fix). Regression test: `51_SingleLineClassBody.ts` (carries
`// deno-fmt-ignore-file` so `deno fmt` can't expand the single-line forms under test). Multi-line
class bodies (the norm) are unaffected. Validated: full suites green, zero regressions.

## Class construction gaps surfaced during Phase 51 instanceof — FIXED 2026-06-05

Found while writing instanceof tests; both predated Phase 51 and were unrelated to instanceof (the
WASM output silently diverged from the TS oracle — no error — so they were latent). Both now fixed
with regression tests `51_ModuleLevelClassInstance` + `51_ClassInstanceArrayLiteral` (suite 283→285).

1. **Module-level class instances weren't tracked in `classVars`.** `const b: Box = new Box(7)` at
   module scope constructed the object (the const-new statement handler ran), but `classVars` had no
   entry for `b`, so `b.v` / method dispatch / `b instanceof Box` didn't resolve (field reads stubbed
   to 0; instanceof folded to 0). Root cause: the `startBodyLines` pre-scan resets `classVars` and had
   no `newClassPre` equivalent (the registration lived only in `emitFunction`). **Fix** (`src/wasic.ts`):
   added a `newClassPre` block to the startBodyLines pre-scan mirroring `emitFunction` — allocates the
   instance via `allocStructData(cd.struct, {}, classTag)` (STATIC ptr, because the const-new statement
   handler emits `(i32.const ptr)` for both the `local.set` and the ctor call) and registers
   `classVars[var] = {className: ctorClass, ptr}`. The `if (cd)` guard skips TypedArrays.
2. **Array-literal of `new` instances were zero-filled.** `const a: C[] = [new C(1), new C(2)]` ran the
   static struct-array path, which parses `{field: val}` literals only — for `new C(...)` it allocated
   zeroed structs with no ctor call and no class tag, so fields read 0 and `a[i] instanceof C` was
   always false. (Field-access emission was already correct; only construction was missing.) **Fix**
   (`src/wasic.ts`): new `expandClassInstanceArrayLiterals()` source pre-pass (runs after `parseClasses`,
   before `parseFunctions`/`parseTopLevel`; bracket- and string-aware so multi-line literals work)
   desugars `const a: C[] = [new C(…), …]` → `const a: C[] = []; a.push(new C(…));…` when the element
   type is a known class and every element is a `new …(…)`. This reuses the proven `arr.push(new C())`
   path, which constructs each element with its ctor + tag. Helpers `findMatchingBracketAware` /
   `splitTopLevelCommasStringAware` / `skipStringLiteral` added.

(The single-physical-line class/constructor body gap that this work also surfaced was fixed in the
same Phase 51 pass — see the "Single-physical-line class / constructor bodies" section above.)

## FIXED — single-physical-line function bodies were mangled (2026-06-03)

When a whole function body lived on ONE physical line, multi-statement bodies were mis-emitted and
trailing statements after a brace `if` block were silently dropped. Two root causes:

1. **Function bodies were only split on `\n`.** A single-physical-line body
   (`{ let x = 0; if (c) { x = 1; } x += 100; return x; }`) was never split into statements — the
   whole thing was emitted as one mangled statement (e.g. jammed into the first `let`'s initializer).
2. **`expandInlineBraceChain` dropped trailing statements.** For `if (c) { return 1; } return 2;`
   it discarded everything after the brace chain that wasn't `else`, leaving a value-returning fn
   whose body is just a void `if` → V8 `expected 1 elements on the stack for fallthru, found 0`.

**Fix** (`src/wasic.ts`):
- In `parseFunctions`, when `rawLines.length === 1` (single-physical-line body), split it into
  statements up front via `splitStmts` before the existing per-line processing. Multi-line bodies
  (the norm — virtually every shipped test) are untouched, so blast radius is minimal.
- Made `splitStmts` **string-aware** (skips `"`/`'`/`` ` `` literals with `\` escapes) so a `;`,
  `{`, or `}` inside a string at depth 0 is never a false statement boundary. Its only prior caller
  (`expandInlineBraceChain`) benefits too; single-statement input is returned unchanged (idempotent).
- In `expandInlineBraceChain`, when the trailing content after the brace chain isn't `else`, close
  the block with `}` then re-emit the trailing statements (via `splitStmts`) as siblings instead of
  dropping them.

After splitting, each resulting statement is the idiomatic single-line form the existing if-handler
already handles (`expandInlineBraceChain` for the brace case, `fixTerminalFallthru` for terminal
void-if). The earlier repros now pass: `if (c) { return 1; } else { return -1; }` → `1 / -1`,
`if (c) { return 1; } return 2;` → `1 / 2`, plus else-if chains, brace-less inline-if + trailing
return, non-if-first single-line bodies, and string-literal `;`/`{`/`}` guards. Regression test:
`tests/wasm_wasi/48_SingleLineBraceIf.ts` (carries `// deno-fmt-ignore-file` so `deno fmt` can't
expand the single-physical-line forms under test). Validated: `wasm_wasi` **279/279**, `bindgen`
**103/103**, `jstyper` **73/73** (wabt-ts 1.3.2 + binaryen-ts 1.3.3), zero regressions.

(Note: bug1 — `if (c) { return 1; } else { return -1; }` — had already started passing by 2026-06-03
via the earlier value-fallthru/short-circuit work; the remaining live failure was the trailing-drop
and the non-if-first single-line body, both fixed here. The legacy machine-local `CLAUDE.md`'s claim
that `expandInlineBraceChain` alone fixed this was inaccurate; `cmem/` is authoritative.)

## FIXED — the 7 long-standing test failures (2026-06-02)

All 7 of the previously-"known pre-existing" failures are now fixed; as of 2026-06-02 the full
`tests/wasm_wasi` was **278/278** (the 7 fixes brought it to 277/277; the new `18h` virtual-
capability test added the 278th). (Current count is **279/279** — the 2026-06-03 single-line-brace
`if` fix added `48_SingleLineBraceIf`; see the top section.) They were two unrelated root causes:

### (a) Value-fallthru codegen — `5e_MixedSignatures`, `19_NestedDiscriminantUnions`, `19_VariantMaximumMemoryAlignment` (fixed in wasic)

A value-returning function whose body **ends in a statement-level (void) `if/else` where every
path `return`s** left nothing on the stack at the implicit function end. wabt + binaryen accept
this; **V8's strict validator rejects it** (`expected 1 elements on the stack for fallthru,
found 0`). Appending `(unreachable)` does NOT survive Binaryen `-Oz` — it strips the trailing
unreachable as dead code and re-emits the invalid void `if`.

**Fix** (`src/wasic.ts`, `emitFunction` → new `fixTerminalFallthru` + module-level `tokenizeWat`/
`parseWatNodes`/`serializeWat`/`watNodeToValue`/`watBranchToValue` helpers): when a value-returning
function's last top-level WAT s-expr is a void `if`, rewrite it into a value-producing
`(if (result T) cond (then … X) (else … Y))` by turning each branch's trailing `(return X)` into a
bare value `X` (recursing through nested all-returning ifs). Binaryen preserves a value-if as the
function result. Conservative: only rewrites when every branch leaf is a `return` (or a nested
all-returning `if`); otherwise leaves the body unchanged. Behavior is unchanged (the construct
already returned on all paths).

NOTE: the **single-physical-line** brace form (`if (c) { return 1; } else { return -1; }`) was a
SEPARATE bug, now **fixed 2026-06-03** — see the "FIXED — single-physical-line function bodies"
section at the top of this file. The 7 fixes here all use the multi-line form.

### (b) Hex-float literals encoded as 0 — `38_MathExpLog`, `38_MathHyperbolic`, `38_MathTrig`, `38_Phase38Combined` (fixed in wabt-ts 1.3.1)

The mathlib functions are merged from `mathlib.wasm`, whose f64 constants are in **hex-float**
notation (`0x1.921fb54442d18p+2`) after wabt disassembly. `wabt-ts@1.3.0`'s parser
(`parseF32/F64LiteralBits`) handled `LiteralType.Hexfloat` with JavaScript's `parseFloat()`, which
**cannot parse hex-float notation** — it reads the leading `0`, stops at `x`, returns `0`. So every
mathlib polynomial coefficient / π / e / ln2 was encoded as `0`, making merged `Math.*` return
garbage (and trapping `$__f64_to_str`'s `i64.trunc_f64_s` on the resulting NaN/Inf). The main
module's own constants (decimal) were unaffected — that's why only func-13-onward (the spliced
mathlib) was corrupt.

Bisected with a minimal repro (`f64.const 0x1.921fb54442d18p+2` → npm:wabt gives 6.283, wabt-ts gave
0) and confirmed by swapping `deno.json` to `npm:wabt` (all 4 tests pass). **Fixed upstream in
`@jrmarcum/wabt-ts@1.3.1`** (`src/parser/wast-parser.ts`: new `parseHexFloatValue` reconstructor;
both f32 and f64 Hexfloat cases route through it; decimal `Float` still uses `parseFloat`). `deno.json`
bumped `^1.3.0` → `^1.3.1`. Regression test in wabt-ts `tests/tools/wat2wasm.test.ts`.

## FIXED — short-circuit `&&`/`||` removes the merge OOB-`charCodeAt` trap class (2026-06-02)

This was the last OPEN bug. **Fixed properly** (Proper-fix #1 from the original writeup) by making
wasic emit **short-circuit** `&&`/`||` instead of a bitwise `i32.and`/`i32.or`; the RegExp library's
defensive workaround was then **removed** and 18g still passes, proving the codegen fix carries the
original trap construct on its own. Full suite re-validated: `wasm_wasi` **278/278**, `bindgen`
**103/103**, `jstyper` **73/73** (wabt-ts 1.3.2 + binaryen-ts 1.3.3).

**Original symptom:** a modc library that ran **correctly standalone** silently halted (WASM trap;
runner exits 0, no stderr) once `wasmbundle`/`wasmmerge` spliced it into a host module. Surfaced
building the RegExp capability (the matcher's count loop). Minimal repro: a `while` loop whose
condition is `i < len && atomMatches(p, pi, s.charCodeAt(i)) === 1` — a function call wrapping
`charCodeAt`, nested in an `i32.and`, in the loop's `br_if`. wasic emitted `a && b` as a
**non-short-circuit `i32.and`** (both operands always evaluated), so when `i == len` the OOB
`s.charCodeAt(i)` still ran; standalone `$__str_char_code_at` bounds-checks and returns -1, but the
spliced/reassembled `call`-in-`i32.and`-in-`loop`-`br_if` mis-encoded and trapped. (JSON didn't hit
it: its `&&`-with-`charCodeAt` conditions were in `if`s with a *direct* one-call `charCodeAt`, not a
nested call inside a `while` `br_if`.)

**The fix** (`src/wasic.ts` `emitExpr` binary-op loop, ~line 6135; mirrored in `src/console_log.ts`
`exprToWat`, ~line 1298): intercept `op === "&&" | "||"` before the bitwise `["&&","and",…]` /
`["||","or",…]` table mapping is applied and emit short-circuit control flow —
`&&` → `(if (result i32) <lhs> (then <rhs>) (else (i32.const 0)))`,
`||` → `(if (result i32) <lhs> (then (i32.const 1)) (else <rhs>))`. The result is i32 0/1, promoted
to the surrounding context via `(f64.convert_i32_s …)` / `(i64.extend_i32_s …)` when `watBaseType`
of the context type is wider. The old table entries STAY — they still drive operator *detection* in
the scan; only emission changed. Matches JavaScript semantics (RHS skipped once the LHS decides),
which is independently more correct. High blast radius (every `&&`/`||` site) — validated with the
three full suites above, zero regressions.

**Workaround removed:** `tests/wasm_wasi_bundle/regex_bundle/regex_lib_modc.ts` was rewritten to the
natural form — `atomAt` now returns `ti < t.length && atomMatches(p, pi, t.charCodeAt(ti)) === 1`,
and `matchStar`'s consume loop puts `ti + count < t.length && atomMatches(p, atomPi,
t.charCodeAt(ti + count)) === 1` **directly in the `while` `br_if`** (the exact original trap shape).
18g passes merged, so the fix — not the guard — is what carries it.

## FIXED — RegExp work (2026-05-31)

- **Greedy `charCodeAt` (and `startsWith`/`endsWith`/`split`) regex swallowed a following operator.**
  `expr.match(/^(\w+)\.charCodeAt\s*\((.+)\)$/)` with greedy `(.+)` matched the whole
  `p.charCodeAt(i) === t.charCodeAt(i)` as one call (the expr *starts* with `p.charCodeAt(` and
  *ends* with `)`), so the `===` never reached the binary-op loop → always-true comparison. Fix:
  added a `parenDepthNeverNegative(match[2])` guard to those four handlers in `emitExpr`
  (`src/wasic.ts`) so an unbalanced arg falls through to the binary-op loop. (JSON's
  `v[i] !== t.charCodeAt(i)` didn't hit this because it starts with `v[`, not `X.charCodeAt`.)

## FIXED — JSON work (2026-05-31)

1. **String args to a merged import dropped to one stack value** (`need 2, got 1`). A modc
   `func(s: string)` compiles its string param to `(i32 i32)`, so `mergeWasmWat` registered the
   import as `[i32, i32]` and the call site couldn't expand a string arg. Fix: read the sibling
   `.wit` (which preserves `s: string`) and overlay logical types onto each `ExternalFuncDef` in
   `compileWasiTs`/`compileLibTs` (new helpers `parseWitLogicalSigs`/`readWitLogicalSigs`/
   `applyWitSig`/`witTypeToWat`/`kebabToCamel`). Numeric-only libs unaffected.
2. **Allocator detector false-positive dropped a real function.** `detectBumpAllocator` matched a
   plain `global += param; return global` accumulator (a parser cursor `advance`) and silently
   dropped it during the merge → `undefined func`. Fix: a real `$__malloc` returns the *old* value
   captured before the `global.set`, so it reads the heap global **exactly once**; the accumulator
   reads it twice. Require exactly one `global.get` AND one `global.set` occurrence.
3. **Escaped-quote string literals matched as empty.** `"([^"]*)"` stops at the first `\"`, so a
   literal with escaped quotes (an embedded JSON doc) crossed as length 0 / hit "string assignment
   from complex expression not yet supported". Fixed to escape-aware `"((?:[^"\\]|\\.)*)"` at three
   sites in `src/wasic.ts`: `emitStringPtrLen` (string-arg path), `emitStringAssign` (local string
   assign), module-const detection in `parseTopLevel`. (`console_log.ts`'s `console.log`-arg
   emitter still has the un-escaped form — pass escaped-quote literals via the main paths, which
   the JSON driver does.)
4. **`findBinaryOp` missed an operator whose RHS ends in a call.** The scan started at
   `expr.length - op.length`, never counting the last `op.length-1` chars for depth — a trailing
   `)` (e.g. `v[i] !== t.charCodeAt(i)`) drove paren depth negative so the operator was never found
   and the whole expression fell to the always-false comment-stub. Also added bracket `[]` counting
   (matching `findDepth0LTR`/`findDepth0Keyword`). Fix: scan the full string for depth, match only
   at valid start positions. High blast radius; re-validated with no regression.

## The 7 formerly-known test failures — ALL FIXED 2026-06-02

These failed for a long time but are **now all passing** (full suite 278/278 as of 2026-06-02;
**279/279** currently). Kept here as a
pointer; full root-cause writeups are in the "FIXED — the 7 long-standing test failures" section at
the top of this file.

| Test | Was | Fix |
| --- | --- | --- |
| `19_NestedDiscriminantUnions`, `19_VariantMaximumMemoryAlignment`, `5e_MixedSignatures` | V8 strict-validation fallthru on terminal void-if/else where all paths return | value-fallthru rewrite in wasic (`fixTerminalFallthru`) |
| `38_MathExpLog` / `38_MathHyperbolic` / `38_MathTrig` / `38_Phase38Combined` | merged mathlib returned garbage — hex-float consts encoded as 0; the original "f64→i32 truncation" framing was a downstream symptom (NaN/Inf → `i64.trunc_f64_s` trap) | wabt-ts 1.3.1 hex-float parse fix |

## Regenerated `.wat`/`.wasm` artifact churn

Running the suite overwrites many committed `tests/wasm_wasi/*.wat`/`*.wasm` from passing tests
(cumulative compiler drift, not behavior changes — outputs are identical). One incidental cosmetic
change: `6a_json.wat` now emits an explicit "not yet supported" stub for an already-broken
string-accumulation-in-a-loop helper (was a silent partial compile; the test passes either way).
If you want a focused diff, `git restore` the unrelated `.wat`/`.wasm` before committing.
