/**
 * Increments the `version` field in deno.json, then propagates the new version
 * to package.json + src/utils.ts (by importing sync-version.ts, which runs after
 * deno.json has already been written here).
 *
 * Run via:  deno task bump            # rightmost: 1.6.2 → 1.6.3
 *           deno task bump minor      # middle:    1.6.2 → 1.7.0
 *           deno task bump major      # leftmost:  1.6.2 → 2.0.0
 *
 * VERSIONS ARE A SEQUENTIAL COUNTER, NOT A COMPATIBILITY SIGNAL (owner directive 2026-07-30).
 * `patch` / `minor` / `major` name the POSITION to increment — rightmost, middle, leftmost — and
 * carry no semver meaning on their own.
 *
 * One caveat: `bump major` is also the tool for a DELIBERATE jump to a round number to mark a
 * breaking release (that is what 1.11.12 → 2.0.0 was, and it may be done again). So an `x.0.0` can
 * mean either "the odometer carried" (~every 100 releases) or "we advanced on purpose to flag a
 * break" — the number cannot tell them apart. The README's `### ⚠️ Breaking Changes` table is what
 * disambiguates them, and any deliberate jump must add a row there.
 *
 * ODOMETER SEQUENCING (owner directive 2026-07-30): the minor and patch components
 * are single digits and MUST NOT exceed 9. Reaching 9 rolls the component back to 0
 * and carries 1 into the component to its left:
 *
 *     1.2.9  --patch-->  1.3.0        patch rolls over, minor carries
 *     1.9.9  --patch-->  2.0.0        both roll over, major carries
 *     1.9.4  --minor-->  2.0.0        minor rolls over, major carries
 *     0.9.9  --patch-->  1.0.0        the owner's worked example
 *
 * Only `major` is unbounded — it just keeps counting (9 → 10 → 11 …).
 *
 * NOTE this is intentionally NARROWER than semver, which permits multi-digit
 * components (1.11.12 is perfectly valid semver and this project published it).
 * Versions carrying a minor or patch above 9 therefore exist in the history and
 * cannot be produced by this script; it REFUSES to bump from one rather than
 * guessing, since no carry rule reproduces the intended next version. Set
 * deno.json's version by hand in that case, then resume using bump.
 *
 * Unlike `update-version` (which only COPIES the existing deno.json version out to
 * package.json/src/utils.ts), this RAISES the deno.json version first. Must be run
 * from the project root (deno task does this automatically).
 */

/** Highest permitted value for the minor and patch components. */
const MAX_COMPONENT = 9;

const root = Deno.cwd();
const denoJsonPath = `${root}/deno.json`;

const kind = (Deno.args[0] ?? "patch").toLowerCase();
if (kind !== "patch" && kind !== "minor" && kind !== "major") {
  console.error(`❌ bump: unknown release kind "${kind}" — use patch | minor | major`);
  Deno.exit(1);
}

const text = await Deno.readTextFile(denoJsonPath);
const m = text.match(/("version"\s*:\s*)"(\d+)\.(\d+)\.(\d+)"/);
if (!m) {
  console.error('❌ bump: could not find a "version": "X.Y.Z" field in deno.json');
  Deno.exit(1);
}

let [major, minor, patch] = [Number(m[2]), Number(m[3]), Number(m[4])];
const from = `${major}.${minor}.${patch}`;

// Refuse to bump from a version this scheme could never have produced. Carrying from, say,
// 1.11.12 is ambiguous (is the next one 1.12.0? 2.0.0? 2.2.3?), and every answer is a guess that
// would silently pick a wrong release number — so stop and make the owner state the intent.
if (minor > MAX_COMPONENT || patch > MAX_COMPONENT) {
  console.error(
    `❌ bump: ${from} has a minor/patch component above ${MAX_COMPONENT}, which the odometer ` +
      `sequencing rule cannot carry from unambiguously.\n` +
      `   Edit "version" in deno.json by hand to the intended next release, run ` +
      `\`deno task update-version\`, then use \`deno task bump\` from there.`,
  );
  Deno.exit(1);
}

if (kind === "major") {
  major += 1;
  minor = 0;
  patch = 0;
} else if (kind === "minor") {
  minor += 1;
  patch = 0;
} else {
  patch += 1;
}

// Odometer carry: a component that reaches 10 rolls to 0 and adds 1 to the one on its left.
// Applied patch-first so a patch bump from x.9.9 carries all the way through to (x+1).0.0.
if (patch > MAX_COMPONENT) {
  patch = 0;
  minor += 1;
}
if (minor > MAX_COMPONENT) {
  minor = 0;
  major += 1;
}

const to = `${major}.${minor}.${patch}`;

// Targeted replace so the rest of deno.json's formatting is untouched.
const updated = text.replace(/("version"\s*:\s*)"\d+\.\d+\.\d+"/, `$1"${to}"`);
await Deno.writeTextFile(denoJsonPath, updated);
console.log(`✅ deno.json     → ${to}  (${kind} bump from ${from})`);

// Propagate the freshly-written version to package.json + src/utils.ts.
await import("./sync-version.ts");
