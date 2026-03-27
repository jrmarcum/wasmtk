# wasmtk

<p align="center">
  <img src="wasmtk_logo.png" alt="wasmtk logo" width="300">
</p>

A polyglot WebAssembly toolkit for Deno. Seamlessly run, inspect, and convert Wasm modules regardless of their source language (Zig, Rust, AssemblyScript, or Javy).

## 🌟 Why wasmtk?

Most runners are either too minimal (breaking on complex Zig/Rust builds) or too heavy. `wasmtk` provides a "just right" developer experience with:

- **Universal Running**: Execute `.ts`, `.js`, `.wasm`, and `.wat` with a single command.
- **Strict WASI Support**: Expanded syscall shims (`fd_pwrite`, `clock_time_get`, etc.) ensure compatibility with Zig 0.11+ and Rust modules.
- **Intelligent Inspection**: `wasmtk info` filters out the noise (CABI glue, memory helpers) to show you only what's callable.
- **JIT WAT Compilation**: Run WebAssembly Text files directly—no manual `wat2wasm` steps required.

## 🚀 Quick Start

### Installation

```bash
deno add jsr:@jrmarcum/wasmtk
```

---

## 🔨 Compiler Options

wasmtk provides three distinct compilation paths. Choosing the right one depends on what your program needs at runtime.

---

### `wasmtk wasic` — Direct TypeScript-to-WASM (WASI Standalone)

Compiles a TypeScript source file directly to a **standalone WASI module** with no embedded JavaScript runtime. The compiler translates TypeScript syntax directly into WebAssembly Text (WAT) and then to a `.wasm` binary via a bundler pre-pass that resolves imports, followed by the WasicTranspiler, wabt, and Binaryen `-Oz` optimization.

```bash
wasmtk wasic myprogram.ts
wasmtk run myprogram.wasm
```

**What it produces:** A self-contained WASI executable. Exports a `_start` function that WASI hosts invoke as the program entry point.

**Best suited for:**

- Numeric computation (i32, i64, f32, f64)
- Performance-critical, zero-overhead code
- Data structures with known, fixed layouts (arrays, structs)
- Multi-file programs composed from local `.ts` modules
- Programs that only need WASI I/O (`console.log`, file I/O)
- Situations where binary size and startup time matter

---

#### Supported TypeScript Features

##### Functions & Variables

| Feature | Syntax |
| --- | --- |
| Typed function declarations | `function add(a: i32, b: i32): i32 { ... }` |
| Default parameters | `function f(x: i32 = 0)` |
| Optional parameters | `function f(x?: i32)` |
| Arrow functions | `const fn = (x: i32): i32 => x * 2` |
| First-class function variables | `const op: (a: i32, b: i32) => i32 = add` |
| Higher-order / callbacks | `function apply(f: (x: i32) => i32, v: i32): i32` |
| Closure capture | Outer-scope variables injected as hidden parameters |
| Variable declarations | `let`, `const`, `var` with optional type annotations |

##### Control Flow

| Feature | Syntax |
| --- | --- |
| Conditionals | `if / else if / else` |
| While loop | `while (cond) { }` |
| Do-while loop | `do { } while (cond)` |
| For loop | `for (let i = 0; i < n; i++)` |
| Switch | `switch (x) { case 1: ... break; default: ... }` |
| Labeled break/continue | `outer: for(...) { inner: for(...) { break outer; } }` |
| Ternary | `cond ? a : b` |

##### Operators

| Category | Operators |
| --- | --- |
| Arithmetic | `+ - * / %` |
| Comparison | `=== !== == != < > <= >=` |
| Logical | `&& \|\| !` |
| Bitwise | `& \| ^ ~ << >> >>>` |
| Compound assignment | `+= -= *= /= %= &= \|= ^= <<= >>= >>>=` |

##### Numeric Types

