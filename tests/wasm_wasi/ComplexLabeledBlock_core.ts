type i32 = number;
export function testLabeledBlock(x: i32): i32 {
  let val = 0;

  my_logic: {
    val = 10;
    if (x < 0) {
      break my_logic; // Jump to end of block
    }
    val = 20; // Only reached if x >= 0
  }

  return val;
}

console.log(testLabeledBlock(-5)); // Output: 10
console.log(testLabeledBlock(5));  // Output: 20