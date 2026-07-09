/**
 * go_merge_tests.ts — Mergeable, alloc-free Go leaf (wasm-unknown) → wasmmerge → run
 *
 * Proves that a Go library built with `modc --lang=go --go-target=wasm-unknown` (TinyGo's
 * freestanding target: no WASI, no scheduler, no runtime allocator → 0 imports, no memory.grow)
 * is `wasmmerge`-able into a wasic build — the Go analog of a Zig `FixedBufferAllocator` leaf. The
 * wasic side `import { addi, muli, clampi } from "./mathleaf.wasm"`; wasmtk merges the leaf
 * (calling its `_initialize` — TinyGo guards each export on a runtime-init flag) and the combined
 * module runs, computing correct results.
 *
 * GATED on TinyGo being installed (the CI image has none) — skips cleanly.
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

const HERE = import.meta.dirname!;
const FIXTURE = join(HERE, "go_fixtures", "leaf");
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

async function run(cmd: string, args: string[]): Promise<{ ok: boolean; text: string }> {
  const out = await new Deno.Command(cmd, { args, stdout: "piped", stderr: "piped" }).output();
  const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);
  return { ok: out.success, text };
}

async function main(): Promise<void> {
  console.log("── Mergeable Go leaf (wasm-unknown) → wasmmerge → run ──");

  if (!await toolAvailable("tinygo", ["version"])) {
    console.log("  (skipped — TinyGo not on PATH)");
    return;
  }

  const useTs = join(FIXTURE, "use_mathleaf.ts");
  const useWasm = join(FIXTURE, "use_mathleaf.wasm");

  // 1) Build the alloc-free mergeable leaf.
  const build = await run(WASMTK, ["modc", "--lang=go", "--go-target=wasm-unknown", join(FIXTURE, "mathleaf.go")]);
  ok("modc --lang=go --go-target=wasm-unknown builds mathleaf.wasm", build.ok);
  if (!build.ok) {
    console.error(build.text.slice(0, 500));
    console.log(`\n  ${passed} passed, ${failed} failed`);
    Deno.exit(1);
  }
  ok("leaf reports the wasm-unknown build", /wasm-unknown leaf/.test(build.text));

  // 2) Compile the wasic importer fixture (use_mathleaf.ts) — this performs the merge — + run.
  const comp = await run(WASMTK, ["wasic", useTs]);
  ok("wasic merges the leaf (Merged: mathleaf)", comp.ok && /Merged:\s*mathleaf/.test(comp.text));
  if (!comp.ok) console.error(comp.text.slice(0, 500));

  const res = await run(WASMTK, ["run", useWasm]);
  ok("merged module runs", res.ok);
  ok("addi(3,4) = 7", /addi:\s*7/.test(res.text));
  ok("muli(5,6) = 30", /muli:\s*30/.test(res.text));
  ok("clampi(42,0,10) = 10", /clampi:\s*10/.test(res.text));
  if (failed > 0) console.error(res.text.slice(0, 500));

  console.log(`\n  ${passed} passed, ${failed} failed`);
  if (failed > 0) Deno.exit(1);
}

await main();
