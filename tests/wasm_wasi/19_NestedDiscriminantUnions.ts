type i32 = number;

interface AddOp { type: "add"; value: i32; }
interface MulOp { type: "mul"; value: i32; }
type MathOp = AddOp | MulOp;

interface SuccessResult {
  status: "success"; // Outer Tag index 0
  operation: MathOp;  // Nested Flat Super-Struct
}

interface FailureResult {
  status: "failure"; // Outer Tag index 1
  errorCode: i32;
}

type CommandResult = SuccessResult | FailureResult;

export function evaluateResult(res: CommandResult, base: i32): i32 {
  if (res.status === "success") {
    // Narrowing successful: extract nested variant
    const op = res.operation;
    if (op.type === "add") {
      return base + op.value;
    } else {
      return base * op.value;
    }
  } else {
    return res.errorCode * -1;
  }
}

export function testNestedUnions(): void {
  console.log("--- Test 2: Nested Union Tags ---");

  const r1: CommandResult = {
    status: "success",
    operation: { type: "add", value: 15 }
  };
  console.log("Nested Add Result:", evaluateResult(r1, 10)); // Expected: 10 + 15 = 25

  const r2: CommandResult = {
    status: "success",
    operation: { type: "mul", value: 3 }
  };
  console.log("Nested Mul Result:", evaluateResult(r2, 10)); // Expected: 10 * 3 = 30

  const r3: CommandResult = {
    status: "failure",
    errorCode: 404
  };
  console.log("Failure Mapping:", evaluateResult(r3, 10));    // Expected: -404
}

testNestedUnions();