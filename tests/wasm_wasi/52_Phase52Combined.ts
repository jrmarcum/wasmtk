// Phase 52 combined — void / chained assignment / `in` / Array.from-of-isArray / fromCodePoint.
type i32 = number;

interface Cfg {
  width: i32;
  height: i32;
}

let total: i32 = 0;
function acc(n: i32): i32 {
  total = total + n;
  return total;
}

// 52.5 void
void acc(5); // total -> 5
void 0;

// 52.6 chained assignment
let p: i32 = 0;
let q: i32 = 0;
p = q = acc(3); // acc -> total 8; q = 8; p = 8
console.log("total:", total); // 8
console.log("p:", p); // 8
console.log("q:", q); // 8

// 52.7 in operator
const cfg: Cfg = { width: 100, height: 50 };
const hasW: boolean = "width" in cfg;
const hasDepth: boolean = "depth" in cfg;
console.log("hasW:", hasW); // true
console.log("hasDepth:", hasDepth); // false

// 52.8 Array.from / Array.of / isArray
const nums: i32[] = Array.from([2, 4, 6]);
const more: i32[] = Array.of(8, 10);
const numsIsArr: boolean = Array.isArray(nums);
console.log("nums.length:", nums.length); // 3
console.log("more sum:", more[0] + more[1]); // 18
console.log("isArray:", numsIsArr); // true

// 52.9 fromCodePoint
const ch: string = String.fromCodePoint(72, 105); // Hi
console.log("ch:", ch);
