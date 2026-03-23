/**
 * @module console_log
 * @description Converts TypeScript console.log(...) calls into WASI fd_write WAT instructions.
 *
 * Handles all common argument patterns:
 *   - String literals:       console.log("hello")
 *   - Numeric variables:     console.log(x)          [i32 or f64]
 *   - Multiple arguments:    console.log("x =", x)   [space-separated]
 *   - Concatenation:         console.log("val: " + x)
 *   - Template literals:     console.log(`val: ${x}`)
 *
 * Each argument segment becomes one iovec entry, allowing fd_write to output all
 * parts in a single syscall with no intermediate string buffer needed.
 *
 * Memory layout (first 260 bytes — wasic.ts must reserve this region):
 *
 *   Offset     Size    Purpose
 *   ──────────────────────────────────────────────────────────────────
 *   0          128     iovec array  (up to 16 entries × 8 bytes each)
 *   128        4       nwritten result for fd_write
 *   132        128     numeric-to-string scratch  (4 slots × 32 bytes)
 *   260        …       string data section (managed by DataAllocator)
 *
 * Helper functions emitted into the WAT module (only when numeric args appear):
 *   $__i32_to_str  (param $val i32) (param $buf i32) (result i32)
 *   $__f64_to_str  (param $val f64) (param $buf i32) (result i32)
 *     → Both write a decimal string at $buf and return the byte length written.
 *     → f64 outputs the integer part followed by up to 6 significant decimal digits
 *       (trailing zeros stripped). Precision beyond 6 digits is truncated.
 */

// ---------------------------------------------------------------------------
// Memory layout constants
// ---------------------------------------------------------------------------

/** Base of the iovec scratch array. Each iovec is 8 bytes: [ptr: i32, len: i32]. */
export const IOV_BASE = 0;

/** Offset of the 4-byte nwritten result written by fd_write. */
export const NWRITTEN_OFFSET = 128;

/** Base of the numeric-to-string scratch area. */
export const SCRATCH_BASE = 132;

/** Number of scratch slots (32 bytes each). Limits numeric args per console.log call. */
export const SCRATCH_SLOTS = 4;

/** First byte available for static string data. */
export const DATA_BASE = SCRATCH_BASE + SCRATCH_SLOTS * 32; // 260

// ---------------------------------------------------------------------------
// Segment types
// ---------------------------------------------------------------------------

/**
 * Callback for looking up a function's parameter types by name.
 * Return `undefined` if the function is unknown; parameter types default to "i32".
 */
export type FuncLookup = (name: string) => { params: Array<{ type: string }> } | undefined;

/**
 * Callback type: allocates a static string in the WASM data section and returns
 * its [memoryOffset, byteLength]. Identical strings should return the same offset.
 */
export type DataAllocator = (text: string) => [offset: number, byteLen: number];

/** A parsed fragment of a console.log argument list. */
export type LogSegment =
  | { kind: "literal"; text: string }                        // static string (embedded in data section)
  | { kind: "i32var"; name: string }                         // local i32 variable
  | { kind: "i64var"; name: string }                         // local i64 variable
  | { kind: "f64var"; name: string }                         // local f64 variable
  | { kind: "i32expr"; wat: string }                         // arbitrary WAT expression yielding i32
  | { kind: "i64expr"; wat: string }                         // arbitrary WAT expression yielding i64
  | { kind: "f64expr"; wat: string }                         // arbitrary WAT expression yielding f64
  | { kind: "strvar"; ptrLocal: string; lenLocal: string }   // string variable (ptr + len i32 locals)
  | { kind: "boolvar"; name: string }                        // bool-typed local (i32, 0=false 1=true)
  | { kind: "boolexpr"; wat: string };                       // arbitrary WAT expression yielding bool i32

// ---------------------------------------------------------------------------
// Argument parser
// ---------------------------------------------------------------------------

