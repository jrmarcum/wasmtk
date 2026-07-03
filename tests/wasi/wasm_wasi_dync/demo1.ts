// A fully-dynamic program: closures, objects, classes, stdlib, control flow — all interpreted.
function makeCounter(start) {
  let n = start;
  return function () { n = n + 1; return n; };
}
const c = makeCounter(10);
console.log("counter:", c(), c(), c());

class Point {
  constructor(x, y) { this.x = x; this.y = y; }
  dist() { return Math.sqrt(this.x * this.x + this.y * this.y); }
}
const p = new Point(3, 4);
console.log("dist:", p.dist());

const nums = [5, 3, 8, 1, 9, 2];
const sorted = nums.slice().sort(function (a, b) { return a - b; });
console.log("sorted:", JSON.stringify(sorted));
console.log("sum:", nums.reduce(function (a, b) { return a + b; }, 0));

const words = ["apple", "banana", "cherry"];
console.log("upper:", words.map(function (w) { return w.toUpperCase(); }).join(", "));

let fib = [0, 1];
for (let i = 2; i < 10; i++) { fib.push(fib[i - 1] + fib[i - 2]); }
console.log("fib:", JSON.stringify(fib));
