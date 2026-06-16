# Changelog

All notable, user-facing changes to `wasmtk`. Versions follow the `deno.json` version and the
published [`@jrmarcum/wasmtk`](https://jsr.io/@jrmarcum/wasmtk) JSR package.

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
