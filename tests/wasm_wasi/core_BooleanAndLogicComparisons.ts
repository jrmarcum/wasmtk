// Boolean equality
export function compareBool(a: boolean, b: boolean): boolean {
  return a == b;
}

// Logical NOT of a comparison
type i32 = number; // Assuming i32 is defined as a type alias for number
export function compareNot(a: i32, b: i32): boolean {
  return !(a > b);
}

// Chained Comparisons (Short-circuiting)
// This tests if your transpiler correctly handles the 'and' logic
export function compareAnd(a: i32, b: i32, c: i32): boolean {
  return a < b && b < c;
}

export function compareOr(a: i32, b: i32, c: i32): boolean {
  return a == b || a == c;
}

console.log(compareBool(true, true));   // true
console.log(compareBool(true, false));  // false
console.log(compareNot(5, 10));          // true
console.log(compareNot(10, 5));          // false
console.log(compareAnd(1, 2, 3));          // true
console.log(compareAnd(3, 2, 1));          // false
console.log(compareOr(1, 2, 3));           // false
console.log(compareOr(1, 2, 1));           // true
