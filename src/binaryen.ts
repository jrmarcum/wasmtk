/**
 * @module binaryen
 * @description Stable internal facade over whichever Binaryen package is
 * configured via the `"binaryen"` specifier in `deno.json`. Source code in the
 * rest of the project imports from `./binaryen.ts`; never from `"binaryen"`
 * directly.
 *
 * Supported backends (switch by editing `deno.json` only):
 *
 *   "binaryen": "npm:binaryen@^116.0.0"                      // Emscripten WASM blob
 *   "binaryen": "jsr:@jrmarcum/binaryen-ts@^1.2.2/compat"    // JSR-native TS port
 *
 * Both packages expose the same surface (readBinary, Features, setShrinkLevel,
 * setOptimizeLevel, getExportInfo, getFunctionInfo, expandType, i32/i64/...);
 * they only differ in how that surface is reached from an import statement.
 * `npm:binaryen` ships a CommonJS default-export factory; `binaryen-ts/compat`
 * is a pure ES-module namespace with no default export.
 *
 * `import * as ns from "binaryen"` works against both:
 *   - npm:binaryen      → ns is a namespace whose `.default` is the binaryen
 *                         factory object that owns readBinary, Features, etc.
 *   - binaryen-ts compat→ ns is the namespace and owns readBinary, Features,
 *                         etc. directly.
 *
 * This module unwraps `.default` when present and re-exports the result as the
 * default export of `./binaryen.ts`. Call sites use a single
 * `import binaryen from "./binaryen.ts"` and stay agnostic to which backend
 * is in deno.json.
 */

// deno-lint-ignore-file no-explicit-any
import * as ns from "binaryen";

const lib: any = (ns as any).default ?? ns;

export default lib;

/**
 * binaryen-ts `-Oz` over raw wasm bytes. Returns the optimized bytes, or the input unchanged on
 * failure. Shared by the native producers (Go/Zig) to shrink + strip name/debug sections from
 * toolchain output. (Rust's producer doesn't use this — rsxtk optimizes its own output.)
 */
export function binaryenOptimize(bytes: Uint8Array): { bytes: Uint8Array; optimized: boolean } {
  try {
    const m = lib.readBinary(bytes);
    const feat = (lib as Record<string, unknown>)["Features"] as Record<string, number> | undefined;
    if (typeof (m as Record<string, unknown>)["setFeatures"] === "function") {
      (m as { setFeatures(n: number): void }).setFeatures(feat?.["All"] ?? 0x7FFFFFFF);
    }
    lib.setShrinkLevel(2);
    lib.setOptimizeLevel(2);
    m.optimize();
    const out: Uint8Array = m.emitBinary();
    m.dispose();
    return { bytes: out, optimized: true };
  } catch {
    return { bytes, optimized: false };
  }
}
