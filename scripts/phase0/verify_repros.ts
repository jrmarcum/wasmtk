/**
 * verify_repros.ts — H12 Phase 0 audit verifier (2026-09-28)
 *
 * For every `.ts` in a directory: run it natively (Deno), compile it with `wasmtk wasic`, run the
 * wasm with `wasmtk run`, and classify:
 *   MATCH         same stdout and exit code: no bug shown (a FIXED repro reads MATCH)
 *   DIFFER        compiled, ran, printed something else: SILENT-WRONG
 *   COMPILE-FAIL  the compiler refused it: LOUD
 *   RUN-FAIL      compiled, but the wasm failed differently from native: LOUD
 * An audit claim is only a finding once this says so; tracing the code is not evidence.
 * Compiles IN PLACE (outputs are gitignored). Remember `i32`/`i64` are INTEGER types in wasic's
 * subset (README), so `const q: i32 = 7 / 2` printing 3 is the contract, not a bug.
 *
 * Usage:  deno run -A scripts/phase0/verify_repros.ts scripts/phase0/round1/silent-wrong
 */
const dir = Deno.args[0];
const files = [...Deno.readDirSync(dir)].filter((e) => e.name.endsWith(".ts")).map((e) => e.name)
  .sort();
const dec = new TextDecoder();

async function run(
  cmd: string,
  args: string[],
): Promise<{ code: number; out: string; err: string }> {
  const o = await new Deno.Command(cmd, { args, cwd: dir, stdout: "piped", stderr: "piped" })
    .output();
  return {
    code: o.code,
    out: dec.decode(o.stdout).replace(/\r\n/g, "\n"),
    err: dec.decode(o.stderr),
  };
}

for (const f of files) {
  const base = f.replace(/\.ts$/, "");
  const native = await run(Deno.execPath(), ["run", "-A", f]);
  const comp = await run("wasmtk", ["wasic", f]);
  if (comp.code !== 0) {
    const diag = (comp.out + comp.err).split("\n").find((l) =>
      /⚠️|❌/.test(l)
    )?.trim().slice(0, 110) ?? "";
    console.log(`COMPILE-FAIL  ${f}  :: ${diag}`);
    continue;
  }
  const wasm = await run("wasmtk", ["run", `${base}.wasm`]);
  if (wasm.code !== native.code) {
    console.log(
      `RUN-FAIL      ${f}  :: native exit ${native.code}, wasm exit ${wasm.code} ${
        wasm.err.trim().slice(0, 80)
      }`,
    );
    continue;
  }
  if (wasm.out === native.out) {
    console.log(`MATCH         ${f}`);
    continue;
  }
  const a = native.out.split("\n"), b = wasm.out.split("\n");
  const i = a.findIndex((l, k) => l !== b[k]);
  console.log(
    `DIFFER        ${f}  :: line ${i + 1}: native ${JSON.stringify(a[i])} vs wasm ${
      JSON.stringify(b[i])
    }`,
  );
}
