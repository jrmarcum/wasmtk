/**
 * @module main
 * @description The primary CLI entry point for wasmtk.
 * Supports a comprehensive suite of WebAssembly development tools:
 * - `wasic`: Direct TypeScript-to-WASM compiler (no embedded JS runtime)
 * - `modc`: WASM library module compilation (TypeScript → WASM, no _start entry point)
 * - `dync`: Fully-dynamic TS/JS → self-contained WASI module via wasmtk's own runtime (no Javy/QuickJS)
 * - `bindgen`: TypeScript host binding generator from WIT interface files
 * - `hybrid`: TypeScript/WASM split compiler (// @wasm annotations)
 * - `jstyper`: Convert .js + .d.ts pairs to typed .ts for wasic compilation
 * - `run`: Multi-format execution (.wasm, .wat, .js, .ts)
 * - `convert`: Format toggling (.wasm ↔ .wat)
 * - `tsbundle`: TypeScript multi-file bundler
 * - `wasmbundle`: Bundle multiple .wasm files into a single library
 */

import { parseArgs } from "@std/cli/parse-args";
import { join } from "@std/path";
import {
  bundleTs,
  callExport,
  convertFile,
  runWasi,
  showInfo,
  VERSION,
  wasm2js,
} from "./src/utils.ts";
import { rt } from "./src/rt.ts";
// Imported from their defining modules, not re-exported through utils.ts — the same pattern as
// compileDyn below. `./wasic` and `./modc` are the documented public homes for these two (see the
// README's Programmatic API table); routing them through utils.ts published the same declaration
// from two entrypoints for no benefit. See design-decisions.md § JSR doc coverage.
import { compileWasi } from "./src/wasic.ts";
import { compileModule } from "./src/modc.ts";
import { compileDyn } from "./src/dync.ts";
import { runJstyper } from "./src/jstyper.ts";
import { runBindgen } from "./src/bindgen.ts";
import { runHybrid } from "./src/hybrid.ts";

