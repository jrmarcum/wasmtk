// Phase 30: namespace — basic functions and constants
type i32 = number;
type f64 = number;

namespace MathUtils {
  export function add(a: i32, b: i32): i32 {
    return a + b;
  }

  export function multiply(a: i32, b: i32): i32 {
    return a * b;
  }

  export function square(n: i32): i32 {
    return n * n;
  }

  export const PI: f64 = 3.141592653589793;
  export const TWO: i32 = 2;
}

function main(): void {
  const sum: i32 = MathUtils.add(3, 4);
  console.log("sum:", sum);                   // 7

  const product: i32 = MathUtils.multiply(5, 6);
  console.log("product:", product);           // 30

  const sq: i32 = MathUtils.square(7);
  console.log("square:", sq);                 // 49

  console.log("PI:", MathUtils.PI);           // 3.141592653589793

  console.log("TWO:", MathUtils.TWO);         // 2

  // Namespace constant in expression (pure f64 arithmetic)
  const area: f64 = MathUtils.PI * 9.0;
  console.log("circle area approx:", area);   // 28.274333882308138

  // Namespace call as statement
  MathUtils.add(10, 20);
}

main();
