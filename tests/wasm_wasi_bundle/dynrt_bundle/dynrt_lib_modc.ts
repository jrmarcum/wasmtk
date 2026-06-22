// wasmtk own dynamic runtime — #14, increment 1: the boxed-value + dynamic-object model.
//
// DECISION TRACE (roadmap §7-#7 / cmem/dynrt-design.md): wasmtk ships its OWN dynamic runtime
// (boxed values + property map + — later — an interpreter) rather than depending on javyc/QuickJS.
// This first increment delivers ONLY the value + object substrate that everything else lowers onto;
// there is no `eval`/interpreter and no prototype mutation yet. It is authored in the SAME wasic TS
// subset as the Tier-1 caps (Set/Map/Date/JSON/RegExp), so the allocator, strings, dynamic arrays
// and number formatting all come from wasic's own codegen for free — zero duplication (a shared
// `rtcore` + hand-WAT is the chosen path only when the interpreter increment needs it).
//
// Compiled with `wasmtk modc` (no _start / no WASI). A driver/host imports the exports and the
// wasmmerge allocator-unification pass (Stage 0.6) makes every $__malloc here resolve to the host
// module's shared bump cursor, so boxed values live on the ONE heap shared with the program.
//
// THE BOXED VALUE  (value = i32 handle = base pointer of a 4-slot Int32Array node)
// --------------------------------------------------------------------------------
//   node[0] tag : 0=undefined 1=null 2=boolean 3=number 4=string 5=array 6=object
//   node[1] a   : bool→0/1 · number→ptr to Float64Array(1) · string→Uint8Array byte buffer ptr ·
//                 array→i32[] of value handles · object→i32[] of value handles
//   node[2] b   : string→byte length (numbers/arrays/objects read their length LIVE, see below)
//   node[3] c   : object→i32[] of interleaved [keyPtr, keyLen] pairs (length = 2 * entryCount)
//
// Containers (array elems, object vals, object keys) reuse wasic's native dynamic `i32[]`: stored
// by pointer (`arr as unknown as i32`) and reconstructed for access (`ptr as unknown as i32[]`).
// Because `.push` can GROW (reallocate) the backing array, every mutator writes the (possibly new)
// pointer back into the owning node — the one structural difference from the immutable JSON tree.
//
// SCOPE (v1): undefined / null / boolean / number (real f64) / string / array / object; the dynamic
// operators `typeof`, `===` (dynStrictEq) and `+` (dynAdd — numeric add + string concat). Functions
// (tag 7), `eval`/`new Function`, prototype mutation, and string→number coercion are later
// increments. Strings are UTF-16-code-unit / ASCII-accurate (multi-byte is the documented gap, as
// elsewhere in wasic). Absent object keys return the sentinel -1 (the future wasic `any` lowering
// maps that to `undefined`).

type i32 = number;
type f64 = number;

// ── Tag constants (kept as literals at use sites; listed here for reference) ──────────────────
//   0 undefined · 1 null · 2 boolean · 3 number · 4 string · 5 array · 6 object

// ── Constructors ──────────────────────────────────────────────────────────────────────────────

/** The `undefined` value. */
/** @export */
export function dynUndefined(): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 0;
  return n as unknown as i32;
}

/** The `null` value. */
/** @export */
export function dynNull(): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 1;
  return n as unknown as i32;
}

/** A boolean value from 0 (false) / non-zero (true). */
/** @export */
export function dynBool(b: i32): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 2;
  n[1] = b === 0 ? 0 : 1;
  return n as unknown as i32;
}

/** A number value (real f64). */
/** @export */
export function dynNumber(x: f64): i32 {
  const fv: Float64Array = new Float64Array(1);
  fv[0] = x;
  const n: Int32Array = new Int32Array(4);
  n[0] = 3;
  n[1] = fv as unknown as i32;
  return n as unknown as i32;
}

