type i32 = number;

export function _start(): void {
  console.log("stdout line");
  console.error("error: something went wrong");
  console.warn("warn: check this value:", 42);
  console.log("done");
}

_start();
