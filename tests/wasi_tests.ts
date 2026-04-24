/**
 * wasi_tests.ts
 *
 * WASI Compiler Test Suite
 *
 * For each .ts file in the target directory, runs three steps:
 *   1. compile  — wasmtk wasic <file>   (TypeScript → WASM)
 *   2. run-ts   — wasmtk run   <file>   (run TS source as baseline)
 *   3. run-wasm — wasmtk run   <file>.wasm  (run compiled output)
 *
 * Each step shows ✓ on success or ✗ with exit code on failure,
 * matching the style of quick-run.ts.  A file PASSES only when all
 * three steps succeed.  The summary lists Processed / Passed / Failed.
 *
 * Usage:
 *   deno run --allow-read --allow-run wasi_tests.ts [folder]
 *
 * Defaults to the current directory if no folder is given.
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
const targetDir  = Deno.args[0] ?? join(import.meta.dirname ?? Deno.cwd(), "wasm_wasi");

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
 *   ✓ label succeeded                    ← success (not expected to fail)
 *   ✓ label failed as expected           ← failure when expectedFail=true
 *   ✗ label succeeded (expected failure) ← success when expectedFail=true
 *   ✗ label failed (exit code X)         ← unexpected failure
 *   ✗ label error: message               ← process couldn't be spawned
 */
async function runStep(
  label: string,
  cmd: string,
  args: string[],
  expectedFail = false,
): Promise<StepResult> {
  console.log(blue(`  [${label}]`), dim(`${cmd} ${args.join(" ")}`));

  try {
    const { success, code } = await new Deno.Command(cmd, {
      args,
      stdout: "inherit",
      stderr: "inherit",
    }).output();

    if (success) {
      if (expectedFail) {
        console.log(yellow(`  ✗ ${label} succeeded (expected failure)`));
      } else {
        console.log(green(`  ✓ ${label} succeeded`));
      }
    } else {
      if (expectedFail) {
        console.log(green(`  ✓ ${label} failed as expected (exit code ${code})`));
      } else {
        console.log(red(`  ✗ ${label} failed (exit code ${code})`));
      }
    }
    return { success, code };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(red(`  ✗ ${label} error: ${msg}`));
    return { success: false, code: -1 };
  }
}

/**
 * Reads the first 10 lines of a .ts file and returns any steps listed in a
 * "// @expect-fail: compile, run-ts, run-wasm" comment as a Set.
 */
async function readExpectedFailures(tsPath: string): Promise<Set<string>> {
  const expected = new Set<string>();
  try {
    const text = await Deno.readTextFile(tsPath);
    for (const line of text.split("\n").slice(0, 10)) {
      const m = line.match(/\/\/\s*@expect-fail\s*:\s*(.+)/);
      if (m) {
        for (const step of m[1].split(",")) expected.add(step.trim());
        break;
      }
    }
  } catch { /* ignore unreadable files */ }
  return expected;
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

  console.log(magenta(bold("\n🚀 WASI Compiler Test Suite")));
  console.log(cyan(`   Directory: ${resolvedPath}\n`));

  // Collect .ts files, excluding test-runner scripts themselves
  const files: string[] = [];
  for await (const entry of Deno.readDir(resolvedPath)) {
    if (
      entry.isFile &&
      entry.name.endsWith(".ts") &&
      !entry.name.endsWith("_tests.ts")   // exclude wasi_tests.ts, mod_tests.ts, etc.
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

    const expectFail = await readExpectedFailures(tsPath);
    // A step "passes" if it succeeded when not expected to fail, or failed when expected to fail.
    const stepOk = (r: StepResult, step: string) =>
      expectFail.has(step) ? !r.success : r.success;

    // ── Step 1: Compile TS → WASM ─────────────────────────────────
    const compile = await runStep("compile", WASMTK_BIN, ["wasic", tsPath], expectFail.has("compile"));

    // ── Step 2: Run TS source directly (reference baseline) ────────
    const runTs = await runStep("run-ts", WASMTK_BIN, ["run", tsPath], expectFail.has("run-ts"));

    // ── Step 3: Run compiled WASM ─────────────────────────────────
    let runWasm: StepResult;
    const compileExpectedFail = expectFail.has("compile") && !compile.success;
    if (!compile.success) {
      if (!compileExpectedFail) {
        console.log(dim("  (skipping run-wasm — compile failed)"));
      }
      // If compile failed as expected, treat run-wasm as N/A (not a failure).
      runWasm = { success: !compileExpectedFail ? false : true, code: -1 };
    } else if (!(await exists(wasmPath))) {
      console.log(red("  ✗ run-wasm: .wasm file not found after compile"));
      runWasm = { success: false, code: -1 };
    } else {
      runWasm = await runStep("run-wasm", WASMTK_BIN, ["run", wasmPath], expectFail.has("run-wasm"));
    }

    // ── File verdict ──────────────────────────────────────────────
    const allPassed = stepOk(compile, "compile") && stepOk(runTs, "run-ts") && stepOk(runWasm, "run-wasm");
    if (allPassed) {
      const note = expectFail.size > 0 ? dim(` (expected failures: ${[...expectFail].join(", ")})`) : "";
      console.log(green(`✅ ${file} PASSED`) + note + "\n");
      passedCount++;
    } else {
      // List steps whose outcome didn't match expectations.
      const badSteps = (
        [
          !stepOk(compile, "compile") && "compile",
          !stepOk(runTs,   "run-ts")  && "run-ts",
          !stepOk(runWasm, "run-wasm") && "run-wasm",
        ] as (string | false)[]
      ).filter((s): s is string => s !== false).join(", ");
      console.log(red(`❌ ${file} FAILED  [${badSteps}]\n`));
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
