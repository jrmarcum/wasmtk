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
 *  5. **Unifies the allocator**: detects the imported library's wasic-emitted
 *     `$__malloc` and `$__heap_ptr` global, drops both from the merge output, and
 *     redirects every call / global.get / global.set in the imported body to the
 *     main module's allocator. Without this, two merged libraries each keep a
 *     private heap pointer initialised to the page-2 boundary (131072) and hand
 *     out overlapping addresses as soon as both allocate. With it, all merged
 *     modules share one bump cursor over one linear memory — values built by
 *     one library are readable / writable by another, by code in the main
 *     module, and across capability boundaries.
 *  6. Relocates data segment base addresses by a caller-supplied delta so that the
 *     imported module's static data is placed above the main module's data section.
 *  7. Conservatively relocates data-pointer i32.const values in function bodies:
 *     any i32.const >= DATA_PTR_THRESHOLD (260) is assumed to be a static-data
 *     pointer and is shifted by the same delta.  Small integer literals are left
 *     untouched.
 *  8. Returns the ExternalFuncDef list so WasicTranspiler can register imported
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
  /** True if the imported module contained at least one (mut i32) global (e.g. a bump
   * allocator free pointer). The caller must ensure the main module has enough memory
   * pages to accommodate the relocated global's initial address. */
  hasMutableGlobals: boolean;
  /** True if the merge dropped a bump-allocator pair ($__malloc + $__heap_ptr) from
   * the imported module. Call / global.get / global.set sites in `funcWat` were
   * redirected to the unmangled names `$__malloc` and `$__heap_ptr`; the master
   * module (caller) must therefore provide these definitions. wasic / modc output
   * already emits both; `wasmbundle` builds its master WAT from scratch and must
   * synthesise them when this flag is true for any merged module. */
  droppedAllocator: boolean;
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
// Allocator detection
// ---------------------------------------------------------------------------

/**
 * Detect whether a (func ...) form is the wasic-emitted bump allocator $__malloc.
 *
 * Pattern-matching the body byte-for-byte is brittle because Binaryen `-Oz`
 * reshapes the allocator across versions (extra locals, `local.tee` vs
 * `local.set`+`local.get`, dead-write artefacts, etc.). We instead detect by
 * structural property: a `(param i32) (result i32)` function whose body
 * touches exactly one mutable i32 global — once via `global.get`, once via
 * `global.set` — and adds the param to it. Every observed compiled shape of
 * wasic's `$__malloc` satisfies this; nothing else in the wasic / modc output
 * does (string helpers and array helpers either touch zero globals or touch
 * multiple, and `$cabi_realloc` doesn't touch the heap ptr at all).
 *
 * Returns the global index used as the heap pointer if matched, else null.
 */
