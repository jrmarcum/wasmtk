// H12 sw03 (2026-09-29): a top-level ternary in a console argument is decided BEFORE any operator
// split. The conditional binds looser than `+`, `===`, `&&`, but the `+` concat split ran first and
// cut `ok ? "pass" : "fail: " + msg` at the `+` inside the else branch: `pass` printed `passboom`.
type i32 = number;

const ok: boolean = true;
const bad: boolean = false;
const msg: string = "boom";
const n: i32 = 4;
const s: string = "abc";
console.log(ok ? "pass" : "fail: " + msg);
console.log(bad ? "pass" : "fail: " + msg);
console.log(bad ? "x" + msg : "y" + msg);
console.log(n === 4 ? "four" : "other");
console.log(n > 3 && ok ? "both" : "not both");
console.log(s === "abc" ? s.toUpperCase() : "no");
console.log("n=" + n, ok ? "yes" : "no");
console.log(n > 3 ? n + 1 : n - 1);
