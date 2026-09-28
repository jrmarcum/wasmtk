// Regression (2026-09-28): a NUMBER or BOOLEAN operand in a string VALUE built with `+` was
// silently dropped — `"code " + 7` built "code " — and a boolean in a template printed 1/0 instead
// of true/false. console.log(...) was never affected (its own path); the guards below pin that too.
type i32 = number;
type f64 = number;

function label(x: i32): string {
  return "code " + x;
}

function describe(n: i32, x: f64, flag: boolean): string {
  const a: string = "n=" + n;
  const b: string = "x=" + x;
  const c: string = "flag=" + flag;
  const d: string = n + " items";
  const e: string = `t=${flag}`;
  const f: string = "sum=" + (n + 1);
  return a + " " + b + " " + c + " " + d + " " + e + " " + f;
}

console.log(label(7));
console.log(describe(7, 2.5, true));
console.log(describe(0, -1.25, false));
const top: string = "top " + 9 + " " + (2 > 1);
console.log(top);
// Guards: the paths that already worked must keep working.
const name: string = "wasm";
const g: string = "hi " + name + "!";
console.log(g, "direct " + 5, `tmpl ${name} ${3}`);
