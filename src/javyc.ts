/**
 * @module javyc
 * @description Javy-based WASI compiler. Bundles TypeScript via Deno and compiles
 * to a WASI-compatible WebAssembly module using the Javy/QuickJS toolchain.
 *
 * Note: Javy embeds the full QuickJS runtime (~500 KB+) into every output binary.
 * For smaller, runtime-free WASI modules use the `wasic` command instead.
 */

import { basename, dirname } from "@std/path";
import { rt } from "./rt.ts";

const JAVY_VERSION = "v8.0.0";

/**
 * Maps the current OS and architecture to the correct Javy release asset name.
 * Asset naming follows the pattern used in bytecodealliance/javy GitHub releases:
 *   javy-{arch}-{os}-{version}.gz
 */
function getJavyAssetName(): string {
  const os = rt.build.os;
  const arch = rt.build.arch;
  const archStr = arch === "aarch64" ? "arm" : "x86_64";
  let osStr: string;
  if (os === "darwin") osStr = "macos";
  else if (os === "windows") osStr = "windows";
  else osStr = "linux";
  return `javy-${archStr}-${osStr}-${JAVY_VERSION}.gz`;
}

/**
 * Returns the path where the Javy binary should be installed.
 * Uses ~/.deno/bin/ which is already on PATH after `deno install`.
 */
export function getJavyInstallPath(): string {
  const home = rt.env.get("HOME") ?? rt.env.get("USERPROFILE") ?? ".";
  const ext = rt.build.os === "windows" ? ".exe" : "";
  return `${home}/.deno/bin/javy${ext}`;
}

/**
 * Checks if the javy binary is available in PATH or at the install location.
 */
export async function isJavyAvailable(): Promise<boolean> {
  try {
    const { success } = await new rt.Command("javy", {
      args: ["--version"],
      stdout: "null",
      stderr: "null",
    }).output();
    return success;
  } catch {
    return false;
  }
}

/**
 * Ensures the Javy binary is available, downloading it from the Bytecode Alliance
 * GitHub releases if not found. Installs to ~/.deno/bin/javy for automatic PATH availability.
 * @throws Error if the download or installation fails.
 */
export async function ensureJavy(): Promise<void> {
  if (await isJavyAvailable()) return;

  const installPath = getJavyInstallPath();

  try {
    await rt.stat(installPath);
    return; // already downloaded but not on PATH
  } catch { /* not yet installed */ }

  const assetName = getJavyAssetName();
  const url = `https://github.com/bytecodealliance/javy/releases/download/${JAVY_VERSION}/${assetName}`;

  console.log(`✅ Javy not found. Downloading ${assetName} from Bytecode Alliance...`);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download Javy: HTTP ${response.status} from ${url}`);
  }

  const compressed = new Uint8Array(await response.arrayBuffer());
  const decompressed = await new Response(
    new Blob([compressed]).stream().pipeThrough(new DecompressionStream("gzip"))
  ).arrayBuffer();

  await rt.mkdir(
    `${rt.env.get("HOME") ?? rt.env.get("USERPROFILE") ?? "."}/.deno/bin`,
    { recursive: true }
  );
  await rt.writeFile(installPath, new Uint8Array(decompressed));

  if (rt.build.os !== "windows") {
    await new rt.Command("chmod", { args: ["+x", installPath] }).output();
  }

  console.log(`✅ Javy ${JAVY_VERSION} installed to ${installPath}`);
}

/**
 * Scans the binary custom sections of a WASM file to detect if it was built by Javy.
 * Javy embeds its version in the standard "producers" custom section (section id=0).
 * Returns "javy" if detected, or null.
 */
export function detectJavyProvider(buf: Uint8Array): string | null {
  if (buf.length < 8 || buf[0] !== 0x00 || buf[1] !== 0x61 || buf[2] !== 0x73 || buf[3] !== 0x6d) {
    return null;
  }

  const readULEB128 = (p: number): [number, number] => {
    let val = 0, shift = 0;
    while (p < buf.length) {
      const b = buf[p++];
      val |= (b & 0x7f) << shift;
      shift += 7;
      if ((b & 0x80) === 0) return [val, p];
    }
    return [val, p];
  };

  const decoder = new TextDecoder();
  let pos = 8;
  while (pos < buf.length) {
    const sectionId = buf[pos++];
    const [sectionSize, bodyPos] = readULEB128(pos);
    const sectionEnd = bodyPos + sectionSize;
    pos = sectionEnd;

    if (sectionId !== 0) continue;

    let p = bodyPos;
    const [nameLen, afterName] = readULEB128(p); p = afterName;
    const sectionName = decoder.decode(buf.slice(p, p + nameLen));

    if (
      sectionName === "producers" ||
      sectionName === "import_namespace" ||
      sectionName.startsWith("javy")
    ) {
      const bodyText = decoder.decode(buf.slice(p + nameLen, sectionEnd));
      if (bodyText.toLowerCase().includes("javy")) return "javy";
    }
  }
  return null;
}

/**
 * Compiles a TypeScript file into a WASI-compliant module using Javy (javyc).
 * Bundles the TS file via Deno, prepends a Javy-compatible prompt polyfill,
 * then invokes the Javy binary to produce a self-contained WASM.
 *
 * @param path - Path to the source .ts file.
 */
export async function compileJavy(path: string, outPath?: string): Promise<void> {
  await ensureJavy();
  const name = basename(path).replace(/\.[^/.]+$/, "");
  const srcDir = dirname(path);
  const wasmOut = outPath ?? `${srcDir}/${name}.wasm`;
  const jsOut = outPath ? outPath.replace(/\.wasm$/, ".js") : `${srcDir}/${name}.js`;

  if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });

  const bundle = new rt.Command(rt.execPath(), {
    args: ["bundle", "--quiet", path],
    stdout: "piped",
  });
  const output = await bundle.output();
  const preamble = `const prompt = function(message) { if (message) { Javy.IO.writeSync(1, new TextEncoder().encode(message + " ")); } let input = ""; const buffer = new Uint8Array(1); while (true) { const n = Javy.IO.readSync(0, buffer); if (n > 0) { const char = new TextDecoder().decode(buffer); if (char === "\\n" || char === "\\r") break; input += char; } else if (n === 0) { continue; } else { break; } } return input.trim(); };`;
  await rt.writeTextFile(jsOut, preamble + new TextDecoder().decode(output.stdout));
  const javyCmd = (await isJavyAvailable()) ? "javy" : getJavyInstallPath();
  const javy = new rt.Command(javyCmd, {
    args: ["build", jsOut, "-o", wasmOut],
  });
  if ((await javy.output()).success) console.log(`✅ Javy WASI: ${wasmOut}`);
}
