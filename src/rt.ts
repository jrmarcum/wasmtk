/**
 * src/rt.ts — Runtime abstraction for Deno and Bun.
 *
 * Exports a single `rt` object that mirrors the Deno namespace APIs used
 * across wasmtk source files.  Replace every `Deno.*` call site with `rt.*`
 * (and `new Deno.Command` with `new rt.Command`) to gain Bun compatibility
 * without touching any business logic.
 *
 * Unchanged across both runtimes (no shim needed):
 *   process.argv, process.exit, process.stderr.write, process.env
 */

// deno-lint-ignore-file no-explicit-any
import process from "node:process";
const isBun = typeof (globalThis as any).Bun !== "undefined";

// ── File I/O ─────────────────────────────────────────────────────────────────

async function readFile(path: string): Promise<Uint8Array> {
  if (isBun) return new Uint8Array(await (globalThis as any).Bun.file(path).arrayBuffer());
  return Deno.readFile(path);
}

async function readTextFile(path: string): Promise<string> {
  if (isBun) return await (globalThis as any).Bun.file(path).text();
  return Deno.readTextFile(path);
}

async function writeFile(path: string, data: Uint8Array): Promise<void> {
  if (isBun) {
    await (globalThis as any).Bun.write(path, data);
    return;
  }
  return Deno.writeFile(path, data);
}

async function writeTextFile(path: string, text: string): Promise<void> {
  if (isBun) {
    await (globalThis as any).Bun.write(path, text);
    return;
  }
  return Deno.writeTextFile(path, text);
}

// ── File system ───────────────────────────────────────────────────────────────

async function mkdir(path: string, opts?: { recursive?: boolean }): Promise<void> {
  if (isBun) {
    const { mkdir: fsMkdir } = await import("node:fs/promises");
    await fsMkdir(path, opts);
    return;
  }
  return Deno.mkdir(path, opts);
}

async function stat(path: string): Promise<unknown> {
  if (isBun) {
    const { stat: fsStat } = await import("node:fs/promises");
    return fsStat(path);
  }
  return Deno.stat(path);
}

async function realPath(path: string): Promise<string> {
  if (isBun) {
    const { realpath } = await import("node:fs/promises");
    return realpath(path);
  }
  return Deno.realPath(path);
}

async function remove(path: string): Promise<void> {
  if (isBun) {
    const { unlink } = await import("node:fs/promises");
    await unlink(path);
    return;
  }
  return Deno.remove(path);
}

// ── Process ───────────────────────────────────────────────────────────────────

function rtExit(code: number): never {
  process.exit(code);
}

const build = isBun
  ? {
    os: (process.platform === "win32"
      ? "windows"
      : process.platform === "darwin"
      ? "darwin"
      : "linux") as "windows" | "darwin" | "linux",
    arch: (process.arch === "arm64" ? "aarch64" : "x86_64") as "x86_64" | "aarch64",
  }
  : Deno.build;

const env = {
  get: (key: string): string | undefined => isBun ? process.env[key] : Deno.env.get(key),
  toObject: (): Record<string, string> =>
    isBun ? (process.env as Record<string, string>) : Deno.env.toObject(),
  set: (key: string, value: string): void =>
    isBun ? void (process.env[key] = value) : Deno.env.set(key, value),
};

function execPath(): string {
  return isBun ? process.execPath : Deno.execPath();
}

// ── Streams ───────────────────────────────────────────────────────────────────

const stdout = {
  writeSync(buf: Uint8Array): number {
    if (isBun) {
      process.stdout.write(buf);
      return buf.length;
    }
    return Deno.stdout.writeSync(buf);
  },
  async write(buf: Uint8Array): Promise<number> {
    if (isBun) {
      process.stdout.write(buf);
      return buf.length;
    }
    return await Deno.stdout.write(buf);
  },
};

