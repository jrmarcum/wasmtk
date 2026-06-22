/**
 * @module tsbundler
 * @description Import bundler pre-pass for the wasmtk TypeScript-to-WASM compiler.
 *
 * Resolves relative `import` statements in a TypeScript entry file, merges all
 * imported source files into a single flat source string, and strips import /
 * export declarations so the result can be fed directly into WasicTranspiler.
 *
 * ## Name mangling
 *
 * Every exported symbol from an imported file is prefixed with a module name
 * derived from the file's basename (without extension), so that identically-named
 * functions or variables in different modules never collide in the merged output:
 *
 *   mathlib.ts   →  prefix "mathlib"   →  add        becomes  mathlib_add
 *   myotherlib.ts→  prefix "myotherlib"→  add        becomes  myotherlib_add
 *
 * Import aliases are treated as compile-time local names only and are fully
 * erased — the canonical WAT name is always the module-prefixed original:
 *
 *   import { add as mathAdd } from "./mathlib.ts"
 *   →  mathAdd in this file rewrites to  mathlib_add  in the merged output
 *
 * ## Supported import forms (single-line)
 *
 *   import { foo, bar }             from "./path.ts"   — named imports
 *   import { foo as f, bar as b }   from "./path.ts"   — aliased named imports
 *   import defaultExport            from "./path.ts"   — default import
 *   import * as ns                  from "./path.ts"   — namespace import
 *   import defaultExport, { foo }   from "./path.ts"   — default + named
 *   import type { Foo }             from "./path.ts"   — type-only (erased)
 *   import "./path.ts"                                 — side-effect import
 *
 * ## Supported export forms (non-entry files)
 *
 *   export function foo() {}                           — named function export
 *   export const x = 1                                 — named const export
 *   export default function foo() {}                   — default export
 *   export { foo } from "./lib.ts"                     — named re-export
 *   export { foo as bar } from "./lib.ts"              — aliased re-export
 *   export * from "./lib.ts"                           — wildcard re-export
 *
 * Non-relative specifiers (jsr:, npm:, https://) are left in place and will
 * surface as unsupported-feature warnings from the transpiler.
 *
 * Circular and duplicate imports are detected via a visited-path set and
 * silently deduplicated (first occurrence wins).  Export rename maps are cached
 * separately so re-exports can resolve names from already-visited files.
 *
 * ## Limitation
 * Multiline import blocks (opening `{` on a separate line) are not yet
 * handled — use single-line named imports in files intended for wasmtk.
 */

import { basename, dirname, join } from "@std/path";
import { rt } from "./rt.ts";
import { CAPABILITIES } from "./wasm/caps_bytes.ts";

// ---------------------------------------------------------------------------
// Phase 18 — WASM import types
// ---------------------------------------------------------------------------

/**
 * Describes a .wasm file referenced by an import statement in the entry source.
 * Collected by bundleImportsEx and handed to the wasic compiler for WAT-level merge.
 */
export interface WasmImportEntry {
  /** Resolved absolute path to the .wasm file, or a synthetic `wasmtk:<cap>` id for an
   *  embedded capability (Brief #4) — in that case `bytes`/`witText` are populated and no
   *  file is read. */
  filePath: string;
  /** Module prefix derived from the filename, e.g. "math" for "./math.wasm". */
  prefix: string;
  /**
   * Maps each original export name to its canonical prefixed name.
   * e.g. for math.wasm: { "add" → "math_add", "multiply" → "math_multiply" }
   * Import aliases are already resolved: `{ add as sum }` → localRewrites "sum"→"math_add"
   * but renames still records "add"→"math_add" for use by the merge step.
   */
  renames: Map<string, string>;
  /** Embedded module bytes for a virtual `wasmtk:<cap>` import (Brief #4). When set, the
   *  merge reads these instead of `filePath`. */
  bytes?: Uint8Array;
  /** Embedded `.wit` text for a virtual capability — supplies logical (string) signatures
   *  to the merge in place of a sibling `.wit` file. */
  witText?: string;
}

