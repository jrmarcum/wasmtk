# Offload inventory — what wasmtk does that a sibling could own (H11, 2026-09-28)

Answer to workspace letter **H11** (`../../cmem/handoffs.md`) and divergence row **I10**: the owner's
direction is "anything wasmtk can offload in the main program will ultimately be a benefit" and
"nothing moves before its trigger". **This is an inventory. Nothing has moved.**

Sources, all read 2026-09-28: a full survey of `main.ts` + `src/`, and the siblings' own memory
(binaryang `open-work.md` / `binaryen-ts.md`, wasmrt/wazmrt READMEs + `interop.md`, the
universalWasmLoader SPEC 3.0.0) plus workspace rows I2 / I10 / I11 / C1 / S4. Line counts are
`wc -l` on 2026-09-28. Sibling facts carry the date their source gave. Re-derive before acting.

## Where each sibling stands (the facts the triggers depend on)

- **binaryang 1.6.0** (pinned here): assembler, disassembler, validator, objdump, strip, `wasm-opt`,
  and a pass runner, each on a published subpath. **One front end, stage 5: DONE on binaryang `main`
  2026-09-28, UNRELEASED**: one text front end, one reader, one writer. That is I2's trigger, and
  it counts for us only once it is in a version we can pin. **No module merge/link**: binaryen-ts's
  DESIGN row (`binaryen-ts.md` l.507) scopes `wasm-merge` → wasmtk, and I10 says it "may re-open".
  `allFeatures` is not exported (requested 2026-09-28). `./wasm-runtime` is a kernel cache, NOT a
  WASI host. `./wasm2ts` is a stub. `./ts2wasm` is reserved (I11).
- **wasmrt / wazmrt**: WASI preview 1 host, exception handling, `run`/`wasi`/`wast`/`wat` verbs, C
  ABIs (wazmrt ships a `deno_ffi.mjs` example). Exit contract: `proc_exit(n)` → `n & 0xff`; host
  failure and trap → 1. Both run the spec corpus with 0 skips (wasmrt 64,603 on 2026-09-19; wazmrt
  64,092 on 2026-09-21). **Neither is in wasmtk: V8 is.** Workspace goals decision 4: rsxtk and
  wasmtk get the runtime slot first; the winner is "smallest and fastest binary". Lockstep at 1.0.0.
- **universalWasmLoader SPEC 3.0.0** (`-js` is the reference): load `.wasm` plus an auto-detected
  `.wit`, and a canonical-ABI SUBSET (s32/s64/f32/f64/bool/string) "as produced by wasmtk". The WASI
  shim is optional in 3.0.0. Its fixtures are `wasmtk modc` outputs.

## Candidates

