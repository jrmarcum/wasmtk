// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.2: built-in ARRAY METHODS in eval
// source. `arr.push/indexOf/includes/join/slice/concat/reverse` plus the callback methods
// `map/filter/forEach/reduce` (callback invoked with element + index). Dispatched in parsePostfix when
// the receiver is an array and the member isn't a user function; methods chain (filter().map()).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the array-method surface.

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

// ── push (mutates + returns new length) ──────────────────────────────────────────────────────────
checkRun("const a = [1, 2, 3]; a.push(4); a.push(5); return a.length;", 5);
checkRun("const a = [1, 2]; return a.push(9);", 3);

// ── indexOf / includes ───────────────────────────────────────────────────────────────────────────
checkRun("const a = [10, 20, 30]; return a.indexOf(20);", 1);
checkRun("const a = [10, 20, 30]; return a.indexOf(99);", -1);
checkRun("const a = [1, 2, 3]; return a.includes(2) ? 100 : 200;", 100);
checkRun("const a = [1, 2, 3]; return a.includes(9) ? 100 : 200;", 200);

// ── slice / concat / reverse ─────────────────────────────────────────────────────────────────────
checkRun("const a = [1, 2, 3, 4, 5]; const b = a.slice(1, 4); return b.length * 100 + b[0] * 10 + b[2];", 324);
checkRun("const a = [1, 2]; const b = a.concat([3, 4], 5); return b.length * 100 + b[2] * 10 + b[4];", 535);
checkRun("const a = [1, 2, 3]; const b = a.reverse(); return b[0] * 100 + b[1] * 10 + b[2];", 321);

// ── join (string result → check its length) ──────────────────────────────────────────────────────
checkRun("const s = [1, 2, 3].join(\"-\"); return s.length;", 5);

// ── map / filter / forEach / reduce ──────────────────────────────────────────────────────────────
checkRun("const a = [1, 2, 3]; const b = a.map((x) => x * 10); return b[0] + b[1] + b[2];", 60);
checkRun("const a = [10, 20, 30]; const b = a.map((x, i) => x + i); return b[0] + b[1] + b[2];", 63);
checkRun("const a = [1, 2, 3, 4, 5, 6]; const b = a.filter((x) => x > 3); return b.length * 100 + b[0];", 304);
checkRun("let sum = 0; const a = [1, 2, 3, 4]; a.forEach((x) => { sum = sum + x; }); return sum;", 10);
checkRun("const a = [1, 2, 3, 4]; return a.reduce((acc, x) => acc + x, 0);", 10);
checkRun("const a = [5, 10, 15]; return a.reduce((acc, x) => acc + x);", 30);

// ── chained methods ──────────────────────────────────────────────────────────────────────────────
checkRun("const a = [1, 2, 3, 4, 5]; const b = a.filter((x) => x > 2).map((x) => x * 2); return b[0] + b[1] + b[2];", 24);

// ── 2f.2 completion: pop / shift / unshift / at / lastIndexOf ─────────────────────────────────────
checkRun("const a = [1, 2, 3]; const x = a.pop(); return x * 10 + a.length;", 32);
checkRun("const a = [5, 6, 7]; const x = a.shift(); return x * 100 + a.length * 10 + a[0];", 526);
checkRun("const a = [3, 4]; const n = a.unshift(1, 2); return n * 100 + a[0] * 10 + a[3];", 414);
checkRun("const a = [10, 20, 30]; return a.at(1) * 10 + a.at(-1);", 230);
checkRun("const a = [1, 2, 3, 2, 1]; return a.lastIndexOf(2);", 3);

// ── 2f.2 completion: find / findIndex / some / every ─────────────────────────────────────────────
checkRun("const a = [1, 2, 3, 4]; return a.find((x) => x > 2);", 3);
checkRun("const a = [5, 10, 15]; return a.findIndex((x) => x === 10);", 1);
checkRun("const a = [1, 2, 3]; return a.some((x) => x > 2) ? 100 : 200;", 100);
checkRun("const a = [2, 4, 6]; return a.every((x) => x > 1) ? 100 : 200;", 100);
checkRun("const a = [2, 4, 6]; return a.every((x) => x > 3) ? 100 : 200;", 200);

// ── 2f.2 completion: sort (numeric default + comparator) ─────────────────────────────────────────
checkRun("const a = [3, 1, 2]; a.sort(); return a[0] * 100 + a[1] * 10 + a[2];", 123);
checkRun("const a = [1, 3, 2]; a.sort((x, y) => y - x); return a[0] * 100 + a[1] * 10 + a[2];", 321);

console.log("dynrt 2f.2 array methods: all checks passed");
