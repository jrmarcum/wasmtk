/**
 * engine_cross_check_tests.ts — the multi-engine conformance gate.
 *
 * WHY THIS EXISTS. On 2026-08-24 the sibling wabt-ts project reported that every module wasic builds
 * from a TypeScript `try`/`catch`/`finally` is REJECTED by wasmtime — it lowers to the superseded
 * *legacy* exception-handling proposal, which wasmtime implements in no configuration. Ten corpus
 * modules were affected. The wasi suite was **417/417 green** throughout, and had been for months.
 *
 * It stayed invisible because every oracle we owned was V8: `wasi_tests.ts` executes on V8, and
 * `wasmtk wast` validates through host V8 as well. V8 still accepts legacy EH. One engine wearing
 * two hats is one data point, not two — so a defect that only a *different* engine can see was
 * structurally unreachable by our own tests. See cmem/best-practices.md §3: "a round-trip proves
 * agreement with yourself; when a bug can only be seen by a third party, the test has to BE a third
 * party."
 *
 * WHAT IT DOES. For every built `.wasm` in the corpus, run it on V8 (via `wasmtk run`) and on each
 * standalone engine present on PATH, then compare stdout byte-for-byte. Divergence is the signal:
 * an engine that REJECTS what V8 runs is exactly the class above.
 *
 * PER-MODULE BASELINE, not a pass count. Expected per-engine status lives in
 * `tests/engine_baseline.json`. Every module must land on its recorded status:
 *   - a module that regresses (was `match`, now `reject`/`differ`) FAILS — a real break.
 *   - a module that IMPROVES also FAILS, loudly, until the baseline is re-recorded. The 10 legacy-EH
 *     modules are pinned at `reject` precisely so that the day the `try_table` migration lands, this
 *     gate SAYS SO instead of quietly absorbing the win.
 * Same discipline as `wast_tests.ts`; see cmem/testing.md.
 *
 * ENGINE NOTES, measured 2026-08-24:
 *   - wasmtime 47.0.3 — the reference for this gate. WASI Preview 1 + 2 host; `exceptions` (the
 *     modern `try_table` proposal) is ON BY DEFAULT, and there is no `-W legacy-exceptions` at all.
 *   - wasmer 7.2.1 — NO exception-handling support in any backend, legacy *or* `try_table`. It
 *     reports "No backends support the required features" for both, so it can never judge an EH
 *     module and its verdict on one carries no information. Recorded honestly rather than excluded
 *     by name, so the day a wasmer backend gains EH the baseline shift is visible.
 *   - wazero — present here; recorded like any other engine.
 *
 * Absent engines are SKIPPED, never failed (same convention as dync_cross_runtime_tests.ts).
 *
 *   deno run --allow-read --allow-run --allow-env --allow-write tests/engine_cross_check_tests.ts
 *   deno run … tests/engine_cross_check_tests.ts --update-baseline
 *   deno run … tests/engine_cross_check_tests.ts --filter "^15_"     # scope to a subset
 */
import { join } from "jsr:@std/path@1.0.2";

const WASMTK_BIN = "wasmtk";
const ENGINES = ["wasmtime", "wasmer", "wazero"] as const;
const CORPUS = join(import.meta.dirname ?? ".", "wasi", "wasm_wasi");
const BASELINE = join(import.meta.dirname ?? ".", "engine_baseline.json");

const green = (s: string) => `\x1b[32m${s}\x1b[39m`;
const red = (s: string) => `\x1b[31m${s}\x1b[39m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[39m`;
const cyan = (s: string) => `\x1b[36m${s}\x1b[39m`;
const dim = (s: string) => `\x1b[90m${s}\x1b[39m`;

/** `match` = same stdout as V8. `reject` = engine refused it. `differ` = ran, wrong output. */
type Status = "match" | "reject" | "differ";
/** module -> engine -> expected status. Engines absent at record time simply have no key. */
type Baseline = Record<string, Record<string, Status>>;

const args = Deno.args;
const updating = args.includes("--update-baseline");
const filterIdx = args.indexOf("--filter");
const filter = filterIdx !== -1 ? new RegExp(args[filterIdx + 1]) : null;

async function capture(cmd: string, cmdArgs: string[]): Promise<{ ok: boolean; out: string }> {
  try {
    const { success, stdout } = await new Deno.Command(cmd, {
      args: cmdArgs,
      stdout: "piped",
      stderr: "null",
    }).output();
    return { ok: success, out: new TextDecoder().decode(stdout) };
  } catch (err) {
    return { ok: false, out: err instanceof Error ? err.message : String(err) };
  }
}

