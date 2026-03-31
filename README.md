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

##### Generics

`wasic` monomorphizes generic functions and structs at compile time — zero runtime overhead, no boxing, no type-erasure penalty.

| Feature | Syntax / Notes |
| --- | --- |
| Generic functions | `function identity<T>(x: T): T` — one concrete copy per distinct type used |
| Multi-param generics | `function minVal<T>(a: T, b: T): T` — all params bound to the same type |
| Explicit type arguments | `identity<i32>(42)` → emits `identity_i32`; `identity<f64>(3.14)` → `identity_f64` |
| Literal type inference | `identity(42)` → infers `i32`; `identity(3.14)` → `f64`; `identity(true)` → `bool` |
| Generic structs | `interface Box<T> { value: T; count: i32; }` |
| Generic struct usage | `const b: Box<i32> = { value: 99, count: 3 }` → concrete struct `Box_i32` |
| Generic function + struct param | `function getBoxValue<T>(b: Box<T>): T` — struct ref in signature is rewritten |
| Naming convention | Concrete names are `name_T1_T2` (e.g., `identity_i32`, `Box_f64`, `minVal_i32`) |
| `type` alias generics | `type Pair<A, B> = { first: A; second: B; }` — same as `interface` |

##### Exception Handling

| Feature | Notes |
| --- | --- |
| `throw new Error("msg")` | Allocates message string in data section; emits `(throw $__exn_tag ptr len)` |
| `throw "literal"` | Same — string literal as throw payload |
| `throw someStringVar` | Passes existing string variable's `(ptr, len)` as payload |
| `try { } catch (e) { }` | WAT `(try (do ...) (catch $__exn_tag ...))` — catches all `$__exn_tag` exceptions |
| `try { } finally { }` | `finally` body inlined in the `do` block (success path) and in a `catch_all` + `rethrow` (exception path) |
| `try { } catch (e) { } finally { }` | Combined form — `finally` runs on success, catch success, and unhandled exception paths |
| `e` in catch | Bound as a string variable (`$e_ptr` + `$e_len` i32 locals) — the throw message |
| `e.message` | Alias for `e` — resolves to the same string ptr/len pair |

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
| Default imports | `import foo from "./lib.ts"` — `foo` rewrites to the module's default export |
| Namespace imports | `import * as ns from "./lib.ts"` — `ns.foo` rewrites to `lib_foo` |
| Type-only imports | `import type { Foo } from "./lib.ts"` — stripped |
| Side-effect imports | `import "./lib.ts"` |
| Named re-exports | `export { foo } from "./lib.ts"` — bubbles `lib_foo` into this module's export map |
| Wildcard re-exports | `export * from "./lib.ts"` — all of lib's exports become this module's exports |
| Default exports | `export default function foo()` — exposed as `"default"` in the export map |
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

#### Current Limitations

| Feature | Status |
| --- | --- |
| Class inheritance (`extends`) | Deferred — virtual dispatch via vtable requires heap |

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

### `wasmtk modc` — WASM Library Module

Compiles a TypeScript file to a **WASM library module** — not a runnable WASI program. The output contains only your exported functions, callable from any WASM host environment. Implemented in `modc.ts` as a standalone module, parallel to `wasic.ts` and `javyc.ts`.

```bash
wasmtk modc mylib.ts
wasmtk mod mylib.wasm myFunction 42   # call an exported function directly
```

**What it produces:** A `.wasm` library (no `_start`, no WASI imports, no embedded runtime). Exports are pure functions callable from any WASM host (browser, Node.js, Deno, another WASM module).

**Compilation pipeline:**

```text
.ts source
  → tsbundler   (import resolution, module-prefix name mangling)
  → WasicTranspiler in library mode   (TypeScript → WAT, no _start, no proc_exit)
  → wabt parseWat   (WAT → raw WASM binary)
  → Binaryen -Oz   (dead-code elimination, size optimisation)
  → .wasm library
```

**Input requirements:**

The source file must contain at least one `export function` declaration. Top-level runner code (main(), IIFE, console.log, top-level statements) is parsed but silently dropped — only exported functions are callable from the host. Non-exported internal functions are included in the WAT but eliminated by Binaryen -Oz if unreachable.

```typescript
// ✅ Valid modc source — supports the full wasic TypeScript subset
export function add(a: f64, b: f64): f64 {
  return a + b;
}

export function multiply(a: f64, b: f64): f64 {
  return a * b;
}
```

