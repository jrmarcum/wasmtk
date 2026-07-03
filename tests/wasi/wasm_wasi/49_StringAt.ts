// Phase 49: String.prototype.at(index)
type i32 = number;

function main(): void {
  const s: string = "hello world";

  // positive indices
  console.log(s.at(0));    // h
  console.log(s.at(1));    // e

  // negative indices
  console.log(s.at(-1));   // d
  console.log(s.at(-2));   // l

  // shorter string
  const t: string = "abc";
  console.log(t.at(0));    // a
  console.log(t.at(-1));   // c
  console.log(t.at(-2));   // b
  console.log(t.at(2));    // c

  // at(-1) === at(len-1)
  console.log(s.at(-1));   // d
}

main();
// Expected output:
// h
// e
// d
// l
// a
// c
// b
// c
// d
