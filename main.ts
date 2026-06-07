/**
 * @module main
 * @description The primary CLI entry point for wasmtk.
 * Supports a comprehensive suite of WebAssembly development tools:
 * - `wasic`: Direct TypeScript-to-WASM compiler (no embedded JS runtime)
 * - `modc`: WASM library module compilation (TypeScript → WASM, no _start entry point)
 * - `javyc`: TypeScript/JavaScript via Javy/QuickJS embedded runtime
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
  compileJavy,
  compileModule,
  compileWasi,
  convertFile,
  runWasi,
  showInfo,
  VERSION,
  wasm2js,
} from "./src/utils.ts";
import { rt } from "./src/rt.ts";
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
    boolean: ["version", "help", "dts-only", "dry-run", "auto"],
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
  // Rust-only verbs delegate to rsxtk; the shared verbs (init/modc/run) work for go/zig/rust.
  const rustOnlyVerbs = new Set(["initmod", "build", "add", "remove", "list", "fmt", "clean"]);
  const isProducerCmd = ((langLower === "go" || langLower === "zig" || langLower === "rust") &&
    (command === "init" || command === "modc" || command === "run")) ||
    (langLower === "rust" && rustOnlyVerbs.has(command)) ||
    (langLower === "go" && command === "wasic");

  if (args.help || !command || (!target && command !== "wasmbundle" && !isProducerCmd)) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>                   Compile a TypeScript file to a WASM library
  wasmtk wasic <file.ts|.wat>             Compile to a standalone WASI module (no JS runtime, smaller output)
  wasmtk init  --lang=go [dir]            Scaffold a Go wasm library project (go.mod + main.go); --go-target=wasm for a browser project
  wasmtk modc  --lang=go [path]           Compile Go → WASI reactor library (callable via wasmtk mod/bindgen)
                                          (add --go-target=wasm for a browser module + wasm_exec.js)
  wasmtk run   --lang=go [path]           Build a Go WASI module (via TinyGo) and run it in one step
                                          (or just: wasmtk run <file.go> / <dir-with-go.mod> — auto-detected)
  wasmtk init  --lang=zig [dir]           Scaffold a Zig wasm library project (main.zig)
  wasmtk modc  --lang=zig [path]          Compile Zig → wasm library (freestanding; exports 'export fn' funcs)
  wasmtk run   --lang=zig [path]          Build a Zig WASI program (wasm32-wasi) and run it (or: wasmtk run <file.zig>)
  wasmtk init    --lang=rust [dir]        Scaffold a Rust wasi script/program   (delegates to rsxtk)
  wasmtk initmod --lang=rust [dir]        Scaffold a Rust library module        (delegates to rsxtk)
  wasmtk modc    --lang=rust [path]       Build a Rust wasm library              (delegates to rsxtk build)
  wasmtk build   --lang=rust [path]       Build a Rust wasi program             (delegates to rsxtk build)
  wasmtk run     --lang=rust [path]       Build + run a Rust wasi program       (rsxtk run; or: wasmtk run <file.rs>)
  wasmtk add|remove|list --lang=rust      Manage Rust dependencies              (delegates to rsxtk)
  wasmtk fmt|clean --lang=rust            Inject a manifest (fmt) · wipe the .tk cache (clean)  (rsxtk)
  wasmtk javyc <file.ts>                  Compile a TypeScript file to a WASI module via Javy/QuickJS
  wasmtk run <file>                       Run a .wasm, .wat, .js, .ts, .go, .zig, or .rs file (Go/Zig/Rust auto-detected)
  wasmtk mod <file> [fn] [...]            Call a function in a WASM library module (no fn = list functions)
  wasmtk info <file>                      Show callable WASM functions in .wasm or .wat library/module
  wasmtk wasm2js <file.wasm>              Convert .wasm -> .js based script
  wasmtk convert <file>                   Convert .wasm -> .wat and .wat -> .wasm
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
      --lang=go|zig|rust       (init/modc/run)  Treat the input as Go/Zig/Rust (path defaults to cwd)
                               (--lang=rust also enables: initmod build add remove list fmt clean — via rsxtk)
      --go-runtime=tinygo|std  (go)      Go backend: tinygo (default, small) or std go (large).
                                         TinyGo without wasm-opt installed auto-uses binaryen-ts -Oz
                                         (goroutine-free code); goroutine code needs binaryen.
      --go-target=wasm         (init)    Scaffold a browser (syscall/js) project instead of the default wasm library
      --go-target=wasm         (modc)    Build a browser module instead of the default wasm (reactor) library
    `);
    return;
  }

  const lang = (args.lang as string | undefined)?.toLowerCase();
  const goRuntime = ((args["go-runtime"] as string | undefined)?.toLowerCase() === "std")
    ? "std"
    : "tinygo";
  const langPath = target ?? "."; // producer commands default to the current directory

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
    if (lang !== "rust") {
      console.error(`❌ wasmtk: \`${command}\` is a Rust producer command — use --lang=rust.`);
      Deno.exit(1);
    }
    const { runRust } = await import("./src/rustwasic.ts");
    const r = await runRust(subcommand, [...rsxtkForwardArgs(), ...extraArgs]);
    if (!r.success) Deno.exit(1);
  };

  switch (command) {
    case "init": {
      if (lang === "rust") {
        // `init --lang=rust` → rsxtk's wasi script/program template; `initmod` is the library one.
        await delegateRust("init");
        break;
      }
      if (lang === "zig") {
        const { scaffoldZigProject } = await import("./src/zigwasic.ts");
        const r = await scaffoldZigProject(langPath);
        if (!r.success) Deno.exit(1);
        break;
      }
      if (lang !== "go") {
        console.error("❌ wasmtk: `init` supports `--lang=go`, `--lang=zig`, or `--lang=rust`.");
        Deno.exit(1);
      }
      const { scaffoldGoProject } = await import("./src/gowasic.ts");
      // Default scaffold is a wasm LIBRARY (the Go producer's primary output via `modc --lang=go`);
      // a browser project is opt-in via --go-target=wasm.
      const scaffold = (args["go-target"] as string | undefined)?.toLowerCase() === "wasm"
        ? "browser"
        : "library";
      const r = await scaffoldGoProject(langPath, scaffold);
      if (!r.success) Deno.exit(1);
      break;
    }
    case "modc":
      if (lang === "rust") {
        // `modc --lang=rust <path>` → `rsxtk build <path> wasm` (library/universal wasm). The wasi
        // *program* build is `build --lang=rust` (→ `rsxtk build <path> wasi`).
        await delegateRust("build", ["wasm"]);
        break;
      }
      if (lang === "zig") {
        // `modc --lang=zig` builds a freestanding wasm LIBRARY: exports the `export fn` functions,
        // no `_start`/WASI — callable via `wasmtk mod`/bindgen, the Zig analog of TS `modc`.
        const { compileZig } = await import("./src/zigwasic.ts");
        const r = await compileZig(langPath, { outPath, target: "library" });
        if (!r.success) Deno.exit(1);
        break;
      }
      if (lang === "go") {
        // `modc --lang=go` builds a WASI reactor LIBRARY by default (`-buildmode=c-shared`): no
        // _start, exports the `//go:wasmexport` functions + runtime, callable via `wasmtk mod` /
        // bindgen — the Go analog of TS `modc` library mode. The BROWSER build (`-target=wasm`,
        // syscall/js + wasm_exec.js) is opt-in via `--go-target=wasm` (it imports `gojs` and only
        // runs in a browser, so wasmtk can't host it).
        const goBrowser = (args["go-target"] as string | undefined)?.toLowerCase() === "wasm";
        const { compileGoWasi } = await import("./src/gowasic.ts");
        const r = await compileGoWasi(langPath, {
          outPath,
          runtime: goRuntime,
          target: goBrowser ? "wasm" : "reactor",
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
            "       wasmtk run --lang=go [path]\n" +
            "   (For a browser module: wasmtk modc --lang=go [path].)",
        );
        Deno.exit(1);
      }
      await compileWasi(target, outPath);
      break;
    case "javyc":
      await compileJavy(target, outPath);
      break;
    case "run": {
      // Auto-detect producer source so `wasmtk run foo.go` / `foo.zig` / `./pkg` (dir w/ go.mod)
      // builds + runs without needing `--lang`. The explicit flag still works (incl. bare cwd via
      // langPath = "."). Producer build → run on wasmtk's TS WASI host. Detection is in main.ts so a
      // plain `wasmtk run x.wasm` never loads a producer module.
      const runLang = (lang === "go" || lang === "zig" || lang === "rust")
        ? lang
        : (typeof target === "string" ? await detectRunLang(target) : null);
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
      await wasm2js(target, outPath);
      break;
    case "convert":
      await convertFile(target, outPath);
      break;
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
      await delegateRust("initmod");
      break;
    case "build":
      // `build --lang=rust <path>` → `rsxtk build <path> wasi` (a WASI program).
      await delegateRust("build", ["wasi"]);
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
