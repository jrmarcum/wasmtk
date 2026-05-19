# The Polyglot WASM Ecosystem — Project Scope

## Vision Statement

Build a polyglot application development ecosystem where WebAssembly is the universal
binary format and WIT is the universal interface contract. Any language compiles to a
WASM component. Components compose into complete applications regardless of source
language. A single project management tool — built on pixi — orchestrates the entire
build pipeline. A family of language-specific loaders, all following a common
specification with TypeScript as the reference implementation, enables consuming
components from any host language. The result is a system where language choice is an
implementation detail, not an architectural constraint — and where replacing a Python
prototype with a Rust production implementation is a one-line manifest change.

---

## Guiding Principles

1. **WIT is the universal interface contract.** The WIT file is what components agree
   on. The language behind a component is an implementation detail invisible to
   everything else.

2. **The Canonical ABI is the transport standard.** All components follow the WASM
   Component Model Canonical ABI for type encoding. This gives native interop with the
   entire Bytecode Alliance ecosystem at no extra cost.

3. **TypeScript is the reference implementation.** The universalWasmLoader JS/TS
   implementation defines the interface, behavior, and test suite that all language
   ports must match. Build the reference first; ports follow.

4. **pixi manages environments. wasmtk manages WASM intelligence.** pixi installs
   toolchains, manages packages, and runs tasks. wasmtk knows what to build, how to
   wire it, and how to validate the WASM/WIT layer. Neither reimplements the other.

5. **Progressive porting is a first-class workflow.** Swapping one language
   implementation for another behind the same WIT interface must be a safe, validated,
   low-friction operation — not an afterthought.

6. **No lock-in.** Any component built to the Canonical ABI and accompanied by a WIT
   file is a valid participant in the system, regardless of what compiled it.

---

## The Ecosystem Map

```
┌─────────────────────────────────────────────────────────────┐
│                    POLYGLOT BUILD LAYER                     │
│              (pixi foundation + wasmtk orchestration)       │
│   wasmtk build │ wasmtk compose │ wasmtk setup │ wasmtk port│
└─────────────────────────────────────────────────────────────┘
         ↓               ↓               ↓              ↓
┌─────────────────────────────────────────────────────────────┐
│                   LANGUAGE COMPILER LAYER                   │
│  wasic(TS) │ cargo-component(Rust) │ componentize-py(Python)│
│  clang wasm32(C/C++) │ TinyGo(Go) │ dotnet wasi(C#) │ ...  │
└─────────────────────────────────────────────────────────────┘
         ↓               ↓               ↓              ↓
┌─────────────────────────────────────────────────────────────┐
│                  WASM COMPONENT LAYER                       │
│         component.wasm + component.wit (per component)      │
│              wasm-tools compose → app.wasm                  │
└─────────────────────────────────────────────────────────────┘
         ↓               ↓               ↓              ↓
┌─────────────────────────────────────────────────────────────┐
│                   HOST RUNTIME LAYER                        │
│  universalWasmLoader(JS/TS) │ loader-rs │ loader-py         │
│  loader-go │ loader-jvm │ loader-dotnet │ loader-c(header)  │
│         (all implement the UniversalWasmLoader Spec)        │
└─────────────────────────────────────────────────────────────┘
```

---

## Projects

### Project 1 — wasmtk (active)

**Repository:** `jrmarcum/wasmtk`
**Role:** TypeScript-to-WASM compiler; reference language pillar; polyglot build
orchestrator CLI

Current state: **All 50 phases complete + Stage 0 Canonical ABI alignment complete.
349/349 tests passing (2026-05-19).** Compiles TypeScript to optimized WASM via WAT +
Binaryen. Generates WIT files alongside every compiled module (Phase 41). Phase 50
(`wasmtk bindgen`) generates typed TypeScript host binding files from WIT using the
Canonical ABI (`cabi_realloc`, out-parameter string returns). `wasmtk hybrid` (prototype)
splits a TypeScript file into a WASM core + TS runner.

Remaining additions scoped here:

