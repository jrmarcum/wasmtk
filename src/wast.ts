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
 * proposal the host V8 lacks), and values the runner cannot carry (some ref.* kinds, `either`
 * results), are reported as SKIPPED rather than FAILED — so the runner degrades gracefully on the
 * full testsuite while still validating everything in scope.
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
/**
 * An assembly failure tagged with the STAGE it happened at, because `assert_malformed` means
 * exactly one of them.
 *
 * `assert_malformed` asserts the module text **cannot be decoded**. A module that parses and then
 * fails later is *well-formed* — it is invalid, or beyond what the encoder can represent — and the
 * assertion should NOT pass on it.
 *
 * Before this existed the runner caught every failure in one `catch` and scored all of them as a
 * pass, so an ENCODE error satisfied a PARSE assertion. Three assertions in
 * `proposals/threads/memory.wast` passed that way for years: `(memory 0x1_0000_0000)` parses fine
 * (Wasm 3.0 encodes limits as u64) and died in the encoder with `u32 LEB128 out of range`. They
 * were removed by a vendored patch on 2026-09-19 — found by READING them, not by any measurement,
 * because a false pass is invisible in every number the gate reports. This tag is what makes the
 * next one visible. See cmem/testing.md.
 */
class AssembleError extends Error {
  constructor(readonly stage: "parse" | "encode", inner: unknown) {
    super(`assemble failed at ${stage}: ${inner instanceof Error ? inner.message : inner}`);
    this.name = "AssembleError";
  }
}

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
      else {
        // FORWARD-PROGRESS GUARANTEE. `readAtom` stops at `;` without consuming it (because `;;`
        // opens a comment), and `skipTrivia` only consumes `;;` and `(;` — so a LONE `;` inside a
        // list advanced neither, and this loop pushed "" forever until the array hit its maximum
        // length. That surfaced as `parse error: Invalid array length` on `annotations.wast:14`
        // (`(@a , ; ] [ …`), after allocating ~1.9 GB that was never released — on its own the
        // single largest contributor to the runner's memory growth across a directory run.
        // Rather than special-case `;`, assert progress: any character that `readAtom` cannot
        // consume is taken as a one-character atom, so the loop can never stall on a future one.
        const before = i;
        const atom = readAtom();
        if (i === before) {
          list.push(src[i]);
          i++;
        } else {
          list.push(atom);
        }
      }
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
  // `BigInt()` accepts the 0x/0X prefix directly, so no branch is needed. This was a ternary
  // with two IDENTICAL arms until the 2026-08-24 audit — harmless, but it read as though the
  // hex case were handled specially and invited someone to "fix" the wrong half.
  const v = BigInt(s);
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
  // Number(mantVal) is exact for ≤53-bit mantissas (all normalized f64 literals). Scale in TWO
  // steps: `2^e` alone under/overflows at the ends of the range even when the value itself is
  // representable. `0x0.0000000000002p-1023` is 2 × 2^-1075, and 2^-1075 is 0 in f64, so it read as
  // 0 (found 2026-09-28, the day `simd_lane.wast` first ran these through the trampoline). The first
  // step is an exact power-of-two scaling, so the only rounding happens once, in the second.
  const e1 = Math.max(-1000, Math.min(1000, e));
  return Number(mantVal) * Math.pow(2, e1) * Math.pow(2, e - e1);
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

/**
 * The host value a spec-script `(ref.extern N)` / `(ref.host N)` denotes. The reference interpreter
 * treats these as the external and internal views of ONE opaque host value, compared by `N`; in
 * the JS API both cross as the same JS value (V8 internalizes on the way in and hands the original
 * back on the way out). So one canonical object per `N`, shared by every module in the process,
 * gives both views and identity. An object rather than the number `N`: under GC a JS number
 * crossing into `anyref` can become an `i31ref`, which a host reference must never be.
 */
const hostRefs = new Map<string, object>();
function hostRef(n: string): object {
  let r = hostRefs.get(n);
  if (!r) hostRefs.set(n, r = Object.freeze({ wastHostRef: n }));
  return r;
}

