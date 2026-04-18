// Phase 15: Exception handling — try/catch/finally + throw
//
// Expected output (one value per line):
//   5
//   Division by zero
//   -1
//   success
//   finally
//   negative
//   finally
//   custom error
type i32 = number;
function divide(a: i32, b: i32): i32 {
  if (b === 0) {
    throw new Error("Division by zero");
  }
  return a / b;
}

// Basic try/catch: result assigned inside try, catch logs the message.
function safeDivide(a: i32, b: i32): i32 {
  let result: i32 = -1;
  try {
    result = divide(a, b);
  } catch (e) {
    console.log(e instanceof Error ? e.message : String(e));
  }
  return result;
}

// try/catch/finally: finally always runs; catch logs e.message.
function withFinally(x: i32): void {
  try {
    if (x < 0) {
      throw new Error("negative");
    } else {
      console.log("success");
    }
  } catch (e) {
    console.log(e instanceof Error ? e.message : String(e));
  } finally {
    console.log("finally");
  }
}

// throw a string variable (not new Error).
function throwString(msg: string): never {
  throw msg;
}

function testThrowString(): void {
  const msg: string = "custom error";
  try {
    throwString(msg);
  } catch (e) {
    console.log(String(e));
  }
}

const r1 = safeDivide(10, 2);
console.log(r1);          // 5
const r2 = safeDivide(10, 0);
console.log(r2);          // Division by zero  then  -1
withFinally(1);           // success  then  finally
withFinally(-1);          // negative  then  finally
testThrowString();        // custom error
