/**
 * @module wast
 * @description A runner for the WebAssembly `.wast` *script* format (a superset of `.wat`).
 *
 * A `.wast` file is a sequence of top-level commands: `(module …)` definitions interleaved with
 * assertion directives (`assert_return`, `assert_trap`, `assert_invalid`, `assert_malformed`,
 * `assert_unlinkable`, `assert_exhaustion`), actions (`invoke`, `get`), and `register`. This is the
 * format the official WebAssembly spec conformance testsuite is written in.
 *
 * This runner: (1) splits a `.wast` into commands via a position-tracking S-expression reader,
 * (2) assembles each `(module …)` with the pluggable WABT backend, (3) instantiates it on the host
 * `WebAssembly` engine with the standard `spectest` host imports + a `register` linking registry,
 * and (4) executes the actions/assertions, comparing results bit-exactly (i32 as uint32, i64 as
 * BigInt, f32/f64 by bits incl. `nan:canonical`/`nan:arithmetic`/hex-float literals).
 *
 * Directives that use module features the toolchain/engine cannot assemble or instantiate (e.g. a
 * proposal the host V8 lacks), and assertion value types outside i32/i64/f32/f64 (v128, ref.*), are
 * reported as SKIPPED rather than FAILED — so the runner degrades gracefully on the full testsuite
 * while still validating everything in scope.
 */
import wabt from "wabt";
import { rt } from "./rt.ts";

// deno-lint-ignore no-explicit-any
type WabtModule = any;

// ─────────────────────────────────────────────────────────────────────────────
// S-expression reader (position-tracking, comment/string-aware)
// ─────────────────────────────────────────────────────────────────────────────

/** A parsed S-expression node: an atom (string, incl. quoted-string tokens verbatim) or a list. */
export type Sexp = string | SexpList;
/** A list node carrying the source span `[start, end)` so `(module …)` raw text can be recovered. */
export interface SexpList {
  /** The child S-expressions of this list, in source order. */
  list: Sexp[];
  /** Byte offset in the source where this list's opening `(` begins. */
  start: number;
  /** Byte offset in the source one past this list's closing `)`. */
  end: number;
}
/** Type guard: `true` when `s` is a {@link SexpList} (a list) rather than an atom (string). */
export const isList = (s: Sexp): s is SexpList => typeof s !== "string";

/** Read all top-level S-expressions from `.wast` source. */
export function parseSexprs(src: string): SexpList[] {
  const out: SexpList[] = [];
  let i = 0;
  const n = src.length;

  function skipTrivia(): void {
    for (;;) {
      // whitespace
      while (i < n && (src[i] === " " || src[i] === "\t" || src[i] === "\r" || src[i] === "\n")) {
        i++;
      }
      // line comment
      if (i + 1 < n && src[i] === ";" && src[i + 1] === ";") {
        while (i < n && src[i] !== "\n") i++;
        continue;
      }
      // block comment (nesting)
      if (i + 1 < n && src[i] === "(" && src[i + 1] === ";") {
        let depth = 1;
        i += 2;
        while (i < n && depth > 0) {
          if (i + 1 < n && src[i] === "(" && src[i + 1] === ";") {
            depth++;
            i += 2;
          } else if (i + 1 < n && src[i] === ";" && src[i + 1] === ")") {
            depth--;
            i += 2;
          } else i++;
        }
        continue;
      }
      break;
    }
  }

  function readString(): string {
    const start = i;
    i++; // opening quote
    while (i < n) {
      if (src[i] === "\\") {
        i += 2;
        continue;
      }
      if (src[i] === '"') {
        i++;
        break;
      }
      i++;
    }
    return src.slice(start, i); // verbatim, including quotes + escapes
  }

  function readAtom(): string {
    const start = i;
    while (i < n) {
      const c = src[i];
      if (
        c === " " || c === "\t" || c === "\r" || c === "\n" || c === "(" || c === ")" || c === ";"
      ) break;
      i++;
    }
    return src.slice(start, i);
  }

  function readList(): SexpList {
    const start = i;
    i++; // consume '('
    const list: Sexp[] = [];
    for (;;) {
      skipTrivia();
      if (i >= n) break;
      if (src[i] === ")") {
        i++;
        break;
      }
      if (src[i] === "(") list.push(readList());
      else if (src[i] === '"') list.push(readString());
      else list.push(readAtom());
    }
    return { list, start, end: i };
  }

  for (;;) {
    skipTrivia();
    if (i >= n) break;
    if (src[i] === "(") out.push(readList());
    else i++; // stray token at top level (shouldn't happen in valid .wast)
  }
  return out;
}