/** True if `cmd` is invocable here — used for skip-if-absent, never for failing. */
async function have(cmd: string): Promise<boolean> {
  try {
    await new Deno.Command(cmd, { args: ["--version"], stdout: "null", stderr: "null" }).output();
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const present: string[] = [];
  for (const e of ENGINES) if (await have(e)) present.push(e);

  const modules: string[] = [];
  try {
    for await (const entry of Deno.readDir(CORPUS)) {
      if (entry.isFile && entry.name.endsWith(".wasm")) modules.push(entry.name.slice(0, -5));
    }
  } catch {
    console.log(red(`  ✗ corpus not found: ${CORPUS}`));
    console.log(dim("    build it first:  deno run … tests/wasi_tests.ts"));
    Deno.exit(1);
  }
  modules.sort();
  const targets = filter ? modules.filter((m) => filter.test(m)) : modules;

  console.log(cyan("\n🌐 Multi-engine cross-check — V8 (wasmtk run) vs standalone engines"));
  console.log(
    cyan(
      `   Engines: ${
        ENGINES.map((e) => (present.includes(e) ? green(e) : dim(`${e} (absent)`))).join("  ")
      }`,
    ),
  );
  console.log(cyan(`   Modules: ${targets.length}${filter ? ` (filtered)` : ""}\n`));

  if (present.length === 0) {
    console.log(yellow("  ⚠ no standalone engine on PATH — nothing to cross-check, skipping."));
    Deno.exit(0);
  }

  let baseline: Baseline = {};
  if (!updating) {
    try {
      baseline = JSON.parse(await Deno.readTextFile(BASELINE));
    } catch {
      console.log(red(`  ✗ cannot read ${BASELINE} — record it first with --update-baseline`));
      Deno.exit(1);
    }
  }

  const observed: Baseline = {};
  let regressed = 0, improved = 0, ok = 0, unpinned = 0;

  for (const name of targets) {
    const wasm = join(CORPUS, `${name}.wasm`);
    const v8 = await capture(WASMTK_BIN, ["run", wasm]);
    if (!v8.ok) {
      // V8 itself cannot run it — nothing to compare against, so this gate has no opinion.
      console.log(dim(`  – ${name}  (V8 could not run it; out of scope here)`));
      continue;
    }
    observed[name] = {};
    for (const engine of present) {
      // `run <file>` is the uniform invocation across all three — matching
      // dync_cross_runtime_tests.ts. It is NOT cosmetic: wazero requires the subcommand and answers
      // a bare path with "invalid command", which this gate would otherwise have recorded as a
      // legitimate `reject` for every module in the corpus.
      const r = await capture(engine, ["run", wasm]);
      const status: Status = !r.ok ? "reject" : (r.out === v8.out ? "match" : "differ");
      observed[name][engine] = status;
      if (updating) continue;

      const want = baseline[name]?.[engine];
      if (want === undefined) {
        unpinned++;
        console.log(dim(`  ? ${name} [${engine}] ${status} — not in baseline`));
      } else if (want === status) {
        ok++;
      } else if (want === "match") {
        regressed++;
        console.log(red(`  ✗ ${name} [${engine}] REGRESSED: ${want} → ${status}`));
      } else if (status === "match") {
        improved++;
        console.log(yellow(`  ⚠ ${name} [${engine}] IMPROVED: ${want} → ${status} — re-record`));
      } else {
        regressed++;
        console.log(red(`  ✗ ${name} [${engine}] CHANGED: ${want} → ${status}`));
      }
    }
  }

  if (updating) {
    await Deno.writeTextFile(BASELINE, JSON.stringify(observed, null, 2) + "\n");
    const tally: Record<string, number> = {};
    for (const m of Object.values(observed)) {
      for (const [e, s] of Object.entries(m)) tally[`${e}:${s}`] = (tally[`${e}:${s}`] ?? 0) + 1;
    }
    console.log(green(`  wrote ${BASELINE} — ${Object.keys(observed).length} modules`));
    for (const k of Object.keys(tally).sort()) console.log(dim(`    ${k} = ${tally[k]}`));
    Deno.exit(0);
  }

  console.log("\n" + "─".repeat(60));
  console.log(
    `  engine cross-check: ${ok} on-baseline, ${regressed} regressed, ${improved} improved`,
  );
  if (unpinned) console.log(dim(`  ${unpinned} module/engine pair(s) not in the baseline`));
  if (regressed || improved) {
    console.log(`  re-record deliberately once the change is understood:`);
    console.log(
      `    deno run --allow-read --allow-run --allow-env --allow-write ` +
        `tests/engine_cross_check_tests.ts --update-baseline`,
    );
    console.log(red(`  ❌ ${regressed + improved} off-baseline`));
    Deno.exit(1);
  }
  console.log(green(`  ✅ ALL ON BASELINE`));
  Deno.exit(0);
}

await main();