| Feature | Notes |
| --- | --- |
| Integer types | `i32`, `i64`, `number` (→ f64), `boolean` (→ i32) |
| Float types | `f32`, `f64` |
| BigInt literals | `42n` → i64 |
| Numeric enums | `enum Dir { Up = 0, Down = 1 }` — members fold to i32 constants |

##### Strings

| Feature | Notes |
| --- | --- |
| String literals | Stored in linear memory as ptr+len |
| `.length` | Returns character count as i32 |
| Comparisons | `===`, `!==`, `<`, `>`, `<=`, `>=` — lexicographic |
| Template literals | `` `x=${x} y=${y}` `` — numeric and string interpolation |
| `console.log` | Mixed-type argument lists (numbers, strings, booleans, BigInt, template literals) |
| `console.error` / `console.warn` | Same as `console.log` but writes to stderr (fd=2) |
| `str + str` | Concatenation — heap-allocates a new string; chains left-to-right (e.g. `a + b + c`) |
| `str.slice(start, end)` | Returns a sub-range pointer with clamped bounds (no allocation) |
| `str.indexOf(sub)` | Returns i32 offset of first occurrence, or -1 if not found |
| `str.includes(sub)` | Returns bool — `true` if substring is present |
| `String(n)` | Converts numeric value to a heap-allocated string |
| `n.toString()` | Same as `String(n)` — works on `i32`, `f64`, `i64` variables |

##### Arrays

| Feature | Notes |
| --- | --- |
| Static numeric arrays | `i32[]`, `f64[]` — literal initializer, elements baked into the data section |
| Dynamic numeric arrays | `i32[]`, `f64[]` — heap-allocated when any mutating method, query method, or spread usage (`...arr`) is detected by the pre-scan |
| Element access | `arr[i]`, `arr[i] = v` — works on both static and dynamic arrays |
| Length | `arr.length` — compile-time constant for static; runtime load from 8-byte header for dynamic |
| `push(val)` | Appends a value; grows array automatically if at capacity (cap × 2 realloc) |
| `pop()` | Removes and returns the last element; decrements length |
| `shift()` | Removes and returns the first element; shifts remaining elements left |
| `unshift(val)` | Inserts a value at the front; shifts elements right; grows array automatically if at capacity |
| `indexOf(val)` | Returns i32 index of the first matching element, or -1 if not found |
| `includes(val)` | Returns bool — `true` if the element is present in the array |
| `slice(start, end)` | Returns a new heap-allocated array containing elements from `[start, end)`; bounds clamped |
| `forEach(fn)` | Calls `fn(element)` for each element via `call_indirect` through the funcref table |
| `map(fn)` | Returns a new array of the same length where each element is `fn(element)` |
| `filter(fn)` | Returns a new array containing only elements for which `fn(element)` is truthy |
| `find(fn)` | Returns the first element for which `fn(element)` is truthy, or -1 / NaN if not found |
| `reduce(fn, init)` | Folds the array to a single value: `acc = fn(acc, element)` starting from `init` |
| Array parameters | Passed as i32 pointer to the array's memory region |
| Rest parameters | `function f(...args: i32[])` — receives an i32 pointer to a dynamic array; caller builds temp heap array from literal args |
| Spread call | `f(...arr)` — passes an existing dynamic array pointer directly to a rest-param function |
| Spread array literal | `const merged = [...a, ...b]` — heap-allocates a new array via `$__dynarr_concat_T`; source arrays are automatically promoted to dynamic layout |

##### Structs & Objects

| Feature | Notes |
| --- | --- |
| Struct definitions | `interface Vec2 { x: f64; y: f64; }` or `type` alias |
| Struct literals | `const v: Vec2 = { x: 1.0, y: 2.0 }` — static allocation |
| Field access | `v.x`, `v.y = 3.0` |
| Struct parameters | Passed as i32 pointer |
| Object destructuring | `const { x, y } = vec` → i32.load / f64.load at field offsets |
| Renamed destructuring | `const { x: vx, y: vy } = vec` |

##### Math

