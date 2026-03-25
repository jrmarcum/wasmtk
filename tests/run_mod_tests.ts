/**
 * run_mod_tests.ts
 *
 * WASM Library Module Test Runner
 *
 * For each .wasm file in the target directory:
 *   1. Loads the module and discovers exported functions (name, kind)
 *   2. Runs test cases defined in a companion <name>.test.json file
 *   3. Reports pass/fail with a summary
 *
 * Usage:
 *   deno run --allow-read run_mod_tests.ts [folder]
 *
 * Test spec format (<module>.test.json):
 *   {
 *     "funcName": [
 *       { "args": [a, b], "expected": result },
 *       ...
 *     ]
 *   }
 *
 * If no .test.json file is present, the module is still loaded and its
 * exports are listed — the run counts as a discovery pass.
 */

import { join, parse } from "jsr:@std/path";
import { exists } from "jsr:@std/fs";
import {
  blue, bold, cyan, dim, green, magenta, red, yellow,
} from "jsr:@std/fmt/colors";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type WasmValue = number | bigint;

interface TestCase {
  args: WasmValue[];
  expected: WasmValue;
  /** Optional description shown in output */
  desc?: string;
}

/** One entry per exported function: list of test cases to run against it. */
type FuncTestSpec = Record<string, TestCase[]>;

// ─────────────────────────────────────────────────────────────────────────────
// Module loading
// ─────────────────────────────────────────────────────────────────────────────

interface LoadedModule {
  instance: WebAssembly.Instance;
  funcExports: string[];
}

/**
 * Loads and instantiates a WASM binary.
 * Tries with no imports first; if that fails (e.g. module has WASI stubs),
 * retries with no-op stub functions for every declared import.
 */
async function loadModule(wasmPath: string): Promise<LoadedModule | null> {
  let bytes: Uint8Array;
  try {
    bytes = await Deno.readFile(wasmPath);
  } catch (err) {
    console.error(red(`  Cannot read file: ${err instanceof Error ? err.message : err}`));
    return null;
  }

  let mod: WebAssembly.Module;
  try {
    mod = await WebAssembly.compile(bytes);
  } catch (err) {
    console.error(red(`  Compile error: ${err instanceof Error ? err.message : err}`));
    return null;
  }

  // Collect export names before instantiation
  const allExports = WebAssembly.Module.exports(mod);
  const funcExports = allExports
    .filter((e) => e.kind === "function" && !e.name.startsWith("__"))
    .map((e) => e.name);

  // Build a stub import object from the module's import requirements
  const importDescriptors = WebAssembly.Module.imports(mod);
  const importObj: Record<string, Record<string, unknown>> = {};
  for (const imp of importDescriptors) {
    if (!importObj[imp.module]) importObj[imp.module] = {};
    if (imp.kind === "function") {
      importObj[imp.module][imp.name] = () => 0;
    } else if (imp.kind === "memory") {
      importObj[imp.module][imp.name] = new WebAssembly.Memory({ initial: 1 });
    } else if (imp.kind === "table") {
      importObj[imp.module][imp.name] = new WebAssembly.Table({ initial: 0, element: "anyfunc" });
    } else if (imp.kind === "global") {
      importObj[imp.module][imp.name] = new WebAssembly.Global({ value: "i32", mutable: false }, 0);
    }
  }

  let instance: WebAssembly.Instance;
  try {
    instance = await WebAssembly.instantiate(mod, importObj);
  } catch (err) {
    console.error(red(`  Instantiate error: ${err instanceof Error ? err.message : err}`));
    return null;
  }

  return { instance, funcExports };
}

// ─────────────────────────────────────────────────────────────────────────────
// Test execution
// ─────────────────────────────────────────────────────────────────────────────

interface CaseResult {
  passed: boolean;
  actual: WasmValue | undefined;
  error?: string;
}

