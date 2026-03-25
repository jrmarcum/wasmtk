const prompt = function(message) { if (message) { Javy.IO.writeSync(1, new TextEncoder().encode(message + " ")); } let input = ""; const buffer = new Uint8Array(1); while (true) { const n = Javy.IO.readSync(0, buffer); if (n > 0) { const char = new TextDecoder().decode(buffer); if (char === "\n" || char === "\r") break; input += char; } else if (n === 0) { continue; } else { break; } } return input.trim(); };// complex.ts
function add(a, b) {
  return a + b;
}
function multiply(a, b) {
  return a * b;
}
(function main() {
  console.log(add(2, 5));
  console.log(multiply(2, 5));
})();
export {
  add,
  multiply
};
