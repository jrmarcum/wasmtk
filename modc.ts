/**
 * @module modc
 * @description Compiles a TypeScript file to a standalone WASM library module
 * (no WASI entry point, no embedded runtime) using AssemblyScript (asc).
 *
 * The output is a pure `.wasm` binary containing only the user's exported
 * functions. It has no `_start`, no WASI imports, and no JavaScript runtime —
 * making it directly callable from any WASM host (browser, Node.js, Deno,
 * another WASM module).
 *
 * ── Compilation pipeline ────────────────────────────────────────────────────
 *
 *   .ts source
 *     → extract export function declarations
 *     → remap number types to f64 (asc compatibility)
 *     → AssemblyScript compiler (asc) with --runtime stub
 *     → binary post-process: strip env/abort import + start section
 *     → .wasm library
 *
 * The binary post-processing step (removeEnvAbortImport) is necessary because
 * AssemblyScript's default output may include an `env/abort` import and a start
 * section, both of which are incompatible with strict library runtimes like
 * wasmtime and wasmer. The patch rewrites the WASM binary directly at the
 * section level without a WAT round-trip.
 *
 * ── Planned future backend ───────────────────────────────────────────────────
 *
 * A future "wasic library mode" will offer an alternative backend that skips
 * the AssemblyScript toolchain entirely. The WasicTranspiler already generates
 * correct WAT for function bodies; a library-mode switch will drop the WASI
 * scaffolding (wasi_snapshot_preview1 imports, fd_write helpers, _start binding)
 * and emit a pure WASM module directly. This eliminates the temp-file and
 * binary-patching steps and produces cleaner output.
 *
 * The public API (compileModule) will remain stable across the backend change.
 *
 * ── AssemblyScript TypeScript subset ────────────────────────────────────────
 *
 * AssemblyScript is a strict TypeScript subset with its own type system.
 * Key differences from standard TypeScript:
 *   - Explicit integer types required: i32, i64, f32, f64 (not number)
 *   - No closures, no prototype chain, no dynamic dispatch without explicit vtable
 *   - Generics are supported (monomorphized at compile time)
 *   - Classes and interfaces are supported
 *   - Memory is manually managed (no GC by default; --runtime stub for libraries)
 *
 * ── Input requirements ───────────────────────────────────────────────────────
 *
 * The source file must contain at least one `export function` declaration.
 * Top-level runner code (main(), IIFE, console.log, import.meta.main blocks)
 * is stripped before compilation — only export functions are passed to asc.
 */

import { main as asc } from "asc";
import { basename, dirname, join } from "@std/path";

// ---------------------------------------------------------------------------
// Binary post-processor
// ---------------------------------------------------------------------------

/**
 * Post-processes a compiled WASM library binary to:
 *  1. Remove any `env/abort` import left over from AssemblyScript
 *  2. Remove the start section (section id=8), which is illegal in library modules
 *
 * Both fixes make the binary compatible with strict runtimes (wasmtime, wasmer).
 * Operates directly on the WASM binary format without a WAT round-trip.
 *
 * WASM binary structure relevant here:
 *   Section 2 (import):  [id=2][size][num_imports][ [mod_len][mod][name_len][name][kind][...] ... ]
 *   Section 8 (start):   [id=8][size][func_index]  — dropped entirely for libraries
 */
