// Truthiness of a string (usually checks if length > 0 or pointer is non-null)
export function isTruthyString(a: string): boolean {
  if (a) {
    return true;
  }
  return false;
}

// Comparison within a ternary
type f64 = number; // Alias for clarity
type i32 = number; // Alias for clarity
export function ternaryCompare(a: f64, b: f64): i32 {
  return a > b ? 1 : 0;
}

console.log(isTruthyString("")); // false
console.log(isTruthyString("hello")); // true
console.log(ternaryCompare(5, 3)); // 1
console.log(ternaryCompare(2, 4)); // 0