/** Extended return type from bundleImportsEx — includes both the merged TS source
 *  and any .wasm imports that need WAT-level merging. */
export interface BundleResult {
  /** Merged TypeScript source with all .ts imports inlined and names mangled. */
  source: string;
  /** .wasm imports discovered during bundling, in discovery order. */
  wasmImports: WasmImportEntry[];
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Derives a valid identifier prefix from a file path.
 * Takes the basename without extension and replaces non-word characters with `_`.
 *
 * Examples:
 *   "./mathlib.ts"    →  "mathlib"
 *   "../my-utils.ts"  →  "my_utils"
 *   "./vec2d.ts"      →  "vec2d"
 */
function modulePrefix(filePath: string): string {
  return basename(filePath).replace(/\.[^/.]+$/, "").replace(/\W+/g, "_");
}

/**
 * Parses a named clause `{ foo, bar as baz }` and returns a map of
 * **local/alias name → original name** (without any prefix applied).
 * Used when resolving re-exports against a child's exportRenames.
 */
function parseClauseNames(clause: string): Map<string, string> {
  const inner = clause.replace(/^\{|\}$/g, "").trim();
  const map = new Map<string, string>();
  if (!inner) return map;
  for (const part of inner.split(",")) {
    const spec = part.trim();
    if (!spec) continue;
    const asMatch = spec.match(/^(\w+)\s+as\s+(\w+)$/);
    if (asMatch) {
      map.set(asMatch[2], asMatch[1]); // alias → original
    } else {
      map.set(spec, spec); // name → name
    }
  }
  return map;
}

/**
 * Applies a rename map to a source string.
 *
 * Keys may contain dots (e.g. `ns.foo`) for namespace-import rewrites.
 * All regex metacharacters in keys are escaped.  Renames are applied
 * longest-key-first to avoid partial substitution when one renamed symbol is
 * a prefix of another (e.g. "add" vs "addExt").
 *
 * Boundaries: `(?<!\w)key(?!\w)` — no word character immediately before or after.
 * This is equivalent to `\b` for pure-identifier keys and correctly handles
 * dotted keys like `math.add` (the `.` is a non-word character).
 *
 * @param src     - Source text to rewrite.
 * @param renames - Map of oldName → newName.
 */
function applyRenames(src: string, renames: Map<string, string>): string {
  // Sort by descending key length so longer names are replaced first
  const entries = [...renames.entries()].sort((a, b) => b[0].length - a[0].length);
  for (const [from, to] of entries) {
    // Escape all regex metacharacters (including `.` in namespace keys)
    const escaped = from.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    // Use (?<![\w.]) so a plain identifier rename (e.g. "log" → "LoggerProvider_log")
    // does not match the same identifier used as a method name (e.g. console.log).
    src = src.replace(new RegExp(`(?<![\\w.])${escaped}(?!\\w)`, "g"), to);
  }
  return src;
}

// ---------------------------------------------------------------------------
// Load result — carries renamed source + export rename map back to caller
// ---------------------------------------------------------------------------

interface LoadResult {
  /** Merged source with all imports inlined and names rewritten. */
  source: string;
  /**
   * Maps each **original** export name to the canonical prefixed name for this
   * module.  Used by callers to resolve named, default, and re-export bindings.
   *
   * e.g. for mathlib.ts:
   *   { "add" → "mathlib_add", "default" → "mathlib_compute", ... }
   */
  exportRenames: Map<string, string>;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Reads a TypeScript entry file, resolves all relative imports recursively,
 * and returns the merged source plus any .wasm imports that need WAT-level merging.
 *
 * Behaviour:
 * - .ts imports are inlined: files are prepended before the content that imports them.
 * - .wasm imports are detected and recorded in wasmImports; their call sites in the
 *   merged source are rewritten to the canonical prefixed names (e.g. math_add).
 * - All `import` declarations are stripped from the merged output.
 * - Exported symbols in non-entry files are renamed to `<module>_<name>` in
 *   both their definitions and all internal call sites.
 * - Import aliases are resolved to the canonical prefixed name at every call site.
 * - Namespace imports (`import * as ns`) rewrite `ns.foo` to `module_foo`.
 * - Default imports (`import foo from "./lib"`) rewrite `foo` to the default export.
 * - Re-exports bubble child canonical names into this module's export map.
 * - Missing .ts files are silently skipped; missing .wasm files are recorded
 *   with a warning but do not abort bundling.
 * - If the entry file itself cannot be read, the error propagates to the caller.
 *
 * @param entryPath - Absolute or cwd-relative path to the entry .ts file.
 */
export async function bundleImportsEx(entryPath: string): Promise<BundleResult> {
  const visited = new Set<string>();
  // Collected .wasm imports in discovery order (deduped by resolved path).
  const wasmImports: WasmImportEntry[] = [];
  // Cache exportRenames per realPath so re-export chains can resolve names
  // from already-visited (source-deduplicated) files.
  const exportRenamesCache = new Map<string, Map<string, string>>();

  async function load(filePath: string, isEntry: boolean): Promise<LoadResult> {
    // ── 1. Resolve canonical path ─────────────────────────────────────────
    let realPath: string;
    try {
      realPath = await rt.realPath(filePath);
    } catch (err) {
      if (isEntry) throw err;
      return { source: "", exportRenames: new Map() };
    }

    // Already visited: return empty source but supply cached exportRenames so
    // re-export chains still work.
    if (visited.has(realPath)) {
      return { source: "", exportRenames: exportRenamesCache.get(realPath) ?? new Map() };
    }
    visited.add(realPath);

    let src: string;
    try {
      src = await rt.readTextFile(realPath);
    } catch (err) {
      if (isEntry) throw err;
      return { source: "", exportRenames: new Map() };
    }

    // ── #14.3.1 auto-merge: pull the own dynamic runtime when the entry uses `any` or `eval` ──
    // The `any` type lowers to a boxed dynrt handle and `eval(...)` is the dynrt evaluator, so a
    // program using either needs `wasmtk:dynrt` merged. Rather than a new merge path, inject a
    // synthetic `import { …ops… } from "wasmtk:dynrt"` so the existing virtual-capability handler
    // below merges it (and Binaryen DCE strips the dynrt functions the program doesn't call).
    // Only the ENTRY is scanned; programs without `any`/`eval` are byte-for-byte unaffected.
    if (isEntry && !/from\s+["']wasmtk:dynrt["']/.test(src)) {
      const usesAny = /:\s*any\b/.test(src) || /\bany\[\]/.test(src) || /<\s*any\s*>/.test(src);
      const usesEval = /\beval\s*\(/.test(src);
      if (usesAny || usesEval) {
        const ops = [
          "dynNumber", "dynBool", "dynString", "dynNumberValue", "dynBoolValue", "dynToBool",
          "dynToNumber", "dynStrBytes", "dynStrLen", "dynStrCharAt", "dynTypeof", "dynTag",
          "dynAdd", "dynSub", "dynMul", "dynDiv", "dynMod", "dynNeg", "dynNot", "dynStrictEq",
          "dynLt", "dynGt", "dynLe", "dynGe", "dynApply",
          "dynEval", "dynEvalEnv", "dynObject", "dynArray", "dynSet", "dynGet", "dynPush",
          "dynMakeFunc", "dynStdEnv", "dynUndefined", "dynNull",
          // NOTE: dynMember / dynIndexValue are added in 3.3 when they become dynrt exports.
        ].join(", ");
        src = `import { ${ops} } from "wasmtk:dynrt";\n` + src;
      }
    }

    const fileDir = dirname(realPath);
    const prefix = modulePrefix(realPath);
    const importedChunks: string[] = [];

    // Collect all rewrites needed in this file's source after processing imports
    const localRewrites = new Map<string, string>();

    // exportRenames for this file (populated in steps 2 and 4)
    const exportRenames = new Map<string, string>();

    // ── 2a. Process re-export-from statements ─────────────────────────────
    //   export { foo, bar as baz } from "./lib.ts"
    const reExportNamedRe =
      /^[ \t]*export\s+(?:type\s+)?\{([^}]*)\}\s+from\s+['"]([^'"]+)['"]\s*;?[ \t]*\r?\n?/gm;
    let rm: RegExpExecArray | null;
    while ((rm = reExportNamedRe.exec(src)) !== null) {
      const clause = rm[1];
      const specifier = rm[2];
      if (!specifier.startsWith(".")) continue;
      const resolved = join(
        fileDir,
        specifier.endsWith(".ts") ? specifier : specifier + ".ts",
      );
      const childResult = await load(resolved, false);
      // importedChunks: only add source if it hasn't already been added
      if (childResult.source) importedChunks.push(childResult.source);

      const childPrefix = modulePrefix(resolved);
      // Map alias/name → originalName from the clause
      const clauseMap = parseClauseNames(clause);
      for (const [exported, original] of clauseMap) {
        const canonical = childResult.exportRenames.get(original) ?? `${childPrefix}_${original}`;
        exportRenames.set(exported, canonical);
      }
    }

    //   export * from "./lib.ts"
    const reExportStarRe = /^[ \t]*export\s+\*\s+from\s+['"]([^'"]+)['"]\s*;?[ \t]*\r?\n?/gm;
    let rs: RegExpExecArray | null;
    while ((rs = reExportStarRe.exec(src)) !== null) {
      const specifier = rs[1];
      if (!specifier.startsWith(".")) continue;
      const resolved = join(
        fileDir,
        specifier.endsWith(".ts") ? specifier : specifier + ".ts",
      );
      const childResult = await load(resolved, false);
      if (childResult.source) importedChunks.push(childResult.source);
      // Bubble all of child's exports into this module's export map
      for (const [orig, canonical] of childResult.exportRenames) {
        exportRenames.set(orig, canonical);
      }
    }

    // ── 2b. Process import statements ─────────────────────────────────────
    // Captures everything between `import [type]` and `from "specifier"`.
    // Handles: named `{ foo }`, namespace `* as ns`, default `name`,
    //          combined `name, { foo }`, type-only.
    // Group 1: binding text (may be absent for side-effect imports)
    // Group 2: module specifier
    const importRe =
      /^[ \t]*import\s+(?:type\s+)?(.+?)\s+from\s+['"]([^'"]+)['"]\s*;?[ \t]*\r?\n?/gm;

    let m: RegExpExecArray | null;
    while ((m = importRe.exec(src)) !== null) {
      const binding = m[1].trim(); // e.g. "{ foo }", "* as math", "foo", "foo, { bar }"
      const specifier = m[2];

      // ── Virtual capability imports: `import { setNew } from "wasmtk:set"` (Brief #4) ──
      // Resolved to an embedded modc library; merged only because it's imported here
      // (feature-level tree-shake). No fixture .wasm on disk required.
      if (specifier.startsWith("wasmtk:")) {
        const capId = specifier.slice("wasmtk:".length);
        const cap = CAPABILITIES[capId];
        if (!cap) {
          throw new Error(
            `Unknown capability import "wasmtk:${capId}". Available: ${
              Object.keys(CAPABILITIES).map((k) => "wasmtk:" + k).join(", ")
            }`,
          );
        }
        const renames = new Map<string, string>();
        const namedMatch = binding.match(/\{([^}]*)\}/);
        if (namedMatch) {
          for (const [local, original] of parseClauseNames(namedMatch[1])) {
            const canonical = `${cap.prefix}_${original}`;
            renames.set(original, canonical);
            localRewrites.set(local, canonical);
          }
        }
        const virtualId = `wasmtk:${capId}`;
        if (!wasmImports.some((w) => w.filePath === virtualId)) {
          wasmImports.push({
            filePath: virtualId,
            prefix: cap.prefix,
            renames,
            bytes: cap.bytes,
            witText: cap.wit,
          });
        }
        continue;
      }

      if (!specifier.startsWith(".")) continue; // skip non-relative specifiers

      // ── .wasm imports — record for WAT-level merge, don't inline as TS ───
      if (specifier.endsWith(".wasm")) {
        const resolvedWasm = join(fileDir, specifier);
        const wasmPrefix = modulePrefix(resolvedWasm);
        const renames = new Map<string, string>();

        // Parse named imports: `import { add, multiply as mul } from "./math.wasm"`
        const namedMatch = binding.match(/\{([^}]*)\}/);
        if (namedMatch) {
          for (const [local, original] of parseClauseNames(namedMatch[1])) {
            const canonical = `${wasmPrefix}_${original}`;
            renames.set(original, canonical);
            localRewrites.set(local, canonical);
          }
        }

        if (!wasmImports.some((w) => w.filePath === resolvedWasm)) {
          wasmImports.push({ filePath: resolvedWasm, prefix: wasmPrefix, renames });
        }
        continue; // do not attempt to load .wasm as TypeScript
      }

      const resolved = join(
        fileDir,
        specifier.endsWith(".ts") ? specifier : specifier + ".ts",
      );

      const childResult = await load(resolved, false);
      if (childResult.source) importedChunks.push(childResult.source);

      const childPrefix = modulePrefix(resolved);

      // ── Namespace import: `* as ns` ─────────────────────────────────────
      const nsMatch = binding.match(/^\*\s+as\s+(\w+)$/);
      if (nsMatch) {
        const ns = nsMatch[1];
        // For every exported name from child, register `ns.name → canonical`
        for (const [orig, canonical] of childResult.exportRenames) {
          if (orig !== "default") {
            localRewrites.set(`${ns}.${orig}`, canonical);
          }
        }
        continue;
      }

      // ── Default import: plain identifier (no braces, no `*`) ─────────────
      // May be combined with named: `foo, { bar }`
      let remaining = binding;
      const defaultMatch = remaining.match(/^(\w+)\s*(?:,|$)/);
      if (defaultMatch && !remaining.startsWith("{") && !remaining.startsWith("*")) {
        const localDefault = defaultMatch[1];
        const canonical = childResult.exportRenames.get("default") ?? `${childPrefix}_default`;
        localRewrites.set(localDefault, canonical);
        // Strip the default part; remaining may still have `{ named }`
        remaining = remaining.slice(defaultMatch[0].length).trim();
      }

      // ── Named imports: `{ foo, bar as b }` ──────────────────────────────
      const namedMatch = remaining.match(/\{([^}]*)\}/);
      if (namedMatch) {
        const clauseMap = parseClauseNames(namedMatch[1]);
        for (const [local, original] of clauseMap) {
          const canonical = childResult.exportRenames.get(original) ?? `${childPrefix}_${original}`;
          localRewrites.set(local, canonical);
        }
      }
    }

