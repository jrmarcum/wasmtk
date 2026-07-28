# Changelog

All notable, user-facing changes to `wasmtk`. Versions follow the `deno.json` version and the
published [`@jrmarcum/wasmtk`](https://jsr.io/@jrmarcum/wasmtk) JSR package.

## 1.11.7 — Unified producer verbs & Go browser removal (2026-07-28)

### Producers (Go / Zig / Rust) — unified verbs

- **The same verbs work for every producer**, matching the Rust model: `init` scaffolds a **WASI
  program**, `initmod` a **wasm library**, `build` compiles a program to a standalone `.wasm`, `modc`
  a library, and `run` builds + runs.
- **`--lang` is now optional for `run` / `build` / `modc`** — the language is auto-detected from the
  target (a `.go` / `.zig` / `.rs` file, or a directory with `go.mod` / `Cargo.toml`). `init` /
  `initmod` still take `--lang` (there's nothing to detect from).
- **Rust dependency/cache verbs** (`add` / `remove` / `list` / `fmt` / `clean`) no longer require
  `--lang=rust` — they're implicitly Rust.
- **`wasmtk run <dir>`** with no project inside now prints a clear "no Go/Rust project found" error
  instead of a cryptic wasm-instantiate failure.

### Removed

- **Go browser scaffold** (`--go-target=wasm`, the `syscall/js` + `wasm_exec.js` build). wasmtk
  produces WASI modules only — load one in the browser with the universal wasm loader. The
  mergeable-leaf target `--go-target=wasm-unknown` is unchanged.

### Changed — `dync`

- **`wasmtk dync` no longer writes an empty `.wit`** (a fully-dynamic module has no exports).
- Merge notices print as informational (`ℹ️`) rather than warnings (`⚠️`).

### Docs

- README reorganized (Compiler Options / Utility Options / Producers & Backends sections; per-compiler
  Limitations tables) and the roadmap collapsed into a single `Complete | Phase | Feature | Highlights`
  status table. Note: Go/Zig/Rust producers do **not** auto-emit a `.wit` — only the TypeScript path
  (`wasic` / `modc`) does; a Go `bindgen` flow uses a hand-written `.wit`.

## 1.11.6 — Portable dynamic runtime (2026-07-27)

### Changed — `dync`

- **`wasmtk dync` output is now pure-WASI** — it imports only `wasi_snapshot_preview1`, so it runs
  unchanged on any standalone WASI runtime (wasmtime, wasmer, wazero, WAMR), not just wasmtk's own
  `run`.
- **`wasmtk wasic` on a dynamic program now guides you** — it points you to `wasmtk dync` for a
  genuinely dynamic feature, or tells you to fix a real error (e.g. an undefined name) first.

_(Versions 1.9.0–1.11.5 are not itemized here — see the [JSR release history](https://jsr.io/@jrmarcum/wasmtk/versions) and `cmem/roadmap.md`.)_

## 1.8.0 — Async / Promises (2026-06-15)

The headline of this release is a **full v1 `async`/Promise surface for the `wasic` compiler** —
TypeScript async code now compiles directly to a standalone WASI module, with no embedded JavaScript
runtime.

### Added — Async / Promises (`wasic`)

- **`async` / `await`** — `async function f(): Promise<T> { … }` compiles to a real WASM function;
  `await` drains the microtask queue and takes the settled value. Works for `i32` / `f64` results and
  `Promise<void>`.
- **`Promise.resolve(x)` / `Promise.reject(reason)`** — settled fulfilled / rejected promises. A
  rejected `await` re-throws the reason, so it integrates with `try` / `catch` (the Phase-15 exception
  machinery); an `async` body that throws is caught at the `await` site.
- **`.then` / `.catch` / `.finally`** — reaction callbacks run as **microtasks** (correct ordering vs.
  synchronous code, FIFO across reactions, chainable). Callbacks may be **named functions or capturing
  closures**. `.then(onFulfilled, onRejected)` two-arg form supported.
- **`Promise.all([…])` / `Promise.allSettled([…])`** — over an array literal of `i32`/`f64`-valued
  promises. `all` fulfills with a `T[]` (or rejects with the first reason); `allSettled` never rejects
  and yields `{ status, value | reason }` records.
- **Runtime model:** a small **inline microtask runtime** (emitted only when async is used; tree-shaken
  otherwise) under an **eager-execution** model — async bodies run to completion and the queue is
  drained at each `await` and at the end of `_start`. Ordering for sequential / `.then`-chained code
  matches V8.

### Changed — `hybrid`

- `wasmtk hybrid` (and `hybrid --auto`) now **routes `async` functions** that return `Promise<T>` into
  the WASM core, instead of skipping them. Each is wrapped in a synchronous unwrapping wrapper so the
  TypeScript host receives a real value through the generated bindings. (An `async` function whose
  awaited graph reaches a host call still belongs in the runner.)

### v1 limitations

- **Intra-module only** — there is no event loop in WASI Preview 1, so there are no real async sources
  (timers, host I/O); awaiting a promise that can never settle traps with a diagnostic.
- Interleaving order across *concurrently*-pending async functions is not preserved (eager bodies).
- `Promise.all` / `allSettled` take an **array literal** of `i32`/`f64`-valued promises.
- `Promise.race` / `Promise.any` are not in v1.

### Internal

- Full `tests/wasm_wasi` suite at **317/317** (8 new async tests `54_*`–`61_*`), bindgen 104/104,
  jstyper 73/73.
- Removed a dead local in the `Promise.allSettled` codegen helper (lint cleanup).

## 1.7.0 (2026-06-15)

- `Number.parseInt` / `parseFloat` (and bare forms); declaration-order-independent multi-level
  interface inheritance.
- Canonical ABI **return-side forward-alignment** — string-returning exports return an i32 pointer to a
  callee-allocated `[ptr, len]` pair plus a `cabi_post_<name>` release export; `bindgen` updated to
  match. Suite 309/309. JSR package score 100% (provenance + docs).

Earlier history is summarized in the README "Completed Phases" table and `cmem/roadmap.md`.
