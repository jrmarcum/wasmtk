// Regression: struct/interface type names are recognized by the structDefs registry, NOT by a
// PascalCase spelling proxy. `tsbundler` prefixes every imported type with the (lower-case)
// module filename — `Vec2` in `vec.ts` becomes `vec_Vec2` — so the old `[A-Z]\w*` gate rejected
// every bundled struct, and each `p.field` aborted as "unsupported expression"
// (tests/bundle_tests.ts StructImport). Names here deliberately start lower-case / underscore.

type i32 = number;
type f64 = number;

interface vec_Vec2 {
  x: f64;
  y: f64;
}

interface _tagged {
  id: i32;
  weight: f64;
}

function vec_dot(a: vec_Vec2, b: vec_Vec2): f64 {
  return a.x * b.x + a.y * b.y;
}

function vec_lengthSq(v: vec_Vec2): f64 {
  return v.x * v.x + v.y * v.y;
}

function tagWeight(t: _tagged): f64 {
  return t.weight;
}

export function testLowercaseStructNames(): void {
  const a: vec_Vec2 = { x: 3.0, y: 4.0 };
  const b: vec_Vec2 = { x: 1.0, y: 2.0 };

  console.log("lengthSq:", vec_lengthSq(a)); // 25
  console.log("dot:", vec_dot(a, b)); // 11

  // field read + write through a lower-case-initial struct type
  const t: _tagged = { id: 7, weight: 1.5 };
  console.log("id:", t.id); // 7
  console.log("weight:", tagWeight(t)); // 1.5
  t.weight = 2.5;
  console.log("weight after write:", t.weight); // 2.5

  // PascalCase must keep working unchanged
  const c: vec_Vec2 = { x: 0.0, y: 5.0 };
  console.log("mixed:", vec_dot(a, c)); // 20
}

testLowercaseStructNames();
