// Phase 33 — Intersection types: an intersection value passed to a function whose
// parameter is one of its CONSTITUENT interfaces (base-pointer/prefix-layout compatibility).
type f64 = number;

interface Transform {
  scaleX: f64;
  scaleY: f64;
}

interface Renderable {
  alpha: f64;
}

type Sprite = Transform & Renderable;

// Function expects only the base Transform layout
function getScaleArea(t: Transform): f64 {
  return t.scaleX * t.scaleY;
}

export function testIntersectionParamPassing(): void {
  console.log("--- Test 3: Base Pointer Compatibility ---");

  const hero: Sprite = {
    scaleX: 2.0,
    scaleY: 3.0,
    alpha: 0.8
  };

  console.log("Sprite Alpha:", hero.alpha);              // Expected: 0.8
  console.log("Transform Area:", getScaleArea(hero));   // Expected: 6
}

testIntersectionParamPassing();
