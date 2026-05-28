/**
 * @module wasmbundle
 * @description Phase 19 — Bundle multiple .wasm files into a single .wasm library.
 *
 * Merges N standalone .wasm modules (WASI executables or pure libraries) into one
 * combined .wasm that exports all their functions under a unified namespace.
 *
 * ## Conflict resolution (Phase 20)
 *
 * When two or more input modules export a function with the same name, wasmbundle
 * detects the conflict and resolves it. Internal WAT symbol names are always mangled
 * for uniqueness ($mathlib_add); only the WASM export string uses the clean name
 * ("add"), so consumers always see original, predictable function names.
 *
 * Resolution options:
 *
 *  - Interactive (default): four-option prompt per conflict:
 *      [1] Prefix with module name  →  mathlib_add, utils_add
 *      [2] Prefix with alias        →  m_add, u_add  (requires --alias)
 *      [3] Exclude both
 *      [4] Stop compile             →  rename in source and recompile
 *  - --on-conflict=prefix : auto-prefix all conflicts with module filename.
 *  - --on-conflict=alias  : auto-prefix all conflicts with --alias values.
 *  - --on-conflict=exclude: auto-exclude all conflicting exports.
 *  - --alias a.wasm=m,b.wasm=n : supply alias prefixes for interactive or alias mode.
 *
 * Non-conflicting exports always keep their bare name in the output.
 *
 * ## Pipeline
 *
 *  1. Load each .wasm with wabt; disassemble to WAT text.
 *  2. Extract export names; identify conflicts across all modules.
 *  3. Resolve conflicts (interactive or via --on-conflict flag).
 *  4. Merge each module's WAT using mergeWasmWat, tracking data offsets.
 *  5. Assemble a master WAT module with all fragments and export declarations.
 *  6. Compile master WAT → binary via wabt.
 *  7. Optimize with Binaryen (-Oz) if available.
 *  8. Write output (default: combined.wasm).
 */

import { basename } from "@std/path";
import { wat2wasm, wasm2wat, formatErrors, Result } from "wabt";
import binaryen from "binaryen";
import { extractExportNames, mergeWasmWat } from "./wasmmerge.ts";
import { rt } from "./rt.ts";

/** Parse WAT text to a WASM binary, throwing on parse errors. */
function watToBinary(source: string, filename: string): Uint8Array {
  const { binary, errors, result } = wat2wasm(source, { filename });
  if (result !== Result.Ok) {
    throw new Error(`wat2wasm failed:\n${formatErrors(errors)}`);
  }
  return binary;
}

