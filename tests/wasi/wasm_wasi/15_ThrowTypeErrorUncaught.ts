// @expect-exit: 1  (an uncaught TypeError must exit 1 like native TS; before H12 sw01 it exited 0)
type i32 = number;

function check(k: i32): i32 {
  if (k < 0) throw new TypeError("negative");
  return k;
}

console.log("before");
check(-1);
console.log("after");
