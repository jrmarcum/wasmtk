// Phase 53 — Multi-level interface inheritance (>2 deep), declaration-order independent.
// parseStructs now collects all interface / object-type declarations and builds them in
// dependency order, so a derived interface declared BEFORE its base still inherits every field
// (the old source-order pass silently dropped inherited fields on a forward `extends` reference).
type i32 = number;
type f64 = number;

// Declared derived-first on purpose: the bases (C, B, A) appear AFTER their users.
interface D extends C {
  w: f64;
}
interface C extends B {
  z: i32;
}
interface B extends A {
  y: i32;
}
interface A {
  x: i32;
}

// A separate in-order chain with mixed field widths, ending three levels deep.
interface Base2 {
  a: i32;
}
interface Mid2 extends Base2 {
  b: f64;
}
interface Leaf2 extends Mid2 {
  c: i32;
}

// Base-typed parameter receives a deeply-derived value (A's field is at offset 0 in every
// subtype, so reading `.x` through the base type is layout-correct).
function readX(p: A): i32 {
  return p.x;
}

function main(): void {
  const d: D = { x: 1, y: 2, z: 3, w: 4.5 };
  console.log("x:", d.x); // 1
  console.log("y:", d.y); // 2
  console.log("z:", d.z); // 3
  console.log("w:", d.w); // 4.5
  console.log("readX:", readX(d)); // 1

  const leaf: Leaf2 = { a: 10, b: 2.5, c: 30 };
  console.log("a:", leaf.a); // 10
  console.log("b:", leaf.b); // 2.5
  console.log("c:", leaf.c); // 30
}

main();
