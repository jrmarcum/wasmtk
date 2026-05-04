/**
 * src/componentize.ts — WASI Preview 2 component wrapping.
 *
 * Uses @bytecodealliance/jco's `componentNew` API to wrap a wasic-compiled
 * core WASM module as a proper WebAssembly Component Model binary — no
 * separate CLI install required.
 *
 * Two consumer paths exist downstream of the component:
 *   - Cross-language (Rust, Python, C, etc.): use the .component.wasm directly
 *     with a Component Model runtime (wasmtime, etc.)
 *   - TypeScript / browser: use `jco transpile` to get an importable JS module,
 *     or load the core .wasm directly with universal-wasm-loader (no component
 *     needed for that path)
 */

import { componentNew, componentWit, preview1AdapterCommandPath } from "@bytecodealliance/jco";
import { fileURLToPath } from "node:url";
import { rt } from "./rt.ts";

/** Extract the world name from a WIT source string. */
function extractWorldName(wit: string): string {
  const m = wit.match(/world\s+([\w-]+)\s*\{/);
  return m?.[1] ?? "";
}

/**
 * Returns true if the WASM binary imports from wasi_snapshot_preview1.
 * Used to decide whether to attach the WASI p1→p2 adapter.
 */
function detectWasiImports(bytes: Uint8Array): boolean {
  const marker = new TextEncoder().encode("wasi_snapshot_preview1");
  for (let i = 0; i <= bytes.length - marker.length; i++) {
    if (bytes[i] !== marker[0]) continue;
    let match = true;
    for (let j = 1; j < marker.length; j++) {
      if (bytes[i + j] !== marker[j]) { match = false; break; }
    }
    if (match) return true;
  }
  return false;
}

/**
 * Wrap a wasic-compiled core WASM module as a WASI Preview 2 component.
 *
 * - The .wit file must exist alongside the .wasm (wasic writes it automatically).
 * - WASI p1 modules (standard wasic output) get the p1→p2 command adapter applied.
 * - Pure library modules (modc output, no WASI imports) are wrapped as-is.
 */
export async function runComponentize(wasmPath: string, outPath?: string): Promise<void> {
  const witPath = wasmPath.replace(/\.wasm$/, ".wit");

  // Verify both input files exist.
  for (const [label, path] of [["WASM", wasmPath], ["WIT", witPath]] as [string, string][]) {
    try {
      await rt.stat(path);
    } catch {
      console.error(`❌ componentize: ${label} file not found: ${path}`);
      if (label === "WIT") {
        console.error(`   Run 'wasmtk wasic ${wasmPath.replace(/\.wasm$/, ".ts")}' to regenerate it.`);
      }
      rt.exit(1);
      return;
    }
  }

  // Parse world name from WIT.
  const witSrc = await rt.readTextFile(witPath);
  const worldName = extractWorldName(witSrc);
  if (!worldName) {
    console.error(`❌ componentize: no world declaration found in ${witPath}`);
    rt.exit(1);
    return;
  }

  const componentPath = outPath ?? wasmPath.replace(/\.wasm$/, ".component.wasm");
  const coreWasm = await rt.readFile(wasmPath);

  console.log(`🔧 componentize: ${wasmPath}`);
  console.log(`   WIT:   ${witPath}`);
  console.log(`   World: ${worldName}`);

  // Attach the WASI p1→p2 adapter only when the module actually uses WASI.
  // Pure computation modules (modc) need no adapter.
  let adapters: [string, Uint8Array][] | undefined;
  if (detectWasiImports(coreWasm)) {
    const adapterPath = fileURLToPath(preview1AdapterCommandPath());
    const adapterBytes = await rt.readFile(adapterPath);
    adapters = [["wasi_snapshot_preview1", adapterBytes]];
    console.log(`   Adapter: WASI p1 → p2 (command)`);
  }

  const componentBytes = await componentNew(coreWasm, adapters);
  await rt.writeFile(componentPath, componentBytes);

  // Extract the WIT interface that is now encoded inside the component binary.
  // This confirms the component is self-describing: any Component Model consumer
  // (wasmtime, wit-bindgen, jco transpile) can read the interface from the binary
  // without needing the source .wit file.
  // Note: the world name comes from the binary's export structure, not our source
  // .wit, so it may differ — the source .wit remains the authoritative contract.
  const extractedWit = await componentWit(componentBytes);
  const witOutPath = componentPath.replace(/\.wasm$/, ".wit");
  await rt.writeTextFile(witOutPath, extractedWit);

  console.log(`✅ Component: ${componentPath} (${componentBytes.length} bytes)`);
  console.log(`   Interface: ${witOutPath} (extracted from component binary)`);
}
