// @expect-fail: compile
// Phase 33 regression (2026-07-30) — an intersection is passed BY POINTER and the callee reads
// fields at its own parameter type's offsets, so passing `Sprite` to a `Transform` parameter is
// only sound when `Transform` is the intersection's FIRST constituent. Here it is declared SECOND,
// so `Transform`'s scaleX/scaleY (bytes 0/8) land on Sprite's alpha/scaleX — this used to compile
// and silently print `1.6` instead of `6`. It must now abort with a layout-mismatch diagnostic.
// The compatible ordering is pinned by 33_IntersectionBasePointerParam and 33_IntersectionPrefixOk.
type f64 = number;

interface Transform {
  scaleX: f64;
  scaleY: f64;
}

interface Renderable {
  alpha: f64;
}

// Base interface declared SECOND — Transform is NOT a layout prefix of Sprite
type Sprite = Renderable & Transform;

function getScaleArea(t: Transform): f64 {
  return t.scaleX * t.scaleY;
}

const hero: Sprite = { scaleX: 2.0, scaleY: 3.0, alpha: 0.8 };
const area: f64 = getScaleArea(hero);
console.log("Transform Area:", area);