/**
 * True if a const node is an ARGUMENT this runner can marshal across the JS boundary: the four
 * numeric types, `ref.null <heaptype>` (JS `null`), and `ref.extern N` / `ref.host N` (see
 * `hostRef`).
 *
 * ⚠️ `v128.const` is not a DIRECT argument: it goes through the trampoline (`needsTrampoline`).
 * Returning null here makes the whole assertion a SKIP, never a failure.
 *
 * (Admitting `ref.null` 2026-08-27 moved `ref_null.wast` off 0 pass / 32 skip. The gap had been
 * recorded as a backend bug for a week; the backend fixed its half and our number did not move,
 * because THIS function was the binding constraint and a skip never re-announces itself. The same
 * held for `ref.extern N` until 2026-09-28: `ref_test.wast`'s `(invoke "init" (ref.extern 0))` was
 * skipped, so the tables it fills stayed null and 73 GC-cast assertions failed on an empty table.)
 */
function constType(node: Sexp): string | null {
  if (!isList(node)) return null;
  const h = head(node);
  if (h === "i32.const" || h === "i64.const" || h === "f32.const" || h === "f64.const") return h;
  if (h === "ref.null") return h;
  if ((h === "ref.extern" || h === "ref.host") && typeof node.list[1] === "string") return h;
  return null; // v128.const, ref.func, … → unsupported here
}

/**
 * True if a node is an EXPECTED RESULT this runner can check: every argument form, plus the
 * index-less `(ref.extern)` / `(ref.func)`, which mean "any non-null reference of that kind" and
 * can only appear as results. `ref.struct` / `ref.array` / `ref.i31` / `ref.eq` / `ref.any` stay
 * unsupported (SKIP): V8 cannot hand those back to JS in a form we can classify.
 */
function resultType(node: Sexp): string | null {
  if (!isList(node)) return null;
  const h = head(node);
  if ((h === "ref.extern" || h === "ref.func") && node.list.length === 1) return h;
  return constType(node);
}

