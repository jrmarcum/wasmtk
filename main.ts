/**
 * @module main
 * @description The primary CLI entry point for wasmtk.
 * * Supports a comprehensive suite of WebAssembly development tools:
 * - `modc`: AssemblyScript library compilation (asc)
 * - `wasic`: WASI module compilation (Javy)
 * - `run`: Multi-format execution (.wasm, .wat, .js, .ts)
 * - `info`: Module inspection
 * - `wasm2js`: JS porting
 * - `convert`: Format toggling
 * - `bundle`: TS bundling
 */

import { parseArgs } from "@std/cli/parse-args";
import {
  VERSION,
  compileModule,
  runWasi,
  callExport,
  showInfo,
  checkIsLibrary,
  wasm2js,
  compileJavy,
  compileWasi,
  convertFile,
  bundleTs
} from "./utils.ts";

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
    },
    boolean: ["version", "help"],
    string: ["name"],
  });

  if (args.version) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  const command = args._[0] as string;
  const target = args._[1] as string;
  const outPath = args.name as string | undefined;

  if (args.help || !command || !target) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>        Compile a TypeScript file to a WASM library (asc)
  wasmtk wasic <file.ts|.wat>  Compile to a standalone WASI module (no JS runtime, smaller output)
  wasmtk javyc <file.ts>       Compile a TypeScript file to a WASI module via Javy/QuickJS
  wasmtk run <file>            Run a standalone .wasm, .wat, .js, or .ts WASI module
  wasmtk mod <file> [fn] [...] Call a function in a WASM library module (no fn = list functions)
  wasmtk info <file>           Show callable WASM functions in .wasm or .wat library/module
  wasmtk wasm2js <file.wasm>   Convert .wasm -> .js based script
  wasmtk convert <file>        Convert .wasm -> .wat and .wat -> .wasm
  wasmtk bundle <file.ts>      Bundle a .ts project to a single .js file

Options:
  -v, -V, --version            Show version information
  -h, --help                   Show this help message
  -n, --name <path>            Output file path (e.g. dist/mymodule.wasm)
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
        console.log(`✅ Module loaded. To call a function, use: wasmtk mod ${target} <function> [args...]`);
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
    case "bundle":
      await bundleTs(target, outPath ?? target.replace(/\.ts$/, ".js"));
      break;
    default:
      console.error(`❌ Unknown command: ${command}`);
      Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}