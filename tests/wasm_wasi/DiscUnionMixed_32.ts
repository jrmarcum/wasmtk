// Phase 32 — Discriminated union types: mixed i32/f64 fields
type i32 = number;
type f64 = number;

type Value =
  | { tag: "int"; n: i32 }
  | { tag: "float"; v: f64 }
  | { tag: "pair"; a: i32; b: i32 };

function printValue(val: Value): void {
  switch (val.tag) {
    case "int":
      console.log("int:", val.n);
      break;
    case "float":
      console.log("float:", val.v);
      break;
    case "pair":
      console.log("pair a:", val.a);
      console.log("pair b:", val.b);
      break;
  }
}

function sumValue(val: Value): f64 {
  switch (val.tag) {
    case "int":
      return val.n as f64;
    case "float":
      return val.v;
    case "pair":
      return (val.a + val.b) as f64;
    default:
      return 0.0;
  }
}

const vi: Value = { tag: "int", n: 42 };
const vf: Value = { tag: "float", v: 3.14 };
const vp: Value = { tag: "pair", a: 10, b: 20 };

printValue(vi);              // int: 42
printValue(vf);              // float: 3.14
printValue(vp);              // pair a: 10 / pair b: 20

console.log(sumValue(vi));   // 42
console.log(sumValue(vf));   // 3.14
console.log(sumValue(vp));   // 30
