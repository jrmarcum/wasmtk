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

## 📁 Project Structure

```text
wasmtk/
├── main.ts              # CLI entry point
├── deno.json            # Deno configuration, tasks, and JSR exports
├── src/                 # Source modules
│   ├── wasic.ts         # TypeScript-to-WAT transpiler (WasicTranspiler)
│   ├── console_log.ts   # console.log/error/warn WAT emission + number-to-string helpers
│   ├── tsbundler.ts     # Multi-file import bundler (.ts and .wasm imports)
│   ├── wasmmerge.ts     # WAT-level merge of pre-compiled .wasm modules
│   ├── wasmbundle.ts    # CLI bundler for combining multiple .wasm files
│   ├── modc.ts          # Library-mode compilation (no _start, no WASI)
│   ├── javyc.ts         # TypeScript via Javy/QuickJS embedded runtime
│   ├── utils.ts         # WASM runner, WASI shims, and CLI command handlers
│   ├── runner.ts        # Standalone WASM/WAT runner utilities
│   ├── args.ts          # CLI argument parsing helpers
│   └── wasm/            # Pre-compiled WASM library assets (Phase 38+)
├── tests/               # Test suite
│   ├── run_wasi_tests.ts
│   ├── run_bundle_tests.ts
│   ├── run_mod_tests.ts
│   ├── run_wasi_javy_tests.ts
│   ├── wasm_wasi/       # wasic test programs (one per feature/phase)
│   ├── wasm_wasi_bundle/
│   ├── wasm_wasi_javy/
│   └── wasm_mod/
└── README.md

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
| Void arrows | `const noOp = (): void => { }` — no return value |
| First-class function variables | `const op: (a: i32, b: i32) => i32 = add` |
| Higher-order / callbacks | `function apply(f: (x: i32) => i32, v: i32): i32` |
| Closure capture | Outer-scope variables injected as hidden parameters |
| Nested closures | Multi-level capture: inner arrow captures from outer arrow's scope |
| Heap-allocated closures | Factory functions `function f(x) { return (y) => x*y; }` — inner arrow lifted to `f__inner`; factory mallocs `{table_idx, captures}` struct; `$f__trampoline` dispatches via `call_indirect` |
| Named function type aliases | `type Scaler = (val: i32) => i32` — inline capturing arrows heap-allocated as `__anon_N__factory`; closure pointers dispatchable via named-type trampolines |
| Shared mutable captures | `function createCounter() { let count = 0; return { inc: () => { count++; return count; }, dec: () => ... } }` — captured variables shared across multiple closures AND mutated are heap-boxed: a 4-byte cell is allocated per shared variable; each closure receives the cell pointer; reads emit `i32.load`, mutations emit `i32.store` |
| Variable declarations | `let`, `const`, `var` with optional type annotations |

##### Control Flow

| Feature | Syntax |
| --- | --- |
| Conditionals | `if / else if / else` |
| While loop | `while (cond) { }` |
| Do-while loop | `do { } while (cond)` |
| For loop | `for (let i = 0; i < n; i++)` |
| For-of loop | `for (const x of arr)` — iterates `i32[]` / `f64[]` static and dynamic arrays; supports `break` / `continue` |
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
| Logical assignment | `??= \|\|= &&=` — assign only when null/falsy/truthy (Phase 25) |
| Nullish coalescing | `??` — returns rhs when lhs is `null`/`undefined`, else lhs (Phase 25) |

##### Numeric Types

| Feature | Notes |
| --- | --- |
| Integer types | `i32`, `i64`, `number` (→ f64), `boolean` (→ i32) |
| Float types | `f32`, `f64` |
| BigInt literals | `42n` → i64 |
| Numeric enums | `enum Dir { Up = 0, Down = 1 }` — members fold to i32 constants |
| `never` return type | Marks a function that never returns — no WAT result clause; `(unreachable)` appended to body |
| `void` return type | Explicit zero-return annotation — no WAT result clause (fully supported) |
| `const enum` | Identical to numeric enum — members inlined as `i32` constants at every use site |
| `**` operator | Exponentiation — right-associative; `a ** b ** c` → `pow(a, pow(b, c))` |
| `as` type assertion | Numeric type cast → WASM conversion instruction (trunc, convert, promote, demote, wrap, extend) |
| Postfix `!` | Non-null assertion stripped at compile time (no WAT equivalent needed) |
| `satisfies` | Compile-time type hint stripped at compile time (no WAT equivalent needed) |
| `T \| null` / `T \| undefined` | Nullable value types — two WAT locals per variable (`$x` value + `$x__null` i32 flag); nullable function returns use a module-level `$__nullable_ret_flag` side-channel global; `console.log(x)` prints `"null"` when flag is set |
| `x === null` / `x !== null` | Null checks compile to `(local.get $x__null)` / `(i32.eqz (local.get $x__null))` — zero overhead |
| `x ?? fallback` | Nullish coalescing — WAT `(if (result T) nullFlag (then fallback) (else x))` |
| `??=` `\|\|=` `&&=` | Logical assignment — conditional store; supported for both locals and module globals |

##### Strings

| Feature | Notes |
| --- | --- |
| String literals | Stored in linear memory as ptr+len |
| `.length` | Returns character count as i32 |
| Comparisons | `===`, `!==`, `<`, `>`, `<=`, `>=` — lexicographic |
| Template literals | `` `x=${x} y=${y}` `` — numeric and string interpolation |
| `console.log` | Mixed-type argument lists (numbers, strings, booleans, BigInt, template literals, arrays) |
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
| `find(fn)` | Returns the first element for which `fn(element)` is truthy; when not found, returns `-1` (i32) / `NaN` (f64) as a sentinel — `console.log` of the result prints `undefined` to match TypeScript semantics |
| `reduce(fn, init)` | Folds the array to a single value: `acc = fn(acc, element)` starting from `init` |
| Array parameters | Passed as i32 pointer to the array's memory region |
| Rest parameters | `function f(...args: i32[])` — receives an i32 pointer to a dynamic array; caller builds temp heap array from literal args |
| Spread call | `f(...arr)` — passes an existing dynamic array pointer directly to a rest-param function |
| Spread array literal | `const merged = [...a, ...b]` — heap-allocates a new array via `$__dynarr_concat_T`; source arrays are automatically promoted to dynamic layout |
| Multi-dimensional arrays | `i32[][]` — nested dynamic array; `const m: i32[][] = [[1,2],[3,4]]` allocates outer + row arrays; `m[i].push(val)` updates the outer slot after possible row growth; `console.log(m)` prints `[ [ 1, 2 ], ... ]` (Deno format) |
| `console.log` of array-returning calls | `console.log("scores:", getScores())` where `getScores(): i32[]` prints `scores: [ 95, 88, 72 ]` — the `arrptr` LogSegment dispatches to a `$__write_i32arr_to_scratch` WAT helper that walks the dynamic-array header and formats elements in `[ a, b, c ]` style |
| Array destructuring with defaults | `const [a = 10, b = 20] = arr` — each binding gets the array element if in-bounds, or the default value; runtime length check for dynamic arrays; static arrays resolved at compile time |

##### Structs & Objects

| Feature | Notes |
| --- | --- |
| Struct definitions | `interface Vec2 { x: f64; y: f64; }` or `type` alias |
| Struct literals | `const v: Vec2 = { x: 1.0, y: 2.0 }` — static allocation |
| Field access | `v.x`, `v.y = 3.0` |
| Readonly fields | `readonly x: f64` — compile-time write guard; writes outside a class constructor emit a diagnostic |
| Struct parameters | Passed as i32 pointer |
| Object destructuring | `const { x, y } = vec` → i32.load / f64.load at field offsets |
| Renamed destructuring | `const { x: vx, y: vy } = vec` |
| Interface return types | `function createManager(): Manager` returns an i32 pointer to a heap-allocated struct of closure ptrs |
| Interface method dispatch | `manager.addRow([6])` dispatches via `call_indirect` using the trampoline closure pattern — uniform dispatch whether or not the method captures outer variables |
| `return { key: fn }` | Object-literal return emits interface struct; capturing arrows use a factory; non-capturing arrows are wrapped in a 4-byte `{table_idx}` mini-closure for uniform dispatch |
| Tuple types | `const t: [i32, f64] = [3, 4.5]` — anonymous fixed-layout struct; positional fields `_0`, `_1`, … |
| Named tuple aliases | `type Pair = [i32, i32]` — registers as a named struct; usable as parameter and return types |
| Tuple element access | `t[0]`, `t[1]` — compiles to `i32.load`/`f64.load` at field offset |
| Tuple element write | `t[0] = 99` — compiles to `i32.store`/`f64.store` at field offset |
| Tuple destructuring | `const [a, b] = t` — each binding compiles to a field load |
| Tuple return | `function minMax(a: i32, b: i32): [i32, i32] { return [a, b]; }` — heap-allocates struct via `$__malloc`, stores fields, returns pointer |
| Tuple parameters | `function sumPair(p: Pair): i32 { return p[0] + p[1]; }` — received as i32 pointer; fields loaded at offsets |

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
| `throw new Error("msg")` | Emits `(throw $__exn_tag ptr len)` — message stored in linear memory; catchable by any enclosing `try/catch`; uncaught exceptions print `error: Uncaught (in Wasm) Error: <msg>` to stderr and exit `wasmtk run` cleanly (mirrors TypeScript behavior) |
| `throw "literal"` | Same `(throw $__exn_tag ptr len)` path — string literal stored in data segment |
| `throw someStringVar` | `(throw $__exn_tag (local.get $v_ptr) (local.get $v_len))` — passes the string variable's ptr/len pair as the exception payload |
| `try { } catch (e) { }` | WAT `(try (do ...) (catch $__exn_tag ...))` — catches all `$__exn_tag` exceptions |
| `try { } finally { }` | `finally` body inlined in the `do` block (success path) and in a `catch_all` + `rethrow` (exception path) |
| `try { } catch (e) { } finally { }` | Combined form — `finally` runs on success, catch success, and unhandled exception paths |
| `e` in catch | Bound as a string variable (`$e_ptr` + `$e_len` i32 locals) — the throw message |
| `e.message` | Alias for `e` — resolves to the same string ptr/len pair |

##### Math

| Function | Notes |
| --- | --- |
| `Math.sqrt` | Native WASM `f64.sqrt` |
| `Math.abs` | `f64.abs` in f64 context; `$__i32_abs` WAT helper when argument is an i32 variable |
| `Math.floor`, `Math.ceil`, `Math.trunc` | Native WASM float ops (`f64.floor`, `f64.ceil`, `f64.trunc`) |
| `Math.round` | `(f64.floor (f64.add x 0.5))` — round half away from zero, matching JavaScript semantics; note: WASM's native `f64.nearest` uses IEEE 754 round-to-nearest-even (banker's rounding) which diverges from JS at `.5` boundaries |
| `Math.min`, `Math.max` | `f64.min` / `f64.max` in f64 context; `$__i32_min` / `$__i32_max` WAT helpers when both arguments are i32 |
| `Math.pow` | WAT `$__math_pow` helper (Binaryen converts to native `f64.pow`) |
| `Math.sign` | Implemented as WAT comparison + `f64.copysign` sequence |
| `Math.hypot(a, b)` | `f64.sqrt(a² + b²)` — two-argument form |
| `Math.clz32(n)` | Native WASM `i32.clz` — counts leading zeros of a 32-bit integer |
| `Math.imul(a, b)` | Native WASM `i32.mul` — C-style 32-bit integer multiplication |
| `Math.PI`, `Math.E`, `Math.SQRT2`, `Math.LN2`, `Math.LN10`, `Math.LOG2E`, `Math.LOG10E`, `Math.SQRT1_2` | `f64.const` — compile-time constants |

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
| Multi-dimensional arrays beyond `i32[][]` | Phase 6d covers `i32[][]`; `f64[][]` and deeper nesting not yet implemented |
| External interface mapping | Calls to an undeclared/unimported object (e.g. `logger.log(ptr)` where `logger` was never imported) are **rejected at compile time** with `❌ wasic: 'logger' is not defined` and a hint to import the function directly — no WIT / custom-section binding yet; Phase 40 will upgrade this static rejection to a full signature-verified binding; see `tests/wasm_wasi/ExternalMapping_11b.ts` |

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
wasmtk wasmbundle math1.wasm math2.wasm --alias math1.wasm=m1,math2.wasm=m2 --on-conflict=alias
```