/** Splits a top-level comma-separated argument list, respecting nested parens and all string quotes. */
function splitTopLevelArgs(raw: string): string[] {
  const args: string[] = [];
  let depth = 0, inTemplate = false, inDouble = false, inSingle = false, start = 0;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    // Skip escaped characters inside strings
    if ((inDouble || inSingle || inTemplate) && ch === "\\") { i++; continue; }
    if (ch === "`"  && !inDouble && !inSingle) { inTemplate = !inTemplate; continue; }
    if (ch === '"'  && !inTemplate && !inSingle) { inDouble = !inDouble; continue; }
    if (ch === "'"  && !inTemplate && !inDouble) { inSingle = !inSingle; continue; }
    if (!inTemplate && !inDouble && !inSingle) {
      if (ch === "(" || ch === "[" || ch === "{") depth++;
      else if (ch === ")" || ch === "]" || ch === "}") depth--;
      else if (ch === "," && depth === 0) {
        args.push(raw.slice(start, i).trim());
        start = i + 1;
      }
    }
  }
  args.push(raw.slice(start).trim());
  return args.filter(a => a.length > 0);
}

/** Parses a single argument token into LogSegments. */
function parseSingleArg(
  token: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup,
  allocString?: DataAllocator,
  enumLookup?: (key: string) => number | undefined
): LogSegment[] {
  token = token.trim();

  // ── Template literal: `text ${expr} text ...`
  if (token.startsWith("`") && token.endsWith("`")) {
    return parseTemplateLiteral(token.slice(1, -1), locals, funcLookup, allocString, enumLookup);
  }

  // ── Double-quoted string literal
  if (token.startsWith('"') && token.endsWith('"')) {
    return [{ kind: "literal", text: token.slice(1, -1) }];
  }

  // ── Single-quoted string literal
  if (token.startsWith("'") && token.endsWith("'")) {
    return [{ kind: "literal", text: token.slice(1, -1) }];
  }

  // ── Numeric literal (compile-time constant → embed as string)
  if (/^-?\d+(\.\d+)?$/.test(token)) {
    return [{ kind: "literal", text: token }];
  }

  // ── String concatenation: only split on + when at least one side is a string literal
  // or a string-typed local. If both sides are non-strings the + is arithmetic —
  // fall through to the expr handler.
  const concatIdx = findTopLevelOp(token, "+");
  if (concatIdx !== -1) {
    const lhs = token.slice(0, concatIdx).trim();
    const rhs = token.slice(concatIdx + 1).trim();
    const lhsIsStr = /^["'`]/.test(lhs) || locals.get(lhs) === "string";
    const rhsIsStr = /^["'`]/.test(rhs) || locals.get(rhs) === "string";
    if (lhsIsStr || rhsIsStr) {
      return [
        ...parseSingleArg(lhs, locals, funcLookup, allocString),
        ...parseSingleArg(rhs, locals, funcLookup, allocString),
      ];
    }
    // Arithmetic + — fall through to the expression handler below
  }

  // ── Boolean literals
  if (token === "true")  return [{ kind: "boolexpr", wat: "(i32.const 1)" }];
  if (token === "false") return [{ kind: "boolexpr", wat: "(i32.const 0)" }];

  // ── Bigint literal: 42n → i64 constant (must come before identifier check since /^\w+$/ matches "1n")
  if (/^-?\d+n$/.test(token)) {
    const n = token.slice(0, -1);
    return [{ kind: "i64expr", wat: `(i64.const ${n})` }];
  }

  // ── Simple identifier
  if (/^\w+$/.test(token)) {
    const wtype = locals.get(token);
    if (wtype === "string") return [{ kind: "strvar", ptrLocal: `${token}_ptr`, lenLocal: `${token}_len` }];
    if (wtype === "i64") return [{ kind: "i64var", name: token }];
    if (wtype === "i32") return [{ kind: "i32var", name: token }];
    if (wtype === "bool") return [{ kind: "boolvar", name: token }];
    if (wtype === "f32" || wtype === "f64") return [{ kind: "f64var", name: token }];
    // Unknown type — treat as i32 (safest default for integer expressions)
    return [{ kind: "i32var", name: token }];
  }

  // ── Enum member access: EnumName.MemberName → i32 constant
  const enumMatch = token.match(/^(\w+)\.(\w+)$/);
  if (enumMatch && enumLookup) {
    const key = `${enumMatch[1]}.${enumMatch[2]}`;
    const val = enumLookup(key);
    if (val !== undefined) {
      return [{ kind: "i32expr", wat: `(i32.const ${val})` }];
    }
  }

  // ── Function call: name(arg, arg, ...)
  // Look up the callee's parameter types so each argument gets the correct const kind.
  const callMatch = token.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    const sig = funcLookup?.(callee);
    // String params expand to two stack values (ptr + len); use allocString if available.
    const watArgs = argList
      .flatMap((a, i) => {
        const ptype = sig?.params[i]?.type ?? "i32";
        if (ptype === "string") {
          return [exprToWat(a.trim(), locals, "string", funcLookup, allocString)];
        }
        return [exprToWat(a.trim(), locals, ptype, funcLookup, allocString)];
      })
      .join(" ");
    const wat = watArgs ? `(call $${callee} ${watArgs})` : `(call $${callee})`;
    // Return type of the call: use the result type from signature if available, else i32expr
    const retType = (sig as { result?: string } | undefined)?.result;
    if (retType === "bool")             return [{ kind: "boolexpr", wat }];
    if (retType === "f64" || retType === "f32") return [{ kind: "f64expr", wat }];
    return [{ kind: "i32expr", wat }];
  }

  // ── Arithmetic / numeric expression
  // Infer i64 vs f64 from the leading identifier's declared type
  const leadId = token.match(/^(\w+)/)?.[1];
  if (leadId && locals.get(leadId) === "i64") {
    return [{ kind: "i64expr", wat: exprToWat(token, locals, "i64", funcLookup, allocString) }];
  }
  return [{ kind: "f64expr", wat: exprToWat(token, locals, "f64", funcLookup, allocString) }];
}

/** Parses a template literal body (contents between backticks) into segments. */
function parseTemplateLiteral(
  body: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup,
  allocString?: DataAllocator,
  enumLookup?: (key: string) => number | undefined
): LogSegment[] {
  const segments: LogSegment[] = [];
  let i = 0;
  let textStart = 0;

  while (i < body.length) {
    if (body[i] === "$" && body[i + 1] === "{") {
      // Flush preceding text
      if (i > textStart) segments.push({ kind: "literal", text: body.slice(textStart, i) });
      // Find closing }
      let depth = 1;
      let j = i + 2;
      while (j < body.length && depth > 0) {
        if (body[j] === "{") depth++;
        else if (body[j] === "}") depth--;
        j++;
      }
      const expr = body.slice(i + 2, j - 1).trim();
      segments.push(...parseSingleArg(expr, locals, funcLookup, allocString, enumLookup));
      i = j;
      textStart = j;
    } else {
      i++;
    }
  }
  if (textStart < body.length) segments.push({ kind: "literal", text: body.slice(textStart) });
  return segments;
}

/**
 * Converts a simple TypeScript expression to a WAT expression of `expectedType`.
 * Handles: numeric literals, identifiers, nested function calls, and parens.
 * The `expectedType` is used to emit the correct const instruction for literals
 * and to choose the right conversion when calling a function.
 */
function exprToWat(
  expr: string,
  locals: Map<string, string>,
  expectedType: string = "i32",
  funcLookup?: FuncLookup,
  allocString?: DataAllocator
): string {
  expr = expr.trim();

  // String type: emit ptr+len pair (two stack values joined by a space)
  if (expectedType === "string") {
    // String variable → use its ptr/len locals
    if (/^\w+$/.test(expr) && locals.get(expr) === "string") {
      return `(local.get $${expr}_ptr) (local.get $${expr}_len)`;
    }
    // String literal → allocate in data section if allocator provided
    const litMatch = expr.match(/^"([^"]*)"$/) ?? expr.match(/^'([^']*)'$/);
    if (litMatch && allocString) {
      const [offset, len] = allocString(litMatch[1]);
      return `(i32.const ${offset}) (i32.const ${len})`;
    }
    // Fallback: null string
    return `(i32.const 0) (i32.const 0)`;
  }

  // Float literal — always use the expected type's const
  if (/^-?\d+\.\d+$/.test(expr)) {
    return `(${expectedType === "i32" || expectedType === "i64" ? "f64" : expectedType}.const ${expr})`;
  }

  // Integer literal — emit const for the expected type
  if (/^-?\d+$/.test(expr)) {
    const t = (expectedType === "f32" || expectedType === "f64") ? expectedType
            : expectedType === "i64" ? "i64" : "i32";
    return `(${t}.const ${expr})`;
  }

  // Special constants — must be checked before the identifier fallback
  const CONSTANTS: Record<string, string> = {
    NaN:       "(f64.const nan)",
    Infinity:  "(f64.const inf)",
    true:      "(i32.const 1)",
    false:     "(i32.const 0)",
    null:      "(i32.const 0)",
    undefined: "(i32.const 0)",
  };
  if (Object.prototype.hasOwnProperty.call(CONSTANTS, expr)) return CONSTANTS[expr];

  // Simple identifier — look up its declared type
  if (/^\w+$/.test(expr)) return `(local.get $${expr})`;

  // Nested function call: name(args)
  const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    const sig = funcLookup?.(callee);
    // String params expand to two stack values
    const watArgs = argList
      .flatMap((a, i) => {
        const ptype = sig?.params[i]?.type ?? "i32";
        return [exprToWat(a.trim(), locals, ptype, funcLookup, allocString)];
      })
      .join(" ");
    return watArgs ? `(call $${callee} ${watArgs})` : `(call $${callee})`;
  }

  // Parenthesised sub-expression — unwrap and recurse
  if (expr.startsWith("(") && expr.endsWith(")")) {
    return exprToWat(expr.slice(1, -1), locals, expectedType, funcLookup, allocString);
  }

  const isFloat = expectedType === "f64" || expectedType === "f32";
  // i64 is preserved; otherwise default numeric to f64
  const numType = isFloat ? (expectedType as string) : expectedType === "i64" ? "i64" : "f64";

  // Unary ! — logical not → i32.eqz
  if (expr.startsWith("!") && !expr.startsWith("!=")) {
    return `(i32.eqz ${exprToWat(expr.slice(1).trim(), locals, "i32", funcLookup, allocString)})`;
  }

  // Unary ~ — bitwise not → i32.xor with -1
  if (expr.startsWith("~")) {
    return `(i32.xor ${exprToWat(expr.slice(1).trim(), locals, "i32", funcLookup, allocString)} (i32.const -1))`;
  }

  // Unary - on a non-literal (e.g. -x, -(a+b))
  if (expr.startsWith("-") && !/^-\d/.test(expr)) {
    const inner = expr.slice(1).trim();
    if (isFloat) return `(${expectedType}.neg ${exprToWat(inner, locals, numType, funcLookup, allocString)})`;
    return `(i32.sub (i32.const 0) ${exprToWat(inner, locals, "i32", funcLookup, allocString)})`;
  }

  // Ternary: cond ? then : else
  const ternQ = findTopLevelOp(expr, "?");
  if (ternQ !== -1) {
    const rest  = expr.slice(ternQ + 1);
    const ternC = findTopLevelOp(rest, ":");
    if (ternC !== -1) {
      const cond     = expr.slice(0, ternQ).trim();
      const thenPart = rest.slice(0, ternC).trim();
      const elsePart = rest.slice(ternC + 1).trim();
      const resType  = isFloat ? expectedType : "i32";
      return `(if (result ${resType}) ${exprToWat(cond, locals, "i32", funcLookup, allocString)} (then ${exprToWat(thenPart, locals, resType, funcLookup, allocString)}) (else ${exprToWat(elsePart, locals, resType, funcLookup, allocString)}))`;
    }
  }

  // Binary operators — ascending precedence order (lowest first = outermost grouping).
  // [op, f64-watop, i32-watop, requiresPositiveIdx, alwaysI32]
  const binOps: Array<[string, string, string, boolean, boolean]> = [
    ["||",  "i32.or",    "i32.or",    false, true ],   // logical OR
    ["&&",  "i32.and",   "i32.and",   false, true ],   // logical AND
    ["|",   "i32.or",    "i32.or",    false, true ],   // bitwise OR
    ["^",   "i32.xor",   "i32.xor",   false, true ],   // bitwise XOR
    ["&",   "i32.and",   "i32.and",   false, true ],   // bitwise AND
    ["===", "f64.eq",    "i32.eq",    false, false],
    ["!==", "f64.ne",    "i32.ne",    false, false],
    ["==",  "f64.eq",    "i32.eq",    false, false],   // non-strict equality
    ["!=",  "f64.ne",    "i32.ne",    false, false],   // non-strict inequality
    ["<=",  "f64.le",    "i32.le_s",  false, false],
    [">=",  "f64.ge",    "i32.ge_s",  false, false],
    ["<",   "f64.lt",    "i32.lt_s",  false, false],
    [">",   "f64.gt",    "i32.gt_s",  false, false],
    [">>>", "i32.shr_u", "i32.shr_u", false, true ],   // unsigned shift
    [">>",  "i32.shr_s", "i32.shr_s", false, true ],   // signed shift
    ["<<",  "i32.shl",   "i32.shl",   false, true ],   // left shift
    ["+",   "f64.add",   "i32.add",   false, false],
    ["-",   "f64.sub",   "i32.sub",   true,  false],   // positiveIdx: skip unary minus
    ["*",   "f64.mul",   "i32.mul",   false, false],
    ["/",   "f64.div",   "i32.div_s", false, false],
    ["%",   "f64.rem",   "i32.rem_u", false, false],
  ];
  for (const [op, f64op, i32op, positiveIdx, alwaysI32] of binOps) {
    const idx = findTopLevelOp(expr, op);
    if (idx === -1) continue;
    if (positiveIdx && idx === 0) continue;
    const lhs    = expr.slice(0, idx).trim();
    const rhs    = expr.slice(idx + op.length).trim();
    // Infer i64 from LHS local type so i64 expressions don't get cast to f64
    const lhsLocalType = /^\w+$/.test(lhs) ? locals.get(lhs) : undefined;
    const opType = alwaysI32 ? "i32" : (lhsLocalType === "i64" ? "i64" : numType);
    const watOp  = (opType === "f64" || opType === "f32") ? f64op
                 : opType === "i64" ? i32op.replace(/^i32\./, "i64.") : i32op;
    return `(${watOp} ${exprToWat(lhs, locals, opType, funcLookup, allocString)} ${exprToWat(rhs, locals, opType, funcLookup, allocString)})`;
  }

  // Fallback: emit a comment and a zero of the expected type
  const zeroType = isFloat ? expectedType : expectedType === "i64" ? "i64" : "i32";
  return `(;? ${expr};) (${zeroType}.const 0)`;
}

