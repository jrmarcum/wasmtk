const prompt = function(message) { if (message) { Javy.IO.writeSync(1, new TextEncoder().encode(message + " ")); } let input = ""; const buffer = new Uint8Array(1); while (true) { const n = Javy.IO.readSync(0, buffer); if (n > 0) { const char = new TextDecoder().decode(buffer); if (char === "\n" || char === "\r") break; input += char; } else if (n === 0) { continue; } else { break; } } return input.trim(); };// wasm_wasi_javy/guessTheNumber.ts
function guessNumber() {
  const num = Math.floor(Math.random() * 10) + 1;
  let guess = null;
  console.log("Guess the number between 1 and 10 inclusive!");
  while (guess !== num) {
    const input = prompt("Your guess: \n");
    if (input === null) {
      console.log("Game cancelled. Goodbye!");
      return;
    }
    guess = Number(input);
    if (isNaN(guess) || guess < 1 || guess > 10) {
      console.log("Please enter a valid number between 1 and 10.");
      guess = null;
      continue;
    }
    if (guess < num) {
      console.log("Too low! Try again.");
    } else if (guess > num) {
      console.log("Too high! Try again.");
    }
  }
  console.log(`Congratulations! The number was ${num}`);
}
guessNumber();
export {
  guessNumber
};
