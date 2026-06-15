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

```text
┌─────────────────────────────────────────────────────────────┐
│                    POLYGLOT BUILD LAYER                     │
│              (pixi foundation + wasmtk orchestration)       │
│   wasmtk build │ wasmtk compose │ wasmtk setup │ wasmtk port│
└─────────────────────────────────────────────────────────────┘
         ↓               ↓               ↓              ↓
┌─────────────────────────────────────────────────────────────┐
│                   LANGUAGE COMPILER LAYER                   │
│  wasic(TS) │ cargo-component(Rust) │ componentize-py(Python)│
│  TinyGo(Go) │ zig(Zig) │ ...                               │
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
│  loader-go │ loader-jvm │ loader-c(header)                 │
│         (all implement the UniversalWasmLoader Spec)        │
└─────────────────────────────────────────────────────────────┘
```

---

## Projects

### Project 1 — wasmtk (active)

**Repository:** `jrmarcum/wasmtk`
**Role:** TypeScript-to-WASM compiler; reference language pillar; polyglot build
orchestrator CLI

**Rust-side sibling toolkit:** `jrmarcum/rsxtk` (crates.io `rsxtk`, v0.4.4 / 2026-04-20,
MIT OR Apache-2.0) — *"A high-performance Rust WASM Toolkit for managing and running
WASI scripts, WAT, and WASM modules."* It is the **Rust producer's build+run driver**:
compiles Rust → `wasm32-wasip1` (+ `.cwasm` precompile), runs via wasmtime. No
WIT/bindgen/component yet (those stay wasmtk's). Distinct from the planned
`universalWasmLoader-rs` *library loader* — rsxtk is a build/run **CLI**. See
[polyglot-producers.md](polyglot-producers.md) § "Rust producer = rsxtk".

Current state: **All 50 phases complete; Stage 0 Canonical ABI alignment *partial* (see
[polyglot-producers.md](polyglot-producers.md) — `cabi_realloc` exported, but return side not yet
canonical; P1 core module + sidecar WIT, not a component);
Stage 0.5 (dual JSR /compat backends) substantively complete; Stage 0.6
(allocator unification in wasmmerge) complete; Stage 0.7 (all five Tier-1 stdlib
capabilities — `Set<i32>` + `Map<i32,i32>` + `JSON` shared-heap libraries + the
`Date` and `RegExp` leaf libraries) shipped, plus feature-level tree-shake (virtual
`wasmtk:<cap>` imports) and `wasmtk hybrid --auto` type-routing.** Historical baseline
under npm:wabt + npm:binaryen: 446/446 tests passing (2026-05-25; 270 wasic +
Go-by-Example + 103 bindgen + 73 jstyper). **Under the current dual JSR /compat
stack (`jsr:@jrmarcum/wabt-ts@^1.3.2/compat` +
`jsr:@jrmarcum/binaryen-ts@^1.3.5/compat`):** the full `tests/wasm_wasi`
suite is **309/309** (`core_` 33/33), jstyper 73/73, and **bindgen 104/104** (Phase 53, 2026-06-15,
added `Number.parseInt`/`parseFloat` + multi-level interface inheritance; the ABI return side was
forward-aligned to callee-allocated + `cabi_post`, bindgen 103→104; pre-publish hardening
2026-06-12 added `15_ElseChainForms`; Phase 52, 2026-06-11,
added the leaf conveniences `void`/chained-assignment/`in`/`Array.from`-`of`-`isArray`/
`String.fromCodePoint` + 6 `52_*` tests; Phase 51, 2026-06-05/07,
added `instanceof` + 7 `51_*` tests, incl. the 3 class-construction-gap fixes; `51_ObjectSpread` (51.2)
+ `51_ParamDestructuring` + `51_NestedDestructuring` + `51_NestedTuple` (51.3) + `51_UtilityTypes`
(51.4) added 2026-06-07; `48_SingleLineBraceIf` was the single-line-brace-`if` regression added
2026-06-03). The 7
long-standing failures were all fixed 2026-06-02: `5e`/`19_*` via a wasic value-fallthru
rewrite, and `38_*` via the wabt-ts 1.3.1 hex-float-literal fix (the constants were being
encoded as 0). wabt-ts 1.3.0 had earlier recovered `15_panic` / `18_Multi-Scope`
(call-before-return encoder fix). Compiles
TypeScript to optimized WASM via WAT (assembled by `wabt-ts/compat`, the
JSR-native TypeScript port of wabt) and Binaryen `-Oz` (via `binaryen-ts/compat`,
the JSR-native TypeScript port of binaryen). Both compat modules deliberately
mirror their upstream npm shape so wasmtk's deno.json is the single switch point —
flipping back to `npm:wabt` / `npm:binaryen` is a one-line specifier change.
Generates WIT files alongside every compiled module (Phase 41). Phase 50
(`wasmtk bindgen`) generates typed TypeScript host binding files from WIT using
the Canonical ABI (`cabi_realloc`, out-parameter string returns). `wasmtk hybrid`
(prototype) splits a TypeScript file into a WASM core + TS runner.

Remaining additions scoped here:

- All five Tier-1 stdlib capabilities shipped (Set/Map/Date/JSON/RegExp); feature-level
  tree-shake (virtual `wasmtk:<cap>` imports), `hybrid --auto` type-routing, and the §7-#7
  kernel-scope decision (build wasmtk's own dynamic runtime) are all done (2026-06-02). The two
  remaining large tracks are **#5 Promise/async** and the **own dynamic runtime** build — see
  `stdlib-bundling-brief.md` / `roadmap.md`
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

**Local checkouts:** all loader repos live under
`D:\Programs\_ProgramExamples\Example_Programs\GithubProjects\universalWasmLoader\` (each its own git
repo on `main`). Each carries its own portable `cmem/` memory (set up 2026-06-15) and a `cmem/INDEX.md`
with the same "update the project memory" / "look for code issues" triggers as wasmtk.

| Repo                         | Language            | Underlying Runtime | Distribution     |
|------------------------------|---------------------|--------------------|------------------|
| `universalWasmLoader-js`     | TypeScript / JS     | WebAssembly (host) | JSR (+ npm compat) |
| `universalWasmLoader-rs`     | Rust                | wasmtime crate     | crates.io        |
| `universalWasmLoader-py`     | Python              | wasmtime-py        | PyPI             |
| `universalWasmLoader-go`     | Go                  | wasmtime-go        | pkg.go.dev       |
| `universalWasmLoader-jvm`    | Java / Kotlin       | Chicory            | Maven Central    |
| `universalWasmLoader-dotnet` | C# / .NET           | wasmtime-dotnet*   | NuGet            |
| `universalWasmLoader-dart`   | Dart (web-first)    | browser WASM (js_interop) | pub.dev   |
| `universalWasmLoader-c`      | C (Zig/V/Julia)     | wasmtime C API     | header-only      |

Julia uses this loader via Julia's `ccall` FFI to the wasmtime C API — no separate
Julia-specific repo is planned. Julia is Tier 3 (community-contributed or long-term).

### Loader runtime + WASI strategy (owner decisions 2026-06-15)

**Principle: native/server runtimes use wasmtime (engine + built-in WASI + Component-Model-ready);
web/browser runtimes use the host's `WebAssembly` + a hand-rolled minimal WASI-P1 shim.** wasmtime is
preferred for native because it's the de-facto reference runtime, has full built-in WASI, and is the
Component Model runtime — and (owner, 2026-06-15) "wasmtime is faster" than the pure-Go interpreter
alternative (wazero), so even `-go` uses **wasmtime-go** (CGO + native lib) rather than wazero.

| Port(s) | Engine | WASI source |
| --- | --- | --- |
| `-rs` | wasmtime crate | `wasmtime-wasi` (`WasiP1Ctx`; needs `Store<WasiP1Ctx>`) |
| `-py` | wasmtime-py | `linker.define_wasi(WasiConfig())` |
| `-go` | **wasmtime-go** (decided over wazero — speed) | wasmtime built-in |
| `-c`/`-cpp`, **Zig** | wasmtime C API (Zig via `@cImport`, cleanest) | wasmtime built-in |
| `-dotnet` | Wasmtime NuGet | wasmtime built-in |
| `-js` | host `WebAssembly` (Deno/Node/browser) | hand-rolled shim (`wasi.js`) ✅ |
| `-dart` **web** | browser `WebAssembly` (js_interop) | hand-rolled shim |
| `-dart` **native** *(future 2nd backend)* | wasmtime C API via `dart:ffi` | wasmtime built-in |
| `-jvm` | **Chicory** (no wasmtime JVM embedding) | `chicory-wasi` |

**Outliers are intentional:** JS and Dart-web can't reach wasmtime (browser/JS host) → host
`WebAssembly` + hand-roll; the JVM has no official wasmtime embedding → pure-Java Chicory + `chicory-wasi`.

**Dart is dual-backend** (the only language spanning both worlds): the current **web** backend is a
native-Dart impl over browser `WebAssembly` (js_interop), and a future **native** backend would use
`dart:ffi` → the wasmtime C API (Dart VM / Flutter desktop+mobile). Selected via conditional imports.
NOTE: Dart-web *could* instead interop-call the published `-js` loader directly, but that re-adds a JS
dependency and only works on web — so the native-Dart web impl we built is preferred; FFI/wasmtime is
native-only (`dart:ffi` is unavailable on the web). **`dart:ffi`→wasmtime native backend + `libwasmtime`
distribution (bundled per-platform binaries / native-assets) is a tracked FUTURE track**, not part of
the §10 propagation.

### Per-language publishing / versioning (owner guidance 2026-06-15)

Each loader repo publishes to its language's registry with its own version scheme — there is no
shared `deno task` mechanism across them (only `-js` is a Deno project). Set up a bump+publish flow
per repo when it's ready to release; `-js` is the reference (`deno task bump` → `deno task publish` →
tag `vX.Y.Z` → GitHub Action `deno publish` with provenance).

| Repo | Registry | Version lives in | Bump / publish |
|---|---|---|---|
| `-js` | JSR | `deno.json` `version` | ✅ `deno task bump` / `deno task publish` — **PUBLISHED 1.0.8** (provenance, score 100) |
| `-rs` | crates.io | `Cargo.toml` `version` | ✅ run:-only workflow + `scripts/bump.sh`/`release.sh` (2026-06-15). Secret: `CARGO_REGISTRY_TOKEN` |
| `-py` | PyPI | `pyproject.toml` `version` | ✅ run:-only workflow + `pixi run bump`/`scripts/release.sh`. Secret: `PYPI_API_TOKEN` (project-scoped) |
| `-go` | pkg.go.dev | **git tag `vX.Y.Z`** (no version file) | `git tag vX.Y.Z` + push → proxy auto-indexes (stub — no CI yet) |
| `-jvm` | Maven Central | `build.gradle.kts` `version` | ✅ run:-only workflow + `./gradlew bump`. Secrets: `MAVEN_CENTRAL_USERNAME/PASSWORD` + `GPG_PRIVATE_KEY/GPG_PASSPHRASE`; needs `io.github.jrmarcum` namespace verification |
| `-dotnet` | NuGet | `.csproj` `<Version>` | `dotnet pack` + `dotnet nuget push` (stub — no CI yet) |
| `-dart` | pub.dev | `pubspec.yaml` `version` | ✅ run:-only workflow + `scripts/bump.dart`/`release.sh`. Secret: `PUB_DEV_CREDENTIALS` (from `dart pub login`) |
| `-c` (C/C++) | **vcpkg** ([vcpkg.io](https://vcpkg.io/en/)) | `vcpkg.json` `version` | a vcpkg **port** (`portfile.cmake` + `vcpkg.json`) submitted to the vcpkg registry (PR to `microsoft/vcpkg`) or served from a custom registry; the portfile fetches the repo at a tagged ref |
| Zig | **zigistry** ([zigistry.dev](https://zigistry.dev/)) | `build.zig.zon` `.version` | public repo + git tag `vX.Y.Z`; zigistry.dev indexes GitHub Zig packages (those with a `build.zig.zon`), fetched by URL+hash |

`*` `-dotnet` runtime is unconfirmed (no `.csproj` yet — stub). **Maturity (2026-06-15):** `-js`
(reference), `-rs`, `-py`, `-jvm`, and `-dart` are all real implementations **on SPEC 3.0.0**
(canonical callee-allocated string returns + `cabi_post`) and **verified** against their own test
suites (`-js` 24/24, `-rs` `cargo test` 24/24, `-jvm` `./gradlew test` 24/24, `-py` 3 string tests
pass + 13 unrelated pre-existing `.wat`-harness failures, `-dart` `dart test -p chrome` 7/7 in real
Chrome). `-dart` is **web-first** (`dart:js_interop` over browser `WebAssembly`; runtime decision
RESOLVED 2026-06-15 — a native `dart:ffi` backend is a possible future add). `-go` / `-dotnet` are
stubs (no source) → build fresh against SPEC 3.0.0. **C/Zig publishing RESOLVED (owner, 2026-06-15):**
C/C++ → **vcpkg** (vcpkg.io); Zig → **zigistry.dev**. (Both are git-tag/source-fetch ecosystems rather
than upload-a-blob registries — vcpkg via a port that fetches a tagged ref, zigistry via GitHub
indexing of `build.zig.zon`.)

**CI workflow constraint — `run:`-only (learned the hard way 2026-06-15).** The loader repos' org
restricts GitHub Actions to **`jrmarcum`-owned actions**, so any third-party `uses:` step
(`actions/checkout`, `denoland/setup-deno`, …) makes the workflow end in **`startup_failure`** — no
step runs, nothing reaches JSR, yet a local `deno task publish` still creates the tag + GitHub release
(so it *looks* published on GitHub but is absent on the registry). `universalWasmLoader-js` v1.0.6 hit
exactly this when its `publish.yml` was (incorrectly) switched to `actions/checkout@v4` +
`denoland/setup-deno@v2` to "match wasmtk"; reverted to **`run:`-only** steps (`git clone` +
curl-install Deno) and v1.0.8 then published cleanly **with provenance**. So when wiring publish CI for
the other ports, use **`run:`-only** workflows in these repos. (NOTE the asymmetry: the **wasmtk** repo
itself currently DOES allow external `uses:` — its 1.7.0 published with provenance via
`actions/checkout@v4` + `setup-deno@v2` — i.e. the restriction is per-repo, not blindly org-wide.
Verify a repo's Actions policy before assuming either way.)

**`-js` PUBLISHED:** `@jrmarcum/universal-wasm-loader@1.0.8` is live on JSR (package renamed
2026-06-15 from `@jrmarcum/universalwasmloader-js`; `deno.json name` must equal the JSR package name),
**JSR score 100** — `hasProvenance: true`, `percentageDocumentedSymbols: 1.0`.

Every loader exposes the same conceptual API in its language's idiom:

```typescript
// JS/TS   → wasm_import("./module.wasm")
// Python  → wasm_import("./module.wasm")
// Rust    → wasm_import("./module.wasm").await?
// C       → wasm_import("./module.wasm", &exports)

// Go      → WasmImport("./module.wasm")
// Java    → WasmImport.load("./module.wasm")
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
| Rust        | wasmtk --lang=rust (init/initmod/modc/build/run/add/remove/list/fmt/clean → rsxtk) | Producer ✅ 2026-06-07 (delegates to rsxtk); bindgen deferred | Tier 1 |
| Python      | componentize-py                          | Full                    | Tier 1          |
| Go          | wasmtk --lang=go (init/modc/run; TinyGo/std; modc→wasm library) | Producer v1 ✅ 2026-06-06; reactor library ✅ 2026-06-07; string/aggregate bindgen deferred | Tier 2 |
| Zig         | wasmtk --lang=zig (init/modc/run; zig build-exe) | Producer ✅ 2026-06-07 (library + wasi program); bindgen deferred | Tier 2 |
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
out-parameter convention for string returns. 446/446 tests pass under npm:wabt +
npm:binaryen (historical baseline, 2026-05-25). Under the current dual JSR
/compat stack (wabt-ts/compat 1.2.9 + binaryen-ts/compat 1.2.9), the wasic
population is 260/270 PASS (96.3%); Stage 0 functionality (Canonical ABI shim
generation, bindgen out-parameter convention) is unchanged at the wasic /
bindgen layer.*

- ✅ Replaced `__malloc` export with `cabi_realloc(ptr, old_size, align, new_size) → i32`
- ✅ Changed string return emission: shim wrappers write ptr+len to caller-provided 8-byte
  return area (`_r = cabi_realloc(0,0,4,8)` passed as trailing arg)
- ✅ Updated `bindgen.ts`: uses `cabi_realloc` + `DataView` out-parameter pattern
- ✅ `utils.ts` test runner verified — no changes needed (internal WASM calls unaffected)
- ✅ WIT generation confirmed — `string` type in WIT, no regression
- ✅ 446/446 tests pass under npm:wabt (270 wasic + Go-by-Example + 103 bindgen + 73 jstyper; +3 Phase 21 stress tests, +3 Phase 22 stress tests added 2026-05-25)

---

### Stage 0.5 — Dual JSR /compat Migration ✅ COMPLETE (wasmtk, 2026-05-28)

*Substantively complete. Both wasmtk compiler-toolkit dependencies (wabt and
binaryen) now resolve to JSR-native TypeScript ports in the jrmarcum ecosystem:
`npm:wabt@^1.0.36` → `jsr:@jrmarcum/wabt-ts@^1.2.9/compat`, and
`npm:binaryen@^116.0.0` → `jsr:@jrmarcum/binaryen-ts@^1.2.9/compat`. The wasmtk
source code calls the upstream-npm-shaped API (`await wabt()` + `parseWat` /
`readWasm`; `binaryen.readBinary(...)` + `Module` methods) — both compat modules
deliberately mirror that shape, so deno.json is the single switch point. A
3-line `src/binaryen.ts` wrapper handles the only structural asymmetry (CJS
default-export under npm vs ES namespace under JSR). Fifteen toolchain bugs
discovered during this work — 10 in wabt-ts (folded expression parsing, type
section omission, call/call_indirect name resolution, tag-export parsing,
f64 literal encoding, multi-value return, memory alignment defaults,
store-with-call ordering, parenless-folded opcodes, br_if-cond global.get
resolution, try/catch encoding) and 5 in binaryen-ts (if-without-else
inversion, RemoveUnusedModuleElements tag mangling, elem-segment drop on
round-trip, CoalesceLocals signature mismatch, catch-body spurious block
wrapper) — were all filed and fixed upstream by 1.2.9. See CLAUDE.md §
"Pluggable wabt + binaryen backends" for the full bug tables.*

- ✅ `deno.json`: `"wabt": "jsr:@jrmarcum/wabt-ts@^1.2.9/compat"`, `"binaryen": "jsr:@jrmarcum/binaryen-ts@^1.2.9/compat"`
- ✅ `src/binaryen.ts` wrapper handles CJS-default vs ES-namespace asymmetry
- ✅ Call-site shape preserved (upstream-npm-shaped API works against both backends)
- ✅ Wasic-side patch: explicit `inlineExport: false` on `.toText(...)` calls (wabt-ts/compat's default differs from npm:wabt's)
- ✅ Full wasic suite: **260/270 PASS (96.3%)** under dual /compat 1.2.9 — historical snapshot; the 10 then-failing tests (9 wasic-side codegen + 1 binaryen-ts `-Oz` interaction) have all since been fixed (suite is now **293/293**; see compiler-bugs.md / testing.md)
- ✅ Switching back to `npm:wabt` / `npm:binaryen` is a one-line deno.json change — both backends remain supported as fallbacks

---

### Stage 0.6 — Allocator Unification in wasmmerge ✅ COMPLETE (wasmtk, 2026-05-30)

*Closes the last gap that prevented `wasmbundle` from acting as a real on-demand
linker for stdlib capability modules. Pre-unification, each `wasic` / `modc`
module shipped its own bump allocator: `$__malloc` advancing a module-local
`$__heap_ptr` seated past that module's static data. After prefix-mangling, a
merge produced two independent allocators over one linear memory, with
overlapping addresses on the first allocation from either side. With Stage 0.6,
`wasmmerge` detects the bump-allocator function form semantically, drops it from
each merged module, and redirects every call site and global reference to the
master module's shared `$__malloc` and `$__heap_ptr`. The master's heap cursor
is recomputed in `wasic.ts` / `wasmbundle.ts` to sit past the **combined**
post-relocation static data.*

- ✅ `src/wasmmerge.ts` — `detectBumpAllocator()` helper identifies the form
  semantically (single i32 param/result, one set/get on a single global,
  `local.get 0` + `i32.add`, no loads/stores/calls); dropped function index
  redirected to `$__malloc` in `funcName`; `renameGlobalRefs()` extended to
  redirect the heap-ptr global to `$__heap_ptr`. `WatMergeResult` gains
  `droppedAllocator: boolean`.
- ✅ `src/wasic.ts` — post-merge rewrite in `compileWasiTs` and `compileLibTs`
  rewrites `$__heap_ptr` to `(i32.const dataOffset)` and grows memory to
  `max(2, ceil(dataOffset / 65536) + 1)` pages when any sub-merge dropped an
  allocator.
- ✅ `src/wasmbundle.ts` — when any sub-merge dropped an allocator, the master
  WAT synthesizes a shared `$__heap_ptr` global and `$__malloc` function pair
  and recomputes pages.
- ✅ Regression test `tests/wasm_wasi/18b_SharedHeapTwoLibraries.ts` — two
  modc-compiled libraries both allocate via `.push()`; main asserts both
  return the expected length; PASSING.
- ✅ Runtime notice on each unified merge:
  `allocator unified: dropped $__malloc + heap-ptr global; call sites redirected
  to main module's $__malloc / $__heap_ptr.`
- ✅ Binaryen upgrade: `binaryen-ts/compat` 1.2.9 → 1.3.1 (fixes one prior wasic-side
  failure in the suite); full wasic suite **262/271 PASS (96.7%)** under
  wabt-ts/compat 1.2.9 + binaryen-ts/compat 1.3.1 + the unification pass.

This unblocks the Tier-1 stdlib capability libraries
(`stdlib-bundling-brief.md` §3) — delivered first in Stage 0.7 below.

---

### Stage 0.7 — Tier-1 stdlib capabilities: `Set<i32>` + `Map<i32,i32>` + `Date` (wasmtk, 2026-05-30/31)

*First three Tier-1 stdlib capabilities and the pattern-setter for the rest (JSON,
RegExp). Set/Map demonstrate the headline shared-heap case the Stage 0.6 allocator
unification was built for: a hash table built inside a separately-compiled `modc`
library shares ONE live heap with the `wasic` program that imports it. Date is the
first **leaf** capability — pure value-in/value-out with no heap, so the merge is a
straight function splice.*

- ✅ `tests/wasm_wasi_bundle/set_bundle/set_lib_modc.ts` — `Set<i32>` open-addressing
  hash table. Handle = i32 pointer to a 4-slot `Int32Array` header
  `[count, cap, keysPtr, usedPtr]`; two `Int32Array(cap)` bucket arrays; linear
  probing on `key & (cap-1)`; ×2 grow + rehash at load factor 0.5 (handle stays
  stable). Exports `setNew`/`setAdd`/`setHas`/`setSize`.
- ✅ Driver imports the library; the library's `$__malloc` resolves to the host
  module's bump cursor via Stage 0.6 unification → one shared heap. Self-checking
  (`@test-pipeline` `18c_SetCapabilityLibrary.ts`, PASSING; traps on any wrong
  result so the `run` step proves Set semantics).
- ✅ Two supporting compiler fixes the shared-heap pointer pattern required:
  (1) **TypedArray view over a raw pointer** (`src/wasic.ts`) — `const v: Int32Array
  = ptr as unknown as Int32Array` now registers a typed-array view so element
  **writes** through it work (previously stubbed; reads worked only by a
  coincidental i32-pointer fallback); (2) **imported-function signature resolution
  from inline params** (`src/wasmmerge.ts`) — `mergeWasmWat` now parses
  `(param i32 i32)` headers when wabt-ts 1.3.0 emits them without a `(type N)`
  reference (otherwise import args defaulted to f64 → `call[0] expected i32, found
  f64`).
- ✅ Backend bump to `wabt-ts@^1.3.0/compat` (fixes the folded call-before-return
  encoder bug — see brief §7a / CLAUDE.md bug table). Recovered `15_panic` and
  `18_Multi-Scope`.
- ✅ Fixed a pre-existing modc bug: string-**returning** library functions imported
  an unused `wasi_snapshot_preview1.fd_write` (the bindgen loader can't supply it).
  `allocString` no longer sets `hasConsoleLog`. `bindgen_tests.ts` 99/103 → 103/103.
- ✅ `tests/wasm_wasi_bundle/map_bundle/map_lib_modc.ts` — `Map<i32,i32>` reuses the
  Set hash core (linear probing + ×2 grow/rehash) and adds a parallel values array.
  Handle = i32 pointer to a 5-slot `Int32Array` header
  `[count, cap, keysPtr, valsPtr, usedPtr]` over three `Int32Array(cap)` bucket arrays.
  Exports `mapNew`/`mapSet`/`mapGet`/`mapHas`/`mapSize`; `mapSet` updates in place on
  an existing key (count stable), `mapGet(h, key, fallback)` returns the caller's
  fallback for absent keys; key→value association survives rehash. Self-checking
  `@test-pipeline` `18d_MapCapabilityLibrary.ts` (PASSING). **No new compiler fixes
  required** — built entirely on the wasic features the Set capability established.
- ✅ `tests/wasm_wasi_bundle/date_bundle/date_lib_modc.ts` — `Date` UTC integer
  calendar math (first leaf capability). Howard Hinnant's exact-integer civil↔days
  algorithms, valid across the whole proleptic Gregorian calendar incl. pre-epoch /
  negative day counts. Exports `isLeapYear`, `daysInMonth`, `daysFromCivil`,
  `weekdayFromDays`, `yearFromDays`, `monthFromDays`, `dayFromDays`. Self-checking
  `@test-pipeline` `18e_DateCapabilityLibrary.ts` (PASSING). As the first merged
  library that is dense integer arithmetic over large constants, Date surfaced
  **two merge-path codegen bugs**: (1) `wasmmerge`'s blanket `i32.const >= 260`
  data-pointer relocation corrupted arithmetic literals (`% 400` → `% 668`) — fixed by
  scoping relocation to the merged module's own `(data …)` address extent; (2)
  binaryen-ts/compat's optimizer miscompiled the doubly-merged module — **fixed upstream
  in binaryen-ts/compat 1.3.2** (the temporary skip-Binaryen-on-merge workaround was
  removed once 1.3.2 landed). Full `tests/wasm_wasi` suite: **268/275** (7 pre-existing
  failures, no regressions).

All five Tier-1 capabilities (Set/Map/Date/JSON/RegExp) are shipped.

---

### Stage 1 — WIT-Aware Loader + Spec (universalWasmLoader)

*universalWasmLoader repo. **CURRENT PRIORITY.** Approximately 2–3 sessions.*

Reference implementation: `wasmtk/src/bindgen.ts` (Phase 50) — the compile-time code
generator that Stage 1 replicates at runtime. All ABI details are authoritative there.

**Core loader:**

- `wit-parser.js` — parse WIT exports, imports, function signatures and types;
  same regex approach as `wasmtk/src/bindgen.ts` `parseWit()`
- `abi.js` — ABI encode/decode; primary `"component"` profile matches the Canonical ABI
  in `src/bindgen.ts` exactly (`cabi_realloc`, out-parameter string returns, bool as i32,
  numerics direct); `"raw"` profile for modules not following the Canonical ABI
- Update `universal-wasm-loader.js` — WIT auto-detection, options interface
  `wasm_import(path, { abi?, wit?, imports? })`, typed export proxy
- Update `universal-wasm-loader.d.ts` — `WasmImportOptions`, `InstancePool`, generic
  return type

**Instance lifecycle (bump-allocator memory model):**

wasic uses a bump allocator with no `free`. Each WASM instance has its own isolated
linear memory that accumulates allocations for the lifetime of the instance. The two
supported patterns and their correct usage:

- **Singleton** `wasm_import(path, opts)` — one instance, cached after first load.
  Correct for: CLI tools, applications that load a library at startup, modules with
  numeric-only exports, any bounded-call scenario. Memory accumulates but never
  meaningfully fills up in normal application lifetimes.

- **Pool** `createPool(path, { size, ...opts })` — returns an `InstancePool` that
  holds `size` fresh WASM instances and cycles through them. Each checkout gets a
  fresh bump pointer; no memory reset logic needed. Correct for: servers handling
  many requests with string-param calls, loop-intensive processing.

`InstancePool` API to implement in `universal-wasm-loader.js`:

```javascript
// Singleton (DLL pattern — default)
const lib = await wasm_import("./module.wasm");
lib.greet("world");

// Pool (server/loop pattern)
const pool = await createPool("./module.wasm", { size: 4 });
const result = await pool.run(lib => lib.greet("world"));  // acquire → call → release

// Manual acquire/release
const lib2 = await pool.acquire();
try { lib2.greet("world"); }
finally { pool.release(lib2); }
```

`InstancePool` interface:

- `acquire(): Promise<T>` — checks out an instance (waits if all busy)
- `release(instance: T): void` — returns instance to the pool
- `run<R>(fn: (lib: T) => R | Promise<R>): Promise<R>` — acquire + call + release
- `size: number` — total pool capacity
- `available: number` — instances currently idle
- `destroy(): void` — tears down all instances

**Spec and tests:**

- `SPEC.md` — full cross-language specification; sections: core interface, WIT
  auto-detection, ABI profiles, Canonical ABI definition, instance lifecycle model
  (singleton vs. pool, bump allocator memory model), language port requirements,
  reference test suite, versioning
- Reference test suite — `.wasm` + `.wit` pairs from wasmtk Phase 50 fixtures
  (`math_50`, `booleans_50`, `strings_50`, `imports_50`) with known I/O; plus a
  pool test using `strings_50` with 100 iterations to verify no memory exhaustion

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
  (componentize-py)
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
- Additional language recipes: Go, Zig
- Additional loaders: `universalWasmLoader-go`, `universalWasmLoader-jvm`, `universalWasmLoader-c`

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

```text
jrmarcum/
├── wasmtk                        ← TypeScript compiler + polyglot build CLI
├── wabt-ts                       ← JSR-native TS port of wabt; consumed by wasmtk via /compat (Stage 0.5 ✅)
├── binaryen-ts                   ← JSR-native TS port of binaryen; consumed by wasmtk via /compat (Stage 0.5 ✅)
├── universalWasmLoader           ← JS/TS loader + SPEC.md (reference impl)
├── universalWasmLoader-rs        ← Rust port (Stage 2)
├── universalWasmLoader-py        ← Python port (Stage 2)
├── universalWasmLoader-go        ← Go port (Stage 4)
├── universalWasmLoader-jvm       ← Java/Kotlin port (Stage 4)
└── universalWasmLoader-c         ← Zig/V/Julia header (Stage 4)
```

The spec in `universalWasmLoader/SPEC.md` is the single written contract that all
repos agree on. The ABI conventions in `wasmtk/CLAUDE.md` are the authoritative source
for what wasmtk emits. The two documents cross-reference each other.

---

## Immediate Next Steps

In order:

1. **Stage 1** — Enhance universalWasmLoader + write SPEC.md — **CURRENT PRIORITY**
   Reference: `wasmtk/src/bindgen.ts` (Phase 50) for ABI details (Canonical ABI alignment is
   *partial* — see [polyglot-producers.md](polyglot-producers.md); realloc/param side adjacent,
   return side not yet canonical)
2. **stdlib-bundling-brief.md §5–7** — Tier-1 capability libraries as `modc` modules,
   plus tree-shake wiring in `wasmbundle`; unblocked by Stage 0.6 allocator unification.
   `Set<i32>` + `Map<i32,i32>` + `Date` + `JSON` (parse+navigate, integer v1) + `RegExp`
   (backtracking matcher) all shipped (Stage 0.7, 2026-05-30/31). Parallel track to Stage 1.
3. **Stage 2** — `universalWasmLoader-rs` and `universalWasmLoader-py` — validates the spec
4. **Stage 3** — Build orchestration — the pixi integration becomes real
5. **Stage 0** ✅ COMPLETE (partial alignment) — `cabi_realloc` export + out-param string returns (2026-05-19); 446/446 pass under npm:wabt baseline (2026-05-25). NOTE: this is *partial* Canonical ABI alignment — return side not yet canonical, output is a P1 core module + sidecar WIT (see [polyglot-producers.md](polyglot-producers.md)); full forward-alignment is a decided-but-unimplemented track
6. **Stage 0.5** ✅ COMPLETE — Dual JSR /compat migration done (2026-05-28); wabt-ts/compat 1.2.9 + binaryen-ts/compat 1.2.9; 260/270 PASS on the wasic population; 15 toolchain bugs filed and fixed during rollout; deno.json is the single switch point for npm ↔ JSR backends
7. **Stage 0.6** ✅ COMPLETE — Allocator unification in wasmmerge done (2026-05-30); binaryen-ts/compat bumped to 1.3.1; 262/271 PASS; `wasmbundle` now functions as an on-demand stdlib linker
