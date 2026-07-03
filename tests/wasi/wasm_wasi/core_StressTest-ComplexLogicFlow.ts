type i32 = number;
export function complexFlow(input: i32): i32 {
  let x = 0;

  for (let i = 0; i < input; i++) {
    switch (i % 3) {
      case 0:
        x += 5;
        if (x > 50) break; // Should break the switch, not the loop
        continue; // Should skip the x++ and go to next loop iteration
      case 1:
        x += 2;
        break;
      default:
        x -= 1;
        break;
    }
    x++; 
  }

  return x;
}

console.log(complexFlow(10)); // Expected output: 29