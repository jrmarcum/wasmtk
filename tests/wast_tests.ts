/**
 * wast_tests.ts — regression gate for the `.wast` spec-script runner (`src/wast.ts`).
 *
 * Runs the official WebAssembly spec testsuite `.wast` files (under
 * tests/module/wasm_wast/testsuite-main/) and gates on a **per-file baseline** of expected passing
 * EXECUTION assertions, stored in `tests/wast_baseline.json`.
 *
 * WHY PER-FILE, NOT A TOTAL (changed 2026-08-20). The gate used to assert only `failed === 0` plus a
 * single global floor (`totalPass >= 10000` against a total of ~12444). That could not see a file
 * losing coverage: when the 2026-08-20 corpus sync took `return_call.wast` from 44 passes to 12 (a
 * wabt-ts parse gap turned its module unassemblable, so every dependent assertion became a SKIP),
 * the total stayed above the floor and the gate still printed ALL CLEAN. A module that fails to
 * assemble is counted as a skip by design — which means silent coverage loss looks exactly like
 * success. The corpus could have shed ~2400 more passes without a peep.
 *
 * So: every baselined file must produce EXACTLY its baseline pass count AND failure count.
 *   - fewer passes → FAIL. Coverage lost (toolchain regression, or a refresh retiring tests).
 *   - more passes  → FAIL. Good news, but the baseline is stale — re-record it deliberately.
 *   - failure count changed in EITHER direction → FAIL. A new failure is a regression; a vanished
 *     one is a win that must be re-recorded rather than silently pocketed.
 *
 * A baseline of 0 is meaningful and intentional: it pins a file whose modules the toolchain cannot
 * currently assemble at all (e.g. `ref_null.wast` — wabt-ts 1.3.5 cannot encode `ref.null` for any
 * heap type; see cmem/compiler-bugs.md). Pinning it at 0 means the day the backend learns to encode
 * it, this gate says so instead of silently absorbing the win.
 *
 * Updating the baseline is a deliberate, reviewable act — it rewrites a tracked JSON file:
 *
 *   deno run --allow-read --allow-write --allow-net --allow-run tests/wast_tests.ts --update-baseline
 *
 * That rescans the WHOLE corpus. `--allow-run` is needed because it chunks across subprocesses —
 * see the comment above `--update-baseline` for why.
 *
 * KNOWN-FAILING FILES ARE PINNED, NOT EXCLUDED (owner decision 2026-08-24: they fail LOUDLY).
 * They were previously left out of the baseline entirely, which made them invisible: they could
 * gain failures, lose passes, or go completely dark and nothing said so. Each is now pinned at its
 * exact failure count and printed in RED on every run. The gate still exits 0 while they sit at
 * their pinned counts — a gate that can never pass is not a gate — but the summary reports the
 * failure total rather than claiming everything is clean.
 *
 * Read `unbuilt-modules` next to the failure count. Nearly every known failure is a CASCADE from a
 * module the toolchain could not assemble, tagged `[cascade]` by the runner. Rank remediation by
 * the module count, not the failure count: `type-equivalence.wast` shows 1 failure and **13**
 * unbuilt modules.
 *
 *   deno run --allow-read --allow-net tests/wast_tests.ts
 */
import { runWast } from "../src/wast.ts";
import { join } from "jsr:@std/path@1.0.2";
import { walk } from "jsr:@std/fs@1.0.0/walk";

const SUITE = join(import.meta.dirname ?? ".", "module", "wasm_wast", "testsuite-main");
const BASELINE = join(import.meta.dirname ?? ".", "wast_baseline.json");

const green = (s: string) => `\x1b[32m${s}\x1b[39m`;
const red = (s: string) => `\x1b[31m${s}\x1b[39m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[39m`;
const dim = (s: string) => `\x1b[90m${s}\x1b[39m`;

type Entry = { pass: number; skip: number; fail?: number; unbuilt?: number };

/** Every `.wast` in the corpus, as forward-slashed paths relative to SUITE, sorted. */
async function corpusFiles(): Promise<string[]> {
  const names: string[] = [];
  const bs = String.fromCharCode(92);
  for await (const e of walk(SUITE, { exts: [".wast"], includeDirs: false })) {
    names.push(e.path.split(bs).join("/").slice(SUITE.split(bs).join("/").length + 1));
  }
  return names.sort();
}