/** Disassemble a WASM binary to WAT text, throwing on decode errors. */
function wasmToWatText(
  bytes: Uint8Array,
  opts: { readDebugNames?: boolean; inlineExport?: boolean } = {},
): string {
  const { text, errors, result } = wasm2wat(bytes, opts);
  if (result !== Result.Ok) {
    throw new Error(`wasm2wat failed:\n${formatErrors(errors)}`);
  }
  return text;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const WASI_MODULE = "wasi_snapshot_preview1";

/**
 * Inline type signatures for WASI snapshot preview1 functions.
 * Used when building WASI import declarations in the master WAT.
 */
const WASI_SIGNATURES: Record<string, string> = {
  fd_write:          "(param i32 i32 i32 i32) (result i32)",
  fd_read:           "(param i32 i32 i32 i32) (result i32)",
  fd_seek:           "(param i32 i64 i32 i32) (result i32)",
  fd_close:          "(param i32) (result i32)",
  fd_fdstat_get:     "(param i32 i32) (result i32)",
  proc_exit:         "(param i32)",
  args_get:          "(param i32 i32) (result i32)",
  args_sizes_get:    "(param i32 i32) (result i32)",
  environ_get:       "(param i32 i32) (result i32)",
  environ_sizes_get: "(param i32 i32) (result i32)",
  random_get:        "(param i32 i32) (result i32)",
  clock_time_get:    "(param i32 i64 i32) (result i32)",
  path_open:         "(param i32 i32 i32 i32 i64 i64 i32 i32) (result i32)",
  path_filestat_get: "(param i32 i32 i32 i32 i32) (result i32)",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Derive a clean prefix from a .wasm file path (no extension, alphanumeric/underscore). */
function modulePrefix(filePath: string): string {
  return basename(filePath).replace(/\.wasm$/, "").replace(/[^a-zA-Z0-9]/g, "_");
}

/**
 * Prompt the user interactively for a single conflict resolution.
 * Returns "prefix" | "alias" | "exclude" | "stop".
 * Option [2] (alias) is shown with examples when all conflicting files have an
 * alias in the provided map; otherwise it is shown with a usage hint.
 */
async function promptConflict(
  name: string,
  files: string[],
  aliases: Map<string, string>,
): Promise<"prefix" | "alias" | "exclude" | "stop"> {
  const fileNames = files.map((f) => basename(f));
  const prefixExamples = files.map((f) => `${modulePrefix(f)}_${name}`).join(", ");

  const fileAliases = files.map((f) => aliases.get(basename(f)) ?? aliases.get(f));
  const allHaveAliases = fileAliases.every((a) => a !== undefined);
  const aliasLine = allHaveAliases
    ? `  [2]  Prefix with alias         →  ${fileAliases.map((a) => `${a}_${name}`).join(", ")}\n`
    : `  [2]  Prefix with alias         →  (use --alias ${fileNames.map((f) => `${f}=<name>`).join(",")})\n`;

  const encoder = new TextEncoder();
  await rt.stdout.write(
    encoder.encode(
      `\nConflict: "${name}" exported by: ${fileNames.join(", ")}\n` +
        `  [1]  Prefix with module name  →  ${prefixExamples}\n` +
        aliasLine +
        `  [3]  Exclude both\n` +
        `  [4]  Stop compile             →  rename the function in source and recompile\n` +
        `  Choice (1/2/3/4): `,
    ),
  );
  const buf = new Uint8Array(16);
  const n = await rt.stdin.read(buf);
  const choice = n ? new TextDecoder().decode(buf.subarray(0, n)).trim() : "4";

  if (choice === "1") return "prefix";
  if (choice === "2") return allHaveAliases ? "alias" : "prefix";
  if (choice === "3") return "exclude";
  return "stop";
}

/**
 * Compute the highest byte address (relative to the module's own address space)
 * used by any data segment, i.e. base + length of that segment.
 * Returns 0 if there are no data segments.
 *
 * Used to advance the dataReloc offset after each module is merged.
 */
function getDataMaxEnd(wat: string): number {
  let maxEnd = 0;
  // Match both plain and wabt-indexed formats:
  //   (data (i32.const N) "...")
  //   (data (;N;) (i32.const N) "...")
  const dataRe = /\(data\s+(?:\(;[^;]*;\)\s+)?\(i32\.const\s+(\d+)\)\s+"((?:[^"\\]|\\.)*)"\)/g;
  let m: RegExpExecArray | null;
  while ((m = dataRe.exec(wat)) !== null) {
    const base = parseInt(m[1]);
    // Count bytes: each \XX escape = 1 byte, each plain char = 1 byte
    let len = 0;
    const s = m[2];
    for (let i = 0; i < s.length; i++) {
      if (s[i] === "\\") i++; // skip the next char of the \XX pair
      len++;
    }
    const end = base + len;
    if (end > maxEnd) maxEnd = end;
  }
  return maxEnd;
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

interface ModuleEntry {
  filePath: string;
  prefix: string;
  wat: string;
  exports: string[];
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Bundle multiple .wasm files into a single combined .wasm library.
 *
 * @param inputs      Absolute or relative paths to the input .wasm files.
 * @param outputPath  Path for the output .wasm (default: combined.wasm).
 * @param onConflict  Auto-resolve mode: "prefix" | "alias" | "exclude"; omit to prompt.
 * @param aliases     Map of basename (or full path) → alias prefix for conflict resolution.
 */
export async function runWasmBundle(
  inputs: string[],
  outputPath: string,
  onConflict?: "prefix" | "alias" | "exclude",
  aliases: Map<string, string> = new Map(),
): Promise<void> {
  if (inputs.length === 0) {
    console.error("❌ No input files specified.");
    rt.exit(1);
  }

  // ── Load and disassemble each module ─────────────────────────────────────
  console.log(`\nLoading ${inputs.length} module(s)...`);
  const modules: ModuleEntry[] = [];
  for (const filePath of inputs) {
    const bytes = await rt.readFile(filePath);
    const wat = wasmToWatText(bytes, { readDebugNames: true });
    const exports = extractExportNames(wat);
    // Also include _start for WASI executables — mergeWasmWat preserves it in
    // wasmbundle mode (when exportOverrides is supplied) so the bundle is runnable.
    if (/\(export\s+"_start"\s+\(func\s+\d+\)\)/.test(wat) && !exports.includes("_start")) {
      exports.push("_start");
    }
    modules.push({ filePath, prefix: modulePrefix(filePath), wat, exports });
    const expList = exports.length ? exports.join(", ") : "(none)";
    console.log(`  ✓ ${basename(filePath)}: ${exports.length} export(s): ${expList}`);
  }

  // ── Detect export name conflicts ──────────────────────────────────────────
  const nameToFiles = new Map<string, string[]>();
  for (const mod of modules) {
    for (const exp of mod.exports) {
      const list = nameToFiles.get(exp) ?? [];
      list.push(mod.filePath);
      nameToFiles.set(exp, list);
    }
  }

  const conflictNames = new Map<string, string[]>();
  for (const [name, files] of nameToFiles) {
    if (files.length > 1) conflictNames.set(name, files);
  }

  if (conflictNames.size > 0) {
    console.log(`\n⚠️  ${conflictNames.size} export conflict(s) detected:`);
  }

  // ── Resolve conflicts ────────────────────────────────────────────────────
  // resolutionMap: "filePath::exportName" → output export name string, or null (exclude)
  const resolutionMap = new Map<string, string | null>();
  for (const [name, files] of conflictNames) {
    let resolution: "prefix" | "alias" | "exclude" | "stop";

    if (onConflict === "prefix" || onConflict === "exclude") {
      resolution = onConflict;
      const fileNames = files.map((f) => basename(f)).join(", ");
      console.log(`  "${name}" (${fileNames}): → ${resolution}`);
    } else if (onConflict === "alias") {
      const missing = files.filter((f) => !(aliases.get(basename(f)) ?? aliases.get(f)));
      if (missing.length > 0) {
        console.error(
          `\n❌ --on-conflict=alias requires --alias for every conflicting module.\n` +
            `   Missing alias for: ${missing.map((f) => basename(f)).join(", ")}`,
        );
        rt.exit(1);
      }
      resolution = "alias";
      const fileNames = files.map((f) => basename(f)).join(", ");
      console.log(`  "${name}" (${fileNames}): → alias prefix`);
    } else {
      resolution = await promptConflict(name, files, aliases);
    }

    if (resolution === "stop") {
      console.error(
        `\n❌ Compile stopped. Rename "${name}" in your source and recompile.`,
      );
      rt.exit(1);
    }

    for (const file of files) {
      if (resolution === "exclude") {
        resolutionMap.set(`${file}::${name}`, null);
      } else if (resolution === "prefix") {
        resolutionMap.set(`${file}::${name}`, `${modulePrefix(file)}_${name}`);
      } else {
        // alias
        const alias = aliases.get(basename(file)) ?? aliases.get(file) ?? modulePrefix(file);
        resolutionMap.set(`${file}::${name}`, `${alias}_${name}`);
      }
    }
  }

  // ── Merge all modules sequentially ────────────────────────────────────────
  let dataOffset = 0;
  const funcParts: string[] = [];
  const globalParts: string[] = [];
  const dataParts: string[] = [];
  const exportDeclParts: string[] = [];
  const allWasiNames = new Set<string>();
  const allNotices: string[] = [];

  for (const mod of modules) {
    // Build exportOverrides for this module:
    //   null        → excluded from output
    //   string      → the public export name in (export "..."); may differ from $internal
    // Non-conflicting exports keep their original bare name (Phase 20: clean exports).
    const overrides = new Map<string, string | null>();
    for (const exp of mod.exports) {
      const resolved = resolutionMap.get(`${mod.filePath}::${exp}`);
      overrides.set(exp, resolved !== undefined ? resolved : exp);
    }

    const result = mergeWasmWat(mod.wat, mod.prefix, dataOffset, overrides);

    if (result.funcWat) funcParts.push(result.funcWat);
    if (result.globalWat) globalParts.push(result.globalWat);
    if (result.dataWat) dataParts.push(result.dataWat);
    exportDeclParts.push(...result.exportDecls);
    for (const w of result.wasiImportNames) allWasiNames.add(w);
    for (const notice of result.notices) {
      allNotices.push(`  ⚠️  ${basename(mod.filePath)}: ${notice}`);
    }

    // Advance dataOffset: next module's data goes above this module's data region.
    // getDataMaxEnd returns the highest original address + length in this module's
    // WAT; mergeWasmWat shifts all data by dataOffset, so the occupied range is
    // [dataOffset, dataOffset + maxEnd).  Next module's offset = dataOffset + maxEnd.
    const maxEnd = getDataMaxEnd(mod.wat);
    if (maxEnd > 0) dataOffset += maxEnd;
  }

  if (allNotices.length > 0) {
    console.log("\nNotices:");
    for (const n of allNotices) console.log(n);
  }

  // ── Assemble master WAT ───────────────────────────────────────────────────
  const pagesNeeded = Math.max(1, Math.ceil(dataOffset / 65536));

  // WASI imports — one (import ...) per unique WASI function referenced
  const wasiDecls = [...allWasiNames]
    .filter((name) => WASI_SIGNATURES[name])
    .map(
      (name) =>
        `  (import "${WASI_MODULE}" "${name}" (func $${name} ${WASI_SIGNATURES[name]}))`,
    );

  // WAT spec: imports must precede all non-import definitions (memory, funcs, etc.)
  const watParts: string[] = ["(module"];
  if (wasiDecls.length > 0) watParts.push(wasiDecls.join("\n"));
  watParts.push(`  (memory ${pagesNeeded})`);
  if (funcParts.length > 0) watParts.push("  " + funcParts.join("\n  "));
  if (globalParts.length > 0) watParts.push("  " + globalParts.join("\n  "));
  if (dataParts.length > 0) watParts.push("  " + dataParts.join("\n  "));
  // Always export memory — the wasmtk runner and host bindings require it
  watParts.push(`  (export "memory" (memory 0))`);
  if (exportDeclParts.length > 0) watParts.push("  " + exportDeclParts.join("\n  "));
  watParts.push(")");
  const masterWat = watParts.join("\n");

  // ── Compile master WAT → binary ───────────────────────────────────────────
  console.log("\nCompiling...");
  const rawBinary = watToBinary(masterWat, "combined.wat");

  // ── Optimize with Binaryen ────────────────────────────────────────────────
  let finalBytes: Uint8Array;
  try {
    const bMod = binaryen.readBinary(rawBinary);
    bMod.setFeatures(binaryen.Features.All);
    bMod.optimize();
    finalBytes = bMod.emitBinary();
    bMod.dispose();
    console.log("  ✓ Optimized with Binaryen");
  } catch {
    finalBytes = rawBinary;
  }

  // ── Write output ──────────────────────────────────────────────────────────
  await rt.writeFile(outputPath, finalBytes);
  const exportCount = exportDeclParts.length;
  console.log(
    `\n✅ ${inputs.length} module(s) bundled → ${outputPath}` +
      ` (${exportCount} export(s), ${finalBytes.length} bytes)`,
  );
}
