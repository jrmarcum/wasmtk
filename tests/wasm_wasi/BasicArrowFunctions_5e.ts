type i32 = number; // Alias for 32-bit integer

// Test: No parameters, implicit return
const getAnswer = (): i32 => 42;

// Test: Single parameter, i64/bigint support
const doubleBigInt = (n: bigint): bigint => n * 2n;

// Test: Multiple parameters, explicit body
const calculateArea = (width: i32, height: i32): i32 => {
  const area = width * height;
  return area;
};

(function _start(): void {
  console.log(getAnswer());       // 42
  console.log(doubleBigInt(5n));  // 10
  console.log(calculateArea(5, 10)); // 50
})();