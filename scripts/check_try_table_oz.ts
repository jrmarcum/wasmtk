/**
 * check_try_table_oz.ts — decides whether the binaryen `-Oz` skip for `try_table` modules in
 * `src/wasic.ts` may be lifted.
 *
 * Assembles `eh_try_table_live_local_fixture.wat` ONCE, then runs the result both **before** and
 * **after** `-Oz`. One variable, one comparison. The fixture keeps two locals live across a catch
 * edge and exits 42; `-Oz` CoalesceLocals miscompiles exactly that, so a post-`-Oz` exit that is
 * not 42 means the optimiser is still unsafe for the standard exception proposal.
 *
 * Usage:  deno run -A scripts/check_try_table_oz.ts
 *
 * Exit 0 = both sides 42, the skip in `src/wasic.ts` may be removed (re-run the full gate after).
 * Exit 1 = post-`-Oz` is wrong, the skip must stay.
 * Exit 2 = pre-`-Oz` is wrong — the fixture or the assembler broke; this says NOTHING about `-Oz`.
 *
 * ⚠️ Passing here is necessary, not sufficient. The real acceptance gate is `15_Exceptions` +
 * `15_LexicalShadowing_Stress` in `wasi_tests`, which is what caught this when a green fixture did
 * not. See cmem/compiler-bugs.md.
 */
import wabt from "wabt";
import binaryen from "../src/binaryen.ts";

const WANT = 42;
const wat = "scripts/eh_try_table_live_local_fixture.wat";

interface WabtModule {
  parseWat(
    f: string,
    s: string,
    o: unknown,
  ): { toBinary(o: unknown): { buffer: Uint8Array }; destroy(): void };
}

async function runExit(bytes: Uint8Array, tag: string): Promise<number> {
  const tmp = await Deno.makeTempFile({ suffix: ".wasm" });
  await Deno.writeFile(tmp, bytes);
  try {
    const c = await new Deno.Command("wasmtime", {
      args: ["run", tmp],
      stdout: "null",
      stderr: "null",
    }).output();
    console.log(
      `  ${tag.padEnd(9)} ${bytes.length.toString().padStart(5)} bytes -> exit ${c.code}`,
    );
    return c.code;
  } finally {
    await Deno.remove(tmp).catch(() => {});
  }
}

const src = await Deno.readTextFile(wat);
const w = await (wabt as unknown as () => Promise<WabtModule>)();
const parsed = w.parseWat(wat, src, { enable_all: true, exceptions: true });
const raw = new Uint8Array(parsed.toBinary({}).buffer);
parsed.destroy();

const preCode = await runExit(raw, "pre-Oz");
if (preCode !== WANT) {
  console.error(
    `\n[2] pre-Oz exited ${preCode}, want ${WANT} — the fixture or the assembler is broken.`,
  );
  console.error("    This says NOTHING about -Oz. Fix this first.");
  Deno.exit(2);
}

const m = binaryen.readBinary(raw);
const feat = (binaryen as unknown as Record<string, Record<string, number>>)["Features"];
(m as unknown as { setFeatures(n: number): void }).setFeatures(feat?.["All"] ?? 0x7FFFFFFF);
binaryen.setShrinkLevel(2);
binaryen.setOptimizeLevel(2);
m.optimize();
const oz: Uint8Array = m.emitBinary();
m.dispose();

const ozCode = await runExit(oz, "post-Oz");
if (ozCode !== WANT) {
  console.error(`\n[1] -Oz MISCOMPILES try_table: exit ${ozCode}, want ${WANT}.`);
  console.error('    Keep the `watSource.includes("try_table")` skip in src/wasic.ts.');
  Deno.exit(1);
}

console.log(`\n[0] -Oz is safe for try_table (both sides exit ${WANT}).`);
console.log("    The skip in src/wasic.ts may be removed — then run the FULL gate,");
console.log("    because 15_Exceptions / 15_LexicalShadowing_Stress are the real acceptance test.");
