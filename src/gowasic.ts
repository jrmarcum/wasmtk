/**
 * @module gowasic
 * @description Go → WASM producer for wasmtk (polyglot-producer track, ADR 2026-06-03).
 *
 * A front-end plugin: it shells out to a Go toolchain to emit a wasm module, then the existing
 * wasmtk downstream takes over (`wasmtk run` hosts wasip1 output on the TS WASI host; wasmmerge /
 * binaryen can consume it). No part of the wasic TypeScript compiler is involved.
 *
 * Command set (all WASI — no browser/syscall/js output; consume the modules with the universal
 * wasm loader):
 *   - `wasmtk init    --lang=go [dir]`  → scaffold go.mod + a WASI program main.go
 *   - `wasmtk initmod --lang=go [dir]`  → scaffold go.mod + a wasm-library main.go (//go:wasmexport)
 *   - `wasmtk run   [path]`             → build wasip1, then run it (lang auto-detected)
 *   - `wasmtk build [path]`             → `tinygo build -target=wasip1` → standalone WASI `.wasm`
 *   - `wasmtk modc  [path]`             → WASI reactor library (`-buildmode=c-shared`); leaf via
 *                                         `--go-target=wasm-unknown`
 *
 * Backends (`--go-runtime`): `tinygo` (default, small) or `std` (standard `go`, large — full
 * runtime/GC). All builds use `-p 1 -no-debug -panic=trap` and local `TINYGO_CACHE`/`GOTMPDIR`,
 * matching the scripts.
 *
 * wasm-opt: TinyGo runs binaryen's `wasm-opt` internally (`--asyncify -Oz`). `--asyncify` is
 * mandatory codegen for goroutines, not optimization. If a real `wasm-opt` is present (PATH /
 * $WASMOPT) wasmtk lets TinyGo use it (full support incl. goroutines). If not, wasmtk supplies a
 * passthrough `wasm-opt` shim, builds with `-scheduler=none` (no asyncify), and optimizes the
 * result with binaryen `-Oz` instead — no external binaryen, goroutine-FREE code only. (Native
 * goroutine support without binaryen needs an asyncify pass in binaryen — roadmap future item.)
 *
 * Scope (v1, numerics-first): command-mode (`func main`). Go string/aggregate HOST bindings
 * (bindgen) are deferred (ABI forward-alignment).
 */

import { basename, dirname, join, resolve } from "@std/path";
import { rt } from "./rt.ts";
import { binaryenAsyncify, binaryenOptimize } from "./binaryen.ts";

/** Go backend toolchain: `tinygo` (default, small) or `std` (standard `go`, large — full runtime/GC). */
export type GoRuntime = "tinygo" | "std";

/**
 * Go build target: `wasip1` = WASI command (`_start`); `reactor` = WASI library
 * (`-buildmode=c-shared`: no `_start`, exports //go:wasmexport funcs + runtime, callable via
 * `wasmtk mod` / bindgen — the Go analog of TS `modc` library mode); `leaf` = alloc-free mergeable
 * library (`--go-target=wasm-unknown`). Browser (syscall/js) output is intentionally not produced —
 * consume wasmtk's WASI modules with the universal wasm loader instead.
 */
export type GoTarget = "wasip1" | "reactor" | "leaf";

/** Project scaffold flavor: `program` (WASI command, via `init`) or `library` (via `initmod`). */
export type GoScaffold = "program" | "library";

/** Options for {@link compileGoWasi}. */
export interface GoCompileOptions {
  /** Output `.wasm` path. Default: `<name>.wasm` in the build's base directory. */
  outPath?: string;
  /** Backend toolchain. Default: `"tinygo"`. */
  runtime?: GoRuntime;
  /** Build target. Default: `"wasip1"`. */
  target?: GoTarget;
}

/** Result of a Go build / scaffold: `success` plus the output path or an error message. */
export type GoResult = { success: boolean; outputPath?: string; error?: string };

/** Decodes captured stderr+stdout from a piped rt.Command result into one diagnostic string. */
function decodeOut(r: { stdout: Uint8Array; stderr: Uint8Array }): string {
  const dec = new TextDecoder();
  return [dec.decode(r.stderr), dec.decode(r.stdout)].filter((s) => s.trim().length > 0).join("\n");
}

