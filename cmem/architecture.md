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

## Pluggable wabt + binaryen backends — `deno.json` is the single switch

Both WABT and Binaryen are swappable **only** by editing the `"wabt"` / `"binaryen"` specifiers
in `deno.json`; no source change needed.

| Specifier | npm (legacy) | JSR (jrmarcum ecosystem) |
| --- | --- | --- |
| `"wabt"` | `npm:wabt@^1.0.36` | `jsr:@jrmarcum/wabt-ts@^1.3.0/compat` |
| `"binaryen"` | `npm:binaryen@^116.0.0` | `jsr:@jrmarcum/binaryen-ts@^1.3.2/compat` |

**Current (2026-05-31):** `wabt-ts@^1.3.0/compat` + `binaryen-ts@^1.3.2/compat`. The `/compat`
subpaths mirror the upstream-npm shape so call sites stay backend-agnostic. **binaryen-ts must
stay ≥ 1.3.2** (1.3.2 fixed a merge-path optimizer miscompile on division-heavy merged code;
reverting below re-introduces it with no wasmtk-side workaround). wabt-ts 1.3.0 fixed a
folded-`(call)`-before-`(return)` encoder bug (recovered `15_panic`, `18_Multi-Scope`).

**Source wiring:** import `wabt` (default async factory) and `binaryen` via `./binaryen.ts`
(a 3-line wrapper: `const lib = (ns as any).default ?? ns` — picks the CJS default under npm,
the namespace under JSR). Use the upstream-npm shape everywhere: `await wabt()` + `parseWat`/
`readWasm`; `binaryen.readBinary(...)` + `Module` methods. When disassembling imported `.wasm`
for the merge, always pass `.toText({ inlineExport: false })` explicitly (wabt-ts default differs
from npm:wabt and breaks the standalone-export regex otherwise).

15 toolchain bugs were filed+fixed upstream during the JSR migration (10 wabt-ts, 5 binaryen-ts)
plus the 1.3.0 call-before-return fix and 1.3.2 merge-optimizer fix. One **open** merge bug
remains on the wasmtk/wabt-ts side — see compiler-bugs.md § "merge OOB-charCodeAt".

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

## Bump allocator / instance lifecycle

`$__malloc` advances `$__heap_ptr`; **no `free`**. Allocations accumulate for the instance
lifetime — intentional and correct for the DLL/singleton use case (CLI tools, bounded calls).
For servers doing many string-param calls, the planned mitigation is an instance **pool**
(`createPool`) in the universalWasmLoader, cycling fresh instances. `cabi_post_return` (full
Component Model) would remove the need but is deferred.

## Canonical ABI (Stage 0, complete)

- Exports `cabi_realloc(ptr,old,align,new)` (a `select`-based wrapper over `$__malloc`) instead
  of `__malloc`, when any export has a string param/return.
- String returns use an out-parameter: a `$fn__cabi` shim (exported as `"fn"`) calls the internal
  void `$fn` (which sets `$__str_ret_ptr`/`$__str_ret_len` globals) and writes ptr+len into a
  caller-provided 8-byte return area. The globals are **not** exported.
- bindgen host: numerics direct; bool `x?1:0` / `r!==0`; string params `TextEncoder`+`cabi_realloc`;
  string returns `cabi_realloc(0,0,4,8)` area + `DataView.getInt32` at 0/4.
