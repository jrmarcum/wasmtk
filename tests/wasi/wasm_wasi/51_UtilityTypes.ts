// Phase 51.4 — Utility types (compile-time type resolution).
type i32 = number;
type f64 = number;

interface Point {
  x: f64;
  y: f64;
}

interface Config {
  width: i32;
  height: i32;
  depth: i32;
}

// Pass-through: Partial / Readonly / Required resolve to the underlying struct.
function usePartial(p: Partial<Point>): f64 {
  return p.x + p.y;
}

function useReadonly(c: Readonly<Config>): i32 {
  return c.width + c.height + c.depth;
}

// Named alias from a utility type.
type Flat = Pick<Config, "width" | "height">;
function useFlat(f: Flat): i32 {
  return f.width * f.height;
}

function main(): void {
  const a: Partial<Point> = { x: 3.0, y: 4.0 };
  console.log("partial:", usePartial(a)); // 7

  const b: Readonly<Config> = { width: 1, height: 2, depth: 3 };
  console.log("readonly:", useReadonly(b)); // 6

  // Required is also pass-through.
  const r: Required<Point> = { x: 1.5, y: 2.5 };
  console.log("required:", r.x + r.y); // 4

  // NonNullable strips | null.
  const n: NonNullable<i32> = 42;
  console.log("nonnull:", n); // 42

  // Pick<T, K> — subset struct (a Point is layout-compatible with Pick<Point, "x">).
  const px: Pick<Point, "x"> = { x: 9.0 };
  console.log("pick.x:", px.x); // 9

  // Omit<T, K> — Config without depth. (Direct i32 field+field arithmetic in console.log now works.)
  const o: Omit<Config, "depth"> = { width: 10, height: 20 };
  console.log("omit:", o.width + o.height); // 30

  // Record<literal-union, V> — struct keyed by the literals.
  const rec: Record<"a" | "b", i32> = { a: 5, b: 7 };
  console.log("record:", rec.a + rec.b); // 12

  // Named alias from a utility type.
  const flatVal: Flat = { width: 4, height: 6 };
  console.log("flat:", useFlat(flatVal)); // 24
}

main();
