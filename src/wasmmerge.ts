/**
 * @module wasmmerge
 * @description Phase 18 — WAT-level merge of imported WASM modules.
 *
 * Converts an imported .wasm binary (already disassembled to WAT text by wabt)
 * into a fragment that can be appended into the main module's WAT source before
 * the final wabt compile step.
 *
 * ## What this module does
 *
 *  1. Extracts top-level forms from the WAT (types, imports, functions, globals,
 *     data segments) using a parenthesis-depth scanner.
 *  2. Identifies and strips entry-only features (_start, proc_exit, args_get,
 *     args_sizes_get, environ_get, environ_sizes_get), emitting informational
 *     notices so the user knows what happened.
 *  3. Deduplicates WASI imports — WASI functions used by the imported module are
 *     assumed to already be declared in the main module and are not re-emitted.
 *  4. Applies module-prefix name mangling to every function and global name, using
 *     the same prefix scheme as tsbundler.ts for .ts imports.
 *  5. Relocates data segment base addresses by a caller-supplied delta so that the
 *     imported module's static data is placed above the main module's data section.
 *  6. Conservatively relocates data-pointer i32.const values in function bodies:
 *     any i32.const >= DATA_PTR_THRESHOLD (260) is assumed to be a static-data
 *     pointer and is shifted by the same delta.  Small integer literals are left
 *     untouched.
 *  7. Returns the ExternalFuncDef list so WasicTranspiler can register imported
 *     functions in its function table and correctly type call expressions.
 *
 * ## Complexity tiers handled
 *
 *  ✅  Pure computation (no memory, no WASI imports) — clean merge
 *  ✅  Modules with globals — prefixed like functions
 *  ✅  Modules sharing WASI imports (fd_write etc.) — deduplicated
 *  ✅  Modules with memory / data segments — conservative pointer relocation
 *
 * ## Limitations
 *
 *  - call_indirect with imported type indices may fail if the imported module's
 *    type table conflicts with the main module's.  Phase 18 strips type declarations
 *    from imports (the main module emits its own), so call_indirect is unsupported
 *    for now.  Direct calls work fine.
 *  - i32.const values that happen to be >= 260 but are NOT pointers (e.g. a magic
 *    constant 1000) will be incorrectly relocated.  This is a known conservative
 *    over-approximation; use data-section-free modc libraries when precision matters.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Numeric WAT value types (subset of WatType — no pseudo-types like "string"). */
export type WasmWatType = "i32" | "i64" | "f32" | "f64";

/**
 * Describes an exported function from a merged WASM import.
 * Registered into WasicTranspiler.functions so call sites are typed correctly.
 */
export interface ExternalFuncDef {
  /** Canonical prefixed name, e.g. "math_add" for add exported from math.wasm */
  name: string;
  params: WasmWatType[];
  result: WasmWatType | null;
}

