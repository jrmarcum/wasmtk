type i32 = number;
export function testStateMachine(input: i32): i32 {
  let state = 0;
  let counter = 0;

  for (let i = 0; i < input; i++) {
    switch (state) {
      case 0:
        counter += 1;
        state = 1;
        break; // Exits switch, increments i
      case 1:
        counter += 10;
        state = 2;
        break; // Exits switch, increments i
      case 2:
        // No break! Testing fall-through to default
        state = 0;
      default:
        counter += 100;
        break;
    }
  }
  return counter;
}

console.log(testStateMachine(5)); // Example usage