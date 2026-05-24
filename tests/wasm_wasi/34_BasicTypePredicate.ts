// Phase 34 — Type predicates: basic syntax and bool return with discriminated union types
type i32 = number;
type f64 = number;

type Shape =
  | { kind: "circle"; radius: f64 }
  | { kind: "rect"; width: f64; height: f64 };

function isCircle(s: Shape): s is Shape {
  return s.kind === "circle";
}

function isRect(s: Shape): s is Shape {
  return s.kind === "rect";
}

function main(): void {
  const c: Shape = { kind: "circle", radius: 5.0 };
  const r: Shape = { kind: "rect", width: 4.0, height: 3.0 };

  // Predicate returns true/false correctly
  console.log(isCircle(c)); // true
  console.log(isCircle(r)); // false
  console.log(isRect(r));   // true
  console.log(isRect(c));   // false

  // Used in if conditions — DU has all variant fields, so access always works
  if (isCircle(c)) {
    console.log("is circle");  // is circle
    console.log(c.radius);     // 5
  }
  if (isRect(r)) {
    console.log("is rect");    // is rect
    console.log(r.width);      // 4
    console.log(r.height);     // 3
  }
  // Negated predicate in condition
  if (!isCircle(r)) {
    console.log("not circle"); // not circle
  }
  // Predicate with else branch
  if (isCircle(r)) {
    console.log("wrong"); // should not print
  } else {
    console.log("correct else"); // correct else
  }
}

main();
