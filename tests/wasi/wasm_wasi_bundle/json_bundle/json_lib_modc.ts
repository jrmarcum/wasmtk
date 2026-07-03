// Tier-1 stdlib capability — JSON (parse + navigate) as a shared-heap modc library.
//
// Part of the on-demand stdlib bundling track (wasmtk-stdlib-bundling-brief §5/§7-#3).
// Compiled with `wasmtk modc` (no _start / no WASI); a wasic program imports the exports
// and the wasmmerge allocator-unification pass (Stage 0.6) makes every $__malloc here
// resolve to the host module's shared bump cursor, so the parsed value tree lives on the
// ONE heap shared with the importing program. This is the headline case for JSON: a wasic
// program (which has no native JSON) gains JSON.parse + navigation by merging this module.
//
// THE VALUE TREE
// --------------
// Every JSON value is an i32 handle = the base pointer of a 4-slot Int32Array node:
//   node[0] tag : 0=null 1=bool 2=number(int) 3=string 4=array 5=object
//   node[1] a   : bool→0/1 · number→int value · string→byte-buffer ptr ·
//                 array→i32[] of child handles · object→i32[] of value handles
//   node[2] b   : string→byte length · array→length · object→entry count
//   node[3] c   : object→i32[] of interleaved [keyPtr, keyLen] pairs (length 2*count)
//
// Containers reuse wasic's native dynamic `i32[]` (header [len,cap] + elems): a built array
// is stored by its pointer (`arr as unknown as i32`) and later reconstructed for indexing /
// .length (`ptr as unknown as i32[]`). String values are decoded into a `Uint8Array` and
// addressed by char index — so no raw `__malloc` and no raw string-ptr exposure is needed;
// every access stays inside the proven TypedArray-view-over-pointer / dynamic-array idioms.
//
// PARSER
// ------
// Recursive descent. The input string `s` is threaded into every parse function; a single
// module-level cursor `pos` (mutable global) marks the read position, and `lastLen` carries
// the byte length back from string parsing (a second return value the subset can't express
// directly). `s.charCodeAt(pos)` reads the current byte.
//
// SCOPE (v1): null, bool, integer numbers, strings, arrays, objects. Numbers are parsed into
// an i32 (any fractional / exponent tail is consumed but truncated). String escapes handled:
// \" \\ \/ \b \f \n \r \t; `\uXXXX` is NOT decoded (the backslash is dropped and the four hex
// digits pass through literally). Floating-point numbers and `\u` are the documented v2 gap,
// mirroring how Set<i32> / Map<i32,i32> scoped to integer keys first.

type i32 = number;

// ── Parser state (module-level mutable globals) ──────────────────────────────
let pos: i32 = 0;     // current read offset into the source string
let lastLen: i32 = 0; // byte length of the most recently parsed string

// ── Node constructors for the leaf values ────────────────────────────────────
function mkNull(): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 0;
  return n as unknown as i32;
}

function mkBool(b: i32): i32 {
  const n: Int32Array = new Int32Array(4);
  n[0] = 1;
  n[1] = b;
  return n as unknown as i32;
}

// ── Whitespace ───────────────────────────────────────────────────────────────
function skipWs(s: string): void {
  let go: i32 = 1;
  while (go === 1) {
    if (pos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(pos);
      if (c === 32 || c === 9 || c === 10 || c === 13) {
        pos = pos + 1;
      } else {
        go = 0;
      }
    }
  }
}

// ── String content → Uint8Array; returns buffer ptr, sets `lastLen` ──────────
// On entry `pos` is at the opening quote. On exit `pos` is just past the closing quote.
function parseStringRaw(s: string): i32 {
  pos = pos + 1; // skip opening quote
  const contentStart: i32 = pos;

  // Pass 1: find the closing quote (honouring backslash escapes).
  let scan: i32 = 1;
  while (scan === 1) {
    if (pos >= s.length) {
      scan = 0;
    } else {
      const c: i32 = s.charCodeAt(pos);
      if (c === 92) {
        pos = pos + 2; // skip backslash + escaped char
      } else if (c === 34) {
        scan = 0; // pos now at closing quote
      } else {
        pos = pos + 1;
      }
    }
  }
  const endPos: i32 = pos;
  const rawLen: i32 = endPos - contentStart; // worst-case decoded length

  // Pass 2: decode escapes into a fresh byte buffer.
  const buf: Uint8Array = new Uint8Array(rawLen);
  let j: i32 = 0;
  let k: i32 = contentStart;
  while (k < endPos) {
    let c: i32 = s.charCodeAt(k);
    if (c === 92) {
      k = k + 1;
      const e: i32 = s.charCodeAt(k);
      if (e === 110) c = 10;        // \n
      else if (e === 116) c = 9;    // \t
      else if (e === 114) c = 13;   // \r
      else if (e === 98) c = 8;     // \b
      else if (e === 102) c = 12;   // \f
      else if (e === 34) c = 34;    // \"
      else if (e === 92) c = 92;    // \\
      else if (e === 47) c = 47;    // \/
      else c = e;                   // unknown (incl. \u): literal passthrough
    }
    buf[j] = c;
    j = j + 1;
    k = k + 1;
  }

  pos = endPos + 1; // skip closing quote
  lastLen = j;
  return buf as unknown as i32;
}

