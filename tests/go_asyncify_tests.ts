/**
 * go_asyncify_tests.ts — Goroutine Go with NO external binaryen
 *
 * Proves that TinyGo programs using goroutines + channels — which require
 * TinyGo's asyncify transform — build and run through `wasmtk run --lang=go`
 * with the in-house asyncify path (TinyGo's asyncify scheduler + a passthrough
 * wasm-opt shim + binaryen-ts's Asyncify pass, which resolves the in-wasm
 * `asyncify.*` control imports), i.e. WITHOUT any external `wasm-opt`/binaryen.
 *
 * Forced via `WASMTK_GO_BINARYEN_ASYNCIFY=1` so it exercises the binaryen-ts
 * path even on a machine that has a real `wasm-opt` on PATH.
 *
 * Coverage (B3, 2026-07-09) — the full TinyGo goroutine surface:
 *   worker-pool  — `go` + buffered channels + range/close                 (sum: 30)
 *   select_ch    — `select` over unbuffered channels fed by goroutines     (select-total: 300)
 *   sleep_ch     — `time.Sleep` in a goroutine (scheduler yields)          (sleep-result: 42)
 *   waitgroup    — `sync.WaitGroup` + `Mutex` + closure capture + defer    (wg-counter: 45)
 *   pipeline     — 3-stage fan-out with WaitGroup-driven channel close     (pipeline-total: 55)
 *   nested       — a goroutine that suspends on `inner.Wait()` INSIDE another
 *                  suspending goroutine (re-entrant suspension)            (nested-sum: 36)
 *
 * `nested/` was the reproducer for a binaryen-ts BINARY-DECODER bug (WT-2k, fixed
 * in binaryen-ts 1.4.2): the decoder reordered a value kept on the operand stack
 * (TinyGo's goroutine trampoline keeps the caller's `$__stack_pointer` there and
 * restores it via a trailing `global.set`) past the `global.set` that overwrote
 * it → a `global.set(global.get)` self-assign that corrupted the shadow stack and
 * trapped at the linear-memory boundary. NOT an asyncify bug — the fix spills the
 * reordered value to a temp local. See cmem/polyglot-producers.md § "Goroutine Go".
 *
 * GATED on TinyGo being installed (the CI image has none) — skips cleanly.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env --allow-net \
 *     tests/go_asyncify_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

const HERE = import.meta.dirname!;
const FIXTURE = join(HERE, "go_fixtures", "goroutines");
const WASMTK = "wasmtk";

/** Fixtures that MUST pass through the forced in-house binaryen-ts asyncify path. */
const INHOUSE: Array<{ name: string; src: string; expect: RegExp }> = [
  { name: "worker-pool", src: join(FIXTURE, "main.go"), expect: /sum:\s*30/ },
  { name: "select", src: join(FIXTURE, "select_ch", "main.go"), expect: /select-total:\s*300/ },
  { name: "time.Sleep", src: join(FIXTURE, "sleep_ch", "main.go"), expect: /sleep-result:\s*42/ },
  { name: "WaitGroup+Mutex", src: join(FIXTURE, "waitgroup", "main.go"), expect: /wg-counter:\s*45/ },
  { name: "pipeline", src: join(FIXTURE, "pipeline", "main.go"), expect: /pipeline-total:\s*55/ },
  { name: "nested (re-entrant suspend)", src: join(FIXTURE, "nested", "main.go"), expect: /nested-sum:\s*36/ },
];

let passed = 0;
let failed = 0;
function ok(desc: string, cond: boolean): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${desc}`);
  } else {
    failed++;
    console.error(`  ✗ ${desc}`);
  }
}

async function toolAvailable(cmd: string, args: string[]): Promise<boolean> {
  try {
    return (await new Deno.Command(cmd, { args, stdout: "null", stderr: "null" }).output()).success;
  } catch {
    return false;
  }
}

async function runGo(src: string, forceInhouse: boolean): Promise<{ success: boolean; text: string }> {
  const out = await new Deno.Command(WASMTK, {
    args: ["run", src],
    env: forceInhouse ? { WASMTK_GO_BINARYEN_ASYNCIFY: "1" } : {},
    stdout: "piped",
    stderr: "piped",
  }).output();
  const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);
  return { success: out.success, text };
}

async function main(): Promise<void> {
  console.log("── Goroutine Go via in-house asyncify (no external binaryen) ──");

  if (!await toolAvailable("tinygo", ["version"])) {
    console.log("  (skipped — TinyGo not on PATH)");
    return;
  }

  // ── Forced in-house asyncify path: the full working goroutine surface ──
  for (const f of INHOUSE) {
    const { success, text } = await runGo(f.src, /*forceInhouse*/ true);
    ok(`${f.name}: in-house asyncify path used`, /binaryen-ts asyncify/.test(text));
    ok(`${f.name}: ran and printed the expected result`, success && f.expect.test(text));
    if (!(success && f.expect.test(text))) console.error(text.slice(0, 600));
  }

  console.log(`\n  ${passed} passed, ${failed} failed`);
  if (failed > 0) Deno.exit(1);
}

await main();
