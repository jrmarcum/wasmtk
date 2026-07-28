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
 *   2. EXECUTION (skip-if-absent, like the TinyGo gates): for each of wasmtime / wasmer / wazero found
 *      on PATH, run the module and require byte-identical stdout to the `deno run` JS baseline.
 *
 * A fixture PASSES when the invariant holds AND every present runtime matches the baseline. Absent
 * runtimes are reported as skipped, not failed.
 *
 * Usage: deno run --allow-read --allow-run --allow-write --allow-env tests/dync_cross_runtime_tests.ts [folder]
 */

import { join, parse } from "jsr:@std/path";
import { bold, cyan, dim, green, magenta, red, yellow } from "jsr:@std/fmt/colors";

const WASMTK_BIN = "wasmtk";
const RUNTIMES = ["wasmtime", "wasmer", "wazero"] as const;
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
  for (const rt of RUNTIMES) if (await have(rt)) present.add(rt);

  console.log(magenta(bold("\n🌐 dync Cross-Runtime Portability Gate (pure-WASI on any runtime)")));
  console.log(cyan(`   Directory: ${dir}`));
  console.log(
    cyan(
      `   Runtimes : ${
        RUNTIMES.map((r) => (present.has(r) ? green(r) : dim(`${r} (absent)`))).join("  ")
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
          if (!present.has(rt)) continue;
          const run = await capture(rt, ["run", wasmPath]);
          if (run.ok && run.out === baseline.out) {
            console.log(green(`  ✓ ${rt} == baseline`));
          } else {
            console.log(red(`  ✗ ${rt} mismatch:`));
            console.log(dim("  --- baseline ---\n" + baseline.out));
            console.log(dim(`  --- ${rt} ---\n` + run.out));
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
  if (failed > 0) Deno.exit(1);
}

if (import.meta.main) await main();
