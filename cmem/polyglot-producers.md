# Polyglot producer congruence + ABI / P2 posture (+ C/C++ Zig ADR)

> Added 2026-06-03. Authoritative, portable memory (this folder supersedes the gitignored
> machine-local `CLAUDE.md`). Links: [architecture.md](architecture.md) (Canonical ABI / build
> pipeline), [roadmap.md](roadmap.md) (execution order), [vision.md](vision.md) (polyglot ecosystem).

## Project goal — one congruent polyglot wasm capability

**wasmtk's goal is to unify the TS/JS, C, C++, Rust, Zig, and Go toolchains into a single congruent
wasm build capability.** Point wasmtk at source in any of those languages and get a wasm artifact
that flows through one shared downstream contract — not five disjoint toolchains bolted together,
but heterogeneous *producers* converging on a homogeneous middle/back end wasmtk already owns.

### The congruence (the shared contract all producers target)

- **Output:** core wasm module targeting **WASI Preview 1** (imports `wasi_snapshot_preview1`), or
  freestanding with a defined wasmtk import set.
- **ABI:** canonical-ABI marshalling via **bindgen** (auto-emitted `.wit` → typed TS host bindings).
- **Optimize/transform:** **binaryen-ts** (`-Oz` and passes).
- **Link/merge:** **wasmmerge / wasmbundle** (WAT-level merge into one module; shared linear memory,
  symbol prefix-mangling, data-section relocation).
- **Host/run:** wasmtk TS side is the **WASI host**; the `run` multi-format executor drives it.

Each language is a producer plugin; only the front end differs. Everything from optimize → merge →
host is the same code path, so adding a language = adding a producer, not a toolchain.

### Rust producer = `rsxtk` (owner's Rust-side toolkit, 2026-06-03)

**`rsxtk`** (crates.io: <https://crates.io/crates/rsxtk>; repo `jrmarcum/rsxtk`; v0.4.4 2026-04-20;
MIT OR Apache-2.0) — *"A high-performance Rust WASM Toolkit for managing and running WASI scripts,
WAT, and WASM modules."* This is the owner's Rust counterpart to wasmtk and is **the Rust producer's
build+run driver**. Run individual Rust files as scripts with dependency management + WASM compile.

- **Builds** Rust → **`wasm32-wasip1`** (the exact congruent contract), with `.cwasm` (native
  machine-code) pre-compilation for fast repeat runs. Also handles `.wat`/`.wasm`.
- **Runs** in a WASI sandbox via **wasmtime (~v40.x)** with disk caching; "smart entry" tries
  `_start` (WASI command) or lists/calls exported functions (library mode with CLI args).
- Subcommands: `init`, `run`, `csrun` (native via Cargo scripting), `build`, `add`, `remove`,
  `list`, `fmt`, `clean`, `resource` (`rsc/` assets), `build.rs` support.
- **No WIT / bindgen / component-model** — so interface generation + canonical-ABI marshalling
  remain **wasmtk's** job; rsxtk is the producer + native runner.

**Division of labor — RESOLVED 2026-06-07: delegate fully to `rsxtk`** (shipped, `src/rustwasic.ts`;
see "SHIPPED 2026-06-07" section below). rsxtk owns Rust *build + deps + native (wasmtime) run*;
wasmtk wraps its commands and still owns the *optimize (binaryen-ts) → merge (wasmmerge) →
WIT/bindgen* tier (bindgen for Rust deferred). The earlier open question (delegate to rsxtk vs. wasmtk
shelling to `rustc`/`cargo` directly) was decided in favor of **delegation** — reuses rsxtk's
cargo/dep/cwasm machinery; `run --lang=rust` uses rsxtk's wasmtime runner (not wasmtk's TS host).
Still distinguish `rsxtk` (a build/run **CLI toolkit**) from the planned `universalWasmLoader-rs`
(a **library loader** implementing the loader SPEC) — adjacent, not the same; they may converge later.

### Producer → contract mapping

- **TS (typed subset):** `wasic` — direct TS → optimized WAT → wasm, no JS runtime. (existing)
- **TS/JS (dynamic):** `javyc` — embedded Javy/QuickJS engine path. (existing)
- **C / C++:** `zig cc` / `zig c++` — Zig's bundled clang + libc-built-from-source → `wasm32-wasi`.
  (per ADR below)
- **Zig:** `zig build-exe -target wasm32-wasi` (or freestanding). Cleanest native path.
- **Rust:** build/run driver is **`rsxtk`** (jrmarcum's Rust WASM toolkit — see note below), which
  compiles Rust → `wasm32-wasip1` and runs it; underneath it's `rustc` `wasm32-wasip1` (WASI 0.1;
  the old `wasm32-wasi`, renamed in Rust 1.78, removed under the old name in 1.84). Use **Zig as the
  linker / C cross-compiler** for crates with C deps (cargo-zigbuild pattern). rustc does its own
  LLVM wasm codegen; Zig fills the C/link role.
- **Go:** **TinyGo** `tinygo build -target=wasip1` → WASI P1 core module (canonical producer; small
  output, clean wasip1/reactor targets). Library/`modc` analog = reactor exports via
  `//go:wasmexport` (or `-buildmode=c-shared`), no `_start`. Stdlib `GOOS=wasip1 go build` is a
  heavier optional fallback (full Go runtime/GC → large binaries). (per ADR below)

### Scope boundary — pin the contract to WASI Preview 1 / core modules (for now)

**None of the native producers emit WASI Preview 2 / components natively, except Rust.** Ecosystem
norm, not a per-toolchain gap:

- **Zig:** stdlib still targets WASI P1; emits a single core module. P2 only via post-compile adapter
  (`wasm-tools component new --adapt wasi_snapshot_preview1.wasm`), scriptable in build.zig.
  (confirmed 2026-06-03)
- **C / C++ (wasi-sdk / zig cc):** P1 core modules; same adapter step for P2.
- **Rust:** the one exception — `wasm32-wasip2` is native P2 (tier-2 since Rust 1.82, Oct 2024).
  `wasm32-wasip1` is still P1 + adapter.
- **Go (TinyGo):** primarily P1 (`-target=wasip1`), but recent TinyGo (~0.33+) also has a native
  `-target=wasip2` — so, like Rust, it's a native-P2-capable producer. Same rule as Rust: keep it
  behind the P1-merge contract; only emit P2 as the deliberate terminal path, not into a P1 merge.
- (WASI 0.2 "P2" stable since early 2024; latest 0.2.x as of mid-2026. P3 = async/threads, later.)

**This confirms the architecture rather than threatening it.** The whole ecosystem builds components
by starting from a P1 core module and adapting it. Pipeline: producers emit **P1 core modules** →
**wasmmerge** merges at P1 (shared linear memory) → **binaryen-ts** optimizes → *then optionally* one
terminal `wasm-tools component new --adapt` wraps the single merged module into a P2 component.

