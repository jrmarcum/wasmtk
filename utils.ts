/**
 * @module utils
 * @description Core toolchain logic including the WASI shim environment,
 * binary inspection via Binaryen, and multi-runtime execution logic.
 */

import { basename, join, dirname } from "@std/path";
import wasm2js_compiler from "wasm2js";
import binaryen from "binaryen";
import { main as asc } from "asc";
import wabt from "wabt";
import {
  detectJavyProvider,
  ensureJavy,
  isJavyAvailable,
  getJavyInstallPath,
} from "./javyc.ts";

export { compileJavy } from "./javyc.ts";
export { compileWasi } from "./wasic.ts";

// Minimal type stubs for the wabt npm package API
interface WasmFeatures { enable_all?: boolean; [key: string]: boolean | undefined; }
interface WabtWasmModule { toBinary(opts: object): { buffer: ArrayBuffer }; toText(opts: object): string; destroy(): void; applyNames(): void; }
interface WabtModule {
  parseWat(filename: string, source: string, features?: WasmFeatures): WabtWasmModule;
  readWasm(buffer: Uint8Array, opts: { readDebugNames: boolean }): WabtWasmModule;
}

/** The current version of the wasmtk toolkit. */
export const VERSION = "1.1.8";

let wasiInstance: WebAssembly.Instance | undefined;

type WasmCallable = (...args: (number | bigint)[]) => number | bigint | void;
type WasiImports = Record<string, Record<string, WasmCallable | WebAssembly.Memory>>;

interface BinaryenModuleExt extends binaryen.Module {
  getNumImports(): number;
  getImportByIndex(index: number): number;
}

interface BinaryenLibExt {
  getImportInfo(importRef: number): { module: string; name: string; kind: number };
  i32: number; i64: number; f32: number; f64: number;
  v128: number; funcref: number; externref: number; none: number;
}

function getTypeName(typeId: number): string {
  const b = binaryen as unknown as BinaryenLibExt;
  if (typeId === b.i32) return "i32";
  if (typeId === b.i64) return "i64";
  if (typeId === b.f32) return "f32";
  if (typeId === b.f64) return "f64";
  if (typeId === b.none) return "void";
  return "unknown";
}

/**
 * Comprehensive WASI Shims for the wasmtk runtime.
 * Includes extended support for Zig-compiled binaries (fd_pwrite, fd_filestat_get, etc).
 */