// ── --scan-chunk (internal) ───────────────────────────────────────────────────────────────
// Runs a slice of the corpus and writes JSON. Spawned by --update-baseline; not for direct use.
if (Deno.args[0] === "--scan-chunk") {
  const [, startS, countS, outPath] = Deno.args;
  const files = (await corpusFiles()).slice(Number(startS), Number(startS) + Number(countS));
  const acc: Record<string, { pass: number; skip: number; failed: number; unbuilt: number }> = {};
  for (const rel of files) {
    try {
      const r = await runWast(join(SUITE, rel), { maxFailures: 0 });
      acc[rel] = { pass: r.passed, skip: r.skipped, failed: r.failed, unbuilt: r.modulesFailed };
    } catch {
      // A file that throws is simply absent from this chunk's output.
    }
  }
  await Deno.writeTextFile(outPath, JSON.stringify(acc));
  Deno.exit(0);
}

// ── --update-baseline ────────────────────────────────────────────────────────────────────────
//
// Runs the corpus in CHUNKED SUBPROCESSES rather than in one pass. That is not defensive
// programming for its own sake: the runner's memory grows across files badly enough that a
// single-process scan of the full corpus dies with "Fatal JavaScript out of memory", and at least
// one file (proposals/custom-descriptors/exact.wast) exhausts the heap on its own. An OOM cannot be
// caught in-process, so one bad file would otherwise abort the whole rescan and lose every result.
//
// Chunking also makes the unrunnable set SELF-DISCOVERING: when a chunk dies it is retried one file
// at a time, and whatever kills its own subprocess is reported and left out. No hand-maintained
// skip list to go stale. The underlying memory bug is the real fix — see cmem/compiler-bugs.md.
if (Deno.args.includes("--update-baseline")) {
  const files = await corpusFiles();
  const CHUNK = 20;
  const self = new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
  const tmp = await Deno.makeTempDir();
  const merged: Record<string, { pass: number; skip: number; failed: number; unbuilt: number }> =
    {};
  const unrunnable: string[] = [];

  async function scan(start: number, count: number): Promise<boolean> {
    const out = join(tmp, `c${start}_${count}.json`);
    const cmd = new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        "--allow-write",
        "--allow-net",
        self,
        "--scan-chunk",
        String(start),
        String(count),
        out,
      ],
      stdout: "null",
      stderr: "null",
    });
    if (!(await cmd.output()).success) return false;
    try {
      Object.assign(merged, JSON.parse(await Deno.readTextFile(out)));
      return true;
    } catch {
      return false;
    }
  }

  console.log(`Rescanning ${files.length} corpus files in chunks of ${CHUNK}…`);
  for (let i = 0; i < files.length; i += CHUNK) {
    const n = Math.min(CHUNK, files.length - i);
    if (await scan(i, n)) continue;
    console.log(yellow(`  chunk ${i}..${i + n - 1} died — retrying file by file to isolate it`));
    for (let j = i; j < i + n; j++) {
      if (!(await scan(j, 1))) {
        unrunnable.push(files[j]);
        console.log(red(`    UNRUNNABLE (crashes its own process): ${files[j]}`));
      }
    }
  }
  await Deno.remove(tmp, { recursive: true });

  const next: Record<string, Entry> = {};
  let withFailures = 0;
  for (const rel of files) {
    const r = merged[rel];
    if (!r) continue;
    // Files WITH failures used to be excluded here, which made them invisible to the gate: they
    // could gain failures, lose passes, or go entirely dark and nothing would say so. They are now
    // PINNED WITH THEIR FAILURE COUNT and reported in red on every run — loud, and unable to drift.
    const e: Entry = { pass: r.pass, skip: r.skip };
    if (r.failed > 0) {
      e.fail = r.failed;
      withFailures++;
      console.log(yellow(`  pinned WITH ${r.failed} failure(s): ${rel}`));
    }
    if (r.unbuilt > 0) e.unbuilt = r.unbuilt;
    next[rel] = e;
  }
  await Deno.writeTextFile(BASELINE, JSON.stringify(next, null, 2) + "\n");
  const totalPass = Object.values(next).reduce((a, b) => a + b.pass, 0);
  console.log(
    green(
      `\n  wrote ${BASELINE} — ${Object.keys(next).length} files, ${totalPass} passing assertions`,
    ),
  );
  console.log(
    dim(
      `  ${withFailures} file(s) pinned WITH failures (loud, not excluded); ${unrunnable.length} unrunnable`,
    ),
  );
  Deno.exit(0);
}

// ── normal gate run ──────────────────────────────────────────────────────────────────────────────
let baseline: Record<string, Entry>;
try {
  baseline = JSON.parse(await Deno.readTextFile(BASELINE));
} catch (e) {
  console.log(red(`  ✗ cannot read ${BASELINE}: ${e instanceof Error ? e.message : e}`));
  console.log(
    `    Regenerate it with:  deno run --allow-read --allow-write --allow-net tests/wast_tests.ts --update-baseline`,
  );
  Deno.exit(1);
}

const names = Object.keys(baseline).sort();
let totalPass = 0, totalFail = 0, totalSkip = 0, badFiles = 0;
const drifted: string[] = [];

for (const rel of names) {
  const want = baseline[rel];
  let r;
  try {
    r = await runWast(join(SUITE, rel), { maxFailures: 5 });
  } catch (e) {
    console.log(red(`  ✗ ${rel} — could not run: ${e instanceof Error ? e.message : e}`));
    badFiles++;
    continue;
  }
  totalPass += r.passed;
  totalFail += r.failed;
  totalSkip += r.skipped;

  // Check all THREE dimensions independently and collect every mismatch.
  //
  // This was an if/else chain until an audit on 2026-08-24 found two holes in it, both of the same
  // shape the per-file rework exists to close — a coverage collapse that no column reports:
  //
  //   1. The known-failing branch SHORT-CIRCUITED the pass check. `linking.wast` is pinned at 4
  //      failures / 120 passes; had its passes fallen to 50 with failures still 4, the chain
  //      printed "KNOWN FAILING" and the gate went green.
  //   2. `unbuilt` was recorded into 159 entries and NEVER COMPARED. It matters most exactly where
  //      the pass check is toothless: 71 files are pinned at pass == 0, so their pass count cannot
  //      drop, and 66 of those have unbuilt > 0. `table_copy.wast` (pass 0, unbuilt 51) could have
  //      gone to 100 unbuilt modules silently.
  //
  // An `else if` chain is the wrong shape for independent invariants: it reports the first and
  // hides the rest. Collect, then report.
  const wantFail = want.fail ?? 0;
  const wantUnbuilt = want.unbuilt ?? 0;
  const drift: string[] = [];
  if (r.failed !== wantFail) drift.push(`failures ${wantFail} → ${r.failed}`);
  if (r.passed !== want.pass) drift.push(`passes ${want.pass} → ${r.passed}`);
  if (r.modulesFailed !== wantUnbuilt) {
    drift.push(`unbuilt modules ${wantUnbuilt} → ${r.modulesFailed}`);
  }

  if (drift.length > 0) {
    // Any movement is a hard fail, in either direction: a regression must not pass, and an
    // improvement must be re-recorded deliberately rather than silently pocketed.
    badFiles++;
    drifted.push(rel);
    console.log(red(`  ✗ ${rel} — OFF BASELINE: ${drift.join(", ")}`));
    for (const m of r.failures.slice(0, 3)) {
      console.log("      " + m.replace(/\s+/g, " ").slice(0, 120));
    }
  } else if (wantFail > 0) {
    // Known-failing and exactly on its pins. Loud by policy (owner decision 2026-08-24): printed in
    // red every run, never quietly excluded and never converted to skips.
    console.log(
      red(`  ✗ ${rel} — KNOWN FAILING: ${r.failed} failure(s) (pinned)`) +
        dim(`  pass=${r.passed} skip=${r.skipped} unbuilt-modules=${r.modulesFailed}`),
    );
    for (const m of r.failures.slice(0, 2)) {
      console.log("      " + dim(m.replace(/\s+/g, " ").slice(0, 118)));
    }
  } else {
    console.log(
      green(`  ✓ ${rel}`) + `  pass=${r.passed} skip=${r.skipped}` +
        (r.modulesFailed > 0 ? dim(` unbuilt-modules=${r.modulesFailed}`) : ""),
    );
  }
}

// Corpus files that are not pinned at all — cheap directory walk, no execution.
const ungated = (await corpusFiles()).filter((f) => !(f in baseline));

console.log("\n" + "─".repeat(60));
console.log(
  `  wast gate: ${names.length} files — ${totalPass} passed, ${totalFail} failed, ${totalSkip} skipped`,
);
if (ungated.length) {
  console.log(
    dim(
      `  ${ungated.length} corpus file(s) not in the baseline (known-bad or new) — e.g. ${
        ungated.slice(0, 3).join(", ")
      }`,
    ),
  );
}
if (drifted.length) {
  console.log(
    `  ${drifted.length} file(s) drifted from baseline. If the change is understood and wanted, re-record:`,
  );
  console.log(
    `    deno run --allow-read --allow-write --allow-net tests/wast_tests.ts --update-baseline`,
  );
}
if (badFiles === 0) {
  // Never print "ALL CLEAN" while known failures stand — that phrasing is what the whole per-file
  // rework exists to prevent. On baseline is the honest claim; the failure total stays in view.
  if (totalFail > 0) {
    console.log(
      green(`  ✅ ON BASELINE`) +
        red(` — ${totalFail} known failure(s) still standing, listed above`),
    );
  } else {
    console.log(green(`  ✅ ALL CLEAN`));
  }
  Deno.exit(0);
} else {
  console.log(red(`  ❌ ${badFiles} file(s) failing or off-baseline`));
  Deno.exit(1);
}
