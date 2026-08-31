/**
 * upstream-link.ts — generate `deno.upstream.json`, a throwaway config that points the two backend
 * specifiers at the LOCAL `upstream/binaryang` checkout instead of the pinned JSR release.
 *
 * Usage:  deno task upstream:link          # regenerate deno.upstream.json from deno.json
 *
 * ## Why this is a separate config and not an edit to deno.json
 *
 * `deno.json` carries an EXACT pin on both compat subpaths, and the standing invariant is that
 * **neither moves without a full gate** (see cmem/design-decisions.md). A local checkout is not a
 * version anyone can pin, roll back to, or hand to a colleague. Editing `deno.json` to point at it —
 * even temporarily — makes the authoritative pin lie, and this project has already paid for a
 * premature "it's fixed upstream" decision once.
 *
 * So the split is deliberate:
 *
 *   deno.json           the GATE OF RECORD. Always a published, pinned version. Never edited to
 *                       point at a checkout.
 *   deno.upstream.json  EXPLORATION ONLY. Generated, gitignored, disposable. Use it to reproduce a
 *                       bug against upstream `main`, to try a fix before it ships, or to answer
 *                       "is this fixed yet" without waiting for a release.
 *
 * ## The structural guard
 *
 * `deno task upstream:install` installs the binary as **`wasmtk-upstream`**, NOT `wasmtk`. The test
 * suites invoke `wasmtk` by name (`WASMTK_BIN`), so an upstream build **cannot** be picked up by a
 * gate run even by accident. That is not politeness — the recorded failure mode here is exactly
 * "the suite silently ran the wrong binary", and a naming collision is the only thing standing
 * between an exploratory build and a green gate that means nothing.
 *
 * **A result from `wasmtk-upstream` is never evidence for a decision.** It tells you where to look.
 * The gate of record runs `wasmtk`, built from the pin in `deno.json`.
 */
import denoJson from "../deno.json" with { type: "json" };

const ROOT = new URL("../", import.meta.url);
const CHECKOUT = new URL("upstream/binaryang/", ROOT);

/** Map each backend specifier onto the matching entrypoint inside the local checkout. */
const LOCAL: Record<string, string> = {
  "binaryen-backend": "./upstream/binaryang/src/binaryen-ts/api/binaryen-compat.ts",
  "wabt": "./upstream/binaryang/src/wabt-ts/api/wabt-compat.ts",
};

// Fail loudly rather than silently generating a config that resolves to the published package.
try {
  await Deno.stat(new URL("deno.json", CHECKOUT));
} catch {
  console.error("❌ upstream/binaryang is not checked out. Clone it first:");
  console.error("   git clone https://github.com/jrmarcum/binaryang.git upstream/binaryang");
  Deno.exit(1);
}

for (const [spec, path] of Object.entries(LOCAL)) {
  try {
    await Deno.stat(new URL(path.replace("./", ""), ROOT));
  } catch {
    console.error(`❌ entrypoint for "${spec}" not found at ${path}`);
    console.error("   The upstream layout moved — update LOCAL in scripts/upstream-link.ts.");
    Deno.exit(1);
  }
}

const cfg = structuredClone(denoJson) as Record<string, unknown>;
const imports = { ...(cfg.imports as Record<string, string>) };
const swapped: string[] = [];
for (const [spec, path] of Object.entries(LOCAL)) {
  if (!(spec in imports)) {
    console.error(`❌ "${spec}" is not in deno.json imports — did an alias get renamed?`);
    Deno.exit(1);
  }
  swapped.push(`${spec}: ${imports[spec]} → ${path}`);
  imports[spec] = path;
}
cfg.imports = imports;
// A generated config must never be publishable or self-describing as the real package.
delete cfg.publish;
delete cfg.tasks;

const out = new URL("deno.upstream.json", ROOT);
await Deno.writeTextFile(out, JSON.stringify(cfg, null, 2) + "\n");

console.log("✅ wrote deno.upstream.json (gitignored, exploration only)");
for (const s of swapped) console.log(`   ${s}`);
const head = new TextDecoder().decode(
  (await new Deno.Command("git", {
    args: ["-C", "upstream/binaryang", "rev-parse", "--short", "HEAD"],
    stdout: "piped",
  }).output()).stdout,
).trim();
console.log(`   checkout at ${head || "unknown"}`);
console.log("");
console.log("   Use:  deno run -A --config deno.upstream.json <script>");
console.log("         deno task upstream:install     # installs as `wasmtk-upstream`, NOT `wasmtk`");
console.log("   ⚠️  Results from this config are NOT evidence for a decision — the gate of record");
console.log("       runs `wasmtk`, built from the pinned release in deno.json.");