const wasiImports: WasiImports = {
  wasi_snapshot_preview1: {
    proc_exit: (code: number | bigint): void => {
      if (Number(code) === 0) Deno.exit(0);
      throw new WebAssembly.RuntimeError(`exit:${code}`);
    },
    fd_write: (fd: number | bigint, iovs: number | bigint, iovsLen: number | bigint, nwrittenPtr: number | bigint): number => {
      const memory = wasiInstance?.exports.memory as WebAssembly.Memory;
      const view = new DataView(memory.buffer);
      let nwritten = 0;
      for (let i = 0; i < Number(iovsLen); i++) {
        const ptr = view.getUint32(Number(iovs) + i * 8, true);
        const len = view.getUint32(Number(iovs) + i * 8 + 4, true);
        const buf = new Uint8Array(memory.buffer, ptr, len);
        if (Number(fd) === 1) Deno.stdout.writeSync(buf); else Deno.stderr.writeSync(buf);
        nwritten += len;
      }
      view.setUint32(Number(nwrittenPtr), nwritten, true);
      return 0;
    },
    fd_pwrite: (): number => 0,
    fd_read: (fd: number | bigint, iovs: number | bigint, iovsLen: number | bigint, nreadPtr: number | bigint): number => {
      if (Number(fd) !== 0) return 28;
      const memory = wasiInstance?.exports.memory as WebAssembly.Memory;
      const view = new DataView(memory.buffer);
      let totalRead = 0;
      for (let i = 0; i < Number(iovsLen); i++) {
        const ptr = view.getUint32(Number(iovs) + i * 8, true);
        const len = view.getUint32(Number(iovs) + i * 8 + 4, true);
        const buf = new Uint8Array(len);
        const n = Deno.stdin.readSync(buf);
        if (n === null || n === 0) break;
        new Uint8Array(memory.buffer, ptr, n).set(buf.subarray(0, n));
        totalRead += n;
      }
      view.setUint32(Number(nreadPtr), totalRead, true);
      return 0;
    },
    clock_time_get: (_id: number | bigint, _prec: bigint | number, resPtr: number | bigint): number => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setBigUint64(Number(resPtr), BigInt(Date.now()) * 1000000n, true);
      return 0;
    },
    random_get: (bufPtr: number | bigint, bufLen: number | bigint): number => {
      const memory = wasiInstance?.exports.memory as WebAssembly.Memory;
      const buf = new Uint8Array(memory.buffer, Number(bufPtr), Number(bufLen));
      crypto.getRandomValues(buf);
      return 0;
    },
    environ_get: (): number => 0,
    environ_sizes_get: (countPtr: number | bigint, bufSizePtr: number | bigint): number => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint32(Number(countPtr), 0, true);
      view.setUint32(Number(bufSizePtr), 0, true);
      return 0;
    },
    args_get: (): number => 0,
    args_sizes_get: (countPtr: number | bigint, bufSizePtr: number | bigint): number => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint32(Number(countPtr), 0, true);
      view.setUint32(Number(bufSizePtr), 0, true);
      return 0;
    },
    fd_fdstat_get: (fd: number | bigint, ptr: number | bigint): number => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint8(Number(ptr), Number(fd) <= 2 ? 2 : 3);
      view.setUint16(Number(ptr) + 2, 0, true);
      view.setBigUint64(Number(ptr) + 8, 0n, true);
      view.setBigUint64(Number(ptr) + 16, 0n, true);
      return 0;
    },
    fd_close: (): number => 0,
    fd_seek: (): number => 0,
    fd_prestat_get: (): number => 8,
    fd_prestat_dir_name: (): number => 8,
    fd_advise: (): number => 0,
    fd_allocate: (): number => 0,
    fd_datasync: (): number => 0,
    fd_sync: (): number => 0,
    fd_stat_put: (): number => 0,
    fd_filestat_get: (): number => 0,
    poll_oneoff: (): number => 28,
    sched_yield: (): number => 0,
  }
};

