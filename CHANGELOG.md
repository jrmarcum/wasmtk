# Changelog

All notable, user-facing changes to `wasmtk`. Versions follow the `deno.json` version and the
published [`@jrmarcum/wasmtk`](https://jsr.io/@jrmarcum/wasmtk) JSR package.

## 1.11.12 — Intersection types: base-typed parameters are checked (2026-07-30)

Passing an intersection value to a function that takes one of its constituent interfaces either
works or now tells you why it cannot. Previously one such call quietly computed with the wrong
fields — no error, no trap, just wrong numbers.

### Fixed

- **A base-typed parameter could read the wrong fields.** Structs are passed by pointer and the
  callee reads fields at the offsets of its *own* parameter type, while an intersection lays its
  constituents out in **declaration order**. So the base interface has to come first:

  ```ts
  type Sprite = Renderable & Transform;               // ← Transform declared SECOND

  function getScaleArea(t: Transform): f64 {
    return t.scaleX * t.scaleY;
  }

  const hero: Sprite = { scaleX: 2.0, scaleY: 3.0, alpha: 0.8 };
  console.log(getScaleArea(hero));                    // printed 1.6, not 6
  ```

  `getScaleArea` read bytes 0 and 8 — `alpha` and `scaleX` — and multiplied them. Every offset was
  a valid slot, so the module compiled and ran happily with a wrong answer.

  Every call is now checked: the parameter's struct layout must be a byte-exact **prefix** of the
  argument's (same field name, offset, type and size). When it is not, compilation stops with a
  message naming the variable, both types, the offending field, both byte offsets, and the two ways
  out — declare the base constituent first (`type Sprite = Transform & Renderable`), or type the
  parameter with the intersection itself. Writing the constituents in the order the code consumes
  them, which is the common case, is unaffected.

## 1.11.11 — Discriminated unions: shared variant fields (2026-07-30)

A discriminated union whose variants share a field name now compiles correctly. Previously the
shared field silently took the **first** variant's type — the kind of failure that either corrupts a
value or refuses to run, with nothing pointing at the cause.

### Fixed

- **A field declared in more than one variant kept only the first variant's type.**

  ```ts
  type ValueContainer =
    | { type: "intVal"; val: i32 }
    | { type: "floatVal"; val: f64 };

  const v: ValueContainer = { type: "floatVal", val: 25.5 }; // ← stored as 25
  ```

  `val` was laid out as a 4-byte `i32`, so `25.5` was truncated to `25` on the way into memory, and
  reading it back inside a function returning `f64` emitted an `i32` load — producing a module that
  failed to instantiate with `type error in return[0] (expected f64, got i32)`.

  Shared fields are now resolved across **all** variants before layout and widened to the type that
  holds every one of them (`i32`/`f32` → `f64`, `i32` → `i64`). This matches what TypeScript already
  means, since `i32` and `f64` are both `number` aliases — the union's field is simply `number`.
  Fields declared after a widened one keep their alignment, and the result does not depend on which
  variant is declared first.

- **A genuinely incompatible shared field now reports itself.** When two variants declare the same
  field at types that no single slot can hold (e.g. `string` vs `f64`), compilation stops with a
  message naming the union, the field and both types. It previously surfaced as the unrelated
  `Offset is outside the bounds of the DataView`.

- **Unions written as inline `{ … } | { … }` blocks now support nested struct fields**, matching
  unions written as `type X = A | B` over named interfaces. The two forms were handled by separate
  code paths and only the latter propagated nested struct types.

## 1.11.10 — Namespace members (2026-07-30)

Namespaces now work from the inside and with every member type. Both fixes are things that
previously required awkward workarounds — hoisting constants out of the namespace, or qualifying
every internal reference.

### Fixed

- **Using a `namespace` member from inside the same namespace.** A namespace function referring to
  one of its own members by bare name failed to compile with *unsupported expression*:

  ```ts
  namespace Physics {
    export const GRAVITY: i32 = 9;
    export function force(mass: i32): i32 {
      return mass * GRAVITY; // ← failed; only Physics.GRAVITY from outside worked
    }
  }
  ```

  Bare references to sibling **constants** and sibling **functions** now both resolve. A member
  name appearing in a string literal, or as an object field (`obj.GRAVITY`), is correctly left
  alone.

- **`string`-typed namespace members.** `export const NAME: string = "cfg"` printed `0` instead of
  its text, and a namespace function returning a `string` failed to compile. Namespace members of
  every type — `string`, `i32`, `f64` — now work in all positions: read directly, assigned,
  concatenated, compared, and returned from a namespace function.

### Testing

- 5 new tests (3 stress + 2 regression). Suite **395 → 400/400**; `wast_tests` 41 files /
  12444 assertions / 0 failed; every other suite green.

## 1.11.9 — Operator-precedence fix (2026-07-29)

**Upgrade promptly.** This release fixes a long-standing arithmetic bug that produced **silently
wrong numbers** — no error, no warning, just the wrong answer. If your code divides or takes a
remainder after a multiply, your results may have been incorrect.

### Fixed — wrong arithmetic results

- **`a * b / c` and `a * b % c` computed the wrong value.** `*`, `/` and `%` have equal precedence
  and group left-to-right, but were being grouped right-to-left — so `a * b / c` was computed as
  `a * (b / c)`. With integer division the result was badly wrong:

  ```ts
  const a: i32 = 180;
  a * 5 / 9    // was 0    (computed as 180 * (5/9)) — should be 100
  a * 5 % 9    // was 900  (computed as 180 * (5%9)) — should be 0
  ```

  Only `*` to the **left** of `/` or `%` was affected; `a / b * c`, `a / b / c` and `a % b * c`
  were always correct. The bug applied both in ordinary code and in `console.log` arguments. A
  typical victim is any unit conversion, e.g. `(f - 32) * 5 / 9`.

### Fixed — failed to compile

- **String enums are now usable as values.** A **pure** string enum (all members strings) could
  previously only be printed. Assigning one (`const lvl: LogLevel = LogLevel.Error`) or comparing
  (`lvl === LogLevel.Error`) failed to compile. Both work now, and printing a string-enum
  **variable** or function parameter shows its text (`ERROR`) instead of an internal number.
- **`console.log` arithmetic starting with a number or `(`.** `console.log("x:", 1 + n)` and
  `console.log("x:", (n + 0) * 5)` failed to instantiate for integer variables, while the
  equivalent `n + 1` worked. `1.5 + n` still means floating-point.

### Testing

- 4 new tests (3 stress + 1 regression). Suite **391 → 395/395**; `wast_tests` 41 files /
  12444 assertions / 0 failed; every other suite green.

## 1.11.8 — Stress-test bug-fix release (2026-07-28)

Ten compiler bugs found by hand-written stress tests across Phases 22/24/25/26/27/28 and fixed.
Most were **silently wrong output** rather than errors — code compiled and ran, but printed the
wrong value — so they are worth reading if you hit odd results on any of these constructs.

### Fixed — silently wrong output

- **`console.log` string concatenation printed `0` when a literal contained `]` or `)`.**
  `console.log("[" + name + "]")` or `console.log(s + ")")` printed `0` instead of the string. A
  closing bracket inside a string literal confused the expression scanner and hid the `+`. Literals
  with `{`/`}`, or an opening bracket alone, were unaffected — which made it look arbitrary.
- **String methods used inline printed `0`.** `trim`, `trimStart`/`trimEnd`, `charAt`, `repeat`,
  `replace`, `replaceAll` worked when assigned to a variable first but produced `0` when used
  directly as a `console.log` argument, comparison operand, or call argument. String **literal**
  receivers failed the same way for `slice`, `.at` and case conversion (`"hello".slice(1,3)` → `0`).
- **Nested `for...of` iterated only the first row.** Both loops shared one cursor, so the outer loop
  ran exactly one iteration — a 3×2 matrix summed to `3` instead of `21`.
- **`??` inside `console.log` arguments** returned the fallback instead of the value, including for
  a non-null `0` (`0 ?? 999` gave `999`).

### Fixed — failed to compile

- **Multi-file struct imports.** `import { Vec2 } from "./vec.ts"` then using `Vec2` failed with
  *unsupported expression* on every field access. Struct types were matched by a PascalCase naming
  rule, but the bundler prefixes imported names with the module's lower-case filename. Types are now
  recognized by the type registry, so any valid name works — including `interface point`.
- **`arr.join()` as a value.** `const s: string = nums.join("-")` failed to compile; `join` worked
  only inside `console.log`. It now produces a real string, usable in concatenation and comparisons.
- **`T | null` functions returning a tuple or struct literal**, plus an *undefined global* error when
  a nullable return was consumed via inference rather than an explicit annotation.
- **`as` casts of `**` and `Math.*` expressions** — `(base ** 3) as f64` and the common
  `Math.floor(x) as i32` idiom both emitted invalid code.

### Added

- **Module-level nullable globals.** `let g: T | null = null` at module scope now compiles, so
  `g ??= 77` works from inside any function. Previously this aborted as *unsupported statement*;
  only function-local nullables were supported.

### Testing

- 16 new tests (14 stress + 2 regression). Suite **375 → 391/391**; `bundle_tests` is green for the
  first time (4/4); `wast_tests` 41 files / 12444 assertions / 0 failed.

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
