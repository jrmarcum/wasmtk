/**
 * wasi_javy_tests.ts
 *
 * WASI Javy Compiler Test Suite
 *
 * For each .ts file in the target directory, runs three steps:
 *   1. compile  — wasmtk javyc <file>   (TypeScript → WASM via Javy/QuickJS)
 *   2. run-ts   — wasmtk run   <file>   (run TS source as baseline)
 *   3. run-wasm — wasmtk run   <file>.wasm  (run compiled output)
 *
 * Each step shows ✓ on success or ✗ with exit code on failure,
 * matching the style of quick-run.ts.  A file PASSES only when all
 * three steps succeed.  The summary lists Processed / Passed / Failed.
 *
 * Usage:
 *   deno run --allow-read --allow-run wasi_javy_tests.ts [folder]
 *
 * Defaults to the wasm_wasi_javy directory if no folder is given.
 */

import { join, parse } from "jsr:@std/path";
import { exists } from "jsr:@std/fs";
import {
  blue, bold, cyan, dim, green, magenta, red, yellow,
} from "jsr:@std/fmt/colors";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const WASMTK_BIN = "wasmtk";
const targetDir  = Deno.args[0] ?? join(import.meta.dirname ?? Deno.cwd(), "wasm_wasi_javy");

// ─────────────────────────────────────────────────────────────────────────────
// Step runner
// ─────────────────────────────────────────────────────────────────────────────

interface StepResult {
  success: boolean;
  code: number;
}

/**
 * Runs one step of the test pipeline.
 *
 * Prints:
 *   [label]  cmd args...
 *   ✓ label succeeded          ← on success
 *   ✗ label failed (exit code X) ← on failure
 *   ✗ label error: message      ← if the process couldn't be spawned
 */
async function runStep(
  label: string,
  cmd: string,
  args: string[],
): Promise<StepResult> {
  console.log(blue(`  [${label}]`), dim(`${cmd} ${args.join(" ")}`));

  try {
    const { success, code } = await new Deno.Command(cmd, {
      args,
      stdout: "inherit",
      stderr: "inherit",
    }).output();

    if (success) {
      console.log(green(`  ✓ ${label} succeeded`));
    } else {
      console.log(red(`  ✗ ${label} failed (exit code ${code})`));
    }
    return { success, code };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(red(`  ✗ ${label} error: ${msg}`));
    return { success: false, code: -1 };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test suite
// ─────────────────────────────────────────────────────────────────────────────

async function startTestSuite() {
  // Resolve and verify the target directory
  let resolvedPath: string;
  try {
    resolvedPath = await Deno.realPath(targetDir);
  } catch {
    console.error(red(`Directory not found: ${targetDir}`));
    Deno.exit(1);
  }

  if (!(await exists(resolvedPath))) {
    console.error(red(`Directory not found: ${resolvedPath}`));
    Deno.exit(1);
  }

  console.log(magenta(bold("\n🚀 WASI Javy Compiler Test Suite")));
  console.log(cyan(`   Directory: ${resolvedPath}\n`));

  // Collect .ts files, excluding test-runner scripts themselves
  const files: string[] = [];
  for await (const entry of Deno.readDir(resolvedPath)) {
    if (
      entry.isFile &&
      entry.name.endsWith(".ts") &&
      !entry.name.startsWith("run_")
    ) {
      files.push(entry.name);
    }
  }
  files.sort();

  if (files.length === 0) {
    console.log(yellow("No TypeScript files found to test."));
    return;
  }

  let processed = 0;
  let passedCount = 0;
  let failedCount = 0;

  for (const file of files) {
    const { name } = parse(file);
    const tsPath   = join(resolvedPath, file);
    const wasmPath = join(resolvedPath, `${name}.wasm`);

    console.log(yellow(bold(`── ${file}`)));
    processed++;

    // ── Step 1: Compile TS → WASM ─────────────────────────────────
    const compile = await runStep("compile", WASMTK_BIN, ["javyc", tsPath]);

    // ── Step 2: Run TS source directly (reference baseline) ────────
    const runTs = await runStep("run-ts", WASMTK_BIN, ["run", tsPath]);

    // ── Step 3: Run compiled WASM ─────────────────────────────────
    let runWasm: StepResult;
    if (!compile.success) {
      console.log(dim("  (skipping run-wasm — compile failed)"));
      runWasm = { success: false, code: -1 };
    } else if (!(await exists(wasmPath))) {
      console.log(red("  ✗ run-wasm: .wasm file not found after compile"));
      runWasm = { success: false, code: -1 };
    } else {
      runWasm = await runStep("run-wasm", WASMTK_BIN, ["run", wasmPath]);
    }

    // ── File verdict ──────────────────────────────────────────────
    const allPassed = compile.success && runTs.success && runWasm.success;
    if (allPassed) {
      console.log(green(`✅ ${file} PASSED\n`));
      passedCount++;
    } else {
      const failedSteps = (
        [
          !compile.success && "compile",
          !runTs.success   && "run-ts",
          !runWasm.success && "run-wasm",
        ] as (string | false)[]
      ).filter((s): s is string => s !== false).join(", ");
      console.log(red(`❌ ${file} FAILED  [${failedSteps}]\n`));
      failedCount++;
    }
  }

  // ── Final summary ─────────────────────────────────────────────────────────
  const bar = "=".repeat(40);
  console.log(magenta(bold(bar)));
  console.log(magenta(bold("      TEST SUITE SUMMARY")));
  console.log(magenta(bold(bar)));
  console.log(`${cyan("  Processed:")} ${processed}`);
  console.log(`${green("  Passed   :")} ${bold(String(passedCount))}`);
  console.log(
    failedCount > 0
      ? `${red("  Failed   :")} ${bold(String(failedCount))}`
      : `${cyan("  Failed   :")} ${bold(String(failedCount))}`,
  );
  console.log(`${cyan("  Total    :")} ${files.length}`);
  console.log(magenta(bold(bar)));

  if (failedCount > 0) {
    console.log(red("Some tests failed — check output above."));
    Deno.exit(1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

if (import.meta.main) {
  await startTestSuite();
}
