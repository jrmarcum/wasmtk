// Phase 40: declare const with inline object type maps to WASM imports from "env".
// External methods are used only in exported functions — top-level code avoids external calls.
// deno-lint-ignore-file
type i32 = number;

declare const storage: {
  write(key: i32, value: i32): void;
  read(key: i32): i32;
};

export function storeValue(key: i32, value: i32): void {
  storage.write(key, value);
}

export function loadValue(key: i32): i32 {
  return storage.read(key);
}

console.log(300);
