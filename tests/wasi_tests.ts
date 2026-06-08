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
import { blue, bold, cyan, dim, green, magenta, red, yellow } from "jsr:@std/fmt/colors";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const WASMTK_BIN = "wasmtk";
const targetDir = Deno.args[0] ?? join(import.meta.dirname ?? Deno.cwd(), "wasm_wasi");
// Optional second arg: regex filter applied to file basenames (e.g. "^01_" for phase 1)
const fileFilter = Deno.args[1] ? new RegExp(Deno.args[1]) : null;

// ─────────────────────────────────────────────────────────────────────────────
// Step runner
// ─────────────────────────────────────────────────────────────────────────────

interface StepResult {
  success: boolean;
  code: number;
  stdout?: string; // captured stdout when `capture` is requested (for output comparison)
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
  capture = false,
): Promise<StepResult> {
  console.log(blue(`  [${label}]`), dim(`${cmd} ${args.join(" ")}`));

  try {
    const output = await new Deno.Command(cmd, {
      args,
      stdout: capture ? "piped" : "inherit",
      stderr: "inherit",
    }).output();
    const { success, code } = output;

    let captured: string | undefined;
    if (capture) {
      // Echo the captured stdout so the run stays visible, and keep it for comparison.
      // (Only read .stdout when piped — accessing it on an inherited stream throws.)
      await Deno.stdout.write(output.stdout);
      captured = new TextDecoder().decode(output.stdout);
    }

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
    return { success, code, stdout: captured };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(red(`  ✗ ${label} error: ${msg}`));
    return { success: false, code: -1 };
  }
}

/** Normalize captured output for comparison: strip a trailing newline, normalize CRLF→LF,
 *  and trim trailing whitespace on each line. */
function normalizeOutput(s: string): string {
  return s.replace(/\r\n/g, "\n").split("\n").map((l) => l.replace(/\s+$/, "")).join("\n")
    .replace(/\n+$/, "");
}

/**
 * Reads the first 10 lines of a .ts file for a `// @allow-output-diff[: reason]` marker. Tests
 * whose wasic semantics legitimately diverge from native-TS execution (e.g. zero-sentinel
 * destructuring defaults, float-formatting precision) opt out of run-ts vs run-wasm comparison.
 */
