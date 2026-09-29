/**
 * engine_tests.ts — telling the user when the ENGINE (V8), not the module, is the reason (2026-09-28)
 *
 * Owner request: detect that we run on V8 and say so plainly when it does not implement a feature.
 * `src/engine.ts` turns V8's terse refusals into a sentence naming the feature, the engine and its
 * version; `wasmtk run` / `mod` print it under the error, and `wasmtk wast` lists it in its summary
 * and never counts such a refusal as a verdict. This gates:
 *
 *   custom page sizes (V8: `invalid memory limits flags 0x8`)     → explained; wast: skip, not pass
 *   memory64 declared above V8's 16 GiB cap (spec allows 2^48)   → explained, quoting V8's own cap
 *   a 32-bit memory above 65536 pages                            → NOT explained: that cap IS the
 *                                                                  spec's, the module is invalid
 *   a flag-gated proposal (custom descriptors)                   → explained, naming the flag
 *   an ordinary invalid module (type mismatch)                   → NOT explained
 *   core binary.wast's malformed memory-limits flag 0x08         → still a PASS (core: malformed)
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/engine_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";
import wabtInit from "wabt";
import { engineName, explainEngineRejection } from "../src/engine.ts";
import { runWast } from "../src/wast.ts";

let passed = 0;
let failed = 0;
function ok(desc: string, cond: boolean, detail = ""): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${desc}`);
  } else {
    failed++;
    console.error(`  ✗ ${desc}${detail ? `\n    ${detail}` : ""}`);
  }
}

// deno-lint-ignore no-explicit-any
const wabt: any = await (wabtInit as any)();
const bytesOf = (wat: string): Uint8Array => {
  const p = wabt.parseWat("t.wat", wat, { enable_all: true });
  try {
    return new Uint8Array(p.toBinary({}).buffer);
  } finally {
    p.destroy();
  }
};
const refusal = (wat: string): unknown => {
  try {
    new WebAssembly.Module(bytesOf(wat) as BufferSource);
    return null;
  } catch (e) {
    return e;
  }
};

const PAGESIZE = '(module (memory 1 (pagesize 1)) (func (export "_start")))';
const HUGE64 = '(module (memory i64 0 0x1_0000_0000_0000) (func (export "_start")))';
const I32_OVER = '(module (memory 0 65537) (func (export "_start")))';
const EXACT = "(module (type $s (struct)) (func (param (ref null (exact $s)))))";
const MISTYPED = "(module (func (result i32) (i64.const 1)))";

console.log(`\n  engine: ${engineName()}`);
ok("engineName names V8 and Deno", /^V8 \d/.test(engineName()) && engineName().includes("Deno"));

console.log("\n  explainEngineRejection:");
const ps = explainEngineRejection(refusal(PAGESIZE));
ok(
  "custom page sizes → 'not implemented', naming the engine",
  ps?.feature === "custom page sizes" && ps.statement.includes("does not implement") &&
    ps.statement.includes(engineName()),
  JSON.stringify(ps),
);
const h64 = explainEngineRejection(refusal(HUGE64));
ok(
  "memory64 above the cap → quotes V8's cap (262144 pages, 16 GiB) and the declared size",
  h64 !== null && h64.statement.includes("262144 pages (16 GiB)") &&
    h64.statement.includes("281474976710656"),
  JSON.stringify(h64),
);
ok(
  "a 32-bit memory above 65536 pages is NOT the engine: that is the spec's own maximum",
  refusal(I32_OVER) !== null && explainEngineRejection(refusal(I32_OVER)) === null,
);
const ex = explainEngineRejection(refusal(EXACT));
ok(
  "a flag-gated proposal → names the flag",
  ex !== null && ex.statement.includes("--experimental-wasm-custom-descriptors"),
  JSON.stringify(ex),
);
ok(
  "an ordinary invalid module is NOT explained as the engine",
  refusal(MISTYPED) !== null && explainEngineRejection(refusal(MISTYPED)) === null,
);

console.log("\n  wasmtk run:");
const dir = await Deno.makeTempDir({ prefix: "wasmtk_engine_" });
try {
  const run = async (name: string, wat: string) => {
    const p = join(dir, `${name}.wasm`);
    await Deno.writeFile(p, bytesOf(wat));
    const o = await new Deno.Command("wasmtk", {
      args: ["run", p],
      stdout: "piped",
      stderr: "piped",
    })
      .output();
    return { code: o.code, text: new TextDecoder().decode(o.stderr) };
  };
  const a = await run("pagesize", PAGESIZE);
  ok(
    "a custom-page-size module: exit 1 and the plain-words explanation",
    a.code === 1 && a.text.includes("Not supported by the engine") &&
      a.text.includes("custom-page-sizes proposal"),
    a.text,
  );
  const b = await run("huge64", HUGE64);
  ok(
    "a memory64 above the cap: explained",
    b.code === 1 && b.text.includes("caps a declared memory"),
    b.text,
  );
  const c = await run("i32over", I32_OVER);
  ok(
    "a genuinely invalid 32-bit memory: error, but NO engine explanation",
    c.code === 1 && !c.text.includes("Not supported by the engine"),
    c.text,
  );
} finally {
  await Deno.remove(dir, { recursive: true });
}

console.log("\n  wasmtk wast verdicts:");
const SUITE = join(import.meta.dirname ?? ".", "module", "wasm_wast", "testsuite-main");
const inv = await runWast(
  join(SUITE, "proposals", "custom-page-sizes", "custom-page-sizes-invalid.wast"),
);
ok(
  // 17 = the 16 page-size assert_invalids + the file's one plain page-size module V8 refuses.
  "custom-page-sizes-invalid: 16 assert_invalids + 1 module are engine skips, not passes",
  inv.engineLimits["custom page sizes"]?.count === 17 && inv.passed === 3,
  `passed=${inv.passed} limits=${JSON.stringify(inv.engineLimits)}`,
);
const core = await runWast(join(SUITE, "memory.wast"));
ok(
  "core memory.wast: the 32-bit size limits still PASS (V8's cap is the spec's)",
  core.passed === 72 && Object.keys(core.engineLimits).length === 0,
  `passed=${core.passed} limits=${JSON.stringify(core.engineLimits)}`,
);

console.log(`\n  engine explanations: ${passed} passed, ${failed} failed`);
if (failed > 0) Deno.exit(1);
