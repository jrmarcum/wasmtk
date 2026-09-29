/**
 * dync_cross_runtime_tests.ts — proves `wasmtk dync` output is PORTABLE: a pure-WASI module that
 * runs on any standalone WASI runtime, not just wasmtk's own runner.
 *
 * The dynamic runtime (`wasmtk:dynrt`) used to import `env.__host_print` + `env.__host_call`
 * (wasmtk-host-only), so `wasmtk dync` output failed to instantiate on wasmtime / wasmer / WAMR /
 * wazero ("unknown import: env::__host_call"). `internalizeDynrtHostImports` (src/wasic.ts) now
 * rewrites those into internal definitions (print → inline WASI `fd_write`; call → `unreachable`),
 * so every `dync` module imports ONLY `wasi_snapshot_preview1`.
 *
 * Two checks per fixture in `tests/wasi/wasm_wasi_dync/`:
 *
 *   1. INVARIANT (always runs, even in a runtime-free CI): compile via `wasmtk dync`, then assert the
 *      emitted `.wasm` imports come solely from the `wasi_snapshot_preview1` module. This alone guards
 *      the portability fix from regressing.
 *   2. EXECUTION (skip-if-absent, like the TinyGo gates): for each of wasmtime / wasmer / wazero
 *      found on PATH, run the module and require byte-identical stdout to the `deno run` JS baseline.
 *
 * A fixture PASSES when the invariant holds AND every present runtime matches the baseline. Absent
 * runtimes are reported as skipped, not failed.
 *
 * Usage: deno run --allow-read --allow-run --allow-write --allow-env tests/dync_cross_runtime_tests.ts [folder]
 */

import { join, parse } from "jsr:@std/path";
import { bold, cyan, dim, green, magenta, red, yellow } from "jsr:@std/fmt/colors";

const WASMTK_BIN = "wasmtk";

/**
 * The standalone runtimes this gate compares against, and how each is invoked.
 *
 * A table, not a bare name list, because runtimes do not share one argv shape: these three take
 * `<rt> run <module>`, but e.g. wazmrt takes `<rt> <module>` and wasmrt `<rt> wasi <module>`.
 * Hardcoding `run` would pass "run" as the module path to such a runtime, which reads as a runtime
 * bug rather than a harness bug.
 *
 * wazmrt and wasmrt are deliberately NOT listed (owner ruling 2026-09-28): they carry their own
 * testing against these fixtures and are not gated from here. To check one locally, add a row and
 * point `<NAME>_BIN` at its build.
 *
 * Each binary may be overridden by `<NAME>_BIN` (e.g. `WASMTIME_BIN=…/wasmtime.exe`), so a runtime
 * built from source can be gated without first installing it onto PATH.
 */
const RUNTIMES = [
  { name: "wasmtime", runArgs: (wasm: string) => ["run", wasm] },
  { name: "wasmer", runArgs: (wasm: string) => ["run", wasm] },
  { name: "wazero", runArgs: (wasm: string) => ["run", wasm] },
] as const;

/** The executable to invoke for a runtime — `<NAME>_BIN` if set, else the bare name from PATH. */
const binFor = (name: string): string => Deno.env.get(`${name.toUpperCase()}_BIN`) ?? name;
const targetDir = Deno.args[0] ?? join(import.meta.dirname ?? Deno.cwd(), "wasi", "wasm_wasi_dync");

async function capture(
  cmd: string,
  args: string[],
): Promise<{ ok: boolean; out: string; ms: number }> {
  const t0 = performance.now();
  try {
    const { success, stdout } = await new Deno.Command(cmd, {
      args,
      stdout: "piped",
      stderr: "null",
    }).output();
    return { ok: success, out: new TextDecoder().decode(stdout), ms: performance.now() - t0 };
  } catch (err) {
    return {
      ok: false,
      out: err instanceof Error ? err.message : String(err),
      ms: performance.now() - t0,
    };
  }
}

/** True if `cmd` is invocable on this machine (used for skip-if-absent). */
async function have(cmd: string): Promise<boolean> {
  try {
    // `--version` is a cheap, side-effect-free probe supported by all three runtimes.
    await new Deno.Command(cmd, { args: ["--version"], stdout: "null", stderr: "null" }).output();
    return true;
  } catch {
    return false;
  }
}

/** The distinct import module names of a compiled `.wasm` (e.g. ["wasi_snapshot_preview1"]). */
async function importModules(wasmPath: string): Promise<string[]> {
  const bytes = await Deno.readFile(wasmPath);
  const mod = await WebAssembly.compile(bytes);
  const mods = WebAssembly.Module.imports(mod).map((i) => i.module);
  return [...new Set(mods)].sort();
}

