/**
 * @module wasic
 * @description Standalone WASI compiler producing compact WebAssembly modules
 * without external toolchains or embedded JS runtimes.
 *
 * Two compilation paths:
 *   .wat  → wabt parse → Binaryen size-optimise (-Oz) → .wasm
 *   .ts   → WasicTranspiler (numeric + string subset) → WAT → same pipeline
 *
 * Generated binaries are substantially smaller than Javy output because no
 * JavaScript runtime is bundled — only user logic plus the minimal WASI syscall
 * stubs required to satisfy the host (wasmtime, wasmer, wazero, wasmtk run).
 *
 * TypeScript subset supported by the transpiler:
 *   - export function declarations with numeric params (number/i32/i64/f32/f64)
 *   - let / const variable declarations with type annotations
 *   - return statements
 *   - if / else blocks
 *   - while loops
 *   - Arithmetic:          + - * / %
 *   - Comparisons:         === !== == != < > <= >=
 *   - Logical:             && || !
 *   - Bitwise:             & | ^ ~ << >> >>>
 *   - Ternary:             cond ? a : b
 *   - Compound assignment: += -= *= /= %= &= |= ^= <<= >>= >>>=
 *   - String variables:    let/const/var name: string = "literal"  (.length supported)
 *   - console.log(...) via WASI fd_write  (see console_log.ts for full argument support)
 *   - A top-level main() or exported main() becomes the WASI _start entry point
 *
 * Limitations (planned for future iterations):
 *   - No closures, classes, or prototype-based OOP
 *   - No arrays or objects
 *   - No imports between modules
 */

import wabt from "wabt";
import binaryen from "binaryen";
import { basename, dirname } from "@std/path";
import {
  DATA_BASE,
  parseConsoleLogArgs,
  emitConsoleLog,
  getHelperWat,
  type DataAllocator,
  type FuncLookup,
} from "./console_log.ts";

// ---------------------------------------------------------------------------
// wabt type stubs (same pattern as utils.ts)
// ---------------------------------------------------------------------------
interface WasmFeatures { enable_all?: boolean; [key: string]: boolean | undefined; }
interface WabtWasmModule {
  toBinary(opts: object): { buffer: ArrayBuffer };
  destroy(): void;
}
interface WabtModule {
  parseWat(filename: string, source: string, features?: WasmFeatures): WabtWasmModule;
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
    const parsed = wabtMod.parseWat(sourcePath, watSource, { enable_all: true });
    const { buffer } = parsed.toBinary({});
    parsed.destroy();
    const rawBytes = new Uint8Array(buffer);