The earlier "components can't be merged" tension only bites if you try to wasmmerge already-built
**components** (each encapsulates its own memory → use `wac` for that). Merging P1 modules and
componentizing the **result** at the end is fine. So **P2 is a final optional wrap step, not a
merge-tier rewrite.** Keep the congruent contract at P1 core modules; treat componentization as a
terminal stage. Only Rust's `wasm32-wasip2` would bypass the merge tier — decide deliberately before
mixing native-P2 output into a P1-merge flow.

## VERIFIED: wasmtk's own output is NOT a Component Model / P2 producer (2026-06-03)

Confirmed by direct inspection of wasmtk output (`strings_rep.wasm` from `modc`, `wasi_rep.wasm`
from `wasic`), using `jco`/`wasm-tools` + byte parsing. wasmtk emits **WASI Preview 1 core modules
+ a sidecar `.wit` schema + TypeScript host glue (bindgen).**

- **Container:** core module, layer 0 (header `00 61 73 6d 01 00 00 00`, top form `(module`). A
  component is layer 1 (`00 61 73 6d 0d 00 01 00`, top form `(component`). Output only becomes a
  component after an *external* `wasm-tools component new` / `jco new` wrap.
  - NOTE: `wasm-tools validate --features component-model` is **non-discriminating** — a core module
    passes it too (the flag enables component parsing, doesn't require a component). Decisive checks
    are the byte header (layer word) + top form.
- **WIT:** sidecar file only; **not embedded**. No component-type custom section (`jco wit` yields an
  empty `world root {}`). The interface lives in the `.wit` consumed only by our TS bindgen.
- **Canonical ABI:** partial. `cabi_realloc` IS exported (the canonical allocator primitive), but the
  **lift/return side is not canonical**: exports are raw core (e.g. `strLen` is `(i32 i32)->i32`, not
  `func(string)->s32`); string returns use wasic's caller-allocated out-param convention (e.g.
  `greet(name_ptr,name_len,ret_area)` returns nothing); there is **no `cabi_post_return`**. All
  string/list/record/variant marshalling happens **host-side** in the generated `bindings.ts` at
  call time.
- **WASI:** Preview 1 (`wasi_snapshot_preview1`: `proc_exit`, `fd_write`). `modc` library output has
  no imports. Not `wasi:cli/*` / `wasi:io/*` 0.2 worlds.

**Bucket (b): WIT-as-IDL over a core module — portable to wasmtk's TS host, not to an arbitrary P2
runtime.** This is fine and works today; it is the pragmatic pattern. The only correctness issue is
documentation: README/cmem lines claiming the ABI is "aligned with the Component Model Canonical
ABI" **overstate the return-path alignment** and should be tightened — the realloc/input side is
adjacent, the lift/return side is not. (Tightening applied 2026-06-03 in architecture.md + roadmap
Stage 0 line + README; see those files.)

## DECISION: forward-align the current ABI to the Canonical ABI while staying P1 (2026-06-03)

P2 is a future endeavor; current output stays P1 core modules. But shape the ABI *now* so the future
P2 step is a wrap, not a rewrite. Separate three layers — align the first two now (both P1-legal,
mostly free), defer only the third:

1. **In-memory data representation — align FULLY now (free, pure upside).** Make the byte image of
   every boundary value match Canonical ABI layout so a future lift reads existing memory with no
   re-layout:
   - strings: UTF-8 (already, via TextEncoder) as (ptr, len). Keep UTF-8 — canonical default; avoid
     bespoke encodings (no canonopt mismatch later).
   - `list<T>`: (ptr, len) over canonically sized/aligned elements.
   - records / tuples: field concatenation with canonical alignment + padding.
   - variants / option / result: discriminant i32 + payload flattened over joined cases.
   - bool = 0/1 i32; char = Unicode scalar i32.
   - model resources as opaque i32 handle indices NOW (not raw pointers) so the later move to
     component resource tables is a representation swap, not a semantic one.

2. **Boundary calling convention — param side already canonical; fix the RETURN side now.**
   - Params: a `string` arg flattening to (ptr, len) is already canonical. ✓
   - Returns (THE change): switch aggregate returns from the current caller-allocated out-param
     (`greet(…, ret_area)` returns nothing) to the canonical **callee-allocated single i32 pointer
     returned by the callee (allocated via `cabi_realloc`) + a `cabi_post_<name>` that frees it.**
     Caller reads via the returned ptr, then calls post-return. Fully P1-legal — a calling
     convention, not a component feature.
   - `MAX_FLAT_RESULTS` = 1: scalar results stay direct. `str-len -> s32` keeps returning i32 with no
     pointer/post-return; only aggregate returns (greet/shout) move to the pointer convention.
   - Route EVERY boundary allocation through the already-exported `cabi_realloc` (right signature
     `(i32 i32 i32 i32)->i32`) — it's the load-bearing primitive; keep it sole.

3. **Component container — DEFER entirely (the only P2-only piece).** Type section, canon
   lift/lower, instance wrapper. Once (1) and (2) are canonical, producing it later =
   `wasm-tools component embed` (already-generated WIT) + `wasm-tools component new`. A wrap.

**Rule of thumb:** make the linear-memory image and the realloc/return convention canonical now (all
P1-legal); defer only the container. Keep P1 WASI imports behind a thin seam so the later
`wasi_snapshot_preview1` → `wasi:cli`/`wasi:io` swap (or P1→P2 adapter) is a boundary change.

**Honest cost:** the callee-allocated + `cabi_post_*` return path adds a post-return call per
aggregate return and moves return-buffer ownership into the module; the caller-allocated out-param is
simpler/faster in a pure host-glue world. Accepted: small runtime cost now to make future
componentization mechanical. Also tighten the README/cmem "aligned with Canonical ABI" wording — true
once (2) lands; today the return path is not aligned.

**Consumer caveat (why P2-producer stays deferred):** for JS-runtime targets (Node/Deno/Bun/browser)
NONE load components natively — jco transpiles a component back down to core wasm + ESM +
preview2-shim to run. That transpiled shape ≈ wasmtk's current bucket-(b) output. So real P2 only
pays off when the CONSUMER is a native component runtime (Wasmtime/WasmEdge/WAMR/Spin/wasmCloud).
Forward-aligning the ABI (this decision) is worthwhile regardless; flipping to a P2 *producer* is
not, until a native-component-runtime target exists.

## Path to a real P2 producer (only if portability-to-any-host is pursued)

Not required for the congruent-toolchain goal (P1-core + adapter covers it). With the
forward-alignment above already in place, this reduces to:

1. Embed a component-type section (`wasm-tools component embed`) so WIT travels in the binary.
2. (Already done by the forward-alignment return-convention change — callee-returns-pointer +
   `cabi_post_*`.)
3. Emit components directly, or shell out to `wasm-tools component new` as a terminal stage.
4. Migrate WASI imports from P1 to `wasi:cli` / `wasi:io` 0.2 worlds, or ship the P1→P2 adapter.

## Open scope question (shared with the ADR below)

Producers ingest single translation units / crates cleanly; driving full existing build systems
(configure/make/cmake/cargo with C deps) against the wasm target is the harder, less-bounded part.
Decide per language how far wasmtk wraps the build system vs. ingests pre-built units.

## VERIFIED: native-producer mergeability — allocation is the gate, allocator-control is the differentiator (2026-06-07)

Empirically tested end-to-end (TinyGo 0.41.1, Zig 0.16.0, Rust nightly 1.98 `wasm32-unknown-unknown`)
by building leaf + allocating variants of each, disassembling with wabt-ts, and running them through
the **actual** `wasmtk wasic` import-merge pipeline (`import { … } from "./leaf.wasm"` →
`wasmmerge` → binaryen-ts `-Oz` → run). Probe artifacts were under `tmp/go_merge_probe/`.

**One-line summary (owner-confirmed):** *Pure libraries of exported functions from Go, Rust, and Zig
are mergeable.* The gate is **whether the module allocates**, not the source language or the module
"style". For modules that DO allocate, only **Zig** stays mergeable, and only with a **static arena
allocator** (`FixedBufferAllocator`) — not a memory-growing one.

### Results matrix

| Module | `call_indirect` | `memory.grow` | Merge result |
| --- | --- | --- | --- |
| **Go** leaf (no alloc) | — | — | ✅ merges + runs correct (984 B → 3.5 KB merged) |
| **Go** allocating (`make`/`append`, `-gc=leaking`) | none | yes | ❌ **silently corrupts** |
| **Zig** leaf | — | — | ✅ merges + runs (216 B → 3.6 KB) |
| **Zig** alloc — `FixedBufferAllocator` (static arena) | none | none | ✅ **merges + runs correct** |
| **Zig** alloc — `page_allocator` (growing heap) | yes | yes | ❌ rejected **loudly** (call_indirect guard) |
| **Rust** leaf (`#![no_std]`, no allocator) | — | — | ✅ merges + runs |
| **Rust** alloc — `Vec` + static-bump `#[global_allocator]` | yes | none | ❌ rejected loudly |
| **Rust** alloc — manual `alloc()` + static-bump | yes (6) | none | ❌ rejected loudly (panic/`unwrap`/fmt drag in indirect calls) |

NOTE: the merged leaves are NOT WASI modules — they are **freestanding** (`wasm-unknown` /
`wasm32-freestanding` / `wasm32-unknown-unknown`) library modules with **zero WASI imports**, merged
*into* a wasic WASI program. "WASI-ness" is an axis of the consuming/main module, not the leaf.

### Why Go differs from Rust/Zig (the root cause)

- **Go has a mandatory runtime** whose allocator is welded in. Even `-gc=leaking` keeps a runtime
  allocator that (a) stores its heap metadata at **hardcoded absolute linear-memory addresses**
  (`i32.store offset=65540`, base `i32.const 0` — `offset=` *instruction immediates*, NOT relocatable
  `i32.const` data pointers, and Go emits no data segments so wasmmerge's pointer relocation is a
  no-op for it), (b) grows via `memory.grow` claiming all memory from a fixed base upward, and (c)
  relies on `_initialize` running to set that metadata — which the WAT-splice merge never calls. None
  of the three relocation levers (`global` rename, `call`-target rename, data-range `i32.const` shift)
  apply, and Go's allocator doesn't match `detectBumpAllocator` (it touches no wasm global and uses
  `memory.grow`). So it can't be unified — and worse, it **slips past the merge guard** (no
  `call_indirect`) and corrupts wasic's heap region (wasic `$__heap_ptr`≈65796 vs Go's hardcoded
  65536–65568).
- **Rust and Zig are freestanding-capable with no mandatory runtime**, and the allocator is
  **swappable (Rust `#[global_allocator]`) or explicit (Zig passes an `Allocator`)**. So a
  self-contained **static-arena** allocator never calls `memory.grow`, never claims wasic's region,
  and lives high in memory (well above wasic's heap) — it merges cleanly. Verified with Zig's
  `FixedBufferAllocator` (allocates a slice, sums it, returns 4950 merged, no corruption).

### Failure mode is the real headline

- **Go** silently corrupts — `memory.grow`-based, no `call_indirect`, so the only guard misses it.
- **Rust** almost always gets caught: even minimal `alloc` use drags `call_indirect` in via
  panic/`unwrap`/fmt/drop-glue → rejected at merge. Hard to *accidentally* merge a corrupting Rust
  module; also harder than Zig to hit the *working* path (would need `panic=abort`, no `unwrap`, custom
  alloc-error handler, manual memory).
- **Zig** is the sweet spot: explicit allocators make the clean static-arena path natural, and the bad
  (growing-heap) path fails loudly via `call_indirect`.

### Guard gap — CLOSED 2026-06-07 (`memory.grow` merge guard implemented)

The `wasmmerge` guard originally rejected only `call_indirect`. **Go's allocating case proved that
necessary-but-not-sufficient**: a `memory.grow`-based, indirect-call-free allocator (Go's, or a
hand-rolled direct-call dlmalloc in Rust/Zig) slipped through and corrupted. **Now FIXED** —
`wasmmerge` also throws a loud, actionable error on a merged module containing `memory.grow` (message
names the per-language fix: static-arena allocator, or keep standalone as a WIT/bindgen component),
turning Go-style silent corruption into a loud failure across all languages. wasmtk's own producers
never emit `memory.grow`, so no false positives; verified against all 14 merge tests. Full writeup +
implementation: [compiler-bugs.md](compiler-bugs.md) "Merge guard #2". (Companion to the
`call_indirect`-in-merge guard, 2026-06-05.)

### Practical takeaway per language

- **Zig** — best merge fit. Leaf merges trivially; allocating code merges *iff* it uses a static arena
  allocator. Document "use `FixedBufferAllocator`, not `page_allocator`" and Zig is a first-class merge
  producer.
- **Rust** — great for leaf (`no_std`, no allocator). Allocating Rust is realistically a **standalone
  component** (Canonical ABI / instance, not merge), because the toolchain pulls in indirect calls so
  readily.
- **Go** — **leaf-only** for merging; anything with a heap is a standalone component.

### Future — true shared-heap unification is tractable for Rust/Zig, not Go

The "option 4" that's intractable for Go (rebuild its runtime allocator) is **straightforward for
Rust/Zig** precisely because the allocator is user-replaceable: point a custom `#[global_allocator]`
(Rust) / `Allocator` wrapper (Zig) at an **imported wasmtk `$__malloc`/`$__heap_ptr`**, and they'd
share wasic's heap exactly like a modc capability — pointers and all, with full cross-module interop.
Not wired yet; the static-arena path is the available today-answer. This dovetails with the
cross-language-inclusion finding in [component-model-discussion.md](component-model-discussion.md)
(*cross-language merge is the exception; `instance`/WIT/bindgen is the default*).

---

## SHIPPED 2026-06-07 — Zig producer (`--lang=zig`) + Rust producer (`--lang=rust`, via rsxtk)

Both mirror the Go producer's command shape. Zig "stays in chain" (a native shell-out producer like
Go); Rust **delegates fully to `rsxtk`** (the owner's Rust WASM toolkit, installed on PATH — the
decision was: wrap rsxtk wholesale, incl. `run` via its wasmtime). New files: `src/zigwasic.ts`,
`src/rustwasic.ts`. `deno.json` exports both.