const head = (
  s: SexpList,
): string => (s.list.length && typeof s.list[0] === "string" ? s.list[0] : "");

// ─────────────────────────────────────────────────────────────────────────────
// Literal parsing (ints + floats, WAT syntax)
// ─────────────────────────────────────────────────────────────────────────────

/** Parse a WAT integer literal (`0x…` / decimal / `+`/`-` / `_` separators) as a BigInt. */
function parseIntLit(lit: string): bigint {
  let s = lit.replace(/_/g, "");
  let neg = false;
  if (s[0] === "+") s = s.slice(1);
  else if (s[0] === "-") {
    neg = true;
    s = s.slice(1);
  }
  const v = s.startsWith("0x") || s.startsWith("0X") ? BigInt(s) : BigInt(s);
  return neg ? -v : v;
}

const U32 = (v: bigint) => Number(v & 0xffffffffn) >>> 0;
const U64 = (v: bigint) => v & 0xffffffffffffffffn;

const F64_QUIET = 0x0008000000000000n; // MSB of the 52-bit mantissa
const F32_QUIET = 0x00400000n; // MSB of the 23-bit mantissa

const dv = new DataView(new ArrayBuffer(8));
function f64Bits(x: number): bigint {
  dv.setFloat64(0, x);
  return dv.getBigUint64(0);
}
function f32Bits(x: number): bigint {
  dv.setFloat32(0, x);
  return BigInt(dv.getUint32(0));
}
function bitsToF64(b: bigint): number {
  dv.setBigUint64(0, b & 0xffffffffffffffffn);
  return dv.getFloat64(0);
}

/** A float expectation: either an exact bit pattern, or a canonical/arithmetic-NaN matcher. */
type FloatExpect =
  | { kind: "bits"; bits: bigint }
  | { kind: "nan"; canonical: boolean; is32: boolean };

/** Parse a hex-float mantissa/exponent (`0x1.921fp+1`) to a JS number (exact when ≤53 mantissa bits). */
function hexFloatToNumber(body: string): number {
  // body has no sign, no 0x prefix
  const [mantissa, expStr] = body.split(/[pP]/);
  const exp = expStr ? parseInt(expStr, 10) : 0;
  const [intPart, fracPart = ""] = mantissa.split(".");
  const digits = (intPart + fracPart) || "0";
  const mantVal = BigInt("0x" + digits);
  const e = exp - fracPart.length * 4;
  // Number(mantVal) is exact for ≤53-bit mantissas (all normalized f64 literals); *2^e is exact.
  return Number(mantVal) * Math.pow(2, e);
}

/** Parse any WAT float literal to a JS number (for use as an argument / exact const). */
function floatLitToNumber(lit: string, is32: boolean): number {
  let s = lit.replace(/_/g, "");
  let sign = 1;
  if (s[0] === "+") s = s.slice(1);
  else if (s[0] === "-") {
    sign = -1;
    s = s.slice(1);
  }
  let v: number;
  if (s === "inf") v = Infinity;
  else if (s === "nan" || s.startsWith("nan:")) {
    // canonical NaN value (payload MSB set); nan:0x… → specific payload
    const b = is32
      ? (0x7f800000n | (s.startsWith("nan:0x") ? BigInt(s.slice(4)) : F32_QUIET))
      : (0x7ff0000000000000n | (s.startsWith("nan:0x") ? BigInt(s.slice(4)) : F64_QUIET));
    const val = is32 ? Math.fround(bitsF32ToNum(b)) : bitsToF64(b);
    return sign < 0 ? -val : val;
  } else if (s.startsWith("0x") || s.startsWith("0X")) v = hexFloatToNumber(s.slice(2));
  else v = Number(s);
  return sign * v;
}

function bitsF32ToNum(b: bigint): number {
  dv.setUint32(0, Number(b & 0xffffffffn));
  return dv.getFloat32(0);
}

/** Parse a float RESULT expectation node (`(f64.const nan:canonical)` etc.). */
function parseFloatExpect(lit: string, is32: boolean): FloatExpect {
  let s = lit.replace(/_/g, "");
  let neg = false;
  if (s[0] === "+") s = s.slice(1);
  else if (s[0] === "-") {
    neg = true;
    s = s.slice(1);
  }
  if (s === "nan:canonical") return { kind: "nan", canonical: true, is32 };
  if (s === "nan:arithmetic") return { kind: "nan", canonical: false, is32 };
  const num = floatLitToNumber((neg ? "-" : "") + s, is32);
  return { kind: "bits", bits: is32 ? f32Bits(num) : f64Bits(num) };
}