| # | wasmtk responsibility (size) | could move to | trigger | blocker / note |
| --- | --- | --- | --- | --- |
| **1** | **Regex-over-WAT merge**: `wasmmerge.ts` (957 lines, ~45 regex sites), wasic's post-merge fixups (~27 sites: import insertion, `_start` init call, memory raising, heap-ptr scrape/re-seat), `wasmbundle.ts`'s 2 | **binaryang's parser + IR**: parse once, rewrite the IR, write once. The merge LOGIC stays ours | 🔒 **I2, owner-set**: binaryang one-front-end stage 5 **in a published version we pin**. Met on their `main`; not yet released | Needs a stable public IR-edit API (today's `compat/wabt` is parse→encode only). This retires our "never require a bracketing you did not emit" invariant and the `readDebugNames:false` contract. Highest value: every backend text-format change has broken these regexes (wabt-ts 1.3.5→1.4.0→1.4.1, binaryang 1.6.0) |
| **2** | **Module merging / static linking itself**: `mergeWasmWat` semantics (prefix mangling, WASI import dedupe, allocator unification, data relocation) + `runWasmBundle` (410 lines) | **binaryang `wasm-merge`** (Binaryen has one) | binaryang re-opens its DESIGN row (**owner decision**), AFTER #1 | wasmtk-specific semantics (unified `$__malloc`/`$__heap_ptr`, `memory.grow`/`call_indirect` guards) would stay a wasmtk pass over binaryang's IR even if generic merging moves |
| **3** | **WAT post-passes in wasic**: `internalizeDynrtHostImports`, `injectDynrtMarshalExports`, `fixTerminalFallthru` + a private WAT tokenizer/parser/serializer (`tokenizeWat`, `parseWatNodes`, `serializeWat`) | binaryang IR (as #1) | #1 | `fixTerminalFallthru` works around our own emitter. It belongs IN the emitter (H12 / `ts2wasm`), not in a text pass anyone owns. The private WAT parser is a 4th in-house WAT parser (I2 counts three) |
| **4** | **Validation before assembly** (none today), and the wast runner's validity oracle | binaryang `./wasm-validate` | `allFeatures` exported (requested 2026-09-28) | Unblocks 12 wast definitions V8 refuses for its limits. `compat/binaryen`'s `validate()` is a stub that returns 1: do not use it |
| **5** | **Assemble/optimise/inspect wrappers**: `watToOptimisedWasm` (`wasic.ts:202`), `binaryenOptimize`/`binaryenAsyncify` (`binaryen.ts`), `convertFile`, `getWasmBytes`, `showInfo` | already binaryang; could call its TOOL subpaths (`./wat2wasm`, `./tools/wasm-opt`, `./wasm2wat`, `./wasm-objdump`) instead of the `compat` shims | none: a thinning, not a move | Low value on its own. Worth doing WITH #1, when the `compat/*` pins are revisited anyway. `showInfo` ≈ `wasm-objdump -x` |
| **6** | **WASI preview-1 host + runner**: `wasiImports`, `runWasi`, `callExport` (`utils.ts`), exit-status handling | **wasmrt or wazmrt**: CLI `wasi` verb, or C ABI via Deno FFI | the owner's **runtime-slot** decision (goals 4), runtimes at 1.0.0 lockstep, and the runtime added to `engine_cross_check_tests` + `dync_cross_runtime_tests` FIRST (the cheapest foothold, per wazmrt's own vision) | wasmtk's `env` host imports (`console.log` UTF-16, `__host_print`, `__host_call`) need host-function registration, which means the FFI path, not the CLI. Exit codes are ALREADY aligned since 2026-09-28 (trap 1, `proc_exit(N)` → N), except that the runtimes mask `& 0xff` |
| **7** | **Loader generation**: `bindgen.ts` (652 lines), a static TS loader (WASI shim, `cabi_realloc` strings, `cabi_post`, `any` box/unbox via `dynrt_*`, per-runtime byte loading) | universalWasmLoader-js (runtime `.wit` loading) | **owner decision** (bindgen emits a thin wrapper over the loader, or stays generative), and SPEC growth to cover `any` boxing and `__host_call`/`__host_print` | Today the two duplicate the canonical-ABI marshalling in different forms. Workspace S4 wants loader fixtures regenerated from ONE `wasmtk modc` run: do that regardless |
| **8** | **The `.wast` runner** (`wast.ts`, 1,698 lines; SIMD/NaN/exnref trampoline, GC classifier, per-assertion verdict rules) + the vendored corpus (C2) | binaryang (the runner gates ITS assembler), or C1 convergence | **owner / C1** | It tests binaryang assembly + V8 execution; the runtimes run the corpus natively with 0 skips. 2026-09-28's work (100 runner-caused failures, 186 false passes) shows a runner is only as good as its verdict rules. Whoever owns it should inherit `compiler-bugs.md`'s two entries on it |

**Stays in wasmtk** (its role per workspace `projects.md`: orchestration, other-language
producers, the corpus, the loaders' fixtures):

- `rt.ts`, the Deno/Bun/Node host abstraction.
- The Go/Zig/Rust producers. Rust already delegates wholly to rsxtk.
- `.wit` GENERATION (wasmtk is the source of truth for its ABI).
- `main.ts` CLI plumbing.

**Moves with `wasic`, not to a sibling:** `tsbundler`, `jstyper`, `varscope`, `hybrid`, `dync`,
`modc`, and `console_log.ts`'s hand-written WAT stdlib. They follow I11 → `./ts2wasm`, under the H12
modularization. Their bar is owner-set (I11), and their scope is deliberately unwritten.

**Out of scope:** `wasm2js` (`npm:wasm2js`; binaryen-ts routes `wasm2js` → "the runtimes"). Only
the `wasm2js` verb uses it.

## Order, if the triggers land as expected

1. **#1** when binaryang ships stage 5. It is the only owner-set trigger that is nearly met, and
   the highest-value item. #3's text passes ride with it.
2. **#4** the moment `allFeatures` is exported (small).
3. **#6's foothold**: add a runtime to the two cross-engine gates. It is cheap, reversible, and
   costs nothing before the slot decision.
4. **#2, #7, #8** wait on owner decisions. They are listed so each can become its own divergence
   row with a trigger (I10's instruction).

Found while taking this inventory, and fixed: `wasmbundle`'s optimise step swallowed failures
silently (`781c4b6`), the same hole as the Go/Zig producers (`3c2ada9`).