/**
 * Returns the index of the rightmost top-level occurrence of `op` in `expr`, or -1.
 * Scanning right-to-left ensures left-associative grouping (a-b-c → (a-b)-c).
 * Guards prevent shorter operators matching inside longer ones (e.g. & inside &&).
 */
function findTopLevelOp(expr: string, op: string): number {
  let depth = 0;
  for (let i = expr.length - op.length; i >= 0; i--) {
    const ch = expr[i];
    if (ch === ")" || ch === "]") depth++;
    else if (ch === "(" || ch === "[") depth--;
    if (depth === 0 && expr.slice(i, i + op.length) === op) {
      const after  = expr[i + op.length] ?? "";
      const before = i > 0 ? expr[i - 1] : "";
      if (op === "<"  && (after === "=" || after === "<"))               continue;
      if (op === ">"  && (after === "=" || after === ">" || before === ">")) continue;
      if (op === "="  && after === "=")                                  continue;
      if (op === "!"  && after === "=")                                  continue;
      if (op === "==" && (after === "=" || before === "="))             continue; // avoid ===
      if (op === "!=" && after === "=")                                  continue; // avoid !==
      if (op === "&"  && (after === "&" || before === "&"))              continue;
      if (op === "|"  && (after === "|" || before === "|"))              continue;
      if (op === ">>" && (after === ">" || before === ">"))              continue;
      if (op === "?"  && after === ".")                                   continue;
      return i;
    }
  }
  return -1;
}

