/**
 * @module main
 * @description The primary command-line interface entry point for wasmtk.
 */

import { parseArgs } from "@std/cli/parse-args";
import { 
  VERSION, 
  compileModule, 
  runWasi, 
  showInfo, 
  checkIsLibrary, 
  wasm2js, 
  compileWasi, 
  convertFile, 
  bundleTs 
} from "./utils.ts";

/**
 * Main entry point for the wasmtk CLI application.
 * Handles routing of subcommands and displays help documentation.
 * @returns {Promise<void>}
 */
async function main(): Promise<void> {
  const args = parseArgs(Deno.args, {
    alias: { 
      v: "version",
      V: "version",
      h: "help" 
    },
    boolean: ["version", "help"],
  });

  // 1. Version Check
  if (args.version) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  const command = args._[0] as string;
  const target = args._[1] as string;

  // 2. Help/Usage Check - Updated with exact requested descriptions
  if (args.help || !command || !target) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk modc <file.ts>        Compile a Typescript file to a WASM library (asc)
  wasmtk wasic <file.ts>       Compile a Typescript file to a WASI module (Javy)
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

  // 3. Command Routing
  switch (command) {
    case "modc":
      await compileModule(target);
      break;
    case "wasic":
      await compileWasi(target);
      break;
    case "run": {
      const isLib = await checkIsLibrary(target);
      if (isLib) {
        console.log(`💡 Library module loaded. Use: wasmtk run ${target} <function> [args...]`);
        await showInfo(target);
        if (args._.length > 2) {
          await runWasi(target, args._.slice(2).map(String));
        }
      } else {
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