/**
 * rust_tests.ts — Rust producer (`src/rustwasic.ts`) end to end
 *
 * The Rust producer had NO suite (2026-08-24 audit). It delegates fully to `rsxtk`, so this gates
 * the DELEGATION and wasmtk's own edges around it:
 *
 *   init     `wasmtk init --lang=rust hello`  → rsxtk scaffolds `hello.rs`
 *   run      `wasmtk run hello.rs`            → rsxtk builds + runs it: "Hello from rsxtk!", exit 0
 *   build    `wasmtk build hello.rs`          → `hello.wasm` beside the source, non-empty
 *   host     `wasmtk run hello.wasm`          → the rsxtk-built module runs on wasmtk's OWN WASI
 *                                               host too, not just rsxtk's wasmtime
 *   missing  `wasmtk run --lang=rust nope`    → non-zero exit (rsxtk's failure propagates)
 *   absent   rsxtk removed from PATH          → exit 1 with wasmtk's install hint, not a crash
 *
 * Everything runs in a temp dir. GATED on `rsxtk` — skips cleanly.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/rust_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

/** PATH list separator. */
const delimiter = Deno.build.os === "windows" ? ";" : ":";

const HERE = import.meta.dirname!;
const REPO = join(HERE, "..");
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

async function run(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: Record<string, string> } = {},
): Promise<{ code: number; text: string }> {
  const out = await new Deno.Command(cmd, { args, stdout: "piped", stderr: "piped", ...opts })
    .output();
  const dec = new TextDecoder();
  return { code: out.code, text: dec.decode(out.stdout) + dec.decode(out.stderr) };
}

async function size(path: string): Promise<number> {
  try {
    return (await Deno.stat(path)).size;
  } catch {
    return -1;
  }
}

/** PATH with every directory that holds an `rsxtk` executable removed. */
async function pathWithoutRsxtk(): Promise<string> {
  const dirs = (Deno.env.get("PATH") ?? "").split(delimiter);
  const keep: string[] = [];
  for (const d of dirs) {
    const hit = await Promise.all(
      ["rsxtk", "rsxtk.exe", "rsxtk.cmd"].map((n) => size(join(d, n)).then((s) => s >= 0)),
    );
    if (!hit.some(Boolean)) keep.push(d);
  }
  return keep.join(delimiter);
}

async function main(): Promise<void> {
  console.log("── Rust producer (rustwasic → rsxtk) ─────────────────────────");
  if (!await toolAvailable("rsxtk", ["--version"])) {
    console.log("  (skipped — rsxtk not on PATH)");
    return;
  }
  const tmp = await Deno.makeTempDir({ prefix: "wasmtk_rust_" });
  try {
    const init = await run(WASMTK, ["init", "--lang=rust", "hello"], { cwd: tmp });
    ok("init --lang=rust exits 0", init.code === 0);
    ok("…and scaffolds hello.rs", (await size(join(tmp, "hello.rs"))) > 0);

    const runRs = await run(WASMTK, ["run", "hello.rs"], { cwd: tmp });
    ok("run hello.rs exits 0", runRs.code === 0);
    ok("…and prints Hello from rsxtk!", runRs.text.includes("Hello from rsxtk!"));

    const build = await run(WASMTK, ["build", "hello.rs"], { cwd: tmp });
    ok("build hello.rs exits 0", build.code === 0);
    const wasm = join(tmp, "hello.wasm");
    ok("…and writes a non-empty hello.wasm", (await size(wasm)) > 0);

    const host = await run(WASMTK, ["run", wasm]);
    ok(
      "the rsxtk-built module runs on wasmtk's own WASI host",
      host.code === 0 && host.text.includes("Hello from rsxtk!"),
    );

    const missing = await run(WASMTK, ["run", "--lang=rust", "nope"], { cwd: tmp });
    ok("run --lang=rust <missing> exits non-zero", missing.code !== 0);

    // The not-found path: run wasmtk from source with rsxtk removed from PATH. (The installed
    // `wasmtk` shim is not used here, so the PATH change cannot hide deno itself.)
    const absent = await run(
      Deno.execPath(),
      ["run", "-A", "--config", join(REPO, "deno.json"), join(REPO, "main.ts"), "run", "hello.rs"],
      { cwd: tmp, env: { PATH: await pathWithoutRsxtk() } },
    );
    ok("with rsxtk absent: exits 1", absent.code === 1);
    ok(
      "…with the install hint",
      /rsxtk`? not found/i.test(absent.text) && absent.text.includes("cargo install rsxtk"),
    );
  } finally {
    await Deno.remove(tmp, { recursive: true }).catch(() => {});
  }
}

await main();
console.log(`\n  ${passed} passed, ${failed} failed`);
if (failed > 0) Deno.exit(1);