    // Step 2: Binaryen -Oz (shrinkLevel=2, optimizeLevel=2)
    const binMod = binaryen.readBinary(rawBytes);
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

/** WAT numeric types plus "string" and "bool" as compiler-level pseudo-types. */
type WatType = "i32" | "i64" | "f32" | "f64" | "string" | "bool";

/** Maps a compiler WatType to the concrete WAT numeric type (bool → i32, string → i32). */
function watBaseType(t: WatType): "i32" | "i64" | "f32" | "f64" {
  if (t === "bool" || t === "string") return "i32";
  return t as "i32" | "i64" | "f32" | "f64";
}

interface FuncParam {
  name: string;
  type: WatType;
}

interface FuncDef {
  name: string;
  params: FuncParam[];
  result: WatType | null;
  exported: boolean;
  bodyLines: string[];
}

/** Maps TypeScript type annotation strings to WAT types (or the "string" pseudo-type). */
function mapType(ts: string): WatType {
  // Strip union null/undefined modifiers: "string | null" → "string", "T | undefined" → "T"
  const stripped = ts.split("|").map(p => p.trim()).filter(p => p !== "null" && p !== "undefined");
  const base = (stripped[0] ?? ts).trim();
  const t = base.toLowerCase();
  if (t === "i32" || t === "int") return "i32";
  if (t === "i64") return "i64";
  if (t === "f32") return "f32";
  if (t === "bigint") return "i64";
  if (t === "bool" || t === "boolean") return "bool";   // boolean → bool pseudo-type (WAT i32)
  if (t === "string" || t === "str")   return "string"; // pseudo-type: ptr+len i32 locals
  return "f64"; // number, f64, or unknown → f64
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
  enumValues: Map<string, number>
): WatType {
  const e = initExpr.trim();
  // 0. boolean literals
  if (e === "true" || e === "false") return "bool";
  // 1. bigint literal
  if (/^-?\d+n$/.test(e)) return "i64";
  // 2. contains a comparison or logical operator → boolean
  if (/===|!==|==|!=|<=|>=|<|>|&&|\|\||^!/.test(e)) return "bool";
  if (e.startsWith("!")) return "bool";
  // 3. leading identifier declared as i64
  const leadId = e.match(/^(\w+)/)?.[1];
  if (leadId && locals.get(leadId) === "i64") return "i64";
  // 4. enum member access
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
  private dataOffset = DATA_BASE;  // first DATA_BASE bytes reserved for iov/scratch/nwritten
  private hasConsoleLog = false;
  private needsNumericHelpers = false;
  private needsStringHelpers = false;

  // Tracks variable names declared with type "string" (stored as ptr+len i32 locals)
  private stringVars: Set<string> = new Set();
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

  constructor(source: string) {
    this.src = stripComments(source);
  }

  // -------------------------------------------------------------------------
  // Pass 1 – collect function signatures and bodies
  // -------------------------------------------------------------------------
  private parseFunctions(): void {
    const src = this.src;
    // Match: [export] function name(params): returnType {
    const headerRe = /(export\s+)?function\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*(\w+))?\s*\{/g;
    let m: RegExpExecArray | null;

    while ((m = headerRe.exec(src)) !== null) {
      const exported = !!m[1];
      const name = m[2];
      const rawParams = m[3].trim();
      const rawResult = (m[4] ?? "void").trim();

      const params: FuncParam[] = rawParams
        ? rawParams.split(",").map(p => {
            const parts = p.split(":").map(s => s.trim());
            return { name: parts[0], type: mapType(parts[1] ?? "number") };
          })
        : [];

      const result: WatType | null =
        rawResult === "void" || rawResult === "" ? null : mapType(rawResult);

      // Extract body by counting braces from the opening {
      const bodyStart = m.index + m[0].length;
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

      this.functions.push({ name, params, result, exported, bodyLines });
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

        // Pattern 2: IIFE (function …) — inner function already parsed, just skip wrapper
        if (/^\(function\s+/.test(line)) {
          depth += opens - closes;
          continue;
        }

        // Enum declaration — skip body (values captured by parseEnums)
        if (/^(?:export\s+)?(?:const\s+)?enum\s+\w+/.test(line)) {
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
    _locals: Map<string, WatType>
  ): string {
    this.stringVars.add(varName);

    // String literal
    const litMatch = initExpr.match(/^"([^"]*)"$/) ?? initExpr.match(/^'([^']*)'$/);
    if (litMatch) {
      const [offset, len] = this.allocString(litMatch[1]);
      return [
        `(local.set $${varName}_ptr (i32.const ${offset}))`,
        `      (local.set $${varName}_len (i32.const ${len}))`,
      ].join("\n");
    }

    // Another string variable
    if (/^\w+$/.test(initExpr) && this.stringVars.has(initExpr)) {
      return [
        `(local.set $${varName}_ptr (local.get $${initExpr}_ptr))`,
        `      (local.set $${varName}_len (local.get $${initExpr}_len))`,
      ].join("\n");
    }

    return `(;; string assignment from complex expression not yet supported: ${varName} = ${initExpr};)`;
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
    const expr = raw.trim();

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

    // String .length property: varName.length
    const lenPropMatch = expr.match(/^(\w+)\.length$/);
    if (lenPropMatch && locals.get(lenPropMatch[1]) === "string") {
      return `(local.get $${lenPropMatch[1]}_len)`;
    }

    // Enum member access: EnumName.MemberName → (i32.const value)
    const enumDotMatch = expr.match(/^(\w+)\.(\w+)$/);
    if (enumDotMatch) {
      const enumKey = `${enumDotMatch[1]}.${enumDotMatch[2]}`;
      if (this.enumValues.has(enumKey)) {
        return `(i32.const ${this.enumValues.get(enumKey)})`;
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
      return `(local.get $${expr})`;
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
      // String params expand to two stack values (ptr + len)
      const emittedArgs = args.flatMap((a, i) => {
        const paramType = fn?.params[i]?.type ?? defaultType;
        if (paramType === "string") {
          return [this.emitStringPtrLen(a, locals)]; // already "ptr len"
        }
        return [this.emitExpr(a, locals, paramType)];
      }).join(" ");
      return `(call $${callee} ${emittedArgs})`.trim();
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
        return `(${watOp} ${this.emitExpr(lhs, locals, lhsType)} ${this.emitExpr(rhs, locals, lhsType)})`;
      }
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
        if (op === ">"  && (after === "=" || after === ">" || before === ">")) continue;
        if (op === "="  && after === "=")                                 continue;
        if (op === "!"  && after === "=")                                 continue;
        if (op === "==" && (after === "=" || before === "="))             continue; // avoid === match
        if (op === "!=" && after === "=")                                 continue; // avoid !== match
        if (op === "&"  && (after === "&" || before === "&"))             continue;
        if (op === "|"  && (after === "|" || before === "|"))             continue;
        if (op === ">>" && (after === ">" || before === ">"))             continue;
        if (op === "?"  && after === ".")                                  continue; // optional chaining ?.
        return i;
      }
    }
    return -1;
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

    // var / let / const declaration
    const letMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?);?$/);
    if (letMatch) {
      const varName  = letMatch[1];
      const typeStr  = letMatch[2] ?? "";
      const initExpr = letMatch[3].trim();
      const varType = typeStr ? mapType(typeStr) : inferInitType(initExpr, locals, this.enumValues);
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
      const segments = parseConsoleLogArgs(logMatch[1], locals as Map<string, string>, lookup, allocator, enumLookup);
      const { statements, needsHelpers } = emitConsoleLog(segments, allocator);
      if (needsHelpers) this.needsNumericHelpers = true;
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

    // Standalone function call (statement form)
    const callMatch = line.match(/^(\w+)\s*\((.*)?\)\s*;?$/);
    if (callMatch) {
      const callee = callMatch[1];
      if (callee !== "console") {
        const rawArgs = callMatch[2]?.trim() ?? "";
        const args = rawArgs ? this.splitArgs(rawArgs) : [];
        const fn = this.functions.find(f => f.name === callee);
        const emittedArgs = args.flatMap((a, i) => {
          const pt = fn?.params[i]?.type ?? "f64" as WatType;
          if (pt === "string") return [this.emitStringPtrLen(a, locals)];
          return [this.emitExpr(a, locals, pt)];
        }).join(" ");
        const call = `(call $${callee} ${emittedArgs})`.trim();
        return fn?.result ? `(drop ${call})` : call;
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
    const lines = [
      `  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))`,
    ];
    if (this.hasConsoleLog) {
      lines.push(
        `  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))`
      );
    }
    return lines.join("\n");
  }

  private emitHelpers(): string {
    const parts: string[] = [];
    if (this.needsStringHelpers)  parts.push(this.getStringHelperWat());
    if (this.needsNumericHelpers) parts.push(getHelperWat());
    return parts.join("\n");
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

  private emitDataSection(): string {
    if (this.dataMap.size === 0) return "";
    const segments: string[] = [];
    for (const [msg, [offset]] of this.dataMap) {
      const escaped = Array.from(new TextEncoder().encode(msg))
        .map(b => `\\${b.toString(16).padStart(2, "0")}`)
        .join("");
      segments.push(`  (data (i32.const ${offset}) "${escaped}")`);
    }
    return segments.join("\n");
  }

  private emitFunction(fn: FuncDef): string {
    const locals = new Map<string, WatType>();
    for (const p of fn.params) {
      locals.set(p.name, p.type);
      if (p.type === "string") this.stringVars.add(p.name);
    }

    // String params expand to two i32 params: $name_ptr and $name_len
    const params = fn.params
      .flatMap(p => p.type === "string"
        ? [`(param $${p.name}_ptr i32)`, `(param $${p.name}_len i32)`]
        : [`(param $${p.name} ${watBaseType(p.type)})`]
      )
      .join(" ");
    // String/bool return types — string not yet supported (void), bool → i32
    const watResult = fn.result === null || fn.result === "string" ? null : watBaseType(fn.result);
    const result    = watResult ? `(result ${watResult})` : "";
    const exportAttr = fn.exported ? `(export "${fn.name}") ` : "";

    // Pre-scan body for var/let/const declarations to emit WAT locals.
    // String variables expand to two i32 locals: $name_ptr and $name_len.
    const declaredLocals: [string, WatType][] = [];
    for (const line of fn.bodyLines) {
      const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
      if (m) {
        const typeStr = m[2] ?? "";
        const initExpr = (m[3] ?? "").trim();
        const t = typeStr ? mapType(typeStr) : inferInitType(initExpr, locals, this.enumValues);
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
        const t2 = typeStr2 ? mapType(typeStr2) : inferInitType(initExpr2, locals, this.enumValues);
        declaredLocals.push([forM[1], t2]);
        locals.set(forM[1], t2);
      }
    }
    const localDecls = declaredLocals
      .map(([n, t]) => `    (local $${n} ${watBaseType(t)})`)
      .join("\n");

    const body = this.emitBlock(fn.bodyLines, locals, fn.result);

    return [
      `  (func $${fn.name} ${exportAttr}${params} ${result}`,
      localDecls ? localDecls : "",
      body,
      `  )`,
    ].filter(l => l.trim() !== "").join("\n");
  }

  transpile(_moduleName: string): string {
    this.parseEnums();
    this.parseFunctions();
    this.parseTopLevel();

    // Emit all user functions first — this populates hasConsoleLog/needsNumericHelpers
    const funcWat = this.functions.map(f => this.emitFunction(f)).join("\n\n");

    // Build _start inner body — priority: user _start() > named main() > collected startBodyLines > empty
    const hasUserStart = this.functions.some(f => f.name === "_start");
    const hasMain = !hasUserStart && this.functions.some(f => f.name === "main");
    let startBody: string;
    if (hasMain) {
      startBody = `\n    (call $main)\n    (call $proc_exit (i32.const 0))`;
    } else if (this.startBodyLines.length > 0) {
      // Pre-scan for var/let/const so WAT locals are declared at the top of _start.
      // String variables expand to two i32 locals ($name_ptr, $name_len).
      const startLocals = new Map<string, WatType>();
      const startDeclaredLocals: [string, WatType][] = [];
      for (const line of this.startBodyLines) {
        const m = line.match(/^(?:var|let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*(?:=\s*(.+?))?;?$/);
        if (m) {
          const typeStr = m[2] ?? "";
          const initExpr = (m[3] ?? "").trim();
          const t = typeStr ? mapType(typeStr) : inferInitType(initExpr, startLocals, this.enumValues);
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
          const t2 = typeStr2 ? mapType(typeStr2) : inferInitType(initExpr2, startLocals, this.enumValues);
          startDeclaredLocals.push([forM[1], t2]);
          startLocals.set(forM[1], t2);
        }
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
    const memoryPages = Math.max(1, Math.ceil(this.dataOffset / 65536));

    // If the user defined _start() directly, skip the generated wrapper
    const startFunc = hasUserStart ? [] : [
      `  (func $_start (export "_start")${startBody}`,
      `  )`,
    ];

    return [
      `(module`,
      imports,
      `  (memory (export "memory") ${memoryPages})`,
      ``,
      helpers,
      funcWat,
      ``,
      ...startFunc,
      dataSection ? `` : "",
      dataSection,
      `)`,
    ].filter(l => l !== undefined).join("\n");
  }
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
  const out = outPath ?? `./${name}.wasm`;
  // WAT goes alongside the output WASM when outPath is specified
  const watPath = outPath ? out.replace(/\.wasm$/, ".wat") : `./${name}.wat`;

  if (outPath) await Deno.mkdir(dirname(outPath), { recursive: true });

  let source: string;
  try {
    source = await Deno.readTextFile(tsPath);
  } catch (err) {
    return { success: false, error: `Cannot read ${tsPath}: ${err}` };
  }

  const transpiler = new WasicTranspiler(source);
  let wat: string;
  try {
    wat = transpiler.transpile(name);
  } catch (err) {
    return { success: false, error: `Transpile error: ${err instanceof Error ? err.message : String(err)}` };
  }

  // Write WAT alongside the output for inspection / debugging
  await Deno.writeTextFile(watPath, wat);

  const result = await watToOptimisedWasm(wat, watPath, out);
  if (result.success) {
    console.log(`✅ WASI: ${out} (${result.sizeBytes} bytes)`);
    console.log(`   WAT:  ${watPath}`);
  } else {
    console.error(`❌ wasic: ${result.error}`);
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
