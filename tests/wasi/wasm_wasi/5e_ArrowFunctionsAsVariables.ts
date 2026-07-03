type i32 = number;
export function testFunctionAssignment(op: i32): i32 {
  // Assigning arrow functions to a variable
  let mathOp: (a: i32, b: i32) => i32;

  if (op == 1) {
    mathOp = (a, b) => a + b;
  } else {
    mathOp = (a, b) => a * b;
  }

  return mathOp(10, 5);
}

console.log(testFunctionAssignment(1)); // Output: 15
console.log(testFunctionAssignment(2)); // Output: 50