// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.7: RegExp in eval source. A
// compact backtracking matcher: literals, `.`, quantifiers `*`/`+`/`?` (greedy), anchors `^`/`$`,
// character classes `[…]`/`[^…]` with ranges. `new RegExp(pat)` builds it; `re.test(str)` → bool,
// `re.exec(str)` / `str.match(re)` → first matched substring (or null). Patterns are written in
// SINGLE-quoted eval-source strings; character classes ([0-9] etc.) stand in for \d/\w to avoid
// backslash-escape ambiguity at the TS→eval-source boundary.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the RegExp surface.

type i32 = number;
type f64 = number;

import { dynNumberValue, dynObject, dynRun, dynTypeof } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

function checkRun(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0); // result must be a number
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── literals + `.` ───────────────────────────────────────────────────────────────────────────────
checkRun("const re = new RegExp('abc'); return re.test('xabcy') ? 1 : 0;", 1);
checkRun("const re = new RegExp('abc'); return re.test('xyz') ? 1 : 0;", 0);
checkRun("const re = new RegExp('a.c'); return re.test('axc') ? 1 : 0;", 1);

// ── quantifiers * + ? ────────────────────────────────────────────────────────────────────────────
checkRun("const re = new RegExp('ab*c'); return re.test('ac') ? 1 : 0;", 1);
checkRun("const re = new RegExp('ab*c'); return re.test('abbbc') ? 1 : 0;", 1);
checkRun("const re = new RegExp('ab+c'); return re.test('ac') ? 1 : 0;", 0);
checkRun("const re = new RegExp('ab+c'); return re.test('abc') ? 1 : 0;", 1);
checkRun("const re = new RegExp('ab?c'); return re.test('ac') ? 1 : 0;", 1);
checkRun("const re = new RegExp('ab?c'); return re.test('abbc') ? 1 : 0;", 0);

// ── anchors ^ $ ──────────────────────────────────────────────────────────────────────────────────
checkRun("const re = new RegExp('^abc'); return re.test('abcx') ? 1 : 0;", 1);
checkRun("const re = new RegExp('^abc'); return re.test('xabc') ? 1 : 0;", 0);
checkRun("const re = new RegExp('abc$'); return re.test('xabc') ? 1 : 0;", 1);
checkRun("const re = new RegExp('abc$'); return re.test('abcx') ? 1 : 0;", 0);

// ── character classes [..] / ranges / negation ───────────────────────────────────────────────────
checkRun("const re = new RegExp('[abc]'); return re.test('xbz') ? 1 : 0;", 1);
checkRun("const re = new RegExp('[0-9]'); return re.test('a5b') ? 1 : 0;", 1);
checkRun("const re = new RegExp('[^0-9]'); return re.test('abc') ? 1 : 0;", 1);
checkRun("const re = new RegExp('[0-9]+'); return re.test('xx42xx') ? 1 : 0;", 1);

// ── exec / str.match → first matched substring (or null) ─────────────────────────────────────────
checkRun("const re = new RegExp('[0-9]+'); const m = re.exec('abc123def'); return m.length;", 3);
checkRun("const m = 'hello42world'.match(new RegExp('[0-9]+')); return m.length;", 2);
checkRun("const m = 'abc'.match(new RegExp('[0-9]+')); return m === null ? 1 : 0;", 1);

console.log("dynrt 2f.7 regexp: all checks passed");
