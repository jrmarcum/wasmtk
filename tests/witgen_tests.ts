/**
 * witgen_tests.ts — `.wit` auto-emission for optimised / WAT→WASM artifacts (2026-09-28)
 *
 * Owner decision: every `.wasm` wasmtk writes through an optimise or WAT→WASM step gets a `.wit`
 * beside it, derived from core signatures (src/witgen.ts). This gates:
 *
 *   convert x.wat        → x.wit, readable by bindgen's parseWit, exports and types right
 *   wasic x.wat          → x.wit
 *   wasmbundle a b -o c  → c.wit
 *   a HAND-WRITTEN .wit  → kept, never overwritten (it may declare `string`s the binary cannot)
 *   a GENERATED .wit     → refreshed when the module changes
 *   untranslatable exports (v128, multi-value) → listed in a `// skipped` comment, not dropped
 *
 * Everything runs in a temp dir. (Zig/Go emission is asserted in zig_tests.ts / the go suites.)
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-run --allow-env tests/witgen_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";
import { parseWit } from "../src/bindgen.ts";
import { GENERATED_HEADER } from "../src/witgen.ts";

const WASMTK = "wasmtk";

let passed = 0;
let failed = 0;
function ok(desc: string, cond: boolean, detail = ""): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${desc}`);
  } else {
    failed++;
    console.error(`  ✗ ${desc}${detail ? `\n${detail}` : ""}`);
  }
}

async function run(args: string[], cwd: string): Promise<{ code: number; text: string }> {
  const out = await new Deno.Command(WASMTK, { args, cwd, stdout: "piped", stderr: "piped" })
    .output();
  const dec = new TextDecoder();
  return { code: out.code, text: dec.decode(out.stdout) + dec.decode(out.stderr) };
}

const read = (p: string): string | null => {
  try {
    return Deno.readTextFileSync(p);
  } catch {
    return null;
  }
};

const LIB_WAT = `(module
  (func (export "addInts") (param i32 i32) (result i32) (i32.add (local.get 0) (local.get 1)))
  (func (export "scale") (param f64) (result f64) (f64.mul (local.get 0) (f64.const 2)))
  (func (export "big") (param i64) (result i64) (local.get 0))
  (func (export "vec") (param v128) (result v128) (local.get 0))
  (func (export "pair") (result i32 i32) (i32.const 1) (i32.const 2))
  (func (export "_initialize")))
`;

async function main(): Promise<void> {
  const tmp = await Deno.makeTempDir({ prefix: "wasmtk_witgen_" });
  try {
    console.log("── convert x.wat → x.wasm + x.wit ────────────────────────────");
    Deno.writeTextFileSync(join(tmp, "lib.wat"), LIB_WAT);
    const conv = await run(["convert", "lib.wat"], tmp);
    ok("convert exits 0", conv.code === 0, conv.text);
    const wit = read(join(tmp, "lib.wit"));
    ok("lib.wit written beside lib.wasm", wit !== null);
    if (wit) {
      ok("…with the generated header", wit.startsWith(GENERATED_HEADER));
      const parsed = parseWit(wit);
      const byName = new Map(parsed.exports.map((e) => [e.name, e]));
      ok("…parseWit reads it (package local:lib)", parsed.packageName === "local:lib");
      ok(
        "…addInts → add-ints: func(s32, s32) -> s32",
        byName.get("add-ints")?.result === "s32" &&
          byName.get("add-ints")?.params.map((p) => p.type).join(",") === "s32,s32",
      );
      ok("…scale is f64 → f64", byName.get("scale")?.result === "f64");
      ok("…big is s64 → s64", byName.get("big")?.result === "s64");
      ok("…_initialize is not part of the interface", !byName.has("initialize"));
      ok("…v128 export is LISTED as skipped, not dropped", /skipped export vec: .*v128/.test(wit));
      ok(
        "…multi-value export is LISTED as skipped",
        /skipped export pair: multiple results/.test(wit),
      );
      ok("…and neither appears as an export", !byName.has("vec") && !byName.has("pair"));
    }

    console.log("── a hand-written .wit is kept ──────────────────────────────");
    const HAND =
      "package local:lib;\n\nworld lib {\n  export add-ints: func(a: s32, b: s32) -> s32;\n}\n";
    Deno.writeTextFileSync(join(tmp, "lib.wit"), HAND);
    const again = await run(["convert", "lib.wat"], tmp);
    ok("convert still exits 0", again.code === 0);
    ok("hand-written lib.wit is untouched", read(join(tmp, "lib.wit")) === HAND);
    ok("…and the CLI says it kept it", /kept existing lib\.wit/.test(again.text));

    console.log("── a generated .wit is refreshed ────────────────────────────");
    Deno.removeSync(join(tmp, "lib.wit"));
    await run(["convert", "lib.wat"], tmp);
    Deno.writeTextFileSync(
      join(tmp, "lib.wat"),
      LIB_WAT.replace(
        `(func (export "_initialize"))`,
        `(func (export "extra") (result i32) (i32.const 9))`,
      ),
    );
    await run(["convert", "lib.wat"], tmp);
    const refreshed = read(join(tmp, "lib.wit")) ?? "";
    ok(
      "the regenerated .wit picks up the new export",
      /export extra: func\(\) -> s32;/.test(refreshed),
    );

    console.log("── wasic x.wat → x.wit ──────────────────────────────────────");
    Deno.writeTextFileSync(
      join(tmp, "prog.wat"),
      `(module (func (export "answer") (result i32) (i32.const 42)))`,
    );
    const wasic = await run(["wasic", "prog.wat"], tmp);
    ok("wasic prog.wat exits 0", wasic.code === 0, wasic.text);
    ok(
      "prog.wit declares answer",
      /export answer: func\(\) -> s32;/.test(read(join(tmp, "prog.wit")) ?? ""),
    );

    console.log("── a module with no interface gets no .wit ──────────────────");
    Deno.writeTextFileSync(
      join(tmp, "main.wat"),
      `(module (memory (export "memory") 1) (func (export "_start")))`,
    );
    const noIface = await run(["convert", "main.wat"], tmp);
    ok("convert exits 0", noIface.code === 0);
    ok("no main.wit is written (nothing to describe)", read(join(tmp, "main.wit")) === null);
    ok(
      "…and the CLI says why",
      /no \.wit for main\.wasm: it exports no interface/.test(noIface.text),
    );

    console.log("── wasmbundle → bundle.wit ──────────────────────────────────");
    Deno.writeTextFileSync(
      join(tmp, "m1.wat"),
      `(module (memory (export "memory") 1) (func (export "one") (result i32) (i32.const 1)))`,
    );
    Deno.writeTextFileSync(
      join(tmp, "m2.wat"),
      `(module (memory (export "memory") 1) (func (export "two") (result i32) (i32.const 2)))`,
    );
    await run(["convert", "m1.wat"], tmp);
    await run(["convert", "m2.wat"], tmp);
    const bundle = await run(["wasmbundle", "m1.wasm", "m2.wasm", "-o", "bundle.wasm"], tmp);
    ok("wasmbundle exits 0", bundle.code === 0, bundle.text);
    const bwit = read(join(tmp, "bundle.wit")) ?? "";
    ok("bundle.wit exists with the generated header", bwit.startsWith(GENERATED_HEADER), bwit);
    ok(
      "…and lists exports from both modules",
      /func\(\) -> s32;/.test(bwit) && bwit.split("export ").length - 1 >= 2,
      bwit,
    );
  } finally {
    await Deno.remove(tmp, { recursive: true }).catch(() => {});
  }
}

await main();
console.log(`\n  ${passed} passed, ${failed} failed`);
if (failed > 0) Deno.exit(1);
