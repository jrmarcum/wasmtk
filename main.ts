/**
 * @module main
 * @description Command-line entry point for the wasmtk toolkit.
 */

import { parse } from "@std/flags";
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
 * Main entry point for the wasmtk CLI.
 * Handles commands: compile, run, info, wasm2js, wasi, convert, bundle.
 */
async function main(): Promise<void> {
  const args = parse(Deno.args);
  const command = args._[0];
  const target = args._[1] as string;

  if (args.version || args.v) {
    console.log(`wasmtk v${VERSION}`);
    return;
  }

  if (!command || !target) {
    console.log(`
wasmtk - WebAssembly Development Toolkit v${VERSION}

Usage:
  wasmtk compile <file.ts>     Compile AssemblyScript to library WASM
  wasmtk run <file.wasm>       Run WASM/WAT module (WASI supported)
  wasmtk info <file.wasm>      Show exported functions and info
  wasmtk wasm2js <file.wasm>   Convert WASM to standalone JS
  wasmtk wasi <file.ts>        Compile TS to WASI module (Javy)
  wasmtk convert <file>        Toggle between .wasm and .wat
  wasmtk bundle <file.ts>      Bundle TS to JS
    `);
    return;
  }

  switch (command) {
    case "compile":
      await compileModule(target);
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
    case "wasi":
      await compileWasi(target);
      break;
    case "convert":
      await convertFile(target);
      break;
    case "bundle":
      await bundleTs(target, target.replace(/\.ts$/, ".js"));
      break;
    default:
      console.error(`Unknown command: ${command}`);
  }
}

if (import.meta.main) {
  main();
}