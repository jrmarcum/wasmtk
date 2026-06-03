export function testBigIntLogging(): void {
  // Test Literals & Basic i64 Output
  const positive: bigint = 9223372036854775807n; // Max i64
  const negative: bigint = -9223372036854775808n; // Min i64
  const zero: bigint = 0n;

  console.log(positive);
  console.log(negative);
  console.log(zero);

  // Test i64 Expressions in Log
  const a: bigint = 100n;
  const b: bigint = 200n;
  console.log(a + b); // Should trigger i64expr -> $__i64_to_str
}

testBigIntLogging();