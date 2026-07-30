type i32 = number;
type f64 = number;

// Guard: same field name at the SAME type in every variant — one shared slot, unchanged.
type Same =
  | { tag: "a"; n: i32 }
  | { tag: "b"; n: i32 };

// The fix: same field name at DIFFERENT numeric widths. The shared slot must widen to f64
// so the f64 variant is not truncated, and the field declared after it must stay aligned.
type Mixed =
  | { tag: "int"; v: i32; label: i32 }
  | { tag: "flt"; v: f64; label: i32 };

// Guard: widening must not depend on declaration order — here the WIDE variant comes first.
interface WideFirst {
  tag: "wide";
  w: f64;
}
interface NarrowSecond {
  tag: "narrow";
  w: i32;
}
type Reversed = WideFirst | NarrowSecond;

export function testUnionSharedFieldWidening(): void {
  console.log("--- Shared union field widening ---");

  const s1: Same = { tag: "a", n: 7 };
  const s2: Same = { tag: "b", n: 9 };
  console.log("Same-type shared slot:", s1.n + s2.n); // Expected: 16

  const m1: Mixed = { tag: "int", v: 100, label: 1 };
  const m2: Mixed = { tag: "flt", v: 25.5, label: 2 };
  console.log("Widened int payload:", m1.v); // Expected: 100
  console.log("Widened float payload:", m2.v); // Expected: 25.5
  console.log("Field after widened slot:", m1.label + m2.label); // Expected: 3

  const r1: Reversed = { tag: "wide", w: 0.25 };
  const r2: Reversed = { tag: "narrow", w: 4 };
  console.log("Wide-first payload:", r1.w); // Expected: 0.25
  console.log("Narrow-second payload:", r2.w); // Expected: 4
}

testUnionSharedFieldWidening();