/** A string value (bytes copied from the wasic string). */
/** @export */
export function dynString(s: string): i32 {
  const len: i32 = s.length;
  const buf: Uint8Array = new Uint8Array(len);
  let i: i32 = 0;
  while (i < len) {
    buf[i] = s.charCodeAt(i);
    i = i + 1;
  }
  const n: Int32Array = new Int32Array(4);
  n[0] = 4;
  n[1] = buf as unknown as i32;
  n[2] = len;
  return n as unknown as i32;
}

// ── Self-managed growable i32 list (Set/Map idiom) ────────────────────────────────────────────
// A "list" is an Int32Array laid out as [len, cap, e0, e1, …]. We manage growth ourselves with a
// guaranteed nonzero starting capacity and correct doubling — wasic's native `[]`-then-`.push`
// path can't be used here: an empty `[]` literal lowers to a SHARED static zero-capacity array
// (every `dynArray()` would alias address 260) and `$__dynarr_push_i32` grows by `cap<<1`, which
// stays 0 from a 0 capacity (see cmem/dynrt-design.md / compiler-bugs.md "empty-array push gap").
const LIST_CAP0: i32 = 4;

function listNew(): i32 {
  const a: Int32Array = new Int32Array(LIST_CAP0 + 2);
  a[0] = 0;          // len
  a[1] = LIST_CAP0;  // cap
  return a as unknown as i32;
}

function listLen(lp: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  return a[0];
}

function listGet(lp: i32, i: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  return a[i + 2];
}

function listSet(lp: i32, i: i32, v: i32): void {
  const a: Int32Array = lp as unknown as Int32Array;
  a[i + 2] = v;
}

// Append; returns the (possibly reallocated) list pointer — caller must write it back.
function listPush(lp: i32, v: i32): i32 {
  const a: Int32Array = lp as unknown as Int32Array;
  const len: i32 = a[0];
  const cap: i32 = a[1];
  if (len >= cap) {
    const ncap: i32 = cap * 2;
    const b: Int32Array = new Int32Array(ncap + 2);
    b[1] = ncap;
    let i: i32 = 0;
    while (i < len) {
      b[i + 2] = a[i + 2];
      i = i + 1;
    }
    b[len + 2] = v;
    b[0] = len + 1;
    return b as unknown as i32;
  }
  a[len + 2] = v;
  a[0] = len + 1;
  return lp;
}

/** A fresh empty array. */
/** @export */
export function dynArray(): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 5;
  n[1] = listNew();
  return n as unknown as i32;
}

/** A fresh empty object. */
/** @export */
export function dynObject(): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 6;
  n[1] = listNew(); // values
  n[3] = listNew(); // interleaved [keyPtr, keyLen]
  return n as unknown as i32;
}

// ── Introspection ─────────────────────────────────────────────────────────────────────────────

/** Raw structural tag: 0=undefined 1=null 2=boolean 3=number 4=string 5=array 6=object. */
/** @export */
export function dynTag(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[0];
}

/**
 * JS `typeof` code: 0=undefined 1=object 2=boolean 3=number 4=string 5=function.
 * Note the JS quirk: typeof null / array / plain object are all "object" (→ 1).
 */
/** @export */
export function dynTypeof(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 0) return 0; // undefined
  if (t === 2) return 2; // boolean
  if (t === 3) return 3; // number
  if (t === 4) return 4; // string
  return 1;              // null / array / object → "object"
}

// ── Typed accessors (assert nothing; caller is expected to check the tag) ─────────────────────

/** The f64 value of a number box. */
/** @export */
export function dynNumberValue(v: i32): f64 {
  const n: Int32Array = v as unknown as Int32Array;
  const p: i32 = n[1];
  const fv: Float64Array = p as unknown as Float64Array;
  return fv[0];
}

/** The 0/1 value of a boolean box. */
/** @export */
export function dynBoolValue(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[1];
}

/** Byte length of a string box. */
/** @export */
export function dynStrLen(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  return n[2];
}

