// @expect-fail: compile
// H12 sw01 (2026-09-29): wasic throws a string, so a thrown OBJECT has no model. It used to compile
// to proc_exit(0) — exit 0, catch skipped, nothing printed. It is now refused at compile time with
// "Unsupported throw". Native TS runs it and prints "caught".
type i32 = number;

function f(k: i32): i32 {
  if (k > 0) throw { code: k };
  return k;
}

try {
  f(1);
} catch (e) {
  console.log("caught");
}
