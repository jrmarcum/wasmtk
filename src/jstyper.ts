/**
 * @module jstyper
 * @description .d.ts-based JS import pre-processor for wasic.
 *
 * Pipeline: .js + .d.ts  →  typed .ts that wasic can compile to WASM.
 * If no .d.ts exists, --dts-only generates a skeleton for hand-editing.
 *
 * CLI:
 *   wasmtk jstyper <file.js> [--dts-only] [--dry-run]
 *                            [--any-policy=skip|warn|default]
 *                            [-n <out>]
 */

export type AnyPolicy = "skip" | "warn" | "default";

export interface JstyperOptions {
  dtsOnly?: boolean; // generate skeleton .d.ts, don't produce .ts
  dryRun?: boolean; // print to stdout, don't write files
  anyPolicy?: AnyPolicy; // how to handle `any`-typed params / returns
  outPath?: string; // override output path
}

export interface JsFuncDef {
  name: string;
  params: string[]; // raw JS param names (no types)
  body: string; // verbatim { … } block from JS source
  isExported: boolean;
}

export interface DtsFuncDef {
  name: string;
  params: Array<{ name: string; type: string }>;
  returnType: string;
}

// ── JS parsing ───────────────────────────────────────────────────────────────

function extractBraceBlock(src: string, startPos: number): string | null {
  if (src[startPos] !== "{") return null;
  let depth = 0;
  let inStr: string | null = null;
  for (let i = startPos; i < src.length; i++) {
    const ch = src[i];
    if (inStr) {
      if (ch === "\\" && src[i + 1]) {
        i++;
        continue;
      }
      if (ch === inStr) inStr = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") {
      inStr = ch;
      continue;
    }
    if (ch === "{") depth++;
    else if (ch === "}") {
      if (--depth === 0) return src.slice(startPos, i + 1);
    }
  }
  return null;
}

/**
 * Extract all function definitions from a JavaScript source file.
 * Handles:
 *  - (export)? function name(params) { body }
 *  - (export)? const name = (params) => { body }
 *  - (export)? const name = (params) => expr
 */
export function parseJsFunctions(src: string): JsFuncDef[] {
  const results: JsFuncDef[] = [];
  const seen = new Set<string>();

  // Regular functions
  const funcRe = /(export\s+)?function\s+(\w+)\s*\(([^)]*)\)\s*(\{)/g;
  let m: RegExpExecArray | null;
  while ((m = funcRe.exec(src)) !== null) {
    const name = m[2];
    if (seen.has(name)) continue;
    seen.add(name);
    const params = m[3].split(",").map((p) => p.trim()).filter((p) => p.length > 0);
    const bracePos = m.index + m[0].length - 1;
    const body = extractBraceBlock(src, bracePos);
    if (!body) continue;
    results.push({ name, params, body, isExported: !!m[1] });
  }

  // Arrow functions: const foo = (a, b) => { ... } or expr
  const arrowRe = /(export\s+)?const\s+(\w+)\s*=\s*\(([^)]*)\)\s*=>\s*/g;
  while ((m = arrowRe.exec(src)) !== null) {
    const name = m[2];
    if (seen.has(name)) continue;
    seen.add(name);
    const params = m[3].split(",").map((p) => p.trim()).filter((p) => p.length > 0);
    const afterArrow = m.index + m[0].length;
    let body: string;
    if (src[afterArrow] === "{") {
      const extracted = extractBraceBlock(src, afterArrow);
      if (!extracted) continue;
      body = extracted;
    } else {
      const end = src.indexOf("\n", afterArrow);
      const expr = (end >= 0 ? src.slice(afterArrow, end) : src.slice(afterArrow))
        .replace(/;$/, "").trim();
      body = `{\n  return ${expr};\n}`;
    }
    results.push({ name, params, body, isExported: !!m[1] });
  }

  return results;
}

// ── .d.ts parsing ────────────────────────────────────────────────────────────

/**
 * Extract typed function declarations from a .d.ts file.
 * Matches:  (export)? (declare)? function name(params): returnType;
 */
