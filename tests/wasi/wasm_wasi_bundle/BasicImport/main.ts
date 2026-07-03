import { add, multiply, subtract } from "./mathlib.ts";
import { add as encode, negate } from "./myotherlib.ts";

type i32 = number;

function main(): void {
  // mathlib functions
  console.log(add(3, 4));        // 7
  console.log(multiply(6, 7));   // 42
  console.log(subtract(10, 3));  // 7

  // myotherlib functions — "add" imported as "encode" to avoid local name clash
  console.log(encode(2, 5));     // 25  (2*10 + 5)
  console.log(negate(9));        // -9
}

main();
