type i32 = number; type f64 = number;
function f(x: i32): i32 { return x ?? 5; }
console.log(f(0));
