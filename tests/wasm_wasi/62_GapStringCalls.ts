// deno-fmt-ignore-file
// Compiler-gap regression (2026-06-30): Gap 5.1 — `+` concat of two string-returning CALLS.
type i32 = number;
function n1(): string { return "Alice"; }
function n2(): string { return "Bob"; }
const both: string = n1() + n2();
console.log(both); // AliceBob
const framed: string = "[" + n1() + "-" + n2() + "]";
console.log(framed); // [Alice-Bob]
