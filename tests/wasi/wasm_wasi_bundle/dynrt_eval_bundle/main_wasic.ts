// Driver for the wasmtk own dynamic runtime — #14 increment 2a: `eval` of a pure expression
// language. Imports the modc-compiled dynamic-runtime library and exercises `dynEval(src)` over a
// range of expressions (precedence, parens, unary, f64 literals, comparisons, logical, ternary,
// string concat). After the Phase 18 merge + Stage 0.6 allocator unification, the boxed result
// values live on the driver's shared heap.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves the evaluator.

type i32 = number;
type f64 = number;

import { dynEval, dynTypeof, dynNumberValue, dynToBool, dynStrLen, dynStrCharAt } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// helper: evaluate, assert it's a number, assert its f64 value
function checkNum(src: string, expected: f64): void {
  const v: i32 = dynEval(src);
  check(dynTypeof(v) === 3 ? 1 : 0);
  check(dynNumberValue(v) === expected ? 1 : 0);
}

// helper: evaluate, assert it's a boolean, assert its truthiness
function checkBool(src: string, expected: i32): void {
  const v: i32 = dynEval(src);
  check(dynTypeof(v) === 2 ? 1 : 0);
  check(dynToBool(v) === expected ? 1 : 0);
}

// ── arithmetic + precedence ───────────────────────────────────────────────────────────────────
checkNum("1 + 2 * 3", 7);
checkNum("(1 + 2) * 3", 9);
checkNum("10 - 4 - 3", 3);       // left-associative
checkNum("2 * 3 + 4 * 5", 26);
checkNum("(1 + 2) * (3 + 4)", 21);
checkNum("7 % 3", 1);
checkNum("20 / 4 / 5", 1);
checkNum("-5 + 2", -3);          // unary minus
checkNum("- -8", 8);             // double unary
checkNum("3.5 * 2", 7);          // f64
checkNum("1e3 + 1", 1001);       // exponent literal
checkNum("10 % 4 + 1", 3);

// ── comparisons + equality ──────────────────────────────────────────────────────────────────
checkBool("3 < 5", 1);
checkBool("5 < 3", 0);
checkBool("5 <= 5", 1);
checkBool("6 > 9", 0);
checkBool("9 >= 9", 1);
checkBool("2 === 2", 1);
checkBool("2 === 3", 0);
checkBool("2 !== 3", 1);
checkBool("2 + 3 === 5", 1);     // additive binds tighter than equality

// ── logical + ternary ──────────────────────────────────────────────────────────────────────
checkBool("true && false", 0);
checkBool("true || false", 1);
checkBool("!false", 1);
checkBool("3 < 5 && 5 < 10", 1);
checkBool("3 > 5 || 5 < 10", 1);
checkNum("1 < 2 ? 10 : 20", 10);
checkNum("1 > 2 ? 10 : 20", 20);
checkNum("(2 + 3 === 5) ? 100 : 0", 100);

// ── string concat ──────────────────────────────────────────────────────────────────────────
const s1: i32 = dynEval("'ab' + 'cd'");
check(dynTypeof(s1) === 4 ? 1 : 0);
check(dynStrLen(s1) === 4 ? 1 : 0);
check(dynStrCharAt(s1, 0) === 97 ? 1 : 0); // 'a'
check(dynStrCharAt(s1, 2) === 99 ? 1 : 0); // 'c'
checkBool("'foo' === 'foo'", 1);
checkBool("'foo' === 'bar'", 0);
const s2: i32 = dynEval("'x' + 'y' + 'z'");
check(dynStrLen(s2) === 3 ? 1 : 0);

console.log("dynrt eval: all checks passed");
