/**
 * @module gowasic
 * @description Go → WASM producer for wasmtk (polyglot-producer track, ADR 2026-06-03).
 *
 * A front-end plugin: it shells out to a Go toolchain to emit a wasm module, then the existing
 * wasmtk downstream takes over (`wasmtk run` hosts wasip1 output on the TS WASI host; wasmmerge /
 * binaryen-ts can consume it). No part of the wasic TypeScript compiler is involved.
 *
 * Folds in the owner's `tgo-*.ps1` scripts as one congruent command set:
 *   - `wasmtk wasic --lang=go [path]`  → `tinygo build -target=wasip1` (WASI program)   (tgo-wasic)
 *   - `wasmtk run   --lang=go [path]`  → build wasip1, then `wasmtk run` it              (tgo-run)
 *   - `wasmtk modc  --lang=go [path]`  → `tinygo build -target=wasm` (browser WASM)      (tgo-modc)
 *   - `wasmtk init  --lang=go [dir]`   → scaffold go.mod + WASI main.go                  (tgo-init-wasi)
 *   - `wasmtk init  --lang=go --go-target=wasm [dir]` → scaffold browser main.go         (tgo-init-wasm)
 *
 * Backends (`--go-runtime`): `tinygo` (default, small) or `std` (standard `go`, large — full
 * runtime/GC). All builds use `-p 1 -no-debug -panic=trap` and local `TINYGO_CACHE`/`GOTMPDIR`,
 * matching the scripts.
 *
 * wasm-opt: TinyGo runs binaryen's `wasm-opt` internally (`--asyncify -Oz`). `--asyncify` is
 * mandatory codegen for goroutines, not optimization. If a real `wasm-opt` is present (PATH /
 * $WASMOPT) wasmtk lets TinyGo use it (full support incl. goroutines). If not, wasmtk supplies a
 * passthrough `wasm-opt` shim, builds with `-scheduler=none` (no asyncify), and optimizes the
 * result with binaryen-ts `-Oz` instead — no external binaryen, goroutine-FREE code only. (Native
 * goroutine support without binaryen needs an asyncify pass in binaryen-ts — roadmap future item.)
 *
 * Scope (v1, numerics-first): command-mode (`func main`). Go string/aggregate HOST bindings
 * (bindgen) are deferred (ABI forward-alignment).
 */

import { basename, dirname, join, resolve } from "@std/path";
import { rt } from "./rt.ts";
import { binaryenOptimize } from "./binaryen.ts";

export type GoRuntime = "tinygo" | "std";
// wasip1 = WASI command (_start); wasm = browser (syscall/js); reactor = WASI library
// (`-buildmode=c-shared`: no _start, exports //go:wasmexport funcs + runtime, callable via
// `wasmtk mod` / bindgen — the Go analog of TS `modc` library mode).
export type GoTarget = "wasip1" | "wasm" | "reactor";
export type GoScaffold = "library" | "browser";

export interface GoCompileOptions {
  outPath?: string;
  runtime?: GoRuntime; // default "tinygo"
  target?: GoTarget; // default "wasip1"
}

type GoResult = { success: boolean; outputPath?: string; error?: string };

/** Decodes captured stderr+stdout from a piped rt.Command result into one diagnostic string. */
function decodeOut(r: { stdout: Uint8Array; stderr: Uint8Array }): string {
  const dec = new TextDecoder();
  return [dec.decode(r.stderr), dec.decode(r.stdout)].filter((s) => s.trim().length > 0).join("\n");
}

/**
 * Actionable hint appended to a failed Go build, derived from the error text + target. Turns raw
 * toolchain errors into next-step guidance so users aren't surprised. Currently covers the common
 * "imports `syscall/js` under a non-browser target" case (a browser-only file built as the default
 * WASI reactor library): syscall/js only has Go files for the browser (`GOOS=js`) target, so a
 * wasip1/reactor build reports "build constraints exclude all Go files in .../syscall/js".
 */
