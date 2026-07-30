# wasmtk

<p align="center">
  <img src="wasmtk_logo.png" alt="wasmtk logo" width="300">
</p>

A polyglot WebAssembly toolkit for Deno. Compile TypeScript directly to optimized WASM via the
`wasic` compiler, run and inspect modules from any source language, and compose multi-language
projects into a single artifact.

## 🌟 Why wasmtk?

`wasmtk` is the home of **`wasic`** — a direct TypeScript-to-WASM compiler that emits optimized WAT
with no embedded JavaScript runtime. It also provides a complete toolkit for running, inspecting,
and composing WASM modules from any source language.

- **`wasic` compiler**: Compile a TypeScript subset directly to optimized `.wasm` via WAT, assembled
  by [`@jrmarcum/wabt-ts`](https://jsr.io/@jrmarcum/wabt-ts) (JSR-native TypeScript port of wabt)
  and optimized via Binaryen `-Oz`. Supports 50 language phases including closures, generics,
  classes, inheritance, discriminated unions, TypedArrays, and more — all without an embedded JS
  runtime.
- **WIT interface generation**: Every compiled module automatically produces a `.wit` file
  describing its exports and imports — the foundation for cross-language interop and the WASM
  Component Model.
- **Host binding generation (`bindgen`)**: Generate a self-contained TypeScript binding file from
  any `.wit` interface. Load and call WASM exports from a TypeScript host with full type safety and
  automatic ABI translation for numbers, booleans, and strings.
- **Universal running**: Execute `.ts`, `.js`, `.wasm`, and `.wat` with a single command across
  Deno, Bun, and Node. Expanded WASI syscall shims ensure compatibility with modules compiled from
  Zig, Rust, and Go.
- **Go producer (`--lang=go`)**: A Go command set via TinyGo (or the standard `go` toolchain with
  `--go-runtime=std`) — `init`/`initmod` (scaffold a WASI program / wasm library), `build`/`run`
  (build a WASI module, optionally run it), and `modc` (→ a callable WASI library via
  `//go:wasmexport`). Output is always a WASI module — consume it in the browser with the universal
  wasm loader. When `wasm-opt` (binaryen) isn't installed, wasmtk optimizes TinyGo's output with the
  in-house binaryen-ts Asyncify + `-Oz` pipeline instead — no external binaryen required, **including
  for goroutines**.
- **Zig producer (`--lang=zig`)**: `init`/`modc`/`run` via the `zig` toolchain — a wasm library
  (freestanding, `export fn`) or a `wasm32-wasi` program. Same shape as Go.
- **Rust producer (`--lang=rust`)**: delegates to [`rsxtk`](https://crates.io/crates/rsxtk) —
  `init`/`initmod`/`modc`/`build`/`run` plus dependency management (`add`/`remove`/`list`) and
  `fmt`/`clean`. (Polyglot producers: TypeScript, Go, Zig, Rust.)
- **Library mode (`modc`)**: Compile TypeScript to a WASM library with no `_start` entry point —
  callable from any host environment.
- **WASM bundling**: Merge multiple `.wasm` files into a single artifact; import pre-compiled
  `.wasm` modules directly from TypeScript source via `tsbundler`.
- **jstyper**: Convert `.js` + `.d.ts` pairs to typed TypeScript that `wasic` can compile — bridges
  existing JS libraries into the WASM pipeline.

## 🚀 Quick Start

### Installation

#### As a project dependency

Add wasmtk as a dependency in your current project:

Deno:

```bash
deno add jsr:@jrmarcum/wasmtk
```

Bun:

```bash
bunx jsr add @jrmarcum/wasmtk
```

#### As a global CLI tool

Install wasmtk as a globally available `wasmtk` command on your system:

Deno:

```bash
deno install -g -n wasmtk --allow-run --allow-read --allow-write --allow-env --allow-ffi --allow-net jsr:@jrmarcum/wasmtk
```

Bun:

```bash
bun install -g @jsr/jrmarcum__wasmtk
```

Bun installs global binaries to `~/.bun/bin`. Ensure this directory is on your `PATH` so the
`wasmtk` command is available system-wide:

macOS / Linux — add to `~/.bashrc`, `~/.zshrc`, or your shell's profile:

```bash
export PATH="$HOME/.bun/bin:$PATH"
```

Windows — use PowerShell to set the environment variable permanently without risking truncation of
your existing `PATH`. If you have local user privileges only, set it at the user level (no admin
required):

```powershell
[System.Environment]::SetEnvironmentVariable("PATH", "$env:USERPROFILE\.bun\bin;" + [System.Environment]::GetEnvironmentVariable("PATH", "User"), "User")
```

If you have administrator privileges and want it available system-wide for all users:

```powershell
[System.Environment]::SetEnvironmentVariable("PATH", "$env:USERPROFILE\.bun\bin;" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine"), "Machine")
```

In either case, restart your terminal after running the command for the change to take effect.

#### Run on demand without installing

Execute wasmtk directly without any permanent installation:

Deno:

```bash
deno run -A jsr:@jrmarcum/wasmtk
```

Bun requires a one-time registry configuration so it can resolve JSR packages. The `.npmrc` file
must be placed in `~/.bun/bin` — the same directory where Bun installs global binaries. Create or
edit it with the following command for your platform:

macOS / Linux:

```bash
echo '@jsr:registry=https://npm.jsr.io' >> ~/.bun/bin/.npmrc
```

Windows (PowerShell):

```powershell
Add-Content "$env:USERPROFILE\.bun\bin\.npmrc" '@jsr:registry=https://npm.jsr.io'
```

Once configured, run on demand with:

```bash
bunx @jrmarcum/wasmtk
```

---

## 🔨 Compiler Options

wasmtk provides three distinct compilation paths. Choosing the right one depends on what your
program needs at runtime.

---

### `wasmtk wasic` — Direct TypeScript-to-WASM (WASI Standalone)

Compiles a TypeScript or WAT source file to a **standalone WASI module** with no embedded JavaScript
runtime. Two input paths are supported:

- **`.ts`** — runs through the tsbundler import pre-pass, WasicTranspiler, `@jrmarcum/wabt-ts` (WAT
  → binary), and Binaryen `-Oz`
- **`.wat`** — assembled directly by `@jrmarcum/wabt-ts` and optimized by Binaryen `-Oz` (no
  transpiler step)

```bash
wasmtk wasic myprogram.ts       # TypeScript → WAT → optimized .wasm
wasmtk wasic myprogram.wat      # WAT → optimized .wasm (direct, no transpiler)
wasmtk run myprogram.wasm
```

**What it produces:** A self-contained WASI executable. Exports a `_start` function that WASI hosts
invoke as the program entry point.

**Best suited for:**

- Numeric computation (i32, i64, f32, f64)
- Performance-critical, zero-overhead code
- Data structures with known, fixed layouts (arrays, structs)
- Multi-file programs composed from local `.ts` modules
- Programs that only need WASI I/O (`console.log`, file I/O)
- Self-contained `async`/`await` + Promise workflows (intra-module — see the Async row in Completed
  Phases)
- Situations where binary size and startup time matter

---

#### Supported TypeScript Features

##### Functions & Variables

| Feature                        | Syntax                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Typed function declarations    | `function add(a: i32, b: i32): i32 { ... }`                                                                                                                                                                                                                                                                                               |
| Default parameters             | `function f(x: i32 = 0)`                                                                                                                                                                                                                                                                                                                  |
| Optional parameters            | `function f(x?: i32)`                                                                                                                                                                                                                                                                                                                     |
| Arrow functions                | `const fn = (x: i32): i32 => x * 2`                                                                                                                                                                                                                                                                                                       |
| Void arrows                    | `const noOp = (): void => { }` — no return value                                                                                                                                                                                                                                                                                          |
| First-class function variables | `const op: (a: i32, b: i32) => i32 = add`                                                                                                                                                                                                                                                                                                 |
| Higher-order / callbacks       | `function apply(f: (x: i32) => i32, v: i32): i32`                                                                                                                                                                                                                                                                                         |
| Closure capture                | Outer-scope variables injected as hidden parameters                                                                                                                                                                                                                                                                                       |
| Nested closures                | Multi-level capture: inner arrow captures from outer arrow's scope                                                                                                                                                                                                                                                                        |
| Heap-allocated closures        | Factory functions `function f(x) { return (y) => x*y; }` — inner arrow lifted to `f__inner`; factory mallocs `{table_idx, captures}` struct; `$f__trampoline` dispatches via `call_indirect`                                                                                                                                              |
| Named function type aliases    | `type Scaler = (val: i32) => i32` — inline capturing arrows heap-allocated as `__anon_N__factory`; closure pointers dispatchable via named-type trampolines                                                                                                                                                                               |
| Shared mutable captures        | `function createCounter() { let count = 0; return { inc: () => { count++; return count; }, dec: () => ... } }` — captured variables shared across multiple closures AND mutated are heap-boxed: a 4-byte cell is allocated per shared variable; each closure receives the cell pointer; reads emit `i32.load`, mutations emit `i32.store` |
| Variable declarations          | `let`, `const`, `var` with optional type annotations                                                                                                                                                                                                                                                                                      |

##### Control Flow

| Feature                | Syntax                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ |
| Conditionals           | `if / else if / else`                                                                                        |
| While loop             | `while (cond) { }`                                                                                           |
| Do-while loop          | `do { } while (cond)`                                                                                        |
| For loop               | `for (let i = 0; i < n; i++)`                                                                                |
| For-of loop            | `for (const x of arr)` — iterates `i32[]` / `f64[]` static and dynamic arrays; supports `break` / `continue` |
| Switch                 | `switch (x) { case 1: ... break; default: ... }`                                                             |
| Labeled break/continue | `outer: for(...) { inner: for(...) { break outer; } }`                                                       |
| Ternary                | `cond ? a : b`                                                                                               |

##### Operators

| Category            | Operators                                                              |
| ------------------- | ---------------------------------------------------------------------- |
| Arithmetic          | `+ - * / %`                                                            |
| Comparison          | `=== !== == != < > <= >=`                                              |
| Logical             | `&& \|\| !`                                                            |
| Bitwise             | `& \| ^ ~ << >> >>>`                                                   |
| Compound assignment | `+= -= *= /= %= &= \|= ^= <<= >>= >>>= **=`                            |
| Logical assignment  | `??= \|\|= &&=` — assign only when null/falsy/truthy (Phase 25)        |
| Nullish coalescing  | `??` — returns rhs when lhs is `null`/`undefined`, else lhs (Phase 25) |

##### Numeric Types

| Feature                        | Notes                                                                                                                                                                                                                             |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Integer types                  | `i32`, `i64`, `number` (→ f64), `boolean` (→ i32)                                                                                                                                                                                 |
| Float types                    | `f32`, `f64`                                                                                                                                                                                                                      |
| BigInt literals                | `42n` → i64                                                                                                                                                                                                                       |
| Numeric enums                  | `enum Dir { Up = 0, Down = 1 }` — members fold to i32 constants                                                                                                                                                                   |
| String enums                   | `enum Dir { Up = "up", Down = "down" }` — members resolve to static string data; usable in `console.log` and `const x: string = Dir.Up` assignments                                                                               |
| `never` return type            | Marks a function that never returns — no WAT result clause; `(unreachable)` appended to body                                                                                                                                      |
| `void` return type             | Explicit zero-return annotation — no WAT result clause (fully supported)                                                                                                                                                          |
| `const enum`                   | Identical to numeric enum — members inlined as `i32` constants at every use site                                                                                                                                                  |
| `**` operator                  | Exponentiation — right-associative; `a ** b ** c` → `pow(a, pow(b, c))`                                                                                                                                                           |
| `as` type assertion            | Numeric type cast → WASM conversion instruction (trunc, convert, promote, demote, wrap, extend)                                                                                                                                   |
| Postfix `!`                    | Non-null assertion stripped at compile time (no WAT equivalent needed)                                                                                                                                                            |
| `satisfies`                    | Compile-time type hint stripped at compile time (no WAT equivalent needed)                                                                                                                                                        |
| `T \| null` / `T \| undefined` | Nullable value types — two WAT locals per variable (`$x` value + `$x__null` i32 flag); nullable function returns use a module-level `$__nullable_ret_flag` side-channel global; `console.log(x)` prints `"null"` when flag is set |
| `x === null` / `x !== null`    | Null checks compile to `(local.get $x__null)` / `(i32.eqz (local.get $x__null))` — zero overhead                                                                                                                                  |
| `x ?? fallback`                | Nullish coalescing — WAT `(if (result T) nullFlag (then fallback) (else x))`                                                                                                                                                      |
| `??=` `\|\|=` `&&=`            | Logical assignment — conditional store; supported for both locals and module globals                                                                                                                                              |

##### Strings

| Feature                                              | Notes                                                                                                                                                                                                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| String literals                                      | Stored in linear memory as ptr+len                                                                                                                                                                                                          |
| Escape sequences                                     | `\n` `\r` `\t` `\b` `\f` `\v` `\0` `\\` `\"` `\'` — correctly decoded to the single intended byte; `\xHH` hex escapes; `\uHHHH` and `\u{H…}` Unicode code points (UTF-8 encoded); works in both double-quoted strings and template literals |
| `.length`                                            | Returns character count as i32                                                                                                                                                                                                              |
| Comparisons                                          | `===`, `!==`, `<`, `>`, `<=`, `>=` — lexicographic                                                                                                                                                                                          |
| Template literals                                    | `` `x=${x} y=${y}` `` — numeric and string interpolation; escape sequences processed in all static text segments                                                                                                                            |
| `console.log`                                        | Mixed-type argument lists (numbers, strings, booleans, BigInt, template literals, arrays)                                                                                                                                                   |
| `console.error` / `console.warn`                     | Same as `console.log` but writes to stderr (fd=2)                                                                                                                                                                                           |
| `str + str`                                          | Concatenation — heap-allocates a new string; chains left-to-right (e.g. `a + b + c`)                                                                                                                                                        |
| `str.slice(start, end)`                              | Returns a sub-range pointer with clamped bounds (no allocation)                                                                                                                                                                             |
| `str.indexOf(sub)`                                   | Returns i32 offset of first occurrence, or -1 if not found                                                                                                                                                                                  |
| `str.includes(sub)`                                  | Returns bool — `true` if substring is present                                                                                                                                                                                               |
| `String(n)`                                          | Converts numeric value to a heap-allocated string                                                                                                                                                                                           |
| `n.toString()`                                       | Same as `String(n)` — works on `i32`, `f64`, `i64` variables                                                                                                                                                                                |
| `str.trim()` / `str.trimStart()` / `str.trimEnd()`   | Remove whitespace from both ends, start, or end                                                                                                                                                                                             |
| `str.charCodeAt(n)`                                  | Returns the UTF-8 byte value at index n as i32                                                                                                                                                                                              |
| `str.charAt(n)`                                      | Returns a single-character string at index n                                                                                                                                                                                                |
| `str.at(n)`                                          | Returns a single-character string; negative indices count from the end                                                                                                                                                                      |
| `str.startsWith(prefix)` / `str.endsWith(suffix)`    | Returns bool — prefix or suffix match                                                                                                                                                                                                       |
| `str.toUpperCase()` / `str.toLowerCase()`            | Returns a new string with ASCII case conversion                                                                                                                                                                                             |
| `str.replace(old, new)` / `str.replaceAll(old, new)` | Returns a new string with first/all occurrences replaced                                                                                                                                                                                    |
| `str.padStart(n, fill)` / `str.padEnd(n, fill)`      | Returns a new string padded to length n                                                                                                                                                                                                     |
| `str.repeat(n)`                                      | Returns the string repeated n times                                                                                                                                                                                                         |
| `str.split(sep)`                                     | Returns a `string[]` dynamic array of substrings split at the separator                                                                                                                                                                     |
| `str.indexOf(sub, pos?)`                             | Optional second argument: start search from position; returns -1 if not found                                                                                                                                                               |

##### Arrays

| Feature                                | Notes                                                                                                                                                                                                                                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Static numeric arrays                  | `i32[]`, `f64[]` — literal initializer, elements baked into the data section                                                                                                                                                                                       |
| Dynamic numeric arrays                 | `i32[]`, `f64[]` — heap-allocated when any mutating method, query method, or spread usage (`...arr`) is detected by the pre-scan                                                                                                                                   |
| Element access                         | `arr[i]`, `arr[i] = v` — works on both static and dynamic arrays                                                                                                                                                                                                   |
| Length                                 | `arr.length` — compile-time constant for static; runtime load from 8-byte header for dynamic                                                                                                                                                                       |
| `push(val)`                            | Appends a value; grows array automatically if at capacity (cap × 2 realloc)                                                                                                                                                                                        |
| `pop()`                                | Removes and returns the last element; decrements length                                                                                                                                                                                                            |
| `shift()`                              | Removes and returns the first element; shifts remaining elements left                                                                                                                                                                                              |
| `unshift(val)`                         | Inserts a value at the front; shifts elements right; grows array automatically if at capacity                                                                                                                                                                      |
| `indexOf(val)`                         | Returns i32 index of the first matching element, or -1 if not found                                                                                                                                                                                                |
| `includes(val)`                        | Returns bool — `true` if the element is present in the array                                                                                                                                                                                                       |
| `slice(start, end)`                    | Returns a new heap-allocated array containing elements from `[start, end)`; bounds clamped                                                                                                                                                                         |
| `forEach(fn)`                          | Calls `fn(element)` for each element via `call_indirect` through the funcref table                                                                                                                                                                                 |
| `map(fn)`                              | Returns a new array of the same length where each element is `fn(element)`                                                                                                                                                                                         |
| `filter(fn)`                           | Returns a new array containing only elements for which `fn(element)` is truthy                                                                                                                                                                                     |
| `find(fn)`                             | Returns the first element for which `fn(element)` is truthy; when not found, returns `-1` (i32) / `NaN` (f64) as a sentinel — `console.log` of the result prints `undefined` to match TypeScript semantics                                                         |
| `reduce(fn, init)`                     | Folds the array to a single value: `acc = fn(acc, element)` starting from `init`                                                                                                                                                                                   |
| Array parameters                       | Passed as i32 pointer to the array's memory region                                                                                                                                                                                                                 |
| Rest parameters                        | `function f(...args: i32[])` — receives an i32 pointer to a dynamic array; caller builds temp heap array from literal args                                                                                                                                         |
| Spread call                            | `f(...arr)` — passes an existing dynamic array pointer directly to a rest-param function                                                                                                                                                                           |
| Spread array literal                   | `const merged = [...a, ...b]` — heap-allocates a new array via `$__dynarr_concat_T`; source arrays are automatically promoted to dynamic layout                                                                                                                    |
| Multi-dimensional arrays               | `i32[][]` — nested dynamic array; `const m: i32[][] = [[1,2],[3,4]]` allocates outer + row arrays; `m[i].push(val)` updates the outer slot after possible row growth; `console.log(m)` prints `[ [ 1, 2 ], ... ]` (Deno format)                                    |
| `console.log` of array-returning calls | `console.log("scores:", getScores())` where `getScores(): i32[]` prints `scores: [ 95, 88, 72 ]` — the `arrptr` LogSegment dispatches to a `$__write_i32arr_to_scratch` WAT helper that walks the dynamic-array header and formats elements in `[ a, b, c ]` style |
| Array destructuring with defaults      | `const [a = 10, b = 20] = arr` — each binding gets the array element if in-bounds, or the default value; runtime length check for dynamic arrays; static arrays resolved at compile time                                                                           |
| `every(fn)`                            | Returns bool — `true` if `fn(element)` is truthy for every element                                                                                                                                                                                                 |
| `some(fn)`                             | Returns bool — `true` if `fn(element)` is truthy for at least one element                                                                                                                                                                                          |
| `findIndex(fn)`                        | Returns the index of the first element for which `fn(element)` is truthy, or -1                                                                                                                                                                                    |
| `at(i)`                                | Returns the element at index i; negative indices count from the end                                                                                                                                                                                                |
| `reverse()`                            | In-place two-pointer swap; mutates the array and returns the pointer                                                                                                                                                                                               |
| `fill(val, start?, end?)`              | Fills elements from start to end with val; bounds clamped to [0, length]                                                                                                                                                                                           |
| `join(sep?)`                           | Joins all elements into a string with the given separator (default `","`)                                                                                                                                                                                          |
| `sort()` / `sort(cmpFn)`               | In-place insertion sort — ascending by default; custom comparator via `call_indirect`                                                                                                                                                                              |
| `flat()`                               | Flatten a `T[][]` one level deep — two-pass WAT helper sums all inner lengths, allocates result, copies                                                                                                                                                            |
| `flatMap(fn)`                          | Map each element through `fn` (returning `T[]`) then flatten one level                                                                                                                                                                                             |
| `concat(other)`                        | Returns a new array with all elements of this array followed by all elements of other                                                                                                                                                                              |
| Chained calls                          | `arr.filter(f).map(g)` — intermediate result inlined as WAT expression; no temp variable needed                                                                                                                                                                    |
| String array params                    | `function f(arr: string[], pred: (s: string) => boolean)` — string arrays passed as i32 pointer; each element is 8 bytes (ptr i32 + len i32); shift=3                                                                                                              |
| Function pointer arrays                | `const fns: Array<() => void> = []` — stores closure struct pointers; `fns[i]()` dispatches via `call_indirect` trampoline                                                                                                                                         |

##### Structs & Objects

| Feature                   | Notes                                                                                                                                                                      |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Struct definitions        | `interface Vec2 { x: f64; y: f64; }` or `type` alias                                                                                                                       |
| Struct literals           | `const v: Vec2 = { x: 1.0, y: 2.0 }` — static allocation                                                                                                                   |
| Field access              | `v.x`, `v.y = 3.0`                                                                                                                                                         |
| Readonly fields           | `readonly x: f64` — compile-time write guard; writes outside a class constructor emit a diagnostic                                                                         |
| Struct parameters         | Passed as i32 pointer                                                                                                                                                      |
| Object destructuring      | `const { x, y } = vec` → i32.load / f64.load at field offsets                                                                                                              |
| Renamed destructuring     | `const { x: vx, y: vy } = vec`                                                                                                                                             |
| Interface return types    | `function createManager(): Manager` returns an i32 pointer to a heap-allocated struct of closure ptrs                                                                      |
| Interface method dispatch | `manager.addRow([6])` dispatches via `call_indirect` using the trampoline closure pattern — uniform dispatch whether or not the method captures outer variables            |
| `return { key: fn }`      | Object-literal return emits interface struct; capturing arrows use a factory; non-capturing arrows are wrapped in a 4-byte `{table_idx}` mini-closure for uniform dispatch |
| Tuple types               | `const t: [i32, f64] = [3, 4.5]` — anonymous fixed-layout struct; positional fields `_0`, `_1`, …                                                                          |
| Named tuple aliases       | `type Pair = [i32, i32]` — registers as a named struct; usable as parameter and return types                                                                               |
| Tuple element access      | `t[0]`, `t[1]` — compiles to `i32.load`/`f64.load` at field offset                                                                                                         |
| Tuple element write       | `t[0] = 99` — compiles to `i32.store`/`f64.store` at field offset                                                                                                          |
| Tuple destructuring       | `const [a, b] = t` — each binding compiles to a field load                                                                                                                 |
| Tuple return              | `function minMax(a: i32, b: i32): [i32, i32] { return [a, b]; }` — heap-allocates struct via `$__malloc`, stores fields, returns pointer                                   |
| Tuple parameters          | `function sumPair(p: Pair): i32 { return p[0] + p[1]; }` — received as i32 pointer; fields loaded at offsets                                                               |

##### External Interface Bindings

| Feature                    | Notes                                                                                                                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inline external binding    | `declare const host: { log(ptr: i32): void; getTime(): i32 }` — each method compiles to `(import "env" "host_log" ...)` and `(import "env" "host_getTime" ...)` in the WASM binary |
| Named external interface   | `declare interface Logger { log(ptr: i32): void }` then `declare const logger: Logger` — two-declaration form; interface can be reused across multiple bindings                    |
| Multiple external bindings | Any number of `declare const` / `declare interface` bindings in one file; each gets its own set of `(import "env" ...)` declarations                                               |
| Supported method types     | Parameters and return types: `i32`, `i64`, `f32`, `f64`, `bool`, `void` — same type set as the wasic function ABI                                                                  |
| Call-site verification     | Methods called on the binding are type-checked at compile time against the declared signature                                                                                      |
| Host stub proxy            | The test runner provides a no-op Proxy for `env` imports — any undeclared method returns `0`; real host implementations replace these stubs                                        |

##### WIT File Generation

After every successful `wasmtk wasic` or `wasmtk modc` compilation a `.wit` file is written
alongside the `.wasm` output.

| Feature              | Notes                                                                                                                                  |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Automatic generation | `.wit` written at the same path as the output `.wasm` (e.g. `mylib.wasm` → `mylib.wit`) with no extra flags required                   |
| Export section       | Each `export function` becomes a WIT `export name: func(...)` declaration; internal runtime helpers and closure factories are excluded |
| Import section       | Phase 40 external bindings that are actually called in the source become WIT `import name: func(...)` declarations                     |
| WIT types            | `i32→s32`, `i64→s64`, `f32→f32`, `f64→f64`, `bool→bool`; `void` return → no `-> type` clause                                           |
| Kebab-case names     | Function names are automatically converted to WIT-compliant kebab-case (e.g. `logMessage` → `log-message`)                             |
| Package format       | `package local:module-name; world module-name { ... }`                                                                                 |

##### Generics

`wasic` monomorphizes generic functions and structs at compile time — zero runtime overhead, no
boxing, no type-erasure penalty.

| Feature                         | Syntax / Notes                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------- |
| Generic functions               | `function identity<T>(x: T): T` — one concrete copy per distinct type used         |
| Multi-param generics            | `function minVal<T>(a: T, b: T): T` — all params bound to the same type            |
| Explicit type arguments         | `identity<i32>(42)` → emits `identity_i32`; `identity<f64>(3.14)` → `identity_f64` |
| Literal type inference          | `identity(42)` → infers `i32`; `identity(3.14)` → `f64`; `identity(true)` → `bool` |
| Generic structs                 | `interface Box<T> { value: T; count: i32; }`                                       |
| Generic struct usage            | `const b: Box<i32> = { value: 99, count: 3 }` → concrete struct `Box_i32`          |
| Generic function + struct param | `function getBoxValue<T>(b: Box<T>): T` — struct ref in signature is rewritten     |
| Naming convention               | Concrete names are `name_T1_T2` (e.g., `identity_i32`, `Box_f64`, `minVal_i32`)    |
| `type` alias generics           | `type Pair<A, B> = { first: A; second: B; }` — same as `interface`                 |

##### Exception Handling

| Feature                                      | Notes                                                                                                                                                                                                                                                                              |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `throw new Error("msg")`                     | Emits `(throw $__exn_tag ptr len)` — message stored in linear memory; catchable by any enclosing `try/catch`; uncaught exceptions print `error: Uncaught (in Wasm) Error: <msg>` to stderr and exit `wasmtk run` cleanly (mirrors TypeScript behavior)                             |
| `throw "literal"`                            | Same `(throw $__exn_tag ptr len)` path — string literal stored in data segment                                                                                                                                                                                                     |
| `throw someStringVar`                        | `(throw $__exn_tag (local.get $v_ptr) (local.get $v_len))` — passes the string variable's ptr/len pair as the exception payload                                                                                                                                                    |
| `try { } catch (e) { }`                      | WAT `(try (do ...) (catch $__exn_tag ...))` — catches all `$__exn_tag` exceptions                                                                                                                                                                                                  |
| `try { } finally { }`                        | `finally` body inlined in the `do` block (success path) and in a `catch_all` + `rethrow` (exception path)                                                                                                                                                                          |
| `try { } catch (e) { } finally { }`          | Combined form — `finally` runs on success, catch success, and unhandled exception paths                                                                                                                                                                                            |
| `e` in catch                                 | Bound as a string variable (`$e_ptr` + `$e_len` i32 locals) — the throw message                                                                                                                                                                                                    |
| `e.message`                                  | Alias for `e` — resolves to the same string ptr/len pair                                                                                                                                                                                                                           |
| `String(e)` in catch                         | Produces `"Error: <message>"` — matches JavaScript's `Error.prototype.toString()` (e.g. `String(e)` → `"Error: Structural Error Message"`). Only applies when `e` is a catch exception binding; `String()` on non-catch strings behaves normally                                   |
| `e instanceof Error ? e.message : String(e)` | Idiomatic TypeScript catch pattern — simplified at compile time to a direct copy of the exception string (`e.message`), producing just the message text (without `"Error: "` prefix); `String(e)` in the else-branch is unreachable in wasic since all exceptions are string-typed |
| `catch (e)` shadowing outer `e: string`      | The outer string variable is preserved — the catch block uses alias locals `$__catch_e_ptr`/`$__catch_e_len` so `$e_ptr`/`$e_len` are never overwritten; the outer `e` is readable again after the catch scope exits                                                               |

##### Math

| Function                                                                                                | Notes                                                                                                                                                                                                                         |
| ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Math.sqrt`                                                                                             | Native WASM `f64.sqrt`                                                                                                                                                                                                        |
| `Math.abs`                                                                                              | `f64.abs` in f64 context; `$__i32_abs` WAT helper when argument is an i32 variable                                                                                                                                            |
| `Math.floor`, `Math.ceil`, `Math.trunc`                                                                 | Native WASM float ops (`f64.floor`, `f64.ceil`, `f64.trunc`)                                                                                                                                                                  |
| `Math.round`                                                                                            | `(f64.floor (f64.add x 0.5))` — round half away from zero, matching JavaScript semantics; note: WASM's native `f64.nearest` uses IEEE 754 round-to-nearest-even (banker's rounding) which diverges from JS at `.5` boundaries |
| `Math.min`, `Math.max`                                                                                  | `f64.min` / `f64.max` in f64 context; `$__i32_min` / `$__i32_max` WAT helpers when both arguments are i32                                                                                                                     |
| `Math.pow`                                                                                              | WAT `$__math_pow` helper (Binaryen converts to native `f64.pow`)                                                                                                                                                              |
| `Math.sign`                                                                                             | Implemented as WAT comparison + `f64.copysign` sequence                                                                                                                                                                       |
| `Math.hypot(a, b)`                                                                                      | `f64.sqrt(a² + b²)` — two-argument form                                                                                                                                                                                       |
| `Math.clz32(n)`                                                                                         | Native WASM `i32.clz` — counts leading zeros of a 32-bit integer                                                                                                                                                              |
| `Math.imul(a, b)`                                                                                       | Native WASM `i32.mul` — C-style 32-bit integer multiplication                                                                                                                                                                 |
| `Math.PI`, `Math.E`, `Math.SQRT2`, `Math.LN2`, `Math.LN10`, `Math.LOG2E`, `Math.LOG10E`, `Math.SQRT1_2` | `f64.const` — compile-time constants                                                                                                                                                                                          |

##### Multi-file Programs

The bundler pre-pass (`tsbundler.ts`) runs before compilation and merges all imported modules into a
single flat source. Compiled output is always a single `.wasm` file regardless of how many source
files are involved.

| Feature             | Notes                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------- |
| Named imports       | `import { foo, bar } from "./lib.ts"`                                                 |
| Import aliases      | `import { foo as f } from "./lib.ts"` — alias is a compile-time rewrite               |
| Default imports     | `import foo from "./lib.ts"` — `foo` rewrites to the module's default export          |
| Namespace imports   | `import * as ns from "./lib.ts"` — `ns.foo` rewrites to `lib_foo`                     |
| Type-only imports   | `import type { Foo } from "./lib.ts"` — stripped                                      |
| Side-effect imports | `import "./lib.ts"`                                                                   |
| Named re-exports    | `export { foo } from "./lib.ts"` — bubbles `lib_foo` into this module's export map    |
| Wildcard re-exports | `export * from "./lib.ts"` — all of lib's exports become this module's exports        |
| Default exports     | `export default function foo()` — exposed as `"default"` in the export map            |
| Chained imports     | lib A imports lib B imports lib C — resolved recursively                              |
| Name mangling       | Same-named symbols across modules are prefixed: `lib_foo`, `other_foo` — no collision |
| Deduplication       | Circular / duplicate imports are silently resolved (first occurrence wins)            |

---

#### Memory

| Feature                 | Notes                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Bump allocator          | `$__malloc(size: i32): i32` — advances `$__heap_ptr` and returns the old value                                                 |
| Heap start              | Initialized immediately after the static data section; at least 1 extra 64 KB page reserved                                    |
| Dynamic array layout    | `[length: i32][capacity: i32][elem0][elem1]...` — 8-byte header precedes element data                                          |
| Initial capacity        | `max(initialLength × 2, 8)` elements pre-allocated; grows automatically on overflow (`cap × 2` realloc via `$__dynarr_grow_T`) |
| Unused-code elimination | Binaryen `-Oz` strips `$__malloc` and unused array helpers from the binary automatically                                       |

#### Classes

| Feature                    | Notes                                                                                                                                                                                                   |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Class declarations         | `class Foo { field: i32; ... }` — fields desugared to fixed struct layout                                                                                                                               |
| Constructor                | `constructor(params) { }` → `Foo_constructor(__self: i32, params)`                                                                                                                                      |
| Instance methods           | `method(): retType { }` → `Foo_method(__self: i32)` — `this` maps to `local.get $__self`                                                                                                                |
| Static methods             | `static method(params): retType { }` → `Foo_method(params)` — no hidden param                                                                                                                           |
| Static fields              | `static count: i32 = 0` → named WASM global `$Foo_count`; read as `Foo.count`, written as `Foo.count = val` from any context including constructors and static methods                                  |
| Getters                    | `get prop(): T { }` → `Foo_get_prop(__self: i32): T`; `instance.prop` (no parens) dispatches to getter in expression, statement, and `console.log` contexts                                             |
| Setters                    | `set prop(val: T) { }` → `Foo_set_prop(__self: i32, val: T)`; `instance.prop = val` dispatches to setter                                                                                                |
| `this.field` read/write    | Load/store at field offset from `__self` pointer; getter/setter dispatch checked first                                                                                                                  |
| `new Foo(args)`            | Allocates struct in linear memory (static); calls constructor                                                                                                                                           |
| `instance.method(args)`    | Dispatches to `Foo_method(instancePtr, args...)`                                                                                                                                                        |
| `Foo.staticMethod(args)`   | Dispatches to `Foo_staticMethod(args...)`                                                                                                                                                               |
| `instance.field`           | Field read/write via instance pointer in classVars; getter/setter checked before raw load/store                                                                                                         |
| Class instance params      | Functions accepting `obj: Foo` receive an `i32` struct pointer                                                                                                                                          |
| `class Dog extends Animal` | Field layout inheritance — parent fields prepended at their original offsets; derived fields start at parent's `totalSize`; multi-level chains supported                                                |
| `super(args)`              | In the derived constructor body, calls the parent constructor: `(call $Animal_constructor (local.get $__self) args...)`                                                                                 |
| Method overriding          | `speak()` in Dog overrides Animal's `speak()`; concrete-type variables dispatch statically; `arr[i].method()` on base-typed arrays dispatches at runtime via class tag read (4-byte header at offset 0) |
| Class type tags            | When any `extends` is present, every class in the file gets a 4-byte integer tag header at offset 0 of each instance                                                                                    |

#### TypedArrays

All eight typed array types from the JavaScript standard library are supported. Each uses an 8-byte
header `[length i32, 0 i32]` followed by typed element data.

| Feature                    | Notes                                                                                                                                                                 |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Construction               | `new Int32Array(n)` — literal length; `new Int32Array(runtimeVar)` — runtime length; `new Int32Array([1, 2, 3])` — literal initializer (data segment + `memory.copy`) |
| Supported types            | `Int8Array`, `Uint8Array`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array`                                                   |
| Element access             | Typed read/write (`i32.load8_u`, `i32.load`, `f64.load`, etc.) at `ptr+8+idx*bytesPerElem`                                                                            |
| `.length`                  | `i32.load ptr` — count of elements                                                                                                                                    |
| `.byteLength`              | `length × bytesPerElem`                                                                                                                                               |
| `.fill(val, start?, end?)` | Range fill via WAT helper `$__ta_fill_T`; bounds clamped                                                                                                              |
| `.set(src, offset?)`       | Element copy via WAT helper `$__ta_set_T`                                                                                                                             |
| TypedArray parameters      | `function f(arr: Int32Array)` — registered as i32 pointer with correct load/store ops                                                                                 |
| `console.log`              | `Int32Array(4) [ 1, 2, 3, 4 ]`-style output                                                                                                                           |

#### Advanced Type System Features

| Feature                   | Syntax / Notes                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Discriminated union types | `type Shape = { kind: "circle"; r: f64 } \| { kind: "rect"; w: f64; h: f64 }` — flat super-struct layout; `switch (s.kind)` and `if (s.kind === "circle")` compile to integer tag comparisons                                                                                                                                                                                                                                       |
| Intersection types        | `type Widget = Nameable & Sizeable` — all fields merged into a flat struct; chained intersections (`A & B & C`) resolved in source order                                                                                                                                                                                                                                                                                            |
| Type predicates           | `function isCircle(s: Shape): s is Circle { ... }` — return type annotation; compile-time narrowing of `structVars` in if-branch scopes                                                                                                                                                                                                                                                                                             |
| `instanceof`              | `x instanceof Dog` — runtime class-tag check across an inheritance hierarchy (true for the class and any subclass); folds to a compile-time constant when the module has no inheritance. `if (x instanceof Dog)` narrows `x` to `Dog` in the then-branch (subclass fields/methods resolve); also works in `console.log`. Works at module scope and over arrays built with either `[new Sub(), …]` literals or `arr.push(new Sub())` |
| `typeof x`                | Compile-time evaluation: `typeof x === "number"` → `(i32.const 1/0)`; `const t: string = typeof x` → static string in data section; `console.log(typeof x)` → zero-overhead literal                                                                                                                                                                                                                                                 |
| `keyof T`                 | Source pre-pass rewrites `: keyof T` → `: string`; works in function params and variable declarations                                                                                                                                                                                                                                                                                                                               |
| Conditional types         | `type Toggle<T> = T extends i32 ? f64 : i32` (generic) and `type AlwaysI32 = f64 extends number ? i32 : string` (non-generic) — resolved entirely at compile time by `expandConditionalTypes()`                                                                                                                                                                                                                                     |
| `?.` optional chaining    | Stripped to `.` at compile time (safe for non-nullable types; nullable types use explicit `!== null` ternary)                                                                                                                                                                                                                                                                                                                       |
| `Number` constants        | `Number.NaN`, `Number.POSITIVE_INFINITY`, `Number.NEGATIVE_INFINITY`, `Number.EPSILON`, `Number.MAX_SAFE_INTEGER`, `Number.MIN_SAFE_INTEGER`, `Number.MAX_VALUE`, `Number.MIN_VALUE`                                                                                                                                                                                                                                                |
| `Number` predicates       | `Number.isNaN(x)`, `Number.isFinite(x)`, `Number.isInteger(x)` — compile-time expressions                                                                                                                                                                                                                                                                                                                                           |

#### Entry Point Patterns

Any of the following produces a WASI `_start` export in the compiled `.wasm`:

```typescript
// 1. Named main() + call
function main() { ... }
main();

// 2. Explicit _start export
export function _start() { ... }

// 3. IIFE (any function name)
(function run() { ... })();

// 4. Deno entry guard
if (import.meta.main) {
  // statements here become the _start body
}

// 5. Bare top-level statements
console.log("hello");   // any statement at module scope, not inside a function
```

Patterns 1–3 route through a named function that `_start` calls. Patterns 4–5 collect the statements
directly into the `_start` body. All five are recognized automatically — no annotation needed.

---

#### Current Limitations

`wasic` compiles a statically-typed TypeScript subset directly to WAT with no runtime. What it can't
express isn't a dead end — reach for the matching tool instead of a workaround:

| Not supported by `wasic`                                                        | What to use instead                                                                                                                                                       |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 3-D (and deeper) nested arrays `i32[][][]`                                       | `i32[][]` / `f64[][]` / `number[][]` **are** fully supported (incl. `Array.from({ length: N }, () => [])` init + type-coerced element reads); only 3-D+ nesting is unimplemented |
| `any` / `unknown` / `symbol` / generic `object`                                 | **`wasmtk dync`** (whole file), or `: any` / `eval(...)` inside a `wasic` program — both auto-merge the `wasmtk:dynrt` runtime                                            |
| Mapped types · template-literal types · complex recursive conditional types     | **`wasmtk dync`** — these need a full type checker, not a code generator                                                                                                 |
| Prototype / dynamic `this` · dynamic property bags · `eval` / `Function()`      | **`wasmtk dync`** — the whole-file dynamic runtime                                                                                                                       |
| A mostly-typed program with a few dynamic / `async` / `any` functions           | **`wasmtk hybrid`** — `// @wasm`-annotated (or, with `--auto`, every fully-typed) function compiles to a WASM core; the dynamic / `async` / `any` parts stay as host TS  |

> **Which tool?** `wasic` = the typed subset (smallest, fastest) · `wasmtk dync` = a fully-dynamic
> file (runs anything, interpreter-sized) · `wasmtk hybrid` = auto-split a mixed file. See
> [Choosing the Right Compiler](#choosing-the-right-compiler); the `⏳` rows in the
> [roadmap table](#wasmtk-toolkit-roadmap) list the specific types that require `dync`.

---

### `wasmtk dync` — Fully-dynamic TS/JS via the own runtime (the `javyc` replacement)

Compiles an **entire** dynamic TypeScript/JavaScript file to a **self-contained WASI module** by
running its whole source through wasmtk's own embedded dynamic runtime (the `wasmtk:dynrt`
interpreter). **No external Javy/QuickJS binary and no ~500 KB embedded engine** — the interpreter
is authored in the wasic subset and merged on demand, so only the dynamic-runtime capability is
bundled.

```bash
wasmtk dync myprogram.ts
wasmtk run myprogram.wasm      # or any WASI runtime — e.g. `wasmtime run myprogram.wasm`
```

**What it produces:** A self-contained, **pure-WASI** executable that interprets your whole program at
module start; `console.log`/`error`/`warn` print to stdout via WASI `fd_write`. It imports **only**
`wasi_snapshot_preview1`, so it runs unchanged on any standard WASI runtime — wasmtk's own `run`, and
also `wasmtime`, `wasmer`, `wazero`, WAMR, etc.

**Best suited for:**

- Fully-dynamic programs that `wasic` cannot compile statically (`any`, dynamic objects, `eval`,
  prototype-shaped code) — the interpreter covers the dynrt language subset
  (functions/closures/classes, the Array/String/Object/Math/JSON/Map/Set/RegExp stdlib, generators,
  async/await, and `console.log`).
- Prototyping dynamic code that should ship as one portable `.wasm` with no runtime dependency.

**How it differs from `wasic`:** `wasic` validates and lowers statically-typed TypeScript to
hand-tuned WAT (smallest, fastest). `dync` embeds the source and interprets it (larger,
interpreter-speed) but accepts fully-dynamic code. When a program is statically typeable, prefer
`wasic`; reach for `dync` when it isn't. If you run `wasmtk wasic` on a dynamic program it aborts and
points you here (`wasmtk dync <file>`); if the failure is a genuine error such as an undefined name,
it tells you to fix that first (the dynamic runtime would fail on it too). Both compilers are kept —
there is no silent fallback.

**Limitations:**

| Not handled by `dync`                      | Notes / what to do                                                                                                                                                             |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ESM `import` / `export` of _other_ modules | `dync` compiles a **single self-contained file** — inline your imports first with `wasmtk tsbundle`                                                                          |
| Interactive `prompt` / stdin               | the interpreter has no host stdin                                                                                                                                            |
| Size & speed                               | the whole program runs **interpreted** (larger, interpreter-speed) — if it's statically typeable prefer `wasic`, or **`wasmtk hybrid`** for a mix of typed + dynamic code    |

Everything else dynamic **is** supported — `any`, dynamic objects, closures, classes, `eval`,
generators, `async`/`await`, and the Array/String/Object/Math/JSON/Map/Set/RegExp stdlib. Output
parity with a real JS engine is enforced by `tests/dync_conformance_tests.ts` (byte-diff vs
`deno run`).

---

### `wasmtk modc` — WASM Library Module

Compiles a TypeScript file to a **WASM library module** — not a runnable WASI program. The output
contains only your exported functions, callable from any WASM host environment. Implemented in
`modc.ts` as a standalone module, parallel to `wasic.ts` and `dync.ts`.

```bash
wasmtk modc mylib.ts   # → mylib.wasm (call its exports with `wasmtk mod` — see Utility Options)
```

**What it produces:** A `.wasm` library (no `_start`, no WASI imports, no embedded runtime). Exports
are pure functions callable from any WASM host (browser, Node.js, Deno, another WASM module).

**Compilation pipeline:**

```text
.ts source
  → tsbundler   (import resolution, module-prefix name mangling)
  → WasicTranspiler in library mode   (TypeScript → WAT, no _start, no proc_exit)
  → @jrmarcum/wabt-ts wat2wasm   (WAT → raw WASM binary)
  → Binaryen -Oz   (dead-code elimination, size optimisation)
  → .wasm library
```

**Input requirements:**

The source file must contain at least one `export function` declaration. Top-level runner code
(main(), IIFE, console.log, top-level statements) is parsed but silently dropped — only exported
functions are callable from the host. Non-exported internal functions are included in the WAT but
eliminated by Binaryen -Oz if unreachable.

```typescript
// ✅ Valid modc source — supports the full wasic TypeScript subset
export function add(a: f64, b: f64): f64 {
  return a + b;
}

export function multiply(a: f64, b: f64): f64 {
  return a * b;
}
```

**Supported types:** The full wasic subset — `i32`, `i64`, `f32`, `f64`, `number` (→ `f64`),
`boolean`, `string`, arrays, structs, generics, classes, exceptions, and all completed phases. No
AssemblyScript toolchain required.

**Best suited for:**

- Reusable numeric or computational libraries consumed by a JS/TS host
- Browser-side WASM where you call specific functions from JavaScript
- Interop scenarios where WASM functions are invoked by name from outside
- Replacing performance-critical JS functions with fast WASM equivalents

**Key distinction from `wasic` and `dync`:**

- `modc` output is **not a standalone program** — it has no entry point and cannot be run as a WASI
  process
- The module is **imported and called** by a host environment rather than executed independently
- It compiles the **same TypeScript subset as `wasic`** — in fact it *is* the wasic transpiler in
  library mode — so the same [Current Limitations](#current-limitations) apply verbatim.

**What to reach for when `modc` can't compile something** (the fallback differs from `wasic`):

- **`dync` is _not_ a `modc` alternative** — a `dync` module is a runnable WASI command with **no
  exports**, not a callable library. Compiling a fully-dynamic file with `dync` gives you a program
  to _run_, not a library to _import_.
- For a **library that mixes typed and dynamic code**, use **`wasmtk hybrid`**: it builds the typed
  core with `modc` (this exact path) and keeps the dynamic / `async` / `any` parts in a generated
  TypeScript host — so the callable, typed surface stays real WASM.

---

### `wasmtk hybrid` — TypeScript/WASM Split Compiler

Splits a mixed TypeScript file into a wasic-compiled WASM core and a TypeScript runner. Functions
annotated with `// @wasm` are compiled to a `.wasm` library; the rest stays as TypeScript with call
sites automatically rewritten to use the WASM binding.

```bash
wasmtk hybrid myapp.ts          # generates myapp_core.wasm, myapp_core.wit,
                                 # myapp_core.bindings.ts, myapp_runner.ts
wasmtk hybrid myapp.ts -o dist/ # write generated files to dist/
wasmtk hybrid myapp.ts --auto   # route by TYPE — no // @wasm annotations needed
```

**`--auto` (type-driven routing):** with `--auto`, every module-level named function whose
parameters and return type are all wasic-compatible (`i32`/`i64`/`f32`/`f64`/`bool`/`string`/
`number`/typed arrays) is routed to the WASM core automatically — no `// @wasm` needed. `async`
functions are routed too when they return `Promise<T>` with a wasic-compatible `T` (the core wraps
them in a synchronous unwrapping wrapper). `any`-typed, otherwise non-statically-typed, or
async-without-a-`Promise<T>`-annotation functions stay in the TypeScript host. `// @wasm` still
force-includes a function; `// @js` (or `// @host`) force-excludes one. Without `--auto`, the legacy
annotation mode is used (only `// @wasm` functions are extracted).

**Annotation syntax:**

```typescript
// @wasm
export function heavyCompute(n: i32): i32 {
  // This function is compiled to WASM
  let sum = 0;
  for (let i = 0; i < n; i++) sum += i;
  return sum;
}

// This stays as TypeScript
console.log(heavyCompute(1000)); // call site rewritten to lib.heavyCompute(1000)
```

**Five-step pipeline:**

1. Parse source → extract `// @wasm`-annotated functions
2. Write `_core.ts` with extracted functions (all `export`)
3. `modc` compiles `_core.ts` → `_core.wasm` + `_core.wit`
4. `bindgen` reads `_core.wit` → `_core.bindings.ts`
5. Write `_runner.ts`: remaining TypeScript + `import { loadModule }` +
   `const lib = await loadModule(...)` + rewritten call sites

**Async:** `async` functions returning `Promise<T>` are routed into the WASM core (the core wraps
each in a synchronous unwrapping wrapper so the host gets a real value). The awaited graph must be
self-contained / intra-module — an async function that awaits a host call still belongs in the
TypeScript runner.

**Limitations:**

| Constraint                                                       | Notes                                                                                                                          |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Only named `function` declarations route to WASM                | arrow functions and class methods stay in the TypeScript host (they aren't extracted)                                        |
| `async` functions need a `Promise<T>` return annotation         | without it the inner type can't be inferred, so the function stays in the host                                               |
| Routed functions must fit the `wasic` subset                    | a `// @wasm` function using unsupported types errors at compile time — see wasic's [Current Limitations](#current-limitations) |
| Module-level shared mutable state doesn't cross the boundary    | state read/written by **both** WASM and host code is duplicated — expose it via exported getter/setter functions             |
| A `@wasm` function that calls a non-`@wasm` TS function          | needs a manual `declare const` import stub (external interface mapping) added to the core module                             |
| Call-site rewriting is scanner-based (not a full AST parse)     | robust in practice — skips strings/comments/regex/member-access/method-shorthand and rewrites inside `${…}` interpolations   |

---

## Choosing the Right Compiler

| Need                                                      | Use               |
| --------------------------------------------------------- | ----------------- |
| Run a standalone program with WASI I/O                    | `wasic` or `dync` |
| Maximum performance, minimal binary size                  | `wasic`           |
| Multi-file TypeScript project with local imports          | `wasic`           |
| Fully-dynamic code (`any`, dynamic objects, `eval`)       | `dync`            |
| Export functions for use from JavaScript/browser          | `modc`            |
| Numeric/systems code, tight loops, DSP, crypto            | `wasic`           |
| Existing dynamic JS/TS that `wasic` can't type statically | `dync`            |
| WASM library for Deno/Node/browser consumption            | `modc`            |
| Combine multiple `.wasm` files into one library           | `wasmbundle`      |
| Distribute a set of compiled modules as a single artifact | `wasmbundle`      |
| Generate TypeScript bindings from a WIT interface         | `bindgen`         |
| Convert JS library to typed wasic-compatible TypeScript   | `jstyper`         |
| Speed up a TS program — move hot typed functions to a WASM core | `hybrid`     |
| A mostly-typed program with a few dynamic / `async` / `any` functions | `hybrid` |
| A callable **library** that mixes typed + dynamic code (not `dync` — it makes a program, not a library) | `hybrid` |

---

## 🧰 Utility Options

Supporting commands that round out the toolkit — combine compiled modules, turn JavaScript into
typed TypeScript, generate typed host bindings, run WebAssembly spec-conformance scripts, and
execute compiled modules in any supported format.

---

### `wasmtk wasmbundle` — Multi-WASM Bundler

Merges multiple pre-compiled `.wasm` files into a **single combined `.wasm` library** — no
TypeScript source required. Useful for packaging independently compiled modules for distribution as
one artifact.

```bash
wasmtk wasmbundle math.wasm utils.wasm --name combined.wasm
wasmtk wasmbundle math1.wasm math2.wasm --on-conflict=prefix
wasmtk wasmbundle math1.wasm math2.wasm --alias math1.wasm=m1,math2.wasm=m2 --on-conflict=alias
```

**What it produces:** A `.wasm` library with all exported functions from every input module.
Internal WAT symbol names are always mangled for uniqueness (`$mathlib_add`); exported names are
always the original clean names (`"add"`) so consumers see a predictable public API.

**Best suited for:**

- Distributing multiple WASM modules as a single file
- Combining `modc`-compiled libraries for a consumer who only wants one import
- Packaging platform-specific WASM alongside shared utilities
- Reducing load overhead when a host needs functions from several modules

See [Phase 19 — `wasmbundle` CLI](#phase-19--wasmbundle-cli) and
[Phase 20 — Export Name Transparency](#phase-20--export-name-transparency) for full pipeline and
conflict resolution details.

---

### `wasmtk mod` — Call a Function in a WASM Library

Invokes an exported function of a compiled `.wasm` library straight from the command line — no host
code needed. Pass a function name and arguments to call that export and print the result; pass no
function name to list the module's callable exports. Works on any library built by `modc` — the ABI
is the same across producers (TypeScript, Go, Zig, Rust).

```bash
wasmtk mod mylib.wasm                   # list the module's exported functions
wasmtk mod mylib.wasm myFunction 42     # call an export directly (TypeScript library via modc)
wasmtk mod mylib/mylib.wasm add 2 3     # → prints 5   (Go library via modc --lang=go)
wasmtk mod myzig/myzig.wasm add 2 3     # → prints 5   (Zig library via modc --lang=zig)
```

---

### `wasmtk info` — Inspect a Module's Exports

Prints the callable functions of a `.wasm` or `.wat` library/module (names + signatures) without
running anything — handy to discover what a module exposes before calling it with `mod` or binding
it with `bindgen`.

```bash
wasmtk info mylib.wasm
wasmtk info mylib.wat
```

---

### `wasmtk wasm2js` — WASM → JavaScript

Converts a `.wasm` module into a `.js`-based script (via Binaryen's `wasm2js`), for environments
that can't instantiate WebAssembly directly. Defaults the output to the input name with a `.js`
extension; override with `-o`.

```bash
wasmtk wasm2js mymodule.wasm            # → mymodule.js
wasmtk wasm2js mymodule.wasm -o out.js  # custom output path
```

---

### `wasmtk convert` — WASM ↔ WAT

Round-trips between the binary and text WebAssembly formats, choosing the direction from the input
extension: `.wasm` → `.wat` (disassemble) and `.wat` → `.wasm` (assemble). Override the output path
with `-o`.

```bash
wasmtk convert mymodule.wasm            # → mymodule.wat  (disassemble)
wasmtk convert mymodule.wat             # → mymodule.wasm (assemble)
```

---

### `wasmtk jstyper` — JS + .d.ts to Typed TypeScript

Converts an existing JavaScript file and its `.d.ts` type declaration into a typed TypeScript file
that `wasic` can compile. Bridges existing JS libraries into the WASM pipeline without requiring a
TypeScript rewrite.

```bash
wasmtk jstyper mylib.js                    # reads mylib.js + mylib.d.ts → mylib.ts
wasmtk jstyper mylib.js --dts-only         # generate skeleton mylib.d.ts for hand-editing
wasmtk jstyper mylib.js --dry-run          # preview output without writing files
wasmtk jstyper mylib.js --any-policy=skip  # exclude functions with 'any' typed params
```

**What it produces:** A `.ts` file with every JS function body combined with the matching typed
declaration from `.d.ts`. The output is a valid wasic input file.

**`--any-policy` modes:**

| Mode             | Behavior                                                               |
| ---------------- | ---------------------------------------------------------------------- |
| `warn` (default) | `any` mapped to `i32`; warning with corrected declaration suggestion   |
| `skip`           | Functions with `any`-typed params or returns excluded; warning emitted |
| `default`        | `any` mapped to `i32` silently, no warnings                            |

---

### `wasmtk bindgen` — TypeScript Host Binding Generator

Reads a `.wit` interface file (generated automatically by `wasic`/`modc` alongside every compiled
module) and generates a self-contained TypeScript binding file with full ABI translation. No manual
`WebAssembly` API usage required in the host.

```bash
wasmtk bindgen mylib.wit                         # generates mylib.bindings.ts (Deno)
wasmtk bindgen mylib.wit --runtime node          # Node.js host loader
wasmtk bindgen mylib.wit --runtime bun           # Bun host loader
wasmtk bindgen mylib.wit -o path/to/binding.ts   # custom output path
```

**What it produces:** A `mylib.bindings.ts` file with:

- `ModuleExports` interface — typed exports for every WIT export
- `ModuleImports` interface — host callbacks for every WIT import (when present)
- `loadModule(source, imports?)` async function — loads the `.wasm` and returns a typed proxy

**Example usage of the generated binding:**

```typescript
import { loadModule } from "./mylib.bindings.ts";
const lib = await loadModule("./mylib.wasm");
console.log(lib.add(2, 3)); // number
console.log(lib.greet("world")); // string
console.log(lib.isEven(4)); // boolean
```

**ABI translation (Canonical ABI):**

| WIT type                      | Host JS type | Encoding                                                                                                         |
| ----------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------- |
| `s32` / `s64` / `f32` / `f64` | `number`     | Direct passthrough                                                                                               |
| `bool`                        | `boolean`    | params: `v ? 1 : 0`; returns: `result !== 0`                                                                     |
| `string` (param)              | `string`     | `TextEncoder` → `cabi_realloc` → ptr+len WASM args                                                               |
| `string` (return)             | `string`     | export returns an i32 ptr to a callee-allocated `[ptr,len]` pair; `TextDecoder` from it, then `cabi_post_<name>` |

---

### `wasmtk wast` — WebAssembly `.wast` spec-script conformance runner

Run the WebAssembly `.wast` _script_ format (a superset of `.wat` that interleaves `(module …)`
definitions with assertions — the format the official spec conformance testsuite is written in):

```bash
wasmtk wast path/to/file.wast                 # run one .wast file's assertions
wasmtk wast tests/module/wasm_wast/testsuite-main   # run a whole directory tree
wasmtk wast file.wast --verbose               # show skip/toolchain-gap detail
```

It splits the script into commands, assembles each module with the WABT backend, instantiates it on
the host engine with the standard `spectest` imports + a `register` link registry, and executes the
`assert_return` / `assert_trap` / `assert_invalid` / `assert_malformed` / `assert_unlinkable` /
`invoke` / `get` directives — comparing results bit-exactly (i32 as uint32, i64 as BigInt, f32/f64
by bits incl. `nan:canonical`/`nan:arithmetic` and hex-float literals). Exit code is non-zero if any
**execution** assertion fails. Assertions using out-of-scope value types (`v128`, `ref.*`) or
unsupported proposals, and validation assertions the toolchain doesn't reject, are reported as
**skipped**.

### `wasmtk run` — Multi-Format Executor

Runs a file directly. Accepts four input formats:

| Input   | Behavior                                                                                  |
| ------- | ----------------------------------------------------------------------------------------- |
| `.wasm` | Instantiates and executes the WASM module via the built-in WASI runtime                   |
| `.wat`  | Assembled by `@jrmarcum/wabt-ts`, then executed as above                                  |
| `.ts`   | Passed through to the Deno/Bun runtime (`deno run -A` / `bun run`) — not compiled to WASM |
| `.js`   | Same passthrough to the Deno/Bun runtime                                                  |

```bash
wasmtk run myprogram.wasm
wasmtk run myprogram.wat
wasmtk run myprogram.ts
wasmtk run myprogram.js
```

The `.ts` and `.js` paths are native runtime passthrough — they do not go through wasic or any WASM
compilation step. Use them to run a TypeScript file as-is for comparison against its compiled WASM
output.

---

## Programmatic API

Each compiler is a standalone importable module. You can use them directly in Deno without going
through the CLI:

```typescript
import { compileLibTs, compileWasi, compileWasiTs } from "@jrmarcum/wasmtk/wasic";
import { compileModule } from "@jrmarcum/wasmtk/modc";
import { compileDyn } from "@jrmarcum/wasmtk/dync";
import { bundleImports } from "@jrmarcum/wasmtk/tsbundler";
import { runWasmBundle } from "@jrmarcum/wasmtk/wasmbundle";
import { extractExportNames, mergeWasmWat } from "@jrmarcum/wasmtk/wasmmerge";
import {
  generateTypedTs,
  parseDtsFunctions,
  parseJsFunctions,
  runJstyper,
} from "@jrmarcum/wasmtk/jstyper";
import { generateBindings, parseWit, runBindgen } from "@jrmarcum/wasmtk/bindgen";
import { runHybrid } from "@jrmarcum/wasmtk/hybrid";
```

| Export                                              | Module         | Description                                                                                      |
| --------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------ |
| `compileWasi(path, outPath?)`                       | `./wasic`      | Compile `.ts` or `.wat` to a WASI standalone `.wasm`                                             |
| `compileWasiTs(path, outPath?)`                     | `./wasic`      | TypeScript-only path — runs bundler + transpiler + optimizer                                     |
| `compileLibTs(path, outPath?)`                      | `./wasic`      | TypeScript → WASM library (no `_start`, no WASI scaffolding)                                     |
| `compileWat(path, outPath?)`                        | `./wasic`      | WAT-only path — `@jrmarcum/wabt-ts` parse + Binaryen `-Oz`                                       |
| `compileModule(path, outPath?)`                     | `./modc`       | Compile `.ts` to a WASM library via wasic transpiler                                             |
| `compileDyn(path, outPath?)`                        | `./dync`       | Compile a fully-dynamic `.ts`/`.js` file to a self-contained WASI module via the own runtime     |
| `bundleImports(entryPath)`                          | `./tsbundler`  | Resolve and merge relative imports into a single source string                                   |
| `runWasmBundle(inputs, out, onConflict?, aliases?)` | `./wasmbundle` | Bundle multiple `.wasm` files into a single `.wasm` library                                      |
| `mergeWasmWat(wat, prefix, dataReloc, overrides?)`  | `./wasmmerge`  | Merge one WAT module into a parent with prefix mangling and data relocation; returns `exportMap` |
| `extractExportNames(wat)`                           | `./wasmmerge`  | Return bare export names from a WAT module (for conflict detection)                              |
| `runJstyper(path, opts)`                            | `./jstyper`    | CLI entry point — convert `.js` + `.d.ts` to typed `.ts`                                         |
| `parseJsFunctions(src)`                             | `./jstyper`    | Extract function definitions from JS source; returns `JsFuncDef[]`                               |
| `parseDtsFunctions(dts)`                            | `./jstyper`    | Extract typed signatures from `.d.ts` source; returns `DtsFuncDef[]`                             |
| `generateTypedTs(jsFns, dtsFns, anyPolicy)`         | `./jstyper`    | Merge bodies + types into a wasic-compilable `.ts` string                                        |
| `runBindgen(witPath, opts)`                         | `./bindgen`    | CLI entry point — generate TypeScript bindings from a `.wit` file                                |
| `parseWit(src)`                                     | `./bindgen`    | Parse a WIT file into `ParsedWit` (exports, imports, types)                                      |
| `generateBindings(witSrc, opts)`                    | `./bindgen`    | Generate the full TypeScript binding file as a string                                            |
| `runHybrid(path, opts)`                             | `./hybrid`     | CLI entry point — split a `.ts` file into WASM core + TS runner                                  |

---

## 🌐 Producers & Backends

wasmtk isn't limited to its built-in TypeScript compiler — it drives **other source languages**
through the same downstream pipeline (WABT assemble → Binaryen `-Oz` → run / merge). Every producer
shares the **same verbs**, so muscle memory carries across languages:

| Verb | Scaffolds / builds | `--lang` |
| --- | --- | --- |
| `init` | a WASI **program** project (an entry point you can run/build) | **required** |
| `initmod` | a wasm **library** project (exported functions, no entry point) | **required** |
| `build` | the WASI program → a standalone `.wasm` (no run) | optional¹ |
| `modc` | the wasm library → a `.wasm` (callable via `wasmtk mod`) | optional¹ |
| `run` | build + run the WASI program | optional¹ |

¹ **`run` / `build` / `modc` auto-detect the language from the target** — a `.go` / `.zig` / `.rs`
file, or a directory containing `go.mod` / `Cargo.toml` — so `--lang` is optional for them (only
needed to force a bare current directory). `init` / `initmod` scaffold from nothing, so they always
take `--lang`.

The Go producer additionally exposes a `--go-runtime` **backend** switch (TinyGo vs. the standard Go
toolchain), and Rust adds a few dependency/cache verbs (`add`/`remove`/`list`/`fmt`/`clean`) via
`rsxtk`. Reach for a producer when your source is Go, Zig, or Rust rather than TypeScript.

---

### `--lang=go` — Go Producer (TinyGo)

Compiles **Go** to wasm and runs it through the same downstream as every other producer. It uses the
**same verbs as every producer** (`init`/`initmod`/`build`/`modc`/`run`; the path argument defaults
to the current directory): `init` scaffolds a WASI **program**, `initmod` a wasm **library**. The
scaffolded `main.go` includes a commented `//go:wasmexport` example (library) or a `func main`
(program), so the right shape is shown from the start:

```bash
wasmtk init    --lang=go myapp     # scaffold a WASI PROGRAM project (func main); then cd myapp
wasmtk initmod --lang=go mylib     # scaffold a wasm LIBRARY project (//go:wasmexport funcs)
wasmtk run   hello.go              # build a single .go file → WASI module and run it (lang auto-detected)
wasmtk run   ./mypkg               # a directory containing a go.mod is auto-detected too
wasmtk run   hello.go --go-runtime=std           # standard Go toolchain instead of TinyGo
wasmtk build hello.go              # build the WASI program → standalone .wasm (no run; auto-detected)
wasmtk modc  mylib.go              # build the wasm LIBRARY (auto-detected; call exports via wasmtk mod)
wasmtk modc  mylib.go --go-target=wasm-unknown   # build an alloc-free MERGEABLE leaf library
```

**Backends (`--go-runtime`):**

- **`tinygo`** (default) — small output. TinyGo runs binaryen's `wasm-opt` internally. If a real
  `wasm-opt` is on your `PATH` (or `$WASMOPT`), wasmtk lets TinyGo use it. If it's **not**
  installed, wasmtk transparently substitutes a passthrough and runs the **in-house binaryen-ts
  Asyncify + `-Oz`** pipeline instead, so **no external binaryen is required — including for
  goroutines** (binaryen-ts's asyncify pass resolves TinyGo's in-wasm `asyncify.*` control API). Set
  `WASMTK_GO_BINARYEN_ASYNCIFY=1` to force the in-house path even when a real `wasm-opt` is present.
- **`std`** — uses the standard Go toolchain (`GOOS=wasip1 GOARCH=wasm go build`). No `wasm-opt`
  needed, but pulls in the full Go runtime/GC (large, multi-MB binaries).

**Prerequisites:** [TinyGo](https://tinygo.org/getting-started/install/) (for the default backend)
and the [Go toolchain](https://go.dev/dl/) (for `--go-runtime=std`).

**Scope (v1):** command-mode Go (`func main()`) plus the library/reactor build (`modc --lang=go`,
`//go:wasmexport`) with numeric exports. Go string/slice/aggregate **host bindings** (`bindgen`) are
planned — see the roadmap.

### `--lang=zig` — Zig Producer

Compiles **Zig** through the same downstream as the other producers (shells to `zig`; no extra deps
— `zig` self-optimizes, with a binaryen-ts `-Oz` pass on libraries). Same shape as Go:

```bash
wasmtk init    --lang=zig myzig    # scaffold a WASI PROGRAM main.zig (pub fn main)
wasmtk initmod --lang=zig myzig    # scaffold a wasm-LIBRARY main.zig (export fn + a test main)
wasmtk run   main.zig              # build a wasm32-wasi program and run it (lang auto-detected)
wasmtk build main.zig              # build the WASI program → standalone .wasm (no run; auto-detected)
wasmtk modc  main.zig              # build a wasm library (freestanding; exports your 'export fn's)
```

`init` scaffolds a WASI **program** (`pub fn main`); `initmod` scaffolds a wasm **library** — your
`export fn`s plus a `pub fn main` test harness (the `main` is comptime-guarded to the WASI target, so
it's excluded from the freestanding `modc` library build). `run`/`build`/`modc` auto-detect from a
`.zig` file, so `--lang=zig` is only needed for a project directory or bare cwd. Mark library
functions with Zig's `export fn` keyword. **Prerequisite:** [Zig](https://ziglang.org/download/).

### `--lang=rust` — Rust Producer (via rsxtk)

The Rust producer **delegates to [`rsxtk`](https://crates.io/crates/rsxtk)** — the Rust WASM toolkit
(install with `cargo install rsxtk`). Rust is the model the shared producer verbs follow —
`init` = WASI program, `initmod` = wasm library, `build` = program → `.wasm`, `modc` = library →
`.wasm` — with a few Rust-only extras (dependency + cache management):

```bash
wasmtk init    --lang=rust myprog   # scaffold a Rust wasi script (with main)
wasmtk initmod --lang=rust mylib    # scaffold a Rust library module (#[no_mangle] exports)
wasmtk run   myprog.rs              # build + run a wasi program (lang auto-detected)
wasmtk build myprog.rs              # build a wasi program → .wasm (auto-detected)
wasmtk modc  mylib.rs               # build a wasm library → .wasm (auto-detected)
wasmtk add serde                    # manage dependencies (also: remove, list) — Rust-only
wasmtk fmt                          # inject a manifest where missing
wasmtk clean                        # wipe the .tk build cache
```

**Prerequisites:** [`rsxtk`](https://crates.io/crates/rsxtk) on PATH, plus
`rustup target add wasm32-wasip1`. `run`/`build`/`modc` auto-detect from a `.rs` file or a
`Cargo.toml` directory (so `--lang` is optional there); the Rust-only extras
(`add`/`remove`/`list`/`fmt`/`clean`) are implicitly Rust — no `--lang` needed either, since no other
producer uses them. (WIT/bindgen for Rust output remains wasmtk's job and is planned.)

---

## wasmtk Toolkit Roadmap

The toolkit is developed incrementally. Core phases build out the `wasic` TypeScript compiler; later
phases extend the toolchain with bundling and distribution capabilities.

### Feature Status

> **Legend:** ✅ shipped · ⏳ planned, or blocked on an upstream WASM proposal. **Incomplete items
> (⏳ — to-do / planned / blocked) are always listed at the end of the table**, after every ✅ row.
> Worked examples for each feature live in its command section above; deep implementation notes live
> in [`cmem/`](cmem/). Test-count taglines in the table are historical snapshots — the current suite
> is green (`tests/wasi/wasm_wasi` 400/400) on `jsr:@jrmarcum/wabt-ts` + `jsr:@jrmarcum/binaryen-ts`,
> with all 50 wasic phases, Stage 0/0.6/0.7, and the five Tier-1 stdlib capabilities
> (Set/Map/Date/JSON/RegExp) shipped.

| Complete | Phase | Feature | Highlights |
| :---: | --- | --- | --- |
| ✅ | Core | Functions, variables, control flow | `function`, `let`/`const`/`var`, `if`/`else`, `while`, `do-while`, `for` |
| ✅ | Core | Operators | Arithmetic, comparison, logical, bitwise, ternary, compound assignment |
| ✅ | Core | Switch / labeled break / continue | `switch/case`, `outer: for(...) { break outer; }` |
| ✅ | Core | Numeric types | `i32`, `i64`, `f32`, `f64`, `boolean`, BigInt literals (`42n`), numeric enums |
| ✅ | Core | Strings | Literals, `.length`, lexicographic comparisons, template literals |
| ✅ | Core | Console output | `console.log/error/warn` — mixed-type args, numbers, strings, BigInt, templates |
| ✅ | Core bug fix (2026-07-29) | `console.log` arithmetic starting with a number or `(` failed to compile | `console.log("x:", 1 + n)` and `console.log("x:", (n + 0) * 5)` failed to instantiate for integer variables, while the equivalent `n + 1` worked — a leading literal or parenthesis left the expression mis-typed as floating-point. Both now compile; `1.5 + n` still means floating-point |
| ✅ | 5b | Default parameters | `function f(x: i32 = 0)` |
| ✅ | 5c | Optional parameters | `function f(x?: i32)` |
| ✅ | 5e | First-class functions | funcref table, `call_indirect`, named arrow variables, callbacks, closure capture, IIFE entry pattern, nested closures, void arrows, mixed-signature branches; bug fix: type annotation declarations (`let f: (a) => b`) correctly skipped by arrow-substitution pass |
| ✅ | 5f | Heap-allocated closures | Closure factories — functions that `return (params) => expr` produce a heap struct `{table_idx, captures...}`; `factoryFn(a)(b)` dispatches via a generated trampoline (`$fn__trampoline`); supported in `console.log` args and all expression/statement contexts |
| ✅ | 5g | Closures as first-class values | Named function-type aliases; inline capturing arrows heap-allocated as `__anon_N__factory`; closure pointer dispatch via `closureTypedVars` + trampoline; bug fix: outer-scope regex extended to match array types (`i32[][]`) so 2D-array captures are detected correctly |
| ✅ | 5h | Shared mutable captures (heap-boxing) | `return { inc: () => { count++; ... }, dec: () => { count--; ... } }` — variables captured by 2+ closures in a `return { ... }` object literal AND mutated by any of them are heap-boxed: factory allocates a 4-byte cell, stores the initial value, passes the pointer to every closure factory; reads emit `(i32.load (local.get $ptr))`; mutations (`count++`, `count--`, `count += x`, `count = x`) emit load-modify-store through the cell pointer |
| ✅ | 6a | Numeric arrays | `i32[]`, `f64[]` — static allocation, element read/write, `.length`, array params |
| ✅ | 6b | Structs / objects | `interface` and `type` as fixed-layout structs, field read/write, struct params |
| ✅ | 6c | Object destructuring | `const { x, y } = vec` → `i32.load` / `f64.load` at field offsets; renamed destructuring |
| ✅ | 6d | Multi-dimensional arrays | `i32[][]` — nested dynamic arrays; `const m: i32[][] = [[1,2],[3,4]]` allocates outer + inner row arrays; `m[i].push(val)` updates slot after possible row growth; `console.log(m)` prints Deno-format `[ [ 1, 2 ], ... ]` |
| ✅ | 8 bug fix (2026-07-28) | Multi-file struct imports (`import { Vec2 } from "./vec.ts"`) | Importing an `interface`/`type` from another file failed to compile — every field access on it reported *unsupported expression*. Struct types were recognized by a PascalCase spelling rule, but the bundler prefixes imported names with the module's lower-case filename (`Vec2` in `vec.ts` → `vec_Vec2`), so bundled types were never registered. Struct types are now recognized by the type registry, so any valid type name works — including hand-written lower-case ones like `interface point`. Regression `12_LowercaseStructTypeName`; fixes the `StructImport` bundle test |
| ✅ | 12b | Interface dispatch | `interface` types used as return values + method call sites: `createManager()` returns a struct of closure ptrs; `manager.addRow([6])` dispatches via `call_indirect` trampoline pattern; `stats.length` on i32 dynamic-array locals in `console.log`; `return { key: fn }` object literal emits interface struct with factory closure ptrs; trivial closures (no captures) auto-wrapped in a 4-byte `{table_idx}` mini-closure so dispatch is uniform |
| ✅ | 7a | Math intrinsics | `Math.sqrt/abs/pow/floor/ceil/round/min/max/sign/trunc` → native WASM ops |
| ✅ | 7b | Stderr output | `console.error` / `console.warn` → WASI fd=2 |
| ✅ | 8 | Import bundler (`tsbundler.ts`) | Relative import resolution, module-prefix name mangling, alias (`as`) rewriting, chained imports, deduplication |
| ✅ | 9 | Classes | `class` declarations desugared to struct layout + `ClassName_method` prefixed functions; `this` → hidden `__self: i32` param; `new ClassName()` → static alloc + constructor call; instance/static method dispatch; dot-call expressions in `console.log` args |
| ✅ | 10a | Bump allocator | `$__heap_ptr` mutable global initialized to end of static data; `$__malloc(size)` advances and returns old ptr; 1 extra memory page reserved; Binaryen -Oz strips it when unused |
| ✅ | 10b | Dynamic arrays | `push` / `pop` / `shift` / `unshift` on `i32[]` and `f64[]`; heap layout `[length i32][capacity i32][elem...]`; auto-detected by pre-scan; per-type WAT helpers emitted on demand; capacity = `max(n × 2, 8)` |
| ✅ | 10c | Dynamic array growth | `push` / `unshift` grow on overflow: `$__dynarr_grow_T` mallocates new block (`cap × 2`), copies elements, returns new ptr; helpers return new array ptr so callers `local.set` their pointer; old block becomes dead memory (bump allocator has no free) |
| ✅ | 11 | String operations | `str + str` concat (chained, heap-allocated); `str.slice(start, end)` (sub-range, no alloc); `str.indexOf(sub)` → i32; `str.includes(sub)` → bool; `String(n)` / `n.toString()` (number-to-string via heap); gather-buffer mode in `console.log` extended to handle string and bool variables |
| ✅ | 12 | Array methods | `arr.indexOf(val)` → i32; `arr.includes(val)` → bool; `arr.slice(start, end)` → new array; `arr.forEach(fn)`; `arr.map(fn)` → new array; `arr.filter(fn)` → new array; `arr.find(fn)` → element or sentinel (-1/NaN); `arr.reduce(fn, init)` → value; dynamic arrays only; `const r: T[] = arr.map(fn)` pattern supported; `findDynamicArrays` extended to auto-detect arrays used with Phase 12 methods; `findResultVars` tracks variables assigned from `.find()` — `console.log` of those variables emits a sentinel check and prints `undefined` when not found, matching TypeScript semantics |
| ✅ | 13 | Rest parameters / spread | `function f(...args: i32[])` — rest param receives heap array pointer; literal call sites build temp array via `$__malloc`; `f(...arr)` passes existing dynamic array pointer directly; `[...a, ...b]` concat via `$__dynarr_concat_T`; spread-source arrays auto-promoted to dynamic layout by `findDynamicArrays` |
| ✅ | 13b | `console.log` of struct-returning calls | `console.log(tryDivide(10, 2))` where `tryDivide` returns an interface type prints `{ value: 5, hasError: 0 }` — struct pointer stored to `$__struct_tmp`, fields loaded by offset and formatted as `{ fieldName: value, ... }`; `$__struct_tmp` local injected by pre-scan of `_start` and `emitFunction` body lines; `LogSegment` array built directly in `emitStatement` and passed to `emitConsoleLog` |
| ✅ | bug fix | `console.log` of array-returning calls | `console.log("scores:", getScores())` where `getScores(): i32[]` was printing the raw heap pointer; fix: `FuncLookup` now exposes `resultTsName`; `parseSingleArg` checks for `[]` suffix → new `arrptr` LogSegment; gather mode calls `$__write_i32arr_to_scratch` which loops the dynamic-array header and writes `[ a, b, c ]`; `getArrPrintHelperWat()` emits the WAT helper; `wasic.ts` tracks `needsArrPrintHelper` flag |
| ✅ | 14 | Generics (monomorphization) | `function f<T>(x: T): T` — one concrete copy per distinct type; `interface Box<T> { value: T; }` → `Box_i32`, `Box_f64`, etc.; explicit type args (`f<i32>(x)`) and single-T literal inference (`f(42)` → `f_i32`); generic struct refs in function signatures rewritten automatically; source-level `expandGenerics()` pre-pass runs before all other parsing |
| ✅ | 15 | Exception handling | `throw new Error("msg")` / `throw "lit"` / `throw strVar` → `(throw $__exn_tag ptr len)` — WASM exception tag carries a `(ptr i32, len i32)` string payload; catchable by any enclosing `try/catch`; `try/catch(e)/finally` via WAT exceptions proposal; `(tag $__exn_tag (param i32 i32))` declared once per module when any throw is emitted; `e` / `e.message` in catch bound as string locals; the WAT-to-binary assembler (`@jrmarcum/wabt-ts`) accepts the exception proposal opcodes by default — no per-call feature flag needed; `binMod.setFeatures(Features.All)` before Binaryen `-Oz` to preserve exception sections |
| ✅ | stress tests (2026-05-22) | Phase 15 exception handling stress tests | Three edge-case stress tests added: `15_TestCase1-NestedEscalation` — three-level nested try/catch escalation with accumulating trace score; `15_LexicalShadowing_Stress` — `catch (e)` shadowing an outer string variable `e`, inner catch re-throws, outer catch verifies the shadow did not pollute the outer scope; `15_IdiomaticCatch_Stress` — `throw new Error("msg")` caught and converted via `instanceof Error ? e.message : String(e)` ternary and bare `String(e)`, verifying both conversion idioms |
| ✅ | bug fix (2026-05-24) | `expandGenerics` regex — array return types in generic functions | `restMatch` regex in `expandGenerics()` (`src/wasic.ts` line 2153) changed from `[\w<>, ]+?` to `[\w\[\]<>, ]+?` — adds `[` and `]` to the character class so generic functions with array return types (e.g. `mapArray<T, U>(arr: T[], fn: (x: T) => U): U[]`) are correctly recognized during template extraction. Without the fix, any generic with an array return type was silently skipped — the call site was left as raw TypeScript which emitted comparison operators instead of the intended WAT function call |
| ✅ | stress tests (2026-05-24) | Phase 16 generic monomorphization stress tests | Three edge-case stress tests added: `16_NestedMonomorphization` — concrete monomorphized classes `BoxI32`/`BoxF64` with local temporaries to prevent greedy `dotCallExprMatch` from consuming method arguments; `16_GenericInterfaceMappingsAndClosures` — non-capturing named function passed as bare function reference via `funcTypeVars` call_indirect path (capturing closures incompatible with this path); `16_DeepGenericConstraintResolution` — Phase 47 class inheritance (`Item` → `HeavyItem`) with `super()` + `override getWeight()` replacing unsupported `class Scale<T extends Measurable>` |
| ✅ | enhancement (2026-05-24) | Test file naming convention: `NN_Label.ext` | All 1,012 test files in `tests/wasi/wasm_wasi/` renamed from `Label_NN.ext` to `NN_Label.ext` so directory listings sort by phase number; 22 orphan files assigned phase numbers; 250 duplicate unversioned build artifacts deleted. Test runner scans by glob — no hardcoded paths. |
| ✅ | 16 | Module system extras | Default imports (`import foo from "./lib.ts"`); namespace imports (`import * as ns from "./lib.ts"`) with `ns.name` → `lib_name` rewriting; named re-exports (`export { foo } from "./lib.ts"`); wildcard re-exports (`export * from "./lib.ts"`); `export default function`; `exportRenamesCache` to resolve re-export chains across already-visited files; `applyRenames` updated to escape regex metacharacters (enabling dotted-key `ns.foo` rewrites) |
| ✅ | 17 | wasic library mode | `WasicTranspiler` gains `mode: "wasi" \| "library"` constructor param; library mode skips `_start`, `proc_exit` import, and top-level statement processing; `compileLibTs()` public function mirrors `compileWasiTs()`; `modc.ts` backend replaced — AssemblyScript toolchain (`asc`), temp-file creation, and binary post-processor (`removeEnvAbortImport`) all removed; `compileModule` calls `compileLibTs` directly; supports full wasic TypeScript subset (no type restrictions) |
| ✅ | 18 | WASM import bundling | `tsbundler.ts` detects `.wasm` specifiers in ESM imports and `wasm_import()` loader calls; new `wasmmerge.ts` module performs WAT-level merge with module-prefix name mangling; `_start`, `proc_exit`, `args_get/sizes_get`, `environ_get/sizes_get` stripped with notice; WASI imports deduplicated; data segments relocated by `mainModule.dataOffset`; static-data pointer `i32.const` values conservatively relocated; `WasicTranspiler` gains `externalFuncs` constructor param so call sites type-check before WAT merge; `iovBase`/`scratchBase` promoted to instance variables for collision-free merge of `fd_write` scratch areas; `bundleImportsEx()` returns `{ source, wasmImports }` alongside backward-compat `bundleImports()` |
| ✅ | 19 | `wasmbundle` CLI | New `wasmbundle.ts` + `wasmtk wasmbundle` command bundles multiple `.wasm` files into a single combined `.wasm` library; cross-module export conflict detection; interactive per-conflict prompt or `--on-conflict=prefix\|exclude` flag; non-conflicting exports keep bare names; conflicting exports prefixed or excluded; sequential `mergeWasmWat` with tracked `dataOffset`; master WAT assembled with WASI imports (14 common signatures), auto-sized `(memory N)`, and explicit `(export ...)` declarations; `extractExportNames()` added to `wasmmerge.ts`; `exportOverrides` parameter added to `mergeWasmWat` for export name control |
| ✅ | 20 | Export name transparency + `tsbundle` rename | `wasmmerge.ts`: `mergeWasmWat` emits `(export "add" (func $mathlib_add))` — original export name preserved, internal mangling unchanged; `WatMergeResult` gains `exportMap: Map<string, string>` (`originalName → $mangledName`); `wasmbundle.ts`: conflict resolution upgraded to 4-option interactive prompt (prefix / alias / exclude / stop) + `--alias file=name` and `--on-conflict=alias` non-interactive flags; `bundle` CLI command renamed to `tsbundle` |
| ✅ | bug fixes + test (2026-05-24) | Phase 18/19/20 wasmbundle pipeline bug fixes + `@test-pipeline` annotation system | **Four wasmbundle bug fixes** enabling `modc → wasic → wasmbundle → run` end-to-end: (1) **`getDataMaxEnd()` regex** (`wasmbundle.ts`) — updated to `\(data\s+(?:\(;[^;]*;\)\s+)?\(i32\.const\s+(\d+)\)` to match wabt's indexed `(data (;N;) ...)` format; without this, all data sizes returned 0 → no relocation → overlapping segments at offset 260; (2) **ENTRY_ONLY strip guard** (`wasmmerge.ts`) — `mergeWasmWat()` now checks `skipEntryStrip = exportOverrides !== undefined`; in wasmbundle mode `_start` and `proc_exit` are preserved (stripping `proc_exit` left `funcName.get(0) = undefined` → `call 0` stayed as a raw numeric index → `parseWat failed`); (3) **`_start` in export overrides** (`wasmbundle.ts`) — `extractExportNames` excluded ENTRY_ONLY names, so `_start` was never added to the `overrides` map and never emitted as an export; fix: post-processing detects `_start` via regex on raw WAT and pushes it into `exports`; (4) **Import/memory ordering + memory export** (`wasmbundle.ts`) — master WAT now emits WASI `(import ...)` declarations before `(memory N)` (WAT spec: all imports precede definitions) and adds `(export "memory" (memory 0))` (runner accesses `exports.memory` for all WASI I/O). **`@test-pipeline` / `@step` annotation system** (`wasi_tests.ts`) — new comment-based descriptor format: a file with `// @test-pipeline` triggers custom command execution; each `// @step subCmd arg1 arg2 ...` line runs one wasmtk sub-command with paths resolved relative to the test file's directory; replaces the standard compile/run-ts/run-wasm flow for multi-step pipeline tests. **`tsbundle` correction** — `bundleTs` in `utils.ts` now calls `bundleImports()` directly (TypeScript-to-TypeScript import inliner) instead of the deprecated `deno bundle` (which transpiled to `.js`); default output extension changed from `.js` to `.bundled.ts`. **New pipeline test** `18_WasmImportMerge.ts` — four-step `@test-pipeline` test: `modc 18_MathLibrary_Modc.ts` → `wasic 18_MainApplication_Wasic.ts` → `wasmbundle ... --on-conflict=exclude` → `run 18_WasmBundle.wasm`; expected output: `--- Test 1: Static Function Linkage ---\nScaled Area Result: 60\n--- Test 2: Shifted Data Segment Pointers ---\nLibrary Version: v1.8.0-core`. **257/257 wasic suite, 360/360 total.** |
| ✅ | 21 | `never` type, `void` (complete), `readonly` | `"never"` added to `WatType`; `mapType("never")` returns `"never"`; `never`-return functions emit no WAT `(result ...)` and get `(unreachable)` appended to the body; all call-statement `drop` sites guarded against never/string results; `StructField.readonly?` flag; interface and class field parsing captures `readonly` modifier; `this.field = val` writes blocked outside the constructor; `obj.field = val` writes blocked for readonly struct/class fields; `currentMethodName` instance variable added |
| ✅ | 22 | Compile-time convenience additions | `const enum` — identical to numeric enum (already parsed); Math constants (`Math.PI`, `Math.E`, `Math.LN2`, `Math.LOG2E`, `Math.LOG10E`, `Math.SQRT2`, `Math.SQRT1_2`, `Math.LN10`) → `f64.const` (already done); `**` exponentiation operator → `Math.pow` via right-associative LTR scan + `*` guard in `findBinaryOp`; `as` type assertion → `emitTypeCast` (trunc/convert/promote/demote/wrap/extend); postfix `!` non-null assertion stripped; `satisfies` operator stripped; `findDepth0LTR` + `findDepth0Keyword` + `emitTypeCast` helpers added; **bug fix**: `findDepth0Keyword` now scans from `expr.length - 1` so trailing `)` chars are correctly counted in depth before any `as` match is attempted; paren-group check now verifies the outer `(` is balanced with the final `)` before stripping — `as` now compiles correctly inside mixed-type compound expressions such as `(b * b) + (a as f64) + (c as f64)` |
| ✅ | 22 bug fix (2026-07-28) | `as` casts of `**` and `Math.*` expressions | `expr as T` assumed an `i32` source for any compound expression, but `**` and most `Math.*` functions always produce `f64`. `(base ** 3) as f64` emitted an invalid `f64.convert_i32_s` over an f64 value, and the common `Math.floor(x) as i32` idiom failed the same way. Both now compile correctly. Stress test `22_ConstEnumFoldingAndExponentCast` |
| ✅ | 22 bug fix (2026-07-29) | `a * b / c` and `a * b % c` computed the wrong value | `*`, `/` and `%` are equal-precedence and group left-to-right, but were parsed right-to-left — so `a * b / c` was computed as `a * (b / c)`. With integer division that silently gave a wrong answer: `180 * 5 / 9` produced `0` instead of `100`, and `180 * 5 % 9` produced `900` instead of `0`. Affected any expression with `*` to the left of `/` or `%`, in both ordinary code and `console.log` arguments (`a / b * c` and `a / b / c` were always correct). Regression test `22_MultiplicativeAssociativity` |
| ✅ | 23 | Tuple types `[A, B, C]` | Anonymous fixed-layout struct in linear memory; positional fields `_0`, `_1`, …; `type Pair = [i32, i32]` alias parsed in `parseStructs()`; inline `[T1, T2]` annotations; `getOrCreateTupleDef()` / `makeTupleStructDef()` create synthetic `__Tuple_T1_T2` StructDef; `mapType` extended for `[` prefix and `__Tuple_` prefix → i32; tuple params register in structVars via `structType`; `emitStatement` handles tuple literal init, named alias init, destructuring, element write, `return [e0, e1]`; strict `tupleFieldMatch` regex in `emitExpr` avoids greedy-match confusion with arithmetic; dynamic-array fallback guarded by `!structVars.has(var)`; `console_log.ts` handles `t[N]` via `structLookup` for correct type inference |
| ✅ | bug fix | `Math.*` inside `console.log` with float-literal args | `console.log(Math.abs(-4.5))`, `Math.min(3.0, 5.0)`, `Math.max(3.0, 5.0)` produced invalid WAT (`i32.const -4.5`, `i32.const 3.0`, etc.) — root cause: `parseSingleArg` in `console_log.ts` routed these tokens through `dotCallLookup` (which called `emitExpr(..., "i32")`) before the dedicated `Math.*` handler ran; fix: added `!token.startsWith("Math.")` guard on the `dotCallLookup` check; all `Math.*` tokens now reach the correct handler which emits `f64.abs`, `f64.min`, `f64.max`; `MathIntrinsics_7a.ts` compiles and passes — 84/84 suite |
| ✅ | bug fix | wasic compile-time rejection of undefined external dot-call receivers | `receiver.method(args)` where `receiver` is not a declared class instance, class, or interface variable was silently dropped — producing WASM that compiled successfully but omitted the call entirely. Fix: `emitStatement`'s `dotCallStmt` block now checks `classVars`/`classDefs`/`interfaceVars`; if the receiver is unknown it exits with `❌ wasic: 'receiver' is not defined — 'receiver.method(...)' cannot be compiled` and a hint to import the function directly. `ExternalMapping_11b.ts` — 86/86 suite |
| ✅ | enhancement | Test runner `// @expect-fail` marker for negative tests | `wasi_tests.ts` reads `// @expect-fail: compile, run-ts, run-wasm` from the first 10 lines of any test file. `runStep` accepts an `expectedFail` flag and prints `✓ compile failed as expected` for expected failures. A step that fails-as-expected counts as OK in the verdict; run-wasm is treated as N/A when compile fails as expected. Overall result prints `✅ PASSED (expected failures: compile)`. `ExternalMapping_11b.ts` uses `// @expect-fail: compile` — 86/86 suite |
| ✅ | bug fix | `tsbundler` `applyRenames` mangled `console.log` in imported modules | When a non-entry module exported a function whose name matched a built-in method (e.g. `export function log(...)`), `applyRenames` renamed every occurrence including `console.log(...)` — turning the function body into an empty stub (no WASI output). Root cause: lookbehind `(?<!\w)` allows a match after `.` because `.` is not a word character. Fix: changed to `(?<![\w.])` so a dot before the identifier prevents the match; `console.log` and all other method-call forms are left untouched while standalone call sites are correctly renamed. `ExternalMapping_11c.ts` — 85/85 suite |
| ✅ | bug fix | `arr.find()` printed raw sentinel instead of `undefined` | `console.log(notFound)` where `notFound = arr.find(isNeg)` and no element matched printed `-1` (i32 sentinel) or `NaN` (f64 sentinel) instead of `undefined`, diverging from TypeScript semantics. Fix: `emitStatement` now tracks variables declared from `.find()` calls in `findResultVars`; when a `findResultVar` is the sole argument to `console.log`, the emitter wraps the print in a sentinel check — `(if (i32.eq val (i32.const -1)) (then print "undefined\n") (else print val))` — so not-found results display `undefined` exactly as TypeScript does. `ArrayMethods_12.ts` — 85/85 suite |
| ✅ | perf fix (2026-04-17) | `runWasi` library-detection no longer double-compiles | `checkIsLibrary(path)` called a redundant `WebAssembly.compile()` after `WebAssembly.instantiate()` had already succeeded. Fix: inline check `!wasiInstance.exports._start` on the live instance — eliminates one disk read and one compile round-trip for library-call paths |
| ✅ | cleanup (2026-04-15) | Removed `asc` (AssemblyScript) dependency | `compiler.ts` deleted — `runAssemblyScriptCompiler` and `runJavyCompiler` were exported but never imported by any other module in the project; `asc` (`npm:assemblyscript`) removed from `deno.json` imports; `./compiler` removed from `deno.json` exports; `modc` exclusively uses `compileLibTs` from `wasic.ts` — no AssemblyScript toolchain required at any point in the compilation pipeline |
| ✅ | bug fix (2026-04-15) | `Math.round` semantics corrected to round half away from zero | `Math.round` was compiled to `f64.nearest` (IEEE 754 round-to-nearest-even / banker's rounding), causing `Math.round(2.5)` → `2` instead of the JavaScript-correct `3`. Fix: both `wasic.ts` (F64_UNARY table) and `console_log.ts` (exprToWat Math handler) now emit `(f64.floor (f64.add x (f64.const 0.5)))`, which matches JavaScript's "round half away from zero" rule for all normal values |
| ✅ | bug fix (2026-04-15) | `$__f64_to_str` upgraded to ×1e15 / i64 — 15-digit precision | `$__f64_to_str` in `console_log.ts` upgraded from ×1e6 (6 decimal digits, i32 arithmetic) to ×1e15 (15 decimal digits, i64 arithmetic): `$fdigits` promoted from `i32` to `i64`; divisor and modulus changed to `i64.const 10`; digit extracted via `i32.wrap_i64`; loop count raised from 6 to 15; `f64.nearest` wrapping added before `i64.trunc_f64_s` to correct truncation error from f64 values that sit slightly below their true decimal (e.g. `3.14159` stored as `3.14158999…` → frac×1e6 was `141589.999…` → truncated to `141589` → printed `3.141589`; now rounds to `141590` → prints `3.14159`). Output now matches JavaScript for all but a small number of values requiring 17 significant digits (e.g. `Math.SQRT2` → JS `1.4142135623730951`, WASM `1.414213562373095`), a known JavaScript quirk where the f64 bit pattern requires 17 digits to guarantee round-trip uniqueness |
| ✅ | 24 (2026-04-17) | `null` / `undefined` as values; `T \| null` returns | Nullable variable declarations (`const x: i32 \| null`) emit two WAT locals — `$x` (value) and `$x__null` (i32 flag, 1=null); nullable function returns (`function f(): i32 \| null`) use a module-level `$__nullable_ret_flag` global as a side-channel (callee sets to 1=has-value or 0=null, caller reads immediately after call); `parseNullableAnnotation()` helper strips `\| null \| undefined` and returns the inner `WatType`; null comparisons (`x === null`, `x !== null`) compile to `(local.get $x__null)` / `(i32.eqz (...))`; `console.log(x)` of a nullable var prints `"null"` when flag is set and the normal value otherwise; `null` / `undefined` literals added to `console_log.ts` `parseSingleArg`; pre-scans in both `emitFunction` and `startBodyLines` detect `T \| null` type annotations and register both locals; `nullableVarInnerType` map reset at start of each `emitFunction` call; `needsNullableResultFlag` flag gates `$__nullable_ret_flag` global emission — 87/87 suite |
| ✅ | 24 bug fix (2026-07-28) | `T \| null` functions returning a tuple or struct literal | `return [100, 3.14159]` from a `(): Pair \| null` function was emitted as a homogeneous array, producing invalid output for mixed-type tuples. Non-nullable tuple returns were always fine; only the `\| null` form was affected. Also fixes an *undefined global* error when a nullable return was consumed via type inference (`const n = maybeGet()`) rather than an explicit annotation. Stress test `24_NullableTupleReturnAndFlags` |
| ✅ | 25 (2026-04-17) | Nullish coalescing `??`, logical assignment `??=` `\|\|=` `&&=` | `??` handled before binary ops table in `emitExpr` — emits WAT `(if (result T) nullFlag (then rhs) (else lhs))` for nullable locals; pointer/string fallback uses `(i32.eqz ptr)`; `findBinaryOp` guards prevent `??` / `\|\|` / `&&` from matching `??=` / `\|\|=` / `&&=` (`after === "="` early-continue); `logicalAssignMatch` regex handles all three operators in `emitStatement` supporting both WAT locals (`local.get`/`local.set`) and module globals (`global.get`/`global.set`); `??=` for nullable locals clears the `__null` flag on assignment — 87/87 suite |
| ✅ | 25 enhancement (2026-07-28) | Module-level nullable globals | `let g: T \| null = null` at module scope now compiles to a WASM global plus a companion null-flag global, so `g ??= 77` works from inside any function. Previously this aborted with *unsupported statement* — only function-local nullables were supported. A module-level nullable used purely at top level is unaffected (it stays a `_start` local, as before). Stress test `25_LogicalAssignmentOperators` |
| ✅ | 25 bug fix (2026-07-28) | `??` inside `console.log` arguments | `console.log("x:", val ?? -1)` silently printed the fallback instead of the value. Nullish coalescing now resolves correctly in `console.log` / `console.error` arguments, including the null-vs-zero distinction (`0 ?? 999` is `0`, not `999`). Stress tests `25_NullishOnlyNullFallback`, `25_NullishShortCircuitSideEffects` |
| ✅ | 26 (2026-04-17) | `for...of` loops; array destructuring with default values | `for...of` over static `i32[]`, dynamic `i32[]`, `f64[]` arrays; `break` / `continue` inside loops; `for...of` over function-local dynamic arrays; array destructuring with defaults `const [a = 10, b = 20] = arr` — runtime length check on dynamic arrays; `$__forof_idx` (i32) shared local registered by pre-scans in both `emitFunction` and `startBodyLines`; **`parseTopLevel` `collectBlock` fix** — without this, module-level loop bodies were silently stripped because brace depth was never updated for top-level pattern-4 lines; static/dynamic/param access patterns differ (`i32.const` base / `i32.load` header / `local.get` base); pre-scan extracts binding name by splitting on `=` to avoid registering `"a = 10"` as a WAT local name — 88/88 suite |
| ✅ | 26 bug fix (2026-07-28) | Nested `for...of` iterated only the first row | Every `for...of` shared one cursor local, so an inner loop clobbered its outer loop's index and the outer loop ran exactly one iteration — silently wrong, no crash: a 3×2 matrix summed to `3` instead of `21`. Each loop now gets its own cursor keyed by nesting depth. Non-nested loops are unchanged (byte-identical output). Stress tests `26_NestedForOfMatrix`, `26_ForOfBreakContinue`, `26_ArrayDestructuringDefaults` |
| ✅ | 27 (2026-04-18) | Extended string methods + Bun runtime compatibility | **String methods:** `trim`/`trimStart`/`trimEnd`, `charCodeAt`, `charAt`, `startsWith`, `endsWith`, `toUpperCase`/`toLowerCase` (ASCII), `replace`/`replaceAll`, `padStart`/`padEnd`, `repeat`, `split` → `string[]`; `for...of` over `string[]` with 8-byte `(ptr i32, len i32)` element layout; `isStringArr` flag on `arrayVars`; 15 WAT helper functions in `getStringExtHelperWat()`; **Bun compatibility:** new `src/rt.ts` runtime shim — `isBun` detection, unified `rt.readFile`/`writeFile`/`readTextFile`/`writeTextFile`/`mkdir`/`stat`/`remove`/`realPath`/`stdout`/`stderr`/`stdin`/`env`/`build`/`Command`; replaces all `Deno.*` call sites across 7 source files; `bunfig.toml` sets `@jsr` registry to `https://npm.jsr.io/`; `package.json` adds `bin` field for Bun global install; `"nodeModulesDir": "none"` in `deno.json` prevents Deno entering node_modules mode when `package.json` is present |
| ✅ | bug fix (2026-04-18) | `switch` on `number`/`f64` variables; `String(e)` and `instanceof Error` ternary in catch | **`switch` f64 type:** `switch` on a `number`-typed (`f64`) variable emitted `i32.eq`/`i32.const`, causing a Binaryen assertion abort. Fix: switch emission detects the WAT type via `locals`/`moduleGlobals` and uses `f64.eq`/`f64.const` when the type is `f64`. **Catch string patterns:** `String(e)` and `e instanceof Error ? e.message : String(e)` in catch blocks emitted undefined `$String`/`$e` symbols. Fix: two early-exit guards in `parseSingleArg` (`console_log.ts`) — both patterns now resolve to the caught string's `$e_ptr`/`$e_len` locals — 88/88 suite |
| ✅ | 27 bug fix (2026-07-28) | String methods used inline (not assigned first) printed `0` | `trim`, `trimStart`/`trimEnd`, `charAt`, `repeat`, `replace`, `replaceAll` worked when their result was assigned to a variable, but silently produced `0` when used directly as a `console.log` argument, a comparison operand, or a call argument — e.g. `console.log(s.repeat(3))` printed `0`. String **literal** receivers failed the same way for `slice`, `.at` and case conversion (`"hello".slice(1,3)` → `0`). All of these now work in every position, for variable, literal, array-element and function-call receivers alike. Stress tests `27_StringSplitAndForOf`, `27_StringTrimPadReplace`, `27_CharCodeAndSubstringQuery` |
| ✅ | 28 (2026-04-23) | Extended array methods | `every(fn)`, `some(fn)`, `findIndex(fn)`, `at(i)`, `reverse()`, `fill(val, start?, end?)`, `join(sep?)`, `sort()`, `sort(cmpFn)` — all on dynamic `i32[]` and `f64[]`; **`every`/`some`**: predicate loop helpers (`$__dynarr_every_T` / `$__dynarr_some_T`) return i32 1/0; `dotCallLookupFn` returns `type: "bool"` for `every`, `some`, and `includes` on array receivers; `parseSingleArg` maps `type === "bool"` → `boolexpr` — `true`/`false` output matches TypeScript; **`findIndex`**: predicate scan, returns index or -1; **`at`**: negative index wraps via `len + n`; **`reverse`**: two-pointer in-place swap; **`fill`**: range fill with start/end clamped to `[0, len]`; **`join`**: new `joinarr` `LogSegment` kind; `getJoinHelperWat()` emits `$__dynarr_join_to_scratch_i32/f64` which writes the joined string directly into the gather scratch buffer (avoids returning a string pair); separator allocated in data section at compile time; `needsJoinHelper` flag wired through all 6 `emitConsoleLog` call sites and `emitHelpers`; **`sort()`**: in-place insertion sort ascending; **`sort(cmpFn)`**: insertion sort with `call_indirect` comparator; `findDynamicArrays` regex extended for all Phase 28 methods; **bug fix**: `T \| undefined`-typed `.find()` variables now correctly populate `findResultVars` (nullable let match handler was returning early, bypassing `findResultVars.add()`); **`Tuples_23`**: `(a / b) \| 0` pattern documents integer-division semantics for test files where TypeScript float division would diverge — 89/89 suite |
| ✅ | bug fix (2026-04-24) | `arrptr`/`joinarr` segments in per-iov path | `console_log.ts` `emitConsoleLog` has two emission strategies: gather mode (all segments gatherable) and per-iov mode (fallback when a non-gatherable segment such as `boolexpr` is present). `arrptr` and `joinarr` LogSegment kinds were only handled in the gather path — when per-iov mode was forced (e.g. a `boolexpr` + an array in the same `console.log`), the array segment fell through to the final numeric `else` which accessed `.wat` (absent on `joinarr`), producing a TypeScript lint error and incorrect WAT at runtime. Fix: explicit `else if` branches added for both kinds in the per-iov outer chain; each initialises the iov's `buf_len` field to 0 (cursor start), sets `buf` to `scratchBase`, and calls the same array/join helper as gather mode — `mem[iovLen]` holds the byte count after the call, satisfying the iov contract without additional bookkeeping |
| ✅ | 28 bug fix (2026-07-28) | `arr.join()` usable as a string value | `join()` previously worked only *inside* `console.log`; assigning it — `const s: string = nums.join("-")` — failed to compile with *unsupported string assignment*. It now produces a real string, so it also works in concatenation (`"[" + nums.join(",") + "]"`) and comparisons. Covers `i32[]` and `f64[]` with a literal separator (default `","`). Stress test `28_ArrayJoin` |
| ✅ | 27 bug fix (2026-07-28) | `console.log` string concatenation printed `0` when a literal contained `]` or `)` | `console.log("[" + name + "]")` or `console.log(s + ")")` silently printed `0` instead of the string — a closing bracket inside a string literal confused the expression scanner and hid the `+`. Literals containing `{`/`}`, or an opening bracket alone, were unaffected, which made it look arbitrary. All bracket characters now work in any position. Regression test `27_ConsoleLogBracketConcat` |
| ✅ | 29 (2026-04-24) | Class enhancements | **Static fields:** `static count: i32 = 0` → named mutable WASM global `$ClassName_count`; registered during `parseClasses()` directly into `moduleGlobals`; `ClassName.field` reads emit `(global.get $ClassName_field)`, writes emit `(global.set ...)`; accessible from constructors, instance methods, and static methods. **Getters:** `get prop(): T { return this._prop; }` → `ClassName_get_prop(__self: i32): T`; `obj.prop` (no parens) dispatches to getter in `emitExpr`, in `structLookupFn` (console.log), and via `this.prop` inside methods — getter check runs before raw field load. **Setters:** `set prop(val: T) { this._prop = val; }` → `ClassName_set_prop(__self: i32, val: T)`; `obj.prop = val` dispatches to setter in `emitStatement` for both `this.field = val` and `obj.field = val` paths — setter check runs before raw field store. **String enums:** `enum Direction { Up = "up", Down = "down" }` → `enumStringValues: Map<string, string>`; `const dir: string = Direction.Up` allocates the string in the data section via `emitStringAssign`; `console.log(Direction.Up)` emits a `{ kind: "literal", text: "up" }` segment via new `enumStringLookup` callback threaded through `parseConsoleLogArgs` / `parseSingleArg` / `parseTemplateLiteral` in `console_log.ts`; `ClassDef.methods` entries gained `isGetter?` / `isSetter?` flags |
| ✅ | bug fix (2026-04-24) | Phase 29 `console.log(ClassName.staticField)` | Both `structLookupFn` closures in `wasic.ts` (console.log and console.error paths) only checked `classVars` (instance vars) and `structVars` (plain structs) — `console.log("Count:", Rectangle.count)` printed `0` because the lookup returned `undefined` when `vn` was a class name rather than an instance variable, causing `exprToWat` to emit `(f64.const 0)`. Fix: added a static-field branch in both closures that checks `classDefs.get(vn)` → `moduleGlobals.get("${vn}_${fn}")` and returns `(global.get $ClassName_field)` when found. Four new Phase 29 test files added (`StaticFields_29`, `GettersSetters_29`, `StringEnums_29`, `ClassEnhancementsCombined_29`) — 94/94 suite |
| ✅ | 29 bug fix (2026-07-29) | String enums usable as values, not just for printing | A **pure** string enum (`enum LogLevel { Info = "INFO", … }` with no numeric members) could only be printed. Assigning one — `const lvl: LogLevel = LogLevel.Error` — or comparing (`lvl === LogLevel.Error`) failed to compile. Both now work, and printing a string-enum **variable** or parameter shows its text (`ERROR`) rather than an internal number. Stress test `29_StringEnumDispatch` |
| ✅ | 30 (2026-04-27) | Struct/object enhancements + `namespace` | **Namespaces:** `expandNamespaces()` source-level transform runs before all parse passes in `transpile()` — rewrites `export function f()` → `function Name_f()` and `export const C` → `const Name_C`, flattens into top-level declarations; `namespaceDefs: Set<string>` tracks known names; call sites (`Name.f(args)`, `Name.C`) handled in `emitExpr`, `dotCallStmt`, and both `structLookupFn`/`dotCallLookupFn` closures; `parseTopLevel` skips already-expanded namespace blocks. **Interface inheritance:** `parseStructs()` regex captures optional `extends BaseName` group; base fields prepended at their original offsets, derived fields start at `baseDef.totalSize`; re-add guard prevents duplicate fields. **Shorthand property notation:** `return { x, y }` in function bodies — when no `:` separator present, token treated as both key and value; `structVarRuntimeInits: Map<string, Record<string, string>>` populated during pre-scan of both `emitFunction` body and `startBodyLines`; `emitStatement` struct-let match emits runtime `f64.store`/`i32.store` instructions per field from `structVarRuntimeInits`. **Bug fix:** function-returned structs now registered in both `interfaceVars` (method dispatch) and `structVars` (field reads) — enables `const v: Vec2 = makeVec(3.0, 4.0); console.log(v.x)`. Five test files: `Namespace_30`, `NamespaceAdvanced_30`, `InterfaceInheritance_30`, `ShorthandProps_30`, `Phase30Combined_30` — 99/99 suite |
| ✅ | 30 bug fix (2026-07-30) | Using a `namespace` member from inside the same namespace | A namespace function referring to one of its own members by its bare name — `export function calculateForce(m: i32) { return m * GRAVITY; }` — failed to compile with *unsupported expression*. Only qualified access from outside (`Physics.GRAVITY`) worked. Bare references to sibling constants **and** sibling functions now resolve; a member name appearing in a string literal, or as an object field (`obj.GRAVITY`), is correctly left alone. Stress test `30_NamespaceConstAndFunction`, regression `30_NamespaceInternalRefs` |
| ✅ | 30 bug fix (2026-07-30) | `string`-typed `namespace` members | `export const NAME: string = "cfg"` inside a namespace printed `0` instead of its text, and a namespace function returning a `string` failed to compile. Namespace members of every type — `string`, `i32`, `f64` — now work in all positions: read directly, assigned, concatenated, compared, and returned from a namespace function. Regression `30_NamespaceStringMembers` |
| ✅ | 31 (2026-04-29) | TypedArrays | **Types supported:** `Int8Array`, `Uint8Array`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array` — all eight typed array types. **Memory layout:** 8-byte header `[length i32 at +0, 0 i32 at +4]` followed by typed data at `+8`; allocated via `$__malloc`. **Construction:** `new Int32Array(n)` (literal length), `new Int32Array(runtimeVar)` (runtime length), `new Int32Array([1, 2, 3])` (literal array initialiser — data segment + `memory.copy`). **Element access:** typed read (`i32.load8_u`, `i32.load`, `f64.load`, etc.) / write (`i32.store8`, `i32.store`, `f64.store`, etc.) at `ptr+8+idx*shift`; sub-word shift=0 case uses plain `i32.add` offset without `i32.shl`. **Properties:** `.length` (`i32.load ptr`), `.byteLength` (`length * bytesPerElem`). **Methods:** `.fill(val)`, `.fill(val, start)`, `.fill(val, start, end)` — clamped range loop via `$__ta_fill_T` helper; `.set(src)`, `.set(src, offset)` — element copy via `$__ta_set_T` helper. **TypedArray as function param:** registers in `typedArrayVars` from `p.structType`; correct load/store ops used inside callee. **`console.log`:** `Int32Array(4) [ 1, 2, 3, 4 ]`-style output — length header + `arrptr` LogSegment reusing existing i32/f64 array print helpers; `ArrayLookup` type in `console_log.ts` extended with optional `shift` and `customLoadOp` fields for sub-word load ops; `structLookupFn` extended to route `.length`/`.byteLength` via `parseSingleArg`. **Bug fix — `bracketMatch` greedy regex:** `emitExpr`'s `/^(\w+)\[(.+)\]$/` was changed to `/^(\w+)\[([^\]]*)\]$/` — prevents greedy match across binary operators so compound expressions like `nums[0] + nums[1] + nums[2]` fall through to the binary ops loop instead of misparsing as a single bracket access. Four test files: `Int32Array_31`, `Float64Array_31`, `TypedArrayAdvanced_31`, `Phase31Combined_31` — 103/103 suite |
| ✅ | 32 (2026-04-30) | Discriminated union types | **Layout:** flat "super-struct" — discriminant field at offset 0 as `i32` (4 bytes), followed by all unique variant fields from all branches laid out sequentially with natural alignment; every variant of the union shares the same memory region. **Tag mapping:** discriminant string literals (`"circle"`, `"rect"`, etc.) are mapped to integer indices (0, 1, 2…) at compile time inside the pre-scan phase — `allocStructData` only ever sees integers. **`parseDiscriminatedUnions()`:** new parse pass runs before `parseStructs()` in `transpile()`; detects multi-variant `type Name = { disc: "lit1"; … } \| { disc: "lit2"; … }` aliases via regex; identifies the common discriminant field (the one with a string literal in every variant); builds and registers the combined `StructDef` in both `structDefs` and `discUnionDefs`; `parseStructs()` skips names already registered. **Switch narrowing:** `switch (s.kind)` with `case "circle":` — switch handler detects `varName.discField` pattern, emits `(i32.load ptr)` for the dispatch value, converts string case labels to their integer tag constants via `duSwitchDef.variants`. **If/else-if narrowing:** `s.kind === "circle"` handled in `emitExpr` before the binary ops table — emits `(i32.eq (i32.load ptr) (i32.const tagIdx))`; `!==` maps to `i32.ne`. **`else if` chain support (general fix):** `emitBlock`'s if-handler now detects `} else if (cond) {` terminators from `extractBlock`, collects the full chain into a synthetic lines array, and recurses — this was a previously untested code path in wasic. **Bug fix — `as T` cast for struct fields:** `srcType` in `emitExpr`'s `as` handler now resolves struct field types via `structVars` lookup (`val.n as f64` where `n: i32` now emits `f64.convert_i32_s (i32.load …)` instead of a bare `i32.load`). **Bug fix — i32 arithmetic in `console.log`:** `parseSingleArg` in `console_log.ts` now detects a leading i32/bool identifier and returns `i32expr` (not `f64expr`); `exprToWat`'s binary-ops loop extended with an `lhsLocalType === "i32"` check (parallel to the existing i64 check) so `y + m.steps` where both are `i32` emits `i32.add` not `f64.add`. Four test files: `BasicDiscUnion_32`, `DiscUnionIfElse_32`, `DiscUnionMixed_32`, `Phase32Combined_32` — 107/107 suite |
| ✅ | 33 (2026-05-01) | Intersection types `A & B` | **`parseIntersectionTypes()`:** new parse pass in `wasic.ts`, called after `parseStructs()` + `parseClasses()` in `transpile()`. Detects `type Name = A & B [& C …]` declarations where the RHS is two or more `\w` identifier type names separated by `&` (regex excludes object-type `{}`, DU `\|`, tuple `[]`, and function-type `=>` forms). For each match, merges all `StructField` entries from each constituent `structDefs` entry in source order — natural alignment preserved, first definition wins on name conflict, fields already present are skipped. Registers the merged `StructDef` in `structDefs` under the intersection type name. Processes matches in source order so chained intersections (`type D = C & E` where C is itself an intersection) resolve correctly in a single pass; since each intersection is registered before the next match is processed, multi-level chains work without multiple passes. No other changes required — intersection types are ordinary `StructDef` entries so all existing infrastructure (struct literal init, `allocStructData`, field access in `emitExpr`/`emitStatement`, `structLookupFn`, function param `structType` dispatch) works unmodified. Passing a derived intersection pointer (`ColoredParticle*`) to a function expecting a base intersection pointer (`Particle*`) is safe because the first N bytes of the derived layout are identical to the base layout. Four test files: `BasicIntersection_33`, `IntersectionFunc_33`, `IntersectionThreeWay_33`, `Phase33Combined_33` — 112/112 suite |
| ✅ | 34 (2026-05-02) | Type predicates `x is T` | **Syntax:** `function isPred(p: BaseType): p is DerivedType { … }` — the `param is Type` return annotation is parsed by `parseFunctions()` (regex extended with `[\w]+\s+is\s+[\w]+` alternative); the predicate function is registered in `typePredicateFuncs: Map<string, { paramName, targetType }>` and its WAT result type is set to `bool` (i32), so `console.log(isCircle(x))` correctly prints `true`/`false`. **Compile-time narrowing:** in `emitBlock()`'s if-handler, when the condition matches the single-arg call pattern `predFn(arg)` and `predFn` is in `typePredicateFuncs`, the argument variable is narrowed — its `structVars` (or `classVars`) entry is temporarily replaced with `{ def: targetDef, ptr: same-ptr }` before emitting the then-branch body and restored afterward. The current pointer value (static address or -1 for function params) is preserved so all existing field-access paths continue to work. **Else-if chains:** free — `emitBlock` transforms `else if` into a recursive nested-if structure, so each predicate call in a chain gets independent narrowing scope automatically. **Supported patterns:** DU types (all variant fields in the flat struct; `s.disc === "lit"` in the predicate body compiles via Phase 32 infrastructure) and interface inheritance hierarchies — a function accepting the base type can narrow the parameter to a derived type and access derived-only fields. **Limitation:** negated predicates (`!isPred(x)`) and else-branches do not apply narrowing. Four test files: `BasicTypePredicate_34`, `TypePredicateNarrowing_34`, `TypePredicateFunc_34`, `Phase34Combined_34` — 116/116 suite |
| ✅ | 35 (2026-05-03) | `typeof` / `keyof T` (compile-time only) | **`typeof` comparisons:** `typeof x === "number"` (and `!==`, `==`, `!=`) is evaluated entirely at compile time in `emitExpr` before the binary ops table — the new handler resolves the variable's known WAT type to its JS typeof string (`i32`→`"number"`, `f64`→`"number"`, `bool`→`"boolean"`, `string`→`"string"`, `i64`→`"bigint"`, struct/array `i32`→`"object"`) and emits `(i32.const 1/0)`. The reversed form (`"type" === typeof x`) is also matched. **`typeof` as a value:** `const t: string = typeof x` and `const t = typeof x` (inferred as `string` via `inferInitType`) are handled in `emitStringAssign` — calls `resolveTypeofString`, allocates the type-name in the data section, sets `$t_ptr`/`$t_len`. **`console.log(typeof x)`:** `parseSingleArg` in `console_log.ts` detects the `typeof x` token and returns `{ kind: "literal", text: typeStr }` — zero runtime overhead, the type string is embedded as a static literal. **`keyof T` as type annotation:** a source pre-pass in `transpile()` (after `expandNamespaces`) rewrites every `: keyof T` type annotation to `: string` in the raw source before any parsing — making `function f(key: keyof Person)` and `const k: keyof Point = "x"` work transparently through the existing string infrastructure. `mapType()` also has a `/^keyof\s+\w+/` guard as a fallback. `type Alias = keyof T` declarations are stripped by the pre-pass. **Limitation:** `typeof x` in type positions (`param: typeof myVar`) and named `keyof` aliases (`type PK = keyof Person; let k: PK`) are not supported. Four test files: `BasicTypeof_35`, `KeyofBasic_35`, `TypeofInConditions_35`, `Phase35Combined_35` — 120/120 suite |
| ✅ | enhancement (2026-05-01) | `$__f64_to_str` shortest-round-trip pass | **Problem:** the ×1e15 approach occasionally produced a spurious extra trailing digit — e.g. `78.539816339744831` instead of `78.53981633974483` — because multiplying the fractional remainder by `1e15` in IEEE 754 introduces a ±1 ULP rounding error in the last digit. **Fix:** a "shortest round-trip" loop added after the ×1e15 step. Starting from 15 fractional digits, it repeatedly tries stripping the last digit (dividing `fpart` by 10) and checking whether `f64(ipart) + f64(trial) / f64(10^k)` still reconstructs the exact original double via `f64.eq`. Stripping stops at the first k where reconstruction diverges. Powers of 10 from `1` to `1e15` are all exactly representable in f64 (≤ 50 significant bits), so the reconstruction arithmetic introduces no additional error beyond the comparison itself. A new `$__pow10_f64` WAT helper returns `10^n` for n in [0, 15] via a chain of `if`/`return` branches. Per-binary overhead: ~200–300 bytes additional WAT (the helper function + extra locals and loop in `$__f64_to_str`). Known remaining delta: `Math.SQRT2` prints `1.414213562373095` (WASM) vs `1.4142135623730951` (JavaScript) — this requires MORE digits than ×1e15 can supply and is not fixed by the shortening pass. **(Superseded 2026-07-01 — see the pure-Dragon4 row below.)** |
| ✅ | enhancement (2026-07-01) | `$__f64_to_str` rewritten as pure Dragon4 (byte-exact f64→string) | **Replaces the ×1e15 + shortening-loop formatter entirely.** The old approach (a) capped at ~15 significant figures — diverging from V8's 17-sig-fig shortest for values like `Math.SQRT2` and `7/3` — and (b) **trapped** (`i64.trunc_f64_s` "float unrepresentable in integer range") on `\|x\| ≥ ~9.2e18` and emitted **no scientific notation** for runtime floats. The new `$__f64_to_str` is a hand-written-WAT **Dragon4 (Burger–Dybvig free-format)** implementation: fixed-size 48-limb (1536-bit) bignums (`R`, `S`, `m+`, `m-`) in a lazily-`$__malloc`'d 1 KB scratch region held in a new `$__d4s` module global; seven bignum helpers (`$__bz`, `$__bset64`, `$__bmul_u32`, `$__bshl`, `$__bcmp`, `$__badd`, `$__bsub`); a robust bidirectional scale-estimate fixup; round-to-even on ties; then ECMAScript `Number.prototype.toString` formatting (fixed-point for `pointPos ∈ (-6, 21]`, else scientific in either direction — plus sign, zero, `±Infinity`, `NaN`). Result: **100 % byte-exact parity with V8** (`Math.SQRT2` → `1.4142135623730951`, `1e21` → `1e+21`, `1e300` → `1e+300`, subnormal `5e-324`, max `1.7976931348623157e308`), validated at `0/3017` fuzz mismatches. Regression test `66_Dragon4Formatting`; the obsolete `// @allow-output-diff` markers on `1_values` / `7a_MathIntrinsics` / `45_random-numbers` were removed |
| ✅ | enhancement (2026-07-02) | `mathlib` correctly-rounded sweep — **COMPLETE (all functions)** | **Every `mathlib` elementary function now returns the IEEE-754 correctly-rounded result** via double-double arithmetic, extending the sin/cos/tan work below to the whole set: `exp`, `log`/`log2`/`log10`, `cbrt`, `atan`, `asin`/`acos`/`atan2`, `sinh`/`cosh`/`tanh`, `expm1`, `asinh`/`acosh`/`atanh`, `log1p`, and **`pow`** (now a mathlib function — a full `exp(y·log\|x\|)` CR implementation with the complete IEEE special-case ladder, routed from `Math.pow`/`**`/`**=`; exact integer powers stay exact, e.g. `2**10 = 1024`). Each was validated bit-for-bit vs an independent BigInt oracle **and** end-to-end through the full pipeline (0 mismatches across ~0.3–1.5M samples per function). Reusable oracle harness: `scripts/math_cr_oracle.ts`. Also added `wasmtk wast` (a WebAssembly `.wast` spec-script conformance runner) which validates the toolchain against the official spec testsuite. Full suite 375/375. |
| ✅ | enhancement (2026-07-01) | `mathlib` `sin`/`cos`/`tan` — correctly-rounded (double-double) | **`Math.sin`/`cos`/`tan` now return the IEEE-754 correctly-rounded result** — the unique value every correct libm agrees on, giving maximum accuracy _and_ maximum cross-language compatibility for the universal-loader ecosystem (each faithfully-rounded libm — V8/glibc/MSVC/Go/Rust — disagrees with the others by ~1 ULP, but they all cluster on the correctly-rounded value). Chosen over "match V8 bit-for-bit" because modern V8 delegates `Math.sin/cos` to LLVM-libc's `shared::sin/cos`, which are themselves only _faithfully_-rounded (~99.76 % correctly-rounded) and a moving, version-pinned target. **Implementation** (`src/wasm/mathlib.wat`): double-double (dd) arithmetic — `$__ts` (twoSum), `$__tp` (Veltkamp twoProduct, no FMA needed), `$__dda`/`$__ddm`/`$__ddmd`/`$__ddri`/`$__dddiv`, all returning `(hi, lo)` via WASM multi-value; dd Taylor kernels `$__ddsin`/`$__ddcos`; the table-free Veltkamp n-split reduction `$__trig_reduce` (dd remainder in globals `$__tr`/`$__trt`); `tan = dd sin(r)/cos(r)` via `$__dddiv` with quadrant sign. **Validated bit-for-bit against a BigInt fixed-point correctly-rounded oracle through the entire pipeline** (`wat2wasm` + merge + Binaryen `-Oz`, which preserves the dd ops): sin/cos 1032/1032 + tan 412/412, zero errors, `\|x\|` up to 1e12 (correctly-rounded to ~1e15, ≤1 ULP beyond). Pure f64 arithmetic — no Payne-Hanek table, no linear memory — so it survives the merge. Regression `67_TrigCorrectlyRounded`; full suite 375/375. _Note:_ a wasic program's trig now differs from Deno's `Math.*` (V8) on the ~0.24 % of inputs where V8 isn't correctly-rounded — intended (wasic is the more-correct one). Supersedes the earlier fdlibm/≤1-ULP row above. Regenerate after editing: `wasmtk convert src/wasm/mathlib.wat` then `deno run -A scripts/gen_mathlib_bytes.ts` |
| ✅ | 36 (2026-05-04) | Simple conditional types `T extends U ? X : Y` | **`expandConditionalTypes(src)`:** new private method on `WasicTranspiler`, inserted after `expandGenerics` and before `expandNamespaces` in `transpile()` — pure source-level text transformation. **Generic form** (`type Toggle<T> = T extends i32 ? f64 : i32`): declaration removed from source; every `Toggle<ConcreteType>` use site is rewritten by resolving the condition against the concrete argument. **Non-generic form** (`type AlwaysI32 = f64 extends number ? i32 : string`): condition evaluated once at declaration time; all bare occurrences of the type name replaced with the resolved concrete type. **`extendsCheck(concrete, upper)`**: conservative compile-time compatibility — same string, any numeric type extends `number`, `bool`/`boolean` cross-match. Runs after `expandGenerics` so monomorphized call sites produced by generic expansion are also resolved; runs before all other parse passes so no downstream pass ever sees a conditional type declaration or use site. **Limitations:** `infer` not supported; nested conditional types require two passes; conditional types referencing other conditional types by name have source-order dependency. Four test files: `BasicConditionalType_36`, `ConditionalTypeParams_36`, `ConditionalTypeNonGeneric_36`, `Phase36Combined_36` — 124/124 suite |
| ✅ | 37 (2026-07-14) | `flat()` / `flatMap(fn)` | **`flat()`:** one-level flatten of `i32[][]` or `f64[][]` into a 1D array — two-pass WAT helper `$__dynarr_flat_T`: (1) walk outer array (i32 ptrs, shift=2), sum all inner `.length` headers to get `totalLen`; (2) allocate result array of `totalLen` elements; (3) copy inner elements using the element type's shift/load/store. **`flatMap(fn)`:** for each element of a 1D array, call `fn(elem)` via `call_indirect` (functype `(T) → i32`, the i32 being a pointer to an inner `T[]`), then flatten — two-pass WAT helper `$__dynarr_flatmap_T`: allocates a raw temp buffer (`len × 4` bytes, no header) to store inner array ptrs from pass 1, accumulates `totalLen`, allocates result in pass 2, copies. Calling `fn` exactly once per element avoids side-effect duplication. `findDynamicArrays` regex extended to include `flat` and `flatMap` so source arrays are auto-promoted to dynamic layout. `flat()` guards `arrInfo.is2D` — calling it on a 1D array is a compile-time stub. `flatMap` callbacks must be named functions (no inline arrows); the callback's TypeScript return type (`T[]`) maps to WAT `(result i32)` — the same convention as all other array-returning functions. Three test files: `FlatArray_37`, `FlatMapArray_37`, `Phase37Combined_37` — 127/127 suite |
| ✅ | 38 (2026-07-14) | Extended math via external `mathlib.wasm` | **Architecture:** `src/wasm/mathlib.wat` is a standalone WAT module (21 exported functions) compiled to `src/wasm/mathlib.wasm` (binary embedded as `MATHLIB_BYTES` in `src/wasm/mathlib_bytes.ts`). When any Phase 38 `Math.*` function appears in a compiled file, `transpiler.needsMathLib` is set and `compileWasiTs`/`compileLibraryTs` call `mergeOneWasmImport(wat, MATHLIB_BYTES, "mathlib", ...)` to splice the library into the WAT before Binaryen sees it — so dead-stripping and inlining work across the full merged module. **Naming:** wasic emits `(call $mathlib_sin arg)` etc.; `mergeWasmWat` applies the `"mathlib"` prefix to all exported symbols. **Global relocation:** `renameGlobalRefs()` in `wasmmerge.ts` rewrites numeric `global.get N` / `global.set N` references in merged bodies to named `$mathlib_globalN` refs, necessary because the RNG state global (i64) shifts index after the main module's globals are prepended. **`$atan` two-stage range reduction:** complement (z→1/z for z>1) + mid-range ((z-1)/(z+1) for z>tan(π/8)≈0.4142) before the fdlibm aT[0..10] minimax polynomial; four result cases based on which reductions applied; formula `r = z − z³t` (subtraction). **Bug fixes:** (1) greedy `Math.fn(...)` regex in both `wasic.ts` and `console_log.ts` now validates that argsStr has no unmatched `)` at depth 0 — compound expressions like `Math.sin(a) * Math.sin(a) + Math.cos(a) * Math.cos(a)` previously matched as a single `Math.sin(...)` call; (2) `exprToWat` in `console_log.ts` gained a `globals?: Map<string, string>` 8th parameter so module-level f64 globals used as arguments to nested Math calls (e.g. `Math.exp(x)`) emit `(global.get $x)` instead of a comment stub. Five test files: `MathTrig_38`, `MathExpLog_38`, `MathHyperbolic_38`, `MathRandom_38`, `Phase38Combined_38` — 132/132 suite |
| ✅ | 39 (2026-07-14) | `jstyper` — `.d.ts`-based JS import pre-processor | **Architecture:** `src/jstyper.ts` — pure regex/brace-counting implementation with no external dependencies. **Pipeline:** `parseJsFunctions()` extracts function bodies from `.js` (regular functions + arrow functions, block and expression bodies, nested-brace-safe via string-aware `extractBraceBlock()`); `parseDtsFunctions()` extracts typed signatures from `.d.ts` (`export declare function` / `declare function` forms); `generateTypedTs()` merges bodies + types into a typed `.ts` wasic can compile. **Type mapping:** `number→f64`, `int→i32`, `float\|double→f64`; WASM primitives (`i32`, `i64`, `f32`, `f64`, `bool`, `string`, `void`, `never`) pass through unchanged; `any` controlled by `--any-policy`. **`--dts-only` mode:** `generateSkeletonDts()` emits a `number`-typed skeleton `.d.ts` with `@auto-generated by jstyper` header for hand-editing. **`--dry-run`:** prints output to stdout without writing files. **`--any-policy` modes:** `skip` (exclude function + warning with corrected declaration), `warn` (include with `i32` fallback + warning), `default` (include with `i32` silently). **Actionable diagnostics:** every warning and error is multi-line with a "Fix:" block naming the specific file, showing the corrected declaration verbatim, listing valid WASM types, and (for skip mode) offering the `--any-policy=warn` escape hatch; `correctedDecl()` helper reconstructs the declaration with `any→i32` substituted. **CLI:** `wasmtk jstyper <file.js> [--dts-only] [--dry-run] [--any-policy=skip\|warn\|default] [-n out]`. **Tests:** four wasic-compiled `wasm_wasi` test files (`JstyperBasic_39`, `JstyperF64_39`, `JstyperMixed_39`, `Phase39Combined_39`) + `tests/jstyper_tests.ts` unit runner (73 assertions covering all parsing, generation, and pipeline paths). **New files:** `src/jstyper.ts`, `tests/jstyper_tests.ts`, `tests/jstyper_fixtures/` (3 fixture pairs). **Changed:** `main.ts` (`case "jstyper"`, `--dts-only`/`--dry-run`/`--any-policy` flags), `deno.json` (`"./jstyper"` export). Four wasic test files: `JstyperBasic_39`, `JstyperF64_39`, `JstyperMixed_39`, `Phase39Combined_39` — 136/136 suite |
| ✅ | 40 (2026-07-14) | External interface mapping via `declare const` / `declare interface` | **`declare const host: { log(ptr: i32): void; getTime(): i32 }`** — inline object type; each method compiles to `(import "env" "host_log" ...)` + `(import "env" "host_getTime" ...)`. **`declare interface Logger { ... }` + `declare const logger: Logger`** — named form; interface defined once, bound by name. **`parseExternalDeclarations()`** three-pass preprocessor strips declarations before other parsers; `externalInterfaceTypes` + `externalBindings` maps drive call-site emission; `usedExternalMethods` tracks actually-called methods and drives `emitWasiImports()` to emit `(import "env" ...)` declarations. **Runner stub proxy:** `env` import object in test runner is a JavaScript `Proxy` — any unrecognised key returns a no-op `() => 0` stub, allowing Phase 40 WASM modules to instantiate without a real host. **Error message improvement:** undeclared dot-call receivers now suggest the Phase 40 `declare const` syntax. `ExternalMapping_11b.ts` upgraded from `@expect-fail: compile` to a fully-passing test. Six test files: `BasicExternalDecl_40`, `ExternalInterfaceType_40`, `MultiMethodExternal_40`, `ExternalReturnValue_40`, `Phase40Combined_40`, `ExternalMapping_11b` (upgraded) — 142/142 suite |
| ✅ | 41 (2026-07-14) | WIT file generation | After every successful `wasic` or `modc` compilation, a `.wit` file is written alongside the `.wasm` output. **`watTypeToWit()`** maps WAT types to WIT types (`i32→s32`, `i64→s64`, `f32→f32`, `f64→f64`, `bool→bool`). **`toKebabCase()`** converts camelCase/snake_case function names to WIT-compliant kebab-case. **`generateWit(moduleName)`** public method on `WasicTranspiler` produces `package local:name; world name { import ...; export ...; }` — imports from `usedExternalMethods` (Phase 40 externals); exports from `this.functions` filtered by `exported && !isClosureFactory && !INTERNAL`. **`_start`/`_initialize` excluded from exports; `__self` params skipped.** Compile log prints `WIT: <path>` alongside the existing `WAT: <path>` line. Four test files: `BasicWitGen_41`, `WitReturnTypes_41`, `WitWithExternalImports_41`, `Phase41Combined_41` — 146/146 suite |
| ✅ | 42 (2026-05-13) | String-returning user functions + chained struct field access + nested struct literals | **String-return side-channel:** string-returning functions (`function f(): string`) emit as `void` WAT functions; on `return expr`, `emitStringPtrLen` evaluates the expression and stores ptr/len into module-level mutable globals `$__str_ret_ptr` / `$__str_ret_len`; call sites read the globals immediately after `(call $fn args)`. Wired into `emitStringAssign` (string variable init from function call), `parseSingleArg` in `console_log.ts` (detect string-returning calls for `console.log`), template literal emission, and the binary-ops string-comparison path in `emitExpr`. `needsStringRetGlobals` flag on `WasicTranspiler` gates emission of the two globals in the WAT header. **Chained struct field access:** `seg.from.x`, `box.topLeft.y` — `emitExpr` detects `a.b.c` patterns, loads the intermediate struct pointer from the parent field, then loads the leaf field from that pointer (two-level `i32.load`/`f64.load` chain). **Nested struct literals:** `{ from: { x: 1.0, y: 2.0 }, to: { x: 7.0, y: 8.0 } }` — pre-scan and `allocStructData` parse inline nested struct initializers and recursively allocate sub-struct data in the WAT data section. **Nested struct field as function argument:** `describePoint(seg.from)` — when the argument expression is a struct-typed field access, `emitExpr` emits the i32 pointer to the nested struct (loaded from the parent struct's field offset) as the call argument. **`struct-embedding_42.ts`** (previously failing Go-by-Example test) now passes — 215/219 Go-by-Example. Three new wasic test files: `ChainedFieldAccess_42`, `StructFieldArg_42`, `Phase42Combined_42` — 149/149 suite |
| ✅ | 43 (2026-05-14) | String arrays as function parameters | **`string[]` params:** string array parameters registered in `arrayVars` with `dynamic: true, isStringArr: true`; 8-byte-per-element interleaved layout (`[ptr i32, len i32]` pairs, shift=3); `arr[i]` inside the function body returns a ptr+len pair via `emitStringPtrLen`. **Higher-order functions with `(s: string) => boolean` callbacks:** `getOrCreateFuncType` expands `"string"` to two `"i32"` (ptr+len) via `flatMap` — a callback typed `(s: string) => boolean` registers functype `$ftype_i32_i32_r_i32`; `funcTypeVars` dispatch path uses `emitStringPtrLen` for each `string`-typed argument so `call_indirect` receives the correct ptr+len pair. **`string[]` return type:** `strFilter(arr, pred): string[]` functions return an i32 array pointer; call sites store the pointer in an `arrayVars` entry with `isStringArr: true`. **Cross-module signaling via singletons in `console_log.ts`:** `setStrCmpNeededCallback` (fires `needsStringHelpers = true` when `exprToWat` emits `$__str_cmp`) and `setFuncTableLookup` (resolves function names to WASM table indices inside `exprToWat`) — both set by `wasic.ts` before `parseConsoleLogArgs`, cleared after. **Helper dependency fix:** `needsStringExtHelpers` alone now triggers `getStringOpHelperWat()` emission (`$__str_indexof` etc. available for `s[0] === "a"` char comparisons). Four test files: `BasicStringArrParam_43`, `StringArrHigherOrder_43`, `StringArrReturn_43`, `Phase43Combined_43` — 150/150 wasic suite, 221/226 total |
| ✅ | 44 (2026-05-14) | Function pointer arrays (`Array<FunctionType>`) | **`Array<() => void>` detection (three sites):** (1) `detectModuleArrayGlobals()` regex `Array<((?:[^<>]\|=>)*)>` added before the `T[]` match — regex uses `(?:[^<>]\|=>)*` so `=>` inside the type argument is not consumed as `>`; sets `isFuncPtrArr` on the `ArrayInfo` entry; (2) `emitFunction` pre-scan handles local `Array<FuncType> = []` declarations; (3) `startBodyLines` pre-scan seeds from `moduleArrayVars`. **`liftStartBodyArrows()` — new second-pass method:** `liftInlineArrows()` runs before `parseTopLevel()` so `startBodyLines` is empty; a second pass after `parseTopLevel()` creates a synthetic `_start` `FuncDef` with `bodyLines = [...startBodyLines]` and passes it as `enclosingFn` to `substituteOneArrow` — this allows module-level capturing closures (`defer(() => console.log(n))` in a `for` loop) to generate factory/trampoline pairs with correct outer-scope capture analysis. **`emitStatement` additions:** `funcArrLetMatch` handler for `Array<...> = []` calls `emitDynArrayInit`; `arrLenAssign` handler for `arr.length = N` emits `(i32.store ptr val)`; `funcPtrArrCallMatch` handler for `arr[idx]()` emits `(local.set $__fn_tmp (i32.load elemAddr)) (call_indirect (type $ftype_i32_r_void) (local.get $__fn_tmp) (i32.load (local.get $__fn_tmp)))` — loading the closure struct ptr from the i32 element, then reading the trampoline table index from offset 0 of that struct. **`$__fn_tmp` local:** declared in both pre-scans when any body line references a function pointer array via `name[`. **`substituteOneArrow` bug fix:** expression-body arrows (`() => expr`) previously called `inferInitType(expr, ...)` whenever `anonResult === null`, including when `paramInfo.result === null` (the callee explicitly declared `() => void`). JavaScript's `??` operator coalesces `null` (e.g. `null ?? fallback = fallback`), losing the explicit void signal — `inferInitType` would then return `"f64"` as its default fallback, giving the anonymous function `(result f64)` instead of `void`. Fix: changed the condition from `if (anonResult === null)` to `if (anonResult === null && paramInfo === undefined)` so inference only runs when no callee type info is available at all. Without this fix, `() => console.log(n)` generated a trampoline with `(result f64)` causing a `call_indirect` signature mismatch at runtime. **Result:** `defer.ts` and `exit.ts` Go-by-Example tests now pass. Two new test files: `defer_44.ts`, `exit_44.ts` — 152/152 wasic suite, 224/226 total |
| ✅ | 45 (2026-05-15) | `Math.imul` + unsigned right shift (`>>>`) + hex literals | **`Math.imul(a, b)`:** emits `(i32.mul (i32.trunc_f64_s a) (i32.trunc_f64_s b))`; wrapped in `(f64.convert_i32_s ...)` when `defaultType` is f64 so the result is stored correctly in a `number` variable. **`>>>` unsigned right shift:** added to `binaryOps` table with `alwaysI32=true`; the alwaysI32 promotion block uses `f64.convert_i32_u` (unsigned) for `>>>` instead of the signed `f64.convert_i32_s` used by other bitwise ops — correctly implements the JavaScript `>>> 0` unsigned-view idiom. **Hex literals** (`0x6D2B79F5` etc.): added handler in `emitExpr` immediately after the decimal numeric literal check; `/^0[xX][0-9a-fA-F]+$/` → `parseInt(expr, 16)` → `(i32/i64/f64.const n)` based on `defaultType`. **f64→i32 truncation for arithmetic in i32 context** (Fix 3): when `baseType === "f64"` and `defaultType` needs i32, wraps the binary expression with `(i32.trunc_f64_s ...)`; the `!STRING_CMP_OPS.has(op)` guard is critical — f64 comparison instructions (`f64.lt`, `f64.eq` etc.) already return i32 so wrapping them again is invalid. **Assignment guard for mutable closure captures:** compound-assignment `s = expr` now checks `currentClosureCaptureLayout.has(name)` in addition to `locals.has(name)` so assignments to closure-captured variables work correctly in inner functions. **Closure call result type:** `closureTypedVars` lookup added to the `lhsType` chain in the binary ops block so that a closure call expression (`r1()`) uses the declared return type (`f64`) rather than the storage type of the closure pointer (`i32`). **Test:** `random-numbers_45.ts` (mulberry32 PRNG with `Math.imul`, `>>>`, and hex constants) — 154/154 wasic suite, **226/226 total (all tests passing)** |
| ✅ | 46 (2026-05-15) | String escape sequence processing | **Root cause:** wasic read TypeScript source as raw text — `"\n"` was stored as two bytes (`\` + `n`) instead of one byte (0x0A), affecting both string variable assignments and `console.log` output. **`unescapeString(raw: string): string`** — new exported function in `src/console_log.ts`; fast-path via `!raw.includes("\\")` returns immediately; character-by-character walk otherwise. Handles all TypeScript/JavaScript escape sequences: `\n`→0x0A, `\r`→0x0D, `\t`→0x09, `\b`→0x08, `\f`→0x0C, `\v`→0x0B, `\0`→0x00, `\\`→`\`, `\'` `\"` `` \` `` → literal quotes, `\xHH` → byte with hex value HH, `\uHHHH` → UTF-8 of U+HHHH, `\u{H…}` → UTF-8 of variable-length code point; malformed sequences passed through unchanged. **Two fix locations:** (1) `allocString` and `allocStringNoLog` in `wasic.ts` — apply `unescapeString` to the raw source substring before writing to the WAT data section; `dataMap` keyed by the unescaped form so two spellings that unescape to the same bytes share one allocation; (2) `parseSingleArg` double/single-quote handlers and `parseTemplateLiteral` text-segment pushes in `console_log.ts` — `console.log` gather mode directly byte-encodes `{ kind: "literal" }` segments without going through `allocString`, so needed its own fix. **Safety:** `unescapeString` on compiler-internal strings (which already contain actual characters, not escape sequences) is a no-op — the fast-path `!raw.includes("\\")` exits immediately. Four test files: `BasicEscapeSeqs_46`, `TemplateEscapes_46`, `HexUnicodeEscapes_46`, `Phase46Combined_46` — 158/158 wasic suite, 230/230 total |
| ✅ | 47 (2026-05-15) | Class inheritance | **Overview:** `class Dog extends Animal` — field layout inheritance, `super(args)` constructor chaining, and static virtual dispatch via concrete-type tracking. **Field inheritance:** `parseClasses()` regex updated to capture `extends BaseName`; when found, parent struct fields (cloned via `{ ...pf }`) are prepended to the derived class's `fields[]` before the derived class's own fields are scanned; `fieldOffset` starts at `parentCd.struct.totalSize`. Multi-level chains work automatically because parent classes appear before derived classes in source order. **Class tag header:** after all classes are parsed, if `classInheritance.size > 0`, a 4-byte tag header is added to every class in the file — `classHeaderSize = 4`, all field offsets shift by `+4`, all `totalSize` values grow by 4; integer tags assigned in parse order via `classTags: Map<string, number>`; tag written to offset 0 of each instance in `allocStructData`. **`resolveMethodFunc(className, methodName): string \| null`** — new private helper; walks `classInheritance` chain to find the WAT function name (`current_methodName`) that implements a method, falling through to the parent if not found; called at all four method-dispatch sites in `emitExpr` and `emitStatement`. **Virtual dispatch via concrete-type tracking:** `newClassPre` pre-scan now prefers `ctorName` over `typeName` — `const a: Animal = new Dog(3)` registers `classVars.className = "Dog"`, so every subsequent `a.method()` call routes through `resolveMethodFunc("Dog", ...)` automatically (no runtime tag-based dispatch table needed for concrete-type variables). **`super(args)` handler:** inserted in `emitStatement` before `callMatch`; matches `/^super\s*\((.*)\)\s*;?$/` when `currentMethodClass` is a derived class; emits `(call $ParentName_constructor (local.get $__self) args...)`. **`structLookupFn` `this` handler:** added to both `structLookupFn` closures (console.log and console.error paths); when `vn === "this"` and `currentMethodClass` is set, looks up the field in `classDefs.get(currentMethodClass).struct.fields` and emits the correct `loadOp` with `(local.get $__self)` — enables `console.log("Age:", this.age)` inside method bodies. Five test files: `BasicClassInheritance_47`, `SuperConstructor_47`, `ClassMethodOverride_47`, `VirtualDispatch_47`, `Phase47Combined_47` — 163/163 wasic suite, **235/235 total (all tests passing)** |
| ✅ | stress tests + bug fixes (2026-05-24) | Phase 18 multi-scope scale + wasmbundle pipeline fixes | **Seven compiler fixes** to enable `18_Multi-ScopeScaleAndMemoryLongevityTest.ts` (350+ line stress test): (1) `Array.from({ length: N }, () => [])` source pre-pass replaced with `__arr_from_2d__(N)` sentinel BEFORE `parseFunctions()` — prevents `liftInlineArrows()` from lifting `() => []` into a spurious `$__anon_0` with wrong return type; (2) `arr2DPre` updated in both pre-scans to match the sentinel; (3) `Array<{ field: number; ... }>` anonymous struct fields map `number→i32` (not `f64`) — pointer/id semantics; (4) `const target = arr[i]` registers `target` in `structVars` when source array has `structTypeName` so `target.field` access resolves; (5) `tryAllocStructLiteralPtr` now uses `parseDepth0FieldsWithShorthand` and rejects any non-constant field via `isCompileTimeConst()` — falls through to `emitRuntimeStructLiteral` for runtime-variable struct literals; (6) `bracket2DMatch` coerces `f64[][]` element reads to `i32` when `defaultType === "i32"` via `(i32.trunc_f64_s ...)`; (7) `wasmmerge.ts`: mutable `(mut i32)` globals in imported `.wasm` modules are relocated to the page-2 boundary (131072) and `hasMutableGlobals` propagated so `compileWasiTs` pads memory to at least 3 pages. **Four wasmbundle bug fixes** (already in Phase 20 row): `getDataMaxEnd()` regex, ENTRY_ONLY strip guard, `_start` in export overrides, import-before-memory WAT ordering. **New test files:** `18_Multi-ScopeScaleAndMemoryLongevityTest.ts` (zero delta TS vs WASM), `18_WasmImportMerge.ts` (`@test-pipeline` 4-step bundle test). **259/259 wasic suite (prior to Phase 19 stress tests), +2 new tests.** |
| ✅ | stress tests (2026-05-24) | Phase 19 discriminated union edge cases | Three stress tests for discriminated union features (Phase 32) filed as Phase 19 stress tests in the `NN_Label` naming scheme: **`19_NestedDiscriminantUnions.ts`** — outer `Message` DU (text/image/system) each containing an inner DU; `formatMessage(msg)` switch dispatches on outer tag then accesses inner tag/fields; verifies correct nested tag comparison and field access across two switch levels → `Nested Add Result: 25`, `Nested Mul Result: 30`, `Failure Mapping: -404`. **`19_PolyMorphicUnionArrayMutation.ts`** — `Shape[]` array of mixed DU values (circle/rect/triangle); `scaleShapes(arr, factor)` mutates each element's radius/width/height in-place; `sumAreas()` computes total area per variant; verifies element mutation and field reads after mutation → `Calculated Combined Weight: 112`. **`19_VariantMaximumMemoryAlignment.ts`** — DU super-struct exercising all six i32/f64 field-type combinations; verifies all field offsets, `i32.load` vs `f64.load` dispatch, and that the struct layout correctly handles mixed-width fields → `Status Code Extracted: 200`, `Data Sum Extracted: 81`. All three have zero delta between TypeScript and WASM output. **261/261 wasic suite, 364/364 total.** |
| ✅ | stress tests + bug fixes (2026-05-25) | Phase 22 enum expression evaluation + heterogeneous enum support | Three stress tests added: **`22_NUmericEvaluationsAndFlagsShift.ts`** — bit-flag enum with `Read = 1 << 0`, `Admin = Write \| Execute`, `MaxBits` auto-incrementing from a computed value; verifies RHS expression evaluation produces `Admin = 6`, `MaxBits = 7`, and `(userPerm & targetBit) === targetBit` evaluates to true. **`22_HeterogeneousAndMixedStringEnum.ts`** — mixed enum `DeployEnv { Dev = "DEVELOPMENT", Staging = "STAGING", Prod = "PRODUCTION", Local = 0 }` used as a function parameter with `=== DeployEnv.Prod` and `=== DeployEnv.Local` comparisons; verifies string members get synthetic i32 tags so comparisons disambiguate while `console.log(DeployEnv.Prod)` still prints `"PRODUCTION"`. **`22_EnumObjectMemberCompoundMap.ts`** — `enum DeviceStatus` as a class field type; constructor `this.status = DeviceStatus.Offline`; method `updateStatus(next: DeviceStatus)`. (`22_CombinedStressTest.ts` for `const enum` + bigint was already passing.) **Two bug fixes (both in `parseEnums`):** (1) **Expression evaluation** (`wasic.ts` ~line 2384) — old regex `/(\w+)\s*(?:=\s*(?:(-?\d+)\|"…"\|'…')\s*)?\s*,?/g` only matched plain integers or string literals; for `Read = 1 << 0` it grabbed `1` and treated `<< 0` as a fake member. Rewritten to strip comments, split body at top-level commas via depth-tracked scan, parse each part as `name (= rhs)?`, and route the RHS through new private helper `evalEnumExpr(rhs, resolved)` which substitutes prior-member identifiers with their numeric values and evaluates via `Function('"use strict"; return (...);')()` with `\|0` i32 coercion. Supports `<<`, `>>`, `>>>`, `\|`, `&`, `^`, `+`, `-`, `*`, `/`, `%`, parens, and identifier refs to any previously-defined member. (2) **Heterogeneous enum comparison** — when an enum had both string and numeric members, string members had no `enumValues` entry, so `emitExpr("DeployEnv.Prod")` fell to the comment-stub `(i32.const 0)` and every `env === ...` comparison collapsed to compare-with-0. Added a third pass in `parseEnums` that detects heterogeneity and assigns synthetic integer tags to string members starting at `max(numeric) + 1`. `parseSingleArg` in `console_log.ts` (~line 405) now checks `enumStringLookup` BEFORE `enumLookup` so `console.log(DeployEnv.Prod)` still prints `"PRODUCTION"` while `env === DeployEnv.Prod` uses the i32 tag for comparison. Pure numeric and pure string enums are unaffected by the third pass. **270/270 wasic suite, 446/446 total** (270 wasic + 103 bindgen + 73 jstyper). |
| ✅ | stress tests + bug fixes (2026-05-25) | Phase 21 tuple destructuring + embedded class tuple fields | Three stress tests added: **`21_HeterogeneousTypeOffset.ts`** — `const record: [i32, f64, boolean] = [42, 3.14159, true]` + `const [id, value, active] = record` with mixed-type tuple fields and natural alignment; **`21_SkippedElementsAndGaps.ts`** — `const [coordX, , coordY] = coordinates` with positional gap (`, ,`); verifies skipped slots advance the field index so `coordY` reads index 2 (`20`), not index 1 (`999`); **`21_NestedCompoundTuple.ts`** — `class NodeMetric { bounds: [i32, i32]; }` embedded class tuple field; constructor `this.bounds = [min, max]` writes inline; `const [lower, upper] = metric.bounds` destructures via pointer arithmetic on the class layout. **Four bug fixes:** (1) **Gaps in destructuring** (six sites in `wasic.ts`: `arrDestructMatch`/`arrDestructPre`/`arrDestructPre2` array sources + `tupleArrDestructStmt`/`tupleDestructPre`/`tupleDestructPre2` tuple sources) — all used `.split(",").map(trim).filter(Boolean)` which silently removed empty-string bindings; fixed by removing `filter(Boolean)` and adding `if (b === "") continue;` (or `idx++; continue;` for the array path) inside each emission/pre-scan loop so positional indices advance correctly across gaps; (2) **Embedded tuple class fields** (`parseClasses` ~line 2845) — new `(\[[^\]]+\])` regex tried before the existing `[\w\[\]]+` pattern; on match, the field is embedded inline at `tdef.totalSize` bytes (aligned by the first tuple element's natural size) with `tupleTypeName` set on the `StructField`; `StructField` interface gained optional `tupleTypeName?: string`; (3) **Constructor inline-tuple writes** (`thisWriteMatch` ~line 6946) — when the field has `tupleTypeName` and the RHS is a tuple literal, emit per-element `(i32.store offset=fieldOff+tf.offset (local.get $__self) val)` instead of the dynamic-array allocation path that previously generated an undeclared `$__arr_tmp` local; (4) **`const [a, b] = obj.field` destructure from embedded tuple field** — new `tupleFieldDestructStmt` handler in `emitStatement` + matching `tupleFieldDestructPre`/`tupleFieldDestructPre2` in both pre-scans; detects `[bindings] = receiver.field` where receiver is in `classVars` and the named field has `tupleTypeName`; emits per-field `(local.set $bind (loadOp offset=cf.offset+tf.offset baseWat))` with the WAT-correct `offset=N` modifier preceding the address argument. **267/267 wasic suite, 443/443 total** (267 wasic + 103 bindgen + 73 jstyper). |
| ✅ | stress tests + bug fixes (2026-05-24) | Phase 20 array rest destructuring edge cases | Three stress tests for array destructuring with rest syntax (`const [a, b, ...rest] = arr`): **`20_RestBufferSplitting.ts`** — `const [alpha, beta, ...omega] = source` where `source: i32[] = [100, 200, 300, 400]`; verifies static array element extraction with correct 8-byte header offset and rest array copy; `omega.length === 2`, `omega[0] === 300`, `omega[1] === 400`. **`20_EmptyRestAllocationAndSafety.ts`** — `const [first, second, ...remainder] = smallPair` where `smallPair: i32[] = [55, 66]`; rest array is empty (length=0, capacity=8 baseline); verifies `.push(77)` correctly expands the empty rest array without heap corruption. **`20_NestedDestructuringAndOjectMix.ts`** — `const [leadPoint, ...trailingPoints] = points` where `points: Coordinate[] = [{ x:1, y:10 }, ...]`; multi-line struct array literal in function body; `leadPoint.x === 1`, `trailingPoints.length === 2`, `trailingPoints[0].y === 20`. **Four bug fixes:** (1) static array element loads in `arrDestructMatch` now add `+8` to skip the 8-byte `[length, capacity]` header (both simple-binding and rest-copy sites); (2) `parseFunctions` body-line joiner now joins multi-line `const arr: T[] = [...]` declarations (bracket-depth counting) so `arrPre` regex can process them; (3) `arrDestructPre` pre-scan propagates `structTypeName` from the source array to simple bindings (via `structVars`) and the rest binding (via `arrayVars`); (4) `arr[idx].field` access in `console.log` added — new `arrElemDotMatch` handler in `parseSingleArg` (`console_log.ts`) routes to `structLookupFn("arr[idx]", "field")`, and both `structLookupFn` closures now handle the bracket-form virtual `vn` by loading the struct pointer from the array element then loading the named field. **264/264 wasic suite, 367/367 total.** |
| ✅ | stress tests + bug fix (2026-05-24) | Phase 47 class inheritance — `super.method()` in overrides and runtime vtable dispatch from arrays | **`super.method(args)` in non-constructor method bodies:** two new handlers — `superDotExprMatch` in `emitExpr` (matches `/^super\.(\w+)\s*\((.*)\)$/`, used when `super.method()` appears as a sub-expression) and `superMethodStmt` in `emitStatement` (statement-level form); both look up `classInheritance.get(currentMethodClass)` for the parent, call `resolveMethodFunc(parent, methodName)`, and emit `(call $ParentClass_method (local.get $__self) args...)`. **`arr[idx].method(args)` runtime vtable dispatch:** new `emitExpr` handler (`arrMethodCallRe`) matching `/^(\w+)\[([^\]]+)\]\.(\w+)\s*\((.*)\)$/`; checks `arrayVars` for `structTypeName` + `classDefs.has(structTypeName)`; computes the element pointer (i32 load from array at shift=2); when `classHeaderSize > 0` calls `findSubclasses(baseClass)`, sorts by `classTags`, builds a nested if-else dispatch chain reading the class tag at offset 0 of each element pointer — last class is the default. **`findSubclasses(baseClass)` helper:** new private method; iterates `classDefs.keys()` and walks each class's `classInheritance` chain to find all classes that are (or transitively extend) `baseClass`. **Class tag bug fix:** `emitExpr` `new ClassName(args)` handler now passes `this.classTags.get(ctorClassName)` to `allocStructData` — previously, the 4-byte tag at offset 0 was only written for `const obj = new ...` assignment patterns (in the pre-scan); inline `new` inside expressions like `arr.push(new Square(5))` left the tag as zero, causing all vtable reads to return 0 (no dispatch match). Three new stress test files: `17_ConstructorChainingAndFieldPrefixOffest` (three-level super constructor chain + multi-level field access), `17_Cross-PolymorphicArrayStride` (`Shape[]` holding `Square`/`Rectangle`/`Shape` — runtime dispatch via class tag → `Total Combined Area: 49`), `17_DeepHierarchyCTable` (`ExecutiveAccount extends PremiumAccount extends Account` — `super.calculateBonus()` in override + base-typed variables → `Executive Bonus: 80`). **257/257 wasic suite, 360/360 total.** |
| ✅ | 48 (2026-05-15) | Language completeness: Number API, operators, control flow | **`Number.*` constants:** `NUMBER_CONSTS` lookup map added in `emitExpr` (`wasic.ts`) and `exprToWat` (`console_log.ts`) — `Number.NaN→(f64.const nan)`, `Number.POSITIVE_INFINITY→(f64.const inf)`, `Number.NEGATIVE_INFINITY→(f64.const -inf)`, `Number.EPSILON→(f64.const 2.22e-16)`, `Number.MAX_SAFE_INTEGER→(f64.const 9007199254740991)`, `Number.MIN_SAFE_INTEGER→(f64.const -9007199254740991)`, `Number.MAX_VALUE→(f64.const 1.7976931348623157e308)`, `Number.MIN_VALUE→(f64.const 5e-324)`. **`Number.*` predicates:** `Number.isNaN(x)→(f64.ne x x)` (NaN ≠ itself); `Number.isFinite(x)→(i32.and (f64.lt x inf) (f64.gt x -inf))`; `Number.isInteger(x)→(f64.eq (f64.floor x) x)`. **`dotCallLookup` guard:** added `!token.startsWith("Number.")` alongside the existing `!token.startsWith("Math.")` guard so `Number.isNaN(x)` is not misrouted through the dot-call i32 path. **`parseSingleArg` boolexpr ordering fix (critical):** the entire boolexpr detection block (comparisons, `&&`, `\|\|`, `!`) moved BEFORE the `Number.*` and `Math.*` handlers — without this, `Number.MAX_SAFE_INTEGER > 1e16` was caught by the `Number.*` guard and returned `f64expr`, causing `$__f64_to_str` to receive the i32 result of `f64.gt` (WAT type error). **Scientific notation literals:** numeric literal regex extended from `/^-?\d+(\.\d+)?$/` to `/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/` in both `emitExpr` (`wasic.ts`) and `exprToWat` / `parseSingleArg` (`console_log.ts`) so `1e16`, `3.5e-4`, etc. are recognized. **`**=` compound assignment:** new `expAssignMatch` handler in `emitStatement` before `compoundMatch`; uses `$__math_pow` via `mathHelpers.add("math_pow")`; supports locals and module globals. **`$__math_pow` sqrt special case:** early-return branches added for `exp === 0.5` → `(f64.sqrt base)` and `exp === -0.5` → `(f64.div 1 (f64.sqrt base))` before the integer-exponent loop. **Object destructuring with defaults:** `destructMatch` block updated with 4-form binding parser (`"field"`, `"field = default"`, `"field: local"`, `"field: local = default"`); when default present, emits `(if (result T) (eqz loadWat) (then defWat) (else loadWat))` with zero-sentinel semantics (default fires when field is 0). **Labeled `continue` and switch fallthrough:** verified already implemented — no code changes needed. Seven test files: `NumberConstants_48`, `NumberPredicates_48`, `SwitchFallthrough_48`, `ObjectDestructDefault_48`, `LabeledContinue_48`, `ExponentAssign_48`, `Phase48Combined_48` — 170/170 wasic suite, 242/242 total |
| ✅ | 49 (2026-05-15) | Optional chaining and collection method completeness | **`?.` optional chaining:** global source pre-pass `src.replace(/[?][.]/g, ".")` at the start of `transpile()`, before `expandGenerics` — all `?.` on non-nullable types is stripped at compile time (safe because wasic's closed-world; nullable types use explicit `!== null` ternary per Phase 24). **`String.prototype.at(n)`:** inline pointer arithmetic without calling `$__str_char_at` (which returns multi-value `(result i32 i32)`): `normIdx = (select n (i32.add len n) (i32.ge_s n (i32.const 0)))`, result is `(ptr+normIdx, 1)`; added to `emitStringAssign` (`strAtAssignM`), `emitStringPtrLen` (`strAtSPLM`), `appendConcatPart` (`strAtCP`), and `parseSingleArg` in `console_log.ts` (returns `strexpr`). Prologue checks extended to include `.at(` alongside `.charAt(` and `.slice(`. **`Array.prototype.concat(other)`:** added `concat` to `dynArrMethod` dispatch regex with `parenDepthNeverNegative` guard; delegates to existing `$__dynarr_concat_T` helper (already present from Phase 13 spread literals) — no new WAT generation needed. **Chained array method calls** (`arr.filter(f).map(g)`): new `splitLastMethodCall(expr)` private method (backward balanced-paren scan → finds outermost `.method(args)` split) and `inferChainElemType(expr, locals)` (recursively infers element type of chained expression via `arrayVars` or method-type rules). Chain dispatch block after `dynArrMethod` block: when `parenDepthNeverNegative` fails (unbalanced `argsStr` = chained expression), `splitLastMethodCall` separates receiver and outer method; `emitExpr(receiver, "i32")` generates the inner call WAT inline as the first argument to the outer method call — no temp locals needed. Five test files: `OptionalChaining_49`, `StringAt_49`, `ArrayConcat_49`, `ChainedMethods_49`, `Phase49Combined_49` — 175/175 wasic suite, **247/247 total (all tests passing)** |
| ✅ | 50 (2026-05-18) | `bindgen`: TypeScript host binding generator | **Overview:** `wasmtk bindgen <file.wit>` reads a `.wit` interface file (produced automatically by Phase 41) and emits a self-contained TypeScript binding file with full ABI translation — no manual `WebAssembly` API usage required by the host. Completes the TypeScript-as-DLL model. **`src/bindgen.ts`** — new standalone module (pure regex/brace-counting, no external dependencies). `parseWit(src)` extracts `packageName`, `worldName`, `imports[]`, `exports[]` with types and params using regex over the WIT text. `kebabToCamel(name)` converts WIT kebab names to TypeScript camelCase for WASM export lookup; `kebabToWasmName(name)` converts to underscore format for Phase 40 `env` import keys. `generateBindings(witSrc, opts)` produces the complete TypeScript file: `ModuleExports` interface, optional `ModuleImports` interface (when WIT has `import` section), and `loadModule(source, imports?)` async function. **ABI translation in generated bindings (Canonical ABI — Stage 0):** numeric types (`s32`/`s64`/`f32`/`f64`) pass directly; `bool` params → `v ? 1 : 0`, returns → `result !== 0`; `string` params → `TextEncoder` → `cabi_realloc(0,0,1,len)` → ptr+len WASM args; `string` returns → allocate 8-byte return area via `cabi_realloc(0,0,4,8)`, pass as trailing arg, read `ptr`+`len` back via `DataView` → `TextDecoder`. **`--runtime` flag:** `deno` (default, `fetch` + `WebAssembly.instantiate`), `node` (`node:fs` + `readFileSync`), `bun` (`Bun.file().arrayBuffer()`). **`src/wasic.ts` changes:** (1) `watTypeToWit("string")` returns `"string"` (WIT-native type); (2) `generateWit()` emits `name: string` as a single param; (3) `toWat()` exports `cabi_realloc` and generates `$fn__cabi` shim wrappers for each exported string-returning function (Stage 0). **`main.ts` wiring:** `case "bindgen"`, `-o` / `--runtime` flags, help text. **`deno.json`:** `"./bindgen": "./src/bindgen.ts"` export added. Five test files: `math_50` (i32/f64 numeric round-trip), `booleans_50` (bool param/return normalization), `strings_50` (string param encoding + string return side-channel), `imports_50` (WIT import section + host callback wiring) — **102/102 bindgen assertions, 349/349 total** |
| ✅ | 52 (2026-06-11) | Leaf conveniences: `void` / chained assignment / `in` / `Array.from`-`of`-`isArray` / `String.fromCodePoint` | **`void expr;`** — evaluates for side effects, discards the result (`emitStatement`: void/string call re-emitted as a plain call statement; numeric result `(drop …)`). **Chained assignment `a = b = c = 0`** — `emitStatement` detects ≥2 top-level plain `=` (skips `==`/`===`/`=>`/`!=`/`<=`/`>=`/compound), requires bare-identifier targets, lowers to `c = 0; b = c; a = b` (rightmost first) reusing the normal assignment emitter (locals/globals/strings/types for free). **`"field" in obj`** — closed-world compile-time `1`/`0` in `emitExpr` via `findDepth0Keyword(" in ")` + new `structHasField` (resolves struct/class fields from `structVars`/`classVars`); print via a `boolean` local or an `if` condition. **`Array.from([…])` / `Array.of(…)`** — source pre-pass `expandArrayFromOf` (string-aware balanced scan, after the `Array.from({length})` 2D sentinel) rewrites to plain array literals, recursing for nested forms; non-literal `Array.from` left untouched. **`Array.isArray(x)`** — `emitExpr` closed-world const (`1` iff x is a known array/typed-array var). **`String.fromCodePoint(...)`** — UTF-8 encodes code point(s): constant args → static data string (`allocStringDecoded` + `constCodePoint`), single runtime arg → new `$__str_from_codepoint` WAT helper (1–4 byte UTF-8, multi-value ptr,len); wired into `emitStringAssign`, the concat path, `isStringExpr`, and the `$__str_op` prologue detectors. Bonus: `console_log.ts dotLenMatch` now resolves string `.length` (UTF-8 byte length) for local strings / module string consts / string globals (a pre-existing gap that also affected `fromCharCode`). Six test files: `52_VoidExpr`, `52_ChainedAssignment`, `52_InOperator`, `52_ArrayFromOf`, `52_StringFromCodePoint`, `52_Phase52Combined` — **307/307 wasic suite** (bindgen 103/103, jstyper 73/73). (Chained assignment later extended to member/element-target lvalues — `p.x = z = 5`, `arr[i] = w = 9`.) |
| ✅ | hybrid (post-Phase-50) | `hybrid`: TypeScript/WASM split compiler | **Overview:** `wasmtk hybrid <file.ts>` splits a mixed TypeScript file into a wasic-compiled WASM core and a TypeScript runner. Functions annotated with `// @wasm` on the immediately preceding line are extracted, compiled via `modc`, bound via `bindgen`, and replaced with `lib.funcName(...)` call sites in the generated runner. **Five-step pipeline:** parse → extract annotated functions into `_core.ts` → `modc` compiles `_core.ts` → `_core.wasm` + `_core.wit` → `bindgen` reads `_core.wit` → `_core.bindings.ts` → write `_runner.ts` with imports + `const lib = await loadModule(...)` + rewritten call sites. **`src/hybrid.ts`** — new standalone module. `parseHybridFile(src)` uses regex + brace-counting to extract annotated functions and return `{ wasmFuncs, remainingSrc, warnings }`; routes `async` functions that return `Promise<T>` (added 2026-06-15 — see the Async row below); warns on non-wasic types. `generateCoreModule()` writes the wasic-compilable module — for an async fn it emits an internal `f__impl` plus a synchronous unwrapping wrapper `f` (`return await f__impl(args)`), so the host gets a real value via bindgen. `generateRunner()` injects the binding import and `loadModule` call after the last `import` statement, then rewrites bare call sites via negative-lookbehind regex `(?<![."'\x60\w])funcName\s*\(` — method calls, string literals, and backtick expressions are preserved unchanged. Runner uses top-level `await` (native Deno ES module). **Prototype constraints:** `// @wasm` must be exact; only named `function` declarations; call-site rewriting is regex-based (not AST-based); module-level shared mutable state does not cross the WASM boundary; `@wasm` functions calling back into TypeScript require manual `declare const` Phase 40 import stubs. **Test fixtures:** `math_hybrid.ts` (i32/f64/bool), `strings_hybrid.ts` (string params/returns), `async_hybrid.ts` (async fns routed via sync wrappers). **New files:** `src/hybrid.ts`, `tests/hybrid/hybrid_fixtures/`. **Changed:** `main.ts` (`case "hybrid"`), `deno.json` (`"./hybrid"` export). |
| ✅ | #13 async (2026-06-15) | Async / Promises (v1) | **Full v1 Promise surface, standalone WASI.** `async`/`await`; `Promise.resolve`/`reject`; `.then`/`.catch`/`.finally` (named **and** capturing-closure callbacks); `Promise.all`/`Promise.allSettled`. Rejections integrate with `try/catch` (a rejected `await` re-throws the reason). Implemented as a small **inline microtask runtime** (emitted only when async is used) under an **eager-execution model**: async bodies run to completion and the microtask queue is drained at each `await` and at the end of `_start`, so ordering for sequential/`.then`-chained code matches V8. **v1 limits:** intra-module only (no real async sources/timers — there is no event loop in WASI Preview 1; awaiting a never-settling promise traps with a diagnostic); interleaving order across _concurrently_-pending async fns is not preserved (eager bodies); `Promise.all`/`allSettled` take an **array literal** of i32/f64-valued promises; `Promise.race`/`any` are out. `hybrid` routes self-contained async functions into the WASM core (above). 8 tests `54_*`–`61_*`. |
| ✅ | Stage 0 | Canonical ABI alignment | `cabi_realloc` + callee-allocated string returns + `cabi_post_<name>` |
| ✅ | Stage 0.6 | Allocator unification (`wasmmerge`) | merged libraries share one bump allocator / heap cursor |
| ✅ | Stage 0.7 | Tier-1 stdlib capabilities | shared-heap `modc` caps: `Set<i32>`, `Map<i32,i32>`, `Date`, `JSON`, `RegExp` |
| ✅ | dync | `any` / `unknown` / `symbol` / generic `object` | delivered via `wasmtk dync` (embedded dynamic runtime) — not by static `wasic`; `: any` / `eval(...)` in a `wasic` file auto-merges it |
| ✅ | dync | Mapped / template-literal / complex recursive conditional types | delivered via `wasmtk dync` — beyond `wasic`'s static type system |
| ✅ | dync | Prototype / dynamic `this`, dynamic property bags, `eval` / `Function()` | delivered via `wasmtk dync` — runtime object identity, beyond static WASM |
| ⏳ | — | Auto-`.wit` emission for the **Go / Zig / Rust** producers | only TypeScript (`wasic` / `modc`) auto-emits `.wit` today; the producers don't yet — Go `bindgen` currently uses a hand-written `.wit` |
| ⏳ | — | P2 **Component Model** container | deferred pending browser-native WASI P2; the ABI is already forward-aligned |
| ⏳ | — | `os.Exit` non-zero status propagation | `proc_exit(n)` works in wasmtime/wasmer; the Deno test shim treats all exits as success |
| ⏳ | — | Goroutines / channels / `select` (native `wasic`) | needs [Stack-Switching](https://github.com/WebAssembly/stack-switching) (WASI P3); works today via the Go producer's asyncify scheduler |
| ⏳ | — | Shared memory + atomics | needs the [Threads proposal](https://github.com/WebAssembly/threads); `wasi_threads` not standardized across P1 runners |
| ⏳ | — | True async suspension (timers, host I/O, cross-component `await`) | needs Stack-Switching / WASI P3; intra-module async already works |

### Notable Implementation Notes

- **Status.** All 50 wasic phases plus Stage 0 (Canonical ABI), Stage 0.6 (allocator unification),
  and Stage 0.7 (the Set/Map/Date/JSON/RegExp stdlib capabilities) are shipped. The DLL model —
  compile → `.wasm` + `.wit` → `bindgen` → host — is complete end-to-end; active work has moved to
  the polyglot ecosystem (see [`cmem/vision.md`](cmem/vision.md)).
- **Canonical ABI (Stage 0).** Exports use `cabi_realloc`, `(ptr, len)` string params, and
  callee-allocated string returns paired with a `cabi_post_<name>` release export — a WASI-P1 core
  module + sidecar `.wit`; only the P2 Component-Model container is deferred (see
  [`cmem/polyglot-producers.md`](cmem/polyglot-producers.md)).
- **Backends.** wasmtk runs on the dual JSR TypeScript toolchain `jsr:@jrmarcum/wabt-ts` +
  `jsr:@jrmarcum/binaryen-ts` (no Emscripten blobs). wabt-ts 1.3.0/1.3.1 fixed a
  call-before-`return` encoder bug and hex-float-literal parsing; binaryen-ts 1.3.2/1.3.4 fixed a
  doubly-merged optimizer miscompile and an exception-aware `-Oz` CoalesceLocals bug.
- **Output-diff hardening.** The test runner compares run-ts vs run-wasm OUTPUT (not just exit
  codes); that audit surfaced and fixed ~14 silently-wrong codegen bugs across exceptions, string
  formatting, struct-field mutation, `for…of`, and class-array literals.
- **Fully-dynamic features** (`any`/`unknown`/`symbol`/`object`, dynamic `this`, `eval`, mapped &
  template-literal types) are **✅ delivered via `wasmtk dync`** — they're out of static `wasic`'s
  scope, but the toolkit runs them through the embedded dynamic runtime (use `wasmtk dync` whole-file,
  `wasmtk hybrid` for a typed+dynamic mix, or `: any` / `eval(...)` inside a `wasic` file).
- **The ⏳ rows** are the genuinely-pending items: small deferred work (Rust/Zig/Go `.wit` emission,
  the P2 container, `os.Exit` propagation), or features blocked on an upstream WASM proposal —
  Stack-Switching (goroutines / channels / true async suspension) and Threads (shared memory /
  atomics). Goroutines, channels, and `select` **already work today** via the Go producer's asyncify
  scheduler.
