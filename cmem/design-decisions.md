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
  `tests/wasm_wasi/48_SingleLineBraceIf.ts` (`// deno-fmt-ignore-file` keeps the single-line forms).
- **Greedy single-call handlers** (`charCodeAt`/`startsWith`/`endsWith`/`split`, and the `.slice`
  family) must guard their greedy `(.+)` arg with `parenDepthNeverNegative(arg)` so a following
  binary operator isn't swallowed. Reserve `[^)]+` only when nesting is provably impossible.
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

- **`javyc` (QuickJS) as the interim dynamic runtime.** Covers the irreducible dynamic kernel
  (`eval`/`new Function`, pervasive `any`, open-prototype mutation) that wasic deliberately does not
  compile. Stays until wasmtk's own dynamic runtime lands (roadmap §7-#7). Not a bug.
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