- `wasmtk build` — polyglot build orchestration command (Stage 3)
- `wasmtk compose` — component composition wrapper (Stage 3)
- `wasmtk setup <language>` — language recipe installer (Stage 4)
- `wasmtk port <component> --to <language>` — porting scaffold (Stage 4)
- `[wasmtk]` section support in `pixi.toml` (Stage 3)

---

### Project 2 — universalWasmLoader (next active project)

**Repository:** `jrmarcum/universalWasmLoader`
**Role:** JS/TS host runtime; reference implementation of the loader spec

Current state: `wasm_import(path, importObject?)` handles Node, Deno, Bun, browsers,
and TypeScript via fetch + WebAssembly API.

The ABI translation reference is now available: `wasmtk/src/bindgen.ts` (Phase 50)
implements the Canonical ABI — string encoding via `cabi_realloc`, string returns via
the out-parameter convention (caller allocates an 8-byte return area via
`cabi_realloc(0,0,4,8)`, passes its address as the trailing arg, callee writes ptr+len),
bool normalization, numeric passthrough, and import callback wiring. universalWasmLoader
Stage 1 replicates this at runtime (reading WIT dynamically) rather than at compile time
(code generation).

Additions scoped here (Stage 1):

- `wit-parser.js` — regex-based WIT parser; same format wasmtk emits (see CLAUDE.md)
- `abi.js` — ABI encode/decode utilities; primary `"component"` profile matches the
  Canonical ABI in `src/bindgen.ts` exactly (`cabi_realloc`, out-parameter string returns);
  `"raw"` profile for modules not following the Canonical ABI
- Updated `universal-wasm-loader.js` — WIT auto-detection, options interface, ABI
  translation layer, typed export proxy
- Updated `universal-wasm-loader.d.ts` — `WasmImportOptions`, generic return type
- `SPEC.md` — full cross-language specification
- Reference test suite — `.wasm` + `.wit` pairs compiled from wasmtk Phase 50 fixtures

---

### Project 3 — Cross-Language Loaders (new)
**Repositories:** separate repos per language under `jrmarcum/`
**Role:** Per-language host runtimes; each implements the UniversalWasmLoader Spec

| Repo                         | Language            | Underlying Runtime | Distribution     |
|------------------------------|---------------------|--------------------|------------------|
| `universalWasmLoader-rs`     | Rust                | wasmtime crate     | crates.io        |
| `universalWasmLoader-py`     | Python              | wasmtime-py        | PyPI             |
| `universalWasmLoader-go`     | Go                  | wazero             | pkg.go.dev       |
| `universalWasmLoader-jvm`    | Java / Kotlin       | Chicory            | Maven Central    |
| `universalWasmLoader-dotnet` | C# / .NET           | Wasmtime NuGet     | NuGet            |
| `universalWasmLoader-c`      | C/C++/Zig/V/Julia   | wasmtime C API     | header-only      |

Julia uses this loader via Julia's `ccall` FFI to the wasmtime C API — no separate
Julia-specific repo is planned. Julia is Tier 3 (community-contributed or long-term).

Every loader exposes the same conceptual API in its language's idiom:

```
// JS/TS   → wasm_import("./module.wasm")
// Python  → wasm_import("./module.wasm")
// Rust    → wasm_import("./module.wasm").await?
// C       → wasm_import("./module.wasm", &exports)

// Go      → WasmImport("./module.wasm")
// Java    → WasmImport.load("./module.wasm")
// C#      → await WasmImport.LoadAsync("./module.wasm")
```

All pass the same reference test suite defined in the spec.

---

### Project 4 — UniversalWasmLoader Spec (new, lives in Project 2 repo)
**File:** `SPEC.md` in `jrmarcum/universalWasmLoader`
**Role:** The cross-language contract that all loaders implement

Sections:
1. **Core interface** — function signature, options shape, return type contract
2. **WIT auto-detection** — path convention, fallback behavior
3. **ABI profiles** — `component` (canonical), `raw`, and future named profiles
4. **Canonical ABI definition** — string params via `cabi_realloc`, string returns via
   out-parameter, bool as i32 0/1, numerics direct
5. **Language port requirements** — what a port MUST implement to be conformant
6. **Reference test suite** — list of test cases with expected inputs/outputs
7. **Versioning** — spec version, compatibility guarantees

