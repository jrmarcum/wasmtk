/**
 * Publish script: syncs version, commits, tags, and pushes so GitHub Actions
 * can run `deno publish` with OIDC provenance via the publish.yml workflow.
 *
 * Usage: deno task publish
 *
 * Steps:
 *   1. Read current version from deno.json
 *   2. Run scripts/sync-version.ts to propagate to package.json + src/utils.ts
 *   3. git add the changed files
 *   4. git commit "bump version to vX.Y.Z"
 *   5. git tag vX.Y.Z
 *   6. git push && git push --tags  ← triggers the publish.yml workflow
 */

import denoJson from "../deno.json" with { type: "json" };

const version = denoJson.version;
const tag = `v${version}`;

async function run(cmd: string[]): Promise<void> {
  const p = new Deno.Command(cmd[0], { args: cmd.slice(1) });
  const { code, stderr } = await p.output();
  if (code !== 0) {
    console.error(new TextDecoder().decode(stderr));
    Deno.exit(code);
  }
}

console.log(`Publishing ${tag} via GitHub Actions…`);

// 1. Sync version to package.json + src/utils.ts
await run(["deno", "run", "--allow-read", "--allow-write", "scripts/sync-version.ts"]);

// 2. Stage the three files that sync-version touches
await run(["git", "add", "deno.json", "package.json", "src/utils.ts"]);

// 3. Commit (skip if nothing staged — version was already synced)
const status = new Deno.Command("git", {
  args: ["diff", "--cached", "--quiet"],
});
const { code: diffCode } = await status.output();
if (diffCode !== 0) {
  await run(["git", "commit", "-m", `bump version to ${tag}`]);
}

// 4. Tag (force-update in case of re-run after a failed push)
await run(["git", "tag", "-f", tag]);

// 5. Push commit + tag — triggers publish.yml which runs `deno publish` with provenance
await run(["git", "push"]);
await run(["git", "push", "origin", tag]);

console.log(`\nTag ${tag} pushed. GitHub Actions will publish to JSR with provenance.`);
console.log(`Watch progress at: https://github.com/jrmarcum/wasmtk/actions`);