export function parseDtsFunctions(dts: string): DtsFuncDef[] {
  const results: DtsFuncDef[] = [];
  const re =
    /(?:export\s+)?(?:declare\s+)?function\s+(\w+)\s*\(([^)]*)\)\s*:\s*([\w\[\]| ]+?)\s*;/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(dts)) !== null) {
    const name = m[1];
    const rawParams = m[2].trim();
    const returnType = m[3].trim();
    const params = rawParams
      ? rawParams.split(",").map((p) => {
        const colon = p.indexOf(":");
        if (colon < 0) return { name: p.trim(), type: "any" };
        return { name: p.slice(0, colon).trim(), type: p.slice(colon + 1).trim() };
      })
      : [];
    results.push({ name, params, returnType });
  }
  return results;
}

// ── Diagnostic helpers ────────────────────────────────────────────────────────

const WASM_TYPES_HINT = "  Valid WASM types: i32, i64, f32, f64, bool, string, void";

/** Reconstruct a corrected declaration line with every `any` replaced by `i32`. */
function correctedDecl(dts: DtsFuncDef): string {
  const params = dts.params
    .map((p) => `${p.name}: ${p.type === "any" ? "i32" : p.type}`)
    .join(", ");
  const ret = dts.returnType === "any" ? "i32" : dts.returnType;
  return `  export declare function ${dts.name}(${params}): ${ret};`;
}

// ── Type mapping ─────────────────────────────────────────────────────────────

function mapDtsType(t: string, anyPolicy: AnyPolicy): string | null {
  switch (t.trim()) {
    case "i32":
    case "i64":
    case "f32":
    case "f64":
    case "bool":
    case "boolean":
    case "string":
    case "void":
    case "never":
      return t.trim();
    case "number":
      return "f64";
    case "int":
      return "i32";
    case "float":
    case "double":
      return "f64";
    case "any":
      return anyPolicy === "skip" ? null : "i32";
    default:
      return t.trim(); // unknown — pass through
  }
}

// ── Skeleton .d.ts generation ────────────────────────────────────────────────

/** Generate a skeleton .d.ts from JS functions with `number` placeholders. */
export function generateSkeletonDts(fns: JsFuncDef[]): string {
  const lines = ["/** @auto-generated by jstyper — edit WASM types then re-run */", ""];
  for (const fn of fns) {
    const params = fn.params.map((p) => `${p}: number`).join(", ");
    const kw = fn.isExported ? "export declare function" : "declare function";
    lines.push(`${kw} ${fn.name}(${params}): number;`);
  }
  return lines.join("\n") + "\n";
}

// ── Typed .ts generation ─────────────────────────────────────────────────────

/**
 * Merge JS function bodies with .d.ts type declarations to produce typed .ts source.
 * @param dtsFile  Optional display name for the .d.ts file used in diagnostic messages.
 */
