// Checking against an empty literal
export function isStringEmpty(a: string): boolean {
  return a == "";
}

// Checking for null (requires nullable support)
export function isStringNull(a: string | null): boolean {
  return a == null;
}

console.log(isStringEmpty("")); // true
console.log(isStringEmpty("hello")); // false
console.log(isStringNull(null)); // true
console.log(isStringNull("hello")); // false