async function removeEnvAbortImport(wasmPath: string): Promise<void> {
  const bytes = await Deno.readFile(wasmPath);
  const buf = new Uint8Array(bytes);

  const readULEB128 = (p: number): [number, number] => {
    let val = 0, shift = 0;
    while (true) {
      const b = buf[p++];
      val |= (b & 0x7f) << shift;
      shift += 7;
      if ((b & 0x80) === 0) return [val, p];
    }
  };

  const writeULEB128 = (n: number): Uint8Array => {
    const out: number[] = [];
    do {
      let b = n & 0x7f; n >>>= 7;
      if (n !== 0) b |= 0x80;
      out.push(b);
    } while (n !== 0);
    return new Uint8Array(out);
  };

  const outputChunks: Uint8Array[] = [buf.slice(0, 8)]; // WASM magic + version header
  let pos = 8;
  let patched = false;

  while (pos < buf.length) {
    const sectionIdPos = pos;
    const sectionId = buf[pos++];
    const [sectionSize, bodyPos] = readULEB128(pos);
    const sectionEndPos = bodyPos + sectionSize;
    pos = sectionEndPos;

    // Section 8 (start): drop entirely — invalid for library modules
    if (sectionId === 8) {
      patched = true;
      continue;
    }

    // Section 2 (import): filter out env/abort if present
    if (sectionId === 2) {
      let p = bodyPos;
      const [numImports, afterCount] = readULEB128(p); p = afterCount;

      const entries: Array<{ bytes: Uint8Array; drop: boolean }> = [];
      for (let i = 0; i < numImports; i++) {
        const entryStart = p;
        const [modLen, p2] = readULEB128(p); p = p2;
        const modName = new TextDecoder().decode(buf.slice(p, p + modLen)); p += modLen;
        const [nameLen, p3] = readULEB128(p); p = p3;
        const fieldName = new TextDecoder().decode(buf.slice(p, p + nameLen)); p += nameLen;
        const kind = buf[p++];
        // Advance past the import descriptor (varies by kind)
        if (kind === 0) { const [, np] = readULEB128(p); p = np; }
        else if (kind === 1) { p++; const f = buf[p++]; const [, np] = readULEB128(p); p = np; if (f & 1) { const [, np2] = readULEB128(p); p = np2; } }
        else if (kind === 2) { const f = buf[p++]; const [, np] = readULEB128(p); p = np; if (f & 1) { const [, np2] = readULEB128(p); p = np2; } }
        else if (kind === 3) { p += 2; }
        const drop = modName === "env" && fieldName === "abort";
        if (drop) patched = true;
        entries.push({ bytes: buf.slice(entryStart, p), drop });
      }

      const kept = entries.filter(e => !e.drop);
      if (kept.length === entries.length) {
        outputChunks.push(buf.slice(sectionIdPos, sectionEndPos));
        continue;
      }

      // Rebuild import section without the dropped entries
      const newCount = writeULEB128(kept.length);
      const bodyLen = newCount.length + kept.reduce((a, e) => a + e.bytes.length, 0);
      const newSectionSize = writeULEB128(bodyLen);
      const section = new Uint8Array(1 + newSectionSize.length + bodyLen);
      let wp = 0;
      section[wp++] = 2;
      section.set(newSectionSize, wp); wp += newSectionSize.length;
      section.set(newCount, wp); wp += newCount.length;
      for (const e of kept) { section.set(e.bytes, wp); wp += e.bytes.length; }
      outputChunks.push(section);
      continue;
    }

    // All other sections: emit unchanged
    outputChunks.push(buf.slice(sectionIdPos, sectionEndPos));
  }

  if (!patched) return;

  const totalLen = outputChunks.reduce((a, c) => a + c.length, 0);
  const result = new Uint8Array(totalLen);
  let wp = 0;
  for (const chunk of outputChunks) { result.set(chunk, wp); wp += chunk.length; }
  await Deno.writeFile(wasmPath, result);
  console.log("  ✅ Patched: removed start section and env/abort import for standalone runtime compatibility");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Compiles a TypeScript file to a WASM library module using AssemblyScript.
 *
 * Only `export function` declarations are passed to the compiler — all other
 * top-level code (main(), console.log, IIFE, import.meta.main blocks) is
 * stripped so that asc does not encounter unsupported syntax.
 *
 * @param path    - Path to the source `.ts` file.
 * @param outPath - Optional output path; defaults to `<name>.wasm` in the
 *                  same directory as the source file.
 */
export async function compileModule(path: string, outPath?: string): Promise<void> {
  if (path.endsWith(".wasm") || path.endsWith(".wat")) {
    console.error(`❌ Input Error: modc expects an AssemblyScript (.ts) file.`);
    return;
  }

  const name = basename(path).replace(/\.[^/.]+$/, "");
  const dir = dirname(path);
  const tempTsPath = join(dir, `${name}.build.tmp.ts`);
  const out = outPath ?? `./${name}.wasm`;

  console.log(`✅ Building Library: ${basename(out)}`);

  try {
    if (outPath) await Deno.mkdir(dirname(outPath), { recursive: true });

    const fullSource = await Deno.readTextFile(path);

    // Extract only `export function` declarations.
    // Strips runner code, IIFEs, top-level calls, console.log, and
    // import.meta.main blocks that asc cannot parse.
    const exportFunctions: string[] = [];
    const exportFnRegex = /^export\s+function\s+[\s\S]*?^}/gm;
    let match: RegExpExecArray | null;
    while ((match = exportFnRegex.exec(fullSource)) !== null) {
      exportFunctions.push(match[0]);
    }

    if (exportFunctions.length === 0) {
      console.error(`❌ No exported functions found in ${path}. Use "export function" syntax.`);
      return;
    }

    // Remap TypeScript `number` → `f64` for AssemblyScript compatibility
    const source = exportFunctions
      .join("\n\n")
      .replace(/:\s*number/g, ": f64");

    console.log(`  Extracted ${exportFunctions.length} export function(s)`);

    // Use --runtime stub so asc emits no env/abort import or GC overhead
    await Deno.writeTextFile(tempTsPath, source);
    const { error, stderr } = await asc([
      tempTsPath,
      "--target", "release",
      "--outFile", out,
      "--optimize",
      "--noAssert",
      "--runtime", "stub",
      "--converge",
    ]);

    if (!error) {
      // Strip any remaining start section and env/abort import from the binary.
      // asc --runtime stub usually avoids these, but the patch is a safety net.
      await removeEnvAbortImport(out);
      console.log(`✅ Library Ready: ${out}`);
    } else {
      console.error(`❌ Build failed: ${error.message}`);
      if (stderr) console.error(stderr.toString());
    }
  } catch (err) {
    console.error(`❌ modc Exception: ${err}`);
  } finally {
    try { await Deno.remove(tempTsPath); } catch { /* temp file may not exist */ }
  }
}
