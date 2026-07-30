// Phase 34 regression (2026-07-30) — an INLINE object-type predicate target over an interface
// HIERARCHY. Two bugs met here: the function header regex only accepted `p is NamedType`, so the
// predicate was never parsed at all; and once it parsed, an inline target matched no registered
// type, narrowing was skipped, and `s.radius` on a `Shape`-typed variable silently read 0 instead
// of 5. The inline shape is now resolved structurally to `Circle` and narrowing uses its offsets.
// The DU form of the same construct is pinned by 34_DiscUnionPredicateInlineTarget; the
// unresolvable form by 34_InlinePredicateUnresolvable.
type i32 = number;
type f64 = number;

interface Shape {
  kind: i32;
}

interface Circle extends Shape {
  radius: f64;
}

function isCircle(s: Shape): s is { kind: i32; radius: f64 } {
  return s.kind === 0;
}

export function testInlinePredicateTarget(): void {
  const c: Circle = { kind: 0, radius: 5.0 };
  const s: Shape = c;

  console.log("Predicate:", isCircle(s) ? 1 : 0); // Expected: 1
  if (isCircle(s)) {
    console.log("Narrowed Radius:", s.radius); // Expected: 5 (silently printed 0 before the fix)
  }

  // Guard: a NAMED target must keep working exactly as before.
  const c2: Circle = { kind: 0, radius: 9.5 };
  const s2: Shape = c2;
  if (isCircleNamed(s2)) {
    console.log("Named-target Radius:", s2.radius); // Expected: 9.5
  }
}

function isCircleNamed(s: Shape): s is Circle {
  return s.kind === 0;
}

testInlinePredicateTarget();
