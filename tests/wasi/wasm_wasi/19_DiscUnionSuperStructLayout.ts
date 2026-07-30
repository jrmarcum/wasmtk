type i32 = number;
type f64 = number;

type Shape =
  | { kind: "circle"; radius: f64 }
  | { kind: "rectangle"; width: f64; height: f64 }
  | { kind: "point"; id: i32 };

export function testDiscUnionLayout(): void {
  console.log("--- Test 1: Discriminated Union Super-Struct ---");

  const c: Shape = { kind: "circle", radius: 5.0 };
  const r: Shape = { kind: "rectangle", width: 4.0, height: 10.0 };
  const p: Shape = { kind: "point", id: 42 };

  // Testing type narrowing via if/else
  if (c.kind === "circle") {
    console.log("Circle Radius:", c.radius); // Expected: 5
  }

  if (r.kind === "rectangle") {
    console.log("Rectangle Area:", r.width * r.height); // Expected: 40
  }

  if (p.kind === "point") {
    console.log("Point ID:", p.id); // Expected: 42
  }
}

testDiscUnionLayout();
