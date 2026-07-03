# Polyglot component model + language-selection CLI — OPEN DESIGN DISCUSSION

> **STATUS: DRAFT / NOT YET DECIDED (captured 2026-06-06).** This is a saved design
> discussion to circle back to — nothing here is implemented or finalized. It records the
> tentative decisions, the options weighed, the holes found, and a concrete schema draft so the
> thread can be resumed without re-deriving it. When this is resolved, fold the decided parts
> into `architecture.md` / `roadmap.md` / a new `component-model.md` and delete or archive this file.
>
> **UPDATE 2026-06-07 — parts of the Go CLI here are now SHIPPED (supersede the tentatives below):**
> `wasic --lang=go` was **removed** (so tentative #2's "`wasic` takes `--lang=go`" no longer applies to
> Go); **`modc --lang=go` builds a WASI reactor library** by default (browser via `--go-target=wasm`);
> **`run` auto-detects Go** (a `.go` file or a `go.mod` dir — NOT explicit-flag-only); **`init --lang=go`
> defaults to a wasm library scaffold**. See [polyglot-producers.md](polyglot-producers.md) +
> [design-decisions.md](design-decisions.md). Also, the central **"cross-language merge is impossible"**
> finding below is now **empirically backed** (the native-producer mergeability matrix) and **enforced**
> by the `call_indirect` + `memory.grow` merge guards — with one refinement: *allocation-free leaves*
> from Go/Rust/Zig **can** merge; only allocating/runtime modules (real libraries/components) can't. So
> the conclusion (cross-language inclusion = `instance`/WIT/bindgen, not `merge`) stands for components.

## Scope of the discussion

How wasmtk should (1) select the language/producer per command, and (2) organize a polyglot
monorepo where a JS-runtime host project includes WASM components compiled from several
languages. Builds on the congruent-producer goal in [polyglot-producers.md](polyglot-producers.md)
and the "TypeScript as a DLL" vision in [vision.md](vision.md).

## Tentative decisions (by the project owner, this thread)

1. **Producer set = TS (existing), Go, Rust, Zig.** Each has a single unambiguous module file
   extension (`.ts/.go/.rs/.zig`), so producer detection is 1:1.
2. **`init`, `modc`, `wasic` take an explicit `--lang=<>`** for clarity/consistency. In a
   tasks-driven monorepo the flag is written **once per sub-project task**, so it is
   self-documenting, not repetitive friction (the earlier friction objection was about ad-hoc
   interactive use and does not apply here).
3. **`run` auto-detects** the file/project type from extension, compiles to a WASI-based `.wasm`,
   and runs it. `run` is the dev-loop convenience; the build commands stay explicit.

### Recommended refinement to #2 (not yet accepted)

Keeping `--lang` *literally required for every language* collides with the established reality:
`wasmtk wasic foo.ts` is **flagless TS today**, and the entire `tests/wasi/wasm_wasi` suite (287
tests), every `@test-pipeline`/`@step` annotation, the published 1.6.x CLI, and the docs all call
wasic/modc flagless. Proposed resolution — **`--lang` accepted everywhere, defaults to `ts`,
required only when the extension is non-TS**; a non-TS file with no flag errors early with a
detected-extension hint (`foo.go looks like Go — pass --lang=go`). This keeps zero churn, keeps
TS self-documenting-optional (`--lang=ts` is valid), and prevents Go/Rust/Zig being fed to the TS
parser by accident. Consequence: the build commands must **peek at the extension for diagnostics**
(not to auto-select), reusing the same extension table `run` uses.

## Project topology (owner's framing)

A **main host project** in Deno/Bun/Node whose project file drives compilation **through tasks**.
Each language compilation lives in **its own folder as a sub-project** (with its own manifest:
`go.mod` / `Cargo.toml` / `build.zig` / a TS folder), compiled to `.wasm` and **included** into the
main project.

What the topology fixes from the earlier CLI discussion:
- **File-vs-project unit dissolves**: the sub-project *folder* is the compilation unit; the folder
  manifest is the on-disk language truth.
- **The `--lang` friction objection dissolves**: written once per sub-project task, it documents
  intent in the task file.

## THE central architectural finding (most important thing here)

**"Include into the main project" is two different mechanisms, and cross-language can only use one.**

- **`merge`** (`wasmmerge`/`wasmbundle`) → one `.wasm`, **shared linear memory**, allocator
  unification (Stage 0.6). **TS-only** (plus the TS/modc capability libs). A TinyGo/Rust module
  brings its own runtime/stack/allocator/`_start`; splicing it into wasic's linear memory collides
  two runtimes, not two modules. **Cross-language merge is impossible.**
