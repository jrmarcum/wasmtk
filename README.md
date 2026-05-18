# wasmtk

<p align="center">
  <img src="wasmtk_logo.png" alt="wasmtk logo" width="300">
</p>

A polyglot WebAssembly toolkit for Deno. Compile TypeScript directly to optimized WASM via the `wasic` compiler, run and inspect modules from any source language, and compose multi-language projects into a single artifact.

## 🌟 Why wasmtk?

`wasmtk` is the home of **`wasic`** — a direct TypeScript-to-WASM compiler that emits optimized WAT with no embedded JavaScript runtime. It also provides a complete toolkit for running, inspecting, and composing WASM modules from any source language.

- **`wasic` compiler**: Compile a TypeScript subset directly to optimized `.wasm` via WAT + wabt + Binaryen `-Oz`. Supports 49 language phases including closures, generics, classes, inheritance, discriminated unions, TypedArrays, and more — all without an embedded JS runtime.
- **WIT interface generation**: Every compiled module automatically produces a `.wit` file describing its exports and imports — the foundation for cross-language interop and the WASM Component Model.
- **Universal running**: Execute `.ts`, `.js`, `.wasm`, and `.wat` with a single command across Deno, Bun, and Node. Expanded WASI syscall shims ensure compatibility with modules compiled from Zig, Rust, C/C++, and Go.
- **Library mode (`modc`)**: Compile TypeScript to a WASM library with no `_start` entry point — callable from any host environment.
- **WASM bundling**: Merge multiple `.wasm` files into a single artifact; import pre-compiled `.wasm` modules directly from TypeScript source via `tsbundler`.
- **jstyper**: Convert `.js` + `.d.ts` pairs to typed TypeScript that `wasic` can compile — bridges existing JS libraries into the WASM pipeline.

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

Bun installs global binaries to `~/.bun/bin`. Ensure this directory is on your `PATH` so the `wasmtk` command is available system-wide:

macOS / Linux — add to `~/.bashrc`, `~/.zshrc`, or your shell's profile:

```bash
export PATH="$HOME/.bun/bin:$PATH"
```

Windows — use PowerShell to set the environment variable permanently without risking truncation of your existing `PATH`. If you have local user privileges only, set it at the user level (no admin required):

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

Bun requires a one-time registry configuration so it can resolve JSR packages. The `.npmrc` file must be placed in `~/.bun/bin` — the same directory where Bun installs global binaries. Create or edit it with the following command for your platform:

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

## 📁 Project Structure

```text
wasmtk/
├── main.ts              # CLI entry point
├── deno.json            # Deno configuration, tasks, and JSR exports
├── package.json         # Minimal npm shim — bin field for Bun global install
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
├── scripts/
│   └── sync-version.ts  # Version sync — propagates deno.json version → package.json + src/utils.ts
├── tests/               # Test suite
│   ├── wasi_tests.ts
│   ├── bundle_tests.ts
│   ├── mod_tests.ts
│   ├── wasi_javy_tests.ts
│   ├── wasm_wasi/       # wasic test programs (one per feature/phase)
│   ├── wasm_wasi_bundle/
│   ├── wasm_wasi_javy/
│   └── wasm_mod/
└── README.md

```

### Development tasks

| Task | Command | Notes |
| --- | --- | --- |
| Local install | `deno task install` | Syncs version, caches deps, installs global `wasmtk` binary |
| Publish to JSR | `deno task publish` | Syncs version, then runs `deno publish` |
| Bump version | Edit `version` in `deno.json`, then `deno task update-version` | Propagates to `package.json` and `src/utils.ts` automatically; `install` and `publish` call this automatically |
| Dev watch | `deno task dev` | Runs `main.ts` with `--watch` |

---

## 🔨 Compiler Options

wasmtk provides three distinct compilation paths. Choosing the right one depends on what your program needs at runtime.

---

### `wasmtk wasic` — Direct TypeScript-to-WASM (WASI Standalone)

Compiles a TypeScript or WAT source file to a **standalone WASI module** with no embedded JavaScript runtime. Two input paths are supported:

- **`.ts`** — runs through the tsbundler import pre-pass, WasicTranspiler, wabt, and Binaryen `-Oz`
- **`.wat`** — assembled directly by wabt and optimized by Binaryen `-Oz` (no transpiler step)

```bash
wasmtk wasic myprogram.ts       # TypeScript → WAT → optimized .wasm
wasmtk wasic myprogram.wat      # WAT → optimized .wasm (direct, no transpiler)
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
| String enums | `enum Dir { Up = "up", Down = "down" }` — members resolve to static string data; usable in `console.log` and `const x: string = Dir.Up` assignments |
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
| Escape sequences | `\n` `\r` `\t` `\b` `\f` `\v` `\0` `\\` `\"` `\'` — correctly decoded to the single intended byte; `\xHH` hex escapes; `\uHHHH` and `\u{H…}` Unicode code points (UTF-8 encoded); works in both double-quoted strings and template literals |
| `.length` | Returns character count as i32 |
| Comparisons | `===`, `!==`, `<`, `>`, `<=`, `>=` — lexicographic |
| Template literals | `` `x=${x} y=${y}` `` — numeric and string interpolation; escape sequences processed in all static text segments |
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

##### External Interface Bindings

| Feature | Notes |
| --- | --- |
| Inline external binding | `declare const host: { log(ptr: i32): void; getTime(): i32 }` — each method compiles to `(import "env" "host_log" ...)` and `(import "env" "host_getTime" ...)` in the WASM binary |
| Named external interface | `declare interface Logger { log(ptr: i32): void }` then `declare const logger: Logger` — two-declaration form; interface can be reused across multiple bindings |
| Multiple external bindings | Any number of `declare const` / `declare interface` bindings in one file; each gets its own set of `(import "env" ...)` declarations |
| Supported method types | Parameters and return types: `i32`, `i64`, `f32`, `f64`, `bool`, `void` — same type set as the wasic function ABI |
| Call-site verification | Methods called on the binding are type-checked at compile time against the declared signature |
| Host stub proxy | The test runner provides a no-op Proxy for `env` imports — any undeclared method returns `0`; real host implementations replace these stubs |

##### WIT File Generation

After every successful `wasmtk wasic` or `wasmtk modc` compilation a `.wit` file is written alongside the `.wasm` output.

| Feature | Notes |
| --- | --- |
| Automatic generation | `.wit` written at the same path as the output `.wasm` (e.g. `mylib.wasm` → `mylib.wit`) with no extra flags required |
| Export section | Each `export function` becomes a WIT `export name: func(...)` declaration; internal runtime helpers and closure factories are excluded |
| Import section | Phase 40 external bindings that are actually called in the source become WIT `import name: func(...)` declarations |
| WIT types | `i32→s32`, `i64→s64`, `f32→f32`, `f64→f64`, `bool→bool`; `void` return → no `-> type` clause |
| Kebab-case names | Function names are automatically converted to WIT-compliant kebab-case (e.g. `logMessage` → `log-message`) |
| Package format | `package local:module-name; world module-name { ... }` |

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
| `String(e)` in catch | Same as `e` — `String(varName)` where `varName` is a string local passes through as the same ptr/len pair |
| `e instanceof Error ? e.message : String(e)` | Idiomatic TypeScript try/catch pattern — both branches resolve to the caught string; compiles correctly to the `$e_ptr`/`$e_len` locals |

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

Patterns 1–3 route through a named function that `_start` calls. Patterns 4–5 collect the statements directly into the `_start` body. All five are recognized automatically — no annotation needed.

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
| Static fields | `static count: i32 = 0` → named WASM global `$Foo_count`; read as `Foo.count`, written as `Foo.count = val` from any context including constructors and static methods |
| Getters | `get prop(): T { }` → `Foo_get_prop(__self: i32): T`; `instance.prop` (no parens) dispatches to getter in expression, statement, and `console.log` contexts |
| Setters | `set prop(val: T) { }` → `Foo_set_prop(__self: i32, val: T)`; `instance.prop = val` dispatches to setter |
| `this.field` read/write | Load/store at field offset from `__self` pointer; getter/setter dispatch checked first |
| `new Foo(args)` | Allocates struct in linear memory (static); calls constructor |
| `instance.method(args)` | Dispatches to `Foo_method(instancePtr, args...)` |
| `Foo.staticMethod(args)` | Dispatches to `Foo_staticMethod(args...)` |
| `instance.field` | Field read/write via instance pointer in classVars; getter/setter checked before raw load/store |
| Class instance params | Functions accepting `obj: Foo` receive an `i32` struct pointer |

#### Current Limitations

| Feature | Status |
| --- | --- |
| Multi-dimensional arrays beyond `i32[][]` | Phase 6d covers `i32[][]`; `f64[][]` and deeper nesting not yet implemented |

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

### `wasmtk run` — Multi-Format Executor

Runs a file directly. Accepts four input formats:

| Input | Behavior |
| --- | --- |
| `.wasm` | Instantiates and executes the WASM module via the built-in WASI runtime |
| `.wat` | Assembled by wabt, then executed as above |
| `.ts` | Passed through to the Deno/Bun runtime (`deno run -A` / `bun run`) — not compiled to WASM |
| `.js` | Same passthrough to the Deno/Bun runtime |

