// Phase_12_InterfaceTypes.ts
type i32 = number;

/**
 * Testing how a dynamic array (Complex Type) 
 * is "seen" by the outside world.
 */
export function getScores(): i32[] {
  return [95, 88, 72];
}

console.log("getScores:", getScores());