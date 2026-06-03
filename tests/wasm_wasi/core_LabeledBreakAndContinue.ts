type i32 = number;
export function testNestedLabels(target: i32): i32 {
  let iterations = 0;

  outer: for (let i = 0; i < 10; i++) {
    for (let j = 0; j < 10; j++) {
      iterations++;
      
      if (i + j === target) {
        // Should jump out of both loops
        break outer;
      }
      
      if (j === 5) {
        // Should skip the rest of the inner loop and increment i
        continue outer;
      }
    }
  }

  return iterations;
}

console.log(testNestedLabels(7)); // Should return the number of iterations before breaking out of the loops
console.log(testNestedLabels(15)); // Should return the number of iterations before breaking out of the loops