| Function | Notes |
| --- | --- |
| `Math.sqrt`, `Math.abs` | Native WASM `f64.sqrt`, `f64.abs` |
| `Math.floor`, `Math.ceil`, `Math.round`, `Math.trunc` | Native WASM float ops |
| `Math.min`, `Math.max` | Native WASM min/max |
| `Math.pow` | Native WASM `f64.pow` (via Binaryen) |
| `Math.sign` | Implemented as WAT comparison sequence |

##### Multi-file Programs

The bundler pre-pass (`tsbundler.ts`) runs before compilation and merges all imported modules into a single flat source. Compiled output is always a single `.wasm` file regardless of how many source files are involved.

| Feature | Notes |
| --- | --- |
| Named imports | `import { foo, bar } from "./lib.ts"` |
| Import aliases | `import { foo as f } from "./lib.ts"` — alias is a compile-time rewrite |
| Type-only imports | `import type { Foo } from "./lib.ts"` — stripped |
| Side-effect imports | `import "./lib.ts"` |
| Chained imports | lib A imports lib B imports lib C — resolved recursively |
| Name mangling | Same-named symbols across modules are prefixed: `lib_foo`, `other_foo` — no collision |
| Deduplication | Circular / duplicate imports are silently resolved (first occurrence wins) |

---

#### Entry Point Patterns

Any of the following makes a function the WASI `_start` entry point:

```typescript
// 1. top-level call
function main() { ... }
main();

// 2. exported _start
export function _start() { ... }

// 3. IIFE
(function main() { ... })();
```

---

#### Memory

| Feature | Notes |
| --- | --- |
| Bump allocator | `$__malloc(size: i32): i32` — advances `$__heap_ptr` and returns the old value |
| Heap start | Initialized immediately after the static data section; at least 1 extra 64 KB page reserved |
| Dynamic array layout | `[length: i32][capacity: i32][elem0][elem1]...` — 8-byte header precedes element data |
| Initial capacity | `max(initialLength × 2, 8)` elements pre-allocated; grows automatically on overflow (`cap × 2` realloc via `$__dynarr_grow_T`) |
| Unused-code elimination | Binaryen `-Oz` strips `$__malloc` and unused array helpers from the binary automatically |

#### Classes

| Feature | Notes |
| --- | --- |
| Class declarations | `class Foo { field: i32; ... }` — fields desugared to fixed struct layout |
| Constructor | `constructor(params) { }` → `Foo_constructor(__self: i32, params)` |
| Instance methods | `method(): retType { }` → `Foo_method(__self: i32)` — `this` maps to `local.get $__self` |
| Static methods | `static method(params): retType { }` → `Foo_method(params)` — no hidden param |
| `this.field` read/write | Load/store at field offset from `__self` pointer |
| `new Foo(args)` | Allocates struct in linear memory (static); calls constructor |
| `instance.method(args)` | Dispatches to `Foo_method(instancePtr, args...)` |
| `Foo.staticMethod(args)` | Dispatches to `Foo_staticMethod(args...)` |
| `instance.field` | Field read/write via instance pointer in classVars |
| Class instance params | Functions accepting `obj: Foo` receive an `i32` struct pointer |

#### Limitations (Planned for Future Phases)

| Feature | Status |
| --- | --- |
| Class inheritance (`extends`) | Deferred — virtual dispatch via vtable requires heap |
| Generics (monomorphization) | Phase 14 |
| Exception handling (try/catch/throw) | Phase 15 |

> **Why the limitations?** `wasic` compiles directly to raw WAT with no runtime. Dynamic allocation, garbage collection, and prototype semantics cannot be expressed without an embedded runtime library. Use `wasmtk javyc` for programs that need them today.

---

### `wasmtk javyc` — TypeScript/JavaScript via Javy/QuickJS

Compiles a TypeScript or JavaScript file to a **WASI module that embeds the QuickJS JavaScript engine**. The full JavaScript runtime is bundled into the output `.wasm`.

```bash
wasmtk javyc myprogram.ts
wasmtk run myprogram.wasm
```