### Zig — `src/zigwasic.ts` (shell to `zig`; no wasm-opt shim — zig self-optimizes)

| Command | Action |
| --- | --- |
| `wasmtk init --lang=zig [dir]` | scaffold a wasm-library `main.zig` (`export fn` + a comptime-guarded `pub fn main` test harness) |
| `wasmtk modc --lang=zig [path]` | `zig build-exe -target wasm32-freestanding -O ReleaseSmall -fno-entry --export=<name>…` → clean library (only the `export fn`s + memory, no `_start`/WASI) + **binaryen-ts `-Oz`** (62-byte `add` lib in testing) |
| `wasmtk run --lang=zig [path]` / `run <file.zig>` | `zig build-exe -target wasm32-wasi -O ReleaseSmall` → WASI program, run on wasmtk's TS host (auto-detected `.zig`) |

**Zig gotchas discovered (load-bearing):**
- **Zig semantically analyzes `pub fn main` even with `-fno-entry`** — so a single-file scaffold's
  std-using `main` breaks the freestanding (library) build (`std` I/O pulls `posix.getrandom`, absent
  on freestanding). FIX: the scaffold **comptime-guards** the test body to the WASI target
  (`if (builtin.os.tag == .wasi) { … std.debug.print … }`); Zig comptime-prunes the std branch for
  freestanding. Do not remove the guard.
- **Clean library exports via `--export=<name>`, not `-rdynamic`.** `-rdynamic` also exports `main`
  as `_start`; `export fn` alone isn't exported in `build-exe`. So `zigwasic.ts` **scans the root
  source for `export fn <name>`** (`scanExportFns`) and passes explicit `--export=<name>` (falls back
  to `-rdynamic` if none found — e.g. exports in imported files). The user confirmed this pattern
  (`zig build-exe math.zig -target wasm32-freestanding -fno-entry --export=add`).
- WASI target triple: `wasm32-wasi` (alias of `wasm32-wasi-musl` in Zig 0.16; both work, identical).

### Rust — `src/rustwasic.ts` (delegate to `rsxtk`)

A thin delegator: `runRust(subcommand, forwardArgs)` shells to `rsxtk` (spawn + inherited stdio so
its output streams), with a clear "install: `cargo install rsxtk`" error if absent. `main.ts` maps
each verb (the wasmtk command name + `--lang` stripped from the raw args, then forwarded):

| wasmtk command | rsxtk | Notes |
| --- | --- | --- |
| `init --lang=rust <name>` | `rsxtk init` | wasi **script** template (has `main`) |
| `initmod --lang=rust <name>` | `rsxtk initmod` | **library** script (`#[no_mangle]` exports, no `main`) → writes `<name>.rs` |
| `modc --lang=rust <path>` | `rsxtk build <path> wasm` | library/universal wasm (TARGET `wasm` auto-appended) |
| `build --lang=rust <path>` | `rsxtk build <path> wasi` | WASI program (TARGET `wasi` auto-appended) |
| `run --lang=rust <path>` / `run <file.rs>` | `rsxtk run <path>` | build + run via rsxtk's wasmtime (auto-detected `.rs` / `Cargo.toml`) |
| `add/remove/list --lang=rust <path> [crate]` | `rsxtk add/remove/list` | rsxtk arg shape: `add <PATH> <CRATE>`, `list <PATH>` |
| `fmt --lang=rust` / `clean --lang=rust` | `rsxtk fmt` / `rsxtk clean` | clean wipes the `.tk` cache |

- rsxtk's `build` signature is `<PATH> <TARGET>` (`wasi|wasm|wat`) — so `modc` auto-appends `wasm`,
  `build` auto-appends `wasi` (via `delegateRust(sub, extraArgs)`).
- The Rust-only verbs (`initmod build add remove list fmt clean`) **require `--lang=rust`** (else a
  one-line "use --lang=rust" error); they're new top-level `case`s in `main.ts`.
- **Prerequisite:** `rustup target add wasm32-wasip1` (rsxtk builds wasip1; not installed by default —
  rsxtk prints the exact hint if missing). Installed during verification.
- **Verified working:** `init`→`run` ("Hello from rsxtk!"), `build`→`tmp/rprog.wasm` (65 KB),
  `add`/`list` (manifest updated), `clean` (cache cleared), error case (no `--lang`).
- **rsxtk-side limitation (NOT a wasmtk bug):** `rsxtk 0.4.4`'s `initmod` library + `build`/`mod`
  flow compiles the script as a `bin` and errors `main function not found` — its `initmod` template
  lacks a `[lib]`/crate-type marker. So `modc --lang=rust` on an `initmod` library currently fails at
  the rsxtk layer; the wasmtk delegation is correct. To address in **rsxtk** (owner maintains it).

### Host change required by these (general win): WASI-import Proxy

`src/utils.ts` `runWasi` + `callExport` now build `wasi_snapshot_preview1` as a **Proxy** (`makeWasiImport`)
that stubs any WASI function we don't implement (→ `() => 0`), so modules importing a *fuller* WASI
surface than our shims (Zig std imports ~28: `clock_res_get`, `path_*`, `fd_pread`, `fd_readdir`, …)
**instantiate** instead of failing `LinkError`. Implemented shims (`fd_write`, `random_get`, …) are
used as-is. Verified no regression (merge slice 14/14).

### Shared helper

`binaryenOptimize(bytes)` moved from `gowasic.ts` to **`src/binaryen.ts`** (exported); Go + Zig both
import it. Rust skips it (rsxtk optimizes).

---

## ADR: C/C++ → wasm ingestion path — Zig toolchain, not an emscripten/TS reimplementation (2026-06-03)

### Question

Should emscripten (github.com/emscripten-core/emscripten) be reimplemented in TypeScript for
inclusion in wasmtk, to give the toolkit a C/C++ → wasm capability?

