type i32 = number;
export function testDoWhileLogic(limit: i32): i32 {
  let result = 0;
  let i = 0;

  do {
    if (i % 2 === 0) {
      result += i;
    } else {
      result -= 1;
    }
    
    // Testing a break inside the do-while
    if (result > 100) {
      break;
    }

    i++;
  } while (i < limit);

  return result;
}

console.log(testDoWhileLogic(10)); // Should output the result of the function with limit 10
console.log(testDoWhileLogic(20)); // Should output the result of the function with limit 20