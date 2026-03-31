/**
 * @module wtime
 * @description Phase 21 — wasmtime AOT compiler and runner backend.
 *
 * Produces machine-specific Ahead-Of-Time compiled `.cwasm` files via
 * `wasmtime compile`, and runs them via `wasmtime run`.
 *
 * ## Machine-specificity
 *
 * `.cwasm` files are tied to the CPU architecture, OS, and wasmtime version
 * used to compile them. They are NOT portable between machines and cannot be
 * distributed or shared. Their purpose is to eliminate JIT compilation at
 * startup time, giving faster execution on the machine that compiled them.
 *
 * ## Binary management
 *
 * wasmtime is downloaded on first use from the Bytecode Alliance GitHub releases
 * and cached at ~/.deno/bin/wasmtime (mirrors the javy install pattern).
 * No npm package is used — the standalone CLI binary is required for AOT
 * compilation and for running .cwasm files.
 */

import { basename, dirname } from "@std/path";

// ---------------------------------------------------------------------------
// Version & asset resolution
// ---------------------------------------------------------------------------

const WASMTIME_VERSION = "v43.0.0";

/**
 * Maps the current OS and CPU architecture to the correct wasmtime release
 * asset filename. Asset naming follows the pattern used in the Bytecode Alliance
 * wasmtime GitHub releases:
 *   wasmtime-{version}-{arch}-{os}[.tar.xz | .zip]
 */
function getWasmtimeAssetName(): string {
  const os = Deno.build.os;
  const arch = Deno.build.arch;
  const archStr = arch === "aarch64" ? "aarch64" : "x86_64";
  let osStr: string;
  if (os === "darwin") osStr = "macos";
  else if (os === "windows") osStr = "windows";
  else osStr = "linux";
  const ext = os === "windows" ? ".zip" : ".tar.xz";
  return `wasmtime-${WASMTIME_VERSION}-${archStr}-${osStr}${ext}`;
}

// ---------------------------------------------------------------------------
// Install-path helpers
// ---------------------------------------------------------------------------

/**
 * Returns the directory where the wasmtime binary is cached.
 * Uses ~/.deno/bin/ — already on PATH after `deno install`.
 */
function getWasmtimeCacheDir(): string {
  const home = Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE") ?? ".";
  return `${home}/.deno/bin`;
}

/**
 * Returns the full path where the wasmtime binary is installed.
 */
export function getWasmtimeInstallPath(): string {
  const ext = Deno.build.os === "windows" ? ".exe" : "";
  return `${getWasmtimeCacheDir()}/wasmtime${ext}`;
}

// ---------------------------------------------------------------------------
// Availability check
// ---------------------------------------------------------------------------

/**
 * Returns true if wasmtime is available on PATH or at the cached install path.
 */
export async function isWasmtimeAvailable(): Promise<boolean> {
  try {
    const { success } = await new Deno.Command("wasmtime", {
      args: ["--version"],
      stdout: "null",
      stderr: "null",
    }).output();
    return success;
  } catch {
    return false;
  }
}

/** Returns "wasmtime" if on PATH, otherwise the cached install path. */
async function wasmtimeBin(): Promise<string> {
  return (await isWasmtimeAvailable()) ? "wasmtime" : getWasmtimeInstallPath();
}

// ---------------------------------------------------------------------------
// Download & install
// ---------------------------------------------------------------------------

/**
 * Ensures the wasmtime binary is available, downloading and extracting it from
 * the Bytecode Alliance GitHub releases if not found.
 *
 * Archive format by platform:
 *  - Linux / macOS : wasmtime-{version}-{arch}-{os}.tar.xz  (extracted via tar -xJf)
 *  - Windows       : wasmtime-{version}-{arch}-windows.zip   (extracted via tar -xf)
 *
 * @throws {Error} if the download or extraction fails.
 */
