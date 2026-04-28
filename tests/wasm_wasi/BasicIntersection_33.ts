// Phase 33 — Intersection types: basic two-interface merge
type i32 = number;
type f64 = number;

interface Nameable { x: i32; y: i32; }
interface Sizeable { width: f64; height: f64; }
type Widget = Nameable & Sizeable;

const w: Widget = { x: 10, y: 20, width: 100.5, height: 50.25 };
console.log(w.x);      // 10
console.log(w.y);      // 20
console.log(w.width);  // 100.5
console.log(w.height); // 50.25
