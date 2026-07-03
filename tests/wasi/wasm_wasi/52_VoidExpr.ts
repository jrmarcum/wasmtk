// Phase 52.5 — `void expr` evaluates the expression for its side effects and discards the result.
type i32 = number;

let counter: i32 = 0;

function bump(): void {
  counter = counter + 1;
}

function addAndGet(n: i32): i32 {
  counter = counter + n;
  return counter;
}

void bump(); // counter -> 1 (void call, no value)
void addAndGet(10); // counter -> 11, returned value discarded
void 0; // no-op
void counter; // evaluated, discarded
console.log("counter:", counter); // 11

function inFunc(): i32 {
  const local: i32 = 5;
  void (local + 100); // discarded
  return local;
}
console.log("inFunc:", inFunc()); // 5

class Counter {
  n: i32;
  constructor() {
    this.n = 0;
  }
  bump(): void {
    this.n = this.n + 1;
  }
  value(): i32 {
    return this.n;
  }
}
const ctr: Counter = new Counter();
void ctr.bump(); // void dot-call: runs, nothing dropped
void ctr.bump();
console.log("ctr:", ctr.value()); // 2