/** Byte (char code) at index `i` of a string box. */
/** @export */
export function dynStrCharAt(v: i32, i: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const p: i32 = n[1];
  const buf: Uint8Array = p as unknown as Uint8Array;
  return buf[i];
}

// ── Coercions (JS ToBoolean / ToNumber) ───────────────────────────────────────────────────────

/** JS truthiness: 1 if truthy, else 0. */
/** @export */
export function dynToBool(v: i32): i32 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 0) return 0; // undefined
  if (t === 1) return 0; // null
  if (t === 2) return n[1];
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    const x: f64 = fv[0];
    if (x !== x) return 0;      // NaN is falsy
    return x === 0 ? 0 : 1;     // 0 and -0 are falsy
  }
  if (t === 4) return n[2] === 0 ? 0 : 1; // "" is falsy
  return 1;                                // array / object are truthy
}

/** JS ToNumber (v1: string/array/object → NaN). */
/** @export */
export function dynToNumber(v: i32): f64 {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 1) return 0;          // null → 0
  if (t === 2) return n[1] === 0 ? 0 : 1; // bool → 0/1
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    return fv[0];
  }
  return Number.NaN;              // undefined / string / array / object → NaN (v1)
}

// ── Internal: reconstruct a wasic string from a string box's bytes ────────────────────────────
function boxToStr(v: i32): string {
  const n: Int32Array = v as unknown as Int32Array;
  const len: i32 = n[2];
  const p: i32 = n[1];
  const buf: Uint8Array = p as unknown as Uint8Array;
  let r: string = "";
  let i: i32 = 0;
  while (i < len) {
    r = r + String.fromCharCode(buf[i]);
    i = i + 1;
  }
  return r;
}

// ── Internal: JS ToString for the `+` concat path (array/object → "" in v1) ───────────────────
function stringForm(v: i32): string {
  const n: Int32Array = v as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 4) return boxToStr(v);
  if (t === 3) {
    const p: i32 = n[1];
    const fv: Float64Array = p as unknown as Float64Array;
    const x: f64 = fv[0];
    return `${x}`;
  }
  if (t === 2) return n[1] === 0 ? "false" : "true";
  if (t === 1) return "null";
  if (t === 0) return "undefined";
  return ""; // array / object stringification deferred to a later increment
}

// ── Object ops ────────────────────────────────────────────────────────────────────────────────

// Index of `key` among an object's entries, or -1. `keys` list is interleaved [keyPtr, keyLen].
function objIndexOf(obj: i32, key: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const vlp: i32 = n[1];
  const klp: i32 = n[3];
  const count: i32 = listLen(vlp);
  const klen: i32 = key.length;
  let i: i32 = 0;
  while (i < count) {
    const kl: i32 = listGet(klp, i * 2 + 1);
    if (kl === klen) {
      const kptr: i32 = listGet(klp, i * 2);
      const kv: Uint8Array = kptr as unknown as Uint8Array;
      let eq: i32 = 1;
      let j: i32 = 0;
      while (j < kl) {
        if (kv[j] !== key.charCodeAt(j)) {
          eq = 0;
          j = kl;
        } else {
          j = j + 1;
        }
      }
      if (eq === 1) return i;
    }
    i = i + 1;
  }
  return -1;
}

/** Set `obj[key] = val` (overwrite if present, else append). */
/** @export */
export function dynSet(obj: i32, key: string, val: i32): void {
  const n: Int32Array = obj as unknown as Int32Array;
  const hit: i32 = objIndexOf(obj, key);
  if (hit !== -1) {
    listSet(n[1], hit, val); // overwrite value in place
    return;
  }
  // append: copy key bytes, push [keyPtr, keyLen] to the keys list and val to the values list
  const klen: i32 = key.length;
  const kbuf: Uint8Array = new Uint8Array(klen);
  let m: i32 = 0;
  while (m < klen) {
    kbuf[m] = key.charCodeAt(m);
    m = m + 1;
  }
  const kp0: i32 = kbuf as unknown as i32;
  let klp: i32 = n[3];
  klp = listPush(klp, kp0);
  klp = listPush(klp, klen);
  n[3] = klp;
  n[1] = listPush(n[1], val);
}