/**
 * Actionable hint appended to a failed Go build, derived from the error text. Turns raw toolchain
 * errors into next-step guidance. Covers the common "imports `syscall/js`" case: `syscall/js` only
 * has Go files for the browser (`GOOS=js`) target, which wasmtk no longer produces — so a
 * wasip1/reactor build of such code reports "build constraints exclude all Go files in
 * .../syscall/js". The fix is to drop `syscall/js` and expose a WASI module.
 */
function goBuildHint(errText: string, _target: GoTarget): string {
  if (/syscall\/js/i.test(errText)) {
    return "\n   This code imports `syscall/js` (a browser-only package). wasmtk builds WASI " +
      "modules, not browser (syscall/js) modules — consume the WASI output with the universal " +
      "wasm loader instead.\n" +
      "   Remove `syscall/js` and expose your API as //go:wasmexport functions (a plain " +
      "`func main` / test harness is fine; the library build strips it).";
  }
  return "";
}

/** Returns true if `cmd <versionArgs>` runs and exits 0. (Always pipe — rt.Command.output() reads
 *  stdout/stderr and throws unless they are "piped".) */
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

/** The passthrough wasm-opt shim: answers `--version`, otherwise copies TinyGo's input wasm to its
 *  `-o`/`--output` target with NO optimization (binaryen does the -Oz afterwards).
 *  Runtime-agnostic: runs under whichever runtime execs it (Deno, Bun, or Node). */
const SHIM_TS = String.raw`// @ts-nocheck
const _D = typeof Deno !== "undefined" ? Deno : undefined;
const _argv = _D ? _D.args : (typeof process !== "undefined" ? process.argv.slice(2) : []);
const _exit = (c) => { if (_D) _D.exit(c); else process.exit(c); };
if (_argv.includes("--version") || _argv.includes("-version")) {
  console.log("wasm-opt version 116 (wasmtk binaryen passthrough shim)");
  _exit(0);
}
let out = "", input = "";
for (let i = 0; i < _argv.length; i++) {
  if (_argv[i] === "-o" || _argv[i] === "--output") { out = _argv[i + 1] ?? ""; i++; }
}
for (let i = 0; i < _argv.length; i++) {
  const a = _argv[i];
  if (a === "-o" || a === "--output") { i++; continue; }
  if (a.startsWith("-")) continue;
  if (a !== out) input = a; // last non-flag, non-output positional = input
}
try {
  if (_D) {
    await _D.copyFile(input, out);
  } else if (typeof Bun !== "undefined") {
    await Bun.write(out, Bun.file(input));
  } else {
    const fs = await import("node:fs/promises");
    await fs.copyFile(input, out);
  }
} catch (e) {
  console.error("wasmtk wasm-opt shim: copy failed in=" + input + " out=" + out + " " + e);
  _exit(1);
}
`;

/** Writes the passthrough shim + a platform launcher TinyGo can exec as `wasm-opt`. */
async function writeWasmOptShim(
  baseDir: string,
): Promise<{ launcher: string; cleanup: () => Promise<void> }> {
  const tmp = join(baseDir, `.wasmtk_wasmopt_${Date.now()}`);
  await rt.mkdir(tmp, { recursive: true });
  const shimPath = join(tmp, "wasmopt_shim.ts");
  await rt.writeTextFile(shimPath, SHIM_TS);
  const bin = rt.execPath(); // the deno (or bun) binary running wasmtk — no reliance on PATH
  // Deno needs `run -A` (subcommand + all-permissions); Bun executes a file directly
  // with no permission flags. `-A` is a hard parse error under Bun, so branch on runtime.
  const isBun = typeof (globalThis as { Bun?: unknown }).Bun !== "undefined";
  const runPrefix = isBun ? `"${bin}"` : `"${bin}" run -A`;
  let launcher: string;
  if (rt.build.os === "windows") {
    launcher = join(tmp, "wasm-opt.cmd");
    await rt.writeTextFile(launcher, `@echo off\r\n${runPrefix} "${shimPath}" %*\r\n`);
  } else {
    launcher = join(tmp, "wasm-opt");
    await rt.writeTextFile(launcher, `#!/bin/sh\nexec ${runPrefix} "${shimPath}" "$@"\n`);
    try {
      await rt.chmod(launcher, 0o755);
    } catch { /* best effort */ }
  }
  return {
    launcher,
    cleanup: async () => {
      try {
        await rt.remove(tmp, { recursive: true });
      } catch { /* ignore */ }
    },
  };
}