/** Result returned by mergeWasmWat — everything the caller needs to assemble the merged WAT. */
export interface WatMergeResult {
  /** Mangled (func ...) definitions ready to splice into the main module body. */
  funcWat: string;
  /** Mangled (global ...) definitions (excluding the heap-pointer global). */
  globalWat: string;
  /** Relocated (data ...) segments. */
  dataWat: string;
  /** WASI function names the imported module uses — for deduplication in main. */
  wasiImportNames: string[];
  /** Exported function signatures for WasicTranspiler registration. */
  exportedFuncs: ExternalFuncDef[];
  /** Human-readable notices about stripped entry-only features. */
  notices: string[];
  /**
   * Export declarations ready to splice into a master module.
   * Populated only when exportOverrides is passed to mergeWasmWat (wasmbundle mode).
   * Each entry is like: (export "add" (func $math_add))
   */
  exportDecls: string[];
  /**
   * Mapping from original export name to mangled internal WAT symbol name.
   * e.g. "add" → "$mathlib_add". Populated for all exports regardless of whether
   * exportOverrides was passed. Callers can use this to understand the internal name
   * mapping without reconstructing it from the prefix and export name.
   */
  exportMap: Map<string, string>;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** i32.const values >= this threshold are treated as static-data pointers and relocated. */
const DATA_PTR_THRESHOLD = 260; // = DATA_BASE from console_log.ts

/** WASI snapshot module name. */
const WASI_MODULE = "wasi_snapshot_preview1";

/** Functions / exports that only make sense in a running WASI process — always stripped. */
const ENTRY_ONLY_NAMES = new Set([
  "_start",
  "proc_exit",
  "args_get",
  "args_sizes_get",
  "environ_get",
  "environ_sizes_get",
]);

// ---------------------------------------------------------------------------
// WAT form extraction
// ---------------------------------------------------------------------------

/**
 * Extracts the top-level s-expression forms from inside a WAT module.
 * Uses a parenthesis-depth counter; depth 1 = inside (module ...), so
 * depth-2 forms are the immediate children we want.
 */
function extractForms(wat: string): string[] {
  const moduleIdx = wat.indexOf("(module");
  if (moduleIdx === -1) return [];

  const forms: string[] = [];
  let depth = 0;
  let formStart = -1;

  for (let i = moduleIdx; i < wat.length; i++) {
    if (wat[i] === "(") {
      depth++;
      if (depth === 2) formStart = i;
    } else if (wat[i] === ")") {
      if (depth === 2 && formStart !== -1) {
        forms.push(wat.slice(formStart, i + 1));
        formStart = -1;
      }
      depth--;
    }
  }
  return forms;
}

/** Returns the first keyword inside a parenthesised form, e.g. "func" from "(func ...)". */
function formKind(form: string): string {
  return form.match(/^\(\s*(\w+)/)?.[1] ?? "";
}

/**
 * Returns the bare (non-prefixed) export names of functions in a WAT module,
 * excluding entry-only names (_start, proc_exit, etc.).
 * Used by wasmbundle to detect conflicting export names before merging.
 */
export function extractExportNames(wat: string): string[] {
  const forms = extractForms(wat);
  const names: string[] = [];
  for (const form of forms) {
    if (formKind(form) !== "export") continue;
    const m = form.match(/\(export\s+"([^"]+)"\s+\(func\s+\d+\)\)/);
    if (m && !ENTRY_ONLY_NAMES.has(m[1])) names.push(m[1]);
  }
  return names;
}

// ---------------------------------------------------------------------------
// Type-table parsing
// ---------------------------------------------------------------------------

/** Parse type declarations: index → { params, result } */
function parseTypeTable(forms: string[]): Map<number, { params: WasmWatType[]; result: WasmWatType | null }> {
  const table = new Map<number, { params: WasmWatType[]; result: WasmWatType | null }>();
  for (const form of forms) {
    if (formKind(form) !== "type") continue;
    const idxM = form.match(/\(;(\d+);\)/);
    if (!idxM) continue;
    const idx = parseInt(idxM[1]);

    const params: WasmWatType[] = [];
    for (const pm of (form.match(/\(param([^)]*)\)/g) ?? [])) {
      for (const t of pm.replace("(param", "").replace(")", "").trim().split(/\s+/)) {
        if (t === "i32" || t === "i64" || t === "f32" || t === "f64") params.push(t as WasmWatType);
      }
    }
    const resM = form.match(/\(result\s+(i32|i64|f32|f64)\)/);
    table.set(idx, { params, result: resM ? (resM[1] as WasmWatType) : null });
  }
  return table;
}

// ---------------------------------------------------------------------------
// Main merge function
// ---------------------------------------------------------------------------

/**
 * Parses a WAT module string (from wabt disassembly) and produces a
 * WatMergeResult containing the renamed, relocated fragments ready to be
 * spliced into the parent module.
 *
 * @param wat        WAT text produced by wabt.readWasm(...).toText()
 * @param prefix     Module prefix for name mangling, e.g. "math" for math.wasm
 * @param dataReloc  Byte delta to add to data addresses (= mainModule.dataOffset)
 */
export function mergeWasmWat(
  wat: string,
  prefix: string,
  dataReloc: number,
  exportOverrides?: Map<string, string | null>,
): WatMergeResult {
  const forms = extractForms(wat);
  const typeTable = parseTypeTable(forms);

  const notices: string[] = [];
  const wasiImportNames: string[] = [];

  // ── Pass 1: Build index maps ──────────────────────────────────────────────

  // importFuncIdx → { module, name }
  const importMap = new Map<number, { module: string; name: string }>();
  // funcIdx (absolute, including imports) → export name
  const exportFuncMap = new Map<number, string>();
  // funcIdx → WAT type index string (for resolving signatures)
  const funcTypeIndexMap = new Map<number, number>();

  for (const form of forms) {
    const kind = formKind(form);

    if (kind === "import") {
      // (import "module" "name" (func (;N;) (type T)))
      const modM = form.match(/\(import\s+"([^"]+)"\s+"([^"]+)"/);
      const idxM = form.match(/\(func\s+\(;(\d+);\)/);
      if (modM && idxM) {
        importMap.set(parseInt(idxM[1]), { module: modM[1], name: modM[2] });
      }
    }

    if (kind === "export") {
      // (export "name" (func N)) — index is a plain number, not (;N;)
      const expM = form.match(/\(export\s+"([^"]+)"\s+\(func\s+(\d+)\)\)/);
      if (expM) {
        exportFuncMap.set(parseInt(expM[2]), expM[1]);
      }
    }

    if (kind === "func") {
      const idxM = form.match(/\(func\s+\(;(\d+);\)/);
      const typeM = form.match(/\(type\s+(\d+)\)/);
      if (idxM && typeM) {
        funcTypeIndexMap.set(parseInt(idxM[1]), parseInt(typeM[1]));
      }
    }
  }

  // ── Identify & strip entry-only items ────────────────────────────────────

  const strippedNames: string[] = [];

  // Strip entry-only from export map
  for (const [idx, name] of exportFuncMap) {
    if (ENTRY_ONLY_NAMES.has(name)) {
      strippedNames.push(name);
      exportFuncMap.delete(idx);
    }
  }
  // Find import indices for entry-only WASI functions
  const entryOnlyImportIdxs = new Set<number>();
  for (const [idx, info] of importMap) {
    if (ENTRY_ONLY_NAMES.has(info.name)) {
      strippedNames.push(`${info.name} (import)`);
      entryOnlyImportIdxs.add(idx);
    }
  }
  for (const idx of entryOnlyImportIdxs) importMap.delete(idx);

  if (strippedNames.length > 0) {
    const unique = [...new Set(strippedNames.map(n => n.replace(" (import)", "")))];
    notices.push(`entry-only features excluded: ${unique.join(", ")}. Module converted to library mode.`);
  }

  // ── Build funcIdx → canonical WAT $name ──────────────────────────────────

  const funcName = new Map<number, string>();

  // Imported WASI functions → keep canonical name (deduplicated in main module)
  for (const [idx, info] of importMap) {
    if (info.module === WASI_MODULE) {
      wasiImportNames.push(info.name);
      funcName.set(idx, `$${info.name}`);
    } else {
      funcName.set(idx, `$${prefix}_${info.name}`);
    }
  }

  // Exported non-import functions → prefix_exportName
  for (const [idx, exportName] of exportFuncMap) {
    if (!importMap.has(idx)) {
      funcName.set(idx, `$${prefix}_${exportName}`);
    }
  }

  // Internal (non-exported, non-imported) functions → prefix__fnN
  for (const form of forms) {
    if (formKind(form) !== "func") continue;
    const idxM = form.match(/\(func\s+\(;(\d+);\)/);
    if (!idxM) continue;
    const idx = parseInt(idxM[1]);
    if (!funcName.has(idx)) {
      funcName.set(idx, `$${prefix}__fn${idx}`);
    }
  }

  // ── Build ExternalFuncDef list ────────────────────────────────────────────

  const exportedFuncs: ExternalFuncDef[] = [];
  for (const [idx, exportName] of exportFuncMap) {
    if (importMap.has(idx)) continue; // skip WASI re-exports
    const typeIdx = funcTypeIndexMap.get(idx);
    const sig = typeIdx !== undefined ? typeTable.get(typeIdx) : undefined;
    exportedFuncs.push({
      name: `${prefix}_${exportName}`,
      params: sig?.params ?? [],
      result: sig?.result ?? null,
    });
  }

  // ── Build exportMap (original name → mangled internal name) ─────────────
  //
  // Populated for every exported function regardless of whether exportOverrides
  // was supplied. e.g. "add" → "$mathlib_add". Callers can use this to
  // understand the internal symbol mapping without re-deriving it.

  const exportMap = new Map<string, string>();
  for (const [idx, exportName] of exportFuncMap) {
    if (importMap.has(idx)) continue;
    const internalName = funcName.get(idx) ?? `$${prefix}__fn${idx}`;
    exportMap.set(exportName, internalName);
  }

  // ── Build export declarations (wasmbundle mode) ───────────────────────────
  //
  // When exportOverrides is supplied, emit (export "name" (func $internal)) lines.
  // The override value controls the exported name:
  //   null            → excluded (skip)
  //   "some_name"     → use that as the public export name (may differ from internal)
  //   (key absent)    → skip (caller should cover all exports)

  const exportDecls: string[] = [];
  if (exportOverrides !== undefined) {
    for (const [originalName, internalName] of exportMap) {
      const outputName = exportOverrides.get(originalName);
      if (outputName == null) continue; // null = excluded, undefined = not provided
      exportDecls.push(`(export "${outputName}" (func ${internalName}))`);
    }
  }

  // ── Helpers for body transformation ──────────────────────────────────────

  /** Replace `call N` / `call_indirect (type T)` index refs with named $refs. */
  function renameCallSites(text: string): string {
    return text.replace(/\bcall\s+(\d+)\b/g, (_, numStr) => {
      const name = funcName.get(parseInt(numStr));
      return name ? `call ${name}` : `call ${numStr}`;
    });
  }

  /** Replace `global.get N` / `global.set N` numeric refs with named $refs. */
  function renameGlobalRefs(text: string): string {
    return text
      .replace(/\bglobal\.get\s+(\d+)\b/g, (match, numStr) => {
        const name = `$${prefix}_global${parseInt(numStr)}`;
        return `global.get ${name}`;
      })
      .replace(/\bglobal\.set\s+(\d+)\b/g, (match, numStr) => {
        const name = `$${prefix}_global${parseInt(numStr)}`;
        return `global.set ${name}`;
      });
  }

  /**
   * Shift i32.const values >= DATA_PTR_THRESHOLD (260) by dataReloc.
   * These are assumed to be static-data pointers; small literals are left alone.
   */
  function relocateDataPtrs(text: string): string {
    if (dataReloc === 0) return text;
    return text.replace(/\bi32\.const\s+(\d+)\b/g, (match, numStr) => {
      const n = parseInt(numStr);
      return n >= DATA_PTR_THRESHOLD ? `i32.const ${n + dataReloc}` : match;
    });
  }

  // ── Pass 2: Transform forms ───────────────────────────────────────────────

  const funcParts: string[] = [];
  const globalParts: string[] = [];
  const dataParts: string[] = [];

  for (const form of forms) {
    const kind = formKind(form);

    // ── Skip / handle imports ───────────────────────────────────────────────
    if (kind === "import") {
      const idxM = form.match(/\(func\s+\(;(\d+);\)/);
      if (!idxM) continue;
      const idx = parseInt(idxM[1]);
      const info = importMap.get(idx);
      if (!info) continue;                         // was entry-only, already deleted
      if (info.module === WASI_MODULE) continue;   // deduplicated — main module declares these
      // Non-WASI external import: include with mangled name
      const newName = funcName.get(idx) ?? `$${prefix}__fn${idx}`;
      funcParts.push(form.replace(/\(func\s+\(;(\d+);\)/, `(func ${newName}`));
      continue;
    }

    // ── Strip exports — main module controls exports ────────────────────────
    if (kind === "export") continue;

    // ── Skip memory — main module owns memory ──────────────────────────────
    if (kind === "memory") continue;

    // ── Skip type declarations — main module manages its own type table ─────
    if (kind === "type") continue;

    // ── Functions ───────────────────────────────────────────────────────────
    if (kind === "func") {
      const idxM = form.match(/\(func\s+\(;(\d+);\)/);
      if (!idxM) continue;
      const idx = parseInt(idxM[1]);
      if (importMap.has(idx)) continue; // import stubs handled above

      const newName = funcName.get(idx) ?? `$${prefix}__fn${idx}`;
      let body = form.replace(/\(func\s+\(;(\d+);\)(?:\s+\(type\s+\d+\))?/, `(func ${newName}`);
      body = renameCallSites(body);
      body = renameGlobalRefs(body);
      body = relocateDataPtrs(body);
      funcParts.push(body);
      continue;
    }

    // ── Globals ─────────────────────────────────────────────────────────────
    if (kind === "global") {
      const idxM = form.match(/\(global\s+\(;(\d+);\)/);
      if (!idxM) continue;
      const idx = parseInt(idxM[1]);
      // Skip the heap-pointer global — the main module manages its own heap
      if (form.includes("(mut i32)")) continue;
      const newName = `$${prefix}_global${idx}`;
      let renamed = form.replace(/\(global\s+\(;(\d+);\)/, `(global ${newName}`);
      renamed = relocateDataPtrs(renamed);
      globalParts.push(renamed);
      continue;
    }

    // ── Data segments ────────────────────────────────────────────────────────
    if (kind === "data") {
      // Relocate the data segment's base address
      const relocated = form.replace(/\(i32\.const\s+(\d+)\)/, (_, numStr) => {
        return `(i32.const ${parseInt(numStr) + dataReloc})`;
      });
      dataParts.push(relocated);
      continue;
    }

    // Everything else (table, elem, tag, etc.) — skip for Phase 18
  }

  return {
    funcWat: funcParts.join("\n  "),
    globalWat: globalParts.join("\n  "),
    dataWat: dataParts.join("\n  "),
    wasiImportNames,
    exportedFuncs,
    notices,
    exportDecls,
    exportMap,
  };
}
