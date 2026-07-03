# Load-bearing design decisions

Invariants and codegen rules that are easy to break in a refactor and must NOT be silently
reverted. The exhaustive list (with line numbers) is in the legacy `CLAUDE.md`; this is the
high-value subset.

## Scanners / parsing correctness

- **Bracket/paren/operator scanners MUST skip string & template literals.** `findBinaryOp` and the
  `parseFunctions` multi-line array-literal body-joiner count `()`/`[]`/`{}` for depth; without masking
  literal content, a literal containing `]` `)` `}` `[` `(` `{` corrupts depth — e.g. `s + "]"` failed
  to find the top-level `+` (string concat → empty), and `let s = "["` looked like an unclosed array
  (the next statement got joined onto it). Use module-level `buildStringLiteralMask(s)` (marks every
  index inside a `"`/`'`/`` ` `` literal, escape-aware) and `netSquareBracketDepth(s)`. When adding or
  refactoring ANY depth/operator scanner over user expressions, mask literals first. (Known still-latent:
  the single-line-body `splitStmts` `;`-splitter has the same gap — fix if it ever surfaces.)
- **The test runner compares OUTPUT, not just exit codes (2026-06-07).** See testing.md. A codegen
  change can compile + run (exit 0) yet emit wrong output; the hardened `wasi_tests.ts` catches this.
  Do NOT add `// @allow-output-diff` to silence a real mismatch — it's only for genuine wasic-vs-native
  semantic divergences (float precision, zero-sentinel defaults).

## Numeric / codegen correctness

- **`Math.round` = `floor(x + 0.5)`**, NOT `f64.nearest` (which is banker's rounding and gives
  `round(2.5)=2`). Both `wasic.ts` (F64_UNARY special case) and `console_log.ts` must agree.
- **mathlib is being converted to CORRECTLY-ROUNDED double-double, function by function** (`src/wasm/mathlib.wat`, 2026-07-01, "full CR sweep"). DONE + committed: `sin`/`cos`/`tan`, `exp`, `log`/`log2`/`log10`, `cbrt`. Each returns the IEEE-754 correctly-rounded result, validated **bit-for-bit vs a BigInt fixed-point oracle through the full pipeline** (wat2wasm + merge + Binaryen `-Oz`). Shared helpers (reused by every CR function): dd ops `$__ts`/`$__tp`/`$__dda`/`$__ddm`/`$__ddmd`/`$__ddri`/`$__dddiv` (multi-value `(hi,lo)`); `$__scalbn` (musl-style, subnormal/overflow-safe); `$__cr(hi,lo,k)` = correctly-round `(hi+lo)·2^k` (normal via `scalbn(hi+lo,k)`; subnormal via round-`(hi+lo)·2^(k+1074)`-to-even-integer then `·2^-1074` — this avoids the tail double-rounding where `scalbn(lo,k)` lands on exactly half-ulp). `exp`: dd Cody-Waite (dd ln2) + dd Taylor + `$__cr`. `log`: internal `$__logdd` (mantissa/exp decomposition + dd atanh series); `log2`/`log10` = `round(logdd · (1/ln2|1/ln10) dd)`. REMAINING (still old ~1e-11 approx, not yet CR): `expm1`, `log1p`, `pow`(`**`), `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`. NOTE: CR results differ from Deno's V8 `Math.*` on the small % where V8 isn't correctly-rounded (intended). Regen after editing: `wasmtk convert src/wasm/mathlib.wat` then `deno run -A scripts/gen_mathlib_bytes.ts`. Full historical trig detail:
- **mathlib `sin`/`cos`/`tan` are CORRECTLY-ROUNDED double-double** (`src/wasm/mathlib.wat`, 2026-07-01).
  They return the IEEE-754 correctly-rounded result — the unique, platform/version/language-independent
  value every correct libm agrees on (max accuracy AND max cross-language compatibility for the polyglot
  loader ecosystem). **Rationale over "match V8 bit-for-bit":** modern V8's `Math.sin/cos` delegate to
  LLVM-libc's `shared::sin/cos`, which are only *faithfully*-rounded (≤1 ULP, ~99.76% correctly-rounded)
  and a moving version-pinned target; every faithful libm (glibc/MSVC/Go/Rust/V8) disagrees with the
  others by ~1 ULP, but they all cluster on the correctly-rounded value, so correct rounding is the
  maximally-compatible choice. **Implementation:** double-double (dd) helpers `$__ts` (twoSum),
  `$__tp` (Veltkamp twoProduct — no FMA needed), `$__dda`/`$__ddm`/`$__ddmd`/`$__ddri`/`$__dddiv`, each
  returning `(hi, lo)` via WASM multi-value; dd Taylor kernels `$__ddsin`/`$__ddcos` (11 terms); the
  table-free Veltkamp n-split reduction `$__trig_reduce` producing a dd remainder `r` in globals
  `$__tr`/`$__trt` (survive the merge; coexist with the RNG global). `tan = dd sin(r)/cos(r)` via
  `$__dddiv` with quadrant sign. **Validated bit-for-bit vs a BigInt fixed-point correctly-rounded
  oracle** — through the FULL pipeline (wat2wasm + merge + Binaryen `-Oz`, which preserves the dd
  arithmetic): sin/cos 1032/1032 + tan 412/412, 0 off, `|x|` to 1e12; CR holds to ~1e15, ≤1 ULP beyond.
  Pure f64 arithmetic (no Payne-Hanek table, no linear memory) so it survives the wasmmerge splice.
  Do NOT let an optimizer reassociate the dd ops (Binaryen doesn't by default; never enable `--fast-math`).
  Regression: `67_TrigCorrectlyRounded`. Supersedes the earlier fdlibm/≤1-ULP and degree-13-minimax
  versions. After editing `mathlib.wat`: `wasmtk convert src/wasm/mathlib.wat` then
  `deno run --allow-read --allow-write scripts/gen_mathlib_bytes.ts`. NOTE: a wasic program's trig now
  differs from Deno's `Math.*` (V8) on the ~0.24% where V8 isn't correctly-rounded — this is intended
  (wasic is more correct); tests byte-comparing raw trig must use CR==V8 args or tolerances.
- **`$__f64_to_str` is pure Dragon4 (Burger-Dybvig free-format)** as of 2026-07-01 — hand-written
  WAT bignums (48 u32 limbs) over a lazily-`$__malloc`'d scratch region held in the `$__d4s` module
  global, then ECMAScript `Number.prototype.toString` formatting (fixed vs scientific both
  directions; sign/zero/±Inf/NaN). **100% byte-exact with V8**, incl. subnormals, max double, and
  large magnitudes the OLD formatter (×1e15 + shortening loop) either mis-rounded at ~15 sig-figs
  or TRAPPED on (`i64.trunc_f64_s` overflow) with no scientific notation. Do NOT revert to ×1e15.
  `pointPos == k` (the Dragon4 decimal exponent), which drives the fixed/scientific branch. Bignum
  helpers `$__bz/$__bset64/$__bmul_u32/$__bshl/$__bcmp/$__badd/$__bsub` must stay ≥48 limbs (covers
  the full f64 range with margin). Regression: `66_Dragon4Formatting`.
- **Type-erasure casts** `expr as unknown as T` / `expr as unknown` are stripped up front in
  `emitExpr` (before the ` as ` handler) so the inner operand keeps its real type. Without it,
  `buf as unknown as i32` cast the i32 ptr i32→f64 (mapType("unknown")→f64) → `return[0] expected
  i32, got f64`. Guard is `\b`-bounded so `canvas`/`has` aren't touched.
- **`findBinaryOp`** scans the FULL string for paren/bracket depth and only matches at valid op
  positions (`i <= maxStart`). Reverting to start-at-`maxStart` re-hides operators whose RHS ends
  in `)`. Counts `()` and `[]`.
- **`findTopLevelOp` (`console_log.ts`) has the SAME rule (fixed 2026-06-12).** It must scan the FULL
  string from the end (counting trailing `)`/`]`) and only test for an op match at `i <= maxStart`.
  It previously started at `length - op.length`, skipping the trailing chars, so any console.log
  comparison/expression whose RHS ends in `)` (a call, `.slice(…)`, etc.) drove depth negative, the
  operator was never found, and the whole expr silently fell through to the numeric/terminal path
  (wrong boolean / 0). Mirror of the `findBinaryOp` fix — do not revert either.
- **Value-fallthru rewrite** (`emitFunction` → `fixTerminalFallthru`): a value-returning function
  whose body ends in a STATEMENT-level (void) `if/else` where every path `return`s leaves an empty
  stack at the implicit function end — wabt/binaryen accept it, **V8 strict-validation rejects it**
  (`expected 1 elements on the stack for fallthru, found 0`). The terminal void `if` is rewritten
  into a value-producing `(if (result T) cond (then … X) (else … Y))` by turning each branch's
  trailing `(return X)` into a bare value `X` (recursing through nested all-returning ifs), via the
  module-level `tokenizeWat`/`parseWatNodes`/`serializeWat`/`watNodeToValue`/`watBranchToValue`
  helpers. Do NOT instead append `(unreachable)` — Binaryen `-Oz` strips it as dead code and
  re-emits the invalid void `if`. The rewrite is conservative (only when every leaf is a `return`
  or nested all-returning `if`; else body unchanged). Fixed `5e_MixedSignatures`, `19_NestedDU`,
  `19_VariantMax`. (The single-*physical-line* brace form `if (c) { return 1; } else { return -1; }`
  was a separate bug, now **fixed 2026-06-03** — see the single-line-body decision below.)
- **Single-physical-line function bodies are split into statements up front** (`parseFunctions`):
  when the whole body is one physical line (`rawLines.length === 1`), it is split via the
  **string-aware** `splitStmts` before per-line processing. Do not remove this — without it, a
  single-line body with multiple statements, or a trailing statement after a brace `if`
  (`if (c) { return 1; } return 2;`), is mangled (dropped trailing statement → V8 fallthru error; or
  jammed into one statement). `splitStmts` must stay string-aware (skip `"`/`'`/`` ` `` literals with
  `\` escapes) so a `;`/`{`/`}` inside a string is never a false statement boundary; and
  `expandInlineBraceChain` must re-emit trailing statements after the brace chain as siblings rather
  than dropping them. Multi-line bodies (single statement per line) are unaffected. Regression:
  `tests/wasi/wasm_wasi/48_SingleLineBraceIf.ts` (`// deno-fmt-ignore-file` keeps the single-line forms).
- **Greedy single-call handlers** (`charCodeAt`/`startsWith`/`endsWith`/`split`/`.slice` family, plus
  `indexOf`/`includes`/`at`/`charAt`/`replace`/`padStart`/`repeat`/`fromCharCode`/string-char-subscript/
  `isNaN` — extended 2026-06-08) must guard their greedy `(.+)` arg with `parenDepthNeverNegative(arg)`
  so a following binary operator isn't swallowed. Reserve `[^)]+` only when nesting is provably
  impossible. `console_log.ts` has its own `parenDepthNeverNegative` (mirrors wasic's) for the
  console.log-arg `at`/`isNaN` handlers.
- **Struct/class field-base sentinel: use `.ptr < 0`, not `=== -1`.** Both `structVars` (`sv`) and
  `classVars` (`cv`) field/method base computations choose `(local.get $var)` for ptr `< 0` and
  `(i32.const ptr)` for ptr `≥ 0`. `-1` = param/runtime-local, `-3` = heap-malloc'd struct literal
  (runtime fields); both must read via `local.get`. `cv` only holds `-1`/static today (no class
  heap-alloc), but the `< 0` form keeps the two paths consistent and future-proof (mirrors the struct
  fix; reverting `cv` to `=== -1` would re-open the 6b_SimpleStructs class of bug if class heap-alloc
  is ever added). The array sentinel `-2` is never a struct/class `ptr`.
- **Brace-less single-line control flow** (`if`/`while`/`for…of`/`for(;;)` with `stmt;` and no braces)
  is handled in `emitBlock` by capturing the inline tail and `splitStmts`-ing it as the body. The
  `for…of` form was a gap (fixed 2026-06-08). NOTE: `emitBlock`'s `while (i < lines.length)` loop
  advances `i` MANUALLY — every handler that `continue`s a single consumed line MUST `i++` first, or
  it infinite-loops (heap-OOM during compile). The braced multi-line forms use `i += consumed + 1`.
- **String-literal regexes are escape-aware** `"((?:[^"\\]|\\.)*)"` at the statement/expression
  sites (`emitStringPtrLen`, `emitStringAssign`, module-const detection). `allocString` →
  `unescapeString` decodes. (The `console_log.ts` console.log-arg path is still un-escaped.)
- **`&&`/`||` SHORT-CIRCUIT** (since 2026-06-02). `emitExpr`'s binary-op loop (`src/wasic.ts`
  ~6135, mirrored in `console_log.ts` `exprToWat` ~1298) intercepts `&&`/`||` BEFORE the bitwise
  `["&&","and",…]`/`["||","or",…]` table mapping and emits `(if (result i32) lhs (then rhs)
  (else (i32.const 0)))` for `&&` / `(if (result i32) lhs (then (i32.const 1)) (else rhs))` for
  `||`, promoting the i32 0/1 result to the context type via `f64.convert_i32_s`/`i64.extend_i32_s`
  when wider. The RHS is skipped once the LHS decides — matching JS, and the reason an OOB-prone
  `charCodeAt`/array read guarded by `i < len &&` on its LHS is now SAFE (it no longer evaluates
  when out of bounds, which previously trapped after the wasmmerge splice — see compiler-bugs.md).
  Do NOT revert to `i32.and`/`i32.or` emission. The table entries stay (they drive operator
  *detection*); only emission changed. `switch` on `f64`/`number` must use `f64.eq`/`f64.const`.

## Merge (wasmmerge) invariants

- **`detectBumpAllocator`** identifies `$__malloc` semantically: `(param i32)(result i32)`, touches
  exactly one global with `global.get`/`global.set` each occurring **exactly once**, has
  `local.get 0` + `i32.add`, and NO calls/loads/stores. The once-each rule is what keeps a
  `global += param; return global` accumulator from being mis-dropped.
- **`relocateDataPtrs`** relocates only `i32.const` values inside the merged module's own `(data …)`
  address extent (`[dataLo, dataHi)`) — never blanket-shift every `>= 260`, or arithmetic constants
  get corrupted. **AND (2026-06-09) within that range it skips any in-range `i32.const` whose NEXT
  instruction token (the merged body is FLAT/stack form) is a pure arithmetic/bitwise/shift op
  (`ARITH_NEVER_PTR` = `i32.mul/div_s/div_u/rem_s/rem_u/and/or/xor/shl/shr_s/shr_u/rotl/rotr`).** A
  data pointer is never the rhs of those ops, so this never drops a real pointer; it fixes
  over-relocation of an arithmetic constant that coincidentally lands in the data range (e.g. `x %
  271` when the lib's data is `[260, 301)`). Do NOT switch to an "address-position only" rule —
  a genuine pointer can appear in VALUE position (`i32.const 0 / i32.const 260 / i32.store` stores a
  string pointer), so that would under-relocate. `add`/`sub`/comparison/store/load/`(data …)` offset
  all keep relocating (conservative). Regression: `18i_RelocArithmeticConstant`. Tradeoff rationale +
  full proof: compiler-bugs.md "Remaining-items pass" item 5.
- **Imported-function logical signatures** come from the sibling `.wit` (string params hide as
  `i32 i32` in the raw `.wasm`); `applyWitSig` overlays them so string args expand to ptr+len.
- **`.toText({ inlineExport: false })`** must be passed explicitly at every disassembly site in
  `wasic.ts`/`wasmbundle.ts` (wabt-ts default differs from npm:wabt).
- **`isModuleGlobalArr`** checks `arrayVars.get(name)?.ptr === -2` (the module-global sentinel),
  NOT `moduleArrayVars.has()` — so a rest-param shadowing a global array (`ptr === -1`) emits
  `local.get`, not `global.get`. Spread calls `fn(...arr)` likewise pick `global.get` vs
  `local.get` by `moduleGlobals.has(name)` at all three emission sites.

## Runner / ABI invariants

- All runtime I/O goes through `rt.*` (never `Deno.*`) — Bun compatibility.
- Uncaught WASM throw from `_start` prints `error: Uncaught (in Wasm) Error: <msg>` to stderr and
  exits cleanly (code 0). `throw` inside try/catch emits `(throw $__exn_tag ...)`, never `proc_exit`.
- The `env` import object in the runner is a `Proxy` returning a no-op `()=>0` stub for any unknown
  key (so Phase-40 `declare const` external modules instantiate without a real host).
- `cabi_realloc` is exported (not `__malloc`) when any export has a string param/return; string
  returns use the `$fn__cabi` out-param shim. The `$__str_ret_*` globals are NOT exported.

## Parallel-path discipline

`console_log.ts` duplicates much of `wasic.ts`'s expression/arg emission (`parseSingleArg`,
`exprToWat`, the `structLookupFn`/`dotCallLookupFn` closures). When you change an emission rule in
`wasic.ts`, check whether the same rule exists in `console_log.ts` (and in BOTH the console.log and
console.error closures) and update it too. Static-field, getter, TypedArray `.length`/`.byteLength`,
string-array element, and `Math.*`/`Number.*` handling all have such twins.

## Class / feature codegen

- **`instanceof` (Phase 51)** lives in `emitExpr` AFTER the binary-op loop (so `a instanceof X && …`
  splits on `&&` first). When `classHeaderSize > 0` it emits a runtime tag check
  (`tag(obj) ∈ {target + findSubclasses(target)}`, OR-folded, tag read at offset 0); when
  `classHeaderSize === 0` (no inheritance, no tag header) it folds to a compile-time const from the
  var's tracked class. The object pointer comes from `classVars`/`this`, else falls back to
  `emitExpr(lhs)` (this fallback is why the array-element / base-typed-param cases work). Narrowing
  for `if (x instanceof Sub)` reuses the Phase-34 `narrowKey` save/restore in `emitBlock`. For
  `console.log(x instanceof C)`, `console_log.ts` calls back into `emitExpr` via the
  `setInstanceofResolver` singleton (the resolver returns `undefined` for non-class RHS so
  `instanceof Error` etc. still hit their existing handlers). Result is i32 0/1, promoted to
  f64/i64 when the context type is wider (same pattern as the short-circuit `&&`/`||` handler).
- **Module-level class instances (Phase 51)** are registered in `classVars` by a `newClassPre`
  block in the `startBodyLines` pre-scan that mirrors `emitFunction`'s. It MUST allocate a static
  ptr via `allocStructData(cd.struct, {}, classTag)` — the const-new statement handler emits
  `(i32.const ptr)` for both the `local.set` and the constructor call, so registering with `ptr:-1`
  would `local.set`/construct at address -1. The `if (cd)` guard skips TypedArrays (PascalCase but
  not in `classDefs`).
- **Class-instance array literals (Phase 51)** — `const a: C[] = [new C(…), …]` is desugared to
  `const a: C[] = []; a.push(new C(…));…` by `expandClassInstanceArrayLiterals()` (source pre-pass,
  after `parseClasses`, before `parseFunctions`/`parseTopLevel`). The static struct-array path can't
  run constructors (it only fills `{field:val}` literals → zeroed structs, no tag); `push(new C())`
  constructs each element. Only fires when the element type is a known class AND every element is a
  `new …(…)`. Don't move it before `parseClasses` (needs `classDefs`) or after body collection (the
  bodies must already contain the desugared lines).
- **Single-physical-line class/constructor bodies (Phase 51)** — `parseClasses` field parsing iterates
  `splitClassMemberLines(classBody)` (depth/string-aware: splits at depth-0 `;`, depth-0 `\n`, and
  after a depth-0 `}`), NOT raw `classBody.split("\n")` — otherwise a field sharing a physical line
  with the constructor is skipped (the field loop skips any line containing `(`). And a method/ctor
  `rawBody` that is a single physical line is split via `splitStmts` so multi-statement single-line
  bodies (`super(k); this.v = v;`) aren't mangled into one stub. Relies on comments being stripped
  before `parseClasses` (they are — `stripComments` runs at the top of `transpile`).
- **Object spread `{ ...src, k: v }` (Phase 51.2)** — both struct-let pre-scans register the spread
  var with **`ptr:-1`** (NOT `-3`). The 17 struct field-access sites only special-case `ptr === -1`
  → `(local.get $var)`; a `-3` (heap) sentinel would make every read compute `(i32.const -3)`. The
  spread var IS an i32 local holding the malloc'd pointer (same shape as a function-returned struct),
  so `-1` is correct. The `structSpreadMatch` emit branch (in `emitStatement`, BEFORE the static
  `structLetMatch`) owns the `local.set`, so it does not consult `sv.ptr`. `emitSpreadStructLiteral`
  copies base fields BY NAME using the base's own offset/type (string fields copy ptr+len both words);
  unset fields rely on zeroed bump-allocated memory. `parseStructLiteralWithSpread` excludes the
  `...tok` from the override map so the shorthand-detection regex can't misfire on the spread source.
  Single-physical-line literals only; string-field *overrides* are ptr-only (pre-existing
  `emitRuntimeStructLiteral` limit — copies are fine).
- **Param destructuring `f({x,y}: Vec2)` (Phase 51.3)** — `expandParamDestructuring()` is a source
  pre-pass (runs BEFORE `parseFunctions`, after `parseStructs`/`parseClasses`) that rewrites a
  destructuring param to a synthetic `__pd_N: Type` and injects `const { … } = __pd_N;` /
  `const [ … ] = __pd_N;` as the FIRST body statement(s) — deliberately reusing the existing
  struct-param registration + flat-destructure handlers, so there is NO new emit path. Two
  load-bearing details: (1) injected bindings MUST be newline-separated (function bodies are split
  per newline; space-joining collapses multiple bindings into one unmatched stub); (2) `parseParams`'
  param comma-split tracks `()`+`[]`+`{}` (NOT paren-only) — otherwise a tuple-type param
  `__pd_N: [i32, i32]` splits at the inner comma into two broken params. Only named `function NAME(...)`
  declarations are rewritten (arrow/method params are a follow-up). Inline tuple-literal *args*
  (`f([1,2])`) are a separate pre-existing gap; struct-literal args work.
- **Nested object destructuring `const { a: { b }, c } = obj` (Phase 51.3)** — the object-destructure
  emit handler + pre-scan use **balanced-brace detection** (`findMatchingBracketAware`, NOT `\{([^}]+)\}`
  which can't match nested `}`) and delegate to recursive helpers `emitDestructurePattern` /
  `collectDestructureLocals`. A binding whose value is a `{…}`/`[…]` pattern recurses into the nested
  field: pointer fields (`structType`, Phase 42) load the stored ptr as the new base; inline-tuple
  fields (`tupleTypeName`, Phase 21) use the field *address* — `nestedFieldBaseWat` encodes this. No
  temps (nested loads inline). Two load-bearing details when refactoring: (1) object *shorthand with
  default* `{ x = 1.0 }` (no colon) must strip the `= default` BEFORE the field-name lookup — else
  `def.fields.find("x = 1.0")` misses and the whole compile aborts (the binding emits a stub); the
  `valuePart` still carries `x = 1.0` so the flat-bind branch extracts local `x` + default `1.0`.
  (2) `emitDestructurePattern` and `collectDestructureLocals` MUST stay structurally identical (same
  field/valuePart parsing) so the pre-scan declares exactly the locals the emit sets. (3) Both use
  `splitBraceAwareCommasKeepEmpty` (NOT `splitBraceAwareCommas`, which drops empties) so positional
  **gaps** `[a, , c]` keep index alignment — see the gap-collapse bug in compiler-bugs.md.
- **Nested tuple/array `const [[a, b], c] = t` (Phase 51.3)** — tuples are structs, so once the tuple
  *type* parser is bracket-aware the recursive destructure/spread machinery handles nesting for free.
  `tupleTypeName` + `makeTupleStructDef` split elements with `splitBraceAwareCommas` and, for a nested
  tuple element, **embed it INLINE** (a `tupleTypeName` field, natural-aligned via `tupleFieldAlign`,
  `size = nested.totalSize`) — same shape as a Phase-21 embedded tuple, NOT a heap pointer. So
  `nestedFieldBaseWat` uses the field *address* for these. Value construction
  (`const t: [[i32,i32],i32] = [[1,2],3]`) recurses via `emitTupleLiteralStores`, storing each nested
  element at `baseOffset + field.offset` (a compile-time-constant WAT store offset). All tuple
  literal/destructure regexes were widened from `\[[^\]]+\]` (stops at first `]`) to a one-level-nesting
  bracket class or balanced detection (`findMatchingBracketAware`). **Determinism check:** the rewritten
  flat-tuple path emits byte-identical WAT to the pre-rewrite code (verified: zero tracked-`.wat`
  content changes), so only genuinely-new nested cases produce new bytes.

- **Utility types (Phase 51.4)** — two source-level passes, NOT a new emit path. `expandUtilityTypes`
  (BEFORE parseStructs) unwraps pass-through wrappers `Partial`/`Readonly`/`Required`/`NonNullable` →
  inner type (balanced `<…>` via `matchAngleBracket`, loops for nesting). `expandStructUtilityTypes`
  (AFTER parseStructs, needs the base def; BEFORE parseFunctions) synthesizes `Pick`/`Omit`/`Record`
  structs. Load-bearing: (1) the inline synthetic name is `${Kind}_${args}` — MUST start with the
  uppercase Kind letter, because struct-type detection everywhere keys on `[A-Z]\w*` (a `__`-prefixed
  name silently fails to register/allocate → fields read 0). (2) `Pick`/`Omit` copy base StructFields
  PRESERVING offsets + totalSize (so a base value is layout-compatible with the subset), `Record` packs
  fresh. (3) `Record<string,V>` / non-literal keys → unresolved (dynamic map, out of scope). Pick/Omit
  as interface *field* types aren't supported (parseStructs runs first); var/param/return/`type Alias`
  positions are.
- **Phase 52 leaf conveniences (2026-06-11)** — five small features; the load-bearing invariants:
  (1) **`void expr;`** + **chained assignment `a = b = c = 0`** handlers sit at the TOP of
  `emitStatement`, BEFORE the `return` handler and BEFORE the simple-assignment matchers (which would
  otherwise grab `a = (b = c = 0)`). The chain detector counts top-level plain `=` (skipping
  `==`/`===`/`=>`/`!=`/`<=`/`>=`/compound via a prev/next-char check, string/template-aware), requires
  EVERY target to be an assignable lvalue (`\w+` / `\w+.\w+` member / `\w+[…]` element — extended
  2026-06-12 from bare-identifier-only so `p.x = z = 5` and `arr[i] = w = 9` work), and lowers to
  `c=0; b=c; a=b` (rightmost first) reusing the normal assignment emitter — do NOT special-case
  types/strings/globals here, the reuse handles them. Declaration-form chains (`let a = b = 0`)
  intentionally bail (target `let a` isn't an lvalue). (2) **`"field" in obj`** and
  **`Array.isArray(x)`** are closed-world COMPILE-TIME constants resolved in `emitExpr` (NOT
  `console_log.ts` — direct `console.log("x" in o)` / `console.log(Array.isArray(a))` are not wired;
  route via a `boolean` local or an `if` condition, both of which go through `emitExpr`). `in` uses
  `findDepth0Keyword(" in ")` + `structHasField` (structVars→def.fields, classVars→classDefs.struct.fields;
  returns null → fall through when unknown). (3) **`Array.from([…])` / `Array.of(…)`** are a SOURCE
  pre-pass (`expandArrayFromOf`, string-aware balanced scan) that MUST run AFTER the
  `Array.from({length:N}, () => [])` 2D sentinel rewrite (so the `{length}` form is consumed first);
  it rewrites only a literal-array argument (non-literal `Array.from(iterable)` is left untouched) and
  recurses into the rewritten arg for nesting. (4) **`String.fromCodePoint(...)`** — constant args go
  through `allocStringDecoded` (NOT `allocString`): the produced characters are already final and must
  NOT be re-run through `unescapeString` (a produced `\`/quote would be misread). `constCodePoint`
  validates decimal/hex in the 0..0x10FFFF range; out-of-range/runtime falls to the
  `$__str_from_codepoint` WAT helper (1–4 byte UTF-8, multi-value ptr,len, gated by
  `needsStringExtHelpers`). Wired in `emitStringAssign`, the concat `appendConcatPart` path,
  `isStringExpr`, and BOTH `$__str_op` prologue temp-pair detectors (function + startBodyLines).
  (5) **console_log.ts `dotLenMatch` now resolves STRING `.length`** (UTF-8 byte length) for local
  strings (`local.get $x_len`), module string consts (`i32.const <len>`), and string globals
  (`global.get $g_len`) — it previously only handled array `.length` (so `console.log("s.length:",
  s.length)` printed 0 for any string var, `fromCharCode` included). NOTE multi-byte: wasic `.length`
  is the UTF-8 BYTE count, TS `.length` is UTF-16 units — only ASCII results are `.length`-comparable.
- **Else chains after a single-line `if` (2026-06-12, `emitBlock`)** — a single-line `if` (brace-less
  `inlineBody` OR single-line-braced `singleLineBlock`) followed by a self-contained `else`/`else if`
  chain on the NEXT lines used to DROP every branch after the first (the else-detection only matched a
  few braced multi-line forms). FIX, placed BEFORE the inlineBody/singleLineBlock branching: if
  `WasicTranspiler.isSelfContainedElse(lines[i+1])`, assemble the if-body + the whole chain into one
  inline string (`braceifyElseLine` braces brace-less bodies), feed to `expandInlineBraceChain` →
  canonical braced multi-line form, splice + `continue`. `isSelfContainedElse` returns FALSE for an OPEN
  braced `else {` (body continues on later lines) so the existing multi-line machinery still owns those.
  Do NOT remove this — the brace-less and single-line-braced else forms silently miscompile without it
  (regression `15_ElseChainForms`). `instanceof` with a non-user-class (built-in) RHS resolves at
  compile time: Error-family → 1 (wasic models caught exceptions as strings, so `e instanceof Error`
  catch-narrowing is true), other built-ins → 0.
- **Terminal emit diagnostics (silent-fall-through hardening, 2026-06-12)** — the four terminal
  "give-up" fallbacks (`emitExpr` unsupported expr, `emitStatement` unsupported stmt, `emitStringAssign`
  unsupported string assign, `emitStringPtrLen` unsupported string expr → its `(i32.const 0) (i32.const
  0)` sentinel) now `this.diagnostics.push(...)`, which ABORTS the compile (the `warnings` gate in
  `compileWasiTs`/`compileLibTs`) instead of silently emitting `0` / the empty string. **Invariant:**
  SPECULATIVE / guarded probe sites that recover gracefully when they get a stub/sentinel MUST wrap the
  call in `quietEmit(() => …)` (a depth counter `emitDiagSuppressDepth`; the terminal push is skipped
  while > 0). There are ~13 such wrapped sites (10 sentinel-guarded `emitStringPtrLen` callers + 3
  `emitExpr` probes that inspect the result for `(;?`/`(unreachable)`); every OTHER caller passes the
  stub straight through and so DOES get the hard error. The `emitStatement` diagnostic additionally
  skips clearly-non-statement fragments of multi-line constructs parsed elsewhere (lines starting with
  `|` = DU type-alias union continuations; element fragments ending in `,`; bare object-literal /
  numeric / string element lines). When adding a new caller of `emitExpr`/`emitStringPtrLen` that probes
  for failure, wrap it in `quietEmit`; when adding a new terminal fallback, decide whether silent-wrong
  or a diagnostic is correct (default: diagnostic).
- **console.log binary-op operand type from the LHS leading atom (`console_log.ts` `exprToWat`)** —
  the `+`/`-`/… operand type is inferred from the LHS's leading atom: plain local, `var.field` (type via
  `structLookup().type`), `.length` (→i32), OR — for an array-element-led operand `arr[…]` — the
  array's ELEMENT type via `arrayLookup` (the lead atom `arr` is an i32 pointer, so the element type
  is what matters; keying on the lead atom covers compound LHS like `arr[0] + arr[1]` too). Without
  LHS-typing, i32 struct-field arithmetic compiled to `f64.add` of i32 loads. **FIXED 2026-06-08:**
  `console.log("x:", arr[i] + arr[j])` (array-element arithmetic) — previously the greedy `arr[idx]`
  regex captured `0] + arr[1` and emitted one mangled access (dropping terms). Now the bracket index
  is `parenDepthNeverNegative`-guarded in BOTH `parseSingleArg` and `exprToWat`, so the expression
  falls through to the binary-op loop, which infers the op type from the array element type
  (i32[]→`i32.add`, f64[]→`f64.add`). Regression: `6d_ConsoleLogArrayArith`.
- **console.log string comparison non-trivial operands (`console_log.ts`, 2026-06-12)** — `getStrPL`
  (string `===`/`!==`) and the string-ternary `getStrPtrLen` resolve fn-call / struct-field / slice /
  method operands via the `_stringExprResolver` bridge → wasic `emitStringPtrLen` (captures len into
  `$__str_op_len`). Without it those operands silently compared against `""`. The resolver-temp is
  declared by broadening the `$__str_op_ptr/len` prologue trigger to a `console.*` line with a
  string-equality op. **String `!==` is `(i32.ne cmp 0)`** (`$__str_cmp` returns 0 for equal) — the old
  `(i32.ne (i32.eqz cmp) 0)` was inverted. String `.length` as an OPERAND is handled in `exprToWat`'s
  `dotLenM` (not just `parseSingleArg`), plus a general `<stringExpr>.length` via the resolver's len
  word. Regression: `27_ConsoleLogStringCompare`. KNOWN LIMIT: 5th+ numeric arg in per-iov mode prints
  `"?"` (SCRATCH_SLOTS=4; raising it shifts `DATA_BASE`/260 = wasmmerge `DATA_PTR_THRESHOLD`).
- **Greedy `dotCallExprMatch` / `newMatch` / `superDotExprMatch` in `emitExpr` are guarded** (FIXED
  2026-06-08). `a.method() + b.method()`, `new A(x) OP new B(y)`, `super.m() OP x` — the greedy
  `([\s\S]*)` args capture used to consume across the operator (e.g. `a.unwrap() + b.unwrap()` →
  receiver `a`, args `) + b.unwrap(`), so tests had to hoist `const av = a.unwrap()` temporaries
  (16_NestedMonomorphization). Now each carries a `parenDepthNeverNegative(args)` guard so the
  compound expression falls through to the binary-op loop. Regression: `16_MethodCallBinaryOp`.
  (Still-open, narrower: chained `new X(...).method()` inside a binary op has no handler; and a
  module-level multi-statement single physical line `const a = ...; const b = ...;` isn't split —
  both rare.)

## Async / Promise (#13, 2026-06-15) — load-bearing invariants

Full design + implementation log in [async-design.md](async-design.md). The rules a refactor must NOT
silently break (all `src/wasic.ts`):

- **Promise runtime is INLINE, never a merged capability.** It uses `call_indirect` to invoke `.then`
  reactions, and `wasmmerge`'s `call_indirect` guard forbids that in a merged module. The runtime is
  emitted by `getPromiseRuntimeWat()` (gated by `needsPromiseRuntime`) in the main module, sharing one
  funcref table + the `$ftype_i32_i32_i32_r_void` reaction functype with the compiler-emitted trampolines.
  Do NOT move it to a `wasmtk:promise` capability.
- **The reaction functype carries an `env` slot: `(env i32, src i32, result i32) -> void` (13.1b).** The
  reaction RECORD is 20 bytes `[tramp@0 | env@4 | src@8 | result@12 | next@16]`; `$__promise_then` /
  `$__promise_enqueue` take `env` (the capturing-closure struct ptr, 0 for a named callback); the drain
  `call_indirect`s `(env, src, result, tramp)`. Keep this functype/record in lockstep — it is the §3.6
  design-locked shape (the earlier 2-param `(src,result)` form was a 13.2 simplification, corrected here).
  A trampoline invokes a NAMED cb via `(call $name <args>)` (env unused) and a CLOSURE cb via
  `(call_indirect (type [i32,…args]→U) (local.get $env) <args> (i32.load (local.get $env)))`. At most ONE
  closure callback per reaction (one env slot).
- **`promiseInnerType: Map<varName,WatType>` tracks promise-holding locals (13.1b).** Reset per function;
  populated by a non-consuming observer at the TOP of `emitStatement` for `const/let/var p = <promiseExpr>`;
  `isPromiseExpr`/`promiseInnerTypeOf` consult it for a bare identifier (so `await p` / `p.then` work and
  pick `await_<T>`). `promiseInnerTypeOf` resolves a callback's return type via `cbResult`, which covers
  BOTH a named fn AND the `__anon_N__factory(caps)` capturing-closure form — do not regress it to
  named-only or an f64 closure cb mis-picks `await_i32`.
- **Capturing `.catch` (string-param closure) is guarded OUT** (`resolveCb` returns null if a closure's
  real params include `string`). wasic's closure trampoline (`emitClosureFactory`) keeps a `string` param
  as one i32 instead of expanding to (ptr,len), so dispatching it would be arity-mismatched. Use a NAMED
  reject callback. Fixing the closure trampoline's string-param expansion would lift this.
- **`Promise.all`/`Promise.allSettled` lower to per-call-site combinators, NOT reactions (13.4).**
  `genPromiseAllSite(n, elemT)` / `genPromiseAllSettledSite(n, elemT)` have fixed arity = the
  array-LITERAL length; they `$__drain_microtasks` then collect (eager model = all elements settled
  post-drain). `all`: first rejected element wins → reject; else build a fresh `T[]`. `allSettled`: never
  rejects → build an `i32[]` of `__settled_<T>` struct-record ptrs (`{status:string, value:T,
  reason:string}` via `ensureSettledStruct`), the result var registered as a struct array of that synth
  type in the emitFunction pre-scan (the `__Anon_<var>` precedent). Both fulfill with an array ptr
  (vtype=3 → `await_i32`). ARRAY-LITERAL arg ONLY (count must be a compile-time constant); element types
  i32/f64; `Promise.all(arrVar)` unsupported. Do not regress `isPromiseExpr` to drop `all`/`allSettled`.
- **A struct-array string field in console.log returns ptr+len (`watLoadLen`), not just the ptr.** Both
  console.log/console.error `arr[idx].field` struct-lookup closures special-case `field.type ===
  "string"` (else the field prints as a raw i32 ptr). Surfaced by `allSettled`'s `results[i].status`.
- **`hybrid` routes async fns via `f__impl` + a sync unwrapping wrapper (13.5, `src/hybrid.ts`).** A
  compiled async fn returns a promise PTR, not the value — so a routed `async function f(p): Promise<T>`
  is rewritten to an internal `f__impl` (intra-body calls to other routed async fns renamed to `__impl`
  to keep the async call graph promise-typed) plus a SYNCHRONOUS exported `f` that does `return await
  f__impl(args)` (eager model settles synchronously). `Promise<void>` wrappers just invoke the impl.
  Don't expose the raw async fn to bindgen (the host would get a ptr). Async without a `Promise<T>`
  annotation stays in the TS host. The awaited graph must be intra-module (host-I/O async → host).
- **Promise object layout is the canonical `result<T,E>` window** `[state@0, vtype@4, disc@8, payload@16,
  plen@24, reactions@28]` (32 B). `disc`/`payload` are the lift-ready Canonical-ABI image — keep them
  contiguous + naturally aligned (forward-compat for a future WASI-P3 lift). Fresh bump memory is zero
  → a new promise is pending/ok/no-reactions without explicit init.
- **`isPromiseExpr` / the react routers recurse on the receiver for `.then|catch|finally`**, never a
  loose `/\.(then|catch|finally)\(/` substring test. The substring form mis-classified `const y =
  p.then(f)` as a promise statement and mis-routed it. Same trap class as the scanner rules above.
- **Reaction trampolines are DUAL-PATH and chosen by `genReactionTrampoline({kind})` (13.3b)** — they
  read `src.disc` (+8) and branch: `then` → fulfilled runs `onF(value:T)` / rejected propagates (or
  runs `onR` for `.then(onF,onR)`); `catch` → fulfilled passes through / rejected runs `onR(reasonPtr,
  reasonLen)` (the reject reason is a STRING at payload@16 + plen@24, so `onR` is a string-param fn);
  `finally` → runs `onFin()` on both paths then passes through. Passthrough/propagate use a type-agnostic
  `copySettlement` (full 32-B image incl. the 8-B payload via `i64`). The fixed reaction functype
  `(src i32, result i32) → void` is UNCHANGED — only the body differs (so Approach B stays drop-in).
  `promiseInnerTypeOf`: `.catch` → `onR`'s return type, `.finally` → src's inner type.
- **Greedy `Promise.resolve(…)` / `.then(…)` regexes MUST carry a `parenDepthNeverNegative` guard**
  (in `promiseInnerTypeOf`, the `emitExpr` handlers, and the statement router) — without it,
  `Promise.resolve(2).then(triple)` is mis-split as resolve-with-arg `2).then(triple` → wrong inner type
  → f64/i32 trampoline mismatch at instantiate.
- **When `needsPromiseRuntime`, the reaction functype + a funcref table are FORCED** even with no `.then`
  (`getPromiseRuntimeWat` registers `$ftype_i32_i32_r_void`; `emitFuncrefTable` emits `(table 1 funcref)`
  when `funcTable` is empty) — the drain's `call_indirect` references both and would otherwise be a
  dangling type / missing table for an await/resolve-only program.
- **Rejection support is gated by `needsPromiseReject` (separate from `needsPromiseRuntime`)** so
  resolve/then-only programs stay exception-free. When set: `await` helpers gain the `disc==1 → (throw
  $__exn_tag …)` re-throw, `$__promise_reject` is emitted, and `needsExceptionTag` is set. async-body
  `throw` → caught at the `await` site is FREE under the eager model (eager run + WASM exception
  propagation) — no reject-wrapping; do not add one expecting JS deferred-rejection timing.
- **async `Promise<void>` fns are plain void fns** (body runs eagerly, no promise returned); only
  `Promise<T>` with T≠void is promise-returning (`asyncInner` non-null → `return` wraps in
  `$__promise_resolve_<T>`). The `parseFunctions` header regex, `parseTopLevel`, and the nested-fn skip
  all accept an optional `async`; the return-annotation regex accepts `Promise<…>`.

## Tooling

- `tsbundle` outputs **`.ts`** (`.bundled.ts`), an import inliner — NOT `deno bundle`/JavaScript.
- `.wasm` import detection matches **single-line** `import { … } from "./x.wasm"` only.
- **`rt.Command.output()` always reads `result.stdout`/`stderr`, which THROWS unless they are
  `"piped"`.** Never pass `stdout`/`stderr` `"null"` or `"inherit"` to a `.output()` call (it surfaces
  as a misleading `catch` — e.g. a tool wrongly reported "not found"). Always `"piped"` and decode the
  captured bytes. (Bit the Go producer; see `src/gowasic.ts` `decodeOut`.) Also: `rt.remove` is
  single-arg (unlink-based under Bun) — use `Deno.remove(dir, {recursive:true})` for a directory.
  Build subprocess env as `{ ...rt.env.toObject(), …overrides }` so PATH is preserved. `rt.Command`
  now also accepts `cwd` (added 2026-06-06 for the Go producer's `go mod init` / package builds).
- Bump the version with **`deno task bump`** (`scripts/bump.ts`): raises the semver in `deno.json`
  (`patch` default; `deno task bump minor` / `major`) and then propagates to `package.json` +
  `src/utils.ts VERSION` via `sync-version.ts`. `deno task update-version` only *propagates* an
  already-edited `deno.json` version (no increment); `bump` is the increment counterpart. `bump` is
  intentionally NOT wired into `deno task publish` (bumping stays a deliberate step). Don't add
  `dependencies` to `package.json`; don't use `nodeModulesDir: "auto"` (Windows junction failures).
- **Keep the published TypeScript (`main.ts` + `src/`) `deno fmt`-clean.** As of 2026-06-02 it
  passes `deno fmt --check main.ts src/` (one-time reflow to the deno.json fmt config: lineWidth
  100, arrow parens, semicolons). Format with the **scoped** `deno fmt main.ts src/` — do **NOT**
  run bare `deno fmt`: with no `include`/`exclude` in deno.json it would reflow the 176 KB README
  and all `cmem/*.md` markdown (mangling tables/code-fences) plus every test. `deno fmt` preserves
  template-literal contents, so reformatting `wasic.ts`/`console_log.ts` leaves emitted WAT
  byte-identical — but it IS the compiler, so reinstall (`deno install -g … -n wasmtk`) and re-run
  the three suites after any reformat. fmt is not CI-gated (see testing.md), but staying clean keeps
  the pre-publish checklist green.
- **Keep `deno doc --lint` clean across all `deno.json` entrypoints** (the JSR doc-coverage
  score depends on it; published 2026-06-15 with v1.7.0). The score gates on
  `percentageDocumentedSymbols >= 0.80`; every exported symbol (incl. **each interface field**
  individually) needs a `/** … */` JSDoc, every public function must not return a private type
  (`private-type-ref`), and computed exported consts need an explicit type (`missing-explicit-type`).
  v1.7.0 brought this from 0.79 → 0.97 (commit `e64595f`). As part of that, the producer result
  types **`GoResult` / `ZigResult` / `RustResult` are now `export`ed** (they're returned by the
  public `compileGoWasi` / `scaffoldGoProject` / `compileZig` / `scaffoldZigProject` / `runRust`
  functions) — do not re-privatize them. Run `deno doc --lint <all 15 exports>` before publishing;
  it is not CI-gated but a regression silently drops the JSR score.
- **JSR provenance is environmental, NOT a `publish.yml` problem.** Provenance was silently `false`
  across v1.6.2–v1.6.5 even though every Action run succeeded — `deno publish` skips attestation
  non-fatally when it can't mint/submit the GitHub OIDC token. The committed workflow was always
  correct (`id-token: write` + clean `deno publish` with no `--token`/`DENO_AUTH_TOKEN` + `v*` tag
  trigger, byte-identical at the tags); the cause was the OIDC token being gated at the
  org/enterprise Actions level. A **"Check OIDC availability" diagnostic step** was added to
  `.github/workflows/publish.yml` before `deno publish` (echoes whether `ACTIONS_ID_TOKEN_REQUEST_URL`
  /`_TOKEN` reached the runner, `::warning::` if not) so any recurrence is visible in the run log.
  v1.7.0 published with `hasProvenance: true` (JSR score 100). Do not "fix" provenance by editing the
  publish/permissions YAML — it is already correct; check OIDC policy instead.

## Go producer (CLI / build invariants — set 2026-06-07)

The Go command surface was deliberately shaped to mirror the TS commands' *meaning*. Do not silently
revert these (full rationale in [polyglot-producers.md](polyglot-producers.md)):

- **`wasic --lang=go` is REMOVED** — there is no standalone Go→WASI *compile* command (a bare WASI
  executable isn't merge/bindgen-consumable). The `wasic` case intercepts `--lang=go` and prints a
  pointer to `run`. The Go→wasip1 build lives ONLY inside `run`. Don't re-add it as a compile command.
- **`modc --lang=go` = WASI reactor library by default** (`-target=wasip1 -buildmode=c-shared`: no
  `_start`, exports `//go:wasmexport` funcs, callable via `wasmtk mod`/bindgen) — the Go analog of TS
  `modc` (library mode). The **browser** build (`-target=wasm`, syscall/js + `wasm_exec.js`) is opt-in
  via `--go-target=wasm`. Do NOT flip the default back to browser.
- **`run --lang=go` builds a wasip1 COMMAND** (`target: "wasip1"`, has `_start`) and runs it — NOT a
  reactor. It also **auto-detects** Go: a `.go` file or a dir containing `go.mod` routes to the Go
  build+run without `--lang=go`. The detection (`isGoRunTarget`) lives in `main.ts`, deliberately NOT
  in `gowasic.ts`, so a plain `wasmtk run x.wasm` doesn't import the Go module (which pulls in
  binaryen) just to decide.
- **`init --lang=go` defaults to a wasm LIBRARY scaffold** (`GoScaffold = "library" | "browser"`;
  templates `MAIN_GO_LIBRARY` / `MAIN_GO_BROWSER`). No flag needed for the library (the producer's
  primary output); `--go-target=wasm` scaffolds a browser project. The library scaffold is one file:
  `//go:wasmexport` funcs + a `func main` test harness (run with `run`, DCE-stripped by `modc`).
- **Reactor exports require `_initialize`** — `callExport` (`wasmtk mod`) and `runWasi`'s named-export
  path MUST call `exports._initialize()` (if present) before any export, or a reactor library traps
  (`unreachable`). No-op for runtime-free TS libraries. Don't remove.
- **Merge guards (loud-fail, `wasmmerge`)** — a module merged via `wasmbundle`/`.wasm`-import must not
  contain `call_indirect` (Phase 18 strips imported type sections → dangling ref) or `memory.grow` (a
  foreign growing-heap allocator that would corrupt the shared bump heap). Both throw clear,
  actionable diagnostics; wasmtk's own producers emit neither. Keep both guards.

## Zig & Rust producers (CLI / build invariants — set 2026-06-07)

- **Zig (`src/zigwasic.ts`, shell to `zig`):** `init --lang=zig`=library scaffold, `modc --lang=zig`=
  freestanding library, `run --lang=zig`=`wasm32-wasi` program on wasmtk's TS host. Two load-bearing
  details: (1) the scaffold **comptime-guards** the test `main`'s std I/O to `builtin.os.tag == .wasi`
  — Zig analyzes `pub fn main` even with `-fno-entry`, so an unguarded std-using main breaks the
  freestanding library build (`posix.getrandom` absent). (2) the library build passes
  **`--export=<name>` scanned from the root source** (`scanExportFns`), not `-rdynamic` (which also
  exports `main` as `_start`); falls back to `-rdynamic` only if no `export fn` is found. WASI triple
  is `wasm32-wasi`.
- **Rust (`src/rustwasic.ts`) — delegates fully to `rsxtk`** (do NOT reimplement via cargo). wasmtk
  wraps rsxtk: `init`→init, `initmod`→initmod, `modc`→`build … wasm`, `build`→`build … wasi`, `run`→
  run, `add`/`remove`/`list`/`fmt`/`clean`→same. The Rust-only verbs (`initmod build add remove list
  fmt clean`) **require `--lang=rust`**. Args are forwarded raw (command + `--lang` stripped) so
  rsxtk's own positionals/flags pass through; `modc`/`build` auto-append the rsxtk `build` TARGET
  (`wasm`/`wasi`). Prereq: `rustup target add wasm32-wasip1`.
- **Run auto-detect** (`detectRunLang` in `main.ts`, NOT the producer modules): `.go`/`go.mod`→go,
  `.zig`→zig, `.rs`/`Cargo.toml`→rust. Keep it in main.ts so a plain `wasmtk run x.wasm` never loads a
  producer module (binaryen / toolchain shell-out) just to decide.
- **WASI-import Proxy** (`makeWasiImport` in `src/utils.ts`): `runWasi`/`callExport` stub any
  unimplemented `wasi_snapshot_preview1` function (→ `()=>0`) so modules importing a fuller WASI
  surface (Zig/Rust std) instantiate. Don't revert to the fixed `wasiImports` object.
- **`binaryenOptimize`** lives in `src/binaryen.ts` (shared by Go + Zig). Don't duplicate it back into
  the producer modules.

## Intentional fallbacks — NOT workarounds (do not "fix" or remove)

These are deliberate design choices that can look like workarounds in a sweep. They are correct as-is;
removing them would break things. Listed so a future audit doesn't re-flag them.

- **~~`javyc` (QuickJS) as the interim dynamic runtime~~ — SUPERSEDED + DELETED v1.11.1.** wasmtk's
  OWN dynamic runtime (the `wasmtk:dynrt` interpreter, roadmap §7-#7 / dynrt-design.md) now covers the
  dynamic kernel (`eval`/`new Function`, pervasive `any`, open-prototype mutation). It's auto-merged on
  `: any`/`eval` in a `wasic` program, and `wasmtk dync` runs a whole fully-dynamic file through it —
  both with NO external Javy/QuickJS. `src/javyc.ts` and the Javy dependency were removed (#14 2h).
- **`npm:wabt` / `npm:binaryen` as fallback backends.** `deno.json` is the single switch; the JSR
  `/compat` packages are the default, npm is the always-available fallback for the migration's
  lifetime. Both code paths are intentional (see architecture.md).
- **Env-import no-op `Proxy` in the runner** (`utils.ts` `runWasi`): returns a `() => 0` stub for any
  `env` import a module declares but the host doesn't supply (Phase 40 externals). Lets
  `declare const`-importing modules instantiate under `wasmtk run` without a real host. By design.
- **`modc` drops non-`export` top-level statements.** Library mode emits only `export function`s; a
  runner `main()` / module-level code in a modc input is intentionally ignored (it's a library, not
  an executable). By design.
- **Bump allocator with no `free`.** Allocations live for the instance lifetime; this is the documented
  DLL memory model (singleton or pool, see vision.md), not a leak to fix.

## Silent-stub audit (2026-06-05) — why a blanket "make stubs loud" was NOT done

The class-construction gaps were hard to find because the compiler emits silent comment-stubs
(`(;? … ;) 0` in `emitExpr`, `(;; … ;)` in `emitStatement`, and the `emitStringAssign`
complex-expression stub) for code it doesn't fully handle. The obvious fix — route all three to the
`this.diagnostics` channel (which **hard-aborts** the compile) — was **measured and rejected**:
temporary instrumentation logged **77 stub hits across the currently-passing suite**, almost all
**benign**: (a) discriminated-union type-declaration continuation lines (`| { kind: "rect"; … }`) and
multi-line literal element lines reaching `emitStatement` after the type/literal is already parsed
(genuine no-ops); (b) **speculative/pre-scan `emitExpr`/`emitStatement`/`emitStringAssign` calls whose
result is discarded** (e.g. type inference, the `s = "["; for(…)` string-gather mega-lines). The real
emission for those uses correct paths — the tests produce correct output. So a blanket abort would
break valid programs, and a blanket warning would flood noise people learn to ignore. **The stub
fallbacks are deliberate, load-bearing tolerance — keep them.**

The audit DID surface one genuine silent wrong-answer: the chained `s.at(i).charCodeAt(j)` fell to the
expr stub and returned 0 (the plain `charCodeAt` handler only matches a `\w+` receiver). **Fixed**
2026-06-05 with a targeted `atChainMatch` handler in `emitExpr` (norm-index → `$__str_char_code_at`).
Bare `.at()` in other contexts is already handled by the string paths (emitStringAssign /
emitStringPtrLen / parseSingleArg).

RULE going forward: when adding a NEW feature path, prefer pushing a `this.diagnostics` entry (which
aborts) over a silent stub — but do NOT retro-fit aborts onto the existing catch-all stubs (they
absorb benign remnants + speculative calls). For genuinely-broken merges, fail loudly: `wasmmerge`
throws on `call_indirect` inside a merged module (Phase 18 strips imported type sections, so the
table/type ref would dangle), and `main.ts` surfaces thrown errors as a clean `❌ wasmtk:` line.