### Decision

**No TS reimplementation of emscripten. Add a Zig-based compiler path** that vendors the Zig
toolchain (`zig cc` / `wasm-ld` / build.zig) to ingest C/C++ (and Zig source) to wasm.

### Why not reimplement emscripten in TS

- Emscripten's pipeline: Clang (C/C++ → LLVM IR) → LLVM wasm backend → wasm-ld → Binaryen
  (optimize/transform) → JS glue.
- We already replaced the Binaryen box with **binaryen-ts**. That tier is tractable in TS because
  wasm is a small, fully-specified IR. It does NOT move the needle on emscripten.
- Emscripten's defining/irreplaceable component is the C/C++ **front end = Clang + LLVM**.
  Reimplementing that in TS is categorically harder than binaryen-ts (parsing + semantic analysis of
  C++), not "more of the same." No sane TS path exists.
- The syslibs (musl, libc++) are NOT port targets — they are C source *compiled to* wasm. Even with a
  TS front end they'd be compiler inputs, not TS ports.

### Why Zig is the right route

- `zig cc` is a bundled Clang; Zig builds libc from source per target (ships ~40 libcs), including
  wasm targets. One compact toolchain supplies BOTH hard pieces: the C/C++ front end and the syslib
  that compiles to wasm.
- Proven role: cargo-zigbuild uses Zig as the portable C cross-compiler to ship code into
  wasm32-wasi. We'd use it the same way.

### Architectural fit (producer → optimize → host stays ours)

- Producer: Zig emits **wasm32-wasi** modules (or freestanding where we supply imports).
- Optimize: run output through **binaryen-ts** (`-Oz` / transforms) — same step wasic uses.
- Host: wasmtk TS side is the **WASI host** (the `run` executor already lives there); **bindgen**
  bridges the canonical ABI.
- Net: only native dependency is the Zig binary at build time. Runtime stays TS/Deno.

### Caveats / known friction

1. `zig cc` is NOT a clean drop-in clang for wasm *linking*. wasm-only linker flags (export control,
   `--import-undefined`, reactor vs. command `_initialize` model) are only partially supported via the
   `zig cc` arg passthrough (see ziglang/zig #12126, #20636). → For precise import/export surface
   control, drive the bundled `wasm-ld` directly or use the build.zig API instead of raw `zig cc`.
2. Reintroduces a native toolchain dependency: Zig still uses the LLVM backend for wasm by default
   (LLVM-independent path in progress). This departs from the pure-TS line that motivated
   binaryen-ts — accepted as the pragmatic floor, analogous to keeping QuickJS for javyc's dynamic
   path.
3. Zig is pre-1.0 — pin a specific Zig version in the toolchain config; expect CLI/API churn.

### Open question (decide early)

`zig cc` compiles translation units; there is no `emconfigure`/`emmake` equivalent. Driving a large
existing C project's configure/make/cmake against the wasm target is on us. Decide whether wasmtk
wraps build-system invocation for the wasm target, or initially ingests only single translation units
/ build.zig inputs.

### Synergy note

Existing TS→Zig mapping work (number→f64, string struct, GeneralPurposeAllocator / arena patterns)
means a future option is for wasic to emit Zig for cases where hand-rolled WAT is painful, then let
the Zig path lower to wasm. Separate axis from this ADR; revisit later.

---

## ADR: Go → wasm ingestion path — TinyGo producer, WASI-first, run via wasmtk host (2026-06-03)

### Origin

The owner has a set of working PowerShell scripts that build/run Go→wasm via TinyGo (`tgo-wasic.ps1`
= `tinygo build -target=wasip1`; `tgo-run.ps1` = build wasip1 + `wasmtime run`; `tgo-modc.ps1` =
`-target=wasm` browser/`syscall/js`; `tgo-init-*.ps1` scaffold `go.mod`+`main.go`; `tgobuild.ps1` =
native `.exe`). Common flags: `-p 1 -no-debug -panic=trap`, local `TINYGO_CACHE`/`GOTMPDIR`. Intent:
fold this into wasmtk as the **Go producer**.

### Decision (scope approved by owner 2026-06-03)

Add a **TinyGo-based Go producer** to the congruent set (6th producer, after TS/JS, C, C++, Rust,
Zig). Scope:

- **TinyGo is the canonical producer** (`-target=wasip1`); stdlib `GOOS=wasip1 go build` is a heavier
  optional fallback (full runtime/GC → large binaries), not the default.
- **WASI-first.** The browser `-target=wasm` (`syscall/js` + `wasm_exec.js` JS glue) path is **NOT
  WASI** and does not fit the WASI-host contract — defer it as a separate, lower-priority target.
  `tgo-modc.ps1`'s `-target=wasm` is therefore *not* the `modc` analog.
- **`run` via wasmtk's own TS WASI host**, not wasmtime. TinyGo `-target=wasip1` emits a WASI P1 core
  module importing `wasi_snapshot_preview1` — exactly the congruent contract — so `wasmtk run` hosts
  it directly. wasmtime stays an **optional** alternate host, not a hard dependency (the scripts'
  `wasmtime run` step is replaced by our executor).
- Native `tgobuild.ps1` (`.exe`) is **out of scope** (native, not wasm).

### Command surface (producer-plugin model)

(Original plan — superseded by the v1-shipped command table below, which folds in the owner's
`tgo-*.ps1` scripts literally. NOTE the divergence: "modc" in those scripts = the BROWSER
`-target=wasm` build, not a `//go:wasmexport` reactor/library. A real Go reactor/library for the
bindgen DLL model was deferred at v1 but is now **SHIPPED 2026-06-07** — `modc --lang=go` builds it by
default; the browser build moved to `--go-target=wasm`.)

### v1 SHIPPED 2026-06-06 (`src/gowasic.ts`) — full `tgo-*.ps1` command set

> **⚠ This table is the v1 (2026-06-06) snapshot. Three rows were SUPERSEDED on 2026-06-07 — see the
> UPDATE blocks below: `wasic --lang=go` REMOVED; `modc --lang=go` flipped browser→WASI reactor
> library (browser now `--go-target=wasm`); `init --lang=go` defaults to a wasm-library scaffold; `run`
> auto-detects Go.** The rows are kept as historical record; the current behavior is in the UPDATEs.

All five owner scripts folded into wasmtk via the `--lang=go` flag (path defaults to cwd):

| Command | Was | Does (v1; see UPDATEs for current) |
| --- | --- | --- |
| `wasmtk init --lang=go [dir]` | `tgo-init-wasi.ps1` | `go mod init <dir>` + `main.go` (v1: "WASI"; now a wasm-**library** scaffold) |
| `wasmtk init --lang=go --go-target=wasm [dir]` | `tgo-init-wasm.ps1` | `go mod init` + browser `syscall/js` `main.go` |
| `wasmtk modc --lang=go [path]` | `tgo-modc.ps1` | v1: `-target=wasm` browser + `wasm_exec.js`. **SUPERSEDED 2026-06-07 → WASI reactor library by default; browser via `--go-target=wasm`** |
| `wasmtk run [--lang=go] <path>` | `tgo-run.ps1` | build wasip1, then run it on wasmtk's WASI host. **`--lang=go` is now OPTIONAL** — `run` auto-detects Go (see UPDATE below) |

**UPDATE 2026-06-07 — `wasmtk wasic --lang=go` REMOVED as a standalone command.** The direct
Go→WASI compile (was `tgo-wasic.ps1`, `tinygo build -target=wasip1`) is no longer a user-facing CLI
option. Rationale: a standalone Go WASI *executable* isn't consumable by wasmtk's value-add pipeline
— it can't be merged (heap-using Go corrupts the shared heap; even leaf Go is only mergeable as an
import, not as a `_start` program) and a WASI command isn't a bindgen library either. The Go→wasip1
**build still exists** in `compileGoWasi(..., target: "wasip1")` and is invoked by **`run`** (with or
without `--lang=go`), which needs it to execute the module — that path is retained. `main.ts`'s `wasic`
case now intercepts `--lang=go` and prints a removal message pointing at `run --lang=go` (exit 1),
rather than compiling. `gowasic.ts` is unchanged (the function stays; only the CLI entry was
withdrawn). So the live Go CLI surface is **`init` / `modc` / `run`** (the `--lang=go` option help now
reads `(init/modc/run)`).

