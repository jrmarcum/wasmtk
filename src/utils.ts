/**
 * @module utils
 * @description Core toolchain logic including the WASI shim environment,
 * binary inspection via Binaryen, and multi-runtime execution logic.
 */

import { basename, dirname } from "@std/path";
import { rt } from "./rt.ts";
import wasm2js_compiler from "wasm2js";
import binaryen from "binaryen";
import wabt from "wabt";
import {
  detectJavyProvider,
  ensureJavy,
  isJavyAvailable,
  getJavyInstallPath,
} from "./javyc.ts";

export { compileJavy } from "./javyc.ts";
export { compileWasi } from "./wasic.ts";
export { compileModule } from "./modc.ts";

// Minimal type stubs for the wabt npm package API
interface WasmFeatures { enable_all?: boolean; [key: string]: boolean | undefined; }
interface WabtWasmModule { toBinary(opts: object): { buffer: ArrayBuffer }; toText(opts: object): string; destroy(): void; applyNames(): void; }
interface WabtModule {
  parseWat(filename: string, source: string, features?: WasmFeatures): WabtWasmModule;
  readWasm(buffer: Uint8Array, opts: { readDebugNames: boolean }): WabtWasmModule;
}

/** The current version of the wasmtk toolkit. */
export const VERSION = "1.4.6";

let wasiInstance: WebAssembly.Instance | undefined;

type WasmCallable = (...args: (number | bigint)[]) => number | bigint | void;
type WasiImports = Record<string, Record<string, WasmCallable | WebAssembly.Memory>>;


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
      if (Number(code) === 0) rt.exit(0);
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
        if (Number(fd) === 1) rt.stdout.writeSync(buf); else rt.stderr.writeSync(buf);
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
        const n = rt.stdin.readSync(buf);
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
    fd_fdstat_set_flags: (_fd: number | bigint, _flags: number | bigint): number => 0,
  }
};

