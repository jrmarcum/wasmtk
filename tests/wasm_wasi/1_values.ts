// @allow-output-diff: f64-to-string precision on 7.0/3.0 (needs 17 sig-figs; $__f64_to_str ×1e15 limit — same class as 7a_constants). The "go"+"lang" string-literal-concat-in-console.log bug was fixed independently 2026-06-08.
console.log("go" + "lang");
console.log("1+1 =", 1 + 1);
console.log("7.0/3.0 =", 7.0 / 3.0);
console.log(true && false);
console.log(true || false);
console.log(!true);
