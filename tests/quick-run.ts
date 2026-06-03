// run-on-each-file.ts
// Run the same command on every file in a folder (with optional extension filter)

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";

async function main() {
  if (Deno.args.length < 1) {
    console.log(`
${BOLD}Usage:${RESET}
  deno run --allow-read --allow-run ${Deno.mainModule.split("/").pop() ?? "script.ts"} \\
    [folder] [command] [args...] [-- .ext1 .ext2 ...]

${DIM}Examples:${RESET}
  deno run ... . deno fmt
  deno run ... ./src deno lint -- .ts .tsx
  deno run ... ./data node process.js -- .json .csv
    `);
    Deno.exit(1);
  }

  // ── Parse arguments ──────────────────────────────────────────────
  const folder = Deno.args[0] || ".";
  const cmd = Deno.args[1] || "deno";
  let argsBeforeFile = Deno.args.slice(2);

  // Handle optional extension filter after --
  let allowedExtensions: string[] = [];
  const dashIndex = argsBeforeFile.indexOf("--");
  if (dashIndex !== -1) {
    allowedExtensions = argsBeforeFile
      .slice(dashIndex + 1)
      .map((ext) => (ext.startsWith(".") ? ext : `.${ext}`).toLowerCase());
    argsBeforeFile = argsBeforeFile.slice(0, dashIndex);
  }

  // ── Print summary ────────────────────────────────────────────────
  console.log(`${BOLD}Folder:${RESET} ${folder}`);
  console.log(`${BOLD}Command:${RESET} ${cmd} ${argsBeforeFile.join(" ")} <file>`);
  if (allowedExtensions.length > 0) {
    console.log(`${BOLD}Only extensions:${RESET} ${allowedExtensions.join(", ")}`);
  }
  console.log("─".repeat(60));

  let processed = 0;
  let successCount = 0;
  let failedCount = 0;

  // ── Process files ────────────────────────────────────────────────
  for await (const entry of Deno.readDir(folder)) {
    if (!entry.isFile) continue;

    // Extension filter – this belongs inside the loop!
    if (allowedExtensions.length > 0) {
      const ext: string = entry.name.slice(entry.name.lastIndexOf(".")).toLowerCase();
      if (!allowedExtensions.includes(ext)) continue;
    }

    const filePath = `${folder}/${entry.name}`;
    console.log(`→ ${entry.name}`);

    try {
      const command = new Deno.Command(cmd, {
        args: [...argsBeforeFile, filePath],
        stdout: "inherit",
        stderr: "inherit",
      });

      const { success, code } = await command.output();

      processed++;

      if (success) {
        console.log(`  ${GREEN}✓ Success${RESET}`);
        successCount++;
      } else {
        console.log(`  ${RED}✗ Failed (code ${code})${RESET}`);
        failedCount++;
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      console.error(`  ${RED}Error:${RESET} ${errorMessage}`);
      failedCount++;
    }

    console.log("");
  }

  // ── Final summary ────────────────────────────────────────────────
  console.log("─".repeat(60));
  console.log(
    `${BOLD}Finished!${RESET} ` +
      `Processed: ${processed} | ` +
      `${GREEN}Success: ${successCount}${RESET} | ` +
      `${RED}Failed: ${failedCount}${RESET}`
  );

  if (failedCount > 0) {
    console.log(`${RED}Some commands failed — check output above.${RESET}`);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}