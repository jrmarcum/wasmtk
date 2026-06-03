// Identity and Equality
export function compareStringsEqual(a: string, b: string): boolean {
  return a == b;
}

export function compareStringsNotEqual(a: string, b: string): boolean {
  return a != b;
}

// Lexicographical (Ordering)
export function compareStringsLess(a: string, b: string): boolean {
  return a < b;
}

export function compareStringsGreater(a: string, b: string): boolean {
  return a > b;
}

export function compareStringsLessEqual(a: string, b: string): boolean {
  return a <= b;
}

// Edge Case: Different Lengths but same prefix
// e.g., "app" vs "apple"
export function comparePrefix(a: string, b: string): boolean {
  return a < b; 
}

// Edge Case: Empty strings
export function compareEmpty(a: string): boolean {
  return a == "";
}

console.log(compareStringsEqual("hello", "hello")); // true
console.log(compareStringsNotEqual("hello", "world")); // true
console.log(compareStringsLess("apple", "banana")); // true
console.log(compareStringsGreater("banana", "apple")); // true
console.log(compareStringsLessEqual("apple", "apple")); // true
console.log(comparePrefix("app", "apple")); // true
console.log(compareEmpty("")); // true