**What it produces:** A WASI executable that runs your TypeScript/JavaScript through an embedded QuickJS interpreter inside WASM.

**Best suited for:**

- Full TypeScript/JavaScript semantics where runtime compatibility matters more than size
- Programs that use `Date`, `JSON`, `Map`, `Set`, `RegExp`, `Promise`, or prototype-based features
- Rapid prototyping where you need the full JS standard library
- Code that cannot be easily expressed in numeric/systems style

**Trade-offs vs `wasic`:**

- Larger binary (the QuickJS engine is bundled in every output module)
- Slower startup (the JS engine must initialize before your code runs)
- No hand-tuned WAT output — you get JS interpreter performance, not native WASM performance

---

### `wasmtk modc` — AssemblyScript Library Module

Compiles a TypeScript file to a **WASM library module** — not a runnable WASI program. The output contains only your exported functions, callable from any WASM host environment. Implemented in `modc.ts` as a standalone module, parallel to `wasic.ts` and `javyc.ts`.

```bash
wasmtk modc mylib.ts
wasmtk mod mylib.wasm myFunction 42   # call an exported function directly
```

**What it produces:** A `.wasm` library (no `_start`, no WASI imports, no embedded runtime). Exports are pure functions callable from any WASM host (browser, Node.js, Deno, another WASM module).

**Compilation pipeline:**

```text
.ts source
  → extract export function declarations  (runner code stripped)
  → remap number → f64                    (AssemblyScript compatibility)
  → AssemblyScript compiler (asc)         (--runtime stub, --optimize)
  → binary post-process                   (strip env/abort + start section)
  → .wasm library
```

**Input requirements:**

The source file must contain at least one `export function` declaration. Only exported functions are passed to the compiler — all other top-level code (main(), IIFE, console.log, import.meta.main blocks) is stripped automatically.

```typescript
// ✅ Valid modc source
export function add(a: f64, b: f64): f64 {
  return a + b;
}

export function multiply(a: f64, b: f64): f64 {
  return a * b;
}
```

**Best suited for:**

- Reusable numeric or computational libraries consumed by a JS/TS host
- Browser-side WASM where you call specific functions from JavaScript
- Interop scenarios where WASM functions are invoked by name from outside
- Replacing performance-critical JS functions with fast WASM equivalents

**Key distinction from `wasic` and `javyc`:**

- `modc` output is **not a standalone program** — it has no entry point and cannot be run as a WASI process
- The module is **imported and called** by a host environment rather than executed independently
- Uses AssemblyScript's stricter type system — `f64` required instead of `number`

#### Planned: wasic library mode

A future backend will replace AssemblyScript with a `wasic` library mode. The `WasicTranspiler` already generates correct WAT for all function bodies; library mode will simply drop the WASI scaffolding (`wasi_snapshot_preview1` imports, `fd_write` helpers, `_start` binding) and emit a pure WASM module directly. This eliminates the temp-file creation and binary-patching steps and produces cleaner output. The `compileModule` public API will remain stable across the backend change.

---

## Programmatic API

Each compiler is a standalone importable module. You can use them directly in Deno without going through the CLI:

```typescript
import { compileWasiTs, compileWasi } from "@jrmarcum/wasmtk/wasic";
import { compileModule }              from "@jrmarcum/wasmtk/modc";
import { compileJavy }                from "@jrmarcum/wasmtk/javyc";
import { bundleImports }              from "@jrmarcum/wasmtk/tsbundler";
```

| Export | Module | Description |
| --- | --- | --- |
| `compileWasi(path, outPath?)` | `./wasic` | Compile `.ts` or `.wat` to a WASI standalone `.wasm` |
| `compileWasiTs(path, outPath?)` | `./wasic` | TypeScript-only path — runs bundler + transpiler + optimizer |
| `compileWat(path, outPath?)` | `./wasic` | WAT-only path — wabt parse + Binaryen `-Oz` |
| `compileModule(path, outPath?)` | `./modc` | Compile `.ts` to a WASM library via AssemblyScript |
| `compileJavy(path, outPath?)` | `./javyc` | Compile `.ts` to a WASI module via Javy/QuickJS |
| `bundleImports(entryPath)` | `./tsbundler` | Resolve and merge relative imports into a single source string |

