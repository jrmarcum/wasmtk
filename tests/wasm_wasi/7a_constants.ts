// @allow-output-diff: float formatting precision vs native TS
const s: string = "constant";
console.log(s);

const n: number = 500000000;
const d: number = 3e20 / n;
console.log(d);
console.log(Math.trunc(d));
console.log(Math.sin(n));