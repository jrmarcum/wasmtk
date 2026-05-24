export function isHello(a: string): boolean {
  return a == "hello";
}

type i32 = number;
export function isFortyTwo(a: i32): boolean {
  return a === 42;
}

console.log(isHello("hello")); // true
console.log(isHello("world")); // false
console.log(isFortyTwo(42)); // true
console.log(isFortyTwo(100)); // false