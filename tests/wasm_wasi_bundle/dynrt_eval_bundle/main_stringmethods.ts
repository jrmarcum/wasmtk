// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.3: built-in STRING METHODS in eval
// source. `charAt`/`charCodeAt`/`toUpperCase`/`toLowerCase`/`trim`/`slice`/`indexOf`/`includes`/
// `startsWith`/`endsWith`/`repeat`/`padStart`/`padEnd`/`concat`/`split`. Dispatched in parsePostfix when
// the receiver is a tag-4 string; the dynrt string is unboxed to a wasic `string` and the compiler's own
// string ops do the work. String results re-box (so methods chain). `.length` was already supported.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the string-method surface.

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

// ── charCodeAt / charAt (chained) ────────────────────────────────────────────────────────────────
checkRun("return \"A\".charCodeAt(0);", 65);
checkRun("return \"hello\".charAt(1).charCodeAt(0);", 101);

// ── case + trim + length ─────────────────────────────────────────────────────────────────────────
checkRun("return \"abc\".toUpperCase().charCodeAt(0);", 65);
checkRun("return \"XYZ\".toLowerCase().charCodeAt(2);", 122);
checkRun("return \"  hi  \".trim().length;", 2);
checkRun("return \"hello\".length;", 5);

// ── slice (positive + negative) ──────────────────────────────────────────────────────────────────
checkRun("return \"hello\".slice(1, 4).length;", 3);
checkRun("return \"hello\".slice(-2).charCodeAt(0);", 108);

// ── indexOf / includes / startsWith / endsWith ───────────────────────────────────────────────────
checkRun("return \"hello\".indexOf(\"ll\");", 2);
checkRun("return \"hello\".indexOf(\"z\");", -1);
checkRun("return \"hello\".includes(\"ell\") ? 100 : 200;", 100);
checkRun("return \"hello\".startsWith(\"he\") ? 1 : 0;", 1);
checkRun("return \"hello\".endsWith(\"xo\") ? 1 : 0;", 0);

// ── repeat / pad / concat ────────────────────────────────────────────────────────────────────────
checkRun("return \"ab\".repeat(3).length;", 6);
checkRun("return \"5\".padStart(3, \"0\").charCodeAt(0);", 48);
checkRun("return \"5\".padEnd(3, \"x\").length;", 3);
checkRun("return \"ab\".concat(\"cde\").length;", 5);

// ── split (count + element) + chaining ───────────────────────────────────────────────────────────
checkRun("return \"a,b,c\".split(\",\").length;", 3);
checkRun("return \"x,y,z\".split(\",\")[1].charCodeAt(0);", 121);
checkRun("return \"Hello World\".toLowerCase().split(\" \").length;", 2);

console.log("dynrt 2f.3 string methods: all checks passed");