**What it produces:** A `.wasm` library with all exported functions from every input module. Internal WAT symbol names are always mangled for uniqueness (`$mathlib_add`); exported names are always the original clean names (`"add"`) so consumers see a predictable public API.

**Best suited for:**

- Distributing multiple WASM modules as a single file
- Combining `modc`-compiled libraries for a consumer who only wants one import
- Packaging platform-specific WASM alongside shared utilities
- Reducing load overhead when a host needs functions from several modules

See [Phase 19 — `wasmbundle` CLI](#phase-19--wasmbundle-cli) and [Phase 20 — Export Name Transparency](#phase-20--export-name-transparency) for full pipeline and conflict resolution details.

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
| `runWasmBundle(inputs, out, onConflict?, aliases?)` | `./wasmbundle` | Bundle multiple `.wasm` files into a single `.wasm` library |
| `mergeWasmWat(wat, prefix, dataReloc, overrides?)` | `./wasmmerge` | Merge one WAT module into a parent with prefix mangling and data relocation; returns `exportMap` |
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
| 5e | First-class functions | funcref table, `call_indirect`, named arrow variables, callbacks, closure capture, IIFE entry pattern, nested closures, void arrows, mixed-signature branches; bug fix: type annotation declarations (`let f: (a) => b`) correctly skipped by arrow-substitution pass |
| 5f | Heap-allocated closures | Closure factories — functions that `return (params) => expr` produce a heap struct `{table_idx, captures...}`; `factoryFn(a)(b)` dispatches via a generated trampoline (`$fn__trampoline`); supported in `console.log` args and all expression/statement contexts |
| 5g | Closures as first-class values | Named function-type aliases; inline capturing arrows heap-allocated as `__anon_N__factory`; closure pointer dispatch via `closureTypedVars` + trampoline; bug fix: outer-scope regex extended to match array types (`i32[][]`) so 2D-array captures are detected correctly |
| 5h | Shared mutable captures (heap-boxing) | `return { inc: () => { count++; ... }, dec: () => { count--; ... } }` — variables captured by 2+ closures in a `return { ... }` object literal AND mutated by any of them are heap-boxed: factory allocates a 4-byte cell, stores the initial value, passes the pointer to every closure factory; reads emit `(i32.load (local.get $ptr))`; mutations (`count++`, `count--`, `count += x`, `count = x`) emit load-modify-store through the cell pointer |
| 6a | Numeric arrays | `i32[]`, `f64[]` — static allocation, element read/write, `.length`, array params |
| 6b | Structs / objects | `interface` and `type` as fixed-layout structs, field read/write, struct params |
| 6c | Object destructuring | `const { x, y } = vec` → `i32.load` / `f64.load` at field offsets; renamed destructuring |
| 6d | Multi-dimensional arrays | `i32[][]` — nested dynamic arrays; `const m: i32[][] = [[1,2],[3,4]]` allocates outer + inner row arrays; `m[i].push(val)` updates slot after possible row growth; `console.log(m)` prints Deno-format `[ [ 1, 2 ], ... ]` |
| 12b | Interface dispatch | `interface` types used as return values + method call sites: `createManager()` returns a struct of closure ptrs; `manager.addRow([6])` dispatches via `call_indirect` trampoline pattern; `stats.length` on i32 dynamic-array locals in `console.log`; `return { key: fn }` object literal emits interface struct with factory closure ptrs; trivial closures (no captures) auto-wrapped in a 4-byte `{table_idx}` mini-closure so dispatch is uniform |
| 7a | Math intrinsics | `Math.sqrt/abs/pow/floor/ceil/round/min/max/sign/trunc` → native WASM ops |
| 7b | Stderr output | `console.error` / `console.warn` → WASI fd=2 |
| 8 | Import bundler (`tsbundler.ts`) | Relative import resolution, module-prefix name mangling, alias (`as`) rewriting, chained imports, deduplication |
| 9 | Classes | `class` declarations desugared to struct layout + `ClassName_method` prefixed functions; `this` → hidden `__self: i32` param; `new ClassName()` → static alloc + constructor call; instance/static method dispatch; dot-call expressions in `console.log` args |
| 10a | Bump allocator | `$__heap_ptr` mutable global initialized to end of static data; `$__malloc(size)` advances and returns old ptr; 1 extra memory page reserved; Binaryen -Oz strips it when unused |
| 10b | Dynamic arrays | `push` / `pop` / `shift` / `unshift` on `i32[]` and `f64[]`; heap layout `[length i32][capacity i32][elem...]`; auto-detected by pre-scan; per-type WAT helpers emitted on demand; capacity = `max(n × 2, 8)` |
| 10c | Dynamic array growth | `push` / `unshift` grow on overflow: `$__dynarr_grow_T` mallocates new block (`cap × 2`), copies elements, returns new ptr; helpers return new array ptr so callers `local.set` their pointer; old block becomes dead memory (bump allocator has no free) |
| 11 | String operations | `str + str` concat (chained, heap-allocated); `str.slice(start, end)` (sub-range, no alloc); `str.indexOf(sub)` → i32; `str.includes(sub)` → bool; `String(n)` / `n.toString()` (number-to-string via heap); gather-buffer mode in `console.log` extended to handle string and bool variables |
| 12 | Array methods | `arr.indexOf(val)` → i32; `arr.includes(val)` → bool; `arr.slice(start, end)` → new array; `arr.forEach(fn)`; `arr.map(fn)` → new array; `arr.filter(fn)` → new array; `arr.find(fn)` → element or sentinel (-1/NaN); `arr.reduce(fn, init)` → value; dynamic arrays only; `const r: T[] = arr.map(fn)` pattern supported; `findDynamicArrays` extended to auto-detect arrays used with Phase 12 methods; `findResultVars` tracks variables assigned from `.find()` — `console.log` of those variables emits a sentinel check and prints `undefined` when not found, matching TypeScript semantics |
| 13 | Rest parameters / spread | `function f(...args: i32[])` — rest param receives heap array pointer; literal call sites build temp array via `$__malloc`; `f(...arr)` passes existing dynamic array pointer directly; `[...a, ...b]` concat via `$__dynarr_concat_T`; spread-source arrays auto-promoted to dynamic layout by `findDynamicArrays` |
| 13b | `console.log` of struct-returning calls | `console.log(tryDivide(10, 2))` where `tryDivide` returns an interface type prints `{ value: 5, hasError: 0 }` — struct pointer stored to `$__struct_tmp`, fields loaded by offset and formatted as `{ fieldName: value, ... }`; `$__struct_tmp` local injected by pre-scan of `_start` and `emitFunction` body lines; `LogSegment` array built directly in `emitStatement` and passed to `emitConsoleLog` |
| bug fix | `console.log` of array-returning calls | `console.log("scores:", getScores())` where `getScores(): i32[]` was printing the raw heap pointer; fix: `FuncLookup` now exposes `resultTsName`; `parseSingleArg` checks for `[]` suffix → new `arrptr` LogSegment; gather mode calls `$__write_i32arr_to_scratch` which loops the dynamic-array header and writes `[ a, b, c ]`; `getArrPrintHelperWat()` emits the WAT helper; `wasic.ts` tracks `needsArrPrintHelper` flag |
| 14 | Generics (monomorphization) | `function f<T>(x: T): T` — one concrete copy per distinct type; `interface Box<T> { value: T; }` → `Box_i32`, `Box_f64`, etc.; explicit type args (`f<i32>(x)`) and single-T literal inference (`f(42)` → `f_i32`); generic struct refs in function signatures rewritten automatically; source-level `expandGenerics()` pre-pass runs before all other parsing |
| 15 | Exception handling | `throw new Error("msg")` / `throw "lit"` / `throw strVar` → `(throw $__exn_tag ptr len)` — WASM exception tag carries a `(ptr i32, len i32)` string payload; catchable by any enclosing `try/catch`; `try/catch(e)/finally` via WAT exceptions proposal; `(tag $__exn_tag (param i32 i32))` declared once per module when any throw is emitted; `e` / `e.message` in catch bound as string locals; `exceptions: true` in wabt options; `binMod.setFeatures(Features.All)` before Binaryen `-Oz` to preserve exception sections |
| 16 | Module system extras | Default imports (`import foo from "./lib.ts"`); namespace imports (`import * as ns from "./lib.ts"`) with `ns.name` → `lib_name` rewriting; named re-exports (`export { foo } from "./lib.ts"`); wildcard re-exports (`export * from "./lib.ts"`); `export default function`; `exportRenamesCache` to resolve re-export chains across already-visited files; `applyRenames` updated to escape regex metacharacters (enabling dotted-key `ns.foo` rewrites) |
| 17 | wasic library mode | `WasicTranspiler` gains `mode: "wasi" \| "library"` constructor param; library mode skips `_start`, `proc_exit` import, and top-level statement processing; `compileLibTs()` public function mirrors `compileWasiTs()`; `modc.ts` backend replaced — AssemblyScript toolchain (`asc`), temp-file creation, and binary post-processor (`removeEnvAbortImport`) all removed; `compileModule` calls `compileLibTs` directly; supports full wasic TypeScript subset (no type restrictions) |
| 18 | WASM import bundling | `tsbundler.ts` detects `.wasm` specifiers in ESM imports and `wasmImport()` loader calls; new `wasmmerge.ts` module performs WAT-level merge with module-prefix name mangling; `_start`, `proc_exit`, `args_get/sizes_get`, `environ_get/sizes_get` stripped with notice; WASI imports deduplicated; data segments relocated by `mainModule.dataOffset`; static-data pointer `i32.const` values conservatively relocated; `WasicTranspiler` gains `externalFuncs` constructor param so call sites type-check before WAT merge; `iovBase`/`scratchBase` promoted to instance variables for collision-free merge of `fd_write` scratch areas; `bundleImportsEx()` returns `{ source, wasmImports }` alongside backward-compat `bundleImports()` |
| 19 | `wasmbundle` CLI | New `wasmbundle.ts` + `wasmtk wasmbundle` command bundles multiple `.wasm` files into a single combined `.wasm` library; cross-module export conflict detection; interactive per-conflict prompt or `--on-conflict=prefix\|exclude` flag; non-conflicting exports keep bare names; conflicting exports prefixed or excluded; sequential `mergeWasmWat` with tracked `dataOffset`; master WAT assembled with WASI imports (14 common signatures), auto-sized `(memory N)`, and explicit `(export ...)` declarations; `extractExportNames()` added to `wasmmerge.ts`; `exportOverrides` parameter added to `mergeWasmWat` for export name control |
| 20 | Export name transparency + `tsbundle` rename | `wasmmerge.ts`: `mergeWasmWat` emits `(export "add" (func $mathlib_add))` — original export name preserved, internal mangling unchanged; `WatMergeResult` gains `exportMap: Map<string, string>` (`originalName → $mangledName`); `wasmbundle.ts`: conflict resolution upgraded to 4-option interactive prompt (prefix / alias / exclude / stop) + `--alias file=name` and `--on-conflict=alias` non-interactive flags; `bundle` CLI command renamed to `tsbundle` |
| 21 | `never` type, `void` (complete), `readonly` | `"never"` added to `WatType`; `mapType("never")` returns `"never"`; `never`-return functions emit no WAT `(result ...)` and get `(unreachable)` appended to the body; all call-statement `drop` sites guarded against never/string results; `StructField.readonly?` flag; interface and class field parsing captures `readonly` modifier; `this.field = val` writes blocked outside the constructor; `obj.field = val` writes blocked for readonly struct/class fields; `currentMethodName` instance variable added |
| 22 | Compile-time convenience additions | `const enum` — identical to numeric enum (already parsed); Math constants (`Math.PI`, `Math.E`, `Math.LN2`, `Math.LOG2E`, `Math.LOG10E`, `Math.SQRT2`, `Math.SQRT1_2`, `Math.LN10`) → `f64.const` (already done); `**` exponentiation operator → `Math.pow` via right-associative LTR scan + `*` guard in `findBinaryOp`; `as` type assertion → `emitTypeCast` (trunc/convert/promote/demote/wrap/extend); postfix `!` non-null assertion stripped; `satisfies` operator stripped; `findDepth0LTR` + `findDepth0Keyword` + `emitTypeCast` helpers added; **bug fix**: `findDepth0Keyword` now scans from `expr.length - 1` so trailing `)` chars are correctly counted in depth before any ` as ` match is attempted; paren-group check now verifies the outer `(` is balanced with the final `)` before stripping — `as` now compiles correctly inside mixed-type compound expressions such as `(b * b) + (a as f64) + (c as f64)` |
| 23 | Tuple types `[A, B, C]` | Anonymous fixed-layout struct in linear memory; positional fields `_0`, `_1`, …; `type Pair = [i32, i32]` alias parsed in `parseStructs()`; inline `[T1, T2]` annotations; `getOrCreateTupleDef()` / `makeTupleStructDef()` create synthetic `__Tuple_T1_T2` StructDef; `mapType` extended for `[` prefix and `__Tuple_` prefix → i32; tuple params register in structVars via `structType`; `emitStatement` handles tuple literal init, named alias init, destructuring, element write, `return [e0, e1]`; strict `tupleFieldMatch` regex in `emitExpr` avoids greedy-match confusion with arithmetic; dynamic-array fallback guarded by `!structVars.has(var)`; `console_log.ts` handles `t[N]` via `structLookup` for correct type inference |
| bug fix | `Math.*` inside `console.log` with float-literal args | `console.log(Math.abs(-4.5))`, `Math.min(3.0, 5.0)`, `Math.max(3.0, 5.0)` produced invalid WAT (`i32.const -4.5`, `i32.const 3.0`, etc.) — root cause: `parseSingleArg` in `console_log.ts` routed these tokens through `dotCallLookup` (which called `emitExpr(..., "i32")`) before the dedicated `Math.*` handler ran; fix: added `!token.startsWith("Math.")` guard on the `dotCallLookup` check; all `Math.*` tokens now reach the correct handler which emits `f64.abs`, `f64.min`, `f64.max`; `MathIntrinsics_7a.ts` compiles and passes — 84/84 suite |
| bug fix | wasic compile-time rejection of undefined external dot-call receivers | `receiver.method(args)` where `receiver` is not a declared class instance, class, or interface variable was silently dropped — producing WASM that compiled successfully but omitted the call entirely. Fix: `emitStatement`'s `dotCallStmt` block now checks `classVars`/`classDefs`/`interfaceVars`; if the receiver is unknown it exits with `❌ wasic: 'receiver' is not defined — 'receiver.method(...)' cannot be compiled` and a hint to import the function directly. `ExternalMapping_11b.ts` — 86/86 suite |
| enhancement | Test runner `// @expect-fail` marker for negative tests | `run_wasi_tests.ts` reads `// @expect-fail: compile, run-ts, run-wasm` from the first 10 lines of any test file. `runStep` accepts an `expectedFail` flag and prints `✓ compile failed as expected` for expected failures. A step that fails-as-expected counts as OK in the verdict; run-wasm is treated as N/A when compile fails as expected. Overall result prints `✅ PASSED (expected failures: compile)`. `ExternalMapping_11b.ts` uses `// @expect-fail: compile` — 86/86 suite |
| bug fix | `tsbundler` `applyRenames` mangled `console.log` in imported modules | When a non-entry module exported a function whose name matched a built-in method (e.g. `export function log(...)`), `applyRenames` renamed every occurrence including `console.log(...)` — turning the function body into an empty stub (no WASI output). Root cause: lookbehind `(?<!\w)` allows a match after `.` because `.` is not a word character. Fix: changed to `(?<![\w.])` so a dot before the identifier prevents the match; `console.log` and all other method-call forms are left untouched while standalone call sites are correctly renamed. `ExternalMapping_11c.ts` — 85/85 suite |
| bug fix | `arr.find()` printed raw sentinel instead of `undefined` | `console.log(notFound)` where `notFound = arr.find(isNeg)` and no element matched printed `-1` (i32 sentinel) or `NaN` (f64 sentinel) instead of `undefined`, diverging from TypeScript semantics. Fix: `emitStatement` now tracks variables declared from `.find()` calls in `findResultVars`; when a `findResultVar` is the sole argument to `console.log`, the emitter wraps the print in a sentinel check — `(if (i32.eq val (i32.const -1)) (then print "undefined\n") (else print val))` — so not-found results display `undefined` exactly as TypeScript does. `ArrayMethods_12.ts` — 85/85 suite |
| perf fix (2026-04-17) | `runWasi` library-detection no longer double-compiles | `checkIsLibrary(path)` called a redundant `WebAssembly.compile()` after `WebAssembly.instantiate()` had already succeeded. Fix: inline check `!wasiInstance.exports._start` on the live instance — eliminates one disk read and one compile round-trip for library-call paths |
| cleanup (2026-04-15) | Removed `asc` (AssemblyScript) dependency | `compiler.ts` deleted — `runAssemblyScriptCompiler` and `runJavyCompiler` were exported but never imported by any other module in the project; `asc` (`npm:assemblyscript`) removed from `deno.json` imports; `./compiler` removed from `deno.json` exports; `modc` exclusively uses `compileLibTs` from `wasic.ts` — no AssemblyScript toolchain required at any point in the compilation pipeline |
| bug fix (2026-04-15) | `Math.round` semantics corrected to round half away from zero | `Math.round` was compiled to `f64.nearest` (IEEE 754 round-to-nearest-even / banker's rounding), causing `Math.round(2.5)` → `2` instead of the JavaScript-correct `3`. Fix: both `wasic.ts` (F64_UNARY table) and `console_log.ts` (exprToWat Math handler) now emit `(f64.floor (f64.add x (f64.const 0.5)))`, which matches JavaScript's "round half away from zero" rule for all normal values |
| bug fix (2026-04-15) | `$__f64_to_str` upgraded to ×1e15 / i64 — 15-digit precision | `$__f64_to_str` in `console_log.ts` upgraded from ×1e6 (6 decimal digits, i32 arithmetic) to ×1e15 (15 decimal digits, i64 arithmetic): `$fdigits` promoted from `i32` to `i64`; divisor and modulus changed to `i64.const 10`; digit extracted via `i32.wrap_i64`; loop count raised from 6 to 15; `f64.nearest` wrapping added before `i64.trunc_f64_s` to correct truncation error from f64 values that sit slightly below their true decimal (e.g. `3.14159` stored as `3.14158999…` → frac×1e6 was `141589.999…` → truncated to `141589` → printed `3.141589`; now rounds to `141590` → prints `3.14159`). Output now matches JavaScript for all but a small number of values requiring 17 significant digits (e.g. `Math.SQRT2` → JS `1.4142135623730951`, WASM `1.414213562373095`), a known JavaScript quirk where the f64 bit pattern requires 17 digits to guarantee round-trip uniqueness |
| 24 (2026-04-17) | `null` / `undefined` as values; `T \| null` returns | Nullable variable declarations (`const x: i32 \| null`) emit two WAT locals — `$x` (value) and `$x__null` (i32 flag, 1=null); nullable function returns (`function f(): i32 \| null`) use a module-level `$__nullable_ret_flag` global as a side-channel (callee sets to 1=has-value or 0=null, caller reads immediately after call); `parseNullableAnnotation()` helper strips `\| null \| undefined` and returns the inner `WatType`; null comparisons (`x === null`, `x !== null`) compile to `(local.get $x__null)` / `(i32.eqz (...))`; `console.log(x)` of a nullable var prints `"null"` when flag is set and the normal value otherwise; `null` / `undefined` literals added to `console_log.ts` `parseSingleArg`; pre-scans in both `emitFunction` and `startBodyLines` detect `T \| null` type annotations and register both locals; `nullableVarInnerType` map reset at start of each `emitFunction` call; `needsNullableResultFlag` flag gates `$__nullable_ret_flag` global emission — 87/87 suite |
| 25 (2026-04-17) | Nullish coalescing `??`, logical assignment `??=` `\|\|=` `&&=` | `??` handled before binary ops table in `emitExpr` — emits WAT `(if (result T) nullFlag (then rhs) (else lhs))` for nullable locals; pointer/string fallback uses `(i32.eqz ptr)`; `findBinaryOp` guards prevent `??` / `\|\|` / `&&` from matching `??=` / `\|\|=` / `&&=` (`after === "="` early-continue); `logicalAssignMatch` regex handles all three operators in `emitStatement` supporting both WAT locals (`local.get`/`local.set`) and module globals (`global.get`/`global.set`); `??=` for nullable locals clears the `__null` flag on assignment — 87/87 suite |
| 26 (2026-04-17) | `for...of` loops; array destructuring with default values | `for...of` over static `i32[]`, dynamic `i32[]`, `f64[]` arrays; `break` / `continue` inside loops; `for...of` over function-local dynamic arrays; array destructuring with defaults `const [a = 10, b = 20] = arr` — runtime length check on dynamic arrays; `$__forof_idx` (i32) shared local registered by pre-scans in both `emitFunction` and `startBodyLines`; **`parseTopLevel` `collectBlock` fix** — without this, module-level loop bodies were silently stripped because brace depth was never updated for top-level pattern-4 lines; static/dynamic/param access patterns differ (`i32.const` base / `i32.load` header / `local.get` base); pre-scan extracts binding name by splitting on `=` to avoid registering `"a = 10"` as a WAT local name — 88/88 suite |

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

# Bundle with overlapping export names — interactive prompt (4 options)
wasmtk wasmbundle math1.wasm math2.wasm

# Non-interactive: auto-prefix all conflicts with module filename
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=prefix

# Non-interactive: auto-prefix all conflicts with supplied aliases
wasmtk wasmbundle math1.wasm math2.wasm --alias math1.wasm=m1,math2.wasm=m2 --on-conflict=alias

# Non-interactive: auto-exclude all conflicts
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=exclude
```

**Conflict resolution:**

When two or more input modules export a function with the same name, `wasmbundle` detects the conflict. Non-conflicting exports always keep their bare names. For conflicts, the interactive prompt offers four options (upgraded in Phase 20):

```text
Conflict: "add" exported by: math1.wasm, math2.wasm
  [1]  Prefix with module name  →  math1_add, math2_add
  [2]  Prefix with alias         →  (use --alias math1.wasm=<name>,math2.wasm=<name>)
  [3]  Exclude both
  [4]  Stop compile             →  rename the function in source and recompile
  Choice (1/2/3/4):
```

When `--alias` is provided, option 2 shows the resolved names directly:

```text
  [2]  Prefix with alias         →  m1_add, m2_add
```

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

**`wasmmerge.ts` additions (Phase 19):**

- `extractExportNames(wat)` — returns bare non-entry export names; used for conflict detection
- `exportOverrides?: Map<string, string | null>` parameter on `mergeWasmWat` — controls output export names; `null` = exclude; populates `exportDecls: string[]` in `WatMergeResult`

See Phase 20 below for the `exportMap` addition and clean export name convention.

**Key distinction from Phase 18 (wasic import bundling):**

Phase 18 merges `.wasm` at the TypeScript compile step — the calling `.ts` file drives the merge and function names are always prefixed. Phase 19 operates on raw `.wasm` inputs with no TypeScript source involved. Non-conflicting exports keep bare names, making the output a clean drop-in library.

---

#### Phase 20 — Export Name Transparency

Phase 20 cleanly separates internal WAT symbol names (mangled for uniqueness) from WASM export strings (original, consumer-facing names) across both bundling paths. Also renames the `bundle` CLI command to `tsbundle` for clarity alongside `wasmbundle`.

**The core distinction:**

WAT natively supports independent internal and export names:

```wat
;; Internal names are mangled — guaranteed unique in WAT body
(func $mathlib_add      (param i32 i32) (result i32) ...)
(func $utils_add        (param i32 i32) (result i32) ...)

;; Export strings are independent — original names preserved for consumers
(export "add"           (func $mathlib_add))   ;; conflict resolved: mathlib wins
(export "format"        (func $utils_format))
```

Prior phases used the mangled internal name as both the WAT symbol *and* the export string (`"mathlib_add"`), exposing implementation details to consumers. Phase 20 fixes this.

**Two affected paths:**

| Path | File | Change |
| --- | --- | --- |
| TS-with-WASM-imports (Phase 18) | `wasmmerge.ts` | Export declarations use original names; `WatMergeResult` gains `exportMap` |
| WASM-only bundling (Phase 19) | `wasmbundle.ts` | Conflict handling upgraded to 4-option interactive prompt + `--alias` / `--on-conflict=alias` |

**`wasmmerge.ts` changes (shared core):**

`mergeWasmWat` now emits export declarations using the original source name as the export string and the mangled symbol as the internal reference:

```wat
;; Before Phase 20
(export "mathlib_add"   (func $mathlib_add))

;; After Phase 20
(export "add"           (func $mathlib_add))
```

`WatMergeResult` gains `exportMap: Map<string, string>` (`originalName → $mangledName`), populated for every export regardless of whether `exportOverrides` was passed. Both `wasic.ts` and `wasmbundle.ts` callers benefit automatically.

**`wasmbundle.ts` conflict resolution upgrade:**

The interactive prompt now offers four options:

```text
Conflict: "add" exported by: mathlib.wasm, utils.wasm
  [1]  Prefix with module name  →  mathlib_add, utils_add
  [2]  Prefix with alias         →  m_add, u_add
  [3]  Exclude both
  [4]  Stop compile             →  rename the function in source and recompile
  Choice (1/2/3/4):
```

Option 2 shows resolved examples when `--alias` is supplied; otherwise it shows a usage hint. All options are also available non-interactively:

```bash
# Prefix with module filename
wasmtk wasmbundle mathlib.wasm utils.wasm --on-conflict=prefix

# Prefix with alias
wasmtk wasmbundle mathlib.wasm utils.wasm --alias mathlib.wasm=m,utils.wasm=u --on-conflict=alias

# Exclude conflicts
wasmtk wasmbundle mathlib.wasm utils.wasm --on-conflict=exclude
```

**`bundle` → `tsbundle` CLI rename:**

The TypeScript-to-JS bundler command is renamed from `bundle` to `tsbundle` to clearly distinguish it from the `wasmbundle` WASM bundler command.

**TS module path vs WASM-only path — naming comparison:**

| | TS module path (Phases 8/18) | WASM-only path (Phases 19/20) |
| --- | --- | --- |
| Mangling happens at | TS source level (`tsbundler.ts`) | WAT body level (`wasmmerge.ts`) |
| Root module exports | Always clean — never mangled | Preserved explicitly via `exportMap` |
| Internal references | Rewritten in TS before compile | Rewritten in WAT during merge |
| Conflict surface | TS compiler (duplicate symbols) | `wasmbundle` (duplicate export strings) |
| Consumer sees | Clean names from root module | Clean original names from all merged modules |

---

### Planned Phases

Phases 27–39 extend `wasic` incrementally. Early phases add compile-time conveniences and core language features; middle phases build out the runtime data model; later phases complete the type system. No phase requires an embedded runtime — everything maps to static WASM constructs. Features that need a runtime are listed under [Types Requiring `javyc`](#types-requiring-javyc) below.

| Phase | Feature | Strategy |
| --- | --- | --- |
| 27 | Extended string methods + Bun runtime compatibility | String methods: `charCodeAt`, `charAt`, `String.fromCharCode`, `startsWith`, `endsWith`, `substring`, `lastIndexOf`, `trim`/`trimStart`/`trimEnd`, `toUpperCase`/`toLowerCase` (ASCII), `padStart`/`padEnd`, `repeat`, `replace`/`replaceAll`, `split` → dynamic `string[]`; Bun compat: new `src/rt.ts` shim detects Deno vs Bun and exports unified `rt.readFile`/`rt.writeFile`/`rt.readTextFile`/`rt.writeTextFile`/`rt.Command`; replaces 71 `Deno.*` call sites across 8 source files; `deno.json` used as-is by Bun; JSR imports resolved via `bunx jsr add` |
| 28 | Extended array methods | `every(fn)`, `some(fn)`, `findIndex(fn)`, `lastIndexOf(val)`, `at(i)`, `reverse()`, `fill(val)`, `join(sep)`, `sort(compareFn?)` — all extend the Phase 12 `call_indirect` callback infrastructure |
| 29 | Class enhancements | Static class fields → named WASM globals; `get`/`set` accessors → desugared to `ClassName_get_x` / `ClassName_set_x` functions; `private`/`protected`/`public` enforced at compile time; string enums → i32 constants with string lookup table |
| 30 | Struct / object enhancements + `namespace` | Struct arrays `Vec2[]` → dynamic array of i32 pointers; string arrays `string[]` → interleaved ptr+len `i32[]`; spread in object literals `{ ...base, x: 1 }` → field-by-field copy; `namespace Foo { }` → desugared to prefixed functions (same as module mangling) |
| 31 | TypedArrays | `Int32Array`, `Float64Array`, `Uint8Array`, `Int16Array`, etc. → typed views over `$__malloc` regions; constructor, `.subarray()`, `.fill()`, `.copyWithin()`, `.sort()` methods; reuse Phase 28 array infrastructure with fixed element widths |
| 32 | Discriminated union types | Tagged union: `tag: i32` + data region sized to largest variant; numeric literal unions as enum constants; string literal unions as compile-time i32 map; struct unions as tagged-union layout — benefits from Phase 30 struct infrastructure |
| 33 | Intersection types `A & B` | Compile-time struct field merge; field name conflict is a compile error — depends on Phase 30 struct infrastructure |
| 34 | Type predicates `x is T` | For Phase 32 tagged unions: emit `(i32.eq (i32.load $x) (i32.const TAG_FOO))`; predicate returns bool |
| 35 | `typeof` (type position) / `keyof T` | `typeof x` resolved to known `WatType` at compile time; `keyof T` yields string-literal union of struct field names (usable with Phase 32 string literal unions) |
| 36 | Simple conditional types | `T extends U ? X : Y` evaluated during `expandGenerics` monomorphization; complex recursive forms excluded |
| 37 | `flat()` / `flatMap(fn)` | Flatten nested arrays; requires Phase 30 struct arrays and Phase 31 TypedArray infrastructure |
| 38 | Extended math via external library | `Math.sin/cos/tan/asin/acos/atan/atan2`, `Math.log/log2/log10/exp/expm1/log1p`, `Math.hypot/cbrt/sinh/cosh/tanh`, `Math.random()` (WASI `random_get`) — imported as a pre-compiled `src/wasm/mathlib.wasm` via the Phase 18 bundler |
| 39 | `jstyper` — JavaScript import pre-processor | Generates `.d.ts` from `.js` via `npm:typescript`; merges typed signatures with JS bodies to produce `.ts` for wasic; `.js` never modified; existing `.d.ts` / `@types/` used directly; sequenced last so all supported types are available as annotations |
| 40 | External interface mapping (WIT / custom section) | `modc` / `wasic` accept a `.wit` file or WASM custom section declaring an external interface (e.g. `interface Logger { log(msgPtr: i32): void; }`); compiler verifies call sites match the declared signature; host provides the concrete implementation at link time — upgrades the current compile-time rejection (`❌ wasic: 'logger' is not defined`) to a full signature-verified binding; see `tests/wasm_wasi/ExternalMapping_11b.ts` |

---

#### Phase 39 — `jstyper`: JavaScript Import Pre-processor

Phase 39 adds a new pipeline stage that sits upstream of `tsbundler` and `wasic`. When a `.ts` file imports from a `.js` module, `jstyper` produces a `.ts` equivalent that wasic can compile — without ever modifying the original `.js` file.

The key design decision: type information comes from a **`.d.ts` declaration file**, not from inline annotation injection. The `.d.ts` is either generated automatically by the TypeScript compiler or supplied manually, and it remains a permanent, auditable, editable artefact alongside the `.js` source. It is sequenced last so that every type wasic supports is available as a valid annotation.

**Pipeline:**

```text
Step 1 — Resolve type declarations
  helper.d.ts exists?   →  use it directly (skip inference)
  @types/helper exists? →  use it directly (skip inference)
  neither exists?        →  run tsc (allowJs + declaration) to generate helper.d.ts

Step 2 — Parse helper.d.ts
  Extract typed function signatures: declare function add(a: number, b: number): number;
  Extract typed variable declarations: declare const PI: number;
  Hoist object literal shapes to named interface declarations

Step 3 — Merge with helper.js bodies
  For each declaration in .d.ts, find matching function body in .js
  Replace untyped JS header with typed TS signature
  Emit helper.ts  (types from .d.ts, bodies from .js)

Step 4 — Feed helper.ts into existing tsbundler pipeline
  wasic/modc pipeline unchanged
```

**Two usage modes:**

```bash
# Standalone — generate and inspect the .d.ts and .ts artefacts
wasmtk jstyper helper.js                   # generates helper.d.ts + helper.ts
wasmtk jstyper helper.js --dts-only        # generate helper.d.ts only for review/editing
wasmtk jstyper helper.js --dry-run         # print merged .ts to stdout without writing
wasmtk jstyper helper.js --any-policy skip # skip functions where type resolves to 'any'

# Transparent — fires automatically during wasic/modc compilation
import { add } from "./mathlib.js";        # jstyper runs on mathlib.js automatically
wasmtk wasic entry.ts                      # no extra steps needed
```

**Manual refinement workflow:**

Because `.d.ts` is a separate, editable file, developers can refine inferred types to precise WASM types that `tsc` can never infer on its own:

```bash
wasmtk jstyper mathlib.js --dts-only   # generates mathlib.d.ts with inferred types
```

```typescript
// mathlib.d.ts — auto-generated, then hand-edited
// Before: declare function add(a: number, b: number): number;
// After:
declare function add(a: i32, b: i32): i32;          // precise integer type
declare function lerp(a: f32, b: f32, t: f32): f32; // precise float type
```

```bash
wasmtk wasic entry.ts   # jstyper sees mathlib.d.ts, skips inference, uses hand-edited types
```

**Type mapping:**

| `.d.ts` declared type | Merged `.ts` annotation | wasic result | Requires phase |
| --- | --- | --- | --- |
| `number` | `: number` | `f64` | None |
| `string` | `: string` | `string` | None |
| `boolean` | `: boolean` | `bool` | None |
| `bigint` | `: bigint` | `i64` | None |
| `i32`, `i64`, `f32`, `f64` (hand-edited) | exact annotation | exact WASM type | None |
| `T[]` | `: T[]` | `i32` (pointer) | None |
| `void` | `: void` | `void` | ✅ Phase 21 |
| `never` | `: never` | `never` | ✅ Phase 21 |
| `T \| null` | `: T \| null` | `T` (null stripped) | Phase 24 for runtime correctness |
| `{ x: number; y: number }` | hoisted `interface` + `: Name` | `i32` (struct pointer) | None |
| `any` | `: number` + warning | `f64` | None (configurable via `--any-policy`) |
| `[A, B]` | hand-edited `.d.ts` → `type T = [A, B]` alias | `i32` (tuple pointer) | Phase 23 complete — inline tuple annotations supported |
| `Promise<T>`, `Generator<...>` | warning + skip | — | Out of scope |

**Phases 21–38 benefit as they land:**

| Phase | jstyper benefit after landing |
| --- | --- |
| ✅ 21 (`void`, `never`, `readonly`) | `: void` on zero-return functions correct; `readonly` stripped |
| ✅ 22 (compile-time ops) | `const enum` members usable as annotation values; `as` assertions passthrough |
| ✅ 23 (tuples) | tsc rarely infers true tuples from raw JS; hand-edited `.d.ts` can declare `type T = [A, B]` → full tuple support |
| ✅ 24 (`null`/`undefined`) | `T \| null` in `.d.ts` survives merge; nullable locals, null checks, `??`, `??=` fully supported |
| ✅ 25 (optional chaining / nullish) | `??` / `??=` / `\|\|=` / `&&=` fully compiled; transparent in function bodies |
| ✅ 26 (for...of / destructuring) | Transparent — body patterns, not type annotations |
| 27–28 (string/array methods) | Transparent — method calls in bodies, not signatures |
| 29 (class enhancements) | String enum member types usable in `.d.ts` annotations |
| 30 (struct arrays) | `Vec2[]` and `string[]` become valid annotation types in `.d.ts` |
| 31 (TypedArrays) | `Int32Array` etc. usable as annotation types |
| 32 (discriminated unions) | Hand-edited `.d.ts` can declare tagged union shapes |
| 33–34 (intersections, predicates) | Hand-editable in `.d.ts` after those phases land |
| 35 (`typeof`/`keyof`) | Transparent — tsc resolves to concrete type in `.d.ts` output |
| 36 (conditional types) | Not inferred from raw JS |
| 37–38 (flat/math) | Transparent — body calls, not signature types |
| 40 (WASM base64 bundling for JS build and Javy compile) | WASM binary embedded as base64 in JS output; Javy compile integration |

**Out-of-scope JS patterns (warning + skip):**

- CommonJS (`module.exports`, `require()`)
- `async function` / `function*`
- Prototype-based methods (`.prototype` assignments)
- `arguments` object usage
- Recursive object types
- `Symbol`, `Map`, `Set`, `WeakMap`, `Promise`, `Generator`

**New files:** `jstyper.ts`

**Changed files:** `deno.json` (add `npm:typescript` import + `./jstyper` export), `tsbundler.ts` (`.js` detection hook between lines 319–321), `main.ts` (`case "jstyper"` + help text)

---

#### Types Requiring `javyc`

The following TypeScript types require a dynamic runtime and cannot be compiled by `wasic`. Use `wasmtk javyc` for programs that need them:

| Type | Reason |
| --- | --- |
| `any` | Requires runtime type tagging and dynamic dispatch — WASM is fully statically typed |
| `unknown` | Same as `any` — requires runtime type checking before use |
| `symbol` | Requires a global runtime registry to guarantee uniqueness across calls |
| `object` (generic) | Arbitrary property access requires a heap-managed property map |
| Mapped types `{ [K in keyof T]: ... }` | Require full type system iteration — beyond a static code generator |
| Template literal types `` `${string}foo` `` | Type-level string manipulation requires a type checker, not a code generator |
| Complex recursive conditional types (`Awaited<T>`, `ReturnType<T>`) | Require deep type inference infrastructure |
| Prototype / dynamic `this` typing | Runtime object identity — antithetical to WASM's flat memory model |
