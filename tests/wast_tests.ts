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
 *   deno run --allow-read --allow-write --allow-run --allow-env --allow-net tests/wast_tests.ts
 *
 * `--allow-run` is required since 2026-09-28: the gate re-runs itself with the experimental V8
 * flags in `GATE_V8_FLAGS` (see below). Without it the run continues unflagged and
 * `wide-arithmetic.wast` goes OFF BASELINE, loudly.
 */
import { runWast } from "../src/wast.ts";
import { join } from "jsr:@std/path@1.0.2";
import { walk } from "jsr:@std/fs@1.0.0/walk";
import wabtInit from "wabt";

// ── Experimental V8 features for the GATE ONLY (owner decision 2026-09-28) ─────────────────────
// The corpus has proposal files V8 implements only behind a flag. The gate turns them on, so those
// files are measured rather than skipped. The `wasmtk wast` CLI deliberately does NOT: users get
// the stable engine. V8 flags cannot be set at runtime, so when the feature is absent this script
// re-runs itself with the flag. It detects the feature, not an env marker, so it cannot loop and
// cannot be fooled. Without `--allow-run` it continues unflagged, and the baselined
// `wide-arithmetic.wast` counts then fail the gate LOUDLY rather than skipping quietly.
//
// Each flag has a PROBE module that V8 validates only when the feature is on (checked both ways).
//
// A feature WITH A `scope` is turned on only for corpus files under that directory, in their own
// subprocess. A feature that CHANGES core semantics must be scoped: `custom-descriptors` relaxes
// `br_on_cast`'s type rule, so with it on, three `assert_invalid` modules in each of the CORE
// `br_on_cast.wast` / `br_on_cast_fail.wast` validate and the core files lose 6 passes (measured
// 2026-09-28). Core files are measured on core semantics; the proposal's own files carry the new
// rule. `custom-descriptors` joined 2026-09-28 with binaryang 1.7.0, which assembles the proposal:
// every module built, and V8 alone refused them unflagged. (`custom-page-sizes` has no V8 flag in
// this engine; it stays an engine limit.)
interface GateFeature {
  flag: string;
  probe: string;
  /** Corpus directory (relative, trailing `/`) the flag is limited to; absent = every file. */
  scope?: string;
}
const GATE_V8_FEATURES: GateFeature[] = [
  {
    flag: "--experimental-wasm-wide-arithmetic",
    probe: "(module (func (param i64 i64 i64 i64) (result i64 i64) " +
      "(i64.add128 (local.get 0) (local.get 1) (local.get 2) (local.get 3))))",
  },
  {
    flag: "--experimental-wasm-custom-descriptors",
    probe: "(module (type $s (struct)) (func (param (ref null (exact $s)))))",
    scope: "proposals/custom-descriptors/",
  },
];
/** Features every file gets: the gate process itself runs with these. */
const BASE_FEATURES = GATE_V8_FEATURES.filter((f) => !f.scope);
const GATE_V8_FLAGS = BASE_FEATURES.map((f) => f.flag);
/** The features a corpus file runs under (base + any whose scope contains it). */
const featuresFor = (rel: string): GateFeature[] =>
  GATE_V8_FEATURES.filter((f) => !f.scope || rel.startsWith(f.scope));
const isScoped = (rel: string): boolean =>
  GATE_V8_FEATURES.some((f) => f.scope !== undefined && rel.startsWith(f.scope));

/** Of `features`, the ones this V8 does NOT have on right now. */
async function missingFeatures(features: GateFeature[] = BASE_FEATURES): Promise<string[]> {
  // deno-lint-ignore no-explicit-any
  const wabt: any = await (wabtInit as any)();
  const missing: string[] = [];
  for (const { flag, probe: text } of features) {
    const probe = wabt.parseWat("probe.wat", text, { enable_all: true });
    try {
      if (!WebAssembly.validate(new Uint8Array(probe.toBinary({}).buffer))) missing.push(flag);
    } finally {
      probe.destroy();
    }
  }
  return missing;
}