/** True if `path` exists (file or dir). */
async function pathExists(path: string): Promise<boolean> {
  try {
    await rt.stat(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * Detects the producer language for a `wasmtk run` target so it auto-routes without `--lang`:
 * `.go` file or a dir with `go.mod` → "go"; `.zig` file → "zig"; `.rs` file or a dir with
 * `Cargo.toml` → "rust"; otherwise null. Kept here — not in the producer modules — so a plain
 * `wasmtk run x.wasm` never imports a producer module (which pulls in binaryen / shells a toolchain)
 * just to make this decision; the producer module is loaded lazily only once a language is detected.
 */
async function detectRunLang(target: string): Promise<"go" | "zig" | "rust" | null> {
  if (target.endsWith(".go")) return "go";
  if (target.endsWith(".zig")) return "zig";
  if (target.endsWith(".rs")) return "rust";
  try {
    const st = await rt.stat(target) as { isDirectory: boolean | (() => boolean) };
    const isDir = typeof st.isDirectory === "function" ? st.isDirectory() : !!st.isDirectory;
    if (!isDir) return null;
    if (await pathExists(join(target, "go.mod"))) return "go";
    if (await pathExists(join(target, "Cargo.toml"))) return "rust";
    return null;
  } catch {
    return null;
  }
}

/**
 * Main entry point for the wasmtk CLI application.
 * Orchestrates command routing and handles intelligent UX for WASM library execution.
 * @returns {Promise<void>}
 */
async function main(): Promise<void> {
  // Ensure UTF-8 output on Windows so emojis and box-drawing characters render correctly.
  // SetConsoleOutputCP(65001) sets the console to UTF-8 at the Windows API level.
  // chcp is insufficient as Deno writes directly to the console handle, bypassing the code page.
  if (Deno.build.os === "windows") {
    try {
      const kernel32 = Deno.dlopen("kernel32.dll", {
        SetConsoleOutputCP: { parameters: ["u32"], result: "bool" },
      });
      kernel32.symbols.SetConsoleOutputCP(65001);
      kernel32.close();
    } catch { /* FFI unavailable in this build — silently continue */ }
  }

  const args = parseArgs(Deno.args, {
    alias: {
      v: "version",
      V: "version",
      h: "help",
      n: "name",
      o: "name",
    },
    boolean: ["version", "help", "dts-only", "dry-run", "auto", "verbose"],
    string: [
      "name",
      "on-conflict",
      "alias",
      "any-policy",
      "runtime",
      "lang",
      "go-runtime",
      "go-target",
    ],
  });

  if (args.version) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  const command = args._[0] as string;
  const target = args._[1] as string;
  const outPath = args.name as string | undefined;

  // Producer commands (--lang=go|zig) accept an optional path (default = current dir), so they don't
  // require a positional target the way the TS commands do. `wasic` is kept here only so that
  // `wasmtk wasic --lang=go` reaches its handler and prints the "removed — use `run --lang=go`"
  // message rather than falling through to the generic help screen.
  const langLower = (args.lang as string | undefined)?.toLowerCase();
  // Shared producer verbs work for go/zig/rust; the rust-exclusive verbs delegate to rsxtk and are
  // implicitly Rust (no --lang needed — Rust is the only producer that uses them). All accept an
  // optional path (default = cwd), so they must not fall through to the help screen when bare.
  const sharedProducerVerbs = new Set(["init", "initmod", "build", "modc", "run"]);
  const rustExclusiveVerbs = new Set(["add", "remove", "list", "fmt", "clean"]);
  const isProducerCmd = ((langLower === "go" || langLower === "zig" || langLower === "rust") &&
    sharedProducerVerbs.has(command)) ||
    rustExclusiveVerbs.has(command) ||
    (langLower === "go" && command === "wasic");

  if (args.help || !command || (!target && command !== "wasmbundle" && !isProducerCmd)) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>                   Compile a TypeScript file to a WASM library
  wasmtk wasic <file.ts|.wat>             Compile to a standalone WASI module (no JS runtime, smaller output)
  Producers — Go / Zig / Rust. run/build/modc AUTO-DETECT the language from the file
  (.go/.zig/.rs) or dir (go.mod/Cargo.toml), so --lang is optional; init/initmod need --lang:
  wasmtk init    --lang=go|zig|rust [dir]   Scaffold a WASI PROGRAM project (entry point; run/build it)
  wasmtk initmod --lang=go|zig|rust [dir]   Scaffold a wasm LIBRARY project (exported functions, no entry point)
  wasmtk build   [--lang=…] <path>          Build a WASI program → standalone .wasm (no run)
  wasmtk modc    [--lang=…] <path>          Build a wasm LIBRARY (callable via wasmtk mod)
  wasmtk run     [--lang=…] <path>          Build + run a WASI program (e.g. wasmtk run hello.go)
     Go:   --go-target=wasm-unknown → mergeable leaf library · --go-runtime=std → standard Go toolchain
     Rust: also add|remove|list (deps) · fmt · clean  — Rust-only, delegated to rsxtk (no --lang needed)
  wasmtk dync <file.ts>                   Compile a fully-dynamic TS/JS file to a self-contained WASI module via wasmtk's own runtime (no Javy)
  wasmtk run <file>                       Run a .wasm, .wat, .js, .ts, .go, .zig, or .rs file (Go/Zig/Rust auto-detected)
  wasmtk mod <file> [fn] [...]            Call a function in a WASM library module (no fn = list functions)
  wasmtk info <file>                      Show callable WASM functions in .wasm or .wat library/module
  wasmtk wasm2js <file.wasm>              Convert .wasm -> .js based script
  wasmtk convert <file>                   Convert .wasm -> .wat and .wat -> .wasm
  wasmtk wast <file.wast|dir> [--verbose]  Run WebAssembly .wast spec-script assertions (conformance)
  wasmtk tsbundle <file.ts>               Bundle a .ts project to a single .ts file (inlines all imports)
  wasmtk wasmbundle <a.wasm> [b.wasm...]  Bundle multiple .wasm files into a single library
  wasmtk jstyper <file.js>               Convert .js + .d.ts to typed .ts for wasic compilation
  wasmtk bindgen <file.wit>              Generate TypeScript host bindings from a .wit interface file
  wasmtk hybrid <file.ts>               Split into a WASM core (// @wasm functions) + TypeScript runner

Options:
  -v, -V, --version            Show version information
  -h, --help                   Show this help message
  -n, -o, --name <path>        Output file path (e.g. dist/mymodule.wasm or bindings.ts)
      --on-conflict=prefix     (wasmbundle) Auto-prefix conflicting exports with module name
      --on-conflict=alias      (wasmbundle) Auto-prefix conflicting exports with --alias values
      --on-conflict=exclude    (wasmbundle) Auto-exclude conflicting exports
      --alias a.wasm=x,...     (wasmbundle) Alias prefixes for conflict resolution
      --dts-only               (jstyper) Generate skeleton .d.ts instead of .ts
      --dry-run                (jstyper) Print output to stdout, don't write files
      --any-policy=skip|warn|default  (jstyper) How to handle 'any' typed params/returns
      --runtime=deno|node|bun  (bindgen) Target runtime for generated binding (default: deno)
      -o, --name <dir>         (hybrid)  Output directory for generated files (default: same as input)
      --auto                   (hybrid)  Route every statically-typed function to WASM by type
                                         (no // @wasm needed); dynamic/async/any stay in TS host
      --lang=go|zig|rust       Force the producer language. REQUIRED for init/initmod; OPTIONAL for
                               run/build/modc (auto-detected from .go/.zig/.rs or go.mod/Cargo.toml).
                               (add/remove/list/fmt/clean are Rust-only — no --lang needed.)
      --go-runtime=tinygo|std  (go)      Go backend: tinygo (default, small) or std go (large).
                                         TinyGo without wasm-opt installed auto-uses binaryen -Oz
                                         (goroutine-free code); goroutine code needs binaryen.
      --go-target=wasm-unknown (modc)    Build an alloc-free MERGEABLE leaf library (wasmmerge-able into a wasic/bundle build)
                                         (browser/syscall/js output is not produced — use the universal wasm loader)
    `);
    return;
  }

  const lang = (args.lang as string | undefined)?.toLowerCase();
  const goRuntime = ((args["go-runtime"] as string | undefined)?.toLowerCase() === "std")
    ? "std"
    : "tinygo";
  const langPath = target ?? "."; // producer commands default to the current directory

  // For run/build/modc the producer language is either explicit (--lang) or **auto-detected** from
  // the target (a `.go`/`.zig`/`.rs` file, or a directory with go.mod/Cargo.toml) — so `--lang` is
  // OPTIONAL for those verbs. Scaffolding (init/initmod) still needs --lang (there's no file to
  // detect from). `effLang` is the resolved producer language used by run/build/modc + delegateRust.
  const autoDetectVerb = command === "run" || command === "build" || command === "modc";
  const effLang: string | undefined = (lang === "go" || lang === "zig" || lang === "rust")
    ? lang
    : (autoDetectVerb ? (await detectRunLang(langPath)) ?? undefined : undefined);

  // Args to forward to rsxtk: the raw CLI args minus the wasmtk command token and any --lang flag,
  // so rsxtk's own positional args AND flags pass straight through.
  const rsxtkForwardArgs = (): string[] => {
    const out: string[] = [];
    let droppedCommand = false;
    for (let i = 0; i < Deno.args.length; i++) {
      const a = Deno.args[i];
      if (a === "--lang") {
        i++;
        continue;
      } // "--lang rust"
      if (a.startsWith("--lang=")) continue; // "--lang=rust"
      if (!droppedCommand && a === command) {
        droppedCommand = true;
        continue;
      }
      out.push(a);
    }
    return out;
  };

  // Delegate a Rust verb to the matching rsxtk subcommand (requires --lang=rust). `extraArgs` are
  // appended after the forwarded args — used to supply rsxtk `build`'s TARGET (wasm/wasi) so
  // `modc`/`build` carry their library/program meaning without the user typing the target.
  const delegateRust = async (subcommand: string, extraArgs: string[] = []): Promise<void> => {
    // Rust-exclusive verbs (add/remove/list/fmt/clean) are implicitly Rust — no --lang required.
    // For the shared verbs (init/initmod/modc/build), Rust must be explicit or auto-detected.
    if (effLang !== "rust" && !rustExclusiveVerbs.has(command)) {
      console.error(`❌ wasmtk: \`${command}\` is a Rust producer command — use --lang=rust.`);
      Deno.exit(1);
    }
    const { runRust } = await import("./src/rustwasic.ts");
    const r = await runRust(subcommand, [...rsxtkForwardArgs(), ...extraArgs]);
    if (!r.success) Deno.exit(1);
  };

  // Browser (syscall/js) Go output is no longer produced: consume wasmtk's WASI modules with the
  // universal wasm loader instead. `--go-target=wasm` on init/modc surfaces this pointer.
  const goBrowserRemoved = (): never => {
    console.error(
      "❌ wasmtk: `--go-target=wasm` (browser / syscall/js) output is no longer produced.\n" +
        "   wasmtk builds WASI modules — load them in the browser with the universal wasm loader\n" +
        "   (`@jrmarcum/universal-wasm-loader`) alongside the .wasm/.wit you produce here.\n" +
        "   For a mergeable library use `--go-target=wasm-unknown`; for a reactor library, plain `modc`.",
    );
    Deno.exit(1);
  };

  switch (command) {
    case "init": {
      // `init` scaffolds a WASI PROGRAM for every producer (the Rust model). A wasm LIBRARY is
      // scaffolded with `initmod`.
      if (lang === "rust") {
        await delegateRust("init"); // rsxtk's wasi script/program template
        break;
      }
      if (lang === "zig") {
        const { scaffoldZigProject } = await import("./src/zigwasic.ts");
        const r = await scaffoldZigProject(langPath, "program");
        if (!r.success) Deno.exit(1);
        break;
      }
      if (lang !== "go") {
        console.error("❌ wasmtk: `init` supports `--lang=go`, `--lang=zig`, or `--lang=rust`.");
        Deno.exit(1);
      }
      if ((args["go-target"] as string | undefined)?.toLowerCase() === "wasm") goBrowserRemoved();
      const { scaffoldGoProject } = await import("./src/gowasic.ts");
      const r = await scaffoldGoProject(langPath, "program");
      if (!r.success) Deno.exit(1);
      break;
    }
    case "modc":
      // Producer language is explicit (--lang) or auto-detected from the file/dir; a `.ts` input
      // (no producer detected) is the TypeScript library compiler.
      if (effLang === "rust") {
        // `modc --lang=rust <path>` → `rsxtk build <path> wasm` (library/universal wasm). The wasi
        // *program* build is `build --lang=rust` (→ `rsxtk build <path> wasi`).
        await delegateRust("build", ["wasm"]);
        break;
      }
      if (effLang === "zig") {
        // `modc --lang=zig` builds a freestanding wasm LIBRARY: exports the `export fn` functions,
        // no `_start`/WASI — callable via `wasmtk mod`/bindgen, the Zig analog of TS `modc`.
        const { compileZig } = await import("./src/zigwasic.ts");
        const r = await compileZig(langPath, { outPath, target: "library" });
        if (!r.success) Deno.exit(1);
        break;
      }
      if (effLang === "go") {
        // `modc --lang=go` builds a WASI reactor LIBRARY by default (`-buildmode=c-shared`): no
        // _start, exports the `//go:wasmexport` functions + runtime, callable via `wasmtk mod` /
        // bindgen — the Go analog of TS `modc` library mode. `--go-target=wasm-unknown` builds the
        // alloc-free MERGEABLE leaf instead. (Browser output — `--go-target=wasm` — is not produced.)
        const goTgt = (args["go-target"] as string | undefined)?.toLowerCase();
        if (goTgt === "wasm") goBrowserRemoved();
        const goModcTarget = (goTgt === "wasm-unknown" || goTgt === "leaf") ? "leaf" : "reactor";
        const { compileGoWasi } = await import("./src/gowasic.ts");
        const r = await compileGoWasi(langPath, {
          outPath,
          runtime: goRuntime,
          target: goModcTarget,
        });
        if (!r.success) Deno.exit(1);
        break;
      }
      await compileModule(target, outPath);
      break;
    case "wasic":
      if (lang === "go") {
        // Direct Go→WASI compilation was removed as a standalone command (2026-06-07): the Go WASI
        // output isn't consumable by wasmtk's merge/bundle pipeline (heap-using Go can't be merged —
        // see cmem/polyglot-producers.md). The Go→wasip1 build still lives in `run --lang=go`, which
        // needs it to execute the module. Surface a clear pointer instead of a cryptic .ts error.
        console.error(
          "❌ wasmtk: `wasmtk wasic --lang=go` has been removed.\n" +
            "   Direct Go→WASI compilation is no longer a standalone command — the Go WASI output\n" +
            "   isn't consumable by wasmtk's merge/bundle pipeline (heap-using Go can't be merged).\n" +
            "   To build and run a Go WASI module in one step, use:\n" +
            "       wasmtk run <file.go>   (language auto-detected; or a dir with go.mod)\n" +
            "   (For a callable library: wasmtk modc <file.go>.)",
        );
        Deno.exit(1);
      }
      await compileWasi(target, outPath);
      break;
    case "dync":
      await compileDyn(target, outPath);
      break;
    case "run": {
      // Auto-detect producer source so `wasmtk run foo.go` / `foo.zig` / `./pkg` (dir w/ go.mod)
      // builds + runs without needing `--lang`. The explicit flag still works (incl. bare cwd via
      // langPath = "."). Producer build → run on wasmtk's TS WASI host. Detection is in main.ts so a
      // plain `wasmtk run x.wasm` never loads a producer module.
      const runLang = effLang;
      if (runLang === "go") {
        const { compileGoWasi } = await import("./src/gowasic.ts");
        const r = await compileGoWasi(langPath, { outPath, runtime: goRuntime, target: "wasip1" });
        if (!r.success || !r.outputPath) Deno.exit(1);
        await runWasi(r.outputPath, args._.slice(2).map(String));
        break;
      }
      if (runLang === "zig") {
        const { compileZig } = await import("./src/zigwasic.ts");
        const r = await compileZig(langPath, { outPath, target: "wasi" });
        if (!r.success || !r.outputPath) Deno.exit(1);
        await runWasi(r.outputPath, args._.slice(2).map(String));
        break;
      }
      if (runLang === "rust") {
        // Delegate fully to rsxtk (build + run via its wasmtime runner). Works with --lang=rust or
        // auto-detected `.rs` / `Cargo.toml`.
        const { runRust } = await import("./src/rustwasic.ts");
        const r = await runRust("run", rsxtkForwardArgs());
        if (!r.success) Deno.exit(1);
        break;
      }
      // A directory reached here means no producer project was auto-detected in it (no `go.mod` /
      // `Cargo.toml`) — a directory isn't a runnable module, so surface a clear error instead of a
      // cryptic "failed to instantiate" from trying to run it as `.wasm`.
      if (typeof target === "string") {
        let targetIsDir = false;
        try {
          const st = await rt.stat(target) as { isDirectory: boolean | (() => boolean) };
          targetIsDir = typeof st.isDirectory === "function" ? st.isDirectory() : !!st.isDirectory;
        } catch { /* not found — let runWasi report the missing path */ }
        if (targetIsDir) {
          console.error(
            `❌ wasmtk run: '${target}' is a directory, but no Go or Rust project was found in it ` +
              `(expected a go.mod or Cargo.toml).\n` +
              `   Point run at a project directory, or at a .wasm / .wat / .ts / .js / .go / .zig / .rs file.`,
          );
          Deno.exit(1);
        }
      }
      await runWasi(target, []);
      break;
    }
    case "mod": {
      const fn = args._[2] as string | undefined;
      if (fn) {
        await callExport(target, fn, args._.slice(3).map(String));
      } else {
        console.log(
          `✅ Module loaded. To call a function, use: wasmtk mod ${target} <function> [args...]`,
        );
        await showInfo(target);
      }
      break;
    }
    case "info":
      await showInfo(target);
      break;
    case "wasm2js":
      // Exit non-zero on failure. Both of these used to swallow the result, so a failed conversion
      // printed an error and still exited 0 — invisible to any caller checking $?.
      if (!(await wasm2js(target, outPath))) Deno.exit(1);
      break;
    case "convert":
      if (!(await convertFile(target, outPath))) Deno.exit(1);
      break;
    case "wast": {
      // Run the WebAssembly `.wast` spec-script assertions (a file or a directory tree).
      if (!target) {
        console.error("❌ wasmtk wast: expected a .wast file or directory");
        Deno.exit(1);
      }
      const { wastCli } = await import("./src/wast.ts");
      const code = await wastCli(target, { verbose: args.verbose as boolean | undefined });
      Deno.exit(code);
      break;
    }
    case "tsbundle":
      await bundleTs(target, outPath ?? target.replace(/\.ts$/, ".bundled.ts"));
      break;
    case "jstyper": {
      const anyPolicyRaw = args["any-policy"] as string | undefined;
      const anyPolicy =
        anyPolicyRaw === "skip" || anyPolicyRaw === "warn" || anyPolicyRaw === "default"
          ? (anyPolicyRaw as "skip" | "warn" | "default")
          : "warn";
      await runJstyper(target, {
        dtsOnly: args["dts-only"] as boolean | undefined,
        dryRun: args["dry-run"] as boolean | undefined,
        anyPolicy,
        outPath,
      });
      break;
    }
    case "wasmbundle": {
      const { runWasmBundle } = await import("./src/wasmbundle.ts");
      const inputFiles = args._.slice(1).map(String);
      const bundleOut = outPath ?? "combined.wasm";
      const conflictFlag = args["on-conflict"] as string | undefined;
      const onConflict =
        conflictFlag === "prefix" || conflictFlag === "alias" || conflictFlag === "exclude"
          ? (conflictFlag as "prefix" | "alias" | "exclude")
          : undefined;
      const aliasStr = args["alias"] as string | undefined;
      const aliases = new Map<string, string>();
      if (aliasStr) {
        for (const pair of aliasStr.split(",")) {
          const eqIdx = pair.indexOf("=");
          if (eqIdx > 0) aliases.set(pair.slice(0, eqIdx).trim(), pair.slice(eqIdx + 1).trim());
        }
      }
      await runWasmBundle(inputFiles, bundleOut, onConflict, aliases);
      break;
    }
    case "bindgen": {
      const runtimeRaw = args["runtime"] as string | undefined;
      const runtime = runtimeRaw === "deno" || runtimeRaw === "node" || runtimeRaw === "bun"
        ? (runtimeRaw as "deno" | "node" | "bun")
        : "deno";
      await runBindgen(target, { outPath, runtime });
      break;
    }
    case "hybrid": {
      await runHybrid(target, { outDir: outPath, auto: args.auto === true });
      break;
    }
    // Rust producer commands (delegate to rsxtk; require --lang=rust).
    case "initmod":
      // `initmod` scaffolds a wasm LIBRARY (exports, no entry point) for every producer — the
      // counterpart to `init` (a WASI program). Mirrors the Rust producer's init/initmod split.
      if (lang === "rust") {
        await delegateRust("initmod");
      } else if (lang === "zig") {
        const { scaffoldZigProject } = await import("./src/zigwasic.ts");
        const r = await scaffoldZigProject(langPath, "library");
        if (!r.success) Deno.exit(1);
      } else if (lang === "go") {
        const { scaffoldGoProject } = await import("./src/gowasic.ts");
        const r = await scaffoldGoProject(langPath, "library");
        if (!r.success) Deno.exit(1);
      } else {
        console.error("❌ wasmtk: `initmod` supports `--lang=go`, `--lang=zig`, or `--lang=rust`.");
        Deno.exit(1);
      }
      break;
    case "build":
      // `build` compiles a WASI PROGRAM to a standalone `.wasm` (without running it) for every
      // producer — the Rust `build` verb, extended to Go (`wasip1`) and Zig (`wasm32-wasi`). The
      // producer is explicit (--lang) or auto-detected from the file/dir. (For a TypeScript program,
      // use `wasic`.)
      if (effLang === "rust") {
        await delegateRust("build", ["wasi"]); // → `rsxtk build <path> wasi`
      } else if (effLang === "zig") {
        const { compileZig } = await import("./src/zigwasic.ts");
        const r = await compileZig(langPath, { outPath, target: "wasi" });
        if (!r.success) Deno.exit(1);
      } else if (effLang === "go") {
        const { compileGoWasi } = await import("./src/gowasic.ts");
        const r = await compileGoWasi(langPath, { outPath, runtime: goRuntime, target: "wasip1" });
        if (!r.success) Deno.exit(1);
      } else {
        console.error(
          "❌ wasmtk: `build` needs a Go/Zig/Rust program — pass a .go/.zig/.rs file (auto-detected) " +
            "or `--lang=go|zig|rust`. (For a TypeScript program, use `wasmtk wasic`.)",
        );
        Deno.exit(1);
      }
      break;
    case "add":
      await delegateRust("add");
      break;
    case "remove":
      await delegateRust("remove");
      break;
    case "list":
      await delegateRust("list");
      break;
    case "fmt":
      await delegateRust("fmt");
      break;
    case "clean":
      await delegateRust("clean");
      break;
    default:
      console.error(`❌ Unknown command: ${command}`);
      Deno.exit(1);
  }
}

if (import.meta.main) {
  main().catch((err) => {
    // Surface thrown errors (e.g. an unsupported-merge diagnostic from wasmmerge) as a clean
    // one-line message with a non-zero exit, instead of an unhandled-rejection stack trace.
    console.error(`❌ wasmtk: ${err instanceof Error ? err.message : err}`);
    Deno.exit(1);
  });
}
