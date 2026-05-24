type i32 = number;
type f64 = number;

// Concrete monomorphized box wrappers — replaces generic Box<T>
class BoxI32 {
  value: i32;
  constructor(val: i32) {
    this.value = val;
  }
  unwrap(): i32 {
    return this.value;
  }
}

class BoxF64 {
  value: f64;
  constructor(val: f64) {
    this.value = val;
  }
  unwrap(): f64 {
    return this.value;
  }
}

// Concrete monomorphized pair-sum functions — replaces generic Pair<K,V>.sumAsFloat().
// Uses locals to avoid dotCallExprMatch greedy-paren issues on compound return expressions.
function sumBoxII(a: BoxI32, b: BoxI32): f64 {
  const av: i32 = a.unwrap();
  const bv: i32 = b.unwrap();
  return (av as f64) + (bv as f64);
}

function sumBoxFI(a: BoxF64, b: BoxI32): f64 {
  const av: f64 = a.unwrap();
  const bv: i32 = b.unwrap();
  return av + (bv as f64);
}

export function testNestedGenerics(): void {
  console.log("--- Test 1: Nested Monomorphization ---");

  const box1 = new BoxI32(10);
  const box2 = new BoxI32(20);
  console.log("Int-Int Sum:", sumBoxII(box1, box2)); // Expected: 30

  const box3 = new BoxF64(5.5);
  const box4 = new BoxI32(4);
  console.log("Float-Int Sum:", sumBoxFI(box3, box4)); // Expected: 9.5
}

testNestedGenerics();
