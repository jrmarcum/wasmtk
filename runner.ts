import binaryen from "binaryen";

let wasmInstance: WebAssembly.Instance | undefined;

function writeBytes(ptr: number, bytes: Uint8Array) {
  if (!wasmInstance) return;
  const mem = new Uint8Array((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
  mem.set(bytes, ptr);
}

export function createWasiImports(args: string[], env: Record<string, string>) {
  const encoder = new TextEncoder();
  return {
    proc_exit: (code: number) => Deno.exit(code),
    fd_write: (_fd: number, iovs: number, iovsLen: number, nwrittenPtr: number): number => {
      if (!wasmInstance) return 1;
      const memory = wasmInstance.exports.memory as WebAssembly.Memory;
      const view = new DataView(memory.buffer);
      let written = 0;
      const decoder = new TextDecoder();
      for (let i = 0; i < iovsLen; i++) {
        const ptr = view.getUint32(iovs + i * 8, true);
        const len = view.getUint32(iovs + i * 8 + 4, true);
        const text = decoder.decode(new Uint8Array(memory.buffer, ptr, len));
        Deno.stdout.writeSync(encoder.encode(text));
        written += len;
      }
      view.setUint32(nwrittenPtr, written, true);
      return 0;
    },
    fd_read: () => 0,
    fd_close: () => 0,
    fd_seek: () => 0,
    fd_pwrite: () => 0,
    fd_datasync: () => 0,
    fd_sync: () => 0,
    fd_tell: () => 0,
    fd_advise: () => 0,
    fd_allocate: () => 0,
    fd_fdstat_get: (_fd: number, statPtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      view.setUint8(statPtr, 2); 
      return 0;
    },
    fd_filestat_get: (_fd: number, _buf: number) => 0,
    fd_filestat_set_size: () => 0,
    fd_prestat_get: () => 76,
    fd_prestat_dir_name: () => 76,
    args_sizes_get: (argcPtr: number, argvBufSizePtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      view.setUint32(argcPtr, args.length, true);
      const totalLen = args.reduce((acc, a) => acc + encoder.encode(a).length + 1, 0);
      view.setUint32(argvBufSizePtr, totalLen, true);
      return 0;
    },
    args_get: (argvPtr: number, argvBufPtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      let currentBufPtr = argvBufPtr;
      args.forEach((a, i) => {
        view.setUint32(argvPtr + i * 4, currentBufPtr, true);
        const bytes = encoder.encode(a + "\0");
        writeBytes(currentBufPtr, bytes);
        currentBufPtr += bytes.length;
      });
      return 0;
    },
    environ_sizes_get: (countPtr: number, bufSizePtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      const envPairs = Object.entries(env).map(([k, v]) => `${k}=${v}\0`);
      view.setUint32(countPtr, envPairs.length, true);
      const totalLen = envPairs.reduce((acc, p) => acc + encoder.encode(p).length, 0);
      view.setUint32(bufSizePtr, totalLen, true);
      return 0;
    },
    environ_get: (envPtr: number, envBufPtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      let currentBufPtr = envBufPtr;
      Object.entries(env).forEach(([k, v], i) => {
        view.setUint32(envPtr + i * 4, currentBufPtr, true);
        const bytes = encoder.encode(`${k}=${v}\0`);
        writeBytes(currentBufPtr, bytes);
        currentBufPtr += bytes.length;
      });
      return 0;
    },
    clock_time_get: (id: number, _precision: bigint, resultPtr: number): number => {
      if (!wasmInstance) return 1;
      const view = new DataView((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      const now = id === 0 ? BigInt(Date.now()) * 1000000n : 0n;
      view.setBigUint64(resultPtr, now, true);
      return 0;
    },
    random_get: (buf: number, bufLen: number): number => {
      if (!wasmInstance) return 1;
      const mem = new Uint8Array((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
      crypto.getRandomValues(mem.subarray(buf, buf + bufLen));
      return 0;
    },
    path_open: () => 76,
    path_filestat_get: () => 76,
    path_remove_directory: () => 76,
    path_unlink_file: () => 76,
    poll_oneoff: () => 0,
    sock_recv: () => 76,
    sock_send: () => 76,
    sock_shutdown: () => 76,
  };
}

function getImportObject(wasiImports: unknown): WebAssembly.Imports {
  return {
    wasi_snapshot_preview1: wasiImports as WebAssembly.ModuleImports,
    env: {
      "__wbindgen_add_to_stack_pointer": (val: number) => val,
      "__wbindgen_malloc": (val: number) => val,
      "__wbindgen_free": () => {},
      "__wbindgen_realloc": (ptr: number, _old: number, newSize: number) => ptr || newSize,
      "console.log": (ptr: number, len: number) => {
        if (!wasmInstance) return;
        const mem = new Uint8Array((wasmInstance.exports.memory as WebAssembly.Memory).buffer);
        console.log(new TextDecoder().decode(mem.subarray(ptr, ptr + len)));
      },
      "abort": (msg: number, file: number, line: number, col: number) => {
         console.error(`Abort at ${file}:${line}:${col} (ptr: ${msg})`);
      }
    },
  };
}

async function getBinary(filePath: string): Promise<Uint8Array> {
  if (filePath.endsWith(".wat")) {
    const watText = await Deno.readTextFile(filePath);
    const module = binaryen.parseText(watText);
    module.setFeatures(binaryen.Features.All);
    binaryen.setOptimizeLevel(1);
    module.optimize();
    const binary = module.emitBinary();
    module.dispose();
    return binary;
  } 
  return await Deno.readFile(filePath);
}

function handleWasmError(err: unknown) {
  console.error(`\n❌ Execution Error: ${err instanceof Error ? err.message : String(err)}`);
  Deno.exit(1);
}

export async function runFile(filePath: string, args: string[]) {
  if (filePath.endsWith(".ts") || filePath.endsWith(".js")) {
    const command = new Deno.Command(Deno.execPath(), {
      args: ["run", "-A", filePath, ...args],
      stdin: "inherit", stdout: "inherit", stderr: "inherit",
    });
    const { code } = await command.output();
    if (code !== 0) Deno.exit(code);
    return;
  }

  const binary = await getBinary(filePath);
  const wasi = createWasiImports([filePath], Deno.env.toObject());

  try {
    const wasmModule = await WebAssembly.compile(binary.buffer as ArrayBuffer);
    const instance = await WebAssembly.instantiate(wasmModule, getImportObject(wasi));
    wasmInstance = instance;

    // SCENARIO 1: Call a specific export if the first arg is a function name
    if (args.length > 0 && typeof instance.exports[args[0]] === "function") {
      const [funcName, ...funcArgs] = args;
      const target = instance.exports[funcName] as CallableFunction;
      const parsedArgs = funcArgs.map(arg => isNaN(Number(arg)) ? arg : Number(arg));
      const res = target(...parsedArgs);
      if (res !== undefined) console.log(res);
      return;
    }

    // SCENARIO 2: Default WASI _start
    if (typeof instance.exports._start === "function") {
      (instance.exports._start as CallableFunction)();
    } else {
      // SCENARIO 3: Automatic fallback to info
      console.log(`\n💡 Note: No entry point (_start) found.`);
      const { showInfo } = await import("./utils.ts");
      await showInfo(filePath);
    }
  } catch (err) { handleWasmError(err); }
}