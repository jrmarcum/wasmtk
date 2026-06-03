// Equality
type i32 = number;
export function testEqI32(a: i32, b: i32): boolean {
  return a == b;
}

export function testStrictEqI32(a: i32, b: i32): boolean {
  return a === b;
}

// Inequality
export function testNeI32(a: i32, b: i32): boolean {
  return a != b;
}

// Relational
export function testGtI32(a: i32, b: i32): boolean {
  return a > b;
}

export function testGeI32(a: i32, b: i32): boolean {
  return a >= b;
}

export function testLtI32(a: i32, b: i32): boolean {
  return a < b;
}

export function testLeI32(a: i32, b: i32): boolean {
  return a <= b;
}

console.log(testEqI32(5, 5)); // true
console.log(testStrictEqI32(5, 5)); // true
console.log(testNeI32(5, 10)); // true
console.log(testGtI32(10, 5)); // true
console.log(testGeI32(10, 10)); // true
console.log(testLtI32(5, 10)); // true
console.log(testLeI32(5, 5)); // true   