---

## Choosing the Right Compiler

| Need | Use |
| --- | --- |
| Run a standalone program with WASI I/O | `wasic` or `javyc` |
| Maximum performance, minimal binary size | `wasic` |
| Multi-file TypeScript project with local imports | `wasic` |
| Full JS standard library (Date, JSON, Map, Set) | `javyc` |
| Export functions for use from JavaScript/browser | `modc` |
| Numeric/systems code, tight loops, DSP, crypto | `wasic` |
| Existing JS/TS codebase with complex runtime needs | `javyc` |
| WASM library for Deno/Node/browser consumption | `modc` |

---

## `wasic` Compiler Roadmap

The `wasic` direct compiler is developed incrementally. Each phase adds a self-contained TypeScript feature that maps cleanly to WebAssembly primitives.

### Completed Phases

| Phase | Feature | Highlights |
| --- | --- | --- |
| Core | Functions, variables, control flow | `function`, `let`/`const`/`var`, `if`/`else`, `while`, `do-while`, `for` |
| Core | Operators | Arithmetic, comparison, logical, bitwise, ternary, compound assignment |
| Core | Switch / labeled break / continue | `switch/case`, `outer: for(...) { break outer; }` |
| Core | Numeric types | `i32`, `i64`, `f32`, `f64`, `boolean`, BigInt literals (`42n`), numeric enums |
| Core | Strings | Literals, `.length`, lexicographic comparisons, template literals |
| Core | Console output | `console.log/error/warn` — mixed-type args, numbers, strings, BigInt, templates |
| 5b | Default parameters | `function f(x: i32 = 0)` |
| 5c | Optional parameters | `function f(x?: i32)` |
| 5e | First-class functions | funcref table, `call_indirect`, named arrow variables, callbacks, closure capture, IIFE entry pattern |
| 6a | Numeric arrays | `i32[]`, `f64[]` — static allocation, element read/write, `.length`, array params |
| 6b | Structs / objects | `interface` and `type` as fixed-layout structs, field read/write, struct params |
| 6c | Object destructuring | `const { x, y } = vec` → `i32.load` / `f64.load` at field offsets; renamed destructuring |
| 7a | Math intrinsics | `Math.sqrt/abs/pow/floor/ceil/round/min/max/sign/trunc` → native WASM ops |
| 7b | Stderr output | `console.error` / `console.warn` → WASI fd=2 |
| 8 | Import bundler (`tsbundler.ts`) | Relative import resolution, module-prefix name mangling, alias (`as`) rewriting, chained imports, deduplication |
| 9 | Classes | `class` declarations desugared to struct layout + `ClassName_method` prefixed functions; `this` → hidden `__self: i32` param; `new ClassName()` → static alloc + constructor call; instance/static method dispatch; dot-call expressions in `console.log` args |
| 10a | Bump allocator | `$__heap_ptr` mutable global initialized to end of static data; `$__malloc(size)` advances and returns old ptr; 1 extra memory page reserved; Binaryen -Oz strips it when unused |
| 10b | Dynamic arrays | `push` / `pop` / `shift` / `unshift` on `i32[]` and `f64[]`; heap layout `[length i32][capacity i32][elem...]`; auto-detected by pre-scan; per-type WAT helpers emitted on demand; capacity = `max(n × 2, 8)` |
| 10c | Dynamic array growth | `push` / `unshift` grow on overflow: `$__dynarr_grow_T` mallocates new block (`cap × 2`), copies elements, returns new ptr; helpers return new array ptr so callers `local.set` their pointer; old block becomes dead memory (bump allocator has no free) |
| 11 | String operations | `str + str` concat (chained, heap-allocated); `str.slice(start, end)` (sub-range, no alloc); `str.indexOf(sub)` → i32; `str.includes(sub)` → bool; `String(n)` / `n.toString()` (number-to-string via heap); gather-buffer mode in `console.log` extended to handle string and bool variables |
| 12 | Array methods | `arr.indexOf(val)` → i32; `arr.includes(val)` → bool; `arr.slice(start, end)` → new array; `arr.forEach(fn)`; `arr.map(fn)` → new array; `arr.filter(fn)` → new array; `arr.find(fn)` → element; `arr.reduce(fn, init)` → value; dynamic arrays only; `const r: T[] = arr.map(fn)` pattern supported; `findDynamicArrays` extended to auto-detect arrays used with Phase 12 methods |
| 13 | Rest parameters / spread | `function f(...args: i32[])` — rest param receives heap array pointer; literal call sites build temp array via `$__malloc`; `f(...arr)` passes existing dynamic array pointer directly; `[...a, ...b]` concat via `$__dynarr_concat_T`; spread-source arrays auto-promoted to dynamic layout by `findDynamicArrays` |

### Planned Phases

| Phase | Feature | Description |
| --- | --- | --- |
| 14 | Generics | Monomorphization: `function id<T>(x: T): T` expanded per concrete type at compile time |
| 15 | Exception handling | `try`/`catch`/`throw` via WAT exceptions proposal (`exnref`, `throw`, `catch`) |
| 16 | Module system extras | Re-exports (`export { x } from "./lib.ts"`), default exports, namespace imports (`import * as m`) |
| 17 | wasic library mode | `modc` backend: drop WASI scaffolding, emit pure WASM library — replaces AssemblyScript for `wasmtk modc` |
| 18 | WASM import bundling | Import pre-compiled `.wasm` modules directly: `import { add } from "./math.wasm"` — WAT-level merge with module-prefix mangling |

#### Phase 18 — WASM Import Bundling

Phase 18 extends `tsbundler.ts` to handle `.wasm` specifiers alongside `.ts` ones. When a `.wasm` import is encountered:

1. **Disassemble** — wabt converts the `.wasm` to WAT (wabt is already in the pipeline)
2. **Validate** — reject any module that exports a `_start` function with a clear error (see below)
3. **Extract** — parse exported function signatures and bodies from the WAT
4. **Mangle** — apply the same module-prefix naming used for `.ts` imports: `math.wasm` exports `add` → `math_add`
5. **Register** — inject the signatures into `WasicTranspiler`'s function table so call sites type-check correctly
6. **Merge** — append the prefixed function bodies into the final WAT output before the wabt compile step

**Supported cases (incrementally):**

| Case | Complexity | Notes |
| --- | --- | --- |
| Pure computation (no memory, no imports) | Low | Hash functions, math libs, encoders — clean merge |
| Modules with globals | Medium | Globals get prefix mangling like functions |
| Modules sharing WASI imports | Medium | `fd_write` etc. deduplicated against main module's imports |
| Modules with memory / data segments | High | Requires data-offset relocation relative to `DATA_BASE` |

**`_start` exclusion:**

Any `.wasm` module — including WASI executables — can be imported. However, `_start` is **always excluded** from the merge. A compiled program can only have one `_start` entry point; merging a second would produce a WAT compile error or silently override the program's entry. `tsbundler.ts` detects the presence of `_start` and drops it, emitting an informational notice so the user knows what happened:

```text
⚠️  Imported "./myprogram.wasm": _start excluded from merge.
    WASI entry points cannot be imported as callable functions.
    All other exports from this module are available normally.
```

This means WASI executables compiled with `wasmtk wasic` can still be imported as utility libraries — their exported helper functions are fully accessible; only the entry point is withheld. This pairing makes `wasmtk modc` and `wasmtk wasic` a natural matched set: `modc` produces clean importable libraries, `wasic` can consume both `modc` output and other `wasic` modules equally.
