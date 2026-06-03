type i32 = number; // Alias for 32-bit integer
export function testSwitch(value: i32): i32 {
  let result = 0;

  switch (value) {
    case 1:
      result = 10;
      break;
    case 2:
      result = 20;
      break;
    case 3:
    case 4: // Testing fall-through
      result = 40;
      break;
    case 100: // Large gap to test how you handle dense vs sparse tables
      result = 1000;
      break;
    default:
      result = -1;
      break;
  }

  return result;
}

console.log(testSwitch(1)); // Should return 10