async function getWasmBytes(path: string): Promise<Uint8Array> {
  if (path.endsWith(".wat")) {
    try {
      const watSource = await rt.readTextFile(path);
      const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
      const parsed = wabtModule.parseWat(path, watSource, { enable_all: true } as WasmFeatures);
      const { buffer } = parsed.toBinary({});
      parsed.destroy();
      return new Uint8Array(buffer);
    } catch (err) {
      throw new Error(`[WAT Compilation Error] ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  return await rt.readFile(path);
}

/**
 * Polyfilled runner for multiple file types (.wasm, .wat, .js, .ts).
 * @param path - File path to execute.
 * @param args - Positional arguments for library function calls.
 */
export async function runWasi(path: string, args: string[]): Promise<void> {
  if (path.endsWith(".ts") || path.endsWith(".js")) {
    const command = new rt.Command(rt.execPath(), {
      args: ["run", "-A", path, ...args],
    });
    const process = command.spawn();
    await process.status;
    return;
  }

  // Intercept Javy dynamic WAT files before attempting instantiation
  if (path.endsWith(".wat")) {
    try {
      const watSource = await rt.readTextFile(path);
      if (watSource.includes("javy_quickjs_provider") || watSource.includes("javy-default-plugin")) {
        const inferredTs = path.replace(/\.wat$/, ".ts");
        console.error(`❌ Cannot run Javy WAT: "${path}"`);
        console.error(`   This WAT is the app layer only — the QuickJS engine is not embedded.`);
        console.error(`   To run, use the original WASM: wasmtk run ${path.replace(/\.wat$/, ".wasm")}`);
        console.error(`   To rebuild after edits: wasmtk wasic ${inferredTs}`);
        rt.exit(1);
      }
    } catch { /* not readable as text - fall through to normal handling */ }
  }

  try {
    const wasmBytes = await getWasmBytes(path);
    // Phase 40: use a Proxy so any external interface method not explicitly listed
    // receives a no-op stub (returns 0) rather than causing an instantiation LinkError.
    const envBase: Record<string, (...args: unknown[]) => unknown> = {
      "console.log": (ptr: unknown) => {
        if (!wasiInstance) return;
        const memory = wasiInstance.exports.memory as WebAssembly.Memory;
        const view = new Uint32Array(memory.buffer, (ptr as number) - 4, 1);
        const len = view[0];
        const strBuf = new Uint16Array(memory.buffer, ptr as number, len / 2);
        console.log(String.fromCharCode(...strBuf));
      },
      abort: (): void => { throw new WebAssembly.RuntimeError("abort"); },
    };
    const envProxy = new Proxy(envBase, {
      get(target, prop) {
        const key = typeof prop === "string" ? prop : String(prop);
        if (key in target) return target[key];
        return (..._args: unknown[]) => 0;
      },
    });
    const extendedImports = { ...wasiImports, env: envProxy };
    const result = await WebAssembly.instantiate(wasmBytes as BufferSource, extendedImports as unknown as WebAssembly.Imports);
    wasiInstance = result.instance;
    
    if (args.length > 0 && !wasiInstance.exports._start) {
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
        if (err instanceof ((WebAssembly as Record<string, unknown>)["Exception"] as new (...args: unknown[]) => unknown)) {
          // Unhandled WASM throw — print message to stderr (mirrors TypeScript uncaught error), then exit cleanly.
          try {
            const tag = wasiInstance?.exports.__exn_tag as unknown as Record<string, unknown> | undefined;
            if (tag && (err as Record<string, unknown>)["is"] && (err as Record<string, (...a: unknown[]) => unknown>)["is"](tag)) {
              const ptr = (err as Record<string, (...a: unknown[]) => unknown>)["getArg"](tag, 0) as number;
              const len = (err as Record<string, (...a: unknown[]) => unknown>)["getArg"](tag, 1) as number;
              const memory = wasiInstance?.exports.memory as WebAssembly.Memory;
              const msg = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
              rt.stderr.writeSync(new TextEncoder().encode(`error: Uncaught (in Wasm) Error: ${msg}\n`));
            }
          } catch { /* ignore tag extraction errors */ }
          return;
        }
        throw err;
      }
    }
  } catch (err) { console.error(`❌ Run error: ${err}`); rt.exit(1); }
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
      rt.exit(1);
    }

    const parsedArgs = params.map(p => {
      const n = Number(p);
      return isNaN(n) ? 0 : n;
    }) as (number | bigint)[];

    const res = (fn as WasmCallable)(...parsedArgs);
    if (res !== undefined) console.log(`${res}`);
  } catch (err) {
    console.error(`❌ mod error: ${err}`);
    rt.exit(1);
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
      const isInternal = name === "_initialize" || name === "abort" || name.startsWith("__") || name.startsWith("cabi_") || name.includes("config-schema");
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
    try {
      const compiledMod = await WebAssembly.compile(bytes as BufferSource);
      isWasi = WebAssembly.Module.imports(compiledMod).some(
        (imp) => imp.module === "wasi_snapshot_preview1",
      );
    } catch { /* fall through — isWasi stays false */ }
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
export async function wasm2js(path: string, outPath?: string): Promise<void> {
  const out = outPath ?? path.replace(/\.(wasm|wat)$/, ".js");
  try {
    if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });
    const wasmBuffer = await getWasmBytes(path);
    const result = wasm2js_compiler(wasmBuffer as BufferSource);
    await rt.writeTextFile(out, typeof result === "string" ? result : new TextDecoder().decode(result));
    console.log(`✅ Success: ${out}`);
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
      await rt.stat(candidate);
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
export async function convertFile(p: string, outPath?: string): Promise<void> {
  const isWat = p.endsWith(".wat");
  const out = outPath ?? (isWat ? p.replace(".wat", ".wasm") : p.replace(".wasm", ".wat"));
  if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });

  try {
    if (isWat) {
      // --- WAT → WASM ---
      const watSource = await rt.readTextFile(p);

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
      await rt.writeFile(out, new Uint8Array(buffer));
      console.log(`✅ Converted to ${out}`);

    } else {
      // --- WASM → WAT ---
      const wasmBytes = await rt.readFile(p);
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
          await rt.writeTextFile(out, wat);
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
        const emitPlugin = new rt.Command(javyCmd, {
          args: ["emit-plugin", "-o", tempPlugin],
        });
        const emitResult = await emitPlugin.output();
        if (!emitResult.success) {
          const errText = new TextDecoder().decode(emitResult.stderr);
          console.error(`❌ Javy emit-plugin failed: ${errText}`);
          return;
        }

        // Step 2: build the dynamic app module against the emitted plugin
        const javy = new rt.Command(javyCmd, {
          args: ["build", "-C", "dynamic", "-C", `plugin=${tempPlugin}`, sourcePath, "-o", tempWasm],
        });
        const javyResult = await javy.output();
        try { await rt.remove(tempPlugin); } catch { /* ignore */ }

        if (!javyResult.success) {
          const errText = new TextDecoder().decode(javyResult.stderr);
          console.error(`❌ Javy dynamic recompile failed: ${errText}`);
          return;
        }

        try {
          const dynBytes = await rt.readFile(tempWasm);
          const wabtModule = await (wabt as unknown as () => Promise<WabtModule>)();
          const mod = wabtModule.readWasm(dynBytes, { readDebugNames: true });
          const wat = mod.toText({ foldExprs: false, inlineExport: false });
          mod.destroy();
          await rt.writeTextFile(out, wat);
        } finally {
          try { await rt.remove(tempWasm); } catch { /* ignore */ }
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
        await rt.writeTextFile(out, wat);
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
  const b = new rt.Command(rt.execPath(), { args: ["bundle", "--quiet", p], stdout: "piped" });
  const output = await b.output();
  await rt.writeTextFile(out, new TextDecoder().decode(output.stdout));
  console.log(`✅ Bundled: ${out}`);
}