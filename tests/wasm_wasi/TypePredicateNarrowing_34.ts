// Phase 34 — Type predicates: narrowing with interface inheritance (Phase 30)
// Passing a derived-type pointer to a function expecting the base type, then
// narrowing inside that function allows access to derived-type-only fields.
type i32 = number;

interface Entity {
  kind: i32;
  x: i32;
}

interface Player extends Entity {
  score: i32;
}

interface Enemy extends Entity {
  damage: i32;
}

function isPlayer(e: Entity): e is Player {
  return e.kind === 1;
}

function isEnemy(e: Entity): e is Enemy {
  return e.kind === 2;
}

function processEntity(e: Entity): void {
  if (isPlayer(e)) {
    console.log("player score:", e.score);   // accesses Player.score via narrowing
  } else if (isEnemy(e)) {
    console.log("enemy damage:", e.damage);  // accesses Enemy.damage via narrowing
  } else {
    console.log("unknown entity");
  }
}

function main(): void {
  const p: Player = { kind: 1, x: 10, score: 100 };
  const enem: Enemy = { kind: 2, x: 5, damage: 50 };
  const ent: Entity = { kind: 3, x: 7 };

  // Direct predicate calls return bool
  console.log(isPlayer(p));     // true
  console.log(isPlayer(enem));  // false
  console.log(isEnemy(enem));   // true

  // Function that uses predicates and narrowing
  processEntity(p);    // player score: 100
  processEntity(enem); // enemy damage: 50
  processEntity(ent);  // unknown entity
}

main();
