// Phase 32 — Discriminated union types: combined test
type i32 = number;
type f64 = number;

// ── Shape: circle and rectangle ──────────────────────────────────────────────
type Shape =
  | { kind: "circle"; radius: f64 }
  | { kind: "rect"; width: f64; height: f64 };

function area(s: Shape): f64 {
  switch (s.kind) {
    case "circle":
      return s.radius * s.radius * 3.14159;
    case "rect":
      return s.width * s.height;
    default:
      return 0.0;
  }
}

function isCircle(s: Shape): i32 {
  if (s.kind === "circle") {
    return 1;
  }
  return 0;
}

const c: Shape = { kind: "circle", radius: 2.0 };
const r: Shape = { kind: "rect", width: 3.0, height: 5.0 };
console.log(area(c));           // 12.56636
console.log(area(r));           // 15
console.log(isCircle(c));       // 1
console.log(isCircle(r));       // 0

// ── Result type: ok or error ──────────────────────────────────────────────────
type Result =
  | { status: "ok"; value: i32 }
  | { status: "err"; code: i32 };

function checkResult(res: Result): void {
  if (res.status === "ok") {
    console.log("ok:", res.value);
  } else if (res.status === "err") {
    console.log("err:", res.code);
  }
}

function isOk(res: Result): i32 {
  if (res.status !== "ok") {
    return 0;
  }
  return 1;
}

const ok: Result = { status: "ok", value: 100 };
const err: Result = { status: "err", code: 404 };
checkResult(ok);                // ok: 100
checkResult(err);               // err: 404
console.log(isOk(ok));         // 1
console.log(isOk(err));        // 0

// ── Direction union ──────────────────────────────────────────────────────────
type Move =
  | { dir: "up"; steps: i32 }
  | { dir: "down"; steps: i32 }
  | { dir: "left"; steps: i32 }
  | { dir: "right"; steps: i32 };

function applyMove(x: i32, y: i32, m: Move): void {
  switch (m.dir) {
    case "up":
      console.log("y:", y + m.steps);
      break;
    case "down":
      console.log("y:", y - m.steps);
      break;
    case "left":
      console.log("x:", x - m.steps);
      break;
    case "right":
      console.log("x:", x + m.steps);
      break;
  }
}

const mu: Move = { dir: "up", steps: 3 };
const md: Move = { dir: "down", steps: 1 };
const ml: Move = { dir: "left", steps: 5 };
const mr: Move = { dir: "right", steps: 2 };
applyMove(10, 10, mu);          // y: 13
applyMove(10, 10, md);          // y: 9
applyMove(10, 10, ml);          // x: 5
applyMove(10, 10, mr);          // x: 12
