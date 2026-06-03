// Tier-1 stdlib capability — RegExp (a backtracking matcher) as a modc *leaf* library.
//
// Part of the on-demand stdlib bundling track (wasmtk-stdlib-bundling-brief §5/§7-#3, the
// fifth and final Tier-1 capability). Like Date, RegExp is a *leaf*: value-in / value-out,
// no heap allocation and no persistent structure. The pattern and text are threaded — as
// wasic `string` params (ptr+len) — through the recursive matcher; nothing is copied to the
// heap, so the wasmmerge allocator-unification pass is a no-op and the merge is a straight
// function splice.
//
// ENGINE
// ------
// A classic recursive backtracking matcher (Kernighan/Pike style), generalised from the
// null-terminated original to index-based scanning over two `(string, index)` pairs. An
// "atom" is one matchable unit — a literal char, `.`, an escape (`\d \w \s \D \W \S \n \t
// \r` or an escaped literal), or a bracket class `[...]` (with `a-z` ranges, `^` negation,
// and `\d \w \s` inside). An atom may be followed by a quantifier `*` `+` `?`. Anchors `^`
// (start) and `$` (end) are supported. `matchHere` returns the text index just past the
// match (so the caller can recover the matched span), or -1 on failure.
//
// SHORT-CIRCUIT `&&` / `||` (see CLAUDE.md/cmem § "RegExp / merge OOB-charCodeAt bug")
// ------------------------------------------------------------------------------------
// wasic emits `a && b` / `a || b` as SHORT-CIRCUIT control flow (an `(if (result i32) …)`
// that skips the RHS once the LHS decides the result) — matching JavaScript semantics. So a
// condition like `i < s.length && s.charCodeAt(i) === C` does NOT evaluate `charCodeAt(i)`
// when `i >= length`; the bounds guard and the access compose naturally in one expression,
// even inside a loop's `br_if`. (Historically wasic emitted a NON-short-circuit `i32.and`
// that always evaluated both sides; an out-of-bounds `charCodeAt` nested in that `i32.and`
// inside a loop `br_if` was mis-encoded by the wasmmerge splice and trapped after bundling.
// That whole bug class is gone now that `&&`/`||` short-circuit — see the matcher below,
// which relies on it directly in `atomAt` and `matchStar`.)
//
// SCOPE (v1): literals, `.`, char classes `[...]` (ranges, negation, `\d \w \s`), the
// escapes above, quantifiers `* + ?`, and anchors `^ $`. NOT in v1 (documented v2 gap):
// alternation `|`, groups `(...)` and captures, counted quantifiers `{n,m}`, lazy
// quantifiers (`*?`), and backreferences. Greedy quantifiers backtrack correctly; this is
// leftmost-match semantics (the first start position that matches wins).

type i32 = number;

// End text index (exclusive) of the most recent reSearch match — the second return value
// the subset can't express directly. Read via reEnd() right after reSearch()/reTest().
let lastEnd: i32 = 0;

/** 1 if char code `c` is a word char (alnum or underscore), else 0. */
function isWord(c: i32): i32 {
  if (c >= 48 && c <= 57) return 1;  // 0-9
  if (c >= 65 && c <= 90) return 1;  // A-Z
  if (c >= 97 && c <= 122) return 1; // a-z
  if (c === 95) return 1;            // _
  return 0;
}

/** 1 if char code `c` is whitespace, else 0. */
function isSpace(c: i32): i32 {
  if (c === 32 || c === 9 || c === 10 || c === 13 || c === 12 || c === 11) return 1;
  return 0;
}

