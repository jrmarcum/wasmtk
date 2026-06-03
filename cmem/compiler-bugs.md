# Compiler bug log

Live record of bugs found + fixed. Newest first. **No open bugs.** The last one — the single-line
brace `if {…}` form — was fixed 2026-06-03 (see directly below); the full suite is now **279/279**
(the new regression test `48_SingleLineBraceIf` adds the 279th).

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
