/**
 * @module bindgen
 * @description TypeScript host binding generator for wasic-compiled WASM modules.
 *
 * Reads a .wit file (produced by `wasmtk wasic` or `wasmtk modc`) and generates a
 * self-contained TypeScript binding file that loads the WASM module and wraps every
 * export with correct ABI translation:
 *   - Numeric types (s32/s64/f32/f64) pass directly as JS numbers.
 *   - `bool` params → `value ? 1 : 0`; returns → `result !== 0`.
 *   - `string` params → TextEncoder → `cabi_realloc(0,0,1,len)`, pass (ptr, len).
 *   - `string` returns → allocate 8-byte return area via `cabi_realloc(0,0,4,8)`, pass as
 *     trailing arg to the shim, read ptr+len back via DataView.
 *   - WIT `import` section → `ModuleImports` interface + env object wiring.
 *
 * CLI:
 *   wasmtk bindgen <file.wit> [-o output.ts] [--runtime deno|node|bun]
 */

import { rt } from "./rt.ts";

// ── WIT type definitions ─────────────────────────────────────────────────────

/** WIT primitive type that can appear as a parameter or return type in a world declaration. */
export type WitType = "s32" | "s64" | "f32" | "f64" | "bool" | "string";

/** A single parameter in a WIT function signature with its camelCase TypeScript name and WIT type. */
export interface WitParam {
  /** Parameter name in camelCase (already converted from the kebab-case WIT spelling). */
  name: string;
  /** WIT type of the parameter. */
  type: WitType;
}

/** A parsed WIT function declaration with its original kebab-case name, derived camelCase name, params, and optional return type. */
export interface WitFunc {
  /** Original kebab-case WIT name (used to derive the WASM symbol). */
  name: string;
  /** Derived camelCase TypeScript name. */
  tsName: string;
  /** Ordered parameter list of the function signature. */
  params: WitParam[];
  /** Return type, or `null` for a void function. */
  result: WitType | null;
}

/** The complete parsed representation of a `.wit` file produced by `wasmtk wasic` or `wasmtk modc`. */
export interface ParsedWit {
  /** Package name from the `package` declaration, e.g. `"local:basic-wit-gen-41"`. */
  packageName: string;
  /** World name from the `world` declaration, e.g. `"basic-wit-gen-41"`. */
  worldName: string;
  /** Functions declared as imports in the world. */
  imports: WitFunc[];
  /** Functions declared as exports in the world. */
  exports: WitFunc[];
}

/** Options passed to `generateBindings()` and `runBindgen()`. */
export interface BindgenOptions {
  /** Target host runtime that the generated module-loading code is written for. */
  runtime?: "deno" | "node" | "bun";
}

// ── WIT parser ───────────────────────────────────────────────────────────────

function parseWitType(raw: string): WitType {
  switch (raw.trim()) {
    case "s32":
      return "s32";
    case "s64":
      return "s64";
    case "f32":
      return "f32";
    case "f64":
      return "f64";
    case "bool":
      return "bool";
    case "string":
      return "string";
    default:
      return "s32";
  }
}

/** Convert kebab-case WIT name to camelCase TypeScript name. */
function kebabToCamel(name: string): string {
  return name.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

/**
 * Convert a kebab-case WIT name back to the underscore WASM symbol name.
 * e.g. "host-mul" → "host_mul", "env-get-value" → "env_get_value"
 * This is lossless when the original names used underscores + no inner camelCase.
 */
function kebabToWasmName(name: string): string {
  return name.replace(/-/g, "_");
}

function parseWitParams(raw: string): WitParam[] {
  if (!raw.trim()) return [];
  return raw.split(",").map((part) => {
    const colon = part.indexOf(":");
    if (colon < 0) return null;
    const rawName = part.slice(0, colon).trim();
    const type = parseWitType(part.slice(colon + 1));
    return { name: kebabToCamel(rawName), type };
  }).filter(Boolean) as WitParam[];
}

function parseWitFuncs(body: string, keyword: "import" | "export"): WitFunc[] {
  const funcs: WitFunc[] = [];
  const re = new RegExp(
    `\\b${keyword}\\s+([\\w-]+)\\s*:\\s*func\\s*\\(([^)]*)\\)(?:\\s*->\\s*([\\w-]+))?\\s*;`,
    "g",
  );
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) {
    const name = m[1]; // kebab-case WIT name
    const params = parseWitParams(m[2]);
    const result = m[3] ? parseWitType(m[3]) : null;
    funcs.push({ name, tsName: kebabToCamel(name), params, result });
  }
  return funcs;
}

