// H12 sw02 (2026-09-29): a string ternary inside console.log. Before the fix:
//   `flag ? "none" : \`n=${n}\``            printed `n=` (only the template's first piece was kept)
//   `n > 3 ? "big:" + n : "small:" + n`     printed `big:` (the same, for a concat)
//   `flag ? s.toUpperCase() : s.slice(1)`   printed `0` (taken for a number)
//   `n > 3 ? tag(1) : tag(-1)`              built an invalid module
// and `select` ran BOTH branches, so a call in the branch not taken still happened (`calls`), and
// when both branches captured a length, the else branch's length was used for either.
type i32 = number;

let calls: i32 = 0;
function tag(k: i32): string {
  calls = calls + 1;
  return k > 0 ? "pos" : "neg";
}

function show(n: i32, flag: boolean): void {
  const s: string = "abc";
  console.log(flag ? "none" : `n=${n}`);
  console.log(flag ? `yes ${n}` : "no");
  console.log(flag ? `a${n}` : `bb${n}${n}`);
  console.log(n > 3 ? "big:" + n : "small:" + n);
  console.log(flag ? s.toUpperCase() : s.slice(1));
  console.log(n > 3 ? tag(1) : tag(-1));
  console.log(n > 4 ? "gt4" : n > 1 ? `mid ${n}` : "low");
  console.error(flag ? "err-none" : `err n=${n}`);
}

show(5, false);
show(2, true);
show(0, false);
console.log("calls", calls);

const top: i32 = 7;
const on: boolean = top > 5;
console.log(on ? `top=${top}` : "off");
console.log(!on ? "off" : "on:" + top);
