/**
 * @module zigwasic
 * @description Zig → WASM producer for wasmtk (polyglot-producer track, 2026-06-07).
 *
 * A front-end plugin mirroring `src/gowasic.ts`: it shells out to the `zig` toolchain to emit a wasm
 * module, then the existing wasmtk downstream takes over (`wasmtk run` hosts a WASI program on the TS
 * WASI host; `wasmtk mod` / bindgen / wasmmerge consume a library). No part of the wasic TypeScript
 * compiler is involved. Unlike the Go producer there is NO wasm-opt shim — `zig` runs its own
 * optimizer (`-O ReleaseSmall`); we additionally run binaryen-ts `-Oz` on the library output to strip
 * name/debug sections.
 *
 * Commands (wired in `main.ts` under `--lang=zig`):
 *   - `wasmtk init --lang=zig [dir]`  → scaffold a wasm-library `main.zig`
 *   - `wasmtk modc --lang=zig [path]` → freestanding wasm LIBRARY (exports `export fn`, no WASI)
 *   - `wasmtk run  --lang=zig [path]` → wasm32-wasi PROGRAM, run on wasmtk's TS WASI host
 *
 * Scope (v1, numerics-first): command-mode (`pub fn main`) + `export fn` library exports. Zig
 * string/aggregate HOST bindings (bindgen) are deferred (ABI forward-alignment), as for Go.
 */

import { basename, dirname, join, resolve } from "@std/path";
import { rt } from "./rt.ts";
import { binaryenOptimize } from "./binaryen.ts";

// library  = wasm32-freestanding, exports `export fn`, no _start/WASI (the mergeable/bindgen leaf).
// wasi     = wasm32-wasi, has _start + WASI imports (a runnable command).
export type ZigTarget = "library" | "wasi";

export interface ZigCompileOptions {
  outPath?: string;
  target?: ZigTarget; // default "library"
}

type ZigResult = { success: boolean; outputPath?: string; error?: string };

/** Decodes captured stderr+stdout from a piped rt.Command result into one diagnostic string. */
function decodeOut(r: { stdout: Uint8Array; stderr: Uint8Array }): string {
  const dec = new TextDecoder();
  return [dec.decode(r.stderr), dec.decode(r.stdout)].filter((s) => s.trim().length > 0).join("\n");
}

/** True if `cmd <versionArgs>` runs and exits 0. (Always pipe so rt.Command.output() can read.) */
async function toolAvailable(cmd: string, versionArgs: string[]): Promise<boolean> {
  try {
    const r = await new rt.Command(cmd, { args: versionArgs, stdout: "piped", stderr: "piped" })
      .output();
    return r.success;
  } catch {
    return false;
  }
}

/** True if path exists and is a directory (handles Deno property vs node method shapes). */
async function isDirectory(path: string): Promise<boolean> {
  try {
    const s = await rt.stat(path) as { isDirectory: boolean | (() => boolean) };
    return typeof s.isDirectory === "function" ? s.isDirectory() : !!s.isDirectory;
  } catch {
    return false;
  }
}

/**
 * Resolves a Zig build target. `input` may be a `.zig` file, a directory (uses `main.zig` inside it),
 * or "" (current dir). Returns the build cwd, the root source file (relative to cwd), and the name.
 */
async function resolveBuild(
  input: string,
): Promise<{ baseDir: string; srcFile: string; name: string }> {
  const abs = resolve(input && input.length > 0 ? input : ".");
  if (input.endsWith(".zig") && !(await isDirectory(abs))) {
    return {
      baseDir: dirname(abs),
      srcFile: basename(abs),
      name: basename(abs).replace(/\.zig$/, ""),
    };
  }
  // Directory (or cwd): build <dir>/main.zig, output <dirname>.wasm.
  return { baseDir: abs, srcFile: "main.zig", name: basename(abs) };
}

/**
 * Scans a Zig source file for `export fn <name>` declarations (best-effort, root file only) so the
 * library build can pass explicit `--export=<name>` flags — giving a clean library (only the marked
 * functions + memory, no `_start`) rather than `-rdynamic` (which also exports the entry/main).
 */
async function scanExportFns(file: string): Promise<string[]> {
  try {
    const src = await rt.readTextFile(file);
    const names = new Set<string>();
    for (const m of src.matchAll(/\bexport\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)/g)) names.add(m[1]);
    return [...names];
  } catch {
    return [];
  }
}

async function report(out: string, how: string): Promise<ZigResult> {
  let size = 0;
  try {
    size = (await rt.readFile(out)).length;
  } catch { /* ignore */ }
  console.log(`✅ Zig → wasm (${how}): ${out}${size ? ` (${size} bytes)` : ""}`);
  return { success: true, outputPath: out };
}

/**
 * Compiles Zig to a wasm module. `target` "library" → freestanding wasm library (exports, no WASI),
 * then binaryen-ts `-Oz`; "wasi" → a `wasm32-wasi` command runnable via `wasmtk run`.
 */
