// Checks if content is identical
export function testStringEq(a: string, b: string): boolean {
  return a == b;
}

// Strict equality (usually behaves like == for strings in AS)
export function testStringStrictEq(a: string, b: string): boolean {
  return a === b;
}

// Inequality
export function testStringNe(a: string, b: string): boolean {
  return a != b;
}

console.log(testStringEq("hello", "hello")); // true
console.log(testStringEq("hello", "world")); // false
console.log(testStringStrictEq("hello", "hello")); // true
console.log(testStringStrictEq("hello", "world")); // false
console.log(testStringNe("hello", "hello")); // false
console.log(testStringNe("hello", "world")); // true