function detectBumpAllocator(funcForm: string): { heapPtrGlobalIdx: number } | null {
  // Signature gate: exactly one i32 param, one i32 result, no other params/results.
  // Allow zero-or-more (local ...) declarations after the result.
  const sigRe = /\(func\s+\(;\d+;\)(?:\s+\(type\s+\d+\))?\s+\(param\s+i32\)\s+\(result\s+i32\)/;
  if (!sigRe.test(funcForm)) return null;
  // Reject if there's any second `(param ...)` or `(result ...)` — multi-arg
  // functions can't be the allocator.
  if (/\(param[^)]*\)\s*\(param/.test(funcForm)) return null;
  if (/\(result[^)]*\)\s*\(result/.test(funcForm)) return null;
  // Reject if the function declares an f64/f32/i64 local.
  if (/\(local\s+(f32|f64|i64)\b/.test(funcForm)) return null;

  // Find every (distinct) global index referenced by get/set in the body.
  const getRefs = new Set<number>();
  const setRefs = new Set<number>();
  for (const m of funcForm.matchAll(/\bglobal\.get\s+(\d+)\b/g)) getRefs.add(parseInt(m[1]));
  for (const m of funcForm.matchAll(/\bglobal\.set\s+(\d+)\b/g)) setRefs.add(parseInt(m[1]));

  // Must touch exactly one global, both get and set, with the same index.
  if (getRefs.size !== 1 || setRefs.size !== 1) return null;
  const [getIdx] = getRefs;
  const [setIdx] = setRefs;
  if (getIdx !== setIdx) return null;

  // Body must use the param (local 0) at least once and contain i32.add —
  // these together prove the bump-cursor arithmetic pattern.
  if (!/\blocal\.get\s+0\b/.test(funcForm)) return null;
  if (!/\bi32\.add\b/.test(funcForm)) return null;

  // No call or call_indirect — a real allocator doesn't recurse / delegate.
  if (/\bcall(?:_indirect)?\b/.test(funcForm)) return null;

  // No memory ops — $__malloc never touches linear memory directly.
  if (/\bi32\.(load|store)|\bi64\.(load|store)|\bf32\.(load|store)|\bf64\.(load|store)\b/.test(funcForm)) return null;

  return { heapPtrGlobalIdx: getIdx };
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
  // funcIdx → inline signature, for disassemblies that emit `(func (;N;) (param ...)
  // (result ...))` WITHOUT a `(type T)` reference (wabt-ts 1.3.0 emits this form).
  // Used as a fallback when funcTypeIndexMap has no entry for the function.
  const funcInlineSig = new Map<number, { params: WasmWatType[]; result: WasmWatType | null }>();
  // Allocator unification (Phase 18.5): when the imported library carries
  // wasic's bump allocator + heap-ptr global, drop them and redirect call /
  // global.get sites to the main module's $__malloc and $__heap_ptr.
  // This is what turns wasmbundle from a packager into a real linker — without
  // this, two merged libraries each keep a private heap pointer initialised
  // to the page-2 boundary and hand out overlapping addresses.
  let droppedMallocIdx: number | null = null;
  let droppedHeapPtrGlobalIdx: number | null = null;

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
      } else if (idxM) {
        // Inline-signature form (no `(type T)` reference). Parse params + result
        // from the func header — its first line — so signatures still resolve.
        // Only the header carries `(param ...)` / a leading `(result ...)`; body
        // block signatures live on later lines, so restricting to line 0 is safe.
        const headerLine = form.split("\n")[0];
        const params: WasmWatType[] = [];
        for (const pm of (headerLine.match(/\(param([^)]*)\)/g) ?? [])) {
          for (const t of pm.replace("(param", "").replace(")", "").trim().split(/\s+/)) {
            if (t === "i32" || t === "i64" || t === "f32" || t === "f64") params.push(t as WasmWatType);
          }
        }
        const resM = headerLine.match(/\(result\s+(i32|i64|f32|f64)\)/);
        funcInlineSig.set(parseInt(idxM[1]), { params, result: resM ? (resM[1] as WasmWatType) : null });
      }
      // Bump-allocator detection. Each wasic-emitted library carries the same
      // tiny $__malloc body; we keep only the main module's copy and route
      // every imported call site through it.
      if (idxM && droppedMallocIdx === null) {
        const alloc = detectBumpAllocator(form);
        if (alloc) {
          droppedMallocIdx = parseInt(idxM[1]);
          droppedHeapPtrGlobalIdx = alloc.heapPtrGlobalIdx;
        }
      }
    }
  }

  // ── Identify & strip entry-only items ────────────────────────────────────
  // In wasmbundle mode (exportOverrides provided) we preserve _start and
  // proc_exit so the bundle remains a runnable WASI executable. In Phase-18
  // library-merge mode (no exportOverrides) we strip them as before.
  const skipEntryStrip = exportOverrides !== undefined;

  const strippedNames: string[] = [];

  // Strip entry-only from export map
  if (!skipEntryStrip) {
    for (const [idx, name] of exportFuncMap) {
      if (ENTRY_ONLY_NAMES.has(name)) {
        strippedNames.push(name);
        exportFuncMap.delete(idx);
      }
    }
  }
  // Find import indices for entry-only WASI functions
  const entryOnlyImportIdxs = new Set<number>();
  if (!skipEntryStrip) {
    for (const [idx, info] of importMap) {
      if (ENTRY_ONLY_NAMES.has(info.name)) {
        strippedNames.push(`${info.name} (import)`);
        entryOnlyImportIdxs.add(idx);
      }
    }
    for (const idx of entryOnlyImportIdxs) importMap.delete(idx);
  }

  if (strippedNames.length > 0) {
    const unique = [...new Set(strippedNames.map(n => n.replace(" (import)", "")))];
    notices.push(`entry-only features excluded: ${unique.join(", ")}. Module converted to library mode.`);
  }

  if (droppedMallocIdx !== null) {
    notices.push(`allocator unified: dropped $__malloc + heap-ptr global; call sites redirected to main module's $__malloc / $__heap_ptr.`);
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

  // Allocator unification: route every imported call site to the dropped
  // $__malloc through the main module's $__malloc. This is *before* Pass 2
  // emits the func bodies, so the renameCallSites() call below picks it up.
  if (droppedMallocIdx !== null) {
    funcName.set(droppedMallocIdx, "$__malloc");
  }

  // ── Build ExternalFuncDef list ────────────────────────────────────────────

  const exportedFuncs: ExternalFuncDef[] = [];
  for (const [idx, exportName] of exportFuncMap) {
    if (importMap.has(idx)) continue; // skip WASI re-exports
    const typeIdx = funcTypeIndexMap.get(idx);
    const sig = typeIdx !== undefined ? typeTable.get(typeIdx) : funcInlineSig.get(idx);
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

  /** Replace `global.get N` / `global.set N` numeric refs with named $refs.
   *  When N is the imported library's heap-ptr global (identified during Pass 1
   *  alongside the bump allocator), redirect to the main module's $__heap_ptr
   *  so allocations from this library share the unified heap cursor. */
  function renameGlobalRefs(text: string): string {
    const renameOne = (kind: "get" | "set", numStr: string): string => {
      const n = parseInt(numStr);
      if (droppedHeapPtrGlobalIdx !== null && n === droppedHeapPtrGlobalIdx) {
        return `global.${kind} $__heap_ptr`;
      }
      return `global.${kind} $${prefix}_global${n}`;
    };
    return text
      .replace(/\bglobal\.get\s+(\d+)\b/g, (_m, n) => renameOne("get", n))
      .replace(/\bglobal\.set\s+(\d+)\b/g, (_m, n) => renameOne("set", n));
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
  let hasMutableGlobals = false;

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
      // Use a function callback to avoid JavaScript's $1/$2 backreference substitution
      // in the replacement string — critical when newName starts with $1x (e.g. $18_prefix_...).
      funcParts.push(form.replace(/\(func\s+\(;(\d+);\)/, () => `(func ${newName}`));
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

      // Drop the imported library's $__malloc — its call sites were already
      // redirected via funcName above and the body itself is identical to the
      // main module's copy.
      if (droppedMallocIdx !== null && idx === droppedMallocIdx) continue;

      const newName = funcName.get(idx) ?? `$${prefix}__fn${idx}`;
      // Use a function callback to prevent $1 backreference substitution in newName.
      let body = form.replace(/\(func\s+\(;(\d+);\)(?:\s+\(type\s+\d+\))?/, () => `(func ${newName}`);
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

      // Drop the imported library's heap-ptr global — all get/set sites in the
      // merged function bodies are redirected to the main module's $__heap_ptr
      // by renameGlobalRefs (above).
      if (droppedHeapPtrGlobalIdx !== null && idx === droppedHeapPtrGlobalIdx) continue;

      const newName = `$${prefix}_global${idx}`;
      // Use a function callback to prevent $1 backreference substitution in newName.
      let renamed = form.replace(/\(global\s+\(;(\d+);\)/, () => `(global ${newName}`);
      if (form.includes("(mut i32)")) {
        // Other mutable i32 globals (non-heap-ptr — e.g. an imported library's
        // own counter state): place at page-2 boundary (131072) to keep them
        // out of the main module's static data + unified heap region.
        renamed = renamed.replace(/\(i32\.const\s+\d+\)/, `(i32.const ${2 * 65536})`);
        hasMutableGlobals = true;
      } else {
        renamed = relocateDataPtrs(renamed);
      }
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
    hasMutableGlobals,
    droppedAllocator: droppedMallocIdx !== null,
  };
}
