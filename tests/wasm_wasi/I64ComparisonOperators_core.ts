export function testBigIntComparisons(val: bigint): void {
  const limit: bigint = 5000000000n; // Larger than i32 max

  // Equality
  if (val == limit) {
    console.log(1n);
  }

  // Signed Relational
  if (val > 0n) {
    console.log(2n);
  }

  if (val < -100n) {
    console.log(3n);
  }

  // Mixed expression check
  const isLarge = val >= limit;
  console.log(isLarge);
}

testBigIntComparisons(6000000000n);