/** Parse a WIT file produced by `wasmtk wasic` or `wasmtk modc`. */
export function parseWit(src: string): ParsedWit {
  const pkgMatch = src.match(/package\s+([\w:/-]+)\s*;/);
  const packageName = pkgMatch ? pkgMatch[1] : "";

  const worldMatch = src.match(/world\s+([\w-]+)\s*\{([\s\S]*)\}/);
  const worldName = worldMatch ? worldMatch[1] : "";
  const worldBody = worldMatch ? worldMatch[2] : "";

  return {
    packageName,
    worldName,
    imports: parseWitFuncs(worldBody, "import"),
    exports: parseWitFuncs(worldBody, "export"),
  };
}

// ── TypeScript binding generator ─────────────────────────────────────────────

function witTypeToTs(t: WitType): string {
  switch (t) {
    case "s32":
    case "f32":
    case "f64":
      return "number";
    case "s64":
      return "bigint";
    case "bool":
      return "boolean";
    case "string":
      return "string";
  }
}

function genExportsInterface(fns: WitFunc[], name = "ModuleExports"): string {
  const lines = [`export interface ${name} {`];
  for (const fn of fns) {
    const paramStr = fn.params.map((p) => `${p.name}: ${witTypeToTs(p.type)}`).join(", ");
    const retType = fn.result ? witTypeToTs(fn.result) : "void";
    lines.push(`  ${fn.tsName}(${paramStr}): ${retType};`);
  }
  lines.push(`}`);
  return lines.join("\n");
}

function genImportsInterface(fns: WitFunc[]): string {
  if (fns.length === 0) return "";
  const lines = [`export interface ModuleImports {`, `  env?: {`];
  for (const fn of fns) {
    const paramStr = fn.params.map((p) => `${p.name}: ${witTypeToTs(p.type)}`).join(", ");
    const retType = fn.result ? witTypeToTs(fn.result) : "void";
    lines.push(`    ${fn.tsName}?: (${paramStr}) => ${retType};`);
  }
  lines.push(`  };`);
  lines.push(`}`);
  return lines.join("\n");
}

