type i32 = number;

type Action =
  | { type: "start"; priority: i32 }
  | { type: "stop"; code: i32 }
  | { type: "pause" };

function processAction(action: Action): i32 {
  switch (action.type) {
    case "start":
      return action.priority * 10;
    case "stop":
      return action.code;
    case "pause":
      return 0;
  }
}

export function testSwitchDispatch(): void {
  console.log("--- Test 2: Switch Case Dispatch ---");

  const a1: Action = { type: "start", priority: 3 };
  const a2: Action = { type: "stop", code: 404 };
  const a3: Action = { type: "pause" };

  console.log("Start Result:", processAction(a1)); // Expected: 30
  console.log("Stop Result:", processAction(a2)); // Expected: 404
  console.log("Pause Result:", processAction(a3)); // Expected: 0
}

testSwitchDispatch();