    // ── 2c. Detect wasmImport("./path.wasm") loader calls ─────────────────
    // Pattern: const { fn, original: alias } = await wasmImport("./module.wasm")
    // Note: destructuring uses JS colon syntax { original: alias }, unlike TS imports
    // which use { original as alias }.  Parse both here.
    const wasmImportCallRe =
      /^[ \t]*(?:const|let)\s+\{([^}]*)\}\s*=\s*await\s+wasmImport\s*\(\s*['"]([^'"]+)['"]\s*\)\s*;?[ \t]*\r?\n?/gm;
    let wi: RegExpExecArray | null;
    while ((wi = wasmImportCallRe.exec(src)) !== null) {
      const clause = wi[1];
      const spec = wi[2];
      if (!spec.endsWith(".wasm") || !spec.startsWith(".")) continue;
      const resolvedWasm = join(fileDir, spec);
      const wasmPrefix = modulePrefix(resolvedWasm);
      const renames = new Map<string, string>();
      // Parse destructuring clause — supports both plain `name` and `original: alias`
      for (const part of clause.split(",")) {
        const spec2 = part.trim();
        if (!spec2) continue;
        const colonIdx = spec2.indexOf(":");
        if (colonIdx !== -1) {
          const original = spec2.slice(0, colonIdx).trim();
          const alias = spec2.slice(colonIdx + 1).trim();
          const canonical = `${wasmPrefix}_${original}`;
          renames.set(original, canonical);
          localRewrites.set(alias, canonical);
        } else {
          const canonical = `${wasmPrefix}_${spec2}`;
          renames.set(spec2, canonical);
          localRewrites.set(spec2, canonical);
        }
      }
      if (!wasmImports.some((w) => w.filePath === resolvedWasm)) {
        wasmImports.push({ filePath: resolvedWasm, prefix: wasmPrefix, renames });
      }
    }