function genLoadModule(parsed: ParsedWit, runtime: "deno" | "node" | "bun"): string {
  const { imports: importedFns, exports: exportedFns } = parsed;
  const hasImports = importedFns.length > 0;
  const needsMalloc = exportedFns.some((fn) => fn.params.some((p) => p.type === "string"));
  const needsStrRet = exportedFns.some((fn) => fn.result === "string");
  const needsMemory = needsMalloc || needsStrRet;

  const lines: string[] = [];

  // Function signature
  const importParam = hasImports ? `,\n  imports?: ModuleImports` : "";
  lines.push(`export async function loadModule(`);
  lines.push(`  source: string | URL | BufferSource${importParam},`);
  lines.push(`): Promise<ModuleExports> {`);

  // Import object
  if (hasImports) {
    lines.push(`  const env: Record<string, unknown> = {};`);
    for (const fn of importedFns) {
      const wasmName = kebabToWasmName(fn.name);
      const argList = fn.params.map((_, i) => `_a${i}`).join(", ");
      const callArgs = fn.params.map((p, i) => {
        if (p.type === "bool") return `_a${i} !== 0`;
        return `_a${i}`;
      }).join(", ");
      if (fn.result === null) {
        lines.push(
          `  env["${wasmName}"] = (${argList}: number) => { imports?.env?.${fn.tsName}?.(${callArgs}); };`,
        );
      } else {
        lines.push(
          `  env["${wasmName}"] = (${argList}: number) => (imports?.env?.${fn.tsName}?.(${callArgs}) ?? 0);`,
        );
      }
    }
    lines.push(`  const importObj = { env };`);
  } else {
    lines.push(`  const importObj: Record<string, Record<string, unknown>> = {};`);
  }

  // Load raw bytes
  if (runtime === "node") {
    lines.push(`  // deno-lint-ignore-file`);
    lines.push(`  const { readFileSync } = await import("node:fs");`);
    lines.push(
      `  const raw: ArrayBuffer = typeof source === "string" ? readFileSync(source).buffer`,
    );
    lines.push(
      `    : source instanceof URL ? readFileSync(source.pathname).buffer : source as ArrayBuffer;`,
    );
  } else if (runtime === "bun") {
    lines.push(`  const _src = String(source);`);
    lines.push(`  const raw: ArrayBuffer = typeof source === "string" || source instanceof URL`);
    lines.push(
      `    ? await (globalThis as unknown as { Bun: { file(p: string): { arrayBuffer(): Promise<ArrayBuffer> } } }).Bun.file(_src).arrayBuffer()`,
    );
    lines.push(`    : source instanceof ArrayBuffer ? source : (source as Uint8Array).buffer;`);
  } else {
    // deno (default) — use readFile for file:// paths, fetch for http
    lines.push(`  let raw: ArrayBuffer;`);
    lines.push(`  if (source instanceof ArrayBuffer) {`);
    lines.push(`    raw = source;`);
    lines.push(`  } else if (ArrayBuffer.isView(source)) {`);
    lines.push(`    raw = (source as Uint8Array).buffer as ArrayBuffer;`);
    lines.push(`  } else {`);
    lines.push(`    raw = await (await fetch(String(source))).arrayBuffer();`);
    lines.push(`  }`);
  }

  lines.push(`  const { instance } = await WebAssembly.instantiate(raw, importObj);`);
  lines.push(`  const exp = instance.exports as Record<string, unknown>;`);

  if (needsMemory) {
    lines.push(`  const _mem = exp["memory"] as WebAssembly.Memory;`);
  }
  if (needsMalloc || needsStrRet) {
    lines.push(
      `  const _cabi_realloc = exp["cabi_realloc"] as ((ptr: number, oldSize: number, align: number, newSize: number) => number);`,
    );
  }
  if (needsMalloc) {
    lines.push(`  function _writeStr(s: string): [number, number] {`);
    lines.push(`    const b = new TextEncoder().encode(s);`);
    lines.push(`    const ptr = _cabi_realloc(0, 0, 1, b.length);`);
    lines.push(`    new Uint8Array(_mem.buffer).set(b, ptr);`);
    lines.push(`    return [ptr, b.length];`);
    lines.push(`  }`);
  }
  // String returns use the out-parameter convention: caller allocates an 8-byte return area via
  // cabi_realloc(0,0,4,8) and passes its address as the last argument to the shim function.
  // After the call, ptr and len are read back from the return area via DataView.

  // Return object
  lines.push(`  return {`);
  for (const fn of exportedFns) {
    // WASM export name = original camelCase TypeScript name; reconstruct via kebabToCamel
    const wasmName = kebabToCamel(fn.name);
    const paramStr = fn.params.map((p) => `${p.name}: ${witTypeToTs(p.type)}`).join(", ");
    const wasm = `(exp["${wasmName}"] as (...a: unknown[]) => unknown)`;

    // Build WASM call args
    const callArgs = fn.params.map((p) => {
      if (p.type === "string") return `..._writeStr(${p.name})`;
      if (p.type === "bool") return `${p.name} ? 1 : 0`;
      return p.name;
    }).join(", ");

    if (fn.result === "string") {
      const cabiArgs = callArgs ? `${callArgs}, _r` : `_r`;
      lines.push(`    ${fn.tsName}(${paramStr}): string {`);
      lines.push(`      const _r = _cabi_realloc(0, 0, 4, 8);`);
      lines.push(`      ${wasm}(${cabiArgs});`);
      lines.push(`      const _v = new DataView(_mem.buffer);`);
      lines.push(
        `      return new TextDecoder().decode(new Uint8Array(_mem.buffer, _v.getInt32(_r, true), _v.getInt32(_r + 4, true)));`,
      );
      lines.push(`    },`);
    } else if (fn.result === "bool") {
      lines.push(`    ${fn.tsName}(${paramStr}): boolean { return ${wasm}(${callArgs}) !== 0; },`);
    } else if (fn.result === null) {
      lines.push(`    ${fn.tsName}(${paramStr}): void { ${wasm}(${callArgs}); },`);
    } else {
      lines.push(
        `    ${fn.tsName}(${paramStr}): ${
          witTypeToTs(fn.result)
        } { return ${wasm}(${callArgs}) as ${witTypeToTs(fn.result)}; },`,
      );
    }
  }
  lines.push(`  };`);
  lines.push(`}`);
  return lines.join("\n");
}

/**
 * Generate a TypeScript binding file from a WIT source string.
 * The generated file exports `ModuleExports`, optional `ModuleImports`, and `loadModule`.
 */
export function generateBindings(witSrc: string, opts: BindgenOptions = {}): string {
  const runtime = opts.runtime ?? "deno";
  const parsed = parseWit(witSrc);

  const parts: string[] = [
    `// auto-generated by wasmtk bindgen — do not edit manually`,
    `// source: ${parsed.worldName}`,
    `// deno-lint-ignore-file`,
    ``,
    genExportsInterface(parsed.exports),
  ];

  const importsIface = genImportsInterface(parsed.imports);
  if (importsIface) {
    parts.push(``);
    parts.push(importsIface);
  }

  parts.push(``);
  parts.push(genLoadModule(parsed, runtime));

  return parts.join("\n") + "\n";
}

/**
 * CLI entry point: read `witPath`, generate bindings, write to `outPath`.
 */
export async function runBindgen(
  witPath: string,
  opts: { outPath?: string } & BindgenOptions = {},
): Promise<void> {
  const witSrc = await rt.readTextFile(witPath);
  const ts = generateBindings(witSrc, opts);
  const out = opts.outPath ?? witPath.replace(/\.wit$/, ".bindings.ts");
  await rt.writeTextFile(out, ts);
  console.log(`   bindgen: ${out}`);
}
