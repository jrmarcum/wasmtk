# Load-bearing design decisions

Invariants and codegen rules that are easy to break in a refactor and must NOT be silently
reverted. The exhaustive list (with line numbers) is in the legacy `CLAUDE.md`; this is the
high-value subset.

## A discriminated-union field shared by several variants is RESOLVED, never skipped (added 2026-07-30)

- **The union super-struct has ONE slot per field name, and its type must hold EVERY variant's
  value.** `buildDuSuperStructFields` resolves each unique name across all variants first, then
  lays out offsets from the resolved types. Do not go back to
  `if (seen.has(f.name)) continue` — that silently gave the slot the FIRST variant's type, storing
  `25.5` as the i32 `25` and emitting `i32.load` where an f64 was required. See compiler-bugs.md.
- **Widening is only legal between numeric scalars** (`widenDuFieldType`: i32/f32 → f64, i32 → i64).
  It is correct precisely because `i32`/`f64` are `number` aliases, so TypeScript sees one field
  type and no conflict — wasic must not be narrower than the source language here. `i64` vs `f64`
  does NOT widen: neither represents the other without loss.
- **Any other collision throws from the PARSER, not via `diagnostics`.** Diagnostics are reported
  only after a successful transpile, so a conflicting layout crashes downstream first and the
  user sees `Offset is outside the bounds of the DataView`. The parser is the only place that can
  name the union, the field, and both types.
- **The layout code is shared by both union parser passes** — inline `{…} | {…}` blocks and
  `type X = A | B` named variants. They were duplicated and had already drifted (only the named
  pass set `structType`). Keep them on the one helper; this is the same parallel-code-path trap as
  the binary-op loops below. Regression: `19_UnionSharedFieldWidening`.

## Namespace member references are rewritten inside the body (added 2026-07-30)

- **`expandNamespaces` must rewrite BOTH the declarations and the bare references.** Renaming
  `export const GRAVITY` → `PhysicsEngine_GRAVITY` without touching `return mass * GRAVITY` inside
  the same namespace leaves the body pointing at a name that no longer exists. Collect the member
  names BEFORE renaming, then substitute bare occurrences in the transformed body.
