// Phase 32 — Discriminated union types: basic switch narrowing
type i32 = number;
type f64 = number;

type Shape =
  | { kind: "circle"; radius: f64 }
  | { kind: "rect"; width: f64; height: f64 };

function describeShape(s: Shape): void {
  switch (s.kind) {
    case "circle":
      console.log("circle radius:", s.radius);
      break;
    case "rect":
      console.log("rect width:", s.width);
      console.log("rect height:", s.height);
      break;
  }
}

function getArea(s: Shape): f64 {
  switch (s.kind) {
    case "circle":
      return s.radius * s.radius * 3.14159;
    case "rect":
      return s.width * s.height;
    default:
      return 0.0;
  }
}

const c: Shape = { kind: "circle", radius: 5.0 };
console.log(c.radius);        // 5
describeShape(c);              // circle radius: 5
console.log(getArea(c));       // 78.53975

const r: Shape = { kind: "rect", width: 3.0, height: 4.0 };
console.log(r.width);          // 3
console.log(r.height);         // 4
describeShape(r);              // rect width: 3 / rect height: 4
console.log(getArea(r));       // 12