**Supported types:** The full wasic subset — `i32`, `i64`, `f32`, `f64`, `number` (→ `f64`), `boolean`, `string`, arrays, structs, generics, classes, exceptions, and all completed phases. No AssemblyScript toolchain required.

**Best suited for:**

- Reusable numeric or computational libraries consumed by a JS/TS host
- Browser-side WASM where you call specific functions from JavaScript
- Interop scenarios where WASM functions are invoked by name from outside
- Replacing performance-critical JS functions with fast WASM equivalents

**Key distinction from `wasic` and `javyc`:**

- `modc` output is **not a standalone program** — it has no entry point and cannot be run as a WASI process
- The module is **imported and called** by a host environment rather than executed independently
- Supports the same TypeScript subset as `wasic` — no type restrictions beyond the wasic compiler's own limits

---

### `wasmtk wasmbundle` — Multi-WASM Bundler

Merges multiple pre-compiled `.wasm` files into a **single combined `.wasm` library** — no TypeScript source required. Useful for packaging independently compiled modules for distribution as one artifact.

```bash
wasmtk wasmbundle math.wasm utils.wasm --name combined.wasm
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=prefix
```

**What it produces:** A `.wasm` library with all exported functions from every input module, accessible under a unified namespace.

**Best suited for:**

- Distributing multiple WASM modules as a single file
- Combining `modc`-compiled libraries for a consumer who only wants one import
- Packaging platform-specific WASM alongside shared utilities
- Reducing load overhead when a host needs functions from several modules