**UPDATE 2026-06-07 — `wasmtk run` auto-detects Go (no `--lang=go` needed).** `run` now routes to the
Go build+run path when its target is (a) a `.go` file, or (b) a directory containing a `go.mod`. The
detection lives in `main.ts` (`isGoRunTarget()` — a `.go`-extension check + `rt.stat` go.mod probe),
deliberately NOT in `gowasic.ts`, so a plain `wasmtk run x.wasm` doesn't import the Go producer module
(which pulls in binaryen) just to decide; `gowasic.ts` is loaded lazily only once a Go target is
confirmed. The explicit `--lang=go` flag still works and is required only where detection can't tell
(e.g. a bare `wasmtk run` with no path → defaults to cwd, which the help guard would otherwise treat
as missing-target). Auto-detection is **`run`-only**; `init`/`modc` still require `--lang=go`.
Rationale (owner, 2026-06-07): when authoring a pure Go *module/library*, the way to test it is to
import it from a small `_start` driver and run that via WASI output — so `run` is the natural Go entry
point and should "just work" on Go source. Verified: `run hello.go`, `run <dir-with-go.mod>` both
build+run; non-Go `run` (.ts/.wasm) unaffected; a directory WITHOUT go.mod is not treated as Go.

**UPDATE 2026-06-07 — `init` dir-creation bug FIXED + two-part "library + test-driver" workflow
verified, and the library-compile GAP confirmed.** Two related items from validating the owner's real
Go workflow (root `main.go` test-driver + a subfolder library package):

- **Bug fixed (`src/gowasic.ts scaffoldGoProject`):** `wasmtk init --lang=go <newdir>` failed with
  "No such cwd" — `go mod init` runs with `cwd: baseDir` but the scaffolder never created `baseDir`.
  Fixed by `rt.mkdir(baseDir, { recursive: true })` before `go mod init`. Verified: init into a
  non-existent dir now scaffolds `go.mod` + `main.go`.
- **Scaffold templates now teach exports (2026-06-07).** Both Go scaffold templates in `gowasic.ts`
  (`MAIN_GO_LIBRARY` / `MAIN_GO_BROWSER` — renamed later that day from `MAIN_GO_WASI` / `MAIN_GO_WASM`;
  see follow-up (3) below) include a commented `//go:wasmexport` example function (`add` / `square`)
  plus guidance (directive goes on the line directly above `func`, no blank line; only
  annotated funcs are exported; use WASM-friendly numeric/bool types). The WASI template frames
  `func main` as the test harness (runs under `wasmtk run`, DCE'd from a library build — ties to the
  single-file pattern above). Verified: both scaffolds are gofmt-clean and build — WASI `run` prints
  `add(2,3)=5`; browser `modc` produces a module that actually exports `square` (confirms
  `//go:wasmexport` works on `-target=wasm` too).
- **Workflow HALF 1 (test loop) — WORKS today.** Project = `go.mod` + root `main.go` (`package main`,
  imports the subpackage `mod/mathlib`, runs assertions) + `mathlib/mathlib.go` (`package mathlib`,
  exported funcs). `wasmtk run <projdir>` auto-detects the go.mod, builds the root driver → wasip1, runs
  it → all checks PASS. This is the developer's "test the library before shipping it" loop, flagless.
- **Workflow HALF 2 (compile a Go library to a wasm library) — ✅ NOW WIRED (2026-06-07; was the
  long-deferred reactor/library item).** `modc --lang=go` now builds a **WASI reactor library** by
  default (`-target=wasip1 -buildmode=c-shared`): no `_start`, exports the `//go:wasmexport` functions +
  runtime, callable via `wasmtk mod`/bindgen — the Go analog of TS `modc` (library mode). The browser
  build (`-target=wasm`, syscall/js + `wasm_exec.js`) is now **opt-in via `--go-target=wasm`**. See the
  dedicated "UPDATE 2026-06-07 — `modc --lang=go` = reactor library" section below for the full
  implementation + the `_initialize` fix it required. (Historical: before this, `modc --lang=go` built
  browser-only and rejected library packages with *"expected main package to have name 'main'"*.)
- **Path forward CONFIRMED at the toolchain level.** Direct `tinygo build -target=wasip1
  -buildmode=c-shared -scheduler=none` of a `package main` with empty `func main()` + `//go:wasmexport`
  funcs produces a 9.5 KB **reactor library** exporting the funcs (`add`/`isLeap`) + `_initialize` +
  `malloc`/`free`/`realloc`/`calloc` + `memory`, with one wasi import (`random_get`). So TinyGo 0.41
  fully supports the reactor/library build; wasmtk just needs a build mode wired to it. IMPORTANT shape
  note tying back to the mergeability matrix above: this c-shared reactor **exports its own dlmalloc
  heap and uses `memory.grow` (count=1)** → it is the **standalone/bindgen "DLL" shape (own memory,
  host-loaded), NOT a mergeable leaf**. A *mergeable* Go library would instead need to be
  allocation-free + `-target=wasm-unknown` (no wasi import, no allocator) — the leaf case proven
  mergeable in the matrix above. So the deferred feature really has two sub-targets: (a) reactor
  `c-shared`/`wasip1` library for the bindgen/host DLL model (heap OK), and (b) `wasm-unknown`
  allocation-free leaf for the wasmmerge model.
