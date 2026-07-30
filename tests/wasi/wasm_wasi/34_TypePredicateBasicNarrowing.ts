// Phase 34 — Type predicates: a `s is Circle` guard used both as a boolean value and as an
// if-condition, narrowing a base-typed reference so a derived-only field is readable.
type i32 = number;
type f64 = number;

interface Shape {
  kind: i32; // 0 = Circle, 1 = Square
}

interface Circle extends Shape {
  radius: f64;
}

function isCircle(s: Shape): s is Circle {
  return s.kind === 0;
}

export function testTypePredicateBasic(): void {
  console.log("--- Test 1: Type Predicate Basic Narrowing ---");

  const c: Circle = { kind: 0, radius: 5.0 };
  const s: Shape = c; // Base pointer reference

  const checkResult = isCircle(s);
  console.log("Predicate Check Result:", checkResult ? 1 : 0); // Expected: 1

  if (isCircle(s)) {
    // Variable 's' is narrowed to 'Circle' within this block
    console.log("Narrowed Radius Access:", s.radius); // Expected: 5
  }
}

testTypePredicateBasic();
