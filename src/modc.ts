/**
 * @module modc
 * @description Compiles a TypeScript file to a standalone WASM library module
 * (no WASI entry point, no embedded runtime) using the wasic transpiler backend.
 *
 * The output is a pure `.wasm` binary containing only the user's exported
 * functions. It has no `_start`, no embedded JavaScript runtime, and imports
 * only `wasi_snapshot_preview1::fd_write` when console.log is used in a library
 * function (otherwise it has zero imports) — making it directly callable from
 * any WASM host (browser, Node.js, Deno, another WASM module).
 *
 * ── Compilation pipeline ────────────────────────────────────────────────────
 *
 *   .ts source
 *     → tsbundler  (import resolution, module-prefix name mangling)
 *     → WasicTranspiler in library mode  (TypeScript → WAT, no _start, no proc_exit)
 *     → wabt parseWat  (WAT → raw WASM binary)
 *     → Binaryen -Oz  (dead-code elimination, size optimisation)
 *     → .wasm library
 *
 * Library mode differences from WASI mode:
 *   - No _start function is emitted — the module has no entry point.
 *   - proc_exit is never imported or called.
 *   - Top-level runner code (main(), IIFE, top-level statements) is parsed
 *     but silently dropped — only export function declarations are callable.
 *   - Binaryen -Oz eliminates all unreachable internal helpers.
 *
 * ── TypeScript subset ────────────────────────────────────────────────────────
 *
 * The wasic transpiler supports the same TypeScript subset as `wasmtk wasic`:
 * numeric types (i32, i64, f32, f64), structs/interfaces, arrays, classes,
 * generics, string operations, Math intrinsics, and exception handling.
 * See `wasic.ts` module docstring for the full feature list.
 *
 * The source file must contain at least one `export function` declaration.
 */

import { basename, dirname } from "@std/path";
import { compileLibTs } from "./wasic.ts";
import { rt } from "./rt.ts";

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Compiles a TypeScript file to a WASM library module.
 *
 * All top-level runner code (main(), console.log calls, IIFE, top-level
 * statements) is silently dropped — only `export function` declarations
 * appear in the compiled output. Internal (non-exported) functions are
 * included in the WAT but eliminated by Binaryen -Oz if unreachable.
 *
 * @param path    - Path to the source `.ts` file.
 * @param outPath - Optional output path; defaults to `<name>.wasm` in the
 *                  same directory as the source file.
 */
export async function compileModule(path: string, outPath?: string): Promise<void> {
  if (path.endsWith(".wasm") || path.endsWith(".wat")) {
    console.error(`❌ Input Error: modc expects a TypeScript (.ts) file.`);
    return;
  }

  const name = basename(path).replace(/\.[^/.]+$/, "");
  const dir = dirname(path);
  const out = outPath ?? `${dir}/${name}.wasm`;

  console.log(`✅ Building Library: ${basename(out)}`);

  try {
    if (outPath) await rt.mkdir(dirname(outPath), { recursive: true });

    const result = await compileLibTs(path, out);
    if (!result.success) {
      console.error(`❌ modc: ${result.error}`);
    }
  } catch (err) {
    console.error(`❌ modc Exception: ${err}`);
  }
}
