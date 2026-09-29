/**
 * golden_wat_tests.ts — the golden-WAT harness (H12 Phase 0a, 2026-09-28)
 *
 * The modularization plan's hard rule: Phases 1–3 are OUTPUT-PRESERVING, so every refactor commit
 * must reproduce the compiler's emitted output byte for byte. This freezes it and diffs against it.
 *
 * What is compiled (in-process, compiler console muted):
 *   - every `tests/wasi/wasm_wasi/*.ts` with `compileWasiTs` (to a temp dir), and
 *   - every `.ts` target of a `@test-pipeline`'s `@step wasic` / `@step modc` line, with
 *     `compileWasiTs` / `compileLibTs`, IN PLACE and IN STEP ORDER (a later step imports an
 *     earlier step's output; those outputs are gitignored build artifacts), each path once.
 * What is frozen per compile, as sections of ONE `<key>.golden` file (one file, not three: this
 * drive's allocation unit made 1,263 small files cost 314 MB for 104 MB of WAT):
 *   status  success / aborted / error / diagnostics. A compile FAILURE is frozen too, since a
 *           changed diagnostic is a behaviour change.
 *   wat     the WAT the compiler wrote (after merges, before assembly)
 *   wit     the .wit it wrote
 *
 * Modes:
 *   (default)  CHECK: recompile everything; report, per entry and section, the FIRST differing line.
 *   --record   FREEZE: rewrite tests/.golden/ (gitignored, local). Deliberate, like a baseline.
 *   [regex]    optional filter on the corpus file name, e.g. "^27_"
 *
 * Usage:
 *   deno run -A tests/golden_wat_tests.ts --record
 *   deno run -A tests/golden_wat_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";
import { compileLibTs, compileWasiTs, type WasicResult } from "../src/wasic.ts";

const HERE = import.meta.dirname!;
const CORPUS = join(HERE, "wasi", "wasm_wasi");
const GOLDEN = join(HERE, ".golden");
const record = Deno.args.includes("--record");
const filterArg = Deno.args.find((a) => !a.startsWith("--"));
const filter = filterArg ? new RegExp(filterArg) : null;

const SECTIONS = ["status", "wat", "wit"] as const;
type Section = typeof SECTIONS[number];
type Artifacts = Record<Section, string | null>;
const marker = (s: Section) => `;;;; golden-section: ${s} ;;;;`;

/** Run `fn` with the compiler's console chatter muted; the result carries what matters. */
async function quiet<T>(fn: () => Promise<T>): Promise<T> {
  const saved = { log: console.log, warn: console.warn, error: console.error };
  console.log = console.warn = console.error = () => {};
  try {
    return await fn();
  } finally {
    Object.assign(console, saved);
  }
}

function statusText(r: WasicResult): string {
  return JSON.stringify(
    {
      success: r.success,
      aborted: r.aborted ?? false,
      error: r.error ?? null,
      diagnostics: r.diagnostics ?? [],
    },
    null,
    2,
  );
}

async function readOr(path: string): Promise<string | null> {
  try {
    return await Deno.readTextFile(path);
  } catch {
    return null;
  }
}

/** Serialize an entry; an absent section is written as absent (`<none>`), not as empty. */
function serialize(a: Artifacts): string {
  return SECTIONS.map((s) => `${marker(s)}\n${a[s] ?? "<none>"}`).join("\n") + "\n";
}

function parse(text: string): Artifacts {
  const out: Artifacts = { status: null, wat: null, wit: null };
  const parts = text.split(/^;;;; golden-section: (status|wat|wit) ;;;;\n/m);
  for (let i = 1; i + 1 < parts.length; i += 2) {
    const body = parts[i + 1].replace(/\n$/, "");
    out[parts[i] as Section] = body === "<none>" ? null : body;
  }
  return out;
}

/** The first differing line between two texts, or null if identical. */
function firstDiff(want: string | null, got: string | null): string | null {
  if (want === got) return null;
  if (want === null) return "absent in the golden, produced now";
  if (got === null) return "present in the golden, not produced now";
  const a = want.split("\n");
  const b = got.split("\n");
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) {
      return `line ${i + 1}\n        golden: ${
        JSON.stringify((a[i] ?? "<eof>").slice(0, 120))
      }\n        now:    ${JSON.stringify((b[i] ?? "<eof>").slice(0, 120))}`;
    }
  }
  return "differs only in trailing bytes";
}