---

### Project 5 — Polyglot Build Orchestrator (new, extends wasmtk CLI)
**Lives in:** `jrmarcum/wasmtk` as additional CLI commands
**Role:** The pixi-aware project manager that ties all components together

The `[wasmtk]` section of `pixi.toml` defines components, interfaces, and composition
wiring. wasmtk reads this section and orchestrates the build:

```toml
[project]
name = "my-polyglot-app"
channels = ["conda-forge"]
platforms = ["win-64", "linux-64", "osx-64"]

[dependencies]
rust = ">=1.75"

[pypi-dependencies]
componentize-py = "*"

[tasks]
build = "wasmtk build"
test  = "wasmtk test"
run   = "wasmtk run"

[wasmtk.components]
api    = { language = "typescript", source = "src/api/",    wit = "interfaces/api.wit"    }
ingest = { language = "python",     source = "src/ingest/", wit = "interfaces/ingest.wit" }
engine = { language = "rust",       source = "src/engine/", wit = "interfaces/engine.wit" }
legacy = { language = "c",          source = "src/legacy/", wit = "interfaces/legacy.wit" }

[wasmtk.composition]
ingest -> engine
engine -> api
legacy -> engine

[wasmtk.host]
runtime = "deno"
loader  = "universalWasmLoader"
```

`wasmtk build` reads this manifest, invokes the correct compiler per language, validates
WIT interfaces, composes components, and produces the final `app.wasm`.

---

## Language Support Matrix

| Language    | Compiler Path                            | Component Support       | Recipe Priority |
|-------------|------------------------------------------|-------------------------|-----------------|
| TypeScript  | wasmtk wasic                             | Full (Phase 41 WIT)     | Tier 1          |
| Rust        | cargo-component                          | First-class             | Tier 1          |
| Python      | componentize-py                          | Full                    | Tier 1          |
| C / C++     | clang wasm32-wasi + wasm-tools wrap      | Via adapter             | Tier 1          |
| Go          | TinyGo                                   | Partial, in progress    | Tier 2          |
| C# / .NET   | dotnet wasm/wasi                         | .NET 8+ experimental    | Tier 2          |
| Zig         | zig --target wasm32-wasi                 | Via adapter             | Tier 2          |
| Java/Kotlin | TeaVM or GraalVM                         | Limited                 | Tier 3          |
| V           | v -os wasm                               | Basic                   | Tier 3          |
| Julia       | ccall to wasmtime C API                  | None native             | Tier 3          |

Julia hosts WASM via `ccall` into the wasmtime C API. No Julia-specific loader repo is
planned — Julia consumers use `universalWasmLoader-c` directly.

Tier 1 languages ship with the first build orchestrator release. Tier 2 follow in
subsequent releases. Tier 3 are community-contributed or long-term.

---

## Phased Roadmap

### Stage 0 — Canonical ABI Alignment ✅ COMPLETE (wasmtk, 2026-05-19)

*Completed. wasic now exports `cabi_realloc` instead of `__malloc` and uses the
out-parameter convention for string returns. All 349/349 tests pass.*

- ✅ Replaced `__malloc` export with `cabi_realloc(ptr, old_size, align, new_size) → i32`
- ✅ Changed string return emission: shim wrappers write ptr+len to caller-provided 8-byte
  return area (`_r = cabi_realloc(0,0,4,8)` passed as trailing arg)
- ✅ Updated `bindgen.ts`: uses `cabi_realloc` + `DataView` out-parameter pattern
- ✅ `utils.ts` test runner verified — no changes needed (internal WASM calls unaffected)
- ✅ WIT generation confirmed — `string` type in WIT, no regression
- ✅ 349/349 tests pass

---

### Stage 1 — WIT-Aware Loader + Spec (universalWasmLoader)

*universalWasmLoader repo. **CURRENT PRIORITY.** Approximately 2–3 sessions.*

Reference implementation: `wasmtk/src/bindgen.ts` (Phase 50) — the compile-time code
generator that Stage 1 replicates at runtime. All ABI details are authoritative there.

