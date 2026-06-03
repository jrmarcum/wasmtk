// deno-fmt-ignore-file
// Regression: single-physical-line function bodies containing if/else and
// trailing statements were mangled — the trailing statement after a brace
// block was dropped (leaving a value-returning fn whose body is a void if →
// V8 "expected 1 elements on the stack for fallthru, found 0"), and bodies
// with multiple statements on one line were jammed into one. Fixed 2026-06-03
// by splitting single-line bodies into statements at the source (string-aware
// splitStmts) plus preserving trailing statements in expandInlineBraceChain.
// NOTE: deno-fmt-ignore-file is required — the single-physical-line forms below
// are the exact shape under test; `deno fmt` would otherwise expand them.
type i32 = number;

// inline if/else, whole body on one line
function classify(c: i32): i32 { if (c > 0) { return 1; } else { return -1; } }
// inline if + trailing return (no else)
function clampLow(c: i32): i32 { if (c > 0) { return 1; } return 2; }
// inline else-if chain + trailing return
function bucket(c: i32): i32 { if (c > 5) { return 10; } else if (c > 0) { return 5; } return 0; }
// single-line body that does NOT start with if (multiple statements)
function offset(c: i32): i32 { let x: i32 = 0; if (c > 0) { x = 1; } x = x + 100; return x; }
// inline if with a brace-less body + trailing return
function pick(c: i32): i32 { if (c > 0) return 7; return 8; }
// guard against string-literal `;`/`{`/`}` being treated as statement boundaries
function tag(c: i32): void { console.log("a;{b}"); if (c > 0) { console.log("pos"); } }

console.log(classify(5)); // 1
console.log(classify(-2)); // -1
console.log(clampLow(5)); // 1
console.log(clampLow(-2)); // 2
console.log(bucket(9)); // 10
console.log(bucket(3)); // 5
console.log(bucket(-1)); // 0
console.log(offset(5)); // 101
console.log(offset(-5)); // 100
console.log(pick(5)); // 7
console.log(pick(-5)); // 8
tag(1); // a;{b}  then  pos
