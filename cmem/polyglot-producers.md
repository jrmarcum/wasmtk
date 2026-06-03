# Polyglot producer congruence + ABI / P2 posture (+ C/C++ Zig ADR)

> Added 2026-06-03. Authoritative, portable memory (this folder supersedes the gitignored
> machine-local `CLAUDE.md`). Links: [architecture.md](architecture.md) (Canonical ABI / build
> pipeline), [roadmap.md](roadmap.md) (execution order), [vision.md](vision.md) (polyglot ecosystem).

## Project goal — one congruent polyglot wasm capability

**wasmtk's goal is to unify the TS/JS, C, C++, Rust, and Zig toolchains into a single congruent
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

### Producer → contract mapping

- **TS (typed subset):** `wasic` — direct TS → optimized WAT → wasm, no JS runtime. (existing)
- **TS/JS (dynamic):** `javyc` — embedded Javy/QuickJS engine path. (existing)
- **C / C++:** `zig cc` / `zig c++` — Zig's bundled clang + libc-built-from-source → `wasm32-wasi`.
  (per ADR below)
- **Zig:** `zig build-exe -target wasm32-wasi` (or freestanding). Cleanest native path.
- **Rust:** `rustc` `wasm32-wasip1` (WASI 0.1; the old `wasm32-wasi`, renamed in Rust 1.78 and
  removed under the old name in 1.84). Use **Zig as the linker / C cross-compiler** for crates with
  C deps (cargo-zigbuild pattern). rustc does its own LLVM wasm codegen; Zig fills the C/link role.

### Scope boundary — pin the contract to WASI Preview 1 / core modules (for now)

**None of the native producers emit WASI Preview 2 / components natively, except Rust.** Ecosystem
norm, not a per-toolchain gap:

- **Zig:** stdlib still targets WASI P1; emits a single core module. P2 only via post-compile adapter
  (`wasm-tools component new --adapt wasi_snapshot_preview1.wasm`), scriptable in build.zig.
  (confirmed 2026-06-03)
- **C / C++ (wasi-sdk / zig cc):** P1 core modules; same adapter step for P2.
- **Rust:** the one exception — `wasm32-wasip2` is native P2 (tier-2 since Rust 1.82, Oct 2024).
  `wasm32-wasip1` is still P1 + adapter.
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
