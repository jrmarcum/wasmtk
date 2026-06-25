# wasmtk own dynamic runtime (#14) — design + implementation log

**Roadmap #14 / stdlib-bundling brief §6/§7-#7.** DECISION (project owner, 2026-06-02): rather than
declaring the irreducible dynamic kernel out of scope or depending on `javyc`/QuickJS long-term,
wasmtk **ships its own dynamic runtime** — boxed values + a property map + (later) an interpreter for
`eval`/`new Function`. `javyc` stays the interim fallback until this lands. This is the largest single
remaining track; it is gated behind Phase 51 (complete), so it is unblocked. The kernel it must cover:
runtime code-gen from strings (`eval`/`new Function`), pervasive `any` over runtime-unknown shapes,
and open-ended prototype mutation (brief §6).

## Locked architecture decisions (owner, 2026-06-22)

1. **First increment = the value + object model** (the substrate everything else lowers onto). NO
   interpreter / `eval`, NO prototype mutation yet.
2. **Value representation = a tagged heap cell** addressed by an **i32 handle** (not NaN-boxing) — it
   integrates directly with the existing shared-heap allocator, ptr+len strings, dynamic-array
   headers, and `Int32Array`/`Float64Array`/`Uint8Array` view idioms.
3. **Authoring = the wasic TS subset now, extract a shared `rtcore` + go hand-WAT later.** Writing the
   runtime in the same subset as the Tier-1 caps means the allocator, strings, dynamic arrays and
   number formatting all come from wasic's own codegen — **zero duplication**. Hand-WAT would
   duplicate `$__malloc`/`$__str_*`/`$__*_to_str`/dynarr/hashmap. The chosen plan: author in the
   subset now; when the **interpreter** increment actually needs hand-WAT control, extract a single
   mergeable `rtcore` module (move wasic's currently-inlined helpers into it so BOTH wasic output and
   the hand-WAT runtime import it — also shrinks multi-cap bundles) and go hand-WAT against it. So
   `rtcore` is a deliberately deferred, interpreter-stage refactor, not increment-1 work.
4. **Opt-in = runtime-only first.** No wasic `any` type yet — the runtime is built/tested standalone
   (a driver calls its ops directly, like the cap drivers). Wiring a wasic `any` type that lowers to a
   boxed-value handle (and auto-merging the runtime when `any`/dynamic features are used) is a later
   increment once the runtime is proven.

## Increment 1 — value + object model (SHIPPED 2026-06-22)

Delivered exactly like the Tier-1 caps: a shared-heap `modc` library + a self-checking driver +
an `@test-pipeline`. After the Phase 18 merge + Stage 0.6 allocator unification, the library's
`$__malloc` resolves to the driver's bump cursor, so boxed values live on the ONE shared heap.

- Library: `tests/wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts`
- Driver:  `tests/wasm_wasi_bundle/dynrt_bundle/main_wasic.ts`
- Pipeline test: `tests/wasm_wasi/18j_DynRuntimeValueModel.ts` (modc → wasic → run). **PASS.**

**Boxed value** = i32 handle = base ptr of a 4-slot `Int32Array` node `[tag, a, b, c]`:

| tag | type | a | b | c |
| --- | --- | --- | --- | --- |
| 0 | undefined | — | — | — |
| 1 | null | — | — | — |
| 2 | boolean | 0/1 | — | — |
| 3 | number (real f64) | ptr → `Float64Array(1)` | — | — |
| 4 | string | `Uint8Array` byte-buffer ptr | byte length | — |
| 5 | array | list ptr (see below) | — | — |
| 6 | object | values list ptr | — | keys list ptr (interleaved `[keyPtr, keyLen]`) |