async function main() {
  let dir: string;
  try {
    dir = await Deno.realPath(targetDir);
  } catch {
    console.error(red(`Directory not found: ${targetDir}`));
    Deno.exit(1);
  }

  const present = new Set<string>();
  for (const rt of RUNTIMES) if (await have(binFor(rt.name))) present.add(rt.name);

  console.log(magenta(bold("\n🌐 dync Cross-Runtime Portability Gate (pure-WASI on any runtime)")));
  console.log(cyan(`   Directory: ${dir}`));
  console.log(
    cyan(
      `   Runtimes : ${
        RUNTIMES.map((r) => (present.has(r.name) ? green(r.name) : dim(`${r.name} (absent)`)))
          .join("  ")
      }\n`,
    ),
  );

  const files: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && entry.name.endsWith(".ts") && !entry.name.startsWith("run_")) {
      files.push(entry.name);
    }
  }
  files.sort();

  let passed = 0;
  let failed = 0;
  /** Per-runtime wall-clock of each matching run, for the indicative speed summary below. */
  const timing = new Map<string, number[]>();

  for (const file of files) {
    const { name } = parse(file);
    const tsPath = join(dir, file);
    const wasmPath = join(dir, `${name}.wasm`);
    console.log(yellow(bold(`── ${file}`)));

    const compile = await capture(WASMTK_BIN, ["dync", tsPath]);
    if (!compile.ok) {
      console.log(red("  ✗ dync compile failed"));
      console.log(red(`❌ ${file} FAILED\n`));
      failed++;
      continue;
    }

    // 1. INVARIANT — pure-WASI imports.
    let ok = true;
    const mods = await importModules(wasmPath);
    const pureWasi = mods.length > 0 && mods.every((m) => m === "wasi_snapshot_preview1");
    if (pureWasi) {
      console.log(green(`  ✓ pure-WASI imports  [${mods.join(", ")}]`));
    } else {
      console.log(red(`  ✗ non-WASI import module(s): [${mods.join(", ")}]`));
      ok = false;
    }

    // 2. EXECUTION — byte-identical stdout under each present runtime (skip-if-absent).
    if (present.size === 0) {
      console.log(dim("  ~ execution skipped (no external runtime on PATH)"));
    } else {
      const baseline = await capture("deno", ["run", "--quiet", tsPath]);
      if (!baseline.ok) {
        console.log(red("  ✗ baseline (deno run) failed"));
        ok = false;
      } else {
        for (const rt of RUNTIMES) {
          if (!present.has(rt.name)) continue;
          const run = await capture(binFor(rt.name), rt.runArgs(wasmPath));
          if (run.ok && run.out === baseline.out) {
            const seen = timing.get(rt.name) ?? [];
            seen.push(run.ms);
            timing.set(rt.name, seen);
            console.log(green(`  ✓ ${rt.name} == baseline`) + dim(`  ${run.ms.toFixed(0)} ms`));
          } else {
            console.log(red(`  ✗ ${rt.name} mismatch:`));
            console.log(dim("  --- baseline ---\n" + baseline.out));
            console.log(dim(`  --- ${rt.name} ---\n` + run.out));
            ok = false;
          }
        }
      }
    }

    if (ok) {
      console.log(green(`✅ ${file} PASSED\n`));
      passed++;
    } else {
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

  // Indicative speed comparison. NOT a benchmark: this is single-shot wall-clock per fixture and
  // includes process spawn, which dominates for small modules — it tells you the ORDER, not the
  // margin. Only runs whose output matched the baseline are counted, so a wrong-but-fast runtime
  // cannot look good here.
  if (timing.size > 0) {
    const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
    const rows = [...timing.entries()]
      .map(([name, xs]) => ({ name, avg: mean(xs), n: xs.length }))
      .sort((a, b) => a.avg - b.avg);
    const best = rows[0].avg;
    console.log(
      cyan(bold("\n  ⏱  Wall-clock per run (mean, incl. process spawn — indicative only)")),
    );
    for (const r of rows) {
      const rel = r.avg === best ? green("fastest") : dim(`${(r.avg / best).toFixed(2)}× slower`);
      console.log(
        `     ${r.name.padEnd(10)} ${String(r.avg.toFixed(0)).padStart(5)} ms  (n=${r.n})  ${rel}`,
      );
    }
    console.log("");
  }

  if (failed > 0) Deno.exit(1);
}

if (import.meta.main) await main();