function parseString(s: string): i32 {
  const ptr: i32 = parseStringRaw(s);
  const n: Int32Array = new Int32Array(4);
  n[0] = 3;
  n[1] = ptr;
  n[2] = lastLen;
  return n as unknown as i32;
}

// ── Number (integer; fractional / exponent tail consumed but truncated) ──────
function parseNumber(s: string): i32 {
  let neg: i32 = 0;
  if (s.charCodeAt(pos) === 45) { // '-'
    neg = 1;
    pos = pos + 1;
  }
  let val: i32 = 0;
  let go: i32 = 1;
  while (go === 1) {
    if (pos >= s.length) {
      go = 0;
    } else {
      const c: i32 = s.charCodeAt(pos);
      if (c < 48 || c > 57) {
        go = 0;
      } else {
        val = val * 10 + (c - 48);
        pos = pos + 1;
      }
    }
  }
  // Consume a fractional part (digits truncated in v1 integer JSON).
  if (pos < s.length && s.charCodeAt(pos) === 46) { // '.'
    pos = pos + 1;
    let gf: i32 = 1;
    while (gf === 1) {
      if (pos >= s.length) gf = 0;
      else {
        const c2: i32 = s.charCodeAt(pos);
        if (c2 < 48 || c2 > 57) gf = 0;
        else pos = pos + 1;
      }
    }
  }
  // Consume an exponent part.
  if (pos < s.length) {
    const ec: i32 = s.charCodeAt(pos);
    if (ec === 101 || ec === 69) { // 'e' / 'E'
      pos = pos + 1;
      if (pos < s.length) {
        const sgn: i32 = s.charCodeAt(pos);
        if (sgn === 43 || sgn === 45) pos = pos + 1;
      }
      let ge: i32 = 1;
      while (ge === 1) {
        if (pos >= s.length) ge = 0;
        else {
          const c3: i32 = s.charCodeAt(pos);
          if (c3 < 48 || c3 > 57) ge = 0;
          else pos = pos + 1;
        }
      }
    }
  }
  if (neg === 1) val = 0 - val;
  const n: Int32Array = new Int32Array(4);
  n[0] = 2;
  n[1] = val;
  return n as unknown as i32;
}

// ── Array ────────────────────────────────────────────────────────────────────
function parseArray(s: string): i32 {
  pos = pos + 1; // skip '['
  const elems: i32[] = [];
  skipWs(s);
  if (s.charCodeAt(pos) === 93) { // ']'
    pos = pos + 1;
  } else {
    let done: i32 = 0;
    while (done === 0) {
      skipWs(s);
      const child: i32 = parseValue(s);
      elems.push(child);
      skipWs(s);
      const c: i32 = s.charCodeAt(pos);
      if (c === 44) { // ','
        pos = pos + 1;
      } else {
        if (c === 93) pos = pos + 1; // ']'
        done = 1;
      }
    }
  }
  const ePtr: i32 = elems as unknown as i32;
  const n: Int32Array = new Int32Array(4);
  n[0] = 4;
  n[1] = ePtr;
  n[2] = elems.length;
  return n as unknown as i32;
}

