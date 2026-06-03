function createCounter() {
  let count = 0;
  return {
    inc: () => { count++; return count; },
    dec: () => { count--; return count; }
  };
}

console.log(createCounter().inc()); // 1
console.log(createCounter().dec()); // -1
const counter1 = createCounter();
console.log(counter1.inc()); // 1
console.log(counter1.inc()); // 2
const counter2 = createCounter();
console.log(counter2.inc()); // 1
console.log(counter1.dec()); // 1
console.log(counter2.dec()); // 0   