const stderr = {
  writeSync(buf: Uint8Array): number {
    if (isBun) {
      process.stderr.write(buf);
      return buf.length;
    }
    return Deno.stderr.writeSync(buf);
  },
  async write(buf: Uint8Array): Promise<number> {
    if (isBun) {
      process.stderr.write(buf);
      return buf.length;
    }
    return await Deno.stderr.write(buf);
  },
};

const stdin = {
  /** Synchronous read — returns null on Bun (no sync stdin API). */
  readSync(buf: Uint8Array): number | null {
    if (isBun) return null;
    return Deno.stdin.readSync(buf);
  },
  /** Async read. */
  async read(buf: Uint8Array): Promise<number | null> {
    if (isBun) return null;
    return await Deno.stdin.read(buf);
  },
};

// ── Command ───────────────────────────────────────────────────────────────────

export interface RtCommandOptions {
  args?: string[];
  stdin?: "piped" | "null" | "inherit";
  stdout?: "piped" | "null" | "inherit";
  stderr?: "piped" | "null" | "inherit";
  env?: Record<string, string>;
  cwd?: string;
}

export interface RtCommandOutput {
  success: boolean;
  code: number;
  stdout: Uint8Array;
  stderr: Uint8Array;
}

export class RtCommand {
  private _cmd: string;
  private _opts: RtCommandOptions;

  constructor(cmd: string, opts: RtCommandOptions = {}) {
    this._cmd = cmd;
    this._opts = opts;
  }

  spawn(): { status: Promise<{ success: boolean; code: number }> } {
    if (isBun) {
      const bun = (globalThis as any).Bun;
      const proc = bun.spawn([this._cmd, ...(this._opts.args ?? [])], {
        stdout: "inherit",
        stderr: "inherit",
        stdin: "inherit",
        env: this._opts.env,
      });
      return {
        status: proc.exited.then((code: number) => ({ success: code === 0, code: code ?? 0 })),
      };
    }
    const child = new Deno.Command(this._cmd, {
      args: this._opts.args,
      stdout: "inherit",
      stderr: "inherit",
    }).spawn();
    return { status: child.status };
  }

  async output(): Promise<RtCommandOutput> {
    if (isBun) {
      const bun = (globalThis as any).Bun;
      const bunStdout = this._opts.stdout === "piped"
        ? "pipe"
        : this._opts.stdout === "null"
        ? "ignore"
        : "inherit";
      const bunStderr = this._opts.stderr === "piped"
        ? "pipe"
        : this._opts.stderr === "null"
        ? "ignore"
        : "inherit";
      const proc = bun.spawn([this._cmd, ...(this._opts.args ?? [])], {
        stdout: bunStdout,
        stderr: bunStderr,
        stdin: "inherit",
        env: this._opts.env,
        cwd: this._opts.cwd,
      });
      await proc.exited;
      const code: number = proc.exitCode ?? 0;
      const outBuf = this._opts.stdout === "piped"
        ? new Uint8Array(await new Response(proc.stdout).arrayBuffer())
        : new Uint8Array(0);
      const errBuf = this._opts.stderr === "piped"
        ? new Uint8Array(await new Response(proc.stderr).arrayBuffer())
        : new Uint8Array(0);
      return { success: code === 0, code, stdout: outBuf, stderr: errBuf };
    }
    const result = await new Deno.Command(this._cmd, {
      args: this._opts.args,
      stdin: this._opts.stdin as "piped" | "null" | "inherit" | undefined,
      stdout: this._opts.stdout as "piped" | "null" | "inherit" | undefined,
      stderr: this._opts.stderr as "piped" | "null" | "inherit" | undefined,
      env: this._opts.env,
      cwd: this._opts.cwd,
    }).output();
    return {
      success: result.success,
      code: result.code,
      stdout: result.stdout,
      stderr: result.stderr,
    };
  }
}

// ── Export ────────────────────────────────────────────────────────────────────

export const rt = {
  readFile,
  readTextFile,
  writeFile,
  writeTextFile,
  mkdir,
  stat,
  realPath,
  remove,
  exit: rtExit,
  build,
  env,
  execPath,
  stdout,
  stderr,
  stdin,
  Command: RtCommand,
};