export async function compileZig(input: string, opts: ZigCompileOptions = {}): Promise<ZigResult> {
  if (!(await toolAvailable("zig", ["version"]))) {
    const msg =
      "Zig not found on PATH. Install it (https://ziglang.org/download/) to use --lang=zig.";
    console.error(`❌ wasmtk (zig): ${msg}`);
    return { success: false, error: msg };
  }
  const target: ZigTarget = opts.target ?? "library";
  const { baseDir, srcFile, name } = await resolveBuild(input);
  const out = opts.outPath ?? join(baseDir, `${name}.wasm`);

  // library  → freestanding, exports the `export fn` functions (no entry/WASI). We pass explicit
  //            `--export=<name>` (scanned from the root source) for a CLEAN library — only the marked
  //            functions + memory, no `_start`. Falls back to `-rdynamic` if no `export fn` is found
  //            in the root (e.g. exports live in imported files). NOTE: Zig semantically analyzes
  //            `pub fn main` even with `-fno-entry`, so a single-file scaffold must comptime-guard a
  //            std-using `main` to the WASI target (see MAIN_ZIG_LIBRARY) or the freestanding build
  //            fails compiling std I/O.
  // wasi     → a runnable command (_start + WASI imports), hosted by `wasmtk run`.
  let targetArgs: string[];
  if (target === "library") {
    const exportNames = await scanExportFns(join(baseDir, srcFile));
    const exportFlags = exportNames.length > 0
      ? exportNames.map((n) => `--export=${n}`)
      : ["-rdynamic"];
    targetArgs = ["-target", "wasm32-freestanding", "-fno-entry", ...exportFlags];
  } else {
    targetArgs = ["-target", "wasm32-wasi"];
  }

  const r = await new rt.Command("zig", {
    args: ["build-exe", srcFile, ...targetArgs, "-O", "ReleaseSmall", `-femit-bin=${out}`],
    cwd: baseDir,
    env: rt.env.toObject(),
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!r.success) {
    console.error(`❌ wasmtk (zig): zig build failed:\n${decodeOut(r)}`);
    return { success: false, error: "zig build failed" };
  }

  // Library output: shrink + strip name/debug sections with binaryen-ts -Oz (Rust path skips this;
  // a WASI program is left as zig emitted it so `wasmtk run` hosts the unmodified command).
  if (target === "library") {
    try {
      const { bytes, optimized } = binaryenOptimize(await rt.readFile(out));
      if (optimized) await rt.writeFile(out, bytes);
      return await report(
        out,
        `wasm32-freestanding library${optimized ? " + binaryen-ts -Oz" : ""}`,
      );
    } catch {
      return await report(out, "wasm32-freestanding library");
    }
  }
  return await report(out, "wasm32-wasi program");
}

/** Scaffolds a Zig wasm-library project: writes `main.zig` (export fn + a comptime-guarded test main). */
export async function scaffoldZigProject(dir: string): Promise<ZigResult> {
  if (!(await toolAvailable("zig", ["version"]))) {
    const msg =
      "Zig not found on PATH. Install it (https://ziglang.org/download/) to use --lang=zig.";
    console.error(`❌ wasmtk (zig): ${msg}`);
    return { success: false, error: msg };
  }
  const baseDir = resolve(dir && dir.length > 0 ? dir : ".");
  const name = basename(baseDir);
  console.log(`Initializing Zig wasm library project: ${name}`);
  try {
    await rt.mkdir(baseDir, { recursive: true });
  } catch { /* already exists — fine */ }

  const mainPath = join(baseDir, "main.zig");
  try {
    await rt.stat(mainPath);
    console.log("   main.zig already exists — leaving it as is.");
  } catch {
    await rt.writeTextFile(mainPath, MAIN_ZIG_LIBRARY);
    console.log(`   wrote ${mainPath}`);
  }
  console.log(`   Test:  wasmtk run  --lang=zig ${baseDir}   (runs main as a test harness)`);
  console.log(
    `   Build: wasmtk modc --lang=zig ${baseDir}   (→ wasm library; exports 'export fn' funcs)`,
  );
  return { success: true, outputPath: baseDir };
}

const MAIN_ZIG_LIBRARY = `const builtin = @import("builtin");
const std = @import("std");

// add is an EXPORTED library function — this is what your wasm library exposes.
//
// In Zig, the 'export fn' keyword marks a function for WASM export so a host (or another module)
// can call it. Use WASM-friendly types (i32 / i64 / f32 / f64 / bool). Add one 'export fn' per
// function you want to expose. (modc builds with -fno-entry -rdynamic, which exports them.)
export fn add(a: i32, b: i32) i32 {
    return a + b;
}

// main is your test harness. 'wasmtk run --lang=zig .' builds this file as a wasm32-wasi command
// and runs main, so you can test your library before shipping it. The test body is comptime-guarded
// to the WASI target: 'wasmtk modc --lang=zig .' builds for wasm32-freestanding, where std I/O
// isn't available — the guard prunes the std code so the library still compiles (and exports only
// the 'export fn' functions above).
pub fn main() void {
    if (builtin.os.tag == .wasi) {
        if (add(2, 3) == 5) {
            std.debug.print("PASS: add(2, 3) = {d}\\n", .{add(2, 3)});
        } else {
            std.debug.print("FAIL\\n", .{});
        }
    }
}
`;
