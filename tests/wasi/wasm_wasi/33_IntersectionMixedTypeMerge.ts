// Phase 33 — Intersection types: flat merge of an f64-first and an i32-second interface,
// initialised and read back through an exported function.
type i32 = number;
type f64 = number;

interface Positionable {
  x: f64;
  y: f64;
}

interface Identifiable {
  id: i32;
  active: i32;
}

// Flat merged struct layout
type Entity = Positionable & Identifiable;

export function testBasicIntersection(): void {
  console.log("--- Test 1: Basic Intersection Merging ---");

  const ent: Entity = {
    x: 12.5,
    y: 24.5,
    id: 101,
    active: 1
  };

  console.log("Entity ID:", ent.id);                  // Expected: 101
  console.log("Entity Active:", ent.active);          // Expected: 1
  console.log("Coordinates Sum:", ent.x + ent.y);    // Expected: 37
}

testBasicIntersection();