/** Number of pattern chars in the atom starting at `pi`. */
function atomLen(p: string, pi: i32): i32 {
  const c: i32 = p.charCodeAt(pi);
  if (c === 92) return 2; // backslash + escaped char
  if (c === 91) {         // '[' — scan to matching ']'
    let j: i32 = pi + 1;
    if (j < p.length) {
      if (p.charCodeAt(j) === 94) j = j + 1; // leading ^
    }
    let go: i32 = 1;
    while (go === 1) {
      if (j >= p.length) {
        go = 0;
      } else if (p.charCodeAt(j) === 93) {
        go = 0;
      } else if (p.charCodeAt(j) === 92) {
        j = j + 2; // skip escaped char inside class
      } else {
        j = j + 1;
      }
    }
    return (j - pi) + 1; // include the ']'
  }
  return 1;
}

/** 1 if text char code `c` is matched by the bracket class atom at `pi`, else 0. */
function classMatches(p: string, pi: i32, c: i32): i32 {
  let j: i32 = pi + 1;
  let neg: i32 = 0;
  if (j < p.length) {
    if (p.charCodeAt(j) === 94) { neg = 1; j = j + 1; }
  }
  let found: i32 = 0;
  let go: i32 = 1;
  while (go === 1) {
    if (j >= p.length) {
      go = 0;
    } else if (p.charCodeAt(j) === 93) {
      go = 0;
    } else {
      const lo: i32 = p.charCodeAt(j);
      if (lo === 92 && j + 1 < p.length) {
        // Escape inside the class: \d \w \s or an escaped literal.
        const e: i32 = p.charCodeAt(j + 1);
        if (e === 100) { if (c >= 48 && c <= 57) found = 1; }
        else if (e === 119) { if (isWord(c) === 1) found = 1; }
        else if (e === 115) { if (isSpace(c) === 1) found = 1; }
        else { if (c === e) found = 1; }
        j = j + 2;
      } else {
        // Range lo-hi? Only when a '-' follows and a non-']' char follows that.
        let isRange: i32 = 0;
        if (j + 2 < p.length) {
          if (p.charCodeAt(j + 1) === 45) {
            if (p.charCodeAt(j + 2) !== 93) isRange = 1;
          }
        }
        if (isRange === 1) {
          const hi: i32 = p.charCodeAt(j + 2);
          if (c >= lo && c <= hi) found = 1;
          j = j + 3;
        } else {
          if (c === lo) found = 1;
          j = j + 1;
        }
      }
    }
  }
  if (neg === 1) return found === 1 ? 0 : 1;
  return found;
}

/** 1 if text char code `c` matches the atom at pattern index `pi`, else 0. */
function atomMatches(p: string, pi: i32, c: i32): i32 {
  const pc: i32 = p.charCodeAt(pi);
  if (pc === 46) return 1; // '.' matches any char
  if (pc === 92) {
    const e: i32 = p.charCodeAt(pi + 1);
    if (e === 100) return (c >= 48 && c <= 57) ? 1 : 0;   // \d
    if (e === 68) return (c >= 48 && c <= 57) ? 0 : 1;     // \D
    if (e === 119) return isWord(c);                       // \w
    if (e === 87) return isWord(c) === 1 ? 0 : 1;          // \W
    if (e === 115) return isSpace(c);                      // \s
    if (e === 83) return isSpace(c) === 1 ? 0 : 1;         // \S
    if (e === 110) return c === 10 ? 1 : 0;                // \n
    if (e === 116) return c === 9 ? 1 : 0;                 // \t
    if (e === 114) return c === 13 ? 1 : 0;                // \r
    return c === e ? 1 : 0;                                // escaped literal
  }
  if (pc === 91) return classMatches(p, pi, c);            // [...]
  return c === pc ? 1 : 0;                                 // literal
}

/** 1 if the atom at `pi` matches the text char at `ti` (bounds-checked), else 0. */
function atomAt(p: string, t: string, pi: i32, ti: i32): i32 {
  // Short-circuit `&&`: when `ti >= t.length` the RHS `charCodeAt(ti)` is never evaluated.
  return ti < t.length && atomMatches(p, pi, t.charCodeAt(ti)) === 1 ? 1 : 0;
}

