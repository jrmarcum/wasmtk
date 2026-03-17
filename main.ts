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
      h: "help" 
    },
    boolean: ["version", "help"],
  });

  if (args.version) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  const command = args._[0] as string;
  const target = args._[1] as string;

  if (args.help || !command || !target) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>        Compile a TypeScript file to a WASM library (asc)
  wasmtk wasic <file.ts|.wat>  Compile to a standalone WASI module (no JS runtime, smaller output)
  wasmtk javyc <file.ts>       Compile a TypeScript file to a WASI module via Javy/QuickJS
  wasmtk run <file>            Run .wasm, .wat, .js, .ts files, and run callable WASM module functions
  wasmtk info <file>           Show callable WASM functions in .wasm or .wat library/module
  wasmtk wasm2js <file.wasm>   Convert .wasm -> .js based script
  wasmtk convert <file>        Convert .wasm -> .wat and .wat -> .wasm
  wasmtk bundle <file.ts>      Bundle a .ts project to a single .js file

Options:
  -v, -V, --version            Show version information
  -h, --help                   Show this help message
    `);
    return;
  }

  switch (command) {
    case "modc":
      await compileModule(target);
      break;
    case "wasic":
      await compileWasi(target);
      break;
    case "javyc":
      await compileJavy(target);
      break;
    case "run": {
      const isLib = await checkIsLibrary(target);
      const hasFunctionCall = args._.length > 2;

      if (isLib) {
        if (hasFunctionCall) {
          // Executes the function directly without reprinting info
          await runWasi(target, args._.slice(2).map(String));
        } else {
          // Assists the user by showing available functions when none are specified
          console.log(`✅ Library module loaded. To execute a function, use: wasmtk run ${target} <function> [args...]`);
          await showInfo(target);
        }
      } else {
        // Runs standalone WASI binaries or scripts
        await runWasi(target, []);
      }
      break;
    }
    case "info":
      await showInfo(target);
      break;
    case "wasm2js":
      await wasm2js(target);
      break;
    case "convert":
      await convertFile(target);
      break;
    case "bundle":
      await bundleTs(target, target.replace(/\.ts$/, ".js"));
      break;
    default:
      console.error(`❌ Unknown command: ${command}`);
      Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}