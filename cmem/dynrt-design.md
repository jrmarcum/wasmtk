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
- **2d — statements + control flow + `new Function`** (next; a callable from a body string).
  This is where the **`rtcore` extraction + hand-WAT** decision (authoring §3) is most likely
  revisited, if the subset hits a wall.
- **3 — wasic `any` + auto-merge:** add an `any` type to wasic that lowers to a boxed-value handle;
  auto-merge the runtime when `any`/dynamic features are used; migrate `hybrid --auto`'s dynamic
  routing target off `javyc` onto the own-runtime.
