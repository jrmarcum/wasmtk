/**
 * merge_tests.ts
 *
 * Phase 18 WASM Merge Test Suite
 *
 * Scans for subdirectories under the target folder that contain both a
 * `*_Modc.ts` library file and a `*_Wasic.ts` application file, then runs
 * the three-step Phase 18 structural merge pipeline:
 *
 *   1. modc    — wasmtk modc  <lib>_Modc.ts     (compile library, no _start)
 *   2. wasic   — wasmtk wasic <app>_Wasic.ts    (compile app + auto-merge library via Phase 18)
 *   3. run-wasm — wasmtk run  <app>_Wasic.wasm  (execute the fully linked binary)
 *
 * The wasic step automatically invokes mergeWasmWat (wasmmerge.ts) when it
 * detects `import { fn } from "./<lib>_Modc.wasm"` in the application source.
 * This exercises:
 *   - Global & data segment relocation (dataOffset shifting)
 *   - Namespace collision prevention ($__malloc, $__heap_ptr deduplication)
 *   - WASI import deduplication (fd_write, proc_exit)
 *   - Direct call substitution (import elimination)
 *
 * A test PASSES when all three steps succeed.
 *
 * Usage:
 *   deno run --allow-read --allow-run merge_tests.ts [folder]
 *
 * Defaults to tests/wasi/wasm_wasi_bundle/ relative to this script's location.
 */

import { join, basename } from "jsr:@std/path";
import { exists } from "jsr:@std/fs";
import {
  blue, bold, cyan, dim, green, magenta, red, yellow,
} from "jsr:@std/fmt/colors";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const WASMTK_BIN = "wasmtk";
const scriptDir  = import.meta.dirname ?? Deno.cwd();
const targetDir  = Deno.args[0] ?? join(scriptDir, "wasi", "wasm_wasi_bundle");

// ─────────────────────────────────────────────────────────────────────────────
// Step runner
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
// Discovery: find directories with *_Modc.ts + *_Wasic.ts pairs
// ─────────────────────────────────────────────────────────────────────────────

interface MergeTestCase {
  dirName: string;
  dirPath: string;
  modcFile: string;   // full path to the *_Modc.ts file
  wasicFile: string;  // full path to the *_Wasic.ts file
  wasicWasm: string;  // full path to the expected *_Wasic.wasm output
}

async function discoverMergeTests(rootPath: string): Promise<MergeTestCase[]> {
  const cases: MergeTestCase[] = [];

  for await (const entry of Deno.readDir(rootPath)) {
    if (!entry.isDirectory) continue;

    const dirPath = join(rootPath, entry.name);
    const files: string[] = [];
    for await (const f of Deno.readDir(dirPath)) {
      if (f.isFile && f.name.endsWith(".ts")) files.push(f.name);
    }

    const modcFiles  = files.filter(f => f.endsWith("_Modc.ts"));
    const wasicFiles = files.filter(f => f.endsWith("_Wasic.ts"));

    if (modcFiles.length === 0 || wasicFiles.length === 0) continue;

    // Use the first match if multiple exist; phase numbering keeps them sorted.
    const modcName  = modcFiles.sort()[0];
    const wasicName = wasicFiles.sort()[0];
    const wasicBase = wasicName.replace(/\.ts$/, "");

    cases.push({
      dirName:  entry.name,
      dirPath,
      modcFile:  join(dirPath, modcName),
      wasicFile: join(dirPath, wasicName),
      wasicWasm: join(dirPath, `${wasicBase}.wasm`),
    });
  }

  cases.sort((a, b) => a.dirName.localeCompare(b.dirName));
  return cases;
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

  console.log(magenta(bold("\n🔗 Phase 18 WASM Merge Test Suite")));
  console.log(cyan(`   Directory: ${resolvedPath}\n`));
  console.log(dim("   (discovers subdirs containing *_Modc.ts + *_Wasic.ts pairs)\n"));

  const testCases = await discoverMergeTests(resolvedPath);

  if (testCases.length === 0) {
    console.log(yellow("No merge test directories found."));
    console.log(dim("  Expected: subdirectories containing both *_Modc.ts and *_Wasic.ts files."));
    return;
  }

  let processed   = 0;
  let passedCount = 0;
  let failedCount = 0;

  for (const tc of testCases) {
    const modcLabel  = basename(tc.modcFile);
    const wasicLabel = basename(tc.wasicFile);

    console.log(yellow(bold(`── ${tc.dirName}/`)));
    console.log(dim(`   Library : ${modcLabel}`));
    console.log(dim(`   App     : ${wasicLabel}`));
    processed++;

    // ── Step 1: Compile library with modc ─────────────────────────────
    const modc = await runStep(
      "modc",
      WASMTK_BIN,
      ["modc", tc.modcFile],
    );

    // ── Step 2: Compile app with wasic (auto-merges library via Phase 18)
    let wasic: StepResult;
    if (!modc.success) {
      console.log(dim("  (skipping wasic — modc failed)"));
      wasic = { success: false, code: -1 };
    } else {
      wasic = await runStep(
        "wasic",
        WASMTK_BIN,
        ["wasic", tc.wasicFile],
      );
    }

    // ── Step 3: Run the merged WASM binary ─────────────────────────────
    let runWasm: StepResult;
    if (!wasic.success) {
      console.log(dim("  (skipping run-wasm — wasic failed)"));
      runWasm = { success: false, code: -1 };
    } else if (!(await exists(tc.wasicWasm))) {
      console.log(red("  ✗ run-wasm: .wasm file not found after wasic"));
      runWasm = { success: false, code: -1 };
    } else {
      runWasm = await runStep(
        "run-wasm",
        WASMTK_BIN,
        ["run", tc.wasicWasm],
      );
    }

    // ── Verdict ───────────────────────────────────────────────────────
    const allPassed = modc.success && wasic.success && runWasm.success;
    if (allPassed) {
      console.log(green(`✅ ${tc.dirName} PASSED\n`));
      passedCount++;
    } else {
      const failedSteps = (
        [
          !modc.success    && "modc",
          !wasic.success   && "wasic",
          !runWasm.success && "run-wasm",
        ] as (string | false)[]
      ).filter((s): s is string => s !== false).join(", ");
      console.log(red(`❌ ${tc.dirName} FAILED  [${failedSteps}]\n`));
      failedCount++;
    }
  }

  // ── Final summary ─────────────────────────────────────────────────────────
  const bar = "=".repeat(40);
  console.log(magenta(bold(bar)));
  console.log(magenta(bold("   PHASE 18 MERGE TEST SUITE SUMMARY")));
  console.log(magenta(bold(bar)));
  console.log(`${cyan("  Processed:")} ${processed}`);
  console.log(`${green("  Passed   :")} ${bold(String(passedCount))}`);
  console.log(
    failedCount > 0
      ? `${red("  Failed   :")} ${bold(String(failedCount))}`
      : `${cyan("  Failed   :")} ${bold(String(failedCount))}`,
  );
  console.log(`${cyan("  Total    :")} ${testCases.length}`);
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