/** `obj[key]` → value handle, or -1 if absent. */
/** @export */
export function dynGet(obj: i32, key: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const hit: i32 = objIndexOf(obj, key);
  if (hit === -1) return -1;
  return listGet(n[1], hit);
}

/** 1 if `obj` has own `key`, else 0. */
/** @export */
export function dynHas(obj: i32, key: string): i32 {
  return objIndexOf(obj, key) === -1 ? 0 : 1;
}

/** Number of own entries on an object. */
/** @export */
export function dynObjLen(obj: i32): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  return listLen(n[1]);
}

// ── Array ops ─────────────────────────────────────────────────────────────────────────────────

/** Append `val` to an array. */
/** @export */
export function dynPush(arr: i32, val: i32): void {
  const n: Int32Array = arr as unknown as Int32Array;
  n[1] = listPush(n[1], val); // listPush may reallocate — write the new pointer back
}

/** Array length. */
/** @export */
export function dynArrLen(arr: i32): i32 {
  const n: Int32Array = arr as unknown as Int32Array;
  return listLen(n[1]);
}

/** Array element at index `i` (a value handle). */
/** @export */
export function dynArrGet(arr: i32, i: i32): i32 {
  const n: Int32Array = arr as unknown as Int32Array;
  return listGet(n[1], i);
}

// ── Operators ─────────────────────────────────────────────────────────────────────────────────

/** JS `===` (strict equality): primitives by value, objects/arrays by reference. */
/** @export */
export function dynStrictEq(a: i32, b: i32): i32 {
  const na: Int32Array = a as unknown as Int32Array;
  const nb: Int32Array = b as unknown as Int32Array;
  const ta: i32 = na[0];
  const tb: i32 = nb[0];
  if (ta !== tb) return 0;
  if (ta === 0) return 1; // undefined === undefined
  if (ta === 1) return 1; // null === null
  if (ta === 2) return na[1] === nb[1] ? 1 : 0;
  if (ta === 3) {
    const pa: i32 = na[1];
    const pb: i32 = nb[1];
    const fa: Float64Array = pa as unknown as Float64Array;
    const fb: Float64Array = pb as unknown as Float64Array;
    // NOTE: comparing Float64Array elements directly (`fa[0] === fb[0]`) mis-infers as i32 — route
    // through explicitly-typed f64 locals (a known wasic gap; see cmem/dynrt-design.md).
    const xa: f64 = fa[0];
    const xb: f64 = fb[0];
    return xa === xb ? 1 : 0; // NaN === NaN is false (f64.eq)
  }
  if (ta === 4) {
    const len: i32 = na[2];
    if (len !== nb[2]) return 0;
    const pa: i32 = na[1];
    const pb: i32 = nb[1];
    const va: Uint8Array = pa as unknown as Uint8Array;
    const vb: Uint8Array = pb as unknown as Uint8Array;
    let i: i32 = 0;
    while (i < len) {
      if (va[i] !== vb[i]) return 0;
      i = i + 1;
    }
    return 1;
  }
  // array / object: reference identity (same handle)
  return a === b ? 1 : 0;
}

