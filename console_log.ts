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
export type FuncLookup = (name: string) => {
  params: Array<{ type: string; defaultValue?: string }>;
  result?: string | null;
  closureCaptures?: string[];
  /** Phase 5f: true if this function returns a heap-allocated closure (closure factory). */
  isClosureFactory?: boolean;
  /** Original TypeScript return type annotation (e.g. "i32[]", "MatrixManager"). */
  resultTsName?: string;
} | undefined;

/**
 * Callback type: allocates a static string in the WASM data section and returns
 * its [memoryOffset, byteLength]. Identical strings should return the same offset.
 */
export type DataAllocator = (text: string) => [offset: number, byteLen: number];

/** Callback to resolve an array variable by name: returns its element type, base ptr, and length.
 *  ptr=-1 means runtime local (param). ptr=-2 means dynamic heap array (local with 8-byte header).
 *  dynamic=true means the array has a [length, capacity] header at its pointer. */
export type ArrayLookup = (name: string) => { elemType: string; ptr: number; length: number; dynamic?: boolean } | undefined;

/**
 * Callback to resolve a struct field access `varName.fieldName`.
 * Returns the field's WAT type string and the WAT load expression, or undefined if not a struct field.
 */
export type StructFieldLookup = (varName: string, fieldName: string) => { type: string; watLoad: string } | undefined;

/**
 * Callback to resolve a dot-call expression like `receiver.method(args)`.
 * Returns the WAT expression and return type, or undefined if not handled.
 * Used by console_log to support class instance/static method calls in argument position.
 */
export type DotCallLookup = (token: string) => { type: string; wat: string } | undefined;

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
  | { kind: "boolexpr"; wat: string }                        // arbitrary WAT expression yielding bool i32
  | { kind: "arrptr"; wat: string; elemType: string };       // WAT expression yielding a dynamic array ptr

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

/**
 * Phase 5f: paren-aware extraction of `factoryFn(outerArgs)(innerArgs)`.
 * Returns { outerRaw, innerRaw } if the pattern is present, otherwise null.
 */
function extractChainedCallParts(expr: string): { outerRaw: string; innerRaw: string } | null {
  const firstParen = expr.indexOf("(");
  if (firstParen === -1) return null;
  let depth = 0, i = firstParen;
  while (i < expr.length) {
    if (expr[i] === "(") depth++;
    else if (expr[i] === ")") { depth--; if (depth === 0) break; }
    i++;
  }
  const outerRaw = expr.slice(firstParen + 1, i);
  const rest = expr.slice(i + 1).trimStart();
  if (!rest.startsWith("(")) return null;
  let depth2 = 0, j = 0;
  while (j < rest.length) {
    if (rest[j] === "(") depth2++;
    else if (rest[j] === ")") { depth2--; if (depth2 === 0) break; }
    j++;
  }
  return { outerRaw, innerRaw: rest.slice(1, j) };
}