export async function ensureWasmtime(): Promise<void> {
  if (await isWasmtimeAvailable()) return;

  const installPath = getWasmtimeInstallPath();
  try {
    await Deno.stat(installPath);
    return; // cached but not on PATH
  } catch { /* not yet installed */ }

  const assetName = getWasmtimeAssetName();
  const url =
    `https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/${assetName}`;

  console.log(`  wasmtime not found. Downloading ${assetName} from Bytecode Alliance...`);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download wasmtime: HTTP ${response.status} from ${url}`);
  }

  // Write archive to a temp directory
  const tmpDir = await Deno.makeTempDir();
  const archivePath = `${tmpDir}/${assetName}`;
  await Deno.writeFile(archivePath, new Uint8Array(await response.arrayBuffer()));

  // Extract — Windows uses .zip (tar -xf), Linux/macOS uses .tar.xz (tar -xJf)
  const tarFlag = Deno.build.os === "windows" ? "-xf" : "-xJf";
  const tar = await new Deno.Command("tar", {
    args: [tarFlag, archivePath, "-C", tmpDir],
    stderr: "inherit",
  }).output();
  if (!tar.success) {
    throw new Error(`Failed to extract wasmtime archive: ${assetName}`);
  }

  // Binary lives inside wasmtime-{version}-{arch}-{os}/ inside the archive
  const archiveStem = assetName.replace(/\.(tar\.xz|zip)$/, "");
  const binName = Deno.build.os === "windows" ? "wasmtime.exe" : "wasmtime";
  const extractedBin = `${tmpDir}/${archiveStem}/${binName}`;

  const cacheDir = getWasmtimeCacheDir();
  await Deno.mkdir(cacheDir, { recursive: true });
  await Deno.copyFile(extractedBin, installPath);

  if (Deno.build.os !== "windows") {
    await new Deno.Command("chmod", { args: ["+x", installPath] }).output();
  }

  // Clean up temp directory
  try { await Deno.remove(tmpDir, { recursive: true }); } catch { /* best-effort */ }

  console.log(`✅ Wasmtime ${WASMTIME_VERSION} installed to ${installPath}`);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * AOT-compiles a `.wasm` file to a `.cwasm` file using `wasmtime compile`.
 *
 * **The output `.cwasm` is machine-specific.** It is tied to the CPU architecture,
 * OS, and wasmtime version used to produce it. It cannot be transferred to or run
 * on a different machine. In exchange it starts faster than a regular `.wasm` file
 * by skipping the JIT compilation step at runtime.
 *
 * @param inputPath  Path to the input `.wasm` file.
 * @param outputPath Path for the output `.cwasm` (default: same dir, `.cwasm` extension).
 */
export async function compileCwasm(inputPath: string, outputPath?: string): Promise<void> {
  await ensureWasmtime();

  const name = basename(inputPath).replace(/\.wasm$/, "");
  const srcDir = dirname(inputPath);
  const cwOut = outputPath ?? `${srcDir}/${name}.cwasm`;

  if (outputPath) await Deno.mkdir(dirname(outputPath), { recursive: true });

  const result = await new Deno.Command(await wasmtimeBin(), {
    args: ["compile", inputPath, "-o", cwOut],
    stderr: "inherit",
  }).output();

  if (!result.success) {
    console.error(`❌ wasmtime compile failed`);
    Deno.exit(1);
  }

  console.log(`✅ AOT compiled (machine-specific): ${cwOut}`);
  console.log(`   ⚠️  This .cwasm is tied to this machine's CPU and OS — it is not portable.`);
}

/**
 * Runs a `.cwasm` file using `wasmtime run`.
 *
 * @param filePath Path to the `.cwasm` file.
 */
export async function runCwasm(filePath: string): Promise<void> {
  await ensureWasmtime();

  const process = new Deno.Command(await wasmtimeBin(), {
    args: ["run", filePath],
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
  }).spawn();

  await process.status;
}
