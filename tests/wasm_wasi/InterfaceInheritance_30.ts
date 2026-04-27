// Phase 30: interface inheritance — interface B extends A
type i32 = number;
type f64 = number;

interface Entity {
  id: i32;
  active: i32;
}

interface Player extends Entity {
  score: f64;
  level: i32;
}

interface Enemy extends Entity {
  damage: i32;
}

function printEntity(e: Entity): void {
  console.log("id:", e.id);
  console.log("active:", e.active);
}

function main(): void {
  // Player inherits id and active from Entity, plus score and level
  const p: Player = { id: 42, active: 1, score: 98.5, level: 5 };
  console.log("player id:", p.id);       // 42
  console.log("active:", p.active);      // 1
  console.log("score:", p.score);        // 98.5
  console.log("level:", p.level);        // 5

  // Mutate inherited field
  p.active = 0;
  console.log("active after:", p.active); // 0

  // Mutate own field
  p.score = 100.0;
  console.log("score after:", p.score);   // 100

  // Enemy inherits id and active from Entity, plus damage
  const e: Enemy = { id: 7, active: 1, damage: 25 };
  console.log("enemy id:", e.id);         // 7
  console.log("enemy damage:", e.damage); // 25

  // Pass to function expecting base interface
  printEntity(p);                         // id: 42 / active: 0
  printEntity(e);                         // id: 7 / active: 1
}

main();
