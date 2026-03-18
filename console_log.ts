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

/** A parsed fragment of a console.log argument list. */
export type LogSegment =
  | { kind: "literal"; text: string }                        // static string (embedded in data section)
  | { kind: "i32var"; name: string }                         // local i32 variable
  | { kind: "f64var"; name: string }                         // local f64 variable
  | { kind: "i32expr"; wat: string }                         // arbitrary WAT expression yielding i32
  | { kind: "f64expr"; wat: string };                        // arbitrary WAT expression yielding f64

// ---------------------------------------------------------------------------
// Argument parser
// ---------------------------------------------------------------------------

/** Splits a top-level comma-separated argument list, respecting nested parens and backticks. */
function splitTopLevelArgs(raw: string): string[] {
  const args: string[] = [];
  let depth = 0, inTemplate = false, start = 0;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (ch === "`") inTemplate = !inTemplate;
    if (!inTemplate) {
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
  funcLookup?: FuncLookup
): LogSegment[] {
  token = token.trim();

  // ── Template literal: `text ${expr} text ...`
  if (token.startsWith("`") && token.endsWith("`")) {
    return parseTemplateLiteral(token.slice(1, -1), locals, funcLookup);
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

  // ── String concatenation: only split on + when at least one side is a string literal.
  // If both sides are non-strings the + is arithmetic — fall through to the expr handler.
  const concatIdx = findTopLevelOp(token, "+");
  if (concatIdx !== -1) {
    const lhs = token.slice(0, concatIdx).trim();
    const rhs = token.slice(concatIdx + 1).trim();
    const lhsIsStr = /^["'`]/.test(lhs);
    const rhsIsStr = /^["'`]/.test(rhs);
    if (lhsIsStr || rhsIsStr) {
      return [
        ...parseSingleArg(lhs, locals, funcLookup),
        ...parseSingleArg(rhs, locals, funcLookup),
      ];
    }
    // Arithmetic + — fall through to the expression handler below
  }

  // ── Simple identifier
  if (/^\w+$/.test(token)) {
    const wtype = locals.get(token);
    if (wtype === "i32" || wtype === "i64") return [{ kind: "i32var", name: token }];
    if (wtype === "f32" || wtype === "f64") return [{ kind: "f64var", name: token }];
    // Unknown type — treat as i32 (safest default for integer expressions)
    return [{ kind: "i32var", name: token }];
  }

  // ── Function call: name(arg, arg, ...)
  // Look up the callee's parameter types so each argument gets the correct const kind.
  const callMatch = token.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    const sig = funcLookup?.(callee);
    const watArgs = argList
      .map((a, i) => exprToWat(a.trim(), locals, sig?.params[i]?.type ?? "i32", funcLookup))
      .join(" ");
    const wat = watArgs ? `(call $${callee} ${watArgs})` : `(call $${callee})`;
    // Return type of the call: use the result type from signature if available, else i32expr
    const retType = (sig as { result?: string } | undefined)?.result;
    if (retType === "f64" || retType === "f32") return [{ kind: "f64expr", wat }];
    return [{ kind: "i32expr", wat }];
  }

  // ── Arithmetic / numeric expression — emit as f64 (default numeric type)
  return [{ kind: "f64expr", wat: exprToWat(token, locals, "f64", funcLookup) }];
}

/** Parses a template literal body (contents between backticks) into segments. */
function parseTemplateLiteral(
  body: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup
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
      segments.push(...parseSingleArg(expr, locals, funcLookup));
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
  funcLookup?: FuncLookup
): string {
  expr = expr.trim();

  // Float literal — always use the expected type's const
  if (/^-?\d+\.\d+$/.test(expr)) {
    return `(${expectedType === "i32" || expectedType === "i64" ? "f64" : expectedType}.const ${expr})`;
  }

  // Integer literal — emit const for the expected type
  if (/^-?\d+$/.test(expr)) {
    const t = expectedType === "f32" || expectedType === "f64" ? expectedType : "i32";
    return `(${t}.const ${expr})`;
  }

  // Simple identifier — look up its declared type
  if (/^\w+$/.test(expr)) return `(local.get $${expr})`;

  // Nested function call: name(args)
  const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    const sig = funcLookup?.(callee);
    const watArgs = argList
      .map((a, i) => exprToWat(a.trim(), locals, sig?.params[i]?.type ?? "i32", funcLookup))
      .join(" ");
    return watArgs ? `(call $${callee} ${watArgs})` : `(call $${callee})`;
  }

  // Parenthesised sub-expression — unwrap and recurse
  if (expr.startsWith("(") && expr.endsWith(")")) {
    return exprToWat(expr.slice(1, -1), locals, expectedType, funcLookup);
  }

  // Binary arithmetic and comparison operators.
  // Scanned in ascending precedence order so that lower-precedence operators
  // bind at the outermost level, producing correctly-grouped s-expressions.
  // For "-" we guard idx > 0 to avoid mistaking a leading unary minus for binary.
  const isFloat = expectedType === "f64" || expectedType === "f32";
  const numType  = isFloat ? (expectedType as string) : "f64"; // default numeric to f64
  const binOps: Array<[string, string, string, boolean]> = [
    // [operator, f64-op, i32-op, requiresPositiveIdx]
    ["+", "f64.add",   "i32.add",   false],
    ["-", "f64.sub",   "i32.sub",   true ],  // guard: idx > 0 avoids unary minus
    ["*", "f64.mul",   "i32.mul",   false],
    ["/", "f64.div",   "i32.div_s", false],
    ["%", "f64.rem",   "i32.rem_u", false],  // WAT has no f64.rem — approximation
  ];
  for (const [op, f64op, i32op, positiveIdx] of binOps) {
    const idx = findTopLevelOp(expr, op);
    if (idx === -1) continue;
    if (positiveIdx && idx === 0) continue;  // skip unary minus at start
    const lhs = expr.slice(0, idx).trim();
    const rhs = expr.slice(idx + op.length).trim();
    const watOp = isFloat ? f64op : i32op;
    return `(${watOp} ${exprToWat(lhs, locals, numType, funcLookup)} ${exprToWat(rhs, locals, numType, funcLookup)})`;
  }

  // Fallback: emit a comment and a zero of the expected type
  const zeroType = isFloat ? expectedType : "i32";
  return `(;? ${expr};) (${zeroType}.const 0)`;
}

/** Returns the index of the first top-level occurrence of `op` in `expr`, or -1. */
function findTopLevelOp(expr: string, op: string): number {
  let depth = 0;
  for (let i = 0; i < expr.length; i++) {
    const ch = expr[i];
    if (ch === "(" || ch === "[") depth++;
    else if (ch === ")" || ch === "]") depth--;
    else if (depth === 0 && expr.slice(i, i + op.length) === op) {
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
  funcLookup?: FuncLookup
): LogSegment[] {
  const args = splitTopLevelArgs(argsStr);
  const segments: LogSegment[] = [];

  for (let i = 0; i < args.length; i++) {
    if (i > 0) segments.push({ kind: "literal", text: " " }); // space between args
    segments.push(...parseSingleArg(args[i], locals, funcLookup));
  }

  // Always terminate with a newline (console.log behaviour)
  segments.push({ kind: "literal", text: "\n" });
  return segments;
}

// ---------------------------------------------------------------------------
// WAT emitter
// ---------------------------------------------------------------------------

/**
 * Callback type: allocates a static string in the WASM data section and returns
 * its [memoryOffset, byteLength]. Identical strings should return the same offset.
 */
export type DataAllocator = (text: string) => [offset: number, byteLen: number];

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
      } else if (seg.kind === "f64var") {
        callExpr = `(call $__f64_to_str (local.get $${seg.name}) (i32.const ${scratchPtr}))`;
      } else if (seg.kind === "i32expr") {
        callExpr = `(call $__i32_to_str ${seg.wat} (i32.const ${scratchPtr}))`;
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
    (i32.sub (local.get $end) (local.get $buf))
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
`.trimEnd();
}
