# Architecture

## Compilers / tools

| Tool | Input → Output | Notes |
| --- | --- | --- |
| `wasic` | `.ts` → `.wasm` (+`.wat`,`.wit`) WASI executable | Has `_start`; the main compiler. |
| `modc` | `.ts` → `.wasm` (+`.wat`,`.wit`) **library** | No `_start`, no WASI; exports named functions. Use for DLL-style libs. |
| `bindgen` | `.wit` → `.bindings.ts` | TS host loader; canonical ABI marshaling (strings via cabi_realloc + TextEncoder). |
| `hybrid` | `.ts` → core `.wasm` + TS runner | Splits on `// @wasm` annotations; routes annotated fns through modc→bindgen. |
| `jstyper` | `.js`+`.d.ts` → typed `.ts` | Regex-based; `number→f64`, `--any-policy`, `--dts-only`. |
| `javyc` | `.ts` → `.wasm` via QuickJS | The dynamic-kernel fallback (~1.26 MB). Out of scope for typed code. |
| Go producer (`--lang=go`) | `.go` → `.wasm` | **`src/gowasic.ts`** (2026-06-06). Shells to TinyGo (`--go-runtime=std` for stdlib `go`); NOT the wasic TS compiler — a front-end handing wasm to the shared downstream. Commands (path defaults to cwd): `init` (scaffold `go.mod`+`main.go`; `--go-target=wasm`=browser; the scaffold includes a `//go:wasmexport` example), `modc` (**WASI reactor library** by default — `-target=wasip1 -buildmode=c-shared`: no `_start`, exports `//go:wasmexport` funcs + runtime, callable via `wasmtk mod`/bindgen; **`--go-target=wasm`** for a browser module + `wasm_exec.js`), `run` (build wasip1 command + run). **`wasic --lang=go` was REMOVED 2026-06-07** (standalone Go→WASI isn't merge/bindgen-consumable; the wasip1 build now lives inside `run`); **`run` auto-detects Go 2026-06-07** (a `.go` file or a dir with `go.mod` → builds+runs without `--lang=go`). **`modc --lang=go` = reactor library 2026-06-07** (was browser-only; flipped to match TS `modc` = library mode) — required a `_initialize` fix in `callExport`/`runWasi` (reactor exports trap unless `_initialize` runs first; see [compiler-bugs.md](compiler-bugs.md)). wasm-opt auto-fallback: passthrough shim + `-scheduler=none` + binaryen-ts `-Oz` when no real wasm-opt (goroutine-free). See [polyglot-producers.md](polyglot-producers.md). |
| Zig producer (`--lang=zig`) | `.zig` → `.wasm` | **`src/zigwasic.ts`** (2026-06-07). Shells to `zig` (no wasm-opt shim — zig self-optimizes). `init` (scaffold a wasm-library `main.zig`: `export fn` + a **comptime-guarded** `pub fn main` test harness — Zig analyzes `main` even with `-fno-entry`, so std I/O must be guarded to the wasi target), `modc` (freestanding library: `-fno-entry --export=<name>…` scanned from source → clean exports, no `_start`/WASI + binaryen-ts `-Oz`), `run` (`wasm32-wasi` program on wasmtk's TS host; auto-detects `.zig`). See [polyglot-producers.md](polyglot-producers.md). |
| Rust producer (`--lang=rust`) | `.rs` → `.wasm` | **`src/rustwasic.ts`** (2026-06-07) — **delegates fully to `rsxtk`** (owner's Rust WASM toolkit on PATH; `cargo install rsxtk`). `init`→`rsxtk init` (wasi script), `initmod`→`initmod` (library), `modc`→`rsxtk build <p> wasm`, `build`→`rsxtk build <p> wasi`, `run`→`rsxtk run` (its wasmtime; auto-detects `.rs`/`Cargo.toml`), `add`/`remove`/`list`/`fmt`/`clean`→same. Rust-only verbs require `--lang=rust`. Prereq `rustup target add wasm32-wasip1`. See [polyglot-producers.md](polyglot-producers.md). |

## Pluggable wabt + binaryen backends — `deno.json` is the single switch

Both WABT and Binaryen are swappable **only** by editing the `"wabt"` / `"binaryen"` specifiers
in `deno.json`; no source change needed.

| Specifier | npm (legacy) | JSR (jrmarcum ecosystem) |
| --- | --- | --- |
| `"wabt"` | `npm:wabt@^1.0.36` | `jsr:@jrmarcum/wabt-ts@^1.3.2/compat` |
| `"binaryen"` | `npm:binaryen@^116.0.0` | `jsr:@jrmarcum/binaryen-ts@^1.3.5/compat` |

**Current (2026-06-08):** `wabt-ts@^1.3.2/compat` + `binaryen-ts@^1.3.5/compat`. The `/compat`
subpaths mirror the upstream-npm shape so call sites stay backend-agnostic. **binaryen-ts must
stay ≥ 1.3.4** — 1.3.2 fixed a merge-path optimizer miscompile on division-heavy merged code, and
**1.3.4 fixed the `-Oz` CoalesceLocals EH bug** (try/catch catch-variable locals were coalesced with
outer locals live across the try → wrong output; an EH-aware CFG fixed it). 1.3.4 let wasmtk REMOVE
its "skip Binaryen for exception (`$__exn_tag`) modules" workaround, so exception code is `-Oz`'d
again (suite 293/293 with it removed). Reverting below 1.3.4 re-introduces both bugs with no
wasmtk-side workaround. wabt-ts 1.3.0 fixed a
folded-`(call)`-before-`(return)` encoder bug (recovered `15_panic`, `18_Multi-Scope`); **wabt-ts
1.3.1 fixed hex-float literals being parsed as 0** (`parseF*LiteralBits` used JS `parseFloat`,
which can't read `0x1.…p±N` notation — every merged-`mathlib` constant encoded as 0). 1.3.1
recovered all four `38_*` Math tests; **stay ≥ 1.3.1**.

**Source wiring:** import `wabt` (default async factory) and `binaryen` via `./binaryen.ts`
(a 3-line wrapper: `const lib = (ns as any).default ?? ns` — picks the CJS default under npm,
the namespace under JSR). Use the upstream-npm shape everywhere: `await wabt()` + `parseWat`/
`readWasm`; `binaryen.readBinary(...)` + `Module` methods. When disassembling imported `.wasm`
for the merge, always pass `.toText({ inlineExport: false })` explicitly (wabt-ts default differs
from npm:wabt and breaks the standalone-export regex otherwise).

15 toolchain bugs were filed+fixed upstream during the JSR migration (10 wabt-ts, 5 binaryen-ts)
plus the 1.3.0 call-before-return fix, 1.3.2 merge-optimizer fix, and 1.3.1 hex-float-literal fix.
The former **open** merge bug (an OOB `charCodeAt` nested in a non-short-circuit `&&` loop `br_if`
that trapped only after the splice) is **fixed 2026-06-02** by making wasic emit short-circuit
`&&`/`||` — no open merge bugs remain. See compiler-bugs.md § "short-circuit `&&`/`||` removes the
merge OOB-`charCodeAt` trap".

## Build pipeline (wasic)

1. `tsbundler.bundleImportsEx` — inline `.ts` imports; detect `.wasm` imports (single-line only).
2. For each `.wasm` import: disassemble (wabt), `mergeWasmWat(prefix,0)` to pre-register export
   signatures; **read the sibling `.wit`** to recover logical types (string params hide as
   `i32 i32` in the raw signature) and overlay them onto each `ExternalFuncDef`.
3. `WasicTranspiler.transpile()` → WAT.
4. For each `.wasm` import: `mergeOneWasmImport` splices it in (rename, relocate data, unify
   allocator). `mathlib.wasm` auto-merged when `needsMathLib`.
5. Re-seat `$__heap_ptr` past the combined static data; grow memory pages.
6. `watToOptimisedWasm`: wabt `parseWat`→binary, then Binaryen `-Oz` (shrink=2, opt=2).
7. Write `.wat`, `.wit` alongside `.wasm`.

## The merge (wasmmerge.ts) — the "DLL linker"

Splicing a modc `.wasm` into a host module needs three hard parts, all handled:

- **Prefix-mangling** — every internal name → `${prefix}_name` (collision-free).
- **Data relocation** — `relocateDataPtrs` shifts data-segment pointers by the combined data
  offset, **scoped to the merged module's own `(data …)` address extent** so arithmetic
  constants aren't mistaken for pointers (the Date fix; a pure leaf with no data segments
  relocates nothing).
- **Allocator unification (Stage 0.6)** — `detectBumpAllocator` finds each module's `$__malloc`
  (semantic gate: `(param i32)(result i32)`, touches exactly one global read **once** + written
  **once**, `local.get 0` + `i32.add`, no loads/stores/calls), drops duplicates, and redirects
  call sites + the heap-ptr global to the host's single `$__malloc`/`$__heap_ptr`. This makes a
  structure built in one merged unit share one live heap with another. `WatMergeResult.
  droppedAllocator` signals it; a leaf lib (no malloc) skips it.
- **Merge guards (loud failure, not silent corruption)** — a merged-in module must not carry
  constructs that can't survive the WAT-splice; `wasmmerge` throws a clear diagnostic instead of
  emitting a broken/corrupt module: (1) **`call_indirect`** (2026-06-05) — Phase 18 strips imported
  type sections, so a `(type N)`/table ref would dangle; (2) **`memory.grow`** (2026-06-07) — signals
  a foreign allocator that claims linear memory upward (Go runtime alloc / Rust dlmalloc / Zig
  `page_allocator`) instead of sharing the host bump heap, which would silently corrupt once it
  allocates. The `memory.grow` diagnostic names the per-language fix (static-arena allocator) or
  points to keeping the module standalone as a WIT/bindgen component. wasmtk's own producers
  (wasic/modc) emit neither — their bump allocator runs over fixed pre-declared pages — so the guards
  fire only on heap-using foreign-language modules. (Background: the native-producer mergeability
  matrix in [polyglot-producers.md](polyglot-producers.md).)

## Bump allocator / instance lifecycle

`$__malloc` advances `$__heap_ptr`; **no `free`**. Allocations accumulate for the instance
lifetime — intentional and correct for the DLL/singleton use case (CLI tools, bounded calls).
For servers doing many string-param calls, the planned mitigation is an instance **pool**
(`createPool`) in the universalWasmLoader, cycling fresh instances. `cabi_post_return` (full
Component Model) would remove the need but is deferred.

## Canonical ABI (Stage 0 + return-side forward-alignment, 2026-06-15)

**Accuracy note (updated 2026-06-15):** the realloc/param side AND the **return side** are now
canonical-aligned; what remains non-canonical is only the **container** — the artifact is a P1
**core module** with a **sidecar** `.wit` (not an embedded component-type section), and boundary
marshalling is still done **host-side** in bindgen rather than by the binary. So: "aligned with the
Component Model Canonical ABI calling convention, shipped as a P1 core module + sidecar WIT" is the
accurate phrasing. The remaining P1→P2 step (embed the component type + `wasm-tools component new`)
is now a **wrap, not a rewrite** — see [polyglot-producers.md](polyglot-producers.md).

- Exports `cabi_realloc(ptr,old,align,new)` (a `select`-based wrapper over `$__malloc`) instead
  of `__malloc`, when any export has a string param/return.
- **String returns use the canonical callee-allocated convention (2026-06-15).** A `$fn__cabi`
  shim (exported as `"fn"`, signature `(...params) -> i32`) allocates an 8-byte `[ptr, len]` return
  area via `cabi_realloc`, calls the internal void `$fn` (which sets `$__str_ret_ptr`/`$__str_ret_len`
  globals), writes ptr+len into that area, and **returns the area pointer**. A paired
  `cabi_post_<fn>` export (empty body — the bump allocator has no free, but the export must exist
  for the contract) lets the host release the buffer. The `$__str_ret_*` globals stay internal.
- bindgen host: numerics direct; bool `x?1:0` / `r!==0`; string params `TextEncoder`+`cabi_realloc`;
  string returns call the export → read `[ptr,len]` at the returned pointer via `DataView.getInt32`
  at 0/4 → decode → call `cabi_post_<fn>(retPtr)`. (The host no longer allocates the return area.)
