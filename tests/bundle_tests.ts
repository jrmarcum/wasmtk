/**
 * bundle_tests.ts
 *
 * Bundle Compiler Test Suite
 *
 * Scans for subdirectories under the target folder, each containing a
 * multi-file TypeScript project with a `main.ts` entry point, and runs:
 *   1. compile  — wasmtk wasic <subdir>/main.ts   (bundles imports → WASM)
 *   2. run-ts   — wasmtk run   <subdir>/main.ts   (Deno baseline, native imports)
 *   3. run-wasm — wasmtk run   <subdir>/main.wasm (compiled output)
 *
 * A test PASSES only when all three steps succeed.
 *
 * Usage:
 *   deno run --allow-read --allow-run bundle_tests.ts [folder]
 *
 * Defaults to tests/wasm_wasi_bundle/ relative to this script's location.
 */

// deno-lint-ignore no-import-prefix
import { join } from "jsr:@std/path@1.1.4";

// deno-lint-ignore no-import-prefix
import { exists } from "jsr:@std/fs@1.0.23";
import {
  blue, bold, cyan, dim, green, magenta, red, yellow,

// deno-lint-ignore no-import-prefix
} from "jsr:@std/fmt/colors@1.0.25";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const WASMTK_BIN = "wasmtk";
const scriptDir = import.meta.dirname ?? Deno.cwd();
const targetDir = Deno.args[0] ?? join(scriptDir, "wasm_wasi_bundle");

// ─────────────────────────────────────────────────────────────────────────────
// Step runner (mirrors wasi_tests.ts)
// ─────────────────────────────────────────────────────────────────────────────

interface StepResult {
  success: boolean;
  code: number;
}

async function runStep(label: string, cmd: string, args: string[]): Promise<StepResult> {
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

  console.log(magenta(bold("\n📦 Bundle Compiler Test Suite")));
  console.log(cyan(`   Directory: ${resolvedPath}\n`));

  // Collect subdirectories that contain a main.ts
  const testDirs: string[] = [];
  for await (const entry of Deno.readDir(resolvedPath)) {
    if (!entry.isDirectory) continue;
    const mainTs = join(resolvedPath, entry.name, "main.ts");
    if (await exists(mainTs)) {
      testDirs.push(entry.name);
    }
  }
  testDirs.sort();

  if (testDirs.length === 0) {
    console.log(yellow("No bundle test directories found (expected subdirs with main.ts)."));
    return;
  }

  let processed = 0;
  let passedCount = 0;
  let failedCount = 0;

  for (const dir of testDirs) {
    const tsPath   = join(resolvedPath, dir, "main.ts");
    const wasmPath = join(resolvedPath, dir, "main.wasm");

    console.log(yellow(bold(`── ${dir}/main.ts`)));
    processed++;

    // ── Step 1: Compile (bundle + transpile) ──────────────────────
    const compile = await runStep("compile", WASMTK_BIN, ["wasic", tsPath]);

    // ── Step 2: Run TS baseline (Deno native import resolution) ───
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

    const allPassed = compile.success && runTs.success && runWasm.success;
    if (allPassed) {
      console.log(green(`✅ ${dir} PASSED\n`));
      passedCount++;
    } else {
      const failedSteps = (
        [
          !compile.success && "compile",
          !runTs.success   && "run-ts",
          !runWasm.success && "run-wasm",
        ] as (string | false)[]
      ).filter((s): s is string => s !== false).join(", ");
      console.log(red(`❌ ${dir} FAILED  [${failedSteps}]\n`));
      failedCount++;
    }
  }

  // ── Final summary ─────────────────────────────────────────────────────────
  const bar = "=".repeat(40);
  console.log(magenta(bold(bar)));
  console.log(magenta(bold("      BUNDLE TEST SUITE SUMMARY")));
  console.log(magenta(bold(bar)));
  console.log(`${cyan("  Processed:")} ${processed}`);
  console.log(`${green("  Passed   :")} ${bold(String(passedCount))}`);
  console.log(
    failedCount > 0
      ? `${red("  Failed   :")} ${bold(String(failedCount))}`
      : `${cyan("  Failed   :")} ${bold(String(failedCount))}`,
  );
  console.log(`${cyan("  Total    :")} ${testDirs.length}`);
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
