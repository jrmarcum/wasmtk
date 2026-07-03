// Phase 48: labeled continue
type i32 = number;

function main(): void {
  // continue outer skips j=3,4 for each i
  let sum: i32 = 0;
  outer: for (let i: i32 = 0; i < 5; i++) {
    for (let j: i32 = 0; j < 5; j++) {
      if (j === 3) continue outer;
      sum += 1;
    }
  }
  console.log(sum);  // 15  (5 * 3, j=0,1,2 counted per i)

  // labeled continue with while
  let count: i32 = 0;
  let outer2: i32 = 0;
  loop: while (outer2 < 4) {
    outer2 += 1;
    let inner: i32 = 0;
    while (inner < 4) {
      inner += 1;
      if (inner === 2) continue loop;
      count += 1;
    }
  }
  console.log(count);  // 4  (outer2=1..4, inner=1 counted, inner=2 → continue loop)
}

main();
// Expected output:
// 15
// 4