/**
 * Greedy `atom{minCount,}` against `rest` of pattern. Consumes as many atom matches as
 * possible from `ti`, then backtracks down to `minCount`. Returns the end text index of a
 * full match, or -1.
 */
function matchStar(p: string, t: string, atomPi: i32, restPi: i32, ti: i32, minCount: i32): i32 {
  // Consume as many atom matches as possible. The bounds guard and the (function-wrapped)
  // `charCodeAt` compose in one short-circuit `&&` directly in the loop's `br_if` — the exact
  // construct that historically trapped after the wasmmerge splice and now works because
  // wasic short-circuits `&&` (the RHS atom test is skipped once `ti + count >= t.length`).
  let count: i32 = 0;
  while (ti + count < t.length && atomMatches(p, atomPi, t.charCodeAt(ti + count)) === 1) {
    count = count + 1;
  }
  let k: i32 = count;
  while (k >= minCount) {
    const e: i32 = matchHere(p, t, restPi, ti + k);
    if (e >= 0) return e;
    k = k - 1;
  }
  return -1;
}

/** Match the pattern from `pi` against the text at `ti`. Returns the end text index, or -1. */
function matchHere(p: string, t: string, pi: i32, ti: i32): i32 {
  if (pi >= p.length) return ti; // whole pattern consumed → match ends here
  const pc0: i32 = p.charCodeAt(pi);
  // '$' end anchor (only when it is the final pattern char).
  if (pc0 === 36 && pi + 1 >= p.length) {
    return ti >= t.length ? ti : -1;
  }
  const al: i32 = atomLen(p, pi);
  const nextPi: i32 = pi + al;
  let quant: i32 = 0;
  if (nextPi < p.length) {
    const q: i32 = p.charCodeAt(nextPi);
    if (q === 42 || q === 43 || q === 63) quant = q;
  }
  if (quant === 42) return matchStar(p, t, pi, nextPi + 1, ti, 0); // '*'
  if (quant === 43) return matchStar(p, t, pi, nextPi + 1, ti, 1); // '+'
  if (quant === 63) {                                              // '?'
    if (atomAt(p, t, pi, ti) === 1) {
      const e: i32 = matchHere(p, t, nextPi + 1, ti + 1);
      if (e >= 0) return e;
    }
    return matchHere(p, t, nextPi + 1, ti); // the zero branch
  }
  // No quantifier: the atom must match exactly one char.
  if (atomAt(p, t, pi, ti) === 1) {
    return matchHere(p, t, nextPi, ti + 1);
  }
  return -1;
}

/** Internal: first matching start index (sets lastEnd to the match end), or -1. */
function reFind(p: string, t: string): i32 {
  let pstart: i32 = 0;
  let anchored: i32 = 0;
  if (p.length > 0) {
    if (p.charCodeAt(0) === 94) { anchored = 1; pstart = 1; } // '^'
  }
  let ti: i32 = 0;
  let result: i32 = -1;
  let done: i32 = 0;
  while (done === 0) {
    const e: i32 = matchHere(p, t, pstart, ti);
    if (e >= 0) {
      lastEnd = e;
      result = ti;
      done = 1;
    } else if (anchored === 1) {
      done = 1;            // '^' restricts the start to ti == 0
    } else if (ti >= t.length) {
      done = 1;
    } else {
      ti = ti + 1;
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/** 1 if `pattern` matches anywhere in `text`, else 0. Like `/pattern/.test(text)`. */
/** @export */
export function reTest(pattern: string, text: string): i32 {
  return reFind(pattern, text) >= 0 ? 1 : 0;
}

/** Start index of the first match of `pattern` in `text`, or -1. Sets the reEnd() value. */
/** @export */
export function reSearch(pattern: string, text: string): i32 {
  return reFind(pattern, text);
}

/** End index (exclusive) of the most recent reSearch()/reTest() match. */
/** @export */
export function reEnd(): i32 {
  return lastEnd;
}
