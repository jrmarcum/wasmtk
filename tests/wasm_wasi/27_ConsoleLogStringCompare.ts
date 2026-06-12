// Regression — string/numeric comparisons inside console.log, especially when an operand is a
// non-trivial string form (function call, struct field, slice, method) and/or the RHS ends in `)`.
// Three bugs were fixed here:
//   1. findTopLevelOp scanned from `length - op.length`, so a RHS ending in `)` (a call/slice)
//      drove paren depth negative and the operator was never found → the comparison silently fell
//      through to the numeric/terminal path (wrong result).
//   2. console.log string === / !== only handled local/literal/array-element operands; fn-call /
//      field / slice / method operands silently compared against the empty string.
//   3. The string `!==` return was inverted (returned true for EQUAL strings).
type i32 = number;

function getName(): string {
  return "bob";
}

interface P {
  name: string;
}

const p: P = { name: "bob" };
const a: string = "bob";
const c: string = "carol";

// String === / !== with non-trivial operands (RHS ends in `)`).
console.log("fn-eq:", a === getName()); // true
console.log("fn-ne:", c !== getName()); // true
console.log("fn-eq2:", c === getName()); // false
console.log("field-eq:", a === p.name); // true
console.log("upper-eq:", "BOB" === a.toUpperCase()); // true

function inFunc(): void {
  const s: string = "bob";
  const src: string = "bobby";
  console.log("slice-eq:", s === src.slice(0, 3)); // true
  console.log("slice-ne:", s !== src.slice(0, 4)); // true
  // Numeric comparison whose RHS ends in `)` — also broken by the findTopLevelOp bug.
  console.log("len-eq:", s.length === src.slice(0, 3).length); // true
  console.log("len-ne:", s.length !== src.length); // true (3 vs 5)
}
inFunc();
