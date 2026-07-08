/**
 * go_bindgen_tests.ts — Go (TinyGo) → bindgen integration
 *
 * Proves that a TinyGo `//go:wasmexport` reactor library exporting string
 * functions over the wasmtk Canonical ABI is consumable by `wasmtk bindgen`
 * with no Go-specific host code: the generated loader instantiates the module
 * (its `wasi_snapshot_preview1` import satisfied by the loader's SPEC §10 WASI
 * shim, `_initialize` called), and the canonical string marshalling round-trips
 * exactly as it does for a wasic-produced module.
 *
 * GATED on TinyGo being installed (the CI image has none) — skips cleanly.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/go_bindgen_tests.ts
 *
 * @license MIT
 */

import { join, toFileUrl } from "jsr:@std/path";

const HERE = import.meta.dirname!;
const FIXTURE = join(HERE, "go_fixtures", "strlib");
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
    const p = new Deno.Command(cmd, { args, stdout: "null", stderr: "null" });
    return (await p.output()).success;
  } catch {
    return false;
  }
}

async function run(cmd: string, args: string[]): Promise<{ ok: boolean; text: string }> {
  const out = await new Deno.Command(cmd, { args, stdout: "piped", stderr: "piped" }).output();
  const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);
  return { ok: out.success, text };
}

async function main(): Promise<void> {
  console.log("── Go → bindgen integration (strlib) ─────────────────────────");

  if (!await toolAvailable("tinygo", ["version"])) {
    console.log("  (skipped — TinyGo not on PATH)");
    return;
  }

  // 1) Build the TinyGo reactor library.
  const build = await run(WASMTK, ["modc", "--lang=go", FIXTURE]);
  ok("modc --lang=go builds strlib.wasm", build.ok);
  if (!build.ok) {
    console.error(build.text);
    return;
  }

  // 2) Generate host bindings from the hand-written .wit.
  const witPath = join(FIXTURE, "strlib.wit");
  const gen = await run(WASMTK, ["bindgen", witPath]);
  ok("bindgen generates strlib.bindings.ts", gen.ok);
  if (!gen.ok) {
    console.error(gen.text);
    return;
  }

  // 3) Drive the generated loader against the Go .wasm.
  const bindingsUrl = toFileUrl(join(FIXTURE, "strlib.bindings.ts")).href;
  const { loadModule } = await import(bindingsUrl) as {
    loadModule: (
      src: string | URL,
    ) => Promise<{ greet(name: string): string; strLen(s: string): number }>;
  };
  const wasmUrl = toFileUrl(join(FIXTURE, "strlib.wasm"));
  const lib = await loadModule(wasmUrl);

  ok('greet("World") === "Hello, World!"', lib.greet("World") === "Hello, World!");
  ok('greet("héllo wörld") round-trips UTF-8', lib.greet("héllo wörld") === "Hello, héllo wörld!");
  ok('greet("") === "Hello, !"', lib.greet("") === "Hello, !");
  ok('strLen("hello") === 5', lib.strLen("hello") === 5);
  ok('strLen("héllo") === 6 (UTF-8 bytes)', lib.strLen("héllo") === 6);
}

await main();

console.log("──────────────────────────────────────────────");
console.log(`  Passed: ${passed}`);
console.log(`  Failed: ${failed}`);
console.log("==============================================");
if (failed > 0) Deno.exit(1);
