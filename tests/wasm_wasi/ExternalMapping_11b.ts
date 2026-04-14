// External source defines an interface 'logger' with a 'log' function
//@ts-ignore: valid
// deno-lint-ignore-file
import { assert } from "jsr:@std/assert";
import test from "node:test";

// modc identifies this from an uploaded .wit or custom section.
type i32 = number; // Placeholder for the actual i32 type
export function testExternalCall(msgPtr: i32): void {
  // This call must be mapped to the identified external interface
  //@ts-ignore: testExternalCall is expected to be called with an i32 pointer to a string message
  logger.log(msgPtr); 
}

testExternalCall(10);