async function getWasmBytes(path: string): Promise<Uint8Array> {
  if (path.endsWith(".wat")) {
    try {
      const watSource = await Deno.readTextFile(path);
      const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
      const parsed = wabtModule.parseWat(path, watSource, { enable_all: true } as WasmFeatures);
      const { buffer } = parsed.toBinary({});
      parsed.destroy();
      return new Uint8Array(buffer);
    } catch (err) {
      throw new Error(`[WAT Compilation Error] ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  return await Deno.readFile(path);
}

/**
 * Compiles an AssemblyScript file to an optimized WASM library (modc).
 * @param path - Path to the source .ts file.
 */
/**
 * Safety-net post-processor: if env/abort still appears in the module after asc compilation,
 * patch it out via WAT round-trip so the binary is self-contained for wasmtime/wasmer.
 */
/**
 * Removes the env/abort import from an AssemblyScript-compiled WASM binary by directly
 * parsing and rewriting the binary-level import section. This avoids fragile WAT round-trips
 * and works reliably regardless of how Binaryen formats its text output.
 *
 * WASM binary structure of the import section (section id = 2):
 *   [section_id=2][section_size][num_imports][...import entries...]
 * Each import entry: [mod_len][mod_bytes][name_len][name_bytes][import_kind][...]
 */
/**
 * Post-processes a compiled WASM library binary to:
 * 1. Remove any env/abort import (leftover from AssemblyScript)
 * 2. Remove the start section (section id=8) - illegal in library modules
 * Both fixes make the binary compatible with strict runtimes like wasmtime/wasmer.
 */
async function removeEnvAbortImport(wasmPath: string): Promise<void> {
  const bytes = await Deno.readFile(wasmPath);
  const buf = new Uint8Array(bytes);

  const readULEB128 = (p: number): [number, number] => {
    let val = 0, shift = 0;
    while (true) {
      const b = buf[p++];
      val |= (b & 0x7f) << shift;
      shift += 7;
      if ((b & 0x80) === 0) return [val, p];
    }
  };

  const writeULEB128 = (n: number): Uint8Array => {
    const out: number[] = [];
    do {
      let b = n & 0x7f; n >>>= 7;
      if (n !== 0) b |= 0x80;
      out.push(b);
    } while (n !== 0);
    return new Uint8Array(out);
  };

  // Collect sections that need rewriting or dropping
  // We'll rebuild the entire binary, section by section
  const outputChunks: Uint8Array[] = [buf.slice(0, 8)]; // WASM header
  let pos = 8;
  let patched = false;

  while (pos < buf.length) {
    const sectionIdPos = pos;
    const sectionId = buf[pos++];
    const [sectionSize, bodyPos] = readULEB128(pos);
    const sectionEndPos = bodyPos + sectionSize;
    pos = sectionEndPos;

    // --- Section 8: start section --- drop it entirely (invalid for libraries)
    if (sectionId === 8) {
      patched = true;
      continue; // skip - do not emit this section
    }

    // --- Section 2: import section --- filter out env/abort if present
    if (sectionId === 2) {
      let p = bodyPos;
      const [numImports, afterCount] = readULEB128(p); p = afterCount;

      const entries: Array<{ bytes: Uint8Array; drop: boolean }> = [];
      for (let i = 0; i < numImports; i++) {
        const entryStart = p;
        const [modLen, p2] = readULEB128(p); p = p2;
        const modName = new TextDecoder().decode(buf.slice(p, p + modLen)); p += modLen;
        const [nameLen, p3] = readULEB128(p); p = p3;
        const fieldName = new TextDecoder().decode(buf.slice(p, p + nameLen)); p += nameLen;
        const kind = buf[p++];
        if (kind === 0) { const [, np] = readULEB128(p); p = np; }
        else if (kind === 1) { p++; const f = buf[p++]; const [, np] = readULEB128(p); p = np; if (f & 1) { const [, np2] = readULEB128(p); p = np2; } }
        else if (kind === 2) { const f = buf[p++]; const [, np] = readULEB128(p); p = np; if (f & 1) { const [, np2] = readULEB128(p); p = np2; } }
        else if (kind === 3) { p += 2; }
        const drop = modName === "env" && fieldName === "abort";
        if (drop) patched = true;
        entries.push({ bytes: buf.slice(entryStart, p), drop });
      }

      const kept = entries.filter(e => !e.drop);
      if (kept.length === entries.length) {
        // Nothing dropped - emit section unchanged
        outputChunks.push(buf.slice(sectionIdPos, sectionEndPos));
        continue;
      }

      // Rebuild import section
      const newCount = writeULEB128(kept.length);
      const bodyLen = newCount.length + kept.reduce((a, e) => a + e.bytes.length, 0);
      const newSectionSize = writeULEB128(bodyLen);
      const section = new Uint8Array(1 + newSectionSize.length + bodyLen);
      let wp = 0;
      section[wp++] = 2;
      section.set(newSectionSize, wp); wp += newSectionSize.length;
      section.set(newCount, wp); wp += newCount.length;
      for (const e of kept) { section.set(e.bytes, wp); wp += e.bytes.length; }
      outputChunks.push(section);
      continue;
    }

    // All other sections: emit unchanged
    outputChunks.push(buf.slice(sectionIdPos, sectionEndPos));
  }

  if (!patched) return;

  // Concatenate all chunks
  const totalLen = outputChunks.reduce((a, c) => a + c.length, 0);
  const result = new Uint8Array(totalLen);
  let wp = 0;
  for (const chunk of outputChunks) { result.set(chunk, wp); wp += chunk.length; }

  await Deno.writeFile(wasmPath, result);
  console.log("  ✅ Patched: removed start section and env/abort import for standalone runtime compatibility");
}

export async function compileModule(path: string): Promise<void> {
  if (path.endsWith(".wasm") || path.endsWith(".wat")) {
    console.error(`❌ Input Error: modc expects an AssemblyScript (.ts) file.`);
    return;
  }
  const name = basename(path).replace(/\.[^/.]+$/, "");
  const dir = dirname(path);
  const tempTsPath = join(dir, `${name}.build.tmp.ts`);
  console.log(`✅ Building Library: ${name}.wasm`);
  try {
    const fullSource = await Deno.readTextFile(path);

    // Extract only `export function` declarations for asc.
    // Strips all runner code: IIFEs, top-level calls, console.log,
    // import.meta.main blocks, and plain function main() calls.
    // This handles all common TS patterns that asc cannot parse.
    const exportFunctions: string[] = [];
    const exportFnRegex = /^export\s+function\s+[\s\S]*?^}/gm;
    let match: RegExpExecArray | null;
    while ((match = exportFnRegex.exec(fullSource)) !== null) {
      exportFunctions.push(match[0]);
    }

    if (exportFunctions.length === 0) {
      console.error(`\u274c No exported functions found in ${path}. Use "export function" syntax.`);
      return;
    }

    // Remap number types to f64 for asc compatibility
    const source = exportFunctions
      .join("\n\n")
      .replace(/:\s*number/g, ": f64");

    console.log(`  Extracted ${exportFunctions.length} export function(s)`);

    // Tell asc to use its built-in no-op abort stub so no env/abort import is injected
    await Deno.writeTextFile(tempTsPath, source);
    const { error, stderr } = await asc([
      tempTsPath,
      "--target", "release",
      "--outFile", `./${name}.wasm`,
      "--optimize",
      "--noAssert",
      "--runtime", "stub",
      "--converge",
    ]);
    if (!error) {
      // Skip Binaryen post-processing - asc --optimize already produces
      // correct output; Binaryen opt level 3 miscompiles some asc patterns.
      // Just strip the start section and any env/abort import from the binary.
      await removeEnvAbortImport(`./${name}.wasm`);
      console.log(`✅ Library Ready: ${name}.wasm`);
    } else {
      console.error(`❌ Build failed: ${error.message}`);
      if (stderr) console.error(stderr.toString());
    }
  } catch (err) { console.error(`❌ modc Exception: ${err}`); } finally { try { await Deno.remove(tempTsPath); } catch { /* ignore */ } }
}

/**
 * Polyfilled runner for multiple file types (.wasm, .wat, .js, .ts).
 * @param path - File path to execute.
 * @param args - Positional arguments for library function calls.
 */
export async function runWasi(path: string, args: string[]): Promise<void> {
  if (path.endsWith(".ts") || path.endsWith(".js")) {
    const command = new Deno.Command(Deno.execPath(), {
      args: ["run", "-A", path, ...args],
    });
    const process = command.spawn();
    await process.status;
    return;
  }

  // Intercept Javy dynamic WAT files before attempting instantiation
  if (path.endsWith(".wat")) {
    try {
      const watSource = await Deno.readTextFile(path);
      if (watSource.includes("javy_quickjs_provider") || watSource.includes("javy-default-plugin")) {
        const inferredTs = path.replace(/\.wat$/, ".ts");
        console.error(`❌ Cannot run Javy WAT: "${path}"`);
        console.error(`   This WAT is the app layer only — the QuickJS engine is not embedded.`);
        console.error(`   To run, use the original WASM: wasmtk run ${path.replace(/\.wat$/, ".wasm")}`);
        console.error(`   To rebuild after edits: wasmtk wasic ${inferredTs}`);
        Deno.exit(1);
      }
    } catch { /* not readable as text - fall through to normal handling */ }
  }

  try {
    const wasmBytes = await getWasmBytes(path);
    const extendedImports = {
      ...wasiImports,
      env: {
        "console.log": (ptr: number) => {
          if (!wasiInstance) return;
          const memory = wasiInstance.exports.memory as WebAssembly.Memory;
          const view = new Uint32Array(memory.buffer, ptr - 4, 1);
          const len = view[0];
          const strBuf = new Uint16Array(memory.buffer, ptr, len / 2);
          console.log(String.fromCharCode(...strBuf));
        },
        abort: (): void => { throw new WebAssembly.RuntimeError("abort"); }
      }
    };
    const result = await WebAssembly.instantiate(wasmBytes as BufferSource, extendedImports as unknown as WebAssembly.Imports);
    wasiInstance = result.instance;
    
    if (args.length > 0 && await checkIsLibrary(path)) {
      const [name, ...params] = args;
      const fn = wasiInstance.exports[name];
      if (typeof fn === "function") {
        const parsedArgs = params.map(p => {
            const n = Number(p);
            return isNaN(n) ? 0 : n;
        }) as (number | bigint)[];
        const res = (fn as WasmCallable)(...parsedArgs);
        if (res !== undefined) console.log(`${res}`);
        return;
      }
    }

    const init = wasiInstance.exports._initialize || wasiInstance.exports._start;
    if (typeof init === "function") {
      try {
        (init as WasmCallable)();
      } catch (err) {
        if (err instanceof WebAssembly.RuntimeError && err.message.includes("exit:0")) return;
        throw err;
      }
    }
  } catch (err) { console.error(`❌ Run error: ${err}`); Deno.exit(1); }
}

/**
 * Directly calls a named exported function from a WASM module regardless of
 * whether the module also exports _start. This is the backend for the `mod`
 * command and deliberately skips the checkIsLibrary gate used by runWasi.
 *
 * @param path   - Path to the .wasm or .wat file.
 * @param fnName - Name of the exported function to call.
 * @param params - String-encoded numeric arguments to pass.
 */
export async function callExport(path: string, fnName: string, params: string[]): Promise<void> {
  try {
    const wasmBytes = await getWasmBytes(path);
    const extendedImports = {
      ...wasiImports,
      env: { abort: (): void => { throw new WebAssembly.RuntimeError("abort"); } },
    };
    const result = await WebAssembly.instantiate(
      wasmBytes as BufferSource,
      extendedImports as unknown as WebAssembly.Imports
    );
    wasiInstance = result.instance;

    const fn = wasiInstance.exports[fnName];
    if (typeof fn !== "function") {
      console.error(`❌ mod: no exported function named "${fnName}" in ${path}`);
      console.error(`   Use "wasmtk info ${path}" to list available functions.`);
      Deno.exit(1);
    }

    const parsedArgs = params.map(p => {
      const n = Number(p);
      return isNaN(n) ? 0 : n;
    }) as (number | bigint)[];

    const res = (fn as WasmCallable)(...parsedArgs);
    if (res !== undefined) console.log(`${res}`);
  } catch (err) {
    console.error(`❌ mod error: ${err}`);
    Deno.exit(1);
  }
}

/**
 * Displays metadata and callable exported functions for a WASM module.
 * @param path - Path to the module.
 */
export async function showInfo(path: string): Promise<void> {
  try {
    const bytes = await getWasmBytes(path);
    const module = binaryen.readBinary(bytes);
    console.log(`\n✅ Module Info: ${basename(path)}`);
    console.log("─".repeat(40));
    console.log(`📁 User Callable Functions:`);
    const numExports = module.getNumExports();
    let found = 0;
    for (let i = 0; i < numExports; i++) {
      const exp = binaryen.getExportInfo(module.getExportByIndex(i));
      if (exp.kind !== 0) continue; 
      const name = exp.name;
      const isInternal = name === "_start" || name === "_initialize" || name === "abort" || name.startsWith("__") || name.startsWith("cabi_") || name.includes("config-schema");
      if (!isInternal) {
        const func = module.getFunction(exp.value);
        const info = binaryen.getFunctionInfo(func);
        const params = binaryen.expandType(info.params).map(getTypeName).join(", ") || "";
        const results = binaryen.expandType(info.results).map(getTypeName).join(", ") || "void";
        console.log(`  - ${name}(${params}) -> ${results}`);
        found++;
      }
    }
    if (found === 0) console.log("  (None found)");
    let isWasi = false;
    const modExt = module as BinaryenModuleExt;
    const binExt = binaryen as unknown as BinaryenLibExt;
    if (typeof modExt.getNumImports === "function") {
      const numImports = modExt.getNumImports();
      for (let i = 0; i < numImports; i++) {
        const impRef = modExt.getImportByIndex(i);
        const imp = binExt.getImportInfo(impRef);
        if (imp.module === "wasi_snapshot_preview1") {
          isWasi = true;
          break;
        }
      }
    }
    // Detect Javy binary for informational note (Wizer fuses WASI imports so isWasi may be false)
    const isJavy = path.endsWith(".wasm") && detectJavyProvider(bytes) !== null;
    console.log(`\n🛠️  WASI Support: ${isWasi || isJavy ? "Yes" : "No"}${isJavy ? " (Javy/QuickJS — WASI internalized by Wizer)" : ""}`);
    console.log("─".repeat(40));
    module.dispose();
  } catch (err) { console.error("❌ Info error: " + err); }
}

/**
 * Inspects a module to determine if it is a library (no _start function).
 * @param path - Path to the module.
 */
export async function checkIsLibrary(path: string): Promise<boolean> {
  try {
    const bytes = await getWasmBytes(path);
    const mod = await WebAssembly.compile(bytes as BufferSource);
    return !WebAssembly.Module.exports(mod).some(e => e.name === "_start");
  } catch { return false; }
}

/**
 * Converts a WASM/WAT module into a standalone JS-based script.
 * @param path - Path to the module.
 */
export async function wasm2js(path: string): Promise<void> {
  const outPath = path.replace(/\.(wasm|wat)$/, ".js");
  try {
    const wasmBuffer = await getWasmBytes(path);
    const result = wasm2js_compiler(wasmBuffer as BufferSource);
    await Deno.writeTextFile(outPath, typeof result === "string" ? result : new TextDecoder().decode(result));
    console.log(`✅ Success: ${outPath}`);
  } catch (err) { console.error(`❌ Conversion failed: ${err}`); }
}


/**
 * Finds the original JS/TS source file alongside a WASM file.
 * Checks for <name>.js and <name>.ts in the same directory.
 * Returns the path if found, or null.
 */
async function findSourceAlongside(wasmPath: string): Promise<string | null> {
  const base = wasmPath.replace(/\.wasm$/, "");
  for (const ext of [".js", ".ts"]) {
    const candidate = base + ext;
    try {
      await Deno.stat(candidate);
      return candidate;
    } catch { /* not found */ }
  }
  return null;
}

/**
 * Toggles format between .wasm and .wat.
 * Javy WASM files receive special handling:
 *   - WASM → WAT: recompiles source with `javy build -d` to extract the clean app-layer WAT,
 *     with the QuickJS engine excluded. Emits a one-way warning.
 *   - WAT → WASM: detects javy_quickjs_provider imports in the WAT text and blocks conversion with a clear notice.
 * @param p - Path to the input file.
 */
export async function convertFile(p: string): Promise<void> {
  const isWat = p.endsWith(".wat");
  const out = isWat ? p.replace(".wat", ".wasm") : p.replace(".wasm", ".wat");

  try {
    if (isWat) {
      // --- WAT → WASM ---
      const watSource = await Deno.readTextFile(p);

      // Detect Javy dynamic module by checking for javy_quickjs_provider imports in the WAT text
      if (watSource.includes("javy_quickjs_provider") || watSource.includes("javy-default-plugin")) {
        const inferredTs = p.replace(/\.wat$/, ".ts");
        console.warn(`⚠️  Javy WAT detected: "${p}"`);
        console.warn(`   This WAT represents the app layer of a Javy dynamic module.`);
        console.warn(`   The QuickJS engine is not embedded — this WAT cannot be merged`);
        console.warn(`   back into a standalone WASM compatible with wasmtk/wasmtime/wasmer/wazero.`);
        console.warn(`   To produce a runnable binary, recompile the original source:`);
        console.warn(`     wasmtk wasic ${inferredTs}`);
        return;
      }

      // Normal WAT → WASM round-trip
      const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
      const parsed = wabtModule.parseWat(p, watSource, { enable_all: true } as WasmFeatures);
      const { buffer } = parsed.toBinary({});
      parsed.destroy();
      await Deno.writeFile(out, new Uint8Array(buffer));
      console.log(`✅ Converted to ${out}`);

    } else {
      // --- WASM → WAT ---
      const wasmBytes = await Deno.readFile(p);
      const isJavyBinary = detectJavyProvider(wasmBytes) !== null;

      if (isJavyBinary) {
        // Javy static binary — attempt clean app-layer WAT via dynamic recompile
        const sourcePath = await findSourceAlongside(p);

        if (!sourcePath) {
          // No source available — warn and fall through to standard full-binary WAT conversion
          console.warn(`⚠️  Javy WASM detected: "${p}"`);
          console.warn(`   This binary embeds the QuickJS runtime and was built with Javy.`);
          console.warn(`   The original source file was not found alongside the WASM.`);
          console.warn(`   The WAT file produced is large due to QuickJS inclusion.`);
          const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
          const mod = wabtModule.readWasm(wasmBytes, { readDebugNames: true });
          const wat = mod.toText({ foldExprs: false, inlineExport: false });
          mod.destroy();
          await Deno.writeTextFile(out, wat);
          console.log(`✅ Converted to ${out}`);
          return;
        }

        // Source found — recompile with javy -C dynamic to get the clean dynamic app module, then WAT-ify it
        // Javy v6+ requires: (1) emit-plugin to get the provider wasm, (2) build -C dynamic -C plugin=<plugin>
        console.log(`🔍 Javy WASM detected. Extracting app-layer WAT from: ${sourcePath}`);
        await ensureJavy();
        const javyCmd = (await isJavyAvailable()) ? "javy" : getJavyInstallPath();
        const tempWasm = p.replace(".wasm", ".dynamic.tmp.wasm");
        const tempPlugin = p.replace(".wasm", ".plugin.tmp.wasm");

        // Step 1: emit the default plugin
        const emitPlugin = new Deno.Command(javyCmd, {
          args: ["emit-plugin", "-o", tempPlugin],
        });
        const emitResult = await emitPlugin.output();
        if (!emitResult.success) {
          const errText = new TextDecoder().decode(emitResult.stderr);
          console.error(`❌ Javy emit-plugin failed: ${errText}`);
          return;
        }

        // Step 2: build the dynamic app module against the emitted plugin
        const javy = new Deno.Command(javyCmd, {
          args: ["build", "-C", "dynamic", "-C", `plugin=${tempPlugin}`, sourcePath, "-o", tempWasm],
        });
        const javyResult = await javy.output();
        try { await Deno.remove(tempPlugin); } catch { /* ignore */ }

        if (!javyResult.success) {
          const errText = new TextDecoder().decode(javyResult.stderr);
          console.error(`❌ Javy dynamic recompile failed: ${errText}`);
          return;
        }

        try {
          const dynBytes = await Deno.readFile(tempWasm);
          const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
          const mod = wabtModule.readWasm(dynBytes, { readDebugNames: true });
          const wat = mod.toText({ foldExprs: false, inlineExport: false });
          mod.destroy();
          await Deno.writeTextFile(out, wat);
        } finally {
          try { await Deno.remove(tempWasm); } catch { /* ignore */ }
        }

        console.log(`✅ Converted to ${out}`);
        console.warn(`⚠️  One-way conversion: this WAT represents the app layer only.`);
        console.warn(`   The QuickJS engine is excluded.`);
        console.warn(`   This WAT cannot be converted back into a standalone WASM.`);
        console.warn(`   To modify and rebuild, edit the source and run: wasmtk wasic ${sourcePath}`);

      } else {
        // Normal WASM → WAT round-trip
        const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
        const mod = wabtModule.readWasm(wasmBytes, { readDebugNames: true });
        const wat = mod.toText({ foldExprs: false, inlineExport: false });
        mod.destroy();
        await Deno.writeTextFile(out, wat);
        console.log(`✅ Converted to ${out}`);
      }
    }
  } catch (err) { console.error(`❌ Conversion failed: ${err}`); }
}


/**
 * Bundles a TypeScript project into a single JavaScript file.
 * @param p - Path to the source file.
 * @param outPath - The output destination.
 */
export async function bundleTs(p: string, outPath?: string): Promise<void> {
  const out = outPath || p.replace(".ts", ".js");
  const b = new Deno.Command(Deno.execPath(), { args: ["bundle", "--quiet", p], stdout: "piped" });
  const output = await b.output();
  await Deno.writeTextFile(out, new TextDecoder().decode(output.stdout));
  console.log(`✅ Bundled: ${out}`);
}