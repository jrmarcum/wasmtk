// Recursion, generators, destructuring, spread, template literals — all interpreted.
function fact(n) {
  return n <= 1 ? 1 : n * fact(n - 1);
}
console.log("fact 6:", fact(6));

function* range(a, b) {
  for (let i = a; i < b; i++) yield i;
}
let total = 0;
for (const x of range(1, 6)) {
  total = total + x;
}
console.log("range sum:", total);

const nums = [10, 20, 30, 40];
const [first, second] = nums;
console.log("first:", first, "second:", second);

const base = { a: 1, b: 2 };
const ext = { ...base, c: 3 };
console.log("spread:", JSON.stringify(ext));

const name = "wasmtk";
console.log(`hello ${name}, ${2 + 3} times`);