function goBuildHint(errText: string, target: GoTarget): string {
  if (target !== "wasm" && /syscall\/js/i.test(errText)) {
    return "\n   This code imports `syscall/js`, which only builds for the browser target. " +
      "`modc --lang=go` builds a WASI reactor library by default (no syscall/js).\n" +
      "   • For a browser module:  wasmtk modc --lang=go <path> --go-target=wasm\n" +
      "   • For a WASI library:    remove `syscall/js` — use //go:wasmexport functions (a plain " +
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
 *  `-o`/`--output` target with NO optimization (binaryen-ts does the -Oz afterwards). */
const SHIM_TS = String.raw`
const args = Deno.args;
if (args.includes("--version") || args.includes("-version")) {
  console.log("wasm-opt version 116 (wasmtk binaryen-ts passthrough shim)");
  Deno.exit(0);
}
let out = "", input = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "-o" || args[i] === "--output") { out = args[i + 1] ?? ""; i++; }
}
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "-o" || a === "--output") { i++; continue; }
  if (a.startsWith("-")) continue;
  if (a !== out) input = a; // last non-flag, non-output positional = input
}
try {
  await Deno.copyFile(input, out);
} catch (e) {
  console.error("wasmtk wasm-opt shim: copy failed in=" + input + " out=" + out + " " + e);
  Deno.exit(1);
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
  const deno = rt.execPath(); // the deno (or bun) binary running wasmtk — no reliance on PATH
  let launcher: string;
  if (rt.build.os === "windows") {
    launcher = join(tmp, "wasm-opt.cmd");
    await rt.writeTextFile(launcher, `@echo off\r\n"${deno}" run -A "${shimPath}" %*\r\n`);
  } else {
    launcher = join(tmp, "wasm-opt");
    await rt.writeTextFile(launcher, `#!/bin/sh\nexec "${deno}" run -A "${shimPath}" "$@"\n`);
    try {
      await Deno.chmod(launcher, 0o755);
    } catch { /* Bun / non-Deno: best effort */ }
  }
  return {
    launcher,
    cleanup: async () => {
      try {
        await Deno.remove(tmp, { recursive: true });
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
 * Compiles Go to a wasm module. `target` "wasip1" → WASI core module (runnable via `wasmtk run`);
 * "wasm" → browser module (syscall/js; needs wasm_exec.js + a browser).
 */
export async function compileGoWasi(input: string, opts: GoCompileOptions = {}): Promise<GoResult> {
  const runtime: GoRuntime = opts.runtime ?? "tinygo";
  const target: GoTarget = opts.target ?? "wasip1";
  const { baseDir, buildArg, name } = await resolveBuild(input);
  const out = opts.outPath ?? join(baseDir, `${name}.wasm`);
  const r = runtime === "std"
    ? await buildWithStd(baseDir, buildArg, out, target)
    : await buildWithTinyGo(baseDir, buildArg, out, target);
  if (r.success && target === "wasm") await copyWasmExecJs(baseDir, runtime);
  return r;
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
  // reactor (WASI library) builds wasip1 + `-buildmode=c-shared`; everything else maps directly.
  const tgoTarget = target === "wasm" ? "wasm" : "wasip1";
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

  const haveRealWasmOpt = !!rt.env.get("WASMOPT") || await toolAvailable("wasm-opt", ["--version"]);

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

  // No real wasm-opt → passthrough shim + -scheduler=none (skip mandatory asyncify) + binaryen-ts -Oz.
  const shim = await writeWasmOptShim(baseDir);
  try {
    const r = await new rt.Command("tinygo", {
      args: [
        "build",
        "-p",
        "1",
        "-scheduler=none",
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
      const goroutineIssue = /scheduler|goroutine|asyncify|channel/i.test(errText);
      const grHint = goroutineIssue
        ? "\n   This program appears to use goroutines/channels, which need TinyGo's asyncify " +
          "transform (real `wasm-opt`). Install binaryen (e.g. `scoop install binaryen` / " +
          "`brew install binaryen`) so wasm-opt is on PATH, then rebuild. (Roadmap: 'asyncify pass " +
          "in binaryen-ts'.)"
        : "";
      const hint = goBuildHint(errText, target) + grHint;
      console.error(`❌ wasmtk (go): TinyGo build failed:\n${errText}${hint}`);
      return { success: false, error: "tinygo build failed" };
    }
  } finally {
    await shim.cleanup();
  }
  try {
    const { bytes, optimized } = binaryenOptimize(await rt.readFile(out));
    if (optimized) await rt.writeFile(out, bytes);
    return await report(out, `tinygo:${reportLabel}${optimized ? " + binaryen-ts -Oz" : ""}`);
  } catch {
    return await report(out, `tinygo:${reportLabel}`);
  }
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
  console.warn(
    "   ⚠️  --go-runtime=std uses the full Go runtime/GC — output is large (often several MB). " +
      "TinyGo (the default) produces far smaller modules.",
  );
  // wasip1 → GOOS=wasip1; browser wasm → GOOS=js. Both GOARCH=wasm. reactor = wasip1 library
  // via `-buildmode=c-shared` (std Go 1.24+ supports //go:wasmexport for wasip1 in this mode).
  const goos = target === "wasm" ? "js" : "wasip1";
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

/** Copies the toolchain's wasm_exec.js next to a browser build (best effort). */
async function copyWasmExecJs(baseDir: string, runtime: GoRuntime): Promise<void> {
  try {
    let root = "";
    if (runtime === "tinygo") {
      const r = await new rt.Command("tinygo", {
        args: ["env", "TINYGOROOT"],
        stdout: "piped",
        stderr: "piped",
      })
        .output();
      if (r.success) root = new TextDecoder().decode(r.stdout).trim();
    } else {
      const r = await new rt.Command("go", {
        args: ["env", "GOROOT"],
        stdout: "piped",
        stderr: "piped",
      })
        .output();
      if (r.success) root = new TextDecoder().decode(r.stdout).trim();
    }
    if (!root) return;
    const candidates = runtime === "tinygo"
      ? [join(root, "targets", "wasm_exec.js")]
      : [join(root, "lib", "wasm", "wasm_exec.js"), join(root, "misc", "wasm", "wasm_exec.js")];
    for (const c of candidates) {
      try {
        const data = await rt.readFile(c);
        await rt.writeFile(join(baseDir, "wasm_exec.js"), data);
        console.log(
          `   wasm_exec.js: ${join(baseDir, "wasm_exec.js")} (load with the .wasm in a browser)`,
        );
        return;
      } catch { /* try next */ }
    }
  } catch { /* best effort — skip silently */ }
}

/**
 * Scaffolds a Go project: `go mod init <dirname>` + a boilerplate main.go. Default is a **wasm
 * library** (`//go:wasmexport` functions + a `func main` test harness); `"browser"` is the
 * syscall/js variant. The library scaffold is the default precisely because the Go producer's
 * primary output is a wasm library (`modc --lang=go`) — no flag should be needed for it.
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
    scaffold === "browser"
      ? `Initializing Go browser WASM project: ${name}`
      : `Initializing Go wasm library project: ${name}`,
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
    await rt.writeTextFile(mainPath, scaffold === "browser" ? MAIN_GO_BROWSER : MAIN_GO_LIBRARY);
    console.log(`   wrote ${mainPath}`);
  }
  if (scaffold === "browser") {
    // Browser scaffold uses syscall/js → needs --go-target=wasm (modc's default is a wasm library).
    console.log(`   Build: wasmtk modc --lang=go ${baseDir} --go-target=wasm`);
  } else {
    console.log(`   Test:  wasmtk run  --lang=go ${baseDir}   (runs func main as a test harness)`);
    console.log(
      `   Build: wasmtk modc --lang=go ${baseDir}   (→ wasm library; exports //go:wasmexport funcs)`,
    );
  }
  return { success: true, outputPath: baseDir };
}

// Default scaffold: a wasm LIBRARY (exports + a test harness in one file). Build it with
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

const MAIN_GO_BROWSER = `package main

import "syscall/js"

// square is exported from the compiled WASM module.
//
// ` + "`//go:wasmexport <name>`" + ` (TinyGo) marks a function for raw WASM export — callable
// from JavaScript as ` + "`instance.exports.square(...)`" + `. Put the directive on the line
// DIRECTLY above the function (no blank line between it and "func"); ONLY annotated functions
// are exported. Use WASM-friendly types (int32 / int64 / float32 / float64 / bool). (For the
// JS-bridge style instead, expose functions with js.Global().Set("name", js.FuncOf(...)).)
//
//go:wasmexport square
func square(x int32) int32 {
	return x * x
}

// main runs when the module is loaded in the browser (via wasm_exec.js).
func main() {
	println("WASM Initialized")
	alert := js.Global().Get("alert")
	alert.Invoke("Hello from the Browser!")
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
