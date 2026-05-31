# Load-bearing design decisions

Invariants and codegen rules that are easy to break in a refactor and must NOT be silently
reverted. The exhaustive list (with line numbers) is in the legacy `CLAUDE.md`; this is the
high-value subset.

## Numeric / codegen correctness

- **`Math.round` = `floor(x + 0.5)`**, NOT `f64.nearest` (which is banker's rounding and gives
  `round(2.5)=2`). Both `wasic.ts` (F64_UNARY special case) and `console_log.ts` must agree.
- **`$__f64_to_str`** uses ×1e15 + a shortest-round-trip shortening loop (`$__pow10_f64`). Do not
  revert to ×1e6 or drop the shortening loop. Known accepted limit: `Math.SQRT2` prints 15 dp.
- **Type-erasure casts** `expr as unknown as T` / `expr as unknown` are stripped up front in
  `emitExpr` (before the ` as ` handler) so the inner operand keeps its real type. Without it,
  `buf as unknown as i32` cast the i32 ptr i32→f64 (mapType("unknown")→f64) → `return[0] expected
  i32, got f64`. Guard is `\b`-bounded so `canvas`/`has` aren't touched.
- **`findBinaryOp`** scans the FULL string for paren/bracket depth and only matches at valid op
  positions (`i <= maxStart`). Reverting to start-at-`maxStart` re-hides operators whose RHS ends
  in `)`. Counts `()` and `[]`.
- **Greedy single-call handlers** (`charCodeAt`/`startsWith`/`endsWith`/`split`, and the `.slice`
  family) must guard their greedy `(.+)` arg with `parenDepthNeverNegative(arg)` so a following
  binary operator isn't swallowed. Reserve `[^)]+` only when nesting is provably impossible.
- **String-literal regexes are escape-aware** `"((?:[^"\\]|\\.)*)"` at the statement/expression
  sites (`emitStringPtrLen`, `emitStringAssign`, module-const detection). `allocString` →
  `unescapeString` decodes. (The `console_log.ts` console.log-arg path is still un-escaped.)
- **`&&`/`||` are NON-short-circuit** (`i32.and`/`i32.or`) — both operands always evaluate. Code
  must not rely on the RHS being skipped; in particular never put an OOB-prone `charCodeAt`/array
  read on the RHS of a bound check inside a merged library (see compiler-bugs.md). `switch` on
  `f64`/`number` must use `f64.eq`/`f64.const`.

## Merge (wasmmerge) invariants

- **`detectBumpAllocator`** identifies `$__malloc` semantically: `(param i32)(result i32)`, touches
  exactly one global with `global.get`/`global.set` each occurring **exactly once**, has
  `local.get 0` + `i32.add`, and NO calls/loads/stores. The once-each rule is what keeps a
  `global += param; return global` accumulator from being mis-dropped.
- **`relocateDataPtrs`** relocates only `i32.const` values inside the merged module's own `(data …)`
  address extent — never blanket-shift every `>= 260`, or arithmetic constants get corrupted.
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

## Tooling

- `tsbundle` outputs **`.ts`** (`.bundled.ts`), an import inliner — NOT `deno bundle`/JavaScript.
- `.wasm` import detection matches **single-line** `import { … } from "./x.wasm"` only.
- Bump version in `deno.json` only, then `deno task update-version` (propagates to `package.json`
  + `src/utils.ts VERSION`). Don't add `dependencies` to `package.json`; don't use
  `nodeModulesDir: "auto"` (Windows junction failures).