- **`instance`** (`bindgen` → `loadModule` per `.wasm`) → isolated memories, host mediates calls
  across the **WIT** boundary. This is the "TypeScript as a DLL" model, applied polyglot. **Every
  non-TS component must reach the host this way.**

So the cross-language convergence point is the **WIT/bindgen host boundary, NOT wasmmerge**.
wasmmerge is the intra-TS / capability optimization. A polyglot host loads a Go component and a
Rust component as **two separate instances behind two WIT contracts**, never as one bundle.

**And the instance path is ABI-blocked for non-TS today:** TS emits clean WIT now; **bindgen for
Go/Zig/Rust output is deferred** (strings/aggregates need ABI forward-alignment — see
polyglot-producers.md). NOTE (2026-06-07): the **Go, Zig, and Rust producers are now all shipped**
(`--lang=go|zig|rust`), but shipping a producer is **not** the same as shipping an includable
component — TS components are fully includable now; Go/Zig/Rust are *runnable/buildable* but not yet
cleanly *includable* via WIT/bindgen for strings/structs (bindgen pending for all three).

## Secondary holes to remember

- **Task file isn't hermetic.** `deno task build:rust` → wasmtk → cargo assumes the toolchains
  exist out of band. That provisioning layer is **pixi** (vision). Real topology is 3 layers:
  pixi (toolchains) ⟶ deno/bun/node tasks (orchestration) ⟶ wasmtk (drivers).
- **Build graph / incrementality.** Merge/stage step fans in on all sub-builds; sub-builds are
  independent/parallel. Decide whether wasmtk does staleness skipping (source mtime vs `.wasm`) or
  leans on each toolchain's own cache (cargo/tinygo cache well). `build` should be a near-no-op
  when nothing changed.
- **Output staging convention.** Where the per-component `.wasm`/`.wit`/`.bindings.ts` land
  (`dist/wasm/`) — encode per-component in the component map.
- **Two-level `init`.** "Init the host project" vs "add a language sub-project" are different ops,
  both wanting `--lang`. Suggest `wasmtk init` (scaffold host) vs `wasmtk add --lang=go ./go-core`
  (scaffold a component folder + register it). Don't fold both into one `init --lang`.
- **Reproducibility spans lockfiles.** Each sub-project pins its own toolchain (Cargo.lock,
  go.mod toolchain, zig version); `deno.lock` captures none. Only pixi pins the toolchains. The
  project file is the orchestration envelope, not the reproducibility envelope.

## Draft schema — `wasmtk.json` at the host root

One source of truth, consumed by the build task graph AND the host loader wiring. Runtime-agnostic
(works for Deno/Bun/Node; tasks just read it).

```jsonc
{
  "host": {
    "runtime": "deno",            // deno | bun | node
    "entry": "src/main.ts",
    "out": "dist/app.wasm",
    "stage": "dist/wasm"          // where component .wasm/.wit/.bindings.ts land
  },
  "components": {
    "strutil": {                  // pre-built shared TS lib, spliced into host
      "lang": "ts", "source": "components/strutil",
      "shape": "lib", "include": "merge"
    },
    "geo": {                      // Go component, loaded as its own instance
      "lang": "go", "source": "components/geo",
      "shape": "lib", "include": "instance",
      "toolchain": { "go-runtime": "tinygo", "target": "wasip1" }
    },
    "physics": {                  // Rust component, instance
      "lang": "rust", "source": "components/physics",
      "shape": "lib", "include": "instance",
      "toolchain": { "target": "wasip1" }
    },
    "bench": {                    // standalone Zig executable — an endpoint you `run`
      "lang": "zig", "source": "components/bench",
      "shape": "exe", "include": "none"
    }
  }
}
```

### Field reference

| Field | Values | Meaning |
| --- | --- | --- |
| `lang` | `ts` `go` `rust` `zig` | the producer (`--lang`); folder manifest should agree |
| `source` | path | the sub-project folder = the compilation unit |
| `shape` | `exe` \| `lib` | `exe`→wasic (`_start`, runnable); `lib`→modc (exports, includable) |
| `include` | `merge` \| `instance` \| `none` | how the host consumes it (`none` = exe endpoint) |
| `toolchain` | obj | per-language variant (`go-runtime`, `target` triple…) |
| `out` | path | output override (default `stage/<name>.wasm`) |
| `wit` | path | interface contract (default `stage/<name>.wit`; required for `instance`) |
| `deps` | `[name]` | build ordering / cross-instance wiring |

> Built-in **capabilities** (Set/Map/Date/JSON/RegExp) are NOT components — they're auto-pulled via
> virtual `wasmtk:<cap>` imports + tree-shake merge when the host TS imports them. Never in the map.

