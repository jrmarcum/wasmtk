/**
 * @module wasic
 * @description Standalone WASI compiler producing compact WebAssembly modules
 * without external toolchains or embedded JS runtimes.
 *
 * Two compilation paths:
 *   .wat  → wabt parse → Binaryen size-optimise (-Oz) → .wasm
 *   .ts   → tsbundler (import pre-pass) → WasicTranspiler → WAT → same pipeline
 *
 * Generated binaries are substantially smaller than Javy output because no
 * JavaScript runtime is bundled — only user logic plus the minimal WASI syscall
 * stubs required to satisfy the host (wasmtime, wasmer, wazero, wasmtk run).
 *
 * ── TypeScript subset supported by the transpiler ───────────────────────────
 *
 * Functions & Variables
 *   - Function declarations with typed params (i32/i64/f32/f64/number/string/bool)
 *   - Default parameters:        function f(x: i32 = 0)
 *   - Optional parameters:       function f(x?: i32)
 *   - Arrow functions:           const fn = (x: i32): i32 => x * 2
 *   - First-class function vars: const op: (a: i32, b: i32) => i32 = add
 *   - Closure capture:           outer-scope variables injected as hidden params
 *   - let / const / var declarations with optional type annotations
 *   - return statements
 *
 * Control Flow
 *   - if / else if / else
 *   - while / do-while
 *   - for (init; cond; update)
 *   - switch / case / default / break / fallthrough
 *   - Labeled break and continue:  outer: for(...) { break outer; }
 *   - Ternary:                     cond ? a : b
 *
 * Operators
 *   - Arithmetic:          + - * / %
 *   - Comparisons:         === !== == != < > <= >=
 *   - Logical:             && || !
 *   - Bitwise:             & | ^ ~ << >> >>>
 *   - Compound assignment: += -= *= /= %= &= |= ^= <<= >>= >>>=
 *
 * Numeric Types
 *   - i32, i64 (BigInt literals: 42n), f32, f64, number, boolean
 *   - Enums (numeric):  enum Dir { Up = 0, Down = 1 }  → i32 constants
 *   - never:            function return type → no WAT result clause + (unreachable) appended (Phase 21)
 *   - void:             function return type → no WAT result clause (complete, Phase 21)
 *   - `**` operator:    exponentiation → Math.pow (right-associative, Phase 22)
 *   - `as` assertion:   type cast → WASM trunc/convert/promote/demote/wrap/extend (Phase 22)
 *   - Postfix `!`:      non-null assertion stripped at compile time (Phase 22)
 *   - `satisfies`:      compile-time type hint stripped at compile time (Phase 22)
 *   - `const enum`:     identical to numeric enum — members inlined as i32 constants (Phase 22)
 *
 * Strings
 *   - String literals stored in linear memory as ptr+len pairs
 *   - .length property
 *   - Lexicographic comparisons (===, !==, <, >, <=, >=)
 *   - Template literals:  `x=${x} y=${y}`  with numeric / string interpolation
 *   - console.log / console.error / console.warn with mixed-type argument lists
 *
 * Arrays
 *   - Static arrays:    i32[], f64[] — literal initializer, elements in data section
 *   - Dynamic arrays:   heap-allocated when push/pop/shift/unshift, any Phase 12 method, or spread is used
 *   - Element access:   arr[i], arr[i] = v — static and dynamic
 *   - .length:          compile-time constant (static) or runtime load from header (dynamic)
 *   - push(v):          appends; grows to cap×2 if full
 *   - pop():            removes and returns last element
 *   - shift():          removes and returns first element (O(n) shift)
 *   - unshift(v):       inserts at front; grows to cap×2 if full
 *   - indexOf(v):       i32 index of first match, or -1
 *   - includes(v):      bool — true if element present
 *   - slice(s, e):      new heap array from [s, e); bounds clamped
 *   - forEach(fn):      calls fn(elem) for each element via call_indirect
 *   - map(fn):          new array of fn(elem) results via call_indirect
 *   - filter(fn):       new array of elements where fn(elem) is truthy
 *   - find(fn):         first element where fn(elem) is truthy, or -1/NaN
 *   - reduce(fn, init): folds array to a single value via call_indirect
 *   - Array parameters: passed as i32 pointer
 *   - Rest parameters:  function f(...args: i32[]) — receives heap array ptr; literal call sites build temp array
 *   - Spread call:      f(...arr) — passes existing dynamic array pointer directly
 *   - Spread literal:   const m = [...a, ...b] — new heap array via $__dynarr_concat_T
 *
 * Structs / Objects
 *   - interface / type alias declarations as struct definitions
 *   - Struct literals:   const v: Vec2 = { x: 1.0, y: 2.0 }
 *   - Field read/write:  v.x, v.y = 3.0
 *   - Struct function parameters (passed as i32 pointer)
 *   - Object destructuring:  const { x, y } = vec  → i32.load / f64.load
 *   - Renamed destructuring: const { x: vx } = vec
 *   - readonly fields:   compile-time write guard; writes outside constructor emit a diagnostic (Phase 21)
 *
 * Math
 *   - Math.sqrt, Math.abs, Math.pow, Math.floor, Math.ceil, Math.round
 *   - Math.min, Math.max, Math.sign, Math.trunc  → native WASM ops
 *
 * Multi-file Programs (tsbundler.ts)
 *   - Relative import resolution:  import { foo } from "./lib.ts"
 *   - Import aliases:              import { foo as f } from "./lib.ts"
 *   - Type-only imports:           import type { Foo } from "./lib.ts"
 *   - Side-effect imports:         import "./lib.ts"
 *   - Module-prefix name mangling: same-named symbols across modules never collide
 *   - Chained imports:             lib A imports lib B imports lib C
 *
 * Entry Point
 *   - A top-level main() call or exported _start() becomes the WASI _start entry
 *   - IIFE pattern:  (function main() { ... })()
 *
 * Exception Handling (Phase 15)
 *   - throw new Error("msg")    → (throw $__exn_tag ptr len)
 *   - throw "literal"           → (throw $__exn_tag ptr len)
 *   - throw someStringVar       → (throw $__exn_tag ptr len)
 *   - try { } catch (e) { }     → WAT (try (do ...) (catch $__exn_tag ...))
 *   - try { } finally { }       → WAT (try (do ...) (catch_all ... rethrow 0))
 *   - try { } catch (e) { } finally { }  → combined form
 *   - e / e.message in catch    → string variable (ptr + len locals)
 *
 * ── Not yet supported (planned) ─────────────────────────────────────────────
 *   (none in this area — see Phase 16+ for module system extensions)
 */

import wabt from "wabt";
import binaryen from "binaryen";
import { basename, dirname } from "@std/path";
import { bundleImportsEx } from "./tsbundler.ts";
import { mergeWasmWat, type ExternalFuncDef } from "./wasmmerge.ts";
import {
  IOV_BASE,
  SCRATCH_BASE,
  parseConsoleLogArgs,
  emitConsoleLog,
  getHelperWat,
  type DataAllocator,
  type FuncLookup,
  type StructFieldLookup,
  type DotCallLookup,
} from "./console_log.ts";

// ---------------------------------------------------------------------------
// wabt type stubs (same pattern as utils.ts)
// ---------------------------------------------------------------------------
interface WasmFeatures { enable_all?: boolean; [key: string]: boolean | undefined; }
interface WabtWasmModule {
  toBinary(opts: object): { buffer: ArrayBuffer };
  toText(opts?: { foldExprs?: boolean; inlineExport?: boolean }): string;
  destroy(): void;
}
interface WabtModule {
  parseWat(filename: string, source: string, features?: WasmFeatures): WabtWasmModule;
  readWasm(buffer: ArrayBuffer, opts?: { readDebugNames?: boolean }): WabtWasmModule;
}

// ---------------------------------------------------------------------------
// Public result type
// ---------------------------------------------------------------------------
export interface WasicResult {
  success: boolean;
  outputPath?: string;
  sizeBytes?: number;
  error?: string;
}

// ---------------------------------------------------------------------------
// Core WAT → optimised WASM pipeline
// ---------------------------------------------------------------------------

/**
 * Parses WAT source and applies Binaryen -Oz size-optimisation passes,
 * then writes the resulting binary to outPath.
 */
async function watToOptimisedWasm(
  watSource: string,
  sourcePath: string,
  outPath: string
): Promise<WasicResult> {
  try {
    // Step 1: WAT → raw binary via wabt
    const wabtMod = await (wabt as unknown as () => Promise<WabtModule>)();
    const parsed = wabtMod.parseWat(sourcePath, watSource, { enable_all: true, exceptions: true });
    const { buffer } = parsed.toBinary({});
    parsed.destroy();
    const rawBytes = new Uint8Array(buffer);

    // Step 2: Binaryen -Oz (shrinkLevel=2, optimizeLevel=2)
    const binMod = binaryen.readBinary(rawBytes);
    // Enable all features (incl. exceptions) so the optimizer preserves them.
    const binAny = binaryen as unknown as Record<string, unknown>;
    const featFlags = (binAny["Features"] as Record<string, number> | undefined);
    if (featFlags && typeof (binMod as unknown as Record<string, unknown>)["setFeatures"] === "function") {
      (binMod as unknown as { setFeatures(n: number): void }).setFeatures(featFlags["All"] ?? 0x7FFFFFFF);
    }
    binaryen.setShrinkLevel(2);
    binaryen.setOptimizeLevel(2);
    binMod.optimize();
    const optimised = binMod.emitBinary();
    binMod.dispose();

    await Deno.writeFile(outPath, optimised);
    return { success: true, outputPath: outPath, sizeBytes: optimised.length };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : String(err) };
  }
}

/**
 * Compiles a .wat file to a size-optimised .wasm binary.
 *
 * @param watPath - Path to the WAT source file.
 * @param outPath - Output path; defaults to same name with .wasm extension.
 */
export async function compileWat(watPath: string, outPath?: string): Promise<WasicResult> {
  const out = outPath ?? watPath.replace(/\.wat$/, ".wasm");
  const source = await Deno.readTextFile(watPath);
  const result = await watToOptimisedWasm(source, watPath, out);
  if (result.success) {
    console.log(`✅ WASI: ${out} (${result.sizeBytes} bytes)`);
  } else {
    console.error(`❌ wasic: ${result.error}`);
  }
  return result;
}

// ---------------------------------------------------------------------------
// TypeScript subset transpiler
// ---------------------------------------------------------------------------

/** WAT numeric types plus "string" and "bool" as compiler-level pseudo-types.
 *  "never" marks functions that never return (Phase 21): no WAT result; body ends with unreachable. */
type WatType = "i32" | "i64" | "f32" | "f64" | "string" | "bool" | "never";

/** Maps a compiler WatType to the concrete WAT numeric type (bool → i32, string → i32).
 *  "never" should never reach this function (guarded at call sites), but returns i32 as a safe default. */
function watBaseType(t: WatType): "i32" | "i64" | "f32" | "f64" {
  if (t === "bool" || t === "string" || t === "never") return "i32";
  return t as "i32" | "i64" | "f32" | "f64";
}

interface FuncParam {
  name: string;
  type: WatType;
  defaultValue?: string;   // default expression, e.g. "0" or "42"
  arrayElemType?: WatType; // set when param is an array pointer (T[])
  structType?: string;     // set when param is a struct pointer (stores struct name, e.g. "Point")
  funcTypeInfo?: { params: WatType[]; result: WatType | null }; // set when param is a function type
  isRest?: boolean;        // set when param is a rest parameter (...name: T[])
}

interface StructField {
  name: string;
  type: WatType;
  offset: number;
  size: number;
  /** Phase 21: field declared with `readonly` modifier — writes are a compile-time error. */
  readonly?: boolean;
}

interface StructDef {
  name: string;
  fields: StructField[];
  totalSize: number;
}

interface ClassDef {
  name: string;
  struct: StructDef;
  methods: Array<{ name: string; isStatic: boolean; isConstructor: boolean }>;
}

interface FuncDef {
  name: string;
  params: FuncParam[];
  result: WatType | null;
  exported: boolean;
  bodyLines: string[];
  /** Names of outer-scope variables captured as hidden extra parameters (closure capture). */
  closureCaptures?: string[];
  /** Class name this function is an instance method of (Phase 9). */
  className?: string;
  /** True if this function returns a heap-allocated closure object (Phase 5f). */
  isClosureFactory?: boolean;
  /** The lifted inner arrow returned by this closure factory (Phase 5f). */
  returnedArrow?: FuncDef;
  /** Name of the closure factory whose body returns this arrow (Phase 5f). */
  returnedByFactory?: string;
}

/** Maps TypeScript type annotation strings to WAT types (or the "string"/"never" pseudo-types).
 *  "void" is handled by callers before mapType is invoked and never reaches this function. */
function mapType(ts: string): WatType {
  // Strip union null/undefined modifiers: "string | null" → "string", "T | undefined" → "T"
  const stripped = ts.split("|").map(p => p.trim()).filter(p => p !== "null" && p !== "undefined");
  const base = (stripped[0] ?? ts).trim();
  // Array type annotation T[] → i32 pointer
  if (base.endsWith("[]")) return "i32";
  const t = base.toLowerCase();
  if (t === "never") return "never";                    // Phase 21: never → unreachable at end of body
  // Note: "void" is intercepted at each call site before mapType is invoked; it never reaches here.
  if (t === "i32" || t === "int") return "i32";
  if (t === "i64") return "i64";
  if (t === "f32") return "f32";
  if (t === "bigint") return "i64";
  if (t === "bool" || t === "boolean") return "bool";   // boolean → bool pseudo-type (WAT i32)
  if (t === "string" || t === "str")   return "string"; // pseudo-type: ptr+len i32 locals
  return "f64"; // number, f64, or unknown → f64
}

/** Encodes a 32-bit integer as 4 little-endian WAT escape bytes. */
function encodeI32LE(val: number): string {
  const v = (val | 0) >>> 0;
  return [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]
    .map(b => `\\${b.toString(16).padStart(2, "0")}`).join("");
}

/** Encodes a 64-bit float as 8 little-endian WAT escape bytes. */
function encodeF64LE(val: number): string {
  const buf = new ArrayBuffer(8);
  new DataView(buf).setFloat64(0, val, true);
  return Array.from(new Uint8Array(buf)).map(b => `\\${b.toString(16).padStart(2, "0")}`).join("");
}

/** Returns the WAT zero-literal for a given type. */
function zeroOf(t: WatType): string {
  if (t === "string" || t === "bool") return "(i32.const 0)";
  return t === "f64" ? "(f64.const 0)" : t === "f32" ? "(f32.const 0)" : `(${t}.const 0)`;
}

/**
 * Heuristically infers the WAT result type of a TypeScript init expression
 * when no explicit type annotation is present.
 *
 * Rules (in priority order):
 *   1. bigint literal (42n)              → i64
 *   2. comparison / logical operator     → i32  (comparisons always return i32 in WAT)
 *   3. leading identifier is i64/bigint  → i64
 *   4. enum member (Word.Word)           → i32
 *   5. otherwise                         → f64  (JS "number" default)
 */
