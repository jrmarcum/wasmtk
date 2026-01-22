/**
 * @module runner
 * @description Provides the WASI execution environment and import factories for WebAssembly modules.
 */

let wasiInstance: WebAssembly.Instance | undefined;

/**
 * Creates a standard WASI (snapshot_preview1) import object.
 * @param _args Unused command line arguments (WASI interface compatibility).
 * @param _env Unused environment variables (WASI interface compatibility).
 * @returns An object compatible with WebAssembly.instantiate imports.
 */
export function createWasiImports(_args: string[], _env: Record<string, string>): WebAssembly.Imports {
  return {
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
    }
  };
}

/**
 * Instantiates and runs a WASM module as a command-line application.
 * @param path Path to the .wasm file.
 * @param args Arguments passed to the module's _start function.
 */
export async function executeWasm(path: string, args: string[] = []): Promise<void> {
  const bytes = await Deno.readFile(path);
  const imports = createWasiImports(args, Deno.env.toObject());
  const { instance } = await WebAssembly.instantiate(bytes, imports);
  wasiInstance = instance;
  const start = instance.exports._start as CallableFunction;
  if (typeof start === "function") {
    try {
      start();
    } catch (e) {
      if (e instanceof WebAssembly.RuntimeError && e.message.includes("exit:0")) return;
      throw e;
    }
  }
}