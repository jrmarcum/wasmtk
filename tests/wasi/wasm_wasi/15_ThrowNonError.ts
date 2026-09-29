// H12 sw01 + sw33 (2026-09-29): every built-in Error constructor, a number, a numeric variable and a
// boolean are all catchable, and the catch variable prints what native TS prints. Before the fix,
// `throw new TypeError(..)` and `throw 42` compiled to proc_exit(0): no catch ran, nothing printed,
// exit 0. `String(<bool>)` printed `1` instead of `true` (sw33, found fixing sw01).
type i32 = number;
type f64 = number;

function risky(k: i32): i32 {
  const code: i32 = 7;
  const ratio: f64 = 2.5;
  const flag: boolean = k > 3;
  if (k === 1) throw new TypeError("bad type");
  if (k === 2) throw new RangeError(`out of range: ${k}`);
  if (k === 3) throw -42;
  if (k === 4) throw code;
  if (k === 5) throw ratio;
  if (k === 6) throw flag;
  if (k === 7) throw new Error();
  if (k === 8) throw new SyntaxError("bad syntax");
  return k;
}

for (let i: i32 = 1; i <= 9; i++) {
  try {
    const r: i32 = risky(i);
    console.log("returned", r);
  } catch (e) {
    console.log("caught", i, e instanceof Error ? e.message : e);
  }
}

const n: i32 = 5;
const big: boolean = n > 3;
const small: boolean = n < 3;
const s1: string = String(big);
const s2: string = String(small);
console.log(s1, s2);
console.log("done");