function inferInitType(
  initExpr: string,
  locals: Map<string, WatType>,
  enumValues: Map<string, number>,
  functions?: FuncDef[]
): WatType {
  const e = initExpr.trim();
  // 0. boolean literals
  if (e === "true" || e === "false") return "bool";
  // 1. bigint literal
  if (/^-?\d+n$/.test(e)) return "i64";
  // 2. contains a comparison or logical operator → boolean
  if (/===|!==|==|!=|<=|>=|<|>|&&|\|\||^!/.test(e)) return "bool";
  if (e.startsWith("!")) return "bool";
  // 2b. string-producing expressions
  if (e.startsWith('"') || e.startsWith("'")) return "string";   // string literal or concat
  if (/^String\s*\(/.test(e)) return "string";                   // String(n)
  if (/^\w+\.toString\s*\(\s*\)$/.test(e)) return "string";     // n.toString()
  // str.slice(...) — only if receiver is a known string var (checked at call sites; hint here)
  const sliceLeadId = e.match(/^(\w+)\.slice\s*\(/)?.[1];
  if (sliceLeadId && locals.get(sliceLeadId) === "string") return "string";
  // 3. leading identifier has a known declared type — inherit it
  const leadId = e.match(/^(\w+)/)?.[1];
  if (leadId) { const t = locals.get(leadId); if (t) return t; }
  // 4. function call — infer from return type of known function
  const callMatch = e.match(/^(\w+)\s*\(/);
  if (callMatch && functions) {
    const fn = functions.find(f => f.name === callMatch[1]);
    if (fn?.result) return fn.result;
  }
  // 4b. dot-call: Receiver.method(args) — look up prefixed function name
  const dotCallMatch = e.match(/^(\w+)\.(\w+)\s*\(/);
  if (dotCallMatch && functions) {
    const prefixedName = `${dotCallMatch[1]}_${dotCallMatch[2]}`;
    const fn = functions.find(f => f.name === prefixedName);
    if (fn?.result) return fn.result;
  }
  // 5. enum member access
  if (/^\w+\.\w+$/.test(e) && enumValues.has(e)) return "i32";
  // plain integer literal (no decimal, no n suffix) → i32 (typical loop counter)
  if (/^-?\d+$/.test(e)) return "i32";
  return "f64";
}

/** Strips JS/TS comments from source. */
function stripComments(src: string): string {
  return src
    .replace(/\/\/[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
}

// ---------------------------------------------------------------------------
// WasicTranspiler
// ---------------------------------------------------------------------------

class WasicTranspiler {
  private src: string;
  private functions: FuncDef[] = [];

  // String data section: message → [offset, byteLength]
  private dataMap: Map<string, [number, number]> = new Map();
  // iovBase/scratchBase are the module-relative addresses of the fd_write scratch area.
  // Initialized to the standard layout (iov at 0, scratch at 132); Phase 18 merge will
  // allocate these above mainModule.dataOffset for imported modules so they never collide.
  private iovBase: number = IOV_BASE;
  private scratchBase: number = SCRATCH_BASE;
  private dataOffset = this.scratchBase + 4 * 32;  // DATA_BASE = SCRATCH_BASE + SCRATCH_SLOTS*32 = 260

  /** End of the static data section after transpilation — used by Phase 18 merge. */
  get dataEnd(): number { return this.dataOffset; }
  private hasConsoleLog = false;
  private needsNumericHelpers = false;
  private needsStringHelpers = false;
  private needsStringOpHelpers = false;
  private needsStrGatherHelper = false;

  // String data section: message → [offset, byteLength]
  // Raw (non-string) data segments for arrays etc.
  private rawDataSegments: Array<{ ptr: number; bytes: string }> = [];
  // Per-function array variable tracking: varName → { elemType, ptr, length, dynamic?, capacity?, initElements? }
  // ptr=-1: runtime param pointer. ptr=-2: dynamic heap array (ptr in local). ptr>=0: static data address.
  // Reset at the start of each emitFunction call.
  private arrayVars: Map<string, {
    elemType: WatType; ptr: number; length: number;
    dynamic?: boolean; capacity?: number; initElements?: string[];
  }> = new Map();

  // Tracks which dynamic-array WAT helper functions are needed for this module.
  // Key format: "push_i32", "pop_f64", "shift_i32", "unshift_f64", etc.
  private dynArrHelpers: Set<string> = new Set();

  // Set to true when any throw/try/catch is emitted; causes (tag $__exn_tag) to be emitted.
  private needsExceptionTag = false;

  // Compilation mode: "wasi" emits _start + WASI scaffolding; "library" emits only export functions.
  private mode: "wasi" | "library" = "wasi";

  // Struct type definitions parsed from interface/type declarations.
  private structDefs: Map<string, StructDef> = new Map();
  // Per-function struct variable tracking: varName → { def, ptr }
  // ptr=-1 means the struct comes from a parameter (runtime pointer); ptr>=0 is a static address.
  // Reset at the start of each emitFunction call.
  private structVars: Map<string, { def: StructDef; ptr: number }> = new Map();

  // Class definitions (Phase 9): className → ClassDef
  private classDefs: Map<string, ClassDef> = new Map();
  // Per-function class instance variable tracking: varName → { className, ptr }
  // ptr=-1 means the instance comes from a parameter (runtime pointer); ptr>=0 is static address.
  // Reset at the start of each emitFunction call.
  private classVars: Map<string, { className: string; ptr: number }> = new Map();
  // Set to the class name when emitting an instance method body (for `this.field` resolution).
  private currentMethodClass: string | null = null;
  // Set to the WAT function name of the method currently being emitted (Phase 21: constructor check).
  private currentMethodName: string | null = null;

  // Tracks which Math.* WAT helper functions are needed (emitted on demand)
  private mathHelpers: Set<string> = new Set();

  // Tracks variable names declared with type "string" (stored as ptr+len i32 locals)
  private stringVars: Set<string> = new Set();
  // Tracks variable names declared with a function type (e.g. let f: (a: i32) => i32)
  // Stored as Map<name, signature> — the i32 local holds the funcref table index.
  private funcTypeVars: Map<string, { params: WatType[]; result: WatType | null }> = new Map();
  // funcref table: function name → table slot index (assigned lazily as functions are used as values)
  private funcTable: Map<string, number> = new Map();
  // Unique function type signatures for call_indirect: "i32,i32->i32" → "$ftype_i32_i32_r_i32"
  private funcTypes: Map<string, string> = new Map();
  // Counter for synthetic anonymous arrow function names
  private anonArrowCounter = 0;
  // Diagnostics emitted during transpilation for unsupported/unrecognised patterns.
  private diagnostics: string[] = [];
  /** Diagnostics collected during the last transpile() call. */
  get warnings(): readonly string[] { return this.diagnostics; }
  // Enum member name lookup: "EnumName.MemberName" → i32 value
  private enumValues: Map<string, number> = new Map();
  private loopCounter = 0;
  // Stack of { breakLabel, continueLabel? } entries for break/continue emission.
  // switch pushes only breakLabel; loops push both.
  private controlStack: Array<{ breakLabel: string; continueLabel?: string }> = [];
  // When a label precedes a loop/block ("outer: for ..."), the label is stored here
  // so the next loop handler can use it as the WAT label name instead of a counter.
  private pendingLabel: string | null = null;

  // Top-level statements that become the _start body (patterns 2–4)
  private startBodyLines: string[] = [];

  constructor(source: string, mode: "wasi" | "library" = "wasi", externalFuncs: ExternalFuncDef[] = []) {
    this.src = stripComments(source);
    this.mode = mode;
    // Register imported WASM functions so call-site type inference works correctly.
    for (const ef of externalFuncs) {
      this.functions.push({
        name: ef.name,
        params: ef.params.map((t, i) => ({ name: `p${i}`, type: t as WatType })),
        result: ef.result as WatType | null,
        exported: true,
        bodyLines: [], // body is provided by the WAT merge step, not the transpiler
      });
    }
  }

  /** Lazily assigns a funcref table slot to a named function. */
  private getFuncTableIdx(name: string): number {
    if (!this.funcTable.has(name)) this.funcTable.set(name, this.funcTable.size);
    return this.funcTable.get(name)!;
  }

  /** Returns the WAT type name for a unique function signature, creating it if needed. */
  private getOrCreateFuncType(params: WatType[], result: WatType | null): string {
    const key = (params.length ? params.join(",") : "void") + "->" + (result ?? "void");
    if (!this.funcTypes.has(key)) {
      const pStr = params.length ? params.join("_") : "void";
      this.funcTypes.set(key, `$ftype_${pStr}_r_${result ?? "void"}`);
    }
    return this.funcTypes.get(key)!;
  }

  /** Parses a function-type annotation string like "(a: i32, b: i32) => i32" into a signature. */
  private parseFuncTypeSig(typeStr: string): { params: WatType[]; result: WatType | null } {
    const [rawInner, afterClose] = WasicTranspiler.extractParamBlock(typeStr, 0);
    const restMatch = typeStr.slice(afterClose).match(/^\s*=>\s*(\w+)/);
    const result: WatType | null = restMatch?.[1]
      ? (restMatch[1] === "void" ? null : mapType(restMatch[1]) as WatType)
      : null;
    const params: WatType[] = rawInner
      ? rawInner.split(",").map(ip => {
          ip = ip.trim();
          const ci = ip.indexOf(":");
          return (ci !== -1 ? mapType(ip.slice(ci + 1).trim()) : "i32") as WatType;
        }).filter(Boolean)
      : [];
    return { params, result };
  }

  /**
   * Pre-pass: scans all function bodies and startBodyLines for inline arrow literals
   * used as arguments to function calls. Each one is lifted to a synthetic module-level
   * function (__anon_N) and the inline text is replaced with the synthetic name.
   * Must run after injectClosureCaptures() and before transpile() emits functions.
   */
  private liftInlineArrows(): void {
    for (const fn of this.functions) {
      // Pre-scan body for functype variable declarations so assignment arrows can use type info.
      // e.g. `let mathOp: (a: i32, b: i32) => i32` tells us the type of `mathOp = (a, b) => ...`
      const bodyFuncTypes = new Map<string, { params: WatType[]; result: WatType | null }>();
      for (const line of fn.bodyLines) {
        const m = line.match(/^(?:let|const|var)\s+(\w+)\s*:\s*(\([^)]*\)\s*=>\s*\w+)/);
        if (m) bodyFuncTypes.set(m[1], this.parseFuncTypeSig(m[2]));
      }
      fn.bodyLines = fn.bodyLines.map(line => this.substituteOneArrow(line, bodyFuncTypes));
    }
    this.startBodyLines = this.startBodyLines.map(line => this.substituteOneArrow(line, new Map()));
  }

  private substituteOneArrow(
    line: string,
    bodyFuncTypes: Map<string, { params: WatType[]; result: WatType | null }> = new Map()
  ): string {
    if (!line.includes("=>")) return line;

    // Find the first `=>` in the line
    const arrowIdx = line.indexOf("=>");

    // Scan left of `=>` to find the `)` closing the arrow's param list
    let i = arrowIdx - 1;
    while (i >= 0 && line[i] === " ") i--;
    if (i < 0 || line[i] !== ")") return line;

    // Find the matching `(` — this is the start of the arrow params
    let depth = 0;
    let paramsStart = i;
    while (paramsStart >= 0) {
      if (line[paramsStart] === ")") depth++;
      else if (line[paramsStart] === "(") { depth--; if (depth === 0) break; }
      paramsStart--;
    }
    if (paramsStart < 0) return line;

    // Must be preceded by `(` or `,` (argument position), ignoring spaces
    let beforeParens = paramsStart - 1;
    while (beforeParens >= 0 && line[beforeParens] === " ") beforeParens--;
    if (beforeParens < 0 || (line[beforeParens] !== "," && line[beforeParens] !== "(" && line[beforeParens] !== "=")) return line;

    // For `=` (assignment arrow): extract the target variable name.
    // If it's already a known module-level function (parsed by parseArrowFunctions), skip lifting.
    let assignTarget = "";
    if (line[beforeParens] === "=") {
      let nameEnd = beforeParens - 1;
      while (nameEnd >= 0 && line[nameEnd] === " ") nameEnd--;
      let nameStart = nameEnd;
      while (nameStart > 0 && /\w/.test(line[nameStart - 1])) nameStart--;
      assignTarget = line.slice(nameStart, nameEnd + 1);
      if (this.functions.find(f => f.name === assignTarget)) return line; // already handled
    }

    // Find the end of the arrow body (expression or block)
    let bodyStart = arrowIdx + 2;
    while (bodyStart < line.length && line[bodyStart] === " ") bodyStart++;

    let arrowEnd: number;
    if (line[bodyStart] === "{") {
      depth = 0; arrowEnd = bodyStart;
      while (arrowEnd < line.length) {
        if (line[arrowEnd] === "{") depth++;
        else if (line[arrowEnd] === "}") { depth--; if (depth === 0) { arrowEnd++; break; } }
        arrowEnd++;
      }
    } else {
      depth = 0; arrowEnd = bodyStart;
      while (arrowEnd < line.length) {
        const ch = line[arrowEnd];
        if (ch === "(" || ch === "[") depth++;
        else if (ch === ")" || ch === "]") { if (depth === 0) break; depth--; }
        else if ((ch === "," || ch === ";") && depth === 0) break;
        arrowEnd++;
      }
    }

    // Determine the enclosing function call and arg index to get type info
    let calleeName = "";
    let argIdx = 0;
    const preceding = line[beforeParens];

    if (preceding === "(") {
      // First arg: find function name before `(`
      let nameEnd = beforeParens;
      while (nameEnd > 0 && /\w/.test(line[nameEnd - 1])) nameEnd--;
      calleeName = line.slice(nameEnd, beforeParens);
      argIdx = 0;
    } else if (preceding !== "=") {
      // After a comma: find enclosing `(` and count commas
      depth = 1; let j = beforeParens - 1; argIdx = 1;
      while (j >= 0 && depth > 0) {
        if (line[j] === ")") depth++;
        else if (line[j] === "(") { depth--; if (depth === 0) break; }
        else if (line[j] === "," && depth === 1) argIdx++;
        j--;
      }
      let nameEnd = j;
      while (nameEnd > 0 && /\w/.test(line[nameEnd - 1])) nameEnd--;
      calleeName = line.slice(nameEnd, j);
    }
    // else: assignment — calleeName stays "", type info comes from bodyFuncTypes

    const calleeFn = this.functions.find(f => f.name === calleeName);
    // For assignment arrows, look up the declared functype of the target variable
    const assignInfo = preceding === "=" ? bodyFuncTypes.get(assignTarget) : undefined;
    const paramInfo = calleeFn?.params[argIdx]?.funcTypeInfo ?? assignInfo;

    // Parse the inline arrow's params
    const innerRaw = line.slice(paramsStart + 1, i).trim();
    const paramList: FuncParam[] = [];
    if (innerRaw) {
      innerRaw.split(",").map(p => p.trim()).filter(Boolean).forEach((pp, pi) => {
        const ci = pp.indexOf(":");
        const pname = ci !== -1 ? pp.slice(0, ci).trim().replace(/\?$/, "") : pp.trim();
        const ptype: WatType = ci !== -1
          ? mapType(pp.slice(ci + 1).trim()) as WatType
          : (paramInfo?.params[pi] ?? "i32" as WatType);
        paramList.push({ name: pname, type: ptype });
      });
    }

    // Parse optional return type annotation between `)` and `=>`
    const betweenParenArrow = line.slice(i + 1, arrowIdx).trim();
    const retAnnotation = betweenParenArrow.match(/^:\s*(\w+)/)?.[1];
    const anonResult: WatType | null = retAnnotation
      ? (retAnnotation === "void" ? null : mapType(retAnnotation) as WatType)
      : (paramInfo?.result ?? null);

    // Build body lines
    const bodyRaw = line.slice(bodyStart, arrowEnd).trim();
    let bodyLines: string[];
    if (bodyRaw.startsWith("{")) {
      const inner = bodyRaw.slice(1, bodyRaw.endsWith("}") ? -1 : undefined).trim();
      bodyLines = inner.split(";").map(l => l.trim()).filter(Boolean).map(l => l.endsWith(";") ? l : l + ";");
    } else {
      bodyLines = anonResult !== null ? [`return ${bodyRaw};`] : [`${bodyRaw};`];
    }

    const anonName = `__anon_${this.anonArrowCounter++}`;
    this.functions.push({ name: anonName, params: paramList, result: anonResult, exported: false, bodyLines });
    this.getFuncTableIdx(anonName);

    return line.slice(0, paramsStart) + anonName + line.slice(arrowEnd);
  }

  /** Emits (type $ftype_... (func ...)) declarations for all used call_indirect signatures. */
  private emitFuncTypes(): string {
    if (this.funcTypes.size === 0) return "";
    const lines: string[] = [];
    for (const [key, typeName] of this.funcTypes) {
      const [paramPart, resultPart] = key.split("->");
      const params = paramPart === "void" ? "" : paramPart.split(",").map(t => `(param ${t})`).join(" ");
      const result = resultPart === "void" ? "" : `(result ${resultPart})`;
      lines.push(`  (type ${typeName} (func ${[params, result].filter(Boolean).join(" ")}))`);
    }
    return lines.join("\n");
  }

  /** Emits (table N funcref) and (elem ...) for all functions registered in funcTable. */
  private emitFuncrefTable(): string {
    if (this.funcTable.size === 0) return "";
    const sorted = [...this.funcTable.entries()].sort((a, b) => a[1] - b[1]);
    const elem = sorted.map(([name]) => `$${name}`).join(" ");
    return [
      `  (table ${this.funcTable.size} funcref)`,
      `  (elem (i32.const 0) ${elem})`,
    ].join("\n");
  }

  // -------------------------------------------------------------------------
  // Pass 1 – collect function signatures and bodies
  // -------------------------------------------------------------------------
  /**
   * Extracts the content of a parenthesised block starting at `openParen` in `src`.
   * `src[openParen]` must be `(`.
   * Returns [innerContent, indexAfterCloseParen].
   */
  private static extractParamBlock(src: string, openParen: number): [string, number] {
    let depth = 1;
    let i = openParen + 1;
    while (i < src.length && depth > 0) {
      if (src[i] === "(") depth++;
      else if (src[i] === ")") depth--;
      i++;
    }
    return [src.slice(openParen + 1, i - 1), i];
  }

  /**
   * Shared param parser used by parseFunctions and parseArrowFunctions.
   * Handles function-type params (`name: (p) => retType`) by treating them
   * as `i32` placeholders and registering the name in funcTypeVars.
   */
  private parseParams(rawParams: string): FuncParam[] {
    if (!rawParams.trim()) return [];
    // Paren-aware comma split so function-type params don't get split mid-type
    const paramStrs: string[] = [];
    let depth = 0, start = 0;
    for (let i = 0; i < rawParams.length; i++) {
      if (rawParams[i] === "(") depth++;
      else if (rawParams[i] === ")") depth--;
      else if (rawParams[i] === "," && depth === 0) {
        paramStrs.push(rawParams.slice(start, i).trim());
        start = i + 1;
      }
    }
    paramStrs.push(rawParams.slice(start).trim());

    return paramStrs.filter(p => p.length > 0).map(p => {
      // Rest parameter: ...name: T[]
      if (p.startsWith("...")) {
        const withoutDots = p.slice(3);
        const colonIdx = withoutDots.indexOf(":");
        const name = colonIdx !== -1 ? withoutDots.slice(0, colonIdx).trim() : withoutDots.trim();
        const typeAnnotation = colonIdx !== -1 ? withoutDots.slice(colonIdx + 1).trim().replace(/\s*=.*$/, "") : "i32[]";
        const arrElemMatch = typeAnnotation.match(/^(\w+)\[\]$/);
        const arrayElemType: WatType = arrElemMatch ? mapType(arrElemMatch[1]) as WatType : "i32";
        return { name, type: "i32" as WatType, isRest: true, arrayElemType };
      }
      // Function-type param: name: (params) => retType  — track as funcTypeVar (i32 = table index)
      if (/^\w+\s*:\s*\(/.test(p) && p.includes("=>")) {
        const nm = p.match(/^(\w+)/)![1];
        const sig = this.parseFuncTypeSig(p.slice(p.indexOf(":") + 1).trim());
        this.funcTypeVars.set(nm, sig);
        return { name: nm, type: "i32" as WatType, funcTypeInfo: sig };
      }
      const colonIdx = p.indexOf(":");
      if (colonIdx === -1) return { name: p.trim(), type: "f64" as WatType };
      const rawName = p.slice(0, colonIdx).trim();
      // Optional param: name?: type  — strip '?' and default to zero
      const isOptional = rawName.endsWith("?");
      const name = isOptional ? rawName.slice(0, -1) : rawName;
      const afterColon = p.slice(colonIdx + 1).trim();
      const typeAnnotation = afterColon.replace(/\s*=.*$/, "").trim();
      const paramType = mapType(typeAnnotation);
      // Detect array param: T[] → i32 pointer with element type T
      const arrElemMatch = typeAnnotation.match(/^(\w+)\[\]$/);
      const arrayElemType: WatType | undefined = arrElemMatch
        ? mapType(arrElemMatch[1]) as WatType : undefined;
      // Detect struct param: capitalized type name that isn't a known primitive
      // structType is stored so emitFunction can register it in structVars.
      const structType: string | undefined =
        !arrElemMatch && /^[A-Z]\w*$/.test(typeAnnotation) ? typeAnnotation : undefined;
      const resolvedType: WatType = structType ? "i32" : paramType;
      // Split "type = defaultExpr" if an explicit default value is present
      const eqIdx = afterColon.indexOf("=");
      if (eqIdx !== -1) {
        return { name, type: resolvedType, defaultValue: afterColon.slice(eqIdx + 1).trim(), arrayElemType, structType };
      }
      if (isOptional) {
        return { name, type: resolvedType, defaultValue: "0", arrayElemType, structType };
      }
      return { name, type: resolvedType, arrayElemType, structType };
    });
  }

  private parseFunctions(): void {
    const src = this.src;
    // Find `[export] function name(` — params extracted separately to handle nested parens
    const headerRe = /(export\s+)?function\s+(\w+)\s*\(/g;
    let m: RegExpExecArray | null;

    while ((m = headerRe.exec(src)) !== null) {
      const exported = !!m[1];
      const name = m[2];
      const openParen = m.index + m[0].length - 1; // position of opening `(`

      // Extract param list with paren-counting (handles function-type params)
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);

      // After `)` expect optional `: returnType` then `{`
      const restMatch = src.slice(afterClose).match(/^\s*(?::\s*(\w+))?\s*\{/);
      if (!restMatch) continue; // malformed header — skip

      const rawResult = (restMatch[1] ?? "void").trim();
      const result: WatType | null =
        rawResult === "void" || rawResult === "" ? null : mapType(rawResult);

      // Extract body by counting braces from the opening {
      const bodyStart = afterClose + restMatch[0].length;
      let depth = 1;
      let i = bodyStart;
      while (i < src.length && depth > 0) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}") depth--;
        i++;
      }
      const rawBody = src.slice(bodyStart, i - 1);
      const bodyLines = rawBody
        .split("\n")
        .map(l => l.trim())
        .filter(l => l.length > 0);

      // Phase 5f: detect closure factory — body is `return (params) => expr;`
      const returnedArrow = this.parseReturnArrow(name, bodyLines);
      if (returnedArrow) this.functions.push(returnedArrow);
      this.functions.push({
        name, params: this.parseParams(rawParams),
        result: returnedArrow ? "i32" : result,
        exported, bodyLines,
        isClosureFactory: !!returnedArrow,
        returnedArrow: returnedArrow ?? undefined,
      });
    }
  }

  // -------------------------------------------------------------------------
  // Pass 1a-extra – parse the arrow returned by a closure factory (Phase 5f)
  // -------------------------------------------------------------------------
  /**
   * If any body line is `return (params): retType => expr;`, lifts the returned
   * arrow as `${factoryName}__inner` and returns its FuncDef.  Returns undefined
   * if this function is not a closure factory.
   */
  private parseReturnArrow(factoryName: string, bodyLines: string[]): FuncDef | undefined {
    const retLine = bodyLines.find(l => /^return\s+\(/.test(l) && l.includes("=>"));
    if (!retLine) return undefined;

    // Strip `return ` prefix and trailing `;`
    const body = retLine.replace(/^return\s+/, "").replace(/;$/, "").trim();
    if (!body.startsWith("(")) return undefined;

    const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(body, 0);
    const restMatch = body.slice(afterClose).match(/^\s*(?::\s*(\w+))?\s*=>/);
    if (!restMatch) return undefined;

    const rawResult = (restMatch[1] ?? "").trim();
    let result: WatType | null = rawResult === "void" || rawResult === "" ? null : mapType(rawResult);

    let bodyStart = afterClose + restMatch[0].length;
    while (bodyStart < body.length && body[bodyStart] === " ") bodyStart++;

    let innerBodyLines: string[];
    if (body[bodyStart] === "{") {
      let depth = 1;
      let ci = bodyStart + 1;
      while (ci < body.length && depth > 0) {
        if (body[ci] === "{") depth++;
        else if (body[ci] === "}") depth--;
        ci++;
      }
      const rawBody = body.slice(bodyStart + 1, ci - 1);
      innerBodyLines = rawBody.split("\n").map(l => l.trim()).filter(l => l.length > 0);
    } else {
      const rawExpr = body.slice(bodyStart).trim().replace(/;$/, "");
      // Infer result type when no explicit annotation was given (e.g. `(val: i32) => val * x`).
      // Build a minimal locals map from the parsed params so inferInitType can resolve identifiers.
      if (result === null) {
        const paramLocals = new Map<string, WatType>();
        for (const p of this.parseParams(rawParams)) paramLocals.set(p.name, p.type);
        result = inferInitType(rawExpr, paramLocals, this.enumValues, this.functions);
      }
      innerBodyLines = result !== null ? [`return ${rawExpr};`] : [`${rawExpr};`];
    }

    const innerName = `${factoryName}__inner`;
    if (this.functions.find(f => f.name === innerName)) return undefined; // already added

    return {
      name: innerName,
      params: this.parseParams(rawParams),
      result,
      exported: false,
      bodyLines: innerBodyLines,
      returnedByFactory: factoryName,
    };
  }

  // -------------------------------------------------------------------------
  // Pass 1b – collect arrow-function declarations
  // -------------------------------------------------------------------------
  /**
   * Scans for top-level and nested `const name = (params): retType => body`
   * declarations and lifts them into this.functions alongside regular functions.
   * Two body forms are supported:
   *   - Block body:      const f = (a: i32): i32 => { return a + 1; }
   *   - Expression body: const f = (a: i32): i32 => a + 1;
   */
  private parseArrowFunctions(): void {
    const src = this.src;
    // Find `[export] const name = (` — params extracted separately to handle nested parens
    const headerRe = /(?:export\s+)?const\s+(\w+)\s*=\s*\(/g;
    let m: RegExpExecArray | null;

    while ((m = headerRe.exec(src)) !== null) {
      const name = m[1];
      const openParen = m.index + m[0].length - 1;

      // Extract param list with paren-counting
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);

      // After `)` expect optional `: retType` then `=>` — if not present, not an arrow function
      const restMatch = src.slice(afterClose).match(/^\s*(?::\s*(\w+))?\s*=>/);
      if (!restMatch) continue;

      const rawResult = (restMatch[1] ?? "").trim();
      const result: WatType | null =
        rawResult === "void" || rawResult === "" ? null : mapType(rawResult);

      // Find start of body (skip whitespace after =>)
      let bodyStart = afterClose + restMatch[0].length;
      while (bodyStart < src.length && src[bodyStart] === " ") bodyStart++;

      let bodyLines: string[];
      if (src[bodyStart] === "{") {
        // Block body: brace-count extraction (same as parseFunctions)
        let depth = 1;
        let i = bodyStart + 1;
        while (i < src.length && depth > 0) {
          if (src[i] === "{") depth++;
          else if (src[i] === "}") depth--;
          i++;
        }
        const rawBody = src.slice(bodyStart + 1, i - 1);
        bodyLines = rawBody.split("\n").map(l => l.trim()).filter(l => l.length > 0);
      } else {
        // Expression body: read to end-of-line / semicolon
        const eol = src.indexOf("\n", bodyStart);
        const rawExpr = (eol !== -1 ? src.slice(bodyStart, eol) : src.slice(bodyStart))
          .trim()
          .replace(/;$/, "");
        bodyLines = result !== null ? [`return ${rawExpr};`] : [`${rawExpr};`];
      }

      // Avoid duplicates (nested arrows inside functions share the source scan)
      if (!this.functions.find(f => f.name === name)) {
        this.functions.push({ name, params: this.parseParams(rawParams), result, exported: false, bodyLines });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Pass 2 – collect top-level statements for _start
  // -------------------------------------------------------------------------
  /**
   * Scans source lines at brace-depth 0 and populates startBodyLines with
   * statements that should run in _start. Handles all four TS entry patterns:
   *
   *   Pattern 1: function main(){...}; main();
   *     → main() is already in this.functions; hasMain logic in transpile() calls it.
   *       The bare `main();` call is skipped here.
   *
   *   Pattern 2: (function main(){...}).call(this);
   *     → parseFunctions() captured the inner function; the IIFE wrapper is skipped
   *       so the body isn't duplicated. hasMain logic in transpile() calls it.
   *
   *   Pattern 3: if (import.meta.main) { ... }
   *     → The block body is collected into startBodyLines.
   *
   *   Pattern 4: bare top-level statement (e.g. console.log(...))
   *     → Collected directly into startBodyLines.
   */
  private parseTopLevel(): void {
    const lines = this.src.split("\n").map(l => l.trim()).filter(l => l.length > 0);
    let depth = 0;
    let collectInner = false; // true while inside an import.meta.main block

    for (const line of lines) {
      const opens  = (line.match(/\{/g) ?? []).length;
      const closes = (line.match(/\}/g) ?? []).length;

      if (depth === 0) {
        // Regular function declaration — skip body, already parsed
        if (/^(?:export\s+)?function\s+\w+/.test(line)) {
          depth += opens - closes;
          continue;
        }

        // Arrow function declaration — skip body, already parsed by parseArrowFunctions
        if (/^(?:export\s+)?(?:const|let)\s+\w+\s*=\s*\(/.test(line) && line.includes("=>")) {
          depth += opens - closes;
          continue;
        }

        // Pattern 2: IIFE (function …) — inner function already parsed, call it in _start
        if (/^\(function\s+/.test(line)) {
          const iifeNameMatch = line.match(/^\(function\s+(\w+)/);
          if (iifeNameMatch && iifeNameMatch[1] !== "main") {
            this.startBodyLines.push(`${iifeNameMatch[1]}();`);
          }
          depth += opens - closes;
          continue;
        }

        // Enum declaration — skip body (values captured by parseEnums)
        if (/^(?:export\s+)?(?:const\s+)?enum\s+\w+/.test(line)) {
          depth += opens - closes;
          continue;
        }

        // Class declaration — skip body, already parsed by parseClasses
        if (/^(?:export\s+)?class\s+\w+/.test(line)) {
          depth += opens - closes;
          continue;
        }

        // Interface / type alias declaration — skip body
        if (/^(?:export\s+)?(?:interface|type)\s+\w+/.test(line)) {
          depth += opens - closes;
          continue;
        }

        // Pattern 3: if (import.meta.main) { … }
        if (/^if\s*\(\s*import\.meta\.main\s*\)/.test(line)) {
          depth += opens - closes;
          collectInner = true;
          continue;
        }

        // Pattern 1 trailing call: main(); — hasMain handles it
        if (/^main\s*\(\s*\)\s*;?$/.test(line)) continue;

        // Skip bare closing braces, comment lines, and export/import statements
        if (line === "}" || line === "};" || line === ";" ) continue;
        if (line.startsWith("//") || line.startsWith("*") || line.startsWith("import ") || line.startsWith("export {")) continue;

        // Pattern 4: bare top-level statement → goes into _start
        this.startBodyLines.push(line);

      } else {
        // Inside a function/block body
        const newDepth = depth + opens - closes;

        if (collectInner) {
          // Collect lines belonging to if (import.meta.main) block.
          // When newDepth would reach 0 this is the closing } — don't collect it.
          if (newDepth >= 1) {
            this.startBodyLines.push(line);
          } else {
            collectInner = false;
          }
        }

        depth = Math.max(0, newDepth);
        if (depth === 0) collectInner = false;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Pre-pass 0g – generic template expansion (monomorphization)
  // -------------------------------------------------------------------------
  /**
   * Expands generic function and struct templates by monomorphization.
   * Must run before all other parse passes so concrete definitions are visible
   * to parseStructs, parseFunctions, etc.
   *
   * Supports:
   *   function identity<T>(x: T): T                — generic function
   *   interface Box<T> { value: T; count: i32; }   — generic struct
   *   identity<i32>(42)                             — explicit type args at call site
   *   identity(42)                                  — single-T inference from literal arg
   *   const b: Box<i32> = { ... }                   — generic type annotation rewriting
   *   function f<T>(b: Box<T>): T                   — generic struct ref in func signature
   *
   * Returns the rewritten source with:
   *   - Generic templates removed
   *   - Concrete monomorphized definitions prepended
   *   - All use sites rewritten to concrete names (e.g., identity_i32, Box_f64)
   */
  private expandGenerics(src: string): string {
    type GFuncTmpl = {
      typeParams: string[];
      rawParams: string;
      rawResult: string;
      bodyText: string;
      exported: boolean;
      start: number;
      end: number;
    };
    type GStructTmpl = {
      typeParams: string[];
      rawFields: string;
      start: number;
      end: number;
    };

    const gFuncs   = new Map<string, GFuncTmpl>();
    const gStructs = new Map<string, GStructTmpl>();

    // --- 1. Find generic function templates: [export] function name<T,...>( ---
    const gFuncRe = /(export\s+)?function\s+(\w+)\s*<([^>]+)>\s*\(/g;
    let m: RegExpExecArray | null;
    while ((m = gFuncRe.exec(src)) !== null) {
      const exported   = !!m[1];
      const name       = m[2];
      const typeParams = m[3].split(",").map(t => t.trim()).filter(Boolean);
      const openParen  = m.index + m[0].length - 1;
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);
      // Return type may be a type param (T) or a generic type (Box<T>) — use permissive match
      const restMatch = src.slice(afterClose).match(/^\s*(?::\s*([\w<>, ]+?))?\s*\{/);
      if (!restMatch) continue;
      const rawResult = (restMatch[1] ?? "void").trim();
      const bodyStart = afterClose + restMatch[0].length;
      let depth = 1, i = bodyStart;
      while (i < src.length && depth > 0) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}") depth--;
        i++;
      }
      gFuncs.set(name, {
        typeParams, rawParams, rawResult,
        bodyText: src.slice(bodyStart, i - 1),
        exported, start: m.index, end: i,
      });
    }

    // --- 2. Find generic struct templates: interface Name<T,...> { ... } ---
    const gStructRe = /(?:export\s+)?interface\s+(\w+)\s*<([^>]+)>\s*\{([^}]*)\}/g;
    while ((m = gStructRe.exec(src)) !== null) {
      const name       = m[1];
      const typeParams = m[2].split(",").map(t => t.trim()).filter(Boolean);
      gStructs.set(name, { typeParams, rawFields: m[3], start: m.index, end: m.index + m[0].length });
    }
    // Also handle: type Name<T> = { ... }
    const gTypeRe = /(?:export\s+)?type\s+(\w+)\s*<([^>]+)>\s*=\s*\{([^}]*)\}/g;
    while ((m = gTypeRe.exec(src)) !== null) {
      const name = m[1];
      if (!gStructs.has(name)) {
        const typeParams = m[2].split(",").map(t => t.trim()).filter(Boolean);
        gStructs.set(name, { typeParams, rawFields: m[3], start: m.index, end: m.index + m[0].length });
      }
    }

    if (gFuncs.size === 0 && gStructs.size === 0) return src;

    // --- 3. Storage for generated concrete definitions ---
    const concreteFuncs   = new Map<string, string>(); // concreteName → TS source
    const concreteStructs = new Map<string, string>(); // concreteName → TS source

    // Substitute each type param with its concrete type string in text
    const substitute = (text: string, typeParams: string[], concreteTypes: string[]): string => {
      let result = text;
      for (let i = 0; i < typeParams.length; i++) {
        result = result.replace(new RegExp(`\\b${typeParams[i]}\\b`, "g"), concreteTypes[i] ?? "i32");
      }
      return result;
    };

    // Create (or retrieve) a concrete struct definition
    const getOrCreateStruct = (name: string, tmpl: GStructTmpl, typeArgs: string[]): string => {
      const concreteName = `${name}_${typeArgs.join("_")}`;
      if (!concreteStructs.has(concreteName)) {
        const fields = substitute(tmpl.rawFields, tmpl.typeParams, typeArgs);
        concreteStructs.set(concreteName, `interface ${concreteName} {${fields}}`);
      }
      return concreteName;
    };

    // Create (or retrieve) a concrete function definition
    const getOrCreateFunc = (name: string, tmpl: GFuncTmpl, typeArgs: string[]): string => {
      const concreteName = `${name}_${typeArgs.join("_")}`;
      if (!concreteFuncs.has(concreteName)) {
        // Placeholder prevents infinite recursion on recursive generic functions
        concreteFuncs.set(concreteName, "");
        let params = substitute(tmpl.rawParams, tmpl.typeParams, typeArgs);
        let result = substitute(tmpl.rawResult, tmpl.typeParams, typeArgs);
        let body   = substitute(tmpl.bodyText,  tmpl.typeParams, typeArgs);
        // Rewrite any generic struct refs that appear in params / result / body
        for (const [sName, sTmpl] of gStructs) {
          const sRe     = new RegExp(`\\b${sName}\\s*<([\\w,\\s]+)>`, "g");
          const rewrite = (str: string) => str.replace(sRe, (_: string, tArgStr: string) => {
            const tArgs = tArgStr.split(",").map((t: string) => t.trim());
            return getOrCreateStruct(sName, sTmpl, tArgs);
          });
          params = rewrite(params);
          result = rewrite(result);
          body   = rewrite(body);
        }
        // Rewrite explicit generic function calls inside the body
        for (const [fName, fTmpl] of gFuncs) {
          const fRe = new RegExp(`\\b${fName}\\s*<([\\w,\\s]+)>\\s*\\(`, "g");
          body = body.replace(fRe, (_: string, tArgStr: string) => {
            const tArgs = tArgStr.split(",").map((t: string) => t.trim());
            return `${getOrCreateFunc(fName, fTmpl, tArgs)}(`;
          });
        }
        const exportKw = tmpl.exported ? "export " : "";
        const retPart  = (result === "void" || !result) ? "" : `: ${result}`;
        concreteFuncs.set(concreteName,
          `${exportKw}function ${concreteName}(${params})${retPart} {\n${body}\n}`);
      }
      return concreteName;
    };

    // Infer a concrete type name from a simple literal expression.
    // Returns null when the expression is too complex to type-infer (e.g., bare identifier).
    const inferArgTypeLiteral = (expr: string): string | null => {
      const e = expr.trim();
      if (e === "true" || e === "false") return "bool";
      if (/^-?\d+n$/.test(e))           return "i64";
      if (e.startsWith('"') || e.startsWith("'")) return "string";
      if (/^-?\d+\.\d/.test(e) || /^\d*\.\d+/.test(e)) return "f64";
      if (/^-?\d+$/.test(e))            return "i32";
      return null;
    };

    // --- 4. Remove generic templates from source (reverse order to preserve offsets) ---
    const removals = [
      ...[...gFuncs.values()].map(t => ({ start: t.start, end: t.end })),
      ...[...gStructs.values()].map(t => ({ start: t.start, end: t.end })),
    ].sort((a, b) => b.start - a.start);

    let out = src;
    for (const { start, end } of removals) {
      out = out.slice(0, start) + out.slice(end);
    }

    // --- 5. Rewrite use sites in the template-stripped source ---

    // 5a. Rewrite generic type annotations: Name<T1, T2> → Name_T1_T2
    for (const [name, tmpl] of gStructs) {
      const re = new RegExp(`\\b${name}\\s*<([\\w,\\s]+)>`, "g");
      out = out.replace(re, (_: string, typeArgStr: string) => {
        const typeArgs = typeArgStr.split(",").map((t: string) => t.trim());
        return getOrCreateStruct(name, tmpl, typeArgs);
      });
    }

    // 5b. Rewrite explicit generic function calls: funcName<T1,T2>(args) → funcName_T1_T2(args)
    for (const [name, tmpl] of gFuncs) {
      const re = new RegExp(`\\b${name}\\s*<([\\w,\\s]+)>\\s*\\(`, "g");
      out = out.replace(re, (_: string, typeArgStr: string) => {
        const typeArgs = typeArgStr.split(",").map((t: string) => t.trim());
        return `${getOrCreateFunc(name, tmpl, typeArgs)}(`;
      });
    }

    // 5c. Inferred calls (single type param only): funcName(literal) → funcName_inferredType(literal)
    //     Only fires for functions that still have bare calls after step 5b.
    for (const [name, tmpl] of gFuncs) {
      if (tmpl.typeParams.length !== 1) continue;
      const re = new RegExp(`\\b${name}\\s*\\(`, "g");
      out = out.replace(re, (match: string, offset: number, str: string) => {
        // Peek at the first argument to infer T
        const afterParen = str.slice(offset + match.length);
        let depth = 0, end = 0;
        for (let i = 0; i < afterParen.length; i++) {
          const c = afterParen[i];
          if (c === "(" || c === "[") { depth++; }
          else if ((c === ")" || c === "]") && depth > 0) { depth--; }
          else if (c === ")" && depth === 0) { end = i; break; }
          else if (c === "," && depth === 0) { end = i; break; }
        }
        const firstArg     = afterParen.slice(0, end).trim();
        const inferredType = inferArgTypeLiteral(firstArg);
        if (!inferredType) return match; // Can't infer — leave unchanged
        return `${getOrCreateFunc(name, tmpl, [inferredType])}(`;
      });
    }

    // --- 6. Prepend concrete definitions and return the expanded source ---
    const allConcrete = [
      ...[...concreteStructs.values()],
      ...[...concreteFuncs.values()],
    ].join("\n\n");

    return allConcrete + "\n\n" + out;
  }

  // -------------------------------------------------------------------------
  // Pass 0 – collect enum declarations
  // -------------------------------------------------------------------------
  /**
   * Scans source for numeric enum/const enum declarations and populates
   * enumValues with "EnumName.MemberName" → number entries.
   * Supports explicit values (Up = 3) and auto-increment from the last explicit value.
   */
  private parseEnums(): void {
    const enumRe = /(?:export\s+)?(?:const\s+)?enum\s+(\w+)\s*\{([^}]*)\}/g;
    let m: RegExpExecArray | null;
    while ((m = enumRe.exec(this.src)) !== null) {
      const enumName = m[1];
      const body = m[2];
      let autoVal = 0;
      // Each member: optional whitespace, name, optional = value, optional comma
      const memberRe = /(\w+)\s*(?:=\s*(-?\d+))?\s*,?/g;
      let mm: RegExpExecArray | null;
      while ((mm = memberRe.exec(body)) !== null) {
        const memberName = mm[1];
        const val = mm[2] !== undefined ? parseInt(mm[2], 10) : autoVal;
        this.enumValues.set(`${enumName}.${memberName}`, val);
        autoVal = val + 1;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Pass 0b – collect struct/interface declarations
  // -------------------------------------------------------------------------
  /**
   * Scans source for `interface Name { ... }` and `type Name = { ... }` declarations.
   * Computes field offsets with natural alignment and populates `structDefs`.
   */
  private parseStructs(): void {
    const patterns = [
      /(?:export\s+)?interface\s+(\w+)\s*\{([^}]*)\}/g,
      /(?:export\s+)?type\s+(\w+)\s*=\s*\{([^}]*)\}/g,
    ];
    for (const re of patterns) {
      let m: RegExpExecArray | null;
      while ((m = re.exec(this.src)) !== null) {
        const name = m[1];
        const body = m[2];
        const fields: StructField[] = [];
        let offset = 0;
        // Match optional "readonly" prefix, then "fieldName: typeName;" or "fieldName?: typeName;"
        const fieldRe = /(?:(readonly)\s+)?(\w+)\??:\s*([\w\[\]]+)/g;
        let fm: RegExpExecArray | null;
        while ((fm = fieldRe.exec(body)) !== null) {
          const isReadonly = fm[1] === "readonly";
          const fieldName = fm[2];
          const type = mapType(fm[3]);
          const size = (type === "f64" || type === "i64") ? 8 : 4;
          // Natural alignment: round offset up to a multiple of size
          if (offset % size !== 0) offset = Math.ceil(offset / size) * size;
          fields.push({ name: fieldName, type, offset, size, ...(isReadonly ? { readonly: true } : {}) });
          offset += size;
        }
        if (fields.length > 0) {
          this.structDefs.set(name, { name, fields, totalSize: offset });
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Pass 0c – collect class declarations
  // -------------------------------------------------------------------------
  /**
   * Scans source for `class Name { ... }` declarations.
   * For each class:
   *   - Creates a StructDef for the instance fields and registers it in structDefs.
   *   - Creates a ClassDef with the method list.
   *   - Generates FuncDef entries for constructor and methods (prepending __self: i32).
   *   - Static methods get no hidden parameter.
   */
  private parseClasses(): void {
    const src = this.src;
    const classRe = /(?:export\s+)?class\s+(\w+)(?:\s+extends\s+\w+)?\s*\{/g;
    let m: RegExpExecArray | null;

    while ((m = classRe.exec(src)) !== null) {
      const className = m[1];
      const classBodyStart = m.index + m[0].length;

      // Find end of class body by brace counting
      let depth = 1, ci = classBodyStart;
      while (ci < src.length && depth > 0) {
        if (src[ci] === "{") depth++;
        else if (src[ci] === "}") depth--;
        ci++;
      }
      const classBodyEnd = ci - 1;
      const classBody = src.slice(classBodyStart, classBodyEnd);

      // Parse instance fields: scan line by line at depth 0
      const fields: StructField[] = [];
      let fieldOffset = 0;
      let fieldDepth = 0;

      for (const rawLine of classBody.split("\n")) {
        const line = rawLine.trim();
        const opens = (rawLine.match(/\{/g) ?? []).length;
        const closes = (rawLine.match(/\}/g) ?? []).length;

        if (fieldDepth === 0 && line && !line.includes("(") && !/\bstatic\b/.test(line)) {
          // Phase 21: capture readonly modifier before stripping all access modifiers
          const isReadonly = /\breadonly\b/.test(line);
          const fm = line.match(/^(?:(?:private|protected|public|readonly)\s+)*(\w+)\s*[!?]?\s*:\s*([\w\[\]]+)/);
          if (fm) {
            const type = mapType(fm[2]);
            const size = (type === "f64" || type === "i64") ? 8 : 4;
            if (fieldOffset % size !== 0) fieldOffset = Math.ceil(fieldOffset / size) * size;
            fields.push({ name: fm[1], type, offset: fieldOffset, size, ...(isReadonly ? { readonly: true } : {}) });
            fieldOffset += size;
          }
        }

        fieldDepth += opens - closes;
      }

      // Register struct and class definitions
      const def: StructDef = { name: className, fields, totalSize: fieldOffset };
      this.structDefs.set(className, def);
      const classDef: ClassDef = { name: className, struct: def, methods: [] };
      this.classDefs.set(className, classDef);

      // Parse methods: scan src within class body, detect `{` at class-level depth
      let methodDepth = 1; // inside the class body (class's { was depth 0→1)
      let scanPos = classBodyStart;
      let lastMethodEnd = classBodyStart;

      while (scanPos < classBodyEnd) {
        const ch = src[scanPos];

        if (ch === "{") {
          if (methodDepth === 1) {
            // This `{` opens a method body. Backtrack to find the opening paren.
            // Going backwards: `)` is a "pending open" (increment depth),
            // `(` closes a "pending open" (decrement); when depth reaches 0
            // it is the method's own opening paren.
            let parenDepth = 0;
            let openParen = -1;
            for (let k = scanPos - 1; k >= lastMethodEnd; k--) {
              if (src[k] === ")") {
                parenDepth++;
              } else if (src[k] === "(") {
                parenDepth--;
                if (parenDepth === 0) { openParen = k; break; }
              }
            }

            if (openParen !== -1) {
              const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);

              // Extract method name from text before `(`
              const beforeParen = src.slice(lastMethodEnd, openParen).trimEnd();
              const nameMatch = beforeParen.match(/(\w+)\s*$/);

              if (nameMatch) {
                const methodName = nameMatch[1];
                const SKIP = ["if", "while", "for", "switch", "catch", "new", "return", "typeof", "instanceof"];
                if (!SKIP.includes(methodName)) {
                  const isStatic = /\bstatic\s+\w+\s*$/.test(beforeParen);

                  // Parse return type (between `)` and `{`)
                  const betweenParenAndBrace = src.slice(afterClose, scanPos);
                  const retTypeMatch = betweenParenAndBrace.match(/:\s*([\w\[\]]+)/);
                  const rawResult = retTypeMatch ? retTypeMatch[1].trim() : "void";
                  const result: WatType | null = rawResult === "void" ? null : mapType(rawResult as string);

                  // Extract method body
                  const methodBodyStart = scanPos + 1;
                  let bodyDepth = 1, bodyEnd = methodBodyStart;
                  while (bodyEnd < src.length && bodyDepth > 0) {
                    if (src[bodyEnd] === "{") bodyDepth++;
                    else if (src[bodyEnd] === "}") bodyDepth--;
                    bodyEnd++;
                  }
                  const rawBody = src.slice(methodBodyStart, bodyEnd - 1);
                  const bodyLines = rawBody.split("\n").map(l => l.trim()).filter(l => l.length > 0);

                  const isConstructor = methodName === "constructor";
                  const funcName = isConstructor
                    ? `${className}_constructor`
                    : `${className}_${methodName}`;

                  const parsedParams = this.parseParams(rawParams);
                  const allParams: FuncParam[] = isStatic
                    ? parsedParams
                    : [{ name: "__self", type: "i32" as WatType }, ...parsedParams];

                  if (!this.functions.find(f => f.name === funcName)) {
                    this.functions.push({
                      name: funcName,
                      params: allParams,
                      result: isConstructor ? null : result,
                      exported: false,
                      bodyLines,
                      className: isStatic ? undefined : className,
                    });
                  }

                  classDef.methods.push({ name: methodName, isStatic, isConstructor });
                }
              }
            }
          }
          methodDepth++;
        } else if (ch === "}") {
          methodDepth--;
          if (methodDepth === 1) lastMethodEnd = scanPos + 1;
        }

        scanPos++;
      }
    }
  }

  /** Allocates `totalSize` zero-filled bytes in the data section. Returns base pointer. */
  private allocStructData(def: StructDef, initFields: Record<string, string>): number {
    const ptr = this.dataOffset;
    // Build a byte array of totalSize, filling each field
    const bytes = new Uint8Array(def.totalSize);
    const view  = new DataView(bytes.buffer);
    for (const field of def.fields) {
      const raw = initFields[field.name];
      if (raw === undefined) continue;
      const val = parseFloat(raw) || 0;
      if (field.type === "f64") view.setFloat64(field.offset, val, true);
      else if (field.type === "f32") view.setFloat32(field.offset, val, true);
      else if (field.type === "i64") view.setBigInt64(field.offset, BigInt(Math.trunc(val)), true);
      else view.setInt32(field.offset, Math.trunc(val), true);
    }
    const encoded = Array.from(bytes).map(b => `\\${b.toString(16).padStart(2, "0")}`).join("");
    if (encoded) this.rawDataSegments.push({ ptr, bytes: encoded });
    this.dataOffset += def.totalSize;
    return ptr;
  }

  // -------------------------------------------------------------------------
  // String data allocation
  // -------------------------------------------------------------------------
  private allocString(msg: string): [number, number] {
    const existing = this.dataMap.get(msg);
    if (existing) return existing;
    const bytes = new TextEncoder().encode(msg);
    const entry: [number, number] = [this.dataOffset, bytes.length];
    this.dataMap.set(msg, entry);
    this.dataOffset += bytes.length;
    this.hasConsoleLog = true;
    return entry;
  }

  /** Allocates a string in the data section without setting hasConsoleLog (for throw messages). */
  private allocStringNoLog(msg: string): [number, number] {
    const existing = this.dataMap.get(msg);
    if (existing) return existing;
    const bytes = new TextEncoder().encode(msg);
    const entry: [number, number] = [this.dataOffset, bytes.length];
    this.dataMap.set(msg, entry);
    this.dataOffset += bytes.length;
    return entry;
  }

  /** Allocates a static numeric array in the data section. Returns base pointer. */
  private allocArrayData(elements: string[], elemType: WatType): number {
    const ptr = this.dataOffset;
    const elemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
    let encoded = "";
    for (const elem of elements) {
      const e = elem.trim();
      if (elemType === "f64" || elemType === "f32") {
        encoded += encodeF64LE(parseFloat(e) || 0);
      } else if (elemType === "i64") {
        // Simplified: encode as i32 pair (handles values within ±2^31)
        const val = parseInt(e.replace(/n$/, ""), 10) || 0;
        encoded += encodeI32LE(val);
        encoded += encodeI32LE(val < 0 ? -1 : 0);
      } else {
        encoded += encodeI32LE(parseInt(e, 10) || 0);
      }
    }
    if (encoded) this.rawDataSegments.push({ ptr, bytes: encoded });
    this.dataOffset += elements.length * elemSize;
    return ptr;
  }

  // -------------------------------------------------------------------------
  // Dynamic array helpers (Phase 10b)
  // -------------------------------------------------------------------------

  /** Scans function body lines for array method calls to determine which arrays need heap layout. */
  private findDynamicArrays(lines: string[]): Set<string> {
    const dynamic = new Set<string>();
    for (const line of lines) {
      // Method calls that require heap layout
      const m = line.match(/\b(\w+)\.(push|pop|shift|unshift|indexOf|includes|slice|forEach|map|filter|find|reduce)\s*\(/);
      if (m) dynamic.add(m[1]);
      // Spread usages: ...arrName in calls or array literals — source must have heap layout
      for (const sm of line.matchAll(/\.\.\.\s*(\w+)/g)) {
        dynamic.add(sm[1]);
      }
    }
    return dynamic;
  }

  /** Emits WAT statements that malloc + initialise a dynamic array (length/capacity header + elements). */
  private emitDynArrayInit(varName: string, info: {
    elemType: WatType; length: number; capacity?: number; initElements?: string[];
  }): string {
    const capacity = info.capacity ?? Math.max(info.length * 2, 8);
    const elemSize = (info.elemType === "f64" || info.elemType === "i64") ? 8 : 4;
    const byteSize = capacity * elemSize + 8; // 8-byte header: [length i32][capacity i32]
    const storeOp  = info.elemType === "f64" ? "f64.store"
                   : info.elemType === "i64" ? "i64.store" : "i32.store";

    const stmts: string[] = [];
    stmts.push(`(local.set $${varName} (call $__malloc (i32.const ${byteSize})))`);
    stmts.push(`(i32.store (local.get $${varName}) (i32.const ${info.length}))`);
    stmts.push(`(i32.store offset=4 (local.get $${varName}) (i32.const ${capacity}))`);

    for (let i = 0; i < (info.initElements?.length ?? 0); i++) {
      const raw = info.initElements![i].trim();
      const byteOffset = 8 + i * elemSize;
      let valExpr: string;
      if (info.elemType === "f64") {
        valExpr = `(f64.const ${parseFloat(raw) || 0})`;
      } else if (info.elemType === "i64") {
        valExpr = `(i64.const ${parseInt(raw.replace(/n$/, ""), 10) || 0})`;
      } else {
        valExpr = `(i32.const ${parseInt(raw, 10) || 0})`;
      }
      stmts.push(`(${storeOp} offset=${byteOffset} (local.get $${varName}) ${valExpr})`);
    }
    return stmts.join("\n      ");
  }

  // -------------------------------------------------------------------------
  // Phase 13 — Rest parameters & spread helpers
  // -------------------------------------------------------------------------

  /** Returns true if any line in `lines` calls a rest-param function with inline literal args. */
  private hasRestLiteralCalls(lines: string[]): boolean {
    for (const line of lines) {
      // Look for callName(arg1, arg2, ...) where none of the args start with "..."
      // and the callee is a known rest-param function
      const m = line.match(/^\s*(?:(?:var|let|const)\s+\w+\s*(?::\s*[\w\[\]]+)?\s*=\s*)?(\w+)\s*\(([^)]*)\)/);
      if (!m) continue;
      const fnName = m[1];
      const fnDef = this.functions.find((f: FuncDef) => f.name === fnName);
      if (!fnDef) continue;
      const lastParam = fnDef.params[fnDef.params.length - 1];
      if (!lastParam?.isRest) continue;
      // Has rest param — check if call site passes literal args (not a spread)
      const argsStr = m[2].trim();
      if (argsStr && !argsStr.startsWith("...")) return true;
    }
    return false;
  }

  /**
   * Emits WAT for calling a rest-param function with literal arguments.
   * Builds a temporary heap array from the non-rest args, stores it in $__rest_ptr,
   * then calls the function.
   * Returns multi-line WAT string (used in statement context).
   */
  private emitRestParamCall(
    fnName: string,
    allArgs: string[],
    locals: Map<string, WatType>,
    expectReturn: WatType | null
  ): string {
    const fnDef = this.functions.find((f: FuncDef) => f.name === fnName)!;
    const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
    const normalArgs = allArgs.slice(0, restIdx);
    const restArgs  = allArgs.slice(restIdx);
    const restParam = fnDef.params[restIdx];
    const elemType  = restParam.arrayElemType ?? "i32";
    const elemSize  = (elemType === "f64" || elemType === "i64") ? 8 : 4;
    const storeOp   = elemType === "f64" ? "f64.store" : elemType === "i64" ? "i64.store" : "i32.store";
    const len       = restArgs.length;
    const capacity  = Math.max(len * 2, 8);
    const byteSize  = capacity * elemSize + 8;

    const lines: string[] = [];
    lines.push(`(local.set $__rest_ptr (call $__malloc (i32.const ${byteSize})))`);
    lines.push(`(i32.store (local.get $__rest_ptr) (i32.const ${len}))`);
    lines.push(`(i32.store offset=4 (local.get $__rest_ptr) (i32.const ${capacity}))`);
    for (let i = 0; i < restArgs.length; i++) {
      const byteOff = 8 + i * elemSize;
      const val = this.emitExpr(restArgs[i].trim(), locals, elemType);
      lines.push(`(${storeOp} offset=${byteOff} (local.get $__rest_ptr) ${val})`);
    }
    const callArgs = [
      ...normalArgs.map((a, idx) => this.emitExpr(a.trim(), locals, fnDef.params[idx].type)),
      "(local.get $__rest_ptr)",
    ].join(" ");
    const callExpr = `(call $${fnName} ${callArgs})`;
    if (expectReturn) {
      lines.push(callExpr);
    } else {
      lines.push(`(drop ${callExpr})`);
    }
    return lines.join("\n      ");
  }

  /**
   * Emits WAT to build a spread-concat array from `[...a, ...b, ...]` syntax.
   * Returns a WAT expression yielding the new array pointer (i32).
   */
  private emitSpreadArrayInit(
    varName: string,
    spreads: string[],
    elemType: WatType
  ): string {
    const suffix = elemType === "f64" ? "f64" : "i32";
    this.dynArrHelpers.add(`concat_${suffix}`);
    if (spreads.length === 0) {
      // Empty spread: allocate empty dynamic array
      const capacity = 8;
      const elemSize = elemType === "f64" ? 8 : 4;
      const byteSize = capacity * elemSize + 8;
      return [
        `(local.set $${varName} (call $__malloc (i32.const ${byteSize})))`,
        `(i32.store (local.get $${varName}) (i32.const 0))`,
        `(i32.store offset=4 (local.get $${varName}) (i32.const ${capacity}))`,
      ].join("\n      ");
    }
    const stmts: string[] = [];
    // Start with first spread array
    stmts.push(`(local.set $${varName} (local.get $${spreads[0]}))`);
    // Concat subsequent spreads
    for (let i = 1; i < spreads.length; i++) {
      stmts.push(`(local.set $${varName} (call $__dynarr_concat_${suffix} (local.get $${varName}) (local.get $${spreads[i]})))`);
    }
    return stmts.join("\n      ");
  }

  // -------------------------------------------------------------------------
  // String variable helpers
  // -------------------------------------------------------------------------

  /**
   * Emits WAT to assign a string expression to the `$<varName>_ptr` and `$<varName>_len`
   * locals.  Supports:
   *   - String literals:  "hello" or 'hello'
   *   - String variables: another string-typed identifier
   * Complex expressions (concat creating a new heap string) are deferred to Phase 2b.
   */
  private emitStringAssign(
    varName: string,
    initExpr: string,
    locals: Map<string, WatType>
  ): string {
    this.stringVars.add(varName);
    const ind = "      ";

    // String literal
    const litMatch = initExpr.match(/^"([^"]*)"$/) ?? initExpr.match(/^'([^']*)'$/);
    if (litMatch) {
      const [offset, len] = this.allocString(litMatch[1]);
      return [
        `(local.set $${varName}_ptr (i32.const ${offset}))`,
        `${ind}(local.set $${varName}_len (i32.const ${len}))`,
      ].join("\n");
    }

    // Another string variable
    if (/^\w+$/.test(initExpr) && this.stringVars.has(initExpr)) {
      return [
        `(local.set $${varName}_ptr (local.get $${initExpr}_ptr))`,
        `${ind}(local.set $${varName}_len (local.get $${initExpr}_len))`,
      ].join("\n");
    }

    // str.slice(start, end) → call $__str_slice (multi-value → ptr, len)
    const sliceMatch = initExpr.match(/^(\w+)\.slice\s*\((.+?),\s*(.+?)\)$/);
    if (sliceMatch && locals.get(sliceMatch[1]) === "string") {
      this.needsStringOpHelpers = true;
      const startWat = this.emitExpr(sliceMatch[2].trim(), locals, "i32");
      const endWat   = this.emitExpr(sliceMatch[3].trim(), locals, "i32");
      return [
        `(call $__str_slice (local.get $${sliceMatch[1]}_ptr) (local.get $${sliceMatch[1]}_len) ${startWat} ${endWat})`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // n.toString() → malloc 32 bytes, call $__i32_to_str / $__f64_to_str
    const toStrMatch = initExpr.match(/^(\w+)\.toString\s*\(\s*\)$/);
    if (toStrMatch) {
      const srcType = locals.get(toStrMatch[1]);
      if (srcType === "i32" || srcType === "f64" || srcType === "i64") {
        this.needsNumericHelpers = true;
        const helperName = srcType === "f64" ? "$__f64_to_str" : "$__i32_to_str";
        return [
          `(local.set $${varName}_ptr (call $__malloc (i32.const 32)))`,
          `${ind}(local.set $${varName}_len (call ${helperName} (local.get $${toStrMatch[1]}) (local.get $${varName}_ptr)))`,
        ].join("\n");
      }
    }

    // String(n) → same pattern
    const stringOfMatch = initExpr.match(/^String\s*\((.+?)\)\s*$/);
    if (stringOfMatch) {
      this.needsNumericHelpers = true;
      const argExpr = stringOfMatch[1].trim();
      const argType: WatType = /^\w+$/.test(argExpr) ? (locals.get(argExpr) ?? "i32") : "i32";
      const helperName = argType === "f64" ? "$__f64_to_str" : "$__i32_to_str";
      const valWat = this.emitExpr(argExpr, locals, argType);
      return [
        `(local.set $${varName}_ptr (call $__malloc (i32.const 32)))`,
        `${ind}(local.set $${varName}_len (call ${helperName} ${valWat} (local.get $${varName}_ptr)))`,
      ].join("\n");
    }

    // String concatenation: flatten the binary + tree and reduce left-to-right
    // e.g. a + " " + b  →  result = concat(a, " "); result = concat(result, b)
    const concatParts = this.flattenStringConcat(initExpr, locals);
    if (concatParts && concatParts.length >= 2) {
      this.needsStringOpHelpers = true;
      const stmts: string[] = [];
      const p0 = this.emitStringPtrLen(concatParts[0], locals);
      const p1 = this.emitStringPtrLen(concatParts[1], locals);
      stmts.push(`(call $__str_concat ${p0} ${p1})`);
      stmts.push(`(local.set $${varName}_len)`);
      stmts.push(`(local.set $${varName}_ptr)`);
      for (let i = 2; i < concatParts.length; i++) {
        const pi = this.emitStringPtrLen(concatParts[i], locals);
        stmts.push(`(call $__str_concat (local.get $${varName}_ptr) (local.get $${varName}_len) ${pi})`);
        stmts.push(`(local.set $${varName}_len)`);
        stmts.push(`(local.set $${varName}_ptr)`);
      }
      return stmts.join(`\n${ind}`);
    }

    return `(;; string assignment from complex expression not yet supported: ${varName} = ${initExpr};)`;
  }

  /**
   * Returns the list of operand sub-expressions in a left-associative string concat chain,
   * or null if the expression is not a string + operation.
   */
  private flattenStringConcat(expr: string, locals: Map<string, WatType>): string[] | null {
    const plusIdx = this.findBinaryOp(expr, "+");
    if (plusIdx === -1) return null;
    const lhs = expr.slice(0, plusIdx).trim();
    const rhs = expr.slice(plusIdx + 1).trim();
    if (!this.isStringExpr(lhs, locals) && !this.isStringExpr(rhs, locals)) return null;
    const lhsParts = this.flattenStringConcat(lhs, locals) ?? [lhs];
    return [...lhsParts, rhs];
  }

  /** Returns true if expr is a string literal or a known string variable. */
  private isStringExpr(expr: string, locals: Map<string, WatType>): boolean {
    const e = expr.trim();
    if (/^["']/.test(e)) return true;
    if (/^\w+$/.test(e)) return locals.get(e) === "string";
    return false;
  }

  /**
   * Returns a pair of WAT expressions `"ptr_wat len_wat"` for a string-typed
   * expression, suitable as arguments to $__str_cmp.
   * Handles: string variable identifiers and string literals.
   */
  private emitStringPtrLen(expr: string, locals: Map<string, WatType>): string {
    expr = expr.trim();
    // String variable (or param) — use locals map for accuracy
    if (/^\w+$/.test(expr) && locals.get(expr) === "string") {
      return `(local.get $${expr}_ptr) (local.get $${expr}_len)`;
    }
    // varName.message — Error catch variable; .message is the string itself
    const dotMsgMatch = expr.match(/^(\w+)\.message$/);
    if (dotMsgMatch && locals.get(dotMsgMatch[1]) === "string") {
      return `(local.get $${dotMsgMatch[1]}_ptr) (local.get $${dotMsgMatch[1]}_len)`;
    }
    // String literal
    const litMatch = expr.match(/^"([^"]*)"$/) ?? expr.match(/^'([^']*)'$/);
    if (litMatch) {
      const [offset, len] = this.allocString(litMatch[1]);
      return `(i32.const ${offset}) (i32.const ${len})`;
    }
    return `(i32.const 0) (i32.const 0)`;
  }

  // -------------------------------------------------------------------------
  // Expression emitter
  // -------------------------------------------------------------------------
  private emitExpr(
    raw: string,
    locals: Map<string, WatType>,
    defaultType: WatType
  ): string {
    // bool is i32 at the WAT level; normalize so all emission uses i32
    if (defaultType === "bool") defaultType = "i32";
    let expr = raw.trim();

    // Phase 22: strip TypeScript non-null assertion postfix `expr!` → `expr`
    // Guard against != and !== which also end with !
    if (expr.endsWith("!") && !expr.endsWith("!=") && !expr.endsWith("!==")) {
      expr = expr.slice(0, -1).trim();
    }

    // Phase 22: strip `satisfies` operator — `expr satisfies T` → `expr`
    // `satisfies` is a compile-time type-checking hint with no WAT equivalent.
    {
      const satIdx = this.findDepth0Keyword(expr, " satisfies ");
      if (satIdx !== -1) expr = expr.slice(0, satIdx).trim();
    }

    // Phase 22: `as` type assertion — `expr as T` → appropriate WASM conversion
    // Scan right-to-left at depth 0 (lowest-precedence, like a unary postfix suffix).
    {
      const asIdx = this.findDepth0Keyword(expr, " as ");
      if (asIdx !== -1) {
        const inner = expr.slice(0, asIdx).trim();
        const targetTypeStr = expr.slice(asIdx + 4).trim().split(/[\s<]/)[0]; // first word (strip generics)
        const targetType = mapType(targetTypeStr);
        const srcType: WatType = /^\w+$/.test(inner) && locals.has(inner)
          ? locals.get(inner)! : defaultType;
        return this.emitTypeCast(inner, srcType, targetType, locals);
      }
    }

    // Parenthesised group
    if (expr.startsWith("(") && expr.endsWith(")")) {
      return this.emitExpr(expr.slice(1, -1), locals, defaultType);
    }

    // Bigint literal: 42n → (i64.const 42)
    if (/^-?\d+n$/.test(expr)) {
      return `(i64.const ${expr.slice(0, -1)})`;
    }

    // Numeric literal
    if (/^-?\d+(\.\d+)?$/.test(expr)) {
      return `(${defaultType}.const ${expr})`;
    }

    // Array .length property: dynamic → runtime load from header; static → compile-time constant
    const lenPropMatch = expr.match(/^(\w+)\.length$/);
    if (lenPropMatch) {
      const arrInfo = this.arrayVars.get(lenPropMatch[1]);
      if (arrInfo) {
        if (arrInfo.dynamic) return `(i32.load (local.get $${lenPropMatch[1]}))`;
        return `(i32.const ${arrInfo.length})`;
      }
      // String .length property: varName.length
      if (locals.get(lenPropMatch[1]) === "string") {
        return `(local.get $${lenPropMatch[1]}_len)`;
      }
    }

    // String method calls returning i32 (can appear in any expression context)
    // str.indexOf(sub) → i32 offset or -1
    const strIndexOfMatch = expr.match(/^(\w+)\.indexOf\s*\((.+)\)$/);
    if (strIndexOfMatch && locals.get(strIndexOfMatch[1]) === "string") {
      this.needsStringOpHelpers = true;
      const subPtrLen = this.emitStringPtrLen(strIndexOfMatch[2].trim(), locals);
      return `(call $__str_indexof (local.get $${strIndexOfMatch[1]}_ptr) (local.get $${strIndexOfMatch[1]}_len) ${subPtrLen})`;
    }
    // str.includes(sub) → i32 bool (1 = found, 0 = not found)
    const strIncludesMatch = expr.match(/^(\w+)\.includes\s*\((.+)\)$/);
    if (strIncludesMatch && locals.get(strIncludesMatch[1]) === "string") {
      this.needsStringOpHelpers = true;
      const subPtrLen = this.emitStringPtrLen(strIncludesMatch[2].trim(), locals);
      return `(i32.ne (call $__str_indexof (local.get $${strIncludesMatch[1]}_ptr) (local.get $${strIncludesMatch[1]}_len) ${subPtrLen}) (i32.const -1))`;
    }

    // Array element read: arr[idx]
    const bracketMatch = expr.match(/^(\w+)\[(.+)\]$/);
    if (bracketMatch) {
      const arrInfo = this.arrayVars.get(bracketMatch[1]);
      if (arrInfo) {
        const loadOp = arrInfo.elemType === "f64" ? "f64.load"
                     : arrInfo.elemType === "i64" ? "i64.load" : "i32.load";
        const shift   = (arrInfo.elemType === "f64" || arrInfo.elemType === "i64") ? 3 : 2;
        const idxWat  = this.emitExpr(bracketMatch[2], locals, "i32");
        // ptr=-1/ptr=-2: runtime local; ptr>=0: static data address. Dynamic arrays add 8-byte header offset.
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? `(local.get $${bracketMatch[1]})`
          : `(i32.const ${arrInfo.ptr})`;
        const dataBase = arrInfo.dynamic
          ? `(i32.add ${baseWat} (i32.const 8))`
          : baseWat;
        return `(${loadOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))))`;
      }
    }

    // Dynamic array methods used as expressions: arr.push(val), arr.pop(), arr.shift(), arr.unshift(val)
    const dynArrExpr = expr.match(/^(\w+)\.(push|pop|shift|unshift)\s*\((.*?)\)$/);
    if (dynArrExpr) {
      const arrName  = dynArrExpr[1];
      const method   = dynArrExpr[2] as "push" | "pop" | "shift" | "unshift";
      const argsStr  = dynArrExpr[3].trim();
      const arrInfo  = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const key        = `${method}_${arrInfo.elemType}`;
        const helperName = `$__dynarr_${key}`;
        this.dynArrHelpers.add(key);
        if (method === "push" || method === "unshift") {
          const valWat = this.emitExpr(argsStr, locals, arrInfo.elemType);
          // Push/unshift return new arr ptr (possibly grown); update local and return new length.
          return `(i32.load (local.tee $${arrName} (call ${helperName} (local.get $${arrName}) ${valWat})))`;
        }
        return `(call ${helperName} (local.get $${arrName}))`;
      }
    }

    // Dynamic array read/query methods: arr.indexOf(val), arr.includes(val), arr.slice(start,end)
    // Dynamic array callback methods (expression form): arr.map(fn), arr.filter(fn), arr.find(fn), arr.reduce(fn,init)
    const dynArrMethod = expr.match(/^(\w+)\.(indexOf|includes|slice|map|filter|find|reduce)\s*\(([\s\S]*)\)$/);
    if (dynArrMethod) {
      const arrName  = dynArrMethod[1];
      const method   = dynArrMethod[2] as "indexOf"|"includes"|"slice"|"map"|"filter"|"find"|"reduce";
      const argsStr  = dynArrMethod[3].trim();
      const arrInfo  = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const elemType = arrInfo.elemType as WatType;
        if (method === "indexOf") {
          const key = `indexof_${elemType}`;
          this.dynArrHelpers.add(key);
          const valWat = this.emitExpr(argsStr, locals, elemType);
          return `(call $__dynarr_${key} (local.get $${arrName}) ${valWat})`;
        }
        if (method === "includes") {
          const key = `indexof_${elemType}`;
          this.dynArrHelpers.add(key);
          const valWat = this.emitExpr(argsStr, locals, elemType);
          return `(i32.ne (call $__dynarr_${key} (local.get $${arrName}) ${valWat}) (i32.const -1))`;
        }
        if (method === "slice") {
          const key = `slice_${elemType}`;
          this.dynArrHelpers.add(key);
          const args = this.splitArgs(argsStr);
          const startWat = args[0]?.trim() ? this.emitExpr(args[0].trim(), locals, "i32") : "(i32.const 0)";
          const endWat   = args[1]?.trim() ? this.emitExpr(args[1].trim(), locals, "i32") : `(i32.load (local.get $${arrName}))`;
          return `(call $__dynarr_${key} (local.get $${arrName}) ${startWat} ${endWat})`;
        }
        // Callback methods: map, filter, find, reduce
        const args = this.splitArgs(argsStr);
        const fnName = args[0]?.trim() ?? "";
        const fnIdx  = this.getFuncTableIdx(fnName);
        const key    = `${method}_${elemType}`;
        this.dynArrHelpers.add(key);
        // Pre-register callback funtype so emitFuncTypes() includes it
        if (method === "map") {
          this.getOrCreateFuncType([elemType], elemType);
        } else if (method === "filter" || method === "find") {
          this.getOrCreateFuncType([elemType], "i32");
        } else if (method === "reduce") {
          this.getOrCreateFuncType([elemType, elemType], elemType);
        }
        if (method === "reduce") {
          const initWat = args[1]?.trim() ? this.emitExpr(args[1].trim(), locals, elemType) : zeroOf(elemType);
          return `(call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx}) ${initWat})`;
        }
        return `(call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx}))`;
      }
    }

    // this.field (read) or this.method(args) — inside a class instance method
    if (expr.startsWith("this.") && this.currentMethodClass) {
      const dotMethodMatch = expr.match(/^this\.(\w+)\s*\(([\s\S]*)\)$/);
      if (dotMethodMatch) {
        const methodName = dotMethodMatch[1];
        const argsStr = dotMethodMatch[2].trim();
        const funcName = `${this.currentMethodClass}_${methodName}`;
        const fn = this.functions.find(f => f.name === funcName);
        if (fn) {
          const args = argsStr ? this.splitArgs(argsStr) : [];
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i + 1]?.type ?? defaultType;
            return [this.emitExpr(a, locals, pt)];
          });
          return `(call $${funcName} (local.get $__self) ${emittedArgs.join(" ")})`.trim();
        }
      }
      const dotFieldMatch = expr.match(/^this\.(\w+)$/);
      if (dotFieldMatch) {
        const cd = this.classDefs.get(this.currentMethodClass);
        const field = cd?.struct.fields.find(f => f.name === dotFieldMatch[1]);
        if (field) {
          const loadOp = field.type === "f64" ? "f64.load"
                       : field.type === "i64" ? "i64.load" : "i32.load";
          return `(${loadOp} (i32.add (local.get $__self) (i32.const ${field.offset})))`;
        }
      }
    }

    // Enum member access: EnumName.MemberName → (i32.const value)
    const enumDotMatch = expr.match(/^(\w+)\.(\w+)$/);
    if (enumDotMatch) {
      const enumKey = `${enumDotMatch[1]}.${enumDotMatch[2]}`;
      if (this.enumValues.has(enumKey)) {
        return `(i32.const ${this.enumValues.get(enumKey)})`;
      }
    }

    // Struct field read: p.field  (where p is a known struct variable)
    // This check must come after enum dot-match (which has already returned if it matched).
    const structFieldMatch = expr.match(/^(\w+)\.(\w+)$/);
    if (structFieldMatch) {
      // Class instance field read (takes priority over struct field)
      const cv = this.classVars.get(structFieldMatch[1]);
      if (cv) {
        const cd = this.classDefs.get(cv.className);
        const field = cd?.struct.fields.find(f => f.name === structFieldMatch[2]);
        if (field) {
          const loadOp = field.type === "f64" ? "f64.load"
                       : field.type === "i64" ? "i64.load" : "i32.load";
          const baseWat = cv.ptr === -1 ? `(local.get $${structFieldMatch[1]})` : `(i32.const ${cv.ptr})`;
          return `(${loadOp} (i32.add ${baseWat} (i32.const ${field.offset})))`;
        }
      }
      const sv = this.structVars.get(structFieldMatch[1]);
      if (sv) {
        const field = sv.def.fields.find(f => f.name === structFieldMatch[2]);
        if (field) {
          const loadOp = field.type === "f64" ? "f64.load"
                       : field.type === "i64" ? "i64.load" : "i32.load";
          const baseWat = sv.ptr === -1
            ? `(local.get $${structFieldMatch[1]})`
            : `(i32.const ${sv.ptr})`;
          return `(${loadOp} (i32.add ${baseWat} (i32.const ${field.offset})))`;
        }
      }
    }

    // Math.* constants and functions
    if (expr.startsWith("Math.")) {
      // Constants
      const MATH_CONSTS: Record<string, string> = {
        PI:      "3.141592653589793",
        E:       "2.718281828459045",
        LN2:     "0.6931471805599453",
        LN10:    "2.302585092994046",
        LOG2E:   "1.4426950408889634",
        LOG10E:  "0.4342944819032518",
        SQRT2:   "1.4142135623730951",
        SQRT1_2: "0.7071067811865476",
      };
      const mathConstMatch = expr.match(/^Math\.(\w+)$/);
      if (mathConstMatch && MATH_CONSTS[mathConstMatch[1]] !== undefined) {
        return `(f64.const ${MATH_CONSTS[mathConstMatch[1]]})`;
      }

      // Function calls: Math.fn(args)
      const mathCallMatch = expr.match(/^Math\.(\w+)\(([\s\S]*)\)$/);
      if (mathCallMatch) {
        const mathFn  = mathCallMatch[1];
        const argsStr = mathCallMatch[2].trim();
        const args    = argsStr ? this.splitArgs(argsStr) : [];

        // Always-i32 ops
        if (mathFn === "clz32") {
          return `(i32.clz ${this.emitExpr(args[0] ?? "0", locals, "i32")})`;
        }
        if (mathFn === "imul") {
          return `(i32.mul ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${this.emitExpr(args[1] ?? "0", locals, "i32")})`;
        }

        // abs — i32 helper in i32 context, native f64.abs otherwise
        if (mathFn === "abs") {
          if (defaultType === "i32") {
            this.mathHelpers.add("i32_abs");
            return `(call $__i32_abs ${this.emitExpr(args[0] ?? "0", locals, "i32")})`;
          }
          return `(f64.abs ${this.emitExpr(args[0] ?? "0", locals, "f64")})`;
        }

        // min / max — i32 helper in i32 context, native f64.min/max otherwise
        if (mathFn === "min") {
          if (defaultType === "i32") {
            this.mathHelpers.add("i32_min");
            return `(call $__i32_min ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${this.emitExpr(args[1] ?? "0", locals, "i32")})`;
          }
          return `(f64.min ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${this.emitExpr(args[1] ?? "0", locals, "f64")})`;
        }
        if (mathFn === "max") {
          if (defaultType === "i32") {
            this.mathHelpers.add("i32_max");
            return `(call $__i32_max ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${this.emitExpr(args[1] ?? "0", locals, "i32")})`;
          }
          return `(f64.max ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${this.emitExpr(args[1] ?? "0", locals, "f64")})`;
        }

        // Native f64 single-arg instructions
        const F64_UNARY: Record<string, string> = {
          sqrt:  "f64.sqrt",
          floor: "f64.floor",
          ceil:  "f64.ceil",
          trunc: "f64.trunc",
          round: "f64.nearest",
        };
        if (F64_UNARY[mathFn]) {
          return `(${F64_UNARY[mathFn]} ${this.emitExpr(args[0] ?? "0", locals, "f64")})`;
        }

        // Math.pow — iterative WAT helper
        if (mathFn === "pow") {
          this.mathHelpers.add("math_pow");
          return `(call $__math_pow ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${this.emitExpr(args[1] ?? "0", locals, "f64")})`;
        }

        // Math.sign — copysign(1, x); returns ±1, 0 for zero
        if (mathFn === "sign") {
          const xWat = this.emitExpr(args[0] ?? "0", locals, "f64");
          return `(if (result f64) (f64.eq ${xWat} (f64.const 0)) (then (f64.const 0)) (else (f64.copysign (f64.const 1) ${xWat})))`;
        }

        // Math.hypot(a, b) — sqrt(a²+b²)
        if (mathFn === "hypot") {
          const a = this.emitExpr(args[0] ?? "0", locals, "f64");
          const b = this.emitExpr(args[1] ?? "0", locals, "f64");
          return `(f64.sqrt (f64.add (f64.mul ${a} ${a}) (f64.mul ${b} ${b})))`;
        }

        // Math.fround — demote to f32 then promote back
        if (mathFn === "fround") {
          return `(f64.promote_f32 (f32.demote_f64 ${this.emitExpr(args[0] ?? "0", locals, "f64")}))`;
        }

        // Functions that require a math library — not available in the direct-compile path
        const NEEDS_LIBRARY = new Set([
          "sin","cos","tan","asin","acos","atan","atan2",
          "log","log2","log10","exp","expm1","log1p",
          "random","cbrt","sinh","cosh","tanh","asinh","acosh","atanh",
        ]);
        if (NEEDS_LIBRARY.has(mathFn)) {
          this.diagnostics.push(
            `Unsupported: Math.${mathFn}() requires a floating-point math library — ` +
            `use \`wasmtk javyc\` for full Math support, or a future bundler phase`
          );
          return zeroOf(defaultType);
        }
      }
    }

    // Special constants — must be checked before the identifier fallback.
    // null/undefined/true/false are typed to match defaultType so binary ops don't produce
    // a type mismatch (e.g. f64.eq with an i32 rhs).
    if (expr === "NaN")       return "(f64.const nan)";
    if (expr === "Infinity")  return "(f64.const inf)";
    {
      const numType = (defaultType === "f64" || defaultType === "f32") ? defaultType : "i32";
      if (expr === "true")      return `(${numType}.const 1)`;
      if (expr === "false")     return `(${numType}.const 0)`;
      if (expr === "null")      return `(${numType}.const 0)`;
      if (expr === "undefined") return `(${numType}.const 0)`;
    }

    // Identifier (local variable or parameter)
    if (/^\w+$/.test(expr)) {
      // Use per-function locals map for accurate type — stringVars is instance-level and
      // could contain names from other functions compiled earlier in the same pass.
      const localType = locals.get(expr);
      if (localType === "string") {
        // In boolean (i32) context: string truthiness = length > 0 (empty string is falsy)
        if (defaultType === "i32") return `(i32.gt_s (local.get $${expr}_len) (i32.const 0))`;
        // In other numeric contexts: yield the ptr (i32) for use in expressions
        return `(local.get $${expr}_ptr)`;
      }
      if (localType) return `(local.get $${expr})`;
      // Known function name used as a value → funcref table index
      if (this.functions.find(f => f.name === expr)) {
        return `(i32.const ${this.getFuncTableIdx(expr)})`;
      }
    }

    // new ClassName(args) — allocate static struct + call constructor
    const newMatch = expr.match(/^new\s+([A-Z]\w*)\s*\(([\s\S]*)\)$/);
    if (newMatch) {
      const ctorClassName = newMatch[1];
      const argsStr = newMatch[2].trim();
      const cd = this.classDefs.get(ctorClassName);
      if (cd) {
        const ptr = this.allocStructData(cd.struct, {});
        const constructorName = `${ctorClassName}_constructor`;
        const ctorFn = this.functions.find(f => f.name === constructorName);
        if (ctorFn) {
          const args = argsStr ? this.splitArgs(argsStr) : [];
          const emittedArgs = args.flatMap((a, i) => {
            const pt = ctorFn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const ctorCall = `(call $${constructorName} (i32.const ${ptr}) ${emittedArgs.join(" ")})`.trim();
          return `(block (result i32) ${ctorCall} (i32.const ${ptr}))`;
        }
        return `(i32.const ${ptr})`;
      }
    }

    // instance.method(args) or ClassName.staticMethod(args) dot-call in expression position
    const dotCallExprMatch = expr.match(/^(\w+)\.(\w+)\s*\(([\s\S]*)\)$/);
    if (dotCallExprMatch) {
      const receiver = dotCallExprMatch[1];
      const methodName = dotCallExprMatch[2];
      const argsStr = dotCallExprMatch[3].trim();
      const args = argsStr ? this.splitArgs(argsStr) : [];

      // Instance method call
      const cv = this.classVars.get(receiver);
      if (cv) {
        const funcName = `${cv.className}_${methodName}`;
        const fn = this.functions.find(f => f.name === funcName);
        if (fn) {
          const baseWat = cv.ptr === -1 ? `(local.get $${receiver})` : `(i32.const ${cv.ptr})`;
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i + 1]?.type ?? defaultType;
            return [this.emitExpr(a, locals, pt)];
          });
          return `(call $${funcName} ${baseWat} ${emittedArgs.join(" ")})`.trim();
        }
      }

      // Static method call
      const staticCd = this.classDefs.get(receiver);
      if (staticCd) {
        const method = staticCd.methods.find(mm => mm.name === methodName && mm.isStatic);
        if (method) {
          const funcName = `${receiver}_${methodName}`;
          const fn = this.functions.find(f => f.name === funcName);
          if (fn) {
            const emittedArgs = args.flatMap((a, i) => {
              const pt = fn.params[i]?.type ?? defaultType;
              return [this.emitExpr(a, locals, pt)];
            });
            return `(call $${funcName} ${emittedArgs.join(" ")})`.trim();
          }
        }
      }
    }

    // Spread call: foo(...arr) — passes arr pointer directly to rest-param function
    // Handles the case where the entire argument list is a single spread of an array variable.
    const spreadCallMatch = expr.match(/^(\w+)\s*\(\s*\.\.\.(\w+)\s*\)$/);
    if (spreadCallMatch) {
      const fnName  = spreadCallMatch[1];
      const arrName = spreadCallMatch[2];
      const fn      = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fn?.params[fn.params.length - 1];
      if (fn && lastParam?.isRest) {
        // Pass all normal args (none expected in pure spread call) then the array ptr
        const normalCount = fn.params.length - 1;
        const normalEmitted = fn.params.slice(0, normalCount).map((p: FuncParam) =>
          p.defaultValue !== undefined ? this.emitExpr(p.defaultValue, locals, p.type) : `(i32.const 0)`
        );
        return `(call $${fnName} ${[...normalEmitted, `(local.get $${arrName})`].join(" ")})`.trim();
      }
    }

    // Phase 5f: chained call — factoryFn(outerArgs)(innerArgs) closure factory invocation
    {
      const chainHead = expr.match(/^(\w+)\s*\(/)?.[1];
      if (chainHead) {
        const factoryFn = this.functions.find(f => f.name === chainHead && f.isClosureFactory);
        if (factoryFn?.returnedArrow) {
          const openParen1 = expr.indexOf("(");
          const [rawOuterArgs, afterOuter] = WasicTranspiler.extractParamBlock(expr, openParen1);
          const rest = expr.slice(afterOuter).trimStart();
          if (rest.startsWith("(")) {
            const [rawInnerArgs] = WasicTranspiler.extractParamBlock(rest, 0);
            const inner = factoryFn.returnedArrow;
            const innerCallParams = inner.params.filter(p => !(inner.closureCaptures ?? []).includes(p.name));
            const outerArgs = rawOuterArgs.trim() ? this.splitArgs(rawOuterArgs) : [];
            const outerEmitted = outerArgs.map((a, i) =>
              this.emitExpr(a, locals, factoryFn.params[i]?.type ?? "i32")
            );
            const innerArgs = rawInnerArgs.trim() ? this.splitArgs(rawInnerArgs) : [];
            const innerEmitted = innerArgs.map((a, i) =>
              this.emitExpr(a, locals, innerCallParams[i]?.type ?? "i32")
            );
            return `(call $${chainHead}__trampoline (call $${chainHead} ${outerEmitted.join(" ")}) ${innerEmitted.join(" ")})`.trim();
          }
        }
      }
    }

    // Function call: name(arg1, arg2, ...)
    const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
    if (callMatch) {
      const callee = callMatch[1];
      const rawArgs = callMatch[2]?.trim() ?? "";
      const args = rawArgs ? this.splitArgs(rawArgs) : [];

      // Built-in type casts
      if (callee === "BigInt") {
        // BigInt(x) → sign-extend i32 to i64
        const arg = args[0] ?? "0";
        return `(i64.extend_i32_s ${this.emitExpr(arg, locals, "i32")})`;
      }
      if (callee === "Number") {
        // Number(x) — if x is i64, truncate to f64; else just emit as f64
        const arg = args[0] ?? "0";
        const argType = /^\w+$/.test(arg) ? (locals.get(arg) ?? defaultType) : defaultType;
        if (argType === "i64") return `(f64.convert_i64_s ${this.emitExpr(arg, locals, "i64")})`;
        return this.emitExpr(arg, locals, "f64");
      }

      const fn = this.functions.find(f => f.name === callee);
      if (!fn) {
        if (this.funcTypeVars.has(callee)) {
          const sig = this.funcTypeVars.get(callee)!;
          const typeName = this.getOrCreateFuncType(sig.params, sig.result);
          const emittedArgs = args.map((a, idx) =>
            this.emitExpr(a, locals, sig.params[idx] ?? defaultType)
          );
          return `(call_indirect (type ${typeName}) ${emittedArgs.join(" ")} (local.get $${callee}))`.trim();
        }
        this.diagnostics.push(`Unknown function '${callee}' — not declared in this module`);
        return `(unreachable)`;
      }
      // String params expand to two stack values (ptr + len)
      const emittedArgsList = args.flatMap((a, i) => {
        const paramType = fn.params[i]?.type ?? defaultType;
        if (paramType === "string") {
          return [this.emitStringPtrLen(a, locals)]; // already "ptr len"
        }
        return [this.emitExpr(a, locals, paramType)];
      });
      // Fill in default values for omitted trailing params
      const baseParamCount = fn.params.length - (fn.closureCaptures?.length ?? 0);
      for (let i = args.length; i < baseParamCount; i++) {
        const param = fn.params[i];
        if (param.defaultValue !== undefined) {
          emittedArgsList.push(this.emitExpr(param.defaultValue, locals, param.type));
        }
      }
      // Append closure-captured variable values as hidden extra args
      if (fn.closureCaptures) {
        for (const cap of fn.closureCaptures) {
          const capType = locals.get(cap);
          if (capType) emittedArgsList.push(this.emitExpr(cap, locals, capType));
        }
      }
      return `(call $${callee} ${emittedArgsList.join(" ")})`.trim();
    }

    // Ternary: cond ? then : else
    const ternQ = this.findBinaryOp(expr, "?");
    if (ternQ !== -1) {
      const rest  = expr.slice(ternQ + 1);
      const ternC = this.findBinaryOp(rest, ":");
      if (ternC !== -1) {
        const cond     = expr.slice(0, ternQ).trim();
        const thenPart = rest.slice(0, ternC).trim();
        const elsePart = rest.slice(ternC + 1).trim();
        return `(if (result ${defaultType}) ${this.emitExpr(cond, locals, "i32")} (then ${this.emitExpr(thenPart, locals, defaultType)}) (else ${this.emitExpr(elsePart, locals, defaultType)}))`;
      }
    }

    // Unary ! — logical not → i32.eqz
    if (expr.startsWith("!") && !expr.startsWith("!=")) {
      return `(i32.eqz ${this.emitExpr(expr.slice(1).trim(), locals, "i32")})`;
    }

    // Unary ~ — bitwise not → i32.xor with -1
    if (expr.startsWith("~")) {
      return `(i32.xor ${this.emitExpr(expr.slice(1).trim(), locals, "i32")} (i32.const -1))`;
    }

    // Unary - on a non-literal (e.g. -x, -(a+b))
    if (expr.startsWith("-") && !/^-\d/.test(expr)) {
      const inner     = expr.slice(1).trim();
      const innerType = /^\w+$/.test(inner) && locals.has(inner) ? locals.get(inner)! : defaultType;
      if (innerType === "f64" || innerType === "f32") {
        return `(${innerType}.neg ${this.emitExpr(inner, locals, innerType)})`;
      }
      return `(i32.sub (i32.const 0) ${this.emitExpr(inner, locals, "i32")})`;
    }

    // Phase 22: exponentiation `a ** b` → Math.pow(a, b)
    // Right-associative: use LTR scan so `a ** b ** c` → pow(a, pow(b, c)).
    {
      const powIdx = this.findDepth0LTR(expr, "**");
      if (powIdx !== -1) {
        this.mathHelpers.add("math_pow");
        const lhs = expr.slice(0, powIdx).trim();
        const rhs = expr.slice(powIdx + 2).trim();
        return `(call $__math_pow ${this.emitExpr(lhs, locals, "f64")} ${this.emitExpr(rhs, locals, "f64")})`;
      }
    }

    // Binary operators — scanned in ascending-precedence order so the lowest-precedence
    // operator is matched first, producing correctly-grouped s-expressions.
    // [op, i32-suffix, f64-suffix, alwaysI32]
    const binaryOps: [string, string, string, boolean][] = [
      ["||",  "or",    "or",    true ],   // logical OR   → i32.or
      ["&&",  "and",   "and",   true ],   // logical AND  → i32.and
      ["|",   "or",    "or",    true ],   // bitwise OR
      ["^",   "xor",   "xor",   true ],   // bitwise XOR
      ["&",   "and",   "and",   true ],   // bitwise AND
      ["===", "eq",    "eq",    false],
      ["!==", "ne",    "ne",    false],
      ["==",  "eq",    "eq",    false],   // non-strict equality (same as === for numerics)
      ["!=",  "ne",    "ne",    false],   // non-strict inequality
      ["<=",  "le_s",  "le",    false],
      [">=",  "ge_s",  "ge",    false],
      ["<",   "lt_s",  "lt",    false],
      [">",   "gt_s",  "gt",    false],
      [">>>", "shr_u", "shr_u", true ],   // unsigned right shift
      [">>",  "shr_s", "shr_s", true ],   // signed right shift
      ["<<",  "shl",   "shl",   true ],   // left shift
      ["+",   "add",   "add",   false],
      ["-",   "sub",   "sub",   false],
      ["*",   "mul",   "mul",   false],
      ["/",   "div_s", "div",   false],
      ["%",   "rem_s", "rem",   false],
    ];

    const STRING_CMP_OPS = new Set(["===", "!==", "==", "!=", "<", ">", "<=", ">="]);
    for (const [op, i32suf, f64suf, alwaysI32] of binaryOps) {
      const idx = this.findBinaryOp(expr, op);
      if (idx !== -1) {
        const lhs     = expr.slice(0, idx).trim();
        const rhs     = expr.slice(idx + op.length).trim();
        // For logical/bitwise ops always use i32; for others infer from the LHS local type.
        const lhsType: WatType = alwaysI32
          ? "i32"
          : (/^\w+$/.test(lhs) && locals.has(lhs) ? locals.get(lhs)! : defaultType);

        // String comparison: route through $__str_cmp instead of string.eq / string.lt, etc.
        if (lhsType === "string" && STRING_CMP_OPS.has(op)) {
          this.needsStringHelpers = true;
          const aWat = this.emitStringPtrLen(lhs, locals);
          const bWat = this.emitStringPtrLen(rhs, locals);
          const cmpCall = `(call $__str_cmp ${aWat} ${bWat})`;
          const STR_CMP: Record<string, string> = {
            "===": `(i32.eqz ${cmpCall})`,
            "==":  `(i32.eqz ${cmpCall})`,
            "!==": `(i32.ne ${cmpCall} (i32.const 0))`,
            "!=":  `(i32.ne ${cmpCall} (i32.const 0))`,
            "<":   `(i32.lt_s ${cmpCall} (i32.const 0))`,
            ">":   `(i32.gt_s ${cmpCall} (i32.const 0))`,
            "<=":  `(i32.le_s ${cmpCall} (i32.const 0))`,
            ">=":  `(i32.ge_s ${cmpCall} (i32.const 0))`,
          };
          return STR_CMP[op] ?? `(i32.eqz ${cmpCall})`;
        }

        const baseType = watBaseType(lhsType);
        const isFloat  = baseType === "f64" || baseType === "f32";
        const suffix   = isFloat ? f64suf : i32suf;
        const watOp    = `${baseType}.${suffix}`;
        const innerWat = `(${watOp} ${this.emitExpr(lhs, locals, lhsType)} ${this.emitExpr(rhs, locals, lhsType)})`;
        // Mixed-type promotion: if context needs f64/i64 but arithmetic ran in i32, convert.
        if (!alwaysI32 && baseType === "i32") {
          const ctxBase = watBaseType(defaultType as WatType);
          if (ctxBase === "f64") return `(f64.convert_i32_s ${innerWat})`;
          if (ctxBase === "i64") return `(i64.extend_i32_s ${innerWat})`;
        }
        return innerWat;
      }
    }

    // Inline arrow literal still present — liftInlineArrows() couldn't lift it
    if (expr.includes("=>")) {
      this.diagnostics.push(`Unsupported: inline arrow could not be lifted as funcref: ${expr.slice(0, 40)}`);
      return zeroOf(defaultType);
    }

    // Fallback: emit a comment and a zero so compilation succeeds
    return `(;? ${expr};) ${zeroOf(defaultType)}`;
  }

  /** Finds an operator in an expression while respecting paren nesting.
   *  Scans right-to-left so repeated left-associative operators (a-b-c) group correctly. */
  private findBinaryOp(expr: string, op: string): number {
    let depth = 0;
    for (let i = expr.length - op.length; i >= 0; i--) {
      const ch = expr[i];
      if (ch === ")") depth++;
      else if (ch === "(") depth--;
      if (depth === 0 && expr.slice(i, i + op.length) === op) {
        const after  = expr[i + op.length] ?? "";
        const before = i > 0 ? expr[i - 1] : "";
        // Guard: don't match a short op that is a prefix/suffix of a longer one
        if (op === "<"  && (after === "=" || after === "<"))              continue;
        if (op === ">"  && (after === "=" || after === ">" || before === ">" || before === "=")) continue; // skip >=, >>, =>
        if (op === "="  && after === "=")                                 continue;
        if (op === "!"  && after === "=")                                 continue;
        if (op === "==" && (after === "=" || before === "="))             continue; // avoid === match
        if (op === "!=" && after === "=")                                 continue; // avoid !== match
        if (op === "&"  && (after === "&" || before === "&"))             continue;
        if (op === "|"  && (after === "|" || before === "|"))             continue;
        if (op === "*"  && (after === "*" || before === "*"))             continue; // skip **
        if (op === ">>" && (after === ">" || before === ">"))             continue;
        if (op === "?"  && after === ".")                                  continue; // optional chaining ?.
        return i;
      }
    }
    return -1;
  }

  /** Finds the first (leftmost) occurrence of `needle` at paren depth 0 (left-to-right scan).
   *  Used for right-associative operators like `**`. */
  private findDepth0LTR(expr: string, needle: string): number {
    let depth = 0;
    for (let i = 0; i <= expr.length - needle.length; i++) {
      const ch = expr[i];
      if (ch === "(" || ch === "[") { depth++; continue; }
      if (ch === ")" || ch === "]") { depth--; continue; }
      if (depth === 0 && expr.slice(i, i + needle.length) === needle) {
        return i;
      }
    }
    return -1;
  }

  /** Finds the last (rightmost) occurrence of `needle` (as a whole-word keyword with surrounding
   *  spaces) at paren depth 0. Used for `as` and `satisfies`. */
  private findDepth0Keyword(expr: string, needle: string): number {
    let depth = 0;
    for (let i = expr.length - needle.length; i >= 0; i--) {
      const ch = expr[i];
      if (ch === ")" || ch === "]") depth++;
      else if (ch === "(" || ch === "[") depth--;
      if (depth === 0 && expr.slice(i, i + needle.length) === needle) {
        return i;
      }
    }
    return -1;
  }

  /** Emits a WAT type-conversion expression for `expr as targetType`.
   *  Applies the appropriate WASM numeric conversion instruction.
   *  Phase 22: `as` type assertion support. */
  private emitTypeCast(
    inner: string,
    src: WatType,
    target: WatType,
    locals: Map<string, WatType>
  ): string {
    const srcBase = watBaseType(src);
    const tgtBase = watBaseType(target);
    // Same base type — just re-emit with target context (no instruction needed)
    if (srcBase === tgtBase) return this.emitExpr(inner, locals, target);
    // Integer literal: emit directly with target type to avoid redundant trunc
    if (/^-?\d+$/.test(inner.trim())) return `(${tgtBase}.const ${inner.trim()})`;
    const innerWat = this.emitExpr(inner, locals, src);
    if (tgtBase === "i32" && srcBase === "f64") return `(i32.trunc_f64_s ${innerWat})`;
    if (tgtBase === "i32" && srcBase === "f32") return `(i32.trunc_f32_s ${innerWat})`;
    if (tgtBase === "i32" && srcBase === "i64") return `(i32.wrap_i64 ${innerWat})`;
    if (tgtBase === "f64" && srcBase === "i32") return `(f64.convert_i32_s ${innerWat})`;
    if (tgtBase === "f64" && srcBase === "f32") return `(f64.promote_f32 ${innerWat})`;
    if (tgtBase === "f64" && srcBase === "i64") return `(f64.convert_i64_s ${innerWat})`;
    if (tgtBase === "f32" && srcBase === "f64") return `(f32.demote_f64 ${innerWat})`;
    if (tgtBase === "f32" && srcBase === "i32") return `(f32.convert_i32_s ${innerWat})`;
    if (tgtBase === "i64" && srcBase === "i32") return `(i64.extend_i32_s ${innerWat})`;
    if (tgtBase === "i64" && srcBase === "f64") return `(i64.trunc_f64_s ${innerWat})`;
    // Fallback — emit inner directly with target type
    return this.emitExpr(inner, locals, target);
  }

  /** Splits a comma-separated argument list, respecting nested parens and string quotes. */
  private splitArgs(raw: string): string[] {
    const args: string[] = [];
    let depth = 0, inDouble = false, inSingle = false, start = 0;
    for (let i = 0; i < raw.length; i++) {
      const ch = raw[i];
      if ((inDouble || inSingle) && ch === "\\") { i++; continue; }
      if (ch === '"' && !inSingle) { inDouble = !inDouble; continue; }
      if (ch === "'" && !inDouble) { inSingle = !inSingle; continue; }
      if (!inDouble && !inSingle) {
        if (ch === "(" || ch === "[") depth++;
        else if (ch === ")" || ch === "]") depth--;
        else if (ch === "," && depth === 0) {
          args.push(raw.slice(start, i).trim());
          start = i + 1;
        }
      }
    }
    args.push(raw.slice(start).trim());
    return args.filter(a => a.length > 0);
  }

  // -------------------------------------------------------------------------
  // Statement emitter
  // -------------------------------------------------------------------------
  private emitStatement(
    line: string,
    locals: Map<string, WatType>,
    funcResult: WatType | null
  ): string {
    // return expr;
    if (line.startsWith("return")) {
      const expr = line.replace(/^return\s*/, "").replace(/;$/, "").trim();
      if (!expr || funcResult === null) return "(return)";
      return `(return ${this.emitExpr(expr, locals, funcResult)})`;
    }

    // throw new Error("msg") | throw "literal" | throw someVar;
    const throwMatch = line.match(/^throw\s+(.+?);?$/);
    if (throwMatch) {
      this.needsExceptionTag = true;
      const throwExpr = throwMatch[1].trim();
      // throw new Error("msg") or throw new Error('msg')
      const newErrMatch = throwExpr.match(/^new\s+Error\s*\(\s*["']([^"']*)["']\s*\)$/);
      if (newErrMatch) {
        const [ptr, len] = this.allocStringNoLog(newErrMatch[1]);
        return `(throw $__exn_tag (i32.const ${ptr}) (i32.const ${len}))`;
      }
      // throw "literal" or throw 'literal'
      const strLitMatch = throwExpr.match(/^["']([^"']*)["']$/);
      if (strLitMatch) {
        const [ptr, len] = this.allocStringNoLog(strLitMatch[1]);
        return `(throw $__exn_tag (i32.const ${ptr}) (i32.const ${len}))`;
      }
      // throw someVar
      if (/^\w+$/.test(throwExpr)) {
        if (locals.get(throwExpr) === "string") {
          return `(throw $__exn_tag (local.get $${throwExpr}_ptr) (local.get $${throwExpr}_len))`;
        }
        // Numeric value — wrap as ptr with len=0
        return `(throw $__exn_tag (local.get $${throwExpr}) (i32.const 0))`;
      }
      // Fallback: emit as ptr expression with len=0
      return `(throw $__exn_tag ${this.emitExpr(throwExpr, locals, "i32")} (i32.const 0))`;
    }

    // Function-type variable: const f: (a: i32) => i32 = someFunc  OR  let f: (a: i32) => i32;
    // Local was declared as i32 in pre-scan; here we emit the initialiser if present.
    const funcTypeDecl = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*\([^)]*\)\s*=>\s*\w+(?:\s*=\s*(\w+))?/);
    if (funcTypeDecl) {
      const initName = funcTypeDecl[2];
      if (initName && this.functions.find(f => f.name === initName)) {
        const idx = this.getFuncTableIdx(initName);
        return `(local.set $${funcTypeDecl[1]} (i32.const ${idx}))`;
      }
      return "";
    }

    // Assignment to a function-type variable: f = anotherFunc
    const funcVarAssign = line.match(/^(\w+)\s*=\s*(\w+)\s*;?$/);
    if (funcVarAssign && this.funcTypeVars.has(funcVarAssign[1])) {
      const fn = this.functions.find(f => f.name === funcVarAssign[2]);
      if (fn) {
        return `(local.set $${funcVarAssign[1]} (i32.const ${this.getFuncTableIdx(funcVarAssign[2])}))`;
      }
    }

    // Spread array literal declaration: const merged: T[] = [...a, ...b]
    const spreadDeclMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/);
    if (spreadDeclMatch && spreadDeclMatch[3]?.includes("...")) {
      const varName = spreadDeclMatch[1];
      const typeHint = spreadDeclMatch[2] ?? "";
      const info = this.arrayVars.get(varName);
      const elemType: WatType = info?.elemType ?? (typeHint ? mapType(typeHint) as WatType : "i32");
      const parts = spreadDeclMatch[3].split(",").map(s => s.trim()).filter(Boolean);
      const spreads = parts.filter(p => p.startsWith("...")).map(p => p.slice(3).trim());
      return this.emitSpreadArrayInit(varName, spreads, elemType);
    }

    // Array literal declaration: const arr: T[] = [...] or const arr = [...]
    const arrLetMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*\w+\[\])?\s*=\s*\[/);
    if (arrLetMatch) {
      const info = this.arrayVars.get(arrLetMatch[1]);
      if (info) {
        if (info.dynamic) return this.emitDynArrayInit(arrLetMatch[1], info);
        return `(local.set $${arrLetMatch[1]} (i32.const ${info.ptr}))`;
      }
    }

    // Array variable from method-call RHS: const arr: T[] = someArr.slice/map/filter(...)
    const arrCallDecl = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*\w+\[\]\s*=\s*([^[].+?);?$/);
    if (arrCallDecl) {
      const varName = arrCallDecl[1];
      const info = this.arrayVars.get(varName);
      if (info?.dynamic) {
        const initWat = this.emitExpr(arrCallDecl[2].trim(), locals, "i32");
        return `(local.set $${varName} ${initWat})`;
      }
    }

    // Rest-param call with var init: const result = fnName(a, b, restArgs...)
    const restVarCallMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*[\w\[\]]+)?\s*=\s*(\w+)\s*\(([^)]*)\)\s*;?$/);
    if (restVarCallMatch) {
      const varName = restVarCallMatch[1];
      const fnName  = restVarCallMatch[2];
      const fnDef   = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fnDef?.params[fnDef.params.length - 1];
      if (fnDef && lastParam?.isRest) {
        const rawArgs = restVarCallMatch[3].split(",").map(s => s.trim()).filter(Boolean);
        const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
        const restRaw = rawArgs.slice(restIdx);
        // Spread call: pass existing array pointer directly
        if (restRaw.length === 1 && restRaw[0].startsWith("...")) {
          const arrName = restRaw[0].slice(3).trim();
          const normalEmitted = rawArgs.slice(0, restIdx).map((a, i) => this.emitExpr(a, locals, fnDef!.params[i].type));
          const callWat = `(call $${fnName} ${[...normalEmitted, `(local.get $${arrName})`].join(" ")})`.trim();
          return `${callWat}\n      (local.set $${varName})`;
        }
        const retType = fnDef.result ?? "i32";
        const callWat = this.emitRestParamCall(fnName, rawArgs, locals, retType);
        return `${callWat}\n      (local.set $${varName})`;
      }
    }

    // Rest-param call statement: fnName(a, b, restArgs...)
    const restCallStmtMatch = line.match(/^(\w+)\s*\(([^)]*)\)\s*;?$/);
    if (restCallStmtMatch) {
      const fnName  = restCallStmtMatch[1];
      const fnDef   = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fnDef?.params[fnDef.params.length - 1];
      if (fnDef && lastParam?.isRest) {
        const rawArgs = restCallStmtMatch[2].split(",").map(s => s.trim()).filter(Boolean);
        const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
        const restRaw = rawArgs.slice(restIdx);
        // Spread call: pass existing array pointer directly
        if (restRaw.length === 1 && restRaw[0].startsWith("...")) {
          const arrName = restRaw[0].slice(3).trim();
          const normalEmitted = rawArgs.slice(0, restIdx).map((a, i) => this.emitExpr(a, locals, fnDef!.params[i].type));
          return `(call $${fnName} ${[...normalEmitted, `(local.get $${arrName})`].join(" ")})`.trim();
        }
        return this.emitRestParamCall(fnName, rawArgs, locals, null);
      }
    }

    // Struct object literal init: const/let p: TypeName = { ... }
    // The pre-scan allocated static memory; emit local.set $p (i32.const ptr).
    // Must come BEFORE the generic letMatch handler below.
    const structLetMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{/);
    if (structLetMatch) {
      const sv = this.structVars.get(structLetMatch[1]);
      if (sv && sv.ptr >= 0) return `(local.set $${structLetMatch[1]} (i32.const ${sv.ptr}))`;
    }

    // Object destructuring: const { x, y } = structVar  or  const { x: localX } = structVar
    const destructMatch = line.match(/^(?:var|let|const)\s*\{([^}]+)\}\s*=\s*(\w+)\s*;?$/);
    if (destructMatch) {
      const sv = this.structVars.get(destructMatch[2]);
      if (!sv) {
        this.diagnostics.push(`Destructuring: '${destructMatch[2]}' is not a known struct variable`);
        return "";
      }
      const stmts: string[] = [];
      for (const binding of destructMatch[1].split(",").map(b => b.trim()).filter(Boolean)) {
        const colonIdx = binding.indexOf(":");
        const fieldName = colonIdx !== -1 ? binding.slice(0, colonIdx).trim() : binding;
        const localName = colonIdx !== -1 ? binding.slice(colonIdx + 1).trim() : binding;
        const field = sv.def.fields.find(f => f.name === fieldName);
        if (!field) {
          this.diagnostics.push(`Destructuring: field '${fieldName}' not found in struct '${sv.def.name}'`);
          continue;
        }
        const loadOp = field.type === "f64" ? "f64.load"
                     : field.type === "i64" ? "i64.load" : "i32.load";
        const baseWat = sv.ptr === -1
          ? `(local.get $${destructMatch[2]})`
          : `(i32.const ${sv.ptr})`;
        stmts.push(`(local.set $${localName} (${loadOp} (i32.add ${baseWat} (i32.const ${field.offset}))))`);
      }
      return stmts.join("\n      ");
    }

    // Class instance declaration: const obj: ClassName = new ClassName(args)
    const newDeclMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*[A-Z]\w*)?\s*=\s*new\s+([A-Z]\w*)\s*\(([\s\S]*?)\)\s*;?$/);
    if (newDeclMatch) {
      const varName = newDeclMatch[1];
      const cv = this.classVars.get(varName);
      if (cv) {
        const ptr = cv.ptr;
        const argsStr = newDeclMatch[3].trim();
        const constructorName = `${cv.className}_constructor`;
        const ctorFn = this.functions.find(f => f.name === constructorName);
        const setLocal = `(local.set $${varName} (i32.const ${ptr}))`;
        if (ctorFn) {
          const args = argsStr ? this.splitArgs(argsStr) : [];
          const emittedArgs = args.flatMap((a, i) => {
            const pt = ctorFn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const ctorCall = `(call $${constructorName} (i32.const ${ptr}) ${emittedArgs.join(" ")})`.trim();
          return `${setLocal}\n      ${ctorCall}`;
        }
        return setLocal;
      }
    }

    // var / let / const declaration
    const letMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?);?$/);
    if (letMatch) {
      const varName  = letMatch[1];
      const typeStr  = letMatch[2] ?? "";
      const initExpr = letMatch[3].trim();
      // Arrow function declaration — already lifted to module level by parseArrowFunctions.
      // If the variable name is a known function and registered as a funcref, emit the table index.
      if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) {
        if (this.funcTypeVars.has(varName)) {
          const fn = this.functions.find(f => f.name === varName);
          if (fn) return `(local.set $${varName} (i32.const ${this.getFuncTableIdx(varName)}))`;
        }
        return "";
      }
      // Function variable: const f = knownFuncName — emit table index
      if (/^\w+$/.test(initExpr) && this.funcTypeVars.has(varName)) {
        const fn = this.functions.find(f => f.name === initExpr);
        if (fn) return `(local.set $${varName} (i32.const ${this.getFuncTableIdx(initExpr)}))`;
      }
      const varType = typeStr ? mapType(typeStr) : inferInitType(initExpr, locals, this.enumValues, this.functions);
      if (varType === "string") {
        locals.set(varName, "string");
        return this.emitStringAssign(varName, initExpr, locals);
      }
      locals.set(varName, varType);
      return `(local.set $${varName} ${this.emitExpr(initExpr, locals, varType)})`;
    }

    // Compound assignment: +=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=  >>>=
    const compoundMatch = line.match(/^(\w+)\s*(>>>=|>>=|<<=|\+=|-=|\*=|\/=|%=|&=|\|=|\^=)\s*(.+?);?$/);
    if (compoundMatch && locals.has(compoundMatch[1])) {
      const varName = compoundMatch[1];
      const varType = locals.get(varName)!;
      const op      = compoundMatch[2];
      const rhs     = compoundMatch[3].trim();
      type CE = [fOp: string, iOp: string, alwaysI32: boolean];
      const watOps: Record<string, CE> = {
        "+=":   ["add",   "add",   false],
        "-=":   ["sub",   "sub",   false],
        "*=":   ["mul",   "mul",   false],
        "/=":   ["div",   "div_s", false],
        "%=":   ["rem",   "rem_s", false],
        "&=":   ["and",   "and",   true ],
        "|=":   ["or",    "or",    true ],
        "^=":   ["xor",   "xor",   true ],
        "<<=":  ["shl",   "shl",   true ],
        ">>=":  ["shr_s", "shr_s", true ],
        ">>>=": ["shr_u", "shr_u", true ],
      };
      const [fOp, iOp, alwaysI32] = watOps[op] ?? ["add", "add", false];
      const opType  = alwaysI32 ? "i32" : watBaseType(varType);
      const isFloat = opType === "f64" || opType === "f32";
      const suffix  = isFloat ? fOp : iOp;
      return `(local.set $${varName} (${opType}.${suffix} (local.get $${varName}) ${this.emitExpr(rhs, locals, opType)}))`;
    }

    // this.field = val — write to instance field inside a class method
    const thisWriteMatch = line.match(/^this\.(\w+)\s*=\s*(.+?);?$/);
    if (thisWriteMatch && this.currentMethodClass) {
      const cd = this.classDefs.get(this.currentMethodClass);
      const field = cd?.struct.fields.find(f => f.name === thisWriteMatch[1]);
      if (field) {
        // Phase 21: readonly guard — only allow writes inside the constructor
        if (field.readonly && this.currentMethodName !== `${this.currentMethodClass}_constructor`) {
          this.diagnostics.push(
            `Cannot assign to readonly field '${thisWriteMatch[1]}' of '${this.currentMethodClass}'`
          );
        }
        const storeOp = field.type === "f64" ? "f64.store"
                      : field.type === "i64" ? "i64.store" : "i32.store";
        const valWat = this.emitExpr(thisWriteMatch[2], locals, field.type);
        return `(${storeOp} (i32.add (local.get $__self) (i32.const ${field.offset})) ${valWat})`;
      }
    }

    // Struct field write: p.field = value
    const structWriteMatch = line.match(/^(\w+)\.(\w+)\s*=\s*(.+?);?$/);
    if (structWriteMatch) {
      // Class instance field write (takes priority)
      const wCv = this.classVars.get(structWriteMatch[1]);
      if (wCv) {
        const wCd = this.classDefs.get(wCv.className);
        const wField = wCd?.struct.fields.find(f => f.name === structWriteMatch[2]);
        if (wField) {
          // Phase 21: readonly guard for class instance fields accessed via variable
          if (wField.readonly) {
            this.diagnostics.push(
              `Cannot assign to readonly field '${structWriteMatch[2]}' of '${wCv.className}'`
            );
          }
          const storeOp = wField.type === "f64" ? "f64.store"
                        : wField.type === "i64" ? "i64.store" : "i32.store";
          const baseWat = wCv.ptr === -1 ? `(local.get $${structWriteMatch[1]})` : `(i32.const ${wCv.ptr})`;
          const valWat = this.emitExpr(structWriteMatch[3], locals, wField.type);
          return `(${storeOp} (i32.add ${baseWat} (i32.const ${wField.offset})) ${valWat})`;
        }
      }
      const sv = this.structVars.get(structWriteMatch[1]);
      if (sv) {
        const field = sv.def.fields.find(f => f.name === structWriteMatch[2]);
        if (field) {
          // Phase 21: readonly guard for struct fields
          if (field.readonly) {
            this.diagnostics.push(
              `Cannot assign to readonly field '${structWriteMatch[2]}' of struct '${sv.def.name}'`
            );
          }
          const storeOp = field.type === "f64" ? "f64.store"
                        : field.type === "i64" ? "i64.store" : "i32.store";
          const baseWat = sv.ptr === -1
            ? `(local.get $${structWriteMatch[1]})`
            : `(i32.const ${sv.ptr})`;
          const valWat = this.emitExpr(structWriteMatch[3], locals, field.type);
          return `(${storeOp} (i32.add ${baseWat} (i32.const ${field.offset})) ${valWat})`;
        }
      }
    }

    // Dynamic array methods: arr.push(val), arr.pop(), arr.shift(), arr.unshift(val) — statement form
    const dynArrStmt = line.match(/^(\w+)\.(push|pop|shift|unshift)\s*\((.*?)\)\s*;?$/);
    if (dynArrStmt) {
      const arrName  = dynArrStmt[1];
      const method   = dynArrStmt[2] as "push" | "pop" | "shift" | "unshift";
      const argsStr  = dynArrStmt[3].trim();
      const arrInfo  = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const key        = `${method}_${arrInfo.elemType}`;
        const helperName = `$__dynarr_${key}`;
        this.dynArrHelpers.add(key);
        if (method === "push" || method === "unshift") {
          const valWat = this.emitExpr(argsStr, locals, arrInfo.elemType);
          // Push/unshift return new arr ptr (possibly grown after realloc); update local via local.set.
          return `(local.set $${arrName} (call ${helperName} (local.get $${arrName}) ${valWat}))`;
        }
        return `(drop (call ${helperName} (local.get $${arrName})))`;
      }
    }

    // Dynamic array callback methods (statement form): arr.forEach(fn), arr.map(fn), etc.
    const dynArrCallbackStmt = line.match(/^(\w+)\.(forEach|map|filter|find|reduce)\s*\(([\s\S]*?)\)\s*;?$/);
    if (dynArrCallbackStmt) {
      const arrName  = dynArrCallbackStmt[1];
      const method   = dynArrCallbackStmt[2] as "forEach"|"map"|"filter"|"find"|"reduce";
      const argsStr  = dynArrCallbackStmt[3].trim();
      const arrInfo  = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const elemType = arrInfo.elemType as WatType;
        const args   = this.splitArgs(argsStr);
        const fnName = args[0]?.trim() ?? "";
        const fnIdx  = this.getFuncTableIdx(fnName);
        // Normalize method name to lowercase for key/helper name consistency
        const methodLc = method.toLowerCase() as string;
        const key    = `${methodLc}_${elemType}`;
        this.dynArrHelpers.add(key);
        if (methodLc === "foreach") {
          this.getOrCreateFuncType([elemType], null);
          return `(call $__dynarr_foreach_${elemType} (local.get $${arrName}) (i32.const ${fnIdx}))`;
        }
        if (methodLc === "map") {
          this.getOrCreateFuncType([elemType], elemType);
        } else if (methodLc === "filter" || methodLc === "find") {
          this.getOrCreateFuncType([elemType], "i32");
        } else if (methodLc === "reduce") {
          this.getOrCreateFuncType([elemType, elemType], elemType);
        }
        if (methodLc === "reduce") {
          const initWat = args[1]?.trim() ? this.emitExpr(args[1].trim(), locals, elemType) : zeroOf(elemType);
          return `(drop (call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx}) ${initWat}))`;
        }
        return `(drop (call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx})))`;
      }
    }

    // Array element write: arr[idx] = val
    const arrWriteMatch = line.match(/^(\w+)\s*\[(.+?)\]\s*=\s*(.+?);?$/);
    if (arrWriteMatch) {
      const arrInfo = this.arrayVars.get(arrWriteMatch[1]);
      if (arrInfo) {
        const storeOp = arrInfo.elemType === "f64" ? "f64.store"
                      : arrInfo.elemType === "i64" ? "i64.store" : "i32.store";
        const shift   = (arrInfo.elemType === "f64" || arrInfo.elemType === "i64") ? 3 : 2;
        const idxWat  = this.emitExpr(arrWriteMatch[2], locals, "i32");
        const valWat  = this.emitExpr(arrWriteMatch[3], locals, arrInfo.elemType);
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? `(local.get $${arrWriteMatch[1]})`
          : `(i32.const ${arrInfo.ptr})`;
        const dataBase = arrInfo.dynamic
          ? `(i32.add ${baseWat} (i32.const 8))`
          : baseWat;
        return `(${storeOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))) ${valWat})`;
      }
    }

    // Simple assignment (no let/const)
    const assignMatch = line.match(/^(\w+)\s*=\s*(.+?);?$/);
    if (assignMatch && locals.has(assignMatch[1])) {
      const varName = assignMatch[1];
      if (locals.get(varName) === "string") {
        return this.emitStringAssign(varName, assignMatch[2].trim(), locals);
      }
      const varType = locals.get(varName)!;
      return `(local.set $${varName} ${this.emitExpr(assignMatch[2].trim(), locals, varType)})`;
    }

    // console.log(...) — delegate to console_log.ts for full argument support
    const logMatch = line.match(/^console\.log\s*\((.+)\)\s*;?$/);
    if (logMatch) {
      this.hasConsoleLog = true;
      const allocator: DataAllocator = (text) => this.allocString(text);
      const lookup: FuncLookup = (name) => this.functions.find(f => f.name === name);
      const enumLookup = (key: string) => this.enumValues.get(key);
      const arrayLookupFn = (name: string) => this.arrayVars.get(name);
      // Pre-register any Math helpers used inside console.log args so they are
      // emitted even when the call only appears inside console.log (not in emitExpr).
      if (logMatch[1].includes("Math.")) {
        this.mathHelpers.add("math_pow");  // triggers all-helpers emission in emitMathHelpers
      }
      const structLookupFn: StructFieldLookup = (vn, fn) => {
        // Check class instance vars first
        const cv = this.classVars.get(vn);
        if (cv) {
          const cd = this.classDefs.get(cv.className);
          const f = cd?.struct.fields.find(fi => fi.name === fn);
          if (f) {
            const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
            const baseWat = cv.ptr === -1 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return { type: f.type, watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))` };
          }
        }
        const sv = this.structVars.get(vn);
        if (!sv) return undefined;
        const f = sv.def.fields.find(fi => fi.name === fn);
        if (!f) return undefined;
        const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
        const baseWat = sv.ptr === -1 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
        return { type: f.type, watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))` };
      };
      const dotCallLookupFn: DotCallLookup = (token) => {
        const result = this.emitExpr(token, locals, "i32");
        if (result === "(unreachable)" || result.startsWith("(;?")) return undefined;
        // Determine return type from the expression
        const m2 = token.match(/^(?:this|\w+)\.(\w+)\s*\(/);
        if (m2) {
          const receiver2 = token.match(/^(\w+)\./)?.[1] ?? "";
          const methodName2 = m2[1];
          const cv2 = receiver2 === "this" ? null : this.classVars.get(receiver2);
          const className2 = receiver2 === "this" ? this.currentMethodClass : cv2?.className;
          const cd2 = className2 ? this.classDefs.get(className2) : null;
          const method2 = cd2?.methods.find(mm => mm.name === methodName2);
          if (method2) {
            const fn2 = this.functions.find(f => f.name === `${className2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Static method
          const staticCd = this.classDefs.get(receiver2);
          if (staticCd) {
            const fn2 = this.functions.find(f => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
        }
        return undefined;
      };
      const segments = parseConsoleLogArgs(logMatch[1], locals as Map<string, string>, lookup, allocator, enumLookup, arrayLookupFn, structLookupFn, dotCallLookupFn);
      const { statements, needsHelpers, needsStrGather } = emitConsoleLog(segments, allocator, "    ", 1, this.iovBase, this.scratchBase);
      if (needsHelpers) this.needsNumericHelpers = true;
      if (needsStrGather) this.needsStrGatherHelper = true;
      return statements.join("\n      ");
    }

    // console.error(...) / console.warn(...) — same pipeline as console.log but fd=2 (stderr)
    const errMatch = line.match(/^console\.(error|warn)\s*\((.+)\)\s*;?$/);
    if (errMatch) {
      this.hasConsoleLog = true;
      const allocator: DataAllocator = (text) => this.allocString(text);
      const lookup: FuncLookup = (name) => this.functions.find(f => f.name === name);
      const enumLookup = (key: string) => this.enumValues.get(key);
      const arrayLookupFn = (name: string) => this.arrayVars.get(name);
      if (errMatch[2].includes("Math.")) this.mathHelpers.add("math_pow");
      const structLookupFn: StructFieldLookup = (vn, fn) => {
        // Check class instance vars first
        const cv = this.classVars.get(vn);
        if (cv) {
          const cd = this.classDefs.get(cv.className);
          const f = cd?.struct.fields.find(fi => fi.name === fn);
          if (f) {
            const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
            const baseWat = cv.ptr === -1 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return { type: f.type, watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))` };
          }
        }
        const sv = this.structVars.get(vn);
        if (!sv) return undefined;
        const f = sv.def.fields.find(fi => fi.name === fn);
        if (!f) return undefined;
        const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
        const baseWat = sv.ptr === -1 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
        return { type: f.type, watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))` };
      };
      const dotCallLookupFnErr: DotCallLookup = (token) => {
        const m2 = token.match(/^(?:this|\w+)\.(\w+)\s*\(/);
        if (m2) {
          const receiver2 = token.match(/^(\w+)\./)?.[1] ?? "";
          const methodName2 = m2[1];
          const cv2 = receiver2 === "this" ? null : this.classVars.get(receiver2);
          const className2 = receiver2 === "this" ? this.currentMethodClass : cv2?.className;
          const cd2 = className2 ? this.classDefs.get(className2) : null;
          const method2 = cd2?.methods.find(mm => mm.name === methodName2);
          if (method2) {
            const fn2 = this.functions.find(f => f.name === `${className2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          const staticCd = this.classDefs.get(receiver2);
          if (staticCd) {
            const fn2 = this.functions.find(f => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
        }
        return undefined;
      };
      const segments = parseConsoleLogArgs(errMatch[2], locals as Map<string, string>, lookup, allocator, enumLookup, arrayLookupFn, structLookupFn, dotCallLookupFnErr);
      const { statements, needsHelpers, needsStrGather } = emitConsoleLog(segments, allocator, "    ", 2, this.iovBase, this.scratchBase);
      if (needsHelpers) this.needsNumericHelpers = true;
      if (needsStrGather) this.needsStrGatherHelper = true;
      return statements.join("\n      ");
    }

    // break / break label
    const breakMatch = line.match(/^break(?:\s+(\w+))?\s*;?$/);
    if (breakMatch) {
      const label = breakMatch[1];
      if (label) return `(br $break_${label})`;
      const ctx = [...this.controlStack].reverse().find(c => c.breakLabel);
      return ctx ? `(br ${ctx.breakLabel})` : `(;; break outside loop;)`;
    }

    // continue / continue label
    const contMatch = line.match(/^continue(?:\s+(\w+))?\s*;?$/);
    if (contMatch) {
      const label = contMatch[1];
      if (label) return `(br $cont_${label})`;
      const ctx = [...this.controlStack].reverse().find(c => c.continueLabel);
      return ctx ? `(br ${ctx.continueLabel})` : `(;; continue outside loop;)`;
    }

    // Post/pre increment/decrement as standalone statements: i++, i--, ++i, --i
    if (/^(\w+)\+\+;?$/.test(line) || /^\+\+(\w+);?$/.test(line)) {
      const v = line.replace(/[+;]/g, "").trim();
      const vt = watBaseType(locals.get(v) ?? "i32");
      return `(local.set $${v} (${vt}.add (local.get $${v}) (${vt}.const 1)))`;
    }
    if (/^(\w+)--;?$/.test(line) || /^--(\w+);?$/.test(line)) {
      const v = line.replace(/[-;]/g, "").trim();
      const vt = watBaseType(locals.get(v) ?? "i32");
      return `(local.set $${v} (${vt}.sub (local.get $${v}) (${vt}.const 1)))`;
    }

    // Dot-method call as statement: instance.method(args) / this.method(args) / ClassName.staticMethod(args)
    const dotCallStmt = line.match(/^(this|\w+)\.(\w+)\s*\(([\s\S]*?)\)\s*;?$/);
    if (dotCallStmt) {
      const receiver = dotCallStmt[1];
      const methodName = dotCallStmt[2];
      const argsStr = dotCallStmt[3].trim();
      const args = argsStr ? this.splitArgs(argsStr) : [];

      if (receiver === "this" && this.currentMethodClass) {
        const funcName = `${this.currentMethodClass}_${methodName}`;
        const fn = this.functions.find(f => f.name === funcName);
        if (fn) {
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const call = `(call $${funcName} (local.get $__self) ${emittedArgs.join(" ")})`.trim();
          const hasResult1 = fn.result !== null && fn.result !== "never" && fn.result !== "string";
          return hasResult1 ? `(drop ${call})` : call;
        }
      }

      const cv = this.classVars.get(receiver);
      if (cv) {
        const funcName = `${cv.className}_${methodName}`;
        const fn = this.functions.find(f => f.name === funcName);
        if (fn) {
          const baseWat = cv.ptr === -1 ? `(local.get $${receiver})` : `(i32.const ${cv.ptr})`;
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const call = `(call $${funcName} ${baseWat} ${emittedArgs.join(" ")})`.trim();
          const hasResult2 = fn.result !== null && fn.result !== "never" && fn.result !== "string";
          return hasResult2 ? `(drop ${call})` : call;
        }
      }

      const staticCd = this.classDefs.get(receiver);
      if (staticCd) {
        const method = staticCd.methods.find(mm => mm.name === methodName && mm.isStatic);
        if (method) {
          const funcName = `${receiver}_${methodName}`;
          const fn = this.functions.find(f => f.name === funcName);
          if (fn) {
            const emittedArgs = args.flatMap((a, i) => {
              const pt = fn.params[i]?.type ?? ("f64" as WatType);
              return [this.emitExpr(a, locals, pt)];
            });
            const call = `(call $${funcName} ${emittedArgs.join(" ")})`.trim();
            return fn.result ? `(drop ${call})` : call;
          }
        }
      }
    }

    // Phase 5f: standalone chained call — factoryFn(outerArgs)(innerArgs);
    {
      const chainHead = line.match(/^(\w+)\s*\(/)?.[1];
      if (chainHead && chainHead !== "console") {
        const factoryFn = this.functions.find(f => f.name === chainHead && f.isClosureFactory);
        if (factoryFn?.returnedArrow) {
          const openParen1 = line.indexOf("(");
          const [rawOuterArgs, afterOuter] = WasicTranspiler.extractParamBlock(line, openParen1);
          const rest = line.slice(afterOuter).trimStart().replace(/;$/, "").trimStart();
          if (rest.startsWith("(")) {
            const [rawInnerArgs] = WasicTranspiler.extractParamBlock(rest, 0);
            const inner = factoryFn.returnedArrow;
            const innerCallParams = inner.params.filter(p => !(inner.closureCaptures ?? []).includes(p.name));
            const outerArgs = rawOuterArgs.trim() ? this.splitArgs(rawOuterArgs) : [];
            const outerEmitted = outerArgs.map((a, i) =>
              this.emitExpr(a, locals, factoryFn.params[i]?.type ?? "i32")
            );
            const innerArgs = rawInnerArgs.trim() ? this.splitArgs(rawInnerArgs) : [];
            const innerEmitted = innerArgs.map((a, i) =>
              this.emitExpr(a, locals, innerCallParams[i]?.type ?? "i32")
            );
            const callWat = `(call $${chainHead}__trampoline (call $${chainHead} ${outerEmitted.join(" ")}) ${innerEmitted.join(" ")})`.trim();
            const hasResult = inner.result !== null && inner.result !== "never" && inner.result !== "string";
            return hasResult ? `(drop ${callWat})` : callWat;
          }
        }
      }
    }

    // Standalone function call (statement form)
    const callMatch = line.match(/^(\w+)\s*\((.*)?\)\s*;?$/);
    if (callMatch) {
      const callee = callMatch[1];
      if (callee !== "console") {
        const rawArgs = callMatch[2]?.trim() ?? "";
        const args = rawArgs ? this.splitArgs(rawArgs) : [];
        const fn = this.functions.find(f => f.name === callee);
        if (!fn) {
          if (this.funcTypeVars.has(callee)) {
            const sig = this.funcTypeVars.get(callee)!;
            const typeName = this.getOrCreateFuncType(sig.params, sig.result);
            const emittedArgs = args.map((a, idx) =>
              this.emitExpr(a, locals, sig.params[idx] ?? "i32" as WatType)
            );
            const callWat = `(call_indirect (type ${typeName}) ${emittedArgs.join(" ")} (local.get $${callee}))`.trim();
            const hasIndResult = sig.result !== null && sig.result !== "never" && sig.result !== "string";
            return hasIndResult ? `(drop ${callWat})` : callWat;
          }
          this.diagnostics.push(`Unknown function '${callee}' — not declared in this module`);
          return "(unreachable)";
        }
        const emittedArgsList = args.flatMap((a, i) => {
          const pt = fn.params[i]?.type ?? "f64" as WatType;
          if (pt === "string") return [this.emitStringPtrLen(a, locals)];
          return [this.emitExpr(a, locals, pt)];
        });
        // Fill in default values for omitted trailing params
        const baseParamCount = fn.params.length - (fn.closureCaptures?.length ?? 0);
        for (let i = args.length; i < baseParamCount; i++) {
          const param = fn.params[i];
          if (param.defaultValue !== undefined) {
            emittedArgsList.push(this.emitExpr(param.defaultValue, locals, param.type));
          }
        }
        // Append closure-captured variable values as hidden extra args
        if (fn.closureCaptures) {
          for (const cap of fn.closureCaptures) {
            const capType = locals.get(cap);
            if (capType) emittedArgsList.push(this.emitExpr(cap, locals, capType));
          }
        }
        const call = `(call $${callee} ${emittedArgsList.join(" ")})`.trim();
        // never and string produce no WAT result value — omit the drop wrapper
        const hasWatResult = fn.result !== null && fn.result !== "never" && fn.result !== "string";
        return hasWatResult ? `(drop ${call})` : call;
      }
    }

    return `(;; ${line};)`;
  }

  /** Emits a WAT statement for a for-loop update expression (i++, i--, i += n, etc.). */
  private emitUpdate(upd: string, locals: Map<string, WatType>): string {
    upd = upd.trim().replace(/;$/, "");
    // i++ / i--
    if (/^(\w+)\+\+$/.test(upd)) return this.emitStatement(`${upd.slice(0, -2)} += 1;`, locals, null);
    if (/^(\w+)--$/.test(upd))   return this.emitStatement(`${upd.slice(0, -2)} -= 1;`, locals, null);
    // ++i / --i
    if (/^\+\+(\w+)$/.test(upd)) return this.emitStatement(`${upd.slice(2)} += 1;`, locals, null);
    if (/^--(\w+)$/.test(upd))   return this.emitStatement(`${upd.slice(2)} -= 1;`, locals, null);
    // compound assignment or other expression-statement
    return this.emitStatement(upd + ";", locals, null);
  }

  // -------------------------------------------------------------------------
  // Block emitter (handles if/else/while by scanning bodyLines)
  // -------------------------------------------------------------------------
  private emitBlock(
    lines: string[],
    locals: Map<string, WatType>,
    funcResult: WatType | null,
    indent: string = "    "
  ): string {
    const out: string[] = [];
    let i = 0;

    while (i < lines.length) {
      const line = lines[i];

      // Labeled statement: "label: { ... }" or "label: for/while/do ..."
      // Must not match "case X:" or "default:" which are handled by switch.
      const labeledMatch = line.match(/^(\w+)\s*:\s*(.*)$/) ;
      if (labeledMatch && labeledMatch[1] !== "case" && labeledMatch[1] !== "default") {
        const userLabel = labeledMatch[1];
        const rest      = labeledMatch[2].trim();
        if (rest === "{" || rest === "") {
          // Standalone labeled block: maps to (block $break_label ...)
          const [blkBody, consumed] = this.extractBlock(lines, i + 1);
          i += consumed + 1;
          this.controlStack.push({ breakLabel: `$break_${userLabel}` });
          const blkWat = this.emitBlock(blkBody, locals, funcResult, indent + "  ");
          this.controlStack.pop();
          out.push(`${indent}(block $break_${userLabel}`);
          out.push(blkWat);
          out.push(`${indent})`);
        } else {
          // Labeled loop: store the label and re-process the loop line in the next iteration
          this.pendingLabel = userLabel;
          // Rewrite the current line to just the loop statement and re-process it
          lines[i] = rest;
          // Do NOT increment i — loop back and process `rest` as a normal line
        }
        continue;
      }

      // Nested function declaration — already lifted to module level, skip its body
      if (/^(?:export\s+)?function\s+\w+\s*\(/.test(line)) {
        if (line.includes("{")) {
          const [, consumed] = this.extractBlock(lines, i + 1);
          i += consumed + 1;
        } else {
          i++;
        }
        continue;
      }

      // Nested arrow function declaration — already lifted to module level, skip its body.
      // If the variable is registered as a funcref (funcTypeVars), emit the table-index
      // assignment (local.set $name (i32.const idx)) and then skip the block body so
      // inner lines are not erroneously emitted in the outer function's context.
      // Single-line blocks (const f = () => { }) have both { and } on one line and do
      // not need extractBlock — only multi-line blocks require consuming subsequent lines.
      if (/^(?:export\s+)?(?:const|let)\s+\w+\s*=\s*\(/.test(line) && line.includes("=>")) {
        const fnName = line.match(/^(?:export\s+)?(?:const|let)\s+(\w+)/)?.[1];
        const isFuncref = fnName != null && this.funcTypeVars.has(fnName);
        if (isFuncref) {
          out.push(`${indent}${this.emitStatement(line, locals, funcResult)}`);
        }
        const braceIdx = line.indexOf("{");
        const isMultiLineBlock = braceIdx !== -1 && line.indexOf("}", braceIdx) === -1;
        if (isMultiLineBlock) {
          const [, consumed] = this.extractBlock(lines, i + 1);
          i += consumed + 1;
        } else {
          i++;
        }
        continue;
      }

      // if (cond) { ... } or if (cond) singleStatement;
      const ifMatch = line.match(/^if\s*\((.+)\)\s*\{?$/) ?? line.match(/^if\s*\((.+)\)\s+(\S.*)$/);
      if (ifMatch) {
        const cond = ifMatch[1].trim();
        const inlineBody = ifMatch[2] && ifMatch[2] !== "{" ? ifMatch[2].trim() : null;
        let ifBody: string[];
        let terminator = "";
        if (inlineBody) {
          // Single-line if: body is the inline statement
          ifBody = [inlineBody];
          i++;
        } else {
          // Multi-line if: collect body lines until matching } or } else {
          const [b, consumed, term] = this.extractBlock(lines, i + 1);
          ifBody = b;
          terminator = term;
          i += consumed + 1;
        }
        // Check for else — either the if-block ended at "} else {" (terminator),
        // or a separate "} else {" line follows the closing "}"
        let elseBody: string[] = [];
        if (terminator === "} else {") {
          // i is already at first else body line (extractBlock called with i, not i+1)
          const [eb, ec] = this.extractBlock(lines, i);
          elseBody = eb;
          i += ec;  // no +1: extractBlock was called at i (no initiating line to skip)
        } else if (i < lines.length && lines[i].match(/^}\s*else\s*\{?$/)) {
          // i points to "} else {"; extractBlock called with i+1 (past initiating line)
          const [eb, ec] = this.extractBlock(lines, i + 1);
          elseBody = eb;
          i += ec + 1;
        }

        const condExpr = this.emitExpr(cond, locals, "i32");
        const ifWat = this.emitBlock(ifBody, locals, funcResult, indent + "  ");
        if (elseBody.length > 0) {
          const elseWat = this.emitBlock(elseBody, locals, funcResult, indent + "  ");
          out.push(`${indent}(if ${condExpr}`);
          out.push(`${indent}  (then\n${ifWat}\n${indent}  )`);
          out.push(`${indent}  (else\n${elseWat}\n${indent}  )`);
          out.push(`${indent})`);
        } else {
          out.push(`${indent}(if ${condExpr}`);
          out.push(`${indent}  (then\n${ifWat}\n${indent}  )`);
          out.push(`${indent})`);
        }
        continue;
      }

      // while (cond) {
      const whileMatch = line.match(/^while\s*\((.+)\)\s*\{?$/);
      if (whileMatch) {
        const cond = whileMatch[1].trim();
        const [whileBody, consumed] = this.extractBlock(lines, i + 1);
        i += consumed + 1;
        const lbl  = this.pendingLabel ?? String(this.loopCounter++); this.pendingLabel = null;
        const brk  = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`;  // continue target: exits cont-block → falls to br loop
        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const condExpr = this.emitExpr(cond, locals, "i32");
        const bodyWat  = this.emitBlock(whileBody, locals, funcResult, indent + "      ");
        this.controlStack.pop();
        out.push(`${indent}(block ${brk}`);
        out.push(`${indent}  (loop ${loop}`);
        out.push(`${indent}    (br_if ${brk} (i32.eqz ${condExpr}))`);
        out.push(`${indent}    (block ${cont}`);
        out.push(bodyWat);
        out.push(`${indent}    )`);
        out.push(`${indent}    (br ${loop})`);
        out.push(`${indent}  )`);
        out.push(`${indent})`);
        continue;
      }

      // for (init; cond; update) {
      // Regex captures everything inside the parens, split on ;
      const forMatch = line.match(/^for\s*\((.+)\)\s*\{?$/);
      if (forMatch) {
        // Split init ; cond ; update at the top-level semicolons
        const inner = forMatch[1];
        const parts = inner.split(";").map(s => s.trim());
        const initPart = parts[0] ?? "";
        const condPart = parts[1] ?? "";
        const updPart  = parts[2] ?? "";

        const [forBody, consumed] = this.extractBlock(lines, i + 1);
        i += consumed + 1;

        const lbl  = this.pendingLabel ?? String(this.loopCounter++); this.pendingLabel = null;
        const brk  = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`;  // continue target: exits cont-block → falls to update then br loop

        // Emit init (may declare a variable via let/const)
        const initWat  = initPart ? this.emitStatement(initPart.replace(/;$/, "") + ";", locals, funcResult) : "";
        const condExpr = condPart ? this.emitExpr(condPart, locals, "i32") : "(i32.const 1)";
        const updWat   = updPart  ? this.emitUpdate(updPart, locals) : "";

        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const bodyWat = this.emitBlock(forBody, locals, funcResult, indent + "      ");
        this.controlStack.pop();

        if (initWat) out.push(`${indent}${initWat}`);
        out.push(`${indent}(block ${brk}`);
        out.push(`${indent}  (loop ${loop}`);
        out.push(`${indent}    (br_if ${brk} (i32.eqz ${condExpr}))`);
        out.push(`${indent}    (block ${cont}`);   // continue exits here → falls to update
        out.push(bodyWat);
        out.push(`${indent}    )`);
        if (updWat) out.push(`${indent}    ${updWat}`);
        out.push(`${indent}    (br ${loop})`);
        out.push(`${indent}  )`);
        out.push(`${indent})`);
        continue;
      }

      // do { ... } while (cond);
      const doMatch = line.match(/^do\s*\{?$/);
      if (doMatch) {
        const [doBody, consumed, termLine] = this.extractBlock(lines, i + 1);
        i += consumed + 1;
        // Extract condition from terminator line "} while (cond);" or from next line "while (cond);"
        let condPart = "0";
        const termWhile = termLine.match(/^}\s*while\s*\((.+)\)\s*;?$/);
        if (termWhile) {
          condPart = termWhile[1].trim();
        } else if (i < lines.length) {
          const nextWhile = lines[i].match(/^while\s*\((.+)\)\s*;?$/);
          if (nextWhile) { condPart = nextWhile[1].trim(); i++; }
        }

        const lbl  = this.pendingLabel ?? String(this.loopCounter++); this.pendingLabel = null;
        const brk  = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`;  // continue exits cont-block → falls to condition check
        const condExpr = this.emitExpr(condPart, locals, "i32");

        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const bodyWat = this.emitBlock(doBody, locals, funcResult, indent + "      ");
        this.controlStack.pop();

        out.push(`${indent}(block ${brk}`);
        out.push(`${indent}  (loop ${loop}`);
        out.push(`${indent}    (block ${cont}`);   // continue exits here → falls to condition
        out.push(bodyWat);
        out.push(`${indent}    )`);
        out.push(`${indent}    (br_if ${loop} ${condExpr})`);
        out.push(`${indent}  )`);
        out.push(`${indent})`);
        continue;
      }

      // switch (expr) {
      const switchMatch = line.match(/^switch\s*\((.+)\)\s*\{?$/);
      if (switchMatch) {
        const switchExpr = switchMatch[1].trim();
        const [switchBody, switchConsumed] = this.extractBlock(lines, i + 1);
        i += switchConsumed + 1;

        const id = this.loopCounter++;
        const exitLabel = `$switch_exit_${id}`;

        // Parse cases from switchBody
        type CaseEntry = { values: string[]; body: string[]; isDefault: boolean };
        const cases: CaseEntry[] = [];
        let cur: CaseEntry | null = null;
        for (const sl of switchBody) {
          const caseM = sl.match(/^case\s+(.+?)\s*:\s*(.*)$/);
          const defM  = sl.match(/^default\s*:\s*(.*)$/);
          if (caseM) {
            if (cur) cases.push(cur);
            cur = { values: [caseM[1].trim()], body: caseM[2] ? [caseM[2].trim()] : [], isDefault: false };
          } else if (defM) {
            if (cur) cases.push(cur);
            cur = { values: [], body: defM[1] ? [defM[1].trim()] : [], isDefault: true };
          } else if (cur) {
            if (sl !== "}" && sl !== "};") cur.body.push(sl);
          }
        }
        if (cur) cases.push(cur);

        // Emit using nested blocks to support fall-through.
        // Structure: (block $exit (block $caseN-1 ... (block $case0 dispatch) body0 br?) body1 br?) bodyN-1 br?)
        // dispatch: br_if $case_k for each non-default case, br $case_default (or br $exit) for default.
        // After dispatch block closes, code falls sequentially through remaining case bodies.
        // A case with break emits (br $exit); without break it falls through to the next case body.
        this.controlStack.push({ breakLabel: exitLabel });
        const switchValWat = this.emitExpr(switchExpr, locals, "i32");
        const nonDefault = cases.filter(c => !c.isDefault);
        const defaultCase = cases.find(c => c.isDefault);
        // Ordered: non-default cases first, default last
        const orderedCases = [...nonDefault, ...(defaultCase ? [defaultCase] : [])];
        const N = orderedCases.length;
        // Label for each case (case k's label = innermost block k uses)
        const caseLabels = orderedCases.map((c, k) =>
          c.isDefault ? `$case_default_${id}` : `$case_${id}_${k}`
        );

        const switchLines: string[] = [];
        switchLines.push(`${indent}(block ${exitLabel}`);

        // Open blocks from outermost (N-1) to innermost (0)
        for (let k = N - 1; k >= 0; k--) {
          const pad = "  ".repeat(N - k);
          switchLines.push(`${indent}${pad}(block ${caseLabels[k]}`);
        }

        // Dispatch inside innermost block: br_if for each non-default, br for default
        const innerPad = "  ".repeat(N + 1);
        for (let k = 0; k < nonDefault.length; k++) {
          const c = nonDefault[k];
          const condWat = c.values.map(v =>
            `(i32.eq ${switchValWat} ${this.emitExpr(v, locals, "i32")})`
          ).join(" ");
          const condExpr = c.values.length === 1 ? condWat : `(i32.or ${condWat})`;
          switchLines.push(`${indent}${innerPad}(br_if ${caseLabels[k]} ${condExpr})`);
        }
        // Default: jump to default label, or exit if no default
        switchLines.push(`${indent}${innerPad}(br ${defaultCase ? caseLabels[N - 1] : exitLabel})`);

        // Close blocks and emit bodies from innermost (k=0) outward (k=N-1)
        for (let k = 0; k < N; k++) {
          const closePad = "  ".repeat(N - k);
          const bodyPad = indent + closePad + "  ";
          switchLines.push(`${indent}${closePad})`);   // close block k
          // Emit body (without break statements — handled via br $exit below)
          const c = orderedCases[k];
          const bodyLines = c.body.filter(l => l.trim() !== "break;" && l.trim() !== "break");
          if (bodyLines.length > 0) {
            switchLines.push(this.emitBlock(bodyLines, locals, funcResult, bodyPad));
          }
          // If the original body contained a break, emit br $exit (exits switch)
          const hasBreak = c.body.some(l => l.trim() === "break;" || l.trim() === "break");
          if (hasBreak) {
            switchLines.push(`${bodyPad}(br ${exitLabel})`);
          }
        }

        switchLines.push(`${indent})`);   // close exit block
        this.controlStack.pop();
        out.push(switchLines.join("\n"));
        continue;
      }

      // try { ... } [catch (e) { ... }] [finally { ... }]
      // Patterns: "try {" or "try{" on its own line.
      const tryMatch = line.match(/^try\s*\{?$/);
      if (tryMatch) {
        const catchRe = /^}\s*catch\s*\(\s*(\w+)(?:\s*:\s*\w+)?\s*\)\s*\{?$/;
        const finallyRe = /^}\s*finally\s*\{?$/;

        const [tryBody, tryConsumed, tryTerminator] = this.extractBlock(lines, i + 1);
        i += tryConsumed + 1;

        let catchVar = "";
        let catchBody: string[] = [];
        let finallyBody: string[] = [];
        let hasCatch = false;
        let hasFinally = false;

        if (catchRe.test(tryTerminator)) {
          hasCatch = true;
          catchVar = tryTerminator.match(catchRe)?.[1] ?? "";
          const [cb, cc, ct] = this.extractBlock(lines, i);
          catchBody = cb;
          i += cc;
          if (finallyRe.test(ct)) {
            hasFinally = true;
            const [fb, fc] = this.extractBlock(lines, i);
            finallyBody = fb;
            i += fc;
          }
        } else if (finallyRe.test(tryTerminator)) {
          hasFinally = true;
          const [fb, fc] = this.extractBlock(lines, i);
          finallyBody = fb;
          i += fc;
        }

        this.needsExceptionTag = true;
        const tryWat     = this.emitBlock(tryBody,     locals, funcResult, indent + "    ");
        const catchWat   = hasCatch   ? this.emitBlock(catchBody,   locals, funcResult, indent + "    ") : "";
        const finallyWat = hasFinally ? this.emitBlock(finallyBody, locals, funcResult, indent + "    ") : "";

        out.push(`${indent}(try`);
        out.push(`${indent}  (do`);
        if (tryWat)     out.push(tryWat);
        if (hasFinally && finallyWat) out.push(finallyWat);   // success path: run finally inline
        out.push(`${indent}  )`);

        if (hasCatch) {
          out.push(`${indent}  (catch $__exn_tag`);
          if (catchVar) {
            // Payload is (ptr i32, len i32); len is on top of stack.
            out.push(`${indent}    (local.set $${catchVar}_len)`);
            out.push(`${indent}    (local.set $${catchVar}_ptr)`);
          } else {
            out.push(`${indent}    (drop)`);
            out.push(`${indent}    (drop)`);
          }
          if (catchWat)   out.push(catchWat);
          if (hasFinally && finallyWat) out.push(finallyWat); // catch success path: run finally inline
          out.push(`${indent}  )`);
        }

        if (hasFinally) {
          // catch_all re-runs finally then rethrows any non-tag exception
          out.push(`${indent}  (catch_all`);
          if (finallyWat) out.push(finallyWat);
          out.push(`${indent}    (rethrow 0)`);
          out.push(`${indent}  )`);
        }

        out.push(`${indent})`);
        continue;
      }

      // Closing brace on its own — skip
      if (line === "}" || line === "};") { i++; continue; }

      out.push(`${indent}${this.emitStatement(line, locals, funcResult)}`);
      i++;
    }

    return out.join("\n");
  }

  /** Extracts lines belonging to a { } block starting from lineIndex.
   *  Returns [bodyLines, linesConsumed, terminator].
   *  terminator is the raw closing line, e.g. "} else {", "} while (cond);", "}", "};", or "". */
  private extractBlock(lines: string[], start: number): [string[], number, string] {
    const body: string[] = [];
    let depth = 1;
    let i = start;
    let terminator = "";
    while (i < lines.length) {
      const l = lines[i];
      // "} while (...)" closes the do-body (depth--)
      if (l === "}" || l === "};") {
        depth--;
        if (depth === 0) { terminator = l; break; }
      } else if (l.match(/^}\s*while\s*\(/)) {
        depth--;
        if (depth === 0) { terminator = l; break; }
      } else if (l === "} else {" || /^}\s*else\s*if\s*\(.*\)\s*\{?$/.test(l)) {
        // At depth 1: terminates the current block (the if-body) — caller will handle the else.
        // At depth > 1: net-zero (inner if-else inside the block), depth unchanged.
        if (depth === 1) { depth--; terminator = l; break; }
      } else if (/^}\s*catch\s*(?:\([^)]*\))?\s*\{?$/.test(l) || /^}\s*finally\s*\{?$/.test(l)) {
        // } catch (e) { or } finally { — at depth 1 terminates the try body; at depth > 1 net-zero
        // (inner try/catch inside the block), so treat as neutral (do NOT increment depth).
        if (depth === 1) { depth--; terminator = l; break; }
        // depth > 1: fall through to body.push — line included but depth unchanged (net-zero)
      } else if (l.endsWith("{")) {
        depth++;
      }
      body.push(l);
      i++;
    }
    return [body, i - start + 1, terminator];
  }

  // -------------------------------------------------------------------------
  // WAT module emission
  // -------------------------------------------------------------------------
  private emitWasiImports(): string {
    const lines: string[] = [];
    // proc_exit is only needed in WASI mode (called from _start; not emitted in library mode).
    if (this.mode === "wasi") {
      lines.push(`  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))`);
    }
    if (this.hasConsoleLog) {
      lines.push(
        `  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))`
      );
    }
    return lines.join("\n");
  }

  private emitHelpers(): string {
    const parts: string[] = [];
    // Bump allocator (Phase 10) — always emitted; Binaryen -Oz strips it when unused
    parts.push(`  ;; Bump allocator — advances __heap_ptr and returns the old value
  (func $__malloc (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $__heap_ptr))
    (global.set $__heap_ptr (i32.add (local.get $ptr) (local.get $size)))
    (local.get $ptr)
  )`);
    if (this.needsStringHelpers)   parts.push(this.getStringHelperWat());
    if (this.needsStringOpHelpers || this.needsStrGatherHelper) parts.push(this.getStringOpHelperWat());
    if (this.needsNumericHelpers)  parts.push(getHelperWat());
    if (this.mathHelpers.size > 0) parts.push(this.emitMathHelpers());
    if (this.dynArrHelpers.size > 0) parts.push(this.emitDynArrHelpers());
    return parts.join("\n");
  }

  private emitMathHelpers(): string {
    // All four helpers are always emitted together — Binaryen -Oz dead-strips unused functions,
    // so there is no binary-size cost. This avoids having to track which helpers are used
    // across the console_log.ts boundary (where mathHelpers cannot be mutated).
    return [
      `  ;; Math.abs for i32
  (func $__i32_abs (param $x i32) (result i32)
    (select
      (i32.sub (i32.const 0) (local.get $x))
      (local.get $x)
      (i32.lt_s (local.get $x) (i32.const 0))
    )
  )`,
      `  ;; Math.min for i32
  (func $__i32_min (param $a i32) (param $b i32) (result i32)
    (select (local.get $a) (local.get $b) (i32.lt_s (local.get $a) (local.get $b)))
  )`,
      `  ;; Math.max for i32
  (func $__i32_max (param $a i32) (param $b i32) (result i32)
    (select (local.get $a) (local.get $b) (i32.gt_s (local.get $a) (local.get $b)))
  )`,
      `  ;; Math.pow — iterative (accurate for non-negative integer exponents)
  (func $__math_pow (param $base f64) (param $exp f64) (result f64)
    (local $result f64)
    (local $n i32)
    (local.set $result (f64.const 1))
    (local.set $n (i32.trunc_f64_s (local.get $exp)))
    (block $done
      (loop $loop
        (br_if $done (i32.le_s (local.get $n) (i32.const 0)))
        (local.set $result (f64.mul (local.get $result) (local.get $base)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $result)
  )`,
    ].join("\n\n");
  }

  private emitDynArrHelpers(): string {
    const parts: string[] = [];

    // Determine which grow helpers are needed (one per elem type used by push or unshift).
    const growNeeded = new Set<string>();
    for (const key of this.dynArrHelpers) {
      const [method, elemType] = key.split("_");
      if (method === "push" || method === "unshift") growNeeded.add(elemType);
    }

    // Emit grow helpers first (push/unshift call them).
    for (const elemType of growNeeded) {
      const isF64   = elemType === "f64";
      const shift   = isF64 ? 3 : 2;
      const loadOp  = isF64 ? "f64.load"  : "i32.load";
      const storeOp = isF64 ? "f64.store" : "i32.store";
      parts.push(`  ;; Dynamic array grow_${elemType}: malloc new block of newcap elements, copy data, return new ptr.
  (func $__dynarr_grow_${elemType} (param $arr i32) (param $newcap i32) (result i32)
    (local $newptr i32)
    (local $len i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $newcap) (i32.const ${shift})))))
    (i32.store (local.get $newptr) (local.get $len))
    (i32.store offset=4 (local.get $newptr) (local.get $newcap))
    (local.set $i (i32.const 0))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (${storeOp}
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (${loadOp}
            (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )`);
    }

    // Emit only the helpers actually used in this module.
    for (const key of this.dynArrHelpers) {
      const [method, elemType] = key.split("_") as [string, WatType];
      const isF64   = elemType === "f64";
      const shift   = isF64 ? 3 : 2;
      const loadOp  = isF64 ? "f64.load"  : "i32.load";
      const storeOp = isF64 ? "f64.store" : "i32.store";
      const valType = isF64 ? "f64" : "i32";
      const name    = `$__dynarr_${key}`;

      if (method === "push") {
        parts.push(`  ;; Dynamic array push_${elemType}: grow if full, store val at end, increment length, return new arr ptr.
  (func ${name} (param $arr i32) (param $val ${valType}) (result i32)
    (local $len i32)
    (local $cap i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $cap (i32.load offset=4 (local.get $arr)))
    (if (i32.ge_u (local.get $len) (local.get $cap))
      (then
        (local.set $arr (call $__dynarr_grow_${elemType} (local.get $arr) (i32.shl (local.get $cap) (i32.const 1))))
      )
    )
    (${storeOp}
      (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $len) (i32.const ${shift})))
      (local.get $val)
    )
    (local.set $len (i32.add (local.get $len) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $len))
    (local.get $arr)
  )`);
      } else if (method === "pop") {
        parts.push(`  ;; Dynamic array pop_${elemType}: decrement length, return last element. Traps if empty.
  (func ${name} (param $arr i32) (result ${valType})
    (local $newlen i32)
    (if (i32.eqz (i32.load (local.get $arr))) (then (unreachable)))
    (local.set $newlen (i32.sub (i32.load (local.get $arr)) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $newlen))
    (${loadOp}
      (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $newlen) (i32.const ${shift})))
    )
  )`);
      } else if (method === "shift") {
        parts.push(`  ;; Dynamic array shift_${elemType}: return first element, shift remainder left. Traps if empty.
  (func ${name} (param $arr i32) (result ${valType})
    (local $len i32)
    (local $val ${valType})
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (if (i32.eqz (local.get $len)) (then (unreachable)))
    (local.set $val (${loadOp} offset=8 (local.get $arr)))
    (local.set $i (i32.const 0))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (i32.sub (local.get $len) (i32.const 1))))
        (${storeOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (${loadOp}
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (i32.const 1)) (i32.const ${shift})))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.store (local.get $arr) (i32.sub (local.get $len) (i32.const 1)))
    (local.get $val)
  )`);
      } else if (method === "unshift") {
        parts.push(`  ;; Dynamic array unshift_${elemType}: grow if full, insert val at front, shift elements right, return new arr ptr.
  (func ${name} (param $arr i32) (param $val ${valType}) (result i32)
    (local $len i32)
    (local $cap i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $cap (i32.load offset=4 (local.get $arr)))
    (if (i32.ge_u (local.get $len) (local.get $cap))
      (then
        (local.set $arr (call $__dynarr_grow_${elemType} (local.get $arr) (i32.shl (local.get $cap) (i32.const 1))))
      )
    )
    (local.set $i (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.eqz (local.get $i)))
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        (${storeOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8))
            (i32.shl (i32.add (local.get $i) (i32.const 1)) (i32.const ${shift})))
          (${loadOp}
            (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          )
        )
        (br $lp)
      )
    )
    (${storeOp} offset=8 (local.get $arr) (local.get $val))
    (local.set $len (i32.add (local.get $len) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $len))
    (local.get $arr)
  )`);
      } else if (method === "indexof") {
        const cmpOp = isF64 ? "f64.eq" : "i32.eq";
        parts.push(`  ;; Dynamic array indexof_${elemType}: linear search, returns index or -1.
  (func ${name} (param $arr i32) (param $val ${valType}) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (if (${cmpOp}
              (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
              (local.get $val))
          (then (return (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const -1)
  )`);
      } else if (method === "slice") {
        parts.push(`  ;; Dynamic array slice_${elemType}: alloc new array from [start,end), clamp to bounds.
  (func ${name} (param $arr i32) (param $start i32) (param $end i32) (result i32)
    (local $len i32)
    (local $newlen i32)
    (local $newptr i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (if (i32.lt_s (local.get $start) (i32.const 0)) (then (local.set $start (i32.const 0))))
    (if (i32.gt_s (local.get $start) (local.get $len)) (then (local.set $start (local.get $len))))
    (if (i32.lt_s (local.get $end) (i32.const 0)) (then (local.set $end (i32.const 0))))
    (if (i32.gt_s (local.get $end) (local.get $len)) (then (local.set $end (local.get $len))))
    (local.set $newlen (i32.sub (local.get $end) (local.get $start)))
    (if (i32.lt_s (local.get $newlen) (i32.const 0)) (then (local.set $newlen (i32.const 0))))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $newlen) (i32.const ${shift})))))
    (i32.store (local.get $newptr) (local.get $newlen))
    (i32.store offset=4 (local.get $newptr) (local.get $newlen))
    (block $done
      (loop $lp
        (br_if $done (i32.ge_u (local.get $i) (local.get $newlen)))
        (${storeOp}
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (${loadOp}
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (local.get $start)) (i32.const ${shift})))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )`);
      } else if (method === "foreach") {
        // Register callback type: (elemType) → void
        const ftName = this.getOrCreateFuncType([elemType], null);
        parts.push(`  ;; Dynamic array foreach_${elemType}: call fn(elem) for each element.
  (func ${name} (param $arr i32) (param $fn i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (call_indirect (type ${ftName})
          (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
          (local.get $fn))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
  )`);
      } else if (method === "map") {
        // Register callback type: (elemType) → elemType
        const ftName = this.getOrCreateFuncType([elemType], elemType);
        parts.push(`  ;; Dynamic array map_${elemType}: alloc new array, fill with fn(elem) results.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $newptr i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $len) (i32.const ${shift})))))
    (i32.store (local.get $newptr) (local.get $len))
    (i32.store offset=4 (local.get $newptr) (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (${storeOp}
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (call_indirect (type ${ftName})
            (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )`);
      } else if (method === "filter") {
        // Register callback type: (elemType) → i32
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        parts.push(`  ;; Dynamic array filter_${elemType}: alloc new array with elements where fn(elem) is truthy.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local $newptr i32)
    (local $newlen i32)
    (local $val ${valType})
    (local.set $len (i32.load (local.get $arr)))
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $len) (i32.const ${shift})))))
    (i32.store offset=4 (local.get $newptr) (local.get $len))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $val (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (if (call_indirect (type ${ftName}) (local.get $val) (local.get $fn))
          (then
            (${storeOp}
              (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $newlen) (i32.const ${shift})))
              (local.get $val))
            (local.set $newlen (i32.add (local.get $newlen) (i32.const 1)))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.store (local.get $newptr) (local.get $newlen))
    (local.get $newptr)
  )`);
      } else if (method === "find") {
        // Register callback type: (elemType) → i32
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        const notFound = isF64 ? "(f64.const nan)" : "(i32.const -1)";
        parts.push(`  ;; Dynamic array find_${elemType}: return first elem where fn(elem) is truthy, or ${isF64 ? "NaN" : "-1"}.
  (func ${name} (param $arr i32) (param $fn i32) (result ${valType})
    (local $i i32)
    (local $len i32)
    (local $val ${valType})
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $val (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (if (call_indirect (type ${ftName}) (local.get $val) (local.get $fn))
          (then (return (local.get $val)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    ${notFound}
  )`);
      } else if (method === "reduce") {
        // Register callback type: (elemType, elemType) → elemType
        const ftName = this.getOrCreateFuncType([elemType, elemType], elemType);
        parts.push(`  ;; Dynamic array reduce_${elemType}: fold array with fn(acc, elem), starting from init.
  (func ${name} (param $arr i32) (param $fn i32) (param $acc ${valType}) (result ${valType})
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $acc
          (call_indirect (type ${ftName})
            (local.get $acc)
            (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
            (local.get $fn)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $acc)
  )`);
      } else if (method === "concat") {
        // Allocate new array of combined length, copy both arrays into it.
        parts.push(`  ;; Dynamic array concat_${elemType}: alloc new array = arrA ++ arrB.
  (func ${name} (param $a i32) (param $b i32) (result i32)
    (local $lenA i32)
    (local $lenB i32)
    (local $newlen i32)
    (local $cap i32)
    (local $newptr i32)
    (local $i i32)
    (local.set $lenA (i32.load (local.get $a)))
    (local.set $lenB (i32.load (local.get $b)))
    (local.set $newlen (i32.add (local.get $lenA) (local.get $lenB)))
    (local.set $cap (local.get $newlen))
    (if (i32.lt_u (local.get $cap) (i32.const 8)) (then (local.set $cap (i32.const 8))))
    (local.set $newptr (call $__malloc
      (i32.add (i32.const 8) (i32.shl (local.get $cap) (i32.const ${shift})))))
    (i32.store (local.get $newptr) (local.get $newlen))
    (i32.store offset=4 (local.get $newptr) (local.get $cap))
    (local.set $i (i32.const 0))
    (block $doneA
      (loop $lpA
        (br_if $doneA (i32.ge_u (local.get $i) (local.get $lenA)))
        (${storeOp}
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (${loadOp} (i32.add (i32.add (local.get $a) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lpA)
      )
    )
    (local.set $i (i32.const 0))
    (block $doneB
      (loop $lpB
        (br_if $doneB (i32.ge_u (local.get $i) (local.get $lenB)))
        (${storeOp}
          (i32.add (i32.add (local.get $newptr) (i32.const 8))
            (i32.shl (i32.add (local.get $i) (local.get $lenA)) (i32.const ${shift})))
          (${loadOp} (i32.add (i32.add (local.get $b) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lpB)
      )
    )
    (local.get $newptr)
  )`);
      }
    }
    return parts.join("\n\n");
  }

  private getStringHelperWat(): string {
    return `
  ;; ── str_cmp: lexicographic byte comparison ─────────────────────────────────
  ;; Returns negative if a<b, 0 if a==b, positive if a>b.
  (func $__str_cmp
    (param $aptr i32) (param $alen i32) (param $bptr i32) (param $blen i32)
    (result i32)
    (local $i i32)
    (local $minlen i32)
    (local $ca i32)
    (local $cb i32)
    (local.set $minlen
      (if (result i32) (i32.lt_s (local.get $alen) (local.get $blen))
        (then (local.get $alen))
        (else (local.get $blen))
      )
    )
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $minlen)))
        (local.set $ca (i32.load8_u (i32.add (local.get $aptr) (local.get $i))))
        (local.set $cb (i32.load8_u (i32.add (local.get $bptr) (local.get $i))))
        (if (i32.ne (local.get $ca) (local.get $cb))
          (then (return (i32.sub (local.get $ca) (local.get $cb))))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.sub (local.get $alen) (local.get $blen))
  )`.trimEnd();
  }

  private getStringOpHelperWat(): string {
    return `
  ;; ── str_gather: copy len bytes from src to dst (byte-copy loop, no bulk-memory) ──
  ;; Used by gather-buffer mode in console.log for strvar/boolvar segments.
  (func $__str_gather (param $src i32) (param $slen i32) (param $dst i32)
    (local $i i32)
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $slen)))
        (i32.store8
          (i32.add (local.get $dst) (local.get $i))
          (i32.load8_u (i32.add (local.get $src) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )

  ;; ── str_concat: heap-allocate new string = a ++ b ───────────────────────────
  ;; Copies bytes of a then b into a malloc'd buffer. Returns (ptr, len).
  ;; Old buffers become dead memory (bump allocator has no free).
  (func $__str_concat
    (param $aptr i32) (param $alen i32) (param $bptr i32) (param $blen i32)
    (result i32 i32)
    (local $newptr i32) (local $newlen i32) (local $i i32)
    (local.set $newlen (i32.add (local.get $alen) (local.get $blen)))
    (local.set $newptr (call $__malloc (local.get $newlen)))
    ;; copy a
    (local.set $i (i32.const 0))
    (block $done_a
      (loop $copy_a
        (br_if $done_a (i32.ge_u (local.get $i) (local.get $alen)))
        (i32.store8
          (i32.add (local.get $newptr) (local.get $i))
          (i32.load8_u (i32.add (local.get $aptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_a)
      )
    )
    ;; copy b
    (local.set $i (i32.const 0))
    (block $done_b
      (loop $copy_b
        (br_if $done_b (i32.ge_u (local.get $i) (local.get $blen)))
        (i32.store8
          (i32.add (local.get $newptr) (i32.add (local.get $alen) (local.get $i)))
          (i32.load8_u (i32.add (local.get $bptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_b)
      )
    )
    (local.get $newptr)
    (local.get $newlen)
  )

  ;; ── str_slice: return sub-range of existing string (no allocation) ───────────
  ;; Clamps start/end to [0, len]. Returns (ptr+start, end-start).
  (func $__str_slice
    (param $ptr i32) (param $len i32) (param $start i32) (param $end i32)
    (result i32 i32)
    (local $cs i32) (local $ce i32)
    ;; clamp start to [0, len]
    (local.set $cs
      (select (i32.const 0) (local.get $start) (i32.lt_s (local.get $start) (i32.const 0)))
    )
    (if (i32.gt_s (local.get $cs) (local.get $len))
      (then (local.set $cs (local.get $len)))
    )
    ;; clamp end to [cs, len]
    (local.set $ce
      (select (local.get $len) (local.get $end) (i32.gt_s (local.get $end) (local.get $len)))
    )
    (if (i32.lt_s (local.get $ce) (local.get $cs))
      (then (local.set $ce (local.get $cs)))
    )
    (i32.add (local.get $ptr) (local.get $cs))
    (i32.sub (local.get $ce) (local.get $cs))
  )

  ;; ── str_indexof: first occurrence of sub in str, or -1 ──────────────────────
  (func $__str_indexof
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $i i32) (local $j i32) (local $max i32) (local $ok i32)
    ;; empty substring always found at position 0
    (if (i32.eqz (local.get $sublen)) (then (return (i32.const 0))))
    ;; if sub is longer than str, impossible
    (local.set $max (i32.sub (local.get $len) (local.get $sublen)))
    (if (i32.lt_s (local.get $max) (i32.const 0)) (then (return (i32.const -1))))
    (block $found_none
      (loop $outer
        (br_if $found_none (i32.gt_s (local.get $i) (local.get $max)))
        (local.set $j (i32.const 0))
        (local.set $ok (i32.const 1))
        (block $inner_done
          (loop $inner
            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $sublen)))
            (if (i32.ne
              (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $i) (local.get $j))))
              (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
            )
              (then
                (local.set $ok (i32.const 0))
                (br $inner_done)
              )
            )
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner)
          )
        )
        (if (local.get $ok) (then (return (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer)
      )
    )
    (i32.const -1)
  )`.trimEnd();
  }

  private emitDataSection(): string {
    const segments: string[] = [];
    for (const [msg, [offset]] of this.dataMap) {
      const escaped = Array.from(new TextEncoder().encode(msg))
        .map(b => `\\${b.toString(16).padStart(2, "0")}`)
        .join("");
      segments.push(`  (data (i32.const ${offset}) "${escaped}")`);
    }
    for (const { ptr, bytes } of this.rawDataSegments) {
      segments.push(`  (data (i32.const ${ptr}) "${bytes}")`);
    }
    return segments.join("\n");
  }

  private emitFunction(fn: FuncDef): string {
    // Phase 5f: closure factory — emit heap-alloc body + trampoline, skip normal body emit
    if (fn.isClosureFactory && fn.returnedArrow) return this.emitClosureFactory(fn);

    // Reset per-function array and struct tracking
    this.arrayVars  = new Map();
    this.structVars = new Map();
    this.classVars  = new Map();
    this.currentMethodClass = fn.className ?? null;
    this.currentMethodName  = fn.name;

    const locals = new Map<string, WatType>();
    for (const p of fn.params) {
      locals.set(p.name, p.type);
      if (p.type === "string") this.stringVars.add(p.name);
      // Array param: register in arrayVars so arr[i] works inside the function body
      if (p.arrayElemType) {
        if (p.isRest) {
          // Rest param: dynamic layout (8-byte header), pointer received from caller
          this.arrayVars.set(p.name, { elemType: p.arrayElemType, ptr: -1, length: 0, dynamic: true });
        } else {
          this.arrayVars.set(p.name, { elemType: p.arrayElemType, ptr: -1, length: 0 });
        }
      }
      // Struct param: register in structVars with ptr=-1 (runtime pointer via local.get)
      if (p.structType) {
        const def = this.structDefs.get(p.structType);
        if (def) this.structVars.set(p.name, { def, ptr: -1 });
      }
      // Class instance param: also register in classVars for method dispatch
      if (p.structType && this.classDefs.has(p.structType)) {
        this.classVars.set(p.name, { className: p.structType, ptr: -1 });
      }
    }

    // String params expand to two i32 params: $name_ptr and $name_len
    const params = fn.params
      .flatMap(p => p.type === "string"
        ? [`(param $${p.name}_ptr i32)`, `(param $${p.name}_len i32)`]
        : [`(param $${p.name} ${watBaseType(p.type)})`]
      )
      .join(" ");
    // String/bool return types — string not yet supported (void), bool → i32
    // never: no WAT result clause (function declared as non-returning)
    const watResult = fn.result === null || fn.result === "string" || fn.result === "never"
      ? null : watBaseType(fn.result);
    const result    = watResult ? `(result ${watResult})` : "";
    // _start is always exported (IIFE pattern parses it with exported=false, but WASI requires it)
    const exportAttr = (fn.exported || fn.name === "_start") ? `(export "${fn.name}") ` : "";

    // Phase 10b: identify arrays that need dynamic (heap) layout because push/pop/shift/unshift are called.
    const dynamicArrayNames = this.findDynamicArrays(fn.bodyLines);

    // Pre-scan body for var/let/const declarations to emit WAT locals.
    // String variables expand to two i32 locals: $name_ptr and $name_len.
    const declaredLocals: [string, WatType][] = [];
    for (const line of fn.bodyLines) {
      // Function-type variable with type annotation: const f: (a: i32) => i32 = someFunc
      // OR declaration only: let f: (a: i32) => i32;
      const funcTypedDecl = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*(\([^)]*\)\s*=>\s*\w+)/);
      if (funcTypedDecl) {
        const sig = this.parseFuncTypeSig(funcTypedDecl[2]);
        this.funcTypeVars.set(funcTypedDecl[1], sig);
        declaredLocals.push([funcTypedDecl[1], "i32"]);
        locals.set(funcTypedDecl[1], "i32");
        continue;
      }
      // Class instance: const obj: ClassName = new ClassName(args) or const obj = new ClassName(args)
      const newClassPre = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*([A-Z]\w*))?\s*=\s*new\s+([A-Z]\w*)\s*\(/);
      if (newClassPre) {
        const varName = newClassPre[1];
        const ctorName = newClassPre[3];
        const typeName = newClassPre[2] ?? ctorName;
        const cd = this.classDefs.get(typeName) ?? this.classDefs.get(ctorName);
        if (cd) {
          const ptr = this.allocStructData(cd.struct, {});
          this.classVars.set(varName, { className: cd.name, ptr });
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }

      // Struct object literal: const p: Point = { x: 1.5, y: 2.5 }
      const structPre = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{([^}]*)\}/);
      if (structPre) {
        const varName  = structPre[1];
        const typeName = structPre[2];
        const def = this.structDefs.get(typeName);
        if (def) {
          // Parse field initializers from "{ x: 1.5, y: 2.5 }"
          const initFields: Record<string, string> = {};
          const initRe = /(\w+)\s*:\s*([^,}]+)/g;
          let im: RegExpExecArray | null;
          while ((im = initRe.exec(structPre[3])) !== null) {
            initFields[im[1]] = im[2].trim();
          }
              const ptr = this.allocStructData(def, initFields);
          this.structVars.set(varName, { def, ptr });
          // Declare an i32 local to hold the pointer (mirrors array var pattern)
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // Spread array literal: const merged = [...a, ...b]
      const spreadArrPre = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/);
      if (spreadArrPre && spreadArrPre[3]?.includes("...")) {
        const varName = spreadArrPre[1];
        const typeHint = spreadArrPre[2] ?? "";
        const elemType: WatType = typeHint ? mapType(typeHint) as WatType : "i32";
        this.arrayVars.set(varName, { elemType, ptr: -2, length: 0, dynamic: true });
        declaredLocals.push([varName, "i32"]);
        locals.set(varName, "i32");
        continue;
      }
      // Array literal declaration: allocate static memory or (for dynamic arrays) heap.
      const arrPre = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/);
      if (arrPre) {
        const varName = arrPre[1];
        const typeHint = arrPre[2] ?? "";
        const elemsStr = arrPre[3] ?? "";
        const elements = elemsStr.split(",").map(e => e.trim()).filter(e => e.length > 0);
        const elemType: WatType = typeHint ? mapType(typeHint) as WatType
          : elements.some(e => /[.]/.test(e) && !/^-?\d+n?$/.test(e)) ? "f64" : "i32";
        if (dynamicArrayNames.has(varName)) {
          // Dynamic array: runtime malloc with [length, capacity] header. ptr=-2 signals heap layout.
          const capacity = Math.max(elements.length * 2, 8);
          this.arrayVars.set(varName, { elemType, ptr: -2, length: elements.length, dynamic: true, capacity, initElements: elements });
        } else {
          const ptr = this.allocArrayData(elements, elemType);
          this.arrayVars.set(varName, { elemType, ptr, length: elements.length });
        }
        declaredLocals.push([varName, "i32"]);
        locals.set(varName, "i32");
        continue;
      }
      // Array variable from method-call RHS: const arr: T[] = someArr.slice(...) / .map(...) etc.
      // Not a literal [...]; runtime pointer returned by the method — always dynamic layout.
      const arrCallPre = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*(\w+)\[\]\s*=\s*([^[].+)/);
      if (arrCallPre && !this.arrayVars.has(arrCallPre[1])) {
        const varName = arrCallPre[1];
        const elemType = mapType(arrCallPre[2]) as WatType;
        this.arrayVars.set(varName, { elemType, ptr: -2, length: 0, dynamic: true });
        declaredLocals.push([varName, "i32"]);
        locals.set(varName, "i32");
        continue;
      }
      // Object destructuring: const { x, y } = structVar  or  const { x: localX } = structVar
      const destructPre = line.match(/^(?:var|let|const)\s*\{([^}]+)\}\s*=\s*(\w+)\s*;?$/);
      if (destructPre) {
        const sv = this.structVars.get(destructPre[2]);
        if (sv) {
          for (const binding of destructPre[1].split(",").map(b => b.trim()).filter(Boolean)) {
            const colonIdx = binding.indexOf(":");
            const fieldName = colonIdx !== -1 ? binding.slice(0, colonIdx).trim() : binding;
            const localName = colonIdx !== -1 ? binding.slice(colonIdx + 1).trim() : binding;
            const field = sv.def.fields.find(f => f.name === fieldName);
            if (field) {
              declaredLocals.push([localName, field.type]);
              locals.set(localName, field.type);
            }
          }
        }
        continue;
      }
      const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
      if (m) {
        const typeStr = m[2] ?? "";
        const initExpr = (m[3] ?? "").trim();
        // Arrow function declarations — already parsed as module-level functions by parseArrowFunctions.
        // If the variable name matches a known function, register it as a funcref i32 local so
        // it can be passed as a callback (e.g. console.log(applyLogic(10, increment))).
        if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) {
          const fn2 = this.functions.find(fn2 => fn2.name === m[1]);
          if (fn2) {
            const baseCount = fn2.params.length - (fn2.closureCaptures?.length ?? 0);
            const sig2 = { params: fn2.params.slice(0, baseCount).map(p => p.type), result: fn2.result };
            this.funcTypeVars.set(m[1], sig2);
            declaredLocals.push([m[1], "i32"]);
            locals.set(m[1], "i32");
          }
          continue;
        }
        // Function variable: const f = knownFuncName (no type annotation)
        if (!typeStr && /^\w+$/.test(initExpr) && this.functions.find(fn2 => fn2.name === initExpr)) {
          const fn2 = this.functions.find(fn2 => fn2.name === initExpr)!;
          const baseCount = fn2.params.length - (fn2.closureCaptures?.length ?? 0);
          const sig2 = { params: fn2.params.slice(0, baseCount).map(p => p.type), result: fn2.result };
          this.funcTypeVars.set(m[1], sig2);
          declaredLocals.push([m[1], "i32"]);
          locals.set(m[1], "i32");
          continue;
        }
        const t = typeStr ? mapType(typeStr) : inferInitType(initExpr, locals, this.enumValues, this.functions);
        if (t === "string") {
          declaredLocals.push([`${m[1]}_ptr`, "i32"], [`${m[1]}_len`, "i32"]);
          locals.set(m[1], "string");
          this.stringVars.add(m[1]);
        } else {
          declaredLocals.push([m[1], t]);
          locals.set(m[1], t);
        }
      }
      // for-loop init variable: for (let i = 0; ...)
      const forM = line.match(/^(?:\w+\s*:\s*)?for\s*\(\s*(?:let|const|var)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?)\s*;/);
      if (forM) {
        const typeStr2 = forM[2] ?? "";
        const initExpr2 = forM[3].trim();
        const t2 = typeStr2 ? mapType(typeStr2) : inferInitType(initExpr2, locals, this.enumValues, this.functions);
        declaredLocals.push([forM[1], t2]);
        locals.set(forM[1], t2);
      }
      // catch variable: } catch (e) { — registers e as a (ptr, len) string pair
      const catchVarPre = line.match(/^}\s*catch\s*\(\s*(\w+)(?:\s*:\s*\w+)?\s*\)\s*\{?$/);
      if (catchVarPre && catchVarPre[1] && !locals.has(catchVarPre[1])) {
        const cv = catchVarPre[1];
        declaredLocals.push([`${cv}_ptr`, "i32"], [`${cv}_len`, "i32"]);
        locals.set(cv, "string");
        this.stringVars.add(cv);
      }
    }
    // Add $__rest_ptr if any body line calls a rest-param function with literal args
    if (this.hasRestLiteralCalls(fn.bodyLines) && !locals.has("__rest_ptr")) {
      declaredLocals.push(["__rest_ptr", "i32"]);
      locals.set("__rest_ptr", "i32");
    }
    const localDecls = declaredLocals
      .map(([n, t]) => `    (local $${n} ${watBaseType(t)})`)
      .join("\n");

    // For never-returning functions pass null so return statements emit (return) with no value.
    const blockResult = fn.result === "never" ? null : fn.result;
    const body = this.emitBlock(fn.bodyLines, locals, blockResult);
    // Phase 21: append (unreachable) for never-typed functions — signals to the WASM validator
    // that control never reaches the end of this function.
    const neverSuffix = fn.result === "never" ? "\n    (unreachable)" : "";

    return [
      `  (func $${fn.name} ${exportAttr}${params} ${result}`,
      localDecls ? localDecls : "",
      body + neverSuffix,
      `  )`,
    ].filter(l => l.trim() !== "").join("\n");
  }

  // -------------------------------------------------------------------------
  // Phase 5f – emit closure factory + trampoline
  // -------------------------------------------------------------------------
  /**
   * Emits two WAT functions for a closure factory:
   *
   *   1. The factory itself: allocates a closure struct {table_idx, captures...}
   *      on the heap and returns its i32 pointer.
   *
   *   2. A trampoline `$name__trampoline(closure_ptr, ...call_params)` that loads
   *      the captured values from the struct and dispatches via call_indirect.
   */
  private emitClosureFactory(fn: FuncDef): string {
    const inner = fn.returnedArrow!;
    const captures = inner.closureCaptures ?? [];

    // Build per-capture layout: {name, type, byte-offset-in-struct}
    let structSize = 4; // first 4 bytes = i32 table index
    const captureLayout: { name: string; type: WatType; offset: number }[] = [];
    for (const cap of captures) {
      const capParam = inner.params.find(p => p.name === cap);
      const capType: WatType = capParam?.type ?? "i32";
      captureLayout.push({ name: cap, type: capType, offset: structSize });
      structSize += (capType === "f64" || capType === "i64") ? 8 : 4;
    }

    // Ensure the inner function is in the funcref table
    const tableIdx = this.getFuncTableIdx(inner.name);

    const exportAttr = fn.exported ? `(export "${fn.name}") ` : "";
    const factoryParams = fn.params
      .map(p => `(param $${p.name} ${watBaseType(p.type)})`)
      .join(" ");

    // ── Factory function ─────────────────────────────────────────────────────
    const factoryLines: string[] = [];
    factoryLines.push(`  (func $${fn.name} ${exportAttr}${factoryParams} (result i32)`.trimEnd());
    factoryLines.push(`    (local $__closure_ptr i32)`);
    factoryLines.push(`    (local.set $__closure_ptr (call $__malloc (i32.const ${structSize})))`);
    factoryLines.push(`    (i32.store (local.get $__closure_ptr) (i32.const ${tableIdx}))`);
    for (const { name, type, offset } of captureLayout) {
      const storeOp = type === "f64" ? "f64.store" : type === "i64" ? "i64.store" : "i32.store";
      factoryLines.push(`    (${storeOp} offset=${offset} (local.get $__closure_ptr) (local.get $${name}))`);
    }
    factoryLines.push(`    (local.get $__closure_ptr)`);
    factoryLines.push(`  )`);

    // ── Trampoline function ───────────────────────────────────────────────────
    // Params: closure_ptr + the inner function's NON-captured params (the "real" call args)
    const innerCallParams = inner.params.filter(p => !captures.includes(p.name));
    const trampolineParamStr = [
      `(param $__closure_ptr i32)`,
      ...innerCallParams.map(p => `(param $${p.name} ${watBaseType(p.type)})`),
    ].join(" ");

    const watResult = inner.result === null || inner.result === "never" ? null : watBaseType(inner.result);
    const resultClause = watResult ? `(result ${watResult})` : "";

    // Register the functype for the full inner signature (call params + captures)
    const innerParamTypes = inner.params.map(p => p.type);
    const innerTypeName = this.getOrCreateFuncType(innerParamTypes, inner.result);

    const trampolineLines: string[] = [];
    trampolineLines.push(`  (func $${fn.name}__trampoline ${trampolineParamStr} ${resultClause}`.trimEnd());
    for (const { name, type } of captureLayout) {
      trampolineLines.push(`    (local $__cap_${name} ${watBaseType(type)})`);
    }
    for (const { name, type, offset } of captureLayout) {
      const loadOp = type === "f64" ? "f64.load" : type === "i64" ? "i64.load" : "i32.load";
      trampolineLines.push(`    (local.set $__cap_${name} (${loadOp} offset=${offset} (local.get $__closure_ptr)))`);
    }
    // call_indirect args: real call params, then captures, then table index (last)
    const callArgs = [
      ...innerCallParams.map(p => `(local.get $${p.name})`),
      ...captureLayout.map(c => `(local.get $__cap_${c.name})`),
      `(i32.load (local.get $__closure_ptr))`,
    ].join(" ");
    trampolineLines.push(`    (call_indirect (type ${innerTypeName}) ${callArgs})`);
    trampolineLines.push(`  )`);

    return [...factoryLines, "", ...trampolineLines].join("\n");
  }

  // -------------------------------------------------------------------------
  // Pass 1c – inject hidden parameters for closure captures
  // -------------------------------------------------------------------------
  /**
   * For each nested arrow function that references variables from an outer
   * function's scope, appends those variables as hidden extra parameters.
   * At call sites (emitExpr / emitStatement) the caller automatically passes
   * the captured values via local.get.
   *
   * Example:  const scale = (val: i32): i32 => val * multiplier;
   *   → $scale gets an extra (param $multiplier i32)
   *   → call sites: (call $scale (i32.const 10) (local.get $multiplier))
   */
  private injectClosureCaptures(): void {
    const KEYWORDS = new Set([
      "return","if","else","while","for","do","switch","case","default",
      "break","continue","const","let","var","true","false","null","undefined",
    ]);

    for (const af of this.functions) {
      // Find the INNERMOST outer function whose bodyLines declare this arrow function.
      // We scan all functions and keep the last match: nested functions appear later in
      // this.functions than the outer ones that contain them verbatim, so the last match
      // is always the closest (innermost) enclosing scope.
      let outer: FuncDef | undefined;
      for (const f of this.functions) {
        if (f !== af && f.bodyLines.some(l => new RegExp(`\\bconst\\s+${af.name}\\s*=`).test(l))) {
          outer = f;
        }
      }
      // Phase 5f: for returned arrows, the factory function is the outer scope directly
      // (no `const name =` pattern exists in the factory body — it's a `return (...)=>` line).
      if (!outer && af.returnedByFactory) {
        outer = this.functions.find(f => f.name === af.returnedByFactory);
      }
      if (!outer) continue;

      // Build outer scope: params + locally declared variables
      const outerScope = new Map<string, WatType>();
      for (const p of outer.params) outerScope.set(p.name, p.type);
      for (const line of outer.bodyLines) {
        const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
        if (m) {
          const typeStr = m[2] ?? "";
          const initExpr = (m[3] ?? "").trim();
          if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) continue; // skip arrow decls
          const t = typeStr ? mapType(typeStr) : inferInitType(initExpr, outerScope, this.enumValues, this.functions);
          if (t !== "string") outerScope.set(m[1], t);
        }
      }

      // Collect all identifiers referenced in af's body
      const ownParams = new Set(af.params.map(p => p.name));
      const used = new Set<string>();
      for (const line of af.bodyLines) {
        for (const m of line.matchAll(/\b([a-zA-Z_]\w*)\b/g)) used.add(m[1]);
      }

      // Captures = identifiers used but not declared in af, that exist in outer scope
      const captures: string[] = [];
      for (const id of used) {
        if (!ownParams.has(id) && !KEYWORDS.has(id) && outerScope.has(id)) {
          captures.push(id);
        }
      }

      if (captures.length > 0) {
        af.closureCaptures = captures;
        for (const cap of captures) {
          af.params.push({ name: cap, type: outerScope.get(cap)! });
        }
      }
    }
  }

  transpile(_moduleName: string): string {
    // Pre-pass: expand generic templates by monomorphization before any other parsing
    this.src = this.expandGenerics(this.src);
    this.parseEnums();
    this.parseStructs();
    this.parseClasses();
    this.parseFunctions();
    this.parseArrowFunctions();
    this.injectClosureCaptures();
    this.liftInlineArrows();
    this.parseTopLevel();

    // Emit all user functions first — this populates hasConsoleLog/needsNumericHelpers
    const funcWat = this.functions.map(f => this.emitFunction(f)).join("\n\n");

    // Build _start inner body — priority: user _start() > named main() > collected startBodyLines > empty.
    // In library mode skip entirely: no entry point, and top-level statements (console.log etc.) must not
    // influence hasConsoleLog / helper flags for the library binary.
    const hasUserStart = this.functions.some(f => f.name === "_start");
    const hasMain = !hasUserStart && this.functions.some(f => f.name === "main");
    let startBody: string;
    if (this.mode === "library") {
      startBody = ""; // unused in library mode — _start is never emitted
    } else if (hasMain) {
      startBody = `\n    (call $main)\n    (call $proc_exit (i32.const 0))`;
    } else if (this.startBodyLines.length > 0) {
      // Pre-scan for var/let/const so WAT locals are declared at the top of _start.
      // String variables expand to two i32 locals ($name_ptr, $name_len).
      // Reset per-function state so dynamic array helpers work for top-level code.
      this.arrayVars  = new Map();
      this.structVars = new Map();
      this.classVars  = new Map();
      const startDynArrayNames = this.findDynamicArrays(this.startBodyLines);
      const startLocals = new Map<string, WatType>();
      const startDeclaredLocals: [string, WatType][] = [];
      for (const line of this.startBodyLines) {
        // Spread array literal — mirrors emitFunction pre-scan
        const spreadArrPre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/);
        if (spreadArrPre2 && spreadArrPre2[3]?.includes("...")) {
          const varNameS = spreadArrPre2[1];
          const typeHintS = spreadArrPre2[2] ?? "";
          const elemTypeS: WatType = typeHintS ? mapType(typeHintS) as WatType : "i32";
          this.arrayVars.set(varNameS, { elemType: elemTypeS, ptr: -2, length: 0, dynamic: true });
          startLocals.set(varNameS, "i32");
          startDeclaredLocals.push([varNameS, "i32"]);
          continue;
        }
        // Array literal declaration — mirrors emitFunction pre-scan
        const arrPre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/);
        if (arrPre2) {
          const varName2  = arrPre2[1];
          const typeHint2 = arrPre2[2] ?? "";
          const elemsStr2 = arrPre2[3] ?? "";
          const elements2 = elemsStr2.split(",").map(e => e.trim()).filter(e => e.length > 0);
          const elemType2: WatType = typeHint2 ? mapType(typeHint2) as WatType
            : elements2.some(e => /[.]/.test(e) && !/^-?\d+n?$/.test(e)) ? "f64" : "i32";
          if (startDynArrayNames.has(varName2)) {
            const capacity2 = Math.max(elements2.length * 2, 8);
            this.arrayVars.set(varName2, { elemType: elemType2, ptr: -2, length: elements2.length, dynamic: true, capacity: capacity2, initElements: elements2 });
          } else {
            const ptr2 = this.allocArrayData(elements2, elemType2);
            this.arrayVars.set(varName2, { elemType: elemType2, ptr: ptr2, length: elements2.length });
          }
          startLocals.set(varName2, "i32");
          startDeclaredLocals.push([varName2, "i32"]);
          continue;
        }
        // Array variable from method-call RHS: const arr: T[] = someArr.slice(...) etc.
        const arrCallPre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*(\w+)\[\]\s*=\s*([^[].+)/);
        if (arrCallPre2 && !this.arrayVars.has(arrCallPre2[1])) {
          const varName2c = arrCallPre2[1];
          const elemType2c = mapType(arrCallPre2[2]) as WatType;
          this.arrayVars.set(varName2c, { elemType: elemType2c, ptr: -2, length: 0, dynamic: true });
          startLocals.set(varName2c, "i32");
          startDeclaredLocals.push([varName2c, "i32"]);
          continue;
        }
        const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
        if (m) {
          const typeStr = m[2] ?? "";
          const initExpr = (m[3] ?? "").trim();
          // Skip arrow function declarations — lifted to module level, not WAT locals
          if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) continue;
          const t = typeStr ? mapType(typeStr) : inferInitType(initExpr, startLocals, this.enumValues, this.functions);
          if (t === "string") {
            startLocals.set(`${m[1]}_ptr`, "i32");
            startLocals.set(`${m[1]}_len`, "i32");
            startLocals.set(m[1], "string"); // tracker — not emitted as a WAT local
            this.stringVars.add(m[1]);
          } else {
            startLocals.set(m[1], t);
          }
        }
        // for-loop init variable: for (let i = 0; ...)
        const forM = line.match(/^(?:\w+\s*:\s*)?for\s*\(\s*(?:let|const|var)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?)\s*;/);
        if (forM) {
          const typeStr2 = forM[2] ?? "";
          const initExpr2 = forM[3].trim();
          const t2 = typeStr2 ? mapType(typeStr2) : inferInitType(initExpr2, startLocals, this.enumValues, this.functions);
          startDeclaredLocals.push([forM[1], t2]);
          startLocals.set(forM[1], t2);
        }
        // catch variable: } catch (e) { — registers e as a (ptr, len) string pair
        const catchVarPre2 = line.match(/^}\s*catch\s*\(\s*(\w+)(?:\s*:\s*\w+)?\s*\)\s*\{?$/);
        if (catchVarPre2 && catchVarPre2[1] && !startLocals.has(catchVarPre2[1])) {
          const cv2 = catchVarPre2[1];
          startDeclaredLocals.push([`${cv2}_ptr`, "i32"], [`${cv2}_len`, "i32"]);
          startLocals.set(cv2, "string");
          this.stringVars.add(cv2);
        }
      }
      // Add $__rest_ptr if any start body line calls a rest-param function with literal args
      if (this.hasRestLiteralCalls(this.startBodyLines) && !startLocals.has("__rest_ptr")) {
        startDeclaredLocals.push(["__rest_ptr", "i32"]);
        startLocals.set("__rest_ptr", "i32");
      }
      const localDecls = [...startLocals.entries()]
        .filter(([, t]) => t !== "string") // "string" is a tracker only
        .map(([n, t]) => `    (local $${n} ${watBaseType(t as WatType)})`)
        .join("\n");
      const bodyWat = this.emitBlock(this.startBodyLines, startLocals, null);
      startBody = `\n${localDecls ? localDecls + "\n" : ""}${bodyWat}\n    (call $proc_exit (i32.const 0))`;
    } else {
      startBody = `\n    (call $proc_exit (i32.const 0))`;
    }

    // Emit imports after all body emission so fd_write/helpers flags are set
    const imports = this.emitWasiImports();
    const helpers = this.emitHelpers();
    const dataSection = this.emitDataSection();
    // Reserve at least 1 extra page (64 KB) beyond static data for heap growth
    const memoryPages = Math.max(2, Math.ceil(this.dataOffset / 65536) + 1);
    // __heap_ptr starts immediately after the static data section
    const heapStart = this.dataOffset;

    // In library mode, skip _start entirely (no entry point, no proc_exit).
    // In WASI mode, use the user's _start() if present, otherwise emit the generated wrapper.
    const startFunc = (this.mode === "library" || hasUserStart) ? [] : [
      `  (func $_start (export "_start")${startBody}`,
      `  )`,
    ];

    const funcTypesWat = this.emitFuncTypes();
    const funcTableWat = this.emitFuncrefTable();

    return [
      `(module`,
      imports,
      `  (memory (export "memory") ${memoryPages})`,
      `  (global $__heap_ptr (mut i32) (i32.const ${heapStart}))`,
      this.needsExceptionTag ? `  (tag $__exn_tag (param i32 i32))` : "",
      funcTypesWat,
      ``,
      helpers,
      funcWat,
      ``,
      ...startFunc,
      funcTableWat,
      dataSection ? `` : "",
      dataSection,
      `)`,
    ].filter(l => l !== undefined && l !== "").join("\n");
  }
}

// ---------------------------------------------------------------------------
// Phase 18 — WASM import merge helpers
// ---------------------------------------------------------------------------

/**
 * Disassembles a .wasm binary and merges its content into a WAT module string.
 *
 * The WAT string produced by WasicTranspiler ends with a closing `)` for the module.
 * This function splices the imported module's mangled functions, globals, and data
 * segments in just before that closing paren, and deduplicates WASI imports.
 *
 * @param wat          WAT source from WasicTranspiler.transpile()
 * @param wasmBytes    Raw bytes of the .wasm file to merge
 * @param prefix       Module prefix for name mangling (e.g. "math")
 * @param dataOffset   Current end of the main module's static data section
 * @param wabtMod      Initialised wabt instance (already loaded by caller)
 * @returns            { mergedWat, notices, exportedFuncs }
 */
function mergeOneWasmImport(
  wat: string,
  wasmBytes: Uint8Array,
  prefix: string,
  dataOffset: number,
  wabtMod: WabtModule,
): { mergedWat: string; notices: string[]; exportedFuncs: ExternalFuncDef[] } {
  // Disassemble the binary to WAT text
  const importedMod = wabtMod.readWasm(wasmBytes.buffer as ArrayBuffer, { readDebugNames: true });
  const importedWat = importedMod.toText({ foldExprs: false });
  importedMod.destroy();

  const result = mergeWasmWat(importedWat, prefix, dataOffset);

  // Deduplicate WASI imports: if the imported module uses fd_write (etc.) and the
  // main module already imports it, no action needed — the main module's import
  // declaration is already present.  Log for transparency.
  if (result.wasiImportNames.length > 0) {
    const unique = [...new Set(result.wasiImportNames)];
    console.log(`   ℹ️  WASI imports deduplicated from ${prefix}: ${unique.join(", ")}`);
  }

  // Splice merged fragments before the closing `)` of the module
  const fragments: string[] = [];
  if (result.globalWat) fragments.push(`  ;; globals from ${prefix}\n  ${result.globalWat}`);
  if (result.funcWat)   fragments.push(`  ;; functions from ${prefix}\n  ${result.funcWat}`);
  if (result.dataWat)   fragments.push(`  ;; data from ${prefix}\n  ${result.dataWat}`);

  if (fragments.length === 0) return { mergedWat: wat, notices: result.notices, exportedFuncs: result.exportedFuncs };

  // Insert before the final `)` that closes the module
  const closeIdx = wat.lastIndexOf(")");
  const mergedWat = closeIdx === -1
    ? wat + "\n" + fragments.join("\n") + "\n)"
    : wat.slice(0, closeIdx) + "\n" + fragments.join("\n") + "\n)";

  return { mergedWat, notices: result.notices, exportedFuncs: result.exportedFuncs };
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/**
 * Compiles a TypeScript file (numeric subset) to a standalone WASI module.
 * Transpiles to WAT then applies Binaryen size-optimisation, producing a
 * runtime-free binary significantly smaller than Javy output.
 *
 * @param tsPath - Path to the source .ts file.
 * @param outPath - Optional output path; defaults to same name with .wasm extension.
 */
export async function compileWasiTs(tsPath: string, outPath?: string): Promise<WasicResult> {
  const name = basename(tsPath).replace(/\.[^/.]+$/, "");
  const srcDir = dirname(tsPath);
  const out = outPath ?? `${srcDir}/${name}.wasm`;
  // WAT goes alongside the output WASM
  const watPath = out.replace(/\.wasm$/, ".wat");

  if (outPath) await Deno.mkdir(dirname(outPath), { recursive: true });

  let bundleResult: Awaited<ReturnType<typeof bundleImportsEx>>;
  try {
    bundleResult = await bundleImportsEx(tsPath);
  } catch (err) {
    return { success: false, error: `Cannot read ${tsPath}: ${err}` };
  }
  const { source, wasmImports } = bundleResult;

  // Pre-load external function signatures so the transpiler can type call sites.
  // We disassemble each imported .wasm now (before transpilation) to extract exports.
  const wabtMod = await (wabt as unknown as () => Promise<WabtModule>)();
  const allExternalFuncs: ExternalFuncDef[] = [];
  const wasmBytesMap = new Map<string, Uint8Array>();

  for (const entry of wasmImports) {
    try {
      const bytes = await Deno.readFile(entry.filePath);
      wasmBytesMap.set(entry.filePath, bytes);
      const mod = wabtMod.readWasm(bytes.buffer, { readDebugNames: true });
      const importedWat = mod.toText({ foldExprs: false });
      mod.destroy();
      const preResult = mergeWasmWat(importedWat, entry.prefix, 0);
      allExternalFuncs.push(...preResult.exportedFuncs);
    } catch (_err) {
      console.warn(`  ⚠️  Cannot read imported WASM ${entry.filePath} — skipping`);
    }
  }

  const transpiler = new WasicTranspiler(source, "wasi", allExternalFuncs);
  let wat: string;
  try {
    wat = transpiler.transpile(name);
  } catch (err) {
    return { success: false, error: `Transpile error: ${err instanceof Error ? err.message : String(err)}` };
  }

  // Report any unsupported-feature diagnostics collected during transpilation
  for (const msg of transpiler.warnings) {
    console.warn(`  ⚠️  ${msg}`);
  }
  if (transpiler.warnings.length > 0) {
    return { success: false, error: `Compilation aborted: ${transpiler.warnings.length} unsupported feature(s) — see warnings above` };
  }

  // Phase 18: merge each imported .wasm module into the WAT
  let dataOffset = transpiler.dataEnd;
  for (const entry of wasmImports) {
    const bytes = wasmBytesMap.get(entry.filePath);
    if (!bytes) continue;
    const { mergedWat, notices } = mergeOneWasmImport(wat, bytes, entry.prefix, dataOffset, wabtMod);
    for (const notice of notices) {
      console.log(`  ⚠️  Imported "${entry.filePath}": ${notice}`);
    }
    wat = mergedWat;
    // Advance dataOffset so the next imported module's data lands above this one.
    // A second pass with mergeWasmWat(dataReloc=0) gives us the imported module's own
    // dataOffset, which we use as the relocation size.
    const mod2 = wabtMod.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: false });
    const wat2 = mod2.toText({ foldExprs: false });
    mod2.destroy();
    // Advance dataOffset by the imported module's static footprint
    const heapM = wat2.match(/\(global\s+\(;0;\)\s+\(mut i32\)\s+\(i32\.const\s+(\d+)\)\)/);
    dataOffset += heapM ? parseInt(heapM[1]) : 260 /* DATA_BASE fallback */;
  }

  // Write WAT alongside the output for inspection / debugging
  await Deno.writeTextFile(watPath, wat);

  const result = await watToOptimisedWasm(wat, watPath, out);
  if (result.success) {
    console.log(`✅ WASI: ${out} (${result.sizeBytes} bytes)`);
    console.log(`   WAT:  ${watPath}`);
    if (wasmImports.length > 0) {
      console.log(`   Merged: ${wasmImports.map(e => e.prefix).join(", ")}`);
    }
  } else {
    console.error(`❌ wasic: ${result.error}`);
    console.error(`   Inspect generated WAT at: ${watPath}`);
  }
  return result;
}

/**
 * Compiles a TypeScript file to a WASM library module using the wasic transpiler.
 *
 * Library mode differs from WASI mode in three ways:
 *   1. No `_start` function is emitted — the module has no entry point.
 *   2. No `proc_exit` import — only `fd_write` is imported when console.log is used.
 *   3. Only `export function` declarations are visible to callers; all other top-level
 *      code (runner statements, main() calls) is parsed but silently dropped.
 *
 * The output is a pure `.wasm` binary callable from any WASM host environment.
 * Binaryen `-Oz` eliminates any unreachable internal helpers.
 *
 * @param tsPath  - Path to the source `.ts` file.
 * @param outPath - Optional output path; defaults to `<name>.wasm` in the same directory.
 */
export async function compileLibTs(tsPath: string, outPath?: string): Promise<WasicResult> {
  const name = basename(tsPath).replace(/\.[^/.]+$/, "");
  const srcDir = dirname(tsPath);
  const out = outPath ?? `${srcDir}/${name}.wasm`;
  const watPath = out.replace(/\.wasm$/, ".wat");

  if (outPath) await Deno.mkdir(dirname(outPath), { recursive: true });

  let bundleResult2: Awaited<ReturnType<typeof bundleImportsEx>>;
  try {
    bundleResult2 = await bundleImportsEx(tsPath);
  } catch (err) {
    return { success: false, error: `Cannot read ${tsPath}: ${err}` };
  }
  const { source, wasmImports } = bundleResult2;

  const wabtMod2 = await (wabt as unknown as () => Promise<WabtModule>)();
  const allExternalFuncs2: ExternalFuncDef[] = [];
  const wasmBytesMap2 = new Map<string, Uint8Array>();

  for (const entry of wasmImports) {
    try {
      const bytes = await Deno.readFile(entry.filePath);
      wasmBytesMap2.set(entry.filePath, bytes);
      const mod = wabtMod2.readWasm(bytes.buffer, { readDebugNames: true });
      const importedWat = mod.toText({ foldExprs: false });
      mod.destroy();
      const preResult2 = mergeWasmWat(importedWat, entry.prefix, 0);
      allExternalFuncs2.push(...preResult2.exportedFuncs);
    } catch (_err) {
      console.warn(`  ⚠️  Cannot read imported WASM ${entry.filePath} — skipping`);
    }
  }

  const transpiler = new WasicTranspiler(source, "library", allExternalFuncs2);
  let wat: string;
  try {
    wat = transpiler.transpile(name);
  } catch (err) {
    return { success: false, error: `Transpile error: ${err instanceof Error ? err.message : String(err)}` };
  }

  for (const msg of transpiler.warnings) {
    console.warn(`  ⚠️  ${msg}`);
  }
  if (transpiler.warnings.length > 0) {
    return { success: false, error: `Compilation aborted: ${transpiler.warnings.length} unsupported feature(s) — see warnings above` };
  }

  let dataOffset2 = transpiler.dataEnd;
  for (const entry of wasmImports) {
    const bytes = wasmBytesMap2.get(entry.filePath);
    if (!bytes) continue;
    const { mergedWat, notices } = mergeOneWasmImport(wat, bytes, entry.prefix, dataOffset2, wabtMod2);
    for (const notice of notices) {
      console.log(`  ⚠️  Imported "${entry.filePath}": ${notice}`);
    }
    wat = mergedWat;
    const mod2 = wabtMod2.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: false });
    const wat2 = mod2.toText({ foldExprs: false });
    mod2.destroy();
    const heapM = wat2.match(/\(global\s+\(;0;\)\s+\(mut i32\)\s+\(i32\.const\s+(\d+)\)\)/);
    dataOffset2 += heapM ? parseInt(heapM[1]) : 260;
  }

  await Deno.writeTextFile(watPath, wat);

  const result = await watToOptimisedWasm(wat, watPath, out);
  if (result.success) {
    console.log(`✅ Library: ${out} (${result.sizeBytes} bytes)`);
    console.log(`   WAT:  ${watPath}`);
    if (wasmImports.length > 0) {
      console.log(`   Merged: ${wasmImports.map(e => e.prefix).join(", ")}`);
    }
  } else {
    console.error(`❌ wasic (library): ${result.error}`);
    console.error(`   Inspect generated WAT at: ${watPath}`);
  }
  return result;
}

/**
 * Main entry point for the wasic command.
 * Routes .wat files to the direct compilation path and .ts files to the transpiler.
 *
 * @param path - Path to a .ts or .wat source file.
 */
export async function compileWasi(path: string, outPath?: string): Promise<void> {
  if (path.endsWith(".wat")) {
    await compileWat(path, outPath);
    return;
  }

  if (!path.endsWith(".ts")) {
    console.error(`❌ wasic expects a .ts or .wat file. Got: ${path}`);
    return;
  }

  const result = await compileWasiTs(path, outPath);
  if (!result.success) {
    Deno.exit(1);
  }
}