- **VERIFIED 2026-06-07 — single-file "library + tests in one `main.go`" works via DCE.** A single
  `package main` file can hold BOTH the `//go:wasmexport` library functions AND a `func main` test
  harness, and the two build modes cleanly separate them:
  - **Command build** (`-target=wasip1`, what `wasmtk run` does) → `func main` is `_start` → the test
    harness runs. The `//go:wasmexport` funcs are also present (harmless). So `wasmtk run <onefile.go>`
    runs the tests today, no changes.
  - **Reactor/library build** (`-target=wasip1 -buildmode=c-shared`) → `func main` is NOT a root, so
    TinyGo's dead-code elimination strips `main` and everything reachable only from it. Proven: a
    constant placed only in the test harness (`222000`) was ABSENT from the library build while the
    library constant (`111000`) remained; `main`/`selfCheck` were not exported; and even the `println`
    `fd_write` import was gone. The library exported only the two `//go:wasmexport` funcs + runtime
    (`_initialize`/`malloc`/`free`/`memory`/fmin-fmax).
  - Export control is automatic: **only `//go:wasmexport` functions are user-exported**, regardless of
    what else is in the file. The one authoring rule: keep test-only helpers OUT of the exported call
    graph (don't let an exported func call a test helper), else DCE keeps it.
  - **Implication for the deferred feature (NOW IMPLEMENTED 2026-06-07 — see the next UPDATE):** this
    is the ideal Go DLL authoring ergonomic — one file, `wasmtk run` to test, build to ship. It needed
    the **reactor (`-buildmode=c-shared`) build mode** (at the time of writing `modc --lang=go` still
    built `-target=wasm` browser); wiring that reactor-library mode into `modc --lang=go` is exactly
    what was done next, turning this pattern into a wasmtk command. The clean-library result itself is a
    TinyGo guarantee (DCE), confirmed above.

**UPDATE 2026-06-07 — `modc --lang=go` = WASI reactor library (Option A, IMPLEMENTED) + the
`_initialize` fix it required.** Closes the HALF 2 gap above. Triggered by the owner hitting it: a
browser module built by `modc --lang=go` couldn't be called (`wasmtk mod main.wasm square` →
`WebAssembly.instantiate(): Import #2 "gojs": module is not an object or function`). Root cause: the
browser (`-target=wasm`) module imports `gojs` (TinyGo's syscall/js bridge that only `wasm_exec.js` in
a real browser supplies); wasmtk's hosts provide WASI + `env`, not `gojs`. The deeper mismatch: TS
`modc` = a clean library (no `_start`, no WASI imports — wasic emits no runtime), but `modc --lang=go`
was mapped to TinyGo's browser target → a browser app with `_start` + `gojs`, not a library.

**Design decision (owner-approved):** make `modc --lang=go` build the **WASI reactor library** by
default — the Go analog of TS `modc` library mode — and move the browser build behind
`--go-target=wasm`. Caveat captured: Go's mandatory runtime means even this library is NOT as bare as
the TS one — it carries `_initialize` (runtime init), one WASI import (`random_get`), and runtime
`malloc`/`free`. (The truly-bare option, `wasm-unknown` with no WASI, is allocation-free-only — the
mergeable-leaf sub-target, still not auto-wired; reactor is the general default.)

**Implementation:**
- `src/gowasic.ts`: `GoTarget` gained `"reactor"` → `-target=wasip1 -buildmode=c-shared` (both the
  real-wasm-opt and shim+`-scheduler=none` paths add `-buildmode=c-shared`; `buildWithStd` adds it for
  `GOOS=wasip1` too — std Go 1.24+ supports `//go:wasmexport` in c-shared). Report label
  "wasip1 c-shared library".
- `main.ts`: `modc --lang=go` → `target: goBrowser ? "wasm" : "reactor"` where
  `goBrowser = --go-target=wasm`. Help text + the `--go-target` option updated (now `(init/modc)`).
- **`_initialize` fix (`src/utils.ts`) — required, or reactor exports trap.** A reactor must run
  `_initialize` (Go runtime/heap/stack/globals setup) before any export, else exports trap
  (`unreachable`). `callExport` (`wasmtk mod`) and `runWasi`'s named-export path now call
  `exports._initialize()` (if present) right after instantiation, before the target function. No-op for
  non-reactor modules (wasic/modc TS libraries have no `_initialize`). `callExport` also gained the same
  Phase-40 `env` Proxy as `runWasi` (unlisted `env` imports → no-op stubs) for robustness — note this
  does NOT provide `gojs`, so browser modules remain (correctly) un-hostable.
- Empirically proven the bug + fix: reactor `square(12)` trapped without `_initialize`, returned `144`
  after it.

