/**
 * @module wasmbundle
 * @description Phase 19 — Bundle multiple .wasm files into a single .wasm library.
 *
 * Merges N standalone .wasm modules (WASI executables or pure libraries) into one
 * combined .wasm that exports all their functions under a unified namespace.
 *
 * ## Conflict resolution
 *
 * When two or more input modules export a function with the same name, wasmbundle
 * detects the conflict and resolves it one of three ways:
 *
 *  - Interactive (default): prompts the user to choose prefix or exclude per conflict.
 *  - --on-conflict=prefix : automatically prefixes both sides (e.g. math1_add, math2_add).
 *  - --on-conflict=exclude: automatically drops both conflicting exports.
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
import wabtInit from "wabt";
import binaryen from "binaryen";
import { extractExportNames, mergeWasmWat } from "./wasmmerge.ts";

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
 * Returns "prefix" or "exclude".
 */
async function promptConflict(name: string, files: string[]): Promise<"prefix" | "exclude"> {
  const fileNames = files.map((f) => basename(f));
  const prefixExamples = files.map((f) => `${modulePrefix(f)}_${name}`).join(", ");
  const encoder = new TextEncoder();
  await Deno.stdout.write(
    encoder.encode(
      `\nConflict: "${name}" exported by: ${fileNames.join(", ")}\n` +
        `  [p]  Prefix each  →  ${prefixExamples}\n` +
        `  [e]  Exclude both\n` +
        `  Choice (p/e): `,
    ),
  );
  const buf = new Uint8Array(16);
  const n = await Deno.stdin.read(buf);
  const choice = n ? new TextDecoder().decode(buf.subarray(0, n)).trim().toLowerCase() : "e";
  return choice.startsWith("p") ? "prefix" : "exclude";
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
  const dataRe = /\(data\s+\(i32\.const\s+(\d+)\)\s+"((?:[^"\\]|\\.)*)"\)/g;
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
 * @param onConflict  "prefix" | "exclude" for non-interactive use; omit to prompt.
 */
export async function runWasmBundle(
  inputs: string[],
  outputPath: string,
  onConflict?: "prefix" | "exclude",
): Promise<void> {
  if (inputs.length === 0) {
    console.error("❌ No input files specified.");
    Deno.exit(1);
  }

  // ── Load wabt ─────────────────────────────────────────────────────────────
  const wabt = await wabtInit();

  // ── Load and disassemble each module ─────────────────────────────────────
  console.log(`\nLoading ${inputs.length} module(s)...`);
  const modules: ModuleEntry[] = [];
  for (const filePath of inputs) {
    const bytes = await Deno.readFile(filePath);
    const wabtMod = wabt.readWasm(bytes, { readDebugNames: true });
    const wat = wabtMod.toText({ foldExprs: false });
    wabtMod.destroy();
    const exports = extractExportNames(wat);
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
  // resolutionKey: "filePath::exportName" → "prefix" | "exclude"
  const resolutionKey = new Map<string, "prefix" | "exclude">();
  for (const [name, files] of conflictNames) {
    let resolution: "prefix" | "exclude";
    if (onConflict) {
      resolution = onConflict;
      const fileNames = files.map((f) => basename(f)).join(", ");
      console.log(`  "${name}" (${fileNames}): → ${resolution}`);
    } else {
      resolution = await promptConflict(name, files);
    }
    for (const file of files) {
      resolutionKey.set(`${file}::${name}`, resolution);
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
    //   null   → excluded
    //   string → the public name to use in (export "...")
    const overrides = new Map<string, string | null>();
    for (const exp of mod.exports) {
      const key = `${mod.filePath}::${exp}`;
      const resolution = resolutionKey.get(key);
      if (resolution === "exclude") {
        overrides.set(exp, null);
      } else if (resolution === "prefix") {
        overrides.set(exp, `${mod.prefix}_${exp}`);
      } else {
        overrides.set(exp, exp); // non-conflicting: keep bare name
      }
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

  const watParts: string[] = ["(module"];
  watParts.push(`  (memory ${pagesNeeded})`);
  if (wasiDecls.length > 0) watParts.push(wasiDecls.join("\n"));
  if (funcParts.length > 0) watParts.push("  " + funcParts.join("\n  "));
  if (globalParts.length > 0) watParts.push("  " + globalParts.join("\n  "));
  if (dataParts.length > 0) watParts.push("  " + dataParts.join("\n  "));
  if (exportDeclParts.length > 0) watParts.push("  " + exportDeclParts.join("\n  "));
  watParts.push(")");
  const masterWat = watParts.join("\n");

  // ── Compile master WAT → binary ───────────────────────────────────────────
  console.log("\nCompiling...");
  const masterMod = wabt.parseWat("combined.wat", masterWat, { exceptions: true });
  const { buffer } = masterMod.toBinary({});
  masterMod.destroy();

  // ── Optimize with Binaryen ────────────────────────────────────────────────
  let finalBytes: Uint8Array;
  try {
    const bMod = binaryen.readBinary(new Uint8Array(buffer));
    bMod.setFeatures(binaryen.Features.All);
    bMod.optimize();
    finalBytes = bMod.emitBinary();
    bMod.dispose();
    console.log("  ✓ Optimized with Binaryen");
  } catch {
    finalBytes = new Uint8Array(buffer);
  }

  // ── Write output ──────────────────────────────────────────────────────────
  await Deno.writeFile(outputPath, finalBytes);
  const exportCount = exportDeclParts.length;
  console.log(
    `\n✅ ${inputs.length} module(s) bundled → ${outputPath}` +
      ` (${exportCount} export(s), ${finalBytes.length} bytes)`,
  );
}
