# Overview

`wasmtk` is a polyglot WebAssembly toolkit for Deno. Active development centers on **`wasic`**,
a direct TypeScript→WASM compiler that emits WAT, assembles it via a pluggable WABT backend,
and optimizes via a pluggable Binaryen backend. **No embedded JavaScript runtime** — everything
maps to static WASM constructs.

## Repo layout

```text
wasmtk/
├── main.ts              # CLI entry point (root, JSR entry)
├── deno.json            # Deno config, tasks, JSR exports, backend selection
├── cmem/                # Portable project memory (this folder)
├── src/                 # All source modules
│   ├── wasic.ts         # TypeScript→WAT transpiler (WasicTranspiler) — the big one
│   ├── console_log.ts   # console.log/error/warn emission + number→string helpers + unescapeString
│   ├── tsbundler.ts     # Multi-file import bundler (.ts and .wasm imports)
│   ├── wasmmerge.ts     # WAT-level merge of pre-compiled .wasm modules (splice/relocate/unify)
│   ├── wasmbundle.ts    # CLI bundler for combining multiple .wasm files
│   ├── modc.ts          # Library-mode compilation (no _start, no WASI)
│   ├── bindgen.ts       # TS host binding generator from .wit (Phase 50)
│   ├── hybrid.ts        # // @wasm-annotated split compiler
│   ├── gowasic.ts       # Go producer (--lang=go): init/modc/run via TinyGo/std; modc→wasm library, run auto-detects Go (2026-06-06, upd. 2026-06-07)
│   ├── zigwasic.ts      # Zig producer (--lang=zig): init/modc/run via `zig`; modc→freestanding lib, run→wasm32-wasi (2026-06-07)
│   ├── rustwasic.ts     # Rust producer (--lang=rust): delegates to rsxtk (init/initmod/modc/build/run/add/remove/list/fmt/clean) (2026-06-07)
│   ├── dync.ts          # Full-dynamic-compile entry: whole TS/JS file → WASI via the own runtime (wasmtk:dynrt); replaced javyc (deleted v1.11.1)
│   ├── jstyper.ts       # .js + .d.ts → typed .ts pre-processor (Phase 39)
│   ├── binaryen.ts      # wrapper over npm vs JSR binaryen default-export shape + shared binaryenOptimize() (-Oz; used by Go/Zig producers)
│   ├── rt.ts            # Runtime I/O shim (all I/O goes through rt.*, never Deno.* directly)
│   ├── utils.ts         # WASM runner / WASI shims / CLI command handlers
│   └── wasm/            # Pre-compiled WASM library assets (e.g. mathlib.wasm, Phase 38)
└── tests/
    ├── wasi_tests.ts          # Full suite runner (optional 2nd arg = basename regex filter)
    ├── bindgen_tests.ts       # bindgen unit + integration tests
    ├── jstyper_tests.ts       # jstyper unit tests
    ├── wasm_wasi/             # All .ts phase tests + Go-by-Example tests (one file per feature)
    └── wasm_wasi_bundle/      # Multi-module merge fixtures (set/map/date/json/regex bundles, etc.)
```

## Key source files

| File | Role |
| --- | --- |
| `src/wasic.ts` | Main TS→WAT transpiler (`WasicTranspiler` class). Most logic + most bugs live here. |
| `src/console_log.ts` | `console.*` emission; `$__f64_to_str`/`$__i32_to_str`/`$__i64_to_str`; `unescapeString`; many parallel arg-emission paths that must be kept in sync with `wasic.ts`. |
| `src/wasmmerge.ts` | The merge engine: prefix-mangling, data relocation, allocator unification, `detectBumpAllocator`. |
| `src/tsbundler.ts` | Resolves/inlines `.ts` imports and detects `.wasm` imports (`import {…} from "./x.wasm"` — **single-line only**). |

## Mental model

- Closed-world, statically-typed TS subset → WAT. `type i32 = number` etc.; numbers are f64 by
  default unless annotated.
- Strings are `(ptr, len)` pairs; dynamic arrays are `[len i32][cap i32][elems]`; TypedArrays
  have an 8-byte header; structs have fixed field offsets.
- A bump allocator (`$__malloc` over `$__heap_ptr`) with **no free**. See architecture.md.
- The "TypeScript as a DLL" goal: compile TS to `.wasm` libraries and load them from a TS host
  the way C uses a DLL. `.wit` is the header; `.bindings.ts` is the import library. See roadmap.md.
