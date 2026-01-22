import { basename, join, dirname } from "@std/path";
import wasm2js_compiler from "wasm2js";
import binaryen from "binaryen";
import { main as asc } from "asc";

export const VERSION = "1.1.1";
let wasiInstance: WebAssembly.Instance | undefined;

type WasmCallable = (...args: (number | bigint)[]) => number | bigint | void;
type WasiImports = Record<string, Record<string, WasmCallable | WebAssembly.Memory>>;

interface BinaryenModuleExt extends binaryen.Module {
  getNumImports(): number;
  getImportByIndex(index: number): number;
}

interface BinaryenLibExt {
  getImportInfo(importRef: number): { module: string; name: string; kind: number };
  i32: number;
  i64: number;
  f32: number;
  f64: number;
  v128: number;
  funcref: number;
  externref: number;
  none: number;
}

function getTypeName(typeId: number): string {
  const b = binaryen as unknown as BinaryenLibExt;
  if (typeId === b.i32) return "i32";
  if (typeId === b.i64) return "i64";
  if (typeId === b.f32) return "f32";
  if (typeId === b.f64) return "f64";
  if (typeId === b.v128) return "v128";
  if (typeId === b.funcref) return "funcref";
  if (typeId === b.externref) return "externref";
  if (typeId === b.none) return "void";
  return "unknown";
}

const wasiImports: WasiImports = {
  wasi_snapshot_preview1: {
    proc_exit: (code: number | bigint) => {
      if (Number(code) === 0) Deno.exit(0);
      throw new WebAssembly.RuntimeError(`exit:${code}`);
    },
    fd_write: (fd: number | bigint, iovs: number | bigint, iovsLen: number | bigint, nwrittenPtr: number | bigint) => {
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
    fd_pwrite: () => 0, 
    fd_read: (fd: number | bigint, iovs: number | bigint, iovsLen: number | bigint, nreadPtr: number | bigint) => {
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
    clock_time_get: (_id: number | bigint, _prec: bigint | number, resPtr: number | bigint) => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setBigUint64(Number(resPtr), BigInt(Date.now()) * 1000000n, true);
      return 0;
    },
    environ_get: () => 0,
    environ_sizes_get: (countPtr: number | bigint, bufSizePtr: number | bigint) => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint32(Number(countPtr), 0, true);
      view.setUint32(Number(bufSizePtr), 0, true);
      return 0;
    },
    args_get: () => 0,
    args_sizes_get: (countPtr: number | bigint, bufSizePtr: number | bigint) => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint32(Number(countPtr), 0, true);
      view.setUint32(Number(bufSizePtr), 0, true);
      return 0;
    },
    fd_close: () => 0,
    fd_fdstat_get: (fd: number | bigint, ptr: number | bigint) => {
      const view = new DataView((wasiInstance?.exports.memory as WebAssembly.Memory).buffer);
      view.setUint8(Number(ptr), Number(fd) <= 2 ? 2 : 3);
      view.setUint16(Number(ptr) + 2, 0, true);
      view.setBigUint64(Number(ptr) + 8, 0n, true);
      view.setBigUint64(Number(ptr) + 16, 0n, true);
      return 0;
    },
    fd_seek: () => 0,
    fd_prestat_get: () => 8,
    fd_prestat_dir_name: () => 8,
    fd_advise: () => 0,
    fd_allocate: () => 0,
    fd_datasync: () => 0,
    fd_sync: () => 0,
    fd_stat_put: () => 0,
    fd_filestat_get: () => 0,
    poll_oneoff: () => 28,
    random_get: (bufPtr: number | bigint, bufLen: number | bigint) => {
      const memory = wasiInstance?.exports.memory as WebAssembly.Memory;
      const buf = new Uint8Array(memory.buffer, Number(bufPtr), Number(bufLen));
      crypto.getRandomValues(buf);
      return 0;
    },
    sched_yield: () => 0,
  }
};

/**
 * Enhanced getWasmBytes: Automatically converts .wat to .wasm bytes in-memory
 */
async function getWasmBytes(path: string): Promise<Uint8Array> {
  if (path.endsWith(".wat")) {
    const tempWasm = `${path}.tmp.wasm`;
    try {
      const cmd = new Deno.Command("wat2wasm", { args: [path, "-o", tempWasm, "--enable-all"] });
      const { success, stderr } = await cmd.output();
      if (!success) throw new Error(`wat2wasm failed: ${new TextDecoder().decode(stderr)}`);
      return await Deno.readFile(tempWasm);
    } catch (err) {
      throw new Error(`[Compilation Error] ${err instanceof Error ? err.message : String(err)}`);
    } finally { try { await Deno.remove(tempWasm); } catch { /* ignore */ } }
  }
  return await Deno.readFile(path);
}