// ── Object ───────────────────────────────────────────────────────────────────
function parseObject(s: string): i32 {
  pos = pos + 1; // skip '{'
  const vals: i32[] = [];
  const keys: i32[] = [];
  skipWs(s);
  if (s.charCodeAt(pos) === 125) { // '}'
    pos = pos + 1;
  } else {
    let done: i32 = 0;
    while (done === 0) {
      skipWs(s);
      const kptr: i32 = parseStringRaw(s);
      const klen: i32 = lastLen;
      keys.push(kptr);
      keys.push(klen);
      skipWs(s);
      if (s.charCodeAt(pos) === 58) pos = pos + 1; // ':'
      skipWs(s);
      const v: i32 = parseValue(s);
      vals.push(v);
      skipWs(s);
      const c: i32 = s.charCodeAt(pos);
      if (c === 44) { // ','
        pos = pos + 1;
      } else {
        if (c === 125) pos = pos + 1; // '}'
        done = 1;
      }
    }
  }
  const vPtr: i32 = vals as unknown as i32;
  const kPtr: i32 = keys as unknown as i32;
  const n: Int32Array = new Int32Array(4);
  n[0] = 5;
  n[1] = vPtr;
  n[2] = vals.length;
  n[3] = kPtr;
  return n as unknown as i32;
}

// ── Value dispatch ───────────────────────────────────────────────────────────
function parseValue(s: string): i32 {
  skipWs(s);
  const c: i32 = s.charCodeAt(pos);
  if (c === 123) return parseObject(s); // '{'
  if (c === 91) return parseArray(s);   // '['
  if (c === 34) return parseString(s);  // '"'
  if (c === 116) { pos = pos + 4; return mkBool(1); } // true
  if (c === 102) { pos = pos + 5; return mkBool(0); } // false
  if (c === 110) { pos = pos + 4; return mkNull(); }  // null
  return parseNumber(s);                                // number ('-' or digit)
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/** Parse a JSON document; returns the root value handle. */
/** @export */
export function jsonParse(s: string): i32 {
  pos = 0;
  return parseValue(s);
}

/** Value tag: 0=null 1=bool 2=number 3=string 4=array 5=object. */
/** @export */
export function jsonType(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  return n[0];
}

/** Integer value of a number node. */
/** @export */
export function jsonInt(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  return n[1];
}

/** 0/1 value of a bool node. */
/** @export */
export function jsonBool(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  return n[1];
}

/** Element count of an array node. */
/** @export */
export function jsonArrayLen(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  const p: i32 = n[1];
  const a: i32[] = p as unknown as i32[];
  return a.length;
}

/** Child handle at index `i` of an array node. */
/** @export */
export function jsonArrayGet(node: i32, i: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  const p: i32 = n[1];
  const a: i32[] = p as unknown as i32[];
  return a[i];
}

/** Entry count of an object node. */
/** @export */
export function jsonObjectLen(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  return n[2];
}

/** Byte length of a string node. */
/** @export */
export function jsonStrLen(node: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  return n[2];
}

/** Byte (char code) at index `i` of a string node. */
/** @export */
export function jsonStrCharAt(node: i32, i: i32): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  const p: i32 = n[1];
  const v: Uint8Array = p as unknown as Uint8Array;
  return v[i];
}

/** 1 if the string node equals `t` byte-for-byte, else 0. */
/** @export */
export function jsonStrEq(node: i32, t: string): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  if (n[0] !== 3) return 0;
  const len: i32 = n[2];
  if (len !== t.length) return 0;
  const p: i32 = n[1];
  const v: Uint8Array = p as unknown as Uint8Array;
  let i: i32 = 0;
  while (i < len) {
    if (v[i] !== t.charCodeAt(i)) return 0;
    i = i + 1;
  }
  return 1;
}

/** Look up `key` in an object node; returns the value handle, or -1 if absent. */
/** @export */
export function jsonGet(node: i32, key: string): i32 {
  const n: Int32Array = node as unknown as Int32Array;
  if (n[0] !== 5) return -1;
  const count: i32 = n[2];
  const vp: i32 = n[1];
  const kp: i32 = n[3];
  const vals: i32[] = vp as unknown as i32[];
  const keys: i32[] = kp as unknown as i32[];
  const klen: i32 = key.length;
  let i: i32 = 0;
  while (i < count) {
    const kptr: i32 = keys[i * 2];
    const kl: i32 = keys[i * 2 + 1];
    if (kl === klen) {
      const kv: Uint8Array = kptr as unknown as Uint8Array;
      let eq: i32 = 1;
      let j: i32 = 0;
      while (j < kl) {
        if (kv[j] !== key.charCodeAt(j)) {
          eq = 0;
          j = kl; // break
        } else {
          j = j + 1;
        }
      }
      if (eq === 1) return vals[i];
    }
    i = i + 1;
  }
  return -1;
}

/** 1 if an object node contains `key`, else 0. */
/** @export */
export function jsonHas(node: i32, key: string): i32 {
  return jsonGet(node, key) === -1 ? 0 : 1;
}