/** JS `+`: string concat if either operand is a string, else numeric addition. */
/** @export */
export function dynAdd(a: i32, b: i32): i32 {
  const na: Int32Array = a as unknown as Int32Array;
  const nb: Int32Array = b as unknown as Int32Array;
  if (na[0] === 4 || nb[0] === 4) {
    // NOTE: `stringForm(a) + stringForm(b)` (concat of two string-returning CALLS) is not yet
    // supported by emitStringAssign — bind each to a string local first (a known wasic gap; see
    // cmem/dynrt-design.md / compiler-bugs.md). Remove this dance once the compiler handles it.
    const sa: string = stringForm(a);
    const sb: string = stringForm(b);
    const s: string = sa + sb;
    return dynString(s);
  }
  const an: f64 = dynToNumber(a);
  const bn: f64 = dynToNumber(b);
  return dynNumber(an + bn);
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2a — dynamic operators (used by dynEval; also the operator surface the future wasic
// `any` lowering will call for `-` `*` `/` `%` `< > <= >=` `-x` `!x`). Comparisons are numeric in
// v1 (string/lexicographic compare is a documented gap).
// ──────────────────────────────────────────────────────────────────────────────────────────────

/** Unary minus (`-x`). */
/** @export */
export function dynNeg(v: i32): i32 {
  const a: f64 = dynToNumber(v);
  return dynNumber(0 - a);
}

/** Logical NOT (`!x`). */
/** @export */
export function dynNot(v: i32): i32 {
  return dynBool(dynToBool(v) === 0 ? 1 : 0);
}

/** Numeric subtraction (`-`). */
/** @export */
export function dynSub(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a - b);
}

/** Numeric multiplication (`*`). */
/** @export */
export function dynMul(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a * b);
}

/** Numeric division (`/`). */
/** @export */
export function dynDiv(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynNumber(a / b);
}

/** Remainder (`%`, JS truncated-toward-zero semantics). */
/** @export */
export function dynMod(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  const q: f64 = a / b;
  const t: f64 = q < 0 ? Math.ceil(q) : Math.floor(q);
  return dynNumber(a - b * t);
}

/** Less-than (`<`, numeric). */
/** @export */
export function dynLt(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a < b ? 1 : 0);
}

/** Greater-than (`>`, numeric). */
/** @export */
export function dynGt(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a > b ? 1 : 0);
}

/** Less-or-equal (`<=`, numeric). */
/** @export */
export function dynLe(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a <= b ? 1 : 0);
}

/** Greater-or-equal (`>=`, numeric). */
/** @export */
export function dynGe(x: i32, y: i32): i32 {
  const a: f64 = dynToNumber(x);
  const b: f64 = dynToNumber(y);
  return dynBool(a >= b ? 1 : 0);
}

// ──────────────────────────────────────────────────────────────────────────────────────────────
// Increment 2a — `eval` of a pure expression language → boxed value.
//
// A recursive-descent, DIRECT-eval parser (no separate AST) over a module-level cursor `evalPos`,
// mirroring the JSON parser's shape. Grammar (low→high precedence): ternary `?:`, `||`, `&&`,
// equality `=== !== == !=` (`==`/`!=` treated as strict in v1), relational `< > <= >=`, additive
// `+ -`, multiplicative `* / %`, unary `- ! +`, primary (number/string/bool/null/undefined literal
// or parenthesised expr). Because v1 expressions have NO side effects (no variables, calls, or
// assignments yet), `&&`/`||`/`?:` evaluate both sides and select — observationally identical to
// short-circuit. Real short-circuit arrives with 2b (variables + calls). Identifiers other than the
// keywords, member access, and calls are 2b+. See cmem/dynrt-design.md.
// ──────────────────────────────────────────────────────────────────────────────────────────────

let evalPos: i32 = 0;  // read cursor into the eval source string
let evalEnv: i32 = -1; // current environment object handle (names → values), or -1 for none

// Compare two wasic strings byte-for-byte (avoids relying on `===` over reconstructed substrings).
function strEq(a: string, b: string): i32 {
  if (a.length !== b.length) return 0;
  let i: i32 = 0;
  while (i < a.length) {
    if (a.charCodeAt(i) !== b.charCodeAt(i)) return 0;
    i = i + 1;
  }
  return 1;
}