async function readAllowOutputDiff(tsPath: string): Promise<boolean> {
  try {
    const text = await Deno.readTextFile(tsPath);
    for (const line of text.split("\n").slice(0, 10)) {
      if (/\/\/\s*@allow-output-diff\b/.test(line)) return true;
    }
  } catch { /* ignore */ }
  return false;
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

/**
 * Reads the first 10 lines of a .ts file and returns the path from a
 * "// @modc-prereq: path/to/library.ts" comment, or null if absent.
 *
 * Phase 18 WASM-import tests must pre-compile their library with `modc` before
 * the standard wasic compile step can find the .wasm import.
 */
async function readModcPrereq(tsPath: string): Promise<string | null> {
  try {
    const text = await Deno.readTextFile(tsPath);
    for (const line of text.split("\n").slice(0, 10)) {
      const m = line.match(/\/\/\s*@modc-prereq\s*:\s*(.+)/);
      if (m) return m[1].trim();
    }
  } catch { /* ignore unreadable files */ }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom pipeline support  (@test-pipeline / @step)
// ─────────────────────────────────────────────────────────────────────────────

interface PipelineStep {
  label: string; // wasmtk sub-command (modc, wasic, wasmbundle, run, …)
  args: string[]; // full arg list passed to wasmtk (subcommand first)
}

/**
 * Reads the first 40 lines of a .ts file looking for:
 *   // @test-pipeline          ← activates custom pipeline mode
 *   // @step <cmd> <args...>   ← one step in the pipeline
 *
 * Returns the ordered list of steps, or null if no @test-pipeline marker found.
 * Paths inside @step lines are left as-is (relative to the test directory);
 * they are resolved to absolute paths in startTestSuite before execution.
 */
async function readTestPipeline(tsPath: string): Promise<PipelineStep[] | null> {
  try {
    const text = await Deno.readTextFile(tsPath);
    const lines = text.split("\n").slice(0, 40);
    if (!lines.some((l) => /\/\/\s*@test-pipeline\b/.test(l))) return null;

    const steps: PipelineStep[] = [];
    for (const line of lines) {
      const m = line.match(/\/\/\s*@step\s+(\S+)\s*(.*)/);
      if (!m) continue;
      const subCmd = m[1];
      const rest = m[2]?.trim() ?? "";
      const extra = rest.length > 0 ? rest.split(/\s+/) : [];
      steps.push({ label: subCmd, args: [subCmd, ...extra] });
    }
    return steps.length > 0 ? steps : null;
  } catch { /* ignore unreadable files */ }
  return null;
}

/**
 * Resolves a single pipeline argument relative to baseDir.
 * Flags (starting with "-") are returned unchanged.
 * Any argument that contains a path separator or has a known file extension
 * is joined with baseDir; everything else is returned unchanged.
 */
function resolvePipelineArg(arg: string, baseDir: string): string {
  if (arg.startsWith("-")) return arg;
  if (/\.(ts|wasm|wat)(\s|$)/.test(arg) || arg.startsWith("../") || arg.startsWith("./")) {
    return join(baseDir, arg);
  }
  return arg;
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
      !entry.name.endsWith("_tests.ts") && // exclude wasi_tests.ts, mod_tests.ts, etc.
      (fileFilter === null || fileFilter.test(entry.name))
    ) {
      files.push(entry.name);
    }
  }
  files.sort();
  if (fileFilter !== null) {
    console.log(cyan(`   Filter:    /${fileFilter.source}/  → ${files.length} file(s)\n`));
  }

  if (files.length === 0) {
    console.log(yellow("No TypeScript files found to test."));
    return;
  }

  let processed = 0;
  let passedCount = 0;
  let failedCount = 0;

  for (const file of files) {
    const { name } = parse(file);
    const tsPath = join(resolvedPath, file);
    const wasmPath = join(resolvedPath, `${name}.wasm`);

    console.log(yellow(bold(`── ${file}`)));
    processed++;

    // ── @test-pipeline: custom command sequence ───────────────────────
    const pipeline = await readTestPipeline(tsPath);
    if (pipeline !== null) {
      let allPipelinePassed = true;
      let failedPipelineStep = "";
      for (const step of pipeline) {
        const resolvedArgs = step.args.map((a) => resolvePipelineArg(a, resolvedPath));
        const [subCmd, ...stepArgs] = resolvedArgs;
        const r = await runStep(step.label, WASMTK_BIN, [subCmd, ...stepArgs]);
        if (!r.success) {
          allPipelinePassed = false;
          failedPipelineStep = step.label;
          break;
        }
      }
      if (allPipelinePassed) {
        console.log(green(`✅ ${file} PASSED\n`));
        passedCount++;
      } else {
        console.log(red(`❌ ${file} FAILED  [${failedPipelineStep}]\n`));
        failedCount++;
      }
      continue; // skip standard compile / run-ts / run-wasm pipeline
    }

    const expectFail = await readExpectedFailures(tsPath);
    // A step "passes" if it succeeded when not expected to fail, or failed when expected to fail.
    const stepOk = (r: StepResult, step: string) => expectFail.has(step) ? !r.success : r.success;

    // ── Step 0: modc-prereq (Phase 18 — compile library before app) ──
    const prereqRel = await readModcPrereq(tsPath);
    let prereq: StepResult = { success: true, code: 0 };
    if (prereqRel !== null) {
      const prereqFull = join(resolvedPath, prereqRel);
      prereq = await runStep("modc-prereq", WASMTK_BIN, ["modc", prereqFull]);
    }

    // ── Step 1: Compile TS → WASM ─────────────────────────────────
    let compile: StepResult;
    if (!prereq.success) {
      console.log(dim("  (skipping compile — modc-prereq failed)"));
      compile = { success: false, code: -1 };
    } else {
      compile = await runStep("compile", WASMTK_BIN, ["wasic", tsPath], expectFail.has("compile"));
    }

    // ── Step 2: Run TS source directly (reference baseline) ────────
    // Files with @modc-prereq import .wasm modules; Deno cannot resolve those,
    // so run-ts is N/A (skipped, not counted as pass or fail).
    let runTs: StepResult;
    if (prereqRel !== null) {
      console.log(dim("  (skipping run-ts — .wasm imports require modc-prereq)"));
      runTs = { success: true, code: 0 };
    } else {
      runTs = await runStep("run-ts", WASMTK_BIN, ["run", tsPath], expectFail.has("run-ts"), true);
    }

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
      runWasm = await runStep(
        "run-wasm",
        WASMTK_BIN,
        ["run", wasmPath],
        expectFail.has("run-wasm"),
        true,
      );
    }

    // ── Step 4: Compare run-ts vs run-wasm output ─────────────────
    // The compiled WASM must reproduce the TS reference behavior. Only meaningful when both runs
    // succeeded, no failure was expected, and the test didn't opt out via @allow-output-diff
    // (used for the few tests whose wasic semantics legitimately differ from native TS, e.g.
    // zero-sentinel destructuring defaults or float-formatting precision).
    const allowDiff = await readAllowOutputDiff(tsPath);
    let outputMatches = true;
    const canCompare = prereqRel === null && expectFail.size === 0 &&
      runTs.success && runWasm.success &&
      runTs.stdout !== undefined && runWasm.stdout !== undefined;
    if (canCompare && !allowDiff) {
      if (normalizeOutput(runTs.stdout!) === normalizeOutput(runWasm.stdout!)) {
        console.log(green("  ✓ output matches (run-ts == run-wasm)"));
      } else {
        outputMatches = false;
        console.log(red("  ✗ output MISMATCH (run-ts != run-wasm):"));
        const tsLines = normalizeOutput(runTs.stdout!).split("\n");
        const wasmLines = normalizeOutput(runWasm.stdout!).split("\n");
        const n = Math.max(tsLines.length, wasmLines.length);
        let shown = 0;
        for (let i = 0; i < n && shown < 6; i++) {
          if (tsLines[i] !== wasmLines[i]) {
            console.log(red(`      L${i + 1}  ts:   ${JSON.stringify(tsLines[i] ?? "")}`));
            console.log(red(`      L${i + 1}  wasm: ${JSON.stringify(wasmLines[i] ?? "")}`));
            shown++;
          }
        }
      }
    } else if (allowDiff && canCompare) {
      console.log(dim("  (output-diff allowed via @allow-output-diff)"));
    }

    // ── File verdict ──────────────────────────────────────────────
    const allPassed = prereq.success && stepOk(compile, "compile") &&
      stepOk(runTs, "run-ts") && stepOk(runWasm, "run-wasm") && outputMatches;
    if (allPassed) {
      const note = expectFail.size > 0
        ? dim(` (expected failures: ${[...expectFail].join(", ")})`)
        : "";
      console.log(green(`✅ ${file} PASSED`) + note + "\n");
      passedCount++;
    } else {
      // List steps whose outcome didn't match expectations.
      const badSteps = (
        [
          !prereq.success && "modc-prereq",
          !stepOk(compile, "compile") && "compile",
          !stepOk(runTs, "run-ts") && "run-ts",
          !stepOk(runWasm, "run-wasm") && "run-wasm",
          !outputMatches && "output-mismatch",
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
