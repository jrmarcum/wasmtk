/**
 * wast_tests.ts — regression gate for the `.wast` spec-script runner (`src/wast.ts`).
 *
 * Runs a curated set of the official WebAssembly spec testsuite `.wast` files (under
 * tests/module/wasm_wast/testsuite-main/) and asserts every EXECUTION assertion passes
 * (`failed === 0`). These files currently run clean end-to-end (wabt assemble → host V8 execute),
 * so a non-zero failure here is a real regression in the runner, the wabt backend, or the engine.
 *
 * NOTE: a handful of other spec files (`const`, `local_get`, `labels`, `conversions`, `func`) surface
 * genuine **wabt-ts** toolchain bugs (folded/plain `br_if`-with-value encoding; over-precise hex-float
 * consts truncated instead of round-to-nearest-even) and are intentionally NOT in this gate — see
 * cmem/compiler-bugs.md. Run `wasmtk wast <dir>` to see the full picture across the whole suite.
 *
 *   deno run --allow-read --allow-net tests/wast_tests.ts
 */
import { runWast } from "../src/wast.ts";
import { join } from "jsr:@std/path@1.0.2";

const SUITE = join(import.meta.dirname ?? ".", "module", "wasm_wast", "testsuite-main");

// Curated core files that run clean (execution failed === 0). Broad coverage of numerics, memory,
// control flow, and calls.
const FILES = [
  "i32",
  "i64",
  "f32",
  "f64",
  "f32_cmp",
  "f64_cmp",
  "int_exprs",
  "int_literals",
  "address",
  "align",
  "endianness",
  "memory",
  "memory_redundancy",
  "load",
  "store",
  "float_misc",
  "forward",
  "fac",
  "stack",
  "return",
  "select",
  "global",
  "local_set",
  "local_tee",
  "loop",
  "call",
  "call_indirect",
  "switch",
  "unreachable",
  "unwind",
  "nop",
];

const green = (s: string) => `\x1b[32m${s}\x1b[39m`;
const red = (s: string) => `\x1b[31m${s}\x1b[39m`;

let totalPass = 0, totalFail = 0, totalSkip = 0, badFiles = 0;
for (const name of FILES) {
  const path = join(SUITE, name + ".wast");
  let r;
  try {
    r = await runWast(path, { maxFailures: 5 });
  } catch (e) {
    console.log(red(`  ✗ ${name}.wast — could not run: ${e instanceof Error ? e.message : e}`));
    badFiles++;
    continue;
  }
  totalPass += r.passed;
  totalFail += r.failed;
  totalSkip += r.skipped;
  if (r.failed > 0) {
    badFiles++;
    console.log(red(`  ✗ ${name}.wast — ${r.failed} execution failure(s), pass=${r.passed}`));
    for (const m of r.failures.slice(0, 3)) {
      console.log("      " + m.replace(/\s+/g, " ").slice(0, 120));
    }
  } else {
    console.log(green(`  ✓ ${name}.wast`) + `  pass=${r.passed} skip=${r.skipped}`);
  }
}

console.log("\n" + "─".repeat(60));
console.log(
  `  wast gate: ${FILES.length} files — ${totalPass} passed, ${totalFail} failed, ${totalSkip} skipped`,
);
// Sanity floor: the gate must actually be exercising execution (guards against a silent all-skip).
const MIN_PASS = 10000;
if (totalPass < MIN_PASS) {
  console.log(
    red(
      `  ✗ only ${totalPass} assertions passed (expected ≥ ${MIN_PASS}) — runner may be silently skipping`,
    ),
  );
  badFiles++;
}
if (badFiles === 0) {
  console.log(green(`  ✅ ALL CLEAN`));
  Deno.exit(0);
} else {
  console.log(red(`  ❌ ${badFiles} file(s) with failures`));
  Deno.exit(1);
}