See [Phase 19 — `wasmbundle` CLI](#phase-19--wasmbundle-cli) for full pipeline details and conflict resolution options.

---

## Programmatic API

Each compiler is a standalone importable module. You can use them directly in Deno without going through the CLI:

```typescript
import { compileWasiTs, compileWasi, compileLibTs } from "@jrmarcum/wasmtk/wasic";
import { compileModule }                            from "@jrmarcum/wasmtk/modc";
import { compileJavy }                              from "@jrmarcum/wasmtk/javyc";
import { bundleImports }                            from "@jrmarcum/wasmtk/tsbundler";
import { runWasmBundle }                            from "@jrmarcum/wasmtk/wasmbundle";
import { mergeWasmWat, extractExportNames }         from "@jrmarcum/wasmtk/wasmmerge";
```

| Export | Module | Description |
| --- | --- | --- |
| `compileWasi(path, outPath?)` | `./wasic` | Compile `.ts` or `.wat` to a WASI standalone `.wasm` |
| `compileWasiTs(path, outPath?)` | `./wasic` | TypeScript-only path — runs bundler + transpiler + optimizer |
| `compileLibTs(path, outPath?)` | `./wasic` | TypeScript → WASM library (no `_start`, no WASI scaffolding) |
| `compileWat(path, outPath?)` | `./wasic` | WAT-only path — wabt parse + Binaryen `-Oz` |
| `compileModule(path, outPath?)` | `./modc` | Compile `.ts` to a WASM library via wasic transpiler |
| `compileJavy(path, outPath?)` | `./javyc` | Compile `.ts` to a WASI module via Javy/QuickJS |
| `bundleImports(entryPath)` | `./tsbundler` | Resolve and merge relative imports into a single source string |
| `runWasmBundle(inputs, out, onConflict?)` | `./wasmbundle` | Bundle multiple `.wasm` files into a single `.wasm` library |
| `mergeWasmWat(wat, prefix, dataReloc, overrides?)` | `./wasmmerge` | Merge one WAT module into a parent with prefix mangling and data relocation |
| `extractExportNames(wat)` | `./wasmmerge` | Return bare export names from a WAT module (for conflict detection) |

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
| Combine multiple `.wasm` files into one library | `wasmbundle` |
| Distribute a set of compiled modules as a single artifact | `wasmbundle` |

---

## wasmtk Toolkit Roadmap

The toolkit is developed incrementally. Core phases build out the `wasic` TypeScript compiler; later phases extend the toolchain with bundling and distribution capabilities.

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
| 14 | Generics (monomorphization) | `function f<T>(x: T): T` — one concrete copy per distinct type; `interface Box<T> { value: T; }` → `Box_i32`, `Box_f64`, etc.; explicit type args (`f<i32>(x)`) and single-T literal inference (`f(42)` → `f_i32`); generic struct refs in function signatures rewritten automatically; source-level `expandGenerics()` pre-pass runs before all other parsing |
| 15 | Exception handling | `throw new Error("msg")` / `throw str` → `(throw $__exn_tag ptr len)`; `try/catch(e)/finally` via WAT exceptions proposal; `(tag $__exn_tag (param i32 i32))` payload carries `(ptr, len)` string pair; `e` / `e.message` in catch bound as string locals; `exceptions: true` in wabt options; `binMod.setFeatures(Features.All)` before Binaryen `-Oz` to preserve exception sections |
| 16 | Module system extras | Default imports (`import foo from "./lib.ts"`); namespace imports (`import * as ns from "./lib.ts"`) with `ns.name` → `lib_name` rewriting; named re-exports (`export { foo } from "./lib.ts"`); wildcard re-exports (`export * from "./lib.ts"`); `export default function`; `exportRenamesCache` to resolve re-export chains across already-visited files; `applyRenames` updated to escape regex metacharacters (enabling dotted-key `ns.foo` rewrites) |
| 17 | wasic library mode | `WasicTranspiler` gains `mode: "wasi" \| "library"` constructor param; library mode skips `_start`, `proc_exit` import, and top-level statement processing; `compileLibTs()` public function mirrors `compileWasiTs()`; `modc.ts` backend replaced — AssemblyScript toolchain (`asc`), temp-file creation, and binary post-processor (`removeEnvAbortImport`) all removed; `compileModule` calls `compileLibTs` directly; supports full wasic TypeScript subset (no type restrictions) |
| 18 | WASM import bundling | `tsbundler.ts` detects `.wasm` specifiers in ESM imports and `wasmImport()` loader calls; new `wasmmerge.ts` module performs WAT-level merge with module-prefix name mangling; `_start`, `proc_exit`, `args_get/sizes_get`, `environ_get/sizes_get` stripped with notice; WASI imports deduplicated; data segments relocated by `mainModule.dataOffset`; static-data pointer `i32.const` values conservatively relocated; `WasicTranspiler` gains `externalFuncs` constructor param so call sites type-check before WAT merge; `iovBase`/`scratchBase` promoted to instance variables for collision-free merge of `fd_write` scratch areas; `bundleImportsEx()` returns `{ source, wasmImports }` alongside backward-compat `bundleImports()` |
| 19 | `wasmbundle` CLI | New `wasmbundle.ts` + `wasmtk wasmbundle` command bundles multiple `.wasm` files into a single combined `.wasm` library; cross-module export conflict detection; interactive per-conflict prompt or `--on-conflict=prefix\|exclude` flag; non-conflicting exports keep bare names; conflicting exports prefixed or excluded; sequential `mergeWasmWat` with tracked `dataOffset`; master WAT assembled with WASI imports (14 common signatures), auto-sized `(memory N)`, and explicit `(export ...)` declarations; `extractExportNames()` added to `wasmmerge.ts`; `exportOverrides` parameter added to `mergeWasmWat` for export name control |

---

#### Phase 18 — WASM Import Bundling

Phase 18 extends the compiler pipeline to merge pre-compiled `.wasm` modules directly into the WAT output — no runtime loader required.

**Detected import forms:**

```typescript
// 1. Direct ESM import
import { add, multiply } from "./math.wasm";

// 2. universal-wasm-loader pattern
import { wasmImport } from "./universal-wasm-loader.js";
const { calculate: runMath, version: wasmVer } = await wasmImport("./math.wasm");
```

Both forms support rename aliases. Call sites in the TypeScript source are rewritten to the canonical prefixed name (`math_add`) before transpilation.

**WAT merge pipeline:**

1. **Detect** — `tsbundler.ts` recognises `.wasm` specifiers; records them in `WasmImportEntry[]`; applies call-site renames in the merged TS source
2. **Pre-register** — wabt disassembles each `.wasm`; `ExternalFuncDef` signatures are injected into `WasicTranspiler` so the transpiler types call expressions correctly before merge
3. **Transpile** — main TS source compiled to WAT normally; merged module has no knowledge of the import at WAT level yet
4. **Disassemble & parse** — `wasmmerge.ts` extracts all top-level WAT forms using a parenthesis-depth scanner
5. **Strip entry-only features** — `_start`, `proc_exit`, `args_get/sizes_get`, `environ_get/sizes_get` dropped with notice
6. **Mangle** — all `$funcname` and `$globalN` references prefixed; `call N` index references rewritten to `call $prefix_name`
7. **Relocate** — data segment base addresses shifted by `mainModule.dataOffset`; `i32.const >= 260` values in function bodies conservatively shifted as static-data pointers
8. **Deduplicate WASI** — `fd_write` and other WASI imports used by the imported module are not re-declared; main module's declarations suffice
9. **Splice** — mangled functions, globals, and data segments inserted before the closing `)` of the main WAT module
10. **Optimise** — Binaryen `-Oz` eliminates any dead code introduced by the merge

**Supported complexity tiers:**

| Case | Status | Notes |
| --- | --- | --- |
| Pure computation (no memory, no imports) | ✅ | Hash functions, math libs, encoders |
| Modules with globals | ✅ | Prefixed like functions; heap-pointer global skipped |
| Modules sharing WASI imports | ✅ | `fd_write` etc. deduplicated |
| Modules with memory / data segments | ✅ | Conservative pointer relocation (values ≥ 260 shifted) |

**Entry-only notice (WASI executables as imports):**

Any `.wasm` — including a `wasic`-compiled WASI program — can be imported as a library. Entry-only features are stripped automatically:

```text
⚠️  Imported "engine.wasm": entry-only features excluded: _start, proc_exit. Module converted to library mode.
```

All other exported functions remain fully accessible. `modc` and `wasic` are a natural matched set: `modc` produces clean library modules; `wasic` programs can consume both.

**`fd_write` scratch area — collision-free merge:**

`iovBase` and `scratchBase` are instance variables on `WasicTranspiler` (not hardcoded constants). Imported modules receive fresh scratch addresses above `mainModule.dataOffset`, so parallel `console.log` call paths in main and imported code never overwrite each other's iov buffers.

---

#### Phase 19 — `wasmbundle` CLI

Phase 19 adds a new `wasmtk wasmbundle` command that merges multiple standalone `.wasm` files into a single combined `.wasm` library for distribution.

**CLI usage:**

```bash
# Bundle two modules — no conflicts
wasmtk wasmbundle math.wasm utils.wasm --name combined.wasm

# Bundle with overlapping export names — interactive prompt
wasmtk wasmbundle math1.wasm math2.wasm

# Non-interactive: auto-prefix all conflicts
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=prefix

# Non-interactive: auto-exclude all conflicts
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=exclude
```

**Conflict resolution:**

When two or more input modules export a function with the same name, `wasmbundle` detects the conflict and resolves it interactively (default) or via `--on-conflict`:

```text
Conflict: "add" exported by: math1.wasm, math2.wasm
  [p]  Prefix each  →  math1_add, math2_add
  [e]  Exclude both
  Choice (p/e):
```

Non-conflicting exports always keep their bare names in the output. Only the conflicting ones are affected.

**Bundle pipeline:**

1. Load each `.wasm` with wabt; disassemble to WAT text
2. Extract export names via `extractExportNames()`; identify conflicts across all modules
3. Resolve conflicts (interactive or `--on-conflict`)
4. Build `exportOverrides` map for each module: bare name, prefixed name, or `null` (exclude)
5. Merge each module's WAT with `mergeWasmWat(..., exportOverrides)`, tracking cumulative `dataOffset`
6. Assemble master WAT with WASI imports, `(memory N)` (auto-sized), all fragments, and `(export ...)` declarations
7. Compile master WAT → binary via wabt
8. Optimize with Binaryen `-Oz`
9. Write output (default: `combined.wasm`)

**`wasmmerge.ts` additions:**

- `extractExportNames(wat)` — returns bare non-entry export names; used for conflict detection
- `exportOverrides?: Map<string, string | null>` parameter on `mergeWasmWat` — controls output export names; `null` = exclude; populates new `exportDecls: string[]` in `WatMergeResult`

**Key distinction from Phase 18 (wasic import bundling):**

Phase 18 merges `.wasm` at the TypeScript compile step — the calling `.ts` file drives the merge and function names are always prefixed. Phase 19 operates on raw `.wasm` inputs with no TypeScript source involved. Non-conflicting exports keep bare names, making the output a clean drop-in library.

---

### Planned Phases

> No phases currently planned. Phase 19 completed the roadmap. Future work tracked separately.