- **Three guards are load-bearing** and must not be dropped: skip occurrences inside a
  string/template literal (`buildStringLiteralMask` — otherwise a member name mentioned in a
  message gets mangled), after a `.` (a struct FIELD may share the member's name), and after `_`
  (the token is already prefixed, e.g. `Cfg_LIMIT`).
- **QUALIFIED uses are rewritten too: `Ns.member` → `Ns_member`.** This is what makes a namespace
  member an ORDINARY top-level symbol, so every existing path (string consts, the string-return
  side-channel, concat, comparison, arrays, structs) handles it without a per-type special case.
  Resolving qualified uses ad hoc at each site is what left `string` members broken — a
  `export const NAME: string` read as `0` and a string-returning namespace function failed to
  instantiate, because the numeric-constant and dot-call branches didn't know the string ptr/len
  ABI. Do NOT reintroduce per-site resolution; extend the rewrite instead.
- **The qualified rewrite matches only exact (namespace, member) pairs** collected during
  expansion, so an unrelated `obj.member` is never touched, and literal content is skipped by the
  same mask. Regression: `30_NamespaceStringMembers`.

## Narrowing must resolve to a REAL registered layout, never a synthesised one (added 2026-07-30)

- **A type predicate's target is only usable for narrowing if it names a layout that actually
  exists.** `emitBlock`'s predicate handler swaps the variable's `structVars` def for the target's;
  the pointer is unchanged, so the new def must describe the memory that pointer already refers to.
- **Never build a `StructDef` from an inline object type just to have something to narrow to.** Its
  offsets would be computed independently of the allocation the pointer refers to: it would agree
  with a matching declared type only by coincidence, and disagree with a DU super-struct by
  construction. `resolveInlineStructTarget` therefore MATCHES the inline shape to an existing
  registered def (exact field-name set + mapped WAT type) and returns `null` rather than inventing
  one.
- **Skipping narrowing is safe only when the variable's own def already covers every field the
  target names.** That is exactly the discriminated-union case — the Phase 32 flat super-struct
  carries all variants' fields at their real offsets — and it is why an inline DU predicate works
  with no narrowing at all. When a named field is NOT on the current def, there is no layout to read
  against and the compile aborts; do not downgrade that to a warning, because the read that follows
  is a plausible-looking wrong number (it printed `0` where TS printed `5`). Regressions:
  `34_InlinePredicateTargetNarrowing`, `34_InlinePredicateUnresolvable`.
- **The function-header return-annotation regex is a parse gate for the WHOLE function, not just the
  return type.** A shape it fails to match hits `continue // malformed header — skip`, so the
  function silently disappears from the module and its call sites report "Unknown function" — a
  diagnostic that blames the caller for a problem in the declaration. When adding a return-type form,
  remember failure mode is *function vanishes*, not *return type defaults*.

## A struct parameter's layout must be a PREFIX of the argument's (added 2026-07-30)

- **Structs are passed by pointer and the callee reads fields at ITS OWN parameter type's offsets.**
  Passing a different struct type therefore only works when the parameter type is a byte-exact
  layout prefix of the argument type (same field name, offset, WAT type and size). This has always
  been the model — Phase 33's README row states it — but until 2026-07-30 nothing enforced it, so
  `type Sprite = Renderable & Transform` passed to `(t: Transform)` silently read `alpha`/`scaleX`
  as `scaleX`/`scaleY` (printed `1.6`, expected `6`).
- **`checkStructArgLayouts` is a hard abort, not a warning.** Do not downgrade it. The program is
  valid TypeScript, so there is no downstream trap to catch it — the alternative is wrong numbers.
- **It runs at THREE call-emission sites**: the expression and statement forms in `wasic.ts`, plus
  `console_log.ts` via the injected `setStructArgLayoutChecker` hook (a call nested in a
  `console.log` argument never reaches `wasic.ts`'s emitters — this exact gap made the first version
  of the fix look like a no-op). Any new call-emission path needs the check too.
- **Intersection field order is therefore load-bearing.** `parseIntersectionTypes` merges
  constituents in declaration order, so `type T = A & B` is prefix-compatible with `A` and NOT with
  `B`. Do not "normalise" that order (alphabetically, by size, or to pack tighter) — it would break
  every base-typed parameter that compiles today. Regressions: `33_IntersectionBasePrefixGuard`
  (rejected shape), `33_IntersectionPrefixOk` (the four shapes that must keep compiling).

## Same-precedence operator groups split at the RIGHTMOST operator (added 2026-07-29)

- **`*`, `/` and `%` are ONE left-associative precedence group.** Both binary-op loops iterate an
  operator TABLE and split at the first match, so a group member appearing earlier in the table
  wins even when another member sits further right — that parsed `a * b / c` as `a * (b / c)`, i.e.
  right-associative, giving `180 * 5 / 9 = 0` and `180 * 5 % 9 = 900`. The `MUL_GROUP` guard skips a
  candidate when another member occurs further right. Do not remove it, and do not "simplify" it by
  reordering the table — no fixed order fixes both `a * b / c` and `a / b * c`.
- **The guard MUST exist in BOTH loops** — `emitExpr` (`wasic.ts`) and `exprToWat`
  (`console_log.ts`). Fixing only one left `console.log("x:", a * 5 % 9)` emitting
  `(i32.mul … (f64.rem …))`. These two loops are permanent parallel code paths: any operator
  precedence/associativity change belongs in both.
- **`+`/`-` intentionally have no guard.** `a + (b - c)` equals `(a + b) - c` in exact arithmetic, so
  there is no integer bug; they CAN differ in f64 rounding, which is a known, accepted nuance (the
  `+` path also carries string-concat logic, so changing it is higher-risk than the payoff).

## console.log operand typing: a literal or paren LHS has no type (added 2026-07-29)

- **The operand type is taken from the LHS lead atom, which an integer literal and a parenthesised
  group both lack** — so `console.log("x:", 1 + n)` and `console.log("x:", (n + 0) * 5)` emitted
  f64 ops over i32 operands and failed to instantiate, while `n + 1` worked. Both now fall back to
  the first TYPED atom: the RHS for an integer-literal LHS, inside the group for a parenthesised one.
- **The fallback must be applied in BOTH decisions** — `parseSingleArg` (which picks the segment
  KIND, `i32expr` vs `f64expr`) and `exprToWat` (which picks the WAT OPS). Fixing only one yields
  `$__i32_to_str` wrapped around f64 arithmetic.
- **A FLOAT literal LHS keeps f64** (`1.5 + n` is genuinely f64), and the fallback is deliberately
  NOT applied to a call LHS — scanning there would take an argument's type instead of the return
  type. Keep it narrow to those two shapes.

## String enums carry BOTH a tag and a text (added 2026-07-29)

- **Every string enum member gets a synthetic i32 tag, pure or heterogeneous.** Gating tag
  assignment on `hasString && hasNumeric` left a PURE string enum with no `enumValues` entry, so
  `const a: LogLevel = LogLevel.Error` and `a === LogLevel.Error` aborted as unsupported. The tag is
  the runtime representation; `enumStringValues` holds the display text.
- **Printing a string-enum VARIABLE needs the runtime ladder `$__enum_str_<Enum>`** — the variable
  holds the tag, not the text. `stringEnumVars` (populated from params and both pre-scans) drives
  `setEnumStrVarResolver`, which must be consulted BEFORE console_log's simple-identifier handler or
  the raw tag is printed. Member access (`LogLevel.Info`) stays a compile-time lookup.
- **The `$__str_op_ptr`/`$__str_op_len` prologue must cover it** — the ladder returns multi-value
  (ptr,len) captured into that pair; without the extra condition the WAT references undeclared
  locals.

## `console_log.ts` scanners must skip string literals too (added 2026-07-28)

- **`findTopLevelOp` in `console_log.ts` masks string literals via the local `literalMask()`.** It
  counts `()`/`[]` for depth; without the mask a closing `]`/`)` INSIDE a literal drove depth above
  0 and hid the top-level operator, so `console.log(w + "]")` silently printed `0`. This is the same
  bug class as the wasic-side scanners below — the console_log twin was simply never done. Do not
  remove the `if (inStr[i]) continue;` guard.
- **`literalMask()` is a deliberate DUPLICATE of `wasic.ts`'s `buildStringLiteralMask`.**
  `console_log.ts` is imported BY `wasic.ts`, so it cannot import back without a cycle. Keep the two
  implementations in sync; if one gains escape/template handling, mirror it.
- **Parity rule for join-like features:** `console_log.ts` may implement a fast path (e.g. the
  `joinarr` segment writing into the gather scratch buffer), but the feature must ALSO have a
  string-VALUE form reachable from `emitStringPtrLen`, or it works only inside `console.log`.
  `$__dynarr_join_str_i32`/`_f64` wrap the scratch writer to supply that value form.

## String methods: `emitStringPtrLen` must stay at PARITY with `emitStringAssign` (added 2026-07-28)

- **Every string-producing method must be implemented in BOTH entry points.** `emitStringAssign`
  handles the RHS of a string assignment; `emitStringPtrLen` handles a string used as a
  console.log argument, a comparison operand, or a call argument. A method present in only the
  first works when assigned to a variable and **silently emits `0`** when used inline — the
  compiler's worst failure mode, and exactly what happened to `trim`/`charAt`/`repeat`/`replace`/
  `replaceAll` from Phase 27 until 2026-07-28. When adding a string method, add it to both.
- **Resolve the receiver by recursing through `emitStringPtrLen`, never by gating on
  `locals.get(recv) === "string"`.** The recursion is what makes a variable, a string LITERAL, a
  string-array element, and a string-returning call all work with one handler (this is the
  long-standing `padStart` pattern). The `locals` gate silently rejects literal receivers.
- **`stringReceiverParts()` exists for the cases that need ptr and len SEPARATELY** — `slice`'s
  defaulted `end` and `.at`'s negative-index normalization can't use the multi-value pair. It
  returns null for unrecognized receivers so callers fall through to their existing paths; keep
  that null-return contract.
- **Gate on arity before emitting.** The generic Phase 27 block checks the arg count per method
  (0 for the trim family, 1 for `charAt`/`repeat`, 2 for `replace`/`replaceAll`) and falls through
  on a mismatch, rather than emitting a call with a mismatched signature.

## Struct-type detection uses the REGISTRY, not capitalization (added 2026-07-28)

- **Never gate a struct/class type annotation on `/^[A-Z]/`.** The authoritative test is
  `structDefs.has(name)` / `classDefs.has(name)`; the PascalCase spelling test is only a proxy and
  it is WRONG for `tsbundler` output — imported types are prefixed with the module's (lower-case)
  filename, so `Vec2` in `vec.ts` becomes `vec_Vec2`. That broke every multi-file struct import
  (`bundle_tests.ts` StructImport) and any hand-written lower-case interface. The eight
  struct-annotation regexes therefore match `(\w+)` and rely on the registry lookup that
  immediately follows; do not "tighten" them back to `([A-Z]\w*)`.
- **Ordering that makes this safe:** `parseStructs()` (18579) and `parseClasses()` (18580) both run
  before `parseFunctions()` (18606), so a registry lookup inside `parseFunctions` is populated. If
  a pass is ever reordered ahead of `parseStructs`, its struct-type lookups become empty.
- **The function-param `structType` gate is additive on purpose** — PascalCase OR a registered
  struct/class name. It has no registry guard downstream (unlike the other sites), so narrowing it
  to registry-only would drop TypedArray/DU/tuple-alias params that rely on the capitalization arm.
- **Do NOT "fix" this in the bundler** by capitalizing the mangled prefix: it hides the same bug for
  hand-written lower-case type names and breaks tsbundler's documented invariant that the canonical
  name is always `<module>_<original>`.

## Nullable (`T | null`) + cast invariants (added 2026-07-28)

- **Each `for…of` loop needs its OWN cursor local.** `forOfIdxLocal()` returns `__forof_idx` at
  depth 0 and `__forof_idx<N>` deeper; `forOfDepth` is incremented around the loop-body emission in
  BOTH for-of emitters (the `isStringArr` one and the general one). Do NOT collapse these back to a
  single shared `$__forof_idx` — the inner loop then clobbers the outer cursor and the outer loop
  runs exactly one iteration (silently wrong: a 3×2 matrix summed to 3 instead of 21). Depth 0 keeps
  the unsuffixed name deliberately, so non-nested loops emit byte-identical WAT. Both pre-scans
  declare one cursor per `for…of` statement (an upper bound on nesting depth), so any name
  `forOfIdxLocal()` can return is always declared.
- **A nullable annotation must NEVER fall through to the plain-module-global path.** In
  `parseModuleGlobals` the annotation group accepts `T | null`; when the nullable branch declines to
  promote, it MUST `remaining.push(line); continue;`. Letting it reach the ordinary global path
  registers a global with no `__null` companion while every reference site still emits
  `local.get $x__null` (this exact regression broke `24_NullUndefined` + `25_NullishOps`).
- **Module-level nullables are promoted to globals ONLY when a non-`_start` function references
  them.** A nullable used purely at top level stays in `startBodyLines` and becomes a `_start` local
  with its `$x__null` companion local — which is what every existing nullable reference site emits.
- **`moduleNullableGlobals` is persistent; `nullableVarInnerType` is per-function.** Re-seed the
  latter from the former after BOTH resets (`emitFunction` and the `_start` pre-scan), or `g ??= v`
  stops resolving inside function bodies.
- **Set `needsNullableResultFlag` at the site that REFERENCES `$__nullable_ret_flag`** (the
  nullable-return branch), not only where nullable variables are declared — a caller relying on
  inference (`const n = maybeGet()`) otherwise leaves the global undeclared.
- **A `T | null` function returning an aggregate literal must delegate to the aggregate-return
  emitters.** The nullable-return branch short-circuits with a plain `emitExpr`; for `[…]`/`{…}`
  whose return type resolves to a `StructDef`, hand off to the struct/tuple paths instead, or the
  generic array-literal emitter assumes uniform elements and emits `(i32.const 3.14159)` for an f64
  tuple field. Keep the `StructDef` guard so plain `i32[] | null` returns keep their own path.
- **`expr as T` must not assume an `i32` source for compound expressions.**
  `compoundExprIsAlwaysF64()` types the two forms that `emitExpr` emits as f64 regardless of the
  requested `defaultType`: a depth-0 `**` (always `$mathlib_pow`) and a whole-expression
  `Math.fn(...)` whose `fn` is not in `MATH_I32_AWARE` (`abs`/`min`/`max`/`imul`/`clz32` — the only
  handlers that branch on `defaultType`). Keep it whole-expression-only: a merely f64-*containing*
  expression must keep the i32 default. Do NOT replace it with a blanket `inferExprType` fallback —
  `inferInitType` returns "f64" for anything parenthesized, which breaks parenthesized i32
  arithmetic cast to f64.
- **`??` inside `console.log`/`console.error` args routes through `setNullishResolver`.**
  `console_log.ts` has no view of the nullable tables, so it delegates to `emitExpr`. The check must
  sit BEFORE the boolexpr and ternary blocks in `parseSingleArg` — the `_hasTernary` probe matches
  the leading `?` of `??` and otherwise swallows it. (Same singleton pattern as
  `_instanceofResolver`; set and cleared around each `parseConsoleLogArgs` call at BOTH sites.)

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
- `cabi_realloc` is exported (not `__malloc`) when any export has a string param/return. String
  returns use a **callee-allocated pair-pointer** shim (`$fn__cabi`, `wasic.ts` ~19145): it
  `cabi_realloc(0,0,4,8)`s an 8-byte area, calls the internal `$fn` (which sets the `$__str_ret_*`
  globals), stores `[ptr,len]` into that area, and RETURNS the area pointer (i32). A paired no-op
  `cabi_post_<name>` export lets the host release it after reading. `bindgen.ts` reads the returned
  pointer (`getInt32(_r)` / `getInt32(_r+4)`) then calls `cabi_post_<name>` — it does NOT allocate a
  return area host-side. The `$__str_ret_*` globals are NOT exported.
  (Historical note: Stage 0 originally specified the *out-parameter* convention — caller allocates
  the 8-byte area and passes it as a trailing `$__ret_area` arg. The ABI later moved to this
  callee-allocated pair-pointer + `cabi_post` form; older references to an "out-param shim" are
  stale. This is the canonical form and matches the Go `strlib` fixture and `strlib.go`.)

## `hybrid` call-rewriting / body-extraction MUST be context-aware (2026-07-08)

`src/hybrid.ts`'s three scanners — `findCloseBrace` (extract a `@wasm` body), `isMethodDefinition`
(call vs `name(){` definition), and `rewriteWasmCalls` (`name(` → `lib.name(`) — process ARBITRARY
user TypeScript, so they must NOT be naive brace-counters or lookbehind regexes. They share a
`skipLiteral(src, i, prevSig, prevWord)` primitive that treats **strings, templates, `//`/block
comments, AND regex literals** as opaque, with `regexCanPrecede()` disambiguating a regex `/…/`
from division by the previous significant token (a value / keyword). Load-bearing rules:

- A regex literal containing a quote/brace/paren (`/["'{}]/`, `/}{/`) must NOT flip string/brace/
  paren state — else it silently disables all downstream rewrites (→ runtime `ReferenceError`) or
  truncates a body. Do not revert to a scanner that only tracks `"`/`'`/`` ` ``/comments.
- `rewriteWasmCalls` DESCENDS into template `${…}` interpolations (via `findInterpEnd` + recursion)
  so a routed call inside `` `${add(x)}` `` is still rewritten. A blind opaque-template approach
  regresses this (the pre-2026-07-08 naive regex rewrote it by accident).
- `isMethodDefinition` is the guard that keeps an object method shorthand (`{ add(x){…} }`) from
  being rewritten; it must skip strings/regex inside the arg list so a `)` there doesn't misparse.
- **Nested backtick inside a `${…}` interpolation — CLOSED (B5, 2026-07-09).** `skipLiteral`'s
  backtick branch now descends into each `${…}` interpolation via `findInterpEnd` (mutually
  recursive, so arbitrarily-nested templates are handled) instead of scanning greedily for the next
  backtick — which mistook a nested opening backtick for the outer template's close. The observable
  bug: a nested template whose TEXT holds a `}` leaked that brace into depth counting →
  `findCloseBrace` truncated a `@wasm` body early (proven: 68 vs 82 chars), and `findInterpEnd`
  mis-scanned a doubly-nested interpolation → a routed call in it was NOT rewritten. Both cases are
  regression-tested in `tests/hybrid_tests.ts` (the two "(B5)" tests — verified to fail without the
  fix). No known residual scanner edge remains.

## Producer shims must be runtime-agnostic (`rt.*`, not `Deno.*`) (2026-07-08)

`src/gowasic.ts`'s `SHIM_TS` (the passthrough wasm-opt shim TinyGo execs when no real `wasm-opt` is
on PATH) runs as a standalone script under whatever `rt.execPath()` returns, so it detects its own
runtime (`typeof Deno`/`typeof Bun`) and its launcher branches: Deno needs `run -A`, Bun execs the
file directly (`-A` is a hard Bun parse error). All file I/O in gowasic proper goes through `rt.*`
(added `rt.chmod` + recursive `rt.remove`), never `Deno.*` — same Bun-compat rule as the runner.

## WIT type handling fails loud, not silent (2026-07-08)

`witTypeToWat` (wasic overlay) and `parseWitType` (bindgen) cover all scalar int WIT types and
THROW on unknown/aggregate types (`list<>`, `tuple<>`, record) rather than silently mapping to
i32/s32; `parseWitFuncs` rejects multi-value/tuple returns. On the merge path, `readWitLogicalSigs`
swallows ONLY file-absence (numeric-only lib → empty overlay); a parse/type error propagates, and
the per-import merge `catch` RE-THROWS any `wasic:`-prefixed diagnostic instead of downgrading it to
a "skipping" warning (which buried it, then failed later with a confusing "unknown function"). Only
reachable via a hand-written `.wit` — wasic emits only the supported subset.

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
- 🔑 **VERSIONS CARRY NO COMPATIBILITY MEANING — they are a sequential counter (owner directive
  2026-07-30).** The owner does **not** read version changes as "minor vs major" in the semver
  sense; a release number states only *how many releases have happened*, never what changed in
  them. Consequences, all binding:
  - **Never infer breakage from a version number, and never tell a user to.** A leading-digit
    change is AMBIGUOUS by construction — see the next bullet — so the number can never be the
    answer on its own.
  - **A round number may be reached two different ways (owner caveat 2026-07-30):** (a) the counter
    simply carried, which happens about every 100 releases regardless of content, or (b) the owner
    **deliberately advanced to a round number to mark a breaking change**, which is what
    `1.11.12 → 2.0.0` was and which **may be done again** for a future breaking change. The
    mechanism for (b) is `deno task bump major`. Because both produce an identical-looking number,
    **the number is not self-describing** and must never be interpreted without the table.
  - **The README's `### ⚠️ Breaking Changes` table is the ONLY signal of breakage, and the ONLY
    thing that disambiguates (a) from (b).** That is precisely why the owner asked for it and why it
    stands apart from Feature Status: it tells users *what just happened and why*. If a round number
    ships with nothing breaking, the table simply has no row for it. Every deliberate (b) jump MUST
    get a row — a jump with no row is indistinguishable from a carry and defeats the whole point.
  - **Do not "correct" a version choice with semver reasoning.** `2.0.0` was not derived from a
    rule that "a removed export requires a major"; it was the owner choosing a legible number for a
    breaking release. The choice is discretionary — do not turn it into an automatic mapping from
    change-kind to component, and do not assume the next breaking change must also land on a round
    number.
  - The `patch` / `minor` / `major` arguments to `deno task bump` are therefore just **positions to
    increment** (rightmost / middle / leftmost), not statements about compatibility. Read them as
    "carry one position left", not as semver intent.