/** Resolves a Go build target. `input` may be a `.go` file, a directory, or "" (current dir). */
async function resolveBuild(
  input: string,
): Promise<{ baseDir: string; buildArg: string; name: string }> {
  const abs = resolve(input && input.length > 0 ? input : ".");
  if (input.endsWith(".go") && !(await isDirectory(abs))) {
    const baseDir = dirname(abs);
    return { baseDir, buildArg: basename(abs), name: basename(abs).replace(/\.go$/, "") };
  }
  // Directory (or cwd): build the package `.` from inside it, output <dirname>.wasm.
  return { baseDir: abs, buildArg: ".", name: basename(abs) };
}

/**
 * Compiles Go to a WASI wasm module. `target` "wasip1" → WASI core module (runnable via
 * `wasmtk run`); "reactor" → WASI library; "leaf" → alloc-free mergeable library. (No browser
 * output — consume the WASI module with the universal wasm loader.)
 */
export async function compileGoWasi(input: string, opts: GoCompileOptions = {}): Promise<GoResult> {
  const runtime: GoRuntime = opts.runtime ?? "tinygo";
  const target: GoTarget = opts.target ?? "wasip1";
  const { baseDir, buildArg, name } = await resolveBuild(input);
  const out = opts.outPath ?? join(baseDir, `${name}.wasm`);
  return runtime === "std"
    ? await buildWithStd(baseDir, buildArg, out, target)
    : await buildWithTinyGo(baseDir, buildArg, out, target);
}

