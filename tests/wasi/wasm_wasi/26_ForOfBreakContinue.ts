type i32 = number;

export function testForOfLoops(): void {
  console.log("--- Test 1: for...of Loop Iteration ---");

  const staticArr: i32[] = [10, 20, 30, 40, 50];
  let sum: i32 = 0;

  // for...of over static array with continue and break
  for (const item of staticArr) {
    if (item === 20) continue; // Skip 20
    if (item === 40) break; // Stop before 40
    sum += item;
  }

  console.log("Static Loop Filtered Sum:", sum); // Expected: 10 + 30 = 40

  // Dynamic array iteration
  const dynArr: i32[] = [];
  dynArr.push(1);
  dynArr.push(2);
  dynArr.push(3);

  let product: i32 = 1;
  for (const num of dynArr) {
    product *= num;
  }

  console.log("Dynamic Loop Product:", product); // Expected: 1 * 2 * 3 = 6
}

testForOfLoops();
