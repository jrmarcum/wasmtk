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
 *   - Arithmetic: + - * / %
 *   - Comparisons: === !== < > <= >=
 *   - console.log("string literal") via WASI fd_write
 *   - A top-level main() or exported main() becomes the WASI _start entry point
 *
 * Limitations (planned for future iterations):
 *   - No closures, classes, or prototype-based OOP
 *   - No dynamic strings (only string literal arguments to console.log)
 *   - No arrays or objects
 *   - No imports between modules
 */

import wabt from "wabt";
import binaryen from "binaryen";
import { basename } from "@std/path";

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

type WatType = "i32" | "i64" | "f32" | "f64";

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

/** Maps TypeScript type annotation strings to WAT numeric types. */
function mapType(ts: string): WatType {
  const t = ts.trim().toLowerCase();
  if (t === "i32" || t === "int") return "i32";
  if (t === "i64") return "i64";
  if (t === "f32") return "f32";
  return "f64"; // number, f64, or unknown → f64
}

/** Returns the WAT zero-literal for a given type. */
function zeroOf(t: WatType): string {
  return t === "f64" ? "(f64.const 0)" : t === "f32" ? "(f32.const 0)" : `(${t}.const 0)`;
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
  private dataOffset = 256; // first 256 bytes: iov scratch + reserved
  private hasConsoleLog = false;

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
      let bodyStart = m.index + m[0].length;
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
  // Expression emitter
  // -------------------------------------------------------------------------
  private emitExpr(
    raw: string,
    locals: Map<string, WatType>,
    defaultType: WatType
  ): string {
    const expr = raw.trim();

    // Parenthesised group
    if (expr.startsWith("(") && expr.endsWith(")")) {
      return this.emitExpr(expr.slice(1, -1), locals, defaultType);
    }

    // Numeric literal
    if (/^-?\d+(\.\d+)?$/.test(expr)) {
      if (defaultType === "i32" || defaultType === "i64") return `(${defaultType}.const ${expr})`;
      return `(${defaultType}.const ${expr})`;
    }

    // Identifier (local variable or parameter)
    if (/^\w+$/.test(expr)) {
      return `(local.get $${expr})`;
    }

    // Function call: name(arg1, arg2, ...)
    const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
    if (callMatch) {
      const callee = callMatch[1];
      const rawArgs = callMatch[2]?.trim() ?? "";
      const args = rawArgs ? this.splitArgs(rawArgs) : [];
      const fn = this.functions.find(f => f.name === callee);
      const emittedArgs = args.map((a, i) => {
        const paramType = fn?.params[i]?.type ?? defaultType;
        return this.emitExpr(a, locals, paramType);
      }).join(" ");
      return `(call $${callee} ${emittedArgs})`.trim();
    }

    // Binary operators — scan right-to-left for lowest-precedence op outside parens
    const binaryOps: [string, string, string][] = [
      ["===", "eq",   "eq"],
      ["!==", "ne",   "ne"],
      ["<=",  "le_s", "le"],
      [">=",  "ge_s", "ge"],
      ["<",   "lt_s", "lt"],
      [">",   "gt_s", "gt"],
      ["+",   "add",  "add"],
      ["-",   "sub",  "sub"],
      ["*",   "mul",  "mul"],
      ["/",   "div_s","div"],
      ["%",   "rem_s","rem"],
    ];

    for (const [op, i32suf, f64suf] of binaryOps) {
      const idx = this.findBinaryOp(expr, op);
      if (idx !== -1) {
        const lhs = expr.slice(0, idx).trim();
        const rhs = expr.slice(idx + op.length).trim();
        const suffix = (defaultType === "i32" || defaultType === "i64") ? i32suf : f64suf;
        const watOp = `${defaultType}.${suffix}`;
        return `(${watOp} ${this.emitExpr(lhs, locals, defaultType)} ${this.emitExpr(rhs, locals, defaultType)})`;
      }
    }

    // Fallback: emit a comment and a zero so compilation succeeds
    return `(;? ${expr};) ${zeroOf(defaultType)}`;
  }

  /** Finds an operator in an expression while respecting paren nesting. */
  private findBinaryOp(expr: string, op: string): number {
    let depth = 0;
    for (let i = expr.length - op.length; i >= 0; i--) {
      const ch = expr[i];
      if (ch === ")") depth++;
      else if (ch === "(") depth--;
      if (depth === 0 && expr.slice(i, i + op.length) === op) {
        // Avoid matching the operator as part of a longer op (e.g. < in <=)
        const after = expr[i + op.length];
        if (op === "<" && after === "=") continue;
        if (op === ">" && after === "=") continue;
        if (op === "=" && after === "=") continue;
        if (op === "!" && after === "=") continue;
        return i;
      }
    }
    return -1;
  }

  /** Splits a comma-separated argument list, respecting nested parens. */
  private splitArgs(raw: string): string[] {
    const args: string[] = [];
    let depth = 0, start = 0;
    for (let i = 0; i < raw.length; i++) {
      if (raw[i] === "(") depth++;
      else if (raw[i] === ")") depth--;
      else if (raw[i] === "," && depth === 0) {
        args.push(raw.slice(start, i).trim());
        start = i + 1;
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

    // let / const declaration
    const letMatch = line.match(/^(?:let|const)\s+(\w+)\s*(?::\s*(\w+))?\s*=\s*(.+?);?$/);
    if (letMatch) {
      const varName = letMatch[1];
      const varType = mapType(letMatch[2] ?? "number");
      const initExpr = letMatch[3].trim();
      locals.set(varName, varType);
      return `(local.set $${varName} ${this.emitExpr(initExpr, locals, varType)})`;
    }

    // Assignment (no let/const)
    const assignMatch = line.match(/^(\w+)\s*=\s*(.+?);?$/);
    if (assignMatch && locals.has(assignMatch[1])) {
      const varName = assignMatch[1];
      const varType = locals.get(varName)!;
      return `(local.set $${varName} ${this.emitExpr(assignMatch[2].trim(), locals, varType)})`;
    }

    // console.log("string literal")
    const logMatch = line.match(/^console\.log\s*\(\s*"([^"]*)"\s*\)\s*;?$/);
    if (logMatch) {
      const msg = logMatch[1] + "\n";
      const [offset, len] = this.allocString(msg);
      // iov at offset 0: ptr=4 (data ptr field), len=8 (data len field)
      // Layout: [0..3]=ptr, [4..7]=len, nwritten at [8..11]
      return [
        `(i32.store (i32.const 0) (i32.const ${offset}))`,
        `(i32.store (i32.const 4) (i32.const ${len}))`,
        `(drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))`,
      ].join("\n      ");
    }

    // Standalone function call (statement form)
    const callMatch = line.match(/^(\w+)\s*\((.*)?\)\s*;?$/);
    if (callMatch) {
      const callee = callMatch[1];
      if (callee !== "console") {
        const rawArgs = callMatch[2]?.trim() ?? "";
        const args = rawArgs ? this.splitArgs(rawArgs) : [];
        const fn = this.functions.find(f => f.name === callee);
        const emittedArgs = args.map((a, i) => {
          const pt = fn?.params[i]?.type ?? "f64" as WatType;
          return this.emitExpr(a, locals, pt);
        }).join(" ");
        const call = `(call $${callee} ${emittedArgs})`.trim();
        return fn?.result ? `(drop ${call})` : call;
      }
    }

    return `(;; ${line};)`;
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

      // if (cond) {
      const ifMatch = line.match(/^if\s*\((.+)\)\s*\{?$/);
      if (ifMatch) {
        const cond = ifMatch[1].trim();
        // Collect if-body lines until matching }
        const [ifBody, consumed] = this.extractBlock(lines, i + 1);
        i += consumed + 1;
        // Check for else
        let elseBody: string[] = [];
        if (i < lines.length && lines[i].match(/^}\s*else\s*\{?$/)) {
          const [eb, ec] = this.extractBlock(lines, i + 1);
          elseBody = eb;
          i += ec + 1;
        }

        const condExpr = this.emitExpr(cond, locals, "i32");
        const ifWat = this.emitBlock(ifBody, locals, funcResult, indent + "  ");
        if (elseBody.length > 0) {
          const elseWat = this.emitBlock(elseBody, locals, funcResult, indent + "  ");
          out.push(`${indent}(if (result ${funcResult ?? "i32"}) ${condExpr}`);
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
        const condExpr = this.emitExpr(cond, locals, "i32");
        const bodyWat = this.emitBlock(whileBody, locals, funcResult, indent + "    ");
        out.push(`${indent}(block $break`);
        out.push(`${indent}  (loop $loop`);
        out.push(`${indent}    (br_if $break (i32.eqz ${condExpr}))`);
        out.push(bodyWat);
        out.push(`${indent}    (br $loop)`);
        out.push(`${indent}  )`);
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
   *  Returns [bodyLines, linesConsumed]. Handles both implicit (no {) and explicit braces. */
  private extractBlock(lines: string[], start: number): [string[], number] {
    const body: string[] = [];
    let depth = 1;
    let i = start;
    while (i < lines.length) {
      const l = lines[i];
      if (l.endsWith("{")) depth++;
      if (l === "}" || l === "};" || l === "} else {") {
        depth--;
        if (depth === 0) break;
      }
      body.push(l);
      i++;
    }
    return [body, i - start + 1];
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
    for (const p of fn.params) locals.set(p.name, p.type);

    const params = fn.params.map(p => `(param $${p.name} ${p.type})`).join(" ");
    const result = fn.result ? `(result ${fn.result})` : "";
    const exportAttr = fn.exported ? `(export "${fn.name}") ` : "";

    // Pre-scan body for let/const declarations to emit WAT locals
    const declaredLocals: [string, WatType][] = [];
    for (const line of fn.bodyLines) {
      const m = line.match(/^(?:let|const)\s+(\w+)\s*(?::\s*(\w+))?/);
      if (m) {
        const t = mapType(m[2] ?? "number");
        declaredLocals.push([m[1], t]);
        locals.set(m[1], t);
      }
    }
    const localDecls = declaredLocals
      .map(([n, t]) => `    (local $${n} ${t})`)
      .join("\n");

    const body = this.emitBlock(fn.bodyLines, locals, fn.result);

    return [
      `  (func $${fn.name} ${exportAttr}${params} ${result}`,
      localDecls ? localDecls : "",
      body,
      `  )`,
    ].filter(l => l.trim() !== "").join("\n");
  }

  transpile(moduleName: string): string {
    this.parseFunctions();

    // Emit all functions first so hasConsoleLog is populated before imports
    const funcWat = this.functions.map(f => this.emitFunction(f)).join("\n\n");

    // Determine if there is a main() to call from _start
    const hasMain = this.functions.some(f => f.name === "main");
    const startBody = hasMain ? `\n    (call $main)\n    (call $proc_exit (i32.const 0))` : `\n    (call $proc_exit (i32.const 0))`;

    const imports = this.emitWasiImports();
    const dataSection = this.emitDataSection();
    const memoryPages = Math.max(1, Math.ceil(this.dataOffset / 65536));

    return [
      `(module`,
      imports,
      `  (memory (export "memory") ${memoryPages})`,
      ``,
      funcWat,
      ``,
      `  (func $_start (export "_start")${startBody}`,
      `  )`,
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

  // Write WAT alongside the source for inspection / debugging
  const watPath = `./${name}.wasic.wat`;
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
export async function compileWasi(path: string): Promise<void> {
  if (path.endsWith(".wat")) {
    await compileWat(path);
    return;
  }

  if (!path.endsWith(".ts")) {
    console.error(`❌ wasic expects a .ts or .wat file. Got: ${path}`);
    return;
  }

  const result = await compileWasiTs(path);
  if (!result.success) {
    Deno.exit(1);
  }
}
