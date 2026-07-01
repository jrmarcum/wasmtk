# Compiler bug log

Live record of bugs found + fixed. Newest first. **✅ NO SUITE-FAILING BUGS — full suite 360/360** (`bindgen` 131/131, `jstyper` 73/73, `dync` conformance 3/3) as of **2026-06-30** (#14 Route A 2e.6 try/catch `18zh` + 2e.7 block scoping `18zi` + 2e.7a per-iteration let `18zj` + 2e.7b var→let gate `18zk`/`18zl`/`18zm` + 2f.1 this+prototype `18zn` + 2e.8 classes `18zo` + 2e.8a class completion `18zp` + 2f.2 array methods `18zq` + 2f.3 string methods `18zr` + 2f.4 object+math `18zs` + 2f.5 JSON `18zt` + 2f.6 map+set `18zu` + 2f.7 regexp `18zv` + 2e.9 generators `18zw` + 2e.10 async `18zx` + 2e.11 remaining ES6 `18zy` + 2h full-dynamic-compile/javyc-retirement `18zz`).

**#14 2h (2026-06-30) — three interpreter/compiler fixes surfaced building `wasmtk dync`:** (1) **interpreter HANG on a multi-byte UTF-8 char in a comment** — `evalSkipWs` had NO comment handling; line/block comments "worked" only by accident via a downstream parse path that LOOPED on a high byte (e.g. an em-dash `—` in `// …`). FIXED by giving `evalSkipWs` real `//` and `/* */` skipping (safe: the interpreter has no regex LITERALS — RegExp is `new RegExp("…")` — so `//`/`/*` are unambiguously comments). (2) **`Math.min`/`max` were 2-arg only** in `dynMathMethod` (ignored args 3+; `Math.min(3,7,2)`→3) — now variadic; caught by the dync conformance gate. (3) **wasic source scanner is string-blind to `{`** (KNOWN limitation, worked AROUND not fixed): a module-level string literal CONTAINING a brace makes `parseTopLevel`'s regex brace-count mis-count depth and split the line on `;` inside the string (`const s = "function f() {\n …;\n}"` → "Unsupported statement" fragments). `dync` sidesteps it by **base64-embedding** the program source (alphabet has no `{}`/`;`/`"`/newline). A proper fix would make `parseTopLevel` mask strings via `maskCode` — deferred (higher regression risk; not needed for any current path). (+`18j`–`18t` dynrt: value-model / virtual
import / eval / eval-env / calls / statements / functions+`new Function` / `18q` wasic `any`
type+auto-merge / `18r` GC Part 1 auto-grow heap / `18s`-`18z` GC Parts 2-5b + polish COMPLETE (… / splitting / hybrid segregated+coalescing allocator). 4 known wasic gaps are OPEN but worked around in the dynrt library — see next
section; 2d.1/2d.2/3.1 added none. 3.1 has its own documented FOLLOW-UPS — see dynrt-design.md
"Increment 3 → 3.1": any-param unbox, `as string` unbox, inline-cast comparison, non-literal boxing). 3 KNOWN wasic
gaps are OPEN but worked around in the dynrt library (so the suite stays green) — see the next
section; each is a candidate for a real `src/wasic.ts` fix (then the lib workaround can be removed,
the RegExp `&&` precedent). (Pre-18j: 317 = 307 at v1.7.0 + 2 Phase-53 tests + 8 async tests 54–61;
`bindgen` 103→104 from the ABI return-side forward-alignment's `cabi_post` assertion.)

## FIXED — wasic `parseClasses` was string-blind: `class …{}` inside a STRING parsed as a real class (#14 2e.8, 2026-06-26)

Surfaced building #14 2e.8 (classes in the dynrt interpreter): the test driver passes eval-source STRINGS
like `"class Point { constructor(x){ this.x = x; } … } const p = new Point(5); …"` to `dynRun`. wasic's
`parseClasses` (`src/wasic.ts`) ran its `class\s+(\w+)…{` regex over the RAW `this.src` (string-blind), so
it matched `class Point {` INSIDE the driver string, brace-counted the body over the raw source (string
braces miscounted), and extracted a bogus class — leaking its constructor/method bodies as 11 "Unsupported
statement: this.x = x;" errors. **Fix:** detection now runs over a CODE-ONLY mask
(`maskCode(this.src)` from `src/varscope.ts` — string/comment chars → spaces, length preserved) for BOTH
the `classRe` match and the body brace-count; the class body is still SLICED from the real source (valid
because maskCode preserves positions). Same string-blind class as the earlier `=>` / `?.` / `eval(` /
`Function(` fixes — `maskCode` is now the shared code-only primitive (it also backs the 2e.7b var gate).
General wasic improvement: any real wasic program with `class …{}` text inside a string literal now
compiles. Regression test: `18zo` (the 2e.8 pipeline). Full suite re-validated 349/349 — real class tests
(Phase 9/16/17/47) unaffected (maskCode only blanks string/comment CONTENT, leaving real `class` decls
visible).

## FIXED — `deno fmt` wrapped a deeply-indented ternary that modc can't parse (process bug, 2026-06-26)

Found building #14 2e.7: the dynrt lib (`tests/wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts`) is
compiled by **`modc`**, whose body-line joiner does NOT handle a multi-line (wrapped) ternary. Three
deeply-indented ternaries in the 2e.4 member/index-assign path (16-space indent, >100 cols) — e.g.
`const cur: i32 = isDot === 1 ? dynMember(container, segKey) : dynIndexValue(container, segIdx);` — were
WRAPPED by `deno fmt` into `const cur =\n  ? …\n  : …` form, which modc reports as `Unsupported statement:
? dynMember(...)` / `: dynIndexValue(...)` and aborts. **This had silently shipped in v1.10.6's committed
SOURCE** (the lib no longer round-tripped through modc) — but the shipped RUNTIME was unaffected because
`caps_bytes.ts` is generated from the PRE-`fmt` compiled `.wasm`, and the suite passed because the
`@test-pipeline` `modc` step ran on the on-disk lib BEFORE the end-of-increment `deno fmt`. **Fix:**
converted the three fragile ternaries to single-line `if/else` (fmt-stable AND modc-parseable). **Lesson
(now in dynrt-design.md build-order):** after `deno fmt`-ing the dynrt lib, ALWAYS re-run `modc` on the
POST-fmt source before committing — `deno fmt` line-wrapping and the modc subset are not fully compatible.
Cheap guard: keep dynrt conditionals as `if/else` rather than long ternaries at deep indentation.

## FIXED — wasic arrow detection mis-fired on `=>` inside STRING LITERALS (#14 2e.3, 2026-06-24)

Surfaced building #14 2e.3 (arrow functions in the dynrt interpreter): the test driver passes eval-source
STRINGS like `"const add = (a, b) => a + b;"` to `dynRun`. wasic's two arrow-detection sites scanned the
RAW source (string-blind) and mistook the `=>` inside those string literals for real arrows → either
mangled the source (`parseArrowFunctions`) or split the line (`substituteOneArrow`) → "Unsupported
statement: a + b; …". (Single-param `"f = (a) => …"` happened to pass only because it lacked a leading
`const`.) **Two fixes in `src/wasic.ts`:** (1) `parseArrowFunctions` (the `const NAME = (` source pre-pass)
now tracks string state in its existing pre-match scan and `continue`s when the match index lands inside a
string literal; (2) `substituteOneArrow` replaced `line.indexOf("=>")` with a new module-level
`firstCodeArrowIdx(line)` that returns the first `=>` outside strings/`//`-comments (-1 → no arrow). Both
parallel the earlier `rewriteOutsideStringsAndComments` fix for `eval(`/`Function(`. General wasic
improvement — any program with `=>` inside a string literal now compiles. (A 3rd, dynrt-side bug also
fixed: `runStatement` treated a top-level `x => …` arrow statement as the assignment `x = …` because its
`=` check didn't exclude `=>`; added `peek2 !== '>'`. See dynrt-design.md 2e.3.)

**Same class, 2026-06-24 (#14 2e.5):** the Phase-49 optional-chaining strip `this.src.replace(/[?][.]/g,
".")` in `transpile()` was ALSO string-blind, mangling a `?.` inside a dynrt driver's eval-source string
(`"o?.x"`→`"o.x"`). `?.name` "worked" by accident (`o?.x?.y`→`o.x.y` — same result when nothing is null)
but `?.[k]` broke (`.[` is invalid → undefined → trap). Fixed by routing through
`rewriteOutsideStringsAndComments` (code-only). General wasic fix — any program with `?.` inside a string
literal now compiles correctly.

## FIXED — wasmmerge placed a merged module's non-WASI import AFTER function definitions (#14 Phase 2, 2026-06-24)

Surfaced building #14 Phase 2 (host→core callbacks): the dynrt lib gained ONE `env.__host_call` import
(its first import). Adding it broke `18l` (explicit-path dynrt merge) with a runtime "memory access out
of bounds" — while `18q`/`18za` (virtual-path) passed. Long diagnosis (isolation + GOOD/BAD WAT diff +
npm:wabt cross-check) pinpointed it: `mergeWasmWat` pushed the merged module's non-WASI import into
`funcParts` (the FUNCTION section), so it was spliced **after ~30 function definitions** instead of into
the import section. WASM requires ALL imports before ANY function/global/memory. **npm:wabt rejects** such
a module at parse time; **wabt-ts leniently assembles it** but the import lands at the wrong function
index → the whole function index space is off by one → calls resolve to wrong functions → OOB. (The
pre-binaryen merged WAT was the culprit — wabt-only assembly OOB'd too, ruling out binaryen.) **Fix:**
`mergeWasmWat` now collects non-WASI imports into a separate `importWat` (new `WatMergeResult` field);
`mergeOneWasmImport` splices `importWat` into the main module's import section (right after the last
existing `(import …)`, before memory/globals/functions) instead of with the functions. Verified: import
now at line 5 (before first func at line 11); `18l`/`18q`/`18za` + all 29 `18*` pass. **NOTE:** the
`wasmbundle` CLI path (`src/wasmbundle.ts`) consumes `mergeWasmWat` but does not yet route `importWat`
into its master WAT — a non-WASI import in a `wasmbundle`d module would be dropped (it was already
mis-handled there pre-fix; no regression, no current test exercises it) — documented follow-up.

## "look for code issues" audit of the functions-as-`any` work (2026-06-24, post-v1.9.0)

Focused audit of the freshly-shipped functions-as-`any` code (pin table, `Function(` producer, bindgen
tag-7 proxy, the tsbundler comment-strip). Suite **335/335 → 336/336** (item 3 added the `18zb`
regression), bindgen **119 → 122**.

- **FIXED — bindgen tag-7 proxy double-unpin (ABA → use-after-free), `src/bindgen.ts` ~line 374.** The
  generated proxy did `_fn.release = () => _dynGcUnpin(_pin)` and `_pinReg.register(_fn, _pin)` with NO
  unregister token. So an explicit `release()` followed by GC fired `_dynGcUnpin(_pin)` a SECOND time
  via the FinalizationRegistry; if that pin slot was reused by a newer pin in between, the newer
  (still-live) handle was wrongly unpinned and could be collected while the host held it. Fix: a
  `let _released` idempotency guard + `_pinReg.unregister(_fn)` in `release()` + register with `_fn` as
  the 3rd-arg unregister token. New assertions in `testGenBindingsAnyFunction` (idempotent / cancels
  registry / unregister token). Severity was low-med (needs release()+GC+slot-reuse interleaving, and
  FinalizationRegistry timing is non-deterministic) but it's a real correctness hole on a non-moving GC.
- **FIXED — tsbundler auto-merge trigger sniffed over a fragile regex strip, `src/tsbundler.ts`.** The
  earlier `Function(`-self-merge fix stripped comments with `…replace(/\/\/[^\n]*/g,"")`, but that eats
  a `//` INSIDE a string literal (e.g. a URL) and the rest of that line with it — hiding a real
  `: any`/`eval(`/`Function(` later on the same line (false-negative → confusing compile failure).
  Blanking strings first instead would let an apostrophe in a comment (`// it's`) start a bogus string.
  Replaced both with a single left-to-right scanner `stripCommentsAndStrings()` that tracks comment AND
  string/template state correctly (string contents → a space, so a trigger inside a string is data and
  doesn't count; comments removed). Verified: dynrt lib still does NOT self-merge (its doc-comment
  `Function(` is blanked), and all existing `any`/`eval` tests still trigger (suite green).
- **FIXED — wasic `Function(`/`eval(` source pre-passes rewrote inside string literals + comments,
  `src/wasic.ts` ~line 17920.** `this.src.replace(/\beval\s*\(/g, …)` and the `Function(` variant
  rewrote the RAW source, so a literal `console.log("call Function() …")` came out as
  `…dynrt_dynMakeFn() …` (wrong OUTPUT, not a compile error — the rewritten token sits inside string
  data). Pre-existing class (the `eval(` pre-pass shipped this way since #14.3.3). Fix: new module-level
  `rewriteOutsideStringsAndComments(src, transform)` — a single left-to-right scanner that copies string
  literals (`'`/`"`/`` ` ``) and comments through verbatim and applies the `eval(`/`Function(` regex
  replacements only to the CODE spans between them. Both pre-passes route through it. Regression test
  `18zb_PrepassStringSafety` (output-diff: a program that PRINTS `eval( … )` / `Function( … )` with no
  real dynamic code — verifies the strings survive AND that dynrt is not spuriously merged). Templates
  are opaque in full (their `${…}` interpolations are not rewritten — a rare accepted under-reach,
  consistent with the tsbundler trigger sniff). The pin table (`dynGcPin`/`dynGcUnpin`, free-slot 0
  sentinel — valid handles are never 0), `dynMakeFn`'s comma-scanner (relies on the now-shipped `||`
  short-circuit), and the marshal-export DCE protection were all audited CLEAN.

## OPEN (worked around) — `f64call() | 0` doesn't truncate a call result in i32 context (2026-06-23)

`s = s + (dynNumberValue(x) | 0)` where `dynNumberValue` returns `f64` miscompiles:
`i32.add[1] expected type i32, found call of type f64`. The `| 0` integer-truncation idiom doesn't fire
when its operand is a direct **function call returning f64** (it works for f64 variables / arithmetic).
Surfaced writing the GC split test (`18y`); worked around by comparing the f64 array elements directly
instead of summing them with `| 0`. Likely the `| 0` handler doesn't recognize a call-typed operand as
f64 needing `i32.trunc_f64_s`. Low severity. Fix site: the `| 0` / i32-coercion path in `emitExpr`
(detect an f64-returning call operand). Bind the call to an `f64` local first as a workaround.

## FIXED — wasmmerge clobbered ALL merged mutable globals to 131072 (#14 GC Part 3, 2026-06-22)

`mergeWasmWat` (`src/wasmmerge.ts` ~line 776) rewrote the initial value of **every** `(mut i32)` global
in a merged library to `131072` (the page-2 boundary). That hack was meant for a hand-written library
carrying its OWN bump-allocator free-pointer (the Phase 18 `18_symbol_table.wasm`) — placing that
private heap out of the main module's region. But it fired BLANKET on all mutable globals, including
the ordinary STATE globals of modc capability libraries (whose allocator is unified into the host's,
so they have no private heap). Pre-existing dynrt globals (`pos`, `lastLen`) survived only because
they're written-before-read. **GC Part 3's `__gc_reg` registry pointer is read-before-write** (its `0`
value is the "registry not yet created" sentinel): clobbered to 131072, the lazy-init `=== 0` check
never fired, so `mkCell` treated 131072 as the registry list and wrote cell pointers through it →
heap corruption that manifested as `RuntimeError: memory access out of bounds` once enough cells were
allocated (~3–4k). **Fix:** gate the rewrite on `droppedHeapPtrGlobalIdx === null` — i.e. apply the
131072 relocation ONLY when the library was NOT allocator-unified (the genuine private-free-pointer
case). When the allocator WAS unified, the library's other mutable globals are plain state →
`relocateDataPtrs` them (preserves counters/0/-1; the Stage 0.7 range-scoped relocation leaves
non-data-range values untouched). Verified: Phase 18 symbol-table tests still pass (non-unified path),
all 5 capability libs + dynrt still pass (unified path now preserves their state). This was a LATENT
bug — `__gc_reg` is the first merged mutable global that relies on its initial value.

Diagnosis trail (worth remembering): the tell was `dynGcCellCount()` returning a nonzero garbage value
(768) when the registry was DISABLED — proof the global being read wasn't the one being (not) written,
i.e. an initial-value/relocation problem, not a logic bug.

## OPEN — single-physical-line function: nested-block `const` not declared as a WAT local (2026-06-22)

A function written on ONE physical line whose body has a nested block declaring a local —
`function check(c){ if(c===0){ const x = a[i]; console.log(x); } }` — emits `(local.set $x …)` /
`(local.get $x)` but NO `(local $x i32)`, so assembly fails: `local "$x" cannot be resolved at IR
level`. The MULTI-LINE form of the same function is fine (its pre-scan declares `$x`). Root cause: the
single-physical-line body path (`splitStmts`) doesn't recurse into nested `{…}` blocks when collecting
locals to declare. Low severity (rare hand-written form); surfaced writing a GC test — worked around
by writing the test's `check` multi-line. Fix site: the local-declaration pre-scan for single-line
bodies in `emitFunction`.

## OPEN (worked around) — 4 gaps surfaced by the #14 dynamic runtime (2026-06-22)

Surfaced building `tests/wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts` (boxed-value runtime +
expression evaluator in the wasic subset). All four are worked around IN the library; full design +
context in [dynrt-design.md](dynrt-design.md). None fail the suite.

0. **i32 GLOBAL / typed-array-element as an f64 call-arg skips the `f64.convert`** (2c). `dynNumber(g)`
   where `g` is an i32 module-global emitted `(call $dynNumber (global.get $g))` → `call[0] expected
   f64, found global.get i32` at instantiate; same for an `Int32Array` element (`dynNumber(an[2])` →
   `i32.load`). An i32 LOCAL coerces correctly, so the arg-type path inserts `f64.convert_i32_s` only
   for locals. Workaround: bind the global/element to an `i32` local first, then pass. Fix site:
   call-argument coercion in `emitExpr` (recognize global.get / typed-array-element i32 reads in an
   f64 arg position, like the local path does). (Same family as the Float64Array-compare gap #2.)

1. **`+` of two string-returning CALLS not supported.** `stringForm(a) + stringForm(b)` (both operands
   string-returning function calls) aborts with "Unsupported expression" — `emitStringAssign` doesn't
   handle a concat whose operands are both string-call results. Workaround: bind each call to a
   `string` local, then concat the locals. Fix site: `emitStringAssign` / `appendConcatPart` in
   `src/wasic.ts`.
2. **`Float64Array` element in a comparison mis-infers as i32.** `fa[0] === fb[0]` (two Float64Array
   element reads) emits `i32.eq` over `f64.load` operands → `i32.eq[0] expected i32, found f64.load`
   at instantiate. Float64Array element reads aren't tracked as f64 by the binary-op type inference
   unless first assigned to an explicitly-typed `f64` local. Workaround: `const x: f64 = fa[0]` before
   comparing. Fix site: binary-op operand-type inference in `emitExpr` (recognize TypedArray element
   reads' element type, as the i32/Uint8 paths effectively do).
3. **Empty `[]` is a SHARED static zero-capacity array; growth from cap 0 is broken.** `const a: i32[]
   = []` lowers to a static data-segment array (`(local.set $elems (i32.const 260))`) — every such
   literal aliases the SAME ptr until first grow — and `$__dynarr_push_i32` grows by `cap << 1`, which
   stays `0` from a `0` capacity. So pushing to an empty `[]` that was stored and later reconstructed
   scribbles past the allocation into the next `$__malloc` (the dynrt symptom: element 0 lost, later
   elements fine) and independent empty arrays alias. JSON dodged it (build hot, read immediately);
   a mutable runtime can't. Workaround: dynrt manages containers as self-grown `Int32Array` lists
   `[len, cap, …]` (the Set/Map idiom), nonzero starting cap + correct doubling. **Real fix (high
   value — hardens every reconstruct-then-`push` user):** make `[]` heap-allocate with a nonzero
   capacity and make the grow use `max(cap*2, MIN)`.

## console.log struct-array STRING field printed the raw pointer (2026-06-15, async 13.4b)

Both console.log/console.error `arr[idx].field` struct-lookup closures returned a `field.type ===
"string"` field with only `watLoad` (the ptr i32) and NO `watLoadLen`, so `console.log(arr[i].strField)`
printed the raw data pointer (e.g. `260`) instead of the string text. Surfaced by `Promise.allSettled`'s
`results[i].status`. **Fix:** special-case string fields in both closures to return `{type:"string",
watLoad: ptr@offset, watLoadLen: len@offset+4}` (the same shape the class-var string-field path already
used). General improvement — any struct-array string field in console.log now prints correctly.

## Capturing expression-body arrow result-type inferred as f64 (2026-06-15, async 13.1b)

A LATENT bug surfaced by capturing-closure `.then` callbacks. `substituteOneArrow` inferred an
**expression-body** arrow's result type (`v => base + v`, no return annotation) with ONLY the arrow's
own params in scope — so a CAPTURED variable (`base`) was an unknown identifier and `inferInitType`
defaulted the arithmetic to **f64**. The lifted closure body then got `(result f64)` while the body
actually produced i32 → `local.set expected f64, found call of type i32` at instantiate (and a wrong
`await_<T>` pick downstream). The block-body path already seeded the enclosing fn's params/locals; the
expression-body path did not. **Fix:** build the inference scope (enclosing fn params + locals + the
arrow's own params) ONCE and use it for BOTH paths. Benefits any value-returning capturing arrow used
as a callback. Surfaced + covered by `59_AsyncClosureCb` (capturing `.then` i32/f64). Companion fix:
`promiseInnerTypeOf`'s `.then`/`.catch` callback-type resolution was named-only → an f64 closure cb
mis-picked `await_i32`; added a `cbResult` resolver covering the `__anon_N__factory` form.

## Multi-level interface inheritance dropped fields on forward `extends` (2026-06-15, Phase 53.11)

`parseStructs` built interface/object-type structs in a single **source-order** regex pass. When a
derived interface was declared **before** its base (`interface C extends B {…}` above `B`/`A`), the
base wasn't in `structDefs` yet, so the inherited fields were silently lost — `const c: C = {x,y,z}`
read `x:0 y:0 z:3` (only `C`'s own field landed; the base reads returned the 0 fallback). In-order
chains of any depth already worked, so the long-standing "offset-calc" suspicion in the gap notes was
a red herring — the bug was declaration ORDER, not arithmetic. **Fix:** collect all interface +
object-type declarations up front, then build them in **dependency order** to a fixpoint (a decl is
ready when its base is built, has no base, or is external); leftovers/cyclic build last without the
unresolved base. Field-building extracted into the new `buildStructDef` helper. Regression
`53_InterfaceInheritance` (4-level forward-ref chain + mixed-width chain + base-typed param). No
behavior change for in-order decls (non-extends build in the same interfaces-then-type-aliases order).

## console.log string/numeric comparison fixes + member-target chained assignment (2026-06-12)

The remaining audit items (the console_log.ts silent-wrong stubs the wasic-side hardening didn't
reach — console_log has no `diagnostics` channel). Root cause was a single broad bug plus a few
gaps. Suite 306→307 (regression `27_ConsoleLogStringCompare`; `52_ChainedAssignment` extended).

1. **`findTopLevelOp` skipped the trailing `op.length` characters (`src/console_log.ts`).** It
   started the depth scan at `i = expr.length - op.length`, so a RHS ending in `)` / `]` (a function
   call, `.slice(…)`, any parenthesised tail) left that closing bracket uncounted → paren depth went
   NEGATIVE → the operator was never matched at depth 0 → the WHOLE comparison/expression silently
   fell through to the numeric/terminal path. E.g. `console.log("x", a === getName())` and even
   `a.length === getName().length` returned the wrong boolean. This is the SAME bug class as the
   documented wasic-side `findBinaryOp` fix. **Fix:** scan the FULL string from the end (counting
   trailing `)`/`]`) and only test for an op match at valid start positions (`i <= maxStart`).
   Broad impact — every console.log operator/comparison whose RHS ends in `)`.
2. **`console.log` string `===`/`!==` only handled local/literal/array-element operands** — a
   fn-call (`a === getName()`), struct field (`a === p.name`), slice (`a === s.slice(0,3)`) or method
   (`"BOB" === a.toUpperCase()`) operand silently compared against the **empty string** (wrong
   boolean). **Fix:** `getStrPL` (and the string-ternary `getStrPtrLen`) now fall back to the existing
   `_stringExprResolver` bridge → wasic's `emitStringPtrLen`. Wired the resolver-temp declaration:
   broadened the `$__str_op_ptr/len` prologue trigger to fire on a `console.*` line with a
   string-equality op.
3. **String `!==`/`!=` in console.log was INVERTED** (`src/console_log.ts`) — it returned true for
   EQUAL strings (`(i32.ne (i32.eqz cmp) 0)`). `$__str_cmp` returns 0 when equal, so `!==` must be
   `(i32.ne cmp 0)`. Pre-existing; affected every string `!==` in console.log.
4. **String `.length` as a comparison/arithmetic OPERAND fell to the exprToWat terminal → 0**
   (`src/console_log.ts`). The earlier (Phase 52) string-`.length` fix was only in `parseSingleArg`;
   `exprToWat` (used for operands) had only the array-`.length` branch. Added the string-`.length`
   branch there, plus a general `<stringExpr>.length` handler (`getName().length`, `s.slice(…).length`)
   via the resolver's len word.
5. **Member/element-target chained assignment** `p.x = z = 5`, `arr[i] = w = 9` (`emitBlock`/`emitStatement`
   chain handler). Previously only bare-identifier targets were lowered; member/element targets bailed
   (→ silent-wrong, then abort after the hardening). **Fix:** accept any assignable lvalue
   (`\w+`, `\w+.\w+`, `\w+[…]`); the per-step lowering reuses the normal assignment emitter.
6. **`arr[i].method()` empty vtable dispatch** now records a diagnostic (fail-loud) instead of
   silently dispatching to `(i32.const 0)` when a class hierarchy is mis-registered (niche).

**Documented limitation (NOT fixed — too risky pre-publish):** `console.log` of a **5th+ numeric arg
in per-iov mode** prints `"?"` (a VISIBLE marker, not silent-wrong). Raising `SCRATCH_SLOTS` shifts
`DATA_BASE` (260), which is hardcoded in `wasic.ts` and is the **wasmmerge `DATA_PTR_THRESHOLD`** —
load-bearing for data-pointer relocation. Left as-is.

## Pre-publish hardening pass — else-chain drop bug + silent-fall-through diagnostics (2026-06-12)

A pre-bump audit (workarounds / dead code / silent fall-throughs) added **unsupported-feature
diagnostics** to the emitter's terminal "give-up" fallbacks, and that immediately surfaced a **real,
latent codegen bug**:

1. **Brace-less AND single-line-braced `else` / `else if` after a SINGLE-LINE `if` were silently
   DROPPED** (`src/wasic.ts` `emitBlock`). `if (c) s; else if (c2) s2; else sN;` and
   `if (c) { s } else if (c2) { s2 } else { sN }` (each branch on its own line) compiled with only the
   first branch — every `else`/`else if` after it vanished. Proven with a minimal repro: TS `10 20 30 99`
   vs WASM `10 0 0 0`. The if-handler's else-detection only recognised a few braced multi-line forms;
   a single-line if (brace-less `inlineBody` or single-line-braced `singleLineBlock`) followed by these
   self-contained else lines matched none of them, so they fell through to the statement stream and were
   stubbed. **Latent** because the suite's inputs never exercised the dropped branches (e.g. `27_base64`
   `rem===2`, a RegExp lib's escape table). **Fix:** before the inlineBody/singleLineBlock branching,
   detect a following self-contained else chain (`WasicTranspiler.isSelfContainedElse`), assemble the
   if-body + the whole chain into one inline string (brace-less bodies braced via `braceifyElseLine`),
   and feed it to the existing `expandInlineBraceChain` → canonical braced multi-line form the proven
   else/else-if machinery handles. An OPEN braced else (`else {` continuing on later lines) is left to
   the existing machinery. Regression test `15_ElseChainForms.ts` (suite 305→306). NOTE: `deno fmt`
   de-braces single-statement bodies, so the single-line-braced form is tested with non-trivial bodies
   (a nested `if`) that fmt keeps inline.
2. **`x instanceof Error` (a BUILT-IN, not a user class)** reached the `emitExpr` terminal stub (→ silent
   0). The Phase-51 `instanceof` handler only fires for `classDefs` entries. **Fix:** added a branch for
   non-user-class RHS — wasic models caught exceptions as strings, so the idiomatic
   `if (e instanceof Error)` catch-narrow resolves to **1** for the Error family
   (`Error`/`TypeError`/`RangeError`/…), **0** for other unmodelled built-ins. Compile-time constant.

**The hardening itself (kept, all green):** four terminal "give-up" fallbacks now record a diagnostic
(which aborts the compile via the existing `warnings` gate) instead of silently emitting `0` / the empty
string: `emitExpr` (unsupported expression), `emitStatement` (unsupported statement), `emitStringAssign`
(unsupported string assignment), and `emitStringPtrLen` (unsupported string expression — kills the
silent-empty-string class, incl. the dangerous case where a string `===` silently compares against `""`
and flips a branch). Speculative / guarded probe sites that recover gracefully are wrapped in a new
`quietEmit()` (a depth counter `emitDiagSuppressDepth`) so only the ~20 *unguarded* sentinel callers
turn into hard errors. The `emitStatement` diagnostic skips clearly-non-statement fragments of
multi-line constructs that are parsed as a whole elsewhere (DU type-alias `|` continuations, and
array/object/struct-literal element lines — `"success",`, `{ type: "add", value: 15 }`, bare `404`).
See design-decisions.md "Terminal emit diagnostics".

**Dead code removed (same pass):** `allocStringNoLog` (byte-identical to `allocString`) collapsed into
`allocString`; the orphaned, in-repo-unused modules `src/runner.ts` + `src/args.ts` and
`utils.ts:checkIsLibrary` deleted, along with their `deno.json` `./runner` / `./args` exports (a
breaking removal of two unused public subpaths). Also Phase-52 follow-ups: `void c.bump()` (void
dot-call) emitted invalid `(drop (call $void))` → call-shaped `void` exprs now route through the
statement emitter; the chained-assignment `=` scan is now string/template-aware.

## Phase 52 (2026-06-11) — leaf conveniences

Phase 52 surfaced one pre-existing gap, now fixed: `console.log("s.length:", s.length)` on a STRING var
returned 0 — `console_log.ts dotLenMatch` only handled array `.length`; added a string-`.length`
branch (UTF-8 byte length) for local strings / module string consts / string globals (also fixed
the same direct-print path for `fromCharCode` strings).

## Remaining-items pass — chained new().method(), module-level multi-statement lines, string-assign delegation (2026-06-08)

Cleared the low-severity items the pre-bump audit had left (suite 296→298). Two MORE real
silently-wrong bugs surfaced + fixed in the process:

1. **Chained `new ClassName(...).method(...)`** (`src/wasic.ts` `emitExpr`) — had no handler (stubbed
   to 0). Added a balanced-scan handler (find the ctor's matching `)`, then `.method(args)`): allocate
   the struct, call the constructor, call the method on the fresh pointer → `(block (result T) ctorCall
   methodCall)`. Guarded the method-args capture with `parenDepthNeverNegative` so `new A(x).m() + new
   B(y).m()` falls through to the binary-op loop. console.log routes `new`-led tokens through
   `dotCallLookup`→`emitExpr`. String-returning chains out of scope. Works in assign/return/binary-op/
   console.log. Regression: `9_ChainedNewAndMultiStmt`.
2. **Module-level multi-statement single physical line** (`const a = 1; const b = 2;`) — `parseTopLevel`
   pushed it as ONE _start statement. Now split via `splitStmts`, BUT gated by a new
   `hasMultipleTopLevelStatements` helper (a depth-0, bracket+string-aware `;` with content after it) so
   an array/object-literal FRAGMENT (`const x = [`, `{ name: "a" },`) is NOT split — splitStmts tracks
   only `(){}` not `[]` and would append a stray `;` / split at struct `}`, corrupting multi-line array
   literals (caught a 30_sorting / 6b_testing regression before it shipped). Regression in the same test.
3. **i32/i64 module-global arithmetic in console.log emitted `f64.add`** (surfaced by #2; pre-existing).
   `console.log(a + b)` where `a`/`b` are i32 module globals → type error / wrong, because the
   `leadType` routing in `parseSingleArg` AND `exprToWat` consulted only `locals`, never the `globals`
   map. **Fix:** `locals.get(id) ?? globals?.get(id)` in both. Covered by `9_ChainedNewAndMultiStmt`.
4. **`emitStringAssign` complex-expr stub narrowed** — added an `emitStringPtrLen` last-resort before
   the stub, so a string METHOD on an array element in an assignment (`const u = words[0].toUpperCase()`)
   now resolves instead of stubbing to empty. Regression: `27_StringMethodAssignFromArrayElem`.
   STILL feature-gaps (hit the now-narrower stub, not regressions): `arr.join(sep)` as a *value* (no
   value-returning string-array join helper exists — only the console.log gather-scratch numeric join),
   and `.slice()`/`.at()` on a bracket receiver in an assignment (those handlers take only `\w+`).
5. **`relocateDataPtrs` (wasmmerge) — FIXED (2026-06-09).** The range heuristic (`dataLo<=n<dataHi →
   shift`) over-relocated an arithmetic constant that coincidentally lands inside a merged lib's
   static-data range. Grounding in real merged WAT settled the design: (a) the merged module body is
   disassembled to FLAT/stack form (`i32.const N` then its consumer on the next line); (b) a genuine
   data pointer DOES appear in value position (MathLibrary: `i32.const 0 / i32.const 260 / i32.store`
   stores the version-string pointer), so an "address-position only" walk would UNDER-relocate it — an
   exact pointer/arithmetic split is impossible from WAT text. **The one safe signal:** a data pointer
   is NEVER the rhs operand of a pure arithmetic/bitwise/shift op. So the fix scans flat form and, for
   each in-range `i32.const N`, looks at the NEXT instruction token (the stack consumer): if it's in
   `ARITH_NEVER_PTR` (`i32.mul/div/rem/and/or/xor/shl/shr/rotl/rotr`) the constant is left alone;
   every other consumer (store/load/add/sub/call, `(data …)` offset) still relocates, so NO genuine
   pointer is ever dropped. `add`/`sub`/comparison stay relocated (a pointer legitimately appears as
   `base±offset`; over-relocation there is far rarer and undisambiguable without dataflow). Proven both
   directions: the new regression FAILS under the old relocate-all heuristic (`x % 271` → `271→531` →
   wrong) and PASSES with the fix, while the banner string pointer still relocates (`260→520`).
   Regression: `18i_RelocArithmeticConstant` (`@test-pipeline`, trap-on-failure). Zero change to any
   current merge (all in-range pointers were in non-arith positions). See design-decisions.md.

## Pre-bump audit — greedy method/new in binary ops + console.log array arithmetic (2026-06-08)

A "dead code / workarounds / bugs / fallthroughs" sweep (3 parallel scan agents + reproduction)
before bumping wasmtk found two REAL silently-wrong-output bugs (both fixed; suite 293→296):

1. **`a.method() + b.method()` / `new A(x) OP new B(y)` mis-compiled** (`src/wasic.ts` `emitExpr`).
   The `dotCallExprMatch` / `newMatch` / `superDotExprMatch` greedy `([\s\S]*)` args capture consumed
   across the operator — e.g. `a.unwrap() + b.unwrap()` matched receiver `a`, method `unwrap`, args
   `) + b.unwrap(` → a broken call. (Tests had WORKED AROUND this by hoisting `const av = a.unwrap()`
   temporaries — see 16_NestedMonomorphization.) **Fix:** `parenDepthNeverNegative(args)` guard on all
   three, so the compound expr falls through to the binary-op loop (which emits each operand
   correctly). Regression: `16_MethodCallBinaryOp`. (Narrower still-open: chained
   `new X(...).method()` in a binary op has no handler; a module-level multi-statement single physical
   line isn't split — both rare.)
2. **`console.log("x:", arr[i] + arr[j])` dropped terms** (`src/console_log.ts`) — was a documented
   KNOWN-OPEN. The greedy `arr[idx]` regex in `parseSingleArg` AND `exprToWat` captured `0] + arr[1`
   as the index and emitted one mangled access. **Fix:** bracket-balance-guard the index in both
   (nullify on unbalanced), so it falls through to the binary-op loop; and infer the op type from the
   array's ELEMENT type (the lead `arr` is an i32 pointer) so i32[]→`i32.add`, f64[]→`f64.add`.
   Regression: `6d_ConsoleLogArrayArith`.

3. **Runtime `n.toString(radix)` stubbed to 0** (only literal `(14).toString(2)` was folded). **Fixed**
   2026-06-08: new `$__i32_to_str_radix(val, radix, buf)→len` helper in `getHelperWat` (base 2..36,
   digit→char `0-9`/`a-z`, sign-magnitude for negatives) + handlers in `emitStringAssign`,
   `emitStringPtrLen` (via the `$__str_op` temp pair; `.toString(` added to the prologue + the
   console.log string-expr resolver regex), and `inferExprType`. Works across assignment / direct
   console.log / template literal / string-returning function / runtime radix. Value truncated to i32.
   Regression: `48_ToStringRadix`.

The agents' dead-code scan found NONE (the only "unused" symbols — `compileWat`/`compileWasiTs` — are
documented public API). The lower-severity items this audit flagged were then ALL fixed in the
"Remaining-items pass" entry above (chained `new().method()`, module-level multi-statement lines, the
string-assign stub narrowing, and — 2026-06-09 — the `relocateDataPtrs` over-relocation). Only two
narrow FEATURE gaps remain (not regressions): `arr.join(sep)` as a value, and `.slice()`/`.at()` on a
bracket receiver in an assignment.

(Earlier this day, the `26_ForOfSingleLine` test was added by the hazard audit — see "Proactive
hazard-audit fixes" below.) The 14 output-mismatch bugs that the
2026-06-07 runner-hardening surfaced are **ALL FIXED 2026-06-08** — see the "14 output-mismatch
bugs ALL FIXED" entry directly below for the per-cluster root causes. Earlier: Phase 51 (2026-06-05)
added `instanceof`, closed three construction/parsing gaps, and a follow-up workaround-audit fixed
one silent bug + added a loud `call_indirect`-in-merge guard; a 2026-06-07 follow-up added a
companion `memory.grow`-in-merge guard.

## Proactive hazard-audit fixes (2026-06-08, suite 292→293)

A codebase sweep for latent workarounds / fallthroughs found four issues; all fixed (zero
regressions, `src/wasic.ts` + `src/console_log.ts`):

1. **Brace-less single-line `for…of` dropped its body** — `for (const x of arr) stmt;` (no braces):
   the `forOfM` regex required `(\{.*)?$`, so the brace-less form hit `else { i++; continue }` and the
   body was silently skipped (same class as the single-line-`while` bug). Fixed: regex now captures
   any inline tail `(.*)$`, and the non-brace tail is split via `splitStmts` as the body. Regression
   test `26_ForOfSingleLine.ts`. (Other single-line forms — `if`/`while`/`for(;;)` — were already OK.)
2. **`console.error(arr.every/some/includes(...))` printed `1`/`0` not `true`/`false`** — the
   boolean-returning-array-method branch existed in `dotCallLookupFn` (console.log) but was missing
   from its `dotCallLookupFnErr` twin (a parallel-path-drift miss). Mirrored the branch. (No suite
   test — console.error goes to stderr, which the runner doesn't diff; verified manually.)
3. **`cv.ptr === -1` → `cv.ptr < 0`** at 12 class-instance field/method base-computation sites — the
   exact fix applied to structs (`sv.ptr < 0`) but never mirrored to `classVars`. Currently harmless
   (verified: `classVars` only holds `-1` or a static `allocStructData` ptr, never the `-3` heap
   sentinel) but future-proofs against a class heap-alloc path.
4. **Greedy `(.+)` arg-capture guards extended** — `indexOf`/`includes`/`at`/`charAt`/`replace`/
   `padStart`/`repeat`/`fromCharCode` (and the new string-char-subscript / `isNaN` handlers) now carry
   the documented `parenDepthNeverNegative(args)` guard, matching `charCodeAt`/`startsWith`/`split`/
   `slice`. Behaviour-preserving for balanced args; an over-greedy match (a swallowed following `)`)
   now falls through instead of mis-emitting. Added a `parenDepthNeverNegative` helper to
   `console_log.ts` (mirrors wasic's) for the console.log-arg `at`/`isNaN` handlers.

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
  correct, binaryen output is wrong. Interim fix: `watToOptimisedWasm` **skips binaryen** for modules
  that use exceptions (marker: `$__exn_tag`) — rare, ships the correct un-optimized wabt binary. This
  exposed a latent **terminal-`block`-fallthru** bug (a `switch` where every case returns/throws leaves
  an empty stack at the function end → V8 strict-validation reject; binaryen used to mask it) —
  `3_enums` regressed; fixed by extending `fixTerminalFallthru` to append `(unreachable)` after a
  terminal void block (harmless when binaryen runs — it strips trailing unreachable). **PROPER FIX
  (2026-06-08): the binaryen-ts CoalesceLocals bug is fixed upstream in `binaryen-ts@1.3.4`** — an
  EH-aware CFG (`src/passes/cfg.ts`): a `try` pushes its catch entries onto a handler stack while its
  body is visited; throwing instructions (`throw`/`rethrow`, `call`/`call_indirect`) link to the
  enclosing handlers, and a throwing `call` splits the block so a wrapping `local.set` can't strip a
  handler-live local. **INTEGRATED 2026-06-08:** `deno.json` bumped `^1.3.3`→`^1.3.5` (binaryen-ts
  shipped the fix in 1.3.4, plus more fixes in 1.3.5) and the `$__exn_tag` skip was **REMOVED** from
  `watToOptimisedWasm` — exception modules now get full `-Oz` and correct output (full suite
  **293/293**, bindgen 103/103, jstyper 73/73; publish gate clean). `fixTerminalFallthru`'s
  terminal-block `(unreachable)` case was KEPT (independent V8-strict-validation fix, not part of the
  workaround). The binaryen-ts fix + its 2 regression tests live in `../binaryen-ts` (suite 308→310);
  see that repo's `CLAUDE.md` § "Fix log — CoalesceLocals".
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
tracked-`.wat` changes). **`console.log("x:", arr[i] + arr[j])` returning only the first element —
now FIXED 2026-06-12** as a side effect of the `findTopLevelOp` full-scan fix: the old scan skipped
the trailing `]` of `arr[j]`, so the top-level `+` was never found at depth 0 and the expression fell
through. With the full-string scan the `+` is found; array-element arithmetic (i32 + f64, literal and
variable indices) is correct (verified directly).

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
capability test added the 278th). (By 2026-06-03 it was **279/279** — the single-line-brace
`if` fix added `48_SingleLineBraceIf`; the live count is at the top of this file — **309/309**.)
They were two unrelated root causes:

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
live count at the top of this file — **309/309**). Kept here as a
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
