import { 
  compileWasi, 
  runWasi, 
  compileModule, 
  convertFile, 
  bundleTs, 
  showInfo,
  checkIsLibrary,
  wasm2js,
  VERSION 
} from "./utils.ts";

const [command, target, ...extraArgs] = Deno.args;

const helpMessage = `
wasmtk - WebAssembly Toolkit (v${VERSION})

Usage:
  wasmtk wasic <file.ts>   - Compile to WASI
  wasmtk run <file>        - Execute file (.wasm/.wat via WASI, .ts/.js via Deno)
  wasmtk info <file.wasm>  - Display WebAssembly module information
  wasmtk modc <file.ts>    - Compile to non-WASI module
  wasmtk convert <file>    - Convert between .wasm and .wat
  wasmtk wasm2js <file>    - Convert .wasm to .js
  wasmtk bundle <file.ts>  - Bundle TS to a single JS file (No shims)
  wasmtk --version, -v     - Show version
  wasmtk --help, -h        - Show help
`;

const validCommands = [
  "wasic", "run", "info", "modc", "convert", 
  "wasm2js", "bundle", "--version", "-v", "-V", "--help", "-h"
];

if (!command) {
  console.log(helpMessage);
  Deno.exit(0);
}

if (!validCommands.includes(command)) {
  console.error(`❌ Error: "${command}" is not a valid wasmtk command.`);
  Deno.exit(1);
}

if (["--help", "-h"].includes(command)) {
  console.log(helpMessage);
  Deno.exit(0);
}

if (["--version", "-v", "-V"].includes(command)) {
  console.log(`wasmtk v${VERSION}`);
  Deno.exit(0);
}

switch (command) {
  case "wasic":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    await compileWasi(target);
    break;

  case "info":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    await showInfo(target);
    break;

  case "modc":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    compileModule(target);
    break;

  case "convert":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    await convertFile(target);
    break;

  case "wasm2js":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    await wasm2js(target);
    break;

  case "bundle":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    await bundleTs(target, target.replace(/\.ts$/, ".js"));
    break;

  case "run":
    if (!target) { console.error("❌ Target missing."); Deno.exit(1); }
    
    if (target.endsWith(".ts") || target.endsWith(".js")) {
      const process = new Deno.Command(Deno.execPath(), {
        args: ["run", "-A", target, ...extraArgs],
      });
      await process.spawn().status;
    } else if (target.endsWith(".wasm") || target.endsWith(".wat")) {
      const isLib = await checkIsLibrary(target);
      if (isLib && extraArgs.length === 0) {
        console.log(`💡 Library module loaded. Use: wasmtk run ${target} <function> [args...]`);
        await showInfo(target);
      } else {
        await runWasi(target, extraArgs);
      }
    } else {
      console.error("❌ Unknown file type.");
      Deno.exit(1);
    }
    break;
}