// `obj.name` — TOTAL (guarded): object property (undefined if absent), array/string `.length`,
// undefined for anything else. Never dereferences a non-container, so `undefined.x` → undefined
// rather than a trap (a forgiving runtime; this also removes the only trap motivation for
// short-circuit in 2b, so real short-circuit lands with calls in the next sub-increment).
function dynMember(obj: i32, name: string): i32 {
  const n: Int32Array = obj as unknown as Int32Array;
  const t: i32 = n[0];
  if (t === 6) { // object
    const r: i32 = dynGet(obj, name);
    return r === -1 ? dynUndefined() : r;
  }
  if (t === 5) { // array
    if (strEq(name, "length") === 1) {
      const ln: i32 = dynArrLen(obj);
      return dynNumber(ln);
    }
    return dynUndefined();
  }
  if (t === 4) { // string
    if (strEq(name, "length") === 1) {
      const sl: i32 = n[2];
      return dynNumber(sl);
    }
    return dynUndefined();
  }
  return dynUndefined();
}

// `container[idx]` — array element by numeric index, or object property by string key. Guarded.
function dynIndexValue(container: i32, idxBox: i32): i32 {
  const cn: Int32Array = container as unknown as Int32Array;
  const ct: i32 = cn[0];
  const it: i32 = dynTag(idxBox);
  if (ct === 5) { // array
    if (it === 3) {
      const idxf: f64 = dynNumberValue(idxBox);
      const ii: i32 = idxf as unknown as i32; // truncate toward zero
      const len: i32 = dynArrLen(container);
      if (ii < 0 || ii >= len) return dynUndefined();
      return dynArrGet(container, ii);
    }
    return dynUndefined();
  }
  if (ct === 6) { // object
    if (it === 4) {
      const key: string = boxToStr(idxBox);
      const r: i32 = dynGet(container, key);
      return r === -1 ? dynUndefined() : r;
    }
    return dynUndefined();
  }
  return dynUndefined();
}

// Is `c` a valid identifier-start (A-Za-z_$) or, when `cont` is 1, also a digit?
function isIdentChar(c: i32, cont: i32): i32 {
  if (c >= 65 && c <= 90) return 1;  // A-Z
  if (c >= 97 && c <= 122) return 1; // a-z
  if (c === 95 || c === 36) return 1; // _ $
  if (cont === 1 && c >= 48 && c <= 57) return 1; // 0-9
  return 0;
}

function evalSkipWs(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    if (evalPos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(evalPos);
      if (c === 32 || c === 9 || c === 10 || c === 13) {
        evalPos = evalPos + 1;
      } else {
        go = 0;
      }
    }
  }
}

function evalPeek(s: string): i32 {
  if (evalPos >= s.length) return -1;
  return s.charCodeAt(evalPos);
}

function evalPeek2(s: string): i32 {
  if (evalPos + 1 >= s.length) return -1;
  return s.charCodeAt(evalPos + 1);
}

function parseNumLit(s: string): i32 {
  const start: i32 = evalPos;
  let c: i32 = evalPeek(s);
  while (c >= 48 && c <= 57) {
    evalPos = evalPos + 1;
    c = evalPeek(s);
  }
  if (c === 46) { // '.'
    evalPos = evalPos + 1;
    c = evalPeek(s);
    while (c >= 48 && c <= 57) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
  }
  if (c === 101 || c === 69) { // 'e' / 'E'
    evalPos = evalPos + 1;
    c = evalPeek(s);
    if (c === 43 || c === 45) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
    while (c >= 48 && c <= 57) {
      evalPos = evalPos + 1;
      c = evalPeek(s);
    }
  }
  const tok: string = s.slice(start, evalPos);
  return dynNumber(parseFloat(tok));
}

