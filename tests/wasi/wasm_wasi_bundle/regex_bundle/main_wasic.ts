// Shared-heap driver for the RegExp stdlib capability (brief §5/§7-#3, fifth/final Tier-1).
//
// Imports the modc-compiled regex matcher. RegExp is a *leaf*: the pattern and text are
// threaded through the recursive matcher as wasic strings (ptr+len) and nothing is copied to
// the heap, so the merge is a straight function splice (allocator unification is a no-op). It
// is still the second capability — after JSON — to take string input across the merge.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module so the `run` step exits non-zero and the test fails. (A wasic
// uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)
//
// NOTE on escaping: `\d` / `\w` / `\s` in a pattern are written `\\d` etc. in the wasic string
// literal (wasic `\\` → one backslash), so the matcher receives a real backslash-letter.

type i32 = number;

import { reTest, reSearch, reEnd } from "./regex_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// ── Literals + unanchored search ─────────────────────────────────────────────
console.log("abc in xabcy:", reTest("abc", "xabcy"));
check(reTest("abc", "xabcy") === 1 ? 1 : 0);
check(reTest("abc", "xyz") === 0 ? 1 : 0);
check(reTest("abc", "ab") === 0 ? 1 : 0); // partial, no full match

// reSearch returns the start; reEnd the end (exclusive).
const s1: i32 = reSearch("cd", "abcdef");
console.log("search cd:", s1, "..", reEnd()); // 2 .. 4
check(s1 === 2 ? 1 : 0);
check(reEnd() === 4 ? 1 : 0);
check(reSearch("zz", "abcdef") === -1 ? 1 : 0);

// ── Anchors ^ and $ ──────────────────────────────────────────────────────────
check(reTest("^abc", "abcdef") === 1 ? 1 : 0);
check(reTest("^abc", "xabc") === 0 ? 1 : 0);
check(reTest("abc$", "xxabc") === 1 ? 1 : 0);
check(reTest("abc$", "abcx") === 0 ? 1 : 0);
check(reTest("^abc$", "abc") === 1 ? 1 : 0);
check(reTest("^abc$", "abcd") === 0 ? 1 : 0);

// ── Dot (any char) ───────────────────────────────────────────────────────────
check(reTest("a.c", "axc") === 1 ? 1 : 0);
check(reTest("a.c", "abc") === 1 ? 1 : 0);
check(reTest("a.c", "ac") === 0 ? 1 : 0); // dot needs one char

// ── Quantifiers * + ? ────────────────────────────────────────────────────────
check(reTest("ab*c", "ac") === 1 ? 1 : 0);    // zero b
check(reTest("ab*c", "abbbc") === 1 ? 1 : 0); // many b
check(reTest("ab+c", "ac") === 0 ? 1 : 0);    // + needs ≥1
check(reTest("ab+c", "abc") === 1 ? 1 : 0);
check(reTest("ab+c", "abbbc") === 1 ? 1 : 0);
check(reTest("ab?c", "ac") === 1 ? 1 : 0);    // zero
check(reTest("ab?c", "abc") === 1 ? 1 : 0);   // one
check(reTest("ab?c", "abbc") === 0 ? 1 : 0);  // two → no

// ── Character classes (ranges, negation) ─────────────────────────────────────
const s2: i32 = reSearch("[0-9]+", "abc123def");
console.log("digits:", s2, "..", reEnd()); // 3 .. 6
check(s2 === 3 ? 1 : 0);
check(reEnd() === 6 ? 1 : 0);
check(reTest("[A-Z]", "hello") === 0 ? 1 : 0);
check(reTest("[A-Z]", "heLlo") === 1 ? 1 : 0);
check(reTest("[^0-9]", "12345") === 0 ? 1 : 0); // all digits → negated class never matches
check(reTest("[^0-9]", "12a45") === 1 ? 1 : 0);
check(reTest("[abc]+", "xxcabbz") === 1 ? 1 : 0);

// ── Escape shorthands \d \w \s ───────────────────────────────────────────────
const s3: i32 = reSearch("\\d+", "price=42usd");
console.log("\\d+:", s3, "..", reEnd()); // 6 .. 8
check(s3 === 6 ? 1 : 0);
check(reEnd() === 8 ? 1 : 0);
check(reTest("\\d", "abc") === 0 ? 1 : 0);
check(reTest("\\w+", "  hi_there ") === 1 ? 1 : 0);
check(reSearch("\\s", "ab cd") === 2 ? 1 : 0);
check(reTest("\\D+", "123") === 0 ? 1 : 0);

// ── A small "realistic" pattern: word@word ───────────────────────────────────
const s4: i32 = reSearch("\\w+@\\w+", "contact me at bob@acme now");
console.log("email-ish:", s4, "..", reEnd()); // 14 .. 22 ("bob@acme")
check(s4 === 14 ? 1 : 0);
check(reEnd() === 22 ? 1 : 0);

console.log("regex ok");
