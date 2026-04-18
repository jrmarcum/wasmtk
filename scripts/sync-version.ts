/**
 * Reads `version` and `name` from deno.json and writes them into:
 *   - package.json  (version + name fields)
 *   - src/utils.ts  (VERSION constant)
 *
 * Run via:  deno task update-version
 * Must be invoked from the project root (deno task does this automatically).
 */

const root = Deno.cwd();

const denoJson = JSON.parse(await Deno.readTextFile(`${root}/deno.json`));
const { version, name } = denoJson as { version: string; name: string };

// ── package.json ──────────────────────────────────────────────────────────────
const pkgPath = `${root}/package.json`;
const pkg = JSON.parse(await Deno.readTextFile(pkgPath));
pkg.name = name;
pkg.version = version;
await Deno.writeTextFile(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
console.log(`✅ package.json  → ${version}`);

// ── src/utils.ts ──────────────────────────────────────────────────────────────
const utilsPath = `${root}/src/utils.ts`;
const utils = await Deno.readTextFile(utilsPath);
const updated = utils.replace(
  /(export const VERSION\s*=\s*)"[^"]*"/,
  `$1"${version}"`,
);
if (updated === utils) {
  // Either already up to date, or the pattern wasn't found — distinguish the two.
  if (utils.includes(`VERSION = "${version}"`)) {
    console.log(`✅ src/utils.ts  → ${version} (already up to date)`);
  } else {
    console.warn("⚠️  src/utils.ts VERSION constant not found — skipped");
  }
} else {
  await Deno.writeTextFile(utilsPath, updated);
  console.log(`✅ src/utils.ts  → ${version}`);
}