export async function compileModule(path: string): Promise<void> {
  if (path.endsWith(".wasm") || path.endsWith(".wat")) {
    console.error(`❌ Input Error: modc expects an AssemblyScript (.ts) file.`);
    return;
  }
  const name = basename(path).replace(/\.[^/.]+$/, "");
  const dir = dirname(path);
  const tempTsPath = join(dir, `${name}.build.tmp.ts`);
  console.log(`🔨 Building Library: ${name}.wasm`);
  try {
    let source = await Deno.readTextFile(path);
    source = source.replace(/\/\/ @test-start[\s\S]*?\/\/ @test-end/g, "");
    source = source.replace(/^\s*\(\s*function\s+([a-zA-Z0-9_]+)\s*\(\s*\)\s*\{([\s\S]*?)\}\s*\)\s*\(\s*\)\s*;?/gm, 
      "function $1(): void {$2}\n$1();"
    );
    source = source.replace(/console\.log\(([^)]+)\)/g, (match, p1) => {
      const trimmed = p1.trim();
      if (/^["'`].*["'`]$/.test(trimmed)) return match;
      return `console.log((${trimmed}).toString())`;
    });
    const shims = `\nexport function abort(_msg: string | null, _file: string | null, _line: u32, _col: u32): void {}\n`;
    await Deno.writeTextFile(tempTsPath, source + shims);
    const { error, stderr } = await asc([tempTsPath, "--target", "release", "--outFile", `./${name}.wasm`, "--optimize", "--noAssert", "--exportRuntime", "--converge"]);
    if (!error) {
      const bytes = await Deno.readFile(`./${name}.wasm`);
      const module = binaryen.readBinary(bytes);
      module.setFeatures(binaryen.Features.All);
      binaryen.setOptimizeLevel(3);
      if (module.getExport("_start")) module.removeExport("_start");
      module.optimize();
      await Deno.writeFile(`./${name}.wasm`, module.emitBinary());
      module.dispose();
      console.log(`✅ Library Ready: ${name}.wasm`);
    } else {
      console.error(`❌ Build failed: ${error.message}`);
      if (stderr) console.error(stderr.toString());
    }
  } catch (err) { console.error(`❌ modc Exception: ${err}`); } finally { try { await Deno.remove(tempTsPath); } catch { /* ignore */ } }
}

export async function runWasi(path: string, args: string[]): Promise<void> {
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
        abort: () => { throw new WebAssembly.RuntimeError("abort"); }
      }
    };
    const result = await WebAssembly.instantiate(wasmBytes as BufferSource, extendedImports as unknown as WebAssembly.Imports);
    wasiInstance = result.instance;
    if (args.length > 0) {
      const [name, ...params] = args;
      const fn = wasiInstance.exports[name];
      if (typeof fn === "function") {
        const parsedArgs = params.map(p => {
            const n = Number(p);
            return isNaN(n) ? 0 : n;
        }) as (number | bigint)[];
        const res = (fn as WasmCallable)(...parsedArgs);
        if (res !== undefined) console.log(`Result: ${res}`);
      } else { console.error(`❌ Function '${name}' not found.`); }
      return;
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
 * showInfo: Updated to handle .wat files via getWasmBytes
 */
export async function showInfo(path: string): Promise<void> {
  try {
    const bytes = await getWasmBytes(path);
    const module = binaryen.readBinary(bytes);
    
    console.log(`\n📄 Module Info: ${basename(path)}`);
    console.log("─".repeat(40));
    console.log(`🚀 User Callable Functions:`);

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
    
    console.log(`\n🛠️  WASI Support: ${isWasi ? "Yes" : "No"}`);
    console.log("─".repeat(40));
    module.dispose();
  } catch (err) { console.error("❌ Info error: " + err); }
}

export async function checkIsLibrary(path: string): Promise<boolean> {
  try {
    const bytes = await getWasmBytes(path);
    const mod = await WebAssembly.compile(bytes as BufferSource);
    return !WebAssembly.Module.exports(mod).some(e => e.name === "_start");
  } catch { return false; }
}

export async function wasm2js(path: string): Promise<void> {
  const outPath = path.replace(/\.(wasm|wat)$/, ".js");
  try {
    const wasmBuffer = await getWasmBytes(path);
    const result = wasm2js_compiler(wasmBuffer as BufferSource);
    await Deno.writeTextFile(outPath, typeof result === "string" ? result : new TextDecoder().decode(result));
    console.log(`✅ Success: ${outPath}`);
  } catch (err) { console.error(`❌ Conversion failed: ${err}`); }
}

export async function compileWasi(path: string): Promise<void> {
  const name = basename(path).replace(/\.[^/.]+$/, "");
  const bundle = new Deno.Command(Deno.execPath(), { args: ["bundle", "--quiet", path], stdout: "piped" });
  const output = await bundle.output();
  const preamble = `const prompt = function(message) { if (message) { Javy.IO.writeSync(1, new TextEncoder().encode(message + " ")); } let input = ""; const buffer = new Uint8Array(1); while (true) { const n = Javy.IO.readSync(0, buffer); if (n > 0) { const char = new TextDecoder().decode(buffer); if (char === "\\n" || char === "\\r") break; input += char; } else if (n === 0) { continue; } else { break; } } return input.trim(); };`;
  await Deno.writeTextFile(`./${name}.js`, preamble + new TextDecoder().decode(output.stdout));
  const javy = new Deno.Command("javy", { args: ["build", `./${name}.js`, "-o", `./${name}.wasm`] });
  if ((await javy.output()).success) console.log(`✅ WASI: ${name}.wasm`);
}

export async function convertFile(p: string): Promise<void> { 
  const isWat = p.endsWith(".wat");
  const out = isWat ? p.replace(".wat", ".wasm") : p.replace(".wasm", ".wat");
  const command = new Deno.Command(isWat ? "wat2wasm" : "wasm2wat", { args: [p, "-o", out] });
  await command.output();
  console.log(`✅ Converted to ${out}`);
}

export async function bundleTs(p: string): Promise<void> {
  const out = p.replace(".ts", ".js");
  const b = new Deno.Command(Deno.execPath(), { args: ["bundle", "--quiet", p], stdout: "piped" });
  const output = await b.output();
  await Deno.writeTextFile(out, new TextDecoder().decode(output.stdout));
  console.log(`✅ Bundled: ${out}`);
}