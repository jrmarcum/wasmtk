// Is "apple" < "banana"? (True)
export function testStringLt(a: string, b: string): boolean {
  return a < b;
}

// Is "zebra" > "apple"? (True)
export function testStringGt(a: string, b: string): boolean {
  return a > b;
}

export function testStringLe(a: string, b: string): boolean {
  return a <= b;
}

export function testStringGe(a: string, b: string): boolean {
  return a >= b;
}

console.log(testStringLt("apple", "banana")); // true
console.log(testStringGt("zebra", "apple")); // true
console.log(testStringLe("apple", "apple")); // true
console.log(testStringGe("banana", "banana")); // true