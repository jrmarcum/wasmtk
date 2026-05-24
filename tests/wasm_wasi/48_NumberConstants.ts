// Phase 48: Number constants
type i32 = number;
type f64 = number;

function main(): void {
  const nanVal: f64 = Number.NaN;
  const posInf: f64 = Number.POSITIVE_INFINITY;
  const negInf: f64 = Number.NEGATIVE_INFINITY;
  const eps: f64 = Number.EPSILON;
  const maxSafe: f64 = Number.MAX_SAFE_INTEGER;
  const minSafe: f64 = Number.MIN_SAFE_INTEGER;
  const maxVal: f64 = Number.MAX_VALUE;
  const minVal: f64 = Number.MIN_VALUE;

  console.log(isNaN(nanVal));       // true
  console.log(posInf > 1e300);     // true
  console.log(negInf < -1e300);    // true
  console.log(eps > 0);            // true
  console.log(maxSafe);            // 9007199254740991
  console.log(minSafe);            // -9007199254740991
  console.log(maxVal > 1e300);     // true
  console.log(minVal > 0);         // true
}

main();
// Expected output:
// true
// true
// true
// true
// 9007199254740991
// -9007199254740991
// true
// true
