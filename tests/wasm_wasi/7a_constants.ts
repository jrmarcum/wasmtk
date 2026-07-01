// @allow-output-diff: Math.sin(5e8) large-argument ULP difference (mathlib polynomial vs V8 libm; ~13 sig-figs agree). NOT formatting — Dragon4 f64->string is byte-exact.
const s: string = "constant";
console.log(s);

const n: number = 500000000;
const d: number = 3e20 / n;
console.log(d);
console.log(Math.trunc(d));
console.log(Math.sin(n));