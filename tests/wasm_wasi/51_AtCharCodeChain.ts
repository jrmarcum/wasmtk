// Phase 51 follow-up: chained `s.at(i).charCodeAt(j)` previously fell to the catch-all expr stub
// and silently returned 0; now it computes the char code at the normalized index. Self-checking
// via the check()/guard trap pattern.

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

function main(): void {
  const s: string = "hello";
  check(s.at(0).charCodeAt(0) === 104 ? 1 : 0); // 'h'
  check(s.at(1).charCodeAt(0) === 101 ? 1 : 0); // 'e'
  check(s.at(-1).charCodeAt(0) === 111 ? 1 : 0); // 'o' (last)
  check(s.at(-2).charCodeAt(0) === 108 ? 1 : 0); // 'l'

  // In a numeric expression (f64 promotion path).
  const sum: i32 = s.at(0).charCodeAt(0) + s.at(-1).charCodeAt(0);
  check(sum === 215 ? 1 : 0); // 104 + 111

  console.log("codes:", s.at(0).charCodeAt(0), s.at(-1).charCodeAt(0));
  console.log("at-charcode chain ok");
}

main();
