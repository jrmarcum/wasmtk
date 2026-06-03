type i32 = number;
export function testLabels(): i32 {
  let count = 0;

  outerLoop: for (let i = 0; i < 10; i++) {
    for (let j = 0; j < 10; j++) {
      if (i === 1) {
        continue; // Continues inner loop
      }
      if (i === 2 && j === 2) {
        continue outerLoop; // Continues the outer loop
      }
      if (i === 5) {
        break outerLoop; // Breaks out of everything
      }
      count++;
    }
  }

  // Labeled block (not a loop)
  myBlock: {
    count += 100;
    if (count > 50) break myBlock;
    count = 0; // Should be skipped
  }

  return count;
}

console.log(testLabels()); // Should print 111