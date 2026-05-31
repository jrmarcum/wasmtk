// Driver for the Date (UTC integer calendar math) stdlib capability (brief §5/§7-#3).
//
// Imports the modc-compiled Date *leaf* library. Date allocates nothing, so the merge is a
// straight function splice (no allocator unification needed) — this exercises the "leaf
// capability merged when used" path from brief §5, complementing the shared-heap Set/Map.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out
// of bounds, trapping the module so the `run` step exits non-zero and the test fails.
// (A wasic uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)

type i32 = number;

import { isLeapYear, daysInMonth, daysFromCivil, weekdayFromDays, yearFromDays, monthFromDays, dayFromDays } from "./date_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    // Force a WebAssembly trap (memory access out of bounds) → nonzero exit.
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// --- Leap years ---
console.log("leap 2024:", isLeapYear(2024));
console.log("leap 2023:", isLeapYear(2023));
console.log("leap 2000:", isLeapYear(2000));
console.log("leap 1900:", isLeapYear(1900));
check(isLeapYear(2024) === 1 ? 1 : 0); // divisible by 4, not 100
check(isLeapYear(2023) === 0 ? 1 : 0); // not divisible by 4
check(isLeapYear(2000) === 1 ? 1 : 0); // divisible by 400
check(isLeapYear(1900) === 0 ? 1 : 0); // divisible by 100, not 400

// --- Days in month ---
check(daysInMonth(2024, 2) === 29 ? 1 : 0); // leap February
check(daysInMonth(2023, 2) === 28 ? 1 : 0); // common February
check(daysInMonth(2024, 4) === 30 ? 1 : 0); // April
check(daysInMonth(2024, 12) === 31 ? 1 : 0); // December

// --- Civil date -> day count (days since 1970-01-01) ---
console.log("days 1970-01-01:", daysFromCivil(1970, 1, 1));
console.log("days 2000-01-01:", daysFromCivil(2000, 1, 1));
console.log("days 2024-02-29:", daysFromCivil(2024, 2, 29));
console.log("days 1969-12-31:", daysFromCivil(1969, 12, 31));
check(daysFromCivil(1970, 1, 1) === 0 ? 1 : 0);
check(daysFromCivil(2000, 1, 1) === 10957 ? 1 : 0);
check(daysFromCivil(2024, 2, 29) === 19782 ? 1 : 0);
check(daysFromCivil(1969, 12, 31) === -1 ? 1 : 0); // day before the epoch

// --- Weekday (0=Sun .. 6=Sat) ---
console.log("wday epoch:", weekdayFromDays(0));
console.log("wday 2000-01-01:", weekdayFromDays(10957));
console.log("wday 1969-12-31:", weekdayFromDays(-1));
check(weekdayFromDays(0) === 4 ? 1 : 0);     // 1970-01-01 was a Thursday
check(weekdayFromDays(10957) === 6 ? 1 : 0); // 2000-01-01 was a Saturday
check(weekdayFromDays(-1) === 3 ? 1 : 0);    // 1969-12-31 was a Wednesday

// --- Day count -> civil date (round-trip of the conversions above) ---
check(yearFromDays(10957) === 2000 ? 1 : 0);
check(monthFromDays(10957) === 1 ? 1 : 0);
check(dayFromDays(10957) === 1 ? 1 : 0);

check(yearFromDays(19782) === 2024 ? 1 : 0);
check(monthFromDays(19782) === 2 ? 1 : 0);
check(dayFromDays(19782) === 29 ? 1 : 0);

check(yearFromDays(-1) === 1969 ? 1 : 0); // negative day count
check(monthFromDays(-1) === 12 ? 1 : 0);
check(dayFromDays(-1) === 31 ? 1 : 0);

console.log("ymd 19782:", yearFromDays(19782), monthFromDays(19782), dayFromDays(19782));
console.log("date ok");
