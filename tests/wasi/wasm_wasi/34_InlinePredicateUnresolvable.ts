// @expect-fail: compile
// Phase 34 regression (2026-07-30) — the guard on inline object-type predicate targets. This
// inline shape matches no declared type, and the fields it names are absent from the variable's
// own type, so there is no layout to resolve `s.weight` against. Skipping narrowing here would
// read whatever occupies that offset and print it as a number — the exact silent-wrong failure
// 34_InlinePredicateTargetNarrowing pins the fix for. It must abort with a diagnostic instead.
type i32 = number;
type f64 = number;

interface Shape {
  kind: i32;
}

function isHeavy(s: Shape): s is { kind: i32; weight: f64; label: i32 } {
  return s.kind === 0;
}

const s: Shape = { kind: 0 };
if (isHeavy(s)) {
  console.log("weight:", s.weight);
}