function runCase(
  fn: (...args: WasmValue[]) => WasmValue,
  tc: TestCase,
): CaseResult {
  try {
    const actual = fn(...tc.args) as WasmValue;
    // Use loose numeric equality so i32 return values compare cleanly to JS numbers
    const passed =
      typeof tc.expected === "bigint"
        ? BigInt(String(actual)) === tc.expected
        : Number(actual) === Number(tc.expected);
    return { passed, actual };
  } catch (err) {
    return { passed: false, actual: undefined, error: String(err) };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-module report
// ─────────────────────────────────────────────────────────────────────────────

interface ModuleResult {
  loaded: boolean;
  funcExports: string[];
  casesRun: number;
  casesPassed: number;
  hasTestFile: boolean;
}

async function processModule(
  wasmPath: string,
  moduleName: string,
  dir: string,
): Promise<ModuleResult> {
  const result: ModuleResult = {
    loaded: false,
    funcExports: [],
    casesRun: 0,
    casesPassed: 0,
    hasTestFile: false,
  };

  const loaded = await loadModule(wasmPath);
  if (!loaded) return result;
  result.loaded = true;
  result.funcExports = loaded.funcExports;

  // List exports
  if (loaded.funcExports.length === 0) {
    console.log(dim("  No exported functions found."));
  } else {
    console.log(
      blue("  Exports: ") + loaded.funcExports.map((n) => cyan(n)).join("  "),
    );
  }

  // Check for test spec file
  const specPath = join(dir, `${moduleName}.test.json`);
  if (!(await exists(specPath))) {
    console.log(
      dim(`  No test file — create ${moduleName}.test.json to add test cases.`),
    );
    return result;
  }

  result.hasTestFile = true;
  let spec: FuncTestSpec;
  try {
    spec = JSON.parse(await Deno.readTextFile(specPath)) as FuncTestSpec;
  } catch (err) {
    console.error(red(`  Could not parse test file: ${err}`));
    return result;
  }

  // Run each function's test cases
  for (const [funcName, cases] of Object.entries(spec)) {
    const fn = loaded.instance.exports[funcName] as
      | ((...a: WasmValue[]) => WasmValue)
      | undefined;

    if (typeof fn !== "function") {
      console.log(red(`  ✗ '${funcName}' not found in exports`));
      result.casesRun += cases.length;
      continue;
    }

    let fPass = 0;
    let fFail = 0;

    for (const tc of cases) {
      const cr = runCase(fn, tc);
      result.casesRun++;

      const label = tc.desc
        ? `${funcName}(${tc.args.join(", ")})  [${tc.desc}]`
        : `${funcName}(${tc.args.join(", ")})`;

      if (cr.passed) {
        console.log(green(`  ✓ ${label} = ${cr.actual}`));
        fPass++;
        result.casesPassed++;
      } else if (cr.error) {
        console.log(red(`  ✗ ${label}  threw: ${cr.error}`));
        fFail++;
      } else {
        console.log(
          red(`  ✗ ${label} = ${cr.actual}  (expected ${tc.expected})`),
        );
        fFail++;
      }
    }

    const color = fFail === 0 ? green : red;
    console.log(color(`    ${funcName}: ${fPass}/${fPass + fFail} passed`));
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const targetDir =
    Deno.args[0] ?? join(import.meta.dirname ?? ".", "wasm_mod");

  let resolvedPath: string;
  try {
    resolvedPath = await Deno.realPath(targetDir);
  } catch {
    console.error(red(`Directory not found: ${targetDir}`));
    Deno.exit(1);
  }

  console.log(magenta(bold("\n🧩 WASM Module Test Runner")));
  console.log(cyan(`   Directory: ${resolvedPath}\n`));

  const wasmFiles: string[] = [];
  for await (const entry of Deno.readDir(resolvedPath)) {
    if (entry.isFile && entry.name.endsWith(".wasm")) {
      wasmFiles.push(entry.name);
    }
  }
  wasmFiles.sort();

  if (wasmFiles.length === 0) {
    console.log(yellow("No .wasm files found."));
    return;
  }

  let totalModules = 0;
  let loadFailed = 0;
  let totalCases = 0;
  let totalPassed = 0;
  let testedModules = 0;

  for (const wasmFile of wasmFiles) {
    const { name } = parse(wasmFile);
    const wasmPath = join(resolvedPath, wasmFile);

    console.log(yellow(bold(`── ${wasmFile}`)));
    totalModules++;

    const mr = await processModule(wasmPath, name, resolvedPath);

    if (!mr.loaded) {
      loadFailed++;
      console.log(red("  ❌ Load failed\n"));
      continue;
    }

    totalCases   += mr.casesRun;
    totalPassed  += mr.casesPassed;
    if (mr.hasTestFile) testedModules++;

    const allOk = mr.casesRun === 0 || mr.casesPassed === mr.casesRun;
    console.log(allOk ? green("  ✅ OK\n") : red("  ❌ FAILED\n"));
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  const bar = "─".repeat(40);
  console.log(magenta(bold(bar)));
  console.log(magenta(bold("      MODULE TEST SUMMARY")));
  console.log(magenta(bold(bar)));
  console.log(`${cyan("  Modules loaded  :")} ${totalModules - loadFailed} / ${totalModules}`);
  console.log(`${cyan("  Modules w/ tests:")} ${testedModules}`);
  console.log(`${green("  Cases passed    :")} ${totalPassed}`);
  const failedCases = totalCases - totalPassed;
  const failColor = failedCases > 0 ? red : cyan;
  console.log(`${failColor("  Cases failed    :")} ${failedCases}`);
  console.log(`${cyan("  Cases total     :")} ${totalCases}`);
  console.log(magenta(bold(bar)));

  if (loadFailed > 0 || totalCases - totalPassed > 0) {
    Deno.exit(1);
  }
}

await main();
