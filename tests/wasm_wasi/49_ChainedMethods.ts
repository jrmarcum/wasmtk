// Phase 49: Chained array method calls
type i32 = number;

function isPos(x: i32): boolean {
  return x > 0;
}

function double(x: i32): i32 {
  return x * 2;
}

function triple(x: i32): i32 {
  return x * 3;
}

function main(): void {
  const nums: i32[] = [-2, 1, -3, 4, 5];

  // filter then map
  const r1: i32[] = nums.filter(isPos).map(double);
  console.log(r1.length);  // 3
  console.log(r1[0]);      // 2
  console.log(r1[1]);      // 8
  console.log(r1[2]);      // 10

  // filter then map with different callback
  const r2: i32[] = nums.filter(isPos).map(triple);
  console.log(r2.length);  // 3
  console.log(r2[0]);      // 3
  console.log(r2[1]);      // 12
  console.log(r2[2]);      // 15
}

main();
// Expected output:
// 3
// 2
// 8
// 10
// 3
// 3
// 12
// 15