    // ── 3. Strip all import and re-export-from declarations ──────────────
    // Named imports and side-effect imports
    src = src.replace(
      /^[ \t]*import\s+(?:type\s+)?(?:.+?\s+from\s+)?['"][^'"]+['"]\s*;?[ \t]*\r?\n?/gm,
      "",
    );
    // Strip wasmImport() loader calls (replaced by direct WAT-level merge)
    src = src.replace(wasmImportCallRe, "");
    // Re-export-from: `export { … } from "…"` and `export * from "…"`
    src = src.replace(
      /^[ \t]*export\s+(?:type\s+)?\{[^}]*\}\s+from\s+['"][^'"]+['"]\s*;?[ \t]*\r?\n?/gm,
      "",
    );
    src = src.replace(
      /^[ \t]*export\s+\*\s+from\s+['"][^'"]+['"]\s*;?[ \t]*\r?\n?/gm,
      "",
    );

    // ── 4. Non-entry: rename exported definitions to module-prefixed names ─
    if (!isEntry) {
      // Default exports: `export default function foo()`
      src = src.replace(
        /^export\s+default\s+((?:async\s+)?function)\s+(\w+)/gm,
        (_match, keyword, name) => {
          const prefixed = `${prefix}_${name}`;
          exportRenames.set(name, prefixed);
          exportRenames.set("default", prefixed);
          return `${keyword} ${prefixed}`;
        },
      );

      // Named exports: `export [async] function|const|let|var|type|interface|enum Name`
      src = src.replace(
        /^export\s+((?:async\s+)?function|const|let|var|type|interface|enum)\s+(\w+)/gm,
        (_match, keyword, name) => {
          const prefixed = `${prefix}_${name}`;
          exportRenames.set(name, prefixed);
          return `${keyword} ${prefixed}`;
        },
      );

      // Apply those same renames to the rest of this file (internal call sites,
      // recursive calls, field accesses on struct types, etc.)
      src = applyRenames(src, exportRenames);
    }

    // ── 5. Rewrite imported-symbol references in this file ────────────────
    // (applies to both entry and non-entry files — a lib can import from another lib)
    if (localRewrites.size > 0) {
      src = applyRenames(src, localRewrites);
    }

    // Cache export map so re-export chains can resolve names from this module
    // even after it has been deduplicated (source not emitted twice).
    exportRenamesCache.set(realPath, exportRenames);

    return { source: [...importedChunks, src].join(""), exportRenames };
  }

  const result = await load(entryPath, true);
  return { source: result.source, wasmImports };
}

/**
 * Backward-compatible wrapper around bundleImportsEx.
 * Returns only the merged TypeScript source string; .wasm imports are silently
 * collected but not returned.  Use bundleImportsEx when you need the wasm list.
 *
 * @param entryPath - Absolute or cwd-relative path to the entry .ts file.
 * @returns Merged source string with all .ts imports inlined and names mangled.
 */
export async function bundleImports(entryPath: string): Promise<string> {
  const { source } = await bundleImportsEx(entryPath);
  return source;
}
