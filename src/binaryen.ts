/**
 * @module binaryen
 * @description Stable internal facade over whichever Binaryen implementation is
 * configured via the `"binaryen-backend"` specifier in `deno.json`. Source code in
 * the rest of the project imports from `./binaryen.ts`; never from the specifier
 * directly.
 *
 * ⚠️ **The alias is `binaryen-backend`, NOT `binaryen`, deliberately (2026-08-27).** It used to be
 * the bare name `binaryen` — which is also a REAL published package (`npm:binaryen`) that this very
 * facade can be pointed at. One specifier resolving to two different packages depending on config is
 * a defect regardless of what it is called: a reader of `import ... from "binaryen"` cannot tell
 * which one they are getting without opening `deno.json`. Raised by the binaryang team; the sibling
 * `"wabt"` alias is unambiguous and stays as it is.
 *
 * Supported backends (switch by editing `deno.json` only):
 *
 *   "binaryen-backend": "npm:binaryen@^116.0.0"                          // Emscripten WASM blob
 *   "binaryen-backend": "jsr:@jrmarcum/binaryang@1.5.3/compat/binaryen"  // JSR-native TS port (current)
 *   "binaryen-backend": "jsr:@jrmarcum/binaryen-ts@1.5.0/compat"         // SUPERSEDED — see below
 *
 * ⚠️ **`binaryen-ts` and `wabt-ts` merged into `@jrmarcum/binaryang` (2026-08-27).** One package now
 * ships both TypeScript ports, so the two specifiers in `deno.json` point at ONE dependency at the
 * SAME version — `compat/binaryen` here, `compat/wabt` for the `"wabt"` specifier. **They must be
 * bumped together**; a version skew between the two halves is now a self-inflicted wound rather than
 * a fact of life. The merged root export is deliberately empty (56 type names collide across the two
 * retained IRs), so there is no "just import binaryang" shortcut — always take a compat subpath.
 *
 * Both packages expose the same surface (readBinary, Features, setShrinkLevel,
 * setOptimizeLevel, getExportInfo, getFunctionInfo, expandType, i32/i64/...);
 * they only differ in how that surface is reached from an import statement.
 * `npm:binaryen` ships a CommonJS default-export factory; the JSR compat entry
 * is a pure ES-module namespace with no default export.
 *
 * `import * as ns from "binaryen-backend"` works against both:
 *   - npm:binaryen      → ns is a namespace whose `.default` is the binaryen
 *                         factory object that owns readBinary, Features, etc.
 *   - binaryang compat  → ns is the namespace and owns readBinary, Features,
 *                         etc. directly.
 *
 * This module unwraps `.default` when present and re-exports the result as the
 * default export of `./binaryen.ts`. Call sites use a single
 * `import binaryen from "./binaryen.ts"` and stay agnostic to which backend
 * is in deno.json.
 */

// deno-lint-ignore-file no-explicit-any
import * as ns from "binaryen-backend";

const lib: any = (ns as any).default ?? ns;

export default lib;

/**
 * Binaryen `-Oz` over raw wasm bytes. Returns the optimized bytes, or the input unchanged on
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

/**
 * Binaryen Asyncify + `-Oz` over raw wasm bytes — the in-house replacement for
 * `wasm-opt --asyncify -Oz`. Runs the Asyncify pass (which resolves TinyGo's
 * in-wasm `asyncify.*` control imports), then `-Oz`. Used by the Go producer so
 * goroutine code works with NO external binaryen. **Throws** on failure — an
 * un-asyncified goroutine module has unresolved `asyncify.*` imports and would
 * not instantiate, so the caller must surface a hard error rather than ship it.
 * Requires the Binaryen port ≥ binaryen-ts 1.4.1 / binaryang 1.5.1 (in-wasm asyncify-import mode).
 */
export function binaryenAsyncify(bytes: Uint8Array): Uint8Array {
  const m = lib.readBinary(bytes);
  const feat = (lib as Record<string, unknown>)["Features"] as Record<string, number> | undefined;
  if (typeof (m as Record<string, unknown>)["setFeatures"] === "function") {
    (m as { setFeatures(n: number): void }).setFeatures(feat?.["All"] ?? 0x7FFFFFFF);
  }
  (m as { runPasses(p: string[]): void }).runPasses(["Asyncify"]);
  lib.setShrinkLevel(2);
  lib.setOptimizeLevel(2);
  m.optimize();
  const out: Uint8Array = m.emitBinary();
  m.dispose();
  return out;
}
