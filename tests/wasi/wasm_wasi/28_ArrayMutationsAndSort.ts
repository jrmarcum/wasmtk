type i32 = number;

function descCompare(a: i32, b: i32): i32 {
  return b - a;
}

export function testMutationsAndSort(): void {
  console.log("--- Test 2: Reverse, Fill & Sort ---");

  const arr: i32[] = [5, 2, 8, 1, 9];

  // In-place reverse
  arr.reverse();
  console.log("Reversed Index 0:", arr[0]); // Expected: 9

  // In-place default sort (ascending)
  arr.sort();
  console.log("Sorted Asc Index 0:", arr[0]); // Expected: 1
  console.log("Sorted Asc Index 4:", arr[4]); // Expected: 9

  // In-place custom sort (descending)
  arr.sort(descCompare);
  console.log("Sorted Desc Index 0:", arr[0]); // Expected: 9

  // Range Fill
  const fillArr: i32[] = [0, 0, 0, 0, 0];
  fillArr.fill(7, 1, 4); // Fills indices 1, 2, 3 with 7
  console.log("Filled Index 0:", fillArr[0]); // Expected: 0
  console.log("Filled Index 2:", fillArr[2]); // Expected: 7
  console.log("Filled Index 4:", fillArr[4]); // Expected: 0
}

testMutationsAndSort();
