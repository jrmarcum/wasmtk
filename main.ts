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
import { runJstyper } from "./src/jstyper.ts";
import { runBindgen } from "./src/bindgen.ts";
import { runHybrid } from "./src/hybrid.ts";

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
    string: ["name", "on-conflict", "alias", "any-policy", "runtime"],
  });

  if (args.version) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  const command = args._[0] as string;
  const target = args._[1] as string;
  const outPath = args.name as string | undefined;

  if (args.help || !command || (!target && command !== "wasmbundle")) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>                   Compile a TypeScript file to a WASM library
  wasmtk wasic <file.ts|.wat>             Compile to a standalone WASI module (no JS runtime, smaller output)
  wasmtk javyc <file.ts>                  Compile a TypeScript file to a WASI module via Javy/QuickJS
  wasmtk run <file>                       Run a .wasm, .wat, .js, or .ts file
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
    `);
    return;
  }

  switch (command) {
    case "modc":
      await compileModule(target, outPath);
      break;
    case "wasic":
      await compileWasi(target, outPath);
      break;
    case "javyc":
      await compileJavy(target, outPath);
      break;
    case "run":
      await runWasi(target, []);
      break;
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
