/**
 * zig_tests.ts — Zig producer (`src/zigwasic.ts`) end to end
 *
 * The Zig producer had NO suite (2026-08-24 audit), and two of that audit's findings were in it: a
 * success report that never checked the artifact existed, and a failed `binaryen -Oz` swallowed
 * silently. This gates both build targets and the failure path:
 *
 *   library  `wasmtk modc --lang=zig`  → freestanding wasm, `export fn`s exported, no `_start`;
 *                                         instantiated here and CALLED (add, fib)
 *   program  `wasmtk build <file.zig>` → wasm32-wasi; run on wasmtk's host AND by `wasmtk run
 *                                         <file.zig>` (auto-detect), expecting `Fibonacci(10) = 55`
 *   broken   a compile error           → non-zero exit, and NO artifact left behind
 *
 * `1_fib-zig.zig` prints with `std.debug.print`, i.e. to STDERR; the check reads both streams.
 * Builds go to a temp dir, so the tree is never written. GATED on `zig` — skips cleanly.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/zig_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

const HERE = import.meta.dirname!;
const FIXTURES = join(HERE, "zig_fixtures");
const FIB_PROGRAM = join(HERE, "wasi", "wasm_wasi", "1_fib-zig.zig");
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

async function run(cmd: string, args: string[]): Promise<{ code: number; text: string }> {
  const out = await new Deno.Command(cmd, { args, stdout: "piped", stderr: "piped" }).output();
  const dec = new TextDecoder();
  return { code: out.code, text: dec.decode(out.stdout) + dec.decode(out.stderr) };
}

async function size(path: string): Promise<number> {
  try {
    return (await Deno.stat(path)).size;
  } catch {
    return -1; // absent
  }
}

async function main(): Promise<void> {
  console.log("── Zig producer (zigwasic) ───────────────────────────────────");
  if (!await toolAvailable("zig", ["version"])) {
    console.log("  (skipped — zig not on PATH)");
    return;
  }
  const tmp = await Deno.makeTempDir({ prefix: "wasmtk_zig_" });
  try {
    // 1) Library: freestanding, exports callable from the host.
    const lib = join(tmp, "mathlib.wasm");
    const libBuild = await run(WASMTK, [
      "modc",
      "--lang=zig",
      join(FIXTURES, "mathlib.zig"),
      "-o",
      lib,
    ]);
    ok("modc --lang=zig exits 0", libBuild.code === 0);
    ok("library artifact exists and is non-empty", (await size(lib)) > 0);
    if ((await size(lib)) > 0) {
      const mod = new WebAssembly.Module(await Deno.readFile(lib));
      const names = WebAssembly.Module.exports(mod).map((e) => e.name);
      ok("library exports add and fib", names.includes("add") && names.includes("fib"));
      ok("library has no _start (freestanding, not a program)", !names.includes("_start"));
      const ex = new WebAssembly.Instance(mod, {}).exports as Record<
        string,
        (...a: number[]) => number
      >;
      ok("add(2, 3) = 5", ex.add(2, 3) === 5);
      ok("fib(10) = 55", ex.fib(10) === 55);
    }

    // 2) Program: wasm32-wasi, run on wasmtk's own WASI host.
    const prog = join(tmp, "fib.wasm");
    const progBuild = await run(WASMTK, ["build", FIB_PROGRAM, "-o", prog]);
    ok("build <file.zig> exits 0", progBuild.code === 0);
    ok("program artifact exists and is non-empty", (await size(prog)) > 0);
    const progRun = await run(WASMTK, ["run", prog]);
    ok("wasmtk run fib.wasm exits 0", progRun.code === 0);
    ok("prints Fibonacci(10) = 55", progRun.text.includes("Fibonacci(10) = 55"));

    // 3) `run <file.zig>` — auto-detected producer, build + run in one step.
    const direct = await run(WASMTK, ["run", FIB_PROGRAM, "-o", join(tmp, "fib_direct.wasm")]);
    ok(
      "wasmtk run <file.zig> exits 0 and prints Fibonacci(10) = 55",
      direct.code === 0 && direct.text.includes("Fibonacci(10) = 55"),
    );

    // 4) Cross-engine: the same program on wasmtime, when present.
    if (await toolAvailable("wasmtime", ["--version"])) {
      const wt = await run("wasmtime", ["run", prog]);
      ok("wasmtime runs it identically", wt.code === 0 && wt.text.includes("Fibonacci(10) = 55"));
    }

    // 5) Failure path: a compile error must fail loudly and leave nothing behind.
    const bad = join(tmp, "broken.wasm");
    const badBuild = await run(WASMTK, [
      "modc",
      "--lang=zig",
      join(FIXTURES, "broken.zig"),
      "-o",
      bad,
    ]);
    ok("a compile error exits non-zero", badBuild.code !== 0);
    ok(
      "…and reports the zig error",
      /undeclared|use of undeclared identifier/i.test(badBuild.text),
    );
    ok("…and leaves no artifact", (await size(bad)) === -1);
  } finally {
    await Deno.remove(tmp, { recursive: true }).catch(() => {});
  }
}

await main();
console.log(`\n  ${passed} passed, ${failed} failed`);
if (failed > 0) Deno.exit(1);
