// LoggerProvider.ts (The "Missing" Module)
type i32 = number;

/** * This satisfies the 'logger.log' interface 
 * @export 
 */
export function log(_msgPtr: i32): void {
  console.log(_msgPtr);
}