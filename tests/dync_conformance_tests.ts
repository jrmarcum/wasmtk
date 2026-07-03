/**
 * dync_conformance_tests.ts — the #14 Route A 2h "Javy-parity" conformance gate.
 *
 * For every `.ts` fixture in `tests/wasi/wasm_wasi_dync/`, this runner proves the OWN dynamic runtime
 * (`wasmtk dync` → wasmtk:dynrt interpreter, the `javyc` replacement) produces byte-identical stdout
 * to a true JavaScript baseline (`deno run` of the same source). Three steps per fixture:
 *
 *   1. baseline — `deno run --quiet <file.ts>`        (the JS truth)
 *   2. compile  — `wasmtk dync <file.ts>`             (TS/JS → self-contained WASI via the interpreter)
 *   3. run-wasm — `wasmtk run <file>.wasm`            (execute the compiled module)
 *
 * A fixture PASSES only when compile succeeds AND run-wasm's stdout equals the baseline's stdout.
 * This is the gate that justifies retiring `javyc`: dynamic programs that `wasic` cannot compile
 * statically now compile + run through wasmtk's own runtime with no external Javy/QuickJS dependency.
 *
 * Usage: deno run --allow-read --allow-run --allow-write tests/dync_conformance_tests.ts [folder]
 *
 * NOTE: fixtures must be self-contained, non-interactive programs whose console output is
 * formatting-stable across engines (use `JSON.stringify(...)` rather than logging raw objects/arrays,
 * whose Node/Deno inspect form — `[ 1, 2, 3 ]` — differs from the interpreter's compact JSON form).
 * `prompt`/interactive stdin and ESM `import`/`export` of other modules are out of scope (documented).
 */

import { join, parse } from "jsr:@std/path";
import { bold, cyan, dim, green, magenta, red, yellow } from "jsr:@std/fmt/colors";

const WASMTK_BIN = "wasmtk";
const targetDir = Deno.args[0] ?? join(import.meta.dirname ?? Deno.cwd(), "wasi", "wasm_wasi_dync");

async function capture(cmd: string, args: string[]): Promise<{ ok: boolean; out: string }> {
  try {
    const { success, stdout } = await new Deno.Command(cmd, {
      args,
      stdout: "piped",
      stderr: "null",
    }).output();
    return { ok: success, out: new TextDecoder().decode(stdout) };
  } catch (err) {
    return { ok: false, out: err instanceof Error ? err.message : String(err) };
  }
}

async function main() {
  let dir: string;
  try {
    dir = await Deno.realPath(targetDir);
  } catch {
    console.error(red(`Directory not found: ${targetDir}`));
    Deno.exit(1);
  }

  console.log(magenta(bold("\n🚀 dync Conformance Gate (own dynamic runtime vs JS baseline)")));
  console.log(cyan(`   Directory: ${dir}\n`));

  const files: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && entry.name.endsWith(".ts") && !entry.name.startsWith("run_")) {
      files.push(entry.name);
    }
  }
  files.sort();

  let passed = 0;
  let failed = 0;

  for (const file of files) {
    const { name } = parse(file);
    const tsPath = join(dir, file);
    const wasmPath = join(dir, `${name}.wasm`);
    console.log(yellow(bold(`── ${file}`)));

    const baseline = await capture("deno", ["run", "--quiet", tsPath]);
    const compile = await capture(WASMTK_BIN, ["dync", tsPath]);
    const runWasm = compile.ok ? await capture(WASMTK_BIN, ["run", wasmPath]) : { ok: false, out: "" };

    const match = compile.ok && runWasm.ok && baseline.ok && baseline.out === runWasm.out;
    if (match) {
      console.log(green(`  ✓ baseline == dync  (${baseline.out.split("\n").length - 1} lines)`));
      console.log(green(`✅ ${file} PASSED\n`));
      passed++;
    } else {
      if (!baseline.ok) console.log(red("  ✗ baseline (deno run) failed"));
      if (!compile.ok) console.log(red("  ✗ dync compile failed"));
      else if (!runWasm.ok) console.log(red("  ✗ run-wasm failed"));
      else if (baseline.out !== runWasm.out) {
        console.log(red("  ✗ output mismatch:"));
        console.log(dim("  --- baseline ---\n" + baseline.out));
        console.log(dim("  --- dync ---\n" + runWasm.out));
      }
      console.log(red(`❌ ${file} FAILED\n`));
      failed++;
    }
  }

  const bar = "=".repeat(40);
  console.log(magenta(bold(bar)));
  console.log(`${cyan("  Processed:")} ${files.length}`);
  console.log(`${green("  Passed   :")} ${bold(String(passed))}`);
  console.log(
    failed > 0 ? `${red("  Failed   :")} ${bold(String(failed))}` : `${cyan("  Failed   :")} 0`,
  );
  console.log(magenta(bold(bar)));
  if (failed > 0) Deno.exit(1);
}

if (import.meta.main) await main();
