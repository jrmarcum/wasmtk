type i32 = number;
type f64 = number;
function mk() {
  let n: i32 = 0;
  return { inc: () => { n++; return n; } };
}
const k: { inc: () => i32 } = mk();
console.log(k.inc(), k.inc());
