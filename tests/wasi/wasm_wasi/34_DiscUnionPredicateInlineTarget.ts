// Phase 34 — Type predicates over a discriminated union, with an INLINE object-type target
// (`g is { type: "sphere"; r: f64 }`) rather than a named type.
type f64 = number;

type Geometry =
  | { type: "sphere"; r: f64 }
  | { type: "box"; w: f64; h: f64 };

function isSphere(g: Geometry): g is { type: "sphere"; r: f64 } {
  return g.type === "sphere";
}

export function testDiscUnionPredicate(): void {
  console.log("--- Test 3: Discriminated Union Predicate ---");

  const geom: Geometry = { type: "sphere", r: 10.0 };

  if (isSphere(geom)) {
    console.log("Sphere Radius Extracted:", geom.r); // Expected: 10
  }
}

testDiscUnionPredicate();
