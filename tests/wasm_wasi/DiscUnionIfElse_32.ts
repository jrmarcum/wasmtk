// Phase 32 — Discriminated union types: if/else narrowing
type i32 = number;
type f64 = number;

type Event =
  | { type: "click"; x: i32; y: i32 }
  | { type: "keypress"; code: i32 }
  | { type: "scroll"; delta: f64 };

function handleEvent(e: Event): void {
  if (e.type === "click") {
    console.log("click x:", e.x);
    console.log("click y:", e.y);
  } else if (e.type === "keypress") {
    console.log("key code:", e.code);
  } else if (e.type === "scroll") {
    console.log("scroll delta:", e.delta);
  }
}

function isClick(e: Event): i32 {
  if (e.type === "click") {
    return 1;
  }
  return 0;
}

const click: Event = { type: "click", x: 100, y: 200 };
const key: Event = { type: "keypress", code: 65 };
const scroll: Event = { type: "scroll", delta: -1.5 };

handleEvent(click);     // click x: 100 / click y: 200
handleEvent(key);       // key code: 65
handleEvent(scroll);    // scroll delta: -1.5

console.log(isClick(click));   // 1
console.log(isClick(key));     // 0
