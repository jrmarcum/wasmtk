/**
 * go_asyncify_tests.ts — Goroutine Go with NO external binaryen
 *
 * Proves that a TinyGo program using goroutines + channels — which require
 * TinyGo's asyncify transform — builds and runs through `wasmtk run --lang=go`
 * with the in-house asyncify path (TinyGo's asyncify scheduler + a passthrough
 * wasm-opt shim + binaryen-ts's Asyncify pass, which resolves the in-wasm
 * `asyncify.*` control imports), i.e. WITHOUT any external `wasm-opt`/binaryen.
 *
 * Forced via `WASMTK_GO_BINARYEN_ASYNCIFY=1` so it exercises the binaryen-ts
 * path even on a machine that has a real `wasm-opt` on PATH.
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

async function main(): Promise<void> {
  console.log("── Goroutine Go via in-house asyncify (no external binaryen) ──");

  if (!await toolAvailable("tinygo", ["version"])) {
    console.log("  (skipped — TinyGo not on PATH)");
    return;
  }

  // Build + run the goroutine worker-pool, forcing the binaryen-ts asyncify path.
  const out = await new Deno.Command(WASMTK, {
    args: ["run", join(FIXTURE, "main.go")],
    env: { WASMTK_GO_BINARYEN_ASYNCIFY: "1" },
    stdout: "piped",
    stderr: "piped",
  }).output();
  const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);

  ok("wasmtk run --lang=go (goroutines) succeeded", out.success);
  ok("used the in-house binaryen-ts asyncify path", /binaryen-ts asyncify/.test(text));
  ok("goroutine worker-pool prints the correct sum (sum: 30)", /sum:\s*30/.test(text));
  if (failed > 0) console.error(text.slice(0, 600));

  console.log(`\n  ${passed} passed, ${failed} failed`);
  if (failed > 0) Deno.exit(1);
}

await main();
