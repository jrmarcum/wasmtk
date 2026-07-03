// Phase 29: Getters and Setters
// Tests: f64 getter/setter pair, i32 getter/setter pair, computed getter,
//        setter with validation logic, this.prop inside methods, chained read-after-write.
type i32 = number;
type f64 = number;

class Temperature {
  _celsius: f64;

  constructor(c: f64) {
    this._celsius = c;
  }

  get celsius(): f64 {
    return this._celsius;
  }

  set celsius(c: f64) {
    this._celsius = c;
  }

  // computed getter — converts to Fahrenheit
  get fahrenheit(): f64 {
    return this._celsius * 1.8 + 32.0;
  }
}

class Counter {
  _value: i32;
  _max: i32;

  constructor(max: i32) {
    this._value = 0;
    this._max = max;
  }

  get value(): i32 {
    return this._value;
  }

  set value(v: i32) {
    if (v > this._max) {
      this._value = this._max;
    } else {
      this._value = v;
    }
  }

  get max(): i32 {
    return this._max;
  }
}

function main(): void {
  // Temperature: getter reads backing field
  const t: Temperature = new Temperature(100.0);
  console.log(t.celsius);      // 100
  console.log(t.fahrenheit);   // 212

  // setter updates backing field, getter reflects change
  t.celsius = 0.0;
  console.log(t.celsius);      // 0
  console.log(t.fahrenheit);   // 32

  t.celsius = 20.0;
  console.log(t.celsius);      // 20
  console.log(t.fahrenheit);   // 68

  // Counter: setter clamps to max
  const c: Counter = new Counter(10);
  console.log(c.value);   // 0
  console.log(c.max);     // 10

  c.value = 5;
  console.log(c.value);   // 5

  c.value = 20;           // clamped to max=10
  console.log(c.value);   // 10

  c.value = 3;
  console.log(c.value);   // 3
}

main();