/**
 * Parses the full argument list from a `console.log(...)` call into an ordered
 * array of LogSegments, ready for WAT emission.
 *
 * @param argsStr    - Raw text of the arguments (everything between the outer parens).
 * @param locals     - Map of local variable names to their WAT type strings.
 * @param funcLookup - Optional callback to resolve a callee's parameter/result types.
 *                     When provided, integer/float literals inside function call
 *                     arguments are emitted with the correct WAT const instruction.
 */
export function parseConsoleLogArgs(
  argsStr: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup,
  allocString?: DataAllocator,
  enumLookup?: (key: string) => number | undefined
): LogSegment[] {
  const args = splitTopLevelArgs(argsStr);
  const segments: LogSegment[] = [];

  for (let i = 0; i < args.length; i++) {
    if (i > 0) segments.push({ kind: "literal", text: " " }); // space between args
    segments.push(...parseSingleArg(args[i], locals, funcLookup, allocString, enumLookup));
  }

  // Always terminate with a newline (console.log behaviour)
  segments.push({ kind: "literal", text: "\n" });
  return segments;
}

// ---------------------------------------------------------------------------
// WAT emitter
// ---------------------------------------------------------------------------

/**
 * Generates the sequence of WAT statements that implement a console.log call
 * via WASI fd_write.
 *
 * The generated statements:
 *   1. For each numeric segment: call $__i32_to_str / $__f64_to_str into a scratch slot,
 *      then store the scratch address and returned length into the iovec entry.
 *   2. For each literal segment: store the static data address and byte count into
 *      the iovec entry.
 *   3. Call fd_write once with iov_count = segments.length.
 *
 * @param segments    - Parsed segments from parseConsoleLogArgs.
 * @param allocString - Allocator that places string literals into the data section.
 * @param indent      - Indentation prefix for each emitted line.
 * @returns Array of WAT statement strings to be inserted at the call site.
 */