// One level of re-execution only. If the flagged child STILL lacks a feature (a future V8 that
// dropped or renamed a flag), it must not re-run itself forever: it continues, and the files that
// need the feature go OFF BASELINE loudly.
const REEXEC_MARK = "WASMTK_WAST_GATE_REEXEC";
const missing = await missingFeatures();
if (missing.length > 0 && Deno.env.get(REEXEC_MARK) === "1") {
  console.error(
    `⚠️  still missing after re-running with V8 flags: ${missing.join(" ")} — this V8 no longer ` +
      "accepts them; the files that need them will go OFF BASELINE.",
  );
} else if (missing.length > 0) {
  const self = new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
  try {
    const { code } = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        "--allow-write",
        "--allow-net",
        "--allow-run",
        "--allow-env",
        `--v8-flags=${GATE_V8_FLAGS.join(",")}`,
        self,
        ...Deno.args,
      ],
      env: { [REEXEC_MARK]: "1" },
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    }).output();
    Deno.exit(code);
  } catch (e) {
    console.error(
      `⚠️  could not re-run with ${GATE_V8_FLAGS.join(" ")} (${
        e instanceof Error ? e.message : e
      });` +
        " continuing without them — the files that need them will go OFF BASELINE.",
    );
  }
}

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
// `which` is `base` (skip scoped files) or `scoped` (only scoped files; the parent started this
// process with their flags, and a missing one is fatal rather than a quiet unflagged scan).
if (Deno.args[0] === "--scan-chunk") {
  const [, startS, countS, outPath, which] = Deno.args;
  const files = (await corpusFiles()).slice(Number(startS), Number(startS) + Number(countS))
    .filter((rel) => (which === "scoped") === isScoped(rel));
  const acc: Record<string, { pass: number; skip: number; failed: number; unbuilt: number }> = {};
  for (const rel of files) {
    const missingHere = await missingFeatures(featuresFor(rel));
    if (missingHere.length > 0) {
      console.error(`scoped features missing for ${rel}: ${missingHere.join(" ")}`);
      Deno.exit(2);
    }
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

// ── --run-one (internal) ──────────────────────────────────────────────────────────────────────
// Runs ONE scoped corpus file for the normal gate run, in a process started with that file's
// scoped flags, and writes the result the gate compares. Missing a feature is fatal (exit 2), so a
// scoped file can never be measured unflagged by accident.
if (Deno.args[0] === "--run-one") {
  const [, rel, outPath] = Deno.args;
  const missingHere = await missingFeatures(featuresFor(rel));
  if (missingHere.length > 0) {
    console.error(`scoped features missing for ${rel}: ${missingHere.join(" ")}`);
    Deno.exit(2);
  }
  const r = await runWast(join(SUITE, rel), { maxFailures: 5 });
  await Deno.writeTextFile(
    outPath,
    JSON.stringify({
      passed: r.passed,
      failed: r.failed,
      skipped: r.skipped,
      modulesFailed: r.modulesFailed,
      failures: r.failures,
      validatorRejectedValid: r.validatorRejectedValid,
    }),
  );
  Deno.exit(0);
}

/** Deno args to run this script in a child with `rel`'s full flag set. */
const SELF = new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const childArgs = (flags: string[], ...rest: string[]): string[] => [
  "run",
  "--allow-read",
  "--allow-write",
  "--allow-net",
  "--allow-run",
  "--allow-env",
  `--v8-flags=${flags.join(",")}`,
  SELF,
  ...rest,
];

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
  const tmp = await Deno.makeTempDir();
  const merged: Record<string, { pass: number; skip: number; failed: number; unbuilt: number }> =
    {};
  const unrunnable: string[] = [];

  // `which`: "base" scans a chunk's unscoped files under the base flags; "scoped" scans one scoped
  // file under its own flags.
  async function scan(
    start: number,
    count: number,
    which: "base" | "scoped" = "base",
  ): Promise<boolean> {
    const out = join(tmp, `c${start}_${count}_${which}.json`);
    const flags = which === "scoped" ? featuresFor(files[start]).map((f) => f.flag) : GATE_V8_FLAGS;
    const cmd = new Deno.Command(Deno.execPath(), {
      args: childArgs(flags, "--scan-chunk", String(start), String(count), out, which),
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
    for (let j = i; j < i + n; j++) {
      if (isScoped(files[j]) && !(await scan(j, 1, "scoped"))) {
        unrunnable.push(files[j]);
        console.log(red(`    UNRUNNABLE under its scoped flags: ${files[j]}`));
      }
    }
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
  let r: {
    passed: number;
    failed: number;
    skipped: number;
    modulesFailed: number;
    failures: string[];
    validatorRejectedValid: string[];
  };
  try {
    if (isScoped(rel)) {
      // Its scoped flags cannot be turned on in this process: run it in a child that has them.
      const out = await Deno.makeTempFile({ suffix: ".json" });
      try {
        const flags = featuresFor(rel).map((f) => f.flag);
        const { code, stderr } = await new Deno.Command(Deno.execPath(), {
          args: childArgs(flags, "--run-one", rel, out),
          stdout: "null",
          stderr: "piped",
        }).output();
        if (code !== 0) {
          throw new Error(
            `scoped run exited ${code}: ${new TextDecoder().decode(stderr).trim().slice(0, 200)}`,
          );
        }
        r = JSON.parse(await Deno.readTextFile(out));
      } finally {
        await Deno.remove(out);
      }
    } else {
      r = await runWast(join(SUITE, rel), { maxFailures: 5 });
    }
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
  // Not a baseline number: an invariant. binaryang's validator is the second `assert_invalid`
  // oracle (2026-09-29), and it may only be trusted while it rejects NO module the spec calls valid;
  // one such rejection means its other rejections can be manufacturing passes.
  if (r.validatorRejectedValid.length > 0) {
    drift.push(`binaryang's validator rejected ${r.validatorRejectedValid.length} VALID module(s)`);
    r.failures = [...r.validatorRejectedValid, ...r.failures];
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