### Validity matrix (the decision driver — schema enforces this)

| `lang` | `shape:exe` (`run`) | `lib` + `merge` | `lib` + `instance` |
| --- | --- | --- | --- |
| **ts** | ✅ run standalone | ✅ the only merge path | ✅ DLL today |
| **go** | ✅ run (shipped) | ❌ cross-lang merge impossible | ⚠️ pending Go bindgen/ABI |
| **rust** | ⚠️ run (producer not built) | ❌ | ⚠️ pending producer + bindgen |
| **zig** | ⚠️ run (producer not built) | ❌ | ⚠️ pending producer + bindgen |

Three hard rules the schema encodes:
1. **`merge` ⇒ `lang:ts`** (shared-memory wasmmerge; whole merge column is TS-only, incl. caps).
2. **Cross-language inclusion ⇒ `instance`** (bindgen/loadModule behind WIT, own memory).
3. **`instance` ⇒ a `.wit` exists** — the gap: TS now; Go/Zig/Rust producers all shipped (2026-06-07)
   but their WIT/bindgen is pending (ABI forward-alignment) → not yet includable as instances.

Bluntly: the schema is **fully live for an all-TS monorepo today** (merge + instance + caps). The
moment a Go/Rust/Zig `instance` row is added, you're on the ABI-forward-alignment + per-language
WIT/bindgen track. The schema doesn't change that — it makes the boundary explicit instead of a
link-time surprise.

### Build graph it generates

```
include == "instance":   wasmtk modc <source> --lang=<lang> [toolchain] → stage/<name>.wasm + .wit
                         wasmtk bindgen stage/<name>.wit                → stage/<name>.bindings.ts
include == "merge":      wasmtk modc <source> --lang=ts                 → stage/<name>.wasm
host build (deps: merge libs):
                         wasmtk wasic <host.entry> --lang=ts --merge stage/<merge-libs>.wasm
                                                                        → host.out  (caps auto)
shape == "exe":          wasmtk wasic <source> --lang=<lang>            → run target
```

Fan-out parallel; only fan-in is host-build-depends-on-merge-libs → maps to `deno task`
`dependencies` / npm script chaining.

### Host wiring it generates

```ts
// generated: dist/wasm/_components.ts  — one block per `instance`
import { loadModule as loadGeo }     from "./geo.bindings.ts";
import { loadModule as loadPhysics } from "./physics.bindings.ts";
export const geo     = await loadGeo(new URL("./geo.wasm", import.meta.url));
export const physics = await loadPhysics(new URL("./physics.wasm", import.meta.url));
```

Host imports `{ geo, physics }` and calls `geo.distance(...)`. Merge libs + capabilities are
already inside `host.out`, so they're not in this barrel.

## Open decisions to make when circling back

1. **Keep `merge` at all in the polyglot story, or make the host a pure `instance` orchestrator?**
   Dropping merge collapses the matrix to one uniform rule (everything non-host = `lib` +
   `instance` + WIT) — simpler, isolated memories, host-mediated calls, slightly slower; no
   allocator-unification subtlety. Merge buys shared memory / tight coupling for TS+caps only.
   **Tentative recommendation:** host = instance-orchestrator; reserve `merge` strictly for the
   TS+capability fast path; treat the validity matrix as the contract.
2. **`wasmtk.json` standalone vs a `[wasmtk]` key in `deno.json`/`pixi.toml`.** Standalone =
   runtime-agnostic + portable; pixi key = matches the toolchain-provisioning story. Either way,
   pixi (or manual installs) is unavoidable for the non-TS toolchains.
3. **The TS-default question** (refinement to tentative decision #2 above) — required-for-all
   (churn across 287 tests + pipelines) vs accepted-everywhere/defaults-ts/non-TS-errors-without-flag.
4. **Confirm the gate:** any non-TS `instance` is downstream of ABI forward-alignment + that
   language's WIT/bindgen. Ship/exercise the schema **all-TS now**; light up Go/Rust/Zig instance
   rows as each producer's contract lands.

## Related memory

- [polyglot-producers.md](polyglot-producers.md) — producer tracks, ABI forward-alignment decision,
  Go v1 shipped.
- [vision.md](vision.md) — full polyglot ecosystem + `[wasmtk.components]` pixi idea + universalWasmLoader.
- [architecture.md](architecture.md) — wasic/modc/bindgen/hybrid, wasmmerge, Canonical ABI partial-alignment note.
- [stdlib-bundling-brief.md](stdlib-bundling-brief.md) — capabilities + virtual `wasmtk:<cap>` tree-shake.
