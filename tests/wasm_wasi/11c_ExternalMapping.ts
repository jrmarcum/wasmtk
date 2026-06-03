// External source defines an interface 'logger' with a 'log' function
//@ts-ignore: valid
// deno-lint-ignore-file
import { log } from "./module/LoggerProvider.ts"; // This import is for type checking and documentation purposes only

// modc identifies this from an uploaded .wit or custom section.
type i32 = number; // Placeholder for the actual i32 type
export function testExternalCall(msgPtr: i32): void {
  // This call must be mapped to the identified external interface
  //@ts-ignore: testExternalCall is expected to be called with an i32 pointer to a string message
  log(msgPtr); 
}

testExternalCall(10);