/** Compile one `.ts`, writing to `outWasm`, and collect what the compiler produced. */
async function capture(tsPath: string, outWasm: string, lib: boolean): Promise<Artifacts> {
  const r = await quiet(() => lib ? compileLibTs(tsPath, outWasm) : compileWasiTs(tsPath, outWasm));
  const strip = (s: string | null) => s?.replace(/\n$/, "") ?? null;
  return {
    status: statusText(r),
    wat: strip(await readOr(outWasm.replace(/\.wasm$/, ".wat"))),
    wit: strip(await readOr(outWasm.replace(/\.wasm$/, ".wit"))),
  };
}

/** `// @step modc|wasic <path.ts>` lines of a `@test-pipeline` file, resolved, in order. */
function pipelineCompiles(tsPath: string): { cmd: "modc" | "wasic"; path: string }[] {
  const text = Deno.readTextFileSync(tsPath);
  if (!/\/\/\s*@test-pipeline\b/.test(text)) return [];
  const steps: { cmd: "modc" | "wasic"; path: string }[] = [];
  for (const m of text.matchAll(/^\s*\/\/\s*@step\s+(modc|wasic)\s+(\S+\.ts)\b/gm)) {
    steps.push({ cmd: m[1] as "modc" | "wasic", path: join(CORPUS, m[2]) });
  }
  return steps;
}

async function main(): Promise<void> {
  const files = [...Deno.readDirSync(CORPUS)]
    .filter((e) => e.isFile && e.name.endsWith(".ts") && (!filter || filter.test(e.name)))
    .map((e) => e.name)
    .sort();
  const work = await Deno.makeTempDir({ prefix: "wasmtk_golden_" });
  const doneSteps = new Set<string>();
  let compared = 0, diverged = 0, recorded = 0;
  const started = Date.now();

  const handle = async (key: string, got: Artifacts) => {
    const path = join(GOLDEN, `${key}.golden`);
    if (record) {
      await Deno.mkdir(join(path, ".."), { recursive: true });
      await Deno.writeTextFile(path, serialize(got));
      recorded++;
      return;
    }
    compared++;
    const text = await readOr(path);
    if (text === null) {
      diverged++;
      console.log(`✗ ${key}\n  golden missing (run --record)`);
      return;
    }
    const want = parse(text);
    const problems = SECTIONS.map((s) => [s, firstDiff(want[s], got[s])] as const)
      .filter(([, d]) => d !== null)
      .map(([s, d]) => `  .${s}: ${d}`);
    if (problems.length) {
      diverged++;
      console.log(`✗ ${key}\n${problems.join("\n")}`);
    }
  };

  try {
    for (const file of files) {
      const tsPath = join(CORPUS, file);
      // Pipeline compile steps first, in order (the pipeline's later steps import these outputs).
      for (const step of pipelineCompiles(tsPath)) {
        if (doneSteps.has(step.path)) continue;
        doneSteps.add(step.path);
        const rel = step.path.slice(join(HERE, "wasi").length + 1).replace(/[\\/]/g, "__");
        await handle(
          `pipe/${step.cmd}__${rel.replace(/\.ts$/, "")}`,
          await capture(step.path, step.path.replace(/\.ts$/, ".wasm"), step.cmd === "modc"),
        );
      }
      await handle(
        `wasi/${file.replace(/\.ts$/, "")}`,
        await capture(tsPath, join(work, file.replace(/\.ts$/, ".wasm")), false),
      );
    }
  } finally {
    await Deno.remove(work, { recursive: true }).catch(() => {});
  }

  const secs = ((Date.now() - started) / 1000).toFixed(0);
  if (record) {
    console.log(`\n  recorded ${recorded} golden entries in ${GOLDEN} (${secs}s)`);
    return;
  }
  console.log(`\n  golden-WAT: ${compared} compared, ${diverged} diverged (${secs}s)`);
  if (compared === 0) {
    // A check that compared nothing is not a pass (a typo'd filter printed ✅ once).
    console.log("  ❌ nothing was compared: the filter matched no file");
    Deno.exit(1);
  }
  if (diverged > 0) {
    console.log(
      "  ❌ output changed. A refactor must reproduce it exactly; an intended fix re-records.",
    );
    Deno.exit(1);
  }
  console.log("  ✅ byte-identical to the golden snapshot");
}

await main();
