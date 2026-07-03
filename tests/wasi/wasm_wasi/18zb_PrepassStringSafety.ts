// Regression (audit item 3, 2026-06-24): the `eval(`→`dynrt_dynEval(` and
// `Function(`→`dynrt_dynMakeFn(` source pre-passes must rewrite ONLY real code — never inside string
// literals or comments. Before the fix they rewrote the raw source, so these printed strings came out
// as "dynrt_dynEval(" / "dynrt_dynMakeFn(". The eval( and Function( in THIS comment must be ignored too.
// This file has no real dynamic code, so the dynrt runtime must NOT be auto-merged either.
type i32 = number;
type f64 = number;

console.log("Call eval( s ) or Function( a, b ) to do dynamic things.");
const note: string = "new Function( x ) builds a fn; eval( src ) runs it.";
console.log(note);
console.log("done");