async function buildWithTinyGo(
  baseDir: string,
  buildArg: string,
  out: string,
  target: GoTarget,
): Promise<GoResult> {
  if (!(await toolAvailable("tinygo", ["version"]))) {
    const msg =
      "TinyGo not found on PATH. Install it (https://tinygo.org/getting-started/install/) " +
      "or use `--go-runtime=std`.";
    console.error(`❌ wasmtk (go): ${msg}`);
    return { success: false, error: msg };
  }
  // leaf: an alloc-free, MERGEABLE `wasm-unknown` library (its own build path — no WASI, no
  // scheduler/asyncify, no runtime allocator).
  if (target === "leaf") return await buildGoLeaf(baseDir, buildArg, out);
  // reactor (WASI library) builds wasip1 + `-buildmode=c-shared`; wasip1 program maps directly.
  const tgoTarget = "wasip1";
  const buildModeArgs = target === "reactor" ? ["-buildmode=c-shared"] : [];
  const reportLabel = target === "reactor" ? "wasip1 c-shared library" : tgoTarget;
  const baseEnv = {
    ...rt.env.toObject(),
    TINYGO_CACHE: join(baseDir, ".tinygo-cache"),
    GOTMPDIR: baseDir,
  };
  const baseArgs = [
    "build",
    "-p",
    "1",
    "-no-debug",
    "-panic=trap",
    "-o",
    out,
    `-target=${tgoTarget}`,
    ...buildModeArgs,
  ];

  // `WASMTK_GO_BINARYEN_ASYNCIFY=1` forces the no-external-binaryen path (TinyGo
  // asyncify scheduler + passthrough shim + binaryen Asyncify+-Oz) even when a
  // real `wasm-opt` is on PATH — used by the goroutine e2e and by users who want
  // zero external binaryen. Otherwise a real `wasm-opt` (if present) is preferred.
  const forceBinaryenAsyncify = rt.env.get("WASMTK_GO_BINARYEN_ASYNCIFY") === "1";
  const haveRealWasmOpt = !forceBinaryenAsyncify &&
    (!!rt.env.get("WASMOPT") || await toolAvailable("wasm-opt", ["--version"]));

  if (haveRealWasmOpt) {
    // Real wasm-opt → TinyGo does its full --asyncify -Oz pass (full goroutine support).
    const r = await new rt.Command("tinygo", {
      args: [...baseArgs, buildArg],
      cwd: baseDir,
      env: baseEnv,
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!r.success) {
      const errText = decodeOut(r);
      console.error(
        `❌ wasmtk (go): TinyGo build failed:\n${errText}${goBuildHint(errText, target)}`,
      );
      return { success: false, error: "tinygo build failed" };
    }
    return await report(out, `tinygo:${reportLabel} (wasm-opt)`);
  }

  // No real wasm-opt → build with TinyGo's asyncify scheduler + a passthrough
  // wasm-opt shim (so TinyGo leaves the module un-instrumented, importing the
  // `asyncify.*` control API), then run binaryen's Asyncify (which resolves
  // those imports) + `-Oz` ourselves. This supports GOROUTINES with no external
  // binaryen (in-wasm asyncify-import mode: binaryen ≥ 1.4.1, now binaryang ≥ 1.5.1).
  const shim = await writeWasmOptShim(baseDir);
  try {
    const r = await new rt.Command("tinygo", {
      args: [
        "build",
        "-p",
        "1",
        "-scheduler=asyncify",
        "-no-debug",
        "-panic=trap",
        "-o",
        out,
        `-target=${tgoTarget}`,
        ...buildModeArgs,
        buildArg,
      ],
      cwd: baseDir,
      env: { ...baseEnv, WASMOPT: shim.launcher },
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!r.success) {
      const errText = decodeOut(r);
      console.error(
        `❌ wasmtk (go): TinyGo build failed:\n${errText}${goBuildHint(errText, target)}`,
      );
      return { success: false, error: "tinygo build failed" };
    }
  } finally {
    await shim.cleanup();
  }
  // Resolve the asyncify.* imports + optimize via binaryen. This MUST succeed —
  // an un-asyncified module has unresolved `asyncify.*` imports and won't run.
  try {
    await rt.writeFile(out, binaryenAsyncify(await rt.readFile(out)));
    return await report(out, `tinygo:${reportLabel} + binaryen asyncify+-Oz`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`❌ wasmtk (go): binaryen asyncify pass failed: ${msg}`);
    return { success: false, error: "binaryen asyncify failed" };
  }
}

/**
 * Build an alloc-free, MERGEABLE `wasm-unknown` leaf library from Go (`//go:wasmexport` funcs).
 * `wasm-unknown` is TinyGo's freestanding target: no WASI, no scheduler/asyncify, no runtime
 * allocator — the output has 0 imports and no `memory.grow`, so it `wasmmerge`s into a wasic/
 * wasmbundle build like a Zig `FixedBufferAllocator` leaf. (wasmtk's merge calls the leaf's
 * `_initialize` — TinyGo guards each export on a runtime-init flag — see `mergeOneWasmImport`.)
 * No asyncify path: a leaf has no goroutine scheduler, so `-Oz` alone (real `wasm-opt` or the
 * binaryen passthrough) suffices.
 *
 * CAVEAT: the init flag sits at a fixed page-1 address (65536), so the host program must not use
 * that region — fine for typical small hosts; large-memory hosts should prefer the reactor/bindgen
 * path. Suitable for pure-compute leaves (no Go runtime allocation).
 */
async function buildGoLeaf(baseDir: string, buildArg: string, out: string): Promise<GoResult> {
  const baseEnv = {
    ...rt.env.toObject(),
    TINYGO_CACHE: join(baseDir, ".tinygo-cache"),
    GOTMPDIR: baseDir,
  };
  const args = [
    "build",
    "-p",
    "1",
    "-no-debug",
    "-opt=z",
    "-o",
    out,
    "-target=wasm-unknown",
    buildArg,
  ];
  const runBuild = async (env: Record<string, string>): Promise<GoResult | null> => {
    const r = await new rt.Command("tinygo", {
      args,
      cwd: baseDir,
      env,
      stdout: "piped",
      stderr: "piped",
    })
      .output();
    if (r.success) return null;
    const errText = decodeOut(r);
    console.error(
      `❌ wasmtk (go): TinyGo leaf build failed:\n${errText}${goBuildHint(errText, "leaf")}`,
    );
    return { success: false, error: "tinygo build failed" };
  };
  const haveRealWasmOpt = !!rt.env.get("WASMOPT") || await toolAvailable("wasm-opt", ["--version"]);
  if (haveRealWasmOpt) {
    const fail = await runBuild(baseEnv);
    if (fail) return fail;
    return await report(out, "tinygo:wasm-unknown leaf (wasm-opt)");
  }
  // No real wasm-opt → passthrough shim + binaryen `-Oz` (a leaf needs no asyncify).
  const shim = await writeWasmOptShim(baseDir);
  try {
    const fail = await runBuild({ ...baseEnv, WASMOPT: shim.launcher });
    if (fail) return fail;
  } finally {
    await shim.cleanup();
  }
  const { bytes, optimized } = binaryenOptimize(await rt.readFile(out));
  if (optimized) await rt.writeFile(out, bytes);
  return await report(out, `tinygo:wasm-unknown leaf${optimized ? " + binaryen -Oz" : ""}`);
}

async function buildWithStd(
  baseDir: string,
  buildArg: string,
  out: string,
  target: GoTarget,
): Promise<GoResult> {
  if (!(await toolAvailable("go", ["version"]))) {
    const msg = "The Go toolchain (`go`) was not found on PATH. Install Go (https://go.dev/dl/) " +
      "or use the default TinyGo backend.";
    console.error(`❌ wasmtk (go): ${msg}`);
    return { success: false, error: msg };
  }
  // The alloc-free MERGEABLE leaf (`--go-target=wasm-unknown`) is a TinyGo-only capability:
  // standard Go has no freestanding target — it always links the full runtime + GC + allocator
  // (a memory.grow module that wasmmerge rejects). Fail loud rather than silently building a
  // full-runtime wasip1 module that isn't the mergeable leaf the flag promises.
  if (target === "leaf") {
    const msg =
      "the alloc-free mergeable leaf (--go-target=wasm-unknown) requires TinyGo — standard Go " +
      "(--go-runtime=std) always links the full runtime + allocator, which is NOT mergeable. " +
      "Drop --go-runtime=std to build the leaf with TinyGo.";
    console.error(`❌ wasmtk (go): ${msg}`);
    return { success: false, error: msg };
  }
  console.warn(
    "   ⚠️  --go-runtime=std uses the full Go runtime/GC — output is large (often several MB). " +
      "TinyGo (the default) produces far smaller modules.",
  );
  // GOOS=wasip1, GOARCH=wasm. reactor = wasip1 library via `-buildmode=c-shared` (std Go 1.24+
  // supports //go:wasmexport for wasip1 in this mode).
  const goos = "wasip1";
  const buildModeArgs = target === "reactor" ? ["-buildmode=c-shared"] : [];
  const r = await new rt.Command("go", {
    args: ["build", ...buildModeArgs, "-o", out, buildArg],
    cwd: baseDir,
    env: { ...rt.env.toObject(), GOOS: goos, GOARCH: "wasm" },
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!r.success) {
    const errText = decodeOut(r);
    console.error(`❌ wasmtk (go): go build failed:\n${errText}${goBuildHint(errText, target)}`);
    return { success: false, error: "go build failed" };
  }
  return await report(out, `std:${goos}${target === "reactor" ? " c-shared library" : ""}`);
}

/**
 * Scaffolds a Go project: `go mod init <dirname>` + a boilerplate main.go. The `scaffold` kind
 * selects the template: `"program"` = a WASI command (`func main`, via `wasmtk init`); `"library"`
 * = a wasm library (`//go:wasmexport` functions + a `func main` test harness, via `wasmtk initmod`).
 * This mirrors the Rust producer's `init` (program) vs `initmod` (library) split so all producers
 * scaffold the same way.
 */
export async function scaffoldGoProject(
  dir: string,
  scaffold: GoScaffold,
): Promise<GoResult> {
  const baseDir = resolve(dir && dir.length > 0 ? dir : ".");
  const name = basename(baseDir);
  if (!(await toolAvailable("go", ["version"]))) {
    const msg = "The Go toolchain (`go`) was not found on PATH — needed for `go mod init`.";
    console.error(`❌ wasmtk (go): ${msg}`);
    return { success: false, error: msg };
  }
  console.log(
    scaffold === "library"
      ? `Initializing Go wasm library project: ${name}`
      : `Initializing Go WASI program project: ${name}`,
  );

  // Ensure the target directory exists. `go mod init` (below) runs with cwd=baseDir and the
  // file writes target paths inside it, so scaffolding into a not-yet-created dir (e.g.
  // `wasmtk init --lang=go newproj`) would otherwise fail with "No such cwd".
  try {
    await rt.mkdir(baseDir, { recursive: true });
  } catch { /* already exists (or a benign race) — fine */ }

  // go mod init (skip if go.mod already present)
  let hasGoMod = false;
  try {
    await rt.stat(join(baseDir, "go.mod"));
    hasGoMod = true;
  } catch { /* none */ }
  if (!hasGoMod) {
    const r = await new rt.Command("go", {
      args: ["mod", "init", name],
      cwd: baseDir,
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!r.success) {
      console.error(`❌ wasmtk (go): go mod init failed:\n${decodeOut(r)}`);
      return { success: false, error: "go mod init failed" };
    }
  } else {
    console.log("   go.mod already exists — leaving it as is.");
  }

  // main.go (do not overwrite an existing one)
  const mainPath = join(baseDir, "main.go");
  let hasMain = false;
  try {
    await rt.stat(mainPath);
    hasMain = true;
  } catch { /* none */ }
  if (hasMain) {
    console.log("   main.go already exists — leaving it as is.");
  } else {
    await rt.writeTextFile(mainPath, scaffold === "library" ? MAIN_GO_LIBRARY : MAIN_GO_PROGRAM);
    console.log(`   wrote ${mainPath}`);
  }
  if (scaffold === "program") {
    console.log(`   Run:   wasmtk run   --lang=go ${baseDir}   (runs func main as a WASI program)`);
    console.log(
      `   Build: wasmtk build --lang=go ${baseDir}   (→ standalone WASI .wasm)`,
    );
  } else {
    console.log(`   Test:  wasmtk run  --lang=go ${baseDir}   (runs func main as a test harness)`);
    console.log(
      `   Build: wasmtk modc --lang=go ${baseDir}   (→ wasm library; exports //go:wasmexport funcs)`,
    );
  }
  return { success: true, outputPath: baseDir };
}

// `init` scaffold: a WASI PROGRAM (a runnable command). Run it with `wasmtk run --lang=go`, or
// build a standalone `.wasm` with `wasmtk build --lang=go`. For a callable wasm LIBRARY instead
// (exported functions, no entry point), scaffold with `wasmtk initmod --lang=go`.
const MAIN_GO_PROGRAM = `package main

import "fmt"

// This is a WASI PROGRAM — ` + "`func main`" + ` is the entry point that runs when you
// ` + "`wasmtk run --lang=go .`" + ` (or ` + "`wasmtk build --lang=go .`" + ` to produce a
// standalone .wasm you can run on any WASI runtime). For a callable wasm LIBRARY instead
// (exported functions, no ` + "`main`" + `), scaffold with ` +
  "`wasmtk initmod --lang=go`" + ` and build with ` + "`wasmtk modc --lang=go`" + `.
func main() {
	fmt.Println("Hello from Go on WASI!")
	fmt.Println("2 + 3 =", add(2, 3))
}

func add(a int, b int) int {
	return a + b
}
`;

// `initmod` scaffold: a wasm LIBRARY (exports + a test harness in one file). Build it with
// ` + "`wasmtk modc --lang=go`" + ` (→ wasm library); test it with ` + "`wasmtk run --lang=go`" + `.
const MAIN_GO_LIBRARY = `package main

import "fmt"

// add is an EXPORTED library function — this is what your wasm library exposes.
//
// ` + "`//go:wasmexport <name>`" + ` (TinyGo) marks a function for export so a host — or another
// WASM module — can call it. Rules: put the directive on the line DIRECTLY above the function (no
// blank line between it and "func"), and ONLY functions you annotate are exported. Use WASM-friendly
// types (int32 / int64 / float32 / float64 / bool); strings & slices need host glue. Add one
// //go:wasmexport block per function you want to expose.
//
//go:wasmexport add
func add(a int32, b int32) int32 {
	return a + b
}

// main is your test harness — put assertions here. ` + "`wasmtk run --lang=go .`" + ` builds this
// file as a command and runs main, so you can test your library before shipping it. ` +
  "`wasmtk modc --lang=go .`" + ` builds the wasm LIBRARY: main (and everything reachable only from
// it) is dead-code-eliminated, so the library exports just the //go:wasmexport functions above.
func main() {
	if add(2, 3) == 5 {
		fmt.Println("PASS: add(2, 3) =", add(2, 3))
	} else {
		fmt.Println("FAIL: add(2, 3) =", add(2, 3))
	}
}
`;

async function report(out: string, how: string): Promise<GoResult> {
  let size = 0;
  try {
    size = (await rt.readFile(out)).length;
  } catch { /* ignore */ }
  console.log(`✅ Go → wasm (${how}): ${out}${size ? ` (${size} bytes)` : ""}`);
  return { success: true, outputPath: out };
}