export function emitConsoleLog(
  segments: LogSegment[],
  allocString: DataAllocator,
  indent = "    "
): { statements: string[]; needsHelpers: boolean } {
  const statements: string[] = [];
  let numericSlot = 0;
  let needsHelpers = false;

  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    const iovPtr = IOV_BASE + i * 8;      // iov[i].buf  (i32)
    const iovLen = IOV_BASE + i * 8 + 4;  // iov[i].buf_len (i32)

    if (seg.kind === "literal") {
      const [offset, len] = allocString(seg.text);
      statements.push(
        `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${offset}))`,
        `${indent}(i32.store (i32.const ${iovLen}) (i32.const ${len}))`,
      );
    } else if (seg.kind === "strvar") {
      // String variable: ptr and len are already in i32 locals — no scratch slot needed
      statements.push(
        `${indent}(i32.store (i32.const ${iovPtr}) (local.get $${seg.ptrLocal}))`,
        `${indent}(i32.store (i32.const ${iovLen}) (local.get $${seg.lenLocal}))`,
      );
    } else if (seg.kind === "boolvar" || seg.kind === "boolexpr") {
      // Boolean segment: select "true"/"false" string at runtime — no scratch slot needed
      const [trueOff]  = allocString("true");
      const [falseOff] = allocString("false");
      const val = seg.kind === "boolvar" ? `(local.get $${seg.name})` : seg.wat;
      statements.push(
        `${indent}(i32.store (i32.const ${iovPtr}) (if (result i32) ${val} (then (i32.const ${trueOff})) (else (i32.const ${falseOff}))))`,
        `${indent}(i32.store (i32.const ${iovLen}) (if (result i32) ${val} (then (i32.const 4)) (else (i32.const 5))))`,
      );
    } else {
      // Numeric segment — write to scratch slot, store dynamic length in iov
      if (numericSlot >= SCRATCH_SLOTS) {
        // Overflow: fall back to a placeholder literal
        const [offset, len] = allocString("?");
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${offset}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (i32.const ${len}))`,
        );
        continue;
      }

      needsHelpers = true;
      const scratchPtr = SCRATCH_BASE + numericSlot * 32;
      numericSlot++;

      let callExpr: string;
      if (seg.kind === "i32var") {
        callExpr = `(call $__i32_to_str (local.get $${seg.name}) (i32.const ${scratchPtr}))`;
      } else if (seg.kind === "i64var") {
        callExpr = `(call $__i64_to_str (local.get $${seg.name}) (i32.const ${scratchPtr}))`;
      } else if (seg.kind === "f64var") {
        callExpr = `(call $__f64_to_str (local.get $${seg.name}) (i32.const ${scratchPtr}))`;
      } else if (seg.kind === "i32expr") {
        callExpr = `(call $__i32_to_str ${seg.wat} (i32.const ${scratchPtr}))`;
      } else if (seg.kind === "i64expr") {
        callExpr = `(call $__i64_to_str ${seg.wat} (i32.const ${scratchPtr}))`;
      } else {
        callExpr = `(call $__f64_to_str ${seg.wat} (i32.const ${scratchPtr}))`;
      }

      statements.push(
        `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${scratchPtr}))`,
        `${indent}(i32.store (i32.const ${iovLen}) ${callExpr})`,
      );
    }
  }

  // Single fd_write call covering all iovecs
  statements.push(
    `${indent}(drop (call $fd_write`,
    `${indent}  (i32.const 1)`,
    `${indent}  (i32.const ${IOV_BASE})`,
    `${indent}  (i32.const ${segments.length})`,
    `${indent}  (i32.const ${NWRITTEN_OFFSET})))`,
  );

  return { statements, needsHelpers };
}

// ---------------------------------------------------------------------------
// WAT helper function bodies
// ---------------------------------------------------------------------------

/**
 * Returns WAT definitions for the numeric-to-string helper functions.
 * Include this string once in the module, only when numeric log arguments are present.
 *
 * $__i32_to_str: complete signed decimal conversion.
 * $__f64_to_str: integer part + up to 6 significant decimal digits (trailing zeros stripped).
 *   Note: values outside the i32 range for the integer part will be clamped.
 */
export function getHelperWat(): string {
  return `
  ;; ── i32 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  (func $__i32_to_str (param $val i32) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $neg i32)
    (local $orig i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; Zero
    (if (i32.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (return (i32.const 1))
      )
    )
    ;; Negative
    (if (i32.lt_s (local.get $val) (i32.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $neg (i32.const 1))
        (local.set $val (i32.sub (i32.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $val)))
        (i32.store8
          (local.get $end)
          (i32.add (i32.const 48) (i32.rem_u (local.get $val) (i32.const 10)))
        )
        (local.set $val (i32.div_u (local.get $val) (i32.const 10)))
        (local.set $end (i32.add (local.get $end) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Reverse digit bytes in-place
    (local.set $tmp (local.get $start))
    (local.set $ch (i32.sub (local.get $end) (i32.const 1)))
    (block $rdone
      (loop $rloop
        (br_if $rdone (i32.ge_u (local.get $tmp) (local.get $ch)))
        (local.set $neg (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $neg))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    ;; Return total length (including leading '-' if any)
    (i32.sub (local.get $end) (local.get $orig))
  )

  ;; ── f64 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  ;; Outputs the integer part plus up to 6 significant decimal digits.
  ;; Values outside [-2147483648, 2147483647] for the integer part are clamped.
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $len i32)
    (local $ipart i32)
    (local $fpart i64)
    (local $flen i32)
    (local $fdigits i32)
    (local $ptr i32)
    (local $zeros i32)
    (local.set $ptr (local.get $buf))
    ;; Handle negative
    (if (f64.lt (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $val (f64.neg (local.get $val)))
      )
    )
    ;; Integer part
    (local.set $ipart (i32.trunc_f64_s (local.get $val)))
    (local.set $len (call $__i32_to_str (local.get $ipart) (local.get $ptr)))
    (local.set $ptr (i32.add (local.get $ptr) (local.get $len)))
    ;; Fractional part: multiply remainder by 1 000 000, take integer
    (local.set $fpart
      (i64.trunc_f64_s
        (f64.mul
          (f64.sub (local.get $val) (f64.convert_i32_s (local.get $ipart)))
          (f64.const 1000000)
        )
      )
    )
    (if (i64.ne (local.get $fpart) (i64.const 0))
      (then
        ;; Decimal point
        (i32.store8 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        ;; Write 6-digit fractional string then strip trailing zeros
        (local.set $fdigits (i32.wrap_i64 (local.get $fpart)))
        ;; Write fractional digits in reverse into a 6-byte window
        (local.set $flen (i32.const 6))
        (block $fdone
          (loop $floop
            (br_if $fdone (i32.eqz (local.get $flen)))
            (i32.store8
              (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1)))
              (i32.add (i32.const 48) (i32.rem_u (local.get $fdigits) (i32.const 10)))
            )
            (local.set $fdigits (i32.div_u (local.get $fdigits) (i32.const 10)))
            (local.set $flen (i32.sub (local.get $flen) (i32.const 1)))
            (br $floop)
          )
        )
        ;; Count non-zero trailing digits to strip
        (local.set $flen (i32.const 6))
        (block $strip
          (loop $striploop
            (br_if $strip (i32.eqz (local.get $flen)))
            (br_if $strip
              (i32.ne
                (i32.load8_u (i32.add (local.get $ptr) (i32.sub (local.get $flen) (i32.const 1))))
                (i32.const 48)
              )
            )
            (local.set $flen (i32.sub (local.get $flen) (i32.const 1)))
            (br $striploop)
          )
        )
        (local.set $ptr (i32.add (local.get $ptr) (local.get $flen)))
      )
    )
    ;; Return total length written
    (i32.sub (local.get $ptr) (local.get $buf))
  )

  ;; ── i64 → decimal string ──────────────────────────────────────────────────
  ;; Writes the decimal representation of $val at $buf, returns byte count.
  (func $__i64_to_str (param $val i64) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $neg i32)
    (local $digit i32)
    (local $orig i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; Zero
    (if (i64.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (i32.store8 (i32.add (local.get $buf) (i32.const 1)) (i32.const 110))
        (return (i32.const 2))
      )
    )
    ;; Negative
    (if (i64.lt_s (local.get $val) (i64.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $neg (i32.const 1))
        (local.set $val (i64.sub (i64.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i64.eqz (local.get $val)))
        (local.set $digit (i32.wrap_i64 (i64.rem_u (local.get $val) (i64.const 10))))
        (i32.store8
          (local.get $end)
          (i32.add (i32.const 48) (local.get $digit))
        )
        (local.set $val (i64.div_u (local.get $val) (i64.const 10)))
        (local.set $end (i32.add (local.get $end) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Reverse digit bytes in-place
    (local.set $tmp (local.get $start))
    (local.set $ch (i32.sub (local.get $end) (i32.const 1)))
    (block $rdone
      (loop $rloop
        (br_if $rdone (i32.ge_u (local.get $tmp) (local.get $ch)))
        (local.set $neg (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $neg))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    ;; Append 'n' suffix for bigint display
    (i32.store8 (local.get $end) (i32.const 110))
    (local.set $end (i32.add (local.get $end) (i32.const 1)))
    ;; Return total length (including leading '-' and trailing 'n')
    (i32.sub (local.get $end) (local.get $orig))
  )
`.trimEnd();
}