function parseStringLit(s: string): i32 {
  const quote: i32 = evalPeek(s);
  evalPos = evalPos + 1; // skip opening quote
  let r: string = "";
  let go: i32 = 1;
  while (go === 1) {
    if (evalPos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(evalPos);
      if (c === quote) {
        evalPos = evalPos + 1;
        go = 0;
      } else if (c === 92) { // backslash escape
        evalPos = evalPos + 1;
        const e: i32 = s.charCodeAt(evalPos);
        let d: i32 = e;
        if (e === 110) d = 10;      // \n
        else if (e === 116) d = 9;  // \t
        else if (e === 114) d = 13; // \r
        r = r + String.fromCharCode(d);
        evalPos = evalPos + 1;
      } else {
        r = r + String.fromCharCode(c);
        evalPos = evalPos + 1;
      }
    }
  }
  return dynString(r);
}

function parsePrimary(s: string): i32 {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 40) { // '('
    evalPos = evalPos + 1;
    const v: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 41) evalPos = evalPos + 1; // ')'
    return v;
  }
  if (c === 39 || c === 34) return parseStringLit(s); // ' or "
  if (c >= 48 && c <= 57) return parseNumLit(s);
  if (c === 46) return parseNumLit(s); // .5
  if (isIdentChar(c, 0) === 1) {
    // identifier / keyword: read the full [A-Za-z_$][A-Za-z0-9_$]* run, then dispatch
    const start: i32 = evalPos;
    let ch: i32 = c;
    while (isIdentChar(ch, 1) === 1) {
      evalPos = evalPos + 1;
      ch = evalPeek(s);
    }
    const name: string = s.slice(start, evalPos);
    if (strEq(name, "true") === 1) return dynBool(1);
    if (strEq(name, "false") === 1) return dynBool(0);
    if (strEq(name, "null") === 1) return dynNull();
    if (strEq(name, "undefined") === 1) return dynUndefined();
    // a bare identifier → look it up in the environment object
    if (evalEnv === -1) return dynUndefined();
    const v: i32 = dynGet(evalEnv, name);
    return v === -1 ? dynUndefined() : v;
  }
  return dynUndefined(); // unrecognised → undefined (v1)
}

// Postfix member / index access: `expr.name`, `expr["key"]`, `arr[i]` (binds tighter than unary).
function parsePostfix(s: string): i32 {
  let v: i32 = parsePrimary(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 46) { // .name
      evalPos = evalPos + 1;
      evalSkipWs(s);
      const start: i32 = evalPos;
      let ch: i32 = evalPeek(s);
      while (isIdentChar(ch, 1) === 1) {
        evalPos = evalPos + 1;
        ch = evalPeek(s);
      }
      const name: string = s.slice(start, evalPos);
      v = dynMember(v, name);
    } else if (c === 91) { // [expr]
      evalPos = evalPos + 1;
      const idx: i32 = parseExpr(s);
      evalSkipWs(s);
      if (evalPeek(s) === 93) evalPos = evalPos + 1; // ']'
      v = dynIndexValue(v, idx);
    } else {
      go = 0;
    }
  }
  return v;
}

function parseUnary(s: string): i32 {
  evalSkipWs(s);
  const c: i32 = evalPeek(s);
  if (c === 45) { // -x
    evalPos = evalPos + 1;
    return dynNeg(parseUnary(s));
  }
  if (c === 33) { // !x
    evalPos = evalPos + 1;
    return dynNot(parseUnary(s));
  }
  if (c === 43) { // +x → ToNumber
    evalPos = evalPos + 1;
    const v: i32 = parseUnary(s);
    return dynNumber(dynToNumber(v));
  }
  return parsePostfix(s);
}

function parseMul(s: string): i32 {
  let left: i32 = parseUnary(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 42) { // *
      evalPos = evalPos + 1;
      left = dynMul(left, parseUnary(s));
    } else if (c === 47) { // /
      evalPos = evalPos + 1;
      left = dynDiv(left, parseUnary(s));
    } else if (c === 37) { // %
      evalPos = evalPos + 1;
      left = dynMod(left, parseUnary(s));
    } else {
      go = 0;
    }
  }
  return left;
}

