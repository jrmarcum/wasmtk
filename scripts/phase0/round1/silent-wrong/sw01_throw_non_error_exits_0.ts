type i32 = number;

function risky(k: i32): i32 {
  if (k === 1) {
    throw new TypeError("bad type");
  }
  if (k === 2) {
    throw 42;
  }
  return k;
}

try {
  risky(1);
} catch (e) {
  console.log("caught 1");
}
try {
  risky(2);
} catch (e) {
  console.log("caught 2");
}
console.log("done");
