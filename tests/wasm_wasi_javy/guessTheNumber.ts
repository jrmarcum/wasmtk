// guessTheNumber.ts
export function guessNumber() {
  // Get a random integer from 1 to 10 inclusive
  const num: number = Math.floor(Math.random() * 10) + 1;  // cleaner & correct range

  let guess: number | null = null;  // Use null initially

  console.log("Guess the number between 1 and 10 inclusive!");

  while (guess !== num) {
    const input = prompt("Your guess: \n");  // prompt returns string | null

    if (input === null) {
      console.log("Game cancelled. Goodbye!");
      return;  // User pressed Cancel / Ctrl+C
    }

    // Convert to number and validate
    guess = Number(input);

    if (isNaN(guess) || guess < 1 || guess > 10) {
      console.log("Please enter a valid number between 1 and 10.");
      guess = null;           // Reset so loop continues
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

// Run the game
guessNumber();