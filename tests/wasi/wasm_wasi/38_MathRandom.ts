// Phase 38 — Math.random(): verify values land in [0, 1)
type f64 = number;
type i32 = number;

let allInRange: i32 = 1;

const r0: f64 = Math.random();
if (r0 < 0 || r0 >= 1) { allInRange = 0; }

const r1: f64 = Math.random();
if (r1 < 0 || r1 >= 1) { allInRange = 0; }

const r2: f64 = Math.random();
if (r2 < 0 || r2 >= 1) { allInRange = 0; }

const r3: f64 = Math.random();
if (r3 < 0 || r3 >= 1) { allInRange = 0; }

const r4: f64 = Math.random();
if (r4 < 0 || r4 >= 1) { allInRange = 0; }

console.log(allInRange);   // 1  (all five values were in [0, 1))