**Verified end-to-end (2026-06-07):** `init` Go lib → `modc --lang=go` builds a 9.8 KB reactor library
(no `_start`, exports `add`, has `_initialize`, no `gojs`) → `wasmtk mod golib.wasm add 2 3` → **5**.
Browser opt-in `modc --lang=go --go-target=wasm` → browser module + `wasm_exec.js`. `run --lang=go`
still builds+runs the command test harness. TS `modc` library regression: `wasmtk mod addts.wasm addts
2 3` → 5 (the `_initialize`/proxy changes are a no-op for runtime-free TS). Merge slice `^(18|38)`
14/14 (run-path edits in `utils.ts` don't disturb normal running). So the full Go DLL loop is live:
**one `main.go` (`//go:wasmexport` funcs + `func main` tests) → `wasmtk run` to test → `wasmtk modc
--lang=go` to ship the callable library** (`func main`/tests DCE-stripped from the library).

**Follow-ups from the default flip (2026-06-07):** (1) A browser-style `main.go` (imports
`syscall/js`) fails the default library build — `syscall/js` only has Go files for the browser
(`GOOS=js`) target, so wasip1/reactor reports *"build constraints exclude all Go files in
.../syscall/js"*. Rather than surface the raw error, `gowasic.ts` now appends an actionable hint
(`goBuildHint`): "use `--go-target=wasm` for a browser module, or remove `syscall/js` for a library."
Wired into all three build-error sites (real-wasm-opt, shim, std-go). (2) The browser **scaffold's own
printed Build hint** was corrected to `wasmtk modc --lang=go <dir> --go-target=wasm` (it previously
said plain `modc`, which now builds a library and fails on the syscall/js scaffold). (3) **`init
--lang=go` now defaults to a wasm LIBRARY scaffold** (owner, 2026-06-07): since the Go producer's
primary output is a wasm library (`modc --lang=go`), init shouldn't require a flag for it. `GoScaffold`
renamed `"wasi"|"wasm"` → `"library"|"browser"`; templates renamed `MAIN_GO_WASI`→`MAIN_GO_LIBRARY`
(now frames `add` as "an EXPORTED library function" + a PASS/FAIL self-test `main`), `MAIN_GO_WASM`→
`MAIN_GO_BROWSER`. Default messaging "Initializing Go wasm library project"; post-init guidance prints
both **Test** (`wasmtk run --lang=go <dir>`) and **Build** (`wasmtk modc --lang=go <dir>`). Browser
project still opt-in via `--go-target=wasm`. All verified: init (no flag) → run PASS → modc library →
`wasmtk mod lib.wasm add 2 3` → 5; browser opt-in scaffolds + builds; gofmt-clean.

`--go-runtime=tinygo` (default) / `std` (stdlib `go`: `GOOS=wasip1` for the `run` build, `GOOS=js` for
the browser modc). All builds use `-p 1 -no-debug -panic=trap` + local `TINYGO_CACHE`/`GOTMPDIR`, matching
the scripts. Input may be a `.go` file, a dir, or omitted (cwd); a dir builds package `.` → `<dir>.wasm`
(needs `cwd` on `rt.Command` — added to `rt.ts`). `tgobuild.ps1` (native `.exe`) is out of scope.

NOTE on `modc` (⚠ **v1/2026-06-06 — SUPERSEDED 2026-06-07**: `modc --lang=go` now builds a WASI
reactor library by default and the Go reactor/library is **shipped**, not deferred; browser is
`--go-target=wasm`. See the "UPDATE 2026-06-07 — `modc --lang=go` = WASI reactor library" section
above. The v1 text is kept for history.): in the owner's scripts "modc" = the BROWSER `-target=wasm`
build (NOT the wasmtk TS-library/reactor sense). So `modc --lang=go` produces a browser module
(syscall/js, needs `wasm_exec.js` + a browser) — `wasmtk run` can't host it. A genuine Go
*library/reactor* (`//go:wasmexport`, no `_start`, for the bindgen DLL model) is still **deferred**
(with Go string/aggregate bindgen → ABI forward-alignment). `deno.json` exports `./gowasic`. `main.ts`
branches `init`/`modc`/`run` on
`--lang=go` (and intercepts `wasic --lang=go` with a removal message → `run`; see UPDATE 2026-06-07
above) (+ allows an omitted positional target → cwd). Verified end-to-end (TinyGo 0.41.1 / Go 1.26):
init(wasi+wasm), `run --lang=go` (builds 90 KB wasip1 + prints output), modc browser (10 KB) +
`wasm_exec.js` copied. Fixture: `tests/go_fixtures/hello.go` (NOT auto-run — needs TinyGo).

**wasm-opt handling (the load-bearing detail).** TinyGo's internal `wasm-opt` call is
`--asyncify -Oz -g`. `--asyncify` is **mandatory codegen** (TinyGo's goroutine scheduler), NOT
optimization — a passthrough that skips it leaves unresolved `asyncify` imports (won't instantiate).
So:

- **Real `wasm-opt` present** (on PATH or `$WASMOPT`) → TinyGo uses it → full support incl. goroutines.
- **Absent** → `gowasic` writes a **passthrough `wasm-opt` shim** (answers `--version`; copies input →
  `-o` output, no opt; cross-platform `.cmd`/`.sh` launcher invoking `rt.execPath()` + a Deno shim) and
  builds with **`-scheduler=none`** (which drops the asyncify request — wasm-opt call becomes just
  `-Oz`), then runs **binaryen-ts `-Oz`** on the result. No external binaryen needed. Works for
  goroutine-FREE code; goroutine code errors under `-scheduler=none` → clear "install binaryen" hint.
- binaryen-ts has `-Oz` (`optimize()`) but **NOT the `asyncify` pass** (verified: `runPasses(["asyncify"])`
  → "Unknown pass"). Porting asyncify into binaryen-ts (to cover goroutine Go with zero external deps)
  is a large future item — see roadmap "asyncify pass in binaryen-ts".

**Two `rt.Command` gotchas baked into `gowasic.ts`:** (1) `rt.Command.output()` always reads
`result.stdout`/`stderr`, which **throws unless they are `"piped"`** — never pass `"null"`/`"inherit"`
to a `.output()` call (use `"piped"` and decode). (2) `rt.remove` is single-arg (unlink-based under
Bun) — use `Deno.remove(dir, {recursive:true})` for the temp shim dir. Subprocess env is built as
`{ ...rt.env.toObject(), WASMOPT/GOOS/GOARCH }` so PATH is preserved.

**Deferred (as of v1; updated 2026-06-07):** Go string/slice/aggregate **bindgen** host marshalling
(still deferred — needs ABI forward-alignment; Go's string/slice layout ≠ Canonical ABI). ~~reactor
`modc --lang=go`~~ — **DONE 2026-06-07** (`modc --lang=go` now builds the `//go:wasmexport` reactor
library by default). Browser `syscall/js` — shipped behind `--go-target=wasm`.

### Architectural fit (producer → optimize → host stays ours)

- Producer: TinyGo emits **wasip1** core modules (or reactor libraries via `//go:wasmexport`).
- Optimize: through **binaryen-ts** (`-Oz`) — same step wasic uses.
- Link/merge: **wasmmerge/wasmbundle** at P1 (shared linear memory) — same as every producer.
- Host: wasmtk TS **WASI host** (`run`); **bindgen** bridges the canonical ABI.
- Net new native dependency: the **TinyGo binary** at build time (bundles its own LLVM). Runtime
  stays TS/Deno.

### Caveats / known friction

1. **Native toolchain dependency** (TinyGo binary, bundles LLVM) — same pragmatic-floor caveat as the
   Zig ADR and QuickJS for javyc. Pin a specific TinyGo version; expect CLI churn (pre/early-1.0).
2. **ABI/bindgen is the hard part.** Numeric exports bridge cleanly; Go strings/slices have their own
   in-memory layout, so generic string/aggregate marshalling depends on the **ABI forward-alignment**
   decision (canonical layout + return convention) above. Numerics-first, like every producer.
3. **Reactor exports** require recent TinyGo (`//go:wasmexport`) — verify the pinned version supports
   it; otherwise `-buildmode=c-shared`.
4. **P2:** TinyGo can target `wasip2` natively (~0.33+) — treat like Rust's wasip2 (deliberate
   terminal path only; do not feed native-P2 output into the P1 merge tier).

### Open question (shared with the C/C++ ADR)

TinyGo compiles a Go module/package cleanly; driving larger Go build setups (cgo, build tags, vendored
C deps) against the wasm target is the less-bounded part. Decide how far wasmtk wraps `go.mod`/build
invocation vs. ingests a single package.
