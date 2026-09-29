type i32 = number;

function risky(k: i32): i32 {
  if (k > 0) throw new Error("boom");
  return k;
}

try {
  risky(1);
} catch (e) {
  console.log(e instanceof Error ? "is error" : "not error");
}