- `wit-parser.js` — parse WIT exports, imports, function signatures and types;
  same regex approach as `wasmtk/src/bindgen.ts` `parseWit()`
- `abi.js` — ABI encode/decode with `"wasic"` profile (matching bindgen exactly) and
  stub `"component"` profile for future Canonical ABI support
- Update `universal-wasm-loader.js` — WIT auto-detection, options interface
  `wasm_import(path, { abi?, wit?, imports? })`, typed export proxy
- Update `universal-wasm-loader.d.ts` — `WasmImportOptions`, generic return type
- `SPEC.md` — full cross-language specification
- Reference test suite — `.wasm` + `.wit` pairs from wasmtk Phase 50 fixtures
  (`math_50`, `booleans_50`, `strings_50`, `imports_50`) with known I/O

---

### Stage 2 — High-Priority Cross-Language Loaders
*Separate repos. Approximately 2–3 sessions each.*

- `universalWasmLoader-rs` — Rust (crates.io)
- `universalWasmLoader-py` — Python (PyPI)

These two cover the highest-demand use cases outside the JS ecosystem and validate
that the spec is implementable before committing to additional ports.

---

### Stage 3 — Build Orchestration Foundation
*wasmtk repo. Approximately 3–4 sessions.*

- `[wasmtk]` section parser in wasmtk CLI
- `wasmtk build` command — reads manifest, invokes per-language compilation
- Language recipes: TypeScript (wasic), Rust (cargo-component), Python
  (componentize-py), C (clang wasm32)
- WIT validation — verify interface contracts across components before composition
- `wasmtk compose` — wraps `wasm-tools compose` with WIT-aware wiring
- `wasmtk run` — runs composed output via configured host runtime
- Dependency graph — build components in correct WIT-consumption order

---

### Stage 4 — Full Polyglot Project System
*wasmtk repo + additional language repos. Ongoing.*

- `wasmtk setup <language>` — scaffolds component + adds pixi.toml configuration
- `wasmtk port <component> --to <language>` — new language scaffold with same WIT
- `wasmtk activate <component>` — swaps implementation, validates WIT compatibility
- Incremental builds — source hashing, only rebuild what changed
- Additional language recipes: Go, C#, Zig
- Additional loaders: `universalWasmLoader-go`, `universalWasmLoader-jvm`, `universalWasmLoader-dotnet`, `universalWasmLoader-c`

---

### Stage 5 — Ecosystem
*Long-term.*

- Component registry — publish and consume pre-built WASM components
- IDE integration — WIT-aware cross-language intellisense at component boundaries
- Cross-component debug adapter — WASM DWARF debugging across language boundaries
- Cross-component profiler — trace call paths across component boundaries regardless
  of source language

---

## Repository Summary

```
jrmarcum/
├── wasmtk                        ← TypeScript compiler + polyglot build CLI
├── universalWasmLoader           ← JS/TS loader + SPEC.md (reference impl)
├── universalWasmLoader-rs        ← Rust port (Stage 2)
├── universalWasmLoader-py        ← Python port (Stage 2)
├── universalWasmLoader-go        ← Go port (Stage 4)
├── universalWasmLoader-jvm       ← Java/Kotlin port (Stage 4)
├── universalWasmLoader-dotnet    ← C# port (Stage 4)
└── universalWasmLoader-c         ← C/C++/Zig/V/Julia header (Stage 4)
```

The spec in `universalWasmLoader/SPEC.md` is the single written contract that all
repos agree on. The ABI conventions in `wasmtk/CLAUDE.md` are the authoritative source
for what wasmtk emits. The two documents cross-reference each other.

---

## Immediate Next Steps

In order:

1. **Stage 1** — Enhance universalWasmLoader + write SPEC.md — **CURRENT PRIORITY**
   Reference: `wasmtk/src/bindgen.ts` (Phase 50) for all ABI details (Canonical ABI complete)
2. **Stage 2** — `universalWasmLoader-rs` and `universalWasmLoader-py` — validates the spec
3. **Stage 3** — Build orchestration — the pixi integration becomes real
4. **Stage 0** ✅ COMPLETE — Canonical ABI alignment in wasmtk done (2026-05-19); 349/349 pass
