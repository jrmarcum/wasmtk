/**
 * decltypes.ts — which variable declarations lack a type (owner rule, 2026-09-28)
 *
 * Every `let` / `const` / `var` states its type on its FIRST definition; a later assignment needs
 * none. This module only FINDS the declarations that break the rule, so the compiler (`wasic`, which
 * refuses them) and `hybrid --auto` (which keeps such a function in the TS host instead of routing
 * it to WASM) apply one definition. Pure: no I/O, no compiler state.
 *
 * Not flagged, because TypeScript forbids a type there: `for…of` / `for…in` bindings and `catch`
 * bindings (neither matches `NAME =`). Not flagged because the type is already written: a function
 * value whose parameters and return type are all annotated. Not flagged here: a counting-`for`
 * counter (`for (let i = 0; …)`), which is an integer by standard and checked where wasic emits the
 * loop.
 *
 * @license MIT
 */

import { maskCode } from "./varscope.ts";

/** One untyped first declaration: where it starts in the source, and its shape. */
export interface UntypedDecl {
  /** Offset of the `let` / `const` / `var` keyword in the source. */
  index: number;
  keyword: string;
  /** `name`: `let x = …`. `pattern`: `const [a, b] = …` / `const { x } = …`. */
  kind: "name" | "pattern";
  /** The bound name (kind `name`) or the pattern's opening bracket (kind `pattern`). */
  target: string;
}

/**
 * True when the initialiser at `at` (in MASKED source) is a function value whose signature states
 * every type: `(a: i32, b: i32): i32 => …` or `function (n: number): number { … }`. Nothing is
 * inferred there, so repeating the signature as a declaration type would add no information. A
 * missing parameter or return type still fails the rule.
 */
export function isFullyTypedFunction(masked: string, at: number): boolean {
  let k = at;
  const skipWs = () => {
    while (k < masked.length && /\s/.test(masked[k])) k++;
  };
  skipWs();
  const isFn = /^(?:async\s+)?function\b/.test(masked.slice(k));
  const head = /^(?:async\s+)?(?:function\b\s*[\w$]*\s*)?/.exec(masked.slice(k))![0];
  k += head.length;
  if (masked[k] !== "(") return false;
  let depth = 0;
  const open = k;
  for (; k < masked.length; k++) {
    if ("([{<".includes(masked[k])) depth++;
    else if (")]}>".includes(masked[k]) && masked[k - 1] !== "=" && --depth === 0) break;
  }
  if (k >= masked.length) return false;
  // Top-level parameter list split on commas; each parameter needs its own `: Type`.
  const params: string[] = [];
  let cur = "";
  depth = 0;
  for (const c of masked.slice(open + 1, k)) {
    if ("([{<".includes(c)) depth++;
    else if (")]}>".includes(c)) depth--;
    if (c === "," && depth === 0) {
      params.push(cur);
      cur = "";
    } else cur += c;
  }
  if (cur.trim()) params.push(cur);
  if (params.some((p) => !p.includes(":"))) return false;
  k++;
  skipWs();
  if (masked[k] !== ":") return false; // no return type
  if (isFn) return true;
  return /^[^;\n]*?=>/.test(masked.slice(k));
}

/**
 * Every untyped first declaration in `src`, names first, then patterns, each in source order.
 * Strings and comments are masked, so a declaration-shaped string is never flagged.
 */
export function findUntypedDeclarations(src: string): UntypedDecl[] {
  const masked = maskCode(src);
  const found: UntypedDecl[] = [];
  // `let|const|var NAME =` with no `: Type` before the `=`.
  for (const m of masked.matchAll(/\b(let|const|var)\s+([A-Za-z_$][\w$]*)\s*=(?![=>])/g)) {
    const before = masked.slice(Math.max(0, m.index! - 16), m.index!);
    if (/\bfor\s*\(\s*$/.test(before)) continue; // counting-for counter: the integer rule applies
    if (isFullyTypedFunction(masked, m.index! + m[0].length)) continue;
    found.push({ index: m.index!, keyword: m[1], kind: "name", target: m[2] });
  }
  // A destructuring pattern needs a type on the pattern: `const [a, b]: [i32, i32] = …`.
  for (const m of masked.matchAll(/\b(let|const|var)\s*([\[{])/g)) {
    const open = m.index! + m[0].length - 1;
    const close = m[2] === "[" ? "]" : "}";
    let depth = 0;
    let end = -1;
    for (let k = open; k < masked.length; k++) {
      if (masked[k] === m[2]) depth++;
      else if (masked[k] === close && --depth === 0) {
        end = k;
        break;
      }
    }
    if (end < 0) continue;
    const after = masked.slice(end + 1).trimStart();
    if (/^(of|in)\b/.test(after)) continue; // for-of / for-in binding: TypeScript forbids a type
    if (after.startsWith("=")) {
      found.push({ index: m.index!, keyword: m[1], kind: "pattern", target: m[2] });
    }
  }
  return found;
}