export function generateTypedTs(
  jsFns: JsFuncDef[],
  dtsFns: DtsFuncDef[],
  anyPolicy: AnyPolicy,
  dtsFile = ".d.ts",
): { source: string; warnings: string[] } {
  const warnings: string[] = [];
  const lines: string[] = [];
  const dtsMap = new Map(dtsFns.map((f) => [f.name, f]));

  for (const jsFn of jsFns) {
    const dts = dtsMap.get(jsFn.name);
    if (!dts) {
      const paramHint = jsFn.params.map((p) => `${p}: <type>`).join(", ");
      warnings.push(
        `'${jsFn.name}' has no declaration in ${dtsFile} — skipping\n` +
          `  Fix: add to ${dtsFile}:\n` +
          `    export declare function ${jsFn.name}(${paramHint}): <returnType>;\n` +
          WASM_TYPES_HINT,
      );
      continue;
    }

    let skip = false;
    const typedParams: string[] = [];

    for (const p of dts.params) {
      const mapped = mapDtsType(p.type, anyPolicy);
      if (mapped === null) {
        skip = true;
        break;
      }
      if (p.type === "any" && anyPolicy === "warn") {
        warnings.push(
          `'${jsFn.name}' param '${p.name}' has type 'any' — using i32 as fallback\n` +
            `  Fix: replace 'any' with a concrete type in ${dtsFile}:\n` +
            `${correctedDecl(dts)}\n` +
            WASM_TYPES_HINT,
        );
      }
      typedParams.push(`${p.name}: ${mapped}`);
    }
    if (skip) {
      const anyParam = dts.params.find((p) => p.type === "any")!;
      warnings.push(
        `skipping '${jsFn.name}' — param '${anyParam.name}' is typed 'any' in ${dtsFile}\n` +
          `  Fix: replace 'any' with a concrete type in ${dtsFile}:\n` +
          `${correctedDecl(dts)}\n` +
          WASM_TYPES_HINT + "\n" +
          `  Or use --any-policy=warn to include it as i32 for now.`,
      );
      continue;
    }

    const retMapped = mapDtsType(dts.returnType, anyPolicy);
    if (retMapped === null) {
      warnings.push(
        `skipping '${jsFn.name}' — return type 'any' in ${dtsFile}\n` +
          `  Fix: replace 'any' with a concrete type in ${dtsFile}:\n` +
          `${correctedDecl(dts)}\n` +
          WASM_TYPES_HINT + "\n" +
          `  Or use --any-policy=warn to include it as i32 for now.`,
      );
      continue;
    }
    if (dts.returnType === "any" && anyPolicy === "warn") {
      warnings.push(
        `'${jsFn.name}' return type 'any' — using i32 as fallback\n` +
          `  Fix: replace 'any' with a concrete type in ${dtsFile}:\n` +
          `${correctedDecl(dts)}\n` +
          WASM_TYPES_HINT,
      );
    }

    const kw = jsFn.isExported ? "export function" : "function";
    lines.push(`${kw} ${jsFn.name}(${typedParams.join(", ")}): ${retMapped} ${jsFn.body}`);
    lines.push("");
  }

  return { source: lines.join("\n").trimEnd() + "\n", warnings };
}

// ── CLI entry point ───────────────────────────────────────────────────────────

export async function runJstyper(
  jsFile: string,
  options: JstyperOptions = {},
): Promise<void> {
  const { dtsOnly = false, dryRun = false, anyPolicy = "warn", outPath } = options;

  let jsText: string;
  try {
    jsText = await Deno.readTextFile(jsFile);
  } catch {
    console.error(`❌ jstyper: cannot read ${jsFile}`);
    Deno.exit(1);
    return;
  }

  const jsFns = parseJsFunctions(jsText);

  // --dts-only: generate skeleton .d.ts for hand-editing
  if (dtsOnly) {
    const skeleton = generateSkeletonDts(jsFns);
    const dest = outPath ?? jsFile.replace(/\.js$/, ".d.ts");
    if (dryRun) {
      console.log(`--- ${dest} ---`);
      console.log(skeleton);
    } else {
      await Deno.writeTextFile(dest, skeleton);
      console.log(`✅ jstyper: wrote ${dest}`);
    }
    return;
  }

  // Normal mode: .js + .d.ts  →  .ts
  const dtsPath = jsFile.replace(/\.js$/, ".d.ts");
  const dtsBase = dtsPath.replace(/.*[\\/]/, ""); // basename for display
  const jsBase = jsFile.replace(/.*[\\/]/, "");

  let dtsText: string;
  try {
    dtsText = await Deno.readTextFile(dtsPath);
  } catch {
    console.error(
      `❌ jstyper: no type declarations found for '${jsBase}'\n\n` +
        `  To generate a skeleton .d.ts, run:\n` +
        `    wasmtk jstyper ${jsBase} --dts-only\n\n` +
        `  Then edit ${dtsBase} — replace 'number' placeholders with WASM types\n` +
        `  (i32, f64, bool, string, void) and re-run:\n` +
        `    wasmtk jstyper ${jsBase}`,
    );
    Deno.exit(1);
    return;
  }

  const dtsFns = parseDtsFunctions(dtsText);
  const { source, warnings } = generateTypedTs(jsFns, dtsFns, anyPolicy, dtsBase);

  for (const w of warnings) console.warn(`⚠  jstyper: ${w}`);

  const dest = outPath ?? jsFile.replace(/\.js$/, ".ts");
  if (dryRun) {
    console.log(`--- ${dest} ---`);
    console.log(source);
  } else {
    await Deno.writeTextFile(dest, source);
    console.log(`✅ jstyper: wrote ${dest}`);
  }
}
