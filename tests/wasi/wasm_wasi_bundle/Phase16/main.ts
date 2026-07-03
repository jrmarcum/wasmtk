// Phase 16: Additional module system features
//
// Exercises:
//   - Default import           (import compute from "./lib.ts")
//   - Namespace import         (import * as mu from "./mathutils.ts")
//   - Named import             (import { negate } from "./lib.ts")
//   - Named re-export          (square re-exported by mathutils from lib)
//
// Expected output (one value per line):
//   7
//   10
//   9
//   16
//   -6

import compute from "./lib.ts";           // default import
import * as mu from "./mathutils.ts";     // namespace import
import { square } from "./mathutils.ts";  // named import of a re-exported symbol
import { negate } from "./lib.ts";        // named import from lib directly

const a: i32 = compute(3, 4);   // lib default: 3+4 = 7
console.log(a);                  // 7

const b: i32 = mu.double(5);    // mathutils.double: 5*2 = 10
console.log(b);                  // 10

const c: i32 = mu.triple(3);    // mathutils.triple: 3*3 = 9
console.log(c);                  // 9

const d: i32 = square(4);       // lib.square (via re-export): 4*4 = 16
console.log(d);                  // 16

const e: i32 = negate(6);       // lib.negate: 0-6 = -6
console.log(e);                  // -6