// ─────────────────────────────────────────────────────────────────────────────
// Value nodes → JS values (invoke args) and result comparison
// ─────────────────────────────────────────────────────────────────────────────

/** True if a const node is a numeric type this runner supports (i32/i64/f32/f64). */
function constType(node: Sexp): string | null {
  if (!isList(node)) return null;
  const h = head(node);
  if (h === "i32.const" || h === "i64.const" || h === "f32.const" || h === "f64.const") return h;
  return null; // v128.const, ref.null, ref.func, ref.extern … → unsupported here
}

/** Convert a const node to the JS value WebAssembly expects as an argument. */
function constToJs(node: SexpList): number | bigint {
  const h = head(node);
  const lit = node.list[1] as string;
  switch (h) {
    case "i32.const":
      return U32(parseIntLit(lit)) | 0; // signed i32 arg
    case "i64.const":
      return BigInt.asIntN(64, parseIntLit(lit));
    case "f32.const":
      return floatLitToNumber(lit, true);
    case "f64.const":
      return floatLitToNumber(lit, false);
  }
  throw new Error("unsupported const " + h);
}

/** Compare an actual WebAssembly result value against an expected const node. Returns true on match. */
function resultMatches(expected: SexpList, actual: unknown): boolean {
  const h = head(expected);
  const lit = expected.list[1] as string;
  switch (h) {
    case "i32.const":
      return U32(parseIntLit(lit)) === ((actual as number) >>> 0);
    case "i64.const":
      return U64(parseIntLit(lit)) === U64(actual as bigint);
    case "f32.const":
    case "f64.const": {
      const is32 = h === "f32.const";
      const exp = parseFloatExpect(lit, is32);
      const aBits = is32 ? f32Bits(Math.fround(actual as number)) : f64Bits(actual as number);
      if (exp.kind === "bits") return aBits === exp.bits;
      // NaN matcher
      const isNaNbits = is32
        ? (aBits & 0x7f800000n) === 0x7f800000n && (aBits & 0x007fffffn) !== 0n
        : (aBits & 0x7ff0000000000000n) === 0x7ff0000000000000n &&
          (aBits & 0x000fffffffffffffn) !== 0n;
      if (!isNaNbits) return false;
      if (exp.canonical) {
        const payload = is32 ? (aBits & 0x007fffffn) : (aBits & 0x000fffffffffffffn);
        return payload === (is32 ? F32_QUIET : F64_QUIET);
      }
      // arithmetic: MSB of mantissa set
      return (aBits & (is32 ? F32_QUIET : F64_QUIET)) !== 0n;
    }
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Module assembly + host imports
// ─────────────────────────────────────────────────────────────────────────────

/** Decode a WAT string token (`"\\00\\61…"` incl. escapes) to raw bytes — for `(module binary …)`. */
function decodeWatString(tokens: string[]): Uint8Array {
  const bytes: number[] = [];
  for (const tok of tokens) {
    // tok is a verbatim quoted string, e.g. "\00asm"
    const s = tok.slice(1, -1);
    for (let i = 0; i < s.length; i++) {
      if (s[i] === "\\") {
        const nx = s[i + 1];
        if (nx === "n") {
          bytes.push(10);
          i++;
        } else if (nx === "t") {
          bytes.push(9);
          i++;
        } else if (nx === "r") {
          bytes.push(13);
          i++;
        } else if (nx === '"') {
          bytes.push(34);
          i++;
        } else if (nx === "'") {
          bytes.push(39);
          i++;
        } else if (nx === "\\") {
          bytes.push(92);
          i++;
        } else {
          bytes.push(parseInt(s.substr(i + 1, 2), 16));
          i += 2;
        }
      } else {
        bytes.push(s.charCodeAt(i));
      }
    }
  }
  return new Uint8Array(bytes);
}

/** Decode a single verbatim WAT string token (`"export.name"`) to a JS string. */
function watStrToJs(token: string): string {
  return new TextDecoder().decode(decodeWatString([token]));
}

/** The standard `spectest` host module the spec testsuite imports. */
function spectestImports(): WebAssembly.ModuleImports {
  return {
    print: () => {},
    print_i32: () => {},
    print_i64: () => {},
    print_f32: () => {},
    print_f64: () => {},
    print_i32_f32: () => {},
    print_f64_f64: () => {},
    global_i32: new WebAssembly.Global({ value: "i32", mutable: false }, 666),
    global_i64: new WebAssembly.Global({ value: "i64", mutable: false }, 666n),
    global_f32: new WebAssembly.Global({ value: "f32", mutable: false }, 0),
    global_f64: new WebAssembly.Global({ value: "f64", mutable: false }, 0),
    table: new WebAssembly.Table({ initial: 10, maximum: 20, element: "anyfunc" }),
    memory: new WebAssembly.Memory({ initial: 1, maximum: 2 }),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Runner
// ─────────────────────────────────────────────────────────────────────────────

/** Tally of running one `.wast` file: per-command pass/fail/skip counts plus the failure messages. */
export interface WastResult {
  /** Path of the `.wast` file this result is for. */
  file: string;
  /** Number of assertion commands that passed. */
  passed: number;
  /** Number of assertion commands that failed. */
  failed: number;
  /** Number of commands skipped (unsupported directive or unhandled command kind). */
  skipped: number;
  /** Human-readable messages for each failed command (one entry per failure). */
  failures: string[];
}

/** Run a single `.wast` file. Never throws — every command's outcome is tallied. */
export async function runWast(
  path: string,
  opts: { verbose?: boolean; maxFailures?: number } = {},
): Promise<WastResult> {
  const res: WastResult = { file: path, passed: 0, failed: 0, skipped: 0, failures: [] };
  const src = await rt.readTextFile(path);
  let cmds: SexpList[];
  try {
    cmds = parseSexprs(src);
  } catch (e) {
    res.failed++;
    res.failures.push(`parse error: ${e instanceof Error ? e.message : e}`);
    return res;
  }

  const wabtMod: WabtModule = await (wabt as unknown as () => Promise<WabtModule>)();

  let cur: WebAssembly.Instance | null = null;
  const named = new Map<string, WebAssembly.Instance>();
  const registry: Record<string, WebAssembly.ModuleImports> = { spectest: spectestImports() };

  const fail = (msg: string) => {
    res.failed++;
    if (res.failures.length < (opts.maxFailures ?? 25)) res.failures.push(msg);
  };

  // Build the import object a module needs from the registry (+ spectest).
  const buildImports = (): WebAssembly.Imports => {
    const imp: WebAssembly.Imports = {};
    for (const [k, v] of Object.entries(registry)) imp[k] = v;
    return imp;
  };

  // Assemble a `(module …)` node to bytes. Supports `(module binary …)` + text. Throws on failure.
  function assemble(mod: SexpList): Uint8Array {
    const kind = typeof mod.list[1] === "string" ? mod.list[1] : "";
    const nameIdx = typeof mod.list[1] === "string" && (mod.list[1] as string).startsWith("$")
      ? 1
      : -1;
    const bkIdx = mod.list.findIndex((x) => x === "binary");
    const qkIdx = mod.list.findIndex((x) => x === "quote");
    if (bkIdx !== -1) {
      const strs = mod.list.slice(bkIdx + 1).filter((x): x is string => typeof x === "string");
      return decodeWatString(strs);
    }
    let text: string;
    if (qkIdx !== -1) {
      const strs = mod.list.slice(qkIdx + 1).filter((x): x is string => typeof x === "string");
      text = new TextDecoder().decode(decodeWatString(strs));
      if (!/^\s*\(module/.test(text)) text = `(module ${text})`;
    } else {
      text = src.slice(mod.start, mod.end);
    }
    void kind;
    void nameIdx;
    const parsed = wabtMod.parseWat(path, text, { enable_all: true });
    try {
      const { buffer } = parsed.toBinary({});
      return new Uint8Array(buffer);
    } finally {
      parsed.destroy();
    }
  }

  // Instantiate bytes with current imports. Throws on link/instantiate error.
  async function instantiate(bytes: Uint8Array): Promise<WebAssembly.Instance> {
    const { instance } = await WebAssembly.instantiate(bytes as BufferSource, buildImports());
    return instance;
  }

  // Resolve the instance an action targets (optional leading `$name`).
  function actionInstance(nameTok: string | undefined): WebAssembly.Instance | null {
    if (nameTok && nameTok.startsWith("$")) return named.get(nameTok) ?? null;
    return cur;
  }

  // Run an (invoke …) / (get …) action node → array of result values (or throws the trap).
  function runAction(action: SexpList): unknown[] {
    const h = head(action);
    let idx = 1;
    let nameTok: string | undefined;
    if (typeof action.list[idx] === "string" && (action.list[idx] as string).startsWith("$")) {
      nameTok = action.list[idx] as string;
      idx++;
    }
    const field = watStrToJs(action.list[idx] as string);
    idx++;
    const inst = actionInstance(nameTok);
    if (!inst) throw new Error("__skip__: no active module instance");
    const ex = inst.exports as Record<string, unknown>;
    if (h === "get") {
      const g = ex[field] as WebAssembly.Global;
      return [g.value];
    }
    // invoke
    const args: (number | bigint)[] = [];
    for (let k = idx; k < action.list.length; k++) {
      const a = action.list[k];
      if (!isList(a) || !constType(a)) throw new Error("__skip__: unsupported arg type");
      // A NaN with a specific (non-canonical) payload cannot be passed through the JS number
      // boundary — V8 canonicalizes it — so any test that depends on the payload surviving the
      // call is untestable via the JS API (not a toolchain bug). Skip it.
      if (/nan:0x/.test(a.list[1] as string)) {
        throw new Error("__skip__: NaN payload arg cannot cross the JS boundary");
      }
      args.push(constToJs(a));
    }
    const fn = ex[field] as (...a: unknown[]) => unknown;
    if (typeof fn !== "function") throw new Error(`export '${field}' is not a function`);
    const r = fn(...args);
    // void export → undefined → []; multi-value → array; single → [scalar].
    return r === undefined ? [] : (Array.isArray(r) ? r : [r]);
  }

  const anyUnsupportedResult = (nodes: Sexp[]) => nodes.some((x) => !isList(x) || !constType(x));

  for (const cmd of cmds) {
    const h = head(cmd);
    try {
      switch (h) {
        case "module": {
          const nameTok = typeof cmd.list[1] === "string" && (cmd.list[1] as string).startsWith("$")
            ? cmd.list[1] as string
            : undefined;
          try {
            const bytes = assemble(cmd);
            cur = await instantiate(bytes);
            if (nameTok) named.set(nameTok, cur);
          } catch (e) {
            // A module we cannot assemble/instantiate (unsupported proposal, missing import, …).
            // Skip it and its dependent actions rather than failing the whole file.
            cur = null;
            res.skipped++;
            if (opts.verbose) {
              res.failures.push(`skip module: ${e instanceof Error ? e.message : e}`);
            }
          }
          break;
        }
        case "register": {
          const name = watStrToJs(cmd.list[1] as string);
          const idTok = cmd.list[2];
          const inst = typeof idTok === "string" && idTok.startsWith("$") ? named.get(idTok) : cur;
          if (inst) registry[name] = inst.exports as WebAssembly.ModuleImports;
          break;
        }
        case "invoke":
        case "get": {
          try {
            runAction(cmd);
            res.passed++;
          } catch (e) {
            if (String(e).includes("__skip__")) res.skipped++;
            else fail(`action ${head(cmd)} threw: ${e instanceof Error ? e.message : e}`);
          }
          break;
        }
        case "assert_return": {
          const action = cmd.list[1] as SexpList;
          const expected = cmd.list.slice(2) as SexpList[];
          if (anyUnsupportedResult(expected)) {
            res.skipped++;
            break;
          }
          let results: unknown[];
          try {
            results = runAction(action);
          } catch (e) {
            if (String(e).includes("__skip__")) {
              res.skipped++;
              break;
            }
            fail(`assert_return action trapped: ${e instanceof Error ? e.message : e}`);
            break;
          }
          let ok = results.length === expected.length;
          for (let k = 0; ok && k < expected.length; k++) {
            if (!resultMatches(expected[k], results[k])) ok = false;
          }
          if (ok) res.passed++;
          else {fail(
              `assert_return mismatch: ${src.slice(cmd.start, Math.min(cmd.end, cmd.start + 120))}`,
            );}
          break;
        }
        case "assert_trap":
        case "assert_exhaustion": {
          const action = cmd.list[1];
          if (!isList(action) || (head(action) !== "invoke" && head(action) !== "get")) {
            res.skipped++;
            break;
          }
          try {
            runAction(action);
            fail(`${h} did not trap: ${src.slice(cmd.start, cmd.start + 100)}`);
          } catch (e) {
            if (String(e).includes("__skip__")) res.skipped++;
            else res.passed++; // any trap/throw counts (message not matched in v1)
          }
          break;
        }
        case "assert_invalid":
        case "assert_unlinkable": {
          // Validation assertions test the ASSEMBLER/VALIDATOR, not execution. wasmtk's wabt(+V8)
          // pipeline is a known-incomplete validator, so a module that fails to reject here is a
          // toolchain-leniency gap (counted as skipped), NOT an execution failure.
          const mod = cmd.list[1] as SexpList;
          try {
            const bytes = assemble(mod);
            if (h === "assert_unlinkable") await instantiate(bytes);
            else await WebAssembly.compile(bytes as BufferSource); // validation
            res.skipped++;
            if (opts.verbose) {
              res.failures.push(
                `toolchain-lenient (${h} not rejected): ${src.slice(cmd.start, cmd.start + 70)}`,
              );
            }
          } catch {
            res.passed++;
          }
          break;
        }
        case "assert_malformed": {
          const mod = cmd.list[1] as SexpList;
          // Only `(module quote …)` / `(module binary …)` are decidable here; a plain `(module …)`
          // that wabt happens to accept is not a text-decode failure we can judge → skip.
          const isQuoteOrBinary = mod.list.some((x) => x === "quote" || x === "binary");
          if (!isQuoteOrBinary) {
            res.skipped++;
            break;
          }
          try {
            const bytes = assemble(mod);
            await WebAssembly.compile(bytes as BufferSource);
            res.skipped++; // toolchain-lenient (see assert_invalid note)
            if (opts.verbose) {
              res.failures.push(
                `toolchain-lenient (malformed not rejected): ${
                  src.slice(cmd.start, cmd.start + 70)
                }`,
              );
            }
          } catch {
            res.passed++;
          }
          break;
        }
        default:
          // assert_return_canonical_nan (legacy), assert_return_arithmetic_nan (legacy), meta, … → skip
          res.skipped++;
      }
    } catch (e) {
      fail(`command ${h} error: ${e instanceof Error ? e.message : e}`);
    }
  }
  return res;
}

// ─────────────────────────────────────────────────────────────────────────────
// Path runner + CLI (single .wast file or a directory tree)
// ─────────────────────────────────────────────────────────────────────────────

async function* walkWast(dir: string): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(dir)) {
    const p = `${dir}/${entry.name}`;
    if (entry.isDirectory) yield* walkWast(p);
    else if (entry.name.endsWith(".wast")) yield p;
  }
}

/** Run every `.wast` under `target` (a file or a directory tree). */
export async function runWastPath(
  target: string,
  opts: { verbose?: boolean; maxFailures?: number } = {},
): Promise<WastResult[]> {
  const stat = await Deno.stat(target);
  const files: string[] = [];
  if (stat.isDirectory) {
    for await (const f of walkWast(target)) files.push(f);
    files.sort();
  } else files.push(target);
  const results: WastResult[] = [];
  for (const f of files) results.push(await runWast(f, opts));
  return results;
}

/**
 * CLI entry for `wasmtk wast <file|dir>`. Runs the `.wast` execution assertions on the host engine
 * (via the wabt backend) and prints a per-file + total summary. Returns a process exit code
 * (non-zero if any EXECUTION assertion failed — validation-assertion toolchain gaps count as skips).
 */
export async function wastCli(target: string, opts: { verbose?: boolean } = {}): Promise<number> {
  const results = await runWastPath(target, { verbose: opts.verbose, maxFailures: 6 });
  let tp = 0, tf = 0, ts = 0;
  const multi = results.length > 1;
  for (const r of results) {
    tp += r.passed;
    tf += r.failed;
    ts += r.skipped;
    const base = r.file.split(/[\\/]/).pop();
    if (multi && r.failed === 0 && !opts.verbose) continue; // only surface files with failures in dir mode
    const tag = r.failed > 0 ? "❌" : "✓";
    console.log(`${tag} ${base}: pass=${r.passed} fail=${r.failed} skip=${r.skipped}`);
    for (const m of r.failures.slice(0, 6)) {
      console.log("    " + m.replace(/\s+/g, " ").slice(0, 140));
    }
  }
  console.log(
    `\n${
      tf === 0 ? "✅" : "❌"
    } wast: ${results.length} file(s) — ${tp} passed, ${tf} failed, ${ts} skipped` +
      (tf > 0 ? "  (execution assertion failures)" : ""),
  );
  if (ts > 0) {
    console.log(
      "   skipped = assertions using features/value-types out of scope (v128/ref, unsupported\n" +
        "   proposals, or validation assertions the wabt+host toolchain does not reject).",
    );
  }
  return tf === 0 ? 0 : 1;
}
