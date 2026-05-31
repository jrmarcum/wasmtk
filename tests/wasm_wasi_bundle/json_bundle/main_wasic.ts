// Shared-heap driver for the JSON (parse + navigate) stdlib capability (brief §5/§7-#3).
//
// Imports the modc-compiled JSON library. After the Phase 18 merge + Stage 0.6 allocator
// unification, every $__malloc inside the library resolves to THIS module's bump cursor, so
// the value tree the parser builds lives on the same heap this program uses — the headline
// "a wasic program gains JSON it had no native support for, sharing one live heap" case.
//
// The JSON document is passed as a single wasic string literal. Note the double layer of
// escaping: `\"` becomes a JSON quote, and `\\n` becomes a JSON `\n` escape (a real
// backslash-n in the bytes the parser sees) so the library's escape-decoding path is
// exercised, not pre-decoded by wasic.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out
// of bounds, trapping the module so the `run` step exits non-zero and the test fails. (A
// wasic uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)

type i32 = number;

import { jsonParse, jsonType, jsonInt, jsonBool, jsonArrayLen, jsonArrayGet, jsonObjectLen, jsonStrLen, jsonStrCharAt, jsonStrEq, jsonGet, jsonHas } from "./json_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// Tags: 0=null 1=bool 2=number 3=string 4=array 5=object
const doc: string = "{\"name\":\"wasmtk\",\"version\":50,\"delta\":-7,\"active\":true,\"tags\":[\"json\",\"wasm\",\"ts\"],\"meta\":{\"stars\":100,\"fork\":false},\"nested\":[1,2,[3,4]],\"line\":\"a\\nb\",\"nothing\":null}";

const root: i32 = jsonParse(doc);

// Root is an object with 9 entries.
console.log("root type:", jsonType(root));
check(jsonType(root) === 5 ? 1 : 0);
console.log("root len:", jsonObjectLen(root));
check(jsonObjectLen(root) === 9 ? 1 : 0);

// Number value.
const ver: i32 = jsonGet(root, "version");
console.log("version type:", jsonType(ver));
check(jsonType(ver) === 2 ? 1 : 0);
console.log("version:", jsonInt(ver));
check(jsonInt(ver) === 50 ? 1 : 0);

// Negative number.
const delta: i32 = jsonGet(root, "delta");
console.log("delta:", jsonInt(delta));
check(jsonInt(delta) === -7 ? 1 : 0);

// Boolean (true).
const active: i32 = jsonGet(root, "active");
console.log("active type:", jsonType(active));
check(jsonType(active) === 1 ? 1 : 0);
check(jsonBool(active) === 1 ? 1 : 0);

// String value + equality + char access.
const name: i32 = jsonGet(root, "name");
console.log("name type:", jsonType(name));
check(jsonType(name) === 3 ? 1 : 0);
check(jsonStrEq(name, "wasmtk") === 1 ? 1 : 0);
check(jsonStrEq(name, "wasmtkX") === 0 ? 1 : 0); // length mismatch
check(jsonStrEq(name, "WASMTK") === 0 ? 1 : 0);  // case mismatch
console.log("name len:", jsonStrLen(name));
check(jsonStrLen(name) === 6 ? 1 : 0);
console.log("name[0]:", jsonStrCharAt(name, 0)); // 'w' = 119
check(jsonStrCharAt(name, 0) === 119 ? 1 : 0);

// Array of strings.
const tags: i32 = jsonGet(root, "tags");
console.log("tags type:", jsonType(tags));
check(jsonType(tags) === 4 ? 1 : 0);
console.log("tags len:", jsonArrayLen(tags));
check(jsonArrayLen(tags) === 3 ? 1 : 0);
const t0: i32 = jsonArrayGet(tags, 0);
const t2: i32 = jsonArrayGet(tags, 2);
check(jsonStrEq(t0, "json") === 1 ? 1 : 0);
check(jsonStrEq(t2, "ts") === 1 ? 1 : 0);

// Nested object.
const meta: i32 = jsonGet(root, "meta");
check(jsonType(meta) === 5 ? 1 : 0);
const stars: i32 = jsonGet(meta, "stars");
console.log("stars:", jsonInt(stars));
check(jsonInt(stars) === 100 ? 1 : 0);
const fork: i32 = jsonGet(meta, "fork");
check(jsonType(fork) === 1 ? 1 : 0);
check(jsonBool(fork) === 0 ? 1 : 0); // false

// Nested arrays.
const nested: i32 = jsonGet(root, "nested");
check(jsonArrayLen(nested) === 3 ? 1 : 0);
const inner: i32 = jsonArrayGet(nested, 2); // [3, 4]
console.log("inner type:", jsonType(inner));
check(jsonType(inner) === 4 ? 1 : 0);
check(jsonArrayLen(inner) === 2 ? 1 : 0);
check(jsonInt(jsonArrayGet(inner, 0)) === 3 ? 1 : 0);
check(jsonInt(jsonArrayGet(inner, 1)) === 4 ? 1 : 0);

// Escape decoding: "a\nb" → 3 bytes, middle byte is a newline (10).
const line: i32 = jsonGet(root, "line");
console.log("line len:", jsonStrLen(line));
check(jsonStrLen(line) === 3 ? 1 : 0);
check(jsonStrCharAt(line, 0) === 97 ? 1 : 0);  // 'a'
check(jsonStrCharAt(line, 1) === 10 ? 1 : 0);  // '\n'
check(jsonStrCharAt(line, 2) === 98 ? 1 : 0);  // 'b'

// Null value.
const nothing: i32 = jsonGet(root, "nothing");
console.log("nothing type:", jsonType(nothing));
check(jsonType(nothing) === 0 ? 1 : 0);

// Absent key + membership.
check(jsonGet(root, "absent") === -1 ? 1 : 0);
console.log("has name:", jsonHas(root, "name"));
console.log("has zzz:", jsonHas(root, "zzz"));
check(jsonHas(root, "name") === 1 ? 1 : 0);
check(jsonHas(root, "zzz") === 0 ? 1 : 0);

console.log("json ok");
