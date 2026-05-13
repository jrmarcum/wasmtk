// Phase_11a_Export.ts
type i32 = number;

/**
 * @export
 * This should be identified by modc to generate 
 * a WIT-compatible export shim.
 */
export function add(a: i32, b: i32): i32 {
  return a + b;
}