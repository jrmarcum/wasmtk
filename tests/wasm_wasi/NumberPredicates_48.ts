// Phase 48: Number.isNaN, Number.isFinite, Number.isInteger
type i32 = number;
type f64 = number;

function main(): void {
  const nanVal: f64 = Number.NaN;
  const posInf: f64 = Number.POSITIVE_INFINITY;
  const negInf: f64 = Number.NEGATIVE_INFINITY;
  const finiteVal: f64 = 42.5;
  const intVal: f64 = 7.0;
  const floatVal: f64 = 3.14;

  // Number.isNaN
  console.log(Number.isNaN(nanVal));      // true
  console.log(Number.isNaN(finiteVal));   // false
  console.log(Number.isNaN(posInf));      // false

  // Number.isFinite
  console.log(Number.isFinite(finiteVal)); // true
  console.log(Number.isFinite(nanVal));    // false
  console.log(Number.isFinite(posInf));    // false
  console.log(Number.isFinite(negInf));    // false

  // Number.isInteger
  console.log(Number.isInteger(intVal));   // true
  console.log(Number.isInteger(floatVal)); // false
  console.log(Number.isInteger(nanVal));   // false
}

main();
// Expected output:
// true
// false
// false
// true
// false
// false
// false
// true
// false
// false