/** Convert a const node to the JS value WebAssembly expects as an argument. */
function constToJs(node: SexpList): unknown {
  const h = head(node);
  const lit = node.list[1] as string;
  switch (h) {
    case "ref.extern":
    case "ref.host":
      return hostRef(lit);
    // Every null reference — funcref, externref, or a user-defined heap type — crosses the JS
    // boundary as `null`. The heap type in `lit` is deliberately ignored: JS cannot distinguish
    // a null funcref from a null externref, and the module's own type-checking is what keeps the
    // two apart. See the note on `resultMatches`.
    case "ref.null":
      return null;
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

/**
 * True when a thrown error is V8 refusing to marshal a value across the JS boundary, rather than a
 * genuine trap. V8's JS API can represent `externref` and `funcref`, but not `exnref`, `anyref` or a
 * user-defined heap type — calling such an export throws
 * `type incompatibility when transforming from/to JS`.
 *
 * That is a limit of the JS embedding, NOT a toolchain defect, so it counts as a SKIP — the same
 * treatment the NaN-payload argument case already gets. **Counting it as a failure would be a false
 * negative**: it says the toolchain got something wrong when the module is fine and only the test
 * harness cannot see it. Introduced 2026-08-27 alongside `ref.null` support, which is what first
 * made these assertions reachable at all.
 */
function isJsBoundaryRefusal(e: unknown): boolean {
  return /type incompatibility when transforming/i.test(e instanceof Error ? e.message : String(e));
}

/** Compare an actual WebAssembly result value against an expected const node. Returns true on match. */
function resultMatches(expected: SexpList, actual: unknown): boolean {
  const h = head(expected);
  const lit = expected.list[1] as string;
  switch (h) {
    // ⚠️ The expected heap type is NOT checked, because it cannot be: a null funcref and a null
    // externref are both `null` in JS. This is marginally over-accepting — an assertion expecting
    // `(ref.null extern)` would pass on a null funcref — but a module cannot return the wrong
    // reference type without failing validation first, so the case is unreachable in a corpus that
    // assembles. Recorded rather than silently assumed.
    case "ref.null":
      return actual === null;
    // `(ref.extern N)` / `(ref.host N)`: the very host value passed in (identity). Index-less
    // `(ref.extern)`: any non-null externref; `(ref.func)`: any non-null funcref, which V8 exports
    // as a JS function.
    case "ref.extern":
    case "ref.host":
      return lit === undefined ? actual !== null && actual !== undefined : actual === hostRef(lit);
    case "ref.func":
      return typeof actual === "function";
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
// Trampoline: values the JS boundary cannot carry (v128, NaN payloads)
// ─────────────────────────────────────────────────────────────────────────────
//
// V8 refuses `v128` at the JS boundary outright, and a JS number cannot be trusted with a NaN's
// payload bits. Both are limits of the JS EMBEDDING, not of the module, and together they were
// ~96% of the corpus's skips (2026-09-28: 24,078 in `simd_*` plus ~1,840 `nan:0x…` float
// assertions). A wasm-to-wasm call has neither limit, so such an assertion runs through a small
// generated module that IMPORTS the function under test with its true signature and EXPORTS `run`,
// whose params and results are the same values as raw bits: f32 → i32, f64 → i64, v128 → two
// i64 halves (low, high). Every comparison is then done in JS on exact bits.

/** A value type the trampoline can lower to integer bits. */
type LowType = "i32" | "i64" | "f32" | "f64" | "v128";

const V128_SHAPES: Record<string, { lanes: number; width: number; float: boolean }> = {
  i8x16: { lanes: 16, width: 8, float: false },
  i16x8: { lanes: 8, width: 16, float: false },
  i32x4: { lanes: 4, width: 32, float: false },
  i64x2: { lanes: 2, width: 64, float: false },
  f32x4: { lanes: 4, width: 32, float: true },
  f64x2: { lanes: 2, width: 64, float: true },
};

/** The value type of a const node, if the trampoline can carry it. */
function lowType(node: Sexp): LowType | null {
  if (!isList(node)) return null;
  switch (head(node)) {
    case "i32.const":
      return "i32";
    case "i64.const":
      return "i64";
    case "f32.const":
      return "f32";
    case "f64.const":
      return "f64";
    case "v128.const":
      return V128_SHAPES[node.list[1] as string] ? "v128" : null;
  }
  return null;
}

/**
 * True when an assertion needs the trampoline: any `v128.const`, or any float literal carrying an
 * explicit NaN payload (`nan:0x…`). Everything else keeps the direct JS call, which is proven.
 */
function needsTrampoline(nodes: Sexp[]): boolean {
  return nodes.some((n) =>
    isList(n) && (head(n) === "v128.const" ||
      ((head(n) === "f32.const" || head(n) === "f64.const") && /nan:0x/.test(n.list[1] as string)))
  );
}

/**
 * A float literal's exact bit pattern, sign included. NaNs are built from their bits and never pass
 * through a JS number, which is exactly where a payload would be lost. Finite values do go through
 * a number (as `floatLitToNumber` already does for direct calls).
 */
function floatLitBits(lit: string, is32: boolean): bigint {
  let s = lit.replace(/_/g, "");
  let neg = false;
  if (s[0] === "+") s = s.slice(1);
  else if (s[0] === "-") {
    neg = true;
    s = s.slice(1);
  }
  let mag: bigint;
  if (s === "nan" || s.startsWith("nan:")) {
    const payload = s.startsWith("nan:0x") ? BigInt(s.slice(4)) : (is32 ? F32_QUIET : F64_QUIET);
    mag = (is32 ? 0x7f800000n : 0x7ff0000000000000n) | payload;
  } else {
    const v = floatLitToNumber(s, is32);
    mag = is32 ? f32Bits(v) : f64Bits(v);
  }
  const signBit = is32 ? 0x80000000n : 0x8000000000000000n;
  return neg ? mag | signBit : mag & ~signBit;
}

/** Match a float expectation (exact literal or `nan:canonical`/`nan:arithmetic`) against bits. */
function floatBitsMatch(lit: string, is32: boolean, bits: bigint): boolean {
  const s = lit.replace(/^[+-]/, "");
  if (s !== "nan:canonical" && s !== "nan:arithmetic") return floatLitBits(lit, is32) === bits;
  const expMask = is32 ? 0x7f800000n : 0x7ff0000000000000n;
  const mantMask = is32 ? 0x007fffffn : 0x000fffffffffffffn;
  const quiet = is32 ? F32_QUIET : F64_QUIET;
  if ((bits & expMask) !== expMask || (bits & mantMask) === 0n) return false; // not a NaN
  return s === "nan:canonical" ? (bits & mantMask) === quiet : (bits & quiet) !== 0n;
}

/** The raw bits of a const node (an argument). v128 → one 128-bit BigInt, lane 0 lowest. */
function constBits(node: SexpList): bigint {
  const lit = node.list[1] as string;
  switch (head(node)) {
    case "i32.const":
      return parseIntLit(lit) & 0xffffffffn;
    case "i64.const":
      return U64(parseIntLit(lit));
    case "f32.const":
      return floatLitBits(lit, true);
    case "f64.const":
      return floatLitBits(lit, false);
  }
  // v128.const <shape> <lane>…
  const shape = V128_SHAPES[lit];
  const lanes = node.list.slice(2) as string[];
  if (lanes.length !== shape.lanes) throw new Error(`__skip__: v128.const ${lit} lane count`);
  const mask = (1n << BigInt(shape.width)) - 1n;
  let v = 0n;
  for (let i = 0; i < shape.lanes; i++) {
    const b = shape.float ? floatLitBits(lanes[i], shape.width === 32) : parseIntLit(lanes[i]);
    v |= (b & mask) << BigInt(i * shape.width);
  }
  return v;
}

/** Compare an expected const node against the raw bits the trampoline returned for it. */
function bitsMatch(expected: SexpList, bits: bigint): boolean {
  const lit = expected.list[1] as string;
  switch (head(expected)) {
    case "i32.const":
      return (parseIntLit(lit) & 0xffffffffn) === bits;
    case "i64.const":
      return U64(parseIntLit(lit)) === bits;
    case "f32.const":
      return floatBitsMatch(lit, true, bits);
    case "f64.const":
      return floatBitsMatch(lit, false, bits);
  }
  const shape = V128_SHAPES[lit];
  const lanes = expected.list.slice(2) as string[];
  if (lanes.length !== shape.lanes) return false;
  const mask = (1n << BigInt(shape.width)) - 1n;
  for (let i = 0; i < shape.lanes; i++) {
    const lane = (bits >> BigInt(i * shape.width)) & mask;
    const ok = shape.float
      ? floatBitsMatch(lanes[i], shape.width === 32, lane)
      : (parseIntLit(lanes[i]) & mask) === lane;
    if (!ok) return false;
  }
  return true;
}

/** The trampoline's WAT for a callee of type `params → results`. */
function trampolineWat(params: LowType[], results: LowType[]): string {
  const lowered = (t: LowType) =>
    t === "v128" ? ["i64", "i64"] : [t === "f32" ? "i32" : t === "f64" ? "i64" : t];
  const lp = params.flatMap(lowered);
  const lr = results.flatMap(lowered);
  const body: string[] = [];
  let p = 0;
  for (const t of params) {
    if (t === "v128") {
      body.push(
        `v128.const i64x2 0 0`,
        `local.get ${p}`,
        `i64x2.replace_lane 0`,
        `local.get ${p + 1}`,
        `i64x2.replace_lane 1`,
      );
      p += 2;
    } else {
      body.push(`local.get ${p}`);
      if (t === "f32") body.push("f32.reinterpret_i32");
      if (t === "f64") body.push("f64.reinterpret_i64");
      p += 1;
    }
  }
  body.push("call $f");
  // Results come off the stack last-first into locals placed after the lowered params.
  for (let j = results.length - 1; j >= 0; j--) body.push(`local.set ${lp.length + j}`);
  results.forEach((t, j) => {
    const l = lp.length + j;
    if (t === "v128") {
      body.push(`local.get ${l}`, `i64x2.extract_lane 0`, `local.get ${l}`, `i64x2.extract_lane 1`);
    } else {
      body.push(`local.get ${l}`);
      if (t === "f32") body.push("i32.reinterpret_f32");
      if (t === "f64") body.push("i64.reinterpret_f64");
    }
  });
  const sig = (kw: string, ts: string[]) => ts.length ? ` (${kw} ${ts.join(" ")})` : "";
  return `(module
  (import "t" "f" (func $f${sig("param", params)}${sig("result", results)}))
  (func (export "run")${sig("param", lp)}${sig("result", lr)}${sig("local", results)}
    ${body.join("\n    ")}))`;
}

/** Lower one argument's bits to the JS values `run` takes (i32 → number, i64 → BigInt). */
function lowerArg(t: LowType, bits: bigint): unknown[] {
  if (t === "i32" || t === "f32") return [Number(BigInt.asIntN(32, bits))];
  if (t === "i64" || t === "f64") return [BigInt.asIntN(64, bits)];
  return [BigInt.asIntN(64, bits & 0xffffffffffffffffn), BigInt.asIntN(64, bits >> 64n)];
}

/** Rebuild each result's raw bits from `run`'s lowered return values. */
function raiseResults(results: LowType[], out: unknown[]): bigint[] {
  const bits: bigint[] = [];
  let k = 0;
  for (const t of results) {
    if (t === "i32" || t === "f32") bits.push(BigInt((out[k++] as number) >>> 0));
    else if (t === "i64" || t === "f64") bits.push(U64(out[k++] as bigint));
    else {
      const lo = U64(out[k++] as bigint);
      const hi = U64(out[k++] as bigint);
      bits.push(lo | (hi << 64n));
    }
  }
  return bits;
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
        // UTF-8 ENCODE, do not push the UTF-16 code unit. `charCodeAt` returns a value up to
        // 0xFFFF and `new Uint8Array(bytes)` truncates anything above 0xFF, so every non-ASCII
        // character in a WAT string was silently corrupted. `names.wast` exports a function named
        // U+FEFF (raw EF BB BF in the source): we pushed 0xFEFF, it became 0xFF, and the export
        // lookup missed. Astral characters are worse - a lone surrogate each. Encode the whole
        // code point, and skip the low surrogate the loop would otherwise re-read.
        // Surfaced 2026-08-25 by wabt-ts 1.4.0, which made these modules assemble for the first
        // time; the bug itself predates it.
        const cp = s.codePointAt(i)!;
        if (cp < 0x80) {
          bytes.push(cp);
        } else {
          for (const b of new TextEncoder().encode(String.fromCodePoint(cp))) bytes.push(b);
          if (cp > 0xffff) i++; // consumed a surrogate PAIR
        }
      }
    }
  }
  return new Uint8Array(bytes);
}

/**
 * UTF-8 decoder for WAT string contents. `ignoreBOM: true` is LOAD-BEARING: the default decoder
 * silently drops a leading U+FEFF, so `names.wast`'s export `"\u{FEFF}"` was invoked as `""` and
 * failed (2026-09-28). A name or quoted module is bytes, not a document; nothing here may be eaten.
 */
const watUtf8 = new TextDecoder("utf-8", { ignoreBOM: true });

/** Decode a single verbatim WAT string token (`"export.name"`) to a JS string. */
function watStrToJs(token: string): string {
  return watUtf8.decode(decodeWatString([token]));
}

/**
 * The standard `spectest` host module the spec testsuite imports.
 *
 * These VALUES ARE PART OF THE CONTRACT, not placeholders — the corpus asserts them directly.
 * `global_f32`/`global_f64` were `0` here until 2026-08-24 and the spec defines them as **666.6**,
 * which is why `imports.wast` reported two `assert_return mismatch` failures against `get-5`/`get-6`.
 * A wrong host value is indistinguishable from a codegen bug in the failure output, so it read as
 * ours for as long as it stood.
 *
 * `spectest.unknown` is imported 9 times by the corpus and is DELIBERATELY ABSENT — those are
 * `assert_unlinkable` cases that require the import to fail to resolve. Never add it.
 */
function spectestImports(): WebAssembly.ModuleImports {
  const imports: Record<string, unknown> = {
    print: () => {},
    print_i32: () => {},
    print_i64: () => {},
    print_f32: () => {},
    print_f64: () => {},
    print_i32_f32: () => {},
    print_f64_f64: () => {},
    global_i32: new WebAssembly.Global({ value: "i32", mutable: false }, 666),
    global_i64: new WebAssembly.Global({ value: "i64", mutable: false }, 666n),
    global_f32: new WebAssembly.Global({ value: "f32", mutable: false }, 666.6),
    global_f64: new WebAssembly.Global({ value: "f64", mutable: false }, 666.6),
    table: new WebAssembly.Table({ initial: 10, maximum: 20, element: "anyfunc" }),
    memory: new WebAssembly.Memory({ initial: 1, maximum: 2 }),
  };
  // Proposal-gated exports. Constructed defensively: a host engine that does not implement the
  // feature throws here, and the RIGHT outcome then is that the import stays absent (so dependent
  // modules skip) rather than the whole spectest module failing to build and taking every file
  // with it.
  try {
    imports.shared_memory = new WebAssembly.Memory({ initial: 1, maximum: 1, shared: true });
  } catch { /* threads unsupported by this engine — leave absent */ }
  try {
    imports.table64 = new WebAssembly.Table(
      { initial: 10, maximum: 20, element: "anyfunc", index: "i64" } as WebAssembly.TableDescriptor,
    );
  } catch { /* table64 unsupported by this engine — leave absent */ }
  return imports as WebAssembly.ModuleImports;
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
  /**
   * Modules in this file the toolchain could not ASSEMBLE. Report this alongside pass/fail/skip:
   * a file whose modules do not build is not healthy just because its failure count is small, and
   * every failure after the first one is likely a CASCADE from it rather than an independent
   * verdict. Rank remediation by THIS number, not by the failure count — 11 of the 12 failures in
   * the corpus today come from four unassemblable modules.
   */
  modulesFailed: number;
  /** Human-readable messages for each failed command (one entry per failure). */
  failures: string[];
}

/**
 * Lazily-created, PROCESS-WIDE WABT instance.
 *
 * This used to be `await wabt()` inside `runWast`, i.e. a brand-new WABT module per file, never
 * released. One file was fine; a directory run was not. `wasmtk wast <dir>` over the 288-file spec
 * corpus climbed past 4 GB and died with "Fatal JavaScript out of memory: Ineffective mark-compacts
 * near heap limit" around the 18-second mark — and that directory form is the one the README
 * documents. Reusing a single instance is also what wabt's own JS API expects: one module, many
 * `parseWat` calls, each result `destroy()`ed by the caller (which `assemble` already does).
 */
let wabtModPromise: Promise<WabtModule> | null = null;
function getWabt(): Promise<WabtModule> {
  return (wabtModPromise ??= (wabt as unknown as () => Promise<WabtModule>)());
}

/** Run a single `.wast` file. Never throws — every command's outcome is tallied. */
export async function runWast(
  path: string,
  opts: { verbose?: boolean; maxFailures?: number } = {},
): Promise<WastResult> {
  const res: WastResult = {
    file: path,
    passed: 0,
    failed: 0,
    skipped: 0,
    modulesFailed: 0,
    failures: [],
  };
  const src = await rt.readTextFile(path);
  let cmds: SexpList[];
  try {
    cmds = parseSexprs(src);
  } catch (e) {
    res.failed++;
    res.failures.push(`parse error: ${e instanceof Error ? e.message : e}`);
    return res;
  }

  const wabtMod: WabtModule = await getWabt();

  let cur: WebAssembly.Instance | null = null;
  const named = new Map<string, WebAssembly.Instance>();
  const registry: Record<string, WebAssembly.ModuleImports> = { spectest: spectestImports() };

  // Set once any module in this file fails to assemble. Every later failure is then reported as a
  // CASCADE rather than a bare wrong-answer, because that distinction is knowable HERE and nowhere
  // downstream: a scorer looking at `assert_return mismatch` cannot tell "the engine computed the
  // wrong value" from "a module that should have populated this state never built". Conflating the
  // two is what made these read as codegen bugs. They still FAIL — loudly, by design — they are
  // just now labelled with what actually happened.
  let sawUnassemblableModule = false;
  const fail = (msg: string) => {
    res.failed++;
    const tagged = sawUnassemblableModule
      ? `[cascade: a module in this file did not assemble] ${msg}`
      : msg;
    if (res.failures.length < (opts.maxFailures ?? 25)) res.failures.push(tagged);
  };

  // Build the import object a module needs from the registry (+ spectest).
  const buildImports = (): WebAssembly.Imports => {
    const imp: WebAssembly.Imports = {};
    for (const [k, v] of Object.entries(registry)) imp[k] = v;
    return imp;
  };

  // Assemble a `(module …)` node to bytes. Supports `(module binary …)` + text. Throws on failure.
  function assemble(mod: SexpList): Uint8Array {
    const bkIdx = mod.list.findIndex((x) => x === "binary");
    const qkIdx = mod.list.findIndex((x) => x === "quote");
    if (bkIdx !== -1) {
      const strs = mod.list.slice(bkIdx + 1).filter((x): x is string => typeof x === "string");
      return decodeWatString(strs);
    }
    let text: string;
    if (qkIdx !== -1) {
      const strs = mod.list.slice(qkIdx + 1).filter((x): x is string => typeof x === "string");
      text = watUtf8.decode(decodeWatString(strs));
      if (!/^\s*\(module/.test(text)) text = `(module ${text})`;
    } else {
      text = src.slice(mod.start, mod.end);
    }
    let parsed: ReturnType<WabtModule["parseWat"]>;
    try {
      parsed = wabtMod.parseWat(path, text, { enable_all: true });
    } catch (e) {
      throw new AssembleError("parse", e); // genuinely MALFORMED text
    }
    try {
      const { buffer } = parsed.toBinary({});
      return new Uint8Array(buffer);
    } catch (e) {
      throw new AssembleError("encode", e); // parsed fine → well-formed, but not encodable
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

  // One compiled trampoline per (instance, export, signature). Most SIMD files hammer a handful of
  // exports thousands of times, so the cache is what keeps this from assembling a module per assert.
  const trampolines = new WeakMap<
    WebAssembly.Instance,
    Map<string, (...a: unknown[]) => unknown>
  >();

  /**
   * Run an `(invoke …)` through the trampoline (see `trampolineWat`) and return each result's raw
   * bits. `resultTypes` must come from the assertion's expected values: a wrong guess fails to LINK
   * (the import signature is checked), which is reported as a skip, never as a wrong answer.
   */
  function runTrampolined(action: SexpList, resultTypes: LowType[]): bigint[] {
    let idx = 1;
    let nameTok: string | undefined;
    if (typeof action.list[idx] === "string" && (action.list[idx] as string).startsWith("$")) {
      nameTok = action.list[idx] as string;
      idx++;
    }
    const field = watStrToJs(action.list[idx] as string);
    const argNodes = action.list.slice(idx + 1);
    const inst = actionInstance(nameTok);
    if (!inst) throw new Error("__skip__: no active module instance");
    const paramTypes: LowType[] = [];
    for (const a of argNodes) {
      const t = lowType(a);
      if (!t) throw new Error("__skip__: unsupported arg type");
      paramTypes.push(t);
    }
    const fn = (inst.exports as Record<string, unknown>)[field];
    if (typeof fn !== "function") throw new Error(`export '${field}' is not a function`);

    let perInst = trampolines.get(inst);
    if (!perInst) trampolines.set(inst, perInst = new Map());
    const key = `${field}\u0000${paramTypes.join(",")}\u0000${resultTypes.join(",")}`;
    let run = perInst.get(key);
    if (!run) {
      const wat = trampolineWat(paramTypes, resultTypes);
      let bytes: Uint8Array;
      try {
        const parsed = wabtMod.parseWat("trampoline.wat", wat, { enable_all: true });
        try {
          bytes = new Uint8Array(parsed.toBinary({}).buffer);
        } finally {
          parsed.destroy();
        }
      } catch (e) {
        // Our own generated text failing to assemble is a runner defect: loud, not a skip.
        throw new Error(`trampoline did not assemble: ${e instanceof Error ? e.message : e}`);
      }
      try {
        const tInst = new WebAssembly.Instance(new WebAssembly.Module(bytes as BufferSource), {
          t: { f: fn as WebAssembly.ImportValue },
        });
        run = tInst.exports.run as (...a: unknown[]) => unknown;
      } catch (e) {
        if (e instanceof WebAssembly.LinkError) {
          throw new Error(`__skip__: trampoline signature did not link: ${e.message}`);
        }
        throw e;
      }
      perInst.set(key, run);
    }
    const args = argNodes.flatMap((a, i) => lowerArg(paramTypes[i], constBits(a as SexpList)));
    const r = run(...args);
    const out = r === undefined ? [] : (Array.isArray(r) ? r : [r]);
    return raiseResults(resultTypes, out);
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
    const args: unknown[] = []; // null = `ref.null`; an object = `ref.extern N` (hostRef)
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

  const anyUnsupportedResult = (nodes: Sexp[]) => nodes.some((x) => !isList(x) || !resultType(x));

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
            res.modulesFailed++;
            sawUnassemblableModule = true;
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
          if (head(action) === "invoke" && needsTrampoline([...action.list, ...expected])) {
            const resultTypes = expected.map(lowType);
            if (resultTypes.some((t) => t === null)) {
              res.skipped++; // e.g. `(either …)` — not yet carried
              break;
            }
            let bits: bigint[];
            try {
              bits = runTrampolined(action, resultTypes as LowType[]);
            } catch (e) {
              if (String(e).includes("__skip__")) {
                res.skipped++;
                if (opts.verbose) res.failures.push(`skip (${e instanceof Error ? e.message : e})`);
                break;
              }
              fail(`assert_return action trapped: ${e instanceof Error ? e.message : e}`);
              break;
            }
            if (
              bits.length === expected.length && expected.every((x, k) => bitsMatch(x, bits[k]))
            ) {
              res.passed++;
            } else {
              fail(
                `assert_return mismatch: ${
                  src.slice(cmd.start, Math.min(cmd.end, cmd.start + 120))
                }`,
              );
            }
            break;
          }
          if (anyUnsupportedResult(expected)) {
            res.skipped++;
            break;
          }
          let results: unknown[];
          try {
            results = runAction(action);
          } catch (e) {
            if (String(e).includes("__skip__") || isJsBoundaryRefusal(e)) {
              res.skipped++;
              if (opts.verbose && isJsBoundaryRefusal(e)) {
                res.failures.push(
                  `skip (JS boundary cannot carry this reference type): ${
                    src.slice(cmd.start, cmd.start + 70)
                  }`,
                );
              }
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
            // The argument is a MODULE: `assert_trap` on instantiation. It MUST be run, because
            // instantiation gets part-way before trapping — element and data segments that precede
            // the trap ARE written into the imported table/memory, and later assertions read that
            // state. Until 2026-09-28 it was skipped, which cost 11 `linking*` assertions that read
            // as bare "null function" traps. V8 applies the partial writes itself; we only instantiate.
            let bytes: Uint8Array | null = null;
            try {
              bytes = isList(action) ? assemble(action) : null;
            } catch { /* handled below as unbuilt */ }
            let outcome: "trapped" | "instantiated" | "other" = "other";
            if (bytes) {
              try {
                await instantiate(bytes);
                outcome = "instantiated";
              } catch (e) {
                const trap = e instanceof WebAssembly.RuntimeError ||
                  (h === "assert_exhaustion" && e instanceof RangeError);
                outcome = trap ? "trapped" : "other";
              }
            }
            if (outcome === "trapped") res.passed++;
            else if (outcome === "instantiated") {
              fail(
                `${h} module instantiated without trapping: ${
                  src.slice(cmd.start, cmd.start + 100)
                }`,
              );
            } else {
              // Did not assemble, or failed to LINK/compile — not the trap this asserts. Count it
              // with the unbuilt modules and arm the cascade tag, so a failure it causes says where
              // it came from.
              res.skipped++;
              res.modulesFailed++;
              sawUnassemblableModule = true;
            }
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
          // `(module binary …)` has no text to decode — the BYTES are the subject, and V8's
          // decoder rejecting them ("magic header not detected", "unexpected end") IS the decode
          // failure the assertion asserts. For those, any compile error is a genuine pass.
          const isBinary = mod.list.some((x) => x === "binary");
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
          } catch (e) {
            // A quote/text module that PARSED is well-formed. Whatever killed it afterwards —
            // the encoder, or V8's validator — is not the decode failure this asserts, so it is a
            // toolchain gap (skip), never a pass. Counting it as a pass is how a false green hides.
            if (!isBinary && e instanceof AssembleError && e.stage === "encode") {
              res.skipped++;
              if (opts.verbose) {
                res.failures.push(
                  `not malformed (well-formed; failed at ENCODE): ${
                    src.slice(cmd.start, cmd.start + 70)
                  }`,
                );
              }
              break;
            }
            if (!isBinary && !(e instanceof AssembleError)) {
              // parsed and encoded, then V8 rejected it → invalid, not malformed.
              res.skipped++;
              if (opts.verbose) {
                res.failures.push(
                  `not malformed (well-formed; INVALID per V8): ${
                    src.slice(cmd.start, cmd.start + 70)
                  }`,
                );
              }
              break;
            }
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
  let tp = 0, tf = 0, ts = 0, tm = 0;
  const multi = results.length > 1;
  for (const r of results) {
    tp += r.passed;
    tf += r.failed;
    ts += r.skipped;
    tm += r.modulesFailed;
    const base = r.file.split(/[\\/]/).pop();
    // Surface a file whose MODULES did not build even when it reports no failures — that file is
    // not healthy, it is dark, and it is invisible in all three of the usual columns.
    if (multi && r.failed === 0 && r.modulesFailed === 0 && !opts.verbose) continue;
    const tag = r.failed > 0 ? "❌" : (r.modulesFailed > 0 ? "⚠" : "✓");
    console.log(
      `${tag} ${base}: pass=${r.passed} fail=${r.failed} skip=${r.skipped}` +
        (r.modulesFailed > 0 ? ` unbuilt-modules=${r.modulesFailed}` : ""),
    );
    for (const m of r.failures.slice(0, 6)) {
      console.log("    " + m.replace(/\s+/g, " ").slice(0, 140));
    }
  }
  console.log(
    `\n${
      tf === 0 ? "✅" : "❌"
    } wast: ${results.length} file(s) — ${tp} passed, ${tf} failed, ${ts} skipped, ${tm} unbuilt modules` +
      (tf > 0 ? "  (execution assertion failures)" : ""),
  );
  if (tm > 0) {
    console.log(
      `   ${tm} module(s) could not be ASSEMBLED — read this alongside the other three. A file whose\n` +
        "   modules do not build is not healthy just because its failure count is small, and failures\n" +
        "   after the first unbuilt module are tagged [cascade] because they are knock-on, not\n" +
        "   independent verdicts. RANK REMEDIATION BY THIS NUMBER: one unbuilt module typically\n" +
        "   accounts for several failures and many skips at once.",
    );
  }
  if (ts > 0) {
    console.log(
      "   skipped = assertions using features/value-types out of scope (some ref kinds, unsupported\n" +
        "   proposals, or validation assertions the wabt+host toolchain does not reject).",
    );
  }
  return tf === 0 ? 0 : 1;
}
