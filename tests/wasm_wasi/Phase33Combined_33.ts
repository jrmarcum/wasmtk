// Phase 33 — Intersection types: combined test with chained intersection
type i32 = number;
type f64 = number;

interface Physical { mass: f64; energy: f64; }
interface Spatial { sx: i32; sy: i32; }
type Particle = Physical & Spatial;

function describeParticle(p: Particle): void {
  console.log("mass:", p.mass);
  console.log("sx:", p.sx);
}

function totalEnergy(p: Particle): f64 {
  return p.mass * p.energy;
}

interface Color { r: i32; g: i32; b: i32; }
type ColoredParticle = Particle & Color;

const cp: ColoredParticle = { mass: 2.0, energy: 5.0, sx: 10, sy: 20, r: 255, g: 128, b: 64 };
describeParticle(cp);           // mass: 2 / sx: 10
console.log(totalEnergy(cp));   // 10
console.log("sy:", cp.sy);      // sy: 20
console.log("r:", cp.r);        // r: 255
console.log("g:", cp.g);        // g: 128
console.log("b:", cp.b);        // b: 64

const p: Particle = { mass: 0.5, energy: 3.0, sx: 1, sy: 2 };
console.log(totalEnergy(p));    // 1.5
console.log("sx:", p.sx);       // sx: 1