- **ODOMETER VERSION SEQUENCING (owner directive 2026-07-30).** The **minor and patch components
  must never exceed 9.** Reaching 9 rolls that component to 0 and carries 1 into the component on
  its left; `major` alone is unbounded (9 → 10 → 11 …):

  | From | Bump | To |
  | --- | --- | --- |
  | `1.6.2` | patch | `1.6.3` |
  | `1.2.9` | patch | `1.3.0` |
  | `1.9.9` | patch | `2.0.0` |
  | `0.9.9` | patch | `1.0.0` |
  | `1.9.4` | minor | `2.0.0` |
  | `9.9.9` | patch | `10.0.0` |

  Implemented in `scripts/bump.ts` (`MAX_COMPONENT = 9`, carry applied patch-first so `x.9.9`
  cascades all the way to `(x+1).0.0`). All of the above are covered by a boundary-case check that
  was run against the logic before it shipped.
- **This is deliberately NARROWER than semver**, which permits multi-digit components — `1.11.12`
  is valid semver and this project published it (76 versions exist, several with a minor/patch above
  9). So the rule is forward-only; it does not, and cannot, re-describe the published history.
  **`bump` therefore REFUSES to run from a version whose minor or patch exceeds 9** rather than
  guessing a carry (from `1.11.12`, is the next one `1.12.0`? `2.0.0`? `2.2.3`? — every answer is a
  silent wrong release number). It exits non-zero **without writing**, telling the owner to set
  `deno.json` by hand and run `deno task update-version`. That state was cleared on 2026-07-30 by
  going `1.11.12` → **`2.0.0`**, so `bump` works normally from here; do not "helpfully" replace the
  refusal with a fallback carry.
- ✅ **`main.ts` + `src/` ARE fmt-clean again as of 2026-07-30, and the fix is now STABLE.** It had
  drifted to 8 of 21 files failing. The reason the claim kept going stale is the important part:
  - **`deno fmt` emits LF; this machine's git runs `core.autocrlf=true` and hands out CRLF on every
    checkout.** They fight permanently. Formatting the tree fixes `deno fmt --check` only until the
    next checkout re-converts to CRLF, at which point files fail with *"Text differed by line
    endings"* and **no content diff at all**. Measured, not assumed: after formatting, deleting
    `src/zigwasic.ts` and `git checkout`-ing it brought CRLF straight back and re-broke the check.
  - **Settled with a `.gitattributes` carrying `*.ts text eol=lf`.** The blobs were ALREADY stored
    as LF (verified: `git show HEAD:src/utils.ts` had 0 CRLF, the worktree copy had 523), so this
    rewrites no history — it only stops the checkout filter converting them back. A fresh checkout
    now yields LF and passes. **Do not remove this file**, and do not "fix" CRLF failures by
    reformatting; reformatting treats the symptom and lasts until the next checkout.
  - The 130 worktree `.ts` files that were still CRLF were converted in place; `git diff --numstat`
    was **empty** afterwards, confirming zero content change (git had been normalising them all
    along).
  - **`.wast` is NOT pinned, and that is a live trap (noted 2026-08-20).** `.gitattributes` covers
    `*.ts` only. The vendored spec corpus under `tests/module/wasm_wast/testsuite-main/` is currently
    LF in both the blob and the worktree, so nothing is broken — but `core.autocrlf=true` means git
    warns it will hand out CRLF on the next checkout. That would silently break the byte-for-byte
    diff against upstream that makes a corpus sync verifiable (see [testing.md](testing.md)
    § "Vendored spec testsuite"). **If it ever bites, add `*.wast text eol=lf`** for exactly the
    reason `*.ts` is pinned — do not fix it by rewriting the vendored files, which are upstream's
    bytes and must stay that way.
  - **`wabt-ts` moved to an exact `1.4.1` pin on 2026-08-25** once the three malformations it exposed
    were fixed. **The pin and the `try_table` migration are INSEPARABLE: 1.3.5 cannot encode
    `try_table` at all** (every handler form is an ENCODE-FAIL), so the emitter change cannot land on
    the old backend. Anyone reverting the pin must revert the emitter too, or the compiler emits WAT
    its own assembler rejects. Still exact, not a caret — the constraint is correctness, not
    compatibility.
  - **`minimumDependencyAge: "PT1M"` STAYS — owner directive 2026-08-25. Do not "clean it up".**
    Deno's default 24-hour guard exists to stop a freshly-published malicious version from being
    pulled in unnoticed. That threat model does not describe this repo: **both backends are
    first-party (`@jrmarcum/wabt-ts`, `@jrmarcum/binaryen-ts`), EXACT-pinned, and bumped deliberately
    in lockstep with a full regression gate.** The versions we install are ones we asked for, in
    response to bugs we reported. The guard's only effect here is to block a same-day backend fix for
    a day — which is exactly what it did to 1.4.1 and 1.5.0.
    - Use the ISO-8601 form. `"1h"` is **rejected**; `"PT1H"` / `"PT1M"` are accepted.
    - The safety that actually protects this repo is the **exact pin plus the gate**, not the age
      guard. Loosen either of those and this entry becomes wrong.
  - **`binaryen-ts` is EXACT-pinned at `1.5.0` (2026-08-25), for the same reason and by the same
    lesson.** It was `^1.4.3`; 1.5.0 is what *reads* the multi-value block a `try_table` handler
    produces. The caret came off because a caret is exactly how 1.4.0 got in and regressed us —
    **both backends are now exact pins. Neither may move without a full gate**, because both are code
    generators whose *output text* we parse.
    - 🔒 **`try_table` modules SKIP binaryen `-Oz` — do not remove that branch on a version bump
      alone.** 1.5.0 fixed the reader and then silently miscompiled the same modules: `-Oz`
      CoalesceLocals merges a local live across a `try_table` catch edge, so an inner `catch (e)`
      can overwrite an outer `e`. Reading the module is not the same capability as optimising it,
      and the version that gained the first did not gain the second. Full post-mortem in
      [compiler-bugs.md](compiler-bugs.md); **the gate for lifting it is `15_Exceptions` +
      `15_LexicalShadowing_Stress`, never the acceptance fixture alone.**
  - 🔒 **INVARIANT — never require a bracketing you did not emit.** wabt prints const-exprs folded
    (`(i32.const N)`) or unfolded (`i32.const N`) depending on version; 1.4.1 switched. Read them
    only through `constExprValue` / `replaceConstExpr` in `src/wasmmerge.ts`, which accept either and
    preserve what they found. This is enforced by grep, not by types:
    **`grep -rn -F '\(i32\.const' src/*.ts` must come back empty.** A hard-coded bracketing does not
    throw when the printer changes — it silently reports "no data segments", which collapses data
    relocation and seats the heap inside static data. It cost a hung suite to find; see
    compiler-bugs.md.
  - **`wabt-ts` is EXACT-pinned (`1.3.5`, no caret) as of 2026-08-25 — a CORRECTNESS pin, not a
    compatibility range.** 1.4.0 is a stricter validator that rejects three classes of malformed WAT
    we emit (see compiler-bugs.md), so it must not arrive by accident. It nearly did: with `^1.3.5`
    the lockfile was the only thing holding 1.4.0 back, and one config change let a reload pull it
    in — the `wast` gate went 156 files off-baseline while `deno.json` still said 1.3.5.
    **Restore the caret once the three malformations are fixed and the bump is deliberate.**
    `binaryen-ts` keeps its caret; that constraint really is about compatibility.
  - **`deno.json` MUST STAY STRICT JSON — no JSONC comments (learned 2026-08-25).** Deno itself
    accepts comments, but `scripts/sync-version.ts` reads the file with `JSON.parse`, and
    `deno task install` chains `update-version` → that script. Adding one `//` comment to document a
    setting broke `deno task install` outright. Document settings in `cmem/`, not inline.
  - **`minimumDependencyAge: "PT1H"` (set 2026-08-25, owner decision).** Deno blocks JSR versions
    younger than 24h by default as a supply-chain guard; wabt-ts 1.4.0 was 13h old and carried three
    fixes we were blocked on. Deliberately **not `"0"`** — a zero-age publish is the case the guard
    exists for, and an hour still catches a package pulled immediately after being compromised. The
    value is an ISO-8601 duration or a count of minutes; `"1h"` is REJECTED (`expected minutes,
    RFC3339 datetime, or ISO-8601 duration`).
  - **Real content drift existed too and is now fixed**: `src/bindgen.ts` (40 diff lines),
    `src/hybrid.ts` (16), `src/wasic.ts` (6), `src/console_log.ts` (5), `src/wast.ts` (4).
  - **`src/wasm/` is excluded from fmt via `deno.json` → `fmt.exclude`.** Both files there are
    `AUTO-GENERATED` byte arrays; `src/wasm/mathlib_bytes.ts` is 5 lines holding one enormous array
    that `deno fmt` wants to explode into ~9,000. The generators own those files' shape — never let
    fmt fight them. Note `exclude` applies to the DIRECTORY form (`deno fmt main.ts src/`); passing
    an excluded file explicitly still formats it.
  - **Scope stays `deno fmt main.ts src/`** — never bare `deno fmt`, which would reflow the 214 KB
    README and every `cmem/*.md` (mangling tables and code fences).
  - Reformatting touched `wasic.ts`/`console_log.ts`, i.e. the compiler, so the full gate was run
    after it (see testing.md). fmt is still not CI-gated and not a JSR score factor.
