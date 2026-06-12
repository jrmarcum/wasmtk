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
import binaryen from "./binaryen.ts";
import { basename, dirname } from "@std/path";
import { rt } from "./rt.ts";
import { bundleImportsEx } from "./tsbundler.ts";
import { type ExternalFuncDef, mergeWasmWat, type WasmWatType } from "./wasmmerge.ts";
import { MATHLIB_BYTES } from "./wasm/mathlib_bytes.ts";
import {
  type ClosureVarLookup,
  type DataAllocator,
  type DotCallLookup,
  emitConsoleLog,
  type FuncLookup,
  getArrPrintHelperWat,
  getHelperWat,
  getJoinHelperWat,
  IOV_BASE,
  type LogSegment,
  parseConsoleLogArgs,
  SCRATCH_BASE,
  setFuncTableLookup,
  setInstanceofResolver,
  setStrCmpNeededCallback,
  setStringArrayAllocator,
  setStringExprResolver,
  setStructLiteralAllocator,
  type StructFieldLookup,
  unescapeString,
} from "./console_log.ts";

// ---------------------------------------------------------------------------
// wabt type stubs (same pattern as utils.ts)
// ---------------------------------------------------------------------------
interface WasmFeatures {
  enable_all?: boolean;
  [key: string]: boolean | undefined;
}
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
  outPath: string,
): Promise<WasicResult> {
  try {
    // Step 1: WAT → raw binary via wabt
    const wabtMod = await (wabt as unknown as () => Promise<WabtModule>)();
    const parsed = wabtMod.parseWat(sourcePath, watSource, { enable_all: true, exceptions: true });
    const { buffer } = parsed.toBinary({});
    parsed.destroy();
    const rawBytes = new Uint8Array(buffer);

    // (Exception-using modules used to skip Binaryen here, working around a `-Oz` CoalesceLocals
    // bug that miscompiled try/catch catch-variable locals. That bug is fixed upstream in
    // binaryen-ts 1.3.4 via an EH-aware CFG, so the skip was removed 2026-06-08 — exception modules
    // now get full `-Oz` again. `fixTerminalFallthru`'s terminal-block `(unreachable)` case stays —
    // it's an independent V8-strict-validation fix, not part of the workaround.)

    // Step 2: Binaryen -Oz (shrinkLevel=2, optimizeLevel=2)
    const binMod = binaryen.readBinary(rawBytes);
    // Enable all features (incl. exceptions) so the optimizer preserves them.
    const binAny = binaryen as unknown as Record<string, unknown>;
    const featFlags = binAny["Features"] as Record<string, number> | undefined;
    if (
      featFlags &&
      typeof (binMod as unknown as Record<string, unknown>)["setFeatures"] === "function"
    ) {
      (binMod as unknown as { setFeatures(n: number): void }).setFeatures(
        featFlags["All"] ?? 0x7FFFFFFF,
      );
    }
    binaryen.setShrinkLevel(2);
    binaryen.setOptimizeLevel(2);
    binMod.optimize();
    const optimised = binMod.emitBinary();
    binMod.dispose();

    await rt.writeFile(outPath, optimised);
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
  const source = await rt.readTextFile(watPath);
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

// ---------------------------------------------------------------------------
// Minimal WAT s-expression helpers (used by the terminal-fallthru fix).
// A node is either a raw atom (string, e.g. "i32.add", "$x", "(result", a "…" data
// string) or a nested list of nodes. Comments must be stripped by the caller — the
// tokenizer here only needs to respect "…" data strings.
// ---------------------------------------------------------------------------
type WatNode = string | WatNode[];

function tokenizeWat(s: string): string[] {
  const toks: string[] = [];
  let i = 0;
  while (i < s.length) {
    const ch = s[i];
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") {
      i++;
      continue;
    }
    if (ch === "(" || ch === ")") {
      toks.push(ch);
      i++;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      while (j < s.length) {
        if (s[j] === "\\") {
          j += 2;
          continue;
        }
        if (s[j] === '"') {
          j++;
          break;
        }
        j++;
      }
      toks.push(s.slice(i, j));
      i = j;
      continue;
    }
    let j = i;
    while (j < s.length && !' \t\n\r()"'.includes(s[j])) j++;
    toks.push(s.slice(i, j));
    i = j;
  }
  return toks;
}

function parseWatNodes(toks: string[], pos: { i: number }): WatNode[] {
  const out: WatNode[] = [];
  while (pos.i < toks.length) {
    const t = toks[pos.i];
    if (t === "(") {
      pos.i++;
      out.push(parseWatNodes(toks, pos));
    } else if (t === ")") {
      pos.i++;
      return out;
    } else {
      out.push(t);
      pos.i++;
    }
  }
  return out;
}

function serializeWat(node: WatNode): string {
  if (typeof node === "string") return node;
  return "(" + node.map(serializeWat).join(" ") + ")";
}

function isWatList(n: WatNode): n is WatNode[] {
  return Array.isArray(n);
}

/** Rewrite a node so it leaves a value of type `rt` on the stack instead of `return`ing.
 *  Handles exactly two forms (everything else returns null = "can't safely value this"):
 *    (return X)                       → X
 *    (if cond (then …A) (else …B))    → (if (result rt) cond (then …A') (else …B'))
 *  where A'/B' recursively value their own trailing node. Conservative by design: only
 *  rewrites when every leaf of the construct is a `return` (directly or via nested ifs). */
function watNodeToValue(node: WatNode, rt: string): WatNode | null {
  if (!isWatList(node)) return null;
  const head = node[0];
  if (head === "return") return node.length === 2 ? node[1] : null;
  if (head === "if") {
    const cond = node[1];
    if (cond === undefined || (isWatList(cond) && cond[0] === "result")) return null;
    const thenClause = node.find((n, k) => k >= 2 && isWatList(n) && n[0] === "then") as
      | WatNode[]
      | undefined;
    const elseClause = node.find((n, k) => k >= 2 && isWatList(n) && n[0] === "else") as
      | WatNode[]
      | undefined;
    if (!thenClause || !elseClause) return null;
    const nt = watBranchToValue(thenClause, rt);
    const ne = watBranchToValue(elseClause, rt);
    if (!nt || !ne) return null;
    return ["if", ["result", rt], cond, nt, ne];
  }
  return null;
}

/** Value the trailing node of a (then …) / (else …) clause; null if it can't be valued. */
function watBranchToValue(clause: WatNode[], rt: string): WatNode[] | null {
  const elems = clause.slice(1);
  if (elems.length === 0) return null;
  const li = elems.length - 1;
  const v = watNodeToValue(elems[li], rt);
  if (v === null) return null;
  elems[li] = v;
  return [clause[0], ...elems];
}

// Phase 41: WIT file generation helpers

/** Converts a WatType to the corresponding WIT value type. Returns null for void/never. */
function watTypeToWit(t: WatType | null): string | null {
  if (!t || t === "never") return null;
  switch (t) {
    case "i32":
      return "s32";
    case "i64":
      return "s64";
    case "f32":
      return "f32";
    case "f64":
      return "f64";
    case "bool":
      return "bool";
    case "string":
      return "string"; // Phase 50: emit WIT-native string type (bindgen reads this for ABI mapping)
    default:
      return "s32";
  }
}

/** Converts camelCase or snake_case identifiers to WIT kebab-case. */
function toKebabCase(s: string): string {
  return s
    .replace(/([a-z0-9])([A-Z])/g, "$1-$2")
    .replace(/_/g, "-")
    .toLowerCase();
}

/** Converts a WIT kebab-case name back to the original camelCase export name. */
function kebabToCamel(s: string): string {
  return s.replace(/-([a-z0-9])/g, (_m, c: string) => c.toUpperCase());
}

/** Inverse of watTypeToWit: maps a WIT value type back to the WatType used by wasic. */
function witTypeToWat(t: string): WatType {
  switch (t) {
    case "s32":
    case "u32":
      return "i32";
    case "s64":
    case "u64":
      return "i64";
    case "f32":
      return "f32";
    case "f64":
      return "f64";
    case "bool":
      return "bool";
    case "string":
      return "string";
    default:
      return "i32";
  }
}

/**
 * Parses an imported module's `.wit` interface to recover the *logical* signatures of its
 * exports (where wasic's ptr+len string ABI hides a `string` param behind two `i32`s in the
 * raw `.wasm` signature). Returns a map keyed by the canonical prefixed name
 * (`${prefix}_${exportName}`) so callers can patch the corresponding ExternalFuncDef.
 *
 * Without this, an exported `func(s: string)` reaches the importer as `(param i32 i32)` and a
 * string argument at the call site cannot be expanded to ptr+len — the call emits one value
 * for a two-param target ("not enough arguments on the stack"). The `.wit` is the interface
 * contract (Phase 41), so it is the authoritative source for the pre-ABI-expansion types.
 */
function parseWitLogicalSigs(
  witSrc: string,
  prefix: string,
): Map<string, { params: WatType[]; result: WatType | null }> {
  const out = new Map<string, { params: WatType[]; result: WatType | null }>();
  const re = /export\s+([\w-]+)\s*:\s*func\s*\(([^)]*)\)(?:\s*->\s*([\w-]+))?\s*;/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(witSrc)) !== null) {
    const exportName = kebabToCamel(m[1]);
    const rawParams = m[2].trim();
    const params: WatType[] = rawParams
      ? rawParams.split(",").map((p) => {
        const ci = p.indexOf(":");
        return witTypeToWat((ci !== -1 ? p.slice(ci + 1) : p).trim());
      })
      : [];
    const result: WatType | null = m[3] ? witTypeToWat(m[3].trim()) : null;
    out.set(`${prefix}_${exportName}`, { params, result });
  }
  return out;
}

/**
 * Reads the `.wit` sitting next to an imported `.wasm` (Phase 41 writes them as a pair) and
 * returns its logical export signatures. Returns an empty map if the file is absent —
 * callers then keep the raw `.wasm`-derived signature (correct for i32-only libraries).
 */
async function readWitLogicalSigs(
  wasmFilePath: string,
  prefix: string,
): Promise<Map<string, { params: WatType[]; result: WatType | null }>> {
  const witPath = wasmFilePath.replace(/\.wasm$/, ".wit");
  try {
    const witSrc = await rt.readTextFile(witPath);
    return parseWitLogicalSigs(witSrc, prefix);
  } catch {
    return new Map();
  }
}

/**
 * Overlays a `.wit`-derived logical signature onto an ExternalFuncDef in place. Only the
 * param count or any `string` param/result distinguishes the logical form from the raw
 * `.wasm` signature; for purely-numeric exports the overlay is a no-op. A mismatch in the
 * *number of raw i32 slots a string expands to* is the whole point — so we trust the `.wit`
 * when present and the names line up.
 */
function applyWitSig(
  ef: ExternalFuncDef,
  sigs: Map<string, { params: WatType[]; result: WatType | null }>,
): void {
  const sig = sigs.get(ef.name);
  if (!sig) return;
  // ExternalFuncDef.params is typed WasmWatType[] (numeric-only) but deliberately carries the
  // logical "string"/"bool" types via cast — the transpiler constructor re-casts to WatType.
  ef.params = sig.params as unknown as WasmWatType[];
  ef.result = sig.result as unknown as (WasmWatType | null);
}

interface FuncParam {
  name: string;
  type: WatType;
  defaultValue?: string; // default expression, e.g. "0" or "42"
  arrayElemType?: WatType; // set when param is an array pointer (T[])
  arrayStructElemType?: string; // struct type name when T[] is a struct array, e.g. "Person" for Person[]
  structType?: string; // set when param is a struct pointer (stores struct name, e.g. "Point")
  funcTypeInfo?: { params: WatType[]; result: WatType | null }; // set when param is a function type
  isRest?: boolean; // set when param is a rest parameter (...name: T[])
}

interface StructField {
  name: string;
  type: WatType;
  offset: number;
  size: number;
  /** Phase 21: field declared with `readonly` modifier — writes are a compile-time error. */
  readonly?: boolean;
  /** Phase 12: for method-type fields in interfaces — stores the function signature. */
  funcType?: { params: WatType[]; result: WatType | null };
  /** Phase 42: when this i32 field is a pointer to a named struct, stores the struct name. */
  structType?: string;
  /** Phase 21: when this field is an embedded tuple, names the tuple StructDef.
   *  Field bytes are stored inline (not as a pointer); access yields a tuple pointer. */
  tupleTypeName?: string;
}

interface StructDef {
  name: string;
  fields: StructField[];
  totalSize: number;
}

// Phase 32: discriminated union variant descriptor
interface DiscUnionVariant {
  tag: string; // literal string value (e.g. "circle")
  tagIndex: number; // integer stored in memory (0, 1, 2, …)
  fieldNames: Set<string>; // non-discriminant fields belonging to this variant
}

// Phase 32: discriminated union type descriptor
interface DiscUnionDef {
  name: string;
  discriminant: string; // the common literal-typed field (e.g. "kind")
  variants: DiscUnionVariant[];
}

interface ClassDef {
  name: string;
  struct: StructDef;
  methods: Array<
    {
      name: string;
      isStatic: boolean;
      isConstructor: boolean;
      isGetter?: boolean;
      isSetter?: boolean;
    }
  >;
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
  /** Phase 12: original TypeScript return type annotation (e.g. "MatrixManager") for interface dispatch. */
  resultTsName?: string;
  /** Phase 18: true for functions pre-registered from external .wasm imports. The real body is
   *  spliced in by mergeOneWasmImport; emitFunction must not emit any stub for these. */
  isPhase18Import?: boolean;
  /** Phase 5h: variables in a return-object that are shared across multiple closures AND mutated. */
  sharedMutableCaptures?: Set<string>;
  /** Phase 5h: captured params that are heap cell pointers (boxed) rather than plain values. */
  boxedCaptures?: Set<string>;
  /** For inner functions with mutable captures: maps capture name → {type, offset} in the closure struct.
   *  When set, the inner function takes $__closure_ptr (i32) as its first param and accesses
   *  mutable captures via f64.load/f64.store (or i32.load/i32.store) through the closure pointer. */
  closureCaptureLayout?: Map<string, { type: WatType; offset: number }>;
}

/** Maps TypeScript type annotation strings to WAT types (or the "string"/"never" pseudo-types).
 *  "void" is handled by callers before mapType is invoked and never reaches this function. */
function mapType(ts: string): WatType {
  // Phase 35: keyof T in type annotation positions → string (compile-time key type resolves to string)
  if (/^keyof\s+\w+/.test(ts.trim())) return "string";
  // Strip union null/undefined modifiers: "string | null" → "string", "T | undefined" → "T"
  const stripped = ts.split("|").map((p) => p.trim()).filter((p) =>
    p !== "null" && p !== "undefined"
  );
  const base = (stripped[0] ?? ts).trim();
  // Array type annotation T[] → i32 pointer
  if (base.endsWith("[]")) return "i32";
  // Phase 23: tuple type annotation [T1, T2, ...] → i32 pointer (struct layout)
  if (base.startsWith("[")) return "i32";
  const t = base.toLowerCase();
  if (t === "never") return "never"; // Phase 21: never → unreachable at end of body
  // Note: "void" is intercepted at each call site before mapType is invoked; it never reaches here.
  if (t === "i32" || t === "int") return "i32";
  if (t === "i64") return "i64";
  if (t === "f32") return "f32";
  if (t === "bigint") return "i64";
  if (t === "bool" || t === "boolean") return "bool"; // boolean → bool pseudo-type (WAT i32)
  if (t === "string" || t === "str") return "string"; // pseudo-type: ptr+len i32 locals
  // Phase 23: synthetic tuple StructDef name → i32 pointer
  if (base.startsWith("__Tuple_")) return "i32";
  // PascalCase identifier = interface/class/struct pointer (i32). Guard known primitives.
  if (
    /^[A-Z]/.test(base) && base !== "Number" && base !== "Boolean" && base !== "String" &&
    base !== "BigInt"
  ) return "i32";
  return "f64"; // number, f64, or unknown → f64
}

/** Phase 31: Returns element access info for a TypedArray constructor name, or undefined if not a TypedArray. */
function getTypedArrayInfo(
  name: string,
):
  | { elemType: WatType; loadOp: string; storeOp: string; shift: number; bytesPerElem: number }
  | undefined {
  switch (name) {
    case "Int8Array":
      return {
        elemType: "i32",
        loadOp: "i32.load8_s",
        storeOp: "i32.store8",
        shift: 0,
        bytesPerElem: 1,
      };
    case "Uint8Array":
      return {
        elemType: "i32",
        loadOp: "i32.load8_u",
        storeOp: "i32.store8",
        shift: 0,
        bytesPerElem: 1,
      };
    case "Int16Array":
      return {
        elemType: "i32",
        loadOp: "i32.load16_s",
        storeOp: "i32.store16",
        shift: 1,
        bytesPerElem: 2,
      };
    case "Uint16Array":
      return {
        elemType: "i32",
        loadOp: "i32.load16_u",
        storeOp: "i32.store16",
        shift: 1,
        bytesPerElem: 2,
      };
    case "Int32Array":
      return {
        elemType: "i32",
        loadOp: "i32.load",
        storeOp: "i32.store",
        shift: 2,
        bytesPerElem: 4,
      };
    case "Uint32Array":
      return {
        elemType: "i32",
        loadOp: "i32.load",
        storeOp: "i32.store",
        shift: 2,
        bytesPerElem: 4,
      };
    case "Float32Array":
      return {
        elemType: "f32",
        loadOp: "f32.load",
        storeOp: "f32.store",
        shift: 2,
        bytesPerElem: 4,
      };
    case "Float64Array":
      return {
        elemType: "f64",
        loadOp: "f64.load",
        storeOp: "f64.store",
        shift: 3,
        bytesPerElem: 8,
      };
    default:
      return undefined;
  }
}

/** Phase 24: Detects T|null or T|undefined union annotation; returns the inner WAT type or null.
 *  Returns null if the annotation is not a nullable union, or if the union has more than one
 *  non-null/non-undefined member (complex unions are not supported). */
function parseNullableAnnotation(ts: string): WatType | null {
  const parts = ts.split("|").map((p) => p.trim());
  if (parts.length < 2) return null;
  const nonNull = parts.filter((p) => p !== "null" && p !== "undefined");
  if (nonNull.length === parts.length || nonNull.length !== 1) return null;
  return mapType(nonNull[0]);
}

/** Encodes a 32-bit integer as 4 little-endian WAT escape bytes. */
function encodeI32LE(val: number): string {
  const v = (val | 0) >>> 0;
  return [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]
    .map((b) => `\\${b.toString(16).padStart(2, "0")}`).join("");
}

/** Encodes a 64-bit float as 8 little-endian WAT escape bytes. */
function encodeF64LE(val: number): string {
  const buf = new ArrayBuffer(8);
  new DataView(buf).setFloat64(0, val, true);
  return Array.from(new Uint8Array(buf)).map((b) => `\\${b.toString(16).padStart(2, "0")}`).join(
    "",
  );
}

/** Phase 6d: Parses a nested array literal "[[1,2],[3,4]]" → [["1","2"],["3","4"]]. */
function parse2DArrayLiteral(str: string): string[][] {
  const s = str.trim();
  if (!s.startsWith("[")) return [];
  const inner = s.slice(1, s.lastIndexOf("]")).trim();
  const rows: string[][] = [];
  let depth = 0;
  let rowStart = -1;
  for (let i = 0; i < inner.length; i++) {
    if (inner[i] === "[") {
      if (depth === 0) rowStart = i + 1;
      depth++;
    } else if (inner[i] === "]") {
      depth--;
      if (depth === 0 && rowStart !== -1) {
        rows.push(
          inner.slice(rowStart, i).split(",").map((e) => e.trim()).filter((e) => e.length > 0),
        );
        rowStart = -1;
      }
    }
  }
  return rows;
}

/**
 * Phase 42: Extracts the body of a balanced `{ ... }` object literal.
 * `startIdx` must point at the opening `{`. Returns the inner content (between braces),
 * or null if the braces are unbalanced.
 */
function extractOuterObjectBody(line: string, startIdx: number): string | null {
  let depth = 0;
  for (let i = startIdx; i < line.length; i++) {
    if (line[i] === "{") depth++;
    else if (line[i] === "}") {
      depth--;
      if (depth === 0) return line.slice(startIdx + 1, i);
    }
  }
  return null;
}

/**
 * Phase 42: Splits an object literal body string into a key→value map using
 * depth-0 comma separation. Handles nested `{ ... }` and `[ ... ]` in values.
 */
function parseDepth0Fields(body: string): Record<string, string> {
  const result: Record<string, string> = {};
  let depth = 0;
  let start = 0;
  for (let i = 0; i <= body.length; i++) {
    const ch = i < body.length ? body[i] : ",";
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      const pair = body.slice(start, i).trim();
      const ci = pair.indexOf(":");
      if (ci !== -1) {
        const key = pair.slice(0, ci).trim();
        const val = pair.slice(ci + 1).trim();
        if (key && /^\w+$/.test(key)) result[key] = val;
      }
      start = i + 1;
    }
  }
  return result;
}

/** Like parseDepth0Fields but also handles shorthand properties: { key } → key: key. */
function parseDepth0FieldsWithShorthand(body: string): Record<string, string> {
  const result: Record<string, string> = {};
  let depth = 0;
  let start = 0;
  for (let i = 0; i <= body.length; i++) {
    const ch = i < body.length ? body[i] : ",";
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      const pair = body.slice(start, i).trim();
      const ci = pair.indexOf(":");
      if (ci !== -1) {
        const key = pair.slice(0, ci).trim();
        const val = pair.slice(ci + 1).trim();
        if (key && /^\w+$/.test(key)) result[key] = val;
      } else {
        // Shorthand property: identifier with no colon means key === value
        const key = pair.trim();
        if (key && /^\w+$/.test(key)) result[key] = key;
      }
      start = i + 1;
    }
  }
  return result;
}

/** Phase 51.2: Parse an object-literal body that may contain a spread element `...source`.
 *  Returns the spread source variable (last one wins; null if none) and the explicit
 *  field overrides (named `k: v` and shorthand `k`). Spread tokens are excluded from `fields`. */
function parseStructLiteralWithSpread(
  body: string,
): { spreadSource: string | null; fields: Record<string, string> } {
  const fields: Record<string, string> = {};
  let spreadSource: string | null = null;
  for (const tok of splitBraceAwareCommas(body)) {
    const t = tok.trim();
    if (!t) continue;
    const sp = t.match(/^\.\.\.(\w+)$/);
    if (sp) {
      spreadSource = sp[1];
      continue;
    }
    const ci = t.indexOf(":");
    if (ci !== -1) {
      const key = t.slice(0, ci).trim();
      const val = t.slice(ci + 1).trim();
      if (/^\w+$/.test(key)) fields[key] = val;
    } else if (/^\w+$/.test(t)) {
      fields[t] = t; // shorthand property
    }
  }
  return { spreadSource, fields };
}

/** Phase 51.3: parse a destructuring function parameter `{ a, b }: Type` or `[a, b]: Type`.
 *  Returns the bracket style, the inner binding list (verbatim, so renames/defaults survive), and
 *  the type annotation (trailing `= default` stripped). Returns null if `p` is not a destructuring
 *  pattern or is malformed (unbalanced / missing `: Type`). Uses balanced-bracket scanning so a
 *  nested pattern's inner braces don't terminate the match early. */
function parseDestructParam(
  p: string,
): { open: "{" | "["; close: "}" | "]"; inner: string; type: string } | null {
  const t = p.trim();
  if (t[0] !== "{" && t[0] !== "[") return null;
  const open = t[0] as "{" | "[";
  const close = open === "{" ? "}" : "]";
  let depth = 0;
  let ci = -1;
  for (let k = 0; k < t.length; k++) {
    const ch = t[k];
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") {
      depth--;
      if (depth === 0) {
        ci = k;
        break;
      }
    }
  }
  if (ci === -1) return null;
  const inner = t.slice(1, ci).trim();
  const rest = t.slice(ci + 1).trim();
  if (!rest.startsWith(":")) return null;
  const type = rest.slice(1).trim().replace(/\s*=.*$/, "").trim();
  if (!inner || !type) return null;
  return { open, close, inner, type };
}

/** Splits a comma-separated string respecting curly-brace and bracket nesting.
 *  Use instead of `.split(",")` when elements may be struct/object literals. */
function splitBraceAwareCommas(s: string): string[] {
  const result: string[] = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      const part = s.slice(start, i).trim();
      if (part.length > 0) result.push(part);
      start = i + 1;
    }
  }
  const last = s.slice(start).trim();
  if (last.length > 0) result.push(last);
  return result;
}

/** Like splitBraceAwareCommas but PRESERVES empty elements — needed for positional destructuring
 *  gaps (`[a, , c]` must keep index 1 empty so `c` reads index 2). (Phase 51.3) */
function splitBraceAwareCommasKeepEmpty(s: string): string[] {
  const result: string[] = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      result.push(s.slice(start, i).trim());
      start = i + 1;
    }
  }
  result.push(s.slice(start).trim());
  return result;
}

/** Advances past a string literal starting at s[i] (a quote char); returns the index just after
 *  the closing quote. Handles `\` escapes. Used by the bracket/comma scanners below. */
function skipStringLiteral(s: string, i: number): number {
  const q = s[i];
  i++;
  while (i < s.length) {
    if (s[i] === "\\") {
      i += 2;
      continue;
    }
    if (s[i] === q) return i + 1;
    i++;
  }
  return i;
}

/** Returns a boolean array marking every index of `s` that lies inside a string or template
 *  literal (the surrounding quotes included), so depth/operator scanners can skip literal
 *  content. Handles `"`, `'`, `` ` `` and `\` escapes. (A nested `${…}` inside a template is
 *  treated as part of the literal — fine for top-level operator/bracket scanning.) */
function buildStringLiteralMask(s: string): boolean[] {
  const mask = new Array<boolean>(s.length).fill(false);
  let q: string | null = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q !== null) {
      mask[i] = true;
      if (c === "\\") {
        if (i + 1 < s.length) mask[i + 1] = true;
        i++;
        continue;
      }
      if (c === q) q = null;
    } else if (c === '"' || c === "'" || c === "`") {
      q = c;
      mask[i] = true;
    }
  }
  return mask;
}

/** Net `[`…`]` depth of `s`, IGNORING brackets inside string/template literals. Used by the
 *  multi-line array-literal body joiners — without skipping literals, a `let s = "["` was treated
 *  as an unclosed array and the following statement got joined onto it (silently breaking it). */
function netSquareBracketDepth(s: string): number {
  const mask = buildStringLiteralMask(s);
  let d = 0;
  for (let i = 0; i < s.length; i++) {
    if (mask[i]) continue;
    if (s[i] === "[") d++;
    else if (s[i] === "]") d--;
  }
  return d;
}

/** Given s[openIdx] === "<", returns the index of the matching ">" respecting nested <...>.
 *  Used by Phase 51.4 utility-type expansion (type positions only — no comparison operators). */
function matchAngleBracket(s: string, openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < s.length; i++) {
    if (s[i] === "<") depth++;
    else if (s[i] === ">") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** Given s[openIdx] === "[", returns the index of the matching "]" respecting nested
 *  ()/[]/{} and string literals; -1 if unbalanced. */
function findMatchingBracketAware(s: string, openIdx: number): number {
  let depth = 0;
  let i = openIdx;
  while (i < s.length) {
    const ch = s[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipStringLiteral(s, i);
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") {
      depth--;
      if (depth === 0) return i;
    }
    i++;
  }
  return -1;
}

/** Splits a class body into member "lines" (field declarations and whole method definitions),
 *  respecting nested ()/[]/{} and string literals. Splits at depth-0 `;`, depth-0 newlines, and
 *  immediately after a depth-0 `}` (a method body's close). This makes field parsing work whether
 *  members are newline-separated, semicolon-separated, or all on one physical line (the
 *  single-physical-line class form). Comments are already stripped from the source before this
 *  runs (see stripComments in transpile), so no comment handling is needed here. */
function splitClassMemberLines(body: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let start = 0;
  let i = 0;
  while (i < body.length) {
    const ch = body[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipStringLiteral(body, i);
      continue;
    }
    if (ch === "{" || ch === "(" || ch === "[") {
      depth++;
      i++;
      continue;
    }
    if (ch === "}" || ch === ")" || ch === "]") {
      depth--;
      i++;
      if (depth === 0 && ch === "}") {
        out.push(body.slice(start, i)); // whole method member, incl. its closing brace
        start = i;
      }
      continue;
    }
    if (depth === 0 && (ch === ";" || ch === "\n")) {
      out.push(body.slice(start, i));
      start = i + 1;
      i++;
      continue;
    }
    i++;
  }
  if (start < body.length) out.push(body.slice(start));
  return out.map((l) => l.trim()).filter((l) => l.length > 0);
}

/** Splits on top-level commas, respecting nested ()/[]/{} and string literals (unlike
 *  splitBraceAwareCommas, which is not string-aware). */
function splitTopLevelCommasStringAware(s: string): string[] {
  const result: string[] = [];
  let depth = 0;
  let start = 0;
  let i = 0;
  while (i < s.length) {
    const ch = s[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      i = skipStringLiteral(s, i);
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") depth--;
    else if (ch === "," && depth === 0) {
      const part = s.slice(start, i).trim();
      if (part.length > 0) result.push(part);
      start = i + 1;
    }
    i++;
  }
  const last = s.slice(start).trim();
  if (last.length > 0) result.push(last);
  return result;
}

/** Returns the WAT zero-literal for a given type. */
function zeroOf(t: WatType): string {
  if (t === "string" || t === "bool") return "(i32.const 0)";
  return t === "f64" ? "(f64.const 0)" : t === "f32" ? "(f32.const 0)" : `(${t}.const 0)`;
}

/** True if `line` has a top-level `;` (bracket+string-aware over `()[]{}`) with non-whitespace
 *  content AFTER it — i.e. a genuine multi-statement line (`a; b`), NOT a single statement, a
 *  trailing-`;` statement, or an array/object-literal fragment (`const x = [`, `{ a: 1 },`). Used
 *  to decide whether a module-level line should be split via splitStmts (which only tracks `(){}`
 *  and would corrupt `[`-fragments). */
function hasMultipleTopLevelStatements(line: string): boolean {
  let d = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"' || c === "'" || c === "`") {
      const q = c;
      i++;
      while (i < line.length && line[i] !== q) {
        if (line[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "(" || c === "[" || c === "{") d++;
    else if (c === ")" || c === "]" || c === "}") d--;
    else if (c === ";" && d === 0 && line.slice(i + 1).trim().length > 0) return true;
  }
  return false;
}

/** Returns true if no prefix of s has more ')'/']' than '('/'[' — guards greedy regex matches. */
function parenDepthNeverNegative(s: string): boolean {
  let d = 0;
  for (const ch of s) {
    if (ch === "(" || ch === "[") d++;
    else if (ch === ")" || ch === "]") { if (--d < 0) return false; }
  }
  return true;
}

/** Splits a string of two consecutive top-level WAT S-expressions into [first, second].
 *  E.g. "(local.get $a_ptr) (local.get $a_len)" → ["(local.get $a_ptr)", "(local.get $a_len)"]
 */
function splitTwoWatExprs(s: string): [string, string] {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0) return [s.slice(0, i + 1).trim(), s.slice(i + 1).trim()];
    }
  }
  return [s, ""];
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
  functions?: FuncDef[],
): WatType {
  const e = initExpr.trim();
  // Phase 35: typeof x → the typeof operator always produces a string value
  if (/^typeof\s+\w+$/.test(e)) return "string";
  // 0. boolean literals
  if (e === "true" || e === "false") return "bool";
  // 1. bigint literal
  if (/^-?\d+n$/.test(e)) return "i64";
  // 2. contains a comparison or logical operator → boolean
  if (/===|!==|==|!=|<=|>=|<|>|&&|\|\||^!/.test(e)) return "bool";
  if (e.startsWith("!")) return "bool";
  // 2b. string-producing expressions
  if (e.startsWith('"') || e.startsWith("'")) return "string"; // string literal or concat
  if (/^String\s*\(/.test(e)) return "string"; // String(n)
  if (/^\w+\.toString\s*\(.*\)$/.test(e)) return "string"; // n.toString() / n.toString(radix)
  // str.slice(...) — only if receiver is a known string var (checked at call sites; hint here)
  const sliceLeadId = e.match(/^(\w+)\.slice\s*\(/)?.[1];
  if (sliceLeadId && locals.get(sliceLeadId) === "string") return "string";
  // 3. leading identifier has a known declared type — inherit it
  const leadId = e.match(/^(\w+)/)?.[1];
  if (leadId) {
    const t = locals.get(leadId);
    if (t) return t;
  }
  // 4. function call — infer from return type of known function
  const callMatch = e.match(/^(\w+)\s*\(/);
  if (callMatch && functions) {
    const fn = functions.find((f) => f.name === callMatch[1]);
    if (fn?.result) return fn.result;
  }
  // 4b. dot-call: Receiver.method(args) — look up prefixed function name
  const dotCallMatch = e.match(/^(\w+)\.(\w+)\s*\(/);
  if (dotCallMatch && functions) {
    const prefixedName = `${dotCallMatch[1]}_${dotCallMatch[2]}`;
    const fn = functions.find((f) => f.name === prefixedName);
    if (fn?.result) return fn.result;
  }
  // 5. enum member access
  if (/^\w+\.\w+$/.test(e) && enumValues.has(e)) return "i32";
  // plain integer literal (no decimal, no n suffix) → i32 (typical loop counter)
  if (/^-?\d+$/.test(e)) return "i32";
  return "f64";
}

/** Strips JS/TS comments from source, respecting string literals. */
function stripComments(src: string): string {
  let result = "";
  let i = 0;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '"' || ch === "'") {
      // String literal — copy verbatim until matching unescaped closing quote
      result += src[i++];
      while (i < src.length) {
        const sc = src[i];
        if (sc === "\\") {
          result += src[i++];
          if (i < src.length) result += src[i++];
          continue;
        }
        result += src[i++];
        if (sc === ch) break;
      }
    } else if (ch === "`") {
      // Template literal — copy verbatim until closing backtick (no nested ${} handling needed)
      result += src[i++];
      while (i < src.length) {
        const sc = src[i];
        if (sc === "\\") {
          result += src[i++];
          if (i < src.length) result += src[i++];
          continue;
        }
        result += src[i++];
        if (sc === "`") break;
      }
    } else if (ch === "/" && src[i + 1] === "/") {
      // Line comment — skip to end of line
      while (i < src.length && src[i] !== "\n") i++;
    } else if (ch === "/" && src[i + 1] === "*") {
      // Block comment — skip to */
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++;
      if (i < src.length) i += 2;
    } else {
      result += src[i++];
    }
  }
  return result;
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
  private dataOffset = this.scratchBase + 4 * 32; // DATA_BASE = SCRATCH_BASE + SCRATCH_SLOTS*32 = 260

  /** End of the static data section after transpilation — used by Phase 18 merge. */
  get dataEnd(): number {
    return this.dataOffset;
  }
  private hasConsoleLog = false;
  private needsNumericHelpers = false;
  private needsStringHelpers = false;
  private needsStringOpHelpers = false;
  private needsStringExtHelpers = false; // Phase 27: trim/charCodeAt/case/replace/pad/repeat/split
  private needsStrGatherHelper = false;
  private needsArrPrintHelper = false;
  private needsJoinHelper = false;
  private needsMatrix2DPrintHelper = false; // Phase 6d

  // String data section: message → [offset, byteLength]
  // Raw (non-string) data segments for arrays etc.
  private rawDataSegments: Array<{ ptr: number; bytes: string }> = [];
  // Per-function array variable tracking: varName → { elemType, ptr, length, dynamic?, capacity?, initElements? }
  // ptr=-1: runtime param pointer. ptr=-2: dynamic heap array (ptr in local). ptr>=0: static data address.
  // Reset at the start of each emitFunction call; module-level entries are re-seeded from moduleArrayVars.
  private arrayVars: Map<string, {
    elemType: WatType;
    ptr: number;
    length: number;
    dynamic?: boolean;
    capacity?: number;
    initElements?: string[];
    is2D?: boolean;
    rows?: string[][]; // Phase 6d: i32[][] multi-dimensional array
    arrayFromExpr?: string; // Phase 18 fix: Array.from({ length: N }, () => []) runtime init
    isStringArr?: boolean; // Phase 27: string[] from split() — 8-byte (ptr,len) elements
    structTypeName?: string; // struct element type name for arr[i].field access
    isFuncPtrArr?: { params: WatType[]; result: WatType | null }; // Phase 44: Array<FuncType>
  }> = new Map();

  // Module-level array registrations — populated during startBodyLines pre-scan and never reset.
  // Copied into arrayVars at the start of each emitFunction so functions can access global arrays.
  private moduleArrayVars: Map<string, {
    elemType: WatType;
    ptr: number;
    length: number;
    dynamic?: boolean;
    capacity?: number;
    initElements?: string[];
    is2D?: boolean;
    rows?: string[][];
    arrayFromExpr?: string; // Phase 18 fix: Array.from({ length: N }, () => []) runtime init
    isStringArr?: boolean;
    structTypeName?: string;
    isFuncPtrArr?: { params: WatType[]; result: WatType | null }; // Phase 44: Array<FuncType>
  }> = new Map();

  // Phase 31: typed array variable tracking: varName → {taType, elemType, loadOp, storeOp, shift, bytesPerElem, length}
  // Always held in a local (ptr-2 semantics). Reset at the start of each emitFunction call.
  private typedArrayVars: Map<
    string,
    {
      taType: string;
      elemType: WatType;
      loadOp: string;
      storeOp: string;
      shift: number;
      bytesPerElem: number;
      length: number;
    }
  > = new Map();
  // Phase 31: which TypedArray WAT helper functions are needed. Key format: "fill_i32", "fill_f64".
  private typedArrHelpers: Set<string> = new Set();

  // Tracks which dynamic-array WAT helper functions are needed for this module.
  // Key format: "push_i32", "pop_f64", "shift_i32", "unshift_f64", etc.
  private dynArrHelpers: Set<string> = new Set();

  // Tracks variables assigned from arr.find() calls so console.log can print "undefined"
  // (matching TypeScript semantics) when the not-found sentinel is returned.
  // Reset at the start of each emitFunction call.
  private findResultVars: Set<string> = new Set();

  // Tracks catch exception binding names (e.g. `catch (e)` → "e").
  // Used so String(e) can emit "Error: " + e instead of treating e as a number.
  // Reset at the start of each emitFunction call and startBodyLines processing.
  private catchVarNames: Set<string> = new Set();

  // Tracks catch variable names that shadow an outer string variable of the same name.
  // When a catch var shadows, an alias local ($__catch_cv) is used so the outer is preserved.
  // Reset at the start of each emitFunction call and startBodyLines processing.
  private catchVarShadows: Set<string> = new Set();

  // Set to true when any throw/try/catch is emitted; causes (tag $__exn_tag) to be emitted.
  private needsExceptionTag = false;

  // Phase 38: set when any extended math helper (sin/cos/log/exp/…) is used.
  private needsMathLib38 = false;
  /** True when the compiled module calls any Phase 38 Math.* function (sin/cos/exp/log/…). */
  get needsMathLib(): boolean {
    return this.needsMathLib38;
  }

  // Compilation mode: "wasi" emits _start + WASI scaffolding; "library" emits only export functions.
  private mode: "wasi" | "library" = "wasi";

  // Struct type definitions parsed from interface/type declarations.
  private structDefs: Map<string, StructDef> = new Map();
  // Phase 32: discriminated union definitions: typeName → DiscUnionDef
  private discUnionDefs: Map<string, DiscUnionDef> = new Map();
  // Per-function struct variable tracking: varName → { def, ptr }
  // ptr=-1 means the struct comes from a parameter (runtime pointer); ptr>=0 is a static address.
  // Reset at the start of each emitFunction call.
  private structVars: Map<string, { def: StructDef; ptr: number }> = new Map();

  // Class definitions (Phase 9): className → ClassDef
  private classDefs: Map<string, ClassDef> = new Map();
  // Phase 47: derived class name → base class name (populated by parseClasses)
  private classInheritance: Map<string, string> = new Map();
  // Phase 47: className → integer tag (1, 2, ...) assigned when any class uses extends
  private classTags: Map<string, number> = new Map();
  // Phase 47: 4 when any class in this module uses extends (all classes get a 4-byte tag header), 0 otherwise.
  private classHeaderSize: number = 0;
  // Per-function class instance variable tracking: varName → { className, ptr }
  // ptr=-1 means the instance comes from a parameter (runtime pointer); ptr>=0 is static address.
  // Reset at the start of each emitFunction call.
  private classVars: Map<string, { className: string; ptr: number }> = new Map();
  // Set to the class name when emitting an instance method body (for `this.field` resolution).
  private currentMethodClass: string | null = null;
  // Set to the WAT function name of the method currently being emitted (Phase 21: constructor check).
  private currentMethodName: string | null = null;
  // Phase 12: original TS return type name of the function currently being emitted (for return {} dispatch).
  private currentFuncResultTsName: string | null = null;
  // Phase 12: interface-typed variables in the current function scope: varName → interfaceName.
  private interfaceVars: Map<string, string> = new Map();
  // Phase 5h: boxed captures for the arrow function currently being emitted (pointers, not values).
  private currentBoxedCaptures: Set<string> = new Set();
  // Phase 5h: shared mutable captures for the enclosing factory function currently being emitted.
  private currentSharedMutableCaptures: Set<string> = new Set();
  // Mutable closure captures for the inner function currently being emitted: name → {type, offset}.
  private currentClosureCaptureLayout: Map<string, { type: WatType; offset: number }> = new Map();

  // Tracks which Math.* WAT helper functions are needed (emitted on demand)
  private mathHelpers: Set<string> = new Set();

  // Tracks variable names declared with type "string" (stored as ptr+len i32 locals)
  private stringVars: Set<string> = new Set();
  // Tracks variable names declared with a function type (e.g. let f: (a: i32) => i32)
  // Stored as Map<name, signature> — the i32 local holds the funcref table index.
  private funcTypeVars: Map<string, { params: WatType[]; result: WatType | null }> = new Map();
  // Named function type aliases: "Scaler" → {params:[i32], result:i32}  (from `type Scaler = (v:i32)=>i32`)
  private namedFuncTypeAliases: Map<string, { params: WatType[]; result: WatType | null }> =
    new Map();
  // Closure-typed locals/params: variables that hold heap-allocated closure struct pointers (not bare funcrefs).
  // Dispatch via trampoline: call_indirect (type $tramp) ptr args (i32.load ptr)
  private closureTypedVars: Map<string, { params: WatType[]; result: WatType | null }> = new Map();
  // funcref table: function name → table slot index (assigned lazily as functions are used as values)
  private funcTable: Map<string, number> = new Map();
  // Unique function type signatures for call_indirect: "i32,i32->i32" → "$ftype_i32_i32_r_i32"
  private funcTypes: Map<string, string> = new Map();
  // Counter for synthetic anonymous arrow function names
  private anonArrowCounter = 0;
  // Diagnostics emitted during transpilation for unsupported/unrecognised patterns.
  private diagnostics: string[] = [];
  /** Diagnostics collected during the last transpile() call. */
  get warnings(): readonly string[] {
    return this.diagnostics;
  }
  // When > 0, the terminal "give-up" fallbacks in emitExpr / emitStringPtrLen suppress their
  // unsupported-feature diagnostic. Used to wrap SPECULATIVE / guarded calls — sites that probe
  // the emitter and recover gracefully when it returns a stub/sentinel (so a fallback there is
  // expected, not a hard error). Every other caller passes the stub straight through, so its
  // terminal fallback DOES record a diagnostic (which aborts the compile — better than silently
  // emitting 0 / the empty string). Use the quietEmit() wrapper to scope a suppression.
  private emitDiagSuppressDepth = 0;
  /** Runs `fn` with terminal emit diagnostics suppressed (for speculative/guarded probes). */
  private quietEmit<T>(fn: () => T): T {
    this.emitDiagSuppressDepth++;
    try {
      return fn();
    } finally {
      this.emitDiagSuppressDepth--;
    }
  }
  // Enum member name lookup: "EnumName.MemberName" → i32 value
  private enumValues: Map<string, number> = new Map();
  // Phase 29: string-valued enum members: "EnumName.MemberName" → string value
  private enumStringValues: Map<string, string> = new Map();
  private loopCounter = 0;
  // Stack of { breakLabel, continueLabel? } entries for break/continue emission.
  // switch pushes only breakLabel; loops push both.
  private controlStack: Array<{ breakLabel: string; continueLabel?: string }> = [];
  // When a label precedes a loop/block ("outer: for ..."), the label is stored here
  // so the next loop handler can use it as the WAT label name instead of a counter.
  private pendingLabel: string | null = null;

  // Top-level statements that become the _start body (patterns 2–4)
  private startBodyLines: string[] = [];

  // Phase 24: variables declared as T|null/T|undefined — varName → inner WAT type.
  // Only value types (i32/f64/bool/i64) are tracked here; they get a companion
  // $varName__null local (i32, 1=is-null, 0=has-value).
  // Reference types (string, struct, array) use 0-pointer as the null sentinel.
  // Reset at the start of each emitFunction call and before the _start body pre-scan.
  private nullableVarInnerType: Map<string, WatType> = new Map();
  // Phase 24: functions returning T|null — funcName → inner WAT type.
  private nullableFuncReturnType: Map<string, WatType> = new Map();
  // Phase 24: set to true when the function currently being emitted returns T|null.
  private currentFuncIsNullableReturn = false;
  // Phase 24: set to true when any nullable-return function is compiled — triggers
  // emission of the $__nullable_ret_flag global in the WAT module.
  private needsNullableResultFlag = false;
  // String-return side channel: set to true when any user-defined string-returning
  // function is compiled — triggers emission of $__str_ret_ptr and $__str_ret_len globals.
  private needsStringRetGlobals = false;

  // Module-level scalar globals (const/let/var at top level): varName → { type, mutable, initExpr }
  private moduleGlobals = new Map<string, { type: WatType; mutable: boolean; initExpr: string }>();
  // Module-level string constants: varName → [dataOffset, byteLen] — pre-allocated in data section
  private moduleStringConsts = new Map<string, [number, number]>();
  // Module-level MUTABLE string globals: varName → initial [ptr, len]. Emitted as a pair of
  // mutable i32 globals ($name_ptr / $name_len) so a `let`/`var` string reassigned inside a
  // function persists across calls (e.g. `let message = ""; send()` writes it, `receive()` reads).
  private moduleStringGlobals = new Map<string, { ptr: number; len: number }>();

  // Phase 30: namespace names (populated by expandNamespaces before any parse pass)
  private namespaceDefs: Set<string> = new Set();
  // Phase 30: runtime field initializers for struct literals with non-constant values
  // varName → { fieldName: exprString } — emitted as store instructions after local.set $p
  private structVarRuntimeInits: Map<string, Record<string, string>> = new Map();
  // Phase 51.2: object spread — varName → spread-source var name for `const r: T = { ...src, k: v }`.
  // Marks struct-let vars whose value is built at runtime by copying a base struct then applying
  // overrides; the pre-scan sets ptr=-3 (heap) and the emit path routes to emitRuntimeStructLiteral.
  private structSpreadVars: Map<string, string> = new Map();
  // Phase 34: type predicate functions: funcName → { paramName, targetType }
  // These functions return bool (i32) and annotate narrowing via "param is Type" return syntax.
  private typePredicateFuncs: Map<string, { paramName: string; targetType: string }> = new Map();

  // Phase 40: external interface declarations via `declare const varName: { method(params): retType }`
  // externalInterfaceTypes: interfaceName → methodName → { params, result }
  private externalInterfaceTypes: Map<
    string,
    Map<string, { params: WatType[]; result: WatType | null }>
  > = new Map();
  // externalBindings: varName → interfaceName
  private externalBindings: Map<string, string> = new Map();
  // usedExternalMethods: "$varName_method" → sig (populated during emission; drives WAT import generation)
  private usedExternalMethods: Map<string, { params: WatType[]; result: WatType | null }> =
    new Map();

  constructor(
    source: string,
    mode: "wasi" | "library" = "wasi",
    externalFuncs: ExternalFuncDef[] = [],
  ) {
    this.src = stripComments(source);
    this.mode = mode;
    // Register imported WASM functions so call-site type inference works correctly.
    for (const ef of externalFuncs) {
      this.functions.push({
        name: ef.name,
        params: ef.params.map((t, i) => ({ name: `p${i}`, type: t as WatType })),
        result: ef.result as WatType | null,
        exported: false,
        bodyLines: [],
        isPhase18Import: true, // mergeOneWasmImport splices the real body; skip stub emission
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
    // Normalize pseudo-types; string params expand to two i32 values (ptr + len)
    const normParams = params.flatMap((p) =>
      p === "string"
        ? ["i32", "i32"] as WatType[]
        : (p === "bool" || p === "never")
        ? ["i32" as WatType]
        : [p]
    );
    const normResult = result === "bool" || result === "string"
      ? "i32"
      : result === "never"
      ? null
      : result;
    const key = (normParams.length ? normParams.join(",") : "void") + "->" + (normResult ?? "void");
    if (!this.funcTypes.has(key)) {
      const pStr = normParams.length ? normParams.join("_") : "void";
      this.funcTypes.set(key, `$ftype_${pStr}_r_${normResult ?? "void"}`);
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
      ? rawInner.split(",").map((ip) => {
        ip = ip.trim();
        const ci = ip.indexOf(":");
        return (ci !== -1 ? mapType(ip.slice(ci + 1).trim()) : "i32") as WatType;
      }).filter(Boolean)
      : [];
    return { params, result };
  }

  /** Scans source for `type Alias = (params) => RetType` and populates namedFuncTypeAliases. */
  private parseNamedFuncTypeAliases(): void {
    const re = /type\s+(\w+)\s*=\s*(\([^)]*\)\s*=>\s*\w+)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(this.src)) !== null) {
      this.namedFuncTypeAliases.set(m[1], this.parseFuncTypeSig(m[2]));
    }
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
      fn.bodyLines = fn.bodyLines.map((line) => {
        // Loop until stable — handles multiple arrows on one line (e.g. object literal returns)
        let prev = "";
        while (prev !== line) {
          prev = line;
          line = this.substituteOneArrow(line, bodyFuncTypes, fn);
        }
        return line;
      });
    }
    this.startBodyLines = this.startBodyLines.map((line) => {
      let prev = "";
      while (prev !== line) {
        prev = line;
        line = this.substituteOneArrow(line, new Map());
      }
      return line;
    });
  }

  /** Phase 44: Second arrow-lifting pass for startBodyLines, run after parseTopLevel().
   *  Passes a synthetic _start FuncDef so capturing closures in top-level code
   *  (e.g. `defer(() => console.log(n))`) can detect their outer-scope captures. */
  private liftStartBodyArrows(): void {
    if (this.startBodyLines.length === 0) return;
    const syntheticStart: FuncDef = {
      name: "_start",
      params: [],
      result: null,
      exported: true,
      bodyLines: [...this.startBodyLines],
    };
    const bodyFuncTypes = new Map<string, { params: WatType[]; result: WatType | null }>();
    for (const line of this.startBodyLines) {
      const m = line.match(/^(?:let|const|var)\s+(\w+)\s*:\s*(\([^)]*\)\s*=>\s*\w+)/);
      if (m) bodyFuncTypes.set(m[1], this.parseFuncTypeSig(m[2]));
    }
    this.startBodyLines = this.startBodyLines.map((line) => {
      // Strip function-type annotation so substituteOneArrow can find the actual arrow body.
      // "const name: () => T = () => expr" → "const name = () => expr"
      // The annotation type info is already captured in bodyFuncTypes above.
      let stripped = line.replace(
        /^((?:const|let|var)\s+\w+)\s*:\s*\([^)]*\)\s*=>\s*\w+\s*=/,
        "$1 =",
      );
      let prev = "";
      while (prev !== stripped) {
        prev = stripped;
        stripped = this.substituteOneArrow(stripped, bodyFuncTypes, syntheticStart);
      }
      return stripped;
    });
  }

  private substituteOneArrow(
    line: string,
    bodyFuncTypes: Map<string, { params: WatType[]; result: WatType | null }> = new Map(),
    enclosingFn?: FuncDef,
  ): string {
    if (!line.includes("=>")) return line;

    // Find the first `=>` in the line
    const arrowIdx = line.indexOf("=>");

    // Scan left of `=>` to find the `)` closing the arrow's param list.
    // Skip optional `: ReturnType` annotation that may appear between `)` and `=>`.
    let i = arrowIdx - 1;
    while (i >= 0 && line[i] === " ") i--;
    // If we landed on a word character, try to skip a `: Type` annotation
    if (i >= 0 && /\w/.test(line[i])) {
      while (i >= 0 && /\w/.test(line[i])) i--; // skip type name
      while (i >= 0 && line[i] === " ") i--;
      if (i >= 0 && line[i] === ":") i--; // skip ':'
      while (i >= 0 && line[i] === " ") i--;
    }
    if (i < 0 || line[i] !== ")") return line;

    // Find the matching `(` — this is the start of the arrow params
    let depth = 0;
    let paramsStart = i;
    while (paramsStart >= 0) {
      if (line[paramsStart] === ")") depth++;
      else if (line[paramsStart] === "(") {
        depth--;
        if (depth === 0) break;
      }
      paramsStart--;
    }
    if (paramsStart < 0) return line;

    // Must be preceded by `(` or `,` (argument position), ignoring spaces
    let beforeParens = paramsStart - 1;
    while (beforeParens >= 0 && line[beforeParens] === " ") beforeParens--;
    if (
      beforeParens < 0 ||
      (line[beforeParens] !== "," && line[beforeParens] !== "(" && line[beforeParens] !== "=" &&
        line[beforeParens] !== ":")
    ) return line;

    // Guard: skip type-annotation declarations such as `let mathOp: (a: i32) => i32;`.
    // The `:` context is valid for object-literal values `{ key: (p) => ... }` but NOT
    // for variable type annotations that start with var/let/const.
    if (line[beforeParens] === ":" && /^(?:var|let|const)\s/.test(line)) return line;

    // For `=` (assignment arrow): extract the target variable name.
    // If it's already a known module-level function (parsed by parseArrowFunctions), skip lifting.
    let assignTarget = "";
    if (line[beforeParens] === "=") {
      let nameEnd = beforeParens - 1;
      while (nameEnd >= 0 && line[nameEnd] === " ") nameEnd--;
      let nameStart = nameEnd;
      while (nameStart > 0 && /\w/.test(line[nameStart - 1])) nameStart--;
      assignTarget = line.slice(nameStart, nameEnd + 1);
      if (this.functions.find((f) => f.name === assignTarget)) return line; // already handled
    }

    // Find the end of the arrow body (expression or block)
    let bodyStart = arrowIdx + 2;
    while (bodyStart < line.length && line[bodyStart] === " ") bodyStart++;

    let arrowEnd: number;
    if (line[bodyStart] === "{") {
      depth = 0;
      arrowEnd = bodyStart;
      while (arrowEnd < line.length) {
        if (line[arrowEnd] === "{") depth++;
        else if (line[arrowEnd] === "}") {
          depth--;
          if (depth === 0) {
            arrowEnd++;
            break;
          }
        }
        arrowEnd++;
      }
    } else {
      depth = 0;
      arrowEnd = bodyStart;
      while (arrowEnd < line.length) {
        const ch = line[arrowEnd];
        if (ch === "(" || ch === "[") depth++;
        else if (ch === ")" || ch === "]") {
          if (depth === 0) break;
          depth--;
        } else if ((ch === "," || ch === ";") && depth === 0) break;
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
      depth = 1;
      let j = beforeParens - 1;
      argIdx = 1;
      while (j >= 0 && depth > 0) {
        if (line[j] === ")") depth++;
        else if (line[j] === "(") {
          depth--;
          if (depth === 0) break;
        } else if (line[j] === "," && depth === 1) argIdx++;
        j--;
      }
      let nameEnd = j;
      while (nameEnd > 0 && /\w/.test(line[nameEnd - 1])) nameEnd--;
      calleeName = line.slice(nameEnd, j);
    }
    // else: assignment — calleeName stays "", type info comes from bodyFuncTypes

    const calleeFn = this.functions.find((f) => f.name === calleeName);
    // For assignment arrows, look up the declared functype of the target variable
    const assignInfo = preceding === "=" ? bodyFuncTypes.get(assignTarget) : undefined;
    const paramInfo = calleeFn?.params[argIdx]?.funcTypeInfo ?? assignInfo;

    // Parse the inline arrow's params
    const innerRaw = line.slice(paramsStart + 1, i).trim();
    const paramList: FuncParam[] = [];
    if (innerRaw) {
      innerRaw.split(",").map((p) => p.trim()).filter(Boolean).forEach((pp, pi) => {
        const ci = pp.indexOf(":");
        const pname = ci !== -1 ? pp.slice(0, ci).trim().replace(/\?$/, "") : pp.trim();
        const ptype: WatType = ci !== -1
          ? mapType(pp.slice(ci + 1).trim()) as WatType
          : (paramInfo?.params[pi] ?? "i32" as WatType);
        paramList.push({ name: pname, type: ptype });
      });
    }

    // Phase 12: for object-literal arrow values (key: arrow), look up expected return type
    // from the enclosing function's interface return type (resultTsName → structDefs field).
    let interfaceFieldResult: WatType | null | undefined;
    if (preceding === ":" && enclosingFn?.resultTsName) {
      // Skip whitespace and the `:` separator to reach the field name identifier
      let keyEnd = paramsStart - 1;
      while (keyEnd >= 0 && line[keyEnd] === " ") keyEnd--; // spaces before `(`
      if (keyEnd >= 0 && line[keyEnd] === ":") keyEnd--; // the `:` separator
      while (keyEnd >= 0 && line[keyEnd] === " ") keyEnd--; // spaces before key name
      let keyStart = keyEnd;
      while (keyStart > 0 && /\w/.test(line[keyStart - 1])) keyStart--;
      const keyName = line.slice(keyStart, keyEnd + 1);
      if (keyName) {
        const ifaceStruct = this.structDefs.get(enclosingFn.resultTsName);
        const ifaceField = ifaceStruct?.fields.find((f) => f.name === keyName);
        if (ifaceField?.funcType) interfaceFieldResult = ifaceField.funcType.result;
      }
    }

    // Parse optional return type annotation between `)` and `=>`
    const betweenParenArrow = line.slice(i + 1, arrowIdx).trim();
    const retAnnotation = betweenParenArrow.match(/^:\s*(\w+)/)?.[1];
    let anonResult: WatType | null = retAnnotation
      ? (retAnnotation === "void" ? null : mapType(retAnnotation) as WatType)
      : (paramInfo?.result ?? interfaceFieldResult ?? null);

    // Build body lines
    const bodyRaw = line.slice(bodyStart, arrowEnd).trim();
    let bodyLines: string[];
    if (bodyRaw.startsWith("{")) {
      const inner = bodyRaw.slice(1, bodyRaw.endsWith("}") ? -1 : undefined).trim();
      bodyLines = WasicTranspiler.splitStmts(inner);
      // Infer result type from return statement if not annotated
      if (anonResult === null) {
        // Build scope including outer function params + locals for captured variable types
        const inferLocals = new Map<string, WatType>();
        if (enclosingFn) {
          for (const p of enclosingFn.params) inferLocals.set(p.name, p.type);
          for (const bl of enclosingFn.bodyLines) {
            const vm = bl.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*=/);
            if (vm) inferLocals.set(vm[1], vm[2] ? mapType(vm[2]) as WatType : "i32");
          }
        }
        for (const p of paramList) inferLocals.set(p.name, p.type);
        for (const bl of bodyLines) {
          const retM = bl.match(/^return\s+(.+?)\s*;?$/);
          if (retM) {
            const inferred = inferInitType(
              retM[1].trim(),
              inferLocals,
              this.enumValues,
              this.functions,
            );
            if (inferred) {
              anonResult = inferred;
              break;
            }
          }
        }
      }
    } else {
      // Infer result type from body expression only when we have no callee type info.
      // If paramInfo is defined but its result is null (void callee), don't override with inferInitType
      // because null from JavaScript's ?? coalescing is indistinguishable from "no info" otherwise.
      if (anonResult === null && paramInfo === undefined) {
        const paramLocals = new Map<string, WatType>();
        for (const p of paramList) paramLocals.set(p.name, p.type);
        anonResult = inferInitType(bodyRaw, paramLocals, this.enumValues, this.functions);
      }
      bodyLines = anonResult !== null ? [`return ${bodyRaw};`] : [`${bodyRaw};`];
    }

    const anonName = `__anon_${this.anonArrowCounter++}`;
    const anonDef: FuncDef = {
      name: anonName,
      params: paramList,
      result: anonResult,
      exported: false,
      bodyLines,
    };
    this.functions.push(anonDef);

    // Phase 5g: if we have an enclosing function, detect captures and heap-allocate this arrow.
    if (enclosingFn) {
      const KWORDS = new Set([
        "return",
        "if",
        "else",
        "while",
        "for",
        "do",
        "switch",
        "case",
        "default",
        "break",
        "continue",
        "const",
        "let",
        "var",
        "true",
        "false",
        "null",
        "undefined",
      ]);
      // Build outer scope: params + declared locals of the enclosing function
      const outerScope = new Map<string, WatType>();
      for (const p of enclosingFn.params) outerScope.set(p.name, p.type);
      for (const bl of enclosingFn.bodyLines) {
        // Use ([\w\[\]]+) for the type to handle array types like i32[], i32[][], etc.
        const lm = bl.match(/^(?:const|let|var)\s+(\w+)\s*(?::\s*([\w\[\]]+))?\s*=\s*(.+?)?;?$/);
        if (lm && !lm[3]?.includes("=>")) {
          const t: WatType = lm[2]
            ? mapType(lm[2]) as WatType
            : (inferInitType(lm[3] ?? "", outerScope, this.enumValues, this.functions) ?? "i32");
          if (t !== "string") outerScope.set(lm[1], t);
        }
      }
      // Collect identifiers used in the arrow body
      const ownParams = new Set(paramList.map((p) => p.name));
      const used = new Set<string>();
      for (const bl of bodyLines) {
        for (const ref of bl.matchAll(/\b([a-zA-Z_]\w*)\b/g)) used.add(ref[1]);
      }
      const captures: string[] = [];
      for (const id of used) {
        if (!ownParams.has(id) && !KWORDS.has(id) && outerScope.has(id)) captures.push(id);
      }

      if (captures.length > 0) {
        // Inject captures as extra params on the anon (inner) function
        anonDef.closureCaptures = captures;
        for (const cap of captures) anonDef.params.push({ name: cap, type: outerScope.get(cap)! });
        // Phase 5h: if any capture is a shared mutable capture in the enclosing fn, mark it as boxed
        if (enclosingFn?.sharedMutableCaptures) {
          const boxed = new Set(captures.filter((c) => enclosingFn.sharedMutableCaptures!.has(c)));
          if (boxed.size > 0) anonDef.boxedCaptures = boxed;
        }

        // Create a factory FuncDef that allocates the closure struct and returns a ptr
        const factoryName = `${anonName}__factory`;
        const factoryDef: FuncDef = {
          name: factoryName,
          params: captures.map((cap) => ({ name: cap, type: outerScope.get(cap)! })),
          result: "i32" as WatType,
          exported: false,
          bodyLines: [],
          isClosureFactory: true,
          returnedArrow: anonDef,
        };
        this.functions.push(factoryDef);

        // Replace the inline arrow expression with a factory call: factoryName(cap1, cap2, ...)
        const captureArgs = captures.join(", ");
        return line.slice(0, paramsStart) + `${factoryName}(${captureArgs})` + line.slice(arrowEnd);
      }
    }

    // No captures (or no enclosing fn context): bare funcref in table, as before
    this.getFuncTableIdx(anonName);
    return line.slice(0, paramsStart) + anonName + line.slice(arrowEnd);
  }

  /** Emits (type $ftype_... (func ...)) declarations for all used call_indirect signatures. */
  private emitFuncTypes(): string {
    if (this.funcTypes.size === 0) return "";
    const lines: string[] = [];
    for (const [key, typeName] of this.funcTypes) {
      const [paramPart, resultPart] = key.split("->");
      const params = paramPart === "void"
        ? ""
        : paramPart.split(",").map((t) => `(param ${t})`).join(" ");
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
   * Splits a block body string into statements at depth 0.
   * Splits on `;` at depth 0 (regular statements).
   * Also splits after `}` that brings depth to 0 (end of block statements: if/for/while),
   * UNLESS the next non-whitespace token is `else` (which continues an if/else chain).
   */
  private static splitStmts(inner: string): string[] {
    const parts: string[] = [];
    let depth = 0, start = 0;
    for (let i = 0; i < inner.length; i++) {
      const ch = inner[i];
      // Skip over string / char / template literals so a `;`, `{`, or `}` inside
      // them is never treated as a statement boundary.
      if (ch === '"' || ch === "'" || ch === "`") {
        const quote = ch;
        i++;
        while (i < inner.length && inner[i] !== quote) {
          if (inner[i] === "\\") i++; // skip escaped char
          i++;
        }
        continue;
      }
      if (ch === "(" || ch === "{") depth++;
      else if (ch === ")" || ch === "}") {
        depth--;
        if (depth === 0 && ch === "}") {
          // Check if continuation (else clause) follows — if so, don't split here
          let peek = i + 1;
          while (peek < inner.length && inner[peek] === " ") peek++;
          const next7 = inner.slice(peek, peek + 4);
          if (!next7.startsWith("else")) {
            const part = inner.slice(start, i + 1).trim();
            if (part) parts.push(part);
            start = i + 1;
          }
        }
      } else if (ch === ";" && depth === 0) {
        const part = inner.slice(start, i).trim();
        if (part) parts.push(part + ";");
        start = i + 1;
      }
    }
    const trailing = inner.slice(start).trim();
    if (trailing) parts.push(trailing.endsWith(";") ? trailing : trailing + ";");
    return parts;
  }

  /**
   * Expands a single-line brace chain — `{ A } [else { B }] [else if (c) { … }] …` —
   * into the multi-line form `emitBlock`'s if-handler expects (then-body statements,
   * then a `} else {` / `} else if (c) {` terminator, then the next branch, … , `}`).
   * Lets `if (cond) { A } else { B }` written entirely on one line reuse the correct
   * multi-line else / else-if handling instead of the old strip-last-`}` heuristic that
   * silently swallowed the `else`. `body` must start with `{`.
   */
  private static expandInlineBraceChain(body: string): string[] {
    const out: string[] = [];
    let s = body.trim();
    while (s.startsWith("{")) {
      // Find the matching close brace of the leading "{".
      let d = 0, close = -1;
      for (let j = 0; j < s.length; j++) {
        if (s[j] === "{") d++;
        else if (s[j] === "}") {
          if (--d === 0) {
            close = j;
            break;
          }
        }
      }
      if (close === -1) {
        // Unbalanced (shouldn't happen for a single-line block) — emit what we have.
        const inner = s.slice(1).trim();
        out.push(...(inner ? WasicTranspiler.splitStmts(inner) : []));
        out.push("}");
        return out;
      }
      const inner = s.slice(1, close).trim();
      out.push(...(inner ? WasicTranspiler.splitStmts(inner) : []));
      let rest = s.slice(close + 1).trim();
      if (!rest.startsWith("else")) {
        // Brace chain complete. Close it, then re-emit any trailing statements
        // (e.g. `if (c) { return 1; } return 2;`) as siblings after the if-block
        // so they are not silently dropped.
        out.push("}");
        if (rest) out.push(...WasicTranspiler.splitStmts(rest));
        return out;
      }
      rest = rest.slice(4).trim();
      if (rest.startsWith("{")) {
        out.push("} else {");
        s = rest; // loop processes the final else block, then closes with "}"
        continue;
      }
      if (rest.startsWith("if")) {
        const condStart = rest.indexOf("(");
        let pd = 0, condEnd = -1;
        for (let j = condStart; j < rest.length; j++) {
          if (rest[j] === "(") pd++;
          else if (rest[j] === ")") {
            if (--pd === 0) {
              condEnd = j;
              break;
            }
          }
        }
        if (condEnd === -1 || condStart === -1) {
          out.push("}");
          return out;
        }
        out.push(`} else if (${rest.slice(condStart + 1, condEnd)}) {`);
        s = rest.slice(condEnd + 1).trim(); // continues with "{ … } …"
        continue;
      }
      // Malformed else — close defensively.
      out.push("}");
      return out;
    }
    return out;
  }

  /**
   * True when `line` is a SELF-CONTAINED `else` / `else if` continuation that fits entirely on one
   * line — either brace-less (`else stmt;`, `else if (c) stmt;`) or a balanced single-line braced
   * block (`else { … }`, `else if (c) { … }`). Returns FALSE for an OPEN braced else (`else {` /
   * `else if (c) {` whose body continues on following lines) so the existing multi-line machinery
   * handles it. Used to recover an else chain that follows a single-line `if` (which the if-handler
   * would otherwise silently drop — the brace-less and single-line-braced forms both leaked).
   */
  private static isSelfContainedElse(line: string): boolean {
    const t = line.trim();
    if (!/^else\b/.test(t)) return false;
    let rest = t.replace(/^else\s*/, "");
    if (/^if\s*\(/.test(rest)) {
      const openIdx = rest.indexOf("(");
      let depth = 0, condEnd = -1;
      for (let j = openIdx; j < rest.length; j++) {
        if (rest[j] === "(") depth++;
        else if (rest[j] === ")" && --depth === 0) {
          condEnd = j;
          break;
        }
      }
      if (condEnd === -1) return false;
      rest = rest.slice(condEnd + 1).trim();
    }
    if (rest === "") return false; // `else if (c)` with no body — malformed
    if (rest.startsWith("{")) {
      // Self-contained only if the braces balance within this single line.
      let d = 0;
      for (const ch of rest) {
        if (ch === "{") d++;
        else if (ch === "}") d--;
      }
      return d === 0;
    }
    return true; // brace-less `else stmt` / `else if (c) stmt`
  }

  /**
   * Normalises a self-contained else line (see isSelfContainedElse) to braced form so it can be
   * appended to an inline chain fed to expandInlineBraceChain: `else if (c) stmt` →
   * `else if (c) { stmt }`, `else stmt` → `else { stmt }`; already-braced forms pass through.
   */
  private static braceifyElseLine(line: string): string {
    const t = line.trim();
    let rest = t.replace(/^else\s*/, "");
    let condPart = "";
    if (/^if\s*\(/.test(rest)) {
      const openIdx = rest.indexOf("(");
      let depth = 0, condEnd = -1;
      for (let j = openIdx; j < rest.length; j++) {
        if (rest[j] === "(") depth++;
        else if (rest[j] === ")" && --depth === 0) {
          condEnd = j;
          break;
        }
      }
      condPart = `if (${rest.slice(openIdx + 1, condEnd).trim()}) `;
      rest = rest.slice(condEnd + 1).trim();
    }
    const body = rest.startsWith("{") ? rest : `{ ${rest} }`;
    return `else ${condPart}${body}`;
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
      const ch = rawParams[i];
      // Track (), [], and {} so commas inside tuple types ([i32, i32]) or destructuring
      // patterns ({ x, y }) don't split a single param. (Phase 51.3 — bracket/brace-aware.)
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "]" || ch === "}") depth--;
      else if (ch === "," && depth === 0) {
        paramStrs.push(rawParams.slice(start, i).trim());
        start = i + 1;
      }
    }
    paramStrs.push(rawParams.slice(start).trim());

    return paramStrs.filter((p) => p.length > 0).map((p) => {
      // Rest parameter: ...name: T[]
      if (p.startsWith("...")) {
        const withoutDots = p.slice(3);
        const colonIdx = withoutDots.indexOf(":");
        const name = colonIdx !== -1 ? withoutDots.slice(0, colonIdx).trim() : withoutDots.trim();
        const typeAnnotation = colonIdx !== -1
          ? withoutDots.slice(colonIdx + 1).trim().replace(/\s*=.*$/, "")
          : "i32[]";
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
      // Named function type alias: name: AliasName where AliasName = (p) => RetType
      const funcAlias = this.namedFuncTypeAliases.get(typeAnnotation);
      if (funcAlias) {
        this.funcTypeVars.set(name, funcAlias);
        this.closureTypedVars.set(name, funcAlias);
        return { name, type: "i32" as WatType, funcTypeInfo: funcAlias };
      }
      // Phase 23: detect tuple param: [T1, T2, ...] — register synthetic StructDef, treat as i32 pointer
      if (typeAnnotation.startsWith("[") && typeAnnotation.endsWith("]")) {
        const tupleDef = this.getOrCreateTupleDef(typeAnnotation);
        if (tupleDef) {
          const eqIdx2 = afterColon.indexOf("=");
          const st = tupleDef.name;
          if (eqIdx2 !== -1) {
            return {
              name,
              type: "i32" as WatType,
              defaultValue: afterColon.slice(eqIdx2 + 1).trim(),
              structType: st,
            };
          }
          return { name, type: "i32" as WatType, structType: st };
        }
      }
      const paramType = mapType(typeAnnotation);
      // Detect array param: T[] → i32 pointer with element type T
      const arrElemMatch = typeAnnotation.match(/^(\w+)\[\]$/);
      const arrayElemType: WatType | undefined = arrElemMatch
        ? mapType(arrElemMatch[1]) as WatType
        : undefined;
      // For struct array params (e.g. Person[]), preserve the struct type name for arr[i].field access
      const arrayStructElemType: string | undefined =
        (arrElemMatch && /^[A-Z]/.test(arrElemMatch[1]) && this.structDefs.has(arrElemMatch[1]))
          ? arrElemMatch[1]
          : undefined;
      // Detect struct param: capitalized type name that isn't a known primitive
      // structType is stored so emitFunction can register it in structVars.
      const structType: string | undefined = !arrElemMatch && /^[A-Z]\w*$/.test(typeAnnotation)
        ? typeAnnotation
        : undefined;
      const resolvedType: WatType = structType ? "i32" : paramType;
      // Split "type = defaultExpr" if an explicit default value is present
      const eqIdx = afterColon.indexOf("=");
      if (eqIdx !== -1) {
        return {
          name,
          type: resolvedType,
          defaultValue: afterColon.slice(eqIdx + 1).trim(),
          arrayElemType,
          arrayStructElemType,
          structType,
        };
      }
      if (isOptional) {
        return {
          name,
          type: resolvedType,
          defaultValue: "0",
          arrayElemType,
          arrayStructElemType,
          structType,
        };
      }
      return { name, type: resolvedType, arrayElemType, arrayStructElemType, structType };
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
      // Return type may include array suffix: i32[], i32[][], ClassName, tuple [T1,T2], T|null, etc.
      // Phase 34: also matches type predicate annotations "param is Type".
      // Also matches function-type return annotations like `() => number` or `(a: i32) => f64`.
      const restMatch = src.slice(afterClose).match(
        /^\s*(?::\s*([\w]+\s+is\s+[\w]+|[\w]+(?:\[\])*(?:\s*\|\s*(?:null|undefined))*|\[[^\]]*\]|\([^)]*\)\s*=>\s*[\w]+))?\s*\{/,
      );
      if (!restMatch) continue; // malformed header — skip

      let rawResult = (restMatch[1] ?? "void").trim();
      // Phase 34: detect type predicate return annotation "param is Type"
      // e.g. function isCircle(s: Shape): s is Circle { ... }
      const typePredicateMatch = rawResult.match(/^(\w+)\s+is\s+(\w+)$/);
      if (typePredicateMatch) {
        this.typePredicateFuncs.set(name, {
          paramName: typePredicateMatch[1],
          targetType: typePredicateMatch[2],
        });
        rawResult = "bool"; // type predicates return bool (i32 in WAT)
      }
      // Phase 24: detect T|null or T|undefined return type — register in nullableFuncReturnType
      // and strip the union annotation so the WAT result type is just the base type.
      const nullableRetInner = parseNullableAnnotation(rawResult);
      if (nullableRetInner !== null) {
        this.nullableFuncReturnType.set(name, nullableRetInner);
        rawResult = rawResult.split("|")[0].trim(); // e.g. "i32 | null" → "i32"
      }
      // Phase 23: if return type is a tuple "[T1, T2, ...]", create/register the synthetic StructDef
      if (rawResult.startsWith("[") && rawResult.endsWith("]")) {
        const def = this.getOrCreateTupleDef(rawResult);
        if (def) rawResult = def.name;
      }
      // Function-type return annotation like `() => number` — maps to i32 (closure ptr)
      if (/^\([^)]*\)\s*=>/.test(rawResult)) rawResult = "i32";
      const result: WatType | null = rawResult === "void" || rawResult === ""
        ? null
        : mapType(rawResult);

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
      let rawLines = rawBody
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l.length > 0);
      // Single-physical-line body — the whole function is `{ stmt; stmt; … }` on one
      // line. Split it into statements so multi-statement single-line bodies (e.g.
      // `if (c) { return 1; } return 2;`) are processed correctly instead of being
      // emitted as one mangled statement. splitStmts is string-aware and keeps
      // if/else chains intact; single-statement bodies are returned unchanged.
      if (rawLines.length === 1) {
        rawLines = WasicTranspiler.splitStmts(rawLines[0]);
      }
      // Join multi-line `return { ... }` object literals into one line so substituteOneArrow
      // and emitStatement can process them as a unit.
      const bodyLines: string[] = [];
      let li = 0;
      while (li < rawLines.length) {
        const l = rawLines[li];
        if (/^return\s*\{/.test(l)) {
          let depth = 0, joined = l;
          for (const ch of l) {
            if (ch === "{") depth++;
            else if (ch === "}") depth--;
          }
          while (depth > 0 && li + 1 < rawLines.length) {
            li++;
            const next = rawLines[li];
            joined += " " + next;
            for (const ch of next) {
              if (ch === "{") depth++;
              else if (ch === "}") depth--;
            }
          }
          bodyLines.push(joined.trim());
        } else if (/^return\s+function\s*\(/.test(l)) {
          // Multi-line `return function(params): retType { body }` — join then rewrite to arrow
          let depth = 0, joined = l;
          for (const ch of l) {
            if (ch === "{") depth++;
            else if (ch === "}") depth--;
          }
          while (depth > 0 && li + 1 < rawLines.length) {
            li++;
            const next = rawLines[li];
            joined += "\n" + next; // preserve newlines so parseReturnArrow splits body correctly
            for (const ch of next) {
              if (ch === "{") depth++;
              else if (ch === "}") depth--;
            }
          }
          // Rewrite: `return function(params): retType { body }` → `return (params): retType => { body }`
          const rewrit = joined.trim().replace(
            /^return\s+function\s*(\([\s\S]*?\))(\s*:\s*[\w\[\]|]+)?\s*\{([\s\S]*)\}\s*;?$/,
            (_m, params, ret, body) => `return ${params}${ret ?? ""} => {${body}};`,
          );
          bodyLines.push(rewrit);
        } else if (/^(?:var|let|const)\s+\w+/.test(l)) {
          // Join multi-line `const arr: T[] = [ ... ]` array literals into one line
          // so the arrPre regex (which requires closing ] on same line) can process them.
          // String-literal-aware so `let s: string = "["` is NOT mistaken for an unclosed array
          // (that bug joined the following statement onto it, silently breaking both).
          let arrDepth = netSquareBracketDepth(l);
          if (arrDepth > 0) {
            let joined = l;
            while (arrDepth > 0 && li + 1 < rawLines.length) {
              li++;
              const next = rawLines[li];
              joined += " " + next;
              arrDepth += netSquareBracketDepth(next);
            }
            bodyLines.push(joined.replace(/\s+/g, " ").trim());
          } else {
            bodyLines.push(l);
          }
        } else {
          bodyLines.push(l);
        }
        li++;
      }

      // Phase 5f: detect closure factory — body is `return (params) => expr;`
      const factoryParams = this.parseParams(rawParams);
      const returnedArrow = this.parseReturnArrow(name, bodyLines, factoryParams);
      if (returnedArrow) this.functions.push(returnedArrow);
      let resultTsName = rawResult !== "void" && rawResult !== "" ? rawResult : undefined;
      let autoResultType: WatType | undefined;
      // Phase 5h: auto-detect anonymous struct return — return { key: arrowFn, ... } with no explicit return type
      if (!resultTsName && !returnedArrow) {
        const returnObjLine = bodyLines.find((l) => /^return\s*\{/.test(l));
        if (returnObjLine) {
          let depth = 0, objStart = -1, objEnd = -1;
          for (let bi = 0; bi < returnObjLine.length; bi++) {
            if (returnObjLine[bi] === "{") { if (depth++ === 0) objStart = bi; }
            else if (returnObjLine[bi] === "}") {
              if (--depth === 0) {
                objEnd = bi;
                break;
              }
            }
          }
          if (objStart !== -1 && objEnd !== -1) {
            const objContent = returnObjLine.slice(objStart + 1, objEnd).trim();
            const arrowFieldRe = /(\w+)\s*:\s*\(([^)]*)\)(?:\s*:\s*([\w\[\]|]+))?\s*=>/g;
            const autoFields: StructField[] = [];
            let autoOffset = 0;
            let afm: RegExpExecArray | null;
            while ((afm = arrowFieldRe.exec(objContent)) !== null) {
              const fieldName = afm[1];
              const rawFParams = afm[2];
              const rawFResult = afm[3]?.trim();
              const mParams: WatType[] = rawFParams.trim()
                ? rawFParams.split(",").map((p) => {
                  const ci = p.indexOf(":");
                  return (ci !== -1 ? mapType(p.slice(ci + 1).trim()) : "i32") as WatType;
                })
                : [];
              let mResult: WatType | null = !rawFResult || rawFResult === "void"
                ? null
                : mapType(rawFResult) as WatType;
              // If no explicit result annotation, check body for non-empty return statement
              if (mResult === null) {
                const afterArrow = objContent.slice((afm.index ?? 0) + afm[0].length).trimStart();
                if (afterArrow.startsWith("{")) {
                  if (/return\s+\w/.test(afterArrow)) mResult = "i32" as WatType;
                } else {
                  // Expression body always returns a value
                  mResult = "i32" as WatType;
                }
              }
              autoFields.push({
                name: fieldName,
                type: "i32",
                offset: autoOffset,
                size: 4,
                funcType: { params: mParams, result: mResult },
              });
              autoOffset += 4;
            }
            if (autoFields.length > 0) {
              const autoStructName = `__AnonResult_${name}`;
              this.structDefs.set(autoStructName, {
                name: autoStructName,
                fields: autoFields,
                totalSize: autoOffset,
              });
              resultTsName = autoStructName;
              autoResultType = "i32";
            }
          }
        }
      }
      // Phase 5h: detect shared mutable captures in return { ... } object literals.
      // Variables referenced by 2+ arrows AND mutated in any arrow must be heap-boxed.
      let sharedMutableCaptures: Set<string> | undefined;
      if (!returnedArrow) {
        const retObjLine = bodyLines.find((l) => /^return\s*\{/.test(l));
        if (retObjLine) {
          // Build outer scope (params + top-level declarations before the return)
          const outerVarNames = new Set<string>(factoryParams.map((p) => p.name));
          for (const bl of bodyLines) {
            const vm = bl.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*\w+)?\s*=/);
            if (vm) outerVarNames.add(vm[1]);
          }
          // Extract object literal content
          let od = 0, oStart = -1, oEnd = -1;
          for (let bi = 0; bi < retObjLine.length; bi++) {
            if (retObjLine[bi] === "{") { if (od++ === 0) oStart = bi; }
            else if (retObjLine[bi] === "}") {
              if (--od === 0) {
                oEnd = bi;
                break;
              }
            }
          }
          if (oStart !== -1 && oEnd !== -1) {
            const objBody = retObjLine.slice(oStart + 1, oEnd);
            // For each outer var: count how many distinct arrow bodies reference it
            const refByArrow = new Map<string, Set<number>>();
            const mutatedVars = new Set<string>();
            // Find arrow boundary positions (split on top-level `=>` arrow markers)
            const arrowBodyParts: string[] = [];
            let abd = 0, abStart = 0, inArrow = false;
            for (let bi = 0; bi < objBody.length; bi++) {
              const ch = objBody[bi];
              if (ch === "(" || ch === "{") abd++;
              else if (ch === ")" || ch === "}") abd--;
              // Detect '=>' at depth 0 to find arrow start
              if (!inArrow && abd === 0 && objBody[bi] === "=" && objBody[bi + 1] === ">") {
                inArrow = true;
                abStart = bi + 2;
              }
              // End of an arrow body: comma or end of object at depth 0 after arrow started
              if (inArrow && abd === 0 && (ch === "," || bi === objBody.length - 1)) {
                arrowBodyParts.push(
                  objBody.slice(abStart, bi + (bi === objBody.length - 1 ? 1 : 0)),
                );
                inArrow = false;
              }
            }
            arrowBodyParts.forEach((bodyPart, arrowIdx) => {
              for (const [, id] of bodyPart.matchAll(/\b([a-zA-Z_]\w*)\b/g)) {
                if (outerVarNames.has(id)) {
                  if (!refByArrow.has(id)) refByArrow.set(id, new Set());
                  refByArrow.get(id)!.add(arrowIdx);
                }
              }
              // Detect mutations: id++, ++id, id--, --id, id op= x, id = x (not ==)
              for (
                const [, id] of bodyPart.matchAll(
                  /\b(\w+)\s*(?:\+\+|--)|(?:\+\+|--)\s*(\w+)|\b(\w+)\s*(?:[+\-*\/%&|^]|<<|>>|>>>)?=(?!=)/g,
                )
              ) {
                const mutId = id || "";
                if (mutId && outerVarNames.has(mutId)) mutatedVars.add(mutId);
              }
              // Also catch augmented assignments like count += 1
              for (
                const [, id] of bodyPart.matchAll(/\b(\w+)\s*(?:[+\-*\/%&|^]|<<|>>|>>>)?=(?!=)/g)
              ) {
                if (outerVarNames.has(id)) mutatedVars.add(id);
              }
            });
            const shared = new Set<string>();
            for (const [id, arrowSet] of refByArrow) {
              if (arrowSet.size >= 2 && mutatedVars.has(id)) shared.add(id);
            }
            if (shared.size > 0) sharedMutableCaptures = shared;
          }
        }
      }
      this.functions.push({
        name,
        params: factoryParams,
        result: returnedArrow ? "i32" : (autoResultType ?? result),
        exported,
        bodyLines,
        isClosureFactory: !!returnedArrow,
        returnedArrow: returnedArrow ?? undefined,
        resultTsName,
        sharedMutableCaptures,
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
  private parseReturnArrow(
    factoryName: string,
    bodyLines: string[],
    factoryParams?: Array<{ name: string; type: WatType }>,
  ): FuncDef | undefined {
    const retLine = bodyLines.find((l) => /^return\s+\(/.test(l) && l.includes("=>"));
    if (!retLine) return undefined;

    // Strip `return ` prefix and trailing `;`
    const body = retLine.replace(/^return\s+/, "").replace(/;$/, "").trim();
    if (!body.startsWith("(")) return undefined;

    const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(body, 0);
    const restMatch = body.slice(afterClose).match(/^\s*(?::\s*([\w]+(?:\[\])*|\[[^\]]*\]))?\s*=>/);
    if (!restMatch) return undefined;

    let rawResultRA = (restMatch[1] ?? "").trim();
    if (rawResultRA.startsWith("[") && rawResultRA.endsWith("]")) {
      const def = this.getOrCreateTupleDef(rawResultRA);
      if (def) rawResultRA = def.name;
    }
    const rawResult = rawResultRA;
    let result: WatType | null = rawResult === "void" || rawResult === ""
      ? null
      : mapType(rawResult);

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
      innerBodyLines = rawBody.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
    } else {
      const rawExpr = body.slice(bodyStart).trim().replace(/;$/, "");
      // Infer result type when no explicit annotation was given (e.g. `(val: i32) => val * x`).
      // Build a minimal locals map from the parsed params so inferInitType can resolve identifiers.
      if (result === null) {
        const paramLocals = new Map<string, WatType>();
        for (const p of this.parseParams(rawParams)) paramLocals.set(p.name, p.type);
        // Also include factory params (captures) so identifiers like `original` resolve correctly
        if (factoryParams) {
          for (const p of factoryParams) {
            if (!paramLocals.has(p.name)) paramLocals.set(p.name, p.type);
          }
        }
        // Also include variables declared in the factory body (e.g. `const inner = (x) => ...`)
        // Arrow-assigned variables are i32 closure pointers; other vars use inferInitType.
        for (const bl of bodyLines) {
          const bm = bl.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
          if (!bm || paramLocals.has(bm[1])) continue;
          const initE = (bm[3] ?? "").trim();
          if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initE)) paramLocals.set(bm[1], "i32");
          else {
            const t = bm[2]
              ? mapType(bm[2])
              : inferInitType(initE, paramLocals, this.enumValues, this.functions);
            if (t !== "string") paramLocals.set(bm[1], t);
          }
        }
        result = inferInitType(rawExpr, paramLocals, this.enumValues, this.functions);
      }
      innerBodyLines = result !== null ? [`return ${rawExpr};`] : [`${rawExpr};`];
    }

    const innerName = `${factoryName}__inner`;
    if (this.functions.find((f) => f.name === innerName)) return undefined; // already added

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
      // Count brace depth to detect whether this arrow is inside a function body
      let braceDepth = 0;
      for (let bi = 0; bi < m.index; bi++) {
        if (src[bi] === "{") braceDepth++;
        else if (src[bi] === "}") braceDepth--;
      }

      const name = m[1];
      const openParen = m.index + m[0].length - 1;

      // Extract param list with paren-counting
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);

      // After `)` expect optional `: retType` then `=>` — if not present, not an arrow function
      const restMatch = src.slice(afterClose).match(
        /^\s*(?::\s*([\w]+(?:\[\])*|\[[^\]]*\]))?\s*=>/,
      );
      if (!restMatch) continue;

      let rawResultAF = (restMatch[1] ?? "").trim();
      // Phase 23: tuple return type on arrow function
      if (rawResultAF.startsWith("[") && rawResultAF.endsWith("]")) {
        const def = this.getOrCreateTupleDef(rawResultAF);
        if (def) rawResultAF = def.name;
      }
      const rawResult = rawResultAF;
      const result: WatType | null = rawResult === "void" || rawResult === ""
        ? null
        : mapType(rawResult);

      // Find start of body (skip whitespace after =>)
      let bodyStart = afterClose + restMatch[0].length;
      while (bodyStart < src.length && src[bodyStart] === " ") bodyStart++;

      // Expression-body arrows inside function bodies are handled by liftInlineArrows +
      // substituteOneArrow (which can create closure factories for capturing arrows).
      // Block-body arrows must always be handled here since substituteOneArrow is line-by-line.
      if (braceDepth > 0 && src[bodyStart] !== "{") continue;

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
        bodyLines = rawBody.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
      } else {
        // Expression body: read to end-of-line / semicolon
        const eol = src.indexOf("\n", bodyStart);
        const rawExpr = (eol !== -1 ? src.slice(bodyStart, eol) : src.slice(bodyStart))
          .trim()
          .replace(/;$/, "");
        bodyLines = result !== null ? [`return ${rawExpr};`] : [`${rawExpr};`];
      }

      // Avoid duplicates (nested arrows inside functions share the source scan)
      if (!this.functions.find((f) => f.name === name)) {
        this.functions.push({
          name,
          params: this.parseParams(rawParams),
          result,
          exported: false,
          bodyLines,
        });
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
    const lines = this.src.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
    let depth = 0;
    let collectInner = false; // true while inside an import.meta.main block
    let collectBlock = false; // true while collecting body of a top-level for/while/if block

    for (const line of lines) {
      const opens = (line.match(/\{/g) ?? []).length;
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

        // Namespace declaration — skip body (already expanded by expandNamespaces)
        if (/^(?:export\s+)?namespace\s+\w+/.test(line)) {
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
        if (line === "}" || line === "};" || line === ";") continue;
        if (
          line.startsWith("//") || line.startsWith("*") || line.startsWith("import ") ||
          line.startsWith("export {")
        ) continue;

        // Pattern 4: bare top-level statement → goes into _start.
        // Phase 26: if this statement opens a block (for/while/if/etc.), track depth so inner body
        // lines and closing braces are included in startBodyLines.
        const netOpen = opens - closes;
        if (netOpen > 0) {
          this.startBodyLines.push(line);
          depth = netOpen;
          collectBlock = true;
        } else if (hasMultipleTopLevelStatements(line)) {
          // Genuine multi-statement line (`const a = 1; const b = 2;`) — split string-aware so each
          // becomes its own _start statement. Gated by hasMultipleTopLevelStatements (a depth-0,
          // bracket+string-aware `;` with content after it) so an array-literal FRAGMENT like
          // `const people: Person[] = [` or `{ name: "Alice" },` (which splitStmts would corrupt —
          // it tracks only `(){}` not `[]` and appends a stray `;` to incomplete lines) is left
          // intact for joinMultilineArrayLiterals to reassemble.
          for (const s of WasicTranspiler.splitStmts(line)) {
            if (s.trim().length > 0) this.startBodyLines.push(s);
          }
        } else {
          this.startBodyLines.push(line);
        }
      } else {
        // Inside a function/block body
        const newDepth = depth + opens - closes;

        if (collectBlock) {
          // Collect body lines of a top-level block statement (for/while/if/etc.).
          // Include the closing } so emitBlock/extractBlock can find the block end.
          this.startBodyLines.push(line);
          if (newDepth <= 0) {
            collectBlock = false;
            depth = 0;
          } else {
            depth = newDepth;
          }
        } else if (collectInner) {
          // Collect lines belonging to if (import.meta.main) block.
          // When newDepth would reach 0 this is the closing } — don't collect it.
          if (newDepth >= 1) {
            this.startBodyLines.push(line);
          } else {
            collectInner = false;
          }
          depth = Math.max(0, newDepth);
          if (depth === 0) collectInner = false;
        } else {
          depth = Math.max(0, newDepth);
          if (depth === 0) collectInner = false;
        }
      }
    }
  }

  /** Joins multi-line array literal declarations in startBodyLines into single lines.
   *  e.g. `const x: T[] = [` followed by element lines followed by `]` → one joined line.
   *  This allows the array pre-scan regexes (which need `[...]` on one line) to match. */
  private joinMultilineArrayLiterals(): void {
    // Count net [ ] depth while skipping characters inside string literals.
    const netBrackets = (s: string): number => {
      let d = 0, inSQ = false, inDQ = false, inTmpl = false;
      for (let ci = 0; ci < s.length; ci++) {
        const c = s[ci];
        if (c === "\\" && (inSQ || inDQ || inTmpl)) {
          ci++;
          continue;
        }
        if (!inDQ && !inTmpl && c === "'") {
          inSQ = !inSQ;
          continue;
        }
        if (!inSQ && !inTmpl && c === '"') {
          inDQ = !inDQ;
          continue;
        }
        if (!inSQ && !inDQ && c === "`") {
          inTmpl = !inTmpl;
          continue;
        }
        if (inSQ || inDQ || inTmpl) continue;
        if (c === "[") d++;
        else if (c === "]") d--;
      }
      return d;
    };

    const result: string[] = [];
    let i = 0;
    while (i < this.startBodyLines.length) {
      const line = this.startBodyLines[i];
      // Check if this is an array declaration that opens an unclosed bracket
      const isArrDecl = /^(?:var|let|const)\s+\w+/.test(line);
      if (isArrDecl) {
        let depth = netBrackets(line);
        if (depth > 0) {
          // Collect subsequent lines until brackets balance
          let joined = line;
          i++;
          while (i < this.startBodyLines.length && depth > 0) {
            const next = this.startBodyLines[i];
            joined += " " + next;
            depth += netBrackets(next);
            i++;
          }
          result.push(joined.replace(/\s+/g, " ").trim());
          continue;
        }
      }
      result.push(line);
      i++;
    }
    this.startBodyLines = result;
  }

  // -------------------------------------------------------------------------
  // Pass 2b – extract module-level scalar globals from startBodyLines
  // -------------------------------------------------------------------------
  /**
   * Scans startBodyLines for simple scalar const/let/var declarations and moves
   * them into moduleGlobals so they become WASM (global ...) entries rather than
   * WAT locals in the generated _start body.  Arrays, objects, and arrow-function
   * initialisers are left in startBodyLines for normal processing.
   */
  private parseModuleGlobals(): void {
    const remaining: string[] = [];
    for (const line of this.startBodyLines) {
      const m = line.match(
        /^(?:export\s+)?(const|let|var)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?);?$/,
      );
      if (m) {
        const keyword = m[1];
        const name = m[2];
        const typeStr = m[3] ?? "";
        const initExpr = m[4].trim();
        // Skip arrows, arrays, objects, and multi-word initialisers we can't constant-fold
        if (initExpr.includes("=>") || initExpr.startsWith("[") || initExpr.startsWith("{")) {
          remaining.push(line);
          continue;
        }
        // Pre-register string literal constants before the numeric/enum guard so
        // functions can reference them via moduleStringConsts.
        // Escape-aware so a literal containing `\"` / `\\` (e.g. an embedded JSON document)
        // is recognised and its quotes don't terminate the match early.
        const isStringLit = /^"(?:[^"\\]|\\.)*"$/.test(initExpr) ||
          /^'(?:[^'\\]|\\.)*'$/.test(initExpr);
        if (isStringLit) {
          const typeHere = (typeStr ? mapType(typeStr) : "string") as WatType;
          if (typeHere === "string") {
            const strVal = initExpr.slice(1, -1);
            const [offset, len] = this.allocString(strVal);
            // A MUTABLE module-level string (`let`/`var`) referenced inside any function body
            // must become a global pair so writes from one function are visible to another.
            // A `const`, or a string only used in _start, stays an immutable data-section const.
            const referencedInFn = keyword !== "const" &&
              this.functions.some((f) =>
                f.name !== "_start" && new RegExp(`\\b${name}\\b`).test(f.bodyLines.join("\n"))
              );
            if (referencedInFn) {
              this.moduleStringGlobals.set(name, { ptr: offset, len });
              continue; // drop the init line; the global declaration carries the initial value
            }
            this.moduleStringConsts.set(name, [offset, len]);
          }
          remaining.push(line); // keep in startBodyLines for _start assignment
          continue;
        }
        // Only accept pure constant initialisers valid in WAT global init expressions:
        //   numeric/bigint literals  e.g. 0, 3.14, -5, 42n
        //   known enum member refs   e.g. Color.Red
        const isNumericLit = /^-?\d+(\.\d+)?n?$/.test(initExpr);
        const isEnumRef = /^\w+\.\w+$/.test(initExpr) && this.enumValues.has(initExpr);
        if (!isNumericLit && !isEnumRef) {
          remaining.push(line); // complex init (function call, etc.) — leave in startBodyLines
          continue;
        }
        const type = (typeStr
          ? mapType(typeStr)
          : inferInitType(initExpr, new Map(), this.enumValues, this.functions)) as WatType;
        if (!type || type === "string") {
          remaining.push(line); // unknown type or unhandled string form — leave in startBodyLines
          continue;
        }
        this.moduleGlobals.set(name, { type, mutable: keyword !== "const", initExpr });
        continue;
      }
      remaining.push(line);
    }
    this.startBodyLines = remaining;
  }

  /**
   * Detects module-level dynamic arrays that are accessed from within function bodies,
   * and registers them as mutable i32 WASM globals so functions can read/write them.
   * Must run after parseModuleGlobals() and before emitFunction() calls.
   */
  private detectModuleArrayGlobals(): void {
    // Collect all array names used as method receivers in any function body,
    // and whether they need dynamic (heap) layout (push/pop used in functions).
    const usedInFunctions = new Set<string>();
    const needsDynamic = new Set<string>();
    for (const fn of this.functions) {
      for (const line of fn.bodyLines) {
        const m = line.match(
          /\b(\w+)\.(push|pop|shift|unshift|indexOf|includes|slice|forEach|map|filter|find|reduce|every|some|findIndex|at|reverse|fill|join|sort|flat|flatMap|splice|concat|length)\s*[.(]?/,
        );
        if (m) {
          usedInFunctions.add(m[1]);
          if (["push", "pop", "shift", "unshift", "splice"].includes(m[2])) needsDynamic.add(m[1]);
        }
        // Plain length access: arr.length (no parens)
        const lm = line.match(/\b(\w+)\.length\b/);
        if (lm) usedInFunctions.add(lm[1]);
        // Array element read/write: arr[idx] or arr[idx] = ...
        const em = line.match(/\b(\w+)\[/);
        if (em) usedInFunctions.add(em[1]);
      }
    }
    // Also mark arrays as dynamic if startBodyLines uses push/pop on them.
    for (const name of this.findDynamicArrays(this.startBodyLines)) needsDynamic.add(name);

    // Scan startBodyLines for array declarations whose names appear in function bodies.
    for (const line of this.startBodyLines) {
      // Phase 44: Array<FuncType> = [] syntax (function pointer arrays)
      const mFA = line.match(
        /^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*:\s*Array<((?:[^<>]|=>)*)>\s*=\s*\[\]/,
      );
      if (mFA) {
        const varName = mFA[1];
        if (!usedInFunctions.has(varName)) continue;
        if (this.moduleGlobals.has(varName)) continue;
        const funcSig = this.parseFuncTypeSig(mFA[2].trim());
        const isDynamic = needsDynamic.has(varName);
        this.moduleGlobals.set(varName, { type: "i32", mutable: true, initExpr: "0" });
        this.moduleArrayVars.set(varName, {
          elemType: "i32",
          ptr: -2,
          length: 0,
          dynamic: isDynamic,
          isFuncPtrArr: funcSig,
        });
        continue;
      }
      const m = line.match(
        /^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*(?::\s*([\w]+)(\[\])+)?\s*=\s*\[/,
      );
      if (!m) continue;
      const varName = m[1];
      if (!usedInFunctions.has(varName)) continue;
      if (this.moduleGlobals.has(varName)) continue; // already registered
      // Determine element type
      const typeHint = m[2] ?? "";
      let elemType: WatType = "i32";
      if (typeHint === "string") {
        elemType = "i32"; // string arrays store pair-of-i32 entries via special helpers
      } else if (typeHint === "number") {
        elemType = "f64";
      } else if (typeHint && this.structDefs.has(typeHint)) {
        elemType = "i32"; // struct pointer arrays
      } else if (typeHint) {
        elemType = (mapType(typeHint) as WatType) ?? "i32";
      }
      const isDynamic = needsDynamic.has(varName);
      const isStringArr = typeHint === "string";
      const structTypeName = (typeHint && this.structDefs.has(typeHint)) ? typeHint : undefined;
      // Register as mutable i32 global (holds the heap ptr; 0 = not yet allocated).
      this.moduleGlobals.set(varName, { type: "i32", mutable: true, initExpr: "0" });
      // Store metadata for dynArrStmt/dynArrMethod to use global.get/set.
      this.moduleArrayVars.set(varName, {
        elemType,
        ptr: -2,
        length: 0,
        dynamic: isDynamic,
        isStringArr,
        structTypeName,
      });
    }
  }

  /** Returns whether an array is a true module-level WASM global (registered in moduleGlobals AND not shadowed by a local/parameter in the current function scope). */
  private isModuleGlobalArr(arrName: string): boolean {
    return this.moduleGlobals.has(arrName) && this.arrayVars.get(arrName)?.ptr === -2;
  }

  /** Returns the WAT expression to read the array pointer: global.get for module globals, local.get otherwise. */
  private arrGetWat(arrName: string): string {
    return this.isModuleGlobalArr(arrName) ? `(global.get $${arrName})` : `(local.get $${arrName})`;
  }

  /** Returns the WAT statement to write a new array pointer: global.set for module globals, local.set otherwise. */
  private arrSetWat(arrName: string, valExpr: string): string {
    return this.isModuleGlobalArr(arrName)
      ? `(global.set $${arrName} ${valExpr})`
      : `(local.set $${arrName} ${valExpr})`;
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

    const gFuncs = new Map<string, GFuncTmpl>();
    const gStructs = new Map<string, GStructTmpl>();

    // --- 1. Find generic function templates: [export] function name<T,...>( ---
    const gFuncRe = /(export\s+)?function\s+(\w+)\s*<([^>]+)>\s*\(/g;
    let m: RegExpExecArray | null;
    while ((m = gFuncRe.exec(src)) !== null) {
      const exported = !!m[1];
      const name = m[2];
      const typeParams = m[3].split(",").map((t) => t.trim()).filter(Boolean);
      const openParen = m.index + m[0].length - 1;
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);
      // Return type may be a type param (T), generic type (Box<T>), or array type (T[]) — use permissive match
      const restMatch = src.slice(afterClose).match(/^\s*(?::\s*([\w\[\]<>, ]+?))?\s*\{/);
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
        typeParams,
        rawParams,
        rawResult,
        bodyText: src.slice(bodyStart, i - 1),
        exported,
        start: m.index,
        end: i,
      });
    }

    // --- 2. Find generic struct templates: interface Name<T,...> { ... } ---
    const gStructRe = /(?:export\s+)?interface\s+(\w+)\s*<([^>]+)>\s*\{([^}]*)\}/g;
    while ((m = gStructRe.exec(src)) !== null) {
      const name = m[1];
      const typeParams = m[2].split(",").map((t) => t.trim()).filter(Boolean);
      gStructs.set(name, {
        typeParams,
        rawFields: m[3],
        start: m.index,
        end: m.index + m[0].length,
      });
    }
    // Also handle: type Name<T> = { ... }
    const gTypeRe = /(?:export\s+)?type\s+(\w+)\s*<([^>]+)>\s*=\s*\{([^}]*)\}/g;
    while ((m = gTypeRe.exec(src)) !== null) {
      const name = m[1];
      if (!gStructs.has(name)) {
        const typeParams = m[2].split(",").map((t) => t.trim()).filter(Boolean);
        gStructs.set(name, {
          typeParams,
          rawFields: m[3],
          start: m.index,
          end: m.index + m[0].length,
        });
      }
    }

    if (gFuncs.size === 0 && gStructs.size === 0) return src;

    // --- 3. Storage for generated concrete definitions ---
    const concreteFuncs = new Map<string, string>(); // concreteName → TS source
    const concreteStructs = new Map<string, string>(); // concreteName → TS source

    // Substitute each type param with its concrete type string in text
    const substitute = (text: string, typeParams: string[], concreteTypes: string[]): string => {
      let result = text;
      for (let i = 0; i < typeParams.length; i++) {
        result = result.replace(
          new RegExp(`\\b${typeParams[i]}\\b`, "g"),
          concreteTypes[i] ?? "i32",
        );
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
        let body = substitute(tmpl.bodyText, tmpl.typeParams, typeArgs);
        // Rewrite any generic struct refs that appear in params / result / body
        for (const [sName, sTmpl] of gStructs) {
          const sRe = new RegExp(`\\b${sName}\\s*<([\\w,\\s]+)>`, "g");
          const rewrite = (str: string) =>
            str.replace(sRe, (_: string, tArgStr: string) => {
              const tArgs = tArgStr.split(",").map((t: string) => t.trim());
              return getOrCreateStruct(sName, sTmpl, tArgs);
            });
          params = rewrite(params);
          result = rewrite(result);
          body = rewrite(body);
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
        const retPart = (result === "void" || !result) ? "" : `: ${result}`;
        concreteFuncs.set(
          concreteName,
          `${exportKw}function ${concreteName}(${params})${retPart} {\n${body}\n}`,
        );
      }
      return concreteName;
    };

    // Infer a concrete type name from a simple literal expression.
    // Returns null when the expression is too complex to type-infer (e.g., bare identifier).
    const inferArgTypeLiteral = (expr: string): string | null => {
      const e = expr.trim();
      if (e === "true" || e === "false") return "bool";
      if (/^-?\d+n$/.test(e)) return "i64";
      if (e.startsWith('"') || e.startsWith("'")) return "string";
      if (/^-?\d+\.\d/.test(e) || /^\d*\.\d+/.test(e)) return "f64";
      if (/^-?\d+$/.test(e)) return "i32";
      return null;
    };

    // --- 4. Remove generic templates from source (reverse order to preserve offsets) ---
    const removals = [
      ...[...gFuncs.values()].map((t) => ({ start: t.start, end: t.end })),
      ...[...gStructs.values()].map((t) => ({ start: t.start, end: t.end })),
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
          if (c === "(" || c === "[") depth++;
          else if ((c === ")" || c === "]") && depth > 0) depth--;
          else if (c === ")" && depth === 0) {
            end = i;
            break;
          } else if (c === "," && depth === 0) {
            end = i;
            break;
          }
        }
        const firstArg = afterParen.slice(0, end).trim();
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

      // Strip line/block comments before splitting
      const cleaned = body
        .replace(/\/\/[^\n]*/g, "")
        .replace(/\/\*[\s\S]*?\*\//g, "");

      // Split body at top-level commas
      const parts: string[] = [];
      let depth = 0, start = 0;
      for (let i = 0; i < cleaned.length; i++) {
        const ch = cleaned[i];
        if (ch === "(" || ch === "[" || ch === "{") depth++;
        else if (ch === ")" || ch === "]" || ch === "}") depth--;
        else if (ch === "," && depth === 0) {
          parts.push(cleaned.slice(start, i));
          start = i + 1;
        }
      }
      parts.push(cleaned.slice(start));

      // First pass: parse each member into (name, kind, rhs/stringVal)
      type Raw = {
        name: string;
        kind: "numeric" | "string" | "auto";
        rhs: string;
        stringVal: string;
      };
      const raws: Raw[] = [];
      for (let part of parts) {
        part = part.trim();
        if (!part) continue;
        const eqIdx = part.indexOf("=");
        if (eqIdx === -1) {
          if (!/^\w+$/.test(part)) continue;
          raws.push({ name: part, kind: "auto", rhs: "", stringVal: "" });
        } else {
          const name = part.slice(0, eqIdx).trim();
          const rhs = part.slice(eqIdx + 1).trim();
          if (!/^\w+$/.test(name)) continue;
          const strMatch = rhs.match(/^"([^"]*)"$/) ?? rhs.match(/^'([^']*)'$/);
          if (strMatch) {
            raws.push({ name, kind: "string", rhs: "", stringVal: strMatch[1] });
          } else {
            raws.push({ name, kind: "numeric", rhs, stringVal: "" });
          }
        }
      }

      // Second pass: resolve numeric members and auto-increment
      const resolved = new Map<string, number>();
      let autoVal = 0;
      for (const r of raws) {
        if (r.kind === "string") {
          this.enumStringValues.set(`${enumName}.${r.name}`, r.stringVal);
          continue;
        }
        let val: number;
        if (r.kind === "auto") {
          val = autoVal;
        } else {
          val = this.evalEnumExpr(r.rhs, resolved);
        }
        this.enumValues.set(`${enumName}.${r.name}`, val);
        resolved.set(r.name, val);
        autoVal = val + 1;
      }

      // Third pass: heterogeneous enums — assign synthetic integer tags to string
      // members so comparisons (env === DeployEnv.Prod) work as i32 ops. The string
      // display value is still tracked in enumStringValues; console_log.ts checks
      // enumStringValues first so display contexts keep printing the string.
      const hasString = raws.some((r) => r.kind === "string");
      const hasNumeric = raws.some((r) => r.kind !== "string");
      if (hasString && hasNumeric) {
        let maxVal = -1;
        for (const v of resolved.values()) if (v > maxVal) maxVal = v;
        let nextTag = maxVal + 1;
        for (const r of raws) {
          if (r.kind === "string") {
            this.enumValues.set(`${enumName}.${r.name}`, nextTag);
            nextTag++;
          }
        }
      }
    }
  }

  // Evaluate a compile-time enum initializer expression. Supports prior
  // member references (substituted from `resolved`), integer literals,
  // bitwise operators (| & ^ << >> >>>), arithmetic (+ - * / %), and parens.
  private evalEnumExpr(expr: string, resolved: Map<string, number>): number {
    // Substitute identifiers with already-resolved member values
    const sub = expr.replace(/\b([A-Za-z_]\w*)\b/g, (_m, name) => {
      if (resolved.has(name)) return String(resolved.get(name));
      return name;
    });
    try {
      const result = Function(`"use strict"; return (${sub});`)();
      return (result | 0);
    } catch {
      return 0;
    }
  }

  // -------------------------------------------------------------------------
  // Phase 30 — namespace source expansion
  // -------------------------------------------------------------------------
  /**
   * Transforms `namespace Name { export function f(...) {...}  export const C: T = val; }`
   * into top-level `function Name_f(...) {...}  const Name_C: T = val;`.
   * Records every namespace name in `this.namespaceDefs` so call sites can resolve
   * `Name.f(args)` → `(call $Name_f args)` and `Name.C` → `(global.get $Name_C)`.
   */
  private expandNamespaces(src: string): string {
    const nsRe = /(?:export\s+)?namespace\s+(\w+)\s*\{/g;
    let m: RegExpExecArray | null;
    const replacements: Array<{ start: number; end: number; text: string }> = [];
    while ((m = nsRe.exec(src)) !== null) {
      const nsName = m[1];
      const bodyStart = m.index + m[0].length;
      let depth = 1, ci = bodyStart;
      while (ci < src.length && depth > 0) {
        if (src[ci] === "{") depth++;
        else if (src[ci] === "}") depth--;
        ci++;
      }
      const bodyEnd = ci - 1; // points at the closing `}`
      const body = src.slice(bodyStart, bodyEnd);
      this.namespaceDefs.add(nsName);

      // Replace `export function` → `function Name_`, `export const/let` → `const/let Name_`
      let transformed = body;
      transformed = transformed.replace(
        /\bexport\s+function\s+(\w+)/g,
        (_m2, fn) => `function ${nsName}_${fn}`,
      );
      transformed = transformed.replace(
        /\bexport\s+(const|let)\s+(\w+)/g,
        (_m2, kw, vn) => `${kw} ${nsName}_${vn}`,
      );
      // Remove any remaining `export` keywords (e.g. re-exports)
      transformed = transformed.replace(/\bexport\s+/g, "");

      replacements.push({ start: m.index, end: ci, text: transformed + "\n" });
    }
    // Apply replacements in reverse order to keep indices valid
    let result = src;
    for (let i = replacements.length - 1; i >= 0; i--) {
      const { start, end, text } = replacements[i];
      result = result.slice(0, start) + text + result.slice(end);
    }
    return result;
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
      // Phase 30: capture optional `extends BaseType` between name and `{`
      /(?:export\s+)?interface\s+(\w+)(?:\s+extends\s+(\w+))?\s*\{([^}]*)\}/g,
      /(?:export\s+)?type\s+(\w+)\s*=\s*\{([^}]*)\}/g,
    ];
    for (const reIdx of [0, 1]) {
      const re = patterns[reIdx];
      let m: RegExpExecArray | null;
      while ((m = re.exec(this.src)) !== null) {
        const name = m[1];
        // Phase 32: skip discriminated union types already registered by parseDiscriminatedUnions()
        if (this.structDefs.has(name)) continue;
        // Phase 30: for interface pattern (reIdx===0), m[2]=extendsBase, m[3]=body;
        //           for type pattern (reIdx===1), m[2]=body, no extends.
        const extendsBase = reIdx === 0 ? (m[2] ?? null) : null;
        const body = reIdx === 0 ? m[3] : m[2];
        const fields: StructField[] = [];
        let offset = 0;
        // Match optional "readonly" prefix, then "fieldName: typeName;" or "fieldName?: typeName;"
        // Detect method-type fields: name: (params) => ReturnType
        const methodFieldRe = /(\w+)\??:\s*\(([^)]*)\)\s*=>\s*([\w\[\]|]+)/g;
        const methodFieldNames = new Set<string>();
        // Phase 30: prepend inherited fields from `extends BaseType`
        if (extendsBase) {
          const baseDef = this.structDefs.get(extendsBase);
          if (baseDef) {
            for (const bf of baseDef.fields) {
              fields.push({ ...bf }); // copy with original offsets
            }
            offset = baseDef.totalSize;
          }
        }

        let mf: RegExpExecArray | null;
        while ((mf = methodFieldRe.exec(body)) !== null) {
          const fieldName = mf[1];
          const rawParams = mf[2];
          const rawResult = mf[3].trim();
          methodFieldNames.add(fieldName);
          // Parse method param types
          const methodParams: WatType[] = rawParams.trim()
            ? rawParams.split(",").map((p) => {
              const ci = p.indexOf(":");
              return ci !== -1 ? mapType(p.slice(ci + 1).trim()) as WatType : "i32" as WatType;
            })
            : [];
          const methodResult: WatType | null = rawResult === "void"
            ? null
            : mapType(rawResult) as WatType;
          if (offset % 4 !== 0) offset = Math.ceil(offset / 4) * 4;
          fields.push({
            name: fieldName,
            type: "i32",
            offset,
            size: 4,
            funcType: { params: methodParams, result: methodResult },
          });
          offset += 4;
        }
        // Detect plain data fields (skip method fields already handled)
        const fieldRe = /(?:(readonly)\s+)?(\w+)\??:\s*([\w\[\]]+)/g;
        let fm: RegExpExecArray | null;
        while ((fm = fieldRe.exec(body)) !== null) {
          const isReadonly = fm[1] === "readonly";
          const fieldName = fm[2];
          if (methodFieldNames.has(fieldName)) continue; // already handled as method field
          // Skip fields already inherited from extends
          if (fields.some((f) => f.name === fieldName)) continue;
          const originalTypeName = fm[3].trim();
          const type = mapType(originalTypeName);
          // string fields store ptr+len pair (8 bytes); f64/i64 need 8 bytes; all else 4.
          const size = (type === "f64" || type === "i64" || type === "string") ? 8 : 4;
          // Natural alignment: round offset up to a multiple of size
          if (offset % size !== 0) offset = Math.ceil(offset / size) * size;
          const fieldEntry: StructField = {
            name: fieldName,
            type,
            offset,
            size,
            ...(isReadonly ? { readonly: true } : {}),
          };
          // Phase 42: track struct pointer fields (PascalCase → i32 pointer to another struct)
          if (
            type === "i32" && /^[A-Z]/.test(originalTypeName) &&
            !originalTypeName.endsWith("[]") &&
            !originalTypeName.startsWith("[") &&
            !["Number", "Boolean", "String", "BigInt"].includes(originalTypeName)
          ) {
            fieldEntry.structType = originalTypeName;
          }
          fields.push(fieldEntry);
          offset += size;
        }
        if (fields.length > 0) {
          this.structDefs.set(name, { name, fields, totalSize: offset });
        }
      }
    }
    // Phase 23: tuple type aliases — type Pair = [i32, f64]
    const tupleAliasRe = /(?:export\s+)?type\s+(\w+)\s*=\s*\[([^\]]+)\]/g;
    let ta: RegExpExecArray | null;
    while ((ta = tupleAliasRe.exec(this.src)) !== null) {
      const name = ta[1];
      if (this.structDefs.has(name)) continue; // already parsed as object-type alias
      const def = this.makeTupleStructDef(name, ta[2]);
      if (def.fields.length > 0) this.structDefs.set(name, def);
    }
  }

  // -------------------------------------------------------------------------
  // Phase 32: discriminated union type parser
  // -------------------------------------------------------------------------
  /**
   * Detects `type Name = { disc: "lit1"; ...fields } | { disc: "lit2"; ...fields } | …`
   * declarations, builds a flat "super-struct" StructDef that holds all unique variant
   * fields after a leading i32 discriminant tag, and registers both the StructDef and a
   * DiscUnionDef.  Must be called BEFORE parseStructs() so that parseStructs() can skip
   * already-registered names.
   */
  private parseDiscriminatedUnions(): void {
    // Match: type Name = (optional leading |) { ...block } | { ...block } (2+ variants)
    const outerRe = /(?:export\s+)?type\s+(\w+)\s*=\s*((?:\s*\|?\s*\{[^}]*\})+)/g;
    let m: RegExpExecArray | null;
    while ((m = outerRe.exec(this.src)) !== null) {
      const name = m[1];
      const blocksStr = m[2];
      // Collect individual variant blocks
      const blockRe = /\{([^}]*)\}/g;
      type RawVariant = {
        disc: string;
        discVal: string;
        fields: Array<{ name: string; type: string }>;
      };
      const rawVariants: RawVariant[] = [];
      let bm: RegExpExecArray | null;
      while ((bm = blockRe.exec(blocksStr)) !== null) {
        const body = bm[1];
        // Discriminant field: fieldName: "literal" or fieldName: 'literal'
        const discM = body.match(/(\w+)\s*:\s*["']([^"']+)["']/);
        if (!discM) continue;
        const discField = discM[1];
        const discVal = discM[2];
        // Remaining plain-type fields (name: TypeName — no quotes, no parens)
        const fields: Array<{ name: string; type: string }> = [];
        const fieldRe2 = /(\w+)\s*:\s*([\w\[\]]+)/g;
        let fm: RegExpExecArray | null;
        while ((fm = fieldRe2.exec(body)) !== null) {
          if (fm[1] !== discField) fields.push({ name: fm[1], type: fm[2] });
        }
        rawVariants.push({ disc: discField, discVal, fields });
      }
      // Require at least 2 variants with the same discriminant field name
      if (rawVariants.length < 2) continue;
      const discName = rawVariants[0].disc;
      if (!rawVariants.every((v) => v.disc === discName)) continue;

      // Build flat combined StructDef: i32 disc tag first, then all unique fields in order
      const structFields: StructField[] = [];
      structFields.push({ name: discName, type: "i32", offset: 0, size: 4 });
      let offset = 4;
      const seenFieldNames = new Set<string>([discName]);
      for (const rv of rawVariants) {
        for (const f of rv.fields) {
          if (seenFieldNames.has(f.name)) continue;
          seenFieldNames.add(f.name);
          const type = mapType(f.type) as WatType;
          const size = (type === "f64" || type === "i64") ? 8 : 4;
          if (offset % size !== 0) offset = Math.ceil(offset / size) * size;
          structFields.push({ name: f.name, type, offset, size });
          offset += size;
        }
      }

      const def: StructDef = { name, fields: structFields, totalSize: offset };
      this.structDefs.set(name, def);

      const variants: DiscUnionVariant[] = rawVariants.map((rv, idx) => ({
        tag: rv.discVal,
        tagIndex: idx,
        fieldNames: new Set(rv.fields.map((f) => f.name)),
      }));
      this.discUnionDefs.set(name, { name, discriminant: discName, variants });
    }

    // Second pass: handle `type Name = Ident1 | Ident2 [| ...]` where each Ident is a named
    // interface/type with a discriminant string-literal field (not inline { ... } blocks).
    const namedUnionRe = /(?:export\s+)?type\s+(\w+)\s*=\s*([\w]+(?:\s*\|\s*[\w]+)*)\s*;/g;
    namedUnionRe.lastIndex = 0;
    let nu: RegExpExecArray | null;
    while ((nu = namedUnionRe.exec(this.src)) !== null) {
      const name = nu[1];
      if (this.structDefs.has(name)) continue; // already processed by first pass or parseStructs
      const parts = nu[2].split("|").map((p) => p.trim()).filter(Boolean);
      if (parts.length < 2 || !parts.every((p) => /^\w+$/.test(p))) continue;

      type RawVariantN = {
        disc: string;
        discVal: string;
        fields: Array<{ name: string; type: string }>;
      };
      const rawVariantsN: RawVariantN[] = [];
      for (const partName of parts) {
        // Find the interface/type body in source (handles multi-line bodies with [^}]* matching newlines)
        const ifaceBodyRe = new RegExp(`(?:interface|type)\\s+${partName}\\s*\\{([^}]*)\\}`);
        const ifaceM = ifaceBodyRe.exec(this.src);
        if (!ifaceM) continue;
        const body = ifaceM[1];
        const discM2 = body.match(/(\w+)\s*:\s*["']([^"']+)["']/);
        if (!discM2) continue;
        const discField = discM2[1];
        const discVal = discM2[2];
        const fields: Array<{ name: string; type: string }> = [];
        const fieldRe3 = /(\w+)\s*:\s*([\w\[\]]+)/g;
        let fm3: RegExpExecArray | null;
        while ((fm3 = fieldRe3.exec(body)) !== null) {
          if (fm3[1] !== discField) fields.push({ name: fm3[1], type: fm3[2] });
        }
        rawVariantsN.push({ disc: discField, discVal, fields });
      }
      if (rawVariantsN.length < 2) continue;
      const discNameN = rawVariantsN[0].disc;
      if (!rawVariantsN.every((v) => v.disc === discNameN)) continue;

      const structFieldsN: StructField[] = [];
      structFieldsN.push({ name: discNameN, type: "i32", offset: 0, size: 4 });
      let offsetN = 4;
      const seenN = new Set<string>([discNameN]);
      for (const rv of rawVariantsN) {
        for (const f of rv.fields) {
          if (seenN.has(f.name)) continue;
          seenN.add(f.name);
          const typeN = mapType(f.type) as WatType;
          const sizeN = (typeN === "f64" || typeN === "i64") ? 8 : 4;
          if (offsetN % sizeN !== 0) offsetN = Math.ceil(offsetN / sizeN) * sizeN;
          const feN: StructField = { name: f.name, type: typeN, offset: offsetN, size: sizeN };
          // Set structType for PascalCase field types so allocStructData can recurse on nested literals
          if (
            typeN === "i32" && /^[A-Z]/.test(f.type) &&
            !f.type.endsWith("[]") && !["Number", "Boolean", "String", "BigInt"].includes(f.type)
          ) {
            feN.structType = f.type;
          }
          structFieldsN.push(feN);
          offsetN += sizeN;
        }
      }
      const defN: StructDef = { name, fields: structFieldsN, totalSize: offsetN };
      this.structDefs.set(name, defN);
      const variantsN: DiscUnionVariant[] = rawVariantsN.map((rv, idx) => ({
        tag: rv.discVal,
        tagIndex: idx,
        fieldNames: new Set(rv.fields.map((f) => f.name)),
      }));
      this.discUnionDefs.set(name, { name, discriminant: discNameN, variants: variantsN });
    }
  }

  // -------------------------------------------------------------------------
  // Phase 33: intersection type parser
  // -------------------------------------------------------------------------
  /**
   * Detects `type Name = A & B [& C ...]` declarations, merges all struct fields
   * from each constituent type into a new flat StructDef, and registers it in
   * structDefs.  Must be called AFTER parseStructs() and parseClasses() so that
   * the constituent types are already registered.  Processes matches in source
   * order so that chained intersections (e.g. type D = C & E where C is itself
   * an intersection) work correctly in a single pass.
   */
  private parseIntersectionTypes(): void {
    const re = /(?:export\s+)?type\s+(\w+)\s*=\s*([\w]+(?:\s*&\s*[\w]+)+)\s*;?/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(this.src)) !== null) {
      const name = m[1];
      if (this.structDefs.has(name)) continue; // already registered as plain struct / DU / etc.
      const parts = m[2].split("&").map((p) => p.trim()).filter(Boolean);
      if (parts.length < 2) continue;

      const fields: StructField[] = [];
      let offset = 0;
      const seenFields = new Set<string>();

      for (const part of parts) {
        const partDef = this.structDefs.get(part);
        if (!partDef) continue; // skip unknown / non-struct types
        for (const f of partDef.fields) {
          if (seenFields.has(f.name)) continue; // first definition wins on conflict
          seenFields.add(f.name);
          if (offset % f.size !== 0) offset = Math.ceil(offset / f.size) * f.size;
          fields.push({ ...f, offset });
          offset += f.size;
        }
      }

      if (fields.length > 0) {
        this.structDefs.set(name, { name, fields, totalSize: offset });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Phase 23: tuple struct builder
  // -------------------------------------------------------------------------
  /**
   * Creates a StructDef with positional fields _0, _1, … from a comma-separated
   * types string such as "i32, f64".  The returned name is whatever the caller passes.
   */
  private makeTupleStructDef(name: string, innerTypesStr: string): StructDef {
    // Phase 51.3: bracket-aware element split so a nested tuple element ([i32,i32]) stays whole.
    const typeList = splitBraceAwareCommas(innerTypesStr).map((t) => t.trim()).filter(Boolean);
    const fields: StructField[] = [];
    let offset = 0;
    for (let i = 0; i < typeList.length; i++) {
      const elem = typeList[i];
      // Phase 51.3: nested tuple element — embed INLINE (like a Phase-21 embedded tuple field).
      if (elem.startsWith("[") && elem.endsWith("]")) {
        const nested = this.getOrCreateTupleDef(elem);
        if (nested) {
          const align = this.tupleFieldAlign(nested);
          if (offset % align !== 0) offset = Math.ceil(offset / align) * align;
          fields.push({
            name: `_${i}`,
            type: "i32",
            offset,
            size: nested.totalSize,
            tupleTypeName: nested.name,
          });
          offset += nested.totalSize;
          continue;
        }
      }
      const type = mapType(elem) as WatType;
      const size = (type === "f64" || type === "i64") ? 8 : 4;
      if (offset % size !== 0) offset = Math.ceil(offset / size) * size;
      fields.push({ name: `_${i}`, type, offset, size });
      offset += size;
    }
    return { name, fields, totalSize: offset };
  }

  /** Natural alignment for embedding a (possibly nested) tuple as an inline field: 8 if it
   *  recursively contains an 8-byte primitive (f64/i64), else 4. Alignment is a WAT hint only
   *  (no trap on misalignment), but keeping it natural avoids slow unaligned accesses. */
  private tupleFieldAlign(def: StructDef): number {
    for (const f of def.fields) {
      if (f.tupleTypeName) {
        const nd = this.structDefs.get(f.tupleTypeName);
        if (nd && this.tupleFieldAlign(nd) === 8) return 8;
      } else if (f.size === 8) return 8;
    }
    return 4;
  }

  /** Returns a canonical synthetic name for an inline tuple type annotation like "[i32, f64]".
   *  Phase 51.3: bracket-aware + recursive so nested tuples get a stable unique name. */
  private tupleTypeName(innerTypesStr: string): string {
    const parts = splitBraceAwareCommas(innerTypesStr).map((t) => {
      const e = t.trim();
      return e.startsWith("[") && e.endsWith("]") ? this.tupleTypeName(e.slice(1, -1)) : mapType(e);
    });
    return `__Tuple_${parts.join("_")}`;
  }

  /** Ensures a StructDef exists in structDefs for the given tuple type string "[T1, T2, ...]".
   *  Returns the registered StructDef, or null if the string is not a tuple type. */
  private getOrCreateTupleDef(typeAnnotation: string): StructDef | null {
    const t = typeAnnotation.trim();
    if (!t.startsWith("[") || !t.endsWith("]")) return null;
    const inner = t.slice(1, -1).trim();
    if (!inner) return null;
    const tupleName = this.tupleTypeName(inner);
    let def = this.structDefs.get(tupleName);
    if (!def) {
      def = this.makeTupleStructDef(tupleName, inner);
      if (def.fields.length > 0) this.structDefs.set(tupleName, def);
    }
    return def.fields.length > 0 ? def : null;
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
    const classRe = /(?:export\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?\s*\{/g;
    let m: RegExpExecArray | null;

    while ((m = classRe.exec(src)) !== null) {
      const className = m[1];
      const baseName = m[2] ?? null;
      if (baseName !== null) this.classInheritance.set(className, baseName);
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

      // Phase 47: prepend parent struct fields when extending another class
      if (baseName !== null) {
        const parentCd = this.classDefs.get(baseName);
        if (parentCd) {
          for (const pf of parentCd.struct.fields) fields.push({ ...pf });
          fieldOffset = parentCd.struct.totalSize;
        }
      }

      // Split into member lines via a depth/string-aware splitter (not raw "\n") so a class whose
      // fields share a physical line with the constructor/methods — the single-physical-line form
      // `class C { v: i32; constructor(x: i32) { this.v = x; } }` — still has its fields parsed.
      for (const rawLine of splitClassMemberLines(classBody)) {
        const line = rawLine.trim();
        const opens = (rawLine.match(/\{/g) ?? []).length;
        const closes = (rawLine.match(/\}/g) ?? []).length;

        if (fieldDepth === 0 && line && !line.includes("(")) {
          if (/\bstatic\b/.test(line)) {
            // Phase 29: static field with initializer — strip all modifiers, then match name: type = init
            const stripped = line.replace(
              /\b(?:private|protected|public|readonly|static|abstract|override)\b/g,
              "",
            ).trim();
            const sfm = stripped.match(/^(\w+)\s*[!?]?\s*:\s*([\w\[\]]+)\s*=\s*(.+)/);
            if (sfm) {
              const sfType = mapType(sfm[2]) as WatType;
              const sfInit = sfm[3].trim().replace(/;$/, "");
              this.moduleGlobals.set(`${className}_${sfm[1]}`, {
                type: sfType,
                mutable: true,
                initExpr: sfInit,
              });
            }
          } else {
            // Phase 21: capture readonly modifier before stripping all access modifiers
            const isReadonly = /\breadonly\b/.test(line);
            // Try tuple-type field first: `name: [T1, T2, ...]` — embedded inline, not a pointer
            const fmTup = line.match(
              /^(?:(?:private|protected|public|readonly)\s+)*(\w+)\s*[!?]?\s*:\s*(\[[^\]]+\])/,
            );
            if (fmTup) {
              const tdef = this.getOrCreateTupleDef(fmTup[2]);
              if (tdef) {
                // Align based on first tuple field's natural alignment
                const firstSize = tdef.fields[0]?.size ?? 4;
                if (fieldOffset % firstSize !== 0) {
                  fieldOffset = Math.ceil(fieldOffset / firstSize) * firstSize;
                }
                fields.push({
                  name: fmTup[1],
                  type: "i32",
                  offset: fieldOffset,
                  size: tdef.totalSize,
                  ...(isReadonly ? { readonly: true } : {}),
                  tupleTypeName: tdef.name,
                });
                fieldOffset += tdef.totalSize;
                fieldDepth += opens - closes;
                continue;
              }
            }
            const fm = line.match(
              /^(?:(?:private|protected|public|readonly)\s+)*(\w+)\s*[!?]?\s*:\s*([\w\[\]]+)/,
            );
            if (fm) {
              const type = mapType(fm[2]);
              const size = (type === "f64" || type === "i64") ? 8 : 4;
              if (fieldOffset % size !== 0) fieldOffset = Math.ceil(fieldOffset / size) * size;
              fields.push({
                name: fm[1],
                type,
                offset: fieldOffset,
                size,
                ...(isReadonly ? { readonly: true } : {}),
              });
              fieldOffset += size;
            }
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
                if (parenDepth === 0) {
                  openParen = k;
                  break;
                }
              }
            }

            if (openParen !== -1) {
              const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);

              // Extract method name from text before `(`
              const beforeParen = src.slice(lastMethodEnd, openParen).trimEnd();
              const nameMatch = beforeParen.match(/(\w+)\s*$/);

              if (nameMatch) {
                const methodName = nameMatch[1];
                const SKIP = [
                  "if",
                  "while",
                  "for",
                  "switch",
                  "catch",
                  "new",
                  "return",
                  "typeof",
                  "instanceof",
                ];
                if (!SKIP.includes(methodName)) {
                  const isStatic = /\bstatic\s+\w+\s*$/.test(beforeParen);
                  // Phase 29: detect get/set accessor prefix
                  const isGetter = /\bget\s+\w+\s*$/.test(beforeParen);
                  const isSetter = /\bset\s+\w+\s*$/.test(beforeParen);

                  // Parse return type (between `)` and `{`)
                  const betweenParenAndBrace = src.slice(afterClose, scanPos);
                  const retTypeMatch = betweenParenAndBrace.match(/:\s*([\w\[\]]+)/);
                  const rawResult = retTypeMatch ? retTypeMatch[1].trim() : "void";
                  const result: WatType | null = rawResult === "void"
                    ? null
                    : mapType(rawResult as string);

                  // Extract method body
                  const methodBodyStart = scanPos + 1;
                  let bodyDepth = 1, bodyEnd = methodBodyStart;
                  while (bodyEnd < src.length && bodyDepth > 0) {
                    if (src[bodyEnd] === "{") bodyDepth++;
                    else if (src[bodyEnd] === "}") bodyDepth--;
                    bodyEnd++;
                  }
                  const rawBody = src.slice(methodBodyStart, bodyEnd - 1);
                  let bodyLines = rawBody.split("\n").map((l) => l.trim()).filter((l) =>
                    l.length > 0
                  );
                  // Single-physical-line method/constructor body — `{ stmt; stmt; … }` on one line.
                  // Split into statements so multi-statement single-line bodies (e.g.
                  // `super(k); this.value = v;`) are processed correctly instead of being emitted as
                  // one mangled statement (mirrors the parseFunctions single-line-body fix).
                  // splitStmts is string-aware and keeps if/else chains intact.
                  if (bodyLines.length === 1) {
                    bodyLines = WasicTranspiler.splitStmts(bodyLines[0]);
                  }

                  const isConstructor = methodName === "constructor";
                  const funcName = isConstructor
                    ? `${className}_constructor`
                    : isGetter
                    ? `${className}_get_${methodName}`
                    : isSetter
                    ? `${className}_set_${methodName}`
                    : `${className}_${methodName}`;

                  const parsedParams = this.parseParams(rawParams);
                  const allParams: FuncParam[] = isStatic
                    ? parsedParams
                    : [{ name: "__self", type: "i32" as WatType }, ...parsedParams];

                  if (!this.functions.find((f) => f.name === funcName)) {
                    this.functions.push({
                      name: funcName,
                      params: allParams,
                      result: isConstructor ? null : result,
                      exported: false,
                      bodyLines,
                      className: isStatic ? undefined : className,
                    });
                  }

                  classDef.methods.push({
                    name: methodName,
                    isStatic,
                    isConstructor,
                    isGetter,
                    isSetter,
                  });
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

    // Phase 47: if any class uses extends, add a 4-byte tag header to every class in this module.
    if (this.classInheritance.size > 0) {
      this.classHeaderSize = 4;
      let nextTag = 1;
      for (const name of this.classDefs.keys()) this.classTags.set(name, nextTag++);
      // Shift all class field offsets by +4 and grow totalSize by 4.
      for (const [, cd] of this.classDefs) {
        for (const f of cd.struct.fields) f.offset += 4;
        cd.struct.totalSize += 4;
      }
    }
  }

  /** Phase 47: Walk the classInheritance chain to find the WAT function implementing a method. */
  private resolveMethodFunc(className: string, methodName: string): string | null {
    let current: string | undefined = className;
    while (current !== undefined) {
      const funcName = `${current}_${methodName}`;
      if (this.functions.find((f) => f.name === funcName)) return funcName;
      current = this.classInheritance.get(current);
    }
    return null;
  }

  /** Phase 51.4: pass-through utility types — `Partial<T>` / `Readonly<T>` / `Required<T>` /
   *  `NonNullable<T>` resolve to their inner type `T` (all are layout-identical to `T` in wasic's
   *  fixed-struct world; `NonNullable` additionally strips `| null` / `| undefined`). Pure source
   *  text transform run BEFORE parseStructs so the unwrapped type flows through every parse pass.
   *  Uses balanced `<…>` extraction and loops so nested wrappers (`Partial<Readonly<T>>`) collapse. */
  private expandUtilityTypes(src: string): string {
    const re = /\b(Partial|Readonly|Required|NonNullable)\s*</;
    let guard = 0;
    while (guard++ < 2000) {
      const m = src.match(re);
      if (!m || m.index === undefined) break;
      const open = src.indexOf("<", m.index);
      const close = matchAngleBracket(src, open);
      if (close === -1) break;
      let inner = src.slice(open + 1, close).trim();
      if (m[1] === "NonNullable") {
        inner = inner.replace(/\s*\|\s*(?:null|undefined)\b/g, "").trim();
      }
      src = src.slice(0, m.index) + inner + src.slice(close + 1);
    }
    return src;
  }

  /** Phase 51.4: build a synthetic StructDef for a `Pick`/`Omit`/`Record` utility type, or null if
   *  it can't be resolved statically (unknown base, or a `Record` with non-literal keys like
   *  `Record<string, V>`, which is a dynamic map — out of scope). Pick/Omit PRESERVE the base
   *  field offsets + totalSize so a base-typed value is layout-compatible with the subset type. */
  private buildUtilityStructDef(kind: string, argsStr: string, name: string): StructDef | null {
    const keyNames = (s: string): string[] => [...s.matchAll(/["'](\w+)["']/g)].map((mm) => mm[1]);
    if (kind === "Record") {
      const ci = argsStr.indexOf(",");
      if (ci === -1) return null;
      const keys = keyNames(argsStr.slice(0, ci));
      const valType = argsStr.slice(ci + 1).trim();
      if (keys.length === 0) return null; // Record<string, V> / Record<number, V> — dynamic map
      const fields: StructField[] = [];
      let offset = 0;
      for (const k of keys) {
        const type = mapType(valType) as WatType;
        const size = (type === "f64" || type === "i64" || type === "string") ? 8 : 4;
        if (offset % size !== 0) offset = Math.ceil(offset / size) * size;
        fields.push({ name: k, type, offset, size });
        offset += size;
      }
      return { name, fields, totalSize: offset };
    }
    // Pick / Omit
    const ci = argsStr.indexOf(",");
    if (ci === -1) return null;
    const baseName = argsStr.slice(0, ci).trim();
    const baseDef = this.structDefs.get(baseName);
    if (!baseDef) return null;
    const keys = keyNames(argsStr.slice(ci + 1));
    const isOmit = kind === "Omit";
    const fields = baseDef.fields
      .filter((f) => isOmit ? !keys.includes(f.name) : keys.includes(f.name))
      .map((f) => ({ ...f }));
    return { name, fields, totalSize: baseDef.totalSize };
  }

  /** Phase 51.4: resolve `Pick`/`Omit`/`Record` utility types into synthetic struct types. Runs
   *  AFTER parseStructs (needs the base StructDef) and BEFORE parseFunctions. Two forms:
   *  (1) `type Alias = Pick<T, K>;` → register the StructDef under `Alias`, strip the declaration;
   *  (2) inline `Pick<T, K>` at a use site → register a synthetic `__Pick_T_K` and substitute it.
   *  By now pass-through wrappers are already resolved, so the args never contain nested `<…>`. */
  private expandStructUtilityTypes(): void {
    // (1) `type Alias = Pick/Omit/Record<...>;`
    this.src = this.src.replace(
      /(?:export\s+)?type\s+(\w+)\s*=\s*(Pick|Omit|Record)\s*<([^<>]*)>\s*;?/g,
      (_full, alias, kind, args) => {
        const def = this.buildUtilityStructDef(kind, args, alias);
        if (def) this.structDefs.set(alias, def);
        return ""; // strip the declaration (Alias now resolves via structDefs)
      },
    );
    // (2) inline `Pick/Omit/Record<...>` at use sites.
    this.src = this.src.replace(
      /\b(Pick|Omit|Record)\s*<([^<>]*)>/g,
      (full, kind, args) => {
        const sanitized = (args as string).replace(/[^\w]+/g, "_").replace(/^_+|_+$/g, "");
        // Must start with an uppercase letter so struct-type detection (`[A-Z]\w*`) recognizes it.
        const synth = `${kind}_${sanitized}`;
        if (!this.structDefs.has(synth)) {
          const def = this.buildUtilityStructDef(kind, args, synth);
          if (!def) return full; // leave as-is (unresolved) rather than corrupt
          this.structDefs.set(synth, def);
        }
        return synth;
      },
    );
  }

  /** Phase 51 (gap #2): desugar a class-instance array literal
   *    const arr: C[] = [new C(a), new C(b), …]
   *  into the proven dynamic-array + push form
   *    const arr: C[] = [];
   *    arr.push(new C(a));
   *    arr.push(new C(b));
   *  Static array-literal allocation cannot run constructors (it left the element structs
   *  zero-filled with no class tag); the `arr.push(new C(…))` path constructs each element
   *  correctly (allocate + write tag + call ctor). Only fires when the declared element type is a
   *  known class AND every element is a `new …(…)` expression. Runs as a source pre-pass (after
   *  parseClasses so classDefs is populated, before parseFunctions/parseTopLevel collect bodies);
   *  bracket- and string-aware so multi-line literals are handled. */
  private expandClassInstanceArrayLiterals(): void {
    const src = this.src;
    const declRe =
      /(^|\n)([ \t]*)((?:export\s+)?(?:const|let|var)\s+(\w+)\s*:\s*([A-Z]\w*)\[\]\s*=\s*)\[/g;
    let out = "";
    let lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = declRe.exec(src)) !== null) {
      const className = m[5]!;
      if (!this.classDefs.has(className)) continue;
      const openBracket = declRe.lastIndex - 1; // index of the '['
      const end = findMatchingBracketAware(src, openBracket);
      if (end === -1) continue;
      const body = src.slice(openBracket + 1, end);
      const elements = splitTopLevelCommasStringAware(body);
      if (elements.length === 0) continue; // empty literal — leave [] as-is
      if (!elements.every((e) => /^new\s+\w+\s*\(/.test(e))) continue; // only all-`new` literals
      const lead = m[1]!; // "" (BOL) or "\n"
      const indent = m[2]!;
      const declPrefix = m[3]!; // e.g. "const arr: C[] = "
      const varName = m[4]!;
      out += src.slice(lastIndex, m.index);
      out += `${lead}${indent}${declPrefix}[];`;
      for (const e of elements) out += `\n${indent}${varName}.push(${e});`;
      let after = end + 1;
      if (src[after] === ";") after++; // absorb the literal's own trailing semicolon
      lastIndex = after;
      declRe.lastIndex = after;
    }
    out += src.slice(lastIndex);
    this.src = out;
  }

  /** Phase 51.3: desugar destructuring function parameters into a synthetic struct/tuple/array
   *  param plus an injected destructuring binding statement at the top of the body. E.g.
   *    function f({ x, y }: Vec2): i32 { return x + y; }
   *  becomes
   *    function f(__pd_0: Vec2): i32 { const { x, y } = __pd_0; return x + y; }
   *  This reuses the existing struct-param + `const { … } = obj` / `const [ … ] = tup` machinery,
   *  so no new emit path is needed. Runs as a source pre-pass BEFORE parseFunctions so the injected
   *  binding lands in the collected body. Only named `function NAME(...)` declarations with a body
   *  are rewritten (arrow/method params are a documented follow-up). */
  private expandParamDestructuring(): void {
    const src = this.src;
    let out = "";
    let cursor = 0;
    let counter = 0;
    const headerRe = /\bfunction\s+\w+\s*\(/g;
    let m: RegExpExecArray | null;
    while ((m = headerRe.exec(src)) !== null) {
      const openParen = m.index + m[0].length - 1; // index of '('
      const [rawParams, afterClose] = WasicTranspiler.extractParamBlock(src, openParen);
      const parts = splitBraceAwareCommas(rawParams);
      const injections: string[] = [];
      let changed = false;
      const newParts = parts.map((p) => {
        const d = parseDestructParam(p);
        if (!d) return p;
        const syn = `__pd_${counter++}`;
        changed = true;
        injections.push(`const ${d.open} ${d.inner} ${d.close} = ${syn};`);
        return `${syn}: ${d.type}`;
      });
      if (!changed) {
        headerRe.lastIndex = afterClose;
        continue;
      }
      // Locate the body's opening `{` (skip optional `: ReturnType`). Bail on `;` (overload/decl).
      let bi = afterClose;
      while (bi < src.length && src[bi] !== "{" && src[bi] !== ";") bi++;
      out += src.slice(cursor, openParen + 1); // …function NAME(
      out += newParts.join(", ");
      out += ")";
      if (src[bi] === "{") {
        out += src.slice(afterClose, bi + 1); // : RetType {  (or just {)
        // Each binding on its OWN line — function bodies are split per newline, so multiple
        // injected statements (or an injection sharing a single-line body) must not collide.
        out += "\n" + injections.join("\n") + "\n";
        cursor = bi + 1;
        headerRe.lastIndex = bi + 1;
      } else {
        // No body — rewrite params only, drop the (unusable) injections.
        out += src.slice(afterClose, bi);
        cursor = bi;
        headerRe.lastIndex = bi;
      }
    }
    out += src.slice(cursor);
    this.src = out;
  }

  /** Find all class names that are (or transitively extend) baseClass in this module. */
  private findSubclasses(baseClass: string): string[] {
    const result: string[] = [];
    for (const name of this.classDefs.keys()) {
      let cur: string | undefined = name;
      while (cur) {
        if (cur === baseClass) {
          result.push(name);
          break;
        }
        cur = this.classInheritance.get(cur);
      }
    }
    return result;
  }

  /** Allocates `totalSize` zero-filled bytes in the data section. Returns base pointer. */
  private allocStructData(
    def: StructDef,
    initFields: Record<string, string>,
    classTag?: number,
  ): number {
    const ptr = this.dataOffset;
    this.dataOffset += def.totalSize; // reserve struct bytes FIRST so string allocs land after
    // Build a byte array of totalSize, filling each field
    const bytes = new Uint8Array(def.totalSize);
    const view = new DataView(bytes.buffer);
    // Phase 47: write class tag at offset 0 when inheritance header is present
    if (this.classHeaderSize > 0 && classTag !== undefined) {
      view.setInt32(0, classTag, true);
    }
    for (const field of def.fields) {
      const raw = initFields[field.name];
      if (raw === undefined) continue;
      if (field.type === "string") {
        // String field: 8-byte pair [ptr i32][len i32]. Allocate string after the struct.
        const strVal = raw.replace(/^["']|["']$/g, ""); // strip surrounding quotes
        const [strPtr, strLen] = this.allocString(strVal);
        view.setInt32(field.offset, strPtr, true);
        view.setInt32(field.offset + 4, strLen, true);
      } else if (field.structType && raw.startsWith("{")) {
        // Phase 42: nested struct literal — recursively allocate the inner struct
        const nestedDef = this.structDefs.get(field.structType);
        if (nestedDef) {
          const nestedOpenIdx = raw.indexOf("{");
          const nestedBodyStr = nestedOpenIdx !== -1
            ? extractOuterObjectBody(raw, nestedOpenIdx)
            : null;
          if (nestedBodyStr !== null) {
            const nestedFields = parseDepth0Fields(nestedBodyStr);
            // Phase 19: if the nested struct is a DU type, convert discriminant string to tag index
            const nestedDu = this.discUnionDefs.get(field.structType);
            if (nestedDu) {
              const discRaw = nestedFields[nestedDu.discriminant];
              if (discRaw !== undefined) {
                const tagStr = discRaw.replace(/^["']|["']$/g, "");
                const variant = nestedDu.variants.find((v) => v.tag === tagStr);
                if (variant) nestedFields[nestedDu.discriminant] = String(variant.tagIndex);
              }
            }
            const nestedPtr = this.allocStructData(nestedDef, nestedFields);
            view.setInt32(field.offset, nestedPtr, true);
          }
        }
      } else {
        const val = (raw === "true") ? 1 : (raw === "false") ? 0 : parseFloat(raw) || 0;
        if (field.type === "f64") view.setFloat64(field.offset, val, true);
        else if (field.type === "f32") view.setFloat32(field.offset, val, true);
        else if (field.type === "i64") {
          view.setBigInt64(field.offset, BigInt(Math.trunc(val)), true);
        } else view.setInt32(field.offset, Math.trunc(val), true);
      }
    }
    const encoded = Array.from(bytes).map((b) => `\\${b.toString(16).padStart(2, "0")}`).join("");
    if (encoded) this.rawDataSegments.push({ ptr, bytes: encoded });
    return ptr;
  }

  /** Phase 19: Parse a struct literal string (e.g. `{ type: "leaf", weight: 45 }`) for a
   *  named struct type, apply DU discriminant conversion if needed, and allocate in the
   *  static data section. Returns the static pointer or null on parse failure. */
  private tryAllocStructLiteralPtr(litStr: string, structTypeName: string): number | null {
    const def = this.structDefs.get(structTypeName);
    if (!def) return null;
    const openIdx = litStr.indexOf("{");
    if (openIdx === -1) return null;
    const bodyStr = extractOuterObjectBody(litStr, openIdx);
    if (!bodyStr) return null;
    // Use the shorthand-aware parser to detect ALL field values (including { key } shorthands).
    const rawFieldsCheck = parseDepth0FieldsWithShorthand(bodyStr);
    // If any field value is a runtime variable (not a numeric literal, bool, or quoted string),
    // this literal cannot be allocated statically — fall through to emitRuntimeStructLiteral.
    const isCompileTimeConst = (raw: string): boolean =>
      raw === "true" || raw === "false" ||
      /^["'`]/.test(raw) ||
      /^-?\d+(\.\d+)?([eE][+-]?\d+)?n?$/.test(raw);
    for (const [, raw] of Object.entries(rawFieldsCheck)) {
      if (!isCompileTimeConst(raw)) return null;
    }
    const rawFields = parseDepth0Fields(bodyStr);
    const duDef = this.discUnionDefs.get(structTypeName);
    if (duDef) {
      const discRaw = rawFields[duDef.discriminant];
      if (discRaw !== undefined) {
        const tagStr = discRaw.replace(/^["']|["']$/g, "");
        const variant = duDef.variants.find((v) => v.tag === tagStr);
        if (variant) rawFields[duDef.discriminant] = String(variant.tagIndex);
      }
    }
    return this.allocStructData(def, rawFields);
  }

  /** Phase 18 fix: Allocates a struct at RUNTIME from a literal like { f1: expr, shorthand, ... }.
   *  Returns a WAT block-result-i32 expression, or null if the struct type is unknown. */
  private emitRuntimeStructLiteral(
    litStr: string,
    typeName: string,
    locals: Map<string, WatType>,
  ): string | null {
    const def = this.structDefs.get(typeName);
    if (!def) return null;
    const openIdx = litStr.indexOf("{");
    if (openIdx === -1) return null;
    const bodyStr = extractOuterObjectBody(litStr, openIdx);
    if (!bodyStr) return null;
    // Phase 51.2: object spread `{ ...base, k: v }` — copy base fields, then apply overrides.
    const spreadProbe = parseStructLiteralWithSpread(bodyStr);
    if (spreadProbe.spreadSource) {
      return this.emitSpreadStructLiteral(
        def,
        spreadProbe.spreadSource,
        spreadProbe.fields,
        locals,
      );
    }
    const rawFields = parseDepth0FieldsWithShorthand(bodyStr);
    const stmts: string[] = [
      `(local.set $__rt_struct_ptr (call $__malloc (i32.const ${def.totalSize})))`,
    ];
    for (const field of def.fields) {
      const valExpr = rawFields[field.name] ?? "0";
      const storeOp = field.type === "f64"
        ? "f64.store"
        : field.type === "i64"
        ? "i64.store"
        : "i32.store";
      const valWat = this.emitExpr(valExpr, locals, field.type);
      stmts.push(`(${storeOp} offset=${field.offset} (local.get $__rt_struct_ptr) ${valWat})`);
    }
    stmts.push(`(local.get $__rt_struct_ptr)`);
    return `(block (result i32)\n        ${stmts.join("\n        ")}\n      )`;
  }

  /** Phase 51.2: resolve a spread-source variable to its struct def + a WAT pointer expression.
   *  Works for struct vars (locals, module globals, or static-address consts) and class instances. */
  private resolveStructBase(
    name: string,
    locals: Map<string, WatType>,
  ): { def: StructDef; ptrWat: string } | null {
    const sv = this.structVars.get(name);
    if (sv) {
      const ptrWat = locals.has(name)
        ? `(local.get $${name})`
        : this.moduleGlobals.has(name)
        ? `(global.get $${name})`
        : sv.ptr >= 0
        ? `(i32.const ${sv.ptr})`
        : `(local.get $${name})`;
      return { def: sv.def, ptrWat };
    }
    const cv = this.classVars.get(name);
    if (cv) {
      const cd = this.classDefs.get(cv.className);
      if (cd) {
        const ptrWat = locals.has(name) ? `(local.get $${name})` : `(global.get $${name})`;
        return { def: cd.struct, ptrWat };
      }
    }
    return null;
  }

  /** Phase 51.2: build `{ ...base, k: v }` at runtime. Copies every target field from `base`
   *  (matched by name, using base's own offset/type), then writes the explicit overrides. Fields
   *  present in neither remain zero (fresh bump-allocated memory is zero). String fields copied
   *  from base move both the ptr and len words. */
  private emitSpreadStructLiteral(
    def: StructDef,
    spreadSource: string,
    overrides: Record<string, string>,
    locals: Map<string, WatType>,
  ): string {
    const baseInfo = this.resolveStructBase(spreadSource, locals);
    const stmts: string[] = [
      `(local.set $__rt_struct_ptr (call $__malloc (i32.const ${def.totalSize})))`,
    ];
    for (const field of def.fields) {
      const storeOp = field.type === "f64"
        ? "f64.store"
        : field.type === "i64"
        ? "i64.store"
        : "i32.store";
      if (Object.prototype.hasOwnProperty.call(overrides, field.name)) {
        const valWat = this.emitExpr(overrides[field.name], locals, field.type);
        stmts.push(`(${storeOp} offset=${field.offset} (local.get $__rt_struct_ptr) ${valWat})`);
      } else if (baseInfo) {
        const bf = baseInfo.def.fields.find((f) => f.name === field.name);
        if (bf) {
          if (field.type === "string") {
            stmts.push(
              `(i32.store offset=${field.offset} (local.get $__rt_struct_ptr) (i32.load offset=${bf.offset} ${baseInfo.ptrWat}))`,
            );
            stmts.push(
              `(i32.store offset=${
                field.offset + 4
              } (local.get $__rt_struct_ptr) (i32.load offset=${
                bf.offset + 4
              } ${baseInfo.ptrWat}))`,
            );
          } else {
            const loadOp = field.type === "f64"
              ? "f64.load"
              : field.type === "i64"
              ? "i64.load"
              : "i32.load";
            stmts.push(
              `(${storeOp} offset=${field.offset} (local.get $__rt_struct_ptr) (${loadOp} offset=${bf.offset} ${baseInfo.ptrWat}))`,
            );
          }
        }
      }
    }
    stmts.push(`(local.get $__rt_struct_ptr)`);
    return `(block (result i32)\n        ${stmts.join("\n        ")}\n      )`;
  }

  // -------------------------------------------------------------------------
  // Phase 51.3: nested destructuring (recursive pattern binding against a struct/tuple def)
  // -------------------------------------------------------------------------

  /** First depth-0 occurrence of `ch` in `s` (ignores chars inside (), [], {}). -1 if none. */
  private static depth0IndexOf(s: string, ch: string): number {
    let depth = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (c === "(" || c === "[" || c === "{") depth++;
      else if (c === ")" || c === "]" || c === "}") depth--;
      else if (c === ch && depth === 0) return i;
    }
    return -1;
  }

  /** Emit a single flat field bind: `(local.set $local (load … offset))`, with the Phase 48
   *  zero-sentinel `= default` fallback when a default is present. */
  private emitFlatFieldBind(
    field: StructField,
    baseWat: string,
    localName: string,
    defaultExpr: string | null,
    locals: Map<string, WatType>,
  ): string {
    const loadOp = field.type === "f64"
      ? "f64.load"
      : field.type === "i64"
      ? "i64.load"
      : "i32.load";
    const loadWat = `(${loadOp} (i32.add ${baseWat} (i32.const ${field.offset})))`;
    if (defaultExpr !== null) {
      const defWat = this.emitExpr(defaultExpr, locals, field.type);
      const eqzWat = field.type === "f64"
        ? `(f64.eq ${loadWat} (f64.const 0.0))`
        : `(i32.eqz ${loadWat})`;
      return `(local.set $${localName} (if (result ${field.type}) ${eqzWat} (then ${defWat}) (else ${loadWat})))`;
    }
    return `(local.set $${localName} ${loadWat})`;
  }

  /** The base-pointer WAT for a nested struct/tuple field: inline tuple fields (`tupleTypeName`)
   *  yield the field address; pointer fields (`structType`) load the stored pointer. */
  private nestedFieldBaseWat(field: StructField, baseWat: string): string {
    return field.tupleTypeName
      ? `(i32.add ${baseWat} (i32.const ${field.offset}))`
      : `(i32.load (i32.add ${baseWat} (i32.const ${field.offset})))`;
  }

  /** Resolve the nested StructDef for a struct/tuple field, or null if not a nested aggregate. */
  private nestedFieldDef(field: StructField): StructDef | null {
    const n = field.structType ?? field.tupleTypeName;
    return n ? this.structDefs.get(n) ?? null : null;
  }

  /** Recursively emit a destructuring pattern (`{ … }` object or `[ … ]` tuple) against a base
   *  pointer + its StructDef. Object bindings match by field name; tuple bindings by position.
   *  A binding whose value is itself a `{…}`/`[…]` pattern recurses into the nested field. */
  private emitDestructurePattern(
    pattern: string,
    baseWat: string,
    def: StructDef,
    locals: Map<string, WatType>,
  ): string[] {
    const stmts: string[] = [];
    const isObject = pattern.trim()[0] === "{";
    const inner = pattern.trim().slice(1, -1);
    const parts = splitBraceAwareCommasKeepEmpty(inner);
    for (let i = 0; i < parts.length; i++) {
      const raw = parts[i].trim();
      if (!raw) continue; // tuple gap: skip a position (index i still advances)
      if (raw.startsWith("...")) continue; // rest element: not supported in tuple destructure (no-op)
      let field: StructField | undefined;
      let valuePart: string; // either a local name (+default) or a nested pattern
      if (isObject) {
        const colon = WasicTranspiler.depth0IndexOf(raw, ":");
        if (colon !== -1) {
          field = def.fields.find((f) => f.name === raw.slice(0, colon).trim());
          valuePart = raw.slice(colon + 1).trim();
        } else {
          // shorthand: "field" or "field = default" — strip the default to get the field name
          const eq = raw.indexOf("=");
          field = def.fields.find((f) => f.name === (eq !== -1 ? raw.slice(0, eq) : raw).trim());
          valuePart = raw;
        }
      } else {
        field = def.fields[i];
        valuePart = raw;
      }
      if (!field) {
        this.diagnostics.push(`Destructuring: no field for binding '${raw}' in '${def.name}'`);
        continue;
      }
      if (valuePart[0] === "{" || valuePart[0] === "[") {
        const nestedDef = this.nestedFieldDef(field);
        if (!nestedDef) {
          this.diagnostics.push(
            `Destructuring: field '${field.name}' is not a nested struct/tuple`,
          );
          continue;
        }
        stmts.push(
          ...this.emitDestructurePattern(
            valuePart,
            this.nestedFieldBaseWat(field, baseWat),
            nestedDef,
            locals,
          ),
        );
      } else {
        const eqIdx = valuePart.indexOf("=");
        const localName = eqIdx !== -1 ? valuePart.slice(0, eqIdx).trim() : valuePart;
        const defaultExpr = eqIdx !== -1 ? valuePart.slice(eqIdx + 1).trim() : null;
        stmts.push(this.emitFlatFieldBind(field, baseWat, localName, defaultExpr, locals));
      }
    }
    return stmts;
  }

  /** Recursively collect (localName, type) for every leaf binding in a destructuring pattern,
   *  for the pre-scan local declarations. Mirrors emitDestructurePattern's structure. */
  private collectDestructureLocals(
    pattern: string,
    def: StructDef,
    out: Array<[string, WatType]>,
  ): void {
    const isObject = pattern.trim()[0] === "{";
    const inner = pattern.trim().slice(1, -1);
    const parts = splitBraceAwareCommasKeepEmpty(inner);
    for (let i = 0; i < parts.length; i++) {
      const raw = parts[i].trim();
      if (!raw || raw.startsWith("...")) continue;
      let field: StructField | undefined;
      let valuePart: string;
      if (isObject) {
        const colon = WasicTranspiler.depth0IndexOf(raw, ":");
        if (colon !== -1) {
          field = def.fields.find((f) => f.name === raw.slice(0, colon).trim());
          valuePart = raw.slice(colon + 1).trim();
        } else {
          const eq = raw.indexOf("=");
          field = def.fields.find((f) => f.name === (eq !== -1 ? raw.slice(0, eq) : raw).trim());
          valuePart = raw;
        }
      } else {
        field = def.fields[i];
        valuePart = raw;
      }
      if (!field) continue;
      if (valuePart[0] === "{" || valuePart[0] === "[") {
        const nestedDef = this.nestedFieldDef(field);
        if (nestedDef) this.collectDestructureLocals(valuePart, nestedDef, out);
      } else {
        const eqIdx = valuePart.indexOf("=");
        const localName = eqIdx !== -1 ? valuePart.slice(0, eqIdx).trim() : valuePart;
        out.push([localName, field.type]);
      }
    }
  }

  /** Phase 51.3: recursively emit the element stores for a tuple literal RHS (without the outer
   *  brackets), handling nested tuple literals by recursing inline at `baseOffset + field.offset`.
   *  `basePtr` is the WAT local name holding the (malloc'd) tuple pointer. */
  private emitTupleLiteralStores(
    elementsStr: string,
    basePtr: string,
    def: StructDef,
    baseOffset: number,
    locals: Map<string, WatType>,
  ): string[] {
    const elements = splitBraceAwareCommas(elementsStr).map((e) => e.trim()).filter(Boolean);
    const stmts: string[] = [];
    for (let i = 0; i < elements.length; i++) {
      const field = def.fields[i];
      if (!field) continue;
      const elem = elements[i];
      if (field.tupleTypeName && elem.startsWith("[")) {
        const nested = this.structDefs.get(field.tupleTypeName);
        if (nested) {
          stmts.push(
            ...this.emitTupleLiteralStores(
              elem.slice(1, -1),
              basePtr,
              nested,
              baseOffset + field.offset,
              locals,
            ),
          );
          continue;
        }
      }
      const storeOp = field.type === "f64"
        ? "f64.store"
        : field.type === "i64"
        ? "i64.store"
        : "i32.store";
      const valWat = this.emitExpr(elem, locals, field.type);
      stmts.push(
        `(${storeOp} offset=${baseOffset + field.offset} (local.get $${basePtr}) ${valWat})`,
      );
    }
    return stmts;
  }

  // -------------------------------------------------------------------------
  // String data allocation
  // -------------------------------------------------------------------------
  private allocString(raw: string): [number, number] {
    const msg = unescapeString(raw); // process escape sequences from source code
    const existing = this.dataMap.get(msg);
    if (existing) return existing;
    const bytes = new TextEncoder().encode(msg);
    const entry: [number, number] = [this.dataOffset, bytes.length];
    this.dataMap.set(msg, entry);
    this.dataOffset += bytes.length;
    // NOTE: do NOT set hasConsoleLog here. Allocating string DATA is unrelated to
    // whether the module emits console output via fd_write. Every console.log/error/warn
    // handler sets hasConsoleLog explicitly before emitting fd_write (and console_log.ts's
    // fd_write emission only runs through those handlers). Setting it here caused any
    // string-literal allocation — e.g. a string-returning modc library function like
    // `greet(n) { return "Hi, " + n; }` with no console at all — to import an unused
    // `wasi_snapshot_preview1.fd_write`, which a non-WASI host (bindgen loader) can't supply.
    return entry;
  }

  /** Allocates an ALREADY-DECODED string (no escape processing). Used for compile-time
   *  computed strings such as String.fromCodePoint(...) whose characters must be UTF-8
   *  encoded verbatim — running unescapeString on them could re-interpret a produced
   *  backslash/quote as an escape sequence. */
  private allocStringDecoded(s: string): [number, number] {
    const existing = this.dataMap.get(s);
    if (existing) return existing;
    const bytes = new TextEncoder().encode(s);
    const entry: [number, number] = [this.dataOffset, bytes.length];
    this.dataMap.set(s, entry);
    this.dataOffset += bytes.length;
    return entry;
  }

  /** Phase 52.9: evaluate a String.fromCodePoint argument as a compile-time code point.
   *  Returns the integer code point for a decimal/hex literal in the valid Unicode range,
   *  or null if the argument is a runtime expression / out of range. */
  private constCodePoint(a: string): number | null {
    const t = a.trim();
    let n: number;
    if (/^-?\d+$/.test(t)) n = parseInt(t, 10);
    else if (/^0[xX][0-9a-fA-F]+$/.test(t)) n = parseInt(t, 16);
    else return null;
    if (n < 0 || n > 0x10FFFF) return null; // String.fromCodePoint would throw
    return n;
  }

  /** Phase 52.8: source pre-pass — rewrite `Array.from([…])` → `[…]` and `Array.of(…)` → `[…]`.
   *  Array.from of an array literal is exactly that literal; Array.of(a,b,c) is [a,b,c]. Uses a
   *  string-aware balanced-bracket scan (so brackets inside string elements don't confuse it) and
   *  recurses into the rewritten argument so nested Array.from/of are also expanded. Array.from of
   *  anything other than a literal array (an iterable / a {length} form) is left untouched. */
  private expandArrayFromOf(src: string): string {
    // True when `s` is a single array literal whose opening `[` is closed by its final char.
    const isWholeBracket = (s: string): boolean => {
      if (!s.startsWith("[")) return false;
      let d = 0, inS = false, inD = false, inB = false;
      for (let p = 0; p < s.length; p++) {
        const c = s[p];
        if (inS) {
          if (c === "\\") p++;
          else if (c === "'") inS = false;
          continue;
        }
        if (inD) {
          if (c === "\\") p++;
          else if (c === '"') inD = false;
          continue;
        }
        if (inB) {
          if (c === "\\") p++;
          else if (c === "`") inB = false;
          continue;
        }
        if (c === "'") inS = true;
        else if (c === '"') inD = true;
        else if (c === "`") inB = true;
        else if (c === "[" || c === "(" || c === "{") d++;
        else if (c === "]" || c === ")" || c === "}") {
          d--;
          if (d === 0) return p === s.length - 1;
        }
      }
      return false;
    };
    let out = "";
    let i = 0;
    while (i < src.length) {
      const fromHit = src.startsWith("Array.from", i);
      const ofHit = !fromHit && src.startsWith("Array.of", i);
      // Reject a match that is part of a longer identifier (e.g. `MyArray.from`).
      const prevOk = i === 0 || !/[\w$]/.test(src[i - 1]);
      if ((fromHit || ofHit) && prevOk) {
        const kw = fromHit ? "Array.from" : "Array.of";
        let j = i + kw.length;
        while (j < src.length && /\s/.test(src[j])) j++;
        if (src[j] === "(") {
          let depth = 0, end = -1, inS = false, inD = false, inB = false;
          for (let k = j; k < src.length; k++) {
            const c = src[k];
            if (inS) {
              if (c === "\\") k++;
              else if (c === "'") inS = false;
              continue;
            }
            if (inD) {
              if (c === "\\") k++;
              else if (c === '"') inD = false;
              continue;
            }
            if (inB) {
              if (c === "\\") k++;
              else if (c === "`") inB = false;
              continue;
            }
            if (c === "'") inS = true;
            else if (c === '"') inD = true;
            else if (c === "`") inB = true;
            else if (c === "(" || c === "[" || c === "{") depth++;
            else if (c === ")" || c === "]" || c === "}") {
              depth--;
              if (depth === 0) {
                end = k;
                break;
              }
            }
          }
          if (end !== -1) {
            const inner = src.slice(j + 1, end).trim();
            if (ofHit) {
              out += "[" + this.expandArrayFromOf(inner) + "]";
              i = end + 1;
              continue;
            }
            if (isWholeBracket(inner)) {
              out += this.expandArrayFromOf(inner);
              i = end + 1;
              continue;
            }
          }
        }
      }
      out += src[i];
      i++;
    }
    return out;
  }

  /** Phase 52.7: does the struct/class type of `objName` declare a field named `field`?
   *  Returns true/false when the variable's type is known, or null when it isn't (so the
   *  `in` operator can fall through rather than emit a wrong constant). */
  private structHasField(objName: string, field: string): boolean | null {
    const sv = this.structVars.get(objName);
    if (sv) return sv.def.fields.some((f) => f.name === field);
    const cv = this.classVars.get(objName);
    if (cv) {
      const cd = this.classDefs.get(cv.className);
      if (cd) return cd.struct.fields.some((f) => f.name === field);
    }
    return null;
  }

  /** Allocates a static numeric array in the data section with an 8-byte header.
   *  Layout: [length i32][capacity i32][elem0][elem1]...
   *  Returns pointer to the header (same format as dynamic arrays). */
  private allocArrayData(elements: string[], elemType: WatType): number {
    const ptr = this.dataOffset;
    // String arrays: 8 bytes per element (ptr i32 + len i32); allocate each string separately.
    // Strings must be allocated FIRST (advancing dataOffset past all string data),
    // then the array header + ptr/len pairs are placed at the new dataOffset to avoid overlap.
    if (elemType === "string") {
      const elemSize = 8;
      const strPtrs: Array<[number, number]> = [];
      for (const elem of elements) {
        const e = elem.trim().replace(/^["']|["']$/g, "");
        strPtrs.push(this.allocString(e));
      }
      const arrPtr = this.dataOffset;
      const header = encodeI32LE(elements.length) + encodeI32LE(elements.length);
      let encoded = header;
      for (const [strPtr, strLen] of strPtrs) {
        encoded += encodeI32LE(strPtr) + encodeI32LE(strLen);
      }
      if (encoded) this.rawDataSegments.push({ ptr: arrPtr, bytes: encoded });
      this.dataOffset += 8 + elements.length * elemSize;
      return arrPtr;
    }
    const elemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
    // 8-byte header: length (i32) + capacity (i32, same as length for static)
    const header = encodeI32LE(elements.length) + encodeI32LE(elements.length);
    let encoded = header;
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
    this.dataOffset += 8 + elements.length * elemSize;
    return ptr;
  }

  // -------------------------------------------------------------------------
  // Dynamic array helpers (Phase 10b)
  // -------------------------------------------------------------------------

  /** Phase 49: Splits an expression into outermost method call parts (receiver, method, args). */
  private splitLastMethodCall(
    expr: string,
  ): { receiver: string; method: string; args: string } | null {
    if (!expr.endsWith(")")) return null;
    let depth = 0, openIdx = -1;
    for (let i = expr.length - 1; i >= 0; i--) {
      const ch = expr[i];
      if (ch === ")") depth++;
      else if (ch === "(") {
        if (--depth === 0) {
          openIdx = i;
          break;
        }
      }
    }
    if (openIdx <= 0) return null;
    const args = expr.slice(openIdx + 1, expr.length - 1);
    const beforeParen = expr.slice(0, openIdx);
    const lastDot = beforeParen.lastIndexOf(".");
    if (lastDot < 0) return null;
    const receiver = beforeParen.slice(0, lastDot);
    const method = beforeParen.slice(lastDot + 1);
    if (!receiver || !/^\w+$/.test(method)) return null;
    return { receiver, method, args };
  }

  /** Phase 49: Infer the element type of a (possibly chained) array expression. */
  private inferChainElemType(expr: string, locals: Map<string, string>): string | null {
    const ai = this.arrayVars.get(expr);
    if (ai?.dynamic) return ai.elemType as string;
    const parsed = this.splitLastMethodCall(expr);
    if (!parsed) return null;
    const baseType = this.inferChainElemType(parsed.receiver, locals);
    if (!baseType) return null;
    // These methods preserve or return the same element type
    const preserving = [
      "filter",
      "map",
      "slice",
      "reverse",
      "fill",
      "sort",
      "flat",
      "flatMap",
      "concat",
    ];
    if (preserving.includes(parsed.method)) return baseType;
    return null;
  }

  /** Scans function body lines for array method calls to determine which arrays need heap layout. */
  private findDynamicArrays(lines: string[]): Set<string> {
    const dynamic = new Set<string>();
    for (const line of lines) {
      // Method calls that require heap layout
      const m = line.match(
        /\b(\w+)\.(push|pop|shift|unshift|indexOf|includes|slice|forEach|map|filter|find|reduce|every|some|findIndex|at|reverse|fill|join|sort|flat|flatMap|splice|concat)\s*\(/,
      );
      if (m) dynamic.add(m[1]);
      // Phase 6d: subscript method call: matrix[i].push(...) — outer array must be dynamic
      const subM = line.match(/\b(\w+)\[.+?\]\.(push|pop|shift|unshift)\s*\(/);
      if (subM) dynamic.add(subM[1]);
      // Spread usages: ...arrName in calls or array literals — source must have heap layout
      for (const sm of line.matchAll(/\.\.\.\s*(\w+)/g)) {
        dynamic.add(sm[1]);
      }
    }
    return dynamic;
  }

  /** Emits WAT statements that malloc + initialise a dynamic array (length/capacity header + elements). */
  private emitDynArrayInit(varName: string, info: {
    elemType: WatType;
    length: number;
    capacity?: number;
    initElements?: string[];
  }): string {
    const capacity = info.capacity ?? Math.max(info.length * 2, 8);
    const elemSize =
      (info.elemType === "f64" || info.elemType === "i64" || info.elemType === "string") ? 8 : 4;
    const byteSize = capacity * elemSize + 8; // 8-byte header: [length i32][capacity i32]
    const storeOp = info.elemType === "f64"
      ? "f64.store"
      : info.elemType === "i64"
      ? "i64.store"
      : "i32.store";

    const getWat = this.arrGetWat(varName);
    const stmts: string[] = [];
    stmts.push(this.arrSetWat(varName, `(call $__malloc (i32.const ${byteSize}))`));
    stmts.push(`(i32.store ${getWat} (i32.const ${info.length}))`);
    stmts.push(`(i32.store offset=4 ${getWat} (i32.const ${capacity}))`);

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
      stmts.push(`(${storeOp} offset=${byteOffset} ${getWat} ${valExpr})`);
    }
    return stmts.join("\n      ");
  }

  /** Phase 6d: Emits WAT to malloc + init a 2D dynamic array (outer stores i32 row-ptrs). */
  private emitDynArray2DInit(varName: string, info: {
    elemType: WatType;
    rows: string[][];
  }): string {
    const outerLen = info.rows.length;
    const outerCap = Math.max(outerLen * 2, 8);
    const outerSize = outerCap * 4 + 8; // outer elements are i32 ptrs (4 bytes each)
    const elemSize = (info.elemType === "f64" || info.elemType === "i64") ? 8 : 4;
    const storeOp = info.elemType === "f64"
      ? "f64.store"
      : info.elemType === "i64"
      ? "i64.store"
      : "i32.store";
    const stmts: string[] = [];

    // Allocate outer array
    stmts.push(`(local.set $${varName} (call $__malloc (i32.const ${outerSize})))`);
    stmts.push(`(i32.store (local.get $${varName}) (i32.const ${outerLen}))`);
    stmts.push(`(i32.store offset=4 (local.get $${varName}) (i32.const ${outerCap}))`);

    // For each row: allocate, init, and store its pointer in the outer array
    for (let i = 0; i < info.rows.length; i++) {
      const row = info.rows[i];
      const rowCap = Math.max(row.length * 2, 8);
      const rowSz = rowCap * elemSize + 8;
      const outerSlotOffset = 8 + i * 4;
      // tee $__2d_tmp so we can init the row immediately after storing its ptr
      stmts.push(
        `(i32.store offset=${outerSlotOffset} (local.get $${varName}) (local.tee $__2d_tmp (call $__malloc (i32.const ${rowSz}))))`,
      );
      stmts.push(`(i32.store (local.get $__2d_tmp) (i32.const ${row.length}))`);
      stmts.push(`(i32.store offset=4 (local.get $__2d_tmp) (i32.const ${rowCap}))`);
      for (let j = 0; j < row.length; j++) {
        const raw = row[j].trim();
        const off = 8 + j * elemSize;
        const val = info.elemType === "f64"
          ? `(f64.const ${parseFloat(raw) || 0})`
          : info.elemType === "i64"
          ? `(i64.const ${parseInt(raw.replace(/n$/, ""), 10) || 0})`
          : `(i32.const ${parseInt(raw, 10) || 0})`;
        stmts.push(`(${storeOp} offset=${off} (local.get $__2d_tmp) ${val})`);
      }
    }
    return stmts.join("\n      ");
  }

  /** Phase 18 fix: Emits WAT to runtime-initialize a 2D array from Array.from({ length: N }, () => []).
   *  Allocates N inner arrays each pre-sized with DEFAULT_INNER_CAP elements. */
  private emitArrayFromInit(
    varName: string,
    elemType: WatType,
    lenExpr: string,
    locals: Map<string, WatType>,
  ): string {
    const DEFAULT_INNER_CAP = 32;
    const innerElemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
    const innerSize = 8 + DEFAULT_INNER_CAP * innerElemSize;
    const lenWat = this.emitExpr(lenExpr, locals, "i32");
    const stmts = [
      `(local.set $__from_n ${lenWat})`,
      `(local.set $${varName} (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $__from_n) (i32.const 2)))))`,
      `(i32.store (local.get $${varName}) (local.get $__from_n))`,
      `(i32.store offset=4 (local.get $${varName}) (local.get $__from_n))`,
      `(local.set $__from_i (i32.const 0))`,
      `(block $__from_blk`,
      `  (loop $__from_lp`,
      `    (br_if $__from_blk (i32.ge_s (local.get $__from_i) (local.get $__from_n)))`,
      `    (local.set $__2d_tmp (call $__malloc (i32.const ${innerSize})))`,
      `    (i32.store (local.get $__2d_tmp) (i32.const 0))`,
      `    (i32.store offset=4 (local.get $__2d_tmp) (i32.const ${DEFAULT_INNER_CAP}))`,
      `    (i32.store (i32.add (i32.add (local.get $${varName}) (i32.const 8)) (i32.shl (local.get $__from_i) (i32.const 2))) (local.get $__2d_tmp))`,
      `    (local.set $__from_i (i32.add (local.get $__from_i) (i32.const 1)))`,
      `    (br $__from_lp)`,
      `  )`,
      `)`,
    ];
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
      const m = line.match(
        /^\s*(?:(?:var|let|const)\s+\w+\s*(?::\s*[\w\[\]]+)?\s*=\s*)?(\w+)\s*\(([^)]*)\)/,
      );
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
    expectReturn: WatType | null,
  ): string {
    const fnDef = this.functions.find((f: FuncDef) => f.name === fnName)!;
    const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
    const normalArgs = allArgs.slice(0, restIdx);
    const restArgs = allArgs.slice(restIdx);
    const restParam = fnDef.params[restIdx];
    const elemType = restParam.arrayElemType ?? "i32";
    const elemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
    const storeOp = elemType === "f64"
      ? "f64.store"
      : elemType === "i64"
      ? "i64.store"
      : "i32.store";
    const len = restArgs.length;
    const capacity = Math.max(len * 2, 8);
    const byteSize = capacity * elemSize + 8;

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
    if (fnDef.result !== null && !expectReturn) {
      // Non-void function used as statement — discard the return value
      lines.push(`(drop ${callExpr})`);
    } else {
      // Void function (nothing to drop) or return value is needed
      lines.push(callExpr);
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
    elemType: WatType,
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
      stmts.push(
        `(local.set $${varName} (call $__dynarr_concat_${suffix} (local.get $${varName}) (local.get $${
          spreads[i]
        })))`,
      );
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
    locals: Map<string, WatType>,
  ): string {
    const inner = this.emitStringAssignInner(varName, initExpr, locals);
    // If the assignment TARGET is a mutable module-level string global, rewrite its ptr/len
    // local.set/local.get into global.set/global.get so the write persists across function calls.
    if (this.moduleStringGlobals.has(varName)) {
      return inner
        .replace(
          new RegExp(`\\(local\\.set \\$${varName}_(ptr|len)`, "g"),
          `(global.set $${varName}_$1`,
        )
        .replace(
          new RegExp(`\\(local\\.get \\$${varName}_(ptr|len)`, "g"),
          `(global.get $${varName}_$1`,
        );
    }
    return inner;
  }

  private emitStringAssignInner(
    varName: string,
    initExpr: string,
    locals: Map<string, WatType>,
  ): string {
    this.stringVars.add(varName);
    // If this module-level string was pre-registered as a static const, invalidate it now
    // because the variable is being (re)assigned and is no longer a static constant.
    this.moduleStringConsts.delete(varName);
    const ind = "      ";

    // Phase 24: null/undefined → set ptr=0, len=0 (null string pointer convention)
    if (initExpr === "null" || initExpr === "undefined") {
      return [
        `(local.set $${varName}_ptr (i32.const 0))`,
        `${ind}(local.set $${varName}_len (i32.const 0))`,
      ].join("\n");
    }

    // Phase 35: typeof x → static type-name string (e.g. "number", "string", "boolean")
    const typeofSAMatch = initExpr.match(/^typeof\s+(\w+)$/);
    if (typeofSAMatch) {
      const typeStr = this.resolveTypeofString(typeofSAMatch[1]!, locals);
      const [offset, len] = this.allocString(typeStr);
      return [
        `(local.set $${varName}_ptr (i32.const ${offset}))`,
        `${ind}(local.set $${varName}_len (i32.const ${len}))`,
      ].join("\n");
    }

    // Template literal: `...${expr}...`
    if (initExpr.startsWith("`") && initExpr.endsWith("`")) {
      const parts = this.splitTemplateLiteral(initExpr.slice(1, -1));
      // Single text segment → string literal
      if (parts.length === 1 && parts[0].kind === "text") {
        const [offset, len] = this.allocString(parts[0].value);
        return [
          `(local.set $${varName}_ptr (i32.const ${offset}))`,
          `${ind}(local.set $${varName}_len (i32.const ${len}))`,
        ].join("\n");
      }
      // Single expression → String(expr) or string-var/fn copy
      if (parts.length === 1 && parts[0].kind === "expr") {
        const e = parts[0].value.trim();
        const eType = this.inferExprType(e, locals);
        if (eType === "string") return this.emitStringAssign(varName, e, locals);
        return this.emitStringAssign(varName, `String(${e})`, locals);
      }
      // Multi-part: build concat chain using emitConcat helper
      const tmplStmts: string[] = [];
      let tmplHasFirst = false;
      const emitTmplConcat = (ptrWat2: string, lenWat2: string) => {
        if (!tmplHasFirst) {
          tmplStmts.push(`(local.set $${varName}_ptr ${ptrWat2})`);
          tmplStmts.push(`(local.set $${varName}_len ${lenWat2})`);
          tmplHasFirst = true;
        } else {
          this.needsStringOpHelpers = true;
          tmplStmts.push(
            `(call $__str_concat (local.get $${varName}_ptr) (local.get $${varName}_len) ${ptrWat2} ${lenWat2})`,
          );
          tmplStmts.push(`(local.set $${varName}_len)`);
          tmplStmts.push(`(local.set $${varName}_ptr)`);
        }
      };
      let numericTmpIdx = 0;
      for (const seg of parts) {
        if (seg.kind === "text") {
          if (!seg.value) continue;
          const [off, ln] = this.allocString(seg.value);
          emitTmplConcat(`(i32.const ${off})`, `(i32.const ${ln})`);
        } else {
          const e = seg.value.trim();
          const eType = this.inferExprType(e, locals);
          if (eType === "string") {
            if (/^\w+$/.test(e) && this.moduleStringConsts.has(e)) {
              const [off, ln] = this.moduleStringConsts.get(e)!;
              emitTmplConcat(`(i32.const ${off})`, `(i32.const ${ln})`);
            } else if (/^\w+$/.test(e) && locals.get(e) === "string") {
              emitTmplConcat(`(local.get $${e}_ptr)`, `(local.get $${e}_len)`);
            } else {
              // String array element: arr[idx] where arr is string[]
              const strArrSegM = e.match(/^(\w+)\[([^\]]+)\]$/);
              if (strArrSegM) {
                const segArrInfo = this.arrayVars.get(strArrSegM[1]);
                if (segArrInfo && (segArrInfo.isStringArr || segArrInfo.elemType === "string")) {
                  const segIdxWat = this.emitArrayIndex(strArrSegM[2].trim(), locals);
                  const segBase = (segArrInfo.ptr === -1 || segArrInfo.dynamic)
                    ? this.arrGetWat(strArrSegM[1])
                    : `(i32.const ${segArrInfo.ptr})`;
                  const segAddr =
                    `(i32.add (i32.add ${segBase} (i32.const 8)) (i32.shl ${segIdxWat} (i32.const 3)))`;
                  emitTmplConcat(`(i32.load ${segAddr})`, `(i32.load offset=4 ${segAddr})`);
                  continue;
                }
              }
              // padStart/padEnd in template: `${expr.padStart(n[, pad])}`. Receiver may be a string
              // literal, var, or string-returning call (resolved via emitStringPtrLen). Single-arg
              // form defaults the pad to a space. Captured into the $__str_op temp pair. Must come
              // before the function-call handler so `toFixed(..).padStart(6)` isn't mis-parsed.
              const padTmplM = e.match(/^(.+)\.(padStart|padEnd)\s*\((.+)\)$/);
              if (padTmplM && parenDepthNeverNegative(padTmplM[3]!)) {
                const recvPtrLen = this.quietEmit(() =>
                  this.emitStringPtrLen(padTmplM[1]!.trim(), locals)
                );
                if (recvPtrLen !== "(i32.const 0) (i32.const 0)") {
                  this.needsStringExtHelpers = true;
                  const helper = padTmplM[2] === "padStart" ? "$__str_pad_start" : "$__str_pad_end";
                  const padArgs = this.splitArgs(padTmplM[3]!);
                  const targetWat = this.emitExpr(padArgs[0]!.trim(), locals, "i32");
                  let padStrLen: string;
                  if (padArgs.length >= 2) {
                    padStrLen = this.emitStringPtrLen(padArgs[1]!.trim(), locals);
                  } else {
                    const [po, pl] = this.allocString(" ");
                    padStrLen = `(i32.const ${po}) (i32.const ${pl})`;
                  }
                  tmplStmts.push(`(call ${helper} ${recvPtrLen} ${targetWat} ${padStrLen})`);
                  tmplStmts.push(`(local.set $__str_op_len)`);
                  tmplStmts.push(`(local.set $__str_op_ptr)`);
                  emitTmplConcat(`(local.get $__str_op_ptr)`, `(local.get $__str_op_len)`);
                  continue;
                }
              }
              // String-returning function call in template
              const strFnM2 = e.match(/^(\w+)\s*\(/);
              const strFn2 = strFnM2
                ? this.functions.find((f) => f.name === strFnM2[1] && f.result === "string")
                : undefined;
              if (strFn2) {
                const rawArgs2 = e.slice(strFnM2![1].length + 1, e.endsWith(")") ? -1 : e.length)
                  .trim();
                const argList2 = rawArgs2 ? this.splitArgs(rawArgs2) : [];
                const watArgs2 = argList2.flatMap((a, i) => {
                  const p = strFn2.params[i];
                  if (!p) return [this.emitExpr(a.trim(), locals, "i32")];
                  if (p.type === "string") return [this.emitStringPtrLen(a.trim(), locals)];
                  return [this.emitExpr(a.trim(), locals, p.type)];
                });
                tmplStmts.push(
                  watArgs2.length > 0
                    ? `(call $${strFn2.name} ${watArgs2.join(" ")})`
                    : `(call $${strFn2.name})`,
                );
                emitTmplConcat(`(global.get $__str_ret_ptr)`, `(global.get $__str_ret_len)`);
                continue;
              }
              // General fallback: struct field access, struct array field access, etc.
              const ptrLenTmplFallback = this.quietEmit(() => this.emitStringPtrLen(e, locals));
              if (ptrLenTmplFallback !== "(i32.const 0) (i32.const 0)") {
                const [pWtf, lWtf] = splitTwoWatExprs(ptrLenTmplFallback);
                emitTmplConcat(pWtf, lWtf);
              }
            }
          } else {
            // Numeric segment: convert to string using the pre-declared shared temp pair $__tmpl_num_ptr/$__tmpl_num_len.
            // We reuse the same pair for every numeric segment (safe because each concat happens immediately after).
            numericTmpIdx++;
            this.needsNumericHelpers = true;
            const helper = eType === "f64"
              ? "$__f64_to_str"
              : eType === "i64"
              ? "$__i64_to_str"
              : "$__i32_to_str";
            const valWat = this.emitExpr(e, locals, eType);
            tmplStmts.push(`(local.set $__tmpl_num_ptr (call $__malloc (i32.const 32)))`);
            tmplStmts.push(
              `(local.set $__tmpl_num_len (call ${helper} ${valWat} (local.get $__tmpl_num_ptr)))`,
            );
            emitTmplConcat(`(local.get $__tmpl_num_ptr)`, `(local.get $__tmpl_num_len)`);
          }
        }
      }
      if (!tmplHasFirst) {
        const [off, ln] = this.allocString("");
        tmplStmts.push(`(local.set $${varName}_ptr (i32.const ${off}))`);
        tmplStmts.push(`(local.set $${varName}_len (i32.const ${ln}))`);
      }
      return tmplStmts.join(`\n${ind}`);
    }
    // VAR instanceof Error ? VAR.message : <else> — idiomatic catch pattern.
    // In wasic, all exceptions are stored as plain strings (ptr+len); e.message === e and
    // `instanceof Error` is always true, so the THEN branch is always taken regardless of the
    // else expression (String(VAR), `${VAR}`, etc.). Simplify to a direct ptr/len copy.
    {
      const errTernary = initExpr.match(
        /^(\w+)\s+instanceof\s+Error\s*\?\s*\1\.message\s*:\s*.+$/,
      );
      if (errTernary) {
        const varE = errTernary[1]!;
        if (locals.get(varE) === "string") {
          return [
            `(local.set $${varName}_ptr (local.get $${varE}_ptr))`,
            `${ind}(local.set $${varName}_len (local.get $${varE}_len))`,
          ].join("\n");
        }
      }
    }

    // Ternary: cond ? stringExpr1 : stringExpr2
    {
      const qIdx = this.findBinaryOp(initExpr, "?");
      if (qIdx !== -1) {
        const rest = initExpr.slice(qIdx + 1);
        const cIdx = this.findBinaryOp(rest, ":");
        if (cIdx !== -1) {
          const cond = initExpr.slice(0, qIdx).trim();
          const thenExpr = rest.slice(0, cIdx).trim();
          const elseExpr = rest.slice(cIdx + 1).trim();
          // Both branches must be string expressions
          if (this.isStringExpr(thenExpr, locals) && this.isStringExpr(elseExpr, locals)) {
            const condWat = this.emitExpr(cond, locals, "i32");
            const thenWat = this.emitStringAssign(`${varName}__then`, thenExpr, locals);
            const elseWat = this.emitStringAssign(`${varName}__else`, elseExpr, locals);
            // Rewrite assignments to target varName
            const fixBranch = (wat: string, from: string): string =>
              wat.replace(new RegExp(`\\$${from}_(ptr|len)`, "g"), `$${varName}_$1`);
            return [
              `(if ${condWat}`,
              `${ind}  (then`,
              `${ind}    ${fixBranch(thenWat, `${varName}__then`)}`,
              `${ind}  )`,
              `${ind}  (else`,
              `${ind}    ${fixBranch(elseWat, `${varName}__else`)}`,
              `${ind}  )`,
              `${ind})`,
            ].join("\n");
          }
        }
      }
    }

    // Call to a closure/funcref PARAM that returns a string (e.g. mapStr's `fn(arr[i])` where
    // `fn: (s) => string`). The callee is a string-returning function called via call_indirect; its
    // WAT body is void and writes the $__str_ret globals, which we then read into varName_ptr/len.
    {
      const indM = initExpr.match(/^(\w+)\s*\((.*)?\)\s*;?$/);
      if (indM) {
        const callee = indM[1]!;
        const ftv = this.funcTypeVars.get(callee);
        const ctv = this.closureTypedVars.get(callee);
        if ((ftv && ftv.result === "string") || (ctv && ctv.result === "string")) {
          const sig = (ftv ?? ctv)!;
          const rawArgs = indM[2]?.trim() ?? "";
          const argList = rawArgs ? this.splitArgs(rawArgs) : [];
          const emittedArgs = argList.flatMap((a, idx) => {
            const pt = (sig.params[idx] ?? "i32") as WatType;
            if (pt === "string") return [this.emitStringPtrLen(a.trim(), locals)];
            return [this.emitExpr(a.trim(), locals, pt)];
          });
          let callWat: string;
          if (ftv) {
            // funcType param: string result → void WAT fn, so the call_indirect type result is null.
            const typeName = this.getOrCreateFuncType(sig.params as WatType[], null);
            callWat = `(call_indirect (type ${typeName}) ${
              emittedArgs.join(" ")
            } (local.get $${callee}))`;
          } else {
            // capturing closure param: trampoline takes the closure struct ptr as the first arg.
            const trampParams: WatType[] = ["i32" as WatType, ...(sig.params as WatType[])];
            const typeName = this.getOrCreateFuncType(trampParams, null);
            callWat = `(call_indirect (type ${typeName}) (local.get $${callee}) ${
              emittedArgs.join(" ")
            } (i32.load (local.get $${callee})))`;
          }
          return [
            callWat,
            `(local.set $${varName}_ptr (global.get $__str_ret_ptr))`,
            `${ind}(local.set $${varName}_len (global.get $__str_ret_len))`,
          ].join("\n");
        }
      }
    }

    // Call to a string-returning user function: funcName(args)
    {
      const callM = initExpr.match(/^(\w+)\s*\((.*)?\)\s*;?$/);
      if (callM) {
        const callee = callM[1];
        const strFn = this.functions.find((f) => f.name === callee && f.result === "string");
        if (strFn) {
          const rawArgs = callM[2]?.trim() ?? "";
          const argList = rawArgs ? this.splitArgs(rawArgs) : [];
          const watArgs = argList.flatMap((a, i) => {
            const p = strFn.params[i];
            if (!p) return [this.emitExpr(a.trim(), locals, "i32")];
            if (p.type === "string") return [this.emitStringPtrLen(a.trim(), locals)];
            return [this.emitExpr(a.trim(), locals, p.type)];
          });
          const callWat = watArgs.length > 0
            ? `(call $${callee} ${watArgs.join(" ")})`
            : `(call $${callee})`;
          return [
            callWat,
            `(local.set $${varName}_ptr (global.get $__str_ret_ptr))`,
            `${ind}(local.set $${varName}_len (global.get $__str_ret_len))`,
          ].join("\n");
        }
      }
    }

    // String literal — escape-aware so `\"` / `\\` inside the literal (e.g. an embedded JSON
    // document) don't terminate the match early; allocString → unescapeString decodes them.
    const litMatch = initExpr.match(/^"((?:[^"\\]|\\.)*)"$/) ??
      initExpr.match(/^'((?:[^'\\]|\\.)*)'$/);
    if (litMatch) {
      const [offset, len] = this.allocString(litMatch[1]);
      return [
        `(local.set $${varName}_ptr (i32.const ${offset}))`,
        `${ind}(local.set $${varName}_len (i32.const ${len}))`,
      ].join("\n");
    }

    // Phase 29: string enum value — EnumName.MemberName
    const strEnumAssignMatch = initExpr.match(/^(\w+)\.(\w+)$/);
    if (strEnumAssignMatch) {
      const strVal = this.enumStringValues.get(`${strEnumAssignMatch[1]}.${strEnumAssignMatch[2]}`);
      if (strVal !== undefined) {
        const [offset, len] = this.allocString(strVal);
        return [
          `(local.set $${varName}_ptr (i32.const ${offset}))`,
          `${ind}(local.set $${varName}_len (i32.const ${len}))`,
        ].join("\n");
      }
    }

    // Source is a mutable module-level string global — read via global.get
    if (/^\w+$/.test(initExpr) && this.moduleStringGlobals.has(initExpr)) {
      return [
        `(local.set $${varName}_ptr (global.get $${initExpr}_ptr))`,
        `${ind}(local.set $${varName}_len (global.get $${initExpr}_len))`,
      ].join("\n");
    }

    // Another string variable
    if (/^\w+$/.test(initExpr) && this.stringVars.has(initExpr)) {
      return [
        `(local.set $${varName}_ptr (local.get $${initExpr}_ptr))`,
        `${ind}(local.set $${varName}_len (local.get $${initExpr}_len))`,
      ].join("\n");
    }

    // str.slice(start[, end]) → call $__str_slice (multi-value → ptr, len)
    // Supports both str.slice(start, end) and str.slice(start) (end defaults to str length)
    const sliceAnyM = initExpr.match(/^(\w+)\.slice\s*\((.+)\)$/);
    if (
      sliceAnyM && locals.get(sliceAnyM[1]) === "string" && parenDepthNeverNegative(sliceAnyM[2])
    ) {
      const sliceArgs = this.splitArgs(sliceAnyM[2]);
      if (sliceArgs.length === 1 || sliceArgs.length === 2) {
        this.needsStringOpHelpers = true;
        const recv = sliceAnyM[1];
        const startWat = this.emitArrayIndex(sliceArgs[0].trim(), locals);
        const endWat = sliceArgs.length === 2
          ? this.emitArrayIndex(sliceArgs[1].trim(), locals)
          : `(local.get $${recv}_len)`;
        return [
          `(call $__str_slice (local.get $${recv}_ptr) (local.get $${recv}_len) ${startWat} ${endWat})`,
          `${ind}(local.set $${varName}_len)`,
          `${ind}(local.set $${varName}_ptr)`,
        ].join("\n");
      }
    }

    // Phase 27: str.trim() / str.trimStart() / str.trimEnd()
    const trimMatch = initExpr.match(/^(\w+)\.(trim(?:Start|End|Left|Right)?)\s*\(\s*\)$/);
    if (trimMatch && locals.get(trimMatch[1]) === "string") {
      this.needsStringExtHelpers = true;
      this.needsStringOpHelpers = true;
      const helperName = trimMatch[2] === "trim"
        ? "$__str_trim"
        : (trimMatch[2] === "trimStart" || trimMatch[2] === "trimLeft")
        ? "$__str_trim_start"
        : "$__str_trim_end";
      return [
        `(call ${helperName} (local.get $${trimMatch[1]}_ptr) (local.get $${trimMatch[1]}_len))`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // Phase 49: str.at(n) → (ptr + normIdx, 1) — supports negative indices
    const strAtAssignM = initExpr.match(/^(\w+)\.at\s*\((.+)\)$/);
    if (
      strAtAssignM && locals.get(strAtAssignM[1]) === "string" &&
      parenDepthNeverNegative(strAtAssignM[2])
    ) {
      const strName = strAtAssignM[1];
      const nWat = this.emitExpr(strAtAssignM[2].trim(), locals, "i32");
      const ptrW = "(local.get $" + strName + "_ptr)";
      const lenW = "(local.get $" + strName + "_len)";
      const normIdx = "(select " + nWat + " (i32.add " + lenW + " " + nWat + ") (i32.ge_s " + nWat +
        " (i32.const 0)))";
      return [
        "(local.set $" + varName + "_ptr (i32.add " + ptrW + " " + normIdx + "))",
        ind + "(local.set $" + varName + "_len (i32.const 1))",
      ].join("\n");
    }

    // Phase 27: str.charAt(i) → (ptr+i, 1) string
    const charAtMatch = initExpr.match(/^(\w+)\.charAt\s*\((.+)\)$/);
    if (
      charAtMatch && locals.get(charAtMatch[1]) === "string" &&
      parenDepthNeverNegative(charAtMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      const idxWat = this.emitExpr(charAtMatch[2].trim(), locals, "i32");
      return [
        `(call $__str_char_at (local.get $${charAtMatch[1]}_ptr) (local.get $${
          charAtMatch[1]
        }_len) ${idxWat})`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // str[idx].toLowerCase() / toUpperCase() — subscript then case-convert (chain multi-value call)
    const strSubCaseMatch = initExpr.match(
      /^(\w+)\[([^\]]+)\]\.(toLowerCase|toUpperCase)\s*\(\s*\)$/,
    );
    if (strSubCaseMatch && locals.get(strSubCaseMatch[1]) === "string") {
      this.needsStringExtHelpers = true;
      const idxWat = this.emitExpr(strSubCaseMatch[2].trim(), locals, "i32");
      const caseHelper = strSubCaseMatch[3] === "toLowerCase"
        ? "$__str_to_lower"
        : "$__str_to_upper";
      return [
        `(call ${caseHelper} (call $__str_char_at (local.get $${
          strSubCaseMatch[1]
        }_ptr) (local.get $${strSubCaseMatch[1]}_len) ${idxWat}))`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // str[idx] — single-character substring (same as charAt)
    const strSubscriptMatch = initExpr.match(/^(\w+)\[([^\]]+)\]$/);
    if (strSubscriptMatch && locals.get(strSubscriptMatch[1]) === "string") {
      this.needsStringExtHelpers = true;
      const idxWat = this.emitExpr(strSubscriptMatch[2].trim(), locals, "i32");
      return [
        `(call $__str_char_at (local.get $${strSubscriptMatch[1]}_ptr) (local.get $${
          strSubscriptMatch[1]
        }_len) ${idxWat})`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // String array element: arr[idx] where arr is string[] — load ptr and len pair.
    const strArrElemMatch = initExpr.match(/^(\w+)\[([^\]]+)\]$/);
    if (strArrElemMatch) {
      const [, sarrN, sarrIdx] = strArrElemMatch;
      const sarrInfo = this.arrayVars.get(sarrN);
      if (sarrInfo && (sarrInfo.isStringArr || sarrInfo.elemType === "string")) {
        const idxWat = this.emitArrayIndex(sarrIdx.trim(), locals);
        const baseWat = (sarrInfo.ptr === -1 || sarrInfo.dynamic)
          ? this.arrGetWat(sarrN)
          : `(i32.const ${sarrInfo.ptr})`;
        const addrWat =
          `(i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 3)))`;
        return [
          `(local.set $${varName}_ptr (i32.load ${addrWat}))`,
          `${ind}(local.set $${varName}_len (i32.load offset=4 ${addrWat}))`,
        ].join("\n");
      }
    }

    // Phase 27: str.toUpperCase() / str.toLowerCase()
    const caseMatch = initExpr.match(/^(\w+)\.(toUpperCase|toLowerCase)\s*\(\s*\)$/);
    if (caseMatch && locals.get(caseMatch[1]) === "string") {
      this.needsStringExtHelpers = true;
      const helperName = caseMatch[2] === "toUpperCase" ? "$__str_to_upper" : "$__str_to_lower";
      return [
        `(call ${helperName} (local.get $${caseMatch[1]}_ptr) (local.get $${caseMatch[1]}_len))`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // Phase 27: str.replace(old, new) / str.replaceAll(old, new)
    const replaceAllMatch = initExpr.match(/^(\w+)\.(replaceAll|replace)\s*\((.+)\)$/);
    if (
      replaceAllMatch && locals.get(replaceAllMatch[1]) === "string" &&
      parenDepthNeverNegative(replaceAllMatch[3])
    ) {
      const allArgs = this.splitArgs(replaceAllMatch[3]);
      if (allArgs.length === 2) {
        this.needsStringExtHelpers = true;
        this.needsStringOpHelpers = true;
        const helperName = replaceAllMatch[2] === "replaceAll"
          ? "$__str_replace_all"
          : "$__str_replace";
        const oldPtrLen = this.emitStringPtrLen(allArgs[0].trim(), locals);
        const newPtrLen = this.emitStringPtrLen(allArgs[1].trim(), locals);
        return [
          `(call ${helperName} (local.get $${replaceAllMatch[1]}_ptr) (local.get $${
            replaceAllMatch[1]
          }_len) ${oldPtrLen} ${newPtrLen})`,
          `${ind}(local.set $${varName}_len)`,
          `${ind}(local.set $${varName}_ptr)`,
        ].join("\n");
      }
    }

    // Phase 27: str.padStart(targetLen, pad) / str.padEnd(targetLen, pad)
    const padMatch = initExpr.match(/^(\w+)\.(padStart|padEnd)\s*\((.+)\)$/);
    if (
      padMatch && locals.get(padMatch[1]) === "string" && parenDepthNeverNegative(padMatch[3])
    ) {
      const allArgs = this.splitArgs(padMatch[3]);
      if (allArgs.length === 2) {
        this.needsStringExtHelpers = true;
        const helperName = padMatch[2] === "padStart" ? "$__str_pad_start" : "$__str_pad_end";
        const targetWat = this.emitExpr(allArgs[0].trim(), locals, "i32");
        const padPtrLen = this.emitStringPtrLen(allArgs[1].trim(), locals);
        return [
          `(call ${helperName} (local.get $${padMatch[1]}_ptr) (local.get $${
            padMatch[1]
          }_len) ${targetWat} ${padPtrLen})`,
          `${ind}(local.set $${varName}_len)`,
          `${ind}(local.set $${varName}_ptr)`,
        ].join("\n");
      }
    }

    // Phase 27: str.repeat(n)
    const repeatMatch = initExpr.match(/^(\w+)\.repeat\s*\((.+)\)$/);
    if (
      repeatMatch && locals.get(repeatMatch[1]) === "string" &&
      parenDepthNeverNegative(repeatMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      const nWat = this.emitExpr(repeatMatch[2].trim(), locals, "i32");
      return [
        `(call $__str_repeat (local.get $${repeatMatch[1]}_ptr) (local.get $${
          repeatMatch[1]
        }_len) ${nWat})`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    // n.toString(radix) → malloc + $__i32_to_str_radix (runtime base 2..36; value truncated to i32).
    // Must precede the no-arg toString below (whose regex would not match a non-empty arg anyway).
    const toStrRadixM = initExpr.match(/^(\w+)\.toString\s*\(\s*(.+)\s*\)$/);
    if (toStrRadixM) {
      const srcName = toStrRadixM[1]!;
      const srcType = locals.get(srcName) ?? this.moduleGlobals.get(srcName)?.type;
      if (srcType === "i32" || srcType === "f64") {
        this.needsNumericHelpers = true;
        const valWat = this.emitExpr(srcName, locals, "i32");
        const radixWat = this.emitExpr(toStrRadixM[2]!.trim(), locals, "i32");
        return [
          `(local.set $${varName}_ptr (call $__malloc (i32.const 36)))`,
          `${ind}(local.set $${varName}_len (call $__i32_to_str_radix ${valWat} ${radixWat} (local.get $${varName}_ptr)))`,
        ].join("\n");
      }
    }

    // n.toString() → malloc 32 bytes, call $__i32_to_str / $__f64_to_str
    const toStrMatch = initExpr.match(/^(\w+)\.toString\s*\(\s*\)$/);
    if (toStrMatch) {
      const srcName = toStrMatch[1];
      const srcType = locals.get(srcName) ?? this.moduleGlobals.get(srcName)?.type;
      if (srcType === "i32" || srcType === "f64" || srcType === "i64") {
        this.needsNumericHelpers = true;
        const helperName = srcType === "f64" ? "$__f64_to_str" : "$__i32_to_str";
        const getOp = this.moduleGlobals.has(srcName)
          ? `(global.get $${srcName})`
          : `(local.get $${srcName})`;
        return [
          `(local.set $${varName}_ptr (call $__malloc (i32.const 32)))`,
          `${ind}(local.set $${varName}_len (call ${helperName} ${getOp} (local.get $${varName}_ptr)))`,
        ].join("\n");
      }
    }

    // String(n) → same pattern
    const stringOfMatch = initExpr.match(/^String\s*\((.+?)\)\s*$/);
    if (stringOfMatch) {
      const argExpr = stringOfMatch[1].trim();
      const argType: WatType = this.inferExprType(argExpr, locals);
      // String(catchVar) where the arg is a caught exception: produce "Error: <message>"
      // matching JavaScript's Error.prototype.toString() behaviour.
      if (argType === "string" && this.catchVarNames.has(argExpr)) {
        this.needsStringOpHelpers = true;
        const [prefixPtr, prefixLen] = this.allocString("Error: ");
        return [
          `(call $__str_concat (i32.const ${prefixPtr}) (i32.const ${prefixLen}) (local.get $${argExpr}_ptr) (local.get $${argExpr}_len))`,
          `${ind}(local.set $${varName}_len)`,
          `${ind}(local.set $${varName}_ptr)`,
        ].join("\n");
      }
      this.needsNumericHelpers = true;
      const helperName = argType === "f64"
        ? "$__f64_to_str"
        : argType === "i64"
        ? "$__i64_to_str"
        : "$__i32_to_str";
      const valWat = this.emitExpr(argExpr, locals, argType);
      return [
        `(local.set $${varName}_ptr (call $__malloc (i32.const 32)))`,
        `${ind}(local.set $${varName}_len (call ${helperName} ${valWat} (local.get $${varName}_ptr)))`,
      ].join("\n");
    }

    // String.fromCharCode(n) — allocate 1-byte heap string from char code
    const fccDirect = initExpr.match(/^String\.fromCharCode\s*\((.+)\)$/);
    if (fccDirect && parenDepthNeverNegative(fccDirect[1])) {
      const argWat = this.emitExpr(fccDirect[1].trim(), locals, "i32");
      return [
        `(local.set $${varName}_ptr (call $__malloc (i32.const 1)))`,
        `${ind}(i32.store8 (local.get $${varName}_ptr) ${argWat})`,
        `${ind}(local.set $${varName}_len (i32.const 1))`,
      ].join("\n");
    }

    // Phase 52.9: String.fromCodePoint(...) — UTF-8 encode the code point(s) into a string.
    const fcpDirect = initExpr.match(/^String\.fromCodePoint\s*\((.+)\)$/);
    if (fcpDirect && parenDepthNeverNegative(fcpDirect[1])) {
      const cpArgs = this.splitArgs(fcpDirect[1]);
      const cpConsts = cpArgs.map((a) => this.constCodePoint(a));
      if (cpConsts.length > 0 && cpConsts.every((c) => c !== null)) {
        // All compile-time constants → static UTF-8 string allocated in the data section.
        const s = String.fromCodePoint(...(cpConsts as number[]));
        const [offset, len] = this.allocStringDecoded(s);
        return [
          `(local.set $${varName}_ptr (i32.const ${offset}))`,
          `${ind}(local.set $${varName}_len (i32.const ${len}))`,
        ].join("\n");
      }
      // Single runtime arg → call the UTF-8 encoder helper (returns ptr,len multi-value).
      if (cpArgs.length === 1) {
        this.needsStringExtHelpers = true;
        const argWat = this.emitExpr(cpArgs[0].trim(), locals, "i32");
        return [
          `(call $__str_from_codepoint ${argWat})`,
          `${ind}(local.set $${varName}_len)`,
          `${ind}(local.set $${varName}_ptr)`,
        ].join("\n");
      }
    }

    // String concatenation: flatten the binary + tree and reduce left-to-right
    // e.g. a + " " + b  →  result = concat(a, " "); result = concat(result, b)
    const concatParts = this.flattenStringConcat(initExpr, locals);
    if (concatParts && concatParts.length >= 2) {
      this.needsStringOpHelpers = true;
      const stmts: string[] = [];
      // Self-reference: the accumulator IS varName_ptr/len, so a part that reads varName AFTER the
      // first (prepend, e.g. `r = h[i] + r`) would see the partially-built result. Save the OLD
      // value into $__concat_self once, and substitute it for every varName part below. (Append —
      // `s = s + x`, where varName is the FIRST part — is unaffected and keeps its existing path.)
      const selfRefNonFirst = concatParts.slice(1).some((p) => p.trim() === varName);
      if (selfRefNonFirst) {
        stmts.push(`(local.set $__concat_self_ptr (local.get $${varName}_ptr))`);
        stmts.push(`(local.set $__concat_self_len (local.get $${varName}_len))`);
      }
      // Append ptr+len to the accumulator (varName_ptr/len). First part initializes; rest concat.
      let concatAccumHasValue = false;
      const concatAppend = (ptrWat: string, lenWat: string) => {
        if (!concatAccumHasValue) {
          stmts.push(`(local.set $${varName}_ptr ${ptrWat})`);
          stmts.push(`(local.set $${varName}_len ${lenWat})`);
          concatAccumHasValue = true;
        } else {
          stmts.push(
            `(call $__str_concat (local.get $${varName}_ptr) (local.get $${varName}_len) ${ptrWat} ${lenWat})`,
          );
          stmts.push(`(local.set $${varName}_len)`);
          stmts.push(`(local.set $${varName}_ptr)`);
        }
      };
      // Append one concat part (may be a template literal, string var, literal, etc.)
      const appendConcatPart = (part: string) => {
        // Self-referential part (the target var appearing in its own RHS): use the saved old value.
        if (selfRefNonFirst && part.trim() === varName) {
          concatAppend(`(local.get $__concat_self_ptr)`, `(local.get $__concat_self_len)`);
          return;
        }
        // Template literal: expand each segment as a concat operation
        if (part.startsWith("`") && part.endsWith("`")) {
          const tParts2 = this.splitTemplateLiteral(part.slice(1, -1));
          for (const seg of tParts2) {
            if (seg.kind === "text") {
              if (!seg.value) continue;
              const [off, ln] = this.allocString(seg.value);
              concatAppend(`(i32.const ${off})`, `(i32.const ${ln})`);
            } else {
              const eCC = seg.value.trim();
              const eTypeCC = this.inferExprType(eCC, locals);
              if (eTypeCC === "string") {
                const ptrLenCC = this.quietEmit(() => this.emitStringPtrLen(eCC, locals));
                if (ptrLenCC !== "(i32.const 0) (i32.const 0)") {
                  const [pW, lW] = splitTwoWatExprs(ptrLenCC);
                  concatAppend(pW, lW);
                }
              } else {
                this.needsNumericHelpers = true;
                const helperCC = eTypeCC === "f64"
                  ? "$__f64_to_str"
                  : eTypeCC === "i64"
                  ? "$__i64_to_str"
                  : "$__i32_to_str";
                const valWatCC = this.emitExpr(eCC, locals, eTypeCC);
                stmts.push(`(local.set $__tmpl_num_ptr (call $__malloc (i32.const 32)))`);
                stmts.push(
                  `(local.set $__tmpl_num_len (call ${helperCC} ${valWatCC} (local.get $__tmpl_num_ptr)))`,
                );
                concatAppend(`(local.get $__tmpl_num_ptr)`, `(local.get $__tmpl_num_len)`);
              }
            }
          }
          return;
        }
        // String.fromCharCode(n) in concat — 1-byte heap-allocated char
        const fccCP = part.match(/^String\.fromCharCode\s*\((.+)\)$/);
        if (fccCP && parenDepthNeverNegative(fccCP[1])) {
          const argWat = this.emitExpr(fccCP[1].trim(), locals, "i32");
          stmts.push(`(local.set $__str_op_ptr (call $__malloc (i32.const 1)))`);
          stmts.push(`(i32.store8 (local.get $__str_op_ptr) ${argWat})`);
          concatAppend(`(local.get $__str_op_ptr)`, `(i32.const 1)`);
          return;
        }
        // Phase 52.9: String.fromCodePoint(...) in concat
        const fcpCP = part.match(/^String\.fromCodePoint\s*\((.+)\)$/);
        if (fcpCP && parenDepthNeverNegative(fcpCP[1])) {
          const cpArgs = this.splitArgs(fcpCP[1]);
          const cpConsts = cpArgs.map((a) => this.constCodePoint(a));
          if (cpConsts.length > 0 && cpConsts.every((c) => c !== null)) {
            const s = String.fromCodePoint(...(cpConsts as number[]));
            const [off, ln] = this.allocStringDecoded(s);
            concatAppend(`(i32.const ${off})`, `(i32.const ${ln})`);
            return;
          }
          if (cpArgs.length === 1) {
            this.needsStringExtHelpers = true;
            const argWat = this.emitExpr(cpArgs[0].trim(), locals, "i32");
            stmts.push(`(call $__str_from_codepoint ${argWat})`);
            stmts.push(`(local.set $__str_op_len)`);
            stmts.push(`(local.set $__str_op_ptr)`);
            concatAppend(`(local.get $__str_op_ptr)`, `(local.get $__str_op_len)`);
            return;
          }
        }
        // Phase 49: str.at(n) in concat — supports negative indices
        const strAtCP = part.match(/^(\w+)\.at\s*\((.+)\)$/);
        if (strAtCP && locals.get(strAtCP[1]) === "string" && parenDepthNeverNegative(strAtCP[2])) {
          const strName = strAtCP[1];
          const nWat = this.emitExpr(strAtCP[2].trim(), locals, "i32");
          const ptrW = "(local.get $" + strName + "_ptr)";
          const lenW = "(local.get $" + strName + "_len)";
          const normIdx = "(select " + nWat + " (i32.add " + lenW + " " + nWat + ") (i32.ge_s " +
            nWat + " (i32.const 0)))";
          concatAppend("(i32.add " + ptrW + " " + normIdx + ")", "(i32.const 1)");
          return;
        }
        // str.charAt(idx) in concat — single-char substring via $__str_char_at
        const caCP = part.match(/^(\w+)\.charAt\s*\((.+)\)$/);
        if (caCP && parenDepthNeverNegative(caCP[2])) {
          const strN = caCP[1], idxRaw = caCP[2];
          const isLocal = locals.get(strN) === "string";
          const strConst = this.moduleStringConsts.get(strN);
          if (isLocal || strConst) {
            this.needsStringExtHelpers = true;
            const idxWat = this.emitExpr(idxRaw.trim(), locals, "i32");
            const ptrW = isLocal ? `(local.get $${strN}_ptr)` : `(i32.const ${strConst![0]})`;
            const lenW = isLocal ? `(local.get $${strN}_len)` : `(i32.const ${strConst![1]})`;
            stmts.push(`(call $__str_char_at ${ptrW} ${lenW} ${idxWat})`);
            stmts.push(`(local.set $__str_op_len)`);
            stmts.push(`(local.set $__str_op_ptr)`);
            concatAppend(`(local.get $__str_op_ptr)`, `(local.get $__str_op_len)`);
            return;
          }
        }
        // str[idx] in concat (string char subscript) — equivalent to charAt(idx). Build a 1-char
        // string via $__str_char_code_at + malloc + store8 (same shape as fromCharCode), which
        // avoids a multi-value capture so the concat accumulator stays well-formed.
        const charSubCP = part.match(/^(\w+)\[(.+)\]$/);
        if (
          charSubCP && parenDepthNeverNegative(charSubCP[2]) &&
          (locals.get(charSubCP[1]) === "string" || this.moduleStringConsts.has(charSubCP[1])) &&
          !this.arrayVars.has(charSubCP[1])
        ) {
          this.needsStringExtHelpers = true;
          const idxWat = this.emitArrayIndex(charSubCP[2].trim(), locals);
          const sc = this.moduleStringConsts.get(charSubCP[1]);
          const ptrW = sc ? `(i32.const ${sc[0]})` : `(local.get $${charSubCP[1]}_ptr)`;
          const lenW = sc ? `(i32.const ${sc[1]})` : `(local.get $${charSubCP[1]}_len)`;
          stmts.push(`(local.set $__str_op_ptr (call $__malloc (i32.const 1)))`);
          stmts.push(
            `(i32.store8 (local.get $__str_op_ptr) (call $__str_char_code_at ${ptrW} ${lenW} ${idxWat}))`,
          );
          concatAppend(`(local.get $__str_op_ptr)`, `(i32.const 1)`);
          return;
        }
        // str.slice(start[, end]) in concat — capture multi-value return into temp pair
        const sliceCP = part.match(/^(\w+)\.slice\s*\((.+)\)$/);
        if (sliceCP && parenDepthNeverNegative(sliceCP[2])) {
          const strN = sliceCP[1];
          const isLocal = locals.get(strN) === "string";
          const strConst = this.moduleStringConsts.get(strN);
          if (isLocal || strConst) {
            this.needsStringOpHelpers = true;
            const sliceArgs2 = this.splitArgs(sliceCP[2].trim());
            const startWat2 = this.emitArrayIndex(sliceArgs2[0].trim(), locals);
            const ptrW2 = isLocal ? `(local.get $${strN}_ptr)` : `(i32.const ${strConst![0]})`;
            const lenW2 = isLocal ? `(local.get $${strN}_len)` : `(i32.const ${strConst![1]})`;
            const endWat2 = sliceArgs2.length >= 2
              ? this.emitArrayIndex(sliceArgs2[1].trim(), locals)
              : lenW2;
            stmts.push(`(call $__str_slice ${ptrW2} ${lenW2} ${startWat2} ${endWat2})`);
            stmts.push(`(local.set $__str_op_len)`);
            stmts.push(`(local.set $__str_op_ptr)`);
            concatAppend(`(local.get $__str_op_ptr)`, `(local.get $__str_op_len)`);
            return;
          }
        }
        // Non-template: use emitStringPtrLen (handles vars, literals, struct fields, array elems, fn calls)
        const simple = this.quietEmit(() => this.emitStringPtrLen(part, locals));
        if (simple !== "(i32.const 0) (i32.const 0)") {
          const [pW, lW] = splitTwoWatExprs(simple);
          concatAppend(pW, lW);
        }
      };
      for (const part of concatParts) {
        appendConcatPart(part);
      }
      if (!concatAccumHasValue) {
        const [off, ln] = this.allocString("");
        stmts.push(`(local.set $${varName}_ptr (i32.const ${off}))`);
        stmts.push(`(local.set $${varName}_len (i32.const ${ln}))`);
      }
      return stmts.join(`\n${ind}`);
    }

    // Last resort before the stub: emitStringPtrLen handles many string-valued forms the earlier
    // branches don't (string method on an array element `words[0].toUpperCase()`, `.slice()`,
    // `.padStart()`, `.at()`, `.toString(radix)`, etc.). It returns the `(i32.const 0) (i32.const 0)`
    // sentinel when it can't, so we only use a genuine result. The two stack values are (ptr, len);
    // pop len then ptr. Works for both two-expr and single multi-value-call results.
    const splm = this.quietEmit(() => this.emitStringPtrLen(initExpr, locals));
    if (splm !== "(i32.const 0) (i32.const 0)" && !splm.includes("(;")) {
      return [
        `${splm}`,
        `${ind}(local.set $${varName}_len)`,
        `${ind}(local.set $${varName}_ptr)`,
      ].join("\n");
    }

    this.diagnostics.push(
      `Unsupported string assignment: ${varName} = ${initExpr.slice(0, 80)}`,
    );
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

  /** Returns true if expr is a string literal, a known string variable, a template literal,
   *  a string method call on a string variable, or a call to a string-returning function. */
  private isStringExpr(expr: string, locals: Map<string, WatType>): boolean {
    const e = expr.trim();
    if (/^["']/.test(e)) return true;
    if (e.startsWith("`") && e.endsWith("`")) return true;
    if (/^\w+$/.test(e)) return locals.get(e) === "string" || this.moduleStringConsts.has(e);
    // String array element: arr[idx] where arr is a string array
    const bracketStrM = e.match(/^(\w+)\[/);
    if (bracketStrM) {
      const bArrInfo = this.arrayVars.get(bracketStrM[1]);
      if (bArrInfo && (bArrInfo.isStringArr || bArrInfo.elemType === "string")) return true;
    }
    // String method calls on a string variable (slice, trim, charAt, case, replace, pad, repeat)
    const strMethodM = e.match(
      /^(\w+)\.(slice|trim|trimStart|trimEnd|trimLeft|trimRight|charAt|toUpperCase|toLowerCase|replace|replaceAll|padStart|padEnd|repeat)\s*\(/,
    );
    if (
      strMethodM &&
      (locals.get(strMethodM[1]) === "string" || this.moduleStringConsts.has(strMethodM[1]))
    ) return true;
    // String.fromCharCode(n) / String.fromCodePoint(n) — always produce a string
    if (/^String\.fromCharCode\s*\(/.test(e)) return true;
    if (/^String\.fromCodePoint\s*\(/.test(e)) return true;
    // Call to a string-returning function
    const callM = e.match(/^(\w+)\s*\(/);
    if (callM && this.functions.find((f) => f.name === callM[1] && f.result === "string")) {
      return true;
    }
    return false;
  }

  /** Splits a template literal inner string (between backticks) into text/expr segments. */
  private splitTemplateLiteral(inner: string): Array<{ kind: "text" | "expr"; value: string }> {
    const parts: Array<{ kind: "text" | "expr"; value: string }> = [];
    let i = 0;
    while (i < inner.length) {
      const start = inner.indexOf("${", i);
      if (start === -1) {
        if (i < inner.length) parts.push({ kind: "text", value: inner.slice(i) });
        break;
      }
      if (start > i) parts.push({ kind: "text", value: inner.slice(i, start) });
      // Find matching }
      let depth = 0, j = start + 2;
      while (j < inner.length) {
        if (inner[j] === "{") depth++;
        else if (inner[j] === "}") {
          if (depth === 0) break;
          depth--;
        }
        j++;
      }
      parts.push({ kind: "expr", value: inner.slice(start + 2, j) });
      i = j + 1;
    }
    return parts;
  }

  /** Infers the WAT type of an arbitrary expression, including array element access. */
  private inferExprType(expr: string, locals: Map<string, WatType>): WatType {
    const e = expr.trim();
    // Struct array element field access: arr[i].field → field type
    const arrFieldDotM = e.match(/^(\w+)\[([^\]]+)\]\.(\w+)$/);
    if (arrFieldDotM) {
      const arrI = this.arrayVars.get(arrFieldDotM[1]);
      const stn = arrI?.structTypeName ??
        (arrI && arrI.elemType !== "f64" && arrI.elemType !== "i32" && arrI.elemType !== "i64"
          ? arrI.elemType
          : undefined);
      if (arrI && stn) {
        const def = this.structDefs.get(stn);
        const field = def?.fields.find((f) => f.name === arrFieldDotM[3]);
        if (field) return field.type as WatType;
      }
    }
    // Array element access arr[idx] → element type
    const bracketId = e.match(/^(\w+)\[/)?.[1];
    if (bracketId && this.arrayVars.has(bracketId)) {
      const arrI = this.arrayVars.get(bracketId)!;
      if (arrI.isStringArr || arrI.elemType === "string") return "string";
      return arrI.elemType;
    }
    // TypedArray element access
    if (bracketId && this.typedArrayVars.has(bracketId)) {
      return this.typedArrayVars.get(bracketId)!.elemType as WatType;
    }
    // Struct/class field access: varName.fieldName → return actual field type
    const dotM = e.match(/^(\w+)\.(\w+)$/);
    if (dotM) {
      const sv = this.structVars.get(dotM[1]);
      if (sv) {
        const field = sv.def.fields.find((f) => f.name === dotM[2]);
        if (field) return field.type as WatType;
      }
      const cv = this.classVars.get(dotM[1]);
      if (cv) {
        const cd = this.classDefs.get(cv.className);
        if (cd) {
          const field = cd.struct.fields.find((f) => f.name === dotM[2]);
          if (field) return field.type as WatType;
        }
      }
    }
    // Phase 42: expression starting with a struct field access (e.g. "a.x + b.x"):
    // if the leading sub-expression is a struct field, infer type from that field.
    const leadDotM = e.match(/^(\w+)\.(\w+)\b/);
    if (leadDotM) {
      const sv = this.structVars.get(leadDotM[1]);
      if (sv) {
        const field = sv.def.fields.find((f) => f.name === leadDotM[2]);
        if (field && field.type !== "i32") return field.type as WatType;
      }
    }
    // Phase 42: Chained struct field access: a.b.c → inner field type
    const chainedDotM = e.match(/^(\w+)\.(\w+)\.(\w+)$/);
    if (chainedDotM) {
      const sv = this.structVars.get(chainedDotM[1]);
      if (sv) {
        const outerField = sv.def.fields.find((f) => f.name === chainedDotM[2]);
        if (outerField?.structType) {
          const innerDef = this.structDefs.get(outerField.structType);
          const innerField = innerDef?.fields.find((f) => f.name === chainedDotM[3]);
          if (innerField) return innerField.type as WatType;
        }
      }
    }
    // Simple identifier: check module globals and module string consts when not in locals
    if (/^\w+$/.test(e) && !locals.has(e)) {
      const globalInfo = this.moduleGlobals.get(e);
      if (globalInfo) return globalInfo.type;
      if (this.moduleStringConsts.has(e)) return "string";
    }
    // Use module-level inferInitType
    return inferInitType(e, locals, this.enumValues, this.functions);
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
    // Module-level string const — pre-allocated in data section
    if (/^\w+$/.test(expr) && this.moduleStringConsts.has(expr)) {
      const [offset, len] = this.moduleStringConsts.get(expr)!;
      return `(i32.const ${offset}) (i32.const ${len})`;
    }
    // Mutable module-level string global — read the ptr/len global pair
    if (/^\w+$/.test(expr) && this.moduleStringGlobals.has(expr)) {
      return `(global.get $${expr}_ptr) (global.get $${expr}_len)`;
    }
    // varName.message — Error catch variable; .message is the string itself
    const dotMsgMatch = expr.match(/^(\w+)\.message$/);
    if (dotMsgMatch && locals.get(dotMsgMatch[1]) === "string") {
      return `(local.get $${dotMsgMatch[1]}_ptr) (local.get $${dotMsgMatch[1]}_len)`;
    }
    // String literal — escape-aware so `\"` / `\\` inside the literal don't terminate the
    // match early (allocString → unescapeString decodes the captured escapes to bytes).
    const litMatch = expr.match(/^"((?:[^"\\]|\\.)*)"$/) ?? expr.match(/^'((?:[^'\\]|\\.)*)'$/);
    if (litMatch) {
      const [offset, len] = this.allocString(litMatch[1]);
      return `(i32.const ${offset}) (i32.const ${len})`;
    }
    // Struct string field: p.fieldName where p is a struct/class var with a string-typed field
    const structFieldSPLM = expr.match(/^(\w+)\.(\w+)$/);
    if (structFieldSPLM) {
      const sv = this.structVars.get(structFieldSPLM[1]);
      if (sv) {
        const field = sv.def.fields.find((f) =>
          f.name === structFieldSPLM[2] && f.type === "string"
        );
        if (field) {
          const baseWat = sv.ptr < 0
            ? `(local.get $${structFieldSPLM[1]})`
            : `(i32.const ${sv.ptr})`;
          return `(i32.load offset=${field.offset} ${baseWat}) (i32.load offset=${
            field.offset + 4
          } ${baseWat})`;
        }
      }
      const cv = this.classVars.get(structFieldSPLM[1]);
      if (cv) {
        const cd = this.classDefs.get(cv.className);
        const field = cd?.struct.fields.find((f) =>
          f.name === structFieldSPLM[2] && f.type === "string"
        );
        if (field) {
          const baseWat = cv.ptr < 0
            ? `(local.get $${structFieldSPLM[1]})`
            : `(i32.const ${cv.ptr})`;
          return `(i32.load offset=${field.offset} ${baseWat}) (i32.load offset=${
            field.offset + 4
          } ${baseWat})`;
        }
      }
    }
    // Struct array element string field: arr[idx].fieldName
    const structArrFieldSPLM = expr.match(/^(\w+)\[([^\]]+)\]\.(\w+)$/);
    if (structArrFieldSPLM) {
      const arrI = this.arrayVars.get(structArrFieldSPLM[1]);
      const stn = arrI?.structTypeName ??
        (arrI && arrI.elemType !== "f64" && arrI.elemType !== "i32" && arrI.elemType !== "i64"
          ? arrI.elemType
          : undefined);
      if (arrI && stn) {
        const def = this.structDefs.get(stn);
        const field = def?.fields.find((f) =>
          f.name === structArrFieldSPLM[3] && f.type === "string"
        );
        if (field) {
          const idxWat = this.emitArrayIndex(structArrFieldSPLM[2].trim(), locals);
          const baseWat = (arrI.ptr === -1 || arrI.dynamic)
            ? this.arrGetWat(structArrFieldSPLM[1])
            : `(i32.const ${arrI.ptr})`;
          const elemPtrWat =
            `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
          return `(i32.load offset=${field.offset} ${elemPtrWat}) (i32.load offset=${
            field.offset + 4
          } ${elemPtrWat})`;
        }
      }
    }
    // String char subscript: str[idx] where str is a PLAIN string var/const → the 1-char string
    // at that index, via $__str_char_at (multi-value ptr,len). Must come before the string-array
    // case (a plain string is not in arrayVars). Index may be any i32 expression (e.g. v % 16).
    const strCharSub = expr.match(/^(\w+)\[(.+)\]$/);
    if (
      strCharSub && parenDepthNeverNegative(strCharSub[2]) &&
      (locals.get(strCharSub[1]) === "string" || this.moduleStringConsts.has(strCharSub[1])) &&
      !this.arrayVars.has(strCharSub[1])
    ) {
      this.needsStringExtHelpers = true;
      const idxWat = this.emitArrayIndex(strCharSub[2].trim(), locals);
      const sc = this.moduleStringConsts.get(strCharSub[1]);
      const ptrW = sc ? `(i32.const ${sc[0]})` : `(local.get $${strCharSub[1]}_ptr)`;
      const lenW = sc ? `(i32.const ${sc[1]})` : `(local.get $${strCharSub[1]}_len)`;
      return `(call $__str_char_at ${ptrW} ${lenW} ${idxWat})`;
    }
    // String array element access: arr[idx] where arr is string[] (isStringArr or elemType=string)
    const strArrBracket = expr.match(/^(\w+)\[([^\]]+)\]$/);
    if (strArrBracket) {
      const [, arrN, idxRaw] = strArrBracket;
      const arrInfoSA = this.arrayVars.get(arrN);
      if (arrInfoSA && (arrInfoSA.isStringArr || arrInfoSA.elemType === "string")) {
        const idxWat = this.emitArrayIndex(idxRaw.trim(), locals);
        const baseWat = (arrInfoSA.ptr === -1 || arrInfoSA.dynamic)
          ? this.arrGetWat(arrN)
          : `(i32.const ${arrInfoSA.ptr})`;
        // String elements: 8 bytes each (ptr i32 at +0, len i32 at +4)
        const elemAddrWat =
          `(i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 3)))`;
        return `(i32.load ${elemAddrWat}) (i32.load offset=4 ${elemAddrWat})`;
      }
    }
    // Phase 49: str.at(n) — returns (ptr+normIdx, 1) inline for use in str comparisons
    const strAtSPLM = expr.match(/^(\w+)\.at\s*\((.+)\)$/);
    if (
      strAtSPLM && locals.get(strAtSPLM[1]) === "string" && parenDepthNeverNegative(strAtSPLM[2])
    ) {
      const strName = strAtSPLM[1];
      const nWat = this.emitExpr(strAtSPLM[2].trim(), locals, "i32");
      const ptrW = "(local.get $" + strName + "_ptr)";
      const lenW = "(local.get $" + strName + "_len)";
      const normIdx = "(select " + nWat + " (i32.add " + lenW + " " + nWat + ") (i32.ge_s " + nWat +
        " (i32.const 0)))";
      return "(i32.add " + ptrW + " " + normIdx + ") (i32.const 1)";
    }

    // str.slice(start[, end]) — returns inline multi-value call (ptr, len) for use in $__str_cmp args
    const sliceSPLM = expr.match(/^(\w+)\.slice\s*\((.+)\)$/);
    if (
      sliceSPLM && locals.get(sliceSPLM[1]) === "string" && parenDepthNeverNegative(sliceSPLM[2])
    ) {
      this.needsStringOpHelpers = true;
      const sliceArgs = this.splitArgs(sliceSPLM[2].trim());
      const startWat = this.emitArrayIndex(sliceArgs[0].trim(), locals);
      const endWat = sliceArgs.length >= 2
        ? this.emitArrayIndex(sliceArgs[1].trim(), locals)
        : `(local.get $${sliceSPLM[1]}_len)`;
      return `(call $__str_slice (local.get $${sliceSPLM[1]}_ptr) (local.get $${
        sliceSPLM[1]
      }_len) ${startWat} ${endWat})`;
    }
    // n.toString(radix) — numeric var/global with a radix arg → $__i32_to_str_radix into the
    // $__str_op temp pair, returned as (ptr, len). (No-arg n.toString() is a different, single-value
    // string elsewhere.) Value is truncated to i32.
    const toStrRadixSPLM = expr.match(/^(\w+)\.toString\s*\(\s*(.+)\s*\)$/);
    if (toStrRadixSPLM) {
      const sName = toStrRadixSPLM[1]!;
      const sType = locals.get(sName) ?? this.moduleGlobals.get(sName)?.type;
      if (sType === "i32" || sType === "f64") {
        this.needsNumericHelpers = true;
        const valWat = this.emitExpr(sName, locals, "i32");
        const radixWat = this.emitExpr(toStrRadixSPLM[2]!.trim(), locals, "i32");
        return `(block (result i32) (local.set $__str_op_ptr (call $__malloc (i32.const 36))) ` +
          `(local.set $__str_op_len (call $__i32_to_str_radix ${valWat} ${radixWat} (local.get $__str_op_ptr))) ` +
          `(local.get $__str_op_ptr)) (local.get $__str_op_len)`;
      }
    }
    // str.padStart(n[, pad]) / str.padEnd(n[, pad]) — receiver may be a var, string literal, or
    // string-returning call (via the recursive emitStringPtrLen). Single-arg form defaults the pad
    // to a space. Returns the multi-value ($__str_pad_start/end) call (ptr, len).
    const padSPLM = expr.match(/^(.+)\.(padStart|padEnd)\s*\((.+)\)$/);
    if (padSPLM && parenDepthNeverNegative(padSPLM[3]!)) {
      const recvPtrLen = this.quietEmit(() => this.emitStringPtrLen(padSPLM[1]!.trim(), locals));
      if (recvPtrLen !== "(i32.const 0) (i32.const 0)") {
        this.needsStringExtHelpers = true;
        const helper = padSPLM[2] === "padStart" ? "$__str_pad_start" : "$__str_pad_end";
        const padArgs = this.splitArgs(padSPLM[3]!);
        const targetWat = this.emitExpr(padArgs[0]!.trim(), locals, "i32");
        let padStrLen: string;
        if (padArgs.length >= 2) {
          padStrLen = this.emitStringPtrLen(padArgs[1]!.trim(), locals);
        } else {
          const [po, pl] = this.allocString(" ");
          padStrLen = `(i32.const ${po}) (i32.const ${pl})`;
        }
        return `(call ${helper} ${recvPtrLen} ${targetWat} ${padStrLen})`;
      }
    }

    // str.toUpperCase() / str.toLowerCase() — plain string var OR string-array element receiver.
    // Returns the multi-value ($__str_to_upper/lower) call (ptr, len) for capture by the caller.
    const caseSPLM = expr.match(/^(\w+(?:\[[^\]]*\])?)\.(toUpperCase|toLowerCase)\s*\(\s*\)$/);
    if (caseSPLM) {
      const recv = caseSPLM[1]!;
      const helper = caseSPLM[2] === "toUpperCase" ? "$__str_to_upper" : "$__str_to_lower";
      let ptrLen: string | null = null;
      if (/^\w+$/.test(recv) && locals.get(recv) === "string") {
        ptrLen = `(local.get $${recv}_ptr) (local.get $${recv}_len)`;
      } else if (recv.includes("[")) {
        const inner = this.quietEmit(() => this.emitStringPtrLen(recv, locals)); // string-array element arr[i]
        if (inner !== "(i32.const 0) (i32.const 0)") ptrLen = inner;
      }
      if (ptrLen) {
        this.needsStringExtHelpers = true;
        return `(call ${helper} ${ptrLen})`;
      }
    }

    // Call to a string-returning function: emit void call then read globals
    const callM = expr.match(/^(\w+)\s*\((.*)?\)$/);
    if (callM) {
      const callee = callM[1];
      const strFn = this.functions.find((f) => f.name === callee && f.result === "string");
      if (strFn) {
        const rawArgs = callM[2]?.trim() ?? "";
        const argList = rawArgs ? this.splitArgs(rawArgs) : [];
        const watArgs = argList.flatMap((a, i) => {
          const p = strFn.params[i];
          if (!p) return [this.emitExpr(a.trim(), locals, "i32")];
          if (p.type === "string") return [this.emitStringPtrLen(a.trim(), locals)];
          return [this.emitExpr(a.trim(), locals, p.type)];
        });
        const callExpr = watArgs.length > 0
          ? `(call $${callee} ${watArgs.join(" ")})`
          : `(call $${callee})`;
        return `${callExpr} (global.get $__str_ret_ptr) (global.get $__str_ret_len)`;
      }
    }
    // Sentinel: this string form is unsupported. Callers that recover gracefully wrap the call in
    // quietEmit(); for everyone else, record a diagnostic so the unsupported string expression
    // aborts the compile rather than silently becoming the empty string (e.g. a wrong `===` result).
    if (this.emitDiagSuppressDepth === 0) {
      this.diagnostics.push(`Unsupported string expression: ${expr.slice(0, 80)}`);
    }
    return `(i32.const 0) (i32.const 0)`;
  }

  // -------------------------------------------------------------------------
  // Phase 35: typeof helper
  // -------------------------------------------------------------------------
  /** Returns the TypeScript runtime typeof string for a known local or module global. */
  private resolveTypeofString(varName: string, locals: Map<string, WatType>): string {
    const t = locals.get(varName) ?? this.moduleGlobals.get(varName)?.type;
    if (t === "string") return "string";
    if (t === "bool") return "boolean";
    if (t === "f64" || t === "f32") return "number";
    if (t === "i64") return "bigint";
    if (t === "i32") {
      if (
        this.structVars.has(varName) || this.typedArrayVars.has(varName) ||
        this.arrayVars.has(varName)
      ) return "object";
      return "number";
    }
    return "undefined";
  }

  /** Emits an array-index expression, ensuring the result is always i32.
   *  If the index expression is an f64/f32 value, wraps with i32.trunc_f64_s. */
  private emitArrayIndex(expr: string, locals: Map<string, WatType>): string {
    // Check type first so we can choose the right emitExpr context.
    // emitExpr(expr, locals, "i32") would pre-truncate simple f64 locals to i32,
    // and then inferExprType would wrap again → double i32.trunc_f64_s.
    // Instead: for f64 expressions, emit in f64 context and truncate once.
    const t = this.inferExprType(expr.trim(), locals);
    if (t === "f64" || t === "f32") {
      return `(i32.trunc_f64_s ${this.emitExpr(expr, locals, "f64")})`;
    }
    return this.emitExpr(expr, locals, "i32");
  }

  // -------------------------------------------------------------------------
  // Expression emitter
  // -------------------------------------------------------------------------
  private emitExpr(
    raw: string,
    locals: Map<string, WatType>,
    defaultType: WatType,
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

    // `as unknown` / `as any` are pure type erasure with no runtime representation.
    // Strip them up front so the double-cast idiom `expr as unknown as T` reduces to
    // `expr as T` and `expr as unknown` reduces to `expr`. Without this, the intermediate
    // erasure would reach mapType("unknown"), which falls through to f64 and injects a
    // stray f64.convert_i32_s (e.g. `ptr as unknown as i32` on a pointer return).
    if (/\bas\s+(?:unknown|any)\b/.test(expr)) {
      expr = expr.replace(/\s+as\s+(?:unknown|any)\b/g, " ").replace(/\s{2,}/g, " ").trim();
    }

    // Phase 22: `as` type assertion — `expr as T` → appropriate WASM conversion
    // Scan right-to-left at depth 0 (lowest-precedence, like a unary postfix suffix).
    {
      const asIdx = this.findDepth0Keyword(expr, " as ");
      if (asIdx !== -1) {
        const inner = expr.slice(0, asIdx).trim();
        const targetTypeStr = expr.slice(asIdx + 4).trim().split(/[\s<]/)[0]; // first word (strip generics)
        const targetType = mapType(targetTypeStr);
        let srcType: WatType;
        if (/^\w+$/.test(inner) && locals.has(inner)) {
          srcType = locals.get(inner)!;
        } else {
          const sfM = inner.match(/^(\w+)\.(\w+)$/);
          if (sfM) {
            const sv = this.structVars.get(sfM[1]);
            const field = sv?.def.fields.find((f) => f.name === sfM[2]);
            srcType = (field?.type as WatType) ?? defaultType;
          } else {
            // compound expressions default to i32 (arithmetic result)
            srcType = "i32";
          }
        }
        return this.emitTypeCast(inner, srcType, targetType, locals);
      }
    }

    // Parenthesised group — only strip when the outer ( truly wraps the whole expression.
    // e.g. "(a + b)" → yes; "(a + b) + (c + d)" → no (first ) closes before the end).
    if (expr.startsWith("(") && expr.endsWith(")")) {
      let pd = 0, isWrapped = true;
      for (let pi = 0; pi < expr.length - 1; pi++) {
        if (expr[pi] === "(" || expr[pi] === "[") pd++;
        else if (expr[pi] === ")" || expr[pi] === "]") pd--;
        if (pd === 0) {
          isWrapped = false;
          break;
        }
      }
      if (isWrapped) return this.emitExpr(expr.slice(1, -1), locals, defaultType);
    }

    // Phase 52.8: Array.isArray(x) — closed-world compile-time constant. True when x is a
    // known array/typed-array variable, false otherwise.
    {
      const isArrM = expr.match(/^Array\.isArray\s*\((.+)\)$/);
      if (isArrM && parenDepthNeverNegative(isArrM[1])) {
        const arg = isArrM[1].trim();
        const known = this.arrayVars.has(arg) || this.moduleArrayVars.has(arg) ||
          this.typedArrayVars.has(arg);
        return `(i32.const ${known ? 1 : 0})`;
      }
    }

    // Phase 52.7: `"field" in obj` — closed-world compile-time membership test. Resolved to
    // 1/0 when obj's struct/class type is known and the key is a string literal.
    {
      const inIdx = this.findDepth0Keyword(expr, " in ");
      if (inIdx !== -1) {
        const keyRaw = expr.slice(0, inIdx).trim();
        const objName = expr.slice(inIdx + 4).trim();
        const km = keyRaw.match(/^["'](.+)["']$/);
        if (km && /^\w+$/.test(objName)) {
          const has = this.structHasField(objName, km[1]);
          if (has !== null) return `(i32.const ${has ? 1 : 0})`;
        }
      }
    }

    // Bigint literal: 42n → (i64.const 42)
    if (/^-?\d+n$/.test(expr)) {
      return `(i64.const ${expr.slice(0, -1)})`;
    }

    // Numeric literal (decimal, float, or scientific notation e.g. 1e16, 3.5e-4)
    if (/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(expr)) {
      return `(${defaultType}.const ${expr})`;
    }

    // Hex integer literal (e.g. 0x6D2B79F5, 0xFF)
    if (/^0[xX][0-9a-fA-F]+$/.test(expr)) {
      const n = parseInt(expr, 16);
      if (defaultType === "i32") return `(i32.const ${n})`;
      if (defaultType === "i64") return `(i64.const ${n})`;
      return `(f64.const ${n})`;
    }

    // Array .length property: dynamic → runtime load from header; static → compile-time constant
    // Phase 12: arrName[idx].length — load i-th element (a row ptr), then load its length
    const idxLenMatch = expr.match(/^(\w+)\[([^\]]+)\]\.length$/);
    if (idxLenMatch) {
      const arrName = idxLenMatch[1];
      const arrInfo = this.arrayVars.get(arrName);
      const idxWat = this.emitArrayIndex(idxLenMatch[2], locals);
      // String array element .length: arr[i].length → len field of the 8-byte ptr+len pair
      if (arrInfo && (arrInfo.isStringArr || arrInfo.elemType === "string")) {
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? this.arrGetWat(arrName)
          : `(i32.const ${arrInfo.ptr})`;
        const elemAddrWat =
          `(i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 3)))`;
        return `(i32.load offset=4 ${elemAddrWat})`;
      }
      if (arrInfo || locals.get(arrName) === "i32") {
        const baseWat = `(local.get $${arrName})`;
        const rowPtrWat =
          `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
        return `(i32.load ${rowPtrWat})`;
      }
    }

    const lenPropMatch = expr.match(/^(\w+)\.length$/);
    if (lenPropMatch) {
      const arrInfo = this.arrayVars.get(lenPropMatch[1]);
      if (arrInfo) {
        const rawLen = (arrInfo.dynamic || arrInfo.ptr < 0)
          ? `(i32.load ${this.arrGetWat(lenPropMatch[1])})`
          : `(i32.const ${arrInfo.length})`;
        const needsF64 = defaultType === "f64" || defaultType === "f32";
        return needsF64 ? `(f64.convert_i32_s ${rawLen})` : rawLen;
      }
      // String .length property: varName.length
      if (locals.get(lenPropMatch[1]) === "string") {
        const rawStrLen = `(local.get $${lenPropMatch[1]}_len)`;
        const needsF64s = defaultType === "f64" || defaultType === "f32";
        return needsF64s ? `(f64.convert_i32_s ${rawStrLen})` : rawStrLen;
      }
      // Phase 12: i32 local holding a dynamic array pointer — load length from header
      if (locals.get(lenPropMatch[1]) === "i32") {
        const rawI32Len = `(i32.load (local.get $${lenPropMatch[1]}))`;
        const needsF64i = defaultType === "f64" || defaultType === "f32";
        return needsF64i ? `(f64.convert_i32_s ${rawI32Len})` : rawI32Len;
      }
    }

    // Phase 31: TypedArray .byteLength property
    const byteLenMatch = expr.match(/^(\w+)\.byteLength$/);
    if (byteLenMatch) {
      const taInfoBL = this.typedArrayVars.get(byteLenMatch[1]);
      if (taInfoBL) {
        const lenWat = `(i32.load (local.get $${byteLenMatch[1]}))`;
        return taInfoBL.shift === 0 ? lenWat : `(i32.shl ${lenWat} (i32.const ${taInfoBL.shift}))`;
      }
    }

    // String method calls returning i32 (can appear in any expression context)
    // str.indexOf(sub[, start]) → i32 offset or -1
    const strIndexOfMatch = expr.match(/^(\w+)\.indexOf\s*\((.+)\)$/);
    if (
      strIndexOfMatch && locals.get(strIndexOfMatch[1]) === "string" &&
      parenDepthNeverNegative(strIndexOfMatch[2])
    ) {
      this.needsStringOpHelpers = true;
      // Split sub from optional start position, preserving quoted strings
      const rawArgs = strIndexOfMatch[2].trim();
      const argsArr = this.splitArgs(rawArgs);
      const subPtrLen = this.emitStringPtrLen(argsArr[0].trim(), locals);
      let wat: string;
      if (argsArr.length >= 2) {
        const fromWat = this.emitExpr(argsArr[1].trim(), locals, "i32");
        wat = `(call $__str_indexof_from (local.get $${strIndexOfMatch[1]}_ptr) (local.get $${
          strIndexOfMatch[1]
        }_len) ${subPtrLen} ${fromWat})`;
      } else {
        wat = `(call $__str_indexof (local.get $${strIndexOfMatch[1]}_ptr) (local.get $${
          strIndexOfMatch[1]
        }_len) ${subPtrLen})`;
      }
      // When used in f64 context (number variable holding indexOf result), convert
      if (defaultType === "f64" || defaultType === "f32") return `(f64.convert_i32_s ${wat})`;
      return wat;
    }
    // str.includes(sub) → i32 bool (1 = found, 0 = not found)
    const strIncludesMatch = expr.match(/^(\w+)\.includes\s*\((.+)\)$/);
    if (
      strIncludesMatch && locals.get(strIncludesMatch[1]) === "string" &&
      parenDepthNeverNegative(strIncludesMatch[2])
    ) {
      this.needsStringOpHelpers = true;
      const subPtrLen = this.emitStringPtrLen(strIncludesMatch[2].trim(), locals);
      return `(i32.ne (call $__str_indexof (local.get $${strIncludesMatch[1]}_ptr) (local.get $${
        strIncludesMatch[1]
      }_len) ${subPtrLen}) (i32.const -1))`;
    }

    // Phase 51: chained `s.at(i).charCodeAt(j)` → char code at the normalized index of `s`.
    // `.at(i)` returns a 1-char string, so j is 0 and the result is the code at norm(i). Without
    // this, the chain fell through to the catch-all expr stub and silently returned 0 (the plain
    // charCodeAt handler below only matches a `\w+` receiver, not `s.at(i)`).
    const atChainMatch = expr.match(/^(\w+)\.at\s*\(([^)]*)\)\.charCodeAt\s*\([^)]*\)$/);
    if (atChainMatch && locals.get(atChainMatch[1]) === "string") {
      this.needsStringExtHelpers = true;
      const recv = atChainMatch[1];
      const idxWat = this.emitArrayIndex(atChainMatch[2].trim(), locals);
      const lenWat = `(local.get $${recv}_len)`;
      // normalize a possibly-negative index: i >= 0 ? i : len + i
      const normIdx =
        `(select ${idxWat} (i32.add ${lenWat} ${idxWat}) (i32.ge_s ${idxWat} (i32.const 0)))`;
      const ccaWat = `(call $__str_char_code_at (local.get $${recv}_ptr) ${lenWat} ${normIdx})`;
      if (defaultType === "f64" || defaultType === "f32") return `(f64.convert_i32_s ${ccaWat})`;
      return ccaWat;
    }

    // Phase 27: str.charCodeAt(i) → i32 char code (promoted to f64 in numeric context)
    // parenDepthNeverNegative guards the greedy `(.+)`: when the expression as a whole ends in
    // a `)` belonging to a LATER call (e.g. `p.charCodeAt(i) === t.charCodeAt(i)`), the matched
    // arg has unbalanced parens — skip so the binary-op loop sees the `===`/`!==`/`<`/… instead.
    const charCodeAtMatch = expr.match(/^(\w+)\.charCodeAt\s*\((.+)\)$/);
    if (
      charCodeAtMatch && locals.get(charCodeAtMatch[1]) === "string" &&
      parenDepthNeverNegative(charCodeAtMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      const idxWat = this.emitExpr(charCodeAtMatch[2].trim(), locals, "i32");
      const ccaWat = `(call $__str_char_code_at (local.get $${
        charCodeAtMatch[1]
      }_ptr) (local.get $${charCodeAtMatch[1]}_len) ${idxWat})`;
      if (defaultType === "f64" || defaultType === "f32") return `(f64.convert_i32_s ${ccaWat})`;
      return ccaWat;
    }

    // Phase 27: str.startsWith(sub) → i32 bool
    const startsWithMatch = expr.match(/^(\w+)\.startsWith\s*\((.+)\)$/);
    if (
      startsWithMatch && locals.get(startsWithMatch[1]) === "string" &&
      parenDepthNeverNegative(startsWithMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      const subPtrLen = this.emitStringPtrLen(startsWithMatch[2].trim(), locals);
      return `(call $__str_starts_with (local.get $${startsWithMatch[1]}_ptr) (local.get $${
        startsWithMatch[1]
      }_len) ${subPtrLen})`;
    }

    // Phase 27: str.endsWith(sub) → i32 bool
    const endsWithMatch = expr.match(/^(\w+)\.endsWith\s*\((.+)\)$/);
    if (
      endsWithMatch && locals.get(endsWithMatch[1]) === "string" &&
      parenDepthNeverNegative(endsWithMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      const subPtrLen = this.emitStringPtrLen(endsWithMatch[2].trim(), locals);
      return `(call $__str_ends_with (local.get $${endsWithMatch[1]}_ptr) (local.get $${
        endsWithMatch[1]
      }_len) ${subPtrLen})`;
    }

    // Phase 27: str.split(delim) → i32 pointer to string array (8-byte elements)
    // `template`.split(sep) — receiver is a template literal (e.g. `${n}`.split(".") in toFixed).
    // Materialize the receiver string into the $__str_op temp pair, then call $__str_split.
    const tmplSplitMatch = expr.match(/^(`(?:[^`\\]|\\.)*`)\s*\.split\s*\((.+)\)$/);
    if (tmplSplitMatch && parenDepthNeverNegative(tmplSplitMatch[2])) {
      this.needsStringExtHelpers = true;
      this.needsStringOpHelpers = true;
      const recvAssign = this.emitStringAssign("__str_op", tmplSplitMatch[1]!, locals);
      const delimPtrLen = this.emitStringPtrLen(tmplSplitMatch[2]!.trim(), locals);
      return `(block (result i32) ${recvAssign} (call $__str_split (local.get $__str_op_ptr) (local.get $__str_op_len) ${delimPtrLen}))`;
    }

    const splitMatch = expr.match(/^(\w+)\.split\s*\((.+)\)$/);
    if (
      splitMatch && locals.get(splitMatch[1]) === "string" && parenDepthNeverNegative(splitMatch[2])
    ) {
      this.needsStringExtHelpers = true;
      this.needsStringOpHelpers = true;
      const delimPtrLen = this.emitStringPtrLen(splitMatch[2].trim(), locals);
      return `(call $__str_split (local.get $${splitMatch[1]}_ptr) (local.get $${
        splitMatch[1]
      }_len) ${delimPtrLen})`;
    }

    // Phase 6d: 2D array element read: arr[rowIdx][colIdx]
    // Must come before the 1D check since the greedy 1D regex would swallow both brackets.
    const bracket2DMatch = expr.match(/^(\w+)\[(.+?)\]\[(.+)\]$/);
    if (bracket2DMatch) {
      const outerInfo = this.arrayVars.get(bracket2DMatch[1]);
      if (outerInfo?.is2D) {
        const rowIdxWat = this.emitExpr(bracket2DMatch[2], locals, "i32");
        const colIdxWat = this.emitExpr(bracket2DMatch[3], locals, "i32");
        const elemType = outerInfo.elemType;
        const loadOp = elemType === "f64"
          ? "f64.load"
          : elemType === "i64"
          ? "i64.load"
          : "i32.load";
        const shift = (elemType === "f64" || elemType === "i64") ? 3 : 2;
        // Outer array: dynamic; row pointer is stored at outer + 8 + rowIdx * 4
        const rowPtrWat = `(i32.load (i32.add (i32.add (local.get $${
          bracket2DMatch[1]
        }) (i32.const 8)) (i32.shl ${rowIdxWat} (i32.const 2))))`;
        // Element is at rowPtr + 8 + colIdx * elemSize
        const raw2D =
          `(${loadOp} (i32.add (i32.add ${rowPtrWat} (i32.const 8)) (i32.shl ${colIdxWat} (i32.const ${shift}))))`;
        // Apply narrowing when caller context expects a narrower integer type
        if (elemType === "f64" && defaultType === "i32") return `(i32.trunc_f64_s ${raw2D})`;
        if (elemType === "i64" && defaultType === "i32") return `(i32.wrap_i64 ${raw2D})`;
        return raw2D;
      }
    }

    // Phase 12: inline array literal [e0, e1, ...] used as expression (e.g., argument or 2D-literal row).
    // Allocates a dynamic heap array using $__arr_tmp (outer) and $__arr_tmp2 (inner rows for 2D).
    if (expr.startsWith("[") && expr.endsWith("]")) {
      const inner = expr.slice(1, -1).trim();
      const elements = inner ? this.splitArgs(inner) : [];
      const is2D = elements.some((e) => e.trim().startsWith("["));
      if (is2D) {
        const outerCap = Math.max(elements.length * 2, 8);
        const outerSz = outerCap * 4 + 8;
        const parts: string[] = [
          `(local.set $__arr_tmp (call $__malloc (i32.const ${outerSz})))`,
          `(i32.store (local.get $__arr_tmp) (i32.const ${elements.length}))`,
          `(i32.store offset=4 (local.get $__arr_tmp) (i32.const ${outerCap}))`,
        ];
        for (let ei = 0; ei < elements.length; ei++) {
          const rowExpr = elements[ei].trim();
          const rowElemsRaw = rowExpr.startsWith("[") && rowExpr.endsWith("]")
            ? rowExpr.slice(1, -1).trim()
            : rowExpr;
          const rowElems = rowElemsRaw ? this.splitArgs(rowElemsRaw) : [];
          const rowCap = Math.max(rowElems.length * 2, 8);
          const rowSz = rowCap * 4 + 8;
          parts.push(`(local.set $__arr_tmp2 (call $__malloc (i32.const ${rowSz})))`);
          parts.push(`(i32.store (local.get $__arr_tmp2) (i32.const ${rowElems.length}))`);
          parts.push(`(i32.store offset=4 (local.get $__arr_tmp2) (i32.const ${rowCap}))`);
          for (let ej = 0; ej < rowElems.length; ej++) {
            const valWat = this.emitExpr(rowElems[ej].trim(), locals, "i32");
            parts.push(`(i32.store offset=${8 + ej * 4} (local.get $__arr_tmp2) ${valWat})`);
          }
          parts.push(
            `(i32.store offset=${8 + ei * 4} (local.get $__arr_tmp) (local.get $__arr_tmp2))`,
          );
        }
        parts.push(`(local.get $__arr_tmp)`);
        return `(block (result i32) ${parts.join(" ")})`;
      }
      // 1D inline string array literal: all elements are quoted strings → allocate in data section
      const allStrLits = elements.length > 0 && elements.every((e) => {
        const t = e.trim();
        return (t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"));
      });
      if (allStrLits) {
        const arrPtr = this.allocArrayData(elements, "string");
        return `(i32.const ${arrPtr})`;
      }
      // 1D inline array literal
      const elemType: WatType = (defaultType === "f64" || defaultType === "i64")
        ? defaultType
        : "i32";
      const storeOp = elemType === "f64"
        ? "f64.store"
        : elemType === "i64"
        ? "i64.store"
        : "i32.store";
      const elemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
      const cap1D = Math.max(elements.length * 2, 8);
      const size1D = cap1D * elemSize + 8;
      const pts: string[] = [
        `(local.set $__arr_tmp (call $__malloc (i32.const ${size1D})))`,
        `(i32.store (local.get $__arr_tmp) (i32.const ${elements.length}))`,
        `(i32.store offset=4 (local.get $__arr_tmp) (i32.const ${cap1D}))`,
      ];
      for (let ei = 0; ei < elements.length; ei++) {
        const valWat = this.emitExpr(elements[ei].trim(), locals, elemType);
        pts.push(`(${storeOp} offset=${8 + ei * elemSize} (local.get $__arr_tmp) ${valWat})`);
      }
      pts.push(`(local.get $__arr_tmp)`);
      return `(block (result i32) ${pts.join(" ")})`;
    }

    // Phase 23: tuple element read — t[N] where N is a bare integer literal (strict match, avoids greedy confusion)
    const tupleFieldMatch = expr.match(/^(\w+)\[(\d+)\]$/);
    if (tupleFieldMatch) {
      const svTF = this.structVars.get(tupleFieldMatch[1]);
      if (svTF) {
        const fieldIdxTF = parseInt(tupleFieldMatch[2], 10);
        const fieldTF = svTF.def.fields[fieldIdxTF];
        if (fieldTF) {
          const loadOpTF = fieldTF.type === "f64"
            ? "f64.load"
            : fieldTF.type === "i64"
            ? "i64.load"
            : "i32.load";
          const baseWatTF = svTF.ptr === -1
            ? `(local.get $${tupleFieldMatch[1]})`
            : `(i32.const ${svTF.ptr})`;
          return `(${loadOpTF} (i32.add ${baseWatTF} (i32.const ${fieldTF.offset})))`;
        }
      }
    }

    // Struct array element field access: arr[idx].field
    const arrElemFieldRe = /^(\w+)\[([^\]]+)\]\.(\w+)$/;
    const aefMatch = expr.match(arrElemFieldRe);
    if (aefMatch) {
      const [, arrName, idxExpr, fieldName] = aefMatch;
      const arrInfo = this.arrayVars.get(arrName);
      // structTypeName: struct element type preserved; also check elemType for non-i32 struct names
      const structTypeName = arrInfo?.structTypeName ??
        (arrInfo && arrInfo.elemType !== "f64" && arrInfo.elemType !== "i32" &&
            arrInfo.elemType !== "i64"
          ? arrInfo.elemType
          : undefined);
      if (arrInfo && structTypeName) {
        const structDef = this.structDefs.get(structTypeName);
        if (structDef) {
          const field = structDef.fields.find((f) => f.name === fieldName);
          if (field) {
            const idxWat = this.emitArrayIndex(idxExpr, locals);
            const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
              ? this.arrGetWat(arrName)
              : `(i32.const ${arrInfo.ptr})`;
            const ptrWat =
              `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
            const loadOp = field.type === "f64"
              ? "f64.load"
              : field.type === "i64"
              ? "i64.load"
              : "i32.load";
            return `(${loadOp} (i32.add ${ptrWat} (i32.const ${field.offset})))`;
          }
        }
      }
    }

    // Phase 47: arr[idx].method(args) — class method call on array element (supports runtime vtable dispatch)
    const arrMethodCallRe = /^(\w+)\[([^\]]+)\]\.(\w+)\s*\((.*)\)$/;
    const amcMatch = expr.match(arrMethodCallRe);
    if (amcMatch) {
      const [, amcArr, amcIdx, amcMethod, amcArgsStr] = amcMatch;
      const amcInfo = this.arrayVars.get(amcArr);
      const amcStn = amcInfo?.structTypeName ??
        (amcInfo && amcInfo.elemType !== "f64" && amcInfo.elemType !== "i32" &&
            amcInfo.elemType !== "i64"
          ? amcInfo.elemType
          : undefined);
      if (amcInfo && amcStn && this.classDefs.has(amcStn)) {
        const amcIdxWat = this.emitArrayIndex(amcIdx, locals);
        const amcBase = (amcInfo.ptr === -1 || amcInfo.dynamic)
          ? this.arrGetWat(amcArr)
          : `(i32.const ${amcInfo.ptr})`;
        // Object pointer stored in array at shift=2 (i32 elements)
        const amcObjPtr =
          `(i32.load (i32.add (i32.add ${amcBase} (i32.const 8)) (i32.shl ${amcIdxWat} (i32.const 2))))`;
        const amcArgs = amcArgsStr ? this.splitArgs(amcArgsStr) : [];
        const amcEmitCall = (cls: string): string => {
          const fn2 = this.resolveMethodFunc(cls, amcMethod) ?? `${cls}_${amcMethod}`;
          const fn2Def = this.functions.find((f) => f.name === fn2);
          const eArgs = amcArgs.map((a, i) =>
            this.emitExpr(a, locals, fn2Def?.params[i + 1]?.type ?? ("i32" as WatType))
          );
          return `(call $${fn2} ${amcObjPtr} ${eArgs.join(" ")})`.trim();
        };
        if (this.classHeaderSize === 0) {
          return amcEmitCall(amcStn);
        }
        // Runtime vtable dispatch: read class tag at offset 0, dispatch to matching method
        const amcSubs = this.findSubclasses(amcStn);
        amcSubs.sort((a, b) => (this.classTags.get(a) ?? 0) - (this.classTags.get(b) ?? 0));
        if (amcSubs.length === 0) {
          // No concrete subclass found for the element's declared type — a mis-registered class
          // hierarchy. Fail loud rather than silently dispatching to 0.
          this.diagnostics.push(
            `No subclass found for '${amcStn}.${amcMatch[3]}()' element method dispatch`,
          );
          return `(i32.const 0)`;
        }
        if (amcSubs.length === 1) return amcEmitCall(amcSubs[0]);
        const amcBaseFunc = this.resolveMethodFunc(amcStn, amcMethod);
        const amcBaseFnDef = amcBaseFunc
          ? this.functions.find((f) => f.name === amcBaseFunc)
          : null;
        const amcResult = amcBaseFnDef?.result ?? null;
        // Build if-else dispatch from last class outward (last is the default)
        let amcDispatch = amcEmitCall(amcSubs[amcSubs.length - 1]);
        for (let k = amcSubs.length - 2; k >= 0; k--) {
          const cls = amcSubs[k];
          const tag = this.classTags.get(cls) ?? (k + 1);
          const cond = `(i32.eq (i32.load ${amcObjPtr}) (i32.const ${tag}))`;
          amcDispatch = amcResult
            ? `(if (result ${amcResult}) ${cond} (then ${amcEmitCall(cls)}) (else ${amcDispatch}))`
            : `(if ${cond} (then ${amcEmitCall(cls)}) (else ${amcDispatch}))`;
        }
        return amcDispatch;
      }
    }

    // Array element read: arr[idx]
    const bracketMatch = expr.match(/^(\w+)\[([^\]]*)\]$/);
    if (bracketMatch) {
      // Phase 23: fallback tuple element read (handles edge cases where bracketMatch fires)
      const svE = this.structVars.get(bracketMatch[1]);
      if (svE && /^\d+$/.test(bracketMatch[2])) {
        const fieldIdx2 = parseInt(bracketMatch[2], 10);
        const field2 = svE.def.fields[fieldIdx2];
        if (field2) {
          const loadOp2 = field2.type === "f64"
            ? "f64.load"
            : field2.type === "i64"
            ? "i64.load"
            : "i32.load";
          const baseWat2 = svE.ptr === -1
            ? `(local.get $${bracketMatch[1]})`
            : `(i32.const ${svE.ptr})`;
          return `(${loadOp2} (i32.add ${baseWat2} (i32.const ${field2.offset})))`;
        }
      }
      const arrInfo = this.arrayVars.get(bracketMatch[1]);
      if (arrInfo) {
        // String array element: 8-byte (ptr,len) elements — return the ptr word only in expr context.
        const isStrElem = arrInfo.isStringArr || arrInfo.elemType === "string";
        // 2D array single-index: loads i32 pointer to the inner row array (always 4-byte i32.load).
        const loadOp = arrInfo.is2D
          ? "i32.load"
          : arrInfo.elemType === "f64"
          ? "f64.load"
          : arrInfo.elemType === "i64"
          ? "i64.load"
          : "i32.load";
        const shift = arrInfo.is2D
          ? 2
          : isStrElem
          ? 3
          : (arrInfo.elemType === "f64" || arrInfo.elemType === "i64")
          ? 3
          : 2;
        const idxWat = this.emitArrayIndex(bracketMatch[2], locals);
        // All arrays (static, dynamic, params) use an 8-byte [length, capacity] header.
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? this.arrGetWat(bracketMatch[1])
          : `(i32.const ${arrInfo.ptr})`;
        const dataBase = `(i32.add ${baseWat} (i32.const 8))`;
        return `(${loadOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))))`;
      }
      // Phase 31: TypedArray element read
      const taInfoBr = this.typedArrayVars.get(bracketMatch[1]);
      if (taInfoBr) {
        const idxWat = this.emitArrayIndex(bracketMatch[2], locals);
        const addrWat = taInfoBr.shift === 0
          ? `(i32.add (i32.add (local.get $${bracketMatch[1]}) (i32.const 8)) ${idxWat})`
          : `(i32.add (i32.add (local.get $${
            bracketMatch[1]
          }) (i32.const 8)) (i32.shl ${idxWat} (i32.const ${taInfoBr.shift})))`;
        return `(${taInfoBr.loadOp} ${addrWat})`;
      }
      // Phase 12: fallback — i32 local holding a dynamic i32[] array pointer (captured or assigned)
      // Phase 23: skip if variable is a struct/tuple pointer (not a dynamic array)
      if (locals.get(bracketMatch[1]) === "i32" && !this.structVars.has(bracketMatch[1])) {
        const idxWat = this.emitArrayIndex(bracketMatch[2], locals);
        return `(i32.load (i32.add (i32.add (local.get $${
          bracketMatch[1]
        }) (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
      }
    }

    // Dynamic array methods used as expressions: arr.push(val), arr.pop(), arr.shift(), arr.unshift(val)
    const dynArrExpr = expr.match(/^(\w+)\.(push|pop|shift|unshift)\s*\((.*?)\)$/);
    if (dynArrExpr) {
      const arrName = dynArrExpr[1];
      const method = dynArrExpr[2] as "push" | "pop" | "shift" | "unshift";
      const argsStr = dynArrExpr[3].trim();
      const arrInfo = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const key = `${method}_${arrInfo.elemType}`;
        const helperName = `$__dynarr_${key}`;
        this.dynArrHelpers.add(key);
        if (method === "push" || method === "unshift") {
          const valWat = this.emitExpr(argsStr, locals, arrInfo.elemType);
          const callExpr = `(call ${helperName} ${this.arrGetWat(arrName)} ${valWat})`;
          if (this.moduleArrayVars.has(arrName)) {
            // Global array: use block to sequence set then load-length
            return `(block (result i32) ${this.arrSetWat(arrName, callExpr)} (i32.load ${
              this.arrGetWat(arrName)
            }))`;
          }
          // Local array: use local.tee to update and read new length in one expression
          return `(i32.load (local.tee $${arrName} ${callExpr}))`;
        }
        return `(call ${helperName} ${this.arrGetWat(arrName)})`;
      }
    }

    // Dynamic array read/query methods: arr.indexOf(val), arr.includes(val), arr.slice(start,end)
    // Dynamic array callback methods (expression form): arr.map(fn), arr.filter(fn), arr.find(fn), arr.reduce(fn,init)
    // Phase 28: arr.every(fn), arr.some(fn), arr.findIndex(fn), arr.at(n), arr.reverse(), arr.fill(val,...), arr.sort(fn?)
    // Phase 37: arr.flat(), arr.flatMap(fn)
    const dynArrMethod = expr.match(
      /^(\w+)\.(indexOf|includes|slice|map|filter|find|reduce|every|some|findIndex|at|reverse|fill|sort|flat|flatMap|concat)\s*\(([\s\S]*)\)$/,
    );
    if (dynArrMethod && parenDepthNeverNegative(dynArrMethod[3].trim())) {
      const arrName = dynArrMethod[1];
      const method = dynArrMethod[2] as
        | "indexOf"
        | "includes"
        | "slice"
        | "map"
        | "filter"
        | "find"
        | "reduce"
        | "every"
        | "some"
        | "findIndex"
        | "at"
        | "reverse"
        | "fill"
        | "sort"
        | "flat"
        | "flatMap"
        | "concat";
      const argsStr = dynArrMethod[3].trim();
      const arrInfo = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const elemType = arrInfo.elemType as WatType;
        if (method === "indexOf") {
          const key = `indexof_${elemType}`;
          this.dynArrHelpers.add(key);
          const valWat = this.emitExpr(argsStr, locals, elemType);
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} ${valWat})`;
        }
        if (method === "includes") {
          const key = `indexof_${elemType}`;
          this.dynArrHelpers.add(key);
          const valWat = this.emitExpr(argsStr, locals, elemType);
          return `(i32.ne (call $__dynarr_${key} ${
            this.arrGetWat(arrName)
          } ${valWat}) (i32.const -1))`;
        }
        if (method === "slice") {
          const isStrSlice = arrInfo.isStringArr || elemType === "string";
          const key = isStrSlice ? "slice_string" : `slice_${elemType}`;
          this.dynArrHelpers.add(key);
          const args = this.splitArgs(argsStr);
          const startWat = args[0]?.trim()
            ? this.emitExpr(args[0].trim(), locals, "i32")
            : "(i32.const 0)";
          const endWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, "i32")
            : `(i32.load ${this.arrGetWat(arrName)})`;
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} ${startWat} ${endWat})`;
        }
        // Phase 28: every / some — predicate over all elements
        if (method === "every" || method === "some") {
          const key = `${method}_${elemType}`;
          this.dynArrHelpers.add(key);
          this.getOrCreateFuncType([elemType], "i32");
          const args = this.splitArgs(argsStr);
          const fnIdx = this.getFuncTableIdx(args[0]?.trim() ?? "");
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} (i32.const ${fnIdx}))`;
        }
        // Phase 28: findIndex — returns index of first match or -1
        if (method === "findIndex") {
          const key = `findindex_${elemType}`;
          this.dynArrHelpers.add(key);
          this.getOrCreateFuncType([elemType], "i32");
          const args = this.splitArgs(argsStr);
          const fnIdx = this.getFuncTableIdx(args[0]?.trim() ?? "");
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} (i32.const ${fnIdx}))`;
        }
        // Phase 28: at(n) — element at index (supports negative wrap)
        if (method === "at") {
          const key = `at_${elemType}`;
          this.dynArrHelpers.add(key);
          const nWat = this.emitExpr(argsStr, locals, "i32");
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} ${nWat})`;
        }
        // Phase 28: reverse() — in-place reversal, returns arr ptr
        if (method === "reverse") {
          const key = `reverse_${elemType}`;
          this.dynArrHelpers.add(key);
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)})`;
        }
        // Phase 28: fill(val, start?, end?) — fills range, returns arr ptr
        if (method === "fill") {
          const key = `fill_${elemType}`;
          this.dynArrHelpers.add(key);
          const args = this.splitArgs(argsStr);
          const valWat = args[0]?.trim()
            ? this.emitExpr(args[0].trim(), locals, elemType)
            : zeroOf(elemType);
          const startWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, "i32")
            : "(i32.const 0)";
          const endWat = args[2]?.trim()
            ? this.emitExpr(args[2].trim(), locals, "i32")
            : `(i32.load ${this.arrGetWat(arrName)})`;
          return `(call $__dynarr_${key} ${
            this.arrGetWat(arrName)
          } ${valWat} ${startWat} ${endWat})`;
        }
        // Phase 28: sort(fn?) — in-place insertion sort, returns arr ptr
        if (method === "sort") {
          const args = this.splitArgs(argsStr);
          const fnName = args[0]?.trim() ?? "";
          if (fnName) {
            const key = `sortcmp_${elemType}`;
            this.dynArrHelpers.add(key);
            this.getOrCreateFuncType([elemType, elemType], "i32");
            const fnIdx = this.getFuncTableIdx(fnName);
            return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} (i32.const ${fnIdx}))`;
          } else {
            const key = `sort_${elemType}`;
            this.dynArrHelpers.add(key);
            return `(call $__dynarr_${key} ${this.arrGetWat(arrName)})`;
          }
        }
        // Phase 37: flat() — one-level flatten of a 2D array
        if (method === "flat") {
          if (!arrInfo.is2D) return `(;? flat() requires 2D array ;)`;
          const key = `flat_${elemType}`;
          this.dynArrHelpers.add(key);
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)})`;
        }
        // Phase 37: flatMap(fn) — map each element to an array, then flatten
        if (method === "flatMap") {
          const key = `flatmap_${elemType}`;
          this.dynArrHelpers.add(key);
          this.getOrCreateFuncType([elemType], "i32"); // fn: (elem) → i32 ptr to inner array
          const args = this.splitArgs(argsStr);
          const fnIdx = this.getFuncTableIdx(args[0]?.trim() ?? "");
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} (i32.const ${fnIdx}))`;
        }
        // Phase 49: concat(other) — concatenate two arrays, return new array
        if (method === "concat") {
          const key = `concat_${elemType}`;
          this.dynArrHelpers.add(key);
          const otherWat = this.emitExpr(argsStr, locals, "i32");
          return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} ${otherWat})`;
        }
        // Callback methods: map, filter, find, reduce
        const args = this.splitArgs(argsStr);
        const fnName = args[0]?.trim() ?? "";
        const fnIdx = this.getFuncTableIdx(fnName);
        const key = `${method}_${elemType}`;
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
          const initWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, elemType)
            : zeroOf(elemType);
          return `(call $__dynarr_${key} ${
            this.arrGetWat(arrName)
          } (i32.const ${fnIdx}) ${initWat})`;
        }
        return `(call $__dynarr_${key} ${this.arrGetWat(arrName)} (i32.const ${fnIdx}))`;
      }
    }

    // Phase 49: chained array method calls — e.g. arr.filter(f).map(g)
    // The dynArrMethod regex only matches simple-name receivers; when the receiver is itself
    // a method call, use splitLastMethodCall + inferChainElemType to emit the chain inline.
    {
      const chainParsed = this.splitLastMethodCall(expr);
      if (chainParsed) {
        const CHAIN_METHODS: Record<string, boolean> = {
          "map": true,
          "filter": true,
          "slice": true,
          "concat": true,
          "sort": true,
          "reverse": true,
          "fill": true,
          "flat": true,
          "flatMap": true,
        };
        if (CHAIN_METHODS[chainParsed.method]) {
          const elemType = this.inferChainElemType(chainParsed.receiver, locals);
          if (elemType) {
            const method = chainParsed.method;
            const chainArgs = chainParsed.args.trim();
            const innerWat = this.emitExpr(chainParsed.receiver, locals, "i32");
            const et = elemType as WatType;
            if (method === "map") {
              const key = "map_" + et;
              this.dynArrHelpers.add(key);
              this.getOrCreateFuncType([et], et);
              const fnIdx = this.getFuncTableIdx(chainArgs);
              return "(call $__dynarr_" + key + " " + innerWat + " (i32.const " + fnIdx + "))";
            }
            if (method === "filter") {
              const key = "filter_" + et;
              this.dynArrHelpers.add(key);
              this.getOrCreateFuncType([et], "i32");
              const fnIdx = this.getFuncTableIdx(chainArgs);
              return "(call $__dynarr_" + key + " " + innerWat + " (i32.const " + fnIdx + "))";
            }
            if (method === "concat") {
              const key = "concat_" + et;
              this.dynArrHelpers.add(key);
              const otherWat = this.emitExpr(chainArgs, locals, "i32");
              return "(call $__dynarr_" + key + " " + innerWat + " " + otherWat + ")";
            }
            // Preserve-type methods: reverse, fill, sort, slice, flat, flatMap
            const simpleKey = method + "_" + et;
            this.dynArrHelpers.add(simpleKey);
            return "(call $__dynarr_" + simpleKey + " " + innerWat + ")";
          }
        }
      }
    }

    // this.field (read) or this.method(args) — inside a class instance method
    if (expr.startsWith("this.") && this.currentMethodClass) {
      const dotMethodMatch = expr.match(/^this\.(\w+)\s*\(([\s\S]*)\)$/);
      if (dotMethodMatch) {
        const methodName = dotMethodMatch[1];
        const argsStr = dotMethodMatch[2].trim();
        // Phase 47: walk inheritance chain to find overriding or inherited method
        const funcName = this.resolveMethodFunc(this.currentMethodClass!, methodName) ??
          `${this.currentMethodClass}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
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
        // Phase 29: getter dispatch before raw field load
        const getter = cd?.methods.find((m) => m.isGetter && m.name === dotFieldMatch[1]);
        if (getter) {
          return `(call $${this.currentMethodClass}_get_${dotFieldMatch[1]} (local.get $__self))`;
        }
        const field = cd?.struct.fields.find((f) => f.name === dotFieldMatch[1]);
        if (field) {
          const loadOp = field.type === "f64"
            ? "f64.load"
            : field.type === "i64"
            ? "i64.load"
            : "i32.load";
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
      // Phase 29: static field read — ClassName.fieldName → (global.get $ClassName_fieldName)
      const staticCd = this.classDefs.get(enumDotMatch[1]);
      if (staticCd) {
        const globalKey = `${enumDotMatch[1]}_${enumDotMatch[2]}`;
        if (this.moduleGlobals.has(globalKey)) {
          return `(global.get $${globalKey})`;
        }
      }
      // Phase 30: namespace constant — Namespace.constName → (global.get $Namespace_constName)
      if (this.namespaceDefs.has(enumDotMatch[1])) {
        const globalKey = `${enumDotMatch[1]}_${enumDotMatch[2]}`;
        if (this.moduleGlobals.has(globalKey)) {
          return `(global.get $${globalKey})`;
        }
      }
    }

    // Struct field read: p.field  (where p is a known struct variable)
    // This check must come after enum dot-match (which has already returned if it matched).
    const structFieldMatch = expr.match(/^(\w+)\.(\w+)$/);
    if (structFieldMatch) {
      // Class instance field/getter read (takes priority over struct field)
      const cv = this.classVars.get(structFieldMatch[1]);
      if (cv) {
        const cd = this.classDefs.get(cv.className);
        const field = cd?.struct.fields.find((f) => f.name === structFieldMatch[2]);
        if (field) {
          const loadOp = field.type === "f64"
            ? "f64.load"
            : field.type === "i64"
            ? "i64.load"
            : "i32.load";
          const baseWat = cv.ptr < 0
            ? `(local.get $${structFieldMatch[1]})`
            : `(i32.const ${cv.ptr})`;
          return `(${loadOp} (i32.add ${baseWat} (i32.const ${field.offset})))`;
        }
        // Phase 29: getter dispatch
        const getter = cd?.methods.find((m) => m.isGetter && m.name === structFieldMatch[2]);
        if (getter) {
          const baseWat = cv.ptr < 0
            ? `(local.get $${structFieldMatch[1]})`
            : `(i32.const ${cv.ptr})`;
          return `(call $${cv.className}_get_${structFieldMatch[2]} ${baseWat})`;
        }
      }
      const sv = this.structVars.get(structFieldMatch[1]);
      if (sv) {
        const field = sv.def.fields.find((f) => f.name === structFieldMatch[2]);
        if (field) {
          const loadOp = field.type === "f64"
            ? "f64.load"
            : field.type === "i64"
            ? "i64.load"
            : "i32.load";
          const baseWat = sv.ptr < 0
            ? `(local.get $${structFieldMatch[1]})`
            : `(i32.const ${sv.ptr})`;
          return `(${loadOp} (i32.add ${baseWat} (i32.const ${field.offset})))`;
        }
      }
    }

    // Phase 42: Chained struct field access: a.b.c (outer struct var → nested struct field)
    const chainedFieldMatch = expr.match(/^(\w+)\.(\w+)\.(\w+)$/);
    if (chainedFieldMatch) {
      const sv = this.structVars.get(chainedFieldMatch[1]);
      if (sv) {
        const outerField = sv.def.fields.find((f) => f.name === chainedFieldMatch[2]);
        if (outerField?.structType) {
          const innerDef = this.structDefs.get(outerField.structType);
          const innerField = innerDef?.fields.find((f) => f.name === chainedFieldMatch[3]);
          if (innerField) {
            const outerLoadOp = "i32.load";
            const innerLoadOp = innerField.type === "f64"
              ? "f64.load"
              : innerField.type === "i64"
              ? "i64.load"
              : "i32.load";
            const baseWat = sv.ptr < 0
              ? `(local.get $${chainedFieldMatch[1]})`
              : `(i32.const ${sv.ptr})`;
            const outerPtrWat =
              `(${outerLoadOp} (i32.add ${baseWat} (i32.const ${outerField.offset})))`;
            return `(${innerLoadOp} (i32.add ${outerPtrWat} (i32.const ${innerField.offset})))`;
          }
        }
      }
    }

    // Phase 48: Number.* constants and predicates
    if (expr.startsWith("Number.")) {
      const NUMBER_CONSTS: Record<string, string> = {
        NaN: "nan",
        POSITIVE_INFINITY: "inf",
        NEGATIVE_INFINITY: "-inf",
        EPSILON: "2.220446049250313e-16",
        MAX_SAFE_INTEGER: "9007199254740991",
        MIN_SAFE_INTEGER: "-9007199254740991",
        MAX_VALUE: "1.7976931348623157e+308",
        MIN_VALUE: "5e-324",
      };
      const numConstM = expr.match(/^Number\.(\w+)$/);
      if (numConstM && NUMBER_CONSTS[numConstM[1]] !== undefined) {
        return `(f64.const ${NUMBER_CONSTS[numConstM[1]]})`;
      }
      // Predicates: Number.isNaN(x), Number.isFinite(x), Number.isInteger(x)
      const numPredM = expr.match(/^Number\.(isNaN|isFinite|isInteger)\(([\s\S]*)\)$/);
      let _numPredOk = false;
      if (numPredM) {
        let _d = 0;
        _numPredOk = true;
        for (const _c of numPredM[2]) {
          if (_c === "(") _d++;
          else if (_c === ")") {
            if (_d === 0) {
              _numPredOk = false;
              break;
            }
            _d--;
          }
        }
      }
      if (numPredM && _numPredOk) {
        const predFn = numPredM[1];
        const argExpr = numPredM[2].trim();
        const argWat = this.emitExpr(argExpr, locals, "f64");
        if (predFn === "isNaN") return `(f64.ne ${argWat} ${argWat})`;
        if (predFn === "isFinite") {
          return `(i32.and (f64.lt ${argWat} (f64.const inf)) (f64.gt ${argWat} (f64.const -inf)))`;
        }
        if (predFn === "isInteger") return `(f64.eq (f64.floor ${argWat}) ${argWat})`;
      }
    }

    // Math.* constants and functions
    if (expr.startsWith("Math.")) {
      // Constants
      const MATH_CONSTS: Record<string, string> = {
        PI: "3.141592653589793",
        E: "2.718281828459045",
        LN2: "0.6931471805599453",
        LN10: "2.302585092994046",
        LOG2E: "1.4426950408889634",
        LOG10E: "0.4342944819032518",
        SQRT2: "1.4142135623730951",
        SQRT1_2: "0.7071067811865476",
      };
      const mathConstMatch = expr.match(/^Math\.(\w+)$/);
      if (mathConstMatch && MATH_CONSTS[mathConstMatch[1]] !== undefined) {
        return `(f64.const ${MATH_CONSTS[mathConstMatch[1]]})`;
      }

      // Function calls: Math.fn(args)
      const mathCallMatch = expr.match(/^Math\.(\w+)\(([\s\S]*)\)$/);
      // Guard: the greedy `[\s\S]*` may match the last ')' in a compound expression
      // like `Math.sin(a) * Math.sin(a) + ...`. Verify argsStr has no unmatched ')'
      // at depth 0 — if it does, this isn't a standalone Math call.
      let _mathCallOk = false;
      if (mathCallMatch) {
        let _d = 0;
        _mathCallOk = true;
        for (const _c of mathCallMatch[2]) {
          if (_c === "(") _d++;
          else if (_c === ")") {
            if (_d === 0) {
              _mathCallOk = false;
              break;
            }
            _d--;
          }
        }
      }
      if (mathCallMatch && _mathCallOk) {
        const mathFn = mathCallMatch[1];
        const argsStr = mathCallMatch[2].trim();
        const args = argsStr ? this.splitArgs(argsStr) : [];

        // Always-i32 ops
        if (mathFn === "clz32") {
          return `(i32.clz ${this.emitExpr(args[0] ?? "0", locals, "i32")})`;
        }
        if (mathFn === "imul") {
          const imulWat = `(i32.mul ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${
            this.emitExpr(args[1] ?? "0", locals, "i32")
          })`;
          if (defaultType === "f64" || defaultType === "f32") {
            return `(f64.convert_i32_s ${imulWat})`;
          }
          return imulWat;
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
            return `(call $__i32_min ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${
              this.emitExpr(args[1] ?? "0", locals, "i32")
            })`;
          }
          return `(f64.min ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${
            this.emitExpr(args[1] ?? "0", locals, "f64")
          })`;
        }
        if (mathFn === "max") {
          if (defaultType === "i32") {
            this.mathHelpers.add("i32_max");
            return `(call $__i32_max ${this.emitExpr(args[0] ?? "0", locals, "i32")} ${
              this.emitExpr(args[1] ?? "0", locals, "i32")
            })`;
          }
          return `(f64.max ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${
            this.emitExpr(args[1] ?? "0", locals, "f64")
          })`;
        }

        // Math.round — JavaScript semantics: round half away from zero.
        // f64.nearest uses IEEE 754 ties-to-even (banker's rounding), which
        // gives Math.round(2.5)=2 instead of the JS-correct 3.
        // floor(x + 0.5) matches JS for all normal values.
        if (mathFn === "round") {
          const xWat = this.emitExpr(args[0] ?? "0", locals, "f64");
          return `(f64.floor (f64.add ${xWat} (f64.const 0.5)))`;
        }

        // Native f64 single-arg instructions
        const F64_UNARY: Record<string, string> = {
          sqrt: "f64.sqrt",
          floor: "f64.floor",
          ceil: "f64.ceil",
          trunc: "f64.trunc",
        };
        if (F64_UNARY[mathFn]) {
          return `(${F64_UNARY[mathFn]} ${this.emitExpr(args[0] ?? "0", locals, "f64")})`;
        }

        // Math.pow — iterative WAT helper
        if (mathFn === "pow") {
          this.mathHelpers.add("math_pow");
          return `(call $__math_pow ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${
            this.emitExpr(args[1] ?? "0", locals, "f64")
          })`;
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
          return `(f64.promote_f32 (f32.demote_f64 ${
            this.emitExpr(args[0] ?? "0", locals, "f64")
          }))`;
        }

        // Phase 38: extended math library — inline WAT helpers (Binaryen dead-strips unused)
        const MATH38_UNARY = new Set([
          "sin",
          "cos",
          "tan",
          "asin",
          "acos",
          "atan",
          "log",
          "log2",
          "log10",
          "exp",
          "expm1",
          "log1p",
          "cbrt",
          "sinh",
          "cosh",
          "tanh",
          "asinh",
          "acosh",
          "atanh",
        ]);
        if (mathFn === "random") {
          this.needsMathLib38 = true;
          return `(call $mathlib_random)`;
        }
        if (MATH38_UNARY.has(mathFn)) {
          this.needsMathLib38 = true;
          return `(call $mathlib_${mathFn} ${this.emitExpr(args[0] ?? "0", locals, "f64")})`;
        }
        if (mathFn === "atan2") {
          this.needsMathLib38 = true;
          return `(call $mathlib_atan2 ${this.emitExpr(args[0] ?? "0", locals, "f64")} ${
            this.emitExpr(args[1] ?? "0", locals, "f64")
          })`;
        }
      }
    }

    // Special constants — must be checked before the identifier fallback.
    // null/undefined/true/false are typed to match defaultType so binary ops don't produce
    // a type mismatch (e.g. f64.eq with an i32 rhs).
    if (expr === "NaN") return "(f64.const nan)";
    if (expr === "Infinity") return "(f64.const inf)";

    // isNaN(x) → f64.ne x x (NaN is the only value not equal to itself)
    {
      const isNaNM = expr.match(/^isNaN\s*\((.+)\)$/);
      if (isNaNM && parenDepthNeverNegative(isNaNM[1])) {
        const argWat = this.emitExpr(isNaNM[1].trim(), locals, "f64");
        return `(f64.ne ${argWat} ${argWat})`;
      }
    }
    {
      const numType = (defaultType === "f64" || defaultType === "f32") ? defaultType : "i32";
      if (expr === "true") return `(${numType}.const 1)`;
      if (expr === "false") return `(${numType}.const 0)`;
      if (expr === "null") return `(${numType}.const 0)`;
      if (expr === "undefined") return `(${numType}.const 0)`;
    }

    // Identifier (local variable or parameter)
    if (/^\w+$/.test(expr)) {
      // Mutable closure capture — load through $__closure_ptr (checked before locals, since mutable
      // captures are NOT in locals — they're accessed via the closure pointer).
      {
        const ccl = this.currentClosureCaptureLayout.get(expr);
        if (ccl) {
          const loadOp = ccl.type === "f64"
            ? "f64.load"
            : ccl.type === "i64"
            ? "i64.load"
            : "i32.load";
          const rawLoad = `(${loadOp} offset=${ccl.offset} (local.get $__closure_ptr))`;
          if (ccl.type === "f64" && defaultType === "i32") return `(i32.trunc_f64_s ${rawLoad})`;
          if (
            (ccl.type === "i32" || ccl.type === "bool") &&
            (defaultType === "f64" || defaultType === "f32")
          ) return `(f64.convert_i32_s ${rawLoad})`;
          return rawLoad;
        }
      }
      // Use per-function locals map for accurate type — stringVars is instance-level and
      // could contain names from other functions compiled earlier in the same pass.
      const localType = locals.get(expr);
      if (localType === "string") {
        // In boolean (i32) context: string truthiness = length > 0 (empty string is falsy)
        if (defaultType === "i32") return `(i32.gt_s (local.get $${expr}_len) (i32.const 0))`;
        // In other numeric contexts: yield the ptr (i32) for use in expressions
        return `(local.get $${expr}_ptr)`;
      }
      if (localType) {
        // Phase 5h: boxed capture — load through heap pointer
        if (this.currentBoxedCaptures.has(expr)) return `(i32.load (local.get $${expr}))`;
        const rawGet = `(local.get $${expr})`;
        // Type coercion for context mismatch (e.g. f64 variable used in i32 context or vice versa)
        if (localType === "f64" && defaultType === "i32") return `(i32.trunc_f64_s ${rawGet})`;
        if (
          (localType === "i32" || localType === "bool") &&
          (defaultType === "f64" || defaultType === "f32")
        ) return `(f64.convert_i32_s ${rawGet})`;
        return rawGet;
      }
      // Module-level string const — returns ptr in i32 context
      if (this.moduleStringConsts.has(expr)) {
        const [offset] = this.moduleStringConsts.get(expr)!;
        return `(i32.const ${offset})`;
      }
      // Module global — emit global.get
      const globalInfo = this.moduleGlobals.get(expr);
      if (globalInfo) return `(global.get $${expr})`;
      // Known function name used as a value → funcref table index
      if (this.functions.find((f) => f.name === expr)) {
        return `(i32.const ${this.getFuncTableIdx(expr)})`;
      }
    }

    // Chained `new ClassName(ctorArgs).method(methodArgs)` — construct a fresh instance, then call a
    // method on it. (Must precede the bare `new` handler, whose guard rejects this anyway.)
    {
      const ncHead = expr.match(/^new\s+([A-Z]\w*)\s*\(/);
      if (ncHead) {
        const openIdx = expr.indexOf("(", ncHead[0].length - 1);
        let d = 0;
        let ctorEnd = -1;
        for (let j = openIdx; j < expr.length; j++) {
          if (expr[j] === "(") d++;
          else if (expr[j] === ")" && --d === 0) {
            ctorEnd = j;
            break;
          }
        }
        const tail = ctorEnd !== -1 ? expr.slice(ctorEnd + 1).trim() : "";
        const methodM = tail.match(/^\.\s*(\w+)\s*\((.*)\)$/);
        const ncCd = this.classDefs.get(ncHead[1]!);
        // Guard the greedy method-args capture so a compound expr like `new A(x).m() + new B(y).m()`
        // (where the capture would grab `) + new B(y).m(`) falls through to the binary-op loop.
        if (ctorEnd !== -1 && methodM && parenDepthNeverNegative(methodM[2]!) && ncCd) {
          const mFn = this.resolveMethodFunc(ncHead[1]!, methodM[1]!) ??
            `${ncHead[1]}_${methodM[1]}`;
          const mDef = this.functions.find((f) => f.name === mFn);
          const retType = (mDef?.result ?? "i32") as WatType | null;
          // String-returning chains use the globals side-channel — out of scope here.
          if (retType !== null && retType !== "string") {
            const ptr = this.allocStructData(ncCd.struct, {}, this.classTags.get(ncHead[1]!));
            const ctorName = `${ncHead[1]}_constructor`;
            const ctorFn = this.functions.find((f) => f.name === ctorName);
            const ctorArgs = expr.slice(openIdx + 1, ctorEnd).trim();
            const ctorEmitted = (ctorArgs ? this.splitArgs(ctorArgs) : []).map((a, i) =>
              this.emitExpr(a, locals, ctorFn?.params[i + 1]?.type ?? ("i32" as WatType))
            );
            const ctorCall = ctorFn
              ? `(call $${ctorName} (i32.const ${ptr}) ${ctorEmitted.join(" ")})`.trim()
              : "";
            const mArgs = methodM[2]!.trim();
            const mEmitted = (mArgs ? this.splitArgs(mArgs) : []).map((a, i) =>
              this.emitExpr(a, locals, mDef?.params[i + 1]?.type ?? ("i32" as WatType))
            );
            const mCall = `(call $${mFn} (i32.const ${ptr}) ${mEmitted.join(" ")})`.trim();
            return `(block (result ${watBaseType(retType)}) ${ctorCall} ${mCall})`;
          }
        }
      }
    }

    // new ClassName(args) — allocate static struct + call constructor.
    // Guard the greedy args capture so a compound expr like `new A(x) + new B(y)` (where the
    // capture would grab `x) + new B(y`) falls through to the binary-op loop instead of mis-parsing.
    const newMatch = expr.match(/^new\s+([A-Z]\w*)\s*\(([\s\S]*)\)$/);
    if (newMatch && parenDepthNeverNegative(newMatch[2])) {
      const ctorClassName = newMatch[1];
      const argsStr = newMatch[2].trim();
      const cd = this.classDefs.get(ctorClassName);
      if (cd) {
        const ptr = this.allocStructData(cd.struct, {}, this.classTags.get(ctorClassName));
        const constructorName = `${ctorClassName}_constructor`;
        const ctorFn = this.functions.find((f) => f.name === constructorName);
        if (ctorFn) {
          const args = argsStr ? this.splitArgs(argsStr) : [];
          const emittedArgs = args.flatMap((a, i) => {
            const pt = ctorFn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const ctorCall = `(call $${constructorName} (i32.const ${ptr}) ${emittedArgs.join(" ")})`
            .trim();
          return `(block (result i32) ${ctorCall} (i32.const ${ptr}))`;
        }
        return `(i32.const ${ptr})`;
      }
    }

    // Phase 47: super.method(args) in non-constructor method body (expression form)
    const superDotExprMatch = expr.match(/^super\.(\w+)\s*\((.*)\)$/);
    if (
      superDotExprMatch && parenDepthNeverNegative(superDotExprMatch[2]) && this.currentMethodClass
    ) {
      const sdMethod = superDotExprMatch[1];
      const sdArgsRaw = superDotExprMatch[2].trim();
      const sdParent = this.classInheritance.get(this.currentMethodClass);
      if (sdParent) {
        const sdFuncName = this.resolveMethodFunc(sdParent, sdMethod) ?? `${sdParent}_${sdMethod}`;
        const sdFn = this.functions.find((f) => f.name === sdFuncName);
        if (sdFn) {
          const sdArgs = sdArgsRaw ? this.splitArgs(sdArgsRaw) : [];
          const sdEmitted = sdArgs.map((a, i) =>
            this.emitExpr(a, locals, sdFn.params[i + 1]?.type ?? ("i32" as WatType))
          );
          return `(call $${sdFuncName} (local.get $__self) ${sdEmitted.join(" ")})`.trim();
        }
      }
    }

    // instance.method(args) or ClassName.staticMethod(args) dot-call in expression position.
    // Guard the greedy args capture so a compound expr like `a.unwrap() + b.unwrap()` (where the
    // capture would grab `) + b.unwrap(`) falls through to the binary-op loop instead of mis-parsing
    // into a broken call. (Previously, tests worked around this by hoisting `const av = a.unwrap()`.)
    const dotCallExprMatch = expr.match(/^(\w+)\.(\w+)\s*\(([\s\S]*)\)$/);
    if (dotCallExprMatch && parenDepthNeverNegative(dotCallExprMatch[3])) {
      const receiver = dotCallExprMatch[1];
      const methodName = dotCallExprMatch[2];
      const argsStr = dotCallExprMatch[3].trim();
      const args = argsStr ? this.splitArgs(argsStr) : [];

      // Instance method call
      const cv = this.classVars.get(receiver);
      if (cv) {
        // Phase 47: walk inheritance chain to find overriding or inherited method
        const funcName = this.resolveMethodFunc(cv.className, methodName) ??
          `${cv.className}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
        if (fn) {
          const baseWat = cv.ptr < 0 ? `(local.get $${receiver})` : `(i32.const ${cv.ptr})`;
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
        const method = staticCd.methods.find((mm) => mm.name === methodName && mm.isStatic);
        if (method) {
          const funcName = `${receiver}_${methodName}`;
          const fn = this.functions.find((f) => f.name === funcName);
          if (fn) {
            const emittedArgs = args.flatMap((a, i) => {
              const pt = fn.params[i]?.type ?? defaultType;
              return [this.emitExpr(a, locals, pt)];
            });
            return `(call $${funcName} ${emittedArgs.join(" ")})`.trim();
          }
        }
      }

      // Phase 12: interface method dispatch via closure trampoline
      const ifaceNameExpr = this.interfaceVars.get(receiver);
      if (ifaceNameExpr) {
        const structDefExpr = this.structDefs.get(ifaceNameExpr);
        const fieldExpr = structDefExpr?.fields.find((f) => f.name === methodName);
        if (fieldExpr?.funcType) {
          const closurePtrAddr = fieldExpr.offset === 0
            ? `(local.get $${receiver})`
            : `(i32.add (local.get $${receiver}) (i32.const ${fieldExpr.offset}))`;
          const loadClosure = `(i32.load ${closurePtrAddr})`;
          const trampolineParams: WatType[] = ["i32" as WatType, ...fieldExpr.funcType.params];
          const typeName = this.getOrCreateFuncType(trampolineParams, fieldExpr.funcType.result);
          const emittedArgs = args.map((a, idx) =>
            this.emitExpr(a, locals, fieldExpr.funcType!.params[idx] ?? "i32" as WatType)
          );
          return `(call_indirect (type ${typeName}) (local.tee $__iface_tmp ${loadClosure}) ${
            emittedArgs.join(" ")
          } (i32.load (local.get $__iface_tmp)))`.trim();
        }
      }

      // Phase 30: namespace function call — Namespace.func(args) → (call $Namespace_func args)
      if (this.namespaceDefs.has(receiver)) {
        const funcName = `${receiver}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
        if (fn) {
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i]?.type ?? defaultType;
            return [this.emitExpr(a, locals, pt)];
          });
          return `(call $${funcName} ${emittedArgs.join(" ")})`.trim();
        }
      }

      // Phase 40: external interface binding call in expression position
      if (this.externalBindings.has(receiver)) {
        const ifaceName = this.externalBindings.get(receiver)!;
        const iface = this.externalInterfaceTypes.get(ifaceName);
        const methodSig = iface?.get(methodName);
        if (methodSig) {
          const watFuncName = `$${receiver}_${methodName}`;
          this.usedExternalMethods.set(watFuncName, methodSig);
          const emittedArgs = args.map((a, i) =>
            this.emitExpr(a, locals, methodSig.params[i] ?? ("i32" as WatType))
          );
          return `(call ${watFuncName} ${emittedArgs.join(" ")})`.trim();
        }
      }
    }

    // Spread call: foo(...arr) — passes arr pointer directly to rest-param function
    // Handles the case where the entire argument list is a single spread of an array variable.
    const spreadCallMatch = expr.match(/^(\w+)\s*\(\s*\.\.\.(\w+)\s*\)$/);
    if (spreadCallMatch) {
      const fnName = spreadCallMatch[1];
      const arrName = spreadCallMatch[2];
      const fn = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fn?.params[fn.params.length - 1];
      if (fn && lastParam?.isRest) {
        // Pass all normal args (none expected in pure spread call) then the array ptr
        const normalCount = fn.params.length - 1;
        const normalEmitted = fn.params.slice(0, normalCount).map((p: FuncParam) =>
          p.defaultValue !== undefined
            ? this.emitExpr(p.defaultValue, locals, p.type)
            : `(i32.const 0)`
        );
        const arrGet4 = this.moduleGlobals.has(arrName)
          ? `(global.get $${arrName})`
          : `(local.get $${arrName})`;
        return `(call $${fnName} ${[...normalEmitted, arrGet4].join(" ")})`.trim();
      }
    }

    // Phase 5f: chained call — factoryFn(outerArgs)(innerArgs) closure factory invocation
    {
      const chainHead = expr.match(/^(\w+)\s*\(/)?.[1];
      if (chainHead) {
        const factoryFn = this.functions.find((f) => f.name === chainHead && f.isClosureFactory);
        if (factoryFn?.returnedArrow) {
          const openParen1 = expr.indexOf("(");
          const [rawOuterArgs, afterOuter] = WasicTranspiler.extractParamBlock(expr, openParen1);
          const rest = expr.slice(afterOuter).trimStart();
          if (rest.startsWith("(")) {
            const [rawInnerArgs] = WasicTranspiler.extractParamBlock(rest, 0);
            const inner = factoryFn.returnedArrow;
            const innerCallParams = inner.params.filter((p) =>
              !(inner.closureCaptures ?? []).includes(p.name)
            );
            const outerArgs = rawOuterArgs.trim() ? this.splitArgs(rawOuterArgs) : [];
            const outerEmitted = outerArgs.map((a, i) =>
              this.emitExpr(a, locals, factoryFn.params[i]?.type ?? "i32")
            );
            const innerArgs = rawInnerArgs.trim() ? this.splitArgs(rawInnerArgs) : [];
            const innerEmitted = innerArgs.map((a, i) =>
              this.emitExpr(a, locals, innerCallParams[i]?.type ?? "i32")
            );
            return `(call $${chainHead}__trampoline (call $${chainHead} ${
              outerEmitted.join(" ")
            }) ${innerEmitted.join(" ")})`.trim();
          }
        }
      }
    }

    // Phase 5h: chained method call on factory return — factory(args).method(args)
    // e.g. createCounter().inc(), createSecureMatrix().getRow(0)
    {
      const chainHead5h = expr.match(/^(\w+)\s*\(/)?.[1];
      if (chainHead5h) {
        const factoryFn5h = this.functions.find((f) => f.name === chainHead5h && f.resultTsName);
        if (factoryFn5h?.resultTsName) {
          const openParen5h = expr.indexOf("(");
          const [rawFactoryArgs5h, afterFactory5h] = WasicTranspiler.extractParamBlock(
            expr,
            openParen5h,
          );
          const rest5h = expr.slice(afterFactory5h).trimStart();
          const methodMatch5h = rest5h.match(/^\.(\w+)\s*\((.*?)?\)\s*$/);
          if (methodMatch5h) {
            const methodName5h = methodMatch5h[1];
            const rawMethodArgs5h = methodMatch5h[2] ?? "";
            const structDef5h = this.structDefs.get(factoryFn5h.resultTsName);
            const field5h = structDef5h?.fields.find((f) => f.name === methodName5h);
            if (field5h?.funcType) {
              const emittedFactoryArgs = rawFactoryArgs5h.trim()
                ? this.splitArgs(rawFactoryArgs5h).map((a, i) =>
                  this.emitExpr(a, locals, factoryFn5h.params[i]?.type ?? "i32")
                )
                : [];
              const factoryCallWat = `(call $${chainHead5h} ${emittedFactoryArgs.join(" ")})`
                .trim();
              const loadClosure = field5h.offset === 0
                ? `(i32.load ${factoryCallWat})`
                : `(i32.load (i32.add (local.tee $__iface_tmp ${factoryCallWat}) (i32.const ${field5h.offset})))`;
              const trampolineParams5h: WatType[] = ["i32" as WatType, ...field5h.funcType.params];
              const typeName5h = this.getOrCreateFuncType(
                trampolineParams5h,
                field5h.funcType.result,
              );
              const emittedMethodArgs = rawMethodArgs5h.trim()
                ? this.splitArgs(rawMethodArgs5h).map((a, idx) =>
                  this.emitExpr(a, locals, field5h.funcType!.params[idx] ?? "i32" as WatType)
                )
                : [];
              return `(call_indirect (type ${typeName5h}) (local.tee $__iface_tmp ${loadClosure}) ${
                emittedMethodArgs.join(" ")
              } (i32.load (local.get $__iface_tmp)))`.trim();
            }
          }
        }
      }
    }

    // Function call: name(arg1, arg2, ...)
    const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
    if (callMatch && parenDepthNeverNegative(callMatch[2]?.trim() ?? "")) {
      const callee = callMatch[1];
      const rawArgs = callMatch[2]?.trim() ?? "";
      const args = rawArgs ? this.splitArgs(rawArgs) : [];

      // Built-in predicates
      if (callee === "isNaN") {
        const arg = args[0] ?? "0";
        const xWat = this.emitExpr(arg, locals, "f64");
        return `(f64.ne ${xWat} ${xWat})`;
      }
      if (callee === "isFinite") {
        const arg = args[0] ?? "0";
        const xWat = this.emitExpr(arg, locals, "f64");
        return `(f64.eq (f64.sub ${xWat} ${xWat}) (f64.const 0))`;
      }

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

      const fn = this.functions.find((f) => f.name === callee);
      if (!fn) {
        // Phase 5g: closure pointer dispatch — call via trampoline stored in the struct
        if (this.closureTypedVars.has(callee)) {
          const sig = this.closureTypedVars.get(callee)!;
          const trampolineParamTypes: WatType[] = ["i32" as WatType, ...sig.params as WatType[]];
          // String-returning closures are void WAT functions; use null so functype matches the void trampoline.
          const trampolineResult = sig.result === "string" ? null : sig.result;
          const trampolineTypeName = this.getOrCreateFuncType(
            trampolineParamTypes,
            trampolineResult,
          );
          const emittedArgs = args.map((a, idx) =>
            this.emitExpr(a, locals, sig.params[idx] ?? defaultType)
          );
          return `(call_indirect (type ${trampolineTypeName}) (local.get $${callee}) ${
            emittedArgs.join(" ")
          } (i32.load (local.get $${callee})))`.trim();
        }
        if (this.funcTypeVars.has(callee)) {
          const sig = this.funcTypeVars.get(callee)!;
          const typeName = this.getOrCreateFuncType(sig.params, sig.result);
          const emittedArgs = args.flatMap((a, idx) => {
            const pt = sig.params[idx] ?? defaultType;
            if (pt === "string") return [this.emitStringPtrLen(a, locals)];
            return [this.emitExpr(a, locals, pt)];
          });
          return `(call_indirect (type ${typeName}) ${
            emittedArgs.join(" ")
          } (local.get $${callee}))`.trim();
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
        // Inline struct literal argument: { key: val, ... } for a struct param
        if (paramType === "i32" && a.startsWith("{") && fn.params[i]?.structType) {
          const structName = fn.params[i].structType!;
          const structDef = this.structDefs.get(structName);
          if (structDef) {
            const braceContent = a.slice(1, a.lastIndexOf("}")).trim();
            const initFields: Record<string, string> = {};
            const pairs = splitBraceAwareCommas(braceContent);
            for (const pair of pairs) {
              const ci = pair.indexOf(":");
              const key = ci !== -1 ? pair.slice(0, ci).trim() : pair.trim();
              const val = ci !== -1 ? pair.slice(ci + 1).trim() : key;
              if (key) initFields[key] = val;
            }
            const ptr = this.allocStructData(structDef, initFields);
            return [`(i32.const ${ptr})`];
          }
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
      const rest = expr.slice(ternQ + 1);
      const ternC = this.findBinaryOp(rest, ":");
      if (ternC !== -1) {
        const cond = expr.slice(0, ternQ).trim();
        const thenPart = rest.slice(0, ternC).trim();
        const elsePart = rest.slice(ternC + 1).trim();
        return `(if (result ${defaultType}) ${this.emitExpr(cond, locals, "i32")} (then ${
          this.emitExpr(thenPart, locals, defaultType)
        }) (else ${this.emitExpr(elsePart, locals, defaultType)}))`;
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
      const inner = expr.slice(1).trim();
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
        return `(call $__math_pow ${this.emitExpr(lhs, locals, "f64")} ${
          this.emitExpr(rhs, locals, "f64")
        })`;
      }
    }

    // Phase 25: Nullish coalescing ?? — only short-circuits on null/undefined.
    // Handled before the binaryOps table because its WAT shape differs (if/result).
    {
      const qqIdx = this.findBinaryOp(expr, "??");
      if (qqIdx !== -1) {
        const lhsQQ = expr.slice(0, qqIdx).trim();
        const rhsQQ = expr.slice(qqIdx + 2).trim();
        const qqInner = this.nullableVarInnerType.get(lhsQQ);
        if (qqInner && watBaseType(qqInner) !== undefined) {
          const bt = watBaseType(qqInner);
          const rhsWat = this.emitExpr(rhsQQ, locals, qqInner);
          const lhsWat = this.emitExpr(lhsQQ, locals, qqInner);
          // $lhsQQ__null is 1 when lhs is null → (then rhs) fires when null
          return `(if (result ${bt}) (local.get $${lhsQQ}__null) (then ${rhsWat}) (else ${lhsWat}))`;
        }
        // Pointer/string type: check for null pointer (0).
        // Only applies when lhsQQ is a simple identifier — complex expressions (array
        // access, method calls) evaluate to numeric types that can't be null in WASM,
        // so just emit the LHS directly (the ?? can never trigger).
        const ctxBt = watBaseType(defaultType === "never" ? "i32" : defaultType as WatType);
        const lhsWatP = this.emitExpr(lhsQQ, locals, defaultType);
        if (!/^\w+$/.test(lhsQQ)) {
          // Complex LHS expression: not nullable in WASM, ignore RHS
          return lhsWatP;
        }
        const rhsWatP = this.emitExpr(rhsQQ, locals, defaultType);
        const ptrLocal = locals.get(lhsQQ) === "string" ? `${lhsQQ}_ptr` : lhsQQ;
        const nullCkP = `(i32.eqz (local.get $${ptrLocal}))`;
        return `(if (result ${ctxBt}) ${nullCkP} (then ${rhsWatP}) (else ${lhsWatP}))`;
      }
    }

    // Phase 35: typeof x === "typename" | "typename" === typeof x → compile-time boolean constant.
    // Evaluated entirely at compile time from the variable's known WAT type.
    {
      const typeofCmpRe =
        /^typeof\s+(\w+)\s*(===|!==|==|!=)\s*["'](\w+)["']$|^["'](\w+)["']\s*(===|!==|==|!=)\s*typeof\s+(\w+)$/;
      const tcm = expr.match(typeofCmpRe);
      if (tcm) {
        const varN = (tcm[1] ?? tcm[6])!;
        const op = (tcm[2] ?? tcm[5])!;
        const typeName = (tcm[3] ?? tcm[4])!;
        const actual = this.resolveTypeofString(varN, locals);
        const matches = actual === typeName;
        const result = (op === "!=" || op === "!==") ? !matches : matches;
        return `(i32.const ${result ? 1 : 0})`;
      }
    }

    // Phase 35: standalone typeof x → i32 ptr to static type name string (for use in i32 expression contexts)
    {
      const typeofExpr = expr.match(/^typeof\s+(\w+)$/);
      if (typeofExpr) {
        const typeStr = this.resolveTypeofString(typeofExpr[1]!, locals);
        const [ptr] = this.allocString(typeStr);
        return `(i32.const ${ptr})`;
      }
    }

    // Phase 32: discriminated union discriminant comparison: varName.disc === "lit" or "lit" === varName.disc
    {
      const duCmpRe =
        /^(\w+)\.(\w+)\s*(===|!==|==|!=)\s*["']([^"']+)["']$|^["']([^"']+)["']\s*(===|!==|==|!=)\s*(\w+)\.(\w+)$/;
      const dcm = expr.match(duCmpRe);
      if (dcm) {
        // Groups: lhs form → [1]=varN [2]=fieldN [3]=op [4]=lit ; rhs form → [5]=lit [6]=op [7]=varN [8]=fieldN
        const varN = dcm[1] ?? dcm[7];
        const fieldN = dcm[2] ?? dcm[8];
        const op = dcm[3] ?? dcm[6];
        const lit = dcm[4] ?? dcm[5];
        const sv = this.structVars.get(varN!);
        if (sv) {
          const du = this.discUnionDefs.get(sv.def.name);
          if (du && du.discriminant === fieldN) {
            const tagIdx = du.variants.find((v) => v.tag === lit)?.tagIndex ?? -1;
            const baseWat = sv.ptr < 0 ? `(local.get $${varN})` : `(i32.const ${sv.ptr})`;
            const loadWat = `(i32.load ${baseWat})`;
            const eqOp = (op === "!=" || op === "!==") ? "i32.ne" : "i32.eq";
            return `(${eqOp} ${loadWat} (i32.const ${tagIdx}))`;
          }
        }
      }
    }

    // Binary operators — scanned in ascending-precedence order so the lowest-precedence
    // operator is matched first, producing correctly-grouped s-expressions.
    // [op, i32-suffix, f64-suffix, alwaysI32]
    const binaryOps: [string, string, string, boolean][] = [
      ["||", "or", "or", true], // logical OR   → i32.or
      ["&&", "and", "and", true], // logical AND  → i32.and
      ["|", "or", "or", true], // bitwise OR
      ["^", "xor", "xor", true], // bitwise XOR
      ["&", "and", "and", true], // bitwise AND
      ["===", "eq", "eq", false],
      ["!==", "ne", "ne", false],
      ["==", "eq", "eq", false], // non-strict equality (same as === for numerics)
      ["!=", "ne", "ne", false], // non-strict inequality
      ["<=", "le_s", "le", false],
      [">=", "ge_s", "ge", false],
      ["<", "lt_s", "lt", false],
      [">", "gt_s", "gt", false],
      [">>>", "shr_u", "shr_u", true], // unsigned right shift
      [">>", "shr_s", "shr_s", true], // signed right shift
      ["<<", "shl", "shl", true], // left shift
      ["+", "add", "add", false],
      ["-", "sub", "sub", false],
      ["*", "mul", "mul", false],
      ["/", "div_s", "div", false],
      ["%", "rem_s", "rem", false],
    ];

    const STRING_CMP_OPS = new Set(["===", "!==", "==", "!=", "<", ">", "<=", ">="]);
    for (const [op, i32suf, f64suf, alwaysI32] of binaryOps) {
      const idx = this.findBinaryOp(expr, op);
      if (idx !== -1) {
        const lhs = expr.slice(0, idx).trim();
        const rhs = expr.slice(idx + op.length).trim();

        // Logical && / || — emit SHORT-CIRCUIT form (an if/result that skips the RHS when the
        // LHS already decides the result) instead of a bitwise (i32.and/or) that always
        // evaluates both sides. This matches JavaScript semantics and, critically, prevents an
        // RHS with a guarded side effect (e.g. `i < len && s.charCodeAt(i) === c`) from
        // evaluating an out-of-bounds access when the LHS is false. The old non-short-circuit
        // form also mis-encoded under wasmmerge splice (a `call` nested in an `i32.and` inside a
        // loop `br_if` trapped after reassembly); short-circuiting removes that whole class.
        if (op === "&&" || op === "||") {
          const lWat = this.emitExpr(lhs, locals, "i32");
          const rWat = this.emitExpr(rhs, locals, "i32");
          const scWat = op === "&&"
            ? `(if (result i32) ${lWat} (then ${rWat}) (else (i32.const 0)))`
            : `(if (result i32) ${lWat} (then (i32.const 1)) (else ${rWat}))`;
          // Result is i32 0/1; promote if the surrounding context expects a wider type.
          const ctxBase = watBaseType(defaultType as WatType);
          if (ctxBase === "f64") return `(f64.convert_i32_s ${scWat})`;
          if (ctxBase === "i64") return `(i64.extend_i32_s ${scWat})`;
          return scWat;
        }

        // Phase 24: null/undefined comparison — intercept before the regular type dispatch.
        if (
          (op === "===" || op === "!==" || op === "==" || op === "!=") &&
          (rhs === "null" || rhs === "undefined" || lhs === "null" || lhs === "undefined")
        ) {
          const varName = (rhs === "null" || rhs === "undefined") ? lhs : rhs;
          const nlInner = this.nullableVarInnerType.get(varName);
          if (nlInner) {
            // Value type with __null flag: 1=is-null
            const nullFlag = `(local.get $${varName}__null)`;
            return (op === "===" || op === "==") ? nullFlag : `(i32.eqz ${nullFlag})`;
          }
          // String type: check ptr == 0
          if (locals.get(varName) === "string") {
            const ptrCk = `(i32.eqz (local.get $${varName}_ptr))`;
            return (op === "===" || op === "==")
              ? ptrCk
              : `(i32.ne (local.get $${varName}_ptr) (i32.const 0))`;
          }
          // Pointer types (i32): fall through to normal i32.eq/ne which compares with 0
        }

        // For logical/bitwise ops always use i32; for others infer from the LHS local type.
        // Also peek at the leading identifier for simple compound expressions like "n % 2"
        // (but NOT for dot-access expressions like "r.width" — the leading "r" would give wrong type).
        // str.slice(...) on a string local → string type (used in string comparisons)
        const _lhsSliceRecv = lhs.match(/^(\w+)\.slice\s*\(/)?.[1];
        const _lhsIsStrSlice = _lhsSliceRecv !== undefined &&
          locals.get(_lhsSliceRecv) === "string";
        const _lhsLeadId = !lhs.includes(".") ? lhs.match(/^(\w+)/)?.[1] : undefined;
        // For function calls, extract the leading function name even when args contain dots.
        // E.g. "intMin(tests[i].a, tests[i].b)" → _lhsFnName = "intMin" → result type f64
        const _lhsFnName = lhs.match(/^(\w+)\s*\(/)?.[1];
        const _lhsFnResult = _lhsFnName
          ? this.functions.find((f) => f.name === _lhsFnName)?.result ?? null
          : null;
        // Struct/class field access: varName.field or arr[idx].field → look up field type
        const _dotFieldLhsM = !alwaysI32 && lhs.includes(".")
          ? lhs.match(/^(\w+)(?:\[([^\]]+)\])?\.(\w+)$/)
          : null;
        const _dotFieldType: WatType | null = _dotFieldLhsM
          ? (() => {
            if (_dotFieldLhsM[2] !== undefined) {
              // arr[idx].field: look up struct array field type
              const arrI = this.arrayVars.get(_dotFieldLhsM[1]);
              const stn = arrI?.structTypeName ??
                (arrI && arrI.elemType !== "f64" && arrI.elemType !== "i32" &&
                    arrI.elemType !== "i64"
                  ? arrI.elemType
                  : undefined);
              const field = stn
                ? this.structDefs.get(stn)?.fields.find((f) => f.name === _dotFieldLhsM[3])
                : undefined;
              return (field?.type as WatType) ?? null;
            }
            // varName.field: struct var or class var field
            const sv = this.structVars.get(_dotFieldLhsM[1]);
            if (sv) {
              const field = sv.def.fields.find((f) => f.name === _dotFieldLhsM[3]);
              if (field) return field.type as WatType;
            }
            const cv = this.classVars.get(_dotFieldLhsM[1]);
            if (cv) {
              const cd = this.classDefs.get(cv.className);
              const field = cd?.struct.fields.find((f) => f.name === _dotFieldLhsM[3]);
              if (field) return field.type as WatType;
            }
            return null;
          })()
          : null;
        const lhsType: WatType = alwaysI32 ? "i32" : (_lhsIsStrSlice ? "string" : (_dotFieldType ??
          (/^\w+$/.test(lhs) && locals.has(lhs)
            ? locals.get(lhs)!
            : /^\w+$/.test(lhs) && this.moduleGlobals.has(lhs)
            ? this.moduleGlobals.get(lhs)!.type
            // Array element access arr[idx]: use element type, not pointer type
            : _lhsLeadId && lhs.includes("[") && this.arrayVars.has(_lhsLeadId)
            ? (this.arrayVars.get(_lhsLeadId)!.isStringArr ||
                this.arrayVars.get(_lhsLeadId)!.elemType === "string"
              ? "string"
              : this.arrayVars.get(_lhsLeadId)!.elemType)
            // Fix 5: closure-typed variable call (e.g. r1()) → use the closure's return type, not the i32 pointer type
            : _lhsFnName && this.closureTypedVars.has(_lhsFnName)
            ? (this.closureTypedVars.get(_lhsFnName)!.result ?? "f64") as WatType
            : _lhsLeadId && locals.has(_lhsLeadId)
            ? locals.get(_lhsLeadId)!
            : _lhsLeadId && this.moduleGlobals.has(_lhsLeadId)
            ? this.moduleGlobals.get(_lhsLeadId)!.type
            : _lhsFnResult ?? defaultType)));

        // String comparison: route through $__str_cmp instead of string.eq / string.lt, etc.
        if (lhsType === "string" && STRING_CMP_OPS.has(op)) {
          // Special case: str[idx] === "c" (single-char literal) → charCodeAt comparison
          const lhsSubM = lhs.match(/^(\w+)\[([^\]]+)\]$/);
          const rhsLit1 = rhs.match(/^["'](.*)["']$/);
          const lhsLit1 = lhs.match(/^["'](.*)["']$/);
          const rhsSubM = rhs.match(/^(\w+)\[([^\]]+)\]$/);
          if (
            lhsSubM && locals.get(lhsSubM[1]) === "string" && rhsLit1 && rhsLit1[1].length === 1
          ) {
            this.needsStringExtHelpers = true;
            const charCode = rhsLit1[1].charCodeAt(0);
            const idxWat = this.emitExpr(lhsSubM[2].trim(), locals, "i32");
            const codeWat = `(call $__str_char_code_at (local.get $${lhsSubM[1]}_ptr) (local.get $${
              lhsSubM[1]
            }_len) ${idxWat})`;
            const eqOp = (op === "===" || op === "==") ? "eq" : "ne";
            if (op === "===" || op === "==" || op === "!==" || op === "!=") {
              return `(i32.${eqOp} ${codeWat} (i32.const ${charCode}))`;
            }
          }
          if (
            rhsSubM && locals.get(rhsSubM[1]) === "string" && lhsLit1 && lhsLit1[1].length === 1
          ) {
            this.needsStringExtHelpers = true;
            const charCode = lhsLit1[1].charCodeAt(0);
            const idxWat = this.emitExpr(rhsSubM[2].trim(), locals, "i32");
            const codeWat = `(call $__str_char_code_at (local.get $${rhsSubM[1]}_ptr) (local.get $${
              rhsSubM[1]
            }_len) ${idxWat})`;
            const eqOp = (op === "===" || op === "==") ? "eq" : "ne";
            if (op === "===" || op === "==" || op === "!==" || op === "!=") {
              return `(i32.${eqOp} ${codeWat} (i32.const ${charCode}))`;
            }
          }
          this.needsStringHelpers = true;
          const aWat = this.emitStringPtrLen(lhs, locals);
          const bWat = this.emitStringPtrLen(rhs, locals);
          const cmpCall = `(call $__str_cmp ${aWat} ${bWat})`;
          const STR_CMP: Record<string, string> = {
            "===": `(i32.eqz ${cmpCall})`,
            "==": `(i32.eqz ${cmpCall})`,
            "!==": `(i32.ne ${cmpCall} (i32.const 0))`,
            "!=": `(i32.ne ${cmpCall} (i32.const 0))`,
            "<": `(i32.lt_s ${cmpCall} (i32.const 0))`,
            ">": `(i32.gt_s ${cmpCall} (i32.const 0))`,
            "<=": `(i32.le_s ${cmpCall} (i32.const 0))`,
            ">=": `(i32.ge_s ${cmpCall} (i32.const 0))`,
          };
          return STR_CMP[op] ?? `(i32.eqz ${cmpCall})`;
        }

        const baseType = watBaseType(lhsType);
        const isFloat = baseType === "f64" || baseType === "f32";
        const suffix = isFloat ? f64suf : i32suf;
        // f64.rem does not exist in WebAssembly; use x - trunc(x/y)*y formula instead.
        if (op === "%" && isFloat) {
          const lWat = this.emitExpr(lhs, locals, lhsType);
          const rWat = this.emitExpr(rhs, locals, lhsType);
          const innerWat =
            `(${baseType}.sub ${lWat} (${baseType}.mul (${baseType}.trunc (${baseType}.div ${lWat} ${rWat})) ${rWat}))`;
          return innerWat;
        }
        const watOp = `${baseType}.${suffix}`;
        const innerWat = `(${watOp} ${this.emitExpr(lhs, locals, lhsType)} ${
          this.emitExpr(rhs, locals, lhsType)
        })`;
        // Mixed-type promotion: if context needs f64/i64 but arithmetic ran in i32, convert.
        // Also applies to alwaysI32 ops (|, ^, &, >>>, etc.) when stored in a f64 variable.
        if (baseType === "i32") {
          const ctxBase = watBaseType(defaultType as WatType);
          // >>> produces an unsigned i32 — use unsigned-to-f64 conversion for correct [0,1) range.
          if (ctxBase === "f64") {
            return op === ">>>"
              ? `(f64.convert_i32_u ${innerWat})`
              : `(f64.convert_i32_s ${innerWat})`;
          }
          if (ctxBase === "i64") return `(i64.extend_i32_s ${innerWat})`;
        }
        // Fix 3: if f64 arithmetic was selected (lhsType=f64) but caller needs i32, truncate.
        // Do NOT apply for comparison ops — f64 comparisons (lt/gt/le/ge/eq/ne) already return i32.
        if (
          (baseType === "f64" || baseType === "f32") &&
          watBaseType(defaultType as WatType) === "i32" &&
          !STRING_CMP_OPS.has(op)
        ) {
          return `(i32.trunc_f64_s ${innerWat})`;
        }
        return innerWat;
      }
    }

    // Phase 51: instanceof — class membership test.
    // Placed AFTER the binary-op loop so a compound like `a instanceof X && b instanceof Y`
    // is split on `&&` first; each `a instanceof X` operand (no binary op of its own) then
    // reaches here. When the module has class inheritance (a 4-byte tag header at offset 0)
    // we emit a runtime tag check: tag(obj) ∈ { tags of the target class and all its
    // subclasses }. With no inheritance there is no tag, so the test is resolved at compile
    // time from the variable's statically-tracked class.
    {
      const instM = expr.match(/^(.+?)\s+instanceof\s+(\w+)$/);
      if (instM && this.classDefs.has(instM[2]!)) {
        const lhsExpr = instM[1]!.trim();
        const targetCls = instM[2]!;
        const cvLhs = this.classVars.get(lhsExpr);
        let objWat: string;
        let trackedClass: string | undefined;
        if (lhsExpr === "this" && this.currentMethodClass) {
          objWat = "(local.get $__self)";
          trackedClass = this.currentMethodClass;
        } else if (cvLhs) {
          objWat = cvLhs.ptr === -1 ? `(local.get $${lhsExpr})` : `(i32.const ${cvLhs.ptr})`;
          trackedClass = cvLhs.className;
        } else {
          objWat = this.emitExpr(lhsExpr, locals, "i32");
          trackedClass = undefined;
        }
        let resWat: string;
        if (this.classHeaderSize > 0) {
          const tags = this.findSubclasses(targetCls)
            .map((s) => this.classTags.get(s))
            .filter((t): t is number => t !== undefined);
          if (tags.length === 0) {
            resWat = "(i32.const 0)";
          } else {
            resWat = `(i32.eq (i32.load ${objWat}) (i32.const ${tags[0]}))`;
            for (let k = 1; k < tags.length; k++) {
              resWat = `(i32.or ${resWat} (i32.eq (i32.load ${objWat}) (i32.const ${tags[k]})))`;
            }
          }
        } else {
          const isInstance = trackedClass !== undefined &&
            this.findSubclasses(targetCls).includes(trackedClass);
          resWat = `(i32.const ${isInstance ? 1 : 0})`;
        }
        const ctxBase = watBaseType(defaultType as WatType);
        if (ctxBase === "f64") return `(f64.convert_i32_s ${resWat})`;
        if (ctxBase === "i64") return `(i64.extend_i32_s ${resWat})`;
        return resWat;
      }
    }

    // instanceof with a NON-user-class (a built-in like Error / TypeError). wasic models caught
    // exceptions as plain strings, so the idiomatic `e instanceof Error` (narrow a catch variable
    // before reading `.message`) is treated as TRUE for the Error family; other unmodelled built-ins
    // resolve to FALSE. Resolved at compile time. (Mirrors the `instanceof Error ? …` ternary path.)
    {
      const instBM = expr.match(/^(.+?)\s+instanceof\s+(\w+)$/);
      if (instBM && !this.classDefs.has(instBM[2]!)) {
        const ERR_FAMILY = new Set([
          "Error",
          "TypeError",
          "RangeError",
          "SyntaxError",
          "EvalError",
          "ReferenceError",
          "URIError",
          "AggregateError",
        ]);
        const resWat = `(i32.const ${ERR_FAMILY.has(instBM[2]!) ? 1 : 0})`;
        const ctxBase = watBaseType(defaultType as WatType);
        if (ctxBase === "f64") return `(f64.convert_i32_s ${resWat})`;
        if (ctxBase === "i64") return `(i64.extend_i32_s ${resWat})`;
        return resWat;
      }
    }

    // Inline arrow literal still present — liftInlineArrows() couldn't lift it
    if (expr.includes("=>")) {
      this.diagnostics.push(
        `Unsupported: inline arrow could not be lifted as funcref: ${expr.slice(0, 40)}`,
      );
      return zeroOf(defaultType);
    }

    // Fallback: emit a comment and a zero so compilation succeeds.
    // Escape (;  and ;) inside expr to avoid malformed WAT nested block comments.
    // Also add a trailing space so a bare ( at the end of expr can't merge with ;) to form (;.
    // Record a diagnostic so an unhandled expression aborts the compile instead of silently
    // evaluating to 0 — UNLESS we're inside a speculative/guarded probe (see emitDiagSuppressDepth).
    if (this.emitDiagSuppressDepth === 0) {
      this.diagnostics.push(`Unsupported expression: ${expr.slice(0, 80)}`);
    }
    const safeExpr = expr.replace(/\(;/g, "( ;").replace(/;\)/g, "; )") + " ";
    return `(;? ${safeExpr};) ${zeroOf(defaultType)}`;
  }

  /** Finds an operator in an expression while respecting paren nesting.
   *  Scans right-to-left so repeated left-associative operators (a-b-c) group correctly. */
  private findBinaryOp(expr: string, op: string): number {
    let depth = 0;
    // Scan the FULL string from the end for depth, but only test for an op match at valid
    // op-start positions (i <= maxStart). Starting the loop at maxStart — as this used to —
    // skips the last op.length-1 characters for depth accounting, so a trailing `)` (e.g. a
    // RHS ending in a call like `x !== f(i)`) was never counted, driving depth negative and
    // hiding the operator. Brackets are counted too (matching findDepth0LTR/findDepth0Keyword)
    // so an operator inside `arr[i+1]` is correctly treated as nested, not top-level.
    //
    // Positions inside string / template literals are MASKED so brackets, parens, and operators
    // within a literal don't corrupt depth or match as operators — e.g. `s + "]"` must still find
    // the top-level `+` even though the literal contains `]`. Without this, any string concat whose
    // literal contained `]` `)` `}` `[` `(` `{` silently failed to parse and produced an empty string.
    const inStr = buildStringLiteralMask(expr);
    const maxStart = expr.length - op.length;
    for (let i = expr.length - 1; i >= 0; i--) {
      if (inStr[i]) continue;
      const ch = expr[i];
      if (ch === ")" || ch === "]") {
        depth++;
        continue;
      }
      if (ch === "(" || ch === "[") {
        depth--;
        continue;
      }
      if (depth === 0 && i <= maxStart && expr.slice(i, i + op.length) === op) {
        const after = expr[i + op.length] ?? "";
        const before = i > 0 ? expr[i - 1] : "";
        // Guard: don't match a short op that is a prefix/suffix of a longer one
        if (op === "<" && (after === "=" || after === "<" || before === "<")) continue;
        if (op === ">" && (after === "=" || after === ">" || before === ">" || before === "=")) {
          continue; // skip >=, >>, =>
        }
        if (op === "=" && after === "=") continue;
        if (op === "!" && after === "=") continue;
        if (op === "==" && (after === "=" || before === "=")) continue; // avoid === match
        if (op === "!=" && after === "=") continue; // avoid !== match
        if (op === "&" && (after === "&" || before === "&")) continue;
        if (op === "|" && (after === "|" || before === "|")) continue;
        if (op === "*" && (after === "*" || before === "*")) continue; // skip **
        if (op === ">>" && (after === ">" || before === ">")) continue;
        if (op === "?" && after === ".") continue; // optional chaining ?.
        if (op === "??" && after === "=") continue; // don't match ??=
        if (op === "||" && after === "=") continue; // don't match ||=
        if (op === "&&" && after === "=") continue; // don't match &&=
        // Guard: treat '-' as unary (not binary) when preceded by an operator or open paren/bracket.
        // This prevents `x * -1` from being parsed as `(x *) - (1)`.
        if (op === "-") {
          let prevP = i - 1;
          while (prevP >= 0 && expr[prevP] === " ") prevP--;
          const prevCh2 = prevP >= 0 ? expr[prevP] : "";
          if (!/[\w)\]]/.test(prevCh2)) continue; // unary minus — skip
        }
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
      if (ch === "(" || ch === "[") {
        depth++;
        continue;
      }
      if (ch === ")" || ch === "]") {
        depth--;
        continue;
      }
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
    // Start from the very end so that closing ) chars in the tail are accounted for in
    // the depth before we check any potential match position.
    for (let i = expr.length - 1; i >= 0; i--) {
      const ch = expr[i];
      if (ch === ")" || ch === "]") depth++;
      else if (ch === "(" || ch === "[") depth--;
      if (
        depth === 0 && i + needle.length <= expr.length &&
        expr.slice(i, i + needle.length) === needle
      ) {
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
    locals: Map<string, WatType>,
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
      if ((inDouble || inSingle) && ch === "\\") {
        i++;
        continue;
      }
      if (ch === '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (ch === "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (!inDouble && !inSingle) {
        if (ch === "(" || ch === "[" || ch === "{") depth++;
        else if (ch === ")" || ch === "]" || ch === "}") depth--;
        else if (ch === "," && depth === 0) {
          args.push(raw.slice(start, i).trim());
          start = i + 1;
        }
      }
    }
    args.push(raw.slice(start).trim());
    return args.filter((a) => a.length > 0);
  }

  // -------------------------------------------------------------------------
  // Statement emitter
  // -------------------------------------------------------------------------
  private emitStatement(
    line: string,
    locals: Map<string, WatType>,
    funcResult: WatType | null,
  ): string {
    // Block-scope correction: a struct-typed var can be re-declared in a sibling block with a
    // DIFFERENT struct type. The pre-scan registers structVars globally (last declaration wins),
    // so an earlier block's field access would resolve against the wrong type. Re-register the
    // var's def to match THIS declaration's annotation as it is emitted (emission is sequential).
    // Scoped to function-call / runtime inits (ptr=-1); static-literal ptrs are per-occurrence and
    // owned by their own emit path, so they are left untouched.
    {
      const sdm = line.match(/^(?:const|let|var)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*(.+)$/);
      if (sdm) {
        const declDef = this.structDefs.get(sdm[2]);
        const cur = this.structVars.get(sdm[1]);
        const rhs = sdm[3].trim();
        if (declDef && cur && cur.def !== declDef && cur.ptr === -1 && /^\w+\s*\(/.test(rhs)) {
          this.structVars.set(sdm[1], { def: declDef, ptr: -1 });
        }
      }
    }

    // Phase 52.5: `void expr;` — evaluate expr for its side effects, discard the result.
    {
      const voidStmtM = line.match(/^void\s+(.+?)\s*;?$/);
      if (voidStmtM) {
        const ve = voidStmtM[1].trim();
        // A call expression (named / dot-call `c.bump()` / closure call) → emit as a plain call
        // statement: the call runs and the statement emitter drops any result itself, so we never
        // emit an invalid `(drop (call $void_fn))`. A leading `(` means a parenthesised value
        // expression (e.g. `void (a + b)`), not a call, so that path is excluded.
        const looksLikeCall = !ve.startsWith("(") && /\)\s*$/.test(ve) &&
          /[\w\])]\s*\(/.test(ve) && parenDepthNeverNegative(ve);
        if (looksLikeCall) return this.emitStatement(ve + ";", locals, funcResult);
        // Otherwise a plain value expression → evaluate and drop. String expressions have no single
        // droppable value, so run them as a statement instead.
        const vt = this.inferExprType(ve, locals);
        if (vt === "string") return this.emitStatement(ve + ";", locals, funcResult);
        return `(drop ${this.emitExpr(ve, locals, vt ?? "i32")})`;
      }
    }

    // Phase 52.6: chained assignment `a = b = c = 0` — rightmost value propagates leftward.
    // Detected by ≥2 top-level plain `=` (not ==/===/=>/!=/<=/>=/compound). Every target must be an
    // assignable lvalue (identifier / member / element). Lowered to a sequence reusing the normal
    // assignment emitter: c = 0; b = c; a = b (rightmost assigned first so each reads the fresh value).
    {
      const eqPos: number[] = [];
      let depth = 0, inS = false, inD = false, inB = false;
      for (let p = 0; p < line.length; p++) {
        const c = line[p];
        if (inS) {
          if (c === "\\") p++;
          else if (c === "'") inS = false;
          continue;
        }
        if (inD) {
          if (c === "\\") p++;
          else if (c === '"') inD = false;
          continue;
        }
        if (inB) {
          if (c === "\\") p++;
          else if (c === "`") inB = false;
          continue;
        }
        if (c === "'") inS = true;
        else if (c === '"') inD = true;
        else if (c === "`") inB = true;
        else if (c === "(" || c === "[" || c === "{") depth++;
        else if (c === ")" || c === "]" || c === "}") depth--;
        else if (c === "=" && depth === 0) {
          const prev = line[p - 1], next = line[p + 1];
          if (next === "=" || prev === "=" || next === ">") continue; // ==, ===, =>
          if (prev && "+-*/%&|^<>!".includes(prev)) continue; // compound or comparison
          eqPos.push(p);
        }
      }
      if (eqPos.length >= 2) {
        const targets: string[] = [];
        let segStart = 0;
        for (let t = 0; t < eqPos.length; t++) {
          targets.push(line.slice(segStart, eqPos[t]).trim());
          segStart = eqPos[t] + 1;
        }
        const rhs = line.slice(segStart).replace(/;$/, "").trim();
        // Each target must be an assignable lvalue: a bare identifier, a member access (`p.x`,
        // `this.x`), or an element access (`arr[i]`). The lowering re-emits `target = source` per
        // step, so any lvalue the normal assignment paths handle works.
        const isLValue = (t: string) =>
          /^\w+$/.test(t) || /^\w+\.\w+$/.test(t) || /^\w+\[[^\]]*\]$/.test(t);
        if (targets.every(isLValue) && rhs.length > 0) {
          const stmts: string[] = [];
          stmts.push(
            this.emitStatement(`${targets[targets.length - 1]} = ${rhs};`, locals, funcResult),
          );
          for (let t = targets.length - 2; t >= 0; t--) {
            stmts.push(
              this.emitStatement(`${targets[t]} = ${targets[t + 1]};`, locals, funcResult),
            );
          }
          return stmts.join("\n      ");
        }
      }
    }

    // return expr;
    if (line.startsWith("return")) {
      const expr = line.replace(/^return\s*/, "").replace(/;$/, "").trim();
      if (!expr || funcResult === null) return "(return)";
      // Phase 24: nullable-return function — set $__nullable_ret_flag before returning.
      // flag=1 → has value; flag=0 → is null.
      if (this.currentFuncIsNullableReturn) {
        if (expr === "null" || expr === "undefined") {
          return `(global.set $__nullable_ret_flag (i32.const 0))\n      (return (${
            watBaseType(funcResult)
          }.const 0))`;
        }
        const retWat = this.emitExpr(expr, locals, funcResult);
        return `(global.set $__nullable_ret_flag (i32.const 1))\n      (return ${retWat})`;
      }
      // return { key: val, ... } — interface/struct object literal: malloc struct and store fields
      if (expr.startsWith("{") && this.currentFuncResultTsName) {
        const structDef = this.structDefs.get(this.currentFuncResultTsName);
        if (structDef) {
          let depth = 0, braceEnd = -1;
          for (let bi = 0; bi < expr.length; bi++) {
            if (expr[bi] === "{") depth++;
            else if (expr[bi] === "}") {
              depth--;
              if (depth === 0) {
                braceEnd = bi;
                break;
              }
            }
          }
          if (braceEnd !== -1) {
            const objContent = expr.slice(1, braceEnd).trim();
            // depth-aware comma split for key:value pairs
            const pairs: string[] = [];
            let pd = 0, ps = 0;
            for (let bi = 0; bi < objContent.length; bi++) {
              const ch = objContent[bi];
              if (ch === "(" || ch === "{" || ch === "[") pd++;
              else if (ch === ")" || ch === "}" || ch === "]") pd--;
              else if (ch === "," && pd === 0) {
                pairs.push(objContent.slice(ps, bi).trim());
                ps = bi + 1;
              }
            }
            const lastPair = objContent.slice(ps).trim();
            if (lastPair) pairs.push(lastPair);
            const stmts: string[] = [];
            stmts.push(
              `(local.set $__obj_ret (call $__malloc (i32.const ${structDef.totalSize})))`,
            );
            for (const pair of pairs) {
              const ci = pair.indexOf(":");
              // Phase 30: shorthand property { x } treated as { x: x }
              const key = ci !== -1 ? pair.slice(0, ci).trim() : pair.trim();
              const valExpr = ci !== -1 ? pair.slice(ci + 1).trim() : key;
              if (!key) continue;
              const field = structDef.fields.find((f) => f.name === key);
              if (!field) continue;
              if (field.structType && valExpr.startsWith("{")) {
                // Phase 42: nested struct literal as field value — allocate inner struct at runtime
                const nestedDef = this.structDefs.get(field.structType);
                if (nestedDef) {
                  let nbd = 0, nestedBraceEnd = -1;
                  for (let ni = 0; ni < valExpr.length; ni++) {
                    if (valExpr[ni] === "{") nbd++;
                    else if (valExpr[ni] === "}") {
                      nbd--;
                      if (nbd === 0) {
                        nestedBraceEnd = ni;
                        break;
                      }
                    }
                  }
                  if (nestedBraceEnd !== -1) {
                    const nestedContent = valExpr.slice(1, nestedBraceEnd).trim();
                    const nestedPairs: string[] = [];
                    let npd = 0, nps = 0;
                    for (let ni = 0; ni < nestedContent.length; ni++) {
                      const ch = nestedContent[ni];
                      if (ch === "(" || ch === "{" || ch === "[") npd++;
                      else if (ch === ")" || ch === "}" || ch === "]") npd--;
                      else if (ch === "," && npd === 0) {
                        nestedPairs.push(nestedContent.slice(nps, ni).trim());
                        nps = ni + 1;
                      }
                    }
                    if (nestedContent.slice(nps).trim()) {
                      nestedPairs.push(nestedContent.slice(nps).trim());
                    }
                    stmts.push(
                      `(local.set $__nested_ptr (call $__malloc (i32.const ${nestedDef.totalSize})))`,
                    );
                    for (const np of nestedPairs) {
                      const nci = np.indexOf(":");
                      const nkey = nci !== -1 ? np.slice(0, nci).trim() : np.trim();
                      const nvalExpr = nci !== -1 ? np.slice(nci + 1).trim() : nkey;
                      if (!nkey) continue;
                      const nfield = nestedDef.fields.find((f) => f.name === nkey);
                      if (!nfield) continue;
                      if (nfield.type === "string") {
                        const ptrLen = this.emitStringPtrLen(nvalExpr, locals);
                        const [ptrW, lenW] = splitTwoWatExprs(ptrLen);
                        stmts.push(
                          `(i32.store offset=${nfield.offset} (local.get $__nested_ptr) ${ptrW})`,
                        );
                        stmts.push(
                          `(i32.store offset=${
                            nfield.offset + 4
                          } (local.get $__nested_ptr) ${lenW})`,
                        );
                      } else {
                        const nstoreOp = nfield.type === "f64"
                          ? "f64.store"
                          : nfield.type === "i64"
                          ? "i64.store"
                          : "i32.store";
                        const nvalWat = this.emitExpr(nvalExpr, locals, nfield.type);
                        stmts.push(
                          `(${nstoreOp} offset=${nfield.offset} (local.get $__nested_ptr) ${nvalWat})`,
                        );
                      }
                    }
                    stmts.push(
                      `(i32.store offset=${field.offset} (local.get $__obj_ret) (local.get $__nested_ptr))`,
                    );
                  }
                }
              } else if (field.type === "string") {
                // String field: store ptr+len (8-byte slot)
                const ptrLen = this.emitStringPtrLen(valExpr, locals);
                const [ptrW, lenW] = splitTwoWatExprs(ptrLen);
                stmts.push(`(i32.store offset=${field.offset} (local.get $__obj_ret) ${ptrW})`);
                stmts.push(`(i32.store offset=${field.offset + 4} (local.get $__obj_ret) ${lenW})`);
              } else {
                const storeOp = field.type === "f64"
                  ? "f64.store"
                  : field.type === "i64"
                  ? "i64.store"
                  : "i32.store";
                const valWat = this.emitExpr(valExpr, locals, field.type);
                stmts.push(`(${storeOp} offset=${field.offset} (local.get $__obj_ret) ${valWat})`);
              }
            }
            stmts.push(`(return (local.get $__obj_ret))`);
            return stmts.join("\n      ");
          }
        }
      }
      // Phase 23: return [e0, e1, ...] — tuple literal: malloc struct, store positional fields, return ptr
      if (expr.startsWith("[") && this.currentFuncResultTsName) {
        const tupleDef = this.structDefs.get(this.currentFuncResultTsName);
        if (tupleDef) {
          const innerStr = expr.slice(1, expr.lastIndexOf("]")).trim();
          const tupleElems = innerStr ? this.splitArgs(innerStr) : [];
          const stmtsR: string[] = [
            `(local.set $__obj_ret (call $__malloc (i32.const ${tupleDef.totalSize})))`,
          ];
          for (let i = 0; i < tupleElems.length; i++) {
            const field = tupleDef.fields[i];
            if (!field) continue;
            const storeOp = field.type === "f64"
              ? "f64.store"
              : field.type === "i64"
              ? "i64.store"
              : "i32.store";
            const valWat = this.emitExpr(tupleElems[i].trim(), locals, field.type);
            stmtsR.push(`(${storeOp} offset=${field.offset} (local.get $__obj_ret) ${valWat})`);
          }
          stmtsR.push(`(return (local.get $__obj_ret))`);
          return stmtsR.join("\n      ");
        }
      }
      // return [elem0, elem1, ...] — array literal: malloc + init + return pointer
      const retArrMatch = expr.match(/^\[([^\]]*)\]$/);
      if (retArrMatch && funcResult === "i32") {
        const elements = retArrMatch[1].split(",").map((e) => e.trim()).filter(Boolean);
        const elemType: WatType = elements.some((e) => /[.]/.test(e) && !/^-?\d+n?$/.test(e))
          ? "f64"
          : "i32";
        const storeOp = elemType === "f64" ? "f64.store" : "i32.store";
        const elemSize = elemType === "f64" ? 8 : 4;
        const capacity = Math.max(elements.length * 2, 8);
        const byteSize = capacity * elemSize + 8;
        const stmts: string[] = [
          `(local.set $__arr_ret (call $__malloc (i32.const ${byteSize})))`,
          `(i32.store (local.get $__arr_ret) (i32.const ${elements.length}))`,
          `(i32.store offset=4 (local.get $__arr_ret) (i32.const ${capacity}))`,
        ];
        for (let i = 0; i < elements.length; i++) {
          const valWat = this.emitExpr(elements[i], locals, elemType);
          stmts.push(`(${storeOp} offset=${8 + i * elemSize} (local.get $__arr_ret) ${valWat})`);
        }
        stmts.push(`(return (local.get $__arr_ret))`);
        return stmts.join("\n      ");
      }
      // String-return side-channel: store ptr/len into scratch locals, then set globals and return void.
      if (funcResult === "string") {
        const assignWat = this.emitStringAssign("__ret_str", expr, locals);
        return [
          assignWat,
          `(global.set $__str_ret_ptr (local.get $__ret_str_ptr))`,
          `(global.set $__str_ret_len (local.get $__ret_str_len))`,
          `(return)`,
        ].join("\n      ");
      }
      return `(return ${this.emitExpr(expr, locals, funcResult)})`;
    }

    // throw new Error("msg") | throw "literal" | throw someVar;
    // Strategy: emit (throw $__exn_tag ptr len) so the exception can be caught by any
    // enclosing try/catch block.  Uncaught throws propagate to the host, which exits
    // with a non-zero code.
    const throwMatch = line.match(/^throw\s+(.+?);?$/);
    if (throwMatch) {
      this.needsExceptionTag = true;
      const throwExpr = throwMatch[1].trim();

      // Helper to emit the WASM throw instruction for a static string in data memory
      const throwExnTag = (ptr: number, len: number): string =>
        `(throw $__exn_tag (i32.const ${ptr}) (i32.const ${len}))`;

      // throw new Error("msg") or throw new Error('msg')
      const newErrMatch = throwExpr.match(/^new\s+Error\s*\(\s*["']([^"']*)["']\s*\)$/);
      if (newErrMatch) {
        const [ptr, len] = this.allocString(newErrMatch[1]);
        return throwExnTag(ptr, len);
      }
      // throw "literal" or throw 'literal'
      const strLitMatch = throwExpr.match(/^["']([^"']*)["']$/);
      if (strLitMatch) {
        const [ptr, len] = this.allocString(strLitMatch[1]);
        return throwExnTag(ptr, len);
      }
      // throw someVar (string variable — ptr/len locals)
      if (/^\w+$/.test(throwExpr)) {
        if (locals.get(throwExpr) === "string") {
          return `(throw $__exn_tag (local.get $${throwExpr}_ptr) (local.get $${throwExpr}_len))`;
        }
        // Numeric/opaque value — exit without a message
        return `(call $proc_exit (i32.const 0))\n      (unreachable)`;
      }
      // Fallback
      return `(call $proc_exit (i32.const 0))\n      (unreachable)`;
    }

    // Function-type variable: const f: (a: i32) => i32 = someFunc  OR  let f: (a: i32) => i32;
    // Local was declared as i32 in pre-scan; here we emit the initialiser if present.
    const funcTypeDecl = line.match(
      /^(?:var|let|const)\s+(\w+)\s*:\s*\([^)]*\)\s*=>\s*\w+(?:\s*=\s*(.+?))?\s*;?$/,
    );
    if (funcTypeDecl) {
      const fullInitExpr = funcTypeDecl[2]?.trim();
      if (fullInitExpr) {
        // Check if it's a closure factory call like mulberry32(42)
        const factoryCallM = fullInitExpr.match(/^(\w+)\s*\(/);
        if (factoryCallM) {
          const factoryFn = this.functions.find((f) =>
            f.name === factoryCallM[1] && f.isClosureFactory && f.returnedArrow
          );
          if (factoryFn) {
            const innerFn = factoryFn.returnedArrow!;
            const caps = innerFn.closureCaptures ?? [];
            const extParams = innerFn.params.filter((p) =>
              !caps.includes(p.name) && p.name !== "__closure_ptr"
            ).map((p) => p.type);
            this.closureTypedVars.set(funcTypeDecl[1], {
              params: extParams,
              result: innerFn.result,
            });
            return `(local.set $${funcTypeDecl[1]} ${this.emitExpr(fullInitExpr, locals, "i32")})`;
          }
        }
        // Plain function reference: store table index
        const simpleNameM = fullInitExpr.match(/^(\w+)$/);
        if (simpleNameM && this.functions.find((f) => f.name === simpleNameM[1])) {
          return `(local.set $${funcTypeDecl[1]} (i32.const ${
            this.getFuncTableIdx(simpleNameM[1])
          }))`;
        }
      }
      return "";
    }

    // Assignment to a function-type variable: f = anotherFunc
    const funcVarAssign = line.match(/^(\w+)\s*=\s*(\w+)\s*;?$/);
    if (funcVarAssign && this.funcTypeVars.has(funcVarAssign[1])) {
      const fn = this.functions.find((f) => f.name === funcVarAssign[2]);
      if (fn) {
        return `(local.set $${funcVarAssign[1]} (i32.const ${
          this.getFuncTableIdx(funcVarAssign[2])
        }))`;
      }
    }

    // Array destructuring with rest/defaults: const [a, b = 20, ...rest] = srcArr
    // Phase 21: preserve empty slots ("gaps") so index advances correctly: [a, , c]
    const arrDestructMatch = line.match(/^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\s*;?$/);
    if (arrDestructMatch) {
      const bindingsList = arrDestructMatch[1].split(",").map((b) => b.trim());
      const srcName = arrDestructMatch[2];
      const srcInfo = this.arrayVars.get(srcName);
      if (srcInfo) {
        const elemType = srcInfo.elemType;
        const loadOp = elemType === "f64"
          ? "f64.load"
          : elemType === "i64"
          ? "i64.load"
          : "i32.load";
        const storeOp = elemType === "f64"
          ? "f64.store"
          : elemType === "i64"
          ? "i64.store"
          : "i32.store";
        const shift = (elemType === "f64" || elemType === "i64") ? 3 : 2;
        const elemSize = (elemType === "f64" || elemType === "i64") ? 8 : 4;
        const watType = elemType === "f64" ? "f64" : elemType === "i64" ? "i64" : "i32";
        const stmts: string[] = [];
        let simpleCount = 0;
        let restName: string | null = null;
        // Count simple bindings (including gaps) and find rest name
        for (const b of bindingsList) {
          if (b.startsWith("...")) restName = b.slice(3).trim();
          else simpleCount++;
        }
        // Emit load for each simple binding, supporting optional default values.
        // Empty slots (gaps) advance idx without emitting a binding.
        let idx = 0;
        for (const b of bindingsList) {
          if (b.startsWith("...")) break;
          if (b === "") {
            idx++;
            continue;
          }
          // Parse "name" or "name = default"
          const eqPos = b.indexOf("=");
          const bindName = eqPos !== -1 ? b.slice(0, eqPos).trim() : b;
          const defVal = eqPos !== -1 ? b.slice(eqPos + 1).trim() : null;
          const loadWat = srcInfo.dynamic
            ? `(${loadOp} (i32.add (i32.add (local.get $${srcName}) (i32.const 8)) (i32.shl (i32.const ${idx}) (i32.const ${shift}))))`
            : `(${loadOp} (i32.const ${srcInfo.ptr + 8 + idx * elemSize}))`;
          if (defVal !== null) {
            // Emit default: if idx < length load element, else use default
            const defWat = `(${watType}.const ${defVal})`;
            if (srcInfo.dynamic) {
              stmts.push(
                `(local.set $${bindName} (if (result ${watType}) (i32.gt_u (i32.load (local.get $${srcName})) (i32.const ${idx})) (then ${loadWat}) (else ${defWat})))`,
              );
            } else {
              // Static: length known at compile time
              stmts.push(
                idx < srcInfo.length
                  ? `(local.set $${bindName} ${loadWat})`
                  : `(local.set $${bindName} ${defWat})`,
              );
            }
          } else {
            stmts.push(`(local.set $${bindName} ${loadWat})`);
          }
          idx++;
        }
        // Emit rest binding
        if (restName) {
          if (srcInfo.dynamic) {
            // Slice from simpleCount to end using dynarr_slice helper
            const key = `slice_${elemType}`;
            this.dynArrHelpers.add(key);
            stmts.push(
              `(local.set $${restName} (call $__dynarr_${key} (local.get $${srcName}) (i32.const ${simpleCount}) (i32.load (local.get $${srcName}))))`,
            );
          } else {
            // Static source: malloc and copy remaining elements
            const restLen = Math.max(srcInfo.length - simpleCount, 0);
            const capacity = Math.max(restLen * 2, 8);
            const byteSize = capacity * elemSize + 8;
            stmts.push(`(local.set $${restName} (call $__malloc (i32.const ${byteSize})))`);
            stmts.push(`(i32.store (local.get $${restName}) (i32.const ${restLen}))`);
            stmts.push(`(i32.store offset=4 (local.get $${restName}) (i32.const ${capacity}))`);
            for (let i = 0; i < restLen; i++) {
              const srcWat = `(${loadOp} (i32.const ${
                srcInfo.ptr + 8 + (simpleCount + i) * elemSize
              }))`;
              stmts.push(
                `(${storeOp} offset=${8 + i * elemSize} (local.get $${restName}) ${srcWat})`,
              );
            }
          }
        }
        return stmts.join("\n      ");
      }
    }

    // Spread array literal declaration: const merged: T[] = [...a, ...b]
    const spreadDeclMatch = line.match(
      /^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/,
    );
    if (spreadDeclMatch && spreadDeclMatch[3]?.includes("...")) {
      const varName = spreadDeclMatch[1];
      const typeHint = spreadDeclMatch[2] ?? "";
      const info = this.arrayVars.get(varName);
      const elemType: WatType = info?.elemType ?? (typeHint ? mapType(typeHint) as WatType : "i32");
      const parts = spreadDeclMatch[3].split(",").map((s) => s.trim()).filter(Boolean);
      const spreads = parts.filter((p) => p.startsWith("...")).map((p) => p.slice(3).trim());
      return this.emitSpreadArrayInit(varName, spreads, elemType);
    }

    // Phase 44: Array<FuncType> = [] declaration (function pointer array)
    const funcArrLetMatch = line.match(
      /^(?:var|let|const)\s+(\w+)\s*:\s*Array<(?:[^<>]|=>)*>\s*=\s*\[\]\s*;?$/,
    );
    if (funcArrLetMatch) {
      const info = this.arrayVars.get(funcArrLetMatch[1]);
      if (info?.dynamic) return this.emitDynArrayInit(funcArrLetMatch[1], info);
    }

    // Phase 6d: 2D array literal declaration: const matrix: i32[][] = [[...], [...]]
    const arr2DLetMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*\w+\[\]\[\]\s*=\s*(.+?);?$/);
    if (arr2DLetMatch) {
      const info = this.arrayVars.get(arr2DLetMatch[1]);
      if (info?.is2D && info.rows) {
        return this.emitDynArray2DInit(arr2DLetMatch[1], {
          elemType: info.elemType,
          rows: info.rows,
        });
      }
      // Phase 18 fix: Array.from({ length: N }, () => []) — runtime 2D array initialization
      if (info?.is2D && info.arrayFromExpr) {
        return this.emitArrayFromInit(arr2DLetMatch[1], info.elemType, info.arrayFromExpr, locals);
      }
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
    const restVarCallMatch = line.match(
      /^(?:var|let|const)\s+(\w+)\s*(?::\s*[\w\[\]]+)?\s*=\s*(\w+)\s*\(([^)]*)\)\s*;?$/,
    );
    if (restVarCallMatch) {
      const varName = restVarCallMatch[1];
      const fnName = restVarCallMatch[2];
      const fnDef = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fnDef?.params[fnDef.params.length - 1];
      if (fnDef && lastParam?.isRest) {
        const rawArgs = restVarCallMatch[3].split(",").map((s) => s.trim()).filter(Boolean);
        const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
        const restRaw = rawArgs.slice(restIdx);
        // Spread call: pass existing array pointer directly
        if (restRaw.length === 1 && restRaw[0].startsWith("...")) {
          const arrName = restRaw[0].slice(3).trim();
          const normalEmitted = rawArgs.slice(0, restIdx).map((a, i) =>
            this.emitExpr(a, locals, fnDef!.params[i].type)
          );
          const arrGet5 = this.moduleGlobals.has(arrName)
            ? `(global.get $${arrName})`
            : `(local.get $${arrName})`;
          const callWat = `(call $${fnName} ${[...normalEmitted, arrGet5].join(" ")})`.trim();
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
      const fnName = restCallStmtMatch[1];
      const fnDef = this.functions.find((f: FuncDef) => f.name === fnName);
      const lastParam = fnDef?.params[fnDef.params.length - 1];
      if (fnDef && lastParam?.isRest) {
        const rawArgs = restCallStmtMatch[2].split(",").map((s) => s.trim()).filter(Boolean);
        const restIdx = fnDef.params.findIndex((p: FuncParam) => p.isRest);
        const restRaw = rawArgs.slice(restIdx);
        // Spread call: pass existing array pointer directly
        if (restRaw.length === 1 && restRaw[0].startsWith("...")) {
          const arrName = restRaw[0].slice(3).trim();
          const normalEmitted = rawArgs.slice(0, restIdx).map((a, i) =>
            this.emitExpr(a, locals, fnDef!.params[i].type)
          );
          const arrGet6 = this.moduleGlobals.has(arrName)
            ? `(global.get $${arrName})`
            : `(local.get $${arrName})`;
          return `(call $${fnName} ${[...normalEmitted, arrGet6].join(" ")})`.trim();
        }
        return this.emitRestParamCall(fnName, rawArgs, locals, null);
      }
    }

    // Phase 23: named tuple alias with bracket initializer: const p: Pair = [e0, e1]
    // Must come before the generic letMatch which would mishandle the bracket value.
    const namedTupleLitStmt = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\[/);
    if (namedTupleLitStmt) {
      const sv = this.structVars.get(namedTupleLitStmt[1]);
      if (sv && sv.def.fields.every((f) => /^_\d+$/.test(f.name))) {
        if (sv.ptr >= 0) return `(local.set $${namedTupleLitStmt[1]} (i32.const ${sv.ptr}))`;
        // Runtime allocation
        const eqBI3 = line.indexOf("= [");
        const vBody3 = eqBI3 !== -1 ? line.slice(eqBI3 + 3).replace(/\]\s*;?\s*$/, "") : "";
        const elems4 = vBody3 ? this.splitArgs(vBody3) : [];
        const stmtsN: string[] = [
          `(local.set $${namedTupleLitStmt[1]} (call $__malloc (i32.const ${sv.def.totalSize})))`,
        ];
        for (let i = 0; i < elems4.length; i++) {
          const field = sv.def.fields[i];
          if (!field) continue;
          const storeOp = field.type === "f64"
            ? "f64.store"
            : field.type === "i64"
            ? "i64.store"
            : "i32.store";
          stmtsN.push(
            `(${storeOp} offset=${field.offset} (local.get $${namedTupleLitStmt[1]}) ${
              this.emitExpr(elems4[i].trim(), locals, field.type)
            })`,
          );
        }
        return stmtsN.join("\n      ");
      }
    }

    // Phase 23: tuple literal init: const t: [i32, f64] = [e0, e1, ...]
    // Phase 51.3: bracket-aware type match + recursive element stores so nested tuples
    // (const t: [[i32, i32], i32] = [[1, 2], 3]) construct their inline sub-tuples.
    // Must come before array and struct checks since the type annotation contains brackets.
    const tupleLitStmt = line.match(
      /^(?:var|let|const)\s+(\w+)\s*:\s*\[(?:[^[\]]|\[[^\]]*\])*\]\s*=\s*\[/,
    );
    if (tupleLitStmt) {
      const sv = this.structVars.get(tupleLitStmt[1]);
      if (sv) {
        if (sv.ptr >= 0) {
          return `(local.set $${tupleLitStmt[1]} (i32.const ${sv.ptr}))`;
        }
        // Runtime allocation: malloc, store each (possibly nested) element, set local.
        const eqBI2 = line.indexOf("= [");
        const vBody2 = eqBI2 !== -1 ? line.slice(eqBI2 + 3).replace(/\]\s*;?\s*$/, "") : "";
        const stmtsT: string[] = [
          `(local.set $${tupleLitStmt[1]} (call $__malloc (i32.const ${sv.def.totalSize})))`,
          ...this.emitTupleLiteralStores(vBody2, tupleLitStmt[1], sv.def, 0, locals),
        ];
        return stmtsT.join("\n      ");
      }
    }

    // Phase 21: destructure from a class's embedded tuple field — const [a, b] = obj.bounds
    const tupleFieldDestructStmt = line.match(
      /^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\.(\w+)\s*;?$/,
    );
    if (tupleFieldDestructStmt) {
      const recv = tupleFieldDestructStmt[2];
      const fname = tupleFieldDestructStmt[3];
      const cv = this.classVars.get(recv);
      if (cv) {
        const cd = this.classDefs.get(cv.className);
        const cf = cd?.struct.fields.find((f) => f.name === fname);
        if (cf?.tupleTypeName) {
          const tdef = this.structDefs.get(cf.tupleTypeName);
          if (tdef) {
            const blist = tupleFieldDestructStmt[1].split(",").map((b) => b.trim());
            const stmts: string[] = [];
            const baseWat = cv.ptr < 0 ? `(local.get $${recv})` : `(i32.const ${cv.ptr})`;
            for (let i = 0; i < blist.length; i++) {
              const b = blist[i];
              if (b === "" || b.startsWith("...")) continue;
              const tf = tdef.fields[i];
              if (!tf) continue;
              const loadOp = tf.type === "f64"
                ? "f64.load"
                : tf.type === "i64"
                ? "i64.load"
                : "i32.load";
              stmts.push(
                `(local.set $${b} (${loadOp} offset=${cf.offset + tf.offset} ${baseWat}))`,
              );
            }
            return stmts.join("\n      ");
          }
        }
      }
    }

    // Phase 23: tuple destructuring: const [a, b] = tupleVar (when source is a structVar/tuple)
    // Phase 21: preserve empty slots ("gaps") so positional index advances correctly: [a, , c]
    // Phase 51.3: balanced-bracket detection + recursion so nested tuple patterns work:
    // const [[a, b], c] = t. Runs after the array-destructure handler, so array sources are
    // already consumed; this only fires when the source is a tuple structVar.
    const tupleDestructHead = line.match(/^(?:var|let|const)\s*\[/);
    if (tupleDestructHead) {
      const openIdx = line.indexOf("[");
      const closeIdx = findMatchingBracketAware(line, openIdx);
      const after = closeIdx !== -1 ? line.slice(closeIdx + 1).trim() : "";
      const eqM = after.match(/^=\s*(\w+)\s*;?$/);
      if (closeIdx !== -1 && eqM) {
        const sv = this.structVars.get(eqM[1]);
        if (sv) {
          const pattern = line.slice(openIdx, closeIdx + 1);
          const baseWat = sv.ptr < 0 ? `(local.get $${eqM[1]})` : `(i32.const ${sv.ptr})`;
          return this.emitDestructurePattern(pattern, baseWat, sv.def, locals).join("\n      ");
        }
      }
    }

    // Phase 51.2: object spread init: const/let r: TypeName = { ...src, k: v }
    // The pre-scan flagged `r` in structSpreadVars and declared it as an i32 local; build the
    // struct at runtime (copy base fields, apply overrides) and assign the pointer.
    // Must come BEFORE the static structLetMatch handler below (which assumes a non-spread literal).
    const structSpreadMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{/);
    if (structSpreadMatch && this.structSpreadVars.has(structSpreadMatch[1])) {
      const litStr = line.slice(line.indexOf("{"));
      const rt = this.emitRuntimeStructLiteral(litStr, structSpreadMatch[2], locals);
      if (rt) return `(local.set $${structSpreadMatch[1]} ${rt})`;
    }

    // Struct object literal init: const/let p: TypeName = { ... }
    // The pre-scan allocated static memory; emit local.set $p (i32.const ptr).
    // Phase 30: also emits runtime stores for shorthand-property fields.
    // Must come BEFORE the generic letMatch handler below.
    const structLetMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{/);
    if (structLetMatch) {
      const sv = this.structVars.get(structLetMatch[1]);
      if (sv && sv.ptr >= 0) {
        const stmts = [`(local.set $${structLetMatch[1]} (i32.const ${sv.ptr}))`];
        const runtimeInits = this.structVarRuntimeInits.get(structLetMatch[1]);
        if (runtimeInits) {
          for (const [fieldName, exprStr] of Object.entries(runtimeInits)) {
            const field = sv.def.fields.find((f) => f.name === fieldName);
            if (field) {
              const storeOp = field.type === "f64"
                ? "f64.store"
                : field.type === "i64"
                ? "i64.store"
                : "i32.store";
              const valWat = this.emitExpr(exprStr, locals, field.type);
              stmts.push(`(${storeOp} offset=${field.offset} (i32.const ${sv.ptr}) ${valWat})`);
            }
          }
        }
        return stmts.join("\n      ");
      }
      // ptr === -3: heap-allocate on each call (struct has runtime-computed fields)
      if (sv && sv.ptr === -3) {
        const structSize = sv.def.totalSize;
        const stmts = [
          `(local.set $${structLetMatch[1]} (call $__malloc (i32.const ${structSize})))`,
        ];
        const runtimeInits = this.structVarRuntimeInits.get(structLetMatch[1]);
        // Emit runtime field stores for dynamic values
        if (runtimeInits) {
          for (const [fieldName, exprStr] of Object.entries(runtimeInits)) {
            const field = sv.def.fields.find((f) => f.name === fieldName);
            if (field) {
              const storeOp = field.type === "f64"
                ? "f64.store"
                : field.type === "i64"
                ? "i64.store"
                : "i32.store";
              const valWat = this.emitExpr(exprStr, locals, field.type);
              stmts.push(
                `(${storeOp} offset=${field.offset} (local.get $${structLetMatch[1]}) ${valWat})`,
              );
            }
          }
        }
        // Also emit constant-initialized fields that were stored in initFields
        // We need to re-parse the struct literal here for the constant fields
        const initRe2 = /(\w+)\s*:\s*([^,}]+)/g;
        let im2: RegExpExecArray | null;
        while ((im2 = initRe2.exec(line.slice(line.indexOf("{")))) !== null) {
          const fieldKey2 = im2[1];
          if (runtimeInits && runtimeInits[fieldKey2]) continue; // already handled
          const valStr2 = im2[2].trim();
          const field2 = sv.def.fields.find((f) => f.name === fieldKey2);
          if (field2) {
            const storeOp2 = field2.type === "f64"
              ? "f64.store"
              : field2.type === "i64"
              ? "i64.store"
              : "i32.store";
            const valWat2 = this.emitExpr(valStr2, locals, field2.type);
            stmts.push(
              `(${storeOp2} offset=${field2.offset} (local.get $${structLetMatch[1]}) ${valWat2})`,
            );
          }
        }
        return stmts.join("\n      ");
      }
    }

    // Object destructuring: const { x, y } = structVar  or  const { x: localX } = structVar
    // Phase 48: "= default" fallback when field value is zero (wasic zero-sentinel semantics).
    // Phase 51.3: nesting-aware — `const { a: { b }, c } = obj` recurses into nested struct fields.
    // Balanced-brace detection (not [^}]+) so nested patterns are captured whole.
    const objHead = line.match(/^(?:var|let|const)\s*\{/);
    if (objHead) {
      const openIdx = line.indexOf("{");
      const closeIdx = findMatchingBracketAware(line, openIdx);
      const after = closeIdx !== -1 ? line.slice(closeIdx + 1).trim() : "";
      const eqM = after.match(/^=\s*(\w+)\s*;?$/);
      if (closeIdx !== -1 && eqM) {
        const sv = this.structVars.get(eqM[1]);
        if (!sv) {
          this.diagnostics.push(`Destructuring: '${eqM[1]}' is not a known struct variable`);
          return "";
        }
        const pattern = line.slice(openIdx, closeIdx + 1);
        const baseWat = sv.ptr < 0 ? `(local.get $${eqM[1]})` : `(i32.const ${sv.ptr})`;
        return this.emitDestructurePattern(pattern, baseWat, sv.def, locals).join("\n      ");
      }
    }

    // Phase 31: TypedArray initialization — must come BEFORE newDeclMatch.
    {
      const taInitMatch = line.match(
        /^(?:var|let|const)\s+(\w+)\s*(?::\s*\w+)?\s*=\s*new\s+(Int8Array|Uint8Array|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array)\s*\((.*)\)\s*;?$/,
      );
      if (taInitMatch) {
        const varName = taInitMatch[1];
        const taType = taInitMatch[2];
        const argsStr = taInitMatch[3].trim();
        const taInfo = getTypedArrayInfo(taType)!;
        const { bytesPerElem, shift, storeOp, elemType } = taInfo;
        const stmts: string[] = [];
        if (argsStr.startsWith("[")) {
          // Literal array initializer: new Int32Array([1, 2, 3])
          const elemsStr = argsStr.slice(1).replace(/\]\s*$/, "");
          const elems = elemsStr.split(",").map((s) => s.trim()).filter(Boolean);
          const n = elems.length;
          stmts.push(
            `(local.set $${varName} (call $__malloc (i32.const ${8 + n * bytesPerElem})))`,
          );
          stmts.push(`(i32.store (local.get $${varName}) (i32.const ${n}))`);
          for (let idx = 0; idx < elems.length; idx++) {
            const offset = 8 + idx * bytesPerElem;
            const valWat = this.emitExpr(elems[idx], locals, elemType);
            stmts.push(
              `(${storeOp} (i32.add (local.get $${varName}) (i32.const ${offset})) ${valWat})`,
            );
          }
        } else if (/^\d+$/.test(argsStr)) {
          // Literal length: new Int32Array(5) — zero-fill relies on WASM zeroed memory
          const n = parseInt(argsStr, 10);
          stmts.push(
            `(local.set $${varName} (call $__malloc (i32.const ${8 + n * bytesPerElem})))`,
          );
          stmts.push(`(i32.store (local.get $${varName}) (i32.const ${n}))`);
        } else {
          // Runtime length: new Int32Array(n) — n may be a variable or expression
          const lenWat = this.emitExpr(argsStr, locals, "i32");
          const sizeWat = shift === 0
            ? `(i32.add (i32.const 8) ${lenWat})`
            : `(i32.add (i32.const 8) (i32.shl ${lenWat} (i32.const ${shift})))`;
          stmts.push(`(local.set $${varName} (call $__malloc ${sizeWat}))`);
          stmts.push(`(i32.store (local.get $${varName}) ${lenWat})`);
        }
        return stmts.join("\n      ");
      }
    }
    // Class instance declaration: const obj: ClassName = new ClassName(args)
    const newDeclMatch = line.match(
      /^(?:var|let|const)\s+(\w+)\s*(?::\s*[A-Z]\w*)?\s*=\s*new\s+([A-Z]\w*)\s*\(([\s\S]*?)\)\s*;?$/,
    );
    if (newDeclMatch) {
      const varName = newDeclMatch[1];
      const cv = this.classVars.get(varName);
      if (cv) {
        const ptr = cv.ptr;
        const argsStr = newDeclMatch[3].trim();
        const constructorName = `${cv.className}_constructor`;
        const ctorFn = this.functions.find((f) => f.name === constructorName);
        const setLocal = `(local.set $${varName} (i32.const ${ptr}))`;
        if (ctorFn) {
          const args = argsStr ? this.splitArgs(argsStr) : [];
          const emittedArgs = args.flatMap((a, i) => {
            const pt = ctorFn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const ctorCall = `(call $${constructorName} (i32.const ${ptr}) ${emittedArgs.join(" ")})`
            .trim();
          return `${setLocal}\n      ${ctorCall}`;
        }
        return setLocal;
      }
    }

    // Phase 24: nullable variable declaration: let x: T | null = expr
    // Must come before letMatch because letMatch only captures single-word type annotations.
    const nullableLetMatch = line.match(
      /^(?:var|let|const)\s+(\w+)\s*:\s*([\w\[\]]+(?:\s*\|\s*(?:null|undefined))+)\s*=\s*(.+?);?$/,
    );
    if (nullableLetMatch) {
      const nlVarName = nullableLetMatch[1];
      const nlTypeStr = nullableLetMatch[2];
      const nlInitExpr = nullableLetMatch[3].trim();
      const nlInner = parseNullableAnnotation(nlTypeStr);
      if (nlInner && this.nullableVarInnerType.has(nlVarName)) {
        if (nlInitExpr === "null" || nlInitExpr === "undefined") {
          if (nlInner === "string") {
            locals.set(nlVarName, "string");
            return this.emitStringAssign(nlVarName, nlInitExpr, locals);
          }
          // Value type: clear value, set null flag
          return `(local.set $${nlVarName}__null (i32.const 1))`;
        }
        if (nlInner === "string") {
          locals.set(nlVarName, "string");
          return this.emitStringAssign(nlVarName, nlInitExpr, locals);
        }
        // Track find() result variables so console.log can print "undefined" for not-found sentinel.
        // Must happen here too because nullableLetMatch returns early, bypassing the letMatch path.
        if (/^\w+\.find\s*\(/.test(nlInitExpr) && (nlInner === "i32" || nlInner === "f64")) {
          this.findResultVars.add(nlVarName);
        }
        // Detect call to a nullable-returning function to propagate the flag
        const nlFnCallM = nlInitExpr.match(/^(\w+)\s*\(/);
        const nlCalledFn = nlFnCallM ? this.functions.find((f) => f.name === nlFnCallM[1]) : null;
        const valWat = this.emitExpr(nlInitExpr, locals, nlInner);
        if (nlCalledFn && this.nullableFuncReturnType.has(nlCalledFn.name)) {
          // Read the side-channel flag written by the callee
          return `(local.set $${nlVarName} ${valWat})\n      (local.set $${nlVarName}__null (i32.eqz (global.get $__nullable_ret_flag)))`;
        }
        return `(local.set $${nlVarName} ${valWat})\n      (local.set $${nlVarName}__null (i32.const 0))`;
      }
    }

    // var / let / const declaration
    const letMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?);?$/);
    if (letMatch) {
      const varName = letMatch[1];
      const typeStr = letMatch[2] ?? "";
      const initExpr = letMatch[3].trim();
      // Arrow function declaration — already lifted to module level by parseArrowFunctions.
      // If the variable name is a known function and registered as a funcref, emit the table index.
      if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) {
        if (this.funcTypeVars.has(varName)) {
          const fn = this.functions.find((f) => f.name === varName);
          if (fn) return `(local.set $${varName} (i32.const ${this.getFuncTableIdx(varName)}))`;
        }
        return "";
      }
      // Function variable: const f = knownFuncName — emit table index
      if (/^\w+$/.test(initExpr) && this.funcTypeVars.has(varName)) {
        const fn = this.functions.find((f) => f.name === initExpr);
        if (fn) return `(local.set $${varName} (i32.const ${this.getFuncTableIdx(initExpr)}))`;
      }
      const varType = typeStr
        ? mapType(typeStr)
        : inferInitType(initExpr, locals, this.enumValues, this.functions);
      if (varType === "string") {
        locals.set(varName, "string");
        return this.emitStringAssign(varName, initExpr, locals);
      }
      locals.set(varName, varType);
      // Track find() result variables so console.log can print "undefined" for not-found sentinel
      if (/^\w+\.find\s*\(/.test(initExpr) && (varType === "i32" || varType === "f64")) {
        this.findResultVars.add(varName);
      }
      // Phase 5h: shared mutable capture — allocate heap cell, store initial value into it
      if (this.currentSharedMutableCaptures.has(varName)) {
        const initWat = this.emitExpr(initExpr, locals, "i32");
        return `(local.set $${varName} (call $__malloc (i32.const 4)))\n      (i32.store (local.get $${varName}) ${initWat})`;
      }
      return `(local.set $${varName} ${this.emitExpr(initExpr, locals, varType)})`;
    }

    // Compound assignment: +=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=  >>>=
    // Phase 25: logical assignment ??= ||= &&=
    const logicalAssignMatch = line.match(/^(\w+)\s*(\?\?=|\|\|=|&&=)\s*(.+?);?$/);
    if (
      logicalAssignMatch &&
      (locals.has(logicalAssignMatch[1]) || this.moduleGlobals.has(logicalAssignMatch[1]))
    ) {
      const laVar = logicalAssignMatch[1];
      const laOp = logicalAssignMatch[2];
      const laRhs = logicalAssignMatch[3].trim();
      const isGlobal = !locals.has(laVar) && this.moduleGlobals.has(laVar);
      const nlInner = this.nullableVarInnerType.get(laVar);
      const laType = nlInner ??
        (isGlobal ? this.moduleGlobals.get(laVar)!.type : (locals.get(laVar) as WatType)) ?? "i32";
      const getWat = isGlobal ? `(global.get $${laVar})` : `(local.get $${laVar})`;
      const rhsWat = this.emitExpr(laRhs, locals, laType);
      const setVal = isGlobal
        ? `(global.set $${laVar} ${rhsWat})`
        : `(local.set $${laVar} ${rhsWat})`;
      if (laOp === "??=") {
        if (nlInner) {
          const setNull = isGlobal
            ? `(global.set $${laVar}__null (i32.const 0))`
            : `(local.set $${laVar}__null (i32.const 0))`;
          const nullGet = isGlobal ? `(global.get $${laVar}__null)` : `(local.get $${laVar}__null)`;
          return `(if ${nullGet} (then ${setVal} ${setNull}))`;
        }
        const ptrGet = (locals.get(laVar) === "string") ? `(local.get $${laVar}_ptr)` : getWat;
        return `(if (i32.eqz ${ptrGet}) (then ${setVal}))`;
      }
      if (laOp === "||=") {
        return `(if (i32.eqz ${getWat}) (then ${setVal}))`;
      }
      if (laOp === "&&=") {
        return `(if ${getWat} (then ${setVal}))`;
      }
    }

    // Phase 48: **= exponent compound assignment — expanded to x = Math.pow(x, rhs)
    const expAssignMatch = line.match(/^(\w+)\s*\*\*=\s*(.+?);?$/);
    if (
      expAssignMatch && (locals.has(expAssignMatch[1]) || this.moduleGlobals.has(expAssignMatch[1]))
    ) {
      const eaVar = expAssignMatch[1];
      const eaRhs = expAssignMatch[2].trim();
      const isGlobal = !locals.has(eaVar) && this.moduleGlobals.has(eaVar);
      const getWat = isGlobal ? `(global.get $${eaVar})` : `(local.get $${eaVar})`;
      this.mathHelpers.add("math_pow");
      const powWat = `(call $__math_pow ${getWat} ${this.emitExpr(eaRhs, locals, "f64")})`;
      return isGlobal ? `(global.set $${eaVar} ${powWat})` : `(local.set $${eaVar} ${powWat})`;
    }

    const compoundMatch = line.match(
      /^(\w+)\s*(>>>=|>>=|<<=|\+=|-=|\*=|\/=|%=|&=|\|=|\^=)\s*(.+?);?$/,
    );
    if (
      compoundMatch && (locals.has(compoundMatch[1]) || this.moduleGlobals.has(compoundMatch[1]))
    ) {
      const varName = compoundMatch[1];
      const isGlobal = !locals.has(varName) && this.moduleGlobals.has(varName);
      const varType = isGlobal ? this.moduleGlobals.get(varName)!.type : locals.get(varName)!;
      // String += must route through emitStringAssign, not numeric arithmetic
      if (varType === "string" && compoundMatch[2] === "+=") {
        const rhs = compoundMatch[3].trim();
        return this.emitStringAssign(varName, `${varName} + ${rhs}`, locals);
      }
      const op = compoundMatch[2];
      const rhs = compoundMatch[3].trim();
      type CE = [fOp: string, iOp: string, alwaysI32: boolean];
      const watOps: Record<string, CE> = {
        "+=": ["add", "add", false],
        "-=": ["sub", "sub", false],
        "*=": ["mul", "mul", false],
        "/=": ["div", "div_s", false],
        "%=": ["rem", "rem_s", false],
        "&=": ["and", "and", true],
        "|=": ["or", "or", true],
        "^=": ["xor", "xor", true],
        "<<=": ["shl", "shl", true],
        ">>=": ["shr_s", "shr_s", true],
        ">>>=": ["shr_u", "shr_u", true],
      };
      const [fOp, iOp, alwaysI32] = watOps[op] ?? ["add", "add", false];
      const opType = alwaysI32 ? "i32" : watBaseType(varType);
      const isFloat = opType === "f64" || opType === "f32";
      const suffix = isFloat ? fOp : iOp;
      const getWatVar = isGlobal ? `(global.get $${varName})` : `(local.get $${varName})`;
      const rhsWat = this.emitExpr(rhs, locals, opType);
      // f64.rem does not exist in WebAssembly; emit formula for %=
      const arithWat = (op === "%=" && isFloat)
        ? `(${opType}.sub ${getWatVar} (${opType}.mul (${opType}.trunc (${opType}.div ${getWatVar} ${rhsWat})) ${rhsWat}))`
        : `(${opType}.${suffix} ${getWatVar} ${rhsWat})`;
      if (isGlobal) {
        return `(global.set $${varName} ${arithWat})`;
      }
      // Phase 5h: boxed capture — update through heap pointer
      if (this.currentBoxedCaptures.has(varName)) {
        const boxedGet = `(i32.load (local.get $${varName}))`;
        const boxedRhs = this.emitExpr(rhs, locals, opType);
        const boxedArith = (op === "%=" && isFloat)
          ? `(${opType}.sub ${boxedGet} (${opType}.mul (${opType}.trunc (${opType}.div ${boxedGet} ${boxedRhs})) ${boxedRhs}))`
          : `(${opType}.${suffix} ${boxedGet} ${boxedRhs})`;
        return `(i32.store (local.get $${varName}) ${boxedArith})`;
      }
      // Mutable closure capture — update through $__closure_ptr
      {
        const ccl = this.currentClosureCaptureLayout.get(varName);
        if (ccl) {
          const cLoadOp = ccl.type === "f64"
            ? "f64.load"
            : ccl.type === "i64"
            ? "i64.load"
            : "i32.load";
          const cStoreOp = ccl.type === "f64"
            ? "f64.store"
            : ccl.type === "i64"
            ? "i64.store"
            : "i32.store";
          const cGet = `(${cLoadOp} offset=${ccl.offset} (local.get $__closure_ptr))`;
          const cRhs = this.emitExpr(rhs, locals, ccl.type);
          const cArith = (op === "%=" && (ccl.type === "f64" || ccl.type === "f32"))
            ? `(${ccl.type}.sub ${cGet} (${ccl.type}.mul (${ccl.type}.trunc (${ccl.type}.div ${cGet} ${cRhs})) ${cRhs}))`
            : `(${ccl.type}.${suffix} ${cGet} ${cRhs})`;
          return `(${cStoreOp} offset=${ccl.offset} (local.get $__closure_ptr) ${cArith})`;
        }
      }
      return `(local.set $${varName} ${arithWat})`;
    }

    // this.field = val — write to instance field inside a class method
    const thisWriteMatch = line.match(/^this\.(\w+)\s*=\s*(.+?);?$/);
    if (thisWriteMatch && this.currentMethodClass) {
      const cd = this.classDefs.get(this.currentMethodClass);
      // Phase 29: setter dispatch before raw field store
      const setter = cd?.methods.find((m) => m.isSetter && m.name === thisWriteMatch[1]);
      if (setter) {
        const setFuncName = `${this.currentMethodClass}_set_${thisWriteMatch[1]}`;
        const setterFn = this.functions.find((f) => f.name === setFuncName);
        const paramType = setterFn?.params[1]?.type ?? "i32";
        const valWat = this.emitExpr(thisWriteMatch[2], locals, paramType);
        return `(call $${setFuncName} (local.get $__self) ${valWat})`;
      }
      const field = cd?.struct.fields.find((f) => f.name === thisWriteMatch[1]);
      if (field) {
        // Phase 21: readonly guard — only allow writes inside the constructor
        if (field.readonly && this.currentMethodName !== `${this.currentMethodClass}_constructor`) {
          this.diagnostics.push(
            `Cannot assign to readonly field '${
              thisWriteMatch[1]
            }' of '${this.currentMethodClass}'`,
          );
        }
        // Phase 21: embedded tuple field — `this.bounds = [a, b]` writes per-element inline.
        if (field.tupleTypeName) {
          const tdef = this.structDefs.get(field.tupleTypeName);
          const rhs = thisWriteMatch[2].trim();
          const lit = rhs.match(/^\[(.+)\]$/);
          if (tdef && lit) {
            const elems = lit[1].split(",").map((s) => s.trim());
            const parts: string[] = [];
            for (let i = 0; i < tdef.fields.length && i < elems.length; i++) {
              const tf = tdef.fields[i];
              const sop = tf.type === "f64"
                ? "f64.store"
                : tf.type === "i64"
                ? "i64.store"
                : "i32.store";
              const vw = this.emitExpr(elems[i], locals, tf.type);
              parts.push(`(${sop} offset=${field.offset + tf.offset} (local.get $__self) ${vw})`);
            }
            return parts.join("\n      ");
          }
        }
        const storeOp = field.type === "f64"
          ? "f64.store"
          : field.type === "i64"
          ? "i64.store"
          : "i32.store";
        const valWat = this.emitExpr(thisWriteMatch[2], locals, field.type);
        return `(${storeOp} (i32.add (local.get $__self) (i32.const ${field.offset})) ${valWat})`;
      }
    }

    // Struct field write: p.field = value
    // Desugar field ++/-- and compound-assign (recv.field OP= val) on a struct/class field
    // (or this.field, or a static ClassName.field) into the plain `recv.field = recv.field OP val`
    // form, which the struct/class/static write handlers below already support. Without this,
    // `c.a++` and `c.b += 5` fell through to a comment-stub and the mutation was silently dropped.
    {
      const recvKnown = (r: string): boolean =>
        r === "this" || this.classVars.has(r) || this.structVars.has(r) || this.classDefs.has(r);
      let fim = line.match(/^(this|\w+)\.(\w+)\s*(\+\+|--)\s*;?$/);
      if (fim && recvKnown(fim[1])) {
        const op = fim[3] === "++" ? "+" : "-";
        return this.emitStatement(
          `${fim[1]}.${fim[2]} = ${fim[1]}.${fim[2]} ${op} 1;`,
          locals,
          funcResult,
        );
      }
      fim = line.match(/^(\+\+|--)\s*(this|\w+)\.(\w+)\s*;?$/);
      if (fim && recvKnown(fim[2])) {
        const op = fim[1] === "++" ? "+" : "-";
        return this.emitStatement(
          `${fim[2]}.${fim[3]} = ${fim[2]}.${fim[3]} ${op} 1;`,
          locals,
          funcResult,
        );
      }
      fim = line.match(/^(this|\w+)\.(\w+)\s*([+\-*/%&|^]|<<|>>|>>>)=\s*(.+?);?$/);
      if (fim && recvKnown(fim[1])) {
        return this.emitStatement(
          `${fim[1]}.${fim[2]} = ${fim[1]}.${fim[2]} ${fim[3]} (${fim[4]});`,
          locals,
          funcResult,
        );
      }
    }

    const structWriteMatch = line.match(/^(\w+)\.(\w+)\s*=\s*(.+?);?$/);
    if (structWriteMatch) {
      // Class instance field write (takes priority)
      const wCv = this.classVars.get(structWriteMatch[1]);
      if (wCv) {
        const wCd = this.classDefs.get(wCv.className);
        // Phase 29: setter dispatch before raw field store
        const setter = wCd?.methods.find((m) => m.isSetter && m.name === structWriteMatch[2]);
        if (setter) {
          const setFuncName = `${wCv.className}_set_${structWriteMatch[2]}`;
          const setterFn = this.functions.find((f) => f.name === setFuncName);
          const paramType = setterFn?.params[1]?.type ?? "i32";
          const baseWat = wCv.ptr === -1
            ? `(local.get $${structWriteMatch[1]})`
            : `(i32.const ${wCv.ptr})`;
          const valWat = this.emitExpr(structWriteMatch[3], locals, paramType);
          return `(call $${setFuncName} ${baseWat} ${valWat})`;
        }
        const wField = wCd?.struct.fields.find((f) => f.name === structWriteMatch[2]);
        if (wField) {
          // Phase 21: readonly guard for class instance fields accessed via variable
          if (wField.readonly) {
            this.diagnostics.push(
              `Cannot assign to readonly field '${structWriteMatch[2]}' of '${wCv.className}'`,
            );
          }
          const storeOp = wField.type === "f64"
            ? "f64.store"
            : wField.type === "i64"
            ? "i64.store"
            : "i32.store";
          const baseWat = wCv.ptr === -1
            ? `(local.get $${structWriteMatch[1]})`
            : `(i32.const ${wCv.ptr})`;
          const valWat = this.emitExpr(structWriteMatch[3], locals, wField.type);
          return `(${storeOp} (i32.add ${baseWat} (i32.const ${wField.offset})) ${valWat})`;
        }
      }
      // Phase 29: static field write — ClassName.fieldName = val → (global.set $ClassName_fieldName val)
      if (!wCv) {
        const staticWriteCd = this.classDefs.get(structWriteMatch[1]);
        if (staticWriteCd) {
          const globalKey = `${structWriteMatch[1]}_${structWriteMatch[2]}`;
          if (this.moduleGlobals.has(globalKey)) {
            const gType = this.moduleGlobals.get(globalKey)!.type;
            const valWat = this.emitExpr(structWriteMatch[3], locals, gType);
            return `(global.set $${globalKey} ${valWat})`;
          }
        }
      }
      const sv = this.structVars.get(structWriteMatch[1]);
      if (sv) {
        const field = sv.def.fields.find((f) => f.name === structWriteMatch[2]);
        if (field) {
          // Phase 21: readonly guard for struct fields
          if (field.readonly) {
            this.diagnostics.push(
              `Cannot assign to readonly field '${structWriteMatch[2]}' of struct '${sv.def.name}'`,
            );
          }
          const storeOp = field.type === "f64"
            ? "f64.store"
            : field.type === "i64"
            ? "i64.store"
            : "i32.store";
          const baseWat = sv.ptr < 0
            ? `(local.get $${structWriteMatch[1]})`
            : `(i32.const ${sv.ptr})`;
          const valWat = this.emitExpr(structWriteMatch[3], locals, field.type);
          return `(${storeOp} (i32.add ${baseWat} (i32.const ${field.offset})) ${valWat})`;
        }
      }
    }

    // Phase 6d: 2D subscript push: matrix[i].push(val) — statement form
    const subscriptPushStmt = line.match(/^(\w+)\[(.+?)\]\.(push)\s*\((.+?)\)\s*;?$/);
    if (subscriptPushStmt) {
      const outerName = subscriptPushStmt[1];
      const outerInfo = this.arrayVars.get(outerName);
      if (outerInfo?.dynamic && outerInfo.is2D) {
        const idxWat = this.emitExpr(subscriptPushStmt[2], locals, "i32");
        const valWat = this.emitExpr(subscriptPushStmt[4], locals, outerInfo.elemType);
        const addrWat =
          `(i32.add (i32.add (local.get $${outerName}) (i32.const 8)) (i32.shl ${idxWat} (i32.const 2)))`;
        this.dynArrHelpers.add(`push_${outerInfo.elemType}`);
        // Load inner ptr, push (returns possibly-grown ptr), store back — address evaluated twice
        // but it's pure arithmetic so safe.
        return `(i32.store ${addrWat} (call $__dynarr_push_${outerInfo.elemType} (i32.load ${addrWat}) ${valWat}))`;
      }
      // Phase 5h: 2D array captured as i32 local (closure param) — treat as dynamic i32[][]
      if (!outerInfo && locals.get(outerName) === "i32") {
        const idxWat = this.emitExpr(subscriptPushStmt[2], locals, "i32");
        const valWat = this.emitExpr(subscriptPushStmt[4], locals, "i32");
        const addrWat =
          `(i32.add (i32.add (local.get $${outerName}) (i32.const 8)) (i32.shl ${idxWat} (i32.const 2)))`;
        this.dynArrHelpers.add("push_i32");
        return `(i32.store ${addrWat} (call $__dynarr_push_i32 (i32.load ${addrWat}) ${valWat}))`;
      }
    }

    // Dynamic array methods: arr.push(val), arr.pop(), arr.shift(), arr.unshift(val), arr.splice(i,n) — statement form
    const dynArrStmt = line.match(/^(\w+)\.(push|pop|shift|unshift|splice)\s*\((.*?)\)\s*;?$/);
    if (dynArrStmt) {
      const arrName = dynArrStmt[1];
      const method = dynArrStmt[2] as "push" | "pop" | "shift" | "unshift" | "splice";
      const argsStr = dynArrStmt[3].trim();
      const arrInfo = this.arrayVars.get(arrName);
      // Check if this is a module-level global array (not a function-local).
      const isGlobalArr = !locals.has(arrName) && this.moduleGlobals.has(arrName) &&
        this.moduleArrayVars.has(arrName);
      const globalArrInfo = isGlobalArr ? this.moduleArrayVars.get(arrName)! : null;
      const effectiveInfo = arrInfo ?? globalArrInfo;
      if (effectiveInfo?.dynamic) {
        // 2D arrays store i32 row-pointers in the outer array, regardless of element type.
        const outerElem = effectiveInfo.is2D ? "i32" : effectiveInfo.elemType;
        const isStrArr = effectiveInfo.isStringArr || outerElem === "string";
        const getExpr = isGlobalArr ? `(global.get $${arrName})` : `(local.get $${arrName})`;

        // splice(idx, count) — in-place remove N elements starting at idx
        if (method === "splice") {
          const args = this.splitArgs(argsStr);
          const idxWat = args[0]?.trim()
            ? this.emitExpr(args[0].trim(), locals, "i32")
            : "(i32.const 0)";
          const countWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, "i32")
            : "(i32.const 1)";
          // Use f64 splice (8-byte elements) for string and f64 arrays; i32 splice for 4-byte arrays
          const spliceKey = (isStrArr || outerElem === "f64" || outerElem === "i64")
            ? "splice_f64"
            : "splice_i32";
          this.dynArrHelpers.add(spliceKey);
          return `(call $__dynarr_${spliceKey} ${getExpr} ${idxWat} ${countWat})`;
        }

        // push/unshift on string arrays — need 3-param helper (arr, ptr, len)
        if ((method === "push" || method === "unshift") && isStrArr) {
          this.dynArrHelpers.add("push_string");
          const simpleResult = this.quietEmit(() => this.emitStringPtrLen(argsStr, locals));
          if (simpleResult !== "(i32.const 0) (i32.const 0)") {
            const [ptrWat, lenWat] = splitTwoWatExprs(simpleResult);
            const callExpr = `(call $__dynarr_push_string ${getExpr} ${ptrWat} ${lenWat})`;
            return isGlobalArr
              ? `(global.set $${arrName} ${callExpr})`
              : `(local.set $${arrName} ${callExpr})`;
          }
          // Complex arg (e.g. template literal) — use temp locals
          const initStr = this.emitStringAssign("__str_push", argsStr, locals);
          const callExpr =
            `(call $__dynarr_push_string ${getExpr} (local.get $__str_push_ptr) (local.get $__str_push_len))`;
          const setExpr = isGlobalArr
            ? `(global.set $${arrName} ${callExpr})`
            : `(local.set $${arrName} ${callExpr})`;
          return `${initStr}\n      ${setExpr}`;
        }

        const key = `${method}_${outerElem}`;
        const helperName = `$__dynarr_${key}`;
        this.dynArrHelpers.add(key);
        if (method === "push" || method === "unshift") {
          // Phase 19: struct literal argument — try static data first, then runtime malloc
          let valWat: string;
          const litStr = argsStr.trim();
          if (litStr.startsWith("{") && effectiveInfo.structTypeName) {
            const structPtr = this.tryAllocStructLiteralPtr(litStr, effectiveInfo.structTypeName);
            if (structPtr !== null) {
              valWat = `(i32.const ${structPtr})`;
            } else {
              // Phase 18 fix: runtime struct literal with variable field values
              valWat =
                this.emitRuntimeStructLiteral(litStr, effectiveInfo.structTypeName, locals) ??
                  this.emitExpr(argsStr, locals, outerElem);
            }
          } else {
            valWat = this.emitExpr(argsStr, locals, outerElem);
          }
          if (isGlobalArr) {
            return `(global.set $${arrName} (call ${helperName} ${getExpr} ${valWat}))`;
          }
          // Push/unshift return new arr ptr (possibly grown after realloc); update local via local.set.
          return `(local.set $${arrName} (call ${helperName} (local.get $${arrName}) ${valWat}))`;
        }
        return `(drop (call ${helperName} ${getExpr}))`;
      }
      // Phase 12: fallback — arr is an i32 local (dynamic array pointer captured from outer scope)
      if (method === "push" && locals.get(arrName) === "i32") {
        this.dynArrHelpers.add("push_i32");
        const valWat = this.emitExpr(argsStr, locals, "i32");
        return `(local.set $${arrName} (call $__dynarr_push_i32 (local.get $${arrName}) ${valWat}))`;
      }
    }

    // Phase 44: arr.length = N — set length header of dynamic array
    const arrLenAssign = line.match(/^(\w+)\.length\s*=\s*(.+?)\s*;?$/);
    if (arrLenAssign) {
      const arrNameLA = arrLenAssign[1];
      const valExprLA = arrLenAssign[2].trim();
      const arrInfoLA = this.arrayVars.get(arrNameLA);
      const isGlobalLA = this.isModuleGlobalArr(arrNameLA);
      if (arrInfoLA?.dynamic || isGlobalLA) {
        const getExpr = isGlobalLA ? `(global.get $${arrNameLA})` : `(local.get $${arrNameLA})`;
        const valWat = this.emitExpr(valExprLA, locals, "i32");
        return `(i32.store ${getExpr} ${valWat})`;
      }
    }

    // Phase 44: call through function pointer array element: arr[idx]()
    const funcPtrArrCallMatch = line.match(/^(\w+)\[(.+?)\]\s*\(\s*\)\s*;?$/);
    if (funcPtrArrCallMatch) {
      const arrNameFP = funcPtrArrCallMatch[1];
      const idxExprFP = funcPtrArrCallMatch[2];
      const arrInfoFP = this.arrayVars.get(arrNameFP) ?? this.moduleArrayVars.get(arrNameFP);
      const funcSigFP = arrInfoFP?.isFuncPtrArr;
      if (funcSigFP !== undefined) {
        const getExpr = this.isModuleGlobalArr(arrNameFP)
          ? `(global.get $${arrNameFP})`
          : `(local.get $${arrNameFP})`;
        const idxWat = this.emitArrayIndex(idxExprFP, locals);
        const elemAddr =
          `(i32.add (i32.add ${getExpr} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2)))`;
        // Trampoline dispatch: load element (closure struct ptr), then call via its stored table index
        const trampolineParams: WatType[] = ["i32" as WatType, ...funcSigFP.params];
        const trampolineTypeName = this.getOrCreateFuncType(trampolineParams, funcSigFP.result);
        return `(local.set $__fn_tmp (i32.load ${elemAddr}))\n      (call_indirect (type ${trampolineTypeName}) (local.get $__fn_tmp) (i32.load (local.get $__fn_tmp)))`;
      }
    }

    // Dynamic array callback methods (statement form): arr.forEach(fn), arr.map(fn), etc.
    // Phase 28: also every, some, findIndex
    const dynArrCallbackStmt = line.match(
      /^(\w+)\.(forEach|map|filter|find|reduce|every|some|findIndex)\s*\(([\s\S]*?)\)\s*;?$/,
    );
    if (dynArrCallbackStmt) {
      const arrName = dynArrCallbackStmt[1];
      const method = dynArrCallbackStmt[2] as string;
      const argsStr = dynArrCallbackStmt[3].trim();
      const arrInfo = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const elemType = arrInfo.elemType as WatType;
        const args = this.splitArgs(argsStr);
        const fnName = args[0]?.trim() ?? "";
        const fnIdx = this.getFuncTableIdx(fnName);
        // Normalize method name to lowercase for key/helper name consistency
        const methodLc = method.toLowerCase() as string;
        const key = `${methodLc}_${elemType}`;
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
        } else if (methodLc === "every" || methodLc === "some" || methodLc === "findindex") {
          this.getOrCreateFuncType([elemType], "i32");
        }
        if (methodLc === "reduce") {
          const initWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, elemType)
            : zeroOf(elemType);
          return `(drop (call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx}) ${initWat}))`;
        }
        return `(drop (call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx})))`;
      }
    }

    // Phase 28: Dynamic array mutator methods (statement form): arr.reverse(), arr.fill(val,...), arr.sort(fn?)
    const dynArrMutatorStmt = line.match(/^(\w+)\.(reverse|fill|sort)\s*\(([\s\S]*?)\)\s*;?$/);
    if (dynArrMutatorStmt) {
      const arrName = dynArrMutatorStmt[1];
      const method = dynArrMutatorStmt[2] as "reverse" | "fill" | "sort";
      const argsStr = dynArrMutatorStmt[3].trim();
      const arrInfo = this.arrayVars.get(arrName);
      if (arrInfo?.dynamic) {
        const elemType = arrInfo.elemType as WatType;
        if (method === "reverse") {
          const key = `reverse_${elemType}`;
          this.dynArrHelpers.add(key);
          return `(drop (call $__dynarr_${key} (local.get $${arrName})))`;
        }
        if (method === "fill") {
          const key = `fill_${elemType}`;
          this.dynArrHelpers.add(key);
          const args = this.splitArgs(argsStr);
          const valWat = args[0]?.trim()
            ? this.emitExpr(args[0].trim(), locals, elemType)
            : zeroOf(elemType);
          const startWat = args[1]?.trim()
            ? this.emitExpr(args[1].trim(), locals, "i32")
            : "(i32.const 0)";
          const endWat = args[2]?.trim()
            ? this.emitExpr(args[2].trim(), locals, "i32")
            : `(i32.load (local.get $${arrName}))`;
          return `(drop (call $__dynarr_${key} (local.get $${arrName}) ${valWat} ${startWat} ${endWat}))`;
        }
        if (method === "sort") {
          const isStrArr2 = arrInfo.isStringArr || elemType === "string";
          const args = this.splitArgs(argsStr);
          const fnName = args[0]?.trim() ?? "";
          if (fnName) {
            const key = `sortcmp_${elemType}`;
            this.dynArrHelpers.add(key);
            this.getOrCreateFuncType([elemType, elemType], "i32");
            const fnIdx = this.getFuncTableIdx(fnName);
            return `(drop (call $__dynarr_${key} (local.get $${arrName}) (i32.const ${fnIdx})))`;
          } else if (isStrArr2) {
            this.dynArrHelpers.add("sort_string");
            return `(drop (call $__dynarr_sort_string (local.get $${arrName})))`;
          } else {
            const key = `sort_${elemType}`;
            this.dynArrHelpers.add(key);
            return `(drop (call $__dynarr_sort_${elemType} (local.get $${arrName})))`;
          }
        }
      }
    }

    // Phase 31: TypedArray method statements: arr.fill(val), arr.fill(val, start), arr.fill(val, start, end)
    const taMethodStmt = line.match(/^(\w+)\.(fill|set)\s*\(([\s\S]*)\)\s*;?$/);
    if (taMethodStmt) {
      const arrName = taMethodStmt[1];
      const method = taMethodStmt[2];
      const argsStr = taMethodStmt[3].trim();
      const taInfoS = this.typedArrayVars.get(arrName);
      if (taInfoS) {
        if (method === "fill") {
          const args = this.splitArgs(argsStr);
          const val = args[0] ?? "0";
          const startArg = args[1];
          const endArg = args[2];
          const helperKey = `fill_${taInfoS.elemType}`;
          this.typedArrHelpers.add(helperKey);
          const valWat = this.emitExpr(val, locals, taInfoS.elemType);
          const startWat = startArg
            ? this.emitExpr(startArg.trim(), locals, "i32")
            : "(i32.const 0)";
          const endWat = endArg
            ? this.emitExpr(endArg.trim(), locals, "i32")
            : `(i32.load (local.get $${arrName}))`;
          return `(call $__ta_fill_${taInfoS.elemType} (local.get $${arrName}) ${valWat} ${startWat} ${endWat})`;
        }
        if (method === "set") {
          // arr.set(srcArr) — copy all elements; limited to same-type i32 arrays
          const args = this.splitArgs(argsStr);
          const srcName = args[0]?.trim() ?? "";
          const offsetArg = args[1]?.trim();
          const srcInfo = this.typedArrayVars.get(srcName) ?? this.arrayVars.get(srcName);
          if (srcInfo) {
            const helperKey = `set_${taInfoS.elemType}`;
            this.typedArrHelpers.add(helperKey);
            const offsetWat = offsetArg ? this.emitExpr(offsetArg, locals, "i32") : "(i32.const 0)";
            return `(call $__ta_set_${taInfoS.elemType} (local.get $${arrName}) (local.get $${srcName}) ${offsetWat})`;
          }
        }
      }
    }

    // Array element write: arr[idx] = val
    // Struct field write via array element: arr[idx].field = val
    const arrFieldWriteMatch = line.match(/^(\w+)\[([^\]]+)\]\.(\w+)\s*=\s*(.+?);?$/);
    if (arrFieldWriteMatch) {
      const [, arrName, idxExpr, fieldName, valExpr] = arrFieldWriteMatch;
      const arrInfo = this.arrayVars.get(arrName);
      const structTypeName = arrInfo?.structTypeName ??
        (arrInfo && arrInfo.elemType !== "f64" && arrInfo.elemType !== "i32" &&
            arrInfo.elemType !== "i64"
          ? arrInfo.elemType
          : undefined);
      if (arrInfo && structTypeName) {
        const structDef = this.structDefs.get(structTypeName);
        if (structDef) {
          const field = structDef.fields.find((f) => f.name === fieldName);
          if (field) {
            const idxWat = this.emitArrayIndex(idxExpr, locals);
            const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
              ? this.arrGetWat(arrName)
              : `(i32.const ${arrInfo.ptr})`;
            const ptrWat =
              `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
            const storeOp = field.type === "f64"
              ? "f64.store"
              : field.type === "i64"
              ? "i64.store"
              : "i32.store";
            const valWat = this.emitExpr(valExpr.trim(), locals, field.type as WatType);
            return `(${storeOp} (i32.add ${ptrWat} (i32.const ${field.offset})) ${valWat})`;
          }
        }
      }
    }

    const arrWriteMatch = line.match(/^(\w+)\s*\[(.+?)\]\s*=\s*(.+?);?$/);
    if (arrWriteMatch) {
      // Phase 23: tuple element write — t[N] = val (N must be a compile-time integer literal)
      const svW = this.structVars.get(arrWriteMatch[1]);
      if (svW && /^\d+$/.test(arrWriteMatch[2])) {
        const fieldIdx = parseInt(arrWriteMatch[2], 10);
        const field = svW.def.fields[fieldIdx];
        if (field) {
          const storeOp = field.type === "f64"
            ? "f64.store"
            : field.type === "i64"
            ? "i64.store"
            : "i32.store";
          const baseWat = svW.ptr === -1
            ? `(local.get $${arrWriteMatch[1]})`
            : `(i32.const ${svW.ptr})`;
          const valWat = this.emitExpr(arrWriteMatch[3], locals, field.type);
          return `(${storeOp} (i32.add ${baseWat} (i32.const ${field.offset})) ${valWat})`;
        }
      }
      const arrInfo = this.arrayVars.get(arrWriteMatch[1]);
      if (arrInfo) {
        // Phase 6d: 2D array write — twoD[row][col] = val (index captured as "row][col" by regex)
        if (arrInfo.is2D && arrWriteMatch[2].includes("][")) {
          const [rowRaw, colRaw] = arrWriteMatch[2].split("][");
          const rowIdxWat = this.emitArrayIndex(rowRaw, locals);
          const colIdxWat = this.emitArrayIndex(colRaw, locals);
          const storeOp2D = arrInfo.elemType === "f64"
            ? "f64.store"
            : arrInfo.elemType === "i64"
            ? "i64.store"
            : "i32.store";
          const shift2D = (arrInfo.elemType === "f64" || arrInfo.elemType === "i64") ? 3 : 2;
          const rowPtrWat = `(i32.load (i32.add (i32.add ${
            this.arrGetWat(arrWriteMatch[1])
          } (i32.const 8)) (i32.shl ${rowIdxWat} (i32.const 2))))`;
          const valWat2D = this.emitExpr(arrWriteMatch[3], locals, arrInfo.elemType);
          return `(${storeOp2D} (i32.add (i32.add ${rowPtrWat} (i32.const 8)) (i32.shl ${colIdxWat} (i32.const ${shift2D}))) ${valWat2D})`;
        }
        // String array element write: arr[idx] = "str" — store ptr+len at 8-byte slot
        if (arrInfo.isStringArr || arrInfo.elemType === "string") {
          const idxWat = this.emitArrayIndex(arrWriteMatch[2], locals);
          const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
            ? this.arrGetWat(arrWriteMatch[1])
            : `(i32.const ${arrInfo.ptr})`;
          const elemAddrWat =
            `(i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 3)))`;
          const ptrLen = this.emitStringPtrLen(arrWriteMatch[3].trim(), locals);
          const [ptrWat, lenWat] = splitTwoWatExprs(ptrLen);
          return `(i32.store ${elemAddrWat} ${ptrWat})\n      (i32.store offset=4 ${elemAddrWat} ${lenWat})`;
        }
        const storeOp = arrInfo.elemType === "f64"
          ? "f64.store"
          : arrInfo.elemType === "i64"
          ? "i64.store"
          : "i32.store";
        const shift = (arrInfo.elemType === "f64" || arrInfo.elemType === "i64") ? 3 : 2;
        const idxWat = this.emitArrayIndex(arrWriteMatch[2], locals);
        // Phase 19: struct literal RHS — allocate in static data section and store its pointer
        let valWat: string;
        const valStr3 = arrWriteMatch[3].trim();
        if (valStr3.startsWith("{") && arrInfo.structTypeName) {
          const structPtr = this.tryAllocStructLiteralPtr(valStr3, arrInfo.structTypeName);
          valWat = structPtr !== null
            ? `(i32.const ${structPtr})`
            : this.emitExpr(valStr3, locals, arrInfo.elemType);
        } else {
          valWat = this.emitExpr(arrWriteMatch[3], locals, arrInfo.elemType);
        }
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? this.arrGetWat(arrWriteMatch[1])
          : `(i32.const ${arrInfo.ptr})`;
        const dataBase = `(i32.add ${baseWat} (i32.const 8))`;
        return `(${storeOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))) ${valWat})`;
      }
      // Phase 31: TypedArray element write: arr[idx] = val
      const taInfoW = this.typedArrayVars.get(arrWriteMatch[1]);
      if (taInfoW) {
        const idxWat = this.emitArrayIndex(arrWriteMatch[2], locals);
        const valWat = this.emitExpr(arrWriteMatch[3], locals, taInfoW.elemType);
        const addrWat = taInfoW.shift === 0
          ? `(i32.add (i32.add (local.get $${arrWriteMatch[1]}) (i32.const 8)) ${idxWat})`
          : `(i32.add (i32.add (local.get $${
            arrWriteMatch[1]
          }) (i32.const 8)) (i32.shl ${idxWat} (i32.const ${taInfoW.shift})))`;
        return `(${taInfoW.storeOp} ${addrWat} ${valWat})`;
      }
    }

    // Simple assignment (no let/const)
    // Reassignment to a mutable module-level string global: message = expr (target not a local).
    // emitStringAssign's wrapper rewrites the ptr/len local.set into global.set.
    const strGlobAssign = line.match(/^(\w+)\s*=\s*(.+?);?$/);
    if (
      strGlobAssign && this.moduleStringGlobals.has(strGlobAssign[1]) &&
      !locals.has(strGlobAssign[1])
    ) {
      return this.emitStringAssign(strGlobAssign[1], strGlobAssign[2].trim(), locals);
    }

    const assignMatch = line.match(/^(\w+)\s*=\s*(.+?);?$/);
    if (
      assignMatch &&
      (locals.has(assignMatch[1]) || this.currentClosureCaptureLayout.has(assignMatch[1]))
    ) {
      const varName = assignMatch[1];
      if (locals.get(varName) === "string") {
        return this.emitStringAssign(varName, assignMatch[2].trim(), locals);
      }
      // Phase 24: nullable reassignment — x = null or x = value
      const nlReassignInner = this.nullableVarInnerType.get(varName);
      if (nlReassignInner) {
        const rhs = assignMatch[2].trim();
        if (rhs === "null" || rhs === "undefined") {
          return `(local.set $${varName}__null (i32.const 1))`;
        }
        const nlFnCallM = rhs.match(/^(\w+)\s*\(/);
        const nlCalledFn = nlFnCallM ? this.functions.find((f) => f.name === nlFnCallM[1]) : null;
        const valWat = this.emitExpr(rhs, locals, nlReassignInner);
        if (nlCalledFn && this.nullableFuncReturnType.has(nlCalledFn.name)) {
          return `(local.set $${varName} ${valWat})\n      (local.set $${varName}__null (i32.eqz (global.get $__nullable_ret_flag)))`;
        }
        return `(local.set $${varName} ${valWat})\n      (local.set $${varName}__null (i32.const 0))`;
      }
      const varType = locals.get(varName)!;
      // Phase 5h: boxed capture — store through heap pointer
      if (this.currentBoxedCaptures.has(varName)) {
        return `(i32.store (local.get $${varName}) ${
          this.emitExpr(assignMatch[2].trim(), locals, "i32")
        })`;
      }
      // Mutable closure capture — store through $__closure_ptr
      {
        const ccl = this.currentClosureCaptureLayout.get(varName);
        if (ccl) {
          const storeOp = ccl.type === "f64"
            ? "f64.store"
            : ccl.type === "i64"
            ? "i64.store"
            : "i32.store";
          return `(${storeOp} offset=${ccl.offset} (local.get $__closure_ptr) ${
            this.emitExpr(assignMatch[2].trim(), locals, ccl.type)
          })`;
        }
      }
      return `(local.set $${varName} ${this.emitExpr(assignMatch[2].trim(), locals, varType)})`;
    }
    // Simple assignment to module global
    if (assignMatch && this.moduleGlobals.has(assignMatch[1])) {
      const varName = assignMatch[1];
      const gInfo = this.moduleGlobals.get(varName)!;
      return `(global.set $${varName} ${this.emitExpr(assignMatch[2].trim(), locals, gInfo.type)})`;
    }

    // console.log() with no arguments — emit a bare newline
    if (/^console\.log\s*\(\s*\)\s*;?$/.test(line)) {
      this.hasConsoleLog = true;
      const sb = this.scratchBase;
      return [
        `    (i32.store8 (i32.const ${sb}) (i32.const 10))`,
        `    (i32.store (i32.const ${this.iovBase}) (i32.const ${sb}))`,
        `    (i32.store (i32.const ${this.iovBase + 4}) (i32.const 1))`,
        `    (drop (call $fd_write (i32.const 1) (i32.const ${this.iovBase}) (i32.const 1) (i32.const ${
          this.iovBase + 128
        })))`,
      ].join("\n");
    }

    // console.log(...) — delegate to console_log.ts for full argument support
    const logMatch = line.match(/^console\.log\s*\((.+)\)\s*;?$/);
    if (logMatch) {
      this.hasConsoleLog = true;
      // Phase 6d: console.log of a 2D i32 array variable → call $__print_2d_i32_arr helper
      const log2DArg = logMatch[1].trim();
      const log2DInfo = this.arrayVars.get(log2DArg);
      if (log2DInfo?.is2D && log2DInfo.elemType === "i32") {
        this.needsMatrix2DPrintHelper = true;
        this.needsNumericHelpers = true;
        const sb = this.scratchBase;
        return [
          `    (i32.store (i32.const ${this.iovBase}) (i32.const ${sb}))`,
          `    (i32.store (i32.const ${
            this.iovBase + 4
          }) (call $__print_2d_i32_arr (local.get $${log2DArg}) (i32.const ${sb})))`,
          `    (i32.store8 (i32.add (i32.const ${sb}) (i32.load (i32.const ${
            this.iovBase + 4
          }))) (i32.const 10))`,
          `    (i32.store (i32.const ${this.iovBase + 4}) (i32.add (i32.load (i32.const ${
            this.iovBase + 4
          })) (i32.const 1)))`,
          `    (drop (call $fd_write (i32.const 1) (i32.const ${this.iovBase}) (i32.const 1) (i32.const ${
            this.iovBase + 128
          })))`,
        ].join("\n");
      }
      // Phase 31: console.log of a TypedArray variable → print "TypedArrayName(len) [ ... ]"
      const logSingleArgRaw = logMatch[1].trim();
      const taInfoLog = this.typedArrayVars.get(logSingleArgRaw);
      if (taInfoLog) {
        this.needsArrPrintHelper = true;
        this.needsNumericHelpers = true;
        const lenWat = `(i32.load (local.get $${logSingleArgRaw}))`;
        const ptrWat = `(local.get $${logSingleArgRaw})`;
        const segments: LogSegment[] = [
          { kind: "literal", text: `${taInfoLog.taType}(` },
          { kind: "i32expr", wat: lenWat },
          { kind: "literal", text: ") " },
          { kind: "arrptr", wat: ptrWat, elemType: taInfoLog.elemType === "f64" ? "f64" : "i32" },
          { kind: "literal", text: "\n" },
        ];
        const { statements: taStmts, needsStrGather: taSG } = emitConsoleLog(
          segments,
          (text) => this.allocString(text),
          "    ",
          1,
          this.iovBase,
          this.scratchBase,
        );
        if (taSG) this.needsStrGatherHelper = true;
        return taStmts.join("\n      ");
      }
      // Phase 13b: console.log(structReturningFn(...)) → print { field: val, ... }
      const logSingleArg = logMatch[1].trim();
      // Guard: skip if this is a chained method call like funcCall().method() — those return
      // a scalar, not a struct, and should fall through to the general emitExpr path.
      const structFnCallMatch = !logSingleArg.includes(").")
        ? logSingleArg.match(/^(\w+)\s*\((.*)\)$/)
        : null;
      if (structFnCallMatch) {
        const callee = this.functions.find((f) => f.name === structFnCallMatch[1]);
        if (callee?.resultTsName && this.structDefs.has(callee.resultTsName)) {
          const structDef = this.structDefs.get(callee.resultTsName)!;
          const callWat = this.emitExpr(logSingleArg, locals, "i32");
          const ptrStmt = `    (local.set $__struct_tmp ${callWat})`;
          const segments: LogSegment[] = [{ kind: "literal", text: "{ " }];
          for (let fi = 0; fi < structDef.fields.length; fi++) {
            const field = structDef.fields[fi];
            if (fi > 0) segments.push({ kind: "literal", text: ", " });
            segments.push({ kind: "literal", text: `${field.name}: ` });
            const loadOp = field.type === "f64"
              ? "f64.load"
              : field.type === "i64"
              ? "i64.load"
              : "i32.load";
            const kind = field.type === "f64"
              ? "f64expr" as const
              : field.type === "i64"
              ? "i64expr" as const
              : "i32expr" as const;
            segments.push({
              kind,
              wat: `(${loadOp} offset=${field.offset} (local.get $__struct_tmp))`,
            });
          }
          segments.push({ kind: "literal", text: " }\n" });
          this.needsNumericHelpers = true;
          const { statements, needsStrGather, needsArrPrintHelper, needsJoinHelper } =
            emitConsoleLog(
              segments,
              (text) => this.allocString(text),
              "    ",
              1,
              this.iovBase,
              this.scratchBase,
            );
          if (needsStrGather) this.needsStrGatherHelper = true;
          if (needsArrPrintHelper) this.needsArrPrintHelper = true;
          if (needsJoinHelper) this.needsJoinHelper = true;
          return [ptrStmt, ...statements].join("\n      ");
        }
      }
      // find() result variable: print "undefined" when sentinel (-1 for i32, NaN for f64),
      // matching TypeScript's Array.find() semantics for the not-found case.
      if (this.findResultVars.has(logSingleArg)) {
        const varType = locals.get(logSingleArg);
        this.needsNumericHelpers = true;
        const [undefOffset, undefLen] = this.allocString("undefined\n");
        const isFindF64 = varType === "f64";
        const cond = isFindF64
          ? `(f64.ne (local.get $${logSingleArg}) (local.get $${logSingleArg}))` // NaN != NaN
          : `(i32.eq (local.get $${logSingleArg}) (i32.const -1))`;
        const normalSegs: LogSegment[] = isFindF64
          ? [{ kind: "f64var" as const, name: logSingleArg }, {
            kind: "literal" as const,
            text: "\n",
          }]
          : [{ kind: "i32var" as const, name: logSingleArg }, {
            kind: "literal" as const,
            text: "\n",
          }];
        const {
          statements: normalStmts,
          needsStrGather: nsg,
          needsArrPrintHelper: naph,
          needsJoinHelper: njh,
        } = emitConsoleLog(
          normalSegs,
          (text) => this.allocString(text),
          "      ",
          1,
          this.iovBase,
          this.scratchBase,
        );
        if (nsg) this.needsStrGatherHelper = true;
        if (naph) this.needsArrPrintHelper = true;
        if (njh) this.needsJoinHelper = true;
        return [
          `    (if ${cond}`,
          `      (then`,
          `        (i32.store (i32.const ${this.iovBase}) (i32.const ${undefOffset}))`,
          `        (i32.store (i32.const ${this.iovBase + 4}) (i32.const ${undefLen}))`,
          `        (drop (call $fd_write (i32.const 1) (i32.const ${this.iovBase}) (i32.const 1) (i32.const ${
            this.iovBase + 128
          })))`,
          `      )`,
          `      (else`,
          ...normalStmts.map((s) => `  ${s}`),
          `      )`,
          `    )`,
        ].join("\n");
      }
      // Phase 24: nullable variable — print "null" when flag is set, else print value
      if (this.nullableVarInnerType.has(logSingleArg)) {
        const nlInner = this.nullableVarInnerType.get(logSingleArg)!;
        this.needsNumericHelpers = true;
        const [nullOffset, nullLen] = this.allocString("null\n");
        const isF64 = nlInner === "f64";
        const normalSegs: LogSegment[] = isF64
          ? [{ kind: "f64var" as const, name: logSingleArg }, {
            kind: "literal" as const,
            text: "\n",
          }]
          : [{ kind: "i32var" as const, name: logSingleArg }, {
            kind: "literal" as const,
            text: "\n",
          }];
        const {
          statements: normalStmts,
          needsStrGather: nsg2,
          needsArrPrintHelper: naph2,
          needsJoinHelper: njh2,
        } = emitConsoleLog(
          normalSegs,
          (text) => this.allocString(text),
          "      ",
          1,
          this.iovBase,
          this.scratchBase,
        );
        if (nsg2) this.needsStrGatherHelper = true;
        if (naph2) this.needsArrPrintHelper = true;
        if (njh2) this.needsJoinHelper = true;
        return [
          `    (if (local.get $${logSingleArg}__null)`,
          `      (then`,
          `        (i32.store (i32.const ${this.iovBase}) (i32.const ${nullOffset}))`,
          `        (i32.store (i32.const ${this.iovBase + 4}) (i32.const ${nullLen}))`,
          `        (drop (call $fd_write (i32.const 1) (i32.const ${this.iovBase}) (i32.const 1) (i32.const ${
            this.iovBase + 128
          })))`,
          `      )`,
          `      (else`,
          ...normalStmts.map((s) => `  ${s}`),
          `      )`,
          `    )`,
        ].join("\n");
      }
      // Phase 5h: chained call console.log(factoryFn().method()) — parseSingleArg cannot handle
      // these (callMatch greedily mis-parses the args), so emit directly as i32.
      if (logSingleArg.match(/^(\w+)\s*\(.*\)\.(\w+)\s*\(.*\)$/)) {
        const chainedWat = this.quietEmit(() => this.emitExpr(logSingleArg, locals, "i32"));
        if (!chainedWat.startsWith("(;?") && chainedWat !== "(unreachable)") {
          this.needsNumericHelpers = true;
          const chainedSegs: LogSegment[] = [
            { kind: "i32expr" as const, wat: chainedWat },
            { kind: "literal" as const, text: "\n" },
          ];
          const {
            statements: cs,
            needsStrGather: csg,
            needsArrPrintHelper: caph,
            needsJoinHelper: cjh,
          } = emitConsoleLog(
            chainedSegs,
            (text) => this.allocString(text),
            "    ",
            1,
            this.iovBase,
            this.scratchBase,
          );
          if (csg) this.needsStrGatherHelper = true;
          if (caph) this.needsArrPrintHelper = true;
          if (cjh) this.needsJoinHelper = true;
          return cs.join("\n      ");
        }
      }
      const allocator: DataAllocator = (text) => this.allocString(text);
      const lookup: FuncLookup = (name) => this.functions.find((f) => f.name === name);
      const enumLookup = (key: string) => this.enumValues.get(key);
      const enumStringLookupFn = (key: string) => this.enumStringValues.get(key);
      const arrayLookupFn = (name: string) => {
        const av = this.arrayVars.get(name);
        if (av) {
          return {
            ...av,
            isGlobal: this.moduleGlobals.has(name) && this.moduleArrayVars.has(name),
          };
        }
        const ta = this.typedArrayVars.get(name);
        if (ta) {
          return {
            elemType: ta.elemType,
            ptr: -2 as const,
            length: ta.length,
            dynamic: true as const,
            shift: ta.shift,
            customLoadOp: ta.loadOp,
          };
        }
        return undefined;
      };
      // Pre-register any Math helpers used inside console.log args so they are
      // emitted even when the call only appears inside console.log (not in emitExpr).
      if (logMatch[1].includes("Math.")) {
        this.mathHelpers.add("math_pow");
        if (
          /Math\.(?:sin|cos|tan|asin|acos|atan|log|log2|log10|exp|cbrt|sinh|cosh|tanh|asinh|acosh|atanh|expm1|log1p|random)/
            .test(logMatch[1])
        ) {
          this.needsMathLib38 = true;
        }
      }
      const structLookupFn: StructFieldLookup = (vn, fn) => {
        // Phase 9 / 47: `this.field` access inside a class instance method body
        if (vn === "this" && this.currentMethodClass) {
          const cd = this.classDefs.get(this.currentMethodClass);
          const f = cd?.struct.fields.find((fi) => fi.name === fn);
          if (f) {
            const loadOp = f.type === "f64"
              ? "f64.load"
              : f.type === "i64"
              ? "i64.load"
              : "i32.load";
            return {
              type: f.type,
              watLoad: `(${loadOp} (i32.add (local.get $__self) (i32.const ${f.offset})))`,
            };
          }
          const getter = cd?.methods.find((m) => m.isGetter && m.name === fn);
          if (getter) {
            const getFn = this.functions.find((gf) =>
              gf.name === `${this.currentMethodClass}_get_${fn}`
            );
            return {
              type: getFn?.result ?? "f64",
              watLoad: `(call $${this.currentMethodClass}_get_${fn} (local.get $__self))`,
            };
          }
        }
        // Phase 42: dotted vn = "a.b" — look up field fn on the struct pointed to by a.b
        if (vn.includes(".")) {
          const dotIdx = vn.indexOf(".");
          const outerVarName = vn.slice(0, dotIdx);
          const outerFieldName = vn.slice(dotIdx + 1);
          const outerSv = this.structVars.get(outerVarName);
          if (outerSv) {
            const outerField = outerSv.def.fields.find((f) => f.name === outerFieldName);
            if (outerField?.structType) {
              const innerDef = this.structDefs.get(outerField.structType);
              const innerField = innerDef?.fields.find((fi) => fi.name === fn);
              if (innerField) {
                const outerBaseWat = outerSv.ptr < 0
                  ? `(local.get $${outerVarName})`
                  : `(i32.const ${outerSv.ptr})`;
                const outerPtrWat =
                  `(i32.load (i32.add ${outerBaseWat} (i32.const ${outerField.offset})))`;
                // String leaf field: 8-byte [ptr, len] at innerField.offset — return both so
                // console.log prints the string, not the raw pointer (mirrors the top-level path).
                if (innerField.type === "string") {
                  return {
                    type: "string",
                    watLoad: `(i32.load offset=${innerField.offset} ${outerPtrWat})`,
                    watLoadLen: `(i32.load offset=${innerField.offset + 4} ${outerPtrWat})`,
                  };
                }
                const innerLoadOp = innerField.type === "f64"
                  ? "f64.load"
                  : innerField.type === "i64"
                  ? "i64.load"
                  : "i32.load";
                return {
                  type: innerField.type,
                  watLoad:
                    `(${innerLoadOp} (i32.add ${outerPtrWat} (i32.const ${innerField.offset})))`,
                };
              }
            }
          }
          return undefined;
        }
        // Array element struct field access: arr[idx].field (virtual vn = "arr[idx]")
        const bracketVnMatch = vn.match(/^(\w+)\[([^\]]*)\]$/);
        if (bracketVnMatch) {
          const arrName = bracketVnMatch[1];
          const idxExpr = bracketVnMatch[2];
          const arrInfo = this.arrayVars.get(arrName);
          const structTypeNameBV = arrInfo?.structTypeName;
          const structDefBV = structTypeNameBV ? this.structDefs.get(structTypeNameBV) : undefined;
          if (arrInfo && structDefBV) {
            const field = structDefBV.fields.find((f) => f.name === fn);
            if (field) {
              const idxWat = this.emitArrayIndex(idxExpr, locals);
              const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
                ? this.arrGetWat(arrName)
                : `(i32.const ${arrInfo.ptr})`;
              const ptrWat =
                `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
              const loadOp = field.type === "f64"
                ? "f64.load"
                : field.type === "i64"
                ? "i64.load"
                : "i32.load";
              return {
                type: field.type,
                watLoad: `(${loadOp} (i32.add ${ptrWat} (i32.const ${field.offset})))`,
              };
            }
          }
          return undefined;
        }
        // Check class instance vars first
        const cv = this.classVars.get(vn);
        if (cv) {
          const cd = this.classDefs.get(cv.className);
          const f = cd?.struct.fields.find((fi) => fi.name === fn);
          if (f) {
            if (f.type === "string") {
              const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
              return {
                type: "string",
                watLoad: `(i32.load offset=${f.offset} ${baseWat})`,
                watLoadLen: `(i32.load offset=${f.offset + 4} ${baseWat})`,
              };
            }
            const loadOp = f.type === "f64"
              ? "f64.load"
              : f.type === "i64"
              ? "i64.load"
              : "i32.load";
            const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return {
              type: f.type,
              watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))`,
            };
          }
          // Phase 29: getter dispatch
          const getter = cd?.methods.find((m) => m.isGetter && m.name === fn);
          if (getter) {
            const getFuncName = `${cv.className}_get_${fn}`;
            const getFn = this.functions.find((gf) => gf.name === getFuncName);
            const retType = getFn?.result ?? "f64";
            const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return { type: retType, watLoad: `(call $${getFuncName} ${baseWat})` };
          }
        }
        // Phase 29: static field — ClassName.fieldName → (global.get $ClassName_fieldName)
        const staticCd = this.classDefs.get(vn);
        if (staticCd) {
          const globalKey = `${vn}_${fn}`;
          const gInfo = this.moduleGlobals.get(globalKey);
          if (gInfo) {
            const gType = watBaseType(gInfo.type);
            return { type: gType, watLoad: `(global.get $${globalKey})` };
          }
        }
        // Phase 30: namespace constant — Namespace.constName
        if (this.namespaceDefs.has(vn)) {
          const globalKey = `${vn}_${fn}`;
          const gInfo = this.moduleGlobals.get(globalKey);
          if (gInfo) {
            const gType = watBaseType(gInfo.type);
            return { type: gType, watLoad: `(global.get $${globalKey})` };
          }
        }
        // Phase 31: TypedArray .length and .byteLength properties
        const taInfoSL = this.typedArrayVars.get(vn);
        if (taInfoSL) {
          if (fn === "length") return { type: "i32", watLoad: `(i32.load (local.get $${vn}))` };
          if (fn === "byteLength") {
            const lenW = `(i32.load (local.get $${vn}))`;
            return {
              type: "i32",
              watLoad: taInfoSL.shift === 0
                ? lenW
                : `(i32.shl ${lenW} (i32.const ${taInfoSL.shift}))`,
            };
          }
        }
        const sv = this.structVars.get(vn);
        if (!sv) return undefined;
        const f = sv.def.fields.find((fi) => fi.name === fn);
        if (!f) return undefined;
        if (f.type === "string") {
          const baseWat = sv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
          return {
            type: "string",
            watLoad: `(i32.load offset=${f.offset} ${baseWat})`,
            watLoadLen: `(i32.load offset=${f.offset + 4} ${baseWat})`,
          };
        }
        const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
        const baseWat = sv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
        return {
          type: f.type,
          watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))`,
        };
      };
      const dotCallLookupFn: DotCallLookup = (token) => {
        const result = this.quietEmit(() => this.emitExpr(token, locals, "i32"));
        if (result === "(unreachable)" || result.startsWith("(;?")) return undefined;
        // Determine return type from the expression
        // Phase 47: arr[idx].method(args) — resolve the element class's method return type
        // so console.log formats the result correctly (emitExpr already does vtable dispatch).
        const amc = token.match(/^(\w+)\[([^\]]*)\]\.(\w+)\s*\(/);
        if (amc) {
          const aInfo = this.arrayVars.get(amc[1]!);
          const stn = aInfo?.structTypeName ??
            (aInfo && aInfo.elemType !== "f64" && aInfo.elemType !== "i32" &&
                aInfo.elemType !== "i64"
              ? aInfo.elemType
              : undefined);
          if (stn && this.classDefs.has(stn)) {
            const mfn = this.resolveMethodFunc(stn, amc[3]!);
            const mdef = mfn ? this.functions.find((f) => f.name === mfn) : undefined;
            const retType = (mdef?.result ?? "i32") as WatType;
            return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
          }
        }
        const m2 = token.match(/^(?:this|\w+)\.(\w+)\s*\(/);
        if (m2) {
          const receiver2 = token.match(/^(\w+)\./)?.[1] ?? "";
          const methodName2 = m2[1];
          const cv2 = receiver2 === "this" ? null : this.classVars.get(receiver2);
          const className2 = receiver2 === "this" ? this.currentMethodClass : cv2?.className;
          const cd2 = className2 ? this.classDefs.get(className2) : null;
          const method2 = cd2?.methods.find((mm) => mm.name === methodName2);
          if (method2) {
            const fn2 = this.functions.find((f) => f.name === `${className2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Static method
          const staticCd = this.classDefs.get(receiver2);
          if (staticCd) {
            const fn2 = this.functions.find((f) => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Phase 30: namespace function call
          if (this.namespaceDefs.has(receiver2)) {
            const fn2 = this.functions.find((f) => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Phase 5h/12: interface method dispatch (counter1.inc() etc.)
          const ifaceName2 = this.interfaceVars.get(receiver2);
          if (ifaceName2) {
            const field2 = this.structDefs.get(ifaceName2)?.fields.find((f) =>
              f.name === methodName2
            );
            if (field2?.funcType) {
              return { type: (field2.funcType.result ?? "i32") as string, wat: result };
            }
          }
          // Boolean-returning array methods: every, some, includes
          if (
            ["every", "some", "includes"].includes(methodName2) && this.arrayVars.has(receiver2)
          ) {
            return { type: "bool", wat: result };
          }
        }
        // Phase 5h: emitExpr succeeded (e.g. chained factoryFn().method()) — return as i32
        return { type: "i32", wat: result };
      };
      const globalsMap: Map<string, string> = new Map(
        [...this.moduleGlobals.entries()].map(([k, v]) => [k, watBaseType(v.type)]),
      );
      // Add module string consts encoded as "string:offset:len" so parseSingleArg can look them up
      for (const [k, [offset, len]] of this.moduleStringConsts) {
        globalsMap.set(k, `string:${offset}:${len}`);
      }
      // Add mutable module string globals encoded as "strglobal:name"
      for (const k of this.moduleStringGlobals.keys()) {
        globalsMap.set(k, `strglobal:${k}`);
      }
      const closureVarLookupFn: ClosureVarLookup = (name) => {
        const sig = this.closureTypedVars.get(name);
        if (!sig) return undefined;
        const trampolineParams: WatType[] = ["i32" as WatType, ...sig.params as WatType[]];
        const trampolineResult = sig.result === "string" ? null : sig.result;
        const funcType = this.getOrCreateFuncType(trampolineParams, trampolineResult);
        return { params: sig.params as string[], result: sig.result, funcType };
      };
      setStringArrayAllocator((elems) => this.allocArrayData(elems, "string"));
      setStructLiteralAllocator((sName, fields) =>
        this.allocStructData(this.structDefs.get(sName)!, fields)
      );
      setStrCmpNeededCallback(() => {
        this.needsStringHelpers = true;
      });
      setFuncTableLookup((name) =>
        this.functions.find((f) => f.name === name) ? this.getFuncTableIdx(name) : undefined
      );
      setInstanceofResolver((tok, locs) => {
        const m = tok.match(/^\w+\s+instanceof\s+(\w+)$/);
        if (!m || !this.classDefs.has(m[1]!)) return undefined;
        return this.emitExpr(tok, locs as Map<string, WatType>, "i32");
      });
      // String-producing method calls (s.toUpperCase(), arr[i].toLowerCase(), …): resolve to a
      // ptr/len pair via emitStringPtrLen, captured into $__str_op_len (ptrWat runs the call and
      // leaves ptr; lenWat reads the captured len — both consumers evaluate ptrWat first).
      setStringExprResolver((tok, locs) => {
        const w = this.quietEmit(() => this.emitStringPtrLen(tok, locs as Map<string, WatType>));
        if (w === "(i32.const 0) (i32.const 0)") return undefined;
        return {
          ptrWat: `(block (result i32) ${w} (local.set $__str_op_len))`,
          lenWat: `(local.get $__str_op_len)`,
        };
      });
      const segments = parseConsoleLogArgs(
        logMatch[1],
        locals as Map<string, string>,
        lookup,
        allocator,
        enumLookup,
        arrayLookupFn,
        structLookupFn,
        dotCallLookupFn,
        globalsMap,
        enumStringLookupFn,
        closureVarLookupFn,
      );
      setStringArrayAllocator(undefined);
      setStructLiteralAllocator(undefined);
      setStrCmpNeededCallback(undefined);
      setFuncTableLookup(undefined);
      setInstanceofResolver(undefined);
      setStringExprResolver(undefined);
      const { statements, needsHelpers, needsStrGather, needsArrPrintHelper, needsJoinHelper } =
        emitConsoleLog(segments, allocator, "    ", 1, this.iovBase, this.scratchBase);
      if (needsHelpers) this.needsNumericHelpers = true;
      if (needsStrGather) this.needsStrGatherHelper = true;
      if (needsArrPrintHelper) this.needsArrPrintHelper = true;
      if (needsJoinHelper) this.needsJoinHelper = true;
      return statements.join("\n      ");
    }

    // console.error(...) / console.warn(...) — same pipeline as console.log but fd=2 (stderr)
    const errMatch = line.match(/^console\.(error|warn)\s*\((.+)\)\s*;?$/);
    if (errMatch) {
      this.hasConsoleLog = true;
      const allocator: DataAllocator = (text) => this.allocString(text);
      const lookup: FuncLookup = (name) => this.functions.find((f) => f.name === name);
      const enumLookup = (key: string) => this.enumValues.get(key);
      const enumStringLookupFnErr = (key: string) => this.enumStringValues.get(key);
      const arrayLookupFn = (name: string) => {
        const av = this.arrayVars.get(name);
        if (av) {
          return {
            ...av,
            isGlobal: this.moduleGlobals.has(name) && this.moduleArrayVars.has(name),
          };
        }
        const ta = this.typedArrayVars.get(name);
        if (ta) {
          return {
            elemType: ta.elemType,
            ptr: -2 as const,
            length: ta.length,
            dynamic: true as const,
            shift: ta.shift,
            customLoadOp: ta.loadOp,
          };
        }
        return undefined;
      };
      if (errMatch[2].includes("Math.")) {
        this.mathHelpers.add("math_pow");
        if (
          /Math\.(?:sin|cos|tan|asin|acos|atan|log|log2|log10|exp|cbrt|sinh|cosh|tanh|asinh|acosh|atanh|expm1|log1p|random)/
            .test(errMatch[2])
        ) {
          this.needsMathLib38 = true;
        }
      }
      const structLookupFn: StructFieldLookup = (vn, fn) => {
        // Phase 9 / 47: `this.field` access inside a class instance method body
        if (vn === "this" && this.currentMethodClass) {
          const cd = this.classDefs.get(this.currentMethodClass);
          const f = cd?.struct.fields.find((fi) => fi.name === fn);
          if (f) {
            const loadOp = f.type === "f64"
              ? "f64.load"
              : f.type === "i64"
              ? "i64.load"
              : "i32.load";
            return {
              type: f.type,
              watLoad: `(${loadOp} (i32.add (local.get $__self) (i32.const ${f.offset})))`,
            };
          }
          const getter = cd?.methods.find((m) => m.isGetter && m.name === fn);
          if (getter) {
            const getFn = this.functions.find((gf) =>
              gf.name === `${this.currentMethodClass}_get_${fn}`
            );
            return {
              type: getFn?.result ?? "f64",
              watLoad: `(call $${this.currentMethodClass}_get_${fn} (local.get $__self))`,
            };
          }
        }
        // Phase 42: dotted vn = "a.b" — look up field fn on the struct pointed to by a.b
        if (vn.includes(".")) {
          const dotIdx = vn.indexOf(".");
          const outerVarName = vn.slice(0, dotIdx);
          const outerFieldName = vn.slice(dotIdx + 1);
          const outerSv = this.structVars.get(outerVarName);
          if (outerSv) {
            const outerField = outerSv.def.fields.find((f) => f.name === outerFieldName);
            if (outerField?.structType) {
              const innerDef = this.structDefs.get(outerField.structType);
              const innerField = innerDef?.fields.find((fi) => fi.name === fn);
              if (innerField) {
                const outerBaseWat = outerSv.ptr < 0
                  ? `(local.get $${outerVarName})`
                  : `(i32.const ${outerSv.ptr})`;
                const outerPtrWat =
                  `(i32.load (i32.add ${outerBaseWat} (i32.const ${outerField.offset})))`;
                // String leaf field: 8-byte [ptr, len] at innerField.offset — return both so
                // console.log prints the string, not the raw pointer (mirrors the top-level path).
                if (innerField.type === "string") {
                  return {
                    type: "string",
                    watLoad: `(i32.load offset=${innerField.offset} ${outerPtrWat})`,
                    watLoadLen: `(i32.load offset=${innerField.offset + 4} ${outerPtrWat})`,
                  };
                }
                const innerLoadOp = innerField.type === "f64"
                  ? "f64.load"
                  : innerField.type === "i64"
                  ? "i64.load"
                  : "i32.load";
                return {
                  type: innerField.type,
                  watLoad:
                    `(${innerLoadOp} (i32.add ${outerPtrWat} (i32.const ${innerField.offset})))`,
                };
              }
            }
          }
          return undefined;
        }
        // Array element struct field access: arr[idx].field (virtual vn = "arr[idx]")
        const bracketVnMatchE = vn.match(/^(\w+)\[([^\]]*)\]$/);
        if (bracketVnMatchE) {
          const arrNameE = bracketVnMatchE[1];
          const idxExprE = bracketVnMatchE[2];
          const arrInfoE = this.arrayVars.get(arrNameE);
          const structTypeNameE = arrInfoE?.structTypeName;
          const structDefE = structTypeNameE ? this.structDefs.get(structTypeNameE) : undefined;
          if (arrInfoE && structDefE) {
            const field = structDefE.fields.find((f) => f.name === fn);
            if (field) {
              const idxWat = this.emitArrayIndex(idxExprE, locals);
              const baseWat = (arrInfoE.ptr === -1 || arrInfoE.dynamic)
                ? this.arrGetWat(arrNameE)
                : `(i32.const ${arrInfoE.ptr})`;
              const ptrWat =
                `(i32.load (i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`;
              const loadOp = field.type === "f64"
                ? "f64.load"
                : field.type === "i64"
                ? "i64.load"
                : "i32.load";
              return {
                type: field.type,
                watLoad: `(${loadOp} (i32.add ${ptrWat} (i32.const ${field.offset})))`,
              };
            }
          }
          return undefined;
        }
        // Check class instance vars first
        const cv = this.classVars.get(vn);
        if (cv) {
          const cd = this.classDefs.get(cv.className);
          const f = cd?.struct.fields.find((fi) => fi.name === fn);
          if (f) {
            if (f.type === "string") {
              const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
              return {
                type: "string",
                watLoad: `(i32.load offset=${f.offset} ${baseWat})`,
                watLoadLen: `(i32.load offset=${f.offset + 4} ${baseWat})`,
              };
            }
            const loadOp = f.type === "f64"
              ? "f64.load"
              : f.type === "i64"
              ? "i64.load"
              : "i32.load";
            const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return {
              type: f.type,
              watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))`,
            };
          }
          // Phase 29: getter dispatch
          const getter = cd?.methods.find((m) => m.isGetter && m.name === fn);
          if (getter) {
            const getFuncName = `${cv.className}_get_${fn}`;
            const getFn = this.functions.find((gf) => gf.name === getFuncName);
            const retType = getFn?.result ?? "f64";
            const baseWat = cv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${cv.ptr})`;
            return { type: retType, watLoad: `(call $${getFuncName} ${baseWat})` };
          }
        }
        // Phase 29: static field — ClassName.fieldName → (global.get $ClassName_fieldName)
        const staticCd = this.classDefs.get(vn);
        if (staticCd) {
          const globalKey = `${vn}_${fn}`;
          const gInfo = this.moduleGlobals.get(globalKey);
          if (gInfo) {
            const gType = watBaseType(gInfo.type);
            return { type: gType, watLoad: `(global.get $${globalKey})` };
          }
        }
        // Phase 30: namespace constant
        if (this.namespaceDefs.has(vn)) {
          const globalKey = `${vn}_${fn}`;
          const gInfo = this.moduleGlobals.get(globalKey);
          if (gInfo) {
            const gType = watBaseType(gInfo.type);
            return { type: gType, watLoad: `(global.get $${globalKey})` };
          }
        }
        // Phase 31: TypedArray .length and .byteLength
        const taInfoSLE = this.typedArrayVars.get(vn);
        if (taInfoSLE) {
          if (fn === "length") return { type: "i32", watLoad: `(i32.load (local.get $${vn}))` };
          if (fn === "byteLength") {
            const lenW2 = `(i32.load (local.get $${vn}))`;
            return {
              type: "i32",
              watLoad: taInfoSLE.shift === 0
                ? lenW2
                : `(i32.shl ${lenW2} (i32.const ${taInfoSLE.shift}))`,
            };
          }
        }
        const sv = this.structVars.get(vn);
        if (!sv) return undefined;
        const f = sv.def.fields.find((fi) => fi.name === fn);
        if (!f) return undefined;
        if (f.type === "string") {
          const baseWat = sv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
          return {
            type: "string",
            watLoad: `(i32.load offset=${f.offset} ${baseWat})`,
            watLoadLen: `(i32.load offset=${f.offset + 4} ${baseWat})`,
          };
        }
        const loadOp = f.type === "f64" ? "f64.load" : f.type === "i64" ? "i64.load" : "i32.load";
        const baseWat = sv.ptr < 0 ? `(local.get $${vn})` : `(i32.const ${sv.ptr})`;
        return {
          type: f.type,
          watLoad: `(${loadOp} (i32.add ${baseWat} (i32.const ${f.offset})))`,
        };
      };
      const dotCallLookupFnErr: DotCallLookup = (token) => {
        const result = this.quietEmit(() => this.emitExpr(token, locals, "i32"));
        if (result === "(unreachable)" || result.startsWith("(;?")) return undefined;
        // Phase 47: arr[idx].method(args) — resolve the element class's method return type
        // so console.log formats the result correctly (emitExpr already does vtable dispatch).
        const amc = token.match(/^(\w+)\[([^\]]*)\]\.(\w+)\s*\(/);
        if (amc) {
          const aInfo = this.arrayVars.get(amc[1]!);
          const stn = aInfo?.structTypeName ??
            (aInfo && aInfo.elemType !== "f64" && aInfo.elemType !== "i32" &&
                aInfo.elemType !== "i64"
              ? aInfo.elemType
              : undefined);
          if (stn && this.classDefs.has(stn)) {
            const mfn = this.resolveMethodFunc(stn, amc[3]!);
            const mdef = mfn ? this.functions.find((f) => f.name === mfn) : undefined;
            const retType = (mdef?.result ?? "i32") as WatType;
            return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
          }
        }
        const m2 = token.match(/^(?:this|\w+)\.(\w+)\s*\(/);
        if (m2) {
          const receiver2 = token.match(/^(\w+)\./)?.[1] ?? "";
          const methodName2 = m2[1];
          const cv2 = receiver2 === "this" ? null : this.classVars.get(receiver2);
          const className2 = receiver2 === "this" ? this.currentMethodClass : cv2?.className;
          const cd2 = className2 ? this.classDefs.get(className2) : null;
          const method2 = cd2?.methods.find((mm) => mm.name === methodName2);
          if (method2) {
            const fn2 = this.functions.find((f) => f.name === `${className2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          const staticCd = this.classDefs.get(receiver2);
          if (staticCd) {
            const fn2 = this.functions.find((f) => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Phase 30: namespace function call
          if (this.namespaceDefs.has(receiver2)) {
            const fn2 = this.functions.find((f) => f.name === `${receiver2}_${methodName2}`);
            if (fn2) {
              const retType = fn2.result ?? "i32";
              return { type: retType as string, wat: this.emitExpr(token, locals, retType) };
            }
          }
          // Phase 5h/12: interface method dispatch
          const ifaceName2 = this.interfaceVars.get(receiver2);
          if (ifaceName2) {
            const field2 = this.structDefs.get(ifaceName2)?.fields.find((f) =>
              f.name === methodName2
            );
            if (field2?.funcType) {
              return { type: (field2.funcType.result ?? "i32") as string, wat: result };
            }
          }
          // Boolean-returning array methods: every, some, includes (mirror of dotCallLookupFn)
          if (
            ["every", "some", "includes"].includes(methodName2) && this.arrayVars.has(receiver2)
          ) {
            return { type: "bool", wat: result };
          }
        }
        return { type: "i32", wat: result };
      };
      const globalsMapErr: Map<string, string> = new Map(
        [...this.moduleGlobals.entries()].map(([k, v]) => [k, watBaseType(v.type)]),
      );
      for (const [k, [offset, len]] of this.moduleStringConsts) {
        globalsMapErr.set(k, `string:${offset}:${len}`);
      }
      for (const k of this.moduleStringGlobals.keys()) {
        globalsMapErr.set(k, `strglobal:${k}`);
      }
      const closureVarLookupFnErr: ClosureVarLookup = (name) => {
        const sig = this.closureTypedVars.get(name);
        if (!sig) return undefined;
        const trampolineParams: WatType[] = ["i32" as WatType, ...sig.params as WatType[]];
        const trampolineResult = sig.result === "string" ? null : sig.result;
        const funcType = this.getOrCreateFuncType(trampolineParams, trampolineResult);
        return { params: sig.params as string[], result: sig.result, funcType };
      };
      setStringArrayAllocator((elems) => this.allocArrayData(elems, "string"));
      setStructLiteralAllocator((sName, fields) =>
        this.allocStructData(this.structDefs.get(sName)!, fields)
      );
      setStrCmpNeededCallback(() => {
        this.needsStringHelpers = true;
      });
      setFuncTableLookup((name) =>
        this.functions.find((f) => f.name === name) ? this.getFuncTableIdx(name) : undefined
      );
      setInstanceofResolver((tok, locs) => {
        const m = tok.match(/^\w+\s+instanceof\s+(\w+)$/);
        if (!m || !this.classDefs.has(m[1]!)) return undefined;
        return this.emitExpr(tok, locs as Map<string, WatType>, "i32");
      });
      // String-producing method calls (s.toUpperCase(), arr[i].toLowerCase(), …): resolve to a
      // ptr/len pair via emitStringPtrLen, captured into $__str_op_len (ptrWat runs the call and
      // leaves ptr; lenWat reads the captured len — both consumers evaluate ptrWat first).
      setStringExprResolver((tok, locs) => {
        const w = this.quietEmit(() => this.emitStringPtrLen(tok, locs as Map<string, WatType>));
        if (w === "(i32.const 0) (i32.const 0)") return undefined;
        return {
          ptrWat: `(block (result i32) ${w} (local.set $__str_op_len))`,
          lenWat: `(local.get $__str_op_len)`,
        };
      });
      const segments = parseConsoleLogArgs(
        errMatch[2],
        locals as Map<string, string>,
        lookup,
        allocator,
        enumLookup,
        arrayLookupFn,
        structLookupFn,
        dotCallLookupFnErr,
        globalsMapErr,
        enumStringLookupFnErr,
        closureVarLookupFnErr,
      );
      setStringArrayAllocator(undefined);
      setStructLiteralAllocator(undefined);
      setStrCmpNeededCallback(undefined);
      setFuncTableLookup(undefined);
      setInstanceofResolver(undefined);
      setStringExprResolver(undefined);
      const {
        statements,
        needsHelpers,
        needsStrGather,
        needsArrPrintHelper: errAph,
        needsJoinHelper: errJh,
      } = emitConsoleLog(segments, allocator, "    ", 2, this.iovBase, this.scratchBase);
      if (needsHelpers) this.needsNumericHelpers = true;
      if (needsStrGather) this.needsStrGatherHelper = true;
      if (errAph) this.needsArrPrintHelper = true;
      if (errJh) this.needsJoinHelper = true;
      return statements.join("\n      ");
    }

    // break / break label
    const breakMatch = line.match(/^break(?:\s+(\w+))?\s*;?$/);
    if (breakMatch) {
      const label = breakMatch[1];
      if (label) return `(br $break_${label})`;
      const ctx = [...this.controlStack].reverse().find((c) => c.breakLabel);
      return ctx ? `(br ${ctx.breakLabel})` : `(;; break outside loop;)`;
    }

    // continue / continue label
    const contMatch = line.match(/^continue(?:\s+(\w+))?\s*;?$/);
    if (contMatch) {
      const label = contMatch[1];
      if (label) return `(br $cont_${label})`;
      const ctx = [...this.controlStack].reverse().find((c) => c.continueLabel);
      return ctx ? `(br ${ctx.continueLabel})` : `(;; continue outside loop;)`;
    }

    // Post/pre increment/decrement as standalone statements: i++, i--, ++i, --i
    if (/^(\w+)\+\+;?$/.test(line) || /^\+\+(\w+);?$/.test(line)) {
      const v = line.replace(/[+;]/g, "").trim();
      // Phase 5h: boxed capture — update through heap pointer
      if (this.currentBoxedCaptures.has(v)) {
        return `(i32.store (local.get $${v}) (i32.add (i32.load (local.get $${v})) (i32.const 1)))`;
      }
      // Mutable closure capture — update through $__closure_ptr
      {
        const ccl = this.currentClosureCaptureLayout.get(v);
        if (ccl) {
          const loadOp = ccl.type === "f64"
            ? "f64.load"
            : ccl.type === "i64"
            ? "i64.load"
            : "i32.load";
          const storeOp = ccl.type === "f64"
            ? "f64.store"
            : ccl.type === "i64"
            ? "i64.store"
            : "i32.store";
          const addOp = ccl.type === "f64" ? "f64.add" : ccl.type === "i64" ? "i64.add" : "i32.add";
          const one = ccl.type === "f64"
            ? "f64.const 1"
            : ccl.type === "i64"
            ? "i64.const 1"
            : "i32.const 1";
          return `(${storeOp} offset=${ccl.offset} (local.get $__closure_ptr) (${addOp} (${loadOp} offset=${ccl.offset} (local.get $__closure_ptr)) (${one})))`;
        }
      }
      if (this.moduleGlobals.has(v)) {
        const vt = watBaseType(this.moduleGlobals.get(v)!.type);
        return `(global.set $${v} (${vt}.add (global.get $${v}) (${vt}.const 1)))`;
      }
      const vt = watBaseType(locals.get(v) ?? "i32");
      return `(local.set $${v} (${vt}.add (local.get $${v}) (${vt}.const 1)))`;
    }
    if (/^(\w+)--;?$/.test(line) || /^--(\w+);?$/.test(line)) {
      const v = line.replace(/[-;]/g, "").trim();
      // Phase 5h: boxed capture — update through heap pointer
      if (this.currentBoxedCaptures.has(v)) {
        return `(i32.store (local.get $${v}) (i32.sub (i32.load (local.get $${v})) (i32.const 1)))`;
      }
      // Mutable closure capture — update through $__closure_ptr
      {
        const ccl = this.currentClosureCaptureLayout.get(v);
        if (ccl) {
          const loadOp = ccl.type === "f64"
            ? "f64.load"
            : ccl.type === "i64"
            ? "i64.load"
            : "i32.load";
          const storeOp = ccl.type === "f64"
            ? "f64.store"
            : ccl.type === "i64"
            ? "i64.store"
            : "i32.store";
          const subOp = ccl.type === "f64" ? "f64.sub" : ccl.type === "i64" ? "i64.sub" : "i32.sub";
          const one = ccl.type === "f64"
            ? "f64.const 1"
            : ccl.type === "i64"
            ? "i64.const 1"
            : "i32.const 1";
          return `(${storeOp} offset=${ccl.offset} (local.get $__closure_ptr) (${subOp} (${loadOp} offset=${ccl.offset} (local.get $__closure_ptr)) (${one})))`;
        }
      }
      if (this.moduleGlobals.has(v)) {
        const vt = watBaseType(this.moduleGlobals.get(v)!.type);
        return `(global.set $${v} (${vt}.sub (global.get $${v}) (${vt}.const 1)))`;
      }
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
        // Phase 47: walk inheritance chain to find overriding or inherited method
        const funcName = this.resolveMethodFunc(this.currentMethodClass, methodName) ??
          `${this.currentMethodClass}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
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
        // Phase 47: walk inheritance chain to find overriding or inherited method
        const funcName = this.resolveMethodFunc(cv.className, methodName) ??
          `${cv.className}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
        if (fn) {
          const baseWat = cv.ptr < 0 ? `(local.get $${receiver})` : `(i32.const ${cv.ptr})`;
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
        const method = staticCd.methods.find((mm) => mm.name === methodName && mm.isStatic);
        if (method) {
          const funcName = `${receiver}_${methodName}`;
          const fn = this.functions.find((f) => f.name === funcName);
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

      // Phase 12: interface method dispatch via closure trampoline
      const ifaceNameStmt = this.interfaceVars.get(receiver);
      if (ifaceNameStmt) {
        const structDefStmt = this.structDefs.get(ifaceNameStmt);
        const fieldStmt = structDefStmt?.fields.find((f) => f.name === methodName);
        if (fieldStmt?.funcType) {
          const closurePtrAddrS = fieldStmt.offset === 0
            ? `(local.get $${receiver})`
            : `(i32.add (local.get $${receiver}) (i32.const ${fieldStmt.offset}))`;
          const loadClosureS = `(i32.load ${closurePtrAddrS})`;
          const trampolineParamsS: WatType[] = ["i32" as WatType, ...fieldStmt.funcType.params];
          const typeNameS = this.getOrCreateFuncType(trampolineParamsS, fieldStmt.funcType.result);
          const emittedArgsS = args.map((a, idx) =>
            this.emitExpr(a, locals, fieldStmt.funcType!.params[idx] ?? "i32" as WatType)
          );
          const callWatS =
            `(call_indirect (type ${typeNameS}) (local.tee $__iface_tmp ${loadClosureS}) ${
              emittedArgsS.join(" ")
            } (i32.load (local.get $__iface_tmp)))`.trim();
          const hasResultS = fieldStmt.funcType.result !== null &&
            fieldStmt.funcType.result !== "never";
          return hasResultS ? `(drop ${callWatS})` : callWatS;
        }
      }

      // Phase 30: namespace function call as statement
      if (this.namespaceDefs.has(receiver)) {
        const funcName = `${receiver}_${methodName}`;
        const fn = this.functions.find((f) => f.name === funcName);
        if (fn) {
          const emittedArgs = args.flatMap((a, i) => {
            const pt = fn.params[i]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          const call = `(call $${funcName} ${emittedArgs.join(" ")})`.trim();
          return fn.result ? `(drop ${call})` : call;
        }
      }

      // Phase 40: external interface binding call as statement
      if (this.externalBindings.has(receiver)) {
        const ifaceName = this.externalBindings.get(receiver)!;
        const iface = this.externalInterfaceTypes.get(ifaceName);
        const methodSig = iface?.get(methodName);
        if (methodSig) {
          const watFuncName = `$${receiver}_${methodName}`;
          this.usedExternalMethods.set(watFuncName, methodSig);
          const emittedArgs = args.map((a, i) =>
            this.emitExpr(a, locals, methodSig.params[i] ?? ("i32" as WatType))
          );
          const call = `(call ${watFuncName} ${emittedArgs.join(" ")})`.trim();
          return methodSig.result ? `(drop ${call})` : call;
        }
      }

      // Phase 18 fix: Deno.exit(code) → WASI proc_exit
      if (receiver === "Deno" && methodName === "exit") {
        const code = argsStr.trim() || "0";
        return `(call $proc_exit ${this.emitExpr(code, locals, "i32")})`;
      }

      // Receiver is not `this`, not a class instance, not a class, not an interface variable,
      // not a namespace, and not a declared external binding: it is an undeclared/unimported identifier.
      if (receiver !== "this") {
        const isKnown = this.classVars.has(receiver) || this.classDefs.has(receiver) ||
          this.interfaceVars.has(receiver) || this.namespaceDefs.has(receiver) ||
          this.externalBindings.has(receiver);
        if (!isKnown) {
          console.error(
            `❌ wasic: '${receiver}' is not defined — '${receiver}.${methodName}(...)' cannot be compiled`,
          );
          console.error(`   Note: '${receiver}' was not imported or declared in this module.`);
          console.error(
            `   If '${receiver}' is an external module, use: declare const ${receiver}: { ${methodName}(...): ReturnType }`,
          );
          rt.exit(1);
        }
      }
    }

    // Phase 5f: standalone chained call — factoryFn(outerArgs)(innerArgs);
    {
      const chainHead = line.match(/^(\w+)\s*\(/)?.[1];
      if (chainHead && chainHead !== "console") {
        const factoryFn = this.functions.find((f) => f.name === chainHead && f.isClosureFactory);
        if (factoryFn?.returnedArrow) {
          const openParen1 = line.indexOf("(");
          const [rawOuterArgs, afterOuter] = WasicTranspiler.extractParamBlock(line, openParen1);
          const rest = line.slice(afterOuter).trimStart().replace(/;$/, "").trimStart();
          if (rest.startsWith("(")) {
            const [rawInnerArgs] = WasicTranspiler.extractParamBlock(rest, 0);
            const inner = factoryFn.returnedArrow;
            const innerCallParams = inner.params.filter((p) =>
              !(inner.closureCaptures ?? []).includes(p.name)
            );
            const outerArgs = rawOuterArgs.trim() ? this.splitArgs(rawOuterArgs) : [];
            const outerEmitted = outerArgs.map((a, i) =>
              this.emitExpr(a, locals, factoryFn.params[i]?.type ?? "i32")
            );
            const innerArgs = rawInnerArgs.trim() ? this.splitArgs(rawInnerArgs) : [];
            const innerEmitted = innerArgs.map((a, i) =>
              this.emitExpr(a, locals, innerCallParams[i]?.type ?? "i32")
            );
            const callWat = `(call $${chainHead}__trampoline (call $${chainHead} ${
              outerEmitted.join(" ")
            }) ${innerEmitted.join(" ")})`.trim();
            const hasResult = inner.result !== null && inner.result !== "never" &&
              inner.result !== "string";
            return hasResult ? `(drop ${callWat})` : callWat;
          }
        }
      }
    }

    // Phase 47: super.method(args) — non-constructor super method call (statement form)
    const superMethodStmt = line.match(/^super\.(\w+)\s*\((.*)\)\s*;?$/);
    if (superMethodStmt && this.currentMethodClass) {
      const smsMethod = superMethodStmt[1];
      const smsArgsRaw = superMethodStmt[2].trim();
      const smsParent = this.classInheritance.get(this.currentMethodClass);
      if (smsParent) {
        const smsFuncName = this.resolveMethodFunc(smsParent, smsMethod) ??
          `${smsParent}_${smsMethod}`;
        const smsFn = this.functions.find((f) => f.name === smsFuncName);
        if (smsFn) {
          const smsArgs = smsArgsRaw ? this.splitArgs(smsArgsRaw) : [];
          const smsEmitted = smsArgs.map((a, i) =>
            this.emitExpr(a, locals, smsFn.params[i + 1]?.type ?? ("i32" as WatType))
          );
          const smsCall = `(call $${smsFuncName} (local.get $__self) ${smsEmitted.join(" ")})`
            .trim();
          return smsFn.result ? `(drop ${smsCall})` : smsCall;
        }
      }
    }

    // Phase 47: super(...) — constructor chaining from derived class to parent
    const superCallMatch = line.match(/^super\s*\((.*)\)\s*;?$/);
    if (superCallMatch && this.currentMethodClass) {
      const parentName = this.classInheritance.get(this.currentMethodClass);
      if (parentName) {
        const parentCtorFn = this.functions.find((f) => f.name === `${parentName}_constructor`);
        if (parentCtorFn) {
          const rawSuperArgs = superCallMatch[1].trim();
          const superArgs = rawSuperArgs ? this.splitArgs(rawSuperArgs) : [];
          const emittedSuperArgs = superArgs.flatMap((a, i) => {
            const pt = parentCtorFn.params[i + 1]?.type ?? ("i32" as WatType);
            return [this.emitExpr(a, locals, pt)];
          });
          return `(call $${parentName}_constructor (local.get $__self) ${
            emittedSuperArgs.join(" ")
          })`.trim();
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
        const fn = this.functions.find((f) => f.name === callee);
        if (!fn) {
          // Phase 5g: closure pointer dispatch
          if (this.closureTypedVars.has(callee)) {
            const sig = this.closureTypedVars.get(callee)!;
            const trampolineParamTypes: WatType[] = ["i32" as WatType, ...sig.params as WatType[]];
            const trampolineResult = sig.result === "string" ? null : sig.result;
            const trampolineTypeName = this.getOrCreateFuncType(
              trampolineParamTypes,
              trampolineResult,
            );
            const emittedArgs = args.map((a, idx) =>
              this.emitExpr(a, locals, sig.params[idx] ?? "i32" as WatType)
            );
            const callWat = `(call_indirect (type ${trampolineTypeName}) (local.get $${callee}) ${
              emittedArgs.join(" ")
            } (i32.load (local.get $${callee})))`.trim();
            const hasResult = sig.result !== null && sig.result !== "never" &&
              sig.result !== "string";
            return hasResult ? `(drop ${callWat})` : callWat;
          }
          if (this.funcTypeVars.has(callee)) {
            const sig = this.funcTypeVars.get(callee)!;
            const typeName = this.getOrCreateFuncType(sig.params, sig.result);
            const emittedArgs = args.flatMap((a, idx) => {
              const pt = sig.params[idx] ?? "i32" as WatType;
              if (pt === "string") return [this.emitStringPtrLen(a, locals)];
              return [this.emitExpr(a, locals, pt)];
            });
            const callWat = `(call_indirect (type ${typeName}) ${
              emittedArgs.join(" ")
            } (local.get $${callee}))`.trim();
            const hasIndResult = sig.result !== null && sig.result !== "never" &&
              sig.result !== "string";
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

    // Terminal fallback: an unrecognised statement would otherwise be silently dropped. Record a
    // diagnostic (which aborts the compile) for anything that looks like a real statement, so a
    // genuine unsupported statement fails loudly instead of vanishing. Skip lines that are clearly
    // NOT executable statements but stray fragments of a multi-line construct (a discriminated-union
    // type-alias continuation, or an element/field line of a multi-line array / object / struct
    // literal that is parsed as a whole elsewhere) — and blank / bare-`;` / comment-only lines.
    {
      const t = line.trim();
      const isNonStatementFragment = t === "" || t === ";" || t.startsWith("//") ||
        t.startsWith("|") || // DU type-alias union continuation: `| { kind: "circle"; … }`
        t.endsWith(",") || // array/object element fragment: `"success",`
        /^\{.*\}[,;]?$/.test(t) || // bare object-literal fragment: `{ type: "add", value: 15 }`
        /^-?\d+(\.\d+)?[,;]?$/.test(t) || // bare numeric element: `404`
        /^["'`].*["'`][,;]?$/.test(t); // bare string element: `"failure"`
      if (!isNonStatementFragment) {
        this.diagnostics.push(`Unsupported statement: ${t.slice(0, 80)}`);
      }
    }
    return `(;; ${line};)`;
  }

  /** Emits a WAT statement for a for-loop update expression (i++, i--, i += n, etc.). */
  private emitUpdate(upd: string, locals: Map<string, WatType>): string {
    upd = upd.trim().replace(/;$/, "");
    // i++ / i--
    if (/^(\w+)\+\+$/.test(upd)) {
      return this.emitStatement(`${upd.slice(0, -2)} += 1;`, locals, null);
    }
    if (/^(\w+)--$/.test(upd)) return this.emitStatement(`${upd.slice(0, -2)} -= 1;`, locals, null);
    // ++i / --i
    if (/^\+\+(\w+)$/.test(upd)) return this.emitStatement(`${upd.slice(2)} += 1;`, locals, null);
    if (/^--(\w+)$/.test(upd)) return this.emitStatement(`${upd.slice(2)} -= 1;`, locals, null);
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
    indent: string = "    ",
  ): string {
    const out: string[] = [];
    let i = 0;

    while (i < lines.length) {
      const line = lines[i];

      // Labeled statement: "label: { ... }" or "label: for/while/do ..."
      // Must not match "case X:" or "default:" which are handled by switch.
      const labeledMatch = line.match(/^(\w+)\s*:\s*(.*)$/);
      if (labeledMatch && labeledMatch[1] !== "case" && labeledMatch[1] !== "default") {
        const userLabel = labeledMatch[1];
        const rest = labeledMatch[2].trim();
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
      // Use balanced-paren scan to find condition end (avoids greedy regex misparse when body has parens).
      let ifMatch: string[] | null = null;
      if (/^if\s*\(/.test(line)) {
        const openIdx = line.indexOf("(");
        let depth = 0, condEnd = -1;
        for (let j = openIdx; j < line.length; j++) {
          if (line[j] === "(") depth++;
          else if (line[j] === ")") {
            if (--depth === 0) {
              condEnd = j;
              break;
            }
          }
        }
        if (condEnd !== -1) {
          ifMatch = [line, line.slice(openIdx + 1, condEnd), line.slice(condEnd + 1).trim()];
        }
      }
      if (ifMatch) {
        const cond = ifMatch[1].trim();
        const rawIfBody = ifMatch[2];
        const inlineBody = rawIfBody && rawIfBody !== "{" && !rawIfBody.trimStart().startsWith("{")
          ? rawIfBody.trim()
          : null;
        const singleLineBlock =
          rawIfBody && rawIfBody.trimStart().startsWith("{") && rawIfBody.trim() !== "{"
            ? rawIfBody
            : null;
        let ifBody: string[];
        let terminator = "";
        // A single-line `if` (brace-less `if (c) s;` OR single-line-braced `if (c) { s }`) may be
        // followed by a self-contained `else` / `else if` chain on the NEXT lines. The else-detection
        // further below only recognises a few braced forms, so without this BOTH the brace-less and
        // single-line-braced else branches were silently DROPPED. Assemble the if-body and the whole
        // chain into one inline string and feed it to expandInlineBraceChain, which produces the
        // canonical braced multi-line form the multi-line else / else-if machinery handles. An OPEN
        // braced else (`else {` continuing on later lines) is left to the existing machinery.
        if (
          (inlineBody || singleLineBlock) && i + 1 < lines.length &&
          WasicTranspiler.isSelfContainedElse(lines[i + 1])
        ) {
          let combined = inlineBody ? `{ ${inlineBody} }` : singleLineBlock!.trim();
          let k = i + 1;
          while (k < lines.length && WasicTranspiler.isSelfContainedElse(lines[k])) {
            combined += " " + WasicTranspiler.braceifyElseLine(lines[k]);
            k++;
          }
          const expanded = WasicTranspiler.expandInlineBraceChain(combined);
          lines.splice(i, k - i, `if (${cond}) {`, ...expanded);
          continue;
        }
        if (inlineBody) {
          // Single-line if: body is the inline statement (no braces)
          ifBody = [inlineBody];
          i++;
        } else if (singleLineBlock) {
          // Single-line brace block, possibly with an inline else / else-if chain:
          //   if (cond) { A } else { B }   (entirely on one line)
          // Expand into the multi-line form and re-process so the existing multi-line
          // else / else-if handling applies. The old strip-last-`}` heuristic grabbed the
          // else-block's closing brace and silently swallowed the `else`.
          const expanded = WasicTranspiler.expandInlineBraceChain(singleLineBlock.trim());
          lines.splice(i, 1, `if (${cond}) {`, ...expanded);
          continue;
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
          i += ec; // no +1: extractBlock was called at i (no initiating line to skip)
        } else if (i < lines.length && lines[i].match(/^}\s*else\s*\{?$/)) {
          // i points to "} else {"; extractBlock called with i+1 (past initiating line)
          const [eb, ec] = this.extractBlock(lines, i + 1);
          elseBody = eb;
          i += ec + 1;
        } else if (i < lines.length && /^else\s*(\{.*)?$/.test(lines[i])) {
          // Standalone "else { ... }" line following a single-line if block
          const elseLine = lines[i];
          const elseInline = elseLine.match(/^else\s*\{(.*)\}\s*$/);
          const elseOpen = elseLine.match(/^else\s*\{?\s*$/);
          if (elseInline) {
            const inner = elseInline[1].trim();
            elseBody = inner ? WasicTranspiler.splitStmts(inner) : [];
            i++;
          } else if (elseOpen) {
            const [eb, ec] = this.extractBlock(lines, i + 1);
            elseBody = eb;
            i += ec + 1;
          }
        } else if (/^}\s*else\s*if\s*\(/.test(terminator)) {
          // Phase 32: else-if chain — build a synthetic else body ["if (cond) {", body…, "} else if {", ...]
          // i is already at first body line of the else-if block (same as "} else {" case)
          const synElse: string[] = [];
          const cMei = terminator.match(/^}\s*else\s*if\s*\((.+)\)\s*\{?$/)!;
          synElse.push(`if (${cMei[1]}) {`);
          const [eib0, eic0, eiterm0] = this.extractBlock(lines, i);
          synElse.push(...eib0);
          i += eic0;
          let curTerm = eiterm0;
          // Collect any further else-if links
          while (/^}\s*else\s*if\s*\(/.test(curTerm)) {
            synElse.push(curTerm); // separator line: "} else if (cond2) {"
            const [eibN, eicN, eitermN] = this.extractBlock(lines, i);
            synElse.push(...eibN);
            i += eicN;
            curTerm = eitermN;
          }
          // Final else or closing brace
          if (curTerm === "} else {") {
            synElse.push("} else {");
            const [eibF, eicF] = this.extractBlock(lines, i);
            synElse.push(...eibF);
            synElse.push("}");
            i += eicF;
          } else {
            synElse.push("}");
          }
          elseBody = synElse;
        }

        const condExpr = this.emitExpr(cond, locals, "i32");
        // Phase 34: type predicate narrowing — if cond is "predFn(arg)" where predFn is a
        // registered type predicate, temporarily narrow arg's struct def to the target type
        // in the then-branch.  Save and restore state around emitBlock(ifBody, ...).
        let narrowKey: string | null = null;
        let narrowOrigStruct: { def: StructDef; ptr: number } | undefined;
        let narrowOrigClass: { className: string; ptr: number } | undefined;
        const predCallMatch = cond.match(/^(\w+)\s*\(\s*(\w+)\s*\)$/);
        if (predCallMatch) {
          const predInfo = this.typePredicateFuncs.get(predCallMatch[1]);
          if (predInfo) {
            narrowKey = predCallMatch[2];
            narrowOrigStruct = this.structVars.get(narrowKey);
            narrowOrigClass = this.classVars.get(narrowKey);
            const targetDef = this.structDefs.get(predInfo.targetType);
            const targetCls = this.classDefs.get(predInfo.targetType);
            if (targetDef) {
              // Preserve the current pointer (static address or -1 for params); only swap the def.
              const curPtr = narrowOrigStruct?.ptr ?? -1;
              this.structVars.set(narrowKey, { def: targetDef, ptr: curPtr });
            } else if (targetCls) {
              const curPtr = narrowOrigClass?.ptr ?? -1;
              this.classVars.set(narrowKey, { className: predInfo.targetType, ptr: curPtr });
            }
          }
        }
        // Phase 51: instanceof narrowing — `if (x instanceof Dog) { … }` narrows x's tracked
        // class to Dog in the then-branch so Dog-only fields/methods resolve. Mirrors the
        // predicate-narrowing save/restore above (same narrowKey machinery).
        const instCondMatch = cond.match(/^(\w+)\s+instanceof\s+(\w+)$/);
        if (narrowKey === null && instCondMatch && this.classDefs.has(instCondMatch[2]!)) {
          narrowKey = instCondMatch[1]!;
          narrowOrigClass = this.classVars.get(narrowKey);
          const curPtr = narrowOrigClass?.ptr ?? -1;
          this.classVars.set(narrowKey, { className: instCondMatch[2]!, ptr: curPtr });
        }
        const ifWat = this.emitBlock(ifBody, locals, funcResult, indent + "  ");
        // Restore pre-narrowing state
        if (narrowKey !== null) {
          if (narrowOrigStruct !== undefined) this.structVars.set(narrowKey, narrowOrigStruct);
          else this.structVars.delete(narrowKey);
          if (narrowOrigClass !== undefined) this.classVars.set(narrowKey, narrowOrigClass);
          else this.classVars.delete(narrowKey);
        }
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

      // Single-line while WITHOUT braces: `while (cond) stmt` (e.g. `while (s.length < n) s += "0"`).
      // The braced whileMatch below requires the line to end at the condition, so handle this first
      // with a balanced-paren scan to split condition from the inline body statement.
      if (/^while\s*\(/.test(line) && !line.replace(/;$/, "").endsWith("{")) {
        const openIdx = line.indexOf("(");
        let depth = 0;
        let condEnd = -1;
        for (let j = openIdx; j < line.length; j++) {
          if (line[j] === "(") depth++;
          else if (line[j] === ")" && --depth === 0) {
            condEnd = j;
            break;
          }
        }
        const inlineBody = condEnd !== -1 ? line.slice(condEnd + 1).trim().replace(/;$/, "") : "";
        if (condEnd !== -1 && inlineBody && inlineBody !== "{") {
          const cond = line.slice(openIdx + 1, condEnd).trim();
          const lbl = this.pendingLabel ?? String(this.loopCounter++);
          this.pendingLabel = null;
          const brk = `$break_${lbl}`;
          const loop = `$loop_${lbl}`;
          const cont = `$cont_${lbl}`;
          this.controlStack.push({ breakLabel: brk, continueLabel: cont });
          const condExpr = this.emitExpr(cond, locals, "i32");
          const bodyWat = this.emitBlock(
            WasicTranspiler.splitStmts(inlineBody),
            locals,
            funcResult,
            indent + "      ",
          );
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
          i++; // consumed exactly this one line (emitBlock advances i manually)
          continue;
        }
      }

      // while (cond) {
      const whileMatch = line.match(/^while\s*\((.+)\)\s*\{?$/);
      if (whileMatch) {
        const cond = whileMatch[1].trim();
        const [whileBody, consumed] = this.extractBlock(lines, i + 1);
        i += consumed + 1;
        const lbl = this.pendingLabel ?? String(this.loopCounter++);
        this.pendingLabel = null;
        const brk = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`; // continue target: exits cont-block → falls to br loop
        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const condExpr = this.emitExpr(cond, locals, "i32");
        const bodyWat = this.emitBlock(whileBody, locals, funcResult, indent + "      ");
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

      // Phase 26: for...of loop — for (const/let item of arr) { ... }
      // Must come before the inlined-for and regular-for handlers so "of" isn't split as init;cond;update.
      if (/^for\s*\(\s*(?:const|let)\s+\w+\s+of\s+\w+\s*\)/.test(line)) {
        const forOfM = line.match(/^for\s*\(\s*(?:const|let)\s+(\w+)\s+of\s+(\w+)\s*\)\s*(.*)$/);
        if (forOfM) {
          const itemName = forOfM[1];
          const arrName = forOfM[2];
          const inlinePart = (forOfM[3] ?? "").trim();

          let forOfBody: string[];
          if (inlinePart.startsWith("{") && inlinePart.endsWith("}") && inlinePart.length > 2) {
            // Fully inline: for (...) { body }
            const bodyContent = inlinePart.slice(1, -1).trim();
            forOfBody = bodyContent ? WasicTranspiler.splitStmts(bodyContent) : [];
            i++;
          } else if (inlinePart === "{" || inlinePart === "") {
            // Multi-line block follows
            const [body, consumed] = this.extractBlock(lines, i + 1);
            forOfBody = body;
            i += consumed + 1;
          } else {
            // Brace-less single-line body: `for (const x of arr) stmt;`
            forOfBody = WasicTranspiler.splitStmts(inlinePart);
            i++;
          }

          const arrInfo = this.arrayVars.get(arrName);
          const elemType: WatType = arrInfo?.elemType ?? "i32";

          // Phase 27: string[] (from split) — 8-byte elements, emit ptr+len local sets
          if (arrInfo?.isStringArr) {
            const lbl2 = this.pendingLabel ?? String(this.loopCounter++);
            this.pendingLabel = null;
            const brk2 = `$break_${lbl2}`;
            const loop2 = `$loop_${lbl2}`;
            const cont2 = `$cont_${lbl2}`;
            const idxVar2 = "$__forof_idx";
            const lenWat2 = `(i32.load (local.get $${arrName}))`;
            // base address of element i: arr + 8 + i*8
            const elemBaseWat =
              `(i32.add (i32.add (local.get $${arrName}) (i32.const 8)) (i32.shl (local.get ${idxVar2}) (i32.const 3)))`;
            const setPtrWat = `(local.set $${itemName}_ptr (i32.load ${elemBaseWat}))`;
            const setLenWat = `(local.set $${itemName}_len (i32.load offset=4 ${elemBaseWat}))`;
            this.controlStack.push({ breakLabel: brk2, continueLabel: cont2 });
            const bodyWat2 = this.emitBlock(forOfBody, locals, funcResult, indent + "      ");
            this.controlStack.pop();
            out.push(`${indent}(local.set ${idxVar2} (i32.const 0))`);
            out.push(`${indent}(block ${brk2}`);
            out.push(`${indent}  (loop ${loop2}`);
            out.push(`${indent}    (br_if ${brk2} (i32.ge_u (local.get ${idxVar2}) ${lenWat2}))`);
            out.push(`${indent}    ${setPtrWat}`);
            out.push(`${indent}    ${setLenWat}`);
            out.push(`${indent}    (block ${cont2}`);
            out.push(bodyWat2);
            out.push(`${indent}    )`);
            out.push(
              `${indent}    (local.set ${idxVar2} (i32.add (local.get ${idxVar2}) (i32.const 1)))`,
            );
            out.push(`${indent}    (br ${loop2})`);
            out.push(`${indent}  )`);
            out.push(`${indent})`);
            continue;
          }

          const loadOp = elemType === "f64"
            ? "f64.load"
            : elemType === "i64"
            ? "i64.load"
            : "i32.load";
          const shift = (elemType === "f64" || elemType === "i64") ? 3 : 2;

          const lbl = this.pendingLabel ?? String(this.loopCounter++);
          this.pendingLabel = null;
          const brk = `$break_${lbl}`;
          const loop = `$loop_${lbl}`;
          const cont = `$cont_${lbl}`;
          const idxVar = "$__forof_idx";

          // Element load and length WAT — mirrors the array indexing logic at emitExpr line ~2749.
          // ptr=-1: runtime param pointer (no header). ptr=-2/dynamic: heap array (8-byte header). ptr>=0: static.
          let elemLoadWat: string;
          let lenWat: string;
          if (!arrInfo) {
            // Unknown array (captured var or not in scope) — assume dynamic heap layout
            elemLoadWat =
              `(${loadOp} (i32.add (i32.add (local.get $${arrName}) (i32.const 8)) (i32.shl (local.get ${idxVar}) (i32.const ${shift}))))`;
            lenWat = `(i32.load (local.get $${arrName}))`;
          } else if (arrInfo.dynamic) {
            // Dynamic heap array: [length, capacity, elem0, ...] at base ptr
            elemLoadWat =
              `(${loadOp} (i32.add (i32.add (local.get $${arrName}) (i32.const 8)) (i32.shl (local.get ${idxVar}) (i32.const ${shift}))))`;
            lenWat = `(i32.load (local.get $${arrName}))`;
          } else if (arrInfo.ptr === -1) {
            // Array parameter (runtime pointer, no header): elements start directly at ptr
            // Length is not stored — length must be passed separately; default to 0 if unknown
            elemLoadWat =
              `(${loadOp} (i32.add (local.get $${arrName}) (i32.shl (local.get ${idxVar}) (i32.const ${shift}))))`;
            lenWat = arrInfo.length > 0
              ? `(i32.const ${arrInfo.length})`
              : `(i32.load (local.get $${arrName}))`;
          } else {
            // Static array: compile-time address, known length. Elements start at ptr + 8
            // (past the 8-byte [length, capacity] header) — mirrors the arr[i] path (~line 6662).
            elemLoadWat = `(${loadOp} (i32.add (i32.const ${
              arrInfo.ptr + 8
            }) (i32.shl (local.get ${idxVar}) (i32.const ${shift}))))`;
            lenWat = `(i32.const ${arrInfo.length})`;
          }

          this.controlStack.push({ breakLabel: brk, continueLabel: cont });
          const bodyWat = this.emitBlock(forOfBody, locals, funcResult, indent + "      ");
          this.controlStack.pop();

          out.push(`${indent}(local.set ${idxVar} (i32.const 0))`);
          out.push(`${indent}(block ${brk}`);
          out.push(`${indent}  (loop ${loop}`);
          out.push(`${indent}    (br_if ${brk} (i32.ge_u (local.get ${idxVar}) ${lenWat}))`);
          out.push(`${indent}    (local.set $${itemName} ${elemLoadWat})`);
          out.push(`${indent}    (block ${cont}`);
          out.push(bodyWat);
          out.push(`${indent}    )`);
          out.push(
            `${indent}    (local.set ${idxVar} (i32.add (local.get ${idxVar}) (i32.const 1)))`,
          );
          out.push(`${indent}    (br ${loop})`);
          out.push(`${indent}  )`);
          out.push(`${indent})`);
          continue;
        }
      }

      // Phase 12: inlined for loop — for (...) { body } all on one line (from splitStmts in arrow bodies).
      // Re-expand it in-place so the standard forMatch handler below can process it normally.
      if (/^for\s*\(/.test(line) && line.endsWith("}")) {
        const ps = line.indexOf("(");
        const [rawHdr, afterHdr] = WasicTranspiler.extractParamBlock(line, ps);
        const restHdr = line.slice(afterHdr).trim();
        if (restHdr.startsWith("{") && restHdr.endsWith("}")) {
          const bodyContent = restHdr.slice(1, -1).trim();
          const forBodyInline = bodyContent ? WasicTranspiler.splitStmts(bodyContent) : [];
          const hdrParts = rawHdr.split(";").map((s) => s.trim());
          const initP = hdrParts[0] ?? "";
          const condP = hdrParts[1] ?? "";
          const updP = hdrParts[2] ?? "";
          const lbl2 = this.pendingLabel ?? String(this.loopCounter++);
          this.pendingLabel = null;
          const brk2 = `$break_${lbl2}`;
          const loop2 = `$loop_${lbl2}`;
          const cont2 = `$cont_${lbl2}`;
          const initWat2 = initP
            ? this.emitStatement(initP.replace(/;$/, "") + ";", locals, funcResult)
            : "";
          const condExpr2 = condP ? this.emitExpr(condP, locals, "i32") : "(i32.const 1)";
          const updWat2 = updP ? this.emitUpdate(updP, locals) : "";
          this.controlStack.push({ breakLabel: brk2, continueLabel: cont2 });
          const bodyWat2 = this.emitBlock(forBodyInline, locals, funcResult, indent + "      ");
          this.controlStack.pop();
          if (initWat2) out.push(`${indent}${initWat2}`);
          out.push(`${indent}(block ${brk2}`);
          out.push(`${indent}  (loop ${loop2}`);
          out.push(`${indent}    (br_if ${brk2} (i32.eqz ${condExpr2}))`);
          out.push(`${indent}    (block ${cont2}`);
          out.push(bodyWat2);
          out.push(`${indent}    )`);
          if (updWat2) out.push(`${indent}    ${updWat2}`);
          out.push(`${indent}    (br ${loop2})`);
          out.push(`${indent}  )`);
          out.push(`${indent})`);
          i++;
          continue;
        }
      }

      // Handle single-statement for loop: for (init; cond; update) stmt; (no braces)
      // Find the balanced closing ) of the for header and treat the rest as the body.
      if (/^(?:\w+\s*:\s*)?for\s*\(/.test(line)) {
        const parenStart = line.indexOf("(");
        let pdepth = 0, headerEnd = -1;
        for (let ci = parenStart; ci < line.length; ci++) {
          if (line[ci] === "(") pdepth++;
          else if (line[ci] === ")") {
            pdepth--;
            if (pdepth === 0) {
              headerEnd = ci;
              break;
            }
          }
        }
        if (headerEnd !== -1) {
          const afterParen = line.slice(headerEnd + 1).trim();
          if (afterParen.length > 0 && !afterParen.startsWith("{")) {
            // Single-statement body: process the for loop with a synthetic one-line body
            const inner = line.slice(parenStart + 1, headerEnd);
            const parts = inner.split(";").map((s) => s.trim());
            const initPart = parts[0] ?? "";
            const condPart = parts[1] ?? "";
            const updPart = parts[2] ?? "";
            const forBody = [afterParen.replace(/;$/, "")];

            const lbl = this.pendingLabel ?? String(this.loopCounter++);
            this.pendingLabel = null;
            const brk = `$break_${lbl}`;
            const loop = `$loop_${lbl}`;
            const cont = `$cont_${lbl}`;

            const initWat = initPart
              ? this.emitStatement(initPart.replace(/;$/, "") + ";", locals, funcResult)
              : "";
            const condExpr = condPart ? this.emitExpr(condPart, locals, "i32") : "(i32.const 1)";
            const updWat = updPart ? this.emitUpdate(updPart, locals) : "";

            this.controlStack.push({ breakLabel: brk, continueLabel: cont });
            const bodyWat = this.emitBlock(forBody, locals, funcResult, indent + "      ");
            this.controlStack.pop();

            if (initWat) out.push(`${indent}${initWat}`);
            out.push(`${indent}(block ${brk}`);
            out.push(`${indent}  (loop ${loop}`);
            out.push(`${indent}    (br_if ${brk} (i32.eqz ${condExpr}))`);
            out.push(`${indent}    (block ${cont}`);
            out.push(bodyWat);
            out.push(`${indent}    )`);
            if (updWat) out.push(`${indent}    ${updWat}`);
            out.push(`${indent}    (br ${loop})`);
            out.push(`${indent}  )`);
            out.push(`${indent})`);
            i++;
            continue;
          }
        }
      }

      // for (init; cond; update) {
      // Regex captures everything inside the parens, split on ;
      const forMatch = line.match(/^for\s*\((.+)\)\s*\{?$/);
      if (forMatch) {
        // Split init ; cond ; update at the top-level semicolons
        const inner = forMatch[1];
        const parts = inner.split(";").map((s) => s.trim());
        const initPart = parts[0] ?? "";
        const condPart = parts[1] ?? "";
        const updPart = parts[2] ?? "";

        const [forBody, consumed] = this.extractBlock(lines, i + 1);
        i += consumed + 1;

        const lbl = this.pendingLabel ?? String(this.loopCounter++);
        this.pendingLabel = null;
        const brk = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`; // continue target: exits cont-block → falls to update then br loop

        // Emit init (may declare a variable via let/const)
        const initWat = initPart
          ? this.emitStatement(initPart.replace(/;$/, "") + ";", locals, funcResult)
          : "";
        const condExpr = condPart ? this.emitExpr(condPart, locals, "i32") : "(i32.const 1)";
        const updWat = updPart ? this.emitUpdate(updPart, locals) : "";

        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const bodyWat = this.emitBlock(forBody, locals, funcResult, indent + "      ");
        this.controlStack.pop();

        if (initWat) out.push(`${indent}${initWat}`);
        out.push(`${indent}(block ${brk}`);
        out.push(`${indent}  (loop ${loop}`);
        out.push(`${indent}    (br_if ${brk} (i32.eqz ${condExpr}))`);
        out.push(`${indent}    (block ${cont}`); // continue exits here → falls to update
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
          if (nextWhile) {
            condPart = nextWhile[1].trim();
            i++;
          }
        }

        const lbl = this.pendingLabel ?? String(this.loopCounter++);
        this.pendingLabel = null;
        const brk = `$break_${lbl}`;
        const loop = `$loop_${lbl}`;
        const cont = `$cont_${lbl}`; // continue exits cont-block → falls to condition check
        const condExpr = this.emitExpr(condPart, locals, "i32");

        this.controlStack.push({ breakLabel: brk, continueLabel: cont });
        const bodyWat = this.emitBlock(doBody, locals, funcResult, indent + "      ");
        this.controlStack.pop();

        out.push(`${indent}(block ${brk}`);
        out.push(`${indent}  (loop ${loop}`);
        out.push(`${indent}    (block ${cont}`); // continue exits here → falls to condition
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
          const defM = sl.match(/^default\s*:\s*(.*)$/);
          if (caseM) {
            if (cur) cases.push(cur);
            cur = {
              values: [caseM[1].trim()],
              body: caseM[2] ? [caseM[2].trim()] : [],
              isDefault: false,
            };
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
        // Determine whether the switch expression is f64, string, or i32
        let switchType: "i32" | "f64" | "string" = "i32";
        if (/^\w+$/.test(switchExpr)) {
          const lt = locals.get(switchExpr);
          if (lt === "f64" || lt === "f32") switchType = "f64";
          else if (lt === "string") switchType = "string";
          else {
            const gt = this.moduleGlobals.get(switchExpr)?.type;
            if (gt === "f64" || gt === "f32") switchType = "f64";
            else if (gt === "string") switchType = "string";
          }
        }
        // Phase 32: detect discriminated union discriminant access: varName.discField
        let duSwitchDef: DiscUnionDef | null = null;
        const swDotM = switchExpr.match(/^(\w+)\.(\w+)$/);
        if (swDotM) {
          const swSv = this.structVars.get(swDotM[1]);
          if (swSv) {
            const swDu = this.discUnionDefs.get(swSv.def.name);
            if (swDu && swDu.discriminant === swDotM[2]) duSwitchDef = swDu;
          }
        }
        // For string switch, we need ptr+len separately; switchValWat is used for non-string types
        let switchValPtrWat = "";
        let switchValLenWat = "";
        let switchValWat: string;
        if (switchType === "string" && /^\w+$/.test(switchExpr)) {
          switchValPtrWat = `(local.get $${switchExpr}_ptr)`;
          switchValLenWat = `(local.get $${switchExpr}_len)`;
          switchValWat = switchValPtrWat;
          this.needsStringHelpers = true;
        } else {
          switchValWat = duSwitchDef
            ? (() => {
              const sv2 = this.structVars.get(swDotM![1])!;
              return `(i32.load ${
                sv2.ptr === -1 ? `(local.get $${swDotM![1]})` : `(i32.const ${sv2.ptr})`
              })`;
            })()
            : this.emitExpr(switchExpr, locals, switchType === "string" ? "i32" : switchType);
        }
        const nonDefault = cases.filter((c) => !c.isDefault);
        const defaultCase = cases.find((c) => c.isDefault);
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
          const condWat = c.values.map((v) => {
            // Phase 32: DU discriminant switch — convert string literal case to integer tag index
            if (duSwitchDef) {
              const tagStr = v.replace(/^["']|["']$/g, "");
              const tagIdx = duSwitchDef.variants.find((vv) => vv.tag === tagStr)?.tagIndex ?? -1;
              return `(i32.eq ${switchValWat} (i32.const ${tagIdx}))`;
            }
            if (switchType === "string") {
              // Compare string variable against a string literal case value
              const caseStr = v.replace(/^["']|["']$/g, "");
              const [casePtr, caseLen] = this.allocString(caseStr);
              return `(i32.eq (call $__str_cmp ${switchValPtrWat} ${switchValLenWat} (i32.const ${casePtr}) (i32.const ${caseLen})) (i32.const 0))`;
            }
            if (switchType === "f64") {
              return `(f64.eq ${switchValWat} ${this.emitExpr(v, locals, "f64")})`;
            }
            return `(i32.eq ${switchValWat} ${this.emitExpr(v, locals, "i32")})`;
          }).join(" ");
          const condExpr = c.values.length === 1 ? condWat : `(i32.or ${condWat})`;
          switchLines.push(`${indent}${innerPad}(br_if ${caseLabels[k]} ${condExpr})`);
        }
        // Default: jump to default label, or exit if no default
        switchLines.push(`${indent}${innerPad}(br ${defaultCase ? caseLabels[N - 1] : exitLabel})`);

        // Close blocks and emit bodies from innermost (k=0) outward (k=N-1)
        for (let k = 0; k < N; k++) {
          const closePad = "  ".repeat(N - k);
          const bodyPad = indent + closePad + "  ";
          switchLines.push(`${indent}${closePad})`); // close block k
          // Emit body (without break statements — handled via br $exit below)
          const c = orderedCases[k];
          // Pre-process case body: split compound "stmt; break;" lines into two lines
          const expandedBody: string[] = [];
          let hasBreak = false;
          for (const bl of c.body) {
            const bt = bl.trim();
            if (bt === "break;" || bt === "break") {
              hasBreak = true;
            } else if (bt.endsWith("; break;") || bt.endsWith("; break")) {
              const stmtPart = bt.replace(/;\s*break;?\s*$/, ";");
              expandedBody.push(stmtPart);
              hasBreak = true;
            } else {
              expandedBody.push(bl);
            }
          }
          const bodyLines = expandedBody;
          if (bodyLines.length > 0) {
            switchLines.push(this.emitBlock(bodyLines, locals, funcResult, bodyPad));
          }
          // If the original body contained a break, emit br $exit (exits switch)
          if (hasBreak) {
            switchLines.push(`${bodyPad}(br ${exitLabel})`);
          }
        }

        switchLines.push(`${indent})`); // close exit block
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

        // If the catch variable name shadows an outer string local (detected during pre-scan),
        // use an alias WAT name so the outer variable's ptr/len locals are never overwritten.
        const catchShadowsOuter = catchVar !== "" && this.catchVarShadows.has(catchVar);
        const internalCatchVar = catchShadowsOuter ? `__catch_${catchVar}` : catchVar;

        // Patch catch body: rename catchVar → internalCatchVar so emission uses alias locals.
        let catchBodyToEmit = catchBody;
        if (catchShadowsOuter) {
          const cvRe = new RegExp(`\\b${catchVar}\\b`, "g");
          catchBodyToEmit = catchBody.map((l) => l.replace(cvRe, internalCatchVar));
          locals.set(internalCatchVar, "string");
          this.stringVars.add(internalCatchVar);
        }

        const tryWat = this.emitBlock(tryBody, locals, funcResult, indent + "    ");
        const catchWat = hasCatch
          ? this.emitBlock(catchBodyToEmit, locals, funcResult, indent + "    ")
          : "";
        const finallyWat = hasFinally
          ? this.emitBlock(finallyBody, locals, funcResult, indent + "    ")
          : "";

        if (catchShadowsOuter) {
          locals.delete(internalCatchVar);
          this.stringVars.delete(internalCatchVar);
        }

        out.push(`${indent}(try`);
        out.push(`${indent}  (do`);
        if (tryWat) out.push(tryWat);
        if (hasFinally && finallyWat) out.push(finallyWat); // success path: run finally inline
        out.push(`${indent}  )`);

        if (hasCatch) {
          out.push(`${indent}  (catch $__exn_tag`);
          if (internalCatchVar) {
            // Payload is (ptr i32, len i32); len is on top of stack.
            out.push(`${indent}    (local.set $${internalCatchVar}_len)`);
            out.push(`${indent}    (local.set $${internalCatchVar}_ptr)`);
          } else {
            out.push(`${indent}    (drop)`);
            out.push(`${indent}    (drop)`);
          }
          if (catchWat) out.push(catchWat);
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
      if (line === "}" || line === "};") {
        i++;
        continue;
      }

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
        if (depth === 0) {
          terminator = l;
          break;
        }
      } else if (l.match(/^}\s*while\s*\(/)) {
        depth--;
        if (depth === 0) {
          terminator = l;
          break;
        }
      } else if (l === "} else {" || /^}\s*else\s*if\s*\(.*\)\s*\{?$/.test(l)) {
        // At depth 1: terminates the current block (the if-body) — caller will handle the else.
        // At depth > 1: net-zero (inner if-else inside the block), depth unchanged.
        if (depth === 1) {
          depth--;
          terminator = l;
          break;
        }
      } else if (/^}\s*catch\s*(?:\([^)]*\))?\s*\{?$/.test(l) || /^}\s*finally\s*\{?$/.test(l)) {
        // } catch (e) { or } finally { — at depth 1 terminates the try body; at depth > 1 net-zero
        // (inner try/catch inside the block), so treat as neutral (do NOT increment depth).
        if (depth === 1) {
          depth--;
          terminator = l;
          break;
        }
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
        `  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))`,
      );
    }
    // Phase 40: emit import declarations for each external interface method actually called.
    for (const [funcName, sig] of this.usedExternalMethods) {
      const fieldName = funcName.slice(1); // strip leading "$"
      const paramStr = sig.params.map((p) => `(param ${watBaseType(p)})`).join(" ");
      const resultStr = sig.result ? ` (result ${watBaseType(sig.result)})` : "";
      lines.push(
        `  (import "env" "${fieldName}" (func ${funcName}${
          paramStr ? " " + paramStr : ""
        }${resultStr}))`,
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
  )
  ;; Canonical ABI allocator — fresh allocation (ptr==0) delegates to $__malloc;
  ;; realloc requests (ptr!=0) return ptr unchanged (bump allocator has no free).
  (func $cabi_realloc (param $ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
    (select
      (call $__malloc (local.get $new_size))
      (local.get $ptr)
      (i32.eqz (local.get $ptr))
    )
  )`);
    if (this.needsStringHelpers) parts.push(this.getStringHelperWat());
    // getStringExtHelperWat() includes $__str_replace/$__str_split which depend on
    // $__str_indexof/$__str_gather from getStringOpHelperWat(), so emit op helpers together.
    if (this.needsStringOpHelpers || this.needsStrGatherHelper || this.needsStringExtHelpers) {
      parts.push(this.getStringOpHelperWat());
    }
    if (this.needsStringExtHelpers) parts.push(this.getStringExtHelperWat());
    if (this.needsNumericHelpers) parts.push(getHelperWat());
    if (this.needsArrPrintHelper) parts.push(getArrPrintHelperWat());
    if (this.needsJoinHelper) parts.push(getJoinHelperWat());
    if (this.mathHelpers.size > 0) parts.push(this.emitMathHelpers());
    if (this.dynArrHelpers.size > 0) parts.push(this.emitDynArrHelpers());
    if (this.typedArrHelpers.size > 0) parts.push(this.emitTypedArrHelpers());
    if (this.needsMatrix2DPrintHelper) parts.push(this.emitMatrix2DPrintHelper());
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
      `  ;; Math.pow — iterative for integer exponents; sqrt special case for exp=0.5
  (func $__math_pow (param $base f64) (param $exp f64) (result f64)
    (local $result f64)
    (local $n i32)
    (if (f64.eq (local.get $exp) (f64.const 0.5))
      (then (return (f64.sqrt (local.get $base)))))
    (if (f64.eq (local.get $exp) (f64.const -0.5))
      (then (return (f64.div (f64.const 1) (f64.sqrt (local.get $base))))))
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

  /** Phase 31: Emits TypedArray helper functions (fill, set) for each requested element type. */
  private emitTypedArrHelpers(): string {
    const parts: string[] = [];
    for (const key of this.typedArrHelpers) {
      if (key.startsWith("fill_")) {
        const elemType = key.slice(5) as WatType;
        const watElem = watBaseType(elemType);
        const shift = elemType === "f64" || elemType === "i64" ? 3 : elemType === "f32" ? 2 : 2;
        const storeOp = elemType === "f64"
          ? "f64.store"
          : elemType === "f32"
          ? "f32.store"
          : elemType === "i64"
          ? "i64.store"
          : "i32.store";
        parts.push(`  ;; Phase 31: TypedArray fill — fills elements [start,end) with val
  (func $__ta_fill_${elemType} (param $arr i32) (param $val ${watElem}) (param $start i32) (param $end i32)
    (local $i i32)
    (local $data i32)
    (local.set $data (i32.add (local.get $arr) (i32.const 8)))
    (local.set $i (local.get $start))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $end)))
        (${storeOp} (i32.add (local.get $data) (i32.shl (local.get $i) (i32.const ${shift}))) (local.get $val))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )`);
      }
      if (key.startsWith("set_")) {
        const elemType = key.slice(4) as WatType;
        const shift = elemType === "f64" || elemType === "i64" ? 3 : elemType === "f32" ? 2 : 2;
        const loadOp = elemType === "f64"
          ? "f64.load"
          : elemType === "f32"
          ? "f32.load"
          : elemType === "i64"
          ? "i64.load"
          : "i32.load";
        const storeOp = elemType === "f64"
          ? "f64.store"
          : elemType === "f32"
          ? "f32.store"
          : elemType === "i64"
          ? "i64.store"
          : "i32.store";
        parts.push(
          `  ;; Phase 31: TypedArray set — copies elements from src into dst starting at offset
  (func $__ta_set_${elemType} (param $dst i32) (param $src i32) (param $offset i32)
    (local $i i32)
    (local $len i32)
    (local $dst_data i32)
    (local $src_data i32)
    (local.set $len (i32.load (local.get $src)))
    (local.set $dst_data (i32.add (local.get $dst) (i32.const 8)))
    (local.set $src_data (i32.add (local.get $src) (i32.const 8)))
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (${storeOp}
          (i32.add (local.get $dst_data) (i32.shl (i32.add (local.get $i) (local.get $offset)) (i32.const ${shift})))
          (${loadOp} (i32.add (local.get $src_data) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )`,
        );
      }
    }
    return parts.join("\n\n");
  }

  /** Phase 6d: Emits $__print_2d_i32_arr — writes "[ [ 1, 2 ], [ 3, 4 ] ]" to buf, returns bytes written. */
  private emitMatrix2DPrintHelper(): string {
    return `  ;; Phase 6d: print a 2D i32 array as "[ [ e, ... ], ... ]", returns bytes written.
  (func $__print_2d_i32_arr (param $arr i32) (param $buf i32) (result i32)
    (local $ptr i32)
    (local $outerLen i32)
    (local $i i32)
    (local $inner i32)
    (local $innerLen i32)
    (local $j i32)
    (local $elem i32)
    (local.set $ptr (local.get $buf))
    (local.set $outerLen (i32.load (local.get $arr)))
    (i32.store8 (local.get $ptr) (i32.const 91))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (i32.store8 (local.get $ptr) (i32.const 32))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (local.set $i (i32.const 0))
    (block $outer_done
      (loop $outer_loop
        (br_if $outer_done (i32.ge_u (local.get $i) (local.get $outerLen)))
        (local.set $inner (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
        (local.set $innerLen (i32.load (local.get $inner)))
        (i32.store8 (local.get $ptr) (i32.const 91))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (i32.store8 (local.get $ptr) (i32.const 32))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $j (i32.const 0))
        (block $inner_done
          (loop $inner_loop
            (br_if $inner_done (i32.ge_u (local.get $j) (local.get $innerLen)))
            (local.set $elem (i32.load (i32.add (i32.add (local.get $inner) (i32.const 8)) (i32.shl (local.get $j) (i32.const 2)))))
            (local.set $ptr (i32.add (local.get $ptr) (call $__i32_to_str (local.get $elem) (local.get $ptr))))
            (if (i32.lt_u (i32.add (local.get $j) (i32.const 1)) (local.get $innerLen))
              (then
                (i32.store8 (local.get $ptr) (i32.const 44))
                (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
                (i32.store8 (local.get $ptr) (i32.const 32))
                (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))))
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner_loop)))
        (i32.store8 (local.get $ptr) (i32.const 32))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (i32.store8 (local.get $ptr) (i32.const 93))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (if (i32.lt_u (i32.add (local.get $i) (i32.const 1)) (local.get $outerLen))
          (then
            (i32.store8 (local.get $ptr) (i32.const 44))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
            (i32.store8 (local.get $ptr) (i32.const 32))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer_loop)))
    (i32.store8 (local.get $ptr) (i32.const 32))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (i32.store8 (local.get $ptr) (i32.const 93))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (i32.sub (local.get $ptr) (local.get $buf)))`;
  }

  private emitDynArrHelpers(): string {
    const parts: string[] = [];

    // Determine which grow helpers are needed (one per elem type used by push or unshift).
    const growNeeded = new Set<string>();
    for (const key of this.dynArrHelpers) {
      if (key === "push_string") {
        growNeeded.add("string");
        continue;
      }
      const [method, elemType] = key.split("_");
      if (method === "push" || method === "unshift") growNeeded.add(elemType);
    }

    // Emit grow helpers first (push/unshift call them).
    for (const elemType of growNeeded) {
      // String arrays store 8-byte (ptr,len) pairs — use f64.load/store for bit-identical 8-byte copy.
      const isF64 = elemType === "f64" || elemType === "string";
      const shift = isF64 ? 3 : 2;
      const loadOp = isF64 ? "f64.load" : "i32.load";
      const storeOp = isF64 ? "f64.store" : "i32.store";
      parts.push(
        `  ;; Dynamic array grow_${elemType}: malloc new block of newcap elements, copy data, return new ptr.
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
  )`,
      );
    }

    // Emit only the helpers actually used in this module.
    for (const key of this.dynArrHelpers) {
      const [method, elemType] = key.split("_") as [string, WatType];
      const isF64 = elemType === "f64";
      const shift = isF64 ? 3 : 2;
      const loadOp = isF64 ? "f64.load" : "i32.load";
      const storeOp = isF64 ? "f64.store" : "i32.store";
      const valType = isF64 ? "f64" : "i32";
      const name = `$__dynarr_${key}`;

      if (method === "push" && key !== "push_string") {
        parts.push(
          `  ;; Dynamic array push_${elemType}: grow if full, store val at end, increment length, return new arr ptr.
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
  )`,
        );
      } else if (method === "pop") {
        parts.push(
          `  ;; Dynamic array pop_${elemType}: decrement length, return last element. Traps if empty.
  (func ${name} (param $arr i32) (result ${valType})
    (local $newlen i32)
    (if (i32.eqz (i32.load (local.get $arr))) (then (unreachable)))
    (local.set $newlen (i32.sub (i32.load (local.get $arr)) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $newlen))
    (${loadOp}
      (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $newlen) (i32.const ${shift})))
    )
  )`,
        );
      } else if (method === "shift") {
        parts.push(
          `  ;; Dynamic array shift_${elemType}: return first element, shift remainder left. Traps if empty.
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
  )`,
        );
      } else if (method === "unshift") {
        parts.push(
          `  ;; Dynamic array unshift_${elemType}: grow if full, insert val at front, shift elements right, return new arr ptr.
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
  )`,
        );
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
      } else if (method === "slice" && key !== "slice_string") {
        parts.push(
          `  ;; Dynamic array slice_${elemType}: alloc new array from [start,end), clamp to bounds.
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
  )`,
        );
      } else if (key === "slice_string") {
        // String array slice: copy 8-byte (ptr,len) pairs using f64.load/store for bit-identical copy.
        parts.push(
          `  ;; Dynamic string array slice: alloc new array from [start,end), copy (ptr,len) pairs.
  (func $__dynarr_slice_string (param $arr i32) (param $start i32) (param $end i32) (result i32)
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
    (local.set $newptr (call $__malloc (i32.add (i32.const 8) (i32.shl (local.get $newlen) (i32.const 3)))))
    (i32.store (local.get $newptr) (local.get $newlen))
    (i32.store offset=4 (local.get $newptr) (local.get $newlen))
    (block $done
      (loop $lp
        (br_if $done (i32.ge_u (local.get $i) (local.get $newlen)))
        (f64.store
          (i32.add (i32.add (local.get $newptr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 3)))
          (f64.load
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (local.get $start)) (i32.const 3)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $newptr)
  )`,
        );
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
        parts.push(
          `  ;; Dynamic array filter_${elemType}: alloc new array with elements where fn(elem) is truthy.
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
  )`,
        );
      } else if (method === "find") {
        // Register callback type: (elemType) → i32
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        const notFound = isF64 ? "(f64.const nan)" : "(i32.const -1)";
        parts.push(
          `  ;; Dynamic array find_${elemType}: return first elem where fn(elem) is truthy, or ${
            isF64 ? "NaN" : "-1"
          }.
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
  )`,
        );
      } else if (method === "reduce") {
        // Register callback type: (elemType, elemType) → elemType
        const ftName = this.getOrCreateFuncType([elemType, elemType], elemType);
        parts.push(
          `  ;; Dynamic array reduce_${elemType}: fold array with fn(acc, elem), starting from init.
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
  )`,
        );
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
      } else if (method === "every") {
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        parts.push(
          `  ;; Dynamic array every_${elemType}: returns 1 if fn(elem) is truthy for all elements, else 0.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (if (i32.eqz
              (call_indirect (type ${ftName})
                (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
                (local.get $fn)))
          (then (return (i32.const 0)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const 1)
  )`,
        );
      } else if (method === "some") {
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        parts.push(
          `  ;; Dynamic array some_${elemType}: returns 1 if fn(elem) is truthy for any element, else 0.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (if (call_indirect (type ${ftName})
              (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
              (local.get $fn))
          (then (return (i32.const 1)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const 0)
  )`,
        );
      } else if (method === "findindex") {
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        parts.push(`  ;; Dynamic array findindex_${elemType}: returns index of first match or -1.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $len)))
        (if (call_indirect (type ${ftName})
              (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift}))))
              (local.get $fn))
          (then (return (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.const -1)
  )`);
      } else if (method === "at") {
        parts.push(`  ;; Dynamic array at_${elemType}: element at index n (negative wraps from end).
  (func ${name} (param $arr i32) (param $n i32) (result ${valType})
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (if (i32.lt_s (local.get $n) (i32.const 0))
      (then (local.set $n (i32.add (local.get $len) (local.get $n))))
    )
    (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $n) (i32.const ${shift}))))
  )`);
      } else if (method === "reverse") {
        parts.push(`  ;; Dynamic array reverse_${elemType}: in-place reversal, returns arr ptr.
  (func ${name} (param $arr i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $tmp ${valType})
    (local $len i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $j (i32.sub (local.get $len) (i32.const 1)))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $j)))
        (local.set $tmp (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (${storeOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (${loadOp} (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $j) (i32.const ${shift})))))
        (${storeOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $j) (i32.const ${shift})))
          (local.get $tmp))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (local.set $j (i32.sub (local.get $j) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $arr)
  )`);
      } else if (method === "fill") {
        parts.push(
          `  ;; Dynamic array fill_${elemType}: fill [start,end) with val, clamped to bounds.
  (func ${name} (param $arr i32) (param $val ${valType}) (param $start i32) (param $end i32) (result i32)
    (local $len i32)
    (local $i i32)
    (local.set $len (i32.load (local.get $arr)))
    (if (i32.lt_s (local.get $start) (i32.const 0)) (then (local.set $start (i32.const 0))))
    (if (i32.gt_s (local.get $start) (local.get $len)) (then (local.set $start (local.get $len))))
    (if (i32.lt_s (local.get $end) (i32.const 0)) (then (local.set $end (i32.const 0))))
    (if (i32.gt_s (local.get $end) (local.get $len)) (then (local.set $end (local.get $len))))
    (local.set $i (local.get $start))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $end)))
        (${storeOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))
          (local.get $val))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (local.get $arr)
  )`,
        );
      } else if (method === "sort" && key !== "sort_string") {
        const cmpOp = isF64 ? "f64.gt" : "i32.gt_s";
        parts.push(
          `  ;; Dynamic array sort_${elemType}: in-place insertion sort (ascending), returns arr ptr.
  (func ${name} (param $arr i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $key ${valType})
    (local $len i32)
    (local $base i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $base (i32.add (local.get $arr) (i32.const 8)))
    (local.set $i (i32.const 1))
    (block $outer
      (loop $olp
        (br_if $outer (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $key (${loadOp} (i32.add (local.get $base) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $j (i32.sub (local.get $i) (i32.const 1)))
        (block $inner
          (loop $ilp
            (br_if $inner (i32.lt_s (local.get $j) (i32.const 0)))
            (if (${cmpOp}
                  (${loadOp} (i32.add (local.get $base) (i32.shl (local.get $j) (i32.const ${shift}))))
                  (local.get $key))
              (then
                (${storeOp}
                  (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const ${shift})))
                  (${loadOp} (i32.add (local.get $base) (i32.shl (local.get $j) (i32.const ${shift})))))
                (local.set $j (i32.sub (local.get $j) (i32.const 1)))
                (br $ilp)
              )
              (else (br $inner))
            )
          )
        )
        (${storeOp}
          (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const ${shift})))
          (local.get $key))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $olp)
      )
    )
    (local.get $arr)
  )`,
        );
      } else if (method === "sortcmp") {
        const ftName = this.getOrCreateFuncType([elemType, elemType], "i32");
        parts.push(
          `  ;; Dynamic array sortcmp_${elemType}: in-place insertion sort with comparator, returns arr ptr.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $key ${valType})
    (local $aj ${valType})
    (local $len i32)
    (local $base i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $base (i32.add (local.get $arr) (i32.const 8)))
    (local.set $i (i32.const 1))
    (block $outer
      (loop $olp
        (br_if $outer (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $key (${loadOp} (i32.add (local.get $base) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $j (i32.sub (local.get $i) (i32.const 1)))
        (block $inner
          (loop $ilp
            (br_if $inner (i32.lt_s (local.get $j) (i32.const 0)))
            (local.set $aj (${loadOp} (i32.add (local.get $base) (i32.shl (local.get $j) (i32.const ${shift})))))
            (if (i32.gt_s
                  (call_indirect (type ${ftName}) (local.get $aj) (local.get $key) (local.get $fn))
                  (i32.const 0))
              (then
                (${storeOp}
                  (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const ${shift})))
                  (local.get $aj))
                (local.set $j (i32.sub (local.get $j) (i32.const 1)))
                (br $ilp)
              )
              (else (br $inner))
            )
          )
        )
        (${storeOp}
          (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const ${shift})))
          (local.get $key))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $olp)
      )
    )
    (local.get $arr)
  )`,
        );
      } else if (method === "flat") {
        // Outer array holds i32 pointers (shift=2) to inner arrays of elemType.
        const innerShift = isF64 ? 3 : 2;
        const innerLoadOp = isF64 ? "f64.load" : "i32.load";
        const innerStoreOp = isF64 ? "f64.store" : "i32.store";
        parts.push(
          `  ;; Dynamic array flat_${elemType}: one-level flatten of 2D array (outer=i32 ptrs, inner=${elemType}).
  (func ${name} (param $arr i32) (result i32)
    (local $outerLen i32)
    (local $i i32)
    (local $innerPtr i32)
    (local $innerLen i32)
    (local $totalLen i32)
    (local $result i32)
    (local $j i32)
    (local $dst i32)
    ;; Pass 1: sum inner lengths
    (local.set $outerLen (i32.load (local.get $arr)))
    (local.set $i (i32.const 0))
    (block $done1
      (loop $lp1
        (br_if $done1 (i32.ge_u (local.get $i) (local.get $outerLen)))
        (local.set $innerPtr (i32.load
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
        (local.set $totalLen (i32.add (local.get $totalLen) (i32.load (local.get $innerPtr))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp1)
      )
    )
    ;; Allocate result array
    (local.set $result (call $__malloc
      (i32.add (i32.const 8) (i32.shl (local.get $totalLen) (i32.const ${innerShift})))))
    (i32.store (local.get $result) (local.get $totalLen))
    (i32.store offset=4 (local.get $result) (local.get $totalLen))
    ;; Pass 2: copy inner elements
    (local.set $i (i32.const 0))
    (block $done2
      (loop $lp2
        (br_if $done2 (i32.ge_u (local.get $i) (local.get $outerLen)))
        (local.set $innerPtr (i32.load
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))))
        (local.set $innerLen (i32.load (local.get $innerPtr)))
        (local.set $j (i32.const 0))
        (block $idone
          (loop $ilp
            (br_if $idone (i32.ge_u (local.get $j) (local.get $innerLen)))
            (${innerStoreOp}
              (i32.add (i32.add (local.get $result) (i32.const 8))
                (i32.shl (local.get $dst) (i32.const ${innerShift})))
              (${innerLoadOp}
                (i32.add (i32.add (local.get $innerPtr) (i32.const 8))
                  (i32.shl (local.get $j) (i32.const ${innerShift})))))
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
            (br $ilp)
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp2)
      )
    )
    (local.get $result)
  )`,
        );
      } else if (method === "flatmap") {
        // fn: (elemType) → i32  (i32 = ptr to inner array of elemType)
        const ftName = this.getOrCreateFuncType([elemType], "i32");
        const innerShift = isF64 ? 3 : 2;
        const innerLoadOp = isF64 ? "f64.load" : "i32.load";
        const innerStoreOp = isF64 ? "f64.store" : "i32.store";
        parts.push(
          `  ;; Dynamic array flatmap_${elemType}: map each elem to inner array via fn, then flatten.
  (func ${name} (param $arr i32) (param $fn i32) (result i32)
    (local $len i32)
    (local $i i32)
    (local $elem ${valType})
    (local $innerPtr i32)
    (local $innerLen i32)
    (local $totalLen i32)
    (local $tmparr i32)
    (local $result i32)
    (local $j i32)
    (local $dst i32)
    (local.set $len (i32.load (local.get $arr)))
    ;; Allocate temp storage for inner ptrs (len * 4 bytes, no header)
    (local.set $tmparr (call $__malloc (i32.shl (local.get $len) (i32.const 2))))
    ;; Pass 1: call fn(elem) for each, store inner ptr, accumulate total length
    (local.set $i (i32.const 0))
    (block $done1
      (loop $lp1
        (br_if $done1 (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $elem (${loadOp}
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const ${shift})))))
        (local.set $innerPtr
          (call_indirect (type ${ftName}) (local.get $elem) (local.get $fn)))
        (i32.store
          (i32.add (local.get $tmparr) (i32.shl (local.get $i) (i32.const 2)))
          (local.get $innerPtr))
        (local.set $totalLen (i32.add (local.get $totalLen) (i32.load (local.get $innerPtr))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp1)
      )
    )
    ;; Allocate result array
    (local.set $result (call $__malloc
      (i32.add (i32.const 8) (i32.shl (local.get $totalLen) (i32.const ${innerShift})))))
    (i32.store (local.get $result) (local.get $totalLen))
    (i32.store offset=4 (local.get $result) (local.get $totalLen))
    ;; Pass 2: copy elements from each inner array
    (local.set $i (i32.const 0))
    (block $done2
      (loop $lp2
        (br_if $done2 (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $innerPtr (i32.load
          (i32.add (local.get $tmparr) (i32.shl (local.get $i) (i32.const 2)))))
        (local.set $innerLen (i32.load (local.get $innerPtr)))
        (local.set $j (i32.const 0))
        (block $idone
          (loop $ilp
            (br_if $idone (i32.ge_u (local.get $j) (local.get $innerLen)))
            (${innerStoreOp}
              (i32.add (i32.add (local.get $result) (i32.const 8))
                (i32.shl (local.get $dst) (i32.const ${innerShift})))
              (${innerLoadOp}
                (i32.add (i32.add (local.get $innerPtr) (i32.const 8))
                  (i32.shl (local.get $j) (i32.const ${innerShift})))))
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
            (br $ilp)
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp2)
      )
    )
    (local.get $result)
  )`,
        );
      } else if (key === "push_string") {
        // String array push: stores ptr+len pair (8 bytes per element), grows if needed.
        parts.push(
          `  ;; Dynamic string array push_string: grow if full, store (ptr,len) at end, return new arr ptr.
  (func $__dynarr_push_string (param $arr i32) (param $ptr i32) (param $len i32) (result i32)
    (local $elemLen i32)
    (local $cap i32)
    (local $base i32)
    (local.set $elemLen (i32.load (local.get $arr)))
    (local.set $cap (i32.load offset=4 (local.get $arr)))
    (if (i32.ge_u (local.get $elemLen) (local.get $cap))
      (then
        (local.set $arr (call $__dynarr_grow_string (local.get $arr) (i32.shl (local.get $cap) (i32.const 1))))
      )
    )
    (local.set $base (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $elemLen) (i32.const 3))))
    (i32.store (local.get $base) (local.get $ptr))
    (i32.store offset=4 (local.get $base) (local.get $len))
    (i32.store (local.get $arr) (i32.add (local.get $elemLen) (i32.const 1)))
    (local.get $arr)
  )`,
        );
      } else if (key === "splice_i32") {
        // Remove count elements in-place starting at idx (4-byte elements).
        parts.push(`  ;; Dynamic array splice_i32: remove count elements at idx in-place.
  (func $__dynarr_splice_i32 (param $arr i32) (param $idx i32) (param $count i32)
    (local $len i32)
    (local $i i32)
    (local $end i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $end (i32.sub (local.get $len) (local.get $count)))
    (local.set $i (local.get $idx))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $end)))
        (i32.store
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 2)))
          (i32.load
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (local.get $count)) (i32.const 2)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.store (local.get $arr) (local.get $end))
  )`);
      } else if (key === "splice_f64") {
        // Remove count elements in-place starting at idx (8-byte elements; also used for string arrays).
        parts.push(
          `  ;; Dynamic array splice_f64: remove count elements at idx in-place (8-byte elements).
  (func $__dynarr_splice_f64 (param $arr i32) (param $idx i32) (param $count i32)
    (local $len i32)
    (local $i i32)
    (local $end i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $end (i32.sub (local.get $len) (local.get $count)))
    (local.set $i (local.get $idx))
    (block $brk
      (loop $lp
        (br_if $brk (i32.ge_u (local.get $i) (local.get $end)))
        (f64.store
          (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $i) (i32.const 3)))
          (f64.load
            (i32.add (i32.add (local.get $arr) (i32.const 8))
              (i32.shl (i32.add (local.get $i) (local.get $count)) (i32.const 3)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $lp)
      )
    )
    (i32.store (local.get $arr) (local.get $end))
  )`,
        );
      } else if (key === "sort_string") {
        // Insertion sort for string arrays: compare pairs (ptr,len) lexicographically via $__str_cmp.
        this.needsStringHelpers = true;
        parts.push(
          `  ;; Dynamic string array sort: in-place insertion sort via lexicographic $__str_cmp.
  (func $__dynarr_sort_string (param $arr i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $len i32)
    (local $base i32)
    (local $keyPtr i32)
    (local $keyLen i32)
    (local $jPtr i32)
    (local $jLen i32)
    (local $addr i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $base (i32.add (local.get $arr) (i32.const 8)))
    (local.set $i (i32.const 1))
    (block $outer
      (loop $olp
        (br_if $outer (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $addr (i32.add (local.get $base) (i32.shl (local.get $i) (i32.const 3))))
        (local.set $keyPtr (i32.load (local.get $addr)))
        (local.set $keyLen (i32.load offset=4 (local.get $addr)))
        (local.set $j (i32.sub (local.get $i) (i32.const 1)))
        (block $inner
          (loop $ilp
            (br_if $inner (i32.lt_s (local.get $j) (i32.const 0)))
            (local.set $addr (i32.add (local.get $base) (i32.shl (local.get $j) (i32.const 3))))
            (local.set $jPtr (i32.load (local.get $addr)))
            (local.set $jLen (i32.load offset=4 (local.get $addr)))
            (if (i32.gt_s
                  (call $__str_cmp (local.get $jPtr) (local.get $jLen) (local.get $keyPtr) (local.get $keyLen))
                  (i32.const 0))
              (then
                ;; Shift element at j to j+1
                (local.set $addr (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const 3))))
                (i32.store (local.get $addr) (local.get $jPtr))
                (i32.store offset=4 (local.get $addr) (local.get $jLen))
                (local.set $j (i32.sub (local.get $j) (i32.const 1)))
                (br $ilp)
              )
              (else (br $inner))
            )
          )
        )
        ;; Write key into position j+1
        (local.set $addr (i32.add (local.get $base) (i32.shl (i32.add (local.get $j) (i32.const 1)) (i32.const 3))))
        (i32.store (local.get $addr) (local.get $keyPtr))
        (i32.store offset=4 (local.get $addr) (local.get $keyLen))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $olp)
      )
    )
    (local.get $arr)
  )`,
        );
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
  )

  ;; ── str_indexof_from: first occurrence of sub in str starting at 'from', or -1 ─
  (func $__str_indexof_from
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32) (param $from i32)
    (result i32)
    (local $i i32) (local $j i32) (local $max i32) (local $ok i32)
    (if (i32.eqz (local.get $sublen)) (then (return (local.get $from))))
    (local.set $max (i32.sub (local.get $len) (local.get $sublen)))
    (if (i32.lt_s (local.get $max) (i32.const 0)) (then (return (i32.const -1))))
    (local.set $i (select (i32.const 0) (local.get $from) (i32.lt_s (local.get $from) (i32.const 0))))
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

  // Phase 27: Extended string helpers — trim, charCodeAt, charAt, case conversion,
  // replace, replaceAll, padStart, padEnd, repeat, split.
  private getStringExtHelperWat(): string {
    return `
  ;; ── str_trim: remove leading and trailing ASCII whitespace ─────────────────
  ;; Whitespace = 0x09 (tab), 0x0a (LF), 0x0d (CR), 0x20 (space).
  ;; Returns (new_ptr, new_len) which is a sub-range of the original buffer.
  (func $__str_trim
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $s i32) (local $e i32) (local $b i32)
    (local.set $s (i32.const 0))
    (local.set $e (local.get $len))
    ;; advance $s past leading whitespace
    (block $done_s
      (loop $loop_s
        (br_if $done_s (i32.ge_u (local.get $s) (local.get $e)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $s))))
        (br_if $done_s (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $s (i32.add (local.get $s) (i32.const 1)))
        (br $loop_s)
      )
    )
    ;; retreat $e past trailing whitespace
    (block $done_e
      (loop $loop_e
        (br_if $done_e (i32.le_u (local.get $e) (local.get $s)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $e) (i32.const 1)))))
        (br_if $done_e (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $e (i32.sub (local.get $e) (i32.const 1)))
        (br $loop_e)
      )
    )
    (i32.add (local.get $ptr) (local.get $s))
    (i32.sub (local.get $e) (local.get $s))
  )

  ;; ── str_trim_start: remove leading ASCII whitespace ──────────────────────────
  (func $__str_trim_start
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $s i32) (local $b i32)
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $s) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $s))))
        (br_if $done (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $s (i32.add (local.get $s) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.add (local.get $ptr) (local.get $s))
    (i32.sub (local.get $len) (local.get $s))
  )

  ;; ── str_trim_end: remove trailing ASCII whitespace ───────────────────────────
  (func $__str_trim_end
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $e i32) (local $b i32)
    (local.set $e (local.get $len))
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $e)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $e) (i32.const 1)))))
        (br_if $done (i32.and
          (i32.and (i32.ne (local.get $b) (i32.const 0x20)) (i32.ne (local.get $b) (i32.const 0x09)))
          (i32.and (i32.ne (local.get $b) (i32.const 0x0a)) (i32.ne (local.get $b) (i32.const 0x0d)))
        ))
        (local.set $e (i32.sub (local.get $e) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $ptr)
    (local.get $e)
  )

  ;; ── str_char_code_at: char code at index i, or -1 if out of bounds ───────────
  (func $__str_char_code_at
    (param $ptr i32) (param $len i32) (param $i i32)
    (result i32)
    (if (i32.lt_s (local.get $i) (i32.const 0)) (then (return (i32.const -1))))
    (if (i32.ge_u (local.get $i) (local.get $len)) (then (return (i32.const -1))))
    (i32.load8_u (i32.add (local.get $ptr) (local.get $i)))
  )

  ;; ── str_char_at: single-char sub-string at index i ───────────────────────────
  ;; Returns (ptr+i, 1) if in bounds, (ptr, 0) if out of bounds.
  (func $__str_char_at
    (param $ptr i32) (param $len i32) (param $i i32)
    (result i32 i32)
    (if (i32.lt_s (local.get $i) (i32.const 0))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (if (i32.ge_u (local.get $i) (local.get $len))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (i32.add (local.get $ptr) (local.get $i))
    (i32.const 1)
  )

  ;; ── str_starts_with: true if str begins with sub ─────────────────────────────
  (func $__str_starts_with
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $j i32)
    (if (i32.gt_u (local.get $sublen) (local.get $len)) (then (return (i32.const 0))))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $j) (local.get $sublen)))
        (if (i32.ne
          (i32.load8_u (i32.add (local.get $ptr) (local.get $j)))
          (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
        ) (then (return (i32.const 0))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.const 1)
  )

  ;; ── str_ends_with: true if str ends with sub ─────────────────────────────────
  (func $__str_ends_with
    (param $ptr i32) (param $len i32) (param $subptr i32) (param $sublen i32)
    (result i32)
    (local $j i32) (local $off i32)
    (if (i32.gt_u (local.get $sublen) (local.get $len)) (then (return (i32.const 0))))
    (local.set $off (i32.sub (local.get $len) (local.get $sublen)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $j) (local.get $sublen)))
        (if (i32.ne
          (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $off) (local.get $j))))
          (i32.load8_u (i32.add (local.get $subptr) (local.get $j)))
        ) (then (return (i32.const 0))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.const 1)
  )

  ;; ── str_to_upper: ASCII uppercase into a new heap buffer ────────────────────
  (func $__str_to_upper
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $newptr i32) (local $i i32) (local $b i32)
    (local.set $newptr (call $__malloc (local.get $len)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (if (i32.and (i32.ge_u (local.get $b) (i32.const 97)) (i32.le_u (local.get $b) (i32.const 122)))
          (then (local.set $b (i32.sub (local.get $b) (i32.const 32))))
        )
        (i32.store8 (i32.add (local.get $newptr) (local.get $i)) (local.get $b))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $newptr)
    (local.get $len)
  )

  ;; ── str_to_lower: ASCII lowercase into a new heap buffer ────────────────────
  (func $__str_to_lower
    (param $ptr i32) (param $len i32)
    (result i32 i32)
    (local $newptr i32) (local $i i32) (local $b i32)
    (local.set $newptr (call $__malloc (local.get $len)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $b (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (if (i32.and (i32.ge_u (local.get $b) (i32.const 65)) (i32.le_u (local.get $b) (i32.const 90)))
          (then (local.set $b (i32.add (local.get $b) (i32.const 32))))
        )
        (i32.store8 (i32.add (local.get $newptr) (local.get $i)) (local.get $b))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $newptr)
    (local.get $len)
  )

  ;; ── str_replace: replace first occurrence of old with new ───────────────────
  ;; Returns new heap string (or original ptr/len if old not found).
  (func $__str_replace
    (param $ptr i32) (param $len i32)
    (param $oldptr i32) (param $oldlen i32)
    (param $newptr i32) (param $newlen i32)
    (result i32 i32)
    (local $pos i32) (local $outlen i32) (local $out i32) (local $wi i32)
    (local.set $pos (call $__str_indexof (local.get $ptr) (local.get $len) (local.get $oldptr) (local.get $oldlen)))
    (if (i32.eq (local.get $pos) (i32.const -1))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $outlen (i32.add (i32.sub (local.get $len) (local.get $oldlen)) (local.get $newlen)))
    (local.set $out (call $__malloc (local.get $outlen)))
    ;; copy prefix [0, pos)
    (local.set $wi (i32.const 0))
    (block $d0 (loop $l0
      (br_if $d0 (i32.ge_u (local.get $wi) (local.get $pos)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $wi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l0)
    ))
    ;; copy new string
    (block $d1 (loop $l1
      (br_if $d1 (i32.ge_u (local.get $wi) (i32.add (local.get $pos) (local.get $newlen))))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $newptr) (i32.sub (local.get $wi) (local.get $pos)))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l1)
    ))
    ;; copy suffix [pos+oldlen, len)
    (block $d2 (loop $l2
      (br_if $d2 (i32.ge_u (local.get $wi) (local.get $outlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (i32.sub (i32.add (local.get $wi) (local.get $oldlen)) (local.get $newlen)))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $l2)
    ))
    (local.get $out)
    (local.get $outlen)
  )

  ;; ── str_replace_all: replace all occurrences of old with new ────────────────
  (func $__str_replace_all
    (param $ptr i32) (param $len i32)
    (param $oldptr i32) (param $oldlen i32)
    (param $newptr i32) (param $newlen i32)
    (result i32 i32)
    (local $cur i32) (local $pos i32) (local $buf i32) (local $blen i32)
    (local $wi i32) (local $ri i32) (local $seglen i32)
    ;; worst-case capacity: outlen <= len * (newlen/oldlen + 1) — allocate generously
    ;; simple heuristic: (len + 1) * (newlen + 1)
    (local.set $blen (i32.mul (i32.add (local.get $len) (i32.const 1)) (i32.add (local.get $newlen) (i32.const 1))))
    (local.set $buf (call $__malloc (local.get $blen)))
    (local.set $cur (i32.const 0))
    (local.set $wi (i32.const 0))
    (block $done
      (loop $loop
        ;; find next occurrence from $cur
        (local.set $pos (call $__str_indexof
          (i32.add (local.get $ptr) (local.get $cur))
          (i32.sub (local.get $len) (local.get $cur))
          (local.get $oldptr) (local.get $oldlen)
        ))
        (if (i32.eq (local.get $pos) (i32.const -1)) (then (br $done)))
        (local.set $pos (i32.add (local.get $pos) (local.get $cur)))
        ;; copy segment before match
        (local.set $seglen (i32.sub (local.get $pos) (local.get $cur)))
        (local.set $ri (i32.const 0))
        (block $ds (loop $ls
          (br_if $ds (i32.ge_u (local.get $ri) (local.get $seglen)))
          (i32.store8 (i32.add (local.get $buf) (local.get $wi))
            (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $cur) (local.get $ri)))))
          (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
          (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
          (br $ls)
        ))
        ;; copy new string
        (local.set $ri (i32.const 0))
        (block $dn (loop $ln
          (br_if $dn (i32.ge_u (local.get $ri) (local.get $newlen)))
          (i32.store8 (i32.add (local.get $buf) (local.get $wi))
            (i32.load8_u (i32.add (local.get $newptr) (local.get $ri))))
          (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
          (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
          (br $ln)
        ))
        (local.set $cur (i32.add (local.get $pos) (i32.add (local.get $oldlen) (i32.const 0))))
        ;; guard against zero-length old (avoid infinite loop)
        (if (i32.eqz (local.get $oldlen))
          (then
            (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
            (if (i32.gt_u (local.get $cur) (local.get $len)) (then (br $done)))
          )
        )
        (br $loop)
      )
    )
    ;; copy remaining tail
    (local.set $ri (local.get $cur))
    (block $dt (loop $lt
      (br_if $dt (i32.ge_u (local.get $ri) (local.get $len)))
      (i32.store8 (i32.add (local.get $buf) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $ri))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (local.set $ri (i32.add (local.get $ri) (i32.const 1)))
      (br $lt)
    ))
    (local.get $buf)
    (local.get $wi)
  )

  ;; ── str_pad_start: pad string to targetLen with pad chars on the left ────────
  (func $__str_pad_start
    (param $ptr i32) (param $len i32) (param $target i32) (param $padptr i32) (param $padlen i32)
    (result i32 i32)
    (local $out i32) (local $need i32) (local $wi i32) (local $pi i32)
    (if (i32.le_s (local.get $target) (local.get $len))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $need (i32.sub (local.get $target) (local.get $len)))
    (local.set $out (call $__malloc (local.get $target)))
    ;; fill pad chars cycling through padstr
    (if (i32.eqz (local.get $padlen)) (then (local.set $padlen (i32.const 1))))
    (block $dp (loop $lp
      (br_if $dp (i32.ge_u (local.get $wi) (local.get $need)))
      (local.set $pi (i32.rem_u (local.get $wi) (local.get $padlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $padptr) (local.get $pi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $lp)
    ))
    ;; copy original string
    (local.set $pi (i32.const 0))
    (block $ds (loop $ls
      (br_if $ds (i32.ge_u (local.get $pi) (local.get $len)))
      (i32.store8 (i32.add (local.get $out) (i32.add (local.get $need) (local.get $pi)))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $pi))))
      (local.set $pi (i32.add (local.get $pi) (i32.const 1)))
      (br $ls)
    ))
    (local.get $out)
    (local.get $target)
  )

  ;; ── str_pad_end: pad string to targetLen with pad chars on the right ─────────
  (func $__str_pad_end
    (param $ptr i32) (param $len i32) (param $target i32) (param $padptr i32) (param $padlen i32)
    (result i32 i32)
    (local $out i32) (local $need i32) (local $wi i32) (local $pi i32)
    (if (i32.le_s (local.get $target) (local.get $len))
      (then (return (local.get $ptr) (local.get $len)))
    )
    (local.set $need (i32.sub (local.get $target) (local.get $len)))
    (local.set $out (call $__malloc (local.get $target)))
    ;; copy original string first
    (block $ds (loop $ls
      (br_if $ds (i32.ge_u (local.get $wi) (local.get $len)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $ptr) (local.get $wi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $ls)
    ))
    ;; fill pad chars
    (if (i32.eqz (local.get $padlen)) (then (local.set $padlen (i32.const 1))))
    (block $dp (loop $lp
      (br_if $dp (i32.ge_u (local.get $wi) (local.get $target)))
      (local.set $pi (i32.rem_u (i32.sub (local.get $wi) (local.get $len)) (local.get $padlen)))
      (i32.store8 (i32.add (local.get $out) (local.get $wi))
        (i32.load8_u (i32.add (local.get $padptr) (local.get $pi))))
      (local.set $wi (i32.add (local.get $wi) (i32.const 1)))
      (br $lp)
    ))
    (local.get $out)
    (local.get $target)
  )

  ;; ── str_repeat: concatenate the string n times ───────────────────────────────
  (func $__str_repeat
    (param $ptr i32) (param $len i32) (param $n i32)
    (result i32 i32)
    (local $out i32) (local $outlen i32) (local $i i32) (local $j i32)
    (if (i32.le_s (local.get $n) (i32.const 0))
      (then (return (local.get $ptr) (i32.const 0)))
    )
    (local.set $outlen (i32.mul (local.get $len) (local.get $n)))
    (local.set $out (call $__malloc (local.get $outlen)))
    (block $done
      (loop $outer
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $j (i32.const 0))
        (block $di (loop $li
          (br_if $di (i32.ge_u (local.get $j) (local.get $len)))
          (i32.store8
            (i32.add (local.get $out) (i32.add (i32.mul (local.get $i) (local.get $len)) (local.get $j)))
            (i32.load8_u (i32.add (local.get $ptr) (local.get $j)))
          )
          (local.set $j (i32.add (local.get $j) (i32.const 1)))
          (br $li)
        ))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer)
      )
    )
    (local.get $out)
    (local.get $outlen)
  )

  ;; ── str_split: split string by delimiter, return string-array ptr ────────────
  ;; String array layout: [count i32][capacity i32][{ptr i32, len i32} × count]
  ;; Each element is 8 bytes. The returned i32 is a pointer to this array.
  (func $__str_split
    (param $ptr i32) (param $len i32) (param $dptr i32) (param $dlen i32)
    (result i32)
    (local $arr i32) (local $cap i32) (local $count i32)
    (local $cur i32) (local $pos i32) (local $segptr i32) (local $seglen i32)
    (local $newarr i32) (local $newsz i32)
    ;; initial capacity 8 parts
    (local.set $cap (i32.const 8))
    (local.set $arr (call $__malloc (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8)))))
    (i32.store (local.get $arr) (i32.const 0))
    (i32.store offset=4 (local.get $arr) (local.get $cap))
    ;; special case: empty delimiter → each char is a part (not implemented; treat as no-split)
    (if (i32.eqz (local.get $dlen))
      (then
        ;; store the whole string as single part
        (i32.store offset=8 (local.get $arr) (local.get $ptr))
        (i32.store offset=12 (local.get $arr) (local.get $len))
        (i32.store (local.get $arr) (i32.const 1))
        (return (local.get $arr))
      )
    )
    (block $done
      (loop $loop
        ;; find next delimiter from $cur
        (local.set $pos (call $__str_indexof
          (i32.add (local.get $ptr) (local.get $cur))
          (i32.sub (local.get $len) (local.get $cur))
          (local.get $dptr) (local.get $dlen)
        ))
        (if (i32.eq (local.get $pos) (i32.const -1))
          (then
            ;; last segment: from $cur to end
            (local.set $segptr (i32.add (local.get $ptr) (local.get $cur)))
            (local.set $seglen (i32.sub (local.get $len) (local.get $cur)))
            (br $done)
          )
        )
        (local.set $pos (i32.add (local.get $pos) (local.get $cur)))
        (local.set $segptr (i32.add (local.get $ptr) (local.get $cur)))
        (local.set $seglen (i32.sub (local.get $pos) (local.get $cur)))
        ;; grow array if full
        (if (i32.ge_u (local.get $count) (local.get $cap))
          (then
            (local.set $cap (i32.mul (local.get $cap) (i32.const 2)))
            (local.set $newsz (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8))))
            (local.set $newarr (call $__malloc (local.get $newsz)))
            (call $__str_gather (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))) (local.get $newarr))
            (local.set $arr (local.get $newarr))
            (i32.store offset=4 (local.get $arr) (local.get $cap))
          )
        )
        ;; store segment
        (i32.store
          (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
          (local.get $segptr)
        )
        (i32.store offset=4
          (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
          (local.get $seglen)
        )
        (local.set $count (i32.add (local.get $count) (i32.const 1)))
        (local.set $cur (i32.add (local.get $pos) (local.get $dlen)))
        (if (i32.gt_u (local.get $cur) (local.get $len)) (then (br $done)))
        (br $loop)
      )
    )
    ;; store last segment
    (if (i32.ge_u (local.get $count) (local.get $cap))
      (then
        (local.set $cap (i32.mul (local.get $cap) (i32.const 2)))
        (local.set $newsz (i32.add (i32.const 8) (i32.mul (local.get $cap) (i32.const 8))))
        (local.set $newarr (call $__malloc (local.get $newsz)))
        (call $__str_gather (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))) (local.get $newarr))
        (local.set $arr (local.get $newarr))
        (i32.store offset=4 (local.get $arr) (local.get $cap))
      )
    )
    (i32.store
      (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
      (local.get $segptr)
    )
    (i32.store offset=4
      (i32.add (local.get $arr) (i32.add (i32.const 8) (i32.mul (local.get $count) (i32.const 8))))
      (local.get $seglen)
    )
    (local.set $count (i32.add (local.get $count) (i32.const 1)))
    (i32.store (local.get $arr) (local.get $count))
    (local.get $arr)
  )

  ;; ── str_from_codepoint: UTF-8 encode a single code point into a fresh buffer ──
  ;; Returns (ptr, len). Handles the full U+0000..U+10FFFF range (1–4 bytes).
  (func $__str_from_codepoint (param $cp i32) (result i32 i32)
    (local $p i32)
    (local.set $p (call $__malloc (i32.const 4)))
    (if (i32.lt_u (local.get $cp) (i32.const 0x80))
      (then
        (i32.store8 (local.get $p) (local.get $cp))
        (return (local.get $p) (i32.const 1))))
    (if (i32.lt_u (local.get $cp) (i32.const 0x800))
      (then
        (i32.store8 (local.get $p)
          (i32.or (i32.const 0xC0) (i32.shr_u (local.get $cp) (i32.const 6))))
        (i32.store8 offset=1 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
        (return (local.get $p) (i32.const 2))))
    (if (i32.lt_u (local.get $cp) (i32.const 0x10000))
      (then
        (i32.store8 (local.get $p)
          (i32.or (i32.const 0xE0) (i32.shr_u (local.get $cp) (i32.const 12))))
        (i32.store8 offset=1 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 6)) (i32.const 0x3F))))
        (i32.store8 offset=2 (local.get $p)
          (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
        (return (local.get $p) (i32.const 3))))
    (i32.store8 (local.get $p)
      (i32.or (i32.const 0xF0) (i32.shr_u (local.get $cp) (i32.const 18))))
    (i32.store8 offset=1 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 12)) (i32.const 0x3F))))
    (i32.store8 offset=2 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (i32.shr_u (local.get $cp) (i32.const 6)) (i32.const 0x3F))))
    (i32.store8 offset=3 (local.get $p)
      (i32.or (i32.const 0x80) (i32.and (local.get $cp) (i32.const 0x3F))))
    (local.get $p) (i32.const 4)
  )`.trimEnd();
  }

  private emitDataSection(): string {
    const segments: string[] = [];
    for (const [msg, [offset]] of this.dataMap) {
      const escaped = Array.from(new TextEncoder().encode(msg))
        .map((b) => `\\${b.toString(16).padStart(2, "0")}`)
        .join("");
      segments.push(`  (data (i32.const ${offset}) "${escaped}")`);
    }
    for (const { ptr, bytes } of this.rawDataSegments) {
      segments.push(`  (data (i32.const ${ptr}) "${bytes}")`);
    }
    return segments.join("\n");
  }

  private emitFunction(fn: FuncDef): string {
    // Phase 18: externals pre-registered from imported .wasm files have no body here;
    // mergeOneWasmImport splices the real WAT body after transpilation.
    if (fn.isPhase18Import) return "";

    // Phase 5f: closure factory — emit heap-alloc body + trampoline, skip normal body emit
    if (fn.isClosureFactory && fn.returnedArrow) return this.emitClosureFactory(fn);

    // Reset per-function array, struct, and find-result tracking.
    // Seed arrayVars with module-level arrays so functions can call push/pop on global arrays.
    this.arrayVars = new Map(this.moduleArrayVars);
    this.typedArrayVars = new Map();
    this.structVars = new Map();
    this.structVarRuntimeInits = new Map();
    this.structSpreadVars = new Map();
    this.classVars = new Map();
    this.interfaceVars = new Map();
    this.findResultVars = new Set();
    this.catchVarNames = new Set();
    this.catchVarShadows = new Set();
    this.nullableVarInnerType = new Map();
    this.currentFuncResultTsName = null;
    this.currentFuncIsNullableReturn = this.nullableFuncReturnType.has(fn.name);
    this.currentMethodClass = fn.className ?? null;
    this.currentMethodName = fn.name;

    const locals = new Map<string, WatType>();
    for (const p of fn.params) {
      locals.set(p.name, p.type);
      if (p.type === "string") this.stringVars.add(p.name);
      // Array param: register in arrayVars so arr[i] works inside the function body
      if (p.arrayElemType) {
        const isStrArr = p.arrayElemType === "string";
        if (p.isRest) {
          // Rest param: dynamic layout (8-byte header), pointer received from caller
          this.arrayVars.set(p.name, {
            elemType: p.arrayElemType,
            ptr: -1,
            length: 0,
            dynamic: true,
            isStringArr: isStrArr,
            structTypeName: p.arrayStructElemType,
          });
        } else {
          // string[] params use dynamic layout (8-byte header + 8-byte ptr+len elements)
          this.arrayVars.set(p.name, {
            elemType: p.arrayElemType,
            ptr: -1,
            length: 0,
            dynamic: isStrArr,
            isStringArr: isStrArr,
            structTypeName: p.arrayStructElemType,
          });
        }
      }
      // Phase 31: TypedArray param — register in typedArrayVars for correct element access
      if (p.structType) {
        const taInfoParam = getTypedArrayInfo(p.structType);
        if (taInfoParam) {
          this.typedArrayVars.set(p.name, { taType: p.structType, ...taInfoParam, length: 0 });
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
      .flatMap((p) =>
        p.type === "string"
          ? [`(param $${p.name}_ptr i32)`, `(param $${p.name}_len i32)`]
          : [`(param $${p.name} ${watBaseType(p.type)})`]
      )
      .join(" ");
    // String return: use side-channel globals $__str_ret_ptr / $__str_ret_len (void function).
    // bool → i32; never: no WAT result clause.
    const isStringReturn = fn.result === "string";
    if (isStringReturn) this.needsStringRetGlobals = true;
    const watResult = fn.result === null || isStringReturn || fn.result === "never"
      ? null
      : watBaseType(fn.result);
    const result = watResult ? `(result ${watResult})` : "";
    // _start is always exported (IIFE pattern parses it with exported=false, but WASI requires it).
    // Exported string-returning functions are NOT exported directly; a cabi shim wrapper
    // (emitted in toWat) exports them under the original name with the canonical out-parameter convention.
    const isExportedStringRet = fn.exported && fn.result === "string" && fn.name !== "_start";
    const exportAttr = (!isExportedStringRet && (fn.exported || fn.name === "_start"))
      ? `(export "${fn.name}") `
      : "";

    // Phase 10b: identify arrays that need dynamic (heap) layout because push/pop/shift/unshift are called.
    const dynamicArrayNames = this.findDynamicArrays(fn.bodyLines);

    // Pre-scan body for var/let/const declarations to emit WAT locals.
    // String variables expand to two i32 locals: $name_ptr and $name_len.
    const declaredLocals: [string, WatType][] = [];
    for (let _preI = 0; _preI < fn.bodyLines.length; _preI++) {
      const line = fn.bodyLines[_preI];
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
      // Phase 31: TypedArray declaration — must come BEFORE newClassPre since TypedArray names are PascalCase.
      // Handles: const arr = new Int32Array(n), new Int32Array([...]), new Float64Array(n), etc.
      {
        const taNewPre = line.match(
          /^(?:var|let|const)\s+(\w+)\s*(?::\s*\w+)?\s*=\s*new\s+(Int8Array|Uint8Array|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array)\s*\((.*)\)\s*;?$/,
        );
        if (taNewPre) {
          const varName = taNewPre[1];
          const taType = taNewPre[2];
          const argStr = taNewPre[3].trim();
          const taInfo = getTypedArrayInfo(taType)!;
          let length = 0;
          if (/^\d+$/.test(argStr)) length = parseInt(argStr, 10);
          else if (argStr.startsWith("[")) {
            const elems = argStr.slice(1).replace(/\]\s*$/, "").split(",").filter((s) =>
              s.trim().length > 0
            );
            length = elems.length;
          }
          this.typedArrayVars.set(varName, { taType, ...taInfo, length });
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // TypedArray view via type annotation without `new`:
      //   const view: Int32Array = ptr as unknown as Int32Array
      // Registers `view` as a typed-array view over an existing base pointer so that
      // element read AND write use the typed addressing path (ptr + 8 + idx*bytesPerElem).
      // Without this the read falls through to the i32-pointer fallback (coincidentally
      // correct for i32) while the write path stubs out — see the shared-heap stdlib pattern.
      {
        const taViewPre = line.match(
          /^(?:var|let|const)\s+(\w+)\s*:\s*(Int8Array|Uint8Array|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array)\s*=\s*(?!new\s)/,
        );
        if (taViewPre) {
          const varName = taViewPre[1];
          const taType = taViewPre[2];
          const taInfo = getTypedArrayInfo(taType)!;
          this.typedArrayVars.set(varName, { taType, ...taInfo, length: 0 });
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // Class instance: const obj: ClassName = new ClassName(args) or const obj = new ClassName(args)
      const newClassPre = line.match(
        /^(?:var|let|const)\s+(\w+)\s*(?::\s*([A-Z]\w*))?\s*=\s*new\s+([A-Z]\w*)\s*\(/,
      );
      if (newClassPre) {
        const varName = newClassPre[1];
        const ctorName = newClassPre[3];
        const typeName = newClassPre[2] ?? ctorName;
        // Phase 47: prefer ctorName (concrete constructed type) so classVar.className tracks the
        // concrete type, enabling correct method dispatch for base-typed variables like:
        //   const a: Animal = new Dog(3)  →  classVar.className = "Dog"
        const cd = this.classDefs.get(ctorName) ?? this.classDefs.get(typeName);
        if (cd) {
          const classTag = this.classTags.get(cd.name);
          const ptr = this.allocStructData(cd.struct, {}, classTag);
          this.classVars.set(varName, { className: cd.name, ptr });
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }

      // Phase 23: tuple literal: const t: [i32, f64] = [1, 2.0]
      // Must come before struct and array checks since the type annotation contains brackets.
      const tupleLitPre = line.match(
        /^(?:var|let|const)\s+(\w+)\s*:\s*(\[(?:[^[\]]|\[[^\]]*\])*\])\s*=\s*\[/,
      );
      if (tupleLitPre) {
        const varName = tupleLitPre[1];
        const typeAnnotation = tupleLitPre[2];
        const tupleDef = this.getOrCreateTupleDef(typeAnnotation);
        if (tupleDef) {
          // Extract value elements from the RHS "[e0, e1, ...]"
          const eqBrackIdx = line.indexOf("= [");
          const valueBody = eqBrackIdx !== -1
            ? line.slice(eqBrackIdx + 3).replace(/\]\s*;?\s*$/, "")
            : "";
          const elements = valueBody
            ? valueBody.split(",").map((e) => e.trim()).filter(Boolean)
            : [];
          const isLiteralOnly = elements.every((e) => /^-?\d+(\.\d+)?n?$|^true$|^false$/.test(e));
          if (isLiteralOnly) {
            const initFields: Record<string, string> = {};
            for (let i = 0; i < elements.length; i++) initFields[`_${i}`] = elements[i];
            const ptr = this.allocStructData(tupleDef, initFields);
            this.structVars.set(varName, { def: tupleDef, ptr });
          } else {
            // Runtime allocation — ptr=-1 signals local holds the pointer
            this.structVars.set(varName, { def: tupleDef, ptr: -1 });
          }
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // Phase 23: named tuple alias with bracket initializer: const p: Pair = [6, 7]
      const namedTuplePre = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\[/);
      if (namedTuplePre) {
        const typeName = namedTuplePre[2];
        const def = this.structDefs.get(typeName);
        if (def && def.fields.length > 0 && def.fields.every((f) => /^_\d+$/.test(f.name))) {
          const eqBI = line.indexOf("= [");
          const vBody = eqBI !== -1 ? line.slice(eqBI + 3).replace(/\]\s*;?\s*$/, "") : "";
          const elems = vBody ? vBody.split(",").map((e) => e.trim()).filter(Boolean) : [];
          const isLitOnly = elems.every((e) => /^-?\d+(\.\d+)?n?$|^true$|^false$/.test(e));
          if (isLitOnly) {
            const initF: Record<string, string> = {};
            for (let i = 0; i < elems.length; i++) initF[`_${i}`] = elems[i];
            const ptr = this.allocStructData(def, initF);
            this.structVars.set(namedTuplePre[1], { def, ptr });
          } else {
            this.structVars.set(namedTuplePre[1], { def, ptr: -1 });
          }
          declaredLocals.push([namedTuplePre[1], "i32"]);
          locals.set(namedTuplePre[1], "i32");
          continue;
        }
      }
      // Phase 21: destructure from a class's embedded tuple field — const [a, b] = obj.bounds
      {
        const tupleFieldDestructPre = line.match(
          /^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\.(\w+)\s*;?$/,
        );
        if (tupleFieldDestructPre) {
          const recv = tupleFieldDestructPre[2];
          const fname = tupleFieldDestructPre[3];
          const cv = this.classVars.get(recv);
          if (cv) {
            const cd = this.classDefs.get(cv.className);
            const cf = cd?.struct.fields.find((f) => f.name === fname);
            if (cf?.tupleTypeName) {
              const tdef = this.structDefs.get(cf.tupleTypeName);
              if (tdef) {
                const blist = tupleFieldDestructPre[1].split(",").map((b) => b.trim());
                for (let i = 0; i < blist.length; i++) {
                  const b = blist[i];
                  if (b === "" || b.startsWith("...")) continue;
                  const tf = tdef.fields[i];
                  if (tf) {
                    declaredLocals.push([b, tf.type]);
                    locals.set(b, tf.type);
                  }
                }
                continue;
              }
            }
          }
        }
      }
      // Phase 23: tuple destructuring: const [a, b] = tupleVar (when source is a tuple in structVars)
      // Phase 21: preserve empty slots ("gaps") so positional index aligns with field index
      // Phase 51.3: balanced-bracket detection + recursive local collection for nested patterns.
      const tupleDestructHeadPre = line.match(/^(?:var|let|const)\s*\[/);
      if (tupleDestructHeadPre) {
        const openIdx = line.indexOf("[");
        const closeIdx = findMatchingBracketAware(line, openIdx);
        const after = closeIdx !== -1 ? line.slice(closeIdx + 1).trim() : "";
        const eqM = after.match(/^=\s*(\w+)\s*;?$/);
        if (closeIdx !== -1 && eqM) {
          const sv = this.structVars.get(eqM[1]);
          if (sv) {
            const collected: Array<[string, WatType]> = [];
            this.collectDestructureLocals(line.slice(openIdx, closeIdx + 1), sv.def, collected);
            for (const [localName, ty] of collected) {
              declaredLocals.push([localName, ty]);
              locals.set(localName, ty);
            }
            continue;
          }
        }
      }
      // Struct object literal: const p: Point = { x: 1.5, y: 2.5 }
      // Phase 30: also handles shorthand properties { x, y } (treated as { x: x, y: y })
      // Phase 42: also handles nested struct literals { start: { x: 1, y: 2 }, end: { x: 3, y: 4 } }
      const structPre = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{/);
      if (structPre) {
        const varName = structPre[1];
        const typeName = structPre[2];
        const def = this.structDefs.get(typeName);
        if (def) {
          // Phase 42: use depth-aware body extraction so nested { ... } is handled correctly
          const openIdx = line.indexOf("{", line.indexOf("="));
          let bodyStr = openIdx !== -1 ? extractOuterObjectBody(line, openIdx) : null;
          // Phase 19 Fix A: multi-line struct literal — look ahead until braces balance
          if (bodyStr === null && openIdx !== -1) {
            let combined = line;
            let braceDepth = 0;
            for (let j = openIdx; j < line.length; j++) {
              if (line[j] === "{") braceDepth++;
              else if (line[j] === "}") { if (--braceDepth === 0) break; }
            }
            while (braceDepth > 0 && _preI + 1 < fn.bodyLines.length) {
              _preI++;
              const nextLn = fn.bodyLines[_preI].trim();
              combined += " " + nextLn;
              for (const ch of nextLn) {
                if (ch === "{") braceDepth++;
                else if (ch === "}") { if (--braceDepth === 0) break; }
              }
            }
            if (combined !== line) {
              const cOpenIdx = combined.indexOf("{", combined.indexOf("="));
              bodyStr = cOpenIdx !== -1 ? extractOuterObjectBody(combined, cOpenIdx) : null;
            }
          }
          // Phase 51.2: object spread `const r: T = { ...src, k: v }` — build at runtime by
          // copying the base struct then applying overrides. Mark for heap alloc (ptr=-3) and
          // route the emit path to emitRuntimeStructLiteral; skip static field parsing.
          if (bodyStr !== null && parseStructLiteralWithSpread(bodyStr).spreadSource) {
            this.structSpreadVars.set(
              varName,
              parseStructLiteralWithSpread(bodyStr).spreadSource!,
            );
            // ptr=-1 → "pointer lives in the local" (same as function-returned structs), so all
            // field-access sites read via (local.get $var). The structSpreadMatch emit handler
            // owns the assignment, so the heap pointer is written into the local at the let stmt.
            this.structVars.set(varName, { def, ptr: -1 });
            declaredLocals.push([varName, "i32"]);
            locals.set(varName, "i32");
            if (!locals.has("__rt_struct_ptr")) {
              declaredLocals.push(["__rt_struct_ptr", "i32"]);
              locals.set("__rt_struct_ptr", "i32");
            }
            continue;
          }
          // Parse field initializers using depth-0 field splitter (handles nested struct literals)
          const initFields: Record<string, string> = {};
          const runtimeInits: Record<string, string> = {};
          const namedTokens = new Set<string>();
          if (bodyStr !== null) {
            const rawFields = parseDepth0Fields(bodyStr);
            for (const [fieldKey, valStr] of Object.entries(rawFields)) {
              namedTokens.add(fieldKey);
              // Nested struct literals (starting with {) are treated as compile-time constants
              // and handled recursively in allocStructData when field.structType is set.
              const isConstant = /^-?\d+(\.\d+)?$/.test(valStr) ||
                valStr === "true" || valStr === "false" ||
                valStr === "null" || valStr === "undefined" ||
                /^["'].*["']$/.test(valStr) ||
                valStr.startsWith("{");
              if (isConstant) {
                initFields[fieldKey] = valStr;
              } else {
                runtimeInits[fieldKey] = valStr;
                initFields[fieldKey] = "0"; // placeholder so allocStructData reserves space
              }
            }
          }
          // Detect shorthand tokens (identifiers not followed by `:`)
          if (bodyStr !== null) {
            const shorthandRe = /\b(\w+)\b(?!\s*:)/g;
            let sh: RegExpExecArray | null;
            while ((sh = shorthandRe.exec(bodyStr)) !== null) {
              const tok = sh[1];
              if (!namedTokens.has(tok) && def.fields.some((f) => f.name === tok)) {
                runtimeInits[tok] = tok;
              }
            }
          }
          if (Object.keys(runtimeInits).length > 0) {
            this.structVarRuntimeInits.set(varName, runtimeInits);
          }
          // Phase 32: discriminated union — convert discriminant string literal to integer tag index
          const duDefPre = this.discUnionDefs.get(typeName);
          if (duDefPre) {
            const discVal = initFields[duDefPre.discriminant];
            if (discVal !== undefined) {
              const tagStr = discVal.replace(/^["']|["']$/g, "");
              const variant = duDefPre.variants.find((v) => v.tag === tagStr);
              if (variant) initFields[duDefPre.discriminant] = String(variant.tagIndex);
            }
          }
          // If there are runtime field inits, use heap allocation (ptr=-3 sentinel)
          // so each call gets a fresh struct instance.
          const hasRuntimeInits = Object.keys(runtimeInits).length > 0;
          const ptr = hasRuntimeInits ? -3 : this.allocStructData(def, initFields);
          this.structVars.set(varName, { def, ptr });
          // Declare an i32 local to hold the pointer (mirrors array var pattern)
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // Phase 19 Fix B: const varName = structVar.fieldName (no type annotation)
      // Register varName in structVars when the field has a nested structType.
      {
        const dotFieldPre = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(\w+)\.(\w+)\s*;?$/);
        if (dotFieldPre) {
          const varName = dotFieldPre[1];
          const srcName = dotFieldPre[2];
          const fieldName = dotFieldPre[3];
          const sv = this.structVars.get(srcName);
          if (sv) {
            const field = sv.def.fields.find((f) => f.name === fieldName);
            if (field?.structType) {
              const nestedDef = this.structDefs.get(field.structType);
              if (nestedDef && !locals.has(varName)) {
                this.structVars.set(varName, { def: nestedDef, ptr: -1 });
                declaredLocals.push([varName, "i32"]);
                locals.set(varName, "i32");
                continue;
              }
            }
          }
        }
      }
      // Phase 19 Fix C: const varName = arrName[idx] — register in structVars when array has structTypeName
      {
        const arrIdxPre = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(\w+)\[([^\]]+)\]\s*;?$/);
        if (arrIdxPre) {
          const varName = arrIdxPre[1];
          const srcArr = arrIdxPre[2];
          const ai = this.arrayVars.get(srcArr);
          if (ai?.structTypeName) {
            const def = this.structDefs.get(ai.structTypeName);
            if (def && !locals.has(varName)) {
              this.structVars.set(varName, { def, ptr: -1 });
              declaredLocals.push([varName, "i32"]);
              locals.set(varName, "i32");
              continue;
            }
          }
        }
      }
      // Phase 6d: 2D array literal declaration: const matrix: i32[][] = [[...], [...]]
      // Phase 18 fix: also handles Array.from({ length: N }, () => []) runtime 2D init.
      // Must come before the 1D array check since i32[][] contains [].
      const arr2DPre = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*(\w+)\[\]\[\]\s*=\s*(.+?);?$/);
      if (arr2DPre) {
        const varName2D = arr2DPre[1];
        const elemType2D = mapType(arr2DPre[2]) as WatType;
        const rhs2D = arr2DPre[3].trim();
        const arrayFromM = rhs2D.match(/^__arr_from_2d__\((.+)\)\s*;?$/);
        if (arrayFromM) {
          // Runtime 2D init — length expression evaluated at function call time
          this.arrayVars.set(varName2D, {
            elemType: elemType2D,
            ptr: -2,
            length: 0,
            dynamic: true,
            is2D: true,
            arrayFromExpr: arrayFromM[1],
          });
          if (!locals.has("__from_n")) {
            declaredLocals.push(["__from_n", "i32"]);
            locals.set("__from_n", "i32");
          }
          if (!locals.has("__from_i")) {
            declaredLocals.push(["__from_i", "i32"]);
            locals.set("__from_i", "i32");
          }
        } else {
          const rows2D = parse2DArrayLiteral(rhs2D);
          this.arrayVars.set(varName2D, {
            elemType: elemType2D,
            ptr: -2,
            length: rows2D.length,
            dynamic: true,
            is2D: true,
            rows: rows2D,
          });
        }
        declaredLocals.push([varName2D, "i32"]);
        locals.set(varName2D, "i32");
        if (!locals.has("__2d_tmp")) {
          declaredLocals.push(["__2d_tmp", "i32"]);
          locals.set("__2d_tmp", "i32");
        }
        continue;
      }
      // Array destructuring with rest/defaults: const [a, b = 20, ...rest] = srcArr
      // Phase 21: preserve empty slots ("gaps") — skip them without declaring locals
      const arrDestructPre = line.match(/^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\s*;?$/);
      if (arrDestructPre) {
        const bindingsListPre = arrDestructPre[1].split(",").map((b) => b.trim());
        const srcNamePre = arrDestructPre[2];
        const srcInfoPre = this.arrayVars.get(srcNamePre);
        const elemTypePre: WatType = srcInfoPre?.elemType ?? "i32";
        const structTypeNamePre = srcInfoPre?.structTypeName;
        const structDefPre = structTypeNamePre ? this.structDefs.get(structTypeNamePre) : undefined;
        let simpleCountPre = 0;
        for (const b of bindingsListPre) {
          if (b === "") {
            simpleCountPre++;
            continue;
          }
          if (b.startsWith("...")) {
            const restNamePre = b.slice(3).trim();
            this.arrayVars.set(restNamePre, {
              elemType: elemTypePre,
              ptr: -2,
              length: 0,
              dynamic: true,
              structTypeName: structTypeNamePre,
            });
            declaredLocals.push([restNamePre, "i32"]);
            locals.set(restNamePre, "i32");
          } else {
            // Phase 26: strip "= default" to get the binding name
            const bName = b.includes("=") ? b.slice(0, b.indexOf("=")).trim() : b;
            if (!locals.has(bName)) {
              declaredLocals.push([bName, elemTypePre]);
              locals.set(bName, elemTypePre);
            }
            // If source array holds struct pointers, register binding in structVars
            // so field access like bindingName.field resolves correctly.
            if (structDefPre) {
              this.structVars.set(bName, { def: structDefPre, ptr: -1 });
            }
            simpleCountPre++;
          }
        }
        continue;
      }
      // Phase 44: Array<FuncType> = [] — function pointer array (local variable in a function)
      // Phase 18 fix: Array<{ field: type; ... }> = [] — anonymous inline object struct array
      {
        const funcArrPreF = line.match(
          /^(?:var|let|const)\s+(\w+)\s*:\s*Array<((?:[^<>]|=>)*)>\s*=\s*\[\]\s*;?$/,
        );
        if (funcArrPreF) {
          const varName = funcArrPreF[1];
          const typeArgStr = funcArrPreF[2].trim();
          // Check if the type arg is an inline object type { field: type; ... }
          if (typeArgStr.startsWith("{")) {
            const synName = `__Anon_${varName}`;
            if (!this.structDefs.has(synName)) {
              const anonFields: { name: string; type: WatType; offset: number; size: number }[] =
                [];
              let anonOffset = 0;
              const anonRe = /(\w+)\s*:\s*([\w.]+)/g;
              let anonM: RegExpExecArray | null;
              while ((anonM = anonRe.exec(typeArgStr)) !== null) {
                const fname = anonM[1];
                // 'number' in anonymous struct type args maps to i32 (pointer/id semantics),
                // not f64 — these fields are typically namePtr, typeId, scopeId, addr etc.
                const rawFtype = anonM[2];
                const ftype = (rawFtype === "number") ? "i32" : (mapType(rawFtype) as WatType);
                const fsize = (ftype === "f64" || ftype === "i64") ? 8 : 4;
                if (fsize === 8 && anonOffset % 8 !== 0) anonOffset += 4;
                anonFields.push({ name: fname, type: ftype, offset: anonOffset, size: fsize });
                anonOffset += fsize;
              }
              if (anonFields.length > 0) {
                this.structDefs.set(synName, {
                  name: synName,
                  fields: anonFields,
                  totalSize: anonOffset,
                });
              }
            }
            if (this.structDefs.has(synName)) {
              this.arrayVars.set(varName, {
                elemType: "i32",
                ptr: -2,
                length: 0,
                dynamic: true,
                structTypeName: synName,
              });
              declaredLocals.push([varName, "i32"]);
              locals.set(varName, "i32");
              if (!locals.has("__rt_struct_ptr")) {
                declaredLocals.push(["__rt_struct_ptr", "i32"]);
                locals.set("__rt_struct_ptr", "i32");
              }
              continue;
            }
          }
          const funcSig = this.parseFuncTypeSig(typeArgStr);
          this.arrayVars.set(varName, {
            elemType: "i32",
            ptr: -2,
            length: 0,
            dynamic: true,
            isFuncPtrArr: funcSig,
          });
          declaredLocals.push([varName, "i32"]);
          locals.set(varName, "i32");
          continue;
        }
      }
      // Spread array literal: const merged = [...a, ...b]
      const spreadArrPre = line.match(
        /^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/,
      );
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
      const arrPre = line.match(
        /^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/,
      );
      if (arrPre) {
        const varName = arrPre[1];
        const typeHint = arrPre[2] ?? "";
        const elemsStr = arrPre[3] ?? "";
        const structTypeName =
          (typeHint && /^[A-Z]/.test(typeHint) && this.structDefs.has(typeHint))
            ? typeHint
            : undefined;
        const elements = structTypeName
          ? splitBraceAwareCommas(elemsStr)
          : this.splitArgs(elemsStr).filter((e) => e.length > 0);
        const elemType: WatType = structTypeName
          ? "i32"
          : typeHint
          ? mapType(typeHint) as WatType
          : elements.some((e) => /[.]/.test(e) && !/^-?\d+n?$/.test(e))
          ? "f64"
          : "i32";
        if (dynamicArrayNames.has(varName)) {
          // Dynamic array: runtime malloc with [length, capacity] header. ptr=-2 signals heap layout.
          const capacity = Math.max(elements.length * 2, 8);
          this.arrayVars.set(varName, {
            elemType,
            ptr: -2,
            length: elements.length,
            dynamic: true,
            capacity,
            initElements: elements,
            structTypeName,
          });
        } else {
          let ptr: number;
          if (structTypeName) {
            const def = this.structDefs.get(structTypeName)!;
            const ptrStrs = elements.map((elem) => {
              const initFields: Record<string, string> = {};
              const initRe = /(\w+)\s*:\s*([^,}]+)/g;
              let im: RegExpExecArray | null;
              while ((im = initRe.exec(elem)) !== null) initFields[im[1]] = im[2].trim();
              return String(this.allocStructData(def, initFields));
            });
            ptr = this.allocArrayData(ptrStrs, "i32");
          } else {
            ptr = this.allocArrayData(elements, elemType);
          }
          this.arrayVars.set(varName, { elemType, ptr, length: elements.length, structTypeName });
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
        const isStringArr = elemType === "string";
        this.arrayVars.set(varName, { elemType, ptr: -2, length: 0, dynamic: true, isStringArr });
        declaredLocals.push([varName, "i32"]);
        locals.set(varName, "i32");
        continue;
      }
      // String array push with complex arg (template literal): needs temp locals for ptr+len.
      const strArrPushPre = line.match(/^(\w+)\.(push|unshift)\s*\(/);
      if (strArrPushPre && !locals.has("__str_push_ptr")) {
        const pArrInfo = this.arrayVars.get(strArrPushPre[1]);
        if (pArrInfo && (pArrInfo.isStringArr || pArrInfo.elemType === "string")) {
          declaredLocals.push(["__str_push_ptr", "i32"], ["__str_push_len", "i32"]);
          locals.set("__str_push_ptr", "i32");
          locals.set("__str_push_len", "i32");
        }
      }
      // return [elem, ...] — array literal return: needs a $__arr_ret helper local
      // Phase 23: skip if this is a tuple-returning function (uses __obj_ret instead)
      const isTupleRetFn = !!(fn.resultTsName && this.structDefs.has(fn.resultTsName));
      if (/^return\s*\[/.test(line) && !locals.has("__arr_ret") && !isTupleRetFn) {
        declaredLocals.push(["__arr_ret", "i32"]);
        locals.set("__arr_ret", "i32");
      }
      // Object destructuring: const { x, y } = structVar  or  const { x: localX } = structVar
      // Phase 48: also handles "= default" suffix on each binding
      // Phase 51.3: nesting-aware — declares leaf locals from nested patterns recursively.
      const objDestructHead = line.match(/^(?:var|let|const)\s*\{/);
      if (objDestructHead) {
        const openIdx = line.indexOf("{");
        const closeIdx = findMatchingBracketAware(line, openIdx);
        const after = closeIdx !== -1 ? line.slice(closeIdx + 1).trim() : "";
        const eqM = after.match(/^=\s*(\w+)\s*;?$/);
        if (closeIdx !== -1 && eqM) {
          const sv = this.structVars.get(eqM[1]);
          if (sv) {
            const collected: Array<[string, WatType]> = [];
            this.collectDestructureLocals(line.slice(openIdx, closeIdx + 1), sv.def, collected);
            for (const [localName, ty] of collected) {
              declaredLocals.push([localName, ty]);
              locals.set(localName, ty);
            }
          }
          continue;
        }
      }
      // Phase 24: nullable variable declaration: const x: i32 | null = ...
      const nlPre = line.match(
        /^(?:var|let|const)\s+(\w+)\s*:\s*([\w\[\]]+(?:\s*\|\s*(?:null|undefined))+)\s*=/,
      );
      if (nlPre) {
        const nlVarName = nlPre[1];
        const nlInner = parseNullableAnnotation(nlPre[2]);
        if (nlInner && !locals.has(nlVarName)) {
          this.nullableVarInnerType.set(nlVarName, nlInner);
          declaredLocals.push([nlVarName, nlInner], [`${nlVarName}__null`, "i32"]);
          locals.set(nlVarName, nlInner);
          locals.set(`${nlVarName}__null`, "i32");
          this.needsNullableResultFlag = true;
          continue;
        }
      }
      const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
      if (m) {
        const typeStr = m[2] ?? "";
        const initExpr = (m[3] ?? "").trim();
        // Arrow function declarations — already parsed as module-level functions by parseArrowFunctions.
        // If the variable name matches a known function, register it as a funcref i32 local so
        // it can be passed as a callback (e.g. console.log(applyLogic(10, increment))).
        if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) {
          const fn2 = this.functions.find((fn2) => fn2.name === m[1]);
          if (fn2) {
            const baseCount = fn2.params.length - (fn2.closureCaptures?.length ?? 0);
            const sig2 = {
              params: fn2.params.slice(0, baseCount).map((p) => p.type),
              result: fn2.result,
            };
            this.funcTypeVars.set(m[1], sig2);
            declaredLocals.push([m[1], "i32"]);
            locals.set(m[1], "i32");
          }
          continue;
        }
        // Function variable: const f = knownFuncName (no type annotation)
        if (
          !typeStr && /^\w+$/.test(initExpr) && this.functions.find((fn2) => fn2.name === initExpr)
        ) {
          const fn2 = this.functions.find((fn2) => fn2.name === initExpr)!;
          const baseCount = fn2.params.length - (fn2.closureCaptures?.length ?? 0);
          const sig2 = {
            params: fn2.params.slice(0, baseCount).map((p) => p.type),
            result: fn2.result,
          };
          this.funcTypeVars.set(m[1], sig2);
          declaredLocals.push([m[1], "i32"]);
          locals.set(m[1], "i32");
          continue;
        }
        // Phase 5g: closure factory result — const v = factoryFn(args) → v is a closure pointer
        {
          const fcm = initExpr.match(/^(\w+)\s*\(/);
          if (fcm) {
            const factoryFn = this.functions.find((f) =>
              f.name === fcm[1] && f.isClosureFactory && f.returnedArrow
            );
            if (factoryFn) {
              const innerFn = factoryFn.returnedArrow!;
              const caps = innerFn.closureCaptures ?? [];
              const extParams = innerFn.params.filter((p) => !caps.includes(p.name)).map((p) =>
                p.type
              );
              this.closureTypedVars.set(m[1], { params: extParams, result: innerFn.result });
              declaredLocals.push([m[1], "i32"]);
              locals.set(m[1], "i32");
              continue;
            }
            // Phase 12/23: struct/interface/tuple-typed return — const x = fn(args) → x is a struct pointer
            const calledFn = this.functions.find((f) => f.name === fcm[1]);
            if (calledFn?.resultTsName && this.structDefs.has(calledFn.resultTsName)) {
              const retDef = this.structDefs.get(calledFn.resultTsName)!;
              if (calledFn.resultTsName.startsWith("__Tuple_")) {
                // Phase 23: tuple return — register in structVars (ptr=-1) so t[N] field access works
                this.structVars.set(m[1], { def: retDef, ptr: -1 });
              } else {
                // Phase 30: also register in structVars (ptr=-1) so plain field reads work
                // (interfaceVars handles method dispatch; structVars handles field load/store)
                this.interfaceVars.set(m[1], calledFn.resultTsName);
                this.structVars.set(m[1], { def: retDef, ptr: -1 });
              }
              declaredLocals.push([m[1], "i32"]);
              locals.set(m[1], "i32");
              continue;
            }
          }
        }
        // Phase 18 fix: const target = arr[i] where arr has a structTypeName → register
        // target in structVars so subsequent target.field access can resolve field offsets.
        if (!typeStr && initExpr) {
          const bracketSrcM = initExpr.match(/^(\w+)\s*\[/);
          if (bracketSrcM) {
            const srcArrInfo = this.arrayVars.get(bracketSrcM[1]);
            if (srcArrInfo?.structTypeName) {
              const srcStructDef = this.structDefs.get(srcArrInfo.structTypeName);
              if (srcStructDef) {
                this.structVars.set(m[1], { def: srcStructDef, ptr: -1 });
                if (!locals.has(m[1])) {
                  declaredLocals.push([m[1], "i32"]);
                  locals.set(m[1], "i32");
                }
                continue;
              }
            }
          }
        }
        const t = typeStr
          ? mapType(typeStr)
          : inferInitType(initExpr, locals, this.enumValues, this.functions);
        if (!locals.has(m[1])) {
          if (t === "string") {
            declaredLocals.push([`${m[1]}_ptr`, "i32"], [`${m[1]}_len`, "i32"]);
            locals.set(m[1], "string");
            this.stringVars.add(m[1]);
          } else {
            declaredLocals.push([m[1], t]);
            locals.set(m[1], t);
          }
        }
      }
      // for-loop init variable: for (let i = 0; ...)
      const forM = line.match(
        /^(?:\w+\s*:\s*)?for\s*\(\s*(?:let|const|var)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?)\s*;/,
      );
      if (forM && !locals.has(forM[1])) {
        const typeStr2 = forM[2] ?? "";
        const initExpr2 = forM[3].trim();
        const t2 = typeStr2
          ? mapType(typeStr2)
          : inferInitType(initExpr2, locals, this.enumValues, this.functions);
        declaredLocals.push([forM[1], t2]);
        locals.set(forM[1], t2);
      }
      // Phase 26: for...of item variable: for (const item of arrName) { ... }
      const forOfPre = line.match(/^for\s*\(\s*(?:const|let)\s+(\w+)\s+of\s+(\w+)\s*\)/);
      if (forOfPre) {
        const foItemName = forOfPre[1];
        const foArrName = forOfPre[2];
        const foArrInfo = this.arrayVars.get(foArrName);
        const foElemType: WatType = foArrInfo?.elemType ?? "i32";
        if (foArrInfo?.isStringArr) {
          // Phase 27: string[] — loop variable is a string (needs _ptr and _len locals)
          if (!locals.has(foItemName)) {
            declaredLocals.push([`${foItemName}_ptr`, "i32"], [`${foItemName}_len`, "i32"]);
            locals.set(foItemName, "string");
            this.stringVars.add(foItemName);
          }
        } else if (!locals.has(foItemName)) {
          declaredLocals.push([foItemName, foElemType]);
          locals.set(foItemName, foElemType);
        }
        if (!locals.has("__forof_idx")) {
          declaredLocals.push(["__forof_idx", "i32"]);
          locals.set("__forof_idx", "i32");
        }
      }
      // catch variable: } catch (e) { — registers e as a (ptr, len) string pair
      const catchVarPre = line.match(/^}\s*catch\s*\(\s*(\w+)(?:\s*:\s*\w+)?\s*\)\s*\{?$/);
      if (catchVarPre && catchVarPre[1]) {
        const cv = catchVarPre[1];
        this.catchVarNames.add(cv);
        if (!locals.has(cv)) {
          declaredLocals.push([`${cv}_ptr`, "i32"], [`${cv}_len`, "i32"]);
          locals.set(cv, "string");
          this.stringVars.add(cv);
        } else if (locals.get(cv) === "string") {
          // Catch var shadows an outer string — declare alias locals so the outer is not overwritten
          this.catchVarShadows.add(cv);
          const alias = `__catch_${cv}`;
          declaredLocals.push([`${alias}_ptr`, "i32"], [`${alias}_len`, "i32"]);
        }
      }
    }
    // Add $__rest_ptr if any body line calls a rest-param function with literal args
    if (this.hasRestLiteralCalls(fn.bodyLines) && !locals.has("__rest_ptr")) {
      declaredLocals.push(["__rest_ptr", "i32"]);
      locals.set("__rest_ptr", "i32");
    }
    // Phase 12: add $__obj_ret if any line has `return {` (object literal return)
    // Phase 23: also add for tuple returns — `return [...]` when fn has a tuple resultTsName
    const hasTupleReturn =
      !!(fn.resultTsName?.startsWith("__Tuple_") || this.structDefs.has(fn.resultTsName ?? "")) &&
      fn.bodyLines.some((l) => /^return\s*\[/.test(l));
    if (
      (fn.bodyLines.some((l) => /^return\s*\{/.test(l)) || hasTupleReturn) &&
      !locals.has("__obj_ret")
    ) {
      declaredLocals.push(["__obj_ret", "i32"]);
      locals.set("__obj_ret", "i32");
      // Phase 42: also declare $__nested_ptr for runtime nested struct literal field values
      declaredLocals.push(["__nested_ptr", "i32"]);
      locals.set("__nested_ptr", "i32");
    }
    // Phase 12: add $__iface_tmp for interface method dispatch (any dot-call in body)
    // Phase 5h: also add for factory().method() chained calls
    if (
      fn.bodyLines.some((l) => /\w+\.\w+\s*\(/.test(l) || /\w+\s*\(.*\)\.\w+\s*\(/.test(l)) &&
      !locals.has("__iface_tmp")
    ) {
      declaredLocals.push(["__iface_tmp", "i32"]);
      locals.set("__iface_tmp", "i32");
    }
    // Add $__struct_tmp if any body line has console.log(structReturningFn(...))
    if (
      !locals.has("__struct_tmp") && fn.bodyLines.some((l) => {
        const lm = l.match(/^console\.(log|error|warn)\s*\((.+)\)\s*;?$/);
        if (!lm) return false;
        const callM = lm[2].trim().match(/^(\w+)\s*\(/);
        if (!callM) return false;
        const calledFn = this.functions.find((f) => f.name === callM[1]);
        return !!(calledFn?.resultTsName && this.structDefs.has(calledFn.resultTsName));
      })
    ) {
      declaredLocals.push(["__struct_tmp", "i32"]);
      locals.set("__struct_tmp", "i32");
    }
    // Add $__arr_tmp / $__arr_tmp2 if any body line has inline array literals as call args
    if (
      fn.bodyLines.some((l) => /\(\s*\[/.test(l) || /,\s*\[/.test(l)) && !locals.has("__arr_tmp")
    ) {
      declaredLocals.push(["__arr_tmp", "i32"]);
      locals.set("__arr_tmp", "i32");
    }
    if (fn.bodyLines.some((l) => /\[\[/.test(l)) && !locals.has("__arr_tmp2")) {
      declaredLocals.push(["__arr_tmp2", "i32"]);
      locals.set("__arr_tmp2", "i32");
    }
    // String-return side-channel: add ptr/len scratch locals for functions that return string.
    if (isStringReturn && !locals.has("__ret_str_ptr")) {
      declaredLocals.push(["__ret_str_ptr", "i32"], ["__ret_str_len", "i32"]);
      locals.set("__ret_str_ptr", "i32");
      locals.set("__ret_str_len", "i32");
    }
    // Template literal numeric temp: pre-declare shared pair when any body line uses ${} interpolation.
    if (!locals.has("__tmpl_num_ptr") && fn.bodyLines.some((l) => /`[^`]*\$\{/.test(l))) {
      declaredLocals.push(["__tmpl_num_ptr", "i32"], ["__tmpl_num_len", "i32"]);
      locals.set("__tmpl_num_ptr", "i32");
      locals.set("__tmpl_num_len", "i32");
    }
    // String.fromCharCode / str.charAt / str.slice in concat: pre-declare $__str_op_ptr/$__str_op_len temp pair.
    if (
      !locals.has("__str_op_ptr") &&
      fn.bodyLines.some((l) =>
        l.includes("String.fromCharCode(") || l.includes("String.fromCodePoint(") ||
        l.includes(".charAt(") || l.includes(".slice(") ||
        l.includes(".split(") ||
        l.includes(".padStart(") || l.includes(".padEnd(") || l.includes(".toString(") ||
        l.includes(".at(") || l.includes(".toUpperCase(") || l.includes(".toLowerCase(") ||
        /\w\[[^\]]+\]\s*\+|\+\s*\w+\[/.test(l) || // string char subscript in a concat: s[i] + …
        // console.log/error/warn with a string-equality op: the comparison may route a non-trivial
        // operand (`a === getName()`, `a === obj.f`, `a === s.slice(…)`) through the string-expr
        // resolver, which captures len into $__str_op_len.
        (/\bconsole\.(log|error|warn)\b/.test(l) && /===|!==|==|!=/.test(l))
      )
    ) {
      declaredLocals.push(["__str_op_ptr", "i32"], ["__str_op_len", "i32"]);
      locals.set("__str_op_ptr", "i32");
      locals.set("__str_op_len", "i32");
    }
    // Self-referential string concat prepend (`X = … + X`): pre-declare $__concat_self pair.
    if (
      !locals.has("__concat_self_ptr") &&
      fn.bodyLines.some((l) => /(\w+)\s*=\s*.+\+\s*\1\b/.test(l))
    ) {
      declaredLocals.push(["__concat_self_ptr", "i32"], ["__concat_self_len", "i32"]);
      locals.set("__concat_self_ptr", "i32");
      locals.set("__concat_self_len", "i32");
    }
    // Phase 44: $__fn_tmp for function pointer array element dispatch: arr[idx]()
    if (
      !locals.has("__fn_tmp") && fn.bodyLines.some((l) => {
        const m = l.match(/^(\w+)\[/);
        return m &&
          (this.arrayVars.get(m[1])?.isFuncPtrArr !== undefined ||
            this.moduleArrayVars.get(m[1])?.isFuncPtrArr !== undefined);
      })
    ) {
      declaredLocals.push(["__fn_tmp", "i32"]);
      locals.set("__fn_tmp", "i32");
    }
    const localDecls = declaredLocals
      .map(([n, t]) => `    (local $${n} ${watBaseType(t)})`)
      .join("\n");

    // For never-returning functions pass null so return statements emit (return) with no value.
    const blockResult = fn.result === "never" ? null : fn.result;
    this.currentFuncResultTsName = fn.resultTsName ?? null;
    // Phase 5h: set boxed/shared capture context for this function
    this.currentBoxedCaptures = fn.boxedCaptures ?? new Set();
    this.currentSharedMutableCaptures = fn.sharedMutableCaptures ?? new Set();
    this.currentClosureCaptureLayout = fn.closureCaptureLayout ?? new Map();
    const body = this.emitBlock(fn.bodyLines, locals, blockResult);
    this.currentBoxedCaptures = new Set();
    this.currentSharedMutableCaptures = new Set();
    this.currentClosureCaptureLayout = new Map();
    // Phase 21: append (unreachable) for never-typed functions — signals to the WASM validator
    // that control never reaches the end of this function.
    const neverSuffix = fn.result === "never" ? "\n    (unreachable)" : "";

    // Fallthru-stack fix: a value-returning function whose body ends in a STATEMENT-level
    // (void) if/else where every path returns from inside the construct leaves nothing on
    // the stack at the implicit function end. wabt/binaryen accept this, but V8's strict
    // validator rejects it ("expected 1 elements on the stack for fallthru, found 0").
    // Appending (unreachable) does NOT survive Binaryen -Oz (it strips it as dead code,
    // re-introducing the invalid void if). Instead, rewrite the terminal void `if` into a
    // value-producing `(if (result T) cond (then … X) (else … Y))` by turning each branch's
    // trailing `(return X)` into a bare value `X` (recursing through nested all-returning
    // ifs). Binaryen preserves a value-if as the function result. Behavior is unchanged.
    const finalBody = (watResult !== null) ? this.fixTerminalFallthru(body, watResult) : body;

    return [
      `  (func $${fn.name} ${exportAttr}${params} ${result}`,
      localDecls ? localDecls : "",
      finalBody + neverSuffix,
      `  )`,
    ].filter((l) => l.trim() !== "").join("\n");
  }

  /** Index of the opening `(` of the last top-level s-expression in a WAT body string,
   *  skipping `;;` line comments, `(; … ;)` block comments, and `"…"` data strings.
   *  Returns -1 if there is no top-level group. */
  private findLastTopLevelStart(s: string): number {
    let depth = 0, last = -1, i = 0;
    while (i < s.length) {
      const ch = s[i];
      if (ch === ";" && s[i + 1] === ";") {
        const nl = s.indexOf("\n", i);
        i = nl === -1 ? s.length : nl;
        continue;
      }
      if (ch === "(" && s[i + 1] === ";") {
        const end = s.indexOf(";)", i);
        i = end === -1 ? s.length : end + 2;
        continue;
      }
      if (ch === '"') {
        let j = i + 1;
        while (j < s.length) {
          if (s[j] === "\\") {
            j += 2;
            continue;
          }
          if (s[j] === '"') {
            j++;
            break;
          }
          j++;
        }
        i = j;
        continue;
      }
      if (ch === "(") {
        if (depth === 0) last = i;
        depth++;
        i++;
        continue;
      }
      if (ch === ")") {
        depth--;
        i++;
        continue;
      }
      i++;
    }
    return last;
  }

  /** If `body` ends in a statement-level (void) `if` where every path returns, rewrite that
   *  terminal `if` into a value-producing `(if (result rt) …)` so V8 accepts the function's
   *  fallthru point. Returns `body` unchanged when the last construct already produces a value
   *  or cannot be safely rewritten. */
  private fixTerminalFallthru(body: string, rt: string): string {
    const start = this.findLastTopLevelStart(body);
    if (start === -1) return body;
    const group = body.slice(start);
    const head = group.slice(1).match(/^\s*([\w.$]+)/)?.[1] ?? "";
    // Terminal void `if` where every branch returns → rewrite into a value-producing
    // `(if (result T) …)` (survives binaryen -Oz, which strips a bare trailing unreachable).
    if (head === "if") {
      const afterHead = group.slice(group.indexOf(head) + head.length).trimStart();
      if (afterHead.startsWith("(result")) return body; // already value-producing
      const nodes = parseWatNodes(tokenizeWat(group), { i: 0 });
      if (nodes.length !== 1) return body;
      const valued = watNodeToValue(nodes[0], rt);
      if (valued === null) return body; // not every branch returns — leave as-is (ill-typed input)
      return body.slice(0, start) + serializeWat(valued);
    }
    // Terminal void `block` — a `switch` statement compiles to nested blocks where every case
    // returns/throws and the default ends in `(unreachable)`. The block leaves an empty stack, so a
    // value-returning function needs an explicit `(unreachable)` after it to satisfy V8's strict
    // fallthru validation. (binaryen -Oz strips a trailing unreachable, so this only matters on the
    // exception-module path that skips binaryen — see watToOptimisedWasm.)
    if (head === "block") {
      const afterLabel = group.replace(/^\(\s*block\s*(?:\$[\w$]+)?/, "");
      if (/^\s*\(result\b/.test(afterLabel)) return body; // value-producing block — leave as-is
      return body.slice(0, start) + group + "\n      (unreachable)";
    }
    return body; // bare value expr / explicit return / loop / try — leave as-is
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
  /** Pre-scan all function body lines + startBodyLines for closure factory assignments.
   *  Populates closureTypedVars so inner functions emitted before their factory parents can
   *  resolve closure pointer call sites, and so module-level closure calls dispatch correctly. */
  private prePopulateClosureTypedVars(): void {
    const allLineSets: string[][] = [
      ...this.functions.map((fn) => fn.bodyLines),
      this.startBodyLines,
    ];
    for (const lines of allLineSets) {
      for (const line of lines) {
        // Use ' = ' split to handle complex type annotations like (): () => number
        const declM = line.match(/^(?:var|let|const)\s+(\w+)/);
        if (!declM) continue;
        const eqPos = line.indexOf(" = ", declM[0].length);
        if (eqPos === -1) continue;
        const varName = declM[1];
        const initExpr = line.slice(eqPos + 3).replace(/;$/, "").trim();
        const fcm = initExpr.match(/^(\w+)\s*\(/);
        if (!fcm) continue;
        const factoryFn = this.functions.find((f) =>
          f.name === fcm[1] && f.isClosureFactory && f.returnedArrow
        );
        if (!factoryFn) continue;
        const innerFn = factoryFn.returnedArrow!;
        const caps = innerFn.closureCaptures ?? [];
        const extParams = innerFn.params.filter((p) =>
          !caps.includes(p.name) && p.name !== "__closure_ptr"
        ).map((p) => p.type);
        this.closureTypedVars.set(varName, { params: extParams, result: innerFn.result });
      }
    }
  }

  private emitClosureFactory(fn: FuncDef): string {
    const inner = fn.returnedArrow!;
    const captures = inner.closureCaptures ?? [];

    // Build per-capture layout: {name, type, byte-offset-in-struct}
    // For mutable captures (rewired by detectMutableClosureCaptures), use closureCaptureLayout
    // which has the original type since inner.params no longer contains those captures.
    let structSize = 4; // first 4 bytes = i32 table index
    const captureLayout: { name: string; type: WatType; offset: number }[] = [];
    for (const cap of captures) {
      const mutableInfo = inner.closureCaptureLayout?.get(cap);
      const capType: WatType = mutableInfo?.type ??
        (inner.params.find((p) => p.name === cap)?.type ?? "i32");
      captureLayout.push({ name: cap, type: capType, offset: structSize });
      structSize += (capType === "f64" || capType === "i64") ? 8 : 4;
    }

    // Mutable capture detection and inner-function rewiring is done by detectMutableClosureCaptures()
    // which runs before emitFunction calls, so inner.closureCaptureLayout is already set here if needed.

    // The TRAMPOLINE goes in the funcref table (not the inner function).
    // This enables uniform closure-pointer dispatch: all closures of the same external signature
    // are called via call_indirect (type $trampoline_type) ptr args (i32.load ptr).
    const trampolineName = `${fn.name}__trampoline`;
    const tableIdx = this.getFuncTableIdx(trampolineName);

    const exportAttr = fn.exported ? `(export "${fn.name}") ` : "";
    const factoryParamNames = new Set(fn.params.map((p) => p.name));
    const factoryParams = fn.params
      .map((p) => `(param $${p.name} ${watBaseType(p.type)})`)
      .join(" ");

    // ── Factory function ─────────────────────────────────────────────────────
    // Identify captures that are NOT factory params — they are locally computed in the body.
    const locallyComputedCaptures = captureLayout.filter((c) => !factoryParamNames.has(c.name));

    // Build locals map and emit body lines that compute intermediate closure values.
    // Skip the `return (params) => expr` line — that is the inner function (already handled.
    const locals = new Map<string, WatType>();
    for (const p of fn.params) locals.set(p.name, p.type);
    const bodyStmts: string[] = [];
    for (const line of fn.bodyLines) {
      if (/^return\s+\(/.test(line) && line.includes("=>")) continue; // skip return-arrow line
      const wat = this.emitStatement(line, locals, "i32");
      if (wat) bodyStmts.push(`    ${wat}`);
    }

    const factoryLines: string[] = [];
    factoryLines.push(`  (func $${fn.name} ${exportAttr}${factoryParams} (result i32)`.trimEnd());
    factoryLines.push(`    (local $__closure_ptr i32)`);
    for (const { name, type } of locallyComputedCaptures) {
      factoryLines.push(`    (local $${name} ${watBaseType(type)})`);
    }
    factoryLines.push(...bodyStmts);
    factoryLines.push(`    (local.set $__closure_ptr (call $__malloc (i32.const ${structSize})))`);
    factoryLines.push(`    (i32.store (local.get $__closure_ptr) (i32.const ${tableIdx}))`);
    for (const { name, type, offset } of captureLayout) {
      const storeOp = type === "f64" ? "f64.store" : type === "i64" ? "i64.store" : "i32.store";
      factoryLines.push(
        `    (${storeOp} offset=${offset} (local.get $__closure_ptr) (local.get $${name}))`,
      );
    }
    factoryLines.push(`    (local.get $__closure_ptr)`);
    factoryLines.push(`  )`);

    // ── Trampoline function ───────────────────────────────────────────────────
    // Params: closure_ptr + the inner function's NON-captured params (the "real" call args)
    const updatedCaptures = inner.closureCaptures ?? []; // may have been reduced by mutable cap rewiring
    const innerCallParams = inner.params.filter((p) =>
      !updatedCaptures.includes(p.name) && p.name !== "__closure_ptr"
    );
    const trampolineParamStr = [
      `(param $__closure_ptr i32)`,
      ...innerCallParams.map((p) => `(param $${p.name} ${watBaseType(p.type)})`),
    ].join(" ");

    // String-returning inner functions are void WAT functions (side-channel globals carry the result).
    const watResult = inner.result === null || inner.result === "never" || inner.result === "string"
      ? null
      : watBaseType(inner.result);
    const resultClause = watResult ? `(result ${watResult})` : "";

    const trampolineLines: string[] = [];
    trampolineLines.push(
      `  (func $${fn.name}__trampoline ${trampolineParamStr} ${resultClause}`.trimEnd(),
    );

    if (inner.closureCaptureLayout && inner.closureCaptureLayout.size > 0) {
      // Mutable capture path: load only non-mutable captures; pass $__closure_ptr directly.
      const immutableLayout = captureLayout.filter((c) => !inner.closureCaptureLayout!.has(c.name));
      for (const { name, type } of immutableLayout) {
        trampolineLines.push(`    (local $__cap_${name} ${watBaseType(type)})`);
      }
      for (const { name, type, offset } of immutableLayout) {
        const loadOp = type === "f64" ? "f64.load" : type === "i64" ? "i64.load" : "i32.load";
        trampolineLines.push(
          `    (local.set $__cap_${name} (${loadOp} offset=${offset} (local.get $__closure_ptr)))`,
        );
      }
      const directCallArgs = [
        `(local.get $__closure_ptr)`,
        ...innerCallParams.map((p) => `(local.get $${p.name})`),
        ...immutableLayout.map((c) => `(local.get $__cap_${c.name})`),
      ].join(" ");
      trampolineLines.push(`    (call $${inner.name} ${directCallArgs})`);
    } else {
      // Read-only capture path: load all captures and pass by value (original behavior).
      for (const { name, type } of captureLayout) {
        trampolineLines.push(`    (local $__cap_${name} ${watBaseType(type)})`);
      }
      for (const { name, type, offset } of captureLayout) {
        const loadOp = type === "f64" ? "f64.load" : type === "i64" ? "i64.load" : "i32.load";
        trampolineLines.push(
          `    (local.set $__cap_${name} (${loadOp} offset=${offset} (local.get $__closure_ptr)))`,
        );
      }
      const directCallArgs = [
        ...innerCallParams.map((p) => `(local.get $${p.name})`),
        ...captureLayout.map((c) => `(local.get $__cap_${c.name})`),
      ].join(" ");
      trampolineLines.push(
        `    (call $${inner.name}${directCallArgs ? " " + directCallArgs : ""})`,
      );
    }
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
  /** Pre-pass: detect mutable closure captures in returned inner functions and rewire their
   *  params so they receive $__closure_ptr (i32) instead of the captured values by copy.
   *  Must run AFTER injectClosureCaptures() (so closureCaptures is fully populated) and
   *  BEFORE any emitFunction() calls (inner functions are emitted before their factories). */
  private detectMutableClosureCaptures(): void {
    for (const fn of this.functions) {
      if (!fn.isClosureFactory || !fn.returnedArrow) continue;
      const inner = fn.returnedArrow;
      const captures = inner.closureCaptures ?? [];
      if (captures.length === 0) continue;

      // Build capture layout to know offsets (mirrors emitClosureFactory layout logic)
      let structOffset = 4;
      const captureLayout: { name: string; type: WatType; offset: number }[] = [];
      for (const cap of captures) {
        const capParam = inner.params.find((p) => p.name === cap);
        const capType: WatType = capParam?.type ?? "i32";
        captureLayout.push({ name: cap, type: capType, offset: structOffset });
        structOffset += (capType === "f64" || capType === "i64") ? 8 : 4;
      }

      // Detect which captures are mutated in the inner function body
      const mutableCapSet = new Set<string>();
      for (const cap of captures) {
        for (const line of inner.bodyLines) {
          if (
            new RegExp(`\\b${cap}\\s*(?:\\+\\+|--|[+\\-*/&|^]?=(?!=))`).test(line) ||
            new RegExp(`(?:\\+\\+|--)\\s*${cap}\\b`).test(line)
          ) {
            mutableCapSet.add(cap);
            break;
          }
        }
      }
      if (mutableCapSet.size === 0) continue;

      // Set closureCaptureLayout so emitFunction can emit load/store through $__closure_ptr
      inner.closureCaptureLayout = new Map();
      for (const { name, type, offset } of captureLayout) {
        if (mutableCapSet.has(name)) inner.closureCaptureLayout.set(name, { type, offset });
      }

      // Rewire inner function params: replace mutable capture params with $__closure_ptr.
      // NOTE: inner.closureCaptures is left unchanged so emitClosureFactory can still build
      // the full struct layout (factory must store ALL captured values including mutable ones).
      inner.params = [
        { name: "__closure_ptr", type: "i32" as WatType },
        ...inner.params.filter((p) => !mutableCapSet.has(p.name)),
      ];
    }
  }

  private injectClosureCaptures(): void {
    const KEYWORDS = new Set([
      "return",
      "if",
      "else",
      "while",
      "for",
      "do",
      "switch",
      "case",
      "default",
      "break",
      "continue",
      "const",
      "let",
      "var",
      "true",
      "false",
      "null",
      "undefined",
    ]);

    for (const af of this.functions) {
      // Find the INNERMOST outer function whose bodyLines declare this arrow function.
      // We scan all functions and keep the last match: nested functions appear later in
      // this.functions than the outer ones that contain them verbatim, so the last match
      // is always the closest (innermost) enclosing scope.
      let outer: FuncDef | undefined;
      for (const f of this.functions) {
        if (
          f !== af && f.bodyLines.some((l) => new RegExp(`\\bconst\\s+${af.name}\\s*=`).test(l))
        ) {
          outer = f;
        }
      }
      // Phase 5f: for returned arrows, the factory function is the outer scope directly
      // (no `const name =` pattern exists in the factory body — it's a `return (...)=>` line).
      if (!outer && af.returnedByFactory) {
        outer = this.functions.find((f) => f.name === af.returnedByFactory);
      }
      if (!outer) continue;

      // Build outer scope: params + locally declared variables at depth-0 of outer body.
      // Track brace depth to exclude variables declared inside nested blocks (e.g. inner arrows).
      const outerScope = new Map<string, WatType>();
      for (const p of outer.params) outerScope.set(p.name, p.type);
      let scopeDepth = 0;
      for (const line of outer.bodyLines) {
        // Check depth BEFORE updating — only include top-level declarations (depth 0 at start of line)
        const atTopLevel = scopeDepth === 0;
        for (const ch of line) {
          if (ch === "{") scopeDepth++;
          else if (ch === "}") scopeDepth--;
        }
        if (!atTopLevel) continue;
        const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
        if (m) {
          const typeStr = m[2] ?? "";
          const initExpr = (m[3] ?? "").trim();
          // Arrow declarations are expression-body closures — treated as i32 closure pointers
          if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) {
            outerScope.set(m[1], "i32");
            continue;
          }
          const t = typeStr
            ? mapType(typeStr)
            : inferInitType(initExpr, outerScope, this.enumValues, this.functions);
          if (t !== "string") outerScope.set(m[1], t);
        }
      }

      // Collect all identifiers referenced in af's body
      const ownParams = new Set(af.params.map((p) => p.name));
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

  // Phase 41: generate a WIT (WebAssembly Interface Types) file describing this module.
  // Must be called AFTER transpile() so usedExternalMethods is fully populated.
  generateWit(moduleName: string): string {
    const pkg = toKebabCase(moduleName);
    const lines: string[] = [
      `// Generated by wasmtk wasic — do not edit manually`,
      `package local:${pkg};`,
      ``,
      `world ${pkg} {`,
    ];

    // External imports (Phase 40 bindings → WIT import statements)
    for (const [watFuncName, sig] of this.usedExternalMethods) {
      const fieldName = watFuncName.slice(1); // strip leading "$"
      const witName = toKebabCase(fieldName);
      const paramStr = sig.params.map((p, i) => `p${i}: ${watTypeToWit(p) ?? "s32"}`).join(", ");
      const resultWit = watTypeToWit(sig.result);
      const resultStr = resultWit ? ` -> ${resultWit}` : "";
      lines.push(`  import ${witName}: func(${paramStr})${resultStr};`);
    }

    // Exported user functions (Phase 40 imports are excluded — they have no body)
    const INTERNAL = new Set(["_start", "_initialize"]);
    const exportedFns = this.functions.filter(
      (f) => f.exported && !f.isClosureFactory && !INTERNAL.has(f.name),
    );

    if (this.usedExternalMethods.size > 0 && exportedFns.length > 0) lines.push("");

    for (const fn of exportedFns) {
      const witName = toKebabCase(fn.name);
      const paramParts: string[] = [];
      for (const p of fn.params) {
        if (p.name === "__self") continue; // class `this` pointer — not part of public API
        if (p.type === "string") {
          // Phase 50: emit WIT-native string type (bindgen maps this to ptr+len WASM ABI)
          paramParts.push(`${toKebabCase(p.name)}: string`);
        } else {
          const wt = watTypeToWit(p.type);
          if (wt) paramParts.push(`${toKebabCase(p.name)}: ${wt}`);
        }
      }
      const paramStr = paramParts.join(", ");
      const resultWit = watTypeToWit(fn.result);
      const resultStr = resultWit ? ` -> ${resultWit}` : "";
      lines.push(`  export ${witName}: func(${paramStr})${resultStr};`);
    }

    lines.push(`}`);
    return lines.join("\n") + "\n";
  }

  // Phase 40: parse method signatures from an interface body string.
  private parseExternalInterfaceBody(
    body: string,
  ): Map<string, { params: WatType[]; result: WatType | null }> {
    const methods = new Map<string, { params: WatType[]; result: WatType | null }>();
    const methodRe = /(\w+)\s*\(([^)]*)\)\s*:\s*([\w\[\]]+)/g;
    let mm: RegExpExecArray | null;
    while ((mm = methodRe.exec(body)) !== null) {
      const mname = mm[1];
      const rawParams = mm[2];
      const rawResult = mm[3].trim();
      const params: WatType[] = rawParams.trim()
        ? rawParams.split(",").map((p) => {
          const ci = p.indexOf(":");
          const rawT = ci !== -1 ? p.slice(ci + 1).trim() : "i32";
          return mapType(rawT) as WatType;
        })
        : [];
      const result: WatType | null = rawResult === "void" ? null : mapType(rawResult) as WatType;
      methods.set(mname, { params, result });
    }
    return methods;
  }

  // Phase 40: extract and remove `declare interface` and `declare const` external bindings from source.
  private parseExternalDeclarations(): void {
    // 1. Named interface declarations: declare interface Name { method(p): retType; ... }
    const ifaceRe = /declare\s+interface\s+(\w+)\s*\{([^}]*)\}/g;
    let m: RegExpExecArray | null;
    while ((m = ifaceRe.exec(this.src)) !== null) {
      this.externalInterfaceTypes.set(m[1], this.parseExternalInterfaceBody(m[2]));
    }
    this.src = this.src.replace(/declare\s+interface\s+\w+\s*\{[^}]*\}/g, "");

    // 2. Inline object-type bindings: declare const varName: { method(p): retType; ... };
    const inlineRe = /declare\s+const\s+(\w+)\s*:\s*\{([^}]*)\}\s*;?/g;
    while ((m = inlineRe.exec(this.src)) !== null) {
      const varName = m[1];
      const syntheticName = `__ext_${varName}`;
      this.externalInterfaceTypes.set(syntheticName, this.parseExternalInterfaceBody(m[2]));
      this.externalBindings.set(varName, syntheticName);
    }
    this.src = this.src.replace(/declare\s+const\s+\w+\s*:\s*\{[^}]*\}\s*;?/g, "");

    // 3. Named-type bindings: declare const varName: InterfaceName;
    const namedRe = /declare\s+const\s+(\w+)\s*:\s*(\w+)\s*;?/g;
    while ((m = namedRe.exec(this.src)) !== null) {
      const varName = m[1];
      const typeName = m[2];
      if (this.externalInterfaceTypes.has(typeName)) {
        this.externalBindings.set(varName, typeName);
      }
    }
    this.src = this.src.replace(
      /declare\s+const\s+(\w+)\s*:\s*\w+\s*;?/g,
      (_full, vn) => this.externalBindings.has(vn) ? "" : _full,
    );
  }

  transpile(_moduleName: string): string {
    // Phase 49: optional chaining — strip ?. to . (safe for non-nullable types)
    this.src = this.src.replace(/[?][.]/g, ".");
    // Pre-pass: expand generic templates by monomorphization before any other parsing
    this.src = this.expandGenerics(this.src);
    // Phase 30: expand namespace blocks into prefixed top-level declarations
    this.src = this.expandNamespaces(this.src);
    // Phase 35: normalize `keyof T` in type annotation positions to `string` before any parsing.
    // This allows `key: keyof Person` and `const k: keyof T = "x"` to work via the existing string path.
    // Also strip `type Alias = keyof T` declarations (they become the `string` type inline).
    this.src = this.src.replace(/:\s*keyof\s+\w+/g, ": string");
    this.src = this.src.replace(/(?:export\s+)?type\s+\w+\s*=\s*keyof\s+\w+\s*;?/gm, "");
    // Phase 51.4: pass-through utility types (Partial/Readonly/Required/NonNullable) → inner type,
    // before parseStructs so the unwrapped type is seen everywhere (incl. interface field types).
    this.src = this.expandUtilityTypes(this.src);
    // Rewrite `const/let/var name = function(params): type { ... }` to `function name(params): type { ... }`
    // so parseFunctions() can recognize the pattern as a named function.
    this.src = this.src.replace(
      /(?:^|(?<=\n))(?:const|let|var)\s+(\w+)\s*=\s*function(\s*\()/gm,
      "function $1$2",
    );
    // Phase 40: extract external interface declarations before any other parse pass.
    this.parseExternalDeclarations();
    this.parseEnums();
    this.parseDiscriminatedUnions(); // Phase 32: must precede parseStructs so DU types are pre-registered
    this.parseStructs();
    this.parseClasses();
    this.parseIntersectionTypes(); // Phase 33: after parseStructs+parseClasses so constituent types are registered
    // Phase 51.4: resolve Pick/Omit/Record into synthetic struct types. After parseStructs (needs the
    // base StructDef) and before parseFunctions (so use sites in signatures/bodies see the synth name).
    this.expandStructUtilityTypes();
    // Phase 51 (gap #2): desugar class-instance array literals into push() form. Must run AFTER
    // parseClasses (needs classDefs) and BEFORE parseFunctions/parseTopLevel collect bodies.
    this.expandClassInstanceArrayLiterals();
    this.parseNamedFuncTypeAliases(); // Phase 5g: must precede parseFunctions so parseParams can resolve aliases
    // Phase 18 fix: replace Array.from({ length: N }, () => []) with __arr_from_2d__(N)
    // Must run BEFORE parseFunctions() so that collected bodyLines don't still contain
    // () => [] — liftInlineArrows() would otherwise lift it into a module-level $__anon_N
    // function that lacks $__arr_tmp and has the wrong (f64) return type.
    this.src = this.src.replace(
      /Array\.from\(\s*\{\s*length\s*:\s*([^}]+?)\s*\}\s*,\s*\(\s*\)\s*=>\s*\[\]\s*\)/g,
      (_full, lenExpr) => `__arr_from_2d__(${lenExpr.trim()})`,
    );
    // Phase 52.8: Array.from([…]) and Array.of(…) → plain array literal. Runs AFTER the 2D
    // sentinel above so the {length:N} form is already consumed. Array.from of an array literal
    // is just that literal; Array.of(a,b,c) is [a,b,c]. (Array.from of an iterable other than a
    // literal array is out of scope — no runtime iterator protocol in wasic.)
    this.src = this.expandArrayFromOf(this.src);
    // Phase 51.3: desugar destructuring function params into a synthetic param + injected
    // `const { … } = __pd` binding. Must run BEFORE parseFunctions so the binding is collected
    // into the function body, and after parseStructs/parseClasses so synthetic params resolve.
    this.expandParamDestructuring();
    this.parseFunctions();
    this.parseArrowFunctions();
    this.injectClosureCaptures();
    this.detectMutableClosureCaptures();
    this.liftInlineArrows();
    this.parseTopLevel();
    this.liftStartBodyArrows(); // Phase 44: second pass for startBodyLines with synthetic _start context
    this.joinMultilineArrayLiterals();
    this.parseModuleGlobals();

    // Phase 5g: pre-populate closureTypedVars for all functions so inner functions emitted
    // before their factory parents can still resolve closure pointer call sites.
    this.prePopulateClosureTypedVars();

    // Detect module-level arrays used inside functions and register them as WASM globals.
    // Must run before emitFunction so arrayVars seeding in emitFunction picks them up.
    this.detectModuleArrayGlobals();

    // Emit all user functions first — this populates hasConsoleLog/needsNumericHelpers
    const funcWat = this.functions.map((f) => this.emitFunction(f)).join("\n\n");

    // Build _start inner body — priority: user _start() > named main() > collected startBodyLines > empty.
    // In library mode skip entirely: no entry point, and top-level statements (console.log etc.) must not
    // influence hasConsoleLog / helper flags for the library binary.
    const hasUserStart = this.functions.some((f) => f.name === "_start");
    const hasMain = !hasUserStart && this.functions.some((f) => f.name === "main");
    let startBody: string;
    if (this.mode === "library") {
      startBody = ""; // unused in library mode — _start is never emitted
    } else if (hasMain) {
      startBody = `\n    (call $main)\n    (call $proc_exit (i32.const 0))`;
    } else if (this.startBodyLines.length > 0) {
      // Pre-scan for var/let/const so WAT locals are declared at the top of _start.
      // String variables expand to two i32 locals ($name_ptr, $name_len).
      // Reset per-function state so dynamic array helpers work for top-level code.
      this.arrayVars = new Map();
      this.typedArrayVars = new Map();
      this.structVars = new Map();
      this.structVarRuntimeInits = new Map();
      this.structSpreadVars = new Map();
      this.classVars = new Map();
      this.nullableVarInnerType = new Map();
      this.catchVarNames = new Set();
      this.catchVarShadows = new Set();
      this.currentFuncIsNullableReturn = false;
      const startDynArrayNames = this.findDynamicArrays(this.startBodyLines);
      const startLocals = new Map<string, WatType>();
      const startDeclaredLocals: [string, WatType][] = [];
      for (const line of this.startBodyLines) {
        // Phase 23: tuple literal — const t: [i32, f64] = [1, 2.0] (mirrors emitFunction pre-scan)
        const tupleLitPre2 = line.match(
          /^(?:var|let|const)\s+(\w+)\s*:\s*(\[(?:[^[\]]|\[[^\]]*\])*\])\s*=\s*\[/,
        );
        if (tupleLitPre2) {
          const varNameT = tupleLitPre2[1];
          const tupleDef2 = this.getOrCreateTupleDef(tupleLitPre2[2]);
          if (tupleDef2) {
            const eqBI = line.indexOf("= [");
            const vBody = eqBI !== -1 ? line.slice(eqBI + 3).replace(/\]\s*;?\s*$/, "") : "";
            const elems2 = vBody ? vBody.split(",").map((e) => e.trim()).filter(Boolean) : [];
            const isLit2 = elems2.every((e) => /^-?\d+(\.\d+)?n?$|^true$|^false$/.test(e));
            if (isLit2) {
              const initF2: Record<string, string> = {};
              for (let i = 0; i < elems2.length; i++) initF2[`_${i}`] = elems2[i];
              const ptr2 = this.allocStructData(tupleDef2, initF2);
              this.structVars.set(varNameT, { def: tupleDef2, ptr: ptr2 });
            } else {
              this.structVars.set(varNameT, { def: tupleDef2, ptr: -1 });
            }
            startLocals.set(varNameT, "i32");
            startDeclaredLocals.push([varNameT, "i32"]);
            continue;
          }
        }
        // Phase 23: named tuple alias with bracket initializer: const p: Pair = [6, 7]
        const namedTuplePre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\[/);
        if (namedTuplePre2) {
          const typeNameT2 = namedTuplePre2[2];
          const defT2 = this.structDefs.get(typeNameT2);
          if (
            defT2 && defT2.fields.length > 0 && defT2.fields.every((f) => /^_\d+$/.test(f.name))
          ) {
            const eqBI2 = line.indexOf("= [");
            const vBodyT2 = eqBI2 !== -1 ? line.slice(eqBI2 + 3).replace(/\]\s*;?\s*$/, "") : "";
            const elemsT2 = vBodyT2 ? vBodyT2.split(",").map((e) => e.trim()).filter(Boolean) : [];
            const isLitT2 = elemsT2.every((e) => /^-?\d+(\.\d+)?n?$|^true$|^false$/.test(e));
            if (isLitT2) {
              const initFT2: Record<string, string> = {};
              for (let i = 0; i < elemsT2.length; i++) initFT2[`_${i}`] = elemsT2[i];
              const ptrT2 = this.allocStructData(defT2, initFT2);
              this.structVars.set(namedTuplePre2[1], { def: defT2, ptr: ptrT2 });
            } else {
              this.structVars.set(namedTuplePre2[1], { def: defT2, ptr: -1 });
            }
            startLocals.set(namedTuplePre2[1], "i32");
            startDeclaredLocals.push([namedTuplePre2[1], "i32"]);
            continue;
          }
        }
        // Phase 30: struct object literal (mirrors emitFunction pre-scan)
        // Phase 42: also handles nested struct literals { start: { x: 1, y: 2 }, ... }
        const structPre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*([A-Z]\w*)\s*=\s*\{/);
        if (structPre2) {
          const varName2 = structPre2[1];
          const typeName2 = structPre2[2];
          const def2 = this.structDefs.get(typeName2);
          if (def2) {
            const initFields2: Record<string, string> = {};
            const runtimeInits2: Record<string, string> = {};
            const namedTokens2 = new Set<string>();
            // Phase 42: use depth-aware body extraction
            const openIdx2 = line.indexOf("{", line.indexOf("="));
            const bodyStr2 = openIdx2 !== -1 ? extractOuterObjectBody(line, openIdx2) : null;
            // Phase 51.2: object spread at module scope — mirror the emitFunction pre-scan.
            if (bodyStr2 !== null && parseStructLiteralWithSpread(bodyStr2).spreadSource) {
              this.structSpreadVars.set(
                varName2,
                parseStructLiteralWithSpread(bodyStr2).spreadSource!,
              );
              // ptr=-1 → pointer lives in the local; field reads use (local.get $var).
              this.structVars.set(varName2, { def: def2, ptr: -1 });
              startLocals.set(varName2, "i32");
              startDeclaredLocals.push([varName2, "i32"]);
              if (!startLocals.has("__rt_struct_ptr")) {
                startLocals.set("__rt_struct_ptr", "i32");
                startDeclaredLocals.push(["__rt_struct_ptr", "i32"]);
              }
              continue;
            }
            if (bodyStr2 !== null) {
              const rawFields2 = parseDepth0Fields(bodyStr2);
              for (const [fieldKey2, valStr2] of Object.entries(rawFields2)) {
                initFields2[fieldKey2] = valStr2;
                namedTokens2.add(fieldKey2);
              }
              const shorthandRe2 = /\b(\w+)\b(?!\s*:)/g;
              let sh2: RegExpExecArray | null;
              while ((sh2 = shorthandRe2.exec(bodyStr2)) !== null) {
                const tok2 = sh2[1];
                if (!namedTokens2.has(tok2) && def2.fields.some((f) => f.name === tok2)) {
                  runtimeInits2[tok2] = tok2;
                }
              }
            }
            if (Object.keys(runtimeInits2).length > 0) {
              this.structVarRuntimeInits.set(varName2, runtimeInits2);
            }
            // Phase 32: discriminated union — convert discriminant string literal to integer tag index
            const duDefPre2 = this.discUnionDefs.get(typeName2);
            if (duDefPre2) {
              const discVal2 = initFields2[duDefPre2.discriminant];
              if (discVal2 !== undefined) {
                const tagStr2 = discVal2.replace(/^["']|["']$/g, "");
                const variant2 = duDefPre2.variants.find((v) => v.tag === tagStr2);
                if (variant2) initFields2[duDefPre2.discriminant] = String(variant2.tagIndex);
              }
            }
            const hasRuntimeInits2 = Object.keys(runtimeInits2).length > 0;
            const ptr2 = hasRuntimeInits2 ? -3 : this.allocStructData(def2, initFields2);
            this.structVars.set(varName2, { def: def2, ptr: ptr2 });
            startLocals.set(varName2, "i32");
            startDeclaredLocals.push([varName2, "i32"]);
            continue;
          }
        }
        // Phase 51 (gap #1): module-level class instance — const obj: Base = new Sub(args).
        // Mirrors the emitFunction newClassPre pre-scan so module-level class vars are tracked in
        // classVars (enabling field access, method dispatch, and instanceof at module scope). The
        // static ptr is required because the const-new statement handler emits (i32.const ptr) for
        // both the local.set and the constructor call. The `if (cd)` guard skips TypedArrays
        // (PascalCase but not in classDefs) so they fall through to their own pre-scan below.
        const newClassPre2 = line.match(
          /^(?:var|let|const)\s+(\w+)\s*(?::\s*([A-Z]\w*))?\s*=\s*new\s+([A-Z]\w*)\s*\(/,
        );
        if (newClassPre2) {
          const ncVarName = newClassPre2[1];
          const ncCtorName = newClassPre2[3];
          const ncTypeName = newClassPre2[2] ?? ncCtorName;
          const ncCd = this.classDefs.get(ncCtorName) ?? this.classDefs.get(ncTypeName);
          if (ncCd) {
            const ncTag = this.classTags.get(ncCd.name);
            const ncPtr = this.allocStructData(ncCd.struct, {}, ncTag);
            this.classVars.set(ncVarName, { className: ncCd.name, ptr: ncPtr });
            startLocals.set(ncVarName, "i32");
            startDeclaredLocals.push([ncVarName, "i32"]);
            continue;
          }
        }
        // Phase 21: destructure from a class's embedded tuple field — const [a, b] = obj.bounds
        {
          const tupleFieldDestructPre2 = line.match(
            /^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\.(\w+)\s*;?$/,
          );
          if (tupleFieldDestructPre2) {
            const recv2 = tupleFieldDestructPre2[2];
            const fname2 = tupleFieldDestructPre2[3];
            const cv2 = this.classVars.get(recv2);
            if (cv2) {
              const cd2 = this.classDefs.get(cv2.className);
              const cf2 = cd2?.struct.fields.find((f) => f.name === fname2);
              if (cf2?.tupleTypeName) {
                const tdef2 = this.structDefs.get(cf2.tupleTypeName);
                if (tdef2) {
                  const blistTF = tupleFieldDestructPre2[1].split(",").map((b) => b.trim());
                  for (let i = 0; i < blistTF.length; i++) {
                    const b = blistTF[i];
                    if (b === "" || b.startsWith("...")) continue;
                    const tf = tdef2.fields[i];
                    if (tf) {
                      startLocals.set(b, tf.type);
                      startDeclaredLocals.push([b, tf.type]);
                    }
                  }
                  continue;
                }
              }
            }
          }
        }
        // Phase 23: tuple destructuring — const [a, b] = tupleVar (mirrors emitFunction pre-scan)
        // Phase 21: preserve empty slots ("gaps"); Phase 51.3: balanced + recursive for nesting.
        const tupleDestructHeadPre2 = line.match(/^(?:var|let|const)\s*\[/);
        if (tupleDestructHeadPre2) {
          const openIdx = line.indexOf("[");
          const closeIdx = findMatchingBracketAware(line, openIdx);
          const after = closeIdx !== -1 ? line.slice(closeIdx + 1).trim() : "";
          const eqM = after.match(/^=\s*(\w+)\s*;?$/);
          if (closeIdx !== -1 && eqM) {
            const sv2 = this.structVars.get(eqM[1]);
            if (sv2) {
              const collected: Array<[string, WatType]> = [];
              this.collectDestructureLocals(line.slice(openIdx, closeIdx + 1), sv2.def, collected);
              for (const [localName, ty] of collected) {
                startLocals.set(localName, ty);
                startDeclaredLocals.push([localName, ty]);
              }
              continue;
            }
          }
        }
        // Phase 31: TypedArray declaration (mirrors emitFunction pre-scan)
        {
          const taNewPre2 = line.match(
            /^(?:var|let|const)\s+(\w+)\s*(?::\s*\w+)?\s*=\s*new\s+(Int8Array|Uint8Array|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array)\s*\((.*)\)\s*;?$/,
          );
          if (taNewPre2) {
            const varName2 = taNewPre2[1];
            const taType2 = taNewPre2[2];
            const argStr2 = taNewPre2[3].trim();
            const taInfo2 = getTypedArrayInfo(taType2)!;
            let length2 = 0;
            if (/^\d+$/.test(argStr2)) length2 = parseInt(argStr2, 10);
            else if (argStr2.startsWith("[")) {
              const elems2 = argStr2.slice(1).replace(/\]\s*$/, "").split(",").filter((s) =>
                s.trim().length > 0
              );
              length2 = elems2.length;
            }
            this.typedArrayVars.set(varName2, { taType: taType2, ...taInfo2, length: length2 });
            startLocals.set(varName2, "i32");
            startDeclaredLocals.push([varName2, "i32"]);
            continue;
          }
        }
        // TypedArray view via type annotation without `new` (mirrors emitFunction pre-scan).
        {
          const taViewPre2 = line.match(
            /^(?:var|let|const)\s+(\w+)\s*:\s*(Int8Array|Uint8Array|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array)\s*=\s*(?!new\s)/,
          );
          if (taViewPre2) {
            const varName2 = taViewPre2[1];
            const taType2 = taViewPre2[2];
            const taInfo2 = getTypedArrayInfo(taType2)!;
            this.typedArrayVars.set(varName2, { taType: taType2, ...taInfo2, length: 0 });
            startLocals.set(varName2, "i32");
            startDeclaredLocals.push([varName2, "i32"]);
            continue;
          }
        }
        // Phase 6d: 2D array literal declaration: const matrix: i32[][] = [[...], [...]]
        // Phase 18 fix: also handles __arr_from_2d__(N) runtime 2D init (pre-pass form).
        const arr2DPre = line.match(
          /^(?:var|let|const)\s+(\w+)\s*:\s*(\w+)\[\]\[\]\s*=\s*(.+?);?$/,
        );
        if (arr2DPre) {
          const varName2D = arr2DPre[1];
          const elemType2D = mapType(arr2DPre[2]) as WatType;
          const rhs2Ds = arr2DPre[3].trim();
          const arrayFromMs = rhs2Ds.match(/^__arr_from_2d__\((.+)\)\s*;?$/);
          if (arrayFromMs) {
            this.arrayVars.set(varName2D, {
              elemType: elemType2D,
              ptr: -2,
              length: 0,
              dynamic: true,
              is2D: true,
              arrayFromExpr: arrayFromMs[1],
            });
            if (!startLocals.has("__from_n")) {
              startDeclaredLocals.push(["__from_n", "i32"]);
              startLocals.set("__from_n", "i32");
            }
            if (!startLocals.has("__from_i")) {
              startDeclaredLocals.push(["__from_i", "i32"]);
              startLocals.set("__from_i", "i32");
            }
          } else {
            const rows2D = parse2DArrayLiteral(rhs2Ds);
            this.arrayVars.set(varName2D, {
              elemType: elemType2D,
              ptr: -2,
              length: rows2D.length,
              dynamic: true,
              is2D: true,
              rows: rows2D,
            });
          }
          startLocals.set(varName2D, "i32");
          startDeclaredLocals.push([varName2D, "i32"]);
          if (!startLocals.has("__2d_tmp")) {
            startLocals.set("__2d_tmp", "i32");
            startDeclaredLocals.push(["__2d_tmp", "i32"]);
          }
          continue;
        }
        // Phase 44: Array<FuncType> = [] — function pointer array (mirrors emitFunction pre-scan)
        {
          const funcArrPre2 = line.match(
            /^(?:var|let|const)\s+(\w+)\s*:\s*Array<((?:[^<>]|=>)*)>\s*=\s*\[\]\s*;?$/,
          );
          if (funcArrPre2) {
            const varName2 = funcArrPre2[1];
            const funcSig2 = this.parseFuncTypeSig(funcArrPre2[2].trim());
            const isGlobalArr2 = this.moduleArrayVars.has(varName2) &&
              this.moduleGlobals.has(varName2);
            if (isGlobalArr2) {
              // Module-level global: re-populate arrayVars with the registered metadata
              const existing2 = this.moduleArrayVars.get(varName2)!;
              this.arrayVars.set(varName2, { ...existing2, isFuncPtrArr: funcSig2 });
              // Do NOT declare a WAT local — global is accessed via global.get
            } else {
              this.arrayVars.set(varName2, {
                elemType: "i32",
                ptr: -2,
                length: 0,
                dynamic: true,
                isFuncPtrArr: funcSig2,
              });
              startLocals.set(varName2, "i32");
              startDeclaredLocals.push([varName2, "i32"]);
            }
            continue;
          }
        }
        // Array destructuring with rest/defaults — mirrors emitFunction pre-scan
        // Phase 21: preserve empty slots ("gaps") — skip them without declaring locals
        const arrDestructPre2 = line.match(/^(?:var|let|const)\s*\[([^\]]*)\]\s*=\s*(\w+)\s*;?$/);
        if (arrDestructPre2) {
          const bindingsListPre2 = arrDestructPre2[1].split(",").map((b) => b.trim());
          const srcNamePre2 = arrDestructPre2[2];
          const srcInfoPre2 = this.arrayVars.get(srcNamePre2);
          const elemTypePre2: WatType = srcInfoPre2?.elemType ?? "i32";
          for (const b of bindingsListPre2) {
            if (b === "") continue;
            if (b.startsWith("...")) {
              const restNamePre2 = b.slice(3).trim();
              this.arrayVars.set(restNamePre2, {
                elemType: elemTypePre2,
                ptr: -2,
                length: 0,
                dynamic: true,
              });
              startLocals.set(restNamePre2, "i32");
              startDeclaredLocals.push([restNamePre2, "i32"]);
            } else {
              // Phase 26: strip "= default" to get the binding name
              const bName2 = b.includes("=") ? b.slice(0, b.indexOf("=")).trim() : b;
              if (!startLocals.has(bName2)) {
                startLocals.set(bName2, elemTypePre2);
                startDeclaredLocals.push([bName2, elemTypePre2]);
              }
            }
          }
          continue;
        }
        // Spread array literal — mirrors emitFunction pre-scan
        const spreadArrPre2 = line.match(
          /^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/,
        );
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
        const arrPre2 = line.match(
          /^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+)\[\])?\s*=\s*\[([^\]]*)\]/,
        );
        if (arrPre2) {
          const varName2 = arrPre2[1];
          const typeHint2 = arrPre2[2] ?? "";
          const elemsStr2 = arrPre2[3] ?? "";
          const structTypeName2 =
            (typeHint2 && /^[A-Z]/.test(typeHint2) && this.structDefs.has(typeHint2))
              ? typeHint2
              : undefined;
          const elements2 = structTypeName2
            ? splitBraceAwareCommas(elemsStr2)
            : this.splitArgs(elemsStr2).filter((e) => e.length > 0);
          const elemType2: WatType = structTypeName2
            ? "i32"
            : typeHint2
            ? mapType(typeHint2) as WatType
            : elements2.some((e) => /[.]/.test(e) && !/^-?\d+n?$/.test(e))
            ? "f64"
            : "i32";
          // Module-level arrays used in functions become WASM globals — don't declare as _start locals.
          const isGlobalArr2 = this.moduleArrayVars.has(varName2) &&
            this.moduleGlobals.has(varName2);
          if (startDynArrayNames.has(varName2) || isGlobalArr2) {
            const capacity2 = Math.max(elements2.length * 2, 8);
            this.arrayVars.set(varName2, {
              elemType: elemType2,
              ptr: -2,
              length: elements2.length,
              dynamic: true,
              capacity: capacity2,
              initElements: elements2,
              structTypeName: structTypeName2,
            });
          } else {
            let ptr2: number;
            if (structTypeName2) {
              const def2 = this.structDefs.get(structTypeName2)!;
              const ptrStrs2 = elements2.map((elem) => {
                const initFields2: Record<string, string> = {};
                const initRe2 = /(\w+)\s*:\s*([^,}]+)/g;
                let im2: RegExpExecArray | null;
                while ((im2 = initRe2.exec(elem)) !== null) initFields2[im2[1]] = im2[2].trim();
                return String(this.allocStructData(def2, initFields2));
              });
              ptr2 = this.allocArrayData(ptrStrs2, "i32");
            } else {
              ptr2 = this.allocArrayData(elements2, elemType2);
            }
            this.arrayVars.set(varName2, {
              elemType: elemType2,
              ptr: ptr2,
              length: elements2.length,
              structTypeName: structTypeName2,
            });
          }
          if (!isGlobalArr2) {
            startLocals.set(varName2, "i32");
            startDeclaredLocals.push([varName2, "i32"]);
          }
          continue;
        }
        // Array variable from method-call RHS: const arr: T[] = someArr.slice(...) etc.
        const arrCallPre2 = line.match(/^(?:var|let|const)\s+(\w+)\s*:\s*(\w+)\[\]\s*=\s*([^[].+)/);
        if (arrCallPre2 && !this.arrayVars.has(arrCallPre2[1])) {
          const varName2c = arrCallPre2[1];
          const elemType2c = mapType(arrCallPre2[2]) as WatType;
          const isStringArr2c = elemType2c === "string";
          this.arrayVars.set(varName2c, {
            elemType: elemType2c,
            ptr: -2,
            length: 0,
            dynamic: true,
            isStringArr: isStringArr2c,
          });
          startLocals.set(varName2c, "i32");
          startDeclaredLocals.push([varName2c, "i32"]);
          continue;
        }
        // String array push with complex arg: needs temp locals for ptr+len.
        const strArrPushPre2 = line.match(/^(\w+)\.(push|unshift)\s*\(/);
        if (strArrPushPre2 && !startLocals.has("__str_push_ptr")) {
          const pArrInfo2 = this.arrayVars.get(strArrPushPre2[1]);
          if (pArrInfo2 && (pArrInfo2.isStringArr || pArrInfo2.elemType === "string")) {
            startDeclaredLocals.push(["__str_push_ptr", "i32"], ["__str_push_len", "i32"]);
            startLocals.set("__str_push_ptr", "i32");
            startLocals.set("__str_push_len", "i32");
          }
        }
        // Phase 24: nullable variable: const x: i32 | null = ...
        const nlPreS = line.match(
          /^(?:var|let|const)\s+(\w+)\s*:\s*([\w\[\]]+(?:\s*\|\s*(?:null|undefined))+)\s*=/,
        );
        if (nlPreS) {
          const nlVarNameS = nlPreS[1];
          const nlInnerS = parseNullableAnnotation(nlPreS[2]);
          if (nlInnerS && !startLocals.has(nlVarNameS)) {
            this.nullableVarInnerType.set(nlVarNameS, nlInnerS);
            startDeclaredLocals.push([nlVarNameS, nlInnerS], [`${nlVarNameS}__null`, "i32"]);
            startLocals.set(nlVarNameS, nlInnerS);
            startLocals.set(`${nlVarNameS}__null`, "i32");
            this.needsNullableResultFlag = true;
            continue;
          }
        }
        // Phase 5g: pre-check for closure factory with complex type annotation (e.g., const r1: () => number = factory())
        // The main regex below only handles simple type annotations; this handles function-type annotations.
        if (/^(?:var|let|const)\s+\w+\s*:[^;=]*=>/.test(line)) {
          const complexNameM = line.match(/^(?:var|let|const)\s+(\w+)/);
          const complexEqPos = line.indexOf(" = ");
          if (complexNameM && complexEqPos !== -1) {
            const complexInit = line.slice(complexEqPos + 3).replace(/;$/, "").trim();
            const complexFcm = complexInit.match(/^(\w+)\s*\(/);
            if (complexFcm) {
              const cFactFn = this.functions.find((f) =>
                f.name === complexFcm[1] && f.isClosureFactory && f.returnedArrow
              );
              if (cFactFn) {
                const cInner = cFactFn.returnedArrow!;
                const cCaps = cInner.closureCaptures ?? [];
                const cExtParams = cInner.params.filter((p) =>
                  !cCaps.includes(p.name) && p.name !== "__closure_ptr"
                ).map((p) => p.type);
                this.closureTypedVars.set(complexNameM[1], {
                  params: cExtParams,
                  result: cInner.result,
                });
                startLocals.set(complexNameM[1], "i32");
                startDeclaredLocals.push([complexNameM[1], "i32"]);
                continue;
              }
            }
          }
        }
        const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
        if (m) {
          const typeStr = m[2] ?? "";
          const initExpr = (m[3] ?? "").trim();
          // Skip arrow function declarations — lifted to module level, not WAT locals
          if (/^\s*\([^)]*\)\s*(?::\s*\w+)?\s*=>/.test(initExpr)) continue;
          // Phase 12/23/5g/5h: function-call-returning variable detection
          const fcmS = initExpr.match(/^(\w+)\s*\(/);
          if (fcmS) {
            // Phase 5g: closure factory result at module level
            const factoryFnS = this.functions.find((f) =>
              f.name === fcmS[1] && f.isClosureFactory && f.returnedArrow
            );
            if (factoryFnS) {
              const innerFnS = factoryFnS.returnedArrow!;
              const capsS = innerFnS.closureCaptures ?? [];
              const extParamsS = innerFnS.params.filter((p) =>
                !capsS.includes(p.name) && p.name !== "__closure_ptr"
              ).map((p) => p.type);
              this.closureTypedVars.set(m[1], { params: extParamsS, result: innerFnS.result });
              startLocals.set(m[1], "i32");
              startDeclaredLocals.push([m[1], "i32"]);
              continue;
            }
            const calledFnS = this.functions.find((f) => f.name === fcmS[1]);
            if (calledFnS?.resultTsName && this.structDefs.has(calledFnS.resultTsName)) {
              const retDefS = this.structDefs.get(calledFnS.resultTsName)!;
              if (calledFnS.resultTsName.startsWith("__Tuple_")) {
                this.structVars.set(m[1], { def: retDefS, ptr: -1 });
              } else {
                // Phase 30: also register in structVars so plain field reads work
                this.interfaceVars.set(m[1], calledFnS.resultTsName);
                this.structVars.set(m[1], { def: retDefS, ptr: -1 });
              }
              startLocals.set(m[1], "i32");
              startDeclaredLocals.push([m[1], "i32"]);
              continue;
            }
          }
          const t = typeStr
            ? mapType(typeStr)
            : inferInitType(initExpr, startLocals, this.enumValues, this.functions);
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
        const forM = line.match(
          /^(?:\w+\s*:\s*)?for\s*\(\s*(?:let|const|var)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?)\s*;/,
        );
        if (forM) {
          const typeStr2 = forM[2] ?? "";
          const initExpr2 = forM[3].trim();
          const t2 = typeStr2
            ? mapType(typeStr2)
            : inferInitType(initExpr2, startLocals, this.enumValues, this.functions);
          startDeclaredLocals.push([forM[1], t2]);
          startLocals.set(forM[1], t2);
        }
        // Phase 26: for...of item variable — mirrors emitFunction pre-scan
        const forOfPre2 = line.match(/^for\s*\(\s*(?:const|let)\s+(\w+)\s+of\s+(\w+)\s*\)/);
        if (forOfPre2) {
          const foItemName2 = forOfPre2[1];
          const foArrName2 = forOfPre2[2];
          const foArrInfo2 = this.arrayVars.get(foArrName2);
          const foElemType2: WatType = foArrInfo2?.elemType ?? "i32";
          if (foArrInfo2?.isStringArr) {
            // Phase 27: string[] — loop variable is a string (needs _ptr and _len locals)
            if (!startLocals.has(foItemName2)) {
              startDeclaredLocals.push([`${foItemName2}_ptr`, "i32"], [
                `${foItemName2}_len`,
                "i32",
              ]);
              startLocals.set(foItemName2, "string");
              this.stringVars.add(foItemName2);
            }
          } else if (!startLocals.has(foItemName2)) {
            startDeclaredLocals.push([foItemName2, foElemType2]);
            startLocals.set(foItemName2, foElemType2);
          }
          if (!startLocals.has("__forof_idx")) {
            startDeclaredLocals.push(["__forof_idx", "i32"]);
            startLocals.set("__forof_idx", "i32");
          }
        }
        // catch variable: } catch (e) { — registers e as a (ptr, len) string pair
        const catchVarPre2 = line.match(/^}\s*catch\s*\(\s*(\w+)(?:\s*:\s*\w+)?\s*\)\s*\{?$/);
        if (catchVarPre2 && catchVarPre2[1]) {
          const cv2 = catchVarPre2[1];
          this.catchVarNames.add(cv2);
          if (!startLocals.has(cv2)) {
            startDeclaredLocals.push([`${cv2}_ptr`, "i32"], [`${cv2}_len`, "i32"]);
            startLocals.set(cv2, "string");
            this.stringVars.add(cv2);
          } else if (startLocals.get(cv2) === "string") {
            this.catchVarShadows.add(cv2);
            const alias2 = `__catch_${cv2}`;
            startDeclaredLocals.push([`${alias2}_ptr`, "i32"], [`${alias2}_len`, "i32"]);
          }
        }
      }
      // Add $__rest_ptr if any start body line calls a rest-param function with literal args
      if (this.hasRestLiteralCalls(this.startBodyLines) && !startLocals.has("__rest_ptr")) {
        startDeclaredLocals.push(["__rest_ptr", "i32"]);
        startLocals.set("__rest_ptr", "i32");
      }
      // Phase 12/5h: add $__iface_tmp for interface/factory method dispatch in start body
      if (
        !startLocals.has("__iface_tmp") &&
        this.startBodyLines.some((l) => /\w+\.\w+\s*\(/.test(l) || /\w+\s*\(.*\)\.\w+\s*\(/.test(l))
      ) {
        startDeclaredLocals.push(["__iface_tmp", "i32"]);
        startLocals.set("__iface_tmp", "i32");
      }
      // Add $__struct_tmp if any start body line has console.log(structReturningFn(...))
      if (
        !startLocals.has("__struct_tmp") && this.startBodyLines.some((l) => {
          const lm = l.match(/^console\.(log|error|warn)\s*\((.+)\)\s*;?$/);
          if (!lm) return false;
          const callM = lm[2].trim().match(/^(\w+)\s*\(/);
          if (!callM) return false;
          const fn = this.functions.find((f) => f.name === callM[1]);
          return !!(fn?.resultTsName && this.structDefs.has(fn.resultTsName));
        })
      ) {
        startDeclaredLocals.push(["__struct_tmp", "i32"]);
        startLocals.set("__struct_tmp", "i32");
      }
      // Template literal numeric temp: pre-declare when any start body line uses ${} interpolation.
      if (
        !startLocals.has("__tmpl_num_ptr") && this.startBodyLines.some((l) => /`[^`]*\$\{/.test(l))
      ) {
        startDeclaredLocals.push(["__tmpl_num_ptr", "i32"], ["__tmpl_num_len", "i32"]);
        startLocals.set("__tmpl_num_ptr", "i32");
        startLocals.set("__tmpl_num_len", "i32");
      }
      // String.fromCharCode / str.charAt in concat: pre-declare $__str_op_ptr/$__str_op_len temp pair.
      if (
        !startLocals.has("__str_op_ptr") &&
        this.startBodyLines.some((l) =>
          l.includes("String.fromCharCode(") || l.includes("String.fromCodePoint(") ||
          l.includes(".charAt(") || l.includes(".slice(") ||
          l.includes(".split(") ||
          l.includes(".padStart(") || l.includes(".padEnd(") || l.includes(".toString(") ||
          l.includes(".at(") || l.includes(".toUpperCase(") || l.includes(".toLowerCase(") ||
          /\w\[[^\]]+\]\s*\+|\+\s*\w+\[/.test(l) || // string char subscript in a concat: s[i] + …
          // console.* with a string-equality op may route a non-trivial operand through the
          // string-expr resolver (captures len into $__str_op_len).
          (/\bconsole\.(log|error|warn)\b/.test(l) && /===|!==|==|!=/.test(l))
        )
      ) {
        startDeclaredLocals.push(["__str_op_ptr", "i32"], ["__str_op_len", "i32"]);
        startLocals.set("__str_op_ptr", "i32");
        startLocals.set("__str_op_len", "i32");
      }
      // Self-referential string concat prepend (`X = … + X`): pre-declare $__concat_self pair.
      if (
        !startLocals.has("__concat_self_ptr") &&
        this.startBodyLines.some((l) => /(\w+)\s*=\s*.+\+\s*\1\b/.test(l))
      ) {
        startDeclaredLocals.push(["__concat_self_ptr", "i32"], ["__concat_self_len", "i32"]);
        startLocals.set("__concat_self_ptr", "i32");
        startLocals.set("__concat_self_len", "i32");
      }
      // Phase 44: $__fn_tmp for function pointer array element dispatch: arr[idx]()
      if (
        !startLocals.has("__fn_tmp") && this.startBodyLines.some((l) => {
          const m = l.match(/^(\w+)\[/);
          return m &&
            (this.arrayVars.get(m[1])?.isFuncPtrArr !== undefined ||
              this.moduleArrayVars.get(m[1])?.isFuncPtrArr !== undefined);
        })
      ) {
        startDeclaredLocals.push(["__fn_tmp", "i32"]);
        startLocals.set("__fn_tmp", "i32");
      }
      // Save module-level array registrations so functions can access them via emitFunction seed.
      this.moduleArrayVars = new Map(this.arrayVars);
      const localDecls = [...startLocals.entries()]
        .filter(([, t]) => t !== "string") // "string" is a tracker only
        .map(([n, t]) => `    (local $${n} ${watBaseType(t as WatType)})`)
        .join("\n");
      const bodyWat = this.emitBlock(this.startBodyLines, startLocals, null);
      startBody = `\n${
        localDecls ? localDecls + "\n" : ""
      }${bodyWat}\n    (call $proc_exit (i32.const 0))`;
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

    const moduleGlobalDecls = [...this.moduleGlobals.entries()].map(
      ([name, { type, mutable, initExpr }]) => {
        const baseType = watBaseType(type);
        const initWat = this.emitExpr(initExpr, new Map(), type);
        const typeDecl = mutable ? `(mut ${baseType})` : baseType;
        return `  (global $${name} ${typeDecl} ${initWat})`;
      },
    );
    // Mutable module-level string globals: one (mut i32) for the ptr, one for the len.
    for (const [name, { ptr, len }] of this.moduleStringGlobals) {
      moduleGlobalDecls.push(
        `  (global $${name}_ptr (mut i32) (i32.const ${ptr}))`,
        `  (global $${name}_len (mut i32) (i32.const ${len}))`,
      );
    }

    // Stage 0 / Canonical ABI: export cabi_realloc when any exported function has string params or
    // string returns. The host uses cabi_realloc(0,0,1,n) to allocate param buffers and
    // cabi_realloc(0,0,4,8) to allocate the 8-byte return area for string-returning functions.
    const hasExportedStringParams = this.functions.some(
      (f) => f.exported && !f.isClosureFactory && f.params.some((p) => p.type === "string"),
    );
    const hasExportedStringRets = this.functions.some(
      (f) => f.exported && !f.isClosureFactory && f.result === "string",
    );
    const extraExports: string[] = [];
    if (hasExportedStringParams || hasExportedStringRets) {
      extraExports.push(`  (export "cabi_realloc" (func $cabi_realloc))`);
    }
    // $__str_ret_ptr / $__str_ret_len are no longer exported — string returns use the
    // out-parameter convention via the __cabi shim wrappers generated below.

    // Generate canonical ABI shim wrappers for each exported string-returning function.
    // The shim adds a trailing $__ret_area i32 param, calls the internal function (which sets
    // the globals side-channel), then writes ptr+len into the caller-provided return area.
    const exportedStringRetFns = this.functions.filter(
      (f) => f.exported && !f.isClosureFactory && f.result === "string" && f.name !== "_start",
    );
    const shimsWat = exportedStringRetFns.map((fn) => {
      const paramDecls = fn.params.flatMap((p) =>
        p.type === "string"
          ? [`(param $${p.name}_ptr i32)`, `(param $${p.name}_len i32)`]
          : [`(param $${p.name} ${watBaseType(p.type)})`]
      );
      paramDecls.push(`(param $__ret_area i32)`);
      const callArgParts = fn.params.flatMap((p) =>
        p.type === "string"
          ? [`(local.get $${p.name}_ptr)`, `(local.get $${p.name}_len)`]
          : [`(local.get $${p.name})`]
      );
      const callExpr = callArgParts.length > 0
        ? `(call $${fn.name} ${callArgParts.join(" ")})`
        : `(call $${fn.name})`;
      return [
        `  (func $${fn.name}__cabi (export "${fn.name}") ${paramDecls.join(" ")}`,
        `    ${callExpr}`,
        `    (i32.store (local.get $__ret_area) (global.get $__str_ret_ptr))`,
        `    (i32.store offset=4 (local.get $__ret_area) (global.get $__str_ret_len))`,
        `  )`,
      ].join("\n");
    }).join("\n");

    return [
      `(module`,
      imports,
      `  (memory (export "memory") ${memoryPages})`,
      `  (global $__heap_ptr (mut i32) (i32.const ${heapStart}))`,
      this.needsNullableResultFlag ? `  (global $__nullable_ret_flag (mut i32) (i32.const 0))` : "",
      this.needsStringRetGlobals ? `  (global $__str_ret_ptr (mut i32) (i32.const 0))` : "",
      this.needsStringRetGlobals ? `  (global $__str_ret_len (mut i32) (i32.const 0))` : "",
      ...moduleGlobalDecls,
      this.needsExceptionTag ? `  (tag $__exn_tag (export "__exn_tag") (param i32 i32))` : "",
      funcTypesWat,
      ``,
      helpers,
      funcWat,
      ``,
      shimsWat,
      ...startFunc,
      funcTableWat,
      ...extraExports,
      dataSection ? `` : "",
      dataSection,
      `)`,
    ].filter((l) => l !== undefined && l !== "").join("\n");
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
): {
  mergedWat: string;
  notices: string[];
  exportedFuncs: ExternalFuncDef[];
  hasMutableGlobals: boolean;
} {
  // Disassemble the binary to WAT text
  const importedMod = wabtMod.readWasm(wasmBytes.buffer as ArrayBuffer, { readDebugNames: true });
  const importedWat = importedMod.toText({ foldExprs: false, inlineExport: false });
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
  if (result.funcWat) fragments.push(`  ;; functions from ${prefix}\n  ${result.funcWat}`);
  if (result.dataWat) fragments.push(`  ;; data from ${prefix}\n  ${result.dataWat}`);

  if (fragments.length === 0) {
    return {
      mergedWat: wat,
      notices: result.notices,
      exportedFuncs: result.exportedFuncs,
      hasMutableGlobals: result.hasMutableGlobals,
    };
  }

  // Insert before the final `)` that closes the module
  const closeIdx = wat.lastIndexOf(")");
  const mergedWat = closeIdx === -1
    ? wat + "\n" + fragments.join("\n") + "\n)"
    : wat.slice(0, closeIdx) + "\n" + fragments.join("\n") + "\n)";

  return {
    mergedWat,
    notices: result.notices,
    exportedFuncs: result.exportedFuncs,
    hasMutableGlobals: result.hasMutableGlobals,
  };
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

  if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });

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
      // Embedded capability (Brief #4): bytes/wit are carried inline; otherwise read the file.
      const bytes = entry.bytes ?? await rt.readFile(entry.filePath);
      wasmBytesMap.set(entry.filePath, bytes);
      const mod = wabtMod.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: true });
      const importedWat = mod.toText({ foldExprs: false, inlineExport: false });
      mod.destroy();
      const preResult = mergeWasmWat(importedWat, entry.prefix, 0);
      const logicalSigs = entry.witText !== undefined
        ? parseWitLogicalSigs(entry.witText, entry.prefix)
        : await readWitLogicalSigs(entry.filePath, entry.prefix);
      for (const ef of preResult.exportedFuncs) applyWitSig(ef, logicalSigs);
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
    return {
      success: false,
      error: `Transpile error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  // Report any unsupported-feature diagnostics collected during transpilation
  for (const msg of transpiler.warnings) {
    console.warn(`  ⚠️  ${msg}`);
  }
  if (transpiler.warnings.length > 0) {
    return {
      success: false,
      error:
        `Compilation aborted: ${transpiler.warnings.length} unsupported feature(s) — see warnings above`,
    };
  }

  // Phase 18: merge each imported .wasm module into the WAT
  let dataOffset = transpiler.dataEnd;
  let anyMutableGlobals = false;
  for (const entry of wasmImports) {
    const bytes = wasmBytesMap.get(entry.filePath);
    if (!bytes) continue;
    const { mergedWat, notices, hasMutableGlobals } = mergeOneWasmImport(
      wat,
      bytes,
      entry.prefix,
      dataOffset,
      wabtMod,
    );
    for (const notice of notices) {
      console.log(`  ⚠️  Imported "${entry.filePath}": ${notice}`);
    }
    wat = mergedWat;
    if (hasMutableGlobals) anyMutableGlobals = true;
    // Advance dataOffset so the next imported module's data lands above this one.
    // A second pass with mergeWasmWat(dataReloc=0) gives us the imported module's own
    // dataOffset, which we use as the relocation size.
    const mod2 = wabtMod.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: false });
    const wat2 = mod2.toText({ foldExprs: false, inlineExport: false });
    mod2.destroy();
    // Advance dataOffset by the imported module's static footprint
    const heapM = wat2.match(/\(global\s+\(;0;\)\s+\(mut i32\)\s+\(i32\.const\s+(\d+)\)\)/);
    dataOffset += heapM ? parseInt(heapM[1]) : 260 /* DATA_BASE fallback */;
  }
  // If any merged module has a mutable global placed at the page-2 boundary (131072),
  // ensure the main module declares at least 3 memory pages.
  if (anyMutableGlobals) {
    wat = wat.replace(
      /\(memory\s+\(export\s+"memory"\)\s+(\d+)\)/,
      (_full, nStr) => `(memory (export "memory") ${Math.max(3, parseInt(nStr))})`,
    );
  }

  // Phase 38: auto-merge mathlib.wasm when extended Math.* functions were used
  if (transpiler.needsMathLib) {
    const { mergedWat } = mergeOneWasmImport(wat, MATHLIB_BYTES, "mathlib", dataOffset, wabtMod);
    wat = mergedWat;
  }

  // Phase 18.5: re-seat $__heap_ptr past the COMBINED static data of all
  // merged modules. The transpiler emitted the initial `(global $__heap_ptr
  // (mut i32) (i32.const N))` line with N = main module's own dataEnd; with
  // wasmmerge's allocator unification, every merged library shares this one
  // heap cursor, so the initial value must clear all relocated data segments.
  // Also grow memory to fit the new heap-start (binaryen / runtime can grow
  // further at execution time, but the static initialiser must not point past
  // the declared page count).
  if (wasmImports.length > 0 || transpiler.needsMathLib) {
    wat = wat.replace(
      /\(global \$__heap_ptr \(mut i32\) \(i32\.const \d+\)\)/,
      `(global $__heap_ptr (mut i32) (i32.const ${dataOffset}))`,
    );
    const requiredPages = Math.max(2, Math.ceil(dataOffset / 65536) + 1);
    wat = wat.replace(
      /\(memory\s+\(export\s+"memory"\)\s+(\d+)\)/,
      (_full, nStr) => `(memory (export "memory") ${Math.max(requiredPages, parseInt(nStr))})`,
    );
  }

  // Write WAT alongside the output for inspection / debugging
  await rt.writeTextFile(watPath, wat);

  const result = await watToOptimisedWasm(wat, watPath, out);
  if (result.success) {
    // Phase 41: emit .wit interface file alongside the compiled .wasm
    const witPath = out.replace(/\.wasm$/, ".wit");
    await rt.writeTextFile(witPath, transpiler.generateWit(name));
    console.log(`✅ WASI: ${out} (${result.sizeBytes} bytes)`);
    console.log(`   WAT:  ${watPath}`);
    console.log(`   WIT:  ${witPath}`);
    if (wasmImports.length > 0) {
      console.log(`   Merged: ${wasmImports.map((e) => e.prefix).join(", ")}`);
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

  if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });

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
      const bytes = await rt.readFile(entry.filePath);
      wasmBytesMap2.set(entry.filePath, bytes);
      const mod = wabtMod2.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: true });
      const importedWat = mod.toText({ foldExprs: false, inlineExport: false });
      mod.destroy();
      const preResult2 = mergeWasmWat(importedWat, entry.prefix, 0);
      const logicalSigs2 = await readWitLogicalSigs(entry.filePath, entry.prefix);
      for (const ef of preResult2.exportedFuncs) applyWitSig(ef, logicalSigs2);
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
    return {
      success: false,
      error: `Transpile error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  for (const msg of transpiler.warnings) {
    console.warn(`  ⚠️  ${msg}`);
  }
  if (transpiler.warnings.length > 0) {
    return {
      success: false,
      error:
        `Compilation aborted: ${transpiler.warnings.length} unsupported feature(s) — see warnings above`,
    };
  }

  let dataOffset2 = transpiler.dataEnd;
  for (const entry of wasmImports) {
    const bytes = wasmBytesMap2.get(entry.filePath);
    if (!bytes) continue;
    const { mergedWat, notices } = mergeOneWasmImport(
      wat,
      bytes,
      entry.prefix,
      dataOffset2,
      wabtMod2,
    );
    for (const notice of notices) {
      console.log(`  ⚠️  Imported "${entry.filePath}": ${notice}`);
    }
    wat = mergedWat;
    const mod2 = wabtMod2.readWasm(bytes.buffer as ArrayBuffer, { readDebugNames: false });
    const wat2 = mod2.toText({ foldExprs: false, inlineExport: false });
    mod2.destroy();
    const heapM = wat2.match(/\(global\s+\(;0;\)\s+\(mut i32\)\s+\(i32\.const\s+(\d+)\)\)/);
    dataOffset2 += heapM ? parseInt(heapM[1]) : 260;
  }

  // Phase 38: auto-merge mathlib.wasm when extended Math.* functions were used
  if (transpiler.needsMathLib) {
    const { mergedWat } = mergeOneWasmImport(wat, MATHLIB_BYTES, "mathlib", dataOffset2, wabtMod2);
    wat = mergedWat;
  }

  // Phase 18.5: re-seat $__heap_ptr past the COMBINED static data of all
  // merged modules. Same logic as compileWasiTs — see comment there.
  if (wasmImports.length > 0 || transpiler.needsMathLib) {
    wat = wat.replace(
      /\(global \$__heap_ptr \(mut i32\) \(i32\.const \d+\)\)/,
      `(global $__heap_ptr (mut i32) (i32.const ${dataOffset2}))`,
    );
    const requiredPages = Math.max(2, Math.ceil(dataOffset2 / 65536) + 1);
    wat = wat.replace(
      /\(memory\s+\(export\s+"memory"\)\s+(\d+)\)/,
      (_full, nStr) => `(memory (export "memory") ${Math.max(requiredPages, parseInt(nStr))})`,
    );
  }

  await rt.writeTextFile(watPath, wat);

  const result = await watToOptimisedWasm(wat, watPath, out);
  if (result.success) {
    // Phase 41: emit .wit interface file alongside the compiled .wasm
    const witPath = out.replace(/\.wasm$/, ".wit");
    await rt.writeTextFile(witPath, transpiler.generateWit(name));
    console.log(`✅ Library: ${out} (${result.sizeBytes} bytes)`);
    console.log(`   WAT:  ${watPath}`);
    console.log(`   WIT:  ${witPath}`);
    if (wasmImports.length > 0) {
      console.log(`   Merged: ${wasmImports.map((e) => e.prefix).join(", ")}`);
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
    if (result.error) console.error(`❌ wasic: ${result.error}`);
    rt.exit(1);
  }
}
