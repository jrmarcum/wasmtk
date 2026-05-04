// Phase 40: declare interface + declare const → named external interface binding.
// deno-lint-ignore-file
type i32 = number;

declare interface Logger {
  log(ptr: i32): void;
  getLevel(): i32;
}

declare const logger: Logger;

export function writeLog(msg: i32): void {
  logger.log(msg);
}

export function getLogLevel(): i32 {
  return logger.getLevel();
}

console.log(6);