function parseAdd(s: string): i32 {
  let left: i32 = parseMul(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    if (c === 43) { // +
      evalPos = evalPos + 1;
      left = dynAdd(left, parseMul(s));
    } else if (c === 45) { // -
      evalPos = evalPos + 1;
      left = dynSub(left, parseMul(s));
    } else {
      go = 0;
    }
  }
  return left;
}

function parseRel(s: string): i32 {
  let left: i32 = parseAdd(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    const c2: i32 = evalPeek2(s);
    if (c === 60) { // <
      if (c2 === 61) {
        evalPos = evalPos + 2;
        left = dynLe(left, parseAdd(s));
      } else {
        evalPos = evalPos + 1;
        left = dynLt(left, parseAdd(s));
      }
    } else if (c === 62) { // >
      if (c2 === 61) {
        evalPos = evalPos + 2;
        left = dynGe(left, parseAdd(s));
      } else {
        evalPos = evalPos + 1;
        left = dynGt(left, parseAdd(s));
      }
    } else {
      go = 0;
    }
  }
  return left;
}

function parseEq(s: string): i32 {
  let left: i32 = parseRel(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    const c: i32 = evalPeek(s);
    const c2: i32 = evalPeek2(s);
    if (c === 61 && c2 === 61) { // == or ===
      evalPos = evalPos + 2;
      if (evalPeek(s) === 61) evalPos = evalPos + 1; // consume the 3rd '='
      const right: i32 = parseRel(s);
      left = dynBool(dynStrictEq(left, right));
    } else if (c === 33 && c2 === 61) { // != or !==
      evalPos = evalPos + 2;
      if (evalPeek(s) === 61) evalPos = evalPos + 1; // consume the 3rd '='
      const right: i32 = parseRel(s);
      left = dynBool(dynStrictEq(left, right) === 0 ? 1 : 0);
    } else {
      go = 0;
    }
  }
  return left;
}

function parseAnd(s: string): i32 {
  let left: i32 = parseEq(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    if (evalPeek(s) === 38 && evalPeek2(s) === 38) { // &&
      evalPos = evalPos + 2;
      const right: i32 = parseEq(s);
      left = dynToBool(left) === 1 ? right : left; // a && b
    } else {
      go = 0;
    }
  }
  return left;
}

function parseOr(s: string): i32 {
  let left: i32 = parseAnd(s);
  let go: i32 = 1;
  while (go === 1) {
    evalSkipWs(s);
    if (evalPeek(s) === 124 && evalPeek2(s) === 124) { // ||
      evalPos = evalPos + 2;
      const right: i32 = parseAnd(s);
      left = dynToBool(left) === 1 ? left : right; // a || b
    } else {
      go = 0;
    }
  }
  return left;
}

function parseExpr(s: string): i32 {
  const cond: i32 = parseOr(s);
  evalSkipWs(s);
  if (evalPeek(s) === 63) { // ? :
    evalPos = evalPos + 1;
    const thenV: i32 = parseExpr(s);
    evalSkipWs(s);
    if (evalPeek(s) === 58) evalPos = evalPos + 1; // ':'
    const elseV: i32 = parseExpr(s);
    return dynToBool(cond) === 1 ? thenV : elseV;
  }
  return cond;
}

/** Evaluate a JS expression string with no environment → boxed value handle. */
/** @export */
export function dynEval(s: string): i32 {
  evalPos = 0;
  evalEnv = -1;
  return parseExpr(s);
}

/**
 * Evaluate a JS expression string against an environment object (`env`: names → boxed values), so
 * the expression may reference variables and navigate them with `.prop` / `[i]` / `["key"]`.
 */
/** @export */
export function dynEvalEnv(s: string, env: i32): i32 {
  evalPos = 0;
  evalEnv = env;
  return parseExpr(s);
}