```bash
wasmtk run myprogram.wasm
wasmtk run myprogram.wat
wasmtk run myprogram.ts
wasmtk run myprogram.js
```

The `.ts` and `.js` paths are native runtime passthrough — they do not go through wasic or any WASM compilation step. Use them to run a TypeScript file as-is for comparison against its compiled WASM output.

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
| enhancement | Test runner `// @expect-fail` marker for negative tests | `wasi_tests.ts` reads `// @expect-fail: compile, run-ts, run-wasm` from the first 10 lines of any test file. `runStep` accepts an `expectedFail` flag and prints `✓ compile failed as expected` for expected failures. A step that fails-as-expected counts as OK in the verdict; run-wasm is treated as N/A when compile fails as expected. Overall result prints `✅ PASSED (expected failures: compile)`. `ExternalMapping_11b.ts` uses `// @expect-fail: compile` — 86/86 suite |
| bug fix | `tsbundler` `applyRenames` mangled `console.log` in imported modules | When a non-entry module exported a function whose name matched a built-in method (e.g. `export function log(...)`), `applyRenames` renamed every occurrence including `console.log(...)` — turning the function body into an empty stub (no WASI output). Root cause: lookbehind `(?<!\w)` allows a match after `.` because `.` is not a word character. Fix: changed to `(?<![\w.])` so a dot before the identifier prevents the match; `console.log` and all other method-call forms are left untouched while standalone call sites are correctly renamed. `ExternalMapping_11c.ts` — 85/85 suite |
| bug fix | `arr.find()` printed raw sentinel instead of `undefined` | `console.log(notFound)` where `notFound = arr.find(isNeg)` and no element matched printed `-1` (i32 sentinel) or `NaN` (f64 sentinel) instead of `undefined`, diverging from TypeScript semantics. Fix: `emitStatement` now tracks variables declared from `.find()` calls in `findResultVars`; when a `findResultVar` is the sole argument to `console.log`, the emitter wraps the print in a sentinel check — `(if (i32.eq val (i32.const -1)) (then print "undefined\n") (else print val))` — so not-found results display `undefined` exactly as TypeScript does. `ArrayMethods_12.ts` — 85/85 suite |
| perf fix (2026-04-17) | `runWasi` library-detection no longer double-compiles | `checkIsLibrary(path)` called a redundant `WebAssembly.compile()` after `WebAssembly.instantiate()` had already succeeded. Fix: inline check `!wasiInstance.exports._start` on the live instance — eliminates one disk read and one compile round-trip for library-call paths |
| cleanup (2026-04-15) | Removed `asc` (AssemblyScript) dependency | `compiler.ts` deleted — `runAssemblyScriptCompiler` and `runJavyCompiler` were exported but never imported by any other module in the project; `asc` (`npm:assemblyscript`) removed from `deno.json` imports; `./compiler` removed from `deno.json` exports; `modc` exclusively uses `compileLibTs` from `wasic.ts` — no AssemblyScript toolchain required at any point in the compilation pipeline |
| bug fix (2026-04-15) | `Math.round` semantics corrected to round half away from zero | `Math.round` was compiled to `f64.nearest` (IEEE 754 round-to-nearest-even / banker's rounding), causing `Math.round(2.5)` → `2` instead of the JavaScript-correct `3`. Fix: both `wasic.ts` (F64_UNARY table) and `console_log.ts` (exprToWat Math handler) now emit `(f64.floor (f64.add x (f64.const 0.5)))`, which matches JavaScript's "round half away from zero" rule for all normal values |
| bug fix (2026-04-15) | `$__f64_to_str` upgraded to ×1e15 / i64 — 15-digit precision | `$__f64_to_str` in `console_log.ts` upgraded from ×1e6 (6 decimal digits, i32 arithmetic) to ×1e15 (15 decimal digits, i64 arithmetic): `$fdigits` promoted from `i32` to `i64`; divisor and modulus changed to `i64.const 10`; digit extracted via `i32.wrap_i64`; loop count raised from 6 to 15; `f64.nearest` wrapping added before `i64.trunc_f64_s` to correct truncation error from f64 values that sit slightly below their true decimal (e.g. `3.14159` stored as `3.14158999…` → frac×1e6 was `141589.999…` → truncated to `141589` → printed `3.141589`; now rounds to `141590` → prints `3.14159`). Output now matches JavaScript for all but a small number of values requiring 17 significant digits (e.g. `Math.SQRT2` → JS `1.4142135623730951`, WASM `1.414213562373095`), a known JavaScript quirk where the f64 bit pattern requires 17 digits to guarantee round-trip uniqueness |
| 24 (2026-04-17) | `null` / `undefined` as values; `T \| null` returns | Nullable variable declarations (`const x: i32 \| null`) emit two WAT locals — `$x` (value) and `$x__null` (i32 flag, 1=null); nullable function returns (`function f(): i32 \| null`) use a module-level `$__nullable_ret_flag` global as a side-channel (callee sets to 1=has-value or 0=null, caller reads immediately after call); `parseNullableAnnotation()` helper strips `\| null \| undefined` and returns the inner `WatType`; null comparisons (`x === null`, `x !== null`) compile to `(local.get $x__null)` / `(i32.eqz (...))`; `console.log(x)` of a nullable var prints `"null"` when flag is set and the normal value otherwise; `null` / `undefined` literals added to `console_log.ts` `parseSingleArg`; pre-scans in both `emitFunction` and `startBodyLines` detect `T \| null` type annotations and register both locals; `nullableVarInnerType` map reset at start of each `emitFunction` call; `needsNullableResultFlag` flag gates `$__nullable_ret_flag` global emission — 87/87 suite |
| 25 (2026-04-17) | Nullish coalescing `??`, logical assignment `??=` `\|\|=` `&&=` | `??` handled before binary ops table in `emitExpr` — emits WAT `(if (result T) nullFlag (then rhs) (else lhs))` for nullable locals; pointer/string fallback uses `(i32.eqz ptr)`; `findBinaryOp` guards prevent `??` / `\|\|` / `&&` from matching `??=` / `\|\|=` / `&&=` (`after === "="` early-continue); `logicalAssignMatch` regex handles all three operators in `emitStatement` supporting both WAT locals (`local.get`/`local.set`) and module globals (`global.get`/`global.set`); `??=` for nullable locals clears the `__null` flag on assignment — 87/87 suite |
| 26 (2026-04-17) | `for...of` loops; array destructuring with default values | `for...of` over static `i32[]`, dynamic `i32[]`, `f64[]` arrays; `break` / `continue` inside loops; `for...of` over function-local dynamic arrays; array destructuring with defaults `const [a = 10, b = 20] = arr` — runtime length check on dynamic arrays; `$__forof_idx` (i32) shared local registered by pre-scans in both `emitFunction` and `startBodyLines`; **`parseTopLevel` `collectBlock` fix** — without this, module-level loop bodies were silently stripped because brace depth was never updated for top-level pattern-4 lines; static/dynamic/param access patterns differ (`i32.const` base / `i32.load` header / `local.get` base); pre-scan extracts binding name by splitting on `=` to avoid registering `"a = 10"` as a WAT local name — 88/88 suite |
| 27 (2026-04-18) | Extended string methods + Bun runtime compatibility | **String methods:** `trim`/`trimStart`/`trimEnd`, `charCodeAt`, `charAt`, `startsWith`, `endsWith`, `toUpperCase`/`toLowerCase` (ASCII), `replace`/`replaceAll`, `padStart`/`padEnd`, `repeat`, `split` → `string[]`; `for...of` over `string[]` with 8-byte `(ptr i32, len i32)` element layout; `isStringArr` flag on `arrayVars`; 15 WAT helper functions in `getStringExtHelperWat()`; **Bun compatibility:** new `src/rt.ts` runtime shim — `isBun` detection, unified `rt.readFile`/`writeFile`/`readTextFile`/`writeTextFile`/`mkdir`/`stat`/`remove`/`realPath`/`stdout`/`stderr`/`stdin`/`env`/`build`/`Command`; replaces all `Deno.*` call sites across 7 source files; `bunfig.toml` sets `@jsr` registry to `https://npm.jsr.io/`; `package.json` adds `bin` field for Bun global install; `"nodeModulesDir": "none"` in `deno.json` prevents Deno entering node_modules mode when `package.json` is present |
| bug fix (2026-04-18) | `switch` on `number`/`f64` variables; `String(e)` and `instanceof Error` ternary in catch | **`switch` f64 type:** `switch` on a `number`-typed (`f64`) variable emitted `i32.eq`/`i32.const`, causing a Binaryen assertion abort. Fix: switch emission detects the WAT type via `locals`/`moduleGlobals` and uses `f64.eq`/`f64.const` when the type is `f64`. **Catch string patterns:** `String(e)` and `e instanceof Error ? e.message : String(e)` in catch blocks emitted undefined `$String`/`$e` symbols. Fix: two early-exit guards in `parseSingleArg` (`console_log.ts`) — both patterns now resolve to the caught string's `$e_ptr`/`$e_len` locals — 88/88 suite |
| 28 (2026-04-23) | Extended array methods | `every(fn)`, `some(fn)`, `findIndex(fn)`, `at(i)`, `reverse()`, `fill(val, start?, end?)`, `join(sep?)`, `sort()`, `sort(cmpFn)` — all on dynamic `i32[]` and `f64[]`; **`every`/`some`**: predicate loop helpers (`$__dynarr_every_T` / `$__dynarr_some_T`) return i32 1/0; `dotCallLookupFn` returns `type: "bool"` for `every`, `some`, and `includes` on array receivers; `parseSingleArg` maps `type === "bool"` → `boolexpr` — `true`/`false` output matches TypeScript; **`findIndex`**: predicate scan, returns index or -1; **`at`**: negative index wraps via `len + n`; **`reverse`**: two-pointer in-place swap; **`fill`**: range fill with start/end clamped to `[0, len]`; **`join`**: new `joinarr` `LogSegment` kind; `getJoinHelperWat()` emits `$__dynarr_join_to_scratch_i32/f64` which writes the joined string directly into the gather scratch buffer (avoids returning a string pair); separator allocated in data section at compile time; `needsJoinHelper` flag wired through all 6 `emitConsoleLog` call sites and `emitHelpers`; **`sort()`**: in-place insertion sort ascending; **`sort(cmpFn)`**: insertion sort with `call_indirect` comparator; `findDynamicArrays` regex extended for all Phase 28 methods; **bug fix**: `T \| undefined`-typed `.find()` variables now correctly populate `findResultVars` (nullable let match handler was returning early, bypassing `findResultVars.add()`); **`Tuples_23`**: `(a / b) \| 0` pattern documents integer-division semantics for test files where TypeScript float division would diverge — 89/89 suite |
| bug fix (2026-04-24) | `arrptr`/`joinarr` segments in per-iov path | `console_log.ts` `emitConsoleLog` has two emission strategies: gather mode (all segments gatherable) and per-iov mode (fallback when a non-gatherable segment such as `boolexpr` is present). `arrptr` and `joinarr` LogSegment kinds were only handled in the gather path — when per-iov mode was forced (e.g. a `boolexpr` + an array in the same `console.log`), the array segment fell through to the final numeric `else` which accessed `.wat` (absent on `joinarr`), producing a TypeScript lint error and incorrect WAT at runtime. Fix: explicit `else if` branches added for both kinds in the per-iov outer chain; each initialises the iov's `buf_len` field to 0 (cursor start), sets `buf` to `scratchBase`, and calls the same array/join helper as gather mode — `mem[iovLen]` holds the byte count after the call, satisfying the iov contract without additional bookkeeping |
| 29 (2026-04-24) | Class enhancements | **Static fields:** `static count: i32 = 0` → named mutable WASM global `$ClassName_count`; registered during `parseClasses()` directly into `moduleGlobals`; `ClassName.field` reads emit `(global.get $ClassName_field)`, writes emit `(global.set ...)`; accessible from constructors, instance methods, and static methods. **Getters:** `get prop(): T { return this._prop; }` → `ClassName_get_prop(__self: i32): T`; `obj.prop` (no parens) dispatches to getter in `emitExpr`, in `structLookupFn` (console.log), and via `this.prop` inside methods — getter check runs before raw field load. **Setters:** `set prop(val: T) { this._prop = val; }` → `ClassName_set_prop(__self: i32, val: T)`; `obj.prop = val` dispatches to setter in `emitStatement` for both `this.field = val` and `obj.field = val` paths — setter check runs before raw field store. **String enums:** `enum Direction { Up = "up", Down = "down" }` → `enumStringValues: Map<string, string>`; `const dir: string = Direction.Up` allocates the string in the data section via `emitStringAssign`; `console.log(Direction.Up)` emits a `{ kind: "literal", text: "up" }` segment via new `enumStringLookup` callback threaded through `parseConsoleLogArgs` / `parseSingleArg` / `parseTemplateLiteral` in `console_log.ts`; `ClassDef.methods` entries gained `isGetter?` / `isSetter?` flags |
| bug fix (2026-04-24) | Phase 29 `console.log(ClassName.staticField)` | Both `structLookupFn` closures in `wasic.ts` (console.log and console.error paths) only checked `classVars` (instance vars) and `structVars` (plain structs) — `console.log("Count:", Rectangle.count)` printed `0` because the lookup returned `undefined` when `vn` was a class name rather than an instance variable, causing `exprToWat` to emit `(f64.const 0)`. Fix: added a static-field branch in both closures that checks `classDefs.get(vn)` → `moduleGlobals.get("${vn}_${fn}")` and returns `(global.get $ClassName_field)` when found. Four new Phase 29 test files added (`StaticFields_29`, `GettersSetters_29`, `StringEnums_29`, `ClassEnhancementsCombined_29`) — 94/94 suite |
| 30 (2026-04-27) | Struct/object enhancements + `namespace` | **Namespaces:** `expandNamespaces()` source-level transform runs before all parse passes in `transpile()` — rewrites `export function f()` → `function Name_f()` and `export const C` → `const Name_C`, flattens into top-level declarations; `namespaceDefs: Set<string>` tracks known names; call sites (`Name.f(args)`, `Name.C`) handled in `emitExpr`, `dotCallStmt`, and both `structLookupFn`/`dotCallLookupFn` closures; `parseTopLevel` skips already-expanded namespace blocks. **Interface inheritance:** `parseStructs()` regex captures optional `extends BaseName` group; base fields prepended at their original offsets, derived fields start at `baseDef.totalSize`; re-add guard prevents duplicate fields. **Shorthand property notation:** `return { x, y }` in function bodies — when no `:` separator present, token treated as both key and value; `structVarRuntimeInits: Map<string, Record<string, string>>` populated during pre-scan of both `emitFunction` body and `startBodyLines`; `emitStatement` struct-let match emits runtime `f64.store`/`i32.store` instructions per field from `structVarRuntimeInits`. **Bug fix:** function-returned structs now registered in both `interfaceVars` (method dispatch) and `structVars` (field reads) — enables `const v: Vec2 = makeVec(3.0, 4.0); console.log(v.x)`. Five test files: `Namespace_30`, `NamespaceAdvanced_30`, `InterfaceInheritance_30`, `ShorthandProps_30`, `Phase30Combined_30` — 99/99 suite |
| 31 (2026-04-29) | TypedArrays | **Types supported:** `Int8Array`, `Uint8Array`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array` — all eight typed array types. **Memory layout:** 8-byte header `[length i32 at +0, 0 i32 at +4]` followed by typed data at `+8`; allocated via `$__malloc`. **Construction:** `new Int32Array(n)` (literal length), `new Int32Array(runtimeVar)` (runtime length), `new Int32Array([1, 2, 3])` (literal array initialiser — data segment + `memory.copy`). **Element access:** typed read (`i32.load8_u`, `i32.load`, `f64.load`, etc.) / write (`i32.store8`, `i32.store`, `f64.store`, etc.) at `ptr+8+idx*shift`; sub-word shift=0 case uses plain `i32.add` offset without `i32.shl`. **Properties:** `.length` (`i32.load ptr`), `.byteLength` (`length * bytesPerElem`). **Methods:** `.fill(val)`, `.fill(val, start)`, `.fill(val, start, end)` — clamped range loop via `$__ta_fill_T` helper; `.set(src)`, `.set(src, offset)` — element copy via `$__ta_set_T` helper. **TypedArray as function param:** registers in `typedArrayVars` from `p.structType`; correct load/store ops used inside callee. **`console.log`:** `Int32Array(4) [ 1, 2, 3, 4 ]`-style output — length header + `arrptr` LogSegment reusing existing i32/f64 array print helpers; `ArrayLookup` type in `console_log.ts` extended with optional `shift` and `customLoadOp` fields for sub-word load ops; `structLookupFn` extended to route `.length`/`.byteLength` via `parseSingleArg`. **Bug fix — `bracketMatch` greedy regex:** `emitExpr`'s `/^(\w+)\[(.+)\]$/` was changed to `/^(\w+)\[([^\]]*)\]$/` — prevents greedy match across binary operators so compound expressions like `nums[0] + nums[1] + nums[2]` fall through to the binary ops loop instead of misparsing as a single bracket access. Four test files: `Int32Array_31`, `Float64Array_31`, `TypedArrayAdvanced_31`, `Phase31Combined_31` — 103/103 suite |
| 32 (2026-04-30) | Discriminated union types | **Layout:** flat "super-struct" — discriminant field at offset 0 as `i32` (4 bytes), followed by all unique variant fields from all branches laid out sequentially with natural alignment; every variant of the union shares the same memory region. **Tag mapping:** discriminant string literals (`"circle"`, `"rect"`, etc.) are mapped to integer indices (0, 1, 2…) at compile time inside the pre-scan phase — `allocStructData` only ever sees integers. **`parseDiscriminatedUnions()`:** new parse pass runs before `parseStructs()` in `transpile()`; detects multi-variant `type Name = { disc: "lit1"; … } \| { disc: "lit2"; … }` aliases via regex; identifies the common discriminant field (the one with a string literal in every variant); builds and registers the combined `StructDef` in both `structDefs` and `discUnionDefs`; `parseStructs()` skips names already registered. **Switch narrowing:** `switch (s.kind)` with `case "circle":` — switch handler detects `varName.discField` pattern, emits `(i32.load ptr)` for the dispatch value, converts string case labels to their integer tag constants via `duSwitchDef.variants`. **If/else-if narrowing:** `s.kind === "circle"` handled in `emitExpr` before the binary ops table — emits `(i32.eq (i32.load ptr) (i32.const tagIdx))`; `!==` maps to `i32.ne`. **`else if` chain support (general fix):** `emitBlock`'s if-handler now detects `} else if (cond) {` terminators from `extractBlock`, collects the full chain into a synthetic lines array, and recurses — this was a previously untested code path in wasic. **Bug fix — `as T` cast for struct fields:** `srcType` in `emitExpr`'s `as` handler now resolves struct field types via `structVars` lookup (`val.n as f64` where `n: i32` now emits `f64.convert_i32_s (i32.load …)` instead of a bare `i32.load`). **Bug fix — i32 arithmetic in `console.log`:** `parseSingleArg` in `console_log.ts` now detects a leading i32/bool identifier and returns `i32expr` (not `f64expr`); `exprToWat`'s binary-ops loop extended with an `lhsLocalType === "i32"` check (parallel to the existing i64 check) so `y + m.steps` where both are `i32` emits `i32.add` not `f64.add`. Four test files: `BasicDiscUnion_32`, `DiscUnionIfElse_32`, `DiscUnionMixed_32`, `Phase32Combined_32` — 107/107 suite |
| 33 (2026-05-01) | Intersection types `A & B` | **`parseIntersectionTypes()`:** new parse pass in `wasic.ts`, called after `parseStructs()` + `parseClasses()` in `transpile()`. Detects `type Name = A & B [& C …]` declarations where the RHS is two or more `\w` identifier type names separated by `&` (regex excludes object-type `{}`, DU `\|`, tuple `[]`, and function-type `=>` forms). For each match, merges all `StructField` entries from each constituent `structDefs` entry in source order — natural alignment preserved, first definition wins on name conflict, fields already present are skipped. Registers the merged `StructDef` in `structDefs` under the intersection type name. Processes matches in source order so chained intersections (`type D = C & E` where C is itself an intersection) resolve correctly in a single pass; since each intersection is registered before the next match is processed, multi-level chains work without multiple passes. No other changes required — intersection types are ordinary `StructDef` entries so all existing infrastructure (struct literal init, `allocStructData`, field access in `emitExpr`/`emitStatement`, `structLookupFn`, function param `structType` dispatch) works unmodified. Passing a derived intersection pointer (`ColoredParticle*`) to a function expecting a base intersection pointer (`Particle*`) is safe because the first N bytes of the derived layout are identical to the base layout. Four test files: `BasicIntersection_33`, `IntersectionFunc_33`, `IntersectionThreeWay_33`, `Phase33Combined_33` — 112/112 suite |
| 34 (2026-05-02) | Type predicates `x is T` | **Syntax:** `function isPred(p: BaseType): p is DerivedType { … }` — the `param is Type` return annotation is parsed by `parseFunctions()` (regex extended with `[\w]+\s+is\s+[\w]+` alternative); the predicate function is registered in `typePredicateFuncs: Map<string, { paramName, targetType }>` and its WAT result type is set to `bool` (i32), so `console.log(isCircle(x))` correctly prints `true`/`false`. **Compile-time narrowing:** in `emitBlock()`'s if-handler, when the condition matches the single-arg call pattern `predFn(arg)` and `predFn` is in `typePredicateFuncs`, the argument variable is narrowed — its `structVars` (or `classVars`) entry is temporarily replaced with `{ def: targetDef, ptr: same-ptr }` before emitting the then-branch body and restored afterward. The current pointer value (static address or -1 for function params) is preserved so all existing field-access paths continue to work. **Else-if chains:** free — `emitBlock` transforms `else if` into a recursive nested-if structure, so each predicate call in a chain gets independent narrowing scope automatically. **Supported patterns:** DU types (all variant fields in the flat struct; `s.disc === "lit"` in the predicate body compiles via Phase 32 infrastructure) and interface inheritance hierarchies — a function accepting the base type can narrow the parameter to a derived type and access derived-only fields. **Limitation:** negated predicates (`!isPred(x)`) and else-branches do not apply narrowing. Four test files: `BasicTypePredicate_34`, `TypePredicateNarrowing_34`, `TypePredicateFunc_34`, `Phase34Combined_34` — 116/116 suite |
| 35 (2026-05-03) | `typeof` / `keyof T` (compile-time only) | **`typeof` comparisons:** `typeof x === "number"` (and `!==`, `==`, `!=`) is evaluated entirely at compile time in `emitExpr` before the binary ops table — the new handler resolves the variable's known WAT type to its JS typeof string (`i32`→`"number"`, `f64`→`"number"`, `bool`→`"boolean"`, `string`→`"string"`, `i64`→`"bigint"`, struct/array `i32`→`"object"`) and emits `(i32.const 1/0)`. The reversed form (`"type" === typeof x`) is also matched. **`typeof` as a value:** `const t: string = typeof x` and `const t = typeof x` (inferred as `string` via `inferInitType`) are handled in `emitStringAssign` — calls `resolveTypeofString`, allocates the type-name in the data section, sets `$t_ptr`/`$t_len`. **`console.log(typeof x)`:** `parseSingleArg` in `console_log.ts` detects the `typeof x` token and returns `{ kind: "literal", text: typeStr }` — zero runtime overhead, the type string is embedded as a static literal. **`keyof T` as type annotation:** a source pre-pass in `transpile()` (after `expandNamespaces`) rewrites every `: keyof T` type annotation to `: string` in the raw source before any parsing — making `function f(key: keyof Person)` and `const k: keyof Point = "x"` work transparently through the existing string infrastructure. `mapType()` also has a `/^keyof\s+\w+/` guard as a fallback. `type Alias = keyof T` declarations are stripped by the pre-pass. **Limitation:** `typeof x` in type positions (`param: typeof myVar`) and named `keyof` aliases (`type PK = keyof Person; let k: PK`) are not supported. Four test files: `BasicTypeof_35`, `KeyofBasic_35`, `TypeofInConditions_35`, `Phase35Combined_35` — 120/120 suite |
| enhancement (2026-05-01) | `$__f64_to_str` shortest-round-trip pass | **Problem:** the ×1e15 approach occasionally produced a spurious extra trailing digit — e.g. `78.539816339744831` instead of `78.53981633974483` — because multiplying the fractional remainder by `1e15` in IEEE 754 introduces a ±1 ULP rounding error in the last digit. **Fix:** a "shortest round-trip" loop added after the ×1e15 step. Starting from 15 fractional digits, it repeatedly tries stripping the last digit (dividing `fpart` by 10) and checking whether `f64(ipart) + f64(trial) / f64(10^k)` still reconstructs the exact original double via `f64.eq`. Stripping stops at the first k where reconstruction diverges. Powers of 10 from `1` to `1e15` are all exactly representable in f64 (≤ 50 significant bits), so the reconstruction arithmetic introduces no additional error beyond the comparison itself. A new `$__pow10_f64` WAT helper returns `10^n` for n in [0, 15] via a chain of `if`/`return` branches. Per-binary overhead: ~200–300 bytes additional WAT (the helper function + extra locals and loop in `$__f64_to_str`). Known remaining delta: `Math.SQRT2` prints `1.414213562373095` (WASM) vs `1.4142135623730951` (JavaScript) — this requires MORE digits than ×1e15 can supply and is not fixed by the shortening pass |
| 36 (2026-05-04) | Simple conditional types `T extends U ? X : Y` | **`expandConditionalTypes(src)`:** new private method on `WasicTranspiler`, inserted after `expandGenerics` and before `expandNamespaces` in `transpile()` — pure source-level text transformation. **Generic form** (`type Toggle<T> = T extends i32 ? f64 : i32`): declaration removed from source; every `Toggle<ConcreteType>` use site is rewritten by resolving the condition against the concrete argument. **Non-generic form** (`type AlwaysI32 = f64 extends number ? i32 : string`): condition evaluated once at declaration time; all bare occurrences of the type name replaced with the resolved concrete type. **`extendsCheck(concrete, upper)`**: conservative compile-time compatibility — same string, any numeric type extends `number`, `bool`/`boolean` cross-match. Runs after `expandGenerics` so monomorphized call sites produced by generic expansion are also resolved; runs before all other parse passes so no downstream pass ever sees a conditional type declaration or use site. **Limitations:** `infer` not supported; nested conditional types require two passes; conditional types referencing other conditional types by name have source-order dependency. Four test files: `BasicConditionalType_36`, `ConditionalTypeParams_36`, `ConditionalTypeNonGeneric_36`, `Phase36Combined_36` — 124/124 suite |
| 37 (2026-07-14) | `flat()` / `flatMap(fn)` | **`flat()`:** one-level flatten of `i32[][]` or `f64[][]` into a 1D array — two-pass WAT helper `$__dynarr_flat_T`: (1) walk outer array (i32 ptrs, shift=2), sum all inner `.length` headers to get `totalLen`; (2) allocate result array of `totalLen` elements; (3) copy inner elements using the element type's shift/load/store. **`flatMap(fn)`:** for each element of a 1D array, call `fn(elem)` via `call_indirect` (functype `(T) → i32`, the i32 being a pointer to an inner `T[]`), then flatten — two-pass WAT helper `$__dynarr_flatmap_T`: allocates a raw temp buffer (`len × 4` bytes, no header) to store inner array ptrs from pass 1, accumulates `totalLen`, allocates result in pass 2, copies. Calling `fn` exactly once per element avoids side-effect duplication. `findDynamicArrays` regex extended to include `flat` and `flatMap` so source arrays are auto-promoted to dynamic layout. `flat()` guards `arrInfo.is2D` — calling it on a 1D array is a compile-time stub. `flatMap` callbacks must be named functions (no inline arrows); the callback's TypeScript return type (`T[]`) maps to WAT `(result i32)` — the same convention as all other array-returning functions. Three test files: `FlatArray_37`, `FlatMapArray_37`, `Phase37Combined_37` — 127/127 suite |
| 38 (2026-07-14) | Extended math via external `mathlib.wasm` | **Architecture:** `src/wasm/mathlib.wat` is a standalone WAT module (21 exported functions) compiled to `src/wasm/mathlib.wasm` (binary embedded as `MATHLIB_BYTES` in `src/wasm/mathlib_bytes.ts`). When any Phase 38 `Math.*` function appears in a compiled file, `transpiler.needsMathLib` is set and `compileWasiTs`/`compileLibraryTs` call `mergeOneWasmImport(wat, MATHLIB_BYTES, "mathlib", ...)` to splice the library into the WAT before Binaryen sees it — so dead-stripping and inlining work across the full merged module. **Naming:** wasic emits `(call $mathlib_sin arg)` etc.; `mergeWasmWat` applies the `"mathlib"` prefix to all exported symbols. **Global relocation:** `renameGlobalRefs()` in `wasmmerge.ts` rewrites numeric `global.get N` / `global.set N` references in merged bodies to named `$mathlib_globalN` refs, necessary because the RNG state global (i64) shifts index after the main module's globals are prepended. **`$atan` two-stage range reduction:** complement (z→1/z for z>1) + mid-range ((z-1)/(z+1) for z>tan(π/8)≈0.4142) before the fdlibm aT[0..10] minimax polynomial; four result cases based on which reductions applied; formula `r = z − z³t` (subtraction). **Bug fixes:** (1) greedy `Math.fn(...)` regex in both `wasic.ts` and `console_log.ts` now validates that argsStr has no unmatched `)` at depth 0 — compound expressions like `Math.sin(a) * Math.sin(a) + Math.cos(a) * Math.cos(a)` previously matched as a single `Math.sin(...)` call; (2) `exprToWat` in `console_log.ts` gained a `globals?: Map<string, string>` 8th parameter so module-level f64 globals used as arguments to nested Math calls (e.g. `Math.exp(x)`) emit `(global.get $x)` instead of a comment stub. Five test files: `MathTrig_38`, `MathExpLog_38`, `MathHyperbolic_38`, `MathRandom_38`, `Phase38Combined_38` — 132/132 suite |
| 39 (2026-07-14) | `jstyper` — `.d.ts`-based JS import pre-processor | **Architecture:** `src/jstyper.ts` — pure regex/brace-counting implementation with no external dependencies. **Pipeline:** `parseJsFunctions()` extracts function bodies from `.js` (regular functions + arrow functions, block and expression bodies, nested-brace-safe via string-aware `extractBraceBlock()`); `parseDtsFunctions()` extracts typed signatures from `.d.ts` (`export declare function` / `declare function` forms); `generateTypedTs()` merges bodies + types into a typed `.ts` wasic can compile. **Type mapping:** `number→f64`, `int→i32`, `float\|double→f64`; WASM primitives (`i32`, `i64`, `f32`, `f64`, `bool`, `string`, `void`, `never`) pass through unchanged; `any` controlled by `--any-policy`. **`--dts-only` mode:** `generateSkeletonDts()` emits a `number`-typed skeleton `.d.ts` with `@auto-generated by jstyper` header for hand-editing. **`--dry-run`:** prints output to stdout without writing files. **`--any-policy` modes:** `skip` (exclude function + warning with corrected declaration), `warn` (include with `i32` fallback + warning), `default` (include with `i32` silently). **Actionable diagnostics:** every warning and error is multi-line with a "Fix:" block naming the specific file, showing the corrected declaration verbatim, listing valid WASM types, and (for skip mode) offering the `--any-policy=warn` escape hatch; `correctedDecl()` helper reconstructs the declaration with `any→i32` substituted. **CLI:** `wasmtk jstyper <file.js> [--dts-only] [--dry-run] [--any-policy=skip\|warn\|default] [-n out]`. **Tests:** four wasic-compiled `wasm_wasi` test files (`JstyperBasic_39`, `JstyperF64_39`, `JstyperMixed_39`, `Phase39Combined_39`) + `tests/jstyper_tests.ts` unit runner (73 assertions covering all parsing, generation, and pipeline paths). **New files:** `src/jstyper.ts`, `tests/jstyper_tests.ts`, `tests/jstyper_fixtures/` (3 fixture pairs). **Changed:** `main.ts` (`case "jstyper"`, `--dts-only`/`--dry-run`/`--any-policy` flags), `deno.json` (`"./jstyper"` export). Four wasic test files: `JstyperBasic_39`, `JstyperF64_39`, `JstyperMixed_39`, `Phase39Combined_39` — 136/136 suite |
| 40 (2026-07-14) | External interface mapping via `declare const` / `declare interface` | **`declare const host: { log(ptr: i32): void; getTime(): i32 }`** — inline object type; each method compiles to `(import "env" "host_log" ...)` + `(import "env" "host_getTime" ...)`. **`declare interface Logger { ... }` + `declare const logger: Logger`** — named form; interface defined once, bound by name. **`parseExternalDeclarations()`** three-pass preprocessor strips declarations before other parsers; `externalInterfaceTypes` + `externalBindings` maps drive call-site emission; `usedExternalMethods` tracks actually-called methods and drives `emitWasiImports()` to emit `(import "env" ...)` declarations. **Runner stub proxy:** `env` import object in test runner is a JavaScript `Proxy` — any unrecognised key returns a no-op `() => 0` stub, allowing Phase 40 WASM modules to instantiate without a real host. **Error message improvement:** undeclared dot-call receivers now suggest the Phase 40 `declare const` syntax. `ExternalMapping_11b.ts` upgraded from `@expect-fail: compile` to a fully-passing test. Six test files: `BasicExternalDecl_40`, `ExternalInterfaceType_40`, `MultiMethodExternal_40`, `ExternalReturnValue_40`, `Phase40Combined_40`, `ExternalMapping_11b` (upgraded) — 142/142 suite |
| 41 (2026-07-14) | WIT file generation | After every successful `wasic` or `modc` compilation, a `.wit` file is written alongside the `.wasm` output. **`watTypeToWit()`** maps WAT types to WIT types (`i32→s32`, `i64→s64`, `f32→f32`, `f64→f64`, `bool→bool`). **`toKebabCase()`** converts camelCase/snake_case function names to WIT-compliant kebab-case. **`generateWit(moduleName)`** public method on `WasicTranspiler` produces `package local:name; world name { import ...; export ...; }` — imports from `usedExternalMethods` (Phase 40 externals); exports from `this.functions` filtered by `exported && !isClosureFactory && !INTERNAL`. **`_start`/`_initialize` excluded from exports; `__self` params skipped.** Compile log prints `WIT: <path>` alongside the existing `WAT: <path>` line. Four test files: `BasicWitGen_41`, `WitReturnTypes_41`, `WitWithExternalImports_41`, `Phase41Combined_41` — 146/146 suite |
| 42 (2026-05-13) | String-returning user functions + chained struct field access + nested struct literals | **String-return side-channel:** string-returning functions (`function f(): string`) emit as `void` WAT functions; on `return expr`, `emitStringPtrLen` evaluates the expression and stores ptr/len into module-level mutable globals `$__str_ret_ptr` / `$__str_ret_len`; call sites read the globals immediately after `(call $fn args)`. Wired into `emitStringAssign` (string variable init from function call), `parseSingleArg` in `console_log.ts` (detect string-returning calls for `console.log`), template literal emission, and the binary-ops string-comparison path in `emitExpr`. `needsStringRetGlobals` flag on `WasicTranspiler` gates emission of the two globals in the WAT header. **Chained struct field access:** `seg.from.x`, `box.topLeft.y` — `emitExpr` detects `a.b.c` patterns, loads the intermediate struct pointer from the parent field, then loads the leaf field from that pointer (two-level `i32.load`/`f64.load` chain). **Nested struct literals:** `{ from: { x: 1.0, y: 2.0 }, to: { x: 7.0, y: 8.0 } }` — pre-scan and `allocStructData` parse inline nested struct initializers and recursively allocate sub-struct data in the WAT data section. **Nested struct field as function argument:** `describePoint(seg.from)` — when the argument expression is a struct-typed field access, `emitExpr` emits the i32 pointer to the nested struct (loaded from the parent struct's field offset) as the call argument. **`struct-embedding_42.ts`** (previously failing Go-by-Example test) now passes — 215/219 Go-by-Example. Three new wasic test files: `ChainedFieldAccess_42`, `StructFieldArg_42`, `Phase42Combined_42` — 149/149 suite |
| 43 (2026-05-14) | String arrays as function parameters | **`string[]` params:** string array parameters registered in `arrayVars` with `dynamic: true, isStringArr: true`; 8-byte-per-element interleaved layout (`[ptr i32, len i32]` pairs, shift=3); `arr[i]` inside the function body returns a ptr+len pair via `emitStringPtrLen`. **Higher-order functions with `(s: string) => boolean` callbacks:** `getOrCreateFuncType` expands `"string"` to two `"i32"` (ptr+len) via `flatMap` — a callback typed `(s: string) => boolean` registers functype `$ftype_i32_i32_r_i32`; `funcTypeVars` dispatch path uses `emitStringPtrLen` for each `string`-typed argument so `call_indirect` receives the correct ptr+len pair. **`string[]` return type:** `strFilter(arr, pred): string[]` functions return an i32 array pointer; call sites store the pointer in an `arrayVars` entry with `isStringArr: true`. **Cross-module signaling via singletons in `console_log.ts`:** `setStrCmpNeededCallback` (fires `needsStringHelpers = true` when `exprToWat` emits `$__str_cmp`) and `setFuncTableLookup` (resolves function names to WASM table indices inside `exprToWat`) — both set by `wasic.ts` before `parseConsoleLogArgs`, cleared after. **Helper dependency fix:** `needsStringExtHelpers` alone now triggers `getStringOpHelperWat()` emission (`$__str_indexof` etc. available for `s[0] === "a"` char comparisons). Four test files: `BasicStringArrParam_43`, `StringArrHigherOrder_43`, `StringArrReturn_43`, `Phase43Combined_43` — 150/150 wasic suite, 221/226 total |
| 44 (2026-05-14) | Function pointer arrays (`Array<FunctionType>`) | **`Array<() => void>` detection (three sites):** (1) `detectModuleArrayGlobals()` regex `Array<((?:[^<>]\|=>)*)>` added before the `T[]` match — regex uses `(?:[^<>]\|=>)*` so `=>` inside the type argument is not consumed as `>`; sets `isFuncPtrArr` on the `ArrayInfo` entry; (2) `emitFunction` pre-scan handles local `Array<FuncType> = []` declarations; (3) `startBodyLines` pre-scan seeds from `moduleArrayVars`. **`liftStartBodyArrows()` — new second-pass method:** `liftInlineArrows()` runs before `parseTopLevel()` so `startBodyLines` is empty; a second pass after `parseTopLevel()` creates a synthetic `_start` `FuncDef` with `bodyLines = [...startBodyLines]` and passes it as `enclosingFn` to `substituteOneArrow` — this allows module-level capturing closures (`defer(() => console.log(n))` in a `for` loop) to generate factory/trampoline pairs with correct outer-scope capture analysis. **`emitStatement` additions:** `funcArrLetMatch` handler for `Array<...> = []` calls `emitDynArrayInit`; `arrLenAssign` handler for `arr.length = N` emits `(i32.store ptr val)`; `funcPtrArrCallMatch` handler for `arr[idx]()` emits `(local.set $__fn_tmp (i32.load elemAddr)) (call_indirect (type $ftype_i32_r_void) (local.get $__fn_tmp) (i32.load (local.get $__fn_tmp)))` — loading the closure struct ptr from the i32 element, then reading the trampoline table index from offset 0 of that struct. **`$__fn_tmp` local:** declared in both pre-scans when any body line references a function pointer array via `name[`. **`substituteOneArrow` bug fix:** expression-body arrows (`() => expr`) previously called `inferInitType(expr, ...)` whenever `anonResult === null`, including when `paramInfo.result === null` (the callee explicitly declared `() => void`). JavaScript's `??` operator coalesces `null` (e.g. `null ?? fallback = fallback`), losing the explicit void signal — `inferInitType` would then return `"f64"` as its default fallback, giving the anonymous function `(result f64)` instead of `void`. Fix: changed the condition from `if (anonResult === null)` to `if (anonResult === null && paramInfo === undefined)` so inference only runs when no callee type info is available at all. Without this fix, `() => console.log(n)` generated a trampoline with `(result f64)` causing a `call_indirect` signature mismatch at runtime. **Result:** `defer.ts` and `exit.ts` Go-by-Example tests now pass. Two new test files: `defer_44.ts`, `exit_44.ts` — 152/152 wasic suite, 224/226 total |
| 45 (2026-05-15) | `Math.imul` + unsigned right shift (`>>>`) + hex literals | **`Math.imul(a, b)`:** emits `(i32.mul (i32.trunc_f64_s a) (i32.trunc_f64_s b))`; wrapped in `(f64.convert_i32_s ...)` when `defaultType` is f64 so the result is stored correctly in a `number` variable. **`>>>` unsigned right shift:** added to `binaryOps` table with `alwaysI32=true`; the alwaysI32 promotion block uses `f64.convert_i32_u` (unsigned) for `>>>` instead of the signed `f64.convert_i32_s` used by other bitwise ops — correctly implements the JavaScript `>>> 0` unsigned-view idiom. **Hex literals** (`0x6D2B79F5` etc.): added handler in `emitExpr` immediately after the decimal numeric literal check; `/^0[xX][0-9a-fA-F]+$/` → `parseInt(expr, 16)` → `(i32/i64/f64.const n)` based on `defaultType`. **f64→i32 truncation for arithmetic in i32 context** (Fix 3): when `baseType === "f64"` and `defaultType` needs i32, wraps the binary expression with `(i32.trunc_f64_s ...)`; the `!STRING_CMP_OPS.has(op)` guard is critical — f64 comparison instructions (`f64.lt`, `f64.eq` etc.) already return i32 so wrapping them again is invalid. **Assignment guard for mutable closure captures:** compound-assignment `s = expr` now checks `currentClosureCaptureLayout.has(name)` in addition to `locals.has(name)` so assignments to closure-captured variables work correctly in inner functions. **Closure call result type:** `closureTypedVars` lookup added to the `lhsType` chain in the binary ops block so that a closure call expression (`r1()`) uses the declared return type (`f64`) rather than the storage type of the closure pointer (`i32`). **Test:** `random-numbers_45.ts` (mulberry32 PRNG with `Math.imul`, `>>>`, and hex constants) — 154/154 wasic suite, **226/226 total (all tests passing)** |
| 46 (2026-05-15) | String escape sequence processing | **Root cause:** wasic read TypeScript source as raw text — `"\n"` was stored as two bytes (`\` + `n`) instead of one byte (0x0A), affecting both string variable assignments and `console.log` output. **`unescapeString(raw: string): string`** — new exported function in `src/console_log.ts`; fast-path via `!raw.includes("\\")` returns immediately; character-by-character walk otherwise. Handles all TypeScript/JavaScript escape sequences: `\n`→0x0A, `\r`→0x0D, `\t`→0x09, `\b`→0x08, `\f`→0x0C, `\v`→0x0B, `\0`→0x00, `\\`→`\`, `\'` `\"` `` \` `` → literal quotes, `\xHH` → byte with hex value HH, `\uHHHH` → UTF-8 of U+HHHH, `\u{H…}` → UTF-8 of variable-length code point; malformed sequences passed through unchanged. **Two fix locations:** (1) `allocString` and `allocStringNoLog` in `wasic.ts` — apply `unescapeString` to the raw source substring before writing to the WAT data section; `dataMap` keyed by the unescaped form so two spellings that unescape to the same bytes share one allocation; (2) `parseSingleArg` double/single-quote handlers and `parseTemplateLiteral` text-segment pushes in `console_log.ts` — `console.log` gather mode directly byte-encodes `{ kind: "literal" }` segments without going through `allocString`, so needed its own fix. **Safety:** `unescapeString` on compiler-internal strings (which already contain actual characters, not escape sequences) is a no-op — the fast-path `!raw.includes("\\")` exits immediately. Four test files: `BasicEscapeSeqs_46`, `TemplateEscapes_46`, `HexUnicodeEscapes_46`, `Phase46Combined_46` — 158/158 wasic suite, 230/230 total |
| 47 (2026-05-15) | Class inheritance | **Overview:** `class Dog extends Animal` — field layout inheritance, `super(args)` constructor chaining, and static virtual dispatch via concrete-type tracking. **Field inheritance:** `parseClasses()` regex updated to capture `extends BaseName`; when found, parent struct fields (cloned via `{ ...pf }`) are prepended to the derived class's `fields[]` before the derived class's own fields are scanned; `fieldOffset` starts at `parentCd.struct.totalSize`. Multi-level chains work automatically because parent classes appear before derived classes in source order. **Class tag header:** after all classes are parsed, if `classInheritance.size > 0`, a 4-byte tag header is added to every class in the file — `classHeaderSize = 4`, all field offsets shift by `+4`, all `totalSize` values grow by 4; integer tags assigned in parse order via `classTags: Map<string, number>`; tag written to offset 0 of each instance in `allocStructData`. **`resolveMethodFunc(className, methodName): string \| null`** — new private helper; walks `classInheritance` chain to find the WAT function name (`current_methodName`) that implements a method, falling through to the parent if not found; called at all four method-dispatch sites in `emitExpr` and `emitStatement`. **Virtual dispatch via concrete-type tracking:** `newClassPre` pre-scan now prefers `ctorName` over `typeName` — `const a: Animal = new Dog(3)` registers `classVars.className = "Dog"`, so every subsequent `a.method()` call routes through `resolveMethodFunc("Dog", ...)` automatically (no runtime tag-based dispatch table needed for concrete-type variables). **`super(args)` handler:** inserted in `emitStatement` before `callMatch`; matches `/^super\s*\((.*)\)\s*;?$/` when `currentMethodClass` is a derived class; emits `(call $ParentName_constructor (local.get $__self) args...)`. **`structLookupFn` `this` handler:** added to both `structLookupFn` closures (console.log and console.error paths); when `vn === "this"` and `currentMethodClass` is set, looks up the field in `classDefs.get(currentMethodClass).struct.fields` and emits the correct `loadOp` with `(local.get $__self)` — enables `console.log("Age:", this.age)` inside method bodies. Five test files: `BasicClassInheritance_47`, `SuperConstructor_47`, `ClassMethodOverride_47`, `VirtualDispatch_47`, `Phase47Combined_47` — 163/163 wasic suite, **235/235 total (all tests passing)** |
| 48 (2026-05-15) | Language completeness: Number API, operators, control flow | **`Number.*` constants:** `NUMBER_CONSTS` lookup map added in `emitExpr` (`wasic.ts`) and `exprToWat` (`console_log.ts`) — `Number.NaN→(f64.const nan)`, `Number.POSITIVE_INFINITY→(f64.const inf)`, `Number.NEGATIVE_INFINITY→(f64.const -inf)`, `Number.EPSILON→(f64.const 2.22e-16)`, `Number.MAX_SAFE_INTEGER→(f64.const 9007199254740991)`, `Number.MIN_SAFE_INTEGER→(f64.const -9007199254740991)`, `Number.MAX_VALUE→(f64.const 1.7976931348623157e308)`, `Number.MIN_VALUE→(f64.const 5e-324)`. **`Number.*` predicates:** `Number.isNaN(x)→(f64.ne x x)` (NaN ≠ itself); `Number.isFinite(x)→(i32.and (f64.lt x inf) (f64.gt x -inf))`; `Number.isInteger(x)→(f64.eq (f64.floor x) x)`. **`dotCallLookup` guard:** added `!token.startsWith("Number.")` alongside the existing `!token.startsWith("Math.")` guard so `Number.isNaN(x)` is not misrouted through the dot-call i32 path. **`parseSingleArg` boolexpr ordering fix (critical):** the entire boolexpr detection block (comparisons, `&&`, `\|\|`, `!`) moved BEFORE the `Number.*` and `Math.*` handlers — without this, `Number.MAX_SAFE_INTEGER > 1e16` was caught by the `Number.*` guard and returned `f64expr`, causing `$__f64_to_str` to receive the i32 result of `f64.gt` (WAT type error). **Scientific notation literals:** numeric literal regex extended from `/^-?\d+(\.\d+)?$/` to `/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/` in both `emitExpr` (`wasic.ts`) and `exprToWat` / `parseSingleArg` (`console_log.ts`) so `1e16`, `3.5e-4`, etc. are recognized. **`**=` compound assignment:** new `expAssignMatch` handler in `emitStatement` before `compoundMatch`; uses `$__math_pow` via `mathHelpers.add("math_pow")`; supports locals and module globals. **`$__math_pow` sqrt special case:** early-return branches added for `exp === 0.5` → `(f64.sqrt base)` and `exp === -0.5` → `(f64.div 1 (f64.sqrt base))` before the integer-exponent loop. **Object destructuring with defaults:** `destructMatch` block updated with 4-form binding parser (`"field"`, `"field = default"`, `"field: local"`, `"field: local = default"`); when default present, emits `(if (result T) (eqz loadWat) (then defWat) (else loadWat))` with zero-sentinel semantics (default fires when field is 0). **Labeled `continue` and switch fallthrough:** verified already implemented — no code changes needed. Seven test files: `NumberConstants_48`, `NumberPredicates_48`, `SwitchFallthrough_48`, `ObjectDestructDefault_48`, `LabeledContinue_48`, `ExponentAssign_48`, `Phase48Combined_48` — 170/170 wasic suite, 242/242 total |
| 49 (2026-05-15) | Optional chaining and collection method completeness | **`?.` optional chaining:** global source pre-pass `src.replace(/[?][.]/g, ".")` at the start of `transpile()`, before `expandGenerics` — all `?.` on non-nullable types is stripped at compile time (safe because wasic's closed-world; nullable types use explicit `!== null` ternary per Phase 24). **`String.prototype.at(n)`:** inline pointer arithmetic without calling `$__str_char_at` (which returns multi-value `(result i32 i32)`): `normIdx = (select n (i32.add len n) (i32.ge_s n (i32.const 0)))`, result is `(ptr+normIdx, 1)`; added to `emitStringAssign` (`strAtAssignM`), `emitStringPtrLen` (`strAtSPLM`), `appendConcatPart` (`strAtCP`), and `parseSingleArg` in `console_log.ts` (returns `strexpr`). Prologue checks extended to include `.at(` alongside `.charAt(` and `.slice(`. **`Array.prototype.concat(other)`:** added `concat` to `dynArrMethod` dispatch regex with `parenDepthNeverNegative` guard; delegates to existing `$__dynarr_concat_T` helper (already present from Phase 13 spread literals) — no new WAT generation needed. **Chained array method calls** (`arr.filter(f).map(g)`): new `splitLastMethodCall(expr)` private method (backward balanced-paren scan → finds outermost `.method(args)` split) and `inferChainElemType(expr, locals)` (recursively infers element type of chained expression via `arrayVars` or method-type rules). Chain dispatch block after `dynArrMethod` block: when `parenDepthNeverNegative` fails (unbalanced `argsStr` = chained expression), `splitLastMethodCall` separates receiver and outer method; `emitExpr(receiver, "i32")` generates the inner call WAT inline as the first argument to the outer method call — no temp locals needed. Five test files: `OptionalChaining_49`, `StringAt_49`, `ArrayConcat_49`, `ChainedMethods_49`, `Phase49Combined_49` — 175/175 wasic suite, **247/247 total (all tests passing)** |

### Planned Phases

All planned phases are implementable under WASI Preview 1. **All 247/247 tests pass as of 2026-05-15.** The next phase completes the DLL model.

| Phase | Feature | Target tests | Key changes |
| --- | --- | --- | --- |
| 50 | **Canonical ABI alignment + WIT-aware universalWasmLoader** | New integration tests verifying canonical ABI round-trips for strings, numerics, and booleans from a JS/TS host; existing 247 tests must continue to pass after ABI change | **wasmtk (prerequisite):** replace `__malloc` export with `cabi_realloc(ptr, old_size, align, new_size) → i32`; change string return emission from `$__str_ret_ptr`/`$__str_ret_len` globals to out-parameter convention (caller allocates 8-byte return area via `cabi_realloc`, callee stores ptr+len there) — aligns wasmtk output with the WASM Component Model Canonical ABI, making compiled modules natively consumable by any Component Model-aware runtime or `wit-bindgen`-generated host in Rust, Python, Go, Java, or C#. **universalWasmLoader enhancement:** WIT auto-detection (`.wit` alongside `.wasm`), WIT parser, canonical ABI translation layer (string encode/decode, out-param string return decoding, bool normalization), options interface `wasmImport(path, { abi?, wit?, imports? })`, ABI profiles `"component"` (default) and `"raw"` (legacy passthrough). **Spec document (`SPEC.md` in universalWasmLoader repo):** defines the cross-language loader contract — interface, ABI conventions, and reference test suite — that every language port (Rust, Python, Go, Java, C#) must implement. This phase completes the DLL model and is the foundation of the polyglot WASM ecosystem described in VISION.md. |

### WASM Compatibility Limitations

The following TypeScript/Go patterns cannot be compiled by `wasic` under WASI Preview 1 without additional WASM proposals. The Go-by-Example tests for these topics have been adapted to single-threaded equivalents and currently pass — this section documents the general feature class and what proposal would unblock native support.

| Feature | Blocked by | Status |
| --- | --- | --- |
| **Goroutines / cooperative multitasking** | [WASM Stack-Switching proposal](https://github.com/WebAssembly/stack-switching) | Planned for WASI Preview 3. Asyncify (Binaryen CPS transform) can simulate suspension but requires a JS host — not suitable for standalone WASI modules. |
| **Shared memory + atomics** | [WASM Threads proposal](https://github.com/WebAssembly/threads) | `SharedArrayBuffer`-backed memory and `i32.atomic.*` instructions are available in browsers; the `wasi_threads` snapshot is not yet standardized across WASI p1 runners. |
| **Channel / select communication** | Stack-Switching + Threads (both above) | Go channels are rendezvous synchronization between goroutines — requires suspending one side and resuming it when a peer is ready. No WASI p1 primitive supports this. |
| **`os.Exit` with non-zero status** | Test runner behavior | `proc_exit(n)` works correctly in wasmtime/wasmer. The Deno WASI shim used in the test runner treats all exits as success for output comparison. Full exit-code propagation is a test runner enhancement, not a compiler change. |

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

### Future Directions

All 247/247 tests pass as of Phase 49 (2026-05-15). Phases 46–49 added string escape sequences, class inheritance with virtual dispatch, the `Number` API, optional chaining (`?.`), labeled `continue`, `switch` fallthrough, `str.at(n)`, `Array.concat`, and chained array method calls. Phase 50 completes the DLL model — `wasmtk bindgen` generates typed TypeScript host bindings from a `.wit` file so that wasic-compiled WASM modules can be loaded and called from a TypeScript host with full type safety and no manual `WebAssembly` API work. No phase requires an embedded runtime — everything maps to static WASM constructs. Features that need a runtime are listed under [Types Requiring `javyc`](#types-requiring-javyc) below.

---

#### Phase 41 — WIT File Generation ✅

Every `wasmtk wasic` and `wasmtk modc` compilation now automatically produces a `.wit` file alongside the `.wasm` output with no extra flags. The WIT file describes the module's complete host-visible interface using the [WebAssembly Interface Types](https://component-model.bytecodealliance.org/design/wit.html) format.

**Output format:**

```wit
package local:my-module;

world my-module {
  import host-log: func(ptr: s32);
  import host-get-time: func() -> s32;

  export add: func(a: s32, b: s32) -> s32;
  export multiply: func(a: f64, b: f64) -> f64;
}
```

**Import section** — every Phase 40 external binding method that is actually called in the source (tracked in `usedExternalMethods`) becomes a WIT `import` entry. The method name (without the `$` prefix) is converted to kebab-case.

**Export section** — every `export function` in the TypeScript source (excluding `_start`, `_initialize`, and internal closure factories) becomes a WIT `export` entry. Parameters typed as `string` are represented as `s32` (pointer); wasic's ptr+len ABI is not fully expressible in WIT at this time.

**Type mapping:**

| WAT type | WIT type |
| --- | --- |
| `i32` | `s32` |
| `i64` | `s64` |
| `f32` | `f32` |
| `f64` | `f64` |
| `bool` | `bool` |
| `void` / no return | *(no `-> type` clause)* |
| `string` | `s32` *(pointer only)* |

**Compile log output:**

```text
   WAT:  myprogram.wat
   WIT:  myprogram.wit
   OUT:  myprogram.wasm
```

**Implementation:** `watTypeToWit()` module-level helper for type mapping; `toKebabCase()` for identifier conversion; `generateWit(moduleName)` public method on `WasicTranspiler`; called in `compileWasiTs()` and `compileLibTs()` after `watToOptimisedWasm()` succeeds.

**Test coverage:** four wasic-compiled integration tests — `BasicWitGen_41` (i32/f64 exports), `WitReturnTypes_41` (all four return type variants), `WitWithExternalImports_41` (import + export sections together), `Phase41Combined_41` (full combination of Phase 40 imports and Phase 41 WIT generation).

**Known limitations:** string parameters are represented as `s32` (pointer only — the length parameter of wasic's ptr+len ABI is not visible in WIT); generic / template-instantiated function names appear in their monomorphized form (`add_i32`, `add_f64`).

---

#### Phase 40 — External Interface Mapping ✅

Phase 40 adds `declare const` / `declare interface` syntax for binding TypeScript source code to host-provided WASM imports. External methods are verified at compile time against their declared signatures and emit `(import "env" "...")` declarations in the output WASM.

**Two binding forms:**

```typescript
// Form 1 — inline object type
declare const host: {
  log(ptr: i32): void;
  getTime(): i32;
};

// Form 2 — named interface
declare interface Logger {
  log(ptr: i32): void;
  getLevel(): i32;
}
declare const logger: Logger;
```

**Compiled WAT output:**

```wat
(import "env" "host_log"     (func $host_log     (param i32)))
(import "env" "host_getTime" (func $host_getTime (result i32)))
```

The import field name (`host_log`) is the binding variable name + `_` + method name. The same string becomes the WAT function name (with `$` prefix).

**Pipeline:** `parseExternalDeclarations()` runs as a three-pass preprocessor in `transpile()` — (1) `declare interface` declarations populate `externalInterfaceTypes`, (2) inline `declare const` forms create synthetic interface entries, (3) named `declare const` forms look up `externalInterfaceTypes` and register in `externalBindings`. All declarations are stripped from source before any downstream parser sees them. Call-site emission records each actually-called method in `usedExternalMethods`; `emitWasiImports()` iterates `usedExternalMethods` to produce the final `(import "env" ...)` declarations.

**Test runner support:** the `env` import object in `runWasi` is now a JavaScript `Proxy` that stubs any undeclared key with `() => 0` — WASM modules with external bindings instantiate without a real host implementation.

**Test coverage:** six test files — `BasicExternalDecl_40`, `ExternalInterfaceType_40`, `MultiMethodExternal_40`, `ExternalReturnValue_40`, `Phase40Combined_40`, and `ExternalMapping_11b` (upgraded from a negative compile-error test to a fully-passing Phase 40 test).

**Known limitations:** nested object types in method signatures (`declare const x: { method(a: { b: i32 }): void }`) are not supported. Only the inline and named-interface forms are recognised. Bare `declare function` / `declare module` / `declare class` are not handled.

---

#### Phase 39 — `jstyper`: JavaScript Import Pre-processor ✅

`jstyper` converts a plain JavaScript file into a typed TypeScript file that wasic can compile to WASM. Type information comes from a hand-edited `.d.ts` declaration file — the `.js` source is never modified, and the `.d.ts` is a permanent, auditable artefact.

**Workflow:**

```bash
# Step 1 — generate a skeleton .d.ts with number placeholders
wasmtk jstyper mathlib.js --dts-only
```

```typescript
// mathlib.d.ts — auto-generated skeleton, then hand-edited
// Before: export declare function add(a: number, b: number): number;
// After:
export declare function add(a: i32, b: i32): i32;        // precise integer type
export declare function lerp(a: f64, b: f64, t: f64): f64; // precise float type
```

```bash
# Step 2 — merge JS bodies with typed .d.ts → produces mathlib.ts
wasmtk jstyper mathlib.js

# Step 3 — compile to WASM as usual
wasmtk wasic mathlib.ts
```

**All CLI flags:**

```bash
wasmtk jstyper <file.js>                 # merge .js + .d.ts → typed .ts
wasmtk jstyper <file.js> --dts-only      # generate skeleton .d.ts only
wasmtk jstyper <file.js> --dry-run       # print output to stdout, don't write
wasmtk jstyper <file.js> --any-policy=skip   # exclude functions with 'any' types
wasmtk jstyper <file.js> --any-policy=warn   # include with i32 fallback + warning (default)
wasmtk jstyper <file.js> --any-policy=default # include with i32 fallback, silent
wasmtk jstyper <file.js> -n out.ts       # override output path
```

**Type mapping:**

| `.d.ts` type | Merged `.ts` type | wasic WASM result |
| --- | --- | --- |
| `i32`, `i64`, `f32`, `f64` | exact | exact WASM type |
| `bool`, `boolean` | exact | `i32` (1/0) |
| `string`, `void`, `never` | exact | as-is |
| `number` | `f64` | `f64` |
| `int` | `i32` | `i32` |
| `float`, `double` | `f64` | `f64` |
| `any` | `i32` + warning (configurable) | `i32` |

**Actionable diagnostics** — every warning and error includes the specific `.d.ts` filename, a verbatim corrected declaration, and the list of valid WASM types. For `--any-policy=skip`, a hint to use `--any-policy=warn` is appended. Example:

```text
⚠  jstyper: skipping 'process' — param 'data' is typed 'any' in utils.d.ts
  Fix: replace 'any' with a concrete type in utils.d.ts:
    export declare function process(x: i32, data: i32): i32;
  Valid WASM types: i32, i64, f32, f64, bool, string, void
  Or use --any-policy=warn to include it as i32 for now.
```

**Implementation:** `src/jstyper.ts` — pure regex/brace-counting, no external dependencies. `parseJsFunctions()` handles regular functions, block-body arrows, and expression-body arrows. `parseDtsFunctions()` handles `export declare function` and `declare function` forms. `generateSkeletonDts()` produces the `--dts-only` output. `generateTypedTs()` merges and maps types.

**Test coverage:** four wasic-compiled integration tests in `tests/wasm_wasi/` + `tests/jstyper_tests.ts` (73 unit assertions covering all parsing, generation, any-policy modes, and file I/O paths).

**Known limitations:** no automatic `.d.ts` generation via `tsc` (no `npm:typescript` dependency — skeleton uses `number` placeholders for hand-editing); arrow functions with a single unparenthesised parameter (`x => x * 2`) are not parsed; transparent tsbundler integration (auto-detection of `.js` imports during `wasmtk wasic`) is deferred to a future phase.

**Files added:** `src/jstyper.ts`, `tests/jstyper_tests.ts`, `tests/jstyper_fixtures/` (3 `.js` + `.d.ts` fixture pairs).

**Files changed:** `main.ts` (`case "jstyper"`, `--dts-only`/`--dry-run`/`--any-policy` flags), `deno.json` (`"./jstyper"` export).

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