/** Parses a single argument token into LogSegments. */
function parseSingleArg(
  token: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup,
  allocString?: DataAllocator,
  enumLookup?: (key: string) => number | undefined,
  arrayLookup?: ArrayLookup,
  structLookup?: StructFieldLookup,
  dotCallLookup?: DotCallLookup,
  globals?: Map<string, string>
): LogSegment[] {
  token = token.trim();

  // ── Template literal: `text ${expr} text ...`
  if (token.startsWith("`") && token.endsWith("`")) {
    return parseTemplateLiteral(token.slice(1, -1), locals, funcLookup, allocString, enumLookup, arrayLookup, structLookup, dotCallLookup, globals);
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
        ...parseSingleArg(lhs, locals, funcLookup, allocString, enumLookup, arrayLookup, structLookup, dotCallLookup, globals),
        ...parseSingleArg(rhs, locals, funcLookup, allocString, enumLookup, arrayLookup, structLookup, dotCallLookup, globals),
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
    // Module-level globals: emit global.get instead of local.get
    if (globals?.has(token)) {
      const gType = globals.get(token)!;
      const wat = `(global.get $${token})`;
      if (gType === "i64") return [{ kind: "i64expr", wat }];
      if (gType === "f64" || gType === "f32") return [{ kind: "f64expr", wat }];
      return [{ kind: "i32expr", wat }];
    }
    const wtype = locals.get(token);
    if (wtype === "string") return [{ kind: "strvar", ptrLocal: `${token}_ptr`, lenLocal: `${token}_len` }];
    if (wtype === "i64") return [{ kind: "i64var", name: token }];
    if (wtype === "i32") return [{ kind: "i32var", name: token }];
    if (wtype === "bool") return [{ kind: "boolvar", name: token }];
    if (wtype === "f32" || wtype === "f64") return [{ kind: "f64var", name: token }];
    // Unknown type — treat as i32 (safest default for integer expressions)
    return [{ kind: "i32var", name: token }];
  }

  // ── varName.message — Error catch variable; .message is the string itself
  const errMsgMatch = token.match(/^(\w+)\.message$/);
  if (errMsgMatch && locals.get(errMsgMatch[1]) === "string") {
    return [{ kind: "strvar", ptrLocal: `${errMsgMatch[1]}_ptr`, lenLocal: `${errMsgMatch[1]}_len` }];
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

  // ── Struct field access: p.field
  const sfDotMatch = token.match(/^(\w+)\.(\w+)$/);
  if (sfDotMatch && structLookup) {
    const fi = structLookup(sfDotMatch[1], sfDotMatch[2]);
    if (fi) {
      const kind = fi.type === "f64" || fi.type === "f32" ? "f64expr" as const
                 : fi.type === "i64" ? "i64expr" as const : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }

  // ── Dot-call expression: receiver.method(args) or this.method(args) — class/static calls
  // Skip Math.* tokens — they have their own dedicated handler below.
  if (dotCallLookup && !token.startsWith("Math.") && /^(?:this|\w+)\.(\w+)\s*\(/.test(token)) {
    const result = dotCallLookup(token);
    if (result) {
      const kind = result.type === "f64" || result.type === "f32" ? "f64expr" as const
                 : result.type === "i64" ? "i64expr" as const : "i32expr" as const;
      return [{ kind, wat: result.wat }];
    }
  }

  // ── Phase 5f: chained call — factoryFn(outerArgs)(innerArgs) closure factory
  {
    const factoryHead = token.match(/^(\w+)\s*\(/)?.[1];
    if (factoryHead) {
      const factorySig = funcLookup?.(factoryHead);
      if (factorySig?.isClosureFactory) {
        const parts = extractChainedCallParts(token);
        if (parts) {
          const outerArgList = parts.outerRaw ? splitTopLevelArgs(parts.outerRaw) : [];
          const outerWat = outerArgList.map((a, i) => {
            const ptype = factorySig.params[i]?.type ?? "i32";
            return exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup);
          }).join(" ");
          const innerSig = funcLookup?.(`${factoryHead}__inner`);
          const captureCount = innerSig?.closureCaptures?.length ?? 0;
          const innerCallParams = innerSig ? innerSig.params.slice(0, innerSig.params.length - captureCount) : [];
          const innerArgList = parts.innerRaw ? splitTopLevelArgs(parts.innerRaw) : [];
          const innerWat = innerArgList.map((a, i) => {
            const ptype = innerCallParams[i]?.type ?? "i32";
            return exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup);
          }).join(" ");
          const wat = `(call $${factoryHead}__trampoline (call $${factoryHead} ${outerWat}) ${innerWat})`.trim();
          const innerResult = innerSig?.result;
          const kind = innerResult === "f64" || innerResult === "f32" ? "f64expr" as const
                     : innerResult === "i64" ? "i64expr" as const : "i32expr" as const;
          return [{ kind, wat }];
        }
      }
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
    const watArgsList = argList.flatMap((a, i) => {
      const ptype = sig?.params[i]?.type ?? "i32";
      if (ptype === "string") {
        return [exprToWat(a.trim(), locals, "string", funcLookup, allocString, arrayLookup, structLookup)];
      }
      return [exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup)];
    });
    // Fill in default values for omitted trailing params
    if (sig) {
      const baseParamCount = sig.params.length - (sig.closureCaptures?.length ?? 0);
      for (let i = argList.length; i < baseParamCount; i++) {
        const param = sig.params[i];
        if (param.defaultValue !== undefined) {
          watArgsList.push(exprToWat(param.defaultValue, locals, param.type, funcLookup, allocString, arrayLookup, structLookup));
        }
      }
    }
    const wat = watArgsList.length > 0 ? `(call $${callee} ${watArgsList.join(" ")})` : `(call $${callee})`;
    // Return type of the call: check resultTsName first (preserves array/interface annotation),
    // then fall back to the normalized WatType.
    const retTsName = sig?.resultTsName;
    if (retTsName && /\[\]$/.test(retTsName)) {
      const elemType = retTsName.replace(/\[\]$/, "");
      return [{ kind: "arrptr" as const, wat, elemType }];
    }
    const retType = (sig as { result?: string } | undefined)?.result;
    if (retType === "bool")                    return [{ kind: "boolexpr", wat }];
    if (retType === "i64")                     return [{ kind: "i64expr",  wat }];
    if (retType === "f64" || retType === "f32") return [{ kind: "f64expr",  wat }];
    return [{ kind: "i32expr", wat }];
  }

  // ── Array element access: arr[idx]
  const bracketMatch = token.match(/^(\w+)\[(.+)\]$/);
  // Phase 23: tuple element access t[N] where N is a numeric index → struct field _N
  if (bracketMatch && structLookup && /^\d+$/.test(bracketMatch[2])) {
    const fi = structLookup(bracketMatch[1], `_${bracketMatch[2]}`);
    if (fi) {
      const kind = fi.type === "f64" || fi.type === "f32" ? "f64expr" as const
                 : fi.type === "i64" ? "i64expr" as const : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }
  if (bracketMatch && arrayLookup) {
    const arrInfo = arrayLookup(bracketMatch[1]);
    if (arrInfo) {
      const loadOp  = arrInfo.elemType === "f64" ? "f64.load"
                    : arrInfo.elemType === "i64" ? "i64.load" : "i32.load";
      const shift   = (arrInfo.elemType === "f64" || arrInfo.elemType === "i64") ? 3 : 2;
      const idxWat  = exprToWat(bracketMatch[2], locals, "i32", funcLookup, allocString, arrayLookup, structLookup);
      // Dynamic arrays (ptr=-2) have a [length, capacity] header at the pointer; data starts at +8.
      const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic) ? `(local.get $${bracketMatch[1]})` : `(i32.const ${arrInfo.ptr})`;
      const dataBase = arrInfo.dynamic ? `(i32.add ${baseWat} (i32.const 8))` : baseWat;
      const wat     = `(${loadOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))))`;
      const kind    = arrInfo.elemType === "f64" ? "f64expr" as const
                    : arrInfo.elemType === "i64" ? "i64expr" as const : "i32expr" as const;
      return [{ kind, wat }];
    }
  }
  // Phase 12/5h: fallback — i32 local holding a dynamic i32[] array pointer (captured or method-returned)
  if (bracketMatch && locals.get(bracketMatch[1]) === "i32") {
    const idxWat = exprToWat(bracketMatch[2], locals, "i32", funcLookup, allocString, arrayLookup, structLookup);
    return [{ kind: "i32expr" as const, wat: `(i32.load (i32.add (i32.add (local.get $${bracketMatch[1]}) (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))` }];
  }

  // ── Array .length: dynamic → runtime i32 load from header; static → compile-time constant
  const dotLenMatch = token.match(/^(\w+)\.length$/);
  if (dotLenMatch) {
    const arrInfo = arrayLookup?.(dotLenMatch[1]);
    if (arrInfo) {
      const wat = arrInfo.dynamic
        ? `(i32.load (local.get $${dotLenMatch[1]}))`
        : `(i32.const ${arrInfo.length})`;
      return [{ kind: "i32expr", wat }];
    }
    // Phase 12: i32 local holding a dynamic array pointer — load length from header
    if (locals.get(dotLenMatch[1]) === "i32") {
      return [{ kind: "i32expr", wat: `(i32.load (local.get $${dotLenMatch[1]}))` }];
    }
  }

  // ── Math.* — route to correct kind based on return type
  if (token.startsWith("Math.")) {
    const mathCallM = token.match(/^Math\.(\w+)\(/);
    const mathFn = mathCallM?.[1];
    if (mathFn === "clz32" || mathFn === "imul") {
      return [{ kind: "i32expr", wat: exprToWat(token, locals, "i32", funcLookup, allocString, arrayLookup, structLookup) }];
    }
    // All other Math functions produce f64
    return [{ kind: "f64expr", wat: exprToWat(token, locals, "f64", funcLookup, allocString, arrayLookup, structLookup) }];
  }

  // ── Arithmetic / numeric expression
  // Infer i64 vs f64 from the leading identifier's declared type
  const leadId = token.match(/^(\w+)/)?.[1];
  if (leadId && locals.get(leadId) === "i64") {
    return [{ kind: "i64expr", wat: exprToWat(token, locals, "i64", funcLookup, allocString, arrayLookup, structLookup) }];
  }
  return [{ kind: "f64expr", wat: exprToWat(token, locals, "f64", funcLookup, allocString, arrayLookup, structLookup) }];
}

/** Parses a template literal body (contents between backticks) into segments. */
function parseTemplateLiteral(
  body: string,
  locals: Map<string, string>,
  funcLookup?: FuncLookup,
  allocString?: DataAllocator,
  enumLookup?: (key: string) => number | undefined,
  arrayLookup?: ArrayLookup,
  structLookup?: StructFieldLookup,
  dotCallLookup?: DotCallLookup,
  globals?: Map<string, string>
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
      segments.push(...parseSingleArg(expr, locals, funcLookup, allocString, enumLookup, arrayLookup, structLookup, dotCallLookup, globals));
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
  allocString?: DataAllocator,
  arrayLookup?: ArrayLookup,
  structLookup?: StructFieldLookup
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

  // Bigint literal: 5n → (i64.const 5)  (must come before identifier check: /^\w+$/ matches "5n")
  if (/^-?\d+n$/.test(expr)) return `(i64.const ${expr.slice(0, -1)})`;

  // Array .length: dynamic → runtime i32 load from header; static → compile-time constant
  const dotLenM = expr.match(/^(\w+)\.length$/);
  if (dotLenM) {
    const ai = arrayLookup?.(dotLenM[1]);
    if (ai) return ai.dynamic ? `(i32.load (local.get $${dotLenM[1]}))` : `(i32.const ${ai.length})`;
    // Phase 12: i32 local holding a dynamic array pointer
    if (locals.get(dotLenM[1]) === "i32") return `(i32.load (local.get $${dotLenM[1]}))`;
  }

  // Array element read: arr[idx]
  const bracketM = expr.match(/^(\w+)\[(.+)\]$/);
  // Phase 23: tuple element access t[N] → struct field _N
  if (bracketM && structLookup && /^\d+$/.test(bracketM[2])) {
    const fi = structLookup(bracketM[1], `_${bracketM[2]}`);
    if (fi) return fi.watLoad;
  }
  if (bracketM && arrayLookup) {
    const ai = arrayLookup(bracketM[1]);
    if (ai) {
      const loadOp  = ai.elemType === "f64" ? "f64.load" : ai.elemType === "i64" ? "i64.load" : "i32.load";
      const shift   = (ai.elemType === "f64" || ai.elemType === "i64") ? 3 : 2;
      const idxWat  = exprToWat(bracketM[2], locals, "i32", funcLookup, allocString, arrayLookup, structLookup);
      // Dynamic arrays have a [length, capacity] header; data starts at ptr+8.
      const baseWat = (ai.ptr === -1 || ai.dynamic) ? `(local.get $${bracketM[1]})` : `(i32.const ${ai.ptr})`;
      const dataBase = ai.dynamic ? `(i32.add ${baseWat} (i32.const 8))` : baseWat;
      return `(${loadOp} (i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift}))))`;
    }
  }

  // Struct field access: p.field
  const sfDotM = expr.match(/^(\w+)\.(\w+)$/);
  if (sfDotM && structLookup) {
    const fi = structLookup(sfDotM[1], sfDotM[2]);
    if (fi) return fi.watLoad;
  }

  // Math.* constants and functions
  if (expr.startsWith("Math.")) {
    const MATH_CONSTS: Record<string, string> = {
      PI:      "3.141592653589793",
      E:       "2.718281828459045",
      LN2:     "0.6931471805599453",
      LN10:    "2.302585092994046",
      LOG2E:   "1.4426950408889634",
      LOG10E:  "0.4342944819032518",
      SQRT2:   "1.4142135623730951",
      SQRT1_2: "0.7071067811865476",
    };
    const mathConstM = expr.match(/^Math\.(\w+)$/);
    if (mathConstM && MATH_CONSTS[mathConstM[1]] !== undefined) {
      return `(f64.const ${MATH_CONSTS[mathConstM[1]]})`;
    }
    const mathCallM = expr.match(/^Math\.(\w+)\(([\s\S]*)\)$/);
    if (mathCallM) {
      const fn   = mathCallM[1];
      const aStr = mathCallM[2].trim();
      const a    = aStr ? splitTopLevelArgs(aStr) : [];
      const arg0 = exprToWat(a[0] ?? "0", locals, "f64", funcLookup, allocString, arrayLookup, structLookup);
      const arg1 = exprToWat(a[1] ?? "0", locals, "f64", funcLookup, allocString, arrayLookup, structLookup);
      if (fn === "clz32")  return `(i32.clz ${exprToWat(a[0] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})`;
      if (fn === "imul")   return `(i32.mul ${exprToWat(a[0] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)} ${exprToWat(a[1] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})`;
      if (fn === "abs")    return expectedType === "i32" ? `(call $__i32_abs ${exprToWat(a[0] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})` : `(f64.abs ${arg0})`;
      if (fn === "min")    return expectedType === "i32" ? `(call $__i32_min ${exprToWat(a[0] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)} ${exprToWat(a[1] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})` : `(f64.min ${arg0} ${arg1})`;
      if (fn === "max")    return expectedType === "i32" ? `(call $__i32_max ${exprToWat(a[0] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)} ${exprToWat(a[1] ?? "0", locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})` : `(f64.max ${arg0} ${arg1})`;
      if (fn === "sqrt")   return `(f64.sqrt ${arg0})`;
      if (fn === "floor")  return `(f64.floor ${arg0})`;
      if (fn === "ceil")   return `(f64.ceil ${arg0})`;
      if (fn === "trunc")  return `(f64.trunc ${arg0})`;
      if (fn === "round")  return `(f64.nearest ${arg0})`;
      if (fn === "pow")    return `(call $__math_pow ${arg0} ${arg1})`;
      if (fn === "sign")   return `(if (result f64) (f64.eq ${arg0} (f64.const 0)) (then (f64.const 0)) (else (f64.copysign (f64.const 1) ${arg0})))`;
      if (fn === "hypot")  return `(f64.sqrt (f64.add (f64.mul ${arg0} ${arg0}) (f64.mul ${arg1} ${arg1})))`;
      if (fn === "fround") return `(f64.promote_f32 (f32.demote_f64 ${arg0}))`;
    }
  }

  // Simple identifier — only emit local.get if it is actually a declared local
  if (/^\w+$/.test(expr) && locals.has(expr)) return `(local.get $${expr})`;

  // Phase 5f: chained call — factoryFn(outerArgs)(innerArgs) closure factory
  {
    const factoryHead = expr.match(/^(\w+)\s*\(/)?.[1];
    if (factoryHead) {
      const factorySig = funcLookup?.(factoryHead);
      if (factorySig?.isClosureFactory) {
        const parts = extractChainedCallParts(expr);
        if (parts) {
          const outerArgList = parts.outerRaw ? splitTopLevelArgs(parts.outerRaw) : [];
          const outerWat = outerArgList.map((a, i) => {
            const ptype = factorySig.params[i]?.type ?? "i32";
            return exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup);
          }).join(" ");
          const innerSig = funcLookup?.(`${factoryHead}__inner`);
          const captureCount = innerSig?.closureCaptures?.length ?? 0;
          const innerCallParams = innerSig ? innerSig.params.slice(0, innerSig.params.length - captureCount) : [];
          const innerArgList = parts.innerRaw ? splitTopLevelArgs(parts.innerRaw) : [];
          const innerWat = innerArgList.map((a, i) => {
            const ptype = innerCallParams[i]?.type ?? "i32";
            return exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup);
          }).join(" ");
          return `(call $${factoryHead}__trampoline (call $${factoryHead} ${outerWat}) ${innerWat})`.trim();
        }
      }
    }
  }

  // Nested function call: name(args)
  const callMatch = expr.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    const sig = funcLookup?.(callee);
    // String params expand to two stack values
    const watArgsList = argList.flatMap((a, i) => {
      const ptype = sig?.params[i]?.type ?? "i32";
      return [exprToWat(a.trim(), locals, ptype, funcLookup, allocString, arrayLookup, structLookup)];
    });
    // Fill in default values for omitted trailing params
    if (sig) {
      const baseParamCount = sig.params.length - (sig.closureCaptures?.length ?? 0);
      for (let i = argList.length; i < baseParamCount; i++) {
        const param = sig.params[i];
        if (param.defaultValue !== undefined) {
          watArgsList.push(exprToWat(param.defaultValue, locals, param.type, funcLookup, allocString, arrayLookup, structLookup));
        }
      }
    }
    return watArgsList.length > 0 ? `(call $${callee} ${watArgsList.join(" ")})` : `(call $${callee})`;
  }

  // Parenthesised sub-expression — unwrap and recurse
  if (expr.startsWith("(") && expr.endsWith(")")) {
    return exprToWat(expr.slice(1, -1), locals, expectedType, funcLookup, allocString, arrayLookup, structLookup);
  }

  const isFloat = expectedType === "f64" || expectedType === "f32";
  // i64 is preserved; otherwise default numeric to f64
  const numType = isFloat ? (expectedType as string) : expectedType === "i64" ? "i64" : "f64";

  // Unary ! — logical not → i32.eqz
  if (expr.startsWith("!") && !expr.startsWith("!=")) {
    return `(i32.eqz ${exprToWat(expr.slice(1).trim(), locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})`;
  }

  // Unary ~ — bitwise not → i32.xor with -1
  if (expr.startsWith("~")) {
    return `(i32.xor ${exprToWat(expr.slice(1).trim(), locals, "i32", funcLookup, allocString, arrayLookup, structLookup)} (i32.const -1))`;
  }

  // Unary - on a non-literal (e.g. -x, -(a+b))
  if (expr.startsWith("-") && !/^-\d/.test(expr)) {
    const inner = expr.slice(1).trim();
    if (isFloat) return `(${expectedType}.neg ${exprToWat(inner, locals, numType, funcLookup, allocString, arrayLookup, structLookup)})`;
    return `(i32.sub (i32.const 0) ${exprToWat(inner, locals, "i32", funcLookup, allocString, arrayLookup, structLookup)})`;
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
      return `(if (result ${resType}) ${exprToWat(cond, locals, "i32", funcLookup, allocString, arrayLookup, structLookup)} (then ${exprToWat(thenPart, locals, resType, funcLookup, allocString, arrayLookup, structLookup)}) (else ${exprToWat(elsePart, locals, resType, funcLookup, allocString, arrayLookup, structLookup)}))`;
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
    return `(${watOp} ${exprToWat(lhs, locals, opType, funcLookup, allocString, arrayLookup, structLookup)} ${exprToWat(rhs, locals, opType, funcLookup, allocString, arrayLookup, structLookup)})`;
  }

  // Fallback: emit a comment and a zero of the expected type
  const zeroType = isFloat ? expectedType : expectedType === "i64" ? "i64" : "i32";
  const safeExpr = expr.replace(/\(;/g, "( ;").replace(/;\)/g, "; )") + " ";
  return `(;? ${safeExpr};) (${zeroType}.const 0)`;
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
  enumLookup?: (key: string) => number | undefined,
  arrayLookup?: ArrayLookup,
  structLookup?: StructFieldLookup,
  dotCallLookup?: DotCallLookup,
  globals?: Map<string, string>
): LogSegment[] {
  const args = splitTopLevelArgs(argsStr);
  const segments: LogSegment[] = [];

  for (let i = 0; i < args.length; i++) {
    if (i > 0) segments.push({ kind: "literal", text: " " }); // space between args
    segments.push(...parseSingleArg(args[i], locals, funcLookup, allocString, enumLookup, arrayLookup, structLookup, dotCallLookup, globals));
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
  indent = "    ",
  fd = 1,
  iovBase = IOV_BASE,
  scratchBase = SCRATCH_BASE,
): { statements: string[]; needsHelpers: boolean; needsStrGather: boolean; needsArrPrintHelper: boolean } {
  const nwrittenOffset = iovBase + (NWRITTEN_OFFSET - IOV_BASE); // = iovBase + 128
  // Step 1: merge consecutive literal segments to minimise iov count.
  // e.g. [{literal,"x: "},{literal," "},{literal,"\n"}] → [{literal,"x:  \n"}]
  const merged: LogSegment[] = [];
  for (const seg of segments) {
    const last = merged[merged.length - 1];
    if (seg.kind === "literal" && last?.kind === "literal") {
      merged[merged.length - 1] = { kind: "literal", text: last.text + seg.text };
    } else {
      merged.push({ ...seg } as LogSegment);
    }
  }

  // Step 2: detect a standalone trailing "\n" so we can absorb it inline.
  const numericKinds = new Set(["i32var","i64var","f64var","i32expr","i64expr","f64expr"]);
  const strBoolKinds = new Set(["strvar","boolvar"]);
  const trailingLitNL =
    merged.length >= 2 &&
    merged[merged.length - 1].kind === "literal" &&
    (merged[merged.length - 1] as { kind: "literal"; text: string }).text === "\n";
  const canInlineNL = trailingLitNL &&
    (numericKinds.has(merged[merged.length - 2].kind) || strBoolKinds.has(merged[merged.length - 2].kind));

  // Active segments to process (strip standalone "\n" when we will inline it).
  const activeSegs = (trailingLitNL && canInlineNL) ? merged.slice(0, -1) : merged;

  // Step 3: decide emit strategy.
  // Gather mode consolidates ALL output into scratch (SCRATCH_BASE...) and emits a
  // single fd_write iov — needed because wasmtime 43 only processes the first iov.
  // strvar uses memory.copy into scratch; boolvar uses conditional memory.copy.
  // boolexpr (arbitrary WAT) stays in per-iov mode (evaluated multiple times would be unsafe).
  const gatherable = (s: LogSegment) =>
    s.kind === "literal" || numericKinds.has(s.kind) || s.kind === "strvar" || s.kind === "boolvar" || s.kind === "arrptr";
  const arrptrKinds = new Set(["arrptr"]);
  // Single strvar/boolvar/arrptr segments also use gather so the newline can be inlined.
  const useGather = activeSegs.every(gatherable) &&
    (activeSegs.length > 1 || strBoolKinds.has(activeSegs[0]?.kind ?? "") || arrptrKinds.has(activeSegs[0]?.kind ?? ""));

  const statements: string[] = [];
  let needsHelpers = false;
  let needsStrGather = false;
  let needsArrPrintHelper = false;

  if (useGather) {
    // ── Gather-buffer mode ────────────────────────────────────────────────────
    // iov[0].ptr (iovBase+0) = scratchBase  (set once)
    // iov[0].len (iovBase+4) doubles as the running cursor into scratch.
    const cursorAddr = iovBase + 4;
    statements.push(
      `${indent}(i32.store (i32.const ${iovBase}) (i32.const ${scratchBase}))`,
      `${indent}(i32.store (i32.const ${cursorAddr}) (i32.const 0))`,
    );

    let compileCursor = 0;   // byte offset from SCRATCH_BASE, valid until first numeric
    let runtimeCursor = false; // true after the first numeric (cursor only in mem[cursorAddr])

    for (const seg of activeSegs) {
      if (seg.kind === "literal") {
        const bytes = Array.from(new TextEncoder().encode(seg.text));
        if (!runtimeCursor) {
          // Compile-time position: fixed-address stores
          for (let j = 0; j < bytes.length; j++) {
            statements.push(
              `${indent}(i32.store8 (i32.const ${scratchBase + compileCursor + j}) (i32.const ${bytes[j]}))`,
            );
          }
          compileCursor += bytes.length;
        } else {
          // Runtime position: cursor-relative stores then advance cursor
          for (let j = 0; j < bytes.length; j++) {
            statements.push(
              `${indent}(i32.store8 (i32.add (i32.const ${scratchBase}) (i32.add (i32.load (i32.const ${cursorAddr})) (i32.const ${j}))) (i32.const ${bytes[j]}))`,
            );
          }
          if (bytes.length > 0) {
            statements.push(
              `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) (i32.const ${bytes.length})))`,
            );
          }
        }
      } else if (seg.kind === "strvar") {
        // String variable — copy bytes into scratch via $__str_gather, advance cursor
        // $__str_gather(src_ptr, src_len, dst_ptr) — a byte-copy loop helper, no bulk-memory needed
        needsStrGather = true;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        statements.push(
          `${indent}(call $__str_gather (local.get $${seg.ptrLocal}) (local.get $${seg.lenLocal}) ${destExpr})`,
        );
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) (local.get $${seg.lenLocal})))`,
          );
          runtimeCursor = true;
        } else {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) (local.get $${seg.lenLocal})))`,
          );
        }
      } else if (seg.kind === "boolvar") {
        // Bool variable — copy "true"/"false" bytes into scratch via $__str_gather, advance cursor
        needsStrGather = true;
        const [trueOff]  = allocString("true");
        const [falseOff] = allocString("false");
        const val = `(local.get $${seg.name})`;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        const srcExpr = `(if (result i32) ${val} (then (i32.const ${trueOff})) (else (i32.const ${falseOff})))`;
        const lenExpr = `(if (result i32) ${val} (then (i32.const 4)) (else (i32.const 5)))`;
        statements.push(
          `${indent}(call $__str_gather ${srcExpr} ${lenExpr} ${destExpr})`,
        );
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) ${lenExpr}))`,
          );
          runtimeCursor = true;
        } else {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) ${lenExpr}))`,
          );
        }
      } else if (seg.kind === "arrptr") {
        // Array pointer — write "[ elem, ... ]" into scratch via helper
        needsArrPrintHelper = true;
        needsHelpers = true; // $__write_i32arr_to_scratch depends on $__i32_to_str
        // Flush compile-time cursor to memory before calling helper
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.const ${compileCursor}))`,
          );
          runtimeCursor = true;
        }
        const helperName = seg.elemType === "f64" ? "$__write_f64arr_to_scratch"
                         : seg.elemType === "i64" ? "$__write_i64arr_to_scratch"
                         : "$__write_i32arr_to_scratch";
        statements.push(
          `${indent}(call ${helperName} ${seg.wat} (i32.const ${scratchBase}) (i32.const ${cursorAddr}))`,
        );
      } else {
        // Numeric segment — convert directly into scratch at current cursor position
        needsHelpers = true;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;

        let callExpr: string;
        if (seg.kind === "i32var") {
          callExpr = `(call $__i32_to_str (local.get $${seg.name}) ${destExpr})`;
        } else if (seg.kind === "i64var") {
          callExpr = `(call $__i64_to_str (local.get $${seg.name}) ${destExpr})`;
        } else if (seg.kind === "f64var") {
          callExpr = `(call $__f64_to_str (local.get $${seg.name}) ${destExpr})`;
        } else if (seg.kind === "i32expr") {
          callExpr = `(call $__i32_to_str ${seg.wat} ${destExpr})`;
        } else if (seg.kind === "i64expr") {
          callExpr = `(call $__i64_to_str ${seg.wat} ${destExpr})`;
        } else {
          callExpr = `(call $__f64_to_str ${seg.wat} ${destExpr})`;
        }

        if (!runtimeCursor) {
          // cursor = compileCursor + result_of_call
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) ${callExpr}))`,
          );
          runtimeCursor = true;
        } else {
          // cursor = cursor + result_of_call
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) ${callExpr}))`,
          );
        }
      }
    }

    // Inline the trailing newline into scratch
    if (canInlineNL) {
      statements.push(
        `${indent}(i32.store8 (i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr}))) (i32.const 10))`,
        `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) (i32.const 1)))`,
      );
    }

    // Single fd_write — iov[0].ptr is scratchBase, iov[0].len is the cursor value
    statements.push(
      `${indent}(drop (call $fd_write`,
      `${indent}  (i32.const ${fd})`,
      `${indent}  (i32.const ${iovBase})`,
      `${indent}  (i32.const 1)`,
      `${indent}  (i32.const ${nwrittenOffset})))`,
    );
  } else {
    // ── Per-iov mode (single active segment, or strvar/bool segments) ─────────
    let numericSlot = 0;
    let lastNumericScratch = -1;
    let lastNumericIovLen  = -1;

    for (let i = 0; i < activeSegs.length; i++) {
      const seg = activeSegs[i];
      const iovPtr = iovBase + i * 8;      // iov[i].buf  (i32)
      const iovLen = iovBase + i * 8 + 4;  // iov[i].buf_len (i32)

      if (seg.kind === "literal") {
        const [offset, len] = allocString(seg.text);
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${offset}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (i32.const ${len}))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen  = -1;
      } else if (seg.kind === "strvar") {
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (local.get $${seg.ptrLocal}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (local.get $${seg.lenLocal}))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen  = -1;
      } else if (seg.kind === "boolvar" || seg.kind === "boolexpr") {
        const [trueOff]  = allocString("true");
        const [falseOff] = allocString("false");
        const val = seg.kind === "boolvar" ? `(local.get $${seg.name})` : seg.wat;
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (if (result i32) ${val} (then (i32.const ${trueOff})) (else (i32.const ${falseOff}))))`,
          `${indent}(i32.store (i32.const ${iovLen}) (if (result i32) ${val} (then (i32.const 4)) (else (i32.const 5))))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen  = -1;
      } else {
        // Numeric segment
        if (numericSlot >= SCRATCH_SLOTS) {  // SCRATCH_SLOTS = 4 (constant)
          const [offset, len] = allocString("?");
          statements.push(
            `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${offset}))`,
            `${indent}(i32.store (i32.const ${iovLen}) (i32.const ${len}))`,
          );
          continue;
        }

        needsHelpers = true;
        const scratchPtr = scratchBase + numericSlot * 32;
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
        lastNumericScratch = scratchPtr;
        lastNumericIovLen  = iovLen;
      }
    }

    // Inline the newline byte into the last numeric scratch buffer.
    if (canInlineNL && lastNumericScratch >= 0) {
      statements.push(
        `${indent}(i32.store8 (i32.add (i32.const ${lastNumericScratch}) (i32.load (i32.const ${lastNumericIovLen}))) (i32.const 10))`,
        `${indent}(i32.store (i32.const ${lastNumericIovLen}) (i32.add (i32.load (i32.const ${lastNumericIovLen})) (i32.const 1)))`,
      );
    }

    statements.push(
      `${indent}(drop (call $fd_write`,
      `${indent}  (i32.const ${fd})`,
      `${indent}  (i32.const ${iovBase})`,
      `${indent}  (i32.const ${activeSegs.length})`,
      `${indent}  (i32.const ${nwrittenOffset})))`,
    );
  }

  return { statements, needsHelpers, needsStrGather, needsArrPrintHelper };
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

/**
 * Returns a WAT helper function that writes a dynamic i32 array's contents
 * into the scratch gather buffer in "[ elem, elem, ... ]" format.
 *
 * Signature: $__write_i32arr_to_scratch(arr_ptr: i32, scratch_base: i32, cursor_addr: i32)
 *   arr_ptr     – pointer to [length:i32, capacity:i32, elem0:i32, ...]
 *   scratch_base – start address of the scratch buffer (i32.const scratchBase)
 *   cursor_addr  – address of the i32 cursor (running byte offset from scratch_base)
 * Depends on: $__i32_to_str (from getHelperWat)
 */
export function getArrPrintHelperWat(): string {
  return `
  ;; ── write i32[] to scratch ────────────────────────────────────────────────
  ;; Appends "[ elem, elem, ... ]" into the gather buffer.
  ;; arr_ptr layout: [length:i32, capacity:i32, elem0:i32, elem1:i32, ...]
  (func $__write_i32arr_to_scratch (param $arr_ptr i32) (param $scratch_base i32) (param $cursor_addr i32)
    (local $len i32)
    (local $idx i32)
    (local $cur i32)
    (local $elem i32)
    (local $slen i32)
    (local.set $len (i32.load (local.get $arr_ptr)))
    (local.set $cur (i32.load (local.get $cursor_addr)))
    ;; Write "[ "
    (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 91))
    (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
    (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 32))
    (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
    ;; Loop over elements
    (local.set $idx (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $idx) (local.get $len)))
        ;; Write ", " separator between elements
        (if (i32.gt_u (local.get $idx) (i32.const 0))
          (then
            (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 44))
            (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
            (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 32))
            (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
          )
        )
        ;; Load element at arr_ptr+8+idx*4 and convert to decimal string
        (local.set $elem (i32.load (i32.add (i32.add (local.get $arr_ptr) (i32.const 8)) (i32.shl (local.get $idx) (i32.const 2)))))
        (local.set $slen (call $__i32_to_str (local.get $elem) (i32.add (local.get $scratch_base) (local.get $cur))))
        (local.set $cur (i32.add (local.get $cur) (local.get $slen)))
        (local.set $idx (i32.add (local.get $idx) (i32.const 1)))
        (br $loop)
      )
    )
    ;; Write " ]"
    (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 32))
    (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
    (i32.store8 (i32.add (local.get $scratch_base) (local.get $cur)) (i32.const 93))
    (local.set $cur (i32.add (local.get $cur) (i32.const 1)))
    ;; Update cursor
    (i32.store (local.get $cursor_addr) (local.get $cur))
  )`;
}