**Containers use a self-managed growable `Int32Array` list**, NOT wasic's native `[]`+`.push`
(see the empty-array gap below): a "list" is `Int32Array` laid out `[len, cap, e0, e1, …]` with
`listNew`/`listLen`/`listGet`/`listSet`/`listPush` (starting cap 4, doubling, copy-on-grow,
returns the possibly-realloc'd ptr which the owning node writes back). Objects keep parallel values
+ interleaved-keys lists with O(n) `objIndexOf` lookup (a hashmap is a perf follow-up, not v1).

**Exports (v1 surface, ~23):** constructors `dynUndefined/dynNull/dynBool/dynNumber/dynString/
dynArray/dynObject`; introspection `dynTag` (raw 0–6) / `dynTypeof` (JS code 0=undefined 1=object
2=boolean 3=number 4=string 5=function — null/array/object all → 1, the JS quirk); accessors
`dynNumberValue`(f64)/`dynBoolValue`/`dynStrLen`/`dynStrCharAt`; coercions `dynToBool` (ToBoolean,
NaN/0/""/null/undefined falsy) / `dynToNumber` (f64; string/array/object → NaN in v1); object
`dynSet`/`dynGet`(−1 if absent)/`dynHas`/`dynObjLen`; array `dynPush`/`dynArrLen`/`dynArrGet`;
operators `dynStrictEq` (`===`: primitives by value incl. NaN!==NaN, objects/arrays by handle
identity) and `dynAdd` (`+`: string concat if either operand is a string, else numeric add).

**v1 gaps (documented, deferred):** functions (tag 7) + `eval`/`new Function` (the interpreter
increment); prototype mutation; string→number coercion; array/object stringification in `dynAdd`
(→ `""`); a hashmap-backed property map; UTF-16/multi-byte string fidelity (ASCII-accurate, as
elsewhere in wasic). Absent object key returns sentinel −1 (the future wasic `any` lowering maps it
to `undefined`).

## Increment 1b — virtual `wasmtk:dynrt` import + tree-shake (SHIPPED 2026-06-22)

The runtime is now embedded in the compiler and importable BY NAME, exactly like the Tier-1 caps:
`import { dynNumber, dynObject, … } from "wasmtk:dynrt"`. No `modc` step, no fixture `.wasm` on disk
— the pipeline is just `wasic` + `run`, and the runtime is bundled only when imported (feature-level
tree-shake, brief §7-#4). Wiring (one line each, the resolver in `tsbundler.ts` is generic):

- `scripts/gen_caps_bytes.ts` — added `{ id: "dynrt", dir: "dynrt_bundle", base: "dynrt_lib_modc" }`
  to the `CAPS` list; regenerated `src/wasm/caps_bytes.ts` (dynrt = 4470 bytes embedded). No resolver
  change: `tsbundler.ts` slices `wasmtk:<id>` and looks it up in `CAPABILITIES` generically.
- Driver `tests/wasm_wasi_bundle/dynrt_vcap_bundle/main_wasic.ts` imports from `wasmtk:dynrt`;
  pipeline test `tests/wasm_wasi/18k_DynRuntimeVirtualImport.ts` (wasic → run). **PASS.**

**To regenerate after editing the dynrt library:** `wasmtk modc
tests/wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts` → then `deno run --allow-read --allow-write
scripts/gen_caps_bytes.ts` → then `deno task install` (so the installed binary carries the new bytes).

Deferred from 1b (not blocking): a hashmap-backed property map and f64-aware `dynToNumber(string)`.

## Increment 2a — `eval` of a pure expression language (SHIPPED 2026-06-22)

The first piece of the **interpreter** (#14 increment 2). DECISION (owner 2026-06-22): **continue in
the wasic subset** — the subset already proved out recursive-descent (JSON) and backtracking (RegExp)
with a module cursor, and the interpreter is parsing + tag-dispatch + arithmetic + value-model calls,
so **no `rtcore` extraction / hand-WAT was needed** (kept in reserve for a concrete future wall). And:
**expression evaluator first** (no variables / member access / calls / statements yet — those are 2b+).

`dynEval(src: string): i32` is a **recursive-descent, DIRECT-eval** parser (no separate AST) over a
module-level cursor `evalPos`, mirroring the JSON parser's shape, returning a boxed value handle.
Grammar (low→high precedence): ternary `?:`, `||`, `&&`, equality `=== !== == !=` (`==`/`!=` treated
as strict in v1), relational `< > <= >=`, additive `+ -`, multiplicative `* / %`, unary `- ! +`,
primary (number/string/bool/null/undefined literal or `( … )`). Number literals (int/fraction/exponent)
are sliced and parsed with `parseFloat` (works in modc). String literals handle `\n \t \r` + literal
escapes.

**Key v1 simplification — no real short-circuit (correct here):** because v1 expressions have NO side
effects (no variables, calls, or assignments), `&&`/`||`/`?:` evaluate BOTH sides and select per JS
semantics (`a&&b` → b if truthy(a) else a; `a||b` → a if truthy(a) else b; `?:` picks). This is
observationally identical to short-circuit for a side-effect-free language. **Real short-circuit
(skip-parse or AST) becomes mandatory in 2b** once identifiers/calls can have side effects.

Added the **dynamic operator surface** the value model lacked (also what the future wasic `any`
lowering will call): `dynNeg`/`dynNot`/`dynSub`/`dynMul`/`dynDiv`/`dynMod`/`dynLt`/`dynGt`/`dynLe`/
`dynGe` (comparisons numeric in v1; string/lexicographic compare is a gap). `dynStrictEq`/`dynAdd`
already existed. All are exports of the dynrt library; a program importing only `dynNumber` still
gets them dead-stripped by Binaryen (reachable only from `dynEval`).

- Lives in the same library (`dynrt_lib_modc.ts`); `wasmtk:dynrt` now also exposes `dynEval` (caps
  bytes regenerated → 7773 bytes). Driver `tests/wasm_wasi_bundle/dynrt_eval_bundle/main_wasic.ts`
  (explicit-fixture pipeline, imports `../dynrt_bundle/dynrt_lib_modc.wasm`); pipeline test
  `tests/wasm_wasi/18l_DynRuntimeEval.ts`. **PASS** (precedence/parens/unary/f64/comparisons/logical/
  ternary/string-concat). **No new compiler gaps** — the lib compiled clean on the first try.

**2a gaps (→ 2b+):** variables / an environment (identifier resolution), member/property access,
function calls, `new Function`, statements + control flow, real short-circuit, string comparison,
loose-equality coercion (`==`/`!=` are strict in v1).

## Increment 2b — variables + environment + member/index access (SHIPPED 2026-06-22)

`dynEvalEnv(s: string, env: i32): i32` — evaluate against an **environment object** (a value-model
object, names → boxed values). Bare identifiers resolve via `dynGet(env, name)` (→ `undefined` if
absent or no env); `dynEval(s)` is unchanged (no env). Robust identifier tokenisation replaced 2a's
fragile first-char keyword detection (read the full `[A-Za-z_$][A-Za-z0-9_$]*` run via `isIdentChar`,
then dispatch `true`/`false`/`null`/`undefined`, else look up). Added **postfix member/index access**
(`parsePostfix`, binds tighter than unary): `obj.name`, `obj["key"]`, `arr[i]` (computed index works,
e.g. `arr[x-9]`), and `.length` on arrays/strings.

**`dynMember`/`dynIndexValue` are TOTAL (guarded):** object property → `undefined` if absent;
array/string `.length`; member of a non-container (`undefined.x`) → `undefined`, never a trap. This is
the load-bearing decision for the 2b scope split (below).

**SCOPE SPLIT from the design's original 2b (rationale recorded):** the original 2b lumped in *calls*
and *real short-circuit*. Both moved to the next sub-increment, because **real short-circuit is only
OBSERVABLE — and only TESTABLE — with side-effecting operands, i.e. calls**: in 2b every operand is a
pure read (variable lookup, guarded member access), so evaluating both sides of `&&`/`||`/`?:` and
selecting is observationally identical to short-circuit, and the guarded (total) member access removes
the only trap-safety motivation (`obj && obj.x` is already safe because `undefined.x` → `undefined`).
So 2b ships the read/navigation layer; **calls + function values (tag 7) + real short-circuit land
together in 2c** where short-circuit becomes real and observable.

- Same library; `wasmtk:dynrt` regenerated → 8674 bytes. Driver
  `tests/wasm_wasi_bundle/dynrt_eval_bundle/main_env.ts` (builds `{x,y,name,pt:{a,b},arr:[…]}`);
  pipeline test `tests/wasm_wasi/18m_DynRuntimeEvalEnv.ts`. **PASS** on the first run — **no new
  compiler gaps** (env lookup, `.prop`/`["key"]`/`[i]`, computed index, `.length`, guarded
  `undefined.x`, variables in ternaries).

**2b gaps (→ 2c):** calls + function values + REAL short-circuit; statements + control flow;
`new Function`; loose-equality coercion; string/lexicographic comparison; nested array/object literals
*inside* the eval source (the driver builds them with the value-model API, but `dynEval("{a:1}")` /
`dynEval("[1,2]")` literal syntax is not parsed yet).

## Increment 2c — function values + calls + REAL short-circuit (SHIPPED 2026-06-22)

**Function values (tag 7).** A function value is a boxed cell `[7, builtinId, …]`. Dispatch is a
**static switch on the id** — NOT a function table — because **wasmmerge forbids `call_indirect` in a
merged module** (the same constraint that keeps the Promise runtime inline). So callable values in the
dynamic runtime are **built-ins keyed by id**; user-defined functions / `new Function` (which need a
parsed body) are 2d. `dynBuiltin(id)` constructs one; `dynStdEnv()` returns an env pre-populated with
`abs`/`sqrt`/`floor`/`ceil`/`round`/`min`/`max`/`len` + `inc`; `dynApply(callee, argsArr)` is the
static-switch dispatcher (also exported for host-driven calls). `dynTypeof` of tag 7 → `5` (function).

**Calls in the evaluator.** `parsePostfix` gained a `(args)` case: build a value-model array of arg
boxes (any arity), then `dynApply`. Calling a non-function → `undefined` (guarded). Works over
variables, nested as args (`max(abs(-5), 2)`), and composed (`abs(-3) + sqrt(9)`).

**REAL short-circuit (deferred from 2b, now observable).** The direct-eval parser threads a
module-level `evalLive` flag, saved/restored at each `&&`/`||`/`?:`; the branch that JS would skip is
parsed with `evalLive = 0`. **The CALL dispatch is the ONLY side-effecting op**, so it is the only
thing guarded by `evalLive` (skipped in a dead branch while args still parse to advance the cursor);
pure ops run regardless (harmless). `inc()` (the one side-effecting built-in) + `dynSideEffectCount()`/
`dynResetSideEffects()` make it testable: `false && inc()` → counter 0, `true && inc()` → 1,
`true || inc()` → 0, `false ? inc() : 5` → 0, `max(false && inc(), true && inc())` → 1 (short-circuit
inside call args), `inc() + inc()` → 2.

- Same library; `wasmtk:dynrt` regenerated → 9664 bytes. Driver
  `tests/wasm_wasi_bundle/dynrt_eval_bundle/main_calls.ts`; pipeline test
  `tests/wasm_wasi/18n_DynRuntimeCalls.ts`. **PASS.** Surfaced one wasic gap (i32 global / typed-array
  element as an f64 call-arg skips the `f64.convert` — bind to a local first; see compiler-gaps below)
  and one driver-side gap (a module-level `const env = <call>` isn't visible inside nested driver
  functions — thread it as a param, as the env/calls drivers do).

**2c gaps (→ 2d):** user-defined functions + `new Function`; statements + control flow + assignment;
`Math.x` namespace object (built-ins are bare names via `dynStdEnv`, not `Math.sqrt`); loose-equality
coercion; string comparison; array/object literal syntax inside the eval source.

## Increment 2d.1 — statements + control flow (`dynRun`) (SHIPPED 2026-06-22)

A STATEMENT interpreter layered on the 2a–2c expression evaluator. `dynRun(s: string, env: i32): i32`
executes a statement sequence against a mutable environment object (declarations + assignments mutate
it via `dynSet`), returning the `return` value, else the last expression statement's value, else
`undefined`. **Authoring decision held: continue in the subset — no wall** (the design flagged 2d as
the likely `rtcore`/hand-WAT revisit; the statement layer turned out to be recursive-descent + a
mutable env + cursor manipulation, all expressible — first-compile, first-run pass, NO new gaps).

**Statements:** `let`/`const`/`var name [= expr];` (no init → `undefined`); bare-identifier assignment
`name = expr;` (detected by an `=` not followed by `=`); `if (cond) stmt [else stmt]`; `while (cond)
stmt`; `{ blocks }`; expression statements; `return [expr];`. New helpers `readIdent` +
`runDecl`/`runReturn`/`runIf`/`runWhile`/`runStatement`/`runStatements`; new globals `evalReturned`/
`evalReturnVal`/`lastValue`.

**Control flow via the DIRECT-eval re-parse trick (no AST):** `while` records the condition's cursor
position (`condStart`) and re-sets `evalPos = condStart` each iteration to re-parse condition + body
(so it costs O(body × iterations) to *parse*, but needs no AST and no separate eval walker). Dead
branches of `if`/`while` (and statements after a `return`) are parsed with `evalLive = 0` — reusing
the 2c short-circuit machinery to advance the cursor while executing nothing. `return` sets
`evalReturned`, which stops sequencing (and ends a loop). A 100M-iteration safety cap guards runaway
loops.

**Proven** (`tests/wasm_wasi_bundle/dynrt_eval_bundle/main_run.ts`, pipeline test
`tests/wasm_wasi/18o_DynRuntimeStatements.ts`, `wasmtk:dynrt` → 11140 bytes): real programs — `x = x*2`
chains, `if/else` (incl. no-else + early `return`), `while` sum/factorial/**fibonacci(10)=55**, nested
loops, conditional accumulation, `return` out of a loop, and built-in calls inside statements. **PASS.**

**2d.1 gaps (→ 2d.2):** **user-defined functions + `new Function`** (needs function values holding a
body + a fresh scope on call, and parser-reentrancy save/restore of `evalPos`/`evalEnv`/`evalReturned`
around the nested `dynRun`); no block scoping (all `let`/`const`/`var` share the one flat env); no
`for`; no member-assignment (`obj.x = …` / `arr[i] = …`); `const` is not enforced (reassignable).

## Increment 2d.2 — user-defined functions + `new Function` (SHIPPED 2026-06-22) — COMPLETES interpreter (#14 inc 2)

**User function values.** Built-ins use a 4-slot cell with id ≥ 0; user functions use a **5-slot
cell** `[7, -1, bodyStrBox, paramsArr, defEnv]` (marker id −1). `dynApply` branches on `id === -1`:
create a fresh call scope (a `dynObject`) whose **parent link** (object cell slot 2) is the function's
**defining env**, bind args→params, then `dynRun(bodySrc, scope)`. The parent link is what makes
**recursion + closures-over-outer-vars** work: identifier resolution now walks the chain via new
`envLookup(env, name)` (current → parent → …), replacing the flat `dynGet` in `parsePrimary`.

**Two creation paths.** (1) In-source `function name(params){ body }` declarations — new `runFuncDecl`
captures the body's SOURCE TEXT by a string-aware brace-depth scan, stores it in a string box, binds a
user-function value (closing over the current env). (2) **`dynMakeFunc(paramsArr, bodyStr, defEnv)`**
export — the **`new Function`** capability: build a callable from STRINGS at runtime, then call it
(here via `dynEvalEnv`). The §6 kernel item "runtime code from strings" is now covered.

**Parser reentrancy (the hard part).** A user call re-enters `dynRun`, which resets the shared parser
globals (`evalPos`/`evalEnv`/`evalLive`/`evalReturned`/`evalReturnVal`/`lastValue`). `dynApply` saves
all six to locals before the nested `dynRun` and restores them after, so the OUTER parse resumes
correctly. This works because the source string `s` is a **parameter** (each source stays on its own
call stack) — only the globals need save/restore. Nested/recursive calls each get their own saved
locals.

**Proven** (`tests/wasm_wasi_bundle/dynrt_eval_bundle/main_func.ts`, pipeline test
`tests/wasm_wasi/18p_DynRuntimeFunctions.ts`, `wasmtk:dynrt` → 12185 bytes): in-source decls + calls,
**recursion (factorial, fibonacci)**, **closure over an outer `let`**, mutually-calling functions, a
function with its own locals + loop, functions calling built-ins, and **`new Function`** built from
strings then called through eval. **PASS.** No new compiler gaps.

**KNOWN LIMITATION — heap-bound recursion (no GC).** Each call allocates a fresh scope + reconstructs
the body string (`boxToStr` is O(n²) concat) + re-parses, and the bump allocator never frees, so deep
recursion / very many calls exhaust the merged module's ~2-page heap — `fib(10)` (≈177 calls)
overflows; the test uses `fib(8)`. This is the no-GC bump-allocator reality (the same "bump allocator,
no free" property of the whole DLL model). A future memory pass (bigger pages, body-string interning,
or a real allocator/GC) would lift it; out of scope for the interpreter increment.

**2d.2 gaps (→ later / increment 3):** function EXPRESSIONS (`const f = function(){…}`) + arrow
functions; literal `new Function(...)` *expression syntax* in the eval source (the capability is
`dynMakeFunc`; the sugar isn't parsed); proper block scoping + write-through assignment to outer vars
(assignment writes the current scope); `for`; member-assignment; `const` enforcement; the heap limit
above.

## Compiler gaps surfaced (worked around in the library; candidates for a real wasic fix)

Like every Tier-1 cap, this increment surfaced wasic gaps. Both are worked around in the library and
recorded in `compiler-bugs.md`; each could later be fixed in `src/wasic.ts` and the workaround removed
(the RegExp `&&` precedent).

1. **Concat of two string-returning CALLS** — `stringForm(a) + stringForm(b)` aborted
   ("Unsupported expression"). `emitStringAssign` doesn't handle a `+` whose operands are both
   string-returning function calls. Workaround: bind each call to a `string` local first, then concat.
2. **`Float64Array` element in a comparison mis-infers as i32** — `fa[0] === fb[0]` emitted `i32.eq`
   over `f64.load` operands → instantiate-time type error. Float64Array element reads aren't tracked
   as f64 by the binary-op type inference (only when assigned to an explicitly-typed `f64` local).
   Workaround: route f64 array-element reads through `const x: f64 = fa[0]` before comparing.
3. **Empty-array `[]` is a SHARED static zero-capacity array; growth from cap 0 is broken** — the
   root cause of the first big bug. `const a: i32[] = []` lowers to a static data-segment array (every
   `dynArray()` returned the SAME ptr 260 until first grow), and `$__dynarr_push_i32` grows by
   `cap << 1`, which stays 0 from a 0 capacity — so pushes scribble past the allocation into the next
   `$__malloc` (killing element 0) and independent arrays alias. JSON dodged it by building arrays hot
   and reading immediately; a **mutable** runtime can't. Fix in the library: self-managed `Int32Array`
   lists (above). A real compiler fix would make `[]` heap-allocate with nonzero capacity and make the
   grow use `max(cap*2, MIN)` — this would also harden every future reconstruct-then-`push` user.

## Next increments

- **1a — value + object model — ✅ SHIPPED 2026-06-22** (test `18j`; see above).
- **1b — `wasmtk:dynrt` virtual import + tree-shake — ✅ SHIPPED 2026-06-22** (test `18k`; see above).
  Deferred extras (optional, not started): hashmap-backed property map; f64-aware `dynToNumber(string)`.
- **2a — `eval` of a pure expression language — ✅ SHIPPED 2026-06-22** (test `18l`; see above).
  Authoring decision resolved: continue in the subset (no `rtcore`/hand-WAT needed yet).
- **2b — variables + environment + member/index access — ✅ SHIPPED 2026-06-22** (test `18m`; see
  above). Scope split: calls + real short-circuit moved to 2c (short-circuit is only observable with
  side-effecting calls; guarded member access makes 2b trap-safe without it).
- **2c — function values (tag 7) + calls + REAL short-circuit — ✅ SHIPPED 2026-06-22** (test `18n`;
  see above). Built-ins via static-switch dispatch (no `call_indirect`, merge-safe); `evalLive`
  skip-parse short-circuit guarding the call dispatch.
- **2d.1 — statements + control flow (`dynRun`) — ✅ SHIPPED 2026-06-22** (test `18o`; see above).
  let/const/assignment, if/else, while, blocks, return; direct-eval re-parse loops; still in the
  subset (no wall → no `rtcore`/hand-WAT needed).
- **2d.2 — user-defined functions + `new Function` — ✅ SHIPPED 2026-06-22** (test `18p`; see above).
  **COMPLETES interpreter increment 2.** User function values (5-slot cell + scope-chain); in-source
  `function` decls + `dynMakeFunc` (new Function); recursion/closures via `envLookup`; parser
  reentrancy save/restore. Still in the subset — the `rtcore`/hand-WAT path was never forced.

**Interpreter increment 2 (2a–2d.2) COMPLETE — the whole #14 §6 kernel-of-`eval`/`new Function` is
covered, authored entirely in the wasic TS subset (no `rtcore` extraction / hand-WAT needed).**
Remaining for #14: **increment 3 — wasic `any` type + auto-merge + migrate `hybrid --auto`'s dynamic
target off `javyc`** (lower a wasic `any` to a boxed-value handle and route dynamic-shaped functions
to this runtime), plus an optional memory pass to lift the heap-bound-recursion limit.

## Increment 3 — wasic `any` + auto-merge + hybrid migration — SCOPED 2026-06-22 (not started)

**Decisions (owner 2026-06-22):** (1) **DEEP `any`** — box/unbox + operators + member/index/call on
`any` route to `dynrt`; (2) **hybrid migration IN this increment** (repoint `hybrid --auto`'s dynamic
route to wasic+dynrt, host fallback); (3) **auto-merge on `any`/`eval` usage** (inject a synthetic
`wasmtk:dynrt` import). This is the **largest, most invasive increment of the whole #14 track** — it
modifies the wasic COMPILER (type system, the hot binary-op path, member/call emission), not just the
dynrt library. Recommended BUILD ORDER (land + full-suite-verify each before the next; delivered
collectively as "14.3"):

- **3.1 — `any` as a tracked type + box/unbox + auto-merge.**
  **3.1-foundation ✅ SHIPPED 2026-06-22** (test `18q`): `mapType("any") → i32` (a boxed handle; no
  test used `any` before — it had fallen through to f64, so the change is safe). AUTO-MERGE works —
  the bundler (`tsbundler.ts`, in `load()` for the entry) injects a synthetic `import { …ops… } from
  "wasmtk:dynrt"` when the entry uses `: any` / `any[]` / `<any>` / `eval(`, reusing the existing
  virtual-capability merge + tree-shake; a driver with NO explicit dynrt import merges it purely from
  `: any` usage. New dynrt export **`dynStrBytes`** (raw byte ptr, for any→string unboxing). Proven:
  box/unbox round-trip (`dynNumber`→`dynNumberValue`), `eval` of a string → `any`, `any` string +
  introspection, `any` params/returns (= i32 handle) through a function. Driver
  `tests/wasm_wasi_bundle/dynrt_any_bundle/main_wasic.ts`. (`dynMember`/`dynIndexValue` are NOT yet in
  the injected import set — they become dynrt exports in 3.3.)
  **3.1-sugar ✅ SHIPPED 2026-06-22** (extends `18q`): **implicit boxing of LITERAL initialisers** —
  a transpile source pre-pass rewrites `const x: any = <number|string|template|bool literal>;` →
  `dynrt_dynNumber/dynString/dynBool(...)` (conservative: only a bare literal terminated by `;`, so
  `42+3` / vars / `eval(...)` / already-`any` are untouched). **`as`-unboxing** — new `anyVars`
  side-set (per-function + module, populated by scanning body/start lines for `: any` declarations);
  the `as` handler emits `dynrt_dynNumberValue`(+trunc for i32) / `dynrt_dynToBool` when the operand
  is an any var. **KEY WIRING LESSON:** the bundler rewrites explicit `dynX` imports → `dynrt_dynX`
  (merge prefix) BEFORE transpile, so names the compiler INTRODUCES (boxing pre-pass, as-handler) must
  be **pre-prefixed `dynrt_`** to resolve against the merged module. **Gaps (follow-ups):** any-PARAM
  unboxing (FuncParam doesn't retain the raw `any` annotation — needs an `isAny` flag from
  parseFunctions); `as string` unboxing (needs ptr+len in the string-assign path, not single-value
  emitExpr); inline `(x as f64) === lit` mis-infers the comparison as i32 (use an intermediate typed
  local — the common form); non-literal typed RHS boxing (`const x: any = someI32`).
- **3.2 — operators on `any`. ✅ SHIPPED 2026-06-22** (extends `18q`). In `emitExpr`'s binary-op loop,
  right after `lhs`/`rhs` are split, a guarded block fires **only when an operand is a simple `any`
  var** (`anyVars.has`) — otherwise the existing typed paths run **untouched** (the safety invariant
  for the hottest path). New helper `boxAnyOperand` yields a handle for each operand (any var passes
  through; literal/typed var boxed via merged `dynrt_dynNumber/dynString/dynBool`). Emission:
  arithmetic `+ - * / %` → `dynrt_dynAdd/Sub/Mul/Div/Mod` (result is an **`any` handle**); `=== ==` →
  `dynrt_dynStrictEq` (**raw i32 0/1**), `!== !=` → `(i32.eqz …)`; `< > <= >=` →
  `dynrt_dynToBool(dynrt_dynLt/Gt/Le/Ge …)` (**raw i32**, so they work in conditions, matching wasic's
  comparison convention); `&& ||` → truthiness short-circuit over `dynrt_dynToBool(operand)` (**v1
  returns the boolean, not the JS operand** — documented). String concat on `any` works (`dynAdd`
  dispatches). Full suite stayed green (the guard means zero impact on non-`any` code). **Gaps
  (follow-ups):** inline unbox of an op RESULT (`(a+b) as i32`) — assign to an `: any` var first then
  `as` (same shape as 3.1's inline-cast gap); `typeof x`(any) still resolves at compile time (should
  be runtime `dynTypeof`); unary `-x`/`!x` on `any`; bitwise/shift on `any`; bare `if (anyVar)` needs
  `if (anyVar as bool)`; chained any-arith where an operand is a sub-expression (not a simple var).
- **3.3 — member/index/call on `any` + bare `eval` — ✅ SHIPPED 2026-06-22** (extends `18q`). A guarded
  any-dispatch block near the top of `emitExpr` (fires ONLY when the receiver is a simple `any` var,
  else typed handlers run untouched): `x.foo` → `dynrt_dynMember(x, "foo")`; `x[i]` →
  `dynrt_dynIndexValue(x, boxedIndex)`; `x(args)` → `dynrt_dynCall0/1/2/3(x, …boxed args)`. Library:
  **`dynMember` + `dynIndexValue` are now EXPORTED**, plus new fixed-arity **`dynCall0/1/2/3`** helpers
  (build the args array + `dynApply` as a single expression — wasic can't build an array inline; arity
  > 3 is a gap); all added to the auto-injected import set; caps bytes regenerated (12406). Bare
  **`eval(...)`** → a transpile source pre-pass rewrites `eval(` → `dynrt_dynEval(` (the bundler
  already injected the import + merged on the `eval(` it saw). All results are `any` handles. Proven:
  `obj.x`, `arr[0]`/`arr[ix]` (computed index), `env.sqrt`→`sqrtFn(16)`=4 / `maxFn(3,8)`=8,
  `eval("2 + 3 * 4")`=14. **Gaps (follow-ups):** chained `x.a.b` / `x.a()` (single-level only — use an
  intermediate `: any` var); call arity > 3; member-ASSIGNMENT (`x.foo = …` / `x[i] = …`).
- **3.4 — hybrid `--auto` migration + host fallback — ✅ SHIPPED 2026-06-22 (COMPLETES increment 3 +
  the whole #14 track).** Refined design (avoids a host↔core marshalling gap): `any`-**signature**
  functions stay in the host (marshalling a boxed handle across bindgen is a follow-up), but functions
  with a **typed signature and a DYNAMIC body** (`any`/`eval` internally — which lower to the merged
  dynrt runtime via 3.1–3.3) now compile to the WASM core; their typed signature marshals normally.
  **Try-compile / fall-back-to-host ladder** in `runHybrid` (`src/hybrid.ts`): compile the full core;
  on failure, re-route the dynamic-bodied functions (`parseHybridFile` new `excludeDynamicBody` option
  → keeps `any`/`eval` functions in the host) and recompile the static remainder; if nothing routable
  remains, the runner is host-only. **modc returns (does NOT throw) on a compile abort**, so failure
  is detected by whether the core `.wit` was (re)produced (stale removed first). **Also fixed a real
  bug:** `compileLibTs` (modc) didn't handle EMBEDDED virtual-capability `entry.bytes`/`entry.witText`
  the way `compileWasiTs` does — so the auto-merged `wasmtk:dynrt` failed in the modc core compile
  ("Cannot read imported WASM wasmtk:dynrt"); fixed to mirror `compileWasiTs`. Verified end-to-end:
  fixture `tests/hybrid_fixtures/dynamic_hybrid.ts` (`evalScaled(n: f64): f64` with an `eval`+`any`
  body) routes to WASM → runner prints `evalScaled(8)=50`; `dynamic_fallback_hybrid.ts` (uncompilable
  dynamic body) falls back to host (warning) while the static fn still routes → `plus1(41)=42`; the
  existing `math_hybrid` is unchanged. This realizes the §6 intent — `hybrid --auto`'s dynamic target
  is now the own runtime (wasic+dynrt), not `javyc`. **Follow-ups since shipped (both ✅):**
  any-SIGNATURE host↔core marshalling (the section above) and the fallback refinement (the section
  below — only the FAILING dynamic functions move to host now, not all of them).

**Cross-cutting:** the `any` codegen calls the MERGED dynrt exports (prefixed names from the
`wasmtk:dynrt` merge) — the compiler must emit the right merged symbol. **Heap/no-GC caveat applies**
(§ retirement note below): `any`-heavy / eval-heavy programs inherit the bump-allocator limit. Each
of 3.1–3.4 ships its own regression test (`18q…`/compiler tests) and must keep the full suite green
(output-diff). **Honest risk:** 3.2 (operator routing) + 3.4 (hybrid try/fallback) are the two
highest-risk pieces; 3.1 is foundational and lower-risk.

## #14 follow-up — any-signature host↔core marshalling (SHIPPED 2026-06-22)

Closes the 3.4 gap: a function with an **`any` param or return** can now be called from the host with
**real JS values** (number/string/boolean), not raw handles. Four components:

1. **Track `any` signatures (`src/wasic.ts`):** `FuncParam.isAny` (set in `parseParams` when the
   annotation is `any`) + `FuncDef.isAnyResult` (set in `parseFunctions` from `rawResult === "any"`).
   Also: `emitFunction` now adds **any-PARAMS** to `anyVars` (the 3.1 gap — params lacked `isAny`
   before), so `x as f64` / operators / member-access on an any param work inside the body.
2. **WIT marker:** `generateWit` emits `x: any` / `-> any` (a **wasmtk-extension** WIT type) for any
   params/results instead of `s32`.
3. **Export the marshalling helpers:** `injectDynrtMarshalExports` (module-level helper, called
   post-merge in BOTH `compileWasiTs` and `compileLibTs`) appends `(export "dynNumber" (func
   $dynrt_dynNumber))` … for `dynNumber/dynNumberValue/dynString/dynStrBytes/dynStrLen/dynBool/
   dynToBool/dynTypeof` (+ `cabi_realloc` if not already exported, for boxing an `any` string) when
   `hasAnyExportSignature()` is true. Exporting keeps Binaryen from stripping them.
4. **bindgen marshalling (`src/bindgen.ts`):** `WitType` gains `"any"`; `genLoadModule` emits `_box`
   (JS number→`dynNumber`, boolean→`dynBool`, string→`_writeStr`+`dynString`) and `_unbox` (switch on
   `dynTypeof`: 3→`dynNumberValue`, 4→read `dynStrBytes`+`dynStrLen`+`TextDecoder`, 2→`dynToBool`,
   0→`undefined`, else→opaque handle). `any` params → `_box(arg)`; `any` returns → `_unbox(call)`.

**Verified end-to-end** (`tests/wasm_wasi_bundle/anysig_bundle/`: `anysig_lib.ts` modc lib +
`host.ts`): `identity(42|'hi'|true)` round-trips all three types; `addOne(41)=42` (any-param unbox +
result box); `typeName(42|'x'|true)` → `"number"|"string"|"boolean"` (runtime tag dispatch + string
return); `exclaim('wow')='wow!'` (string concat on an any).

**Objects/arrays — structural marshalling (SHIPPED 2026-06-22, extends this):** objects and arrays as
`any` now cross the boundary as **real, recursively-converted JS objects/arrays** (not opaque
handles). Added dynrt object-enumeration exports `dynObjKeyPtr`/`dynObjKeyLen`/`dynObjValAt` (key data
ptr / key len / value handle by index); `dynrtMarshalExportNames()` now also exports the structural
helpers (`dynTag`/`dynNull`/`dynUndefined`/`dynArray`/`dynArrLen`/`dynArrGet`/`dynPush`/`dynObject`/
`dynObjLen`/`dynObjKeyPtr`/`dynObjKeyLen`/`dynObjValAt`/`dynSet`); the tsbundler auto-import list gained
the container accessors so lib bodies can call them. bindgen's `_box` recurses (Array→`dynArray`+
`dynPush`, object→`dynObject`+`dynSet`, null→`dynNull`, undefined→`dynUndefined`) and `_unbox`
switches on the **RAW `dynTag`** (5=array→build JS array, 6=object→build JS object by enumerating keys,
1=null, plus the primitives). Verified (`anysig_bundle`): `makePoint(3,4)`→`{x:3,y:4}`,
`triple(1,2,3)`→`[1,2,3]`, `sumArr([10,20,30])`→60 (JS array boxed IN), `getX({x:42,y:7})`→42 (JS
object boxed in + member access). **Remaining gaps:** FUNCTIONS as `any` still cross as opaque
handles; boxing a typed VAR into `any` in-body still needs an explicit `dynNumber(...)` (the
non-literal-RHS boxing gap from 3.1); `s64`/`bigint` any not handled; cyclic objects would infinite-loop.

## #14 follow-up — hybrid fallback refinement (per-function) (SHIPPED 2026-06-22)

Refines the 3.4 all-or-nothing fallback (which moved EVERY dynamic-bodied function to the host when
the core failed) to move only the FAILING ones (`src/hybrid.ts` `runHybrid`):

- `parseHybridFile` gains `excludeFns?: Set<string>` (keep specifically-named functions in the host).
- On full-core failure: partition routed functions into **static** (no `any`/`eval`) and **dynamic**;
  **probe each dynamic function** with the static context (`probeCompiles` — compiles `[…statics, d]`
  to a SEPARATE `${base}_probe.*` module that's cleaned up, so it never clobbers the real core);
  collect the ones that fail into `bad`. Re-route only `bad` to the host (`excludeFns: bad`), keeping
  the compilable dynamic functions in the WASM core. The warning names the moved functions.
- **Safety ladders preserved:** if no single culprit is found (e.g. dynamic-calls-dynamic, where each
  fails its static-only probe) → coarsen to all-dynamics-to-host; if the survivors still don't compile
  (a static fn depends on a moved dynamic) → coarsen again; if nothing routable remains → host-only
  runner. So it's strictly ≥ the 3.4 behavior.

**Verified** (`tests/hybrid_fixtures/dynamic_partial_hybrid.ts`: one GOOD dynamic `goodDynamic`
[`eval`+`any`, compiles] + one BAD `badDynamic` [undefined call] + a static `plus1`): only
`badDynamic` is moved to host (warning: "1 dynamic function(s) … : badDynamic"); `goodDynamic` +
`plus1` stay in the WASM core; runner prints `goodDynamic(8)=50` / `plus1(41)=42`. The single-bad
(`dynamic_fallback_hybrid`), all-good (`dynamic_hybrid`), and static (`math_hybrid`) fixtures are
unaffected. **Cost:** one probe-compile per dynamic function (dynamic functions are typically few).
**Gap:** a dynamic function that calls ANOTHER dynamic function is over-rejected to host (its
static-only probe fails) — safe (host runs it), documented.

## #14 — memory / GC track (mark-sweep, built in tested parts) (STARTED 2026-06-22)

Decision (owner 2026-06-22): build a **full mark-sweep GC**, but **in parts that are each tested +
integrated** (same cadence as the rest of #14). **The hard part is ROOT-FINDING:** wasic locals
holding `any` handles aren't distinguishable from plain-i32 locals at runtime, so a precise collector
eventually needs an explicit **shadow-stack** of live handles (a real but bounded redesign, in the
mark phase). Staged plan: **P1 auto-grow** → P2 free-list (`$__free` + reuse) → P3 GC object headers /
cell registry → P4 roots (shadow-stack) + mark → P5 sweep + `collect()` + trigger integration.

**Part 1 — auto-grow `$__malloc` — ✅ SHIPPED 2026-06-22** (test `18r`). `$__malloc` now `memory.grow`s
by `ceil(deficit / 64KiB)` pages when the bump pointer runs past the allocated pages, lifting the
fixed ~2-page limit (that capped deep recursion / long dynamic loops) to WASM's multi-GiB memory
limit. It does NOT free — a truly unbounded loop still exhausts eventually (that's P2–P5) — but it
fixes the immediate symptom: `fib(10)` (≈177 interpreter calls) used to overflow; **`fib(15)` (≈1973
calls) now runs** (`tests/wasm_wasi_bundle/dynrt_eval_bundle/main_gc.ts`).
**CRITICAL gotcha:** auto-grow is emitted **only in executable (WASI) modules**, NOT modc libraries.
A merged library's `$__malloc` is dropped + replaced by the host's during wasmmerge allocator
unification, AND the `memory.grow`/`memory.size` opcodes defeat `detectBumpAllocator` (so the lib's
malloc wouldn't be recognized/dropped) **and break the merge's wabt-ts re-assembly** ("Cannot read
imported WASM"). Gating on `this.mode !== "library"` keeps libraries' malloc simple (merge-safe) while
the surviving executable malloc auto-grows — so merged programs (incl. the dynrt interpreter) still
benefit. (Unrelated bug noticed while testing: a `const x` inside a SINGLE-physical-line nested block
isn't declared as a WAT local → "local $x cannot be resolved"; the test uses a multi-line `check`.)

**Part 2 — free-list allocator — ✅ SHIPPED 2026-06-22** (test `18s`). The allocator can now RECLAIM:
`$__free(ptr, size)` links a block (>= 8 bytes; smaller blocks leak — can't hold the header) into a
new `$__free_list` global, storing `[blockSize@0, nextFree@4]` in the block's own first 8 bytes;
`$__malloc` walks the free list FIRST-FIT before bumping. **No splitting in v1** (returns the whole
block — internal frag is fine). Executable-only (same gating reason as P1: a merged library's malloc
is dropped + replaced by the host's, and the free-list loads/stores/loop would defeat
`detectBumpAllocator` + break the merge). On its own the free list is **dormant** — nothing calls
`$__free` yet (the GC sweep will, in P5). Tested directly via three new wasic intrinsics added for the
GC + its tests: **`__malloc(size)` / `__free(ptr, size)` / `__heapPtr()`** (emitExpr + emitStatement
handlers → `call $__malloc` / `call $__free` / `global.get $__heap_ptr`). Test
(`tests/wasm_wasi_bundle/gc_bundle/freelist.ts`) self-checks (trap-on-failure): a freed 64-byte block
is reused by a later `__malloc(64)` (same ptr, bump cursor unchanged) and by a smaller `__malloc(32)`;
a fresh `__malloc(48)` with an empty list bumps (ptr advances). **Edit gotcha:** the malloc template
shared one `parts.push(\`…\`)` with `$cabi_realloc`; splitting malloc into a mode if/else left
`cabi_realloc` dangling — re-wrap it in its own `parts.push`.

**Part 3 — cell registry — ✅ SHIPPED 2026-06-22** (test `18t`). Every boxed value cell now flows
through `mkCell()` (4-slot) / `mkCell5()` (5-slot user-function), which allocate the cell AND record
its pointer in a registry list `__gc_reg` (the self-managed Set/Map list idiom) — so P4 (mark) / P5
(sweep) can ENUMERATE all allocations. Only value cells are registered; payloads (Float64Array /
Uint8Array / container lists) are reached THROUGH a cell and will be freed by reading its fields.
Exposed `dynGcCellCount()` for testing. The registry append is INLINED into `mkCell` (only the rare
grow path calls listPush) because `mkCell` is the hot allocation site at the DEEPEST interpreter
recursion point, and every extra WAT frame lowers the max depth before V8's call-stack overflows.

**Three traps hit building P3 (all instructive):**
1. **`replace_all` self-recursion.** Routing the 8 `new Int32Array(4)` cell sites through a new helper
   via `replace_all` ALSO rewrote the `new Int32Array(4)` INSIDE the helper's own body → the helper
   called itself → WASM stack overflow on EVERY dynrt program. (The helper was also renamed
   `newCell`→**`mkCell`**; a name starting with `new` was a red herring — wasic parses `newCell()` fine
   — but `mk*` avoids any confusion.)
2. **V8 call-stack, not heap.** `mkCell`'s extra frame tightened the interpreter's max recursion
   (bound by V8's WASM call stack, SEPARATE from the heap limit P1 lifted). Mitigated by inlining the
   registry append; `18p` is fib(8), `18r`'s fib(15) still passes.
3. **The merge mutable-global clobber (the real bug).** `__gc_reg`'s `0` sentinel was being rewritten
   to 131072 by wasmmerge → registry never initialized → heap corruption / OOB at ~3–4k cells. Fixed
   in `src/wasmmerge.ts` (see cmem/compiler-bugs.md "wasmmerge clobbered ALL merged mutable globals").
   This is what unblocked P3 — and `dynGcCellCount()` returning garbage (768) with the registry
   DISABLED was the diagnostic tell.

**Registry overhead caveat (matters for P5):** until the sweep reclaims, the registry is pure overhead
(tracks every cell + the list's doubling leaks old copies, nothing freed). P5's `collect()` is what
makes it pay off — and should also free the registry's own stale doublings (via P2's `__free`).

**Part 4 — roots + mark — ROOT STRATEGY DECIDED (owner 2026-06-22): interpreter SHADOW-STACK.** The
dynrt interpreter will maintain an explicit stack of its live handles (push on bind/alloc, pop on
scope exit); mark traverses from that stack + the env chain. Precise and safe to run mid-interpretation
(reclaims fib-style churn — the real win). It does NOT collect `any` handles sitting in arbitrary
compiled-wasic locals (not enumerable without compiler root-maps) — documented scope, not a bug.
Part 4 is split into **P4a (mark mechanics, explicit roots)** and **P4b (wire the shadow-stack)**.

**Part 4a — mark phase — ✅ SHIPPED 2026-06-22** (test `18u`). From a root handle, `gcMark` recursively
marks every reachable cell. **Mark bit = bit 8 (256) of slot-0 tag** — uniform across 4-slot and
5-slot cells, NO extra storage; real tag = `slot0 & 255`. The bit doubles as the visited set so cycles
terminate. Only CELLS are followed: array/object element handles (the list at slot a) and a
user-function's body/params/defEnv (slots 2/3/4 when slot1 = -1); number/string payloads + object key
byte-pairs are owned non-cell allocations (the sweep frees them via the owning cell). Exports
`dynGcMarkClear` / `dynGcMark(root)` / `dynGcMarkedCount`. **Key invariant:** the rest of the runtime
never sees the mark bit because a full collect() clears every survivor's mark before returning, so
between collections all tags are clean and `dynTag`/`dynTypeof` need no masking (only mark/sweep mask).
Test verifies mark reaches exactly the live set across nesting (`obj → arr → 3 numbers` = 5) and leaves
orphans unmarked. **Caveat:** `gcMark` is recursive — a very deep object graph could overflow the WAT
stack; an explicit work-list is a later hardening if needed. **Next: P4b** (shadow-stack) then **P5**
(sweep: free unmarked cells + their payloads via P2's `__free`, then clear marks; + trigger policy).

**Part 4b — interpreter shadow-stack (roots) — ✅ SHIPPED 2026-06-23** (test `18v`). A precise
collector must know every live handle; wasic locals holding `any` aren't enumerable, but the
interpreter's live state is exactly its chain of active scopes. New explicit root stack `__gc_roots`:
`dynRun` `gcPushRoot(env)` on entry / `gcPopRoot()` on its single exit, so during a nested call the
stack holds `[driver-env, scope1, scope2, …]` — every frame that will resume. `dynGcMarkRoots()`
clears marks then marks from every root. Exports `dynGcPushRoot`/`dynGcPopRoot` (host registers its
OWN top-level roots — needed by P5), `dynGcRootCount`, `dynGcMarkRoots`.

**Critical companion fix to `gcMark`:** an ENV is a tag-6 object whose PARENT scope link lives in
**slot 2** (`en[2]`; regular objects keep 0 there). P4a's `gcMark` did NOT follow slot 2, so marking
an inner scope missed all enclosing scopes. Now `gcMark` follows `n[2]` for tag-6 cells (harmless
no-op for regular objects) — so marking one scope (or a closure's defining env) keeps the whole
lexical chain + captured vars alive. Also guarded the `-1` "no env" sentinel (`evalEnv`/top-level
parent) alongside `0` so it's never dereferenced.

Test verifies: push/pop **balance** (root count back to 0 after a nested `f(4)` run); **mark-from-
roots** reaches a driver-pushed `[1,2,3]` graph (exactly 4 cells); and marking a returned **closure**
traverses tag-7 → defEnv → bound values + slot-2 parent (≥5 cells). **Stack-depth note:** the
push/pop calls return before `runStatements`, so they're NOT on the WAT stack during the deep
recursion — `18r`'s fib(15) still passes. **Next: P5** — `collect()` = `dynGcMarkRoots()` → sweep
(free every unmarked registered cell + its payloads via P2's `__free`, compact the registry) → marks
already cleared on survivors; + a trigger policy (collect when the registry passes a threshold).

**Part 5a — mark-sweep collect (cells) — ✅ SHIPPED 2026-06-23** (test `18w`). The capstone:
`dynGcCollect()` = `dynGcMarkRoots()` → sweep the registry → reclaim every UNMARKED cell and compact
the registry in place; survivors keep their slot, mark cleared. Returns the count reclaimed.

**Allocator decision — dynrt owns a recycling free list (does NOT reuse the wasic `$__free`).** The
clean way to feed P2's `$__free` would need wasmmerge to UNIFY a `$__free_list` global across the
merge (like `$__heap_ptr`) — extra surgery on the delicate merge, AND low memory (0–259, iov+scratch)
has no safe fixed address for a shared head. Instead dynrt has its OWN free list: `dynAlloc(size)`
hands out `8 + n*elemSize` blocks, REUSING ones `dynFreeBlock` returned (first-fit, head `__dyn_free`)
before bumping via the `__malloc` intrinsic; `mkCell`/`mkCell5` now allocate through it. So the GC
reclaims into the same pool it allocates from, fully inside the lib — no wasmmerge/wasic change. A
freed block stores `[size, next]` in its first two view slots (base+8/+12) so it must be ≥16 bytes
(cells are 24/28); **reused blocks are ZEROED** because constructors rely on unset slots being 0 (a
plain object's slot-2 parent link especially — a stale value there would make `gcMark` follow a bogus
parent). Sizes are exact from the wasic formula: 4-slot cell **24**, 5-slot **28**, number payload
**16**, string **8+len**, list **8+(cap+2)*4**.

`dynGcMarkRoots` was extended to also mark the interpreter "registers" (`evalEnv` / `lastValue` /
`evalReturnVal`) so a collection is safe to run at any point / right after a `dynRun`. **Consequence
(broke + fixed `18v`):** mark-from-roots now also marks those registers, so a test asserting an EXACT
marked count from `dynGcMarkRoots` must run with clean interpreter state (before any `dynRun`, when
`evalEnv=-1` / regs=0) — `18v`'s driver-root case was reordered to run first.

Test verifies: collect reclaims the garbage, the registry shrinks by exactly `freed`, the freed cells
land on the recycle list (`dynGcFreeCount`), a live value in a rooted env survives intact, and later
allocations REUSE reclaimed blocks (free count drops). **P5b (remaining):** reclaim the PAYLOADS too
(route the constructors' Float64Array/Uint8Array/list allocations through `dynAlloc`, free them in the
sweep) — payloads are the bulk, so this is what actually bounds memory; plus a TRIGGER policy
(auto-collect at interpreter statement boundaries past a registry threshold) so deep recursion / long
loops collect without an explicit call.

**Part 5b — payload reclamation + auto-collect trigger — ✅ SHIPPED 2026-06-23. THE GC TRACK IS
COMPLETE.** (test `18x`). Two pieces:

(1) **Payloads reclaimed too.** The constructors' `Float64Array(1)` / `Uint8Array(len)` / list
allocations now flow through `dynAlloc` (the same `... as unknown as TypedArray` view — base+8 data,
no header length is ever read), and the sweep frees each garbage cell's payloads by tag (`gcFreePayload`
+ `freeList`): number→16, string→8+len, array→element list, object→values list + keys list + each key
Uint8Array. Referenced CELLS are not freed here (registered + swept on their own). Payloads are ~⅔ of
dynrt's memory, so this is what actually bounds memory.

(2) **Auto-collect trigger.** `maybeCollect()` runs at every interpreter statement boundary in
`runStatements` (a safe point: the previous statement is complete, the next hasn't begun); it collects
once the registry passes `__gc_threshold`, then raises the threshold to 2× the surviving live set (min
8192) — the standard grow-to-amortize heuristic.

**The hard correctness piece — root mid-expression temporaries.** A statement boundary is safe ONLY
for values already bound to a scope; a recursive-descent evaluator also holds **intermediate** operands
(`left` in `a OP b`, the callee + partial args in a call) that live across a right-operand parse, and
that parse can run a user function whose nested statement boundary triggers a collect. So
`fib(n-1) + fib(n-2)` would let the nested `fib(n-2)` free the pending `fib(n-1)` → corruption (seen as
`float unrepresentable in integer range` when the garbage NaN hit `$__f64_to_str`). Fix: the evaluator
now `gcPushRoot`/`gcPopRoot` the accumulated operand across each right-operand parse at EVERY binary
level (`parseMul`/`parseAdd`/`parseRel`/`parseEq`/`parseAnd`/`parseOr`/ternary) and the callee + args
array across a call. **Gotcha hit:** wrapping `parseAnd`/`parseOr` accidentally dropped the
short-circuit `evalLive = saved;` restore → `18n`'s `inc()` short-circuit test failed; restored.

**Proof (`18x`):** a 10000-iteration interpreter loop (`s = s + (i+1)`) allocates ~30000 cells but runs
in BOUNDED memory (auto-collect reclaims each iteration's garbage); the sum is correct (50005000 — no
live value wrongly collected) and a final explicit collect leaves only **5** live cells. `18r`'s fib(15)
also passes with auto-collect firing during the recursion.

**GC track summary (P1–P5b, all shipped 2026-06-22/23):** auto-grow heap → free-list intrinsic → cell
registry → mark (tag-bit-8, env-parent slot-2) → shadow-stack roots → collect (mark-sweep, dynrt-owned
recycling `dynAlloc`/`dynFreeBlock`) → payload reclamation + auto-collect (intermediate-rooted). dynrt
now runs long-lived dynamic code in bounded memory.

**GC polish — ✅ SHIPPED 2026-06-23 (after P5b):** the two memory leaks noted at P5b are FIXED.
(a) **<16-byte blocks** (short strings / object keys — Uint8Array < 16B) used to leak because the
free-list header needs 16 bytes; now both `dynAlloc` AND `dynFreeBlock` round size UP to
`GC_MIN_BLOCK = 16`, so EVERY block is recyclable (a few wasted bytes, no leak — this was the only
*growing* leak). (b) **registry doubling** — `mkCell`'s grow branch now `dynFreeBlock`s the old
backing array after `listPush` copies into the larger one (one-time recovery; the registry stops
growing at steady state). (c) **Free-list SPLITTING — ✅ SHIPPED 2026-06-23** (test `18y`): the real
"coalescing" gap turned out to be the opposite — `dynAlloc` reused an oversized block without
splitting, so when a big block served a small request and was later freed at its smaller logical size,
the leftover bytes were LOST (a slow size-mismatch leak). Now `dynAlloc` carves the remainder (≥16B)
off the chosen block as its own free block at `cur + size`, so nothing is lost. (Number-heavy code
already did exact reuse via first-fit and never splits; this only bit mixed-size workloads.) Verified
with a mixed-size build-large-array / drop / collect cycle that forces the split path — correctness
holds and memory is fully reclaimed (0 live cells). No-regression verified (full dynrt set green).

**(d) Adjacency-COALESCING via a HYBRID allocator — ✅ SHIPPED 2026-06-23 (test `18z`).** First
attempt (address-sorted coalesce-ON-FREE) hung mid-allocation — a free-list CYCLE under split-churn +
registry-array-free (NOT a double-free; a `cur===ptr` guard didn't fix it → a coalescing mis-link
caused by **re-entrancy**: `dynAlloc` splits and frees the remainder *mid-allocation*, interleaving
with the sorted-list pointers). Reverted, then RE-DONE as a three-tier hybrid that isolates the
fragile part:
  • **Segregated buckets** for the dominant exact sizes (16 number-payload / 24 4-cell / 28 5-cell /
    32 smallest list) — pure LIFO push/pop, O(1), structurally CAN'T cycle. Number-heavy code lives
    here and pays nothing; also gives perfect exact reuse (kills the residual sub-16 leftover loss).
  • **Tier 2** (`__dyn_free`) general pool for other sizes — LIFO first-fit + split.
  • **Batch `defragFull`** — the ONLY coalescing site: a SNAPSHOT pass (gather all lists → address
    merge-sort (iterative merge, O(log n) recursion) → merge adjacent → redistribute), so it never
    interleaves with allocation → the re-entrancy bug is impossible. Two triggers: PROACTIVE adaptive
    node threshold (`__free_nodes > __defrag_threshold`, reset ×2 after → amortized O(1)/free) and
    ON-DEMAND (`__free_bytes >= request` before bumping — recover freed runs for a large request only
    when it could plausibly help). Counters `__free_nodes`/`__free_bytes` drive both.
Verified with a `dynGcCheckHeap()` integrity hook (no cycle / valid sizes / counters consistent) run
after every phase of the exact stress that hung the first attempt — all clean, memory fully reclaimed.
**Balance achieved:** hot path O(1) bucket churn (never defrags), Tier-2 + large requests get
coalescing memory-efficiency, defrag amortized + self-gated. **wasic gotchas hit:** an inline
`(cur as Int32Array)[1]` index isn't supported (bind the view first); a `let` global initialized from
a `const` identifier is mis-detected as immutable (init `__defrag_threshold` to a literal `512`); a
ternary assigned to a global isn't supported (use `if`). Tunables (`GC_DEFRAG_BASE=512`, bucket sizes)
are named constants. The root-stack's own (tiny) doublings are still left (negligible).

**Minor wasic gap surfaced (worked around in the split test):** `f64call() | 0` (truncating a
function call that returns f64, in an i32 context) miscompiles — `i32.add[1] expected i32, found call
of type f64` — the `| 0` truncation doesn't fire on a call result. Worked around by comparing the f64
elements directly. Logged in compiler-bugs.md.

**Remaining #14 odds-and-ends (NOT GC, won't fix soon):** **functions-as-`any`** still cross the host
boundary as opaque handles — and this is fundamental, not a quick fix: unlike numbers/strings/objects
(which bindgen deep-COPIES into JS values), a function is code, so it must stay a dynrt handle; but a
host-held handle CAN'T be rooted across collections (the documented root-model limit — the GC only
sees interpreter roots, not host locals), so a host-held function proxy would be unsafe the moment any
later core call triggers a collect. Shipping it would be shipping a use-after-free. Deferred until/if
there's a host-pinning mechanism (e.g. an explicit handle table the GC also roots).

## Functions-as-`any` — Phase 1 (pin table + core→host proxy) ✅ SHIPPED 2026-06-23

The pin table + bindgen proxy are DONE (tests `18za` + bindgen `testGenBindingsAnyFunction`):

**Pin table (dynrt lib).** `__gc_pins` slot-list; `dynGcMarkRoots` also marks every non-zero pin.
Exports `dynGcPin(h) → slot` (reuses a released 0-slot, else appends) / `dynGcUnpin(slot)`. The list is
allocated via listNew (not mkCell) so it's never swept. Non-moving GC ⇒ pinning only needs to keep the
handle marked. Test `18za`: create a function via the interpreter, pin it, make it GC-unreachable
except via the pin, collect under garbage, then call it via `dynApply` — correct result (42) proves it
survived (integrity-checked).

**bindgen `_unbox` tag-7 proxy.** On `dynTag(h)===7`, `_dynGcPin(h)` then return a JS proxy
`(...args) => _unbox(_dynApply(h, argsArr(args.map(_box))))` with a `.release()` (→ `_dynGcUnpin`) and a
`FinalizationRegistry` backstop. Added `dynApply`/`dynGcPin`/`dynGcUnpin` to `dynrtMarshalExportNames`
(wasic.ts) so they're exported post-merge. bindgen 119/119 (the proxy generates + type-checks; existing
`any` marshalling unaffected).

**Function PRODUCER + full END-TO-END — ✅ SHIPPED 2026-06-23.** Typed wasic source can now create a
function value: **`Function(params, body)`** (and `new Function(...)`) lowers — via a wasic.ts pre-pass
(`/\b(?:new\s+)?Function\s*\(/` → `dynrt_dynMakeFn(`) — to a new dynrt export `dynMakeFn(paramNames,
body)` (splits the comma-separated names into a value-model array, builds a user function over a fresh
env). The tsbundler trigger gained `usesFunction` + `dynMakeFn` in the auto-import set. **Full
end-to-end verified** (bindgen `testIntegrationFnAny` + the `anysig_bundle` host): a modc lib
`getDoubler(): any { return Function("x", "return x * 2;"); }` → bindgen → host calls
`m.getDoubler()(21)` → **42** (the proxy boxes the arg, calls `dynApply`, unboxes the result; the
handle is pinned). bindgen 119/119.
**Gotcha (real bug hit + fixed):** the `usesFunction` trigger matched `Function(` inside dynrt's OWN
doc-comment → the dynrt lib auto-merged ITSELF (circular, broke every dynrt test at the wasic step).
Fixed by NOT sniffing triggers over comments/strings.
**Post-publish "look for code issues" audit (2026-06-24) — 3 latent correctness bugs fixed; full detail
in compiler-bugs.md (bindgen 119→122, suite 336/336):** (1) the bindgen tag-7 proxy registered with a
`FinalizationRegistry` WITHOUT an unregister token, so `release()` + later GC double-unpinned the slot →
if reused by a newer pin in between, the live handle was wrongly unpinned (ABA → use-after-free) — fixed
with an idempotent `_released` guard + `unregister(_fn)` + a 3rd-arg unregister token. (2) the tsbundler
comment-only strip ate a `//` inside a string literal (URL) and the rest of that line, hiding a real
trigger after it → replaced with a single-pass `stripCommentsAndStrings()` scanner that tracks comment
AND string state. (3) the wasic `eval(`/`Function(` source pre-passes rewrote inside string literals +
comments (a printed `"…Function()…"` came out `"…dynrt_dynMakeFn()…"`) → new code-only scanner
`rewriteOutsideStringsAndComments()`; regression `18zb`.
**Phase 2 (host→core, a JS function INTO the core) — ✅ SHIPPED 2026-06-24.** A JS function passed into
the core as `any` is registered in a bindgen host-fn table; `_box` wraps the index via a new dynrt export
`dynMakeHostFn(index)` → a tag-7 cell with marker slot[1] = -2, slot[2] = index. `dynApply` routes such a
value back to the host through a single `env.__host_call` import (declared in the dynrt lib via Phase 40
`declare const __host: { call(...) }`). bindgen's loader implements `env.__host_call(fnIdx, argsArr)`:
look up the JS fn, unbox the args array → JS args, invoke, box the result. The import↔impl chicken-and-egg
(import needed at instantiate, impl needs the exports) is solved with a function-scoped `_hostCallImpl`
holder assigned after `_box`/`_unbox` exist, forward-referenced by `env.__host_call`. Verified end-to-end
(bindgen `testIntegrationHostFn`, fixture `hostfn_50`): `m.applyTwice(n=>n+1, 10)` → **12** (core calls the
host fn twice), `m.combine((a,b)=>a*b, 6, 7)` → **42** (two args). Surfaced + FIXED a real wasmmerge bug
(non-WASI imports were spliced after function definitions → malformed module / OOB; see compiler-bugs.md).
**With Phase 2, functions-as-`any` is bidirectional and #14 is COMPLETE with no deferred pieces.**
`dynMakeHostFn` added to the marshal-export set; bindgen 131/131.

## Functions-as-`any` host↔core marshalling — SCOPE (drafted 2026-06-23)

**Goal:** let a dynrt function value (tag 7) cross the host boundary as a real callable. Two directions,
very different difficulty:

**Why it's not like other values.** Numbers/strings/objects/arrays are bindgen-DEEP-COPIED into JS
values, so the host holds independent data. A function is CODE — it must stay a dynrt HANDLE. But the
GC only roots interpreter state (the shadow-stack), not host-held handles, so a host-held function
proxy is collectible the moment any later core call auto-collects → use-after-free. **The enabler is a
host-PIN table.**

**Pin table (the shared prerequisite).** dynrt's GC is NON-MOVING (sweep frees, never relocates), so a
pinned handle's address stays valid — pinning just needs to keep it MARKED. Add `__gc_pins` (a
slot list of pinned handles, 0 = empty); `dynGcMarkRoots` also `gcMark`s every non-zero pin. Exports:
`dynGcPin(h) → slot` (store h in a free/appended slot, return index), `dynGcUnpin(slot)` (clear it).
~30 lines + a test (pin → collect → survives; unpin → collect → reclaimed).

**Phase 1 — core→host (the 80% case; MODERATE effort).** A function RETURNED from a core call becomes
a JS function. bindgen `_unbox`, on `dynTag(h)===7`: `pin = dynGcPin(h)`; return a JS proxy
`(...args) => _unbox(dynApply(h, buildArgsArr(args.map(_box))))`, with a `.release()` that
`dynGcUnpin(pin)`s (+ a FinalizationRegistry backstop, since FR timing is non-deterministic). Needs
`dynTag`/`dynArray`/`dynPush`/`dynApply`/`dynGcPin`/`dynGcUnpin` in the marshal-export set (most already
exported). ~25 lines bindgen + a fixture (core returns a closure; host calls it). **Caveat:** pinned
functions LEAK until released — host responsibility (documented), FR backstop helps.

**Phase 2 — host→core (HARDER; defer).** A JS function passed INTO a core call must let the core call
BACK into JS. Needs: a "foreign function" dynrt value (new tag-7 marker holding a callback id); an
imported `env.__hostcall(id, argsArr) → resultHandle` (Phase-40-style import); the host maintains a JS
callback registry and provides `__hostcall` (look up id, `_unbox` the args, call the JS fn, `_box` the
result); and `dynApply` dispatches a foreign-function value to `__hostcall`. Bigger (import wiring +
dispatch + arg/return marshalling across the boundary mid-interpretation). Reuses the pin table for the
result/args lifetime.

**Recommended order:** pin table → Phase 1 (core→host) → ship + document the leak caveat → Phase 2 later
if needed. Phase 1 alone covers returning closures/callbacks from a core, which is the common ask.

## Does 14.3 let us drop `javyc`? — retirement criteria (decided framing 2026-06-22)

**No — not on 14.3 alone.** 14.3 is *wiring, not language growth*: it lowers `any` → a boxed handle,
auto-merges `dynrt`, and repoints `hybrid --auto`'s dynamic route from `javyc` → `dynrt`. It changes
*which engine dynamic code lands on*; it does not expand what the interpreter understands. `dynrt` is a
**v1 SUBSET interpreter**; `javyc`/QuickJS is a **full spec-compliant engine with a stdlib + GC**.

So after 14.3, **keep `javyc` as the FALLBACK** (route the covered subset to `dynrt`, everything else
to `javyc`) — matches the §7-#7 intent without over-claiming. The gap `javyc` still covers:

- **Language:** arrow fns, function *expressions*, `for`/`for-of`/`for-in`, `switch`, `try/catch` in
  eval, destructuring, spread, template literals, classes, generators, `async`/`await`, object/array
  **literals in eval source**, member-assignment, real block scoping + write-through assignment.
- **Stdlib / semantics:** prototype chains, `this`, `Array`/`String`/`Object`/`Map`/`Set`/`JSON`/
  `RegExp` *as dynamic objects with methods*, `Symbol`.
- **Runtime:** ~~no GC~~ — **GC gap CLOSED 2026-06-23** (the #14 mark-sweep GC P1–P5b + hybrid
  recycling allocator: long-running / deep-recursion dynamic code now runs in bounded memory). This was
  one of the three retirement gaps; the **Language** and **Stdlib/semantics** gaps above remain open.

**Phase 2 (host→core callbacks) does NOT change this answer** — it is marshalling plumbing (passing a JS
function INTO the core via an imported `__hostcall`), the reverse direction of the functions-as-`any`
already shipped in v1.9.0. Like 14.3 it is *wiring, not language growth*: it does not expand what the
interpreter understands, so it does not retire `javyc`.

**`javyc` is removable only when EITHER:** (1) `dynrt` grows to near-language-completeness + a dynamic
stdlib (a large multi-increment track — "2e language", "2f dynamic stdlib"; the "2g GC" piece is now
DONE); OR (2) the uncovered remainder is **declared out of scope** (the brief's "route (a)") and `javyc`
dropped by policy rather than coverage. Until one of those, the default flips to `dynrt` but `javyc`
stays as the safety net.
- **3 — wasic `any` + auto-merge:** add an `any` type to wasic that lowers to a boxed-value handle;
  auto-merge the runtime when `any`/dynamic features are used; migrate `hybrid --auto`'s dynamic
  routing target off `javyc` onto the own-runtime.

---

## #14 own dynamic runtime — FINALIZED 2026-06-24 (shipped in v1.9.0)

The #14 track — **wasmtk's own dynamic runtime** — is **COMPLETE** as the arc scoped in §6/§7-#7:
value model (1) → virtual import + tree-shake (1b) → recursive-descent interpreter `eval`/`new
Function` (2a–2d.2) → wasic `any` type + auto-merge + operators + member/index/call + hybrid `--auto`
migration (3.1–3.4) → host↔core marshalling of all value kinds incl. **functions** → bounded-memory
**mark-sweep GC** (P1–P5b) + **hybrid recycling allocator** → **functions-as-`any`** producer
(`Function(params,body)`) + pinned host proxy, end-to-end (`getDoubler()(21)=42`). Published v1.9.0.

**The ONE deferred #14 follow-up:** **Phase 2 — host→core callbacks** (pass a JS function INTO the core
via an imported `__hostcall`; the reverse of the core→host functions-as-`any` already shipped). It is
marshalling plumbing, independent of language coverage, and does NOT retire `javyc`.

`dynrt` is now the **primary** dynamic engine; `javyc` is the **fallback**. Retiring `javyc` from the
codebase is a SEPARATE, larger track scoped below.

## javyc retirement — scoped task breakdown (2026-06-24)

**Ground truth (verified 2026-06-24):**
- `src/javyc.ts` (178 lines) is a **thin wrapper around the external `Javy` CLI** (which embeds
  QuickJS) — `ensureJavy`/`getJavyInstallPath`/`detectJavyProvider`/`compileJavy`. It is NOT a
  hand-written engine; it shells out to a downloaded binary.
- **Only wiring left:** the standalone **`wasmtk javyc <file>`** command (`main.ts case "javyc"`, help
  text, `deno.json` `./javyc` export) + its own runner `tests/wasi_javy_tests.ts`. **`hybrid --auto`
  does NOT use `javyc`** — its dynamic route is `dynrt`, fallback is the HOST (keep-as-TS), not Javy.
  So `javyc` is an *alternative full-JS→WASM compiler command*, not an internal fallback.
- **dynrt interpreter coverage today** (`dynrt_lib_modc.ts`): full expression grammar
  (`parsePrimary`→`parsePostfix`(member/index/call)→`parseUnary`→Mul/Add/Rel/Eq/And/Or→ternary);
  statements `let`/`const`/`var`, `if`/`else`, `while`, `function` decls, `return`, assignment,
  expression statements. **That is the whole grammar it parses.**

**Two routes to retire `javyc` — ROUTE A DECIDED (owner, 2026-06-24):**
- **✅ Route A — coverage (CHOSEN):** grow `dynrt` (the 2e/2f increments below) until a "compile the
  whole program as dynamic" mode covers what `wasmtk javyc` users need, then remove `javyc`. Large,
  multi-increment — keeps full-JS capability with NO external binary dependency.
- ~~Route B — policy drop~~ (not chosen): would have declared arbitrary-full-JS→WASM out of scope and
  dropped `wasmtk javyc` + the Javy dependency in one small PR. Rejected — the owner wants to keep the
  full-JS capability, just without the external Javy/QuickJS binary.

**Recommended build order (land + full-suite-verify each before the next, one increment per session like
the #13/#14 cadence; each ships a `18*` test, output-diff green):**
1. **2e.1 control flow** — **COMPLETE 2026-06-24** (test `18zc`). 2e.1a: C-style `for`, `for…of`,
   `do…while`, `break`/`continue`, `++`/`--`/`+=`/`-=`/`*=`/`/=` (new `evalBroke`/`evalContinued` signals
   that loops clear; built on the `runWhile` cursor-reset model). 2e.1b leftovers: **`for-in`** (binds
   the key string via a new `dynObjKeyVal` that copies the raw key bytes into a tag-4 string box) and
   **`switch`** (two-pass: DEAD scan the labels to find the matching `case`'s body-start — or `default`'s
   — then execute LIVE with FALL-THROUGH until `break`/`return`/`}`; `break` exits the switch only).
   **Lessons:** (a) the wasic/modc subset rejects a brace-LESS `if (c) stmt; else …` (orphans the `else`)
   — fully brace every chain; (b) a driver's `.wasm` import AND every `checkRun(...)` call must be
   SINGLE-LINE (wasic's import + statement detectors are line-based — add `// deno-fmt-ignore-file` so
   fmt doesn't wrap long lines); (c) **`dynStrictEq`/`dynLt`/… return a RAW i32 (1/0), NOT a value box**
   — use the result directly in an `=== 1` test; do NOT wrap in `dynToBool` (that treats `1` as a cell
   pointer → OOB). The interpreter's own `parseEq` wraps with `dynBool(...)` only to make an `any` value.
2. **2e.2 literals** — **SHIPPED 2026-06-24** (test `18zd`): array `[…]`, object `{…}` (with "quoted"
   and shorthand `{x}` keys), and template `` `…${expr}…` `` literals, all in `parsePrimary`. Templates
   coerce `${expr}` via `dynAdd` (JS `+` → string when either side is a string; uses `stringForm`). Also
   unlocks **`for…of` over an inline array literal** (the 2e.1 deferred case). v1 gaps: template TEXT is
   sliced raw (no `\n`/escape processing yet); object-literal `{` is an object only at EXPRESSION
   position (statement-level `{` stays a block, JS-consistent). Member ASSIGNMENT (`o.x = v`) is still
   2e.4.
3. **2e.4 assignment forms** (compound/`++`/member-assign/destructuring).
4. **2e.3 functions** — **SHIPPED 2026-06-24** (test `18ze`): anonymous `function (p) { … }` expressions
   and arrow functions `(p) => …` / `p => …` / `() => …` (block or expression body) in `parsePrimary`,
   building user-function VALUES that close over the current env — higher-order fns + closures + nested
   arrows all work. Extracted `parseParams`/`parseBlockBody` helpers (shared with `runFuncDecl`); arrow
   bodies: a block → its inner source, an expression → the expr SOURCE captured by dead-parsing to find
   its extent (dynRun returns the last expression value, so no `return` needed); `isArrowAhead` lookahead
   disambiguates `(…)=>` from a parenthesized expr. **Fixed 3 bugs:** (a) wasic `parseArrowFunctions`
   matched `const NAME = (` inside STRING LITERALS (a driver's eval-source string `"const f=(a,b)=>…"`
   was mis-detected as a real arrow → mangled source) — added string-state tracking to the pre-match
   scan; (b) wasic `substituteOneArrow` used `line.indexOf("=>")` (string-blind) — added
   `firstCodeArrowIdx`; (c) dynrt `runStatement` treated `x => …` as the assignment `x = …` (its `=`
   check didn't exclude `=>`) — added `peek2 !== '>'`. **2e.5 operators**, **2e.6 try/catch**, **2e.7
   scoping** remain.
5. **2f.1 prototype + `this`** (object-model upgrade) → unlocks **2e.8 classes**.
6. **2f.2–2f.9 stdlib** — do the BRIDGES first (2f.5 JSON, 2f.6 Map/Set, 2f.7 RegExp reuse the existing
   capability libs → cheap), then Array/String/Object/Math methods.
7. **2e.9 generators**, then **2e.10 async/await** (hardest — needs a microtask loop; ties to #13).
8. **2h removal** — the full-dynamic-compile entry + the Javy-parity conformance gate + delete
   `src/javyc.ts` & wiring.

The **2g GC** prerequisite is **already DONE**. Route A then = **2e (language) + 2f (stdlib) + 2h
(removal)**:

### 2e — interpreter language completeness (extend `dynRun`/`parseExpr` in the dynrt lib)
Each increment mirrors the existing `runWhile`/`runIf`/`parsePrimary` pattern, ships a `18*` test, keeps
the suite green (output-diff):
- **2e.1 control flow:** `for` (C-style), `for-of`, `for-in`, `do-while`, `switch`, `break`/`continue`
  (+ labels).
- **2e.2 literals in source:** object literals `{k:v}`, array literals `[…]`, template literals.
- **2e.3 function forms:** arrow functions, function *expressions*, default/rest params.
- **2e.4 assignment forms:** compound (`+=`…), `++`/`--`, member/index assignment (`x.p=v`/`x[i]=v`),
  destructuring assignment.
- **2e.5 operators:** `typeof`/`instanceof`/`in`, `?.`, `??`, spread/rest, comma (ternary already done).
- **2e.6 error handling:** `try`/`catch`/`finally`, `throw`.
- **2e.7 scoping:** real lexical block scope for `let`/`const`, `var` hoisting.
- **2e.8 classes:** class decl/expr, methods, fields, `this`, `extends`/`super` (needs the 2f.1 object
  model).
- **2e.9 generators + iterators** (`function*`/`yield`, `Symbol.iterator`).
- **2e.10 async/await in dynamic source** (needs a microtask loop — heaviest; ties to #13 async).

### 2f — dynamic stdlib + object semantics
- **2f.1 prototype chain + `this` binding** — the object-model upgrade (method dispatch via prototype);
  gates 2e.8.
- **2f.2–2f.4** built-ins as dynamic objects with methods: `Array` (push/map/filter/reduce/…), `String`,
  `Object` (keys/values/entries/assign), `Number`, `Math`.
- **2f.5 `JSON.parse`/`stringify`** — can BRIDGE the existing JSON capability lib.
- **2f.6 `Map`/`Set`/`WeakMap`/`WeakSet`** — can BRIDGE the existing Set/Map capability libs.
- **2f.7 `RegExp`** dynamic objects — can BRIDGE the existing RegExp capability lib.
- **2f.8 `Date`/`Symbol`/`BigInt`/`Promise`** (dynamic), **2f.9 globals** (`parseInt`/`parseFloat`/…).

### 2h — removal (the actual retirement; the GATE)
- **2h.1** add a "full dynamic compile" entry — a wasmtk mode that routes an ENTIRE TS/JS file through
  `dynrt` (the `javyc` replacement). Decide surface: repoint `wasmtk javyc` to the dynrt backend, or a
  new flag.
- **2h.2 conformance corpus = the gate:** run `tests/wasi_javy_tests.ts`'s programs (+ a broader JS
  corpus) through the dynrt path and require **output parity** before removal.
- **2h.3** flip/deprecate `wasmtk javyc`; **drop the external Javy binary dependency**
  (`ensureJavy`/download/install).
- **2h.4** delete `src/javyc.ts`, the `case "javyc"`, `deno.json` `./javyc`, the Javy asset code; retire
  `tests/wasi_javy_tests.ts`; update CLAUDE.md / README / cmem.

**Effort:** 2e is ~10 interpreter increments, 2f is ~9 (several BRIDGE existing capability libs, cheaper),
2h is the cutover. Comparable in size to the #13 async track or the whole #14 interpreter arc. **2f
async (`2e.10`) + generators (`2e.9`) are the hardest**; everything else is incremental parser/stdlib
growth on the proven dynrt scaffolding. **Recommendation:** get the Route A/B decision first — if the
owner is willing to scope full-JS compile out, Route B retires `javyc` in a single small PR
(`2h.3`/`2h.4` only) without any 2e/2f work.