- **Keep the published TypeScript (`main.ts` + `src/`) `deno fmt`-clean.** As of 2026-06-02 it
  passed `deno fmt --check main.ts src/` (one-time reflow to the deno.json fmt config: lineWidth
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
- **`deno doc --lint` clean does NOT mean 100% documented symbols.** Measured 2026-07-30: the lint
  passed on all 16 entrypoints while JSR reported `percentageDocumentedSymbols: 0.98039216`. That
  number is exactly **100/102**, and the 2 it counted undocumented were the bare re-exports in
  `src/utils.ts` — `export { compileWasi } from "./wasic.ts"` and
  `export { compileModule } from "./modc.ts"`. **A JSDoc comment above an `export … from` cannot fix
  this.** Verified by probe: when the defining module and the re-exporting module are BOTH doc
  entrypoints, `deno doc` collapses the re-export to a `kind: "reference"` node carrying no jsDoc,
  no matter what is written above it. **`deno doc --lint` never flags it** — use
  `deno doc --json <entrypoints>` and count `declarations[].jsDoc.doc` per exported symbol.
- **The precise rule (probed 2026-07-30): `deno doc` documents each underlying DECLARATION exactly
  once per run, at whichever export it resolves FIRST; every other export of that same declaration
  becomes a bare `kind: "reference"` with no jsDoc.** It is keyed on declaration identity, NOT on
  module layout — swapping the argument order of two re-exporting entrypoints flips which one is
  credited. Consequences, all measured:
  - Moving the definition to the other module just relocates the `reference` (1/2 either way).
  - A shared non-entrypoint `common.ts` that two entrypoints both re-export is **also 1/2**; adding
    `common.ts` to the export map makes it 1/3. **No module reorganisation can fix this** — two
    public exports of ONE declaration can only ever be documented once.
  - A true CONSUMER (imports and uses, does **not** re-export) costs nothing and is not counted.
- **FIXED 2026-07-30 by REMOVING the duplicate export, not by working around it** (now **100/100**,
  and note the denominator fell 102 → 100 — the duplicate declaration is gone rather than papered
  over). `src/utils.ts` no longer re-exports `compileWasi`/`compileModule`; `main.ts` imports them
  from `./src/wasic.ts` and `./src/modc.ts` directly, the same pattern it already used for
  `compileDyn`.

  **Why this was the right fix rather than the wrapper that was tried first.** `src/utils.ts` is the
  CLI's helper barrel — it has re-exported these since before the `src/` restructure so `main.ts`
  could import every command from one place. But `deno.json` has published **every** module as a JSR
  entrypoint since the first commit, so an internal convenience barrel became public API by
  accident. The README's Programmatic API table documents `compileWasi` under **`./wasic`** and
  `compileModule` under **`./modc`**; `wasmtk/utils` appears **0 times** in the README; and the
  duplicate had exactly **one** consumer in the whole repo — `main.ts`. So the duplication bought
  nothing and was never intended as public surface.
- **Do NOT re-add the re-export to save an import in `main.ts`.** That is what created the problem.
  If a future module needs these, import from `./wasic.ts` / `./modc.ts`.
- **A pass-through wrapper (`export async function x(…) { return await _x(…) }`) also reaches 100%
  and was implemented, then reverted.** Recorded so it is not re-attempted as a first resort: it is
  credited and keeps `kind: "function"`, but it hand-duplicates the signature, so adding a new
  **optional** param to an impl does NOT fail `deno check` — it silently stops being forwarded. No
  type-level guard catches that (`const g: typeof impl = wrapper` passes, since fewer params are
  assignable). It is the right tool only when the duplicate export must genuinely stay public;
  removing the duplicate is strictly better when it need not. The `export const x: typeof _x = _x`
  form is drift-proof but renders as `variable`, losing the function signature.
- **None of this moved the JSR score, and it was never going to.** JSR's scoring doc states *"you do
  not need to complete all factors to get a 100% score"*; the package already reported **100** at
  98.04% documented. Justify this work as API hygiene and correct rendering on jsr.io — **not** with
  the score number.
- **A module JSDoc needs an explicit `@description` tag, or its description renders EMPTY.**
  `deno doc` treats everything after the first tag as that tag's value, so
  `/** @module foo` + bare prose yields a module with **no** description. 15 entrypoints used
  `@module x` + `@description …`; `src/wast.ts` used `@module wasmtk/wast` followed by bare prose
  and so had an empty module description on jsr.io (fixed 2026-07-30). Module names are also bare
  (`wast`, not `wasmtk/wast`). Check with
  `deno doc --json <entrypoints>` → `nodes[file].module_doc.doc`, not with `--lint`, which does not
  catch it.
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
- 🔴 **Provenance has been ABSENT since v1.11.3 (found 2026-07-30) — 10 releases. Cause traced to
  the Deno version; `deno-version` is now PINNED to `v2.9.1`.** Bisected against the JSR API
  (`api.jsr.io/scopes/jrmarcum/packages/wasmtk/versions/<v>` → `rekorLogId`): **v1.11.2 (2026-07-03)
  is the last version with a Rekor entry** (`2053916008`); **v1.11.3 (2026-07-09) is the first
  without**, and every release since — including v1.11.12 — is `null`.
  `.github/workflows/publish.yml` had not changed since 2026-06-15 (commit `e64595f`), i.e. it was
  byte-identical to what produced provenance for v1.11.2, `git diff v1.11.2..v1.11.3` touches only
  `deno.json` deps, and the JSR↔GitHub repo link is intact — so nothing in the repo explained it.
  **The workflow floated `deno-version: v2.x`, so every release picked up whatever Deno was newest
  that day, and the history splits EXACTLY on a Deno release boundary:**

  | Deno used | wasmtk releases | Provenance |
  | --- | --- | --- |
  | ≤ 2.9.1 (2.9.1 shipped 2026-07-01) | v1.7.0, v1.11.1, v1.11.2 | ✅ present |
  | ≥ 2.9.2 (2.9.2 shipped 2026-07-08) | v1.11.3 … v1.11.12 (ten) | ❌ absent |

  ❌ **The Deno version was TESTED and RULED OUT — do not re-try it.** The split above looked
  causal, so **v2.0.0 was published with `deno-version: v2.9.1` pinned** (2026-07-30) — the exact
  version that produced attested releases a month earlier. **It published with no provenance
  anyway** (`rekorLogId` null; the tag genuinely carried the pin, verified with
  `git show v2.0.0:.github/workflows/publish.yml`). So the 2.9.1/2.9.2 correlation was coincidental.
  The pin was reverted to floating `v2.x` immediately afterwards — it bought nothing and only cost
  the 2.9.2–2.9.4 fixes. Corroborating: no Deno release note from 2.9.2 through 2.9.4 mentions
  provenance at all (2.9.4's only publish entry is `fix(publish): constrain generated source
  rewrites`, unrelated).

  **Remaining suspects: JSR-side or GitHub-side changes in the 2026-07-03 → 07-09 window.** What is
  already known-good and needs no re-checking: `publish.yml` (unchanged since 2026-06-15 and
  byte-identical to what produced attested releases), `id-token: write`, the OIDC prerequisite step
  (passes, no `::warning::`), the JSR↔GitHub repo link (intact), and the absence of
  `--no-provenance`. **The next diagnostic needs an authenticated `gh`** (not installed here; the
  Actions logs endpoint 403s unauthenticated): `gh run view <id> --log` on the v1.11.2 vs v1.11.3
  runs. The "Verify provenance was recorded on JSR" step will detect a fix whenever one lands.
- **The OIDC diagnostic step is NOT sufficient evidence of provenance — it gave 10 releases of false
  assurance.** It checks only the PREREQUISITE (are the OIDC env vars present), and the v1.11.12 run
  emitted no `::warning::` at all (verified via the check-runs annotations API — its one annotation
  is an unrelated Node 20 deprecation notice), yet provenance was still absent. **A green publish run
  is not proof of provenance; only JSR's `rekorLogId` is.** A **"Verify provenance was recorded on
  JSR"** step was therefore added as the LAST step of the workflow: it polls the JSR version API and
  fails the job if `rekorLogId` is null. It runs last on purpose, so a failure surfaces the problem
  without blocking the publish or the GitHub release (JSR versions are immutable — by the time this
  runs, the version exists either way). Logic verified locally against both sides of the bisect:
  1.11.2 → PASS, 1.11.12 → FAIL.
- **Provenance is NOT what is holding the score.** JSR's scoring doc states *"you do not need to
  complete all factors to get a 100% score"*, and the package reports `score: 100` with
  `hasProvenance: false`. Provenance is worth fixing as a **supply-chain/trust** property (SLSA
  attestation linking the artifact to the building workflow), not to move the number — do not
  justify the work with the score, it will not change.
- **Reading CI logs needs auth and `gh` is NOT installed on this machine.** The GitHub Actions logs
  endpoint returns 403 unauthenticated, so the Deno version each run used could not be read. The next
  diagnostic step for provenance is `gh run view <run-id> --log | grep -i "deno\|provenance"` on the
  v1.11.2 vs v1.11.3 runs (ids `30569718486` is v1.11.12; list with
  `gh run list --workflow=publish.yml`), comparing the resolved `deno-version`.

- 🆕 **Three more suspects RULED OUT (2026-08-27), from the binaryang side.** Reported by the
  binaryang merge, which published three packages from this same scope on the same day and hit — and
  then did not hit — the same problem.

  1. **A global JSR- or GitHub-side change is REFUTED.** That was the standing leading hypothesis
     ("remaining suspects: JSR-side or GitHub-side changes in the 2026-07-03 → 07-09 window").
     `binaryen-ts@1.5.1`, `wabt-ts@1.5.1` and `binaryang@1.5.1` all published **attested** on
     2026-08-27 — `rekorLogId` 2618865672, 2618866200 and 2618802426. Provenance works on this
     account, this scope and this workflow shape today. **Whatever this is, it is specific to
     wasmtk.**
  2. **`usesNpm` is not it.** The JSR version metadata reports `usesNpm: true` on **both** sides of
     the boundary — v1.11.1 and v1.11.2 (attested) as well as v1.11.3 onward (not). The npm
     dependency is not the discriminator.
  3. **A cached/stale API read is not it either.** The absence was re-verified with cache-busted
     requests: v1.11.2 returns `rekorLogId` 2053916008, and v1.11.3, v1.11.5, v1.11.12 and v2.0.0
     all return null with `updatedAt == createdAt`. **The absence is real.**

- 🆕 **The verify step could not have been believed — it did not cache-bust. FIXED.** The JSR version
  endpoint is cached, and attestation is written a few seconds AFTER publish, so a plain re-read can
  keep returning the pre-attestation record for minutes.

  Measured on `wabt-ts@1.5.1`: **eight consecutive plain reads over ~3 minutes all returned null**,
  while a single cache-busted read returned `rekorLogId` 2618866200, written 4 seconds after publish.
  That release had provenance the whole time and was briefly reported as having none.

  For wasmtk the bug has been **masked by a true negative** — the step failed, and provenance really
  was absent — so it cost nothing so far. It would cost everything at exactly the wrong moment:
  **when provenance starts working again, the uncached step could still report failure**, hiding the
  fix. `publish.yml` now sends `Cache-Control: no-cache` and a unique `?cb=` per attempt.

  **The tell, worth knowing without any tooling:** an attested version has `updatedAt` a few seconds
  after `createdAt`. Equal timestamps mean not-yet-attested *or* never-attested, and only a
  cache-busted read tells those two apart.

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
