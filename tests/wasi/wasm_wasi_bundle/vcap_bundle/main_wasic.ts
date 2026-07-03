// Virtual capability imports — feature-level tree-shake (stdlib-bundling brief §7-#4).
//
// Instead of importing a capability from a fixture `.wasm` path, this driver imports each
// of the five Tier-1 stdlib capabilities by NAME via the `wasmtk:<cap>` specifier. The
// embedded capability libraries (src/wasm/caps_bytes.ts) are merged on demand — only the
// capabilities actually imported here get bundled.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out
// of bounds, trapping the module so the `run` step exits non-zero and the test fails.

type i32 = number;

import { setNew, setAdd, setHas, setSize } from "wasmtk:set";
import { mapNew, mapSet, mapGet, mapHas } from "wasmtk:map";
import { isLeapYear, daysInMonth } from "wasmtk:date";
import { jsonParse, jsonType, jsonInt, jsonGet } from "wasmtk:json";
import { reTest } from "wasmtk:regex";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// ── Set (shared heap) ──────────────────────────────────────────────────────
const s: i32 = setNew();
setAdd(s, 10);
setAdd(s, 20);
setAdd(s, 10); // duplicate
check(setSize(s) === 2 ? 1 : 0);
check(setHas(s, 10));
check(setHas(s, 99) === 0 ? 1 : 0);

// ── Map (shared heap) ──────────────────────────────────────────────────────
const m: i32 = mapNew();
mapSet(m, 1, 100);
mapSet(m, 2, 200);
check(mapGet(m, 1, -1) === 100 ? 1 : 0);
check(mapGet(m, 9, -1) === -1 ? 1 : 0);
check(mapHas(m, 2));

// ── Date (leaf) ────────────────────────────────────────────────────────────
check(isLeapYear(2024));
check(isLeapYear(2023) === 0 ? 1 : 0);
check(daysInMonth(2024, 2) === 29 ? 1 : 0);

// ── JSON (string input across the merge) ───────────────────────────────────
const obj: i32 = jsonParse("{ \"n\": 42 }");
check(jsonType(obj) === 5 ? 1 : 0); // 5 = object
const n: i32 = jsonGet(obj, "n");
check(jsonInt(n) === 42 ? 1 : 0);

// ── RegExp (leaf, string input) ────────────────────────────────────────────
check(reTest("a.c", "abc"));
check(reTest("a.c", "axd") === 0 ? 1 : 0);

console.log("all virtual-capability checks passed");
