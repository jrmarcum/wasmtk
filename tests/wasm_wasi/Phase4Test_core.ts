export function _start(): void {
  // for loop
  let sum = 0;
  for (let i = 0; i < 5; i++) {
    sum += i;
  }
  console.log(sum); // 0+1+2+3+4 = 10

  // while with break
  let x = 0;
  while (true) {
    if (x >= 3) {
      break;
    }
    x++;
  }
  console.log(x); // 3

  // do...while
  let n = 0;
  do {
    n++;
  } while (n < 4);
  console.log(n); // 4

  // switch/case
  const val: number = 2;
  switch (val) {
    case 1:
      console.log(11);
      break;
    case 2:
      console.log(22);
      break;
    default:
      console.log(99);
  }

  // continue
  let evens = 0;
  for (let j = 0; j < 10; j++) {
    if (j % 2 !== 0) {
      continue;
    }
    evens++;
  }
  console.log(evens); // 5
}

_start();
