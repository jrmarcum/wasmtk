// src/varscope.ts — #14 Route A 2e.7b: the `var` → `let` consumption gate.
//
// Policy (cmem/dynrt-design.md "Language consumption profile"): ES6 (`let`/`const`) is the BASE preferred
// form. A legacy `var` is AUTO-REPAIRED to `let` when it is PROVABLY safe (no behavioral difference), and
// HARD-ERRORS when it is not (the compiler never silently "repairs" an unsafe `var` — silent-wrong is the
// failure mode we are eliminating).
//
// A `var` is UNSAFE to rewrite to `let` when it relies on `var`-specific behavior:
//   (1) block-escape  — declared in a nested block, referenced after that block closes (var leaks; let
//       would be a ReferenceError);
//   (2) use-before-declaration — referenced textually before its declaration (var hoists to `undefined`;
//       let is a TDZ ReferenceError);
//   (3) redeclaration — the same name declared twice in one function (legal for var; duplicate-let is a
//       SyntaxError);
//   (4) loop-closure capture — `for (var i …)` whose body contains a closure (`function`/`=>`) — `var`
//       shares one binding (3,3,3); `let` is per-iteration (0,1,2), a behavior change.
//
// Analysis is CODE-ONLY (string/comment spans are masked out first, so a `var` inside a string literal —
// e.g. dynrt eval source — is never touched). It is CONSERVATIVE: when safety can't be proven it ERRORS
// rather than rewrite. Reference resolution uses a brace-stack scope model with a function-body heuristic;
// genuinely ambiguous constructs surface as a (sound) hard error, not a silent rewrite.

/** Replace every string-literal and comment character with a space, preserving length + newlines, so the
 *  result is a "code skeleton" safe to scan for structure/identifiers without matching inside strings. */
export function maskCode(src: string): string {
  const out: string[] = [];
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    // line comment
    if (c === "/" && i + 1 < n && src[i + 1] === "/") {
      while (i < n && src[i] !== "\n") {
        out.push(src[i] === "\n" ? "\n" : " ");
        i++;
      }
      continue;
    }
    // block comment
    if (c === "/" && i + 1 < n && src[i + 1] === "*") {
      out.push(" ", " ");
      i += 2;
      while (i < n && !(src[i] === "*" && i + 1 < n && src[i + 1] === "/")) {
        out.push(src[i] === "\n" ? "\n" : " ");
        i++;
      }
      if (i < n) {
        out.push(" ", " ");
        i += 2;
      }
      continue;
    }
    // string / template literal
    if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      out.push(" "); // the opening quote
      i++;
      while (i < n) {
        if (src[i] === "\\") { // escape — skip the escaped char
          out.push(" ", " ");
          i += 2;
          continue;
        }
        if (src[i] === quote) {
          out.push(" ");
          i++;
          break;
        }
        out.push(src[i] === "\n" ? "\n" : " ");
        i++;
      }
      continue;
    }
    out.push(c);
    i++;
  }
  return out.join("");
}

const CONTROL_KEYWORDS = new Set(["if", "for", "while", "switch", "catch", "with"]);
const IDENT_RE = /[A-Za-z_$][A-Za-z0-9_$]*/y;

function lineCol(src: string, idx: number): string {
  let line = 1;
  let col = 1;
  for (let i = 0; i < idx && i < src.length; i++) {
    if (src[i] === "\n") {
      line++;
      col = 1;
    } else col++;
  }
  return `${line}:${col}`;
}

/** Index of the `{`/`}` (or `(`/`)`) matching the opener at `open` in `masked`. -1 if unbalanced. */
function matchBrace(masked: string, open: number, openCh: string, closeCh: string): number {
  let depth = 0;
  for (let i = open; i < masked.length; i++) {
    if (masked[i] === openCh) depth++;
    else if (masked[i] === closeCh) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** True if the `{` at index `j` (in masked) opens a FUNCTION body (vs a control block or object literal):
 *  preceded by `=>`, or by `)` whose matching `(` follows a non-control identifier (a call/def signature). */
function isFunctionBrace(masked: string, j: number): boolean {
  let k = j - 1;
  while (k >= 0 && /\s/.test(masked[k])) k--;
  if (k >= 1 && masked[k] === ">" && masked[k - 1] === "=") return true; // `=> {`
  if (k < 0 || masked[k] !== ")") return false;
  // find the matching '(' of this ')'
  let depth = 0;
  let p = k;
  for (; p >= 0; p--) {
    if (masked[p] === ")") depth++;
    else if (masked[p] === "(") {
      depth--;
      if (depth === 0) break;
    }
  }
  if (p < 0) return false;
  let q = p - 1;
  while (q >= 0 && /\s/.test(masked[q])) q--;
  if (q < 0) return false;
  // word immediately before the '(' — a control keyword ⇒ NOT a function
  let s = q;
  while (s >= 0 && /[A-Za-z0-9_$]/.test(masked[s])) s--;
  const word = masked.slice(s + 1, q + 1);
  if (word.length === 0) return false; // e.g. `) (` — not a signature
  return !CONTROL_KEYWORDS.has(word);
}

/** For position `p` (in masked), the [start,end] of the nearest enclosing FUNCTION body, or whole-source
 *  range when `p` is at module scope. `start` is just inside the `{`; `end` is the matching `}`. */
function enclosingFunctionRange(masked: string, p: number): [number, number] {
  const stack: number[] = []; // indices of currently-open '{'
  let fnStart = 0;
  let fnEnd = masked.length;
  let found = false;
  for (let i = 0; i < p; i++) {
    if (masked[i] === "{") stack.push(i);
    else if (masked[i] === "}") stack.pop();
  }
  // walk outward from the innermost open brace to the first function brace still enclosing p
  for (let s = stack.length - 1; s >= 0; s--) {
    const open = stack[s];
    if (isFunctionBrace(masked, open)) {
      const close = matchBrace(masked, open, "{", "}");
      if (close > p) {
        fnStart = open + 1;
        fnEnd = close;
        found = true;
        break;
      }
    }
  }
  if (!found) {
    fnStart = 0;
    fnEnd = masked.length;
  }
  return [fnStart, fnEnd];
}

/** The [start,end] of the nearest enclosing BLOCK (`{…}`, function or control), or the given function
 *  range when the declaration sits directly in a function/module body. */
function enclosingBlockRange(
  masked: string,
  p: number,
  fnRange: [number, number],
): [number, number] {
  const stack: number[] = [];
  for (let i = 0; i < p; i++) {
    if (masked[i] === "{") stack.push(i);
    else if (masked[i] === "}") stack.pop();
  }
  if (stack.length === 0) return fnRange;
  const open = stack[stack.length - 1];
  if (open + 1 === fnRange[0]) return fnRange; // directly in the function body
  const close = matchBrace(masked, open, "{", "}");
  if (close < 0) return fnRange;
  return [open + 1, close];
}

interface RefScan {
  beforeDecl: boolean; // a reference before the declaration (use-before-declaration)
  afterBlock: boolean; // a reference after the enclosing block closes but within the function (leak)
  redeclared: boolean; // a second var/let/const of the same name within the function
}

/** Scan the function range for whole-word references / redeclarations of `name`, ignoring property
 *  access (`.name`) and the declaration site itself. */
function scanRefs(
  masked: string,
  name: string,
  declStart: number,
  declEnd: number,
  fnRange: [number, number],
  blockEnd: number,
): RefScan {
  const res: RefScan = { beforeDecl: false, afterBlock: false, redeclared: false };
  const re = new RegExp(`[A-Za-z_$][A-Za-z0-9_$]*`, "g");
  let m: RegExpExecArray | null;
  const lo = fnRange[0];
  const hi = fnRange[1];
  while ((m = re.exec(masked)) !== null) {
    if (m.index < lo || m.index >= hi) continue;
    if (m[0] !== name) continue;
    const at = m.index;
    if (at >= declStart && at < declEnd) continue; // the declaration's own name token
    // property access `.name` is not a variable reference
    let b = at - 1;
    while (b >= 0 && /\s/.test(masked[b])) b--;
    if (b >= 0 && masked[b] === ".") continue;
    // is this a (re)declaration? preceded by var/let/const
    const declKw = precedingDeclKeyword(masked, at);
    if (declKw) {
      res.redeclared = true;
      continue;
    }
    if (at < declStart) res.beforeDecl = true;
    else if (at >= blockEnd) res.afterBlock = true;
  }
  return res;
}

/** If the identifier at `at` is immediately preceded (one token back) by `var`/`let`/`const`, return it. */
function precedingDeclKeyword(masked: string, at: number): string | null {
  let b = at - 1;
  while (b >= 0 && /\s/.test(masked[b])) b--;
  const e = b;
  while (b >= 0 && /[A-Za-z0-9_$]/.test(masked[b])) b--;
  const word = masked.slice(b + 1, e + 1);
  if (word === "var" || word === "let" || word === "const") return word;
  return null;
}

/** True if `var` at `varKw` is a for-header binding (`for ( … var NAME … )`) AND its loop body contains a
 *  closure (`function`/`=>`) — i.e. a loop-closure capture that `let` would change. */
function isLoopClosureCapture(masked: string, varKw: number): boolean {
  // walk left to see if we're inside a `for (` header
  let depth = 0;
  let i = varKw - 1;
  for (; i >= 0; i--) {
    const c = masked[i];
    if (c === ")") depth++;
    else if (c === "(") {
      if (depth === 0) break;
      depth--;
    }
  }
  if (i < 0) return false;
  let q = i - 1;
  while (q >= 0 && /\s/.test(masked[q])) q--;
  let s = q;
  while (s >= 0 && /[A-Za-z0-9_$]/.test(masked[s])) s--;
  if (masked.slice(s + 1, q + 1) !== "for") return false;
  // header runs to the matching ')'
  const headerEnd = matchBrace(masked, i, "(", ")");
  if (headerEnd < 0) return false;
  // the body is the next `{ … }` (or a single statement up to the next ';')
  let bodyStart = headerEnd + 1;
  while (bodyStart < masked.length && /\s/.test(masked[bodyStart])) bodyStart++;
  let bodyEnd: number;
  if (masked[bodyStart] === "{") {
    bodyEnd = matchBrace(masked, bodyStart, "{", "}");
    if (bodyEnd < 0) bodyEnd = masked.length;
  } else {
    bodyEnd = masked.indexOf(";", bodyStart);
    if (bodyEnd < 0) bodyEnd = masked.length;
  }
  const body = masked.slice(bodyStart, bodyEnd + 1);
  return /=>/.test(body) || /\bfunction\b/.test(body);
}

/** Thrown by {@link gateVarToLet} when a `var` cannot be safely auto-repaired to `let`. The message
 *  carries the `line:col` and the specific reason (block-escape / use-before-declaration / redeclaration /
 *  loop-closure capture). */
export class VarGateError extends Error {}

/** Apply the gate. Returns `src` with provably-safe `var` keywords rewritten to `let`; throws
 *  `VarGateError` (with line:col + reason) on the first unsafe `var`. No-op on var-free source. */
export function gateVarToLet(src: string): string {
  const masked = maskCode(src);
  // collect `var NAME` declaration sites (code-only)
  const decls: Array<{ kw: number; nameStart: number; nameEnd: number; name: string }> = [];
  const re = /\bvar\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(masked)) !== null) {
    const kw = m.index;
    // must be followed by whitespace then an identifier (a declaration, not a stray token)
    let j = kw + 3;
    while (j < masked.length && /\s/.test(masked[j])) j++;
    IDENT_RE.lastIndex = j;
    const im = IDENT_RE.exec(masked);
    if (!im || im.index !== j) continue;
    decls.push({ kw, nameStart: j, nameEnd: j + im[0].length, name: im[0] });
  }
  if (decls.length === 0) return src;

  // classify each; collect rewrite positions
  const rewriteAt: number[] = [];
  for (const d of decls) {
    const fnRange = enclosingFunctionRange(masked, d.kw);
    const blockRange = enclosingBlockRange(masked, d.kw, fnRange);
    const refs = scanRefs(masked, d.name, d.nameStart, d.nameEnd, fnRange, blockRange[1]);
    let reason = "";
    if (refs.beforeDecl) {
      reason =
        `'${d.name}' is referenced before its declaration (relies on var hoisting; let has a temporal dead zone)`;
    } else if (refs.afterBlock) {
      reason =
        `'${d.name}' is referenced after its block closes (relies on var function-scoping; let is block-scoped)`;
    } else if (refs.redeclared) {
      reason =
        `'${d.name}' is redeclared in the same function (legal for var; duplicate let is a SyntaxError)`;
    } else if (isLoopClosureCapture(masked, d.kw)) {
      reason =
        `loop variable '${d.name}' is captured by a closure in the loop body (var shares one binding; let is per-iteration — a behavior change)`;
    }
    if (reason) {
      throw new VarGateError(
        `❌ wasic: cannot auto-repair 'var' at ${lineCol(src, d.kw)} — ${reason}.\n` +
          `   ES6 'let'/'const' is the required form. Rewrite this declaration manually.`,
      );
    }
    rewriteAt.push(d.kw);
  }

  // rewrite `var` → `let` at each safe site (descending so indices stay valid)
  let result = src;
  rewriteAt.sort((a, b) => b - a);
  for (const kw of rewriteAt) {
    result = result.slice(0, kw) + "let" + result.slice(kw + 3);
  }
  return result;
}
