# Compiler bug log

Live record of bugs found + fixed (and one still open). Newest first.

## OPEN — merge mis-encodes an OOB `charCodeAt` in a non-short-circuit `&&` loop condition (2026-05-31)

**Symptom:** A modc library that runs **correctly standalone** silently halts (WASM trap; runner
exits 0, no stderr) once `wasmbundle`/`wasmmerge` splices it into a host module. Surfaced building
the RegExp capability (the matcher's count loop).

**Minimal repro:** a `while` loop whose condition is
`i < len && atomMatches(p, pi, s.charCodeAt(i)) === 1` (i.e. a function call wrapping
`charCodeAt`, nested in an `i32.and`, in the loop's `br_if`). When `i == len`, the **non-short-
circuit `&&`** still evaluates `s.charCodeAt(i)` (an OOB index). Standalone, `$__str_char_code_at`
bounds-checks (`idx>=len → return -1`) and the loop ends cleanly. Merged, the same construct traps.

**Confirmed NOT:** infinite loop (a `count < 1000` cap as the first `&&` operand did not stop it →
it's a trap, not a runaway); Binaryen (halts with Binaryen disabled on both modc and the wasic
merge step via a temporary env gate — now reverted); the merged `charCodeAt`'s bounds check (read
the merged WAT — it is fully intact: `idx<0→-1`, `idx>=len→-1`, else load). The merged call-site
also passes the correct `(t_ptr, t_len, idx)`. So the corruption is introduced by the
**splice + wabt-ts reassembly** of the larger module (shifted function/type indices), in the same
family as the wabt-ts name/index-resolver bugs the brief documents — a `call` nested in an
`i32.and` inside a `loop` `br_if`.

**Why JSON didn't hit it:** JSON's `&&`-with-`charCodeAt` conditions are in `if`s with a *direct*
`charCodeAt` (one call), not a nested `atomMatches(charCodeAt(...))` inside a `while` `br_if`.

**Workaround in use:** the RegExp library is written to NEVER call `charCodeAt` on an unchecked
index — every fetch is guarded by an enclosing `if (i < len)` (helper `atomAt`). This is also the
correct defensive style. Set/Map/Date/JSON are unaffected.

**Proper fixes (future, pick one):**
1. Make wasic emit **short-circuit** `&&`/`||` (an `if`/`select` that skips the RHS when the LHS
   is false) instead of `i32.and`/`i32.or`. This is more correct JS semantics and would fix the
   whole class, but is high-blast-radius (some code may rely on both sides evaluating) — validate
   against the full suite.
2. Confirm + fix in the merge: swap `deno.json` to `npm:wabt` and re-run 18g to verify it's the
   wabt-ts assembler; if so, file/fix upstream like the other wabt-ts encoder bugs.

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

## The 7 known pre-existing test failures (wasic-side codegen, predate this work)

These have failed for a while and are **not** regressions. Do not be alarmed when the suite shows
"7 failed."

| Test | Cause |
| --- | --- |
| `19_NestedDiscriminantUnions` | V8 strict-validation fallthru on nested-if/else DU structures |
| `19_VariantMaximumMemoryAlignment` | same DU nested-if/else fallthru family |
| `38_MathExpLog` / `38_MathHyperbolic` / `38_MathTrig` / `38_Phase38Combined` | f64→i32 truncation in mathlib call paths → "float unrepresentable in integer range" traps |
| `5e_MixedSignatures` | fallthru-stack issue (same family as the 19_* fallthru) |

## Regenerated `.wat`/`.wasm` artifact churn

Running the suite overwrites many committed `tests/wasm_wasi/*.wat`/`*.wasm` from passing tests
(cumulative compiler drift, not behavior changes — outputs are identical). One incidental cosmetic
change: `6a_json.wat` now emits an explicit "not yet supported" stub for an already-broken
string-accumulation-in-a-loop helper (was a silent partial compile; the test passes either way).
If you want a focused diff, `git restore` the unrelated `.wat`/`.wasm` before committing.
