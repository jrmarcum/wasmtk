/**
 * engine.ts — say in plain words when the JavaScript engine, not the module, is the reason a
 * WebAssembly module was refused.
 *
 * wasmtk runs modules on the engine inside Deno, which is V8. V8 does not implement every
 * WebAssembly proposal, implements some only behind experimental flags, and caps some sizes below
 * what the spec allows. Its own messages for those cases are terse (`invalid memory limits flags
 * 0x8`), so `wasmtk run` and `wasmtk wast` translate them: which feature, that it is the engine's
 * limitation, and which engine and version.
 *
 * Recognition is by V8's message text; an unrecognised refusal yields `null` and the caller shows
 * V8's own message unchanged. Pure apart from reading the runtime's version.
 *
 * @module
 */

/** A refusal traced to the engine, not to the module. */
export interface EngineLimit {
  /** Short feature label, stable across assertions: e.g. `custom page sizes`. */
  feature: string;
  /** One sentence for the user: what the engine does not do, naming the engine and version. */
  statement: string;
}

/**
 * The engine running wasmtk, e.g. `V8 15.0.245.2 (the engine in Deno 2.9.7)`. Falls back to a
 * generic phrase outside Deno, where the version is unknown.
 */
export function engineName(): string {
  // deno-lint-ignore no-explicit-any
  const d = (globalThis as any).Deno;
  const v8 = d?.version?.v8 as string | undefined;
  if (!v8) return "this JavaScript engine";
  return `V8 ${v8.replace(/-rusty$/, "")} (the engine in Deno ${d.version.deno})`;
}

/**
 * If `e` is the engine refusing a module for a feature or limit of its own, say so; else `null`.
 *
 * Recognised (V8's wording, measured on V8 15.0.245):
 *  - `invalid memory limits flags 0x8` (bit 0x08 set): the custom-page-sizes proposal, which V8
 *    does not implement at all.
 *  - `(initial|maximum) memory size (N pages) is larger than implementation limit (M pages)`: a
 *    size the spec allows (memory64 reaches 2^48 pages) above V8's own cap. NOT when M is 65536,
 *    a 32-bit memory's spec maximum: then the module is invalid and V8 is right to say so.
 *  - `… --experimental-wasm-<name>`: a proposal V8 implements only behind that flag.
 */
export function explainEngineRejection(e: unknown): EngineLimit | null {
  const msg = e instanceof Error ? e.message : String(e);
  const engine = engineName();

  const flags = /invalid memory limits flags 0x([0-9a-f]+)/i.exec(msg);
  if (flags && (parseInt(flags[1], 16) & 0x08) !== 0) {
    return {
      feature: "custom page sizes",
      statement: `${engine} does not implement the custom-page-sizes proposal (a memory declared ` +
        `with \`(pagesize N)\`), so it refuses every module that uses one, valid or not. A ` +
        `runtime that implements it, such as wasmtime with \`-W custom-page-sizes=y\`, can load it.`,
    };
  }

  const size =
    /(initial|maximum) (memory|table) size \((\d+) (pages|elements)\) is larger than implementation limit \((\d+) \4\)/
      .exec(msg);
  if (size) {
    const [, which, kind, n, unit, cap] = size;
    // V8 reports a 32-bit memory's cap as 65536 pages: that is the SPEC's own maximum (4 GiB), so
    // the module is genuinely invalid and the engine is not the reason. Only a cap BELOW what the
    // spec allows (memory64's 262144 pages vs 2^48; tables' 10000000 elements) is the engine's.
    if (kind === "memory" && cap === "65536") return null;
    const bytes = kind === "memory" ? ` (${formatBytes(BigInt(cap) * 65536n)})` : "";
    return {
      feature: `${kind} size above the engine's limit`,
      statement:
        `${engine} caps a declared ${kind} at ${cap} ${unit}${bytes}; this module declares ` +
        `a ${which} of ${n} ${unit}. The spec allows it, but this engine refuses to load it.`,
    };
  }

  const flag = /--experimental-wasm-([a-z0-9-]+)/.exec(msg);
  if (flag) {
    const name = flag[1].replace(/-/g, " ");
    return {
      feature: name,
      statement: `${engine} implements ${name} only behind the experimental flag ` +
        `\`--experimental-wasm-${flag[1]}\`, which wasmtk does not turn on; this engine refuses ` +
        `the module as it stands.`,
    };
  }
  return null;
}

function formatBytes(n: bigint): string {
  const GiB = 1n << 30n;
  if (n % GiB === 0n) return `${n / GiB} GiB`;
  const MiB = 1n << 20n;
  return n % MiB === 0n ? `${n / MiB} MiB` : `${n} bytes`;
}
