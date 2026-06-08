// @allow-output-diff: wasic zero-sentinel destructuring defaults differ from native TS
// Phase 48: combined test
type i32 = number;
type f64 = number;

interface Config {
  width: i32;
  height: i32;
}

function classify(x: f64): void {
  if (Number.isNaN(x)) {
    console.log("nan");
    return;
  }
  if (!Number.isFinite(x)) {
    console.log("infinite");
    return;
  }
  if (Number.isInteger(x)) {
    console.log("integer");
  } else {
    console.log("float");
  }
}

function switchDemo(x: i32): void {
  switch (x) {
    case 1:
    case 2:
      console.log("low");
      break;
    case 3:
      console.log("mid");
      // fallthrough
    case 4:
      console.log("mid-high");
      break;
    default:
      console.log("high");
  }
}

function labeledSum(): i32 {
  let total: i32 = 0;
  outer: for (let i: i32 = 0; i < 4; i++) {
    for (let j: i32 = 0; j < 4; j++) {
      if (j >= 2) continue outer;
      total += 1;
    }
  }
  return total;  // 4 * 2 = 8
}

function main(): void {
  // Number constants and predicates
  classify(Number.NaN);
  classify(Number.POSITIVE_INFINITY);
  classify(5.0);
  classify(3.7);

  // Switch fallthrough
  switchDemo(1);
  switchDemo(3);
  switchDemo(5);

  // Labeled continue
  console.log(labeledSum());

  // Object destructuring with default
  const cfg: Config = { width: 800, height: 0 };
  const { width = 1920, height = 1080 } = cfg;
  console.log(width);   // 800
  console.log(height);  // 1080

  // Exponent assignment
  let base: f64 = 2.0;
  base **= 8;
  console.log(base);  // 256

  // Number constants comparison
  console.log(Number.MAX_SAFE_INTEGER > 1e16);  // false (MAX_SAFE < 1e16)
  console.log(Number.MIN_SAFE_INTEGER < -1e16); // false (MIN_SAFE > -1e16)
}

main();
// Expected output:
// nan
// infinite
// integer
// float
// low
// mid
// mid-high
// high
// 8
// 800
// 1080
// 256
// false
// false