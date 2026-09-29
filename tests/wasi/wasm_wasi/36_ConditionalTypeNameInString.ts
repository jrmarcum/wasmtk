// Phase 36 — a conditional type's NAME inside a string is text, not a type use.
// The phase as first written (branch 1.4.1) replaced every `\bName\b` in the source, strings included,
// so "Scale is ..." printed as "f64 is ...". Restored 2026-09-28 with use sites rewritten in code only.
type i32 = number;
type f64 = number;

type Scale = i32 extends i32 ? f64 : i32; // non-generic → f64
type Pick2<T> = T extends i32 ? f64 : i32; // generic

function main(): void {
  const s: Scale = 2.5;
  const p: Pick2<i32> = 1.25;
  console.log("Scale is a conditional type:", s);
  console.log("Pick2<i32> resolves at compile time:", p);
}

main();
