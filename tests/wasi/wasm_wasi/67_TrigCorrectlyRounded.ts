// Correctly-rounded sin/cos/tan regression test.
// mathlib's sin/cos/tan are implemented in double-double arithmetic and produce the
// IEEE-754 correctly-rounded result (validated bit-for-bit vs a BigInt fixed-point
// oracle). Each value below is the correctly-rounded double; for these specific args
// V8's Math.* also happens to return the correctly-rounded value, so the wasm output
// is byte-identical to the native-TS baseline. If the dd trig ever regresses (e.g. an
// optimizer reassociates the double-double ops), the printed digits change and the
// output-diff runner fails. Values span the direct kernel, medium args, and the
// large-argument Veltkamp reduction (5e8, 1e9).
function id(x: f64): f64 { return x + 0.0; }

console.log(Math.sin(id(1.0)));            // 0.8414709848078965
console.log(Math.cos(id(1.0)));            // 0.5403023058681398
console.log(Math.tan(id(1.0)));            // 1.5574077246549023
console.log(Math.sin(id(0.5)));            // 0.479425538604203
console.log(Math.cos(id(0.5)));            // 0.8775825618903728
console.log(Math.tan(id(0.5)));            // 0.5463024898437905
console.log(Math.sin(id(2.5)));            // 0.5984721441039565
console.log(Math.cos(id(2.5)));            // -0.8011436155469337
console.log(Math.tan(id(2.5)));            // -0.7470222972386603
console.log(Math.sin(id(3.14159)));        // 0.00000265358979335273
console.log(Math.cos(id(3.14159)));        // -0.9999999999964793
console.log(Math.sin(id(100.0)));          // -0.5063656411097588
console.log(Math.cos(id(100.0)));          // 0.8623188722876839
console.log(Math.tan(id(100.0)));          // -0.5872139151569291
console.log(Math.sin(id(123456789.123)));  // 0.9998429395520451
console.log(Math.cos(id(123456789.123)));  // 0.017722760166677856
console.log(Math.tan(id(123456789.123)));  // 56.41575748635018
console.log(Math.sin(id(500000000.0)));    // -0.28470407323754404
console.log(Math.cos(id(500000000.0)));    // -0.9586154550610746
console.log(Math.tan(id(500000000.0)));    // 0.2969950794496686
console.log(Math.sin(id(1000000000.0)));   // 0.5458434494486996
console.log(Math.cos(id(1000000000.0)));   // 0.8378871813639024
console.log(Math.tan(id(1000000000.0)));   // 0.6514522021451413
