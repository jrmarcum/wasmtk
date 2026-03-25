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
 *   import { foo, bar }           from "./path.ts"
 *   import { foo as f, bar as b } from "./path.ts"
 *   import type { Foo }           from "./path.ts"
 *   import "./path.ts"
 *
 * Non-relative specifiers (jsr:, npm:, https://) are left in place and will
 * surface as unsupported-feature warnings from the transpiler.
 *
 * Circular and duplicate imports are detected via a visited-path set and
 * silently deduplicated (first occurrence wins).
 *
 * ## Limitation
 * Multiline import blocks (opening `{` on a separate line) are not yet
 * handled — use single-line named imports in files intended for wasmtk.
 */

import { basename, dirname, join } from "@std/path";

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
 * Parses the named-import clause of a single-line import statement and returns
 * a map from each **local name** (what the calling file uses) to the
 * **canonical prefixed name** (what will appear in the merged WAT output).
 *
 * Examples (prefix = "mathlib"):
 *   "{ add }"              →  Map { "add"    → "mathlib_add" }
 *   "{ add, multiply }"    →  Map { "add"    → "mathlib_add",
 *                                   "multiply" → "mathlib_multiply" }
 *   "{ add as mathAdd }"   →  Map { "mathAdd" → "mathlib_add" }
 *   "{ add as a, sub }"    →  Map { "a"      → "mathlib_add",
 *                                   "sub"    → "mathlib_sub" }
 *
 * @param clause - The text between `{` and `}` in the import statement.
 * @param prefix - The module prefix derived from the source file's basename.
 * @returns Map of localName → canonicalPrefixedName.
 */
function parseNamedImports(clause: string, prefix: string): Map<string, string> {
  const inner = clause.replace(/^\{|\}$/g, "").trim();
  const map = new Map<string, string>();
  if (!inner) return map;

  for (const part of inner.split(",")) {
    const spec = part.trim();
    if (!spec) continue;
    const asMatch = spec.match(/^(\w+)\s+as\s+(\w+)$/);
    if (asMatch) {
      // "original as alias"  →  alias → prefix_original
      map.set(asMatch[2], `${prefix}_${asMatch[1]}`);
    } else {
      // plain name  →  name → prefix_name
      map.set(spec, `${prefix}_${spec}`);
    }
  }
  return map;
}

/**
 * Applies a rename map to a source string using whole-word (`\b`) boundaries,
 * so that e.g. renaming "add" does not affect "addOne" or "readd".
 *
 * Renames are applied longest-key-first to avoid partial substitution when one
 * renamed symbol is a prefix of another (e.g. "add" vs "addExt").
 *
 * @param src     - Source text to rewrite.
 * @param renames - Map of oldName → newName.
 */
function applyRenames(src: string, renames: Map<string, string>): string {
  // Sort by descending key length so longer names are replaced first
  const entries = [...renames.entries()].sort((a, b) => b[0].length - a[0].length);
  for (const [from, to] of entries) {
    src = src.replace(new RegExp(`\\b${from}\\b`, "g"), to);
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
   * Maps each exported canonical prefixed name to itself (for non-entry files)
   * so callers can build the full rename table for their own import clauses.
   * Keyed by the **original** export name; value is the prefixed name.
   *
   * e.g. for mathlib.ts:  { "add" → "mathlib_add", "multiply" → "mathlib_multiply" }
   */
  exportRenames: Map<string, string>;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Reads a TypeScript entry file, resolves all relative imports recursively,
 * and returns a single merged source string ready for WasicTranspiler.
 *
 * Behaviour:
 * - Imported files are prepended before the content of the file that imports them.
 * - All `import` declarations are stripped from the merged output.
 * - Exported symbols in non-entry files are renamed to `<module>_<name>` in
 *   both their definitions and all internal call sites.
 * - Import aliases are resolved: the alias is rewritten to the canonical
 *   prefixed name at every call site in the importing file.
 * - Missing imported files are silently skipped; the transpiler will surface
 *   any resulting undefined-symbol errors.
 * - If the entry file itself cannot be read, the error propagates to the caller.
 *
 * @param entryPath - Absolute or cwd-relative path to the entry .ts file.
 * @returns Merged source string with all imports inlined and names mangled.
 */
export async function bundleImports(entryPath: string): Promise<string> {
  const visited = new Set<string>();

  async function load(filePath: string, isEntry: boolean): Promise<LoadResult> {
    // ── 1. Resolve canonical path ─────────────────────────────────────────
    let realPath: string;
    try {
      realPath = await Deno.realPath(filePath);
    } catch (err) {
      if (isEntry) throw err;
      return { source: "", exportRenames: new Map() };
    }

    if (visited.has(realPath)) return { source: "", exportRenames: new Map() };
    visited.add(realPath);

    let src: string;
    try {
      src = await Deno.readTextFile(realPath);
    } catch (err) {
      if (isEntry) throw err;
      return { source: "", exportRenames: new Map() };
    }

    const fileDir = dirname(realPath);
    const prefix = modulePrefix(realPath);
    const importedChunks: string[] = [];

    // ── 2. Process import statements ─────────────────────────────────────
    // Regex captures:
    //   group 1 — named-import clause including braces (may be absent for side-effect imports)
    //   group 2 — module specifier string
    const importRe =
      /^[ \t]*import\s+(?:type\s+)?(\{[^}]*\}\s+from\s+)?['"]([^'"]+)['"]\s*;?[ \t]*\r?\n?/gm;

    // Collect all rewrites needed in this file's source after processing imports
    const localRewrites = new Map<string, string>();

    let m: RegExpExecArray | null;
    while ((m = importRe.exec(src)) !== null) {
      const clause    = m[1] ?? ""; // "{foo, bar as b} from " or ""
      const specifier = m[2];

      if (!specifier.startsWith(".")) continue; // skip non-relative specifiers

      const resolved = join(
        fileDir,
        specifier.endsWith(".ts") ? specifier : specifier + ".ts",
      );

      const childResult = await load(resolved, false);
      importedChunks.push(childResult.source);

      // Build local-name → canonical-prefixed-name map for this import
      if (clause) {
        const clauseNames = clause.replace(/\s*from\s*$/, "").trim();
        const childPrefix = modulePrefix(resolved);
        const importMap = parseNamedImports(clauseNames, childPrefix);
        for (const [local, canonical] of importMap) {
          localRewrites.set(local, canonical);
        }
      }
    }

    // ── 3. Strip all import declarations ─────────────────────────────────
    src = src.replace(
      /^[ \t]*import\s+(?:type\s+)?(?:\{[^}]*\}\s+from\s+)?['"][^'"]+['"]\s*;?[ \t]*\r?\n?/gm,
      "",
    );

    // ── 4. Non-entry: rename exported definitions to module-prefixed names ─
    const exportRenames = new Map<string, string>();

    if (!isEntry) {
      // Match: export [async] function|const|let|var|type|interface|enum <Name>
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

    return { source: [...importedChunks, src].join(""), exportRenames };
  }

  const result = await load(entryPath, true);
  return result.source;
}
