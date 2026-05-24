type i32 = number;

/**
 * A function that returns a Result-like structure
 * instead of trapping.
 */
interface DivResult {
  value: i32;
  hasError: i32;
}

export function tryDivide(a: i32, b: i32): DivResult {
  if (b === 0) {
    return { value: 0, hasError: 1 };
  }
  return { value: a / b, hasError: 0 };
}

console.log(tryDivide(10, 2)); // { value: 5, hasError: 0 }
console.log(tryDivide(10, 0)); // { value: 0, hasError: 1 }