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

##### Arrays

| Feature | Notes |
| --- | --- |
| Numeric arrays | `i32[]`, `f64[]` — statically allocated in linear memory |
| Element access | `arr[i]`, `arr[i] = v` |
| Length | `arr.length` |
| Array parameters | Passed as i32 pointer to the array's memory region |

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

#### Limitations (Planned for Future Phases)

| Feature | Status |
| --- | --- |
| Classes / OOP | Phase 9 — desugar to struct + prefixed methods |
| Dynamic memory / heap | Phase 10 — bump allocator for push/pop, dynamic strings |
| String operations (concat, slice, indexOf) | Phase 11 |
| Array methods (push, pop, map, filter) | Phase 12 |
| Rest parameters / spread | Phase 13 |
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

Compiles a TypeScript file using **AssemblyScript** to produce a **WASM library module** — not a runnable WASI program. The output contains only your exported functions, callable from a JavaScript/TypeScript host environment.

```bash
wasmtk modc mylib.ts
wasmtk mod mylib.wasm myFunction 42   # call an exported function directly
```

**What it produces:** A `.wasm` library (no `_start`, no WASI imports). Exports are pure functions callable from any WASM host (browser, Node.js, Deno, another WASM module).

**Best suited for:**

- Reusable numeric or computational libraries consumed by a JS/TS host
- Browser-side WASM where you call specific functions from JavaScript
- Interop scenarios where WASM functions are invoked by name from outside
- Replacing performance-critical JS functions with fast WASM equivalents

**Key distinction from `wasic` and `javyc`:**

- `modc` output is **not a standalone program** — it has no entry point and cannot be run as a WASI process
- The module is **imported and called** by a host environment rather than executed independently
- Uses AssemblyScript's type system, which is stricter than standard TypeScript

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
