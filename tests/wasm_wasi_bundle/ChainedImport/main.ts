import { scale, shift } from "./transform.ts";

type i32 = number;

function main(): void {
  console.log(scale(3));         // 30  (3 * 10)
  console.log(shift(7));         // 12  (7 + 5)
  console.log(scale(shift(2)));  // 70  ((2+5)*10)
}

main();
