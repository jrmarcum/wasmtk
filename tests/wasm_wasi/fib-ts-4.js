const prompt = function(message) { if (message) { Javy.IO.writeSync(1, new TextEncoder().encode(message + " ")); } let input = ""; const buffer = new Uint8Array(1); while (true) { const n = Javy.IO.readSync(0, buffer); if (n > 0) { const char = new TextDecoder().decode(buffer); if (char === "\n" || char === "\r") break; input += char; } else if (n === 0) { continue; } else { break; } } return input.trim(); };// fib-ts-4.ts
function fib(num) {
  var a = 0;
  var b = 1;
  var temp = 0;
  while (num > 0) {
    temp = a;
    a = a + b;
    b = temp;
    num -= 1;
  }
  return a;
}
console.log(`Fibonacci result is: ${fib(10)}`);
export {
  fib
};
