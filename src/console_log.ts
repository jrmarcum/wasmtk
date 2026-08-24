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
export const DATA_BASE: number = SCRATCH_BASE + SCRATCH_SLOTS * 32; // 260

// ---------------------------------------------------------------------------
// Escape-sequence processing
// ---------------------------------------------------------------------------

/**
 * Converts TypeScript/JavaScript escape sequences in a raw source string
 * (the content between the surrounding quote characters) to their actual
 * character values. The surrounding quotes must NOT be included.
 *
 * Supported sequences:
 *   \n \r \t \b \f \v \0  \\ \' \" \`
 *   \xHH          (hex byte, exactly 2 hex digits)
 *   \uHHHH        (Unicode code point, exactly 4 hex digits, UTF-8 encoded)
 *   \u{H…}        (Unicode code point, variable hex digits, UTF-8 encoded)
 *
 * Malformed sequences (e.g. \x with fewer than 2 hex digits) are passed
 * through unchanged so the compiler never silently loses source content.
 */
export function unescapeString(raw: string): string {
  if (!raw.includes("\\")) return raw; // fast path: no escapes present
  let result = "";
  let i = 0;
  while (i < raw.length) {
    if (raw[i] !== "\\") {
      result += raw[i++];
      continue;
    }
    i++; // skip the backslash
    if (i >= raw.length) {
      result += "\\";
      break;
    }
    const ch = raw[i];
    switch (ch) {
      case "n":
        result += "\n";
        i++;
        break;
      case "r":
        result += "\r";
        i++;
        break;
      case "t":
        result += "\t";
        i++;
        break;
      case "b":
        result += "\b";
        i++;
        break;
      case "f":
        result += "\f";
        i++;
        break;
      case "v":
        result += "\v";
        i++;
        break;
      case "0":
        result += "\0";
        i++;
        break;
      case "\\":
        result += "\\";
        i++;
        break;
      case "'":
        result += "'";
        i++;
        break;
      case '"':
        result += '"';
        i++;
        break;
      case "`":
        result += "`";
        i++;
        break;
      case "x": {
        const hex = raw.slice(i + 1, i + 3);
        if (/^[0-9a-fA-F]{2}$/.test(hex)) {
          result += String.fromCharCode(parseInt(hex, 16));
          i += 3; // skip 'x' + 2 hex digits
        } else {
          result += "\\x";
          i++; // malformed — pass through
        }
        break;
      }
      case "u": {
        if (raw[i + 1] === "{") {
          // \u{H…} variable-length code point
          const end = raw.indexOf("}", i + 2);
          if (end !== -1 && end > i + 2) {
            const hex = raw.slice(i + 2, end);
            if (/^[0-9a-fA-F]+$/.test(hex)) {
              result += String.fromCodePoint(parseInt(hex, 16));
              i = end + 1;
            } else {
              result += "\\u{";
              i++;
            }
          } else {
            result += "\\u{";
            i++;
          }
        } else {
          // \uHHHH exactly 4 hex digits
          const hex = raw.slice(i + 1, i + 5);
          if (/^[0-9a-fA-F]{4}$/.test(hex)) {
            result += String.fromCodePoint(parseInt(hex, 16));
            i += 5; // skip 'u' + 4 hex digits
          } else {
            result += "\\u";
            i++;
          }
        }
        break;
      }
      default:
        result += ch;
        i++; // unknown escape → pass the character through
        break;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Segment types
// ---------------------------------------------------------------------------

/**
 * Callback for looking up a function's parameter types by name.
 * Return `undefined` if the function is unknown; parameter types default to "i32".
 */
export type FuncLookup = (name: string) => {
  params: Array<{ type: string; defaultValue?: string; structType?: string }>;
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

/**
 * Module-level string-array allocator: set by wasic.ts before calling parseConsoleLogArgs,
 * cleared afterward. Compilation is synchronous so no concurrency risk.
 */
let _strArrAlloc: ((elements: string[]) => number) | undefined = undefined;
/**
 * Inject the callback that allocates an inline string-array literal into the WASM data section
 * and returns its base pointer, used when emitting `console.log` of a string array. Pass
 * `undefined` to clear it.
 */
export function setStringArrayAllocator(fn: ((elements: string[]) => number) | undefined): void {
  _strArrAlloc = fn;
}

let _structLiteralAlloc:
  | ((structName: string, initFields: Record<string, string>) => number)
  | undefined = undefined;
/**
 * Inject the callback that allocates an inline struct literal (by struct name + field values) into
 * the WASM data section and returns its base pointer, used when a struct literal appears as a
 * `console.log` argument. Pass `undefined` to clear it.
 */
export function setStructLiteralAllocator(
  fn: ((structName: string, initFields: Record<string, string>) => number) | undefined,
): void {
  _structLiteralAlloc = fn;
}

let _structArgLayoutCheck: ((callee: string, argList: string[]) => void) | undefined = undefined;
/**
 * Inject the callback that validates struct-pointer arguments of a direct call against the
 * parameter types they bind to (Phase 33 layout-prefix guard). This module knows the call's
 * argument TEXT but not the struct layouts, so wasic.ts owns the check; without this hook a
 * `console.log(f(x))`-nested call would bypass it entirely. Pass `undefined` to clear it.
 */
export function setStructArgLayoutChecker(
  fn: ((callee: string, argList: string[]) => void) | undefined,
): void {
  _structArgLayoutCheck = fn;
}

/** Called when exprToWat emits a $__str_cmp call so wasic can enable the helper. */
let _strCmpNeeded: (() => void) | undefined = undefined;
/**
 * Inject the callback invoked when this module emits a `$__str_cmp` call, signaling wasic to emit
 * the string-comparison helper. Pass `undefined` to clear it.
 */
export function setStrCmpNeededCallback(fn: (() => void) | undefined): void {
  _strCmpNeeded = fn;
}

/** Callback to get the function table index for a named function. Set by wasic.ts around parseConsoleLogArgs. */
let _funcTableLookup: ((name: string) => number | undefined) | undefined = undefined;
/**
 * Inject the callback that resolves a named function to its function-table index (returns
 * `undefined` for unknown names), used when a function reference is passed as a `console.log`
 * argument. Pass `undefined` to clear it.
 */
export function setFuncTableLookup(fn: ((name: string) => number | undefined) | undefined): void {
  _funcTableLookup = fn;
}

/** Phase 51: resolve `x instanceof ClassName` to a WAT i32 bool via wasic's emitExpr (which owns
 *  the class tag / inheritance tables). Set by wasic.ts around parseConsoleLogArgs. */
let _instanceofResolver:
  | ((token: string, locals: Map<string, string>) => string | undefined)
  | undefined = undefined;
/**
 * Inject the callback that resolves an `x instanceof ClassName` token to a WAT i32 bool expression
 * via wasic's emitExpr (which owns the class tag / inheritance tables); returns `undefined` when
 * the token isn't an instanceof check. Pass `undefined` to clear it.
 */
export function setInstanceofResolver(
  fn: ((token: string, locals: Map<string, string>) => string | undefined) | undefined,
): void {
  _instanceofResolver = fn;
}

/** Resolve a bare identifier that holds a STRING-ENUM value to a ptr/len pair. Such a variable's
 *  WAT value is the member's synthetic i32 tag, so printing it needs a runtime tag→string mapping
 *  (`$__enum_str_<Enum>`); without this it printed the raw tag. Returns undefined for every other
 *  identifier. Set by wasic.ts around parseConsoleLogArgs. */
let _enumStrVarResolver:
  | ((token: string) => { ptrWat: string; lenWat: string } | undefined)
  | undefined = undefined;
/**
 * Inject the callback that maps a string-enum-typed variable to its member text at runtime.
 * Pass `undefined` to clear it.
 */
export function setEnumStrVarResolver(
  fn: ((token: string) => { ptrWat: string; lenWat: string } | undefined) | undefined,
): void {
  _enumStrVarResolver = fn;
}

/** Resolve a nullish-coalescing token (`a ?? b`) to a WAT expression plus its result type via
 *  wasic's emitExpr, which owns the Phase 24 nullable-variable tables (`$x__null` companions)
 *  this module has no view of. Set by wasic.ts around parseConsoleLogArgs. Returns undefined
 *  when the token has no depth-0 `??`. */
let _nullishResolver:
  | ((
    token: string,
    locals: Map<string, string>,
  ) => { wat: string; type: string } | undefined)
  | undefined = undefined;
/**
 * Inject the callback that resolves an `a ?? b` token to a WAT expression via wasic's emitExpr;
 * returns `undefined` when the token isn't a nullish coalesce. Pass `undefined` to clear it.
 */
export function setNullishResolver(
  fn:
    | ((token: string, locals: Map<string, string>) => { wat: string; type: string } | undefined)
    | undefined,
): void {
  _nullishResolver = fn;
}

/** Resolve a string-producing expression (e.g. `s.toUpperCase()`, `arr[i].toUpperCase()`) to a
 *  ptr/len WAT pair via wasic's emitStringPtrLen (captured into temp locals). Set by wasic.ts
 *  around parseConsoleLogArgs. Returns undefined when the token isn't a handled string expr. */
let _stringExprResolver:
  | ((token: string, locals: Map<string, string>) => { ptrWat: string; lenWat: string } | undefined)
  | undefined = undefined;
/**
 * Inject the callback that resolves a string-producing expression (e.g. `s.toUpperCase()`,
 * `arr[i].toUpperCase()`) to a ptr/len WAT pair via wasic's emitStringPtrLen; returns `undefined`
 * when the token isn't a handled string expression. Pass `undefined` to clear it.
 */
export function setStringExprResolver(
  fn:
    | ((
      token: string,
      locals: Map<string, string>,
    ) => { ptrWat: string; lenWat: string } | undefined)
    | undefined,
): void {
  _stringExprResolver = fn;
}

/** Callback to resolve an array variable by name: returns its element type, base ptr, and length.
 *  ptr=-1 means runtime local (param). ptr=-2 means dynamic heap array (local with 8-byte header).
 *  dynamic=true means the array has a [length, capacity] header at its pointer. */
export type ArrayLookup = (name: string) => {
  elemType: string;
  ptr: number;
  length: number;
  dynamic?: boolean;
  /** Phase 31: override shift for sub-word TypedArrays (0=byte, 1=halfword, 2=word, 3=dword) */
  shift?: number;
  /** Phase 31: override load instruction for sub-word TypedArrays */
  customLoadOp?: string;
  /** True when the array is a module-level global (use global.get instead of local.get). */
  isGlobal?: boolean;
  /** True when this is a string array (8-byte elements: [ptr i32, len i32]). */
  isStringArr?: boolean;
  /** Phase 6d: true when this is a 2D array (outer stores i32 row pointers). */
  is2D?: boolean;
} | undefined;

/**
 * Callback to resolve a struct field access `varName.fieldName`.
 * Returns the field's WAT type string and the WAT load expression, or undefined if not a struct field.
 */
export type StructFieldLookup = (
  varName: string,
  fieldName: string,
) => { type: string; watLoad: string; watLoadLen?: string } | undefined;

/**
 * Callback to resolve a dot-call expression like `receiver.method(args)`.
 * Returns the WAT expression and return type, or undefined if not handled.
 * Used by console_log to support class instance/static method calls in argument position.
 */
export type DotCallLookup = (token: string) => { type: string; wat: string } | undefined;

/**
 * Callback to resolve a closure-typed variable call like `varName(args)`.
 * Returns the trampoline funcType string, params, and result, or undefined if not a closure var.
 */
export type ClosureVarLookup = (name: string) => {
  params: string[];
  result: string | null;
  funcType: string; // e.g. "$ftype_i32_r_f64"
} | undefined;

/** A parsed fragment of a console.log argument list. */
export type LogSegment =
  | { kind: "literal"; text: string } // static string (embedded in data section)
  | { kind: "i32var"; name: string } // local i32 variable
  | { kind: "i64var"; name: string } // local i64 variable
  | { kind: "f64var"; name: string } // local f64 variable
  | { kind: "i32expr"; wat: string } // arbitrary WAT expression yielding i32
  | { kind: "i64expr"; wat: string } // arbitrary WAT expression yielding i64
  | { kind: "f64expr"; wat: string } // arbitrary WAT expression yielding f64
  | { kind: "strvar"; ptrLocal: string; lenLocal: string } // string variable (ptr + len i32 locals)
  | { kind: "boolvar"; name: string } // bool-typed local (i32, 0=false 1=true)
  | { kind: "boolexpr"; wat: string } // arbitrary WAT expression yielding bool i32
  | { kind: "arrptr"; wat: string; elemType: string } // WAT expression yielding a dynamic array ptr
  | { kind: "joinarr"; arrWat: string; sepPtr: number; sepLen: number; elemType: string } // arr.join(sep)
  | { kind: "strcall"; callWat: string } // void WAT call that sets $__str_ret_ptr/$__str_ret_len
  | { kind: "strexpr"; ptrWat: string; lenWat: string }; // arbitrary WAT expressions yielding string ptr+len

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
    if ((inDouble || inSingle || inTemplate) && ch === "\\") {
      i++;
      continue;
    }
    if (ch === "`" && !inDouble && !inSingle) {
      inTemplate = !inTemplate;
      continue;
    }
    if (ch === '"' && !inTemplate && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (ch === "'" && !inTemplate && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
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
  return args.filter((a) => a.length > 0);
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
    else if (expr[i] === ")") {
      depth--;
      if (depth === 0) break;
    }
    i++;
  }
  const outerRaw = expr.slice(firstParen + 1, i);
  const rest = expr.slice(i + 1).trimStart();
  if (!rest.startsWith("(")) return null;
  let depth2 = 0, j = 0;
  while (j < rest.length) {
    if (rest[j] === "(") depth2++;
    else if (rest[j] === ")") {
      depth2--;
      if (depth2 === 0) break;
    }
    j++;
  }
  return { outerRaw, innerRaw: rest.slice(1, j) };
}

/** Returns true if expr looks like a string-typed expression (literal, string local, or string array element). */
function looksLikeString(
  expr: string,
  locals: Map<string, string>,
  arrayLookup?: ArrayLookup,
): boolean {
  const t = expr.trim();
  if (/^["']/.test(t)) return true; // string literal
  if (/^\w+$/.test(t) && locals.get(t) === "string") return true; // string variable
  const bm = t.match(/^(\w+)\[/);
  if (bm && arrayLookup) {
    const ai = arrayLookup(bm[1]);
    if (ai?.elemType === "string") return true; // string array element
  }
  return false;
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
  globals?: Map<string, string>,
  enumStringLookup?: (key: string) => string | undefined,
  closureVarLookup?: ClosureVarLookup,
): LogSegment[] {
  token = token.trim();

  // ── Template literal: `text ${expr} text ...`
  if (token.startsWith("`") && token.endsWith("`")) {
    return parseTemplateLiteral(
      token.slice(1, -1),
      locals,
      funcLookup,
      allocString,
      enumLookup,
      arrayLookup,
      structLookup,
      dotCallLookup,
      globals,
      enumStringLookup,
      closureVarLookup,
    );
  }

  // ── Double-quoted string literal (must be ONE complete literal, not `"a" + "b"`)
  if (isWholeStringLiteral(token, '"')) {
    return [{ kind: "literal", text: unescapeString(token.slice(1, -1)) }];
  }

  // ── Single-quoted string literal
  if (isWholeStringLiteral(token, "'")) {
    return [{ kind: "literal", text: unescapeString(token.slice(1, -1)) }];
  }

  // ── (N).toString(radix) on a literal number → constant-fold to the radix string (e.g.
  // (14).toString(2) → "1110"). Runtime-value radix conversion is not yet supported.
  const toStrRadixLit = token.match(/^\(?\s*(-?\d+)\s*\)?\s*\.toString\s*\(\s*(\d+)\s*\)$/);
  if (toStrRadixLit) {
    const radix = parseInt(toStrRadixLit[2]!, 10);
    if (radix >= 2 && radix <= 36) {
      return [{ kind: "literal", text: parseInt(toStrRadixLit[1]!, 10).toString(radix) }];
    }
  }

  // ── Numeric literal (compile-time constant → embed as string)
  if (/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(token)) {
    return [{ kind: "literal", text: String(Number(token)) }];
  }

  // ── Phase 24: null / undefined literals
  if (token === "null") return [{ kind: "literal", text: "null" }];
  if (token === "undefined") return [{ kind: "literal", text: "undefined" }];

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
        ...parseSingleArg(
          lhs,
          locals,
          funcLookup,
          allocString,
          enumLookup,
          arrayLookup,
          structLookup,
          dotCallLookup,
          globals,
          enumStringLookup,
          closureVarLookup,
        ),
        ...parseSingleArg(
          rhs,
          locals,
          funcLookup,
          allocString,
          enumLookup,
          arrayLookup,
          structLookup,
          dotCallLookup,
          globals,
          enumStringLookup,
          closureVarLookup,
        ),
      ];
    }
    // Arithmetic + — fall through to the expression handler below
  }

  // ── Boolean literals
  if (token === "true") return [{ kind: "boolexpr", wat: "(i32.const 1)" }];
  if (token === "false") return [{ kind: "boolexpr", wat: "(i32.const 0)" }];

  // ── Bigint literal: 42n → i64 constant (must come before identifier check since /^\w+$/ matches "1n")
  if (/^-?\d+n$/.test(token)) {
    const n = token.slice(0, -1);
    return [{ kind: "i64expr", wat: `(i64.const ${n})` }];
  }

  // ── Phase 29: an identifier holding a STRING-ENUM value prints its member TEXT, not the
  // synthetic i32 tag it is stored as. Must precede the simple-identifier handler below, which
  // would emit it as a plain i32 (that is what printed `0` / `2` instead of `INFO` / `ERROR`).
  if (_enumStrVarResolver && /^\w+$/.test(token)) {
    const es = _enumStrVarResolver(token);
    if (es) return [{ kind: "strexpr" as const, ptrWat: es.ptrWat, lenWat: es.lenWat }];
  }

  // ── Simple identifier
  if (/^\w+$/.test(token)) {
    // Module-level globals: emit global.get instead of local.get
    if (globals?.has(token)) {
      const gType = globals.get(token)!;
      // Module-level string constant encoded as "string:offset:len"
      if (gType.startsWith("string:")) {
        const parts = gType.split(":");
        const offset = Number(parts[1]);
        const len = Number(parts[2]);
        return [{
          kind: "strvar" as const,
          ptrLocal: `__strconst_ptr_${offset}`,
          lenLocal: `__strconst_len_${len}`,
        }];
      }
      // Mutable module-level string global encoded as "strglobal:name" → read the ptr/len pair
      if (gType.startsWith("strglobal:")) {
        const gname = gType.slice("strglobal:".length);
        return [{
          kind: "strexpr" as const,
          ptrWat: `(global.get $${gname}_ptr)`,
          lenWat: `(global.get $${gname}_len)`,
        }];
      }
      const wat = `(global.get $${token})`;
      if (gType === "i64") return [{ kind: "i64expr", wat }];
      if (gType === "f64" || gType === "f32") return [{ kind: "f64expr", wat }];
      return [{ kind: "i32expr", wat }];
    }
    const wtype = locals.get(token);
    if (wtype === "string") {
      return [{ kind: "strvar", ptrLocal: `${token}_ptr`, lenLocal: `${token}_len` }];
    }
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
    return [{
      kind: "strvar",
      ptrLocal: `${errMsgMatch[1]}_ptr`,
      lenLocal: `${errMsgMatch[1]}_len`,
    }];
  }

  // ── Enum member access: EnumName.MemberName → i32 constant or string literal
  // Check enumStringLookup FIRST so heterogeneous enums (string + numeric members
  // in the same enum, where string members also have synthetic i32 tags) still
  // print the string value in display contexts.
  const enumMatch = token.match(/^(\w+)\.(\w+)$/);
  if (enumMatch) {
    const key = `${enumMatch[1]}.${enumMatch[2]}`;
    if (enumStringLookup) {
      const strVal = enumStringLookup(key);
      if (strVal !== undefined) return [{ kind: "literal", text: strVal }];
    }
    if (enumLookup) {
      const val = enumLookup(key);
      if (val !== undefined) return [{ kind: "i32expr", wat: `(i32.const ${val})` }];
    }
  }

  // ── Struct field access: p.field
  const sfDotMatch = token.match(/^(\w+)\.(\w+)$/);
  if (sfDotMatch && structLookup) {
    const fi = structLookup(sfDotMatch[1], sfDotMatch[2]);
    if (fi) {
      if (fi.type === "string" && fi.watLoadLen) {
        return [{ kind: "strexpr" as const, ptrWat: fi.watLoad, lenWat: fi.watLoadLen }];
      }
      const kind = fi.type === "f64" || fi.type === "f32"
        ? "f64expr" as const
        : fi.type === "i64"
        ? "i64expr" as const
        : fi.type === "bool"
        ? "boolexpr" as const
        : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }

  // Array element struct field access: arr[idx].field
  // Pass "arr[idx]" as virtual varName to structLookup; structLookupFn handles the bracket form.
  const arrElemDotMatch = token.match(/^(\w+)\[([^\]]*)\]\.(\w+)$/);
  if (arrElemDotMatch && structLookup) {
    const fi = structLookup(`${arrElemDotMatch[1]}[${arrElemDotMatch[2]}]`, arrElemDotMatch[3]);
    if (fi) {
      if (fi.type === "string" && fi.watLoadLen) {
        return [{ kind: "strexpr" as const, ptrWat: fi.watLoad, lenWat: fi.watLoadLen }];
      }
      const kind = fi.type === "f64" || fi.type === "f32"
        ? "f64expr" as const
        : fi.type === "i64"
        ? "i64expr" as const
        : fi.type === "bool"
        ? "boolexpr" as const
        : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }

  // Phase 42: three-part chained struct field access: a.b.c
  // Pass "a.b" as virtual varName to structLookup so it resolves nested struct pointer
  const sfChainedDotMatch = token.match(/^(\w+)\.(\w+)\.(\w+)$/);
  if (sfChainedDotMatch && structLookup) {
    const fi = structLookup(
      `${sfChainedDotMatch[1]}.${sfChainedDotMatch[2]}`,
      sfChainedDotMatch[3],
    );
    if (fi) {
      if (fi.type === "string" && fi.watLoadLen) {
        return [{ kind: "strexpr" as const, ptrWat: fi.watLoad, lenWat: fi.watLoadLen }];
      }
      const kind = fi.type === "f64" || fi.type === "f32"
        ? "f64expr" as const
        : fi.type === "i64"
        ? "i64expr" as const
        : fi.type === "bool"
        ? "boolexpr" as const
        : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }

  // ── String-producing method call: receiver.toUpperCase()/toLowerCase()/trim()/slice()/...
  // (receiver may be a plain string var OR a string-array element arr[i]). Routed through wasic's
  // emitStringPtrLen via the resolver, which captures the ptr/len into temp locals.
  // Receiver may be a var, string literal ("12".padStart), or a call (toFixed(..).padStart) — the
  // resolver delegates to emitStringPtrLen and returns undefined for anything it can't resolve, so a
  // permissive receiver pattern is safe (non-string tokens fall through to the handlers below).
  if (
    _stringExprResolver &&
    /^.+\.(toUpperCase|toLowerCase|trim|trimStart|trimEnd|trimLeft|trimRight|slice|charAt|substring|substr|replace|replaceAll|padStart|padEnd|repeat|toString)\s*\(/
      .test(token)
  ) {
    const r = _stringExprResolver(token, locals);
    if (r) return [{ kind: "strexpr" as const, ptrWat: r.ptrWat, lenWat: r.lenWat }];
  }

  // ── Chained `new ClassName(...).method(...)` (possibly inside a binary op): route through
  // dotCallLookup, which delegates to wasic's emitExpr (it owns the new+method-chain handler and the
  // binary-op loop). Returns undefined for anything emitExpr can't resolve, so it's safe.
  if (dotCallLookup && /^new\s+[A-Z]\w*\s*\(/.test(token)) {
    const r = dotCallLookup(token);
    if (r) {
      const k = r.type === "f64" || r.type === "f32"
        ? "f64expr" as const
        : r.type === "i64"
        ? "i64expr" as const
        : r.type === "bool"
        ? "boolexpr" as const
        : "i32expr" as const;
      return [{ kind: k, wat: r.wat }];
    }
  }

  // ── Dot-call expression: receiver.method(args) or this.method(args) — class/static calls
  // Skip Math.* and Number.* tokens — they have their own dedicated handlers below.
  if (
    dotCallLookup && !token.startsWith("Math.") && !token.startsWith("Number.") &&
    /^(?:this|\w+(?:\[[^\]]*\])?)\.(\w+)\s*\(/.test(token)
  ) {
    const result = dotCallLookup(token);
    if (result) {
      const kind = result.type === "f64" || result.type === "f32"
        ? "f64expr" as const
        : result.type === "i64"
        ? "i64expr" as const
        : result.type === "bool"
        ? "boolexpr" as const
        : "i32expr" as const;
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
            return exprToWat(
              a.trim(),
              locals,
              ptype,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            );
          }).join(" ");
          const innerSig = funcLookup?.(`${factoryHead}__inner`);
          const captureCount = innerSig?.closureCaptures?.length ?? 0;
          const innerCallParams = innerSig
            ? innerSig.params.slice(0, innerSig.params.length - captureCount)
            : [];
          const innerArgList = parts.innerRaw ? splitTopLevelArgs(parts.innerRaw) : [];
          const innerWat = innerArgList.map((a, i) => {
            const ptype = innerCallParams[i]?.type ?? "i32";
            return exprToWat(
              a.trim(),
              locals,
              ptype,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            );
          }).join(" ");
          const wat =
            `(call $${factoryHead}__trampoline (call $${factoryHead} ${outerWat}) ${innerWat})`
              .trim();
          const innerResult = innerSig?.result;
          const kind = innerResult === "f64" || innerResult === "f32"
            ? "f64expr" as const
            : innerResult === "i64"
            ? "i64expr" as const
            : "i32expr" as const;
          return [{ kind, wat }];
        }
      }
    }
  }

  // ── String(varName) where varName is a string local → pass through as strvar
  const stringCastMatch = token.match(/^String\s*\(\s*(\w+)\s*\)$/);
  if (stringCastMatch && locals.get(stringCastMatch[1]) === "string") {
    const v = stringCastMatch[1];
    return [{ kind: "strvar", ptrLocal: `${v}_ptr`, lenLocal: `${v}_len` }];
  }

  // ── VAR instanceof Error ? VAR.message : String(VAR) — caught exception is always a string
  const instanceofTernaryMatch = token.match(
    /^(\w+)\s+instanceof\s+Error\s*\?\s*\1\.message\s*:\s*String\s*\(\s*\1\s*\)$/,
  );
  if (instanceofTernaryMatch && locals.get(instanceofTernaryMatch[1]) === "string") {
    const v = instanceofTernaryMatch[1];
    return [{ kind: "strvar", ptrLocal: `${v}_ptr`, lenLocal: `${v}_len` }];
  }

  // ── Phase 49: str.at(n) — character at index, supporting negative indices
  const strAtConsoleM = token.match(/^(\w+)\.at\s*\((.+)\)$/);
  if (
    strAtConsoleM && locals.get(strAtConsoleM[1]) === "string" &&
    parenDepthNeverNegative(strAtConsoleM[2])
  ) {
    const strName = strAtConsoleM[1];
    const rawN = strAtConsoleM[2].trim();
    const nNum = /^-?\d+$/.test(rawN) ? parseInt(rawN, 10) : null;
    const nWat = nNum !== null
      ? "(i32.const " + nNum + ")"
      : exprToWat(rawN, locals, "i32", funcLookup, allocString, arrayLookup, structLookup, globals);
    const ptrW = "(local.get $" + strName + "_ptr)";
    const lenW = "(local.get $" + strName + "_len)";
    const normIdx = "(select " + nWat + " (i32.add " + lenW + " " + nWat + ") (i32.ge_s " + nWat +
      " (i32.const 0)))";
    const ptrWat = "(i32.add " + ptrW + " " + normIdx + ")";
    return [{ kind: "strexpr" as const, ptrWat, lenWat: "(i32.const 1)" }];
  }

  // ── String literal method: "TEXT".toLowerCase() / "TEXT".toUpperCase() → pre-computed literal
  const strLitMethodMatch = token.match(/^(["'])(.*?)\1\.(toLowerCase|toUpperCase)\s*\(\s*\)$/);
  if (strLitMethodMatch) {
    const str = strLitMethodMatch[2];
    const text = strLitMethodMatch[3] === "toLowerCase" ? str.toLowerCase() : str.toUpperCase();
    return [{ kind: "literal", text }];
  }

  // ── Phase 28: arr.join(sep) — write joined string to gather scratch
  const joinMatch = token.match(
    /^(\w+)\.join\(("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)?\)$/,
  );
  if (joinMatch && allocString) {
    const arrName = joinMatch[1];
    const arrInfo = arrayLookup?.(arrName);
    if (arrInfo?.dynamic) {
      const sepRaw = joinMatch[2];
      const sep = sepRaw ? sepRaw.slice(1, -1) : ",";
      const [sepPtr, sepLen] = allocString(sep);
      const arrWat = arrInfo.ptr === -1 ? `(local.get $${arrName})` : `(local.get $${arrName})`;
      return [{ kind: "joinarr", arrWat, sepPtr, sepLen, elemType: arrInfo.elemType }];
    }
  }

  // ── Phase 35: typeof x → compile-time type-name string literal
  const typeofPSAMatch = token.match(/^typeof\s+(\w+)$/);
  if (typeofPSAMatch) {
    const vn = typeofPSAMatch[1]!;
    const t = locals.get(vn) ?? globals?.get(vn);
    let typeStr: string;
    if (t === "string") typeStr = "string";
    else if (t === "bool") typeStr = "boolean";
    else if (t === "f64" || t === "f32") typeStr = "number";
    else if (t === "i64") typeStr = "bigint";
    else if (t === "i32") {
      const arrInfo = arrayLookup?.(vn);
      typeStr = arrInfo ? "object" : "number";
    } else typeStr = "undefined";
    return [{ kind: "literal", text: typeStr }];
  }

  // ── Global isNaN(x) — must precede callMatch to avoid (call $isNaN ...)
  {
    const gIsNaNM = token.match(/^isNaN\s*\((.+)\)$/);
    if (gIsNaNM && parenDepthNeverNegative(gIsNaNM[1])) {
      const aW = exprToWat(
        gIsNaNM[1].trim(),
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      return [{ kind: "boolexpr", wat: `(f64.ne ${aW} ${aW})` }];
    }
  }

  // ── Function call: name(arg, arg, ...)
  // Look up the callee's parameter types so each argument gets the correct const kind.
  const callMatch = token.match(/^(\w+)\s*\((.*)?\)$/);
  if (callMatch) {
    const callee = callMatch[1];
    const rawArgs = callMatch[2]?.trim() ?? "";
    const argList = rawArgs ? splitTopLevelArgs(rawArgs) : [];
    // Phase 5g: closure-typed variable dispatch via trampoline (call_indirect)
    const closureSig = closureVarLookup?.(callee);
    if (closureSig) {
      const watArgsList = argList.map((a, idx) =>
        exprToWat(
          a.trim(),
          locals,
          (closureSig.params[idx] ?? "i32") as string,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        )
      );
      const argsPart = watArgsList.length > 0 ? ` ${watArgsList.join(" ")}` : "";
      const wat =
        `(call_indirect (type ${closureSig.funcType}) (local.get $${callee})${argsPart} (i32.load (local.get $${callee})))`;
      const result = closureSig.result;
      if (result === "f64" || result === "f32") return [{ kind: "f64expr", wat }];
      if (result === "i64") return [{ kind: "i64expr", wat }];
      if (result === "bool") return [{ kind: "boolexpr", wat }];
      if (result === "string") return [{ kind: "strcall" as const, callWat: wat }];
      return [{ kind: "i32expr", wat }];
    }
    const sig = funcLookup?.(callee);
    // Phase 33 guard: struct args must be layout-compatible with the params they bind to
    _structArgLayoutCheck?.(callee, argList);
    // String params expand to two stack values (ptr + len); use allocString if available.
    const watArgsList = argList.flatMap((a, i) => {
      const ptype = sig?.params[i]?.type ?? "i32";
      if (ptype === "string") {
        return [
          exprToWat(
            a.trim(),
            locals,
            "string",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          ),
        ];
      }
      // Inline struct literal arg: { key: val } for a struct param
      const aTrimmed = a.trim();
      if (
        ptype === "i32" && aTrimmed.startsWith("{") && _structLiteralAlloc &&
        sig?.params[i]?.structType
      ) {
        const structName = sig.params[i].structType!;
        const braceContent = aTrimmed.slice(1, aTrimmed.lastIndexOf("}")).trim();
        const initFields: Record<string, string> = {};
        const pairs = splitTopLevelArgs(braceContent);
        for (const pair of pairs) {
          const ci = pair.indexOf(":");
          const key = ci !== -1 ? pair.slice(0, ci).trim() : pair.trim();
          const val = ci !== -1 ? pair.slice(ci + 1).trim() : key;
          if (key) initFields[key] = val;
        }
        return [`(i32.const ${_structLiteralAlloc(structName, initFields)})`];
      }
      return [
        exprToWat(
          a.trim(),
          locals,
          ptype,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        ),
      ];
    });
    // Fill in default values for omitted trailing params
    if (sig) {
      const baseParamCount = sig.params.length - (sig.closureCaptures?.length ?? 0);
      for (let i = argList.length; i < baseParamCount; i++) {
        const param = sig.params[i];
        if (param.defaultValue !== undefined) {
          watArgsList.push(
            exprToWat(
              param.defaultValue,
              locals,
              param.type,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            ),
          );
        }
      }
    }
    const wat = watArgsList.length > 0
      ? `(call $${callee} ${watArgsList.join(" ")})`
      : `(call $${callee})`;
    // Return type of the call: check resultTsName first (preserves array/interface annotation),
    // then fall back to the normalized WatType.
    const retTsName = sig?.resultTsName;
    if (retTsName && /\[\]$/.test(retTsName)) {
      const elemType = retTsName.replace(/\[\]$/, "");
      return [{ kind: "arrptr" as const, wat, elemType }];
    }
    const retType = (sig as { result?: string } | undefined)?.result;
    if (retType === "bool") return [{ kind: "boolexpr", wat }];
    if (retType === "i64") return [{ kind: "i64expr", wat }];
    if (retType === "f64" || retType === "f32") return [{ kind: "f64expr", wat }];
    if (retType === "string") return [{ kind: "strcall" as const, callWat: wat }];
    return [{ kind: "i32expr", wat }];
  }

  // ── Array element access: arr[idx]
  // Guard the greedy index capture: `arr[0] + arr[1]` would match as index `0] + arr[1` (unbalanced
  // brackets), and the branches below would emit a single mangled access — dropping the `+ arr[1]`.
  // Nullify on an unbalanced index so the whole expression falls through to the binary-op-aware
  // exprToWat routing below (which handles array-element arithmetic correctly).
  // Bug fix 2026-06-30: 2D dynamic-array element `arr[i][j]` directly in console.log. The 1D bracket
  // regex below rejects it (its index `i][j` fails parenDepthNeverNegative), so it used to fall to the
  // terminal `(i32.const 0)` stub. Load the row pointer (outer stores i32 row ptrs, shift=2), then the
  // element from the row (elemType shift/loadOp).
  const twoDMatch = token.match(/^(\w+)\[([^\]]+)\]\[([^\]]+)\]$/);
  if (twoDMatch && arrayLookup) {
    const a2 = arrayLookup(twoDMatch[1]);
    if (a2 && a2.is2D) {
      const base = a2.isGlobal
        ? `(global.get $${twoDMatch[1]})`
        : (a2.ptr === -1 || a2.ptr === -2 || a2.dynamic)
        ? `(local.get $${twoDMatch[1]})`
        : `(i32.const ${a2.ptr})`;
      const rowIdx = exprToWat(
        twoDMatch[2],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const colIdx = exprToWat(
        twoDMatch[3],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const rowPtr =
        `(i32.load (i32.add (i32.add ${base} (i32.const 8)) (i32.shl ${rowIdx} (i32.const 2))))`;
      const eShift = (a2.elemType === "f64" || a2.elemType === "i64") ? 3 : 2;
      const eLoad = a2.elemType === "f64"
        ? "f64.load"
        : a2.elemType === "i64"
        ? "i64.load"
        : "i32.load";
      const wat =
        `(${eLoad} (i32.add (i32.add ${rowPtr} (i32.const 8)) (i32.shl ${colIdx} (i32.const ${eShift}))))`;
      const kind = a2.elemType === "f64" || a2.elemType === "f32"
        ? "f64expr" as const
        : a2.elemType === "i64"
        ? "i64expr" as const
        : "i32expr" as const;
      return [{ kind, wat }];
    }
  }
  let bracketMatch = token.match(/^(\w+)\[(.+)\]$/);
  if (bracketMatch && !parenDepthNeverNegative(bracketMatch[2])) bracketMatch = null;
  // Phase 23: tuple element access t[N] where N is a numeric index → struct field _N
  if (bracketMatch && structLookup && /^\d+$/.test(bracketMatch[2])) {
    const fi = structLookup(bracketMatch[1], `_${bracketMatch[2]}`);
    if (fi) {
      const kind = fi.type === "f64" || fi.type === "f32"
        ? "f64expr" as const
        : fi.type === "i64"
        ? "i64expr" as const
        : "i32expr" as const;
      return [{ kind, wat: fi.watLoad }];
    }
  }
  if (bracketMatch && arrayLookup) {
    const arrInfo = arrayLookup(bracketMatch[1]);
    if (arrInfo) {
      // String array element access: arr[idx] — load ptr+len pair (8-byte elements)
      if ((arrInfo as { isStringArr?: boolean }).isStringArr || arrInfo.elemType === "string") {
        let idxWat = exprToWat(
          bracketMatch[2],
          locals,
          "i32",
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        );
        if (/^\w+$/.test(bracketMatch[2].trim())) {
          const idxT = locals.get(bracketMatch[2].trim()) ?? globals?.get(bracketMatch[2].trim());
          if (idxT === "f64" || idxT === "f32") idxWat = `(i32.trunc_f64_s ${idxWat})`;
        }
        const getOp = arrInfo.isGlobal
          ? `(global.get $${bracketMatch[1]})`
          : `(local.get $${bracketMatch[1]})`;
        const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
          ? getOp
          : `(i32.const ${arrInfo.ptr})`;
        const elemAddrWat =
          `(i32.add (i32.add ${baseWat} (i32.const 8)) (i32.shl ${idxWat} (i32.const 3)))`;
        return [{
          kind: "strexpr" as const,
          ptrWat: `(i32.load ${elemAddrWat})`,
          lenWat: `(i32.load offset=4 ${elemAddrWat})`,
        }];
      }
      // Phase 31: respect custom shift/loadOp for sub-word TypedArrays (Uint8Array, Int16Array, etc.)
      const loadOp = arrInfo.customLoadOp ??
        (arrInfo.elemType === "f64"
          ? "f64.load"
          : arrInfo.elemType === "i64"
          ? "i64.load"
          : "i32.load");
      const shift = arrInfo.shift !== undefined
        ? arrInfo.shift
        : (arrInfo.elemType === "f64" || arrInfo.elemType === "i64")
        ? 3
        : 2;
      let idxWat = exprToWat(
        bracketMatch[2],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      if (/^\w+$/.test(bracketMatch[2].trim())) {
        const idxT = locals.get(bracketMatch[2].trim()) ?? globals?.get(bracketMatch[2].trim());
        if (idxT === "f64" || idxT === "f32") idxWat = `(i32.trunc_f64_s ${idxWat})`;
      }
      // All arrays use an 8-byte [length, capacity] header; data starts at +8.
      const getOp2 = arrInfo.isGlobal
        ? `(global.get $${bracketMatch[1]})`
        : `(local.get $${bracketMatch[1]})`;
      const baseWat = (arrInfo.ptr === -1 || arrInfo.dynamic)
        ? getOp2
        : `(i32.const ${arrInfo.ptr})`;
      const dataBase = `(i32.add ${baseWat} (i32.const 8))`;
      const addrWat = shift === 0
        ? `(i32.add ${dataBase} ${idxWat})`
        : `(i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift})))`;
      const wat = `(${loadOp} ${addrWat})`;
      const kind = arrInfo.elemType === "f64"
        ? "f64expr" as const
        : arrInfo.elemType === "i64"
        ? "i64expr" as const
        : "i32expr" as const;
      return [{ kind, wat }];
    }
  }
  // Phase 12/5h: fallback — i32 local holding a dynamic i32[] array pointer (captured or method-returned)
  if (bracketMatch && locals.get(bracketMatch[1]) === "i32") {
    let idxWat = exprToWat(
      bracketMatch[2],
      locals,
      "i32",
      funcLookup,
      allocString,
      arrayLookup,
      structLookup,
      globals,
    );
    if (/^\w+$/.test(bracketMatch[2].trim())) {
      const idxT = locals.get(bracketMatch[2].trim()) ?? globals?.get(bracketMatch[2].trim());
      if (idxT === "f64" || idxT === "f32") idxWat = `(i32.trunc_f64_s ${idxWat})`;
    }
    return [{
      kind: "i32expr" as const,
      wat: `(i32.load (i32.add (i32.add (local.get $${
        bracketMatch[1]
      }) (i32.const 8)) (i32.shl ${idxWat} (i32.const 2))))`,
    }];
  }

  // ── Array .length: dynamic → runtime i32 load from header; static → compile-time constant
  const dotLenMatch = token.match(/^(\w+)\.length$/);
  if (dotLenMatch) {
    const lenName = dotLenMatch[1];
    const arrInfo = arrayLookup?.(lenName);
    if (arrInfo) {
      const getOp = arrInfo.isGlobal ? `(global.get $${lenName})` : `(local.get $${lenName})`;
      const wat = arrInfo.dynamic ? `(i32.load ${getOp})` : `(i32.const ${arrInfo.length})`;
      return [{ kind: "i32expr", wat }];
    }
    // String .length (UTF-8 byte length): local string, module string const, or string global.
    if (locals.get(lenName) === "string") {
      return [{ kind: "i32expr", wat: `(local.get $${lenName}_len)` }];
    }
    const gt = globals?.get(lenName);
    if (gt?.startsWith("string:")) {
      return [{ kind: "i32expr", wat: `(i32.const ${Number(gt.split(":")[2])})` }];
    }
    if (gt?.startsWith("strglobal:")) {
      const gn = gt.slice("strglobal:".length);
      return [{ kind: "i32expr", wat: `(global.get $${gn}_len)` }];
    }
    // Phase 12: i32 local holding a dynamic array pointer — load length from header
    if (locals.get(lenName) === "i32") {
      return [{ kind: "i32expr", wat: `(i32.load (local.get $${lenName}))` }];
    }
  }

  // ── Phase 51: x instanceof ClassName → boolexpr via wasic's emitExpr (owns the tag tables)
  if (_instanceofResolver && /^\w+\s+instanceof\s+\w+$/.test(token)) {
    const iw = _instanceofResolver(token, locals);
    if (iw !== undefined) return [{ kind: "boolexpr", wat: iw }];
  }

  // ── Phase 25: nullish coalescing `a ?? b` → delegate to wasic's emitExpr, which owns the
  // nullable-variable tables. MUST run before the boolexpr and ternary blocks below: the
  // `_hasTernary` probe matches the leading `?` of `??`, so `val ?? -1` would otherwise be
  // mis-parsed as a ternary and fall through to the comment-stub fallback.
  if (_nullishResolver && findTopLevelOp(token, "??") !== -1) {
    const nw = _nullishResolver(token, locals);
    if (nw !== undefined) {
      return [{
        kind: nw.type === "f64" || nw.type === "f32" ? "f64expr" : "i32expr",
        wat: nw.wat,
      }];
    }
  }

  // ── Boolean expression: &&, ||, !, comparisons → boolexpr (prints "true"/"false")
  // Must run BEFORE Number.*/Math.* so that "Number.MAX_SAFE_INTEGER > 1e16" is caught here,
  // not misidentified as an f64 constant by the Number.* handler.
  // BUT: if there's a top-level ternary ? the whole expr is a ternary, not a bool.
  const _hasTernary = findTopLevelOp(token, "?") !== -1;
  if (
    !_hasTernary && (token.startsWith("!") ||
      findTopLevelOp(token, "&&") !== -1 ||
      findTopLevelOp(token, "||") !== -1 ||
      /===|!==/.test(token) ||
      // LOOSE equality belongs here too. `wasic.ts` handles `a == b` / `a != b` everywhere else
      // (`if (a == b)`, `const c: boolean = a != b`), but this list omitted them, so
      // `console.log(a == b)` was not recognised as a boolean, fell through to the numeric path,
      // and emitted an i32 comparison where an f64 was expected. wasic reported SUCCESS and wrote
      // a module that would not instantiate: "expected type f64, found f64.eq of type i32".
      // Exactly the parallel-code-path divergence cmem/design-decisions.md warns about.
      // (`==` also matches inside `===`, which is harmless — both classify as boolexpr.)
      findTopLevelOp(token, "==") !== -1 ||
      findTopLevelOp(token, "!=") !== -1 ||
      findTopLevelOp(token, ">=") !== -1 ||
      findTopLevelOp(token, "<=") !== -1 ||
      findTopLevelOp(token, ">") !== -1 ||
      findTopLevelOp(token, "<") !== -1)
  ) {
    return [{
      kind: "boolexpr",
      wat: exprToWat(
        token,
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      ),
    }];
  }

  // ── Phase 48: Number.* — constants produce f64, predicates produce boolexpr
  if (token.startsWith("Number.")) {
    const numPredCallM = token.match(/^Number\.(isNaN|isFinite|isInteger)\(/);
    if (numPredCallM) {
      return [{
        kind: "boolexpr",
        wat: exprToWat(
          token,
          locals,
          "i32",
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        ),
      }];
    }
    // Constants (Number.NaN, Number.POSITIVE_INFINITY, etc.) → f64
    return [{
      kind: "f64expr",
      wat: exprToWat(
        token,
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      ),
    }];
  }

  // ── Math.* — route to correct kind based on return type
  if (token.startsWith("Math.")) {
    const mathCallM = token.match(/^Math\.(\w+)\(/);
    const mathFn = mathCallM?.[1];
    if (mathFn === "clz32" || mathFn === "imul") {
      return [{
        kind: "i32expr",
        wat: exprToWat(
          token,
          locals,
          "i32",
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        ),
      }];
    }
    // All other Math functions produce f64
    return [{
      kind: "f64expr",
      wat: exprToWat(
        token,
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      ),
    }];
  }

  // ── String ternary: cond ? strExpr : strExpr → strexpr using select for ptr and len
  if (_hasTernary) {
    const ternQIdx = findTopLevelOp(token, "?");
    if (ternQIdx !== -1) {
      const afterQ = token.slice(ternQIdx + 1);
      const ternCIdx = findTopLevelOp(afterQ, ":");
      if (ternCIdx !== -1) {
        const thenPart = afterQ.slice(0, ternCIdx).trim();
        const elsePart = afterQ.slice(ternCIdx + 1).trim();
        if (
          looksLikeString(thenPart, locals, arrayLookup) ||
          looksLikeString(elsePart, locals, arrayLookup)
        ) {
          const condWat = exprToWat(
            token.slice(0, ternQIdx).trim(),
            locals,
            "i32",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          );
          // Recursively parse branches to get strvar/strexpr segments for ptr+len
          const getStrPtrLen = (part: string): [string, string] => {
            const segs = parseSingleArg(
              part,
              locals,
              funcLookup,
              allocString,
              enumLookup,
              arrayLookup,
              structLookup,
              dotCallLookup,
              globals,
              enumStringLookup,
              closureVarLookup,
            );
            const s = segs[0];
            if (!s) return ["(i32.const 0)", "(i32.const 0)"];
            if (s.kind === "strvar") {
              return [`(local.get $${s.ptrLocal})`, `(local.get $${s.lenLocal})`];
            }
            if (s.kind === "strexpr") return [s.ptrWat, s.lenWat];
            if (s.kind === "literal" && allocString) {
              const [p, l] = allocString(s.text);
              return [`(i32.const ${p})`, `(i32.const ${l})`];
            }
            // Any other string-valued branch (slice / method / call that parseSingleArg didn't
            // surface as a strvar/strexpr): resolve via emitStringPtrLen rather than emit empty.
            const r = _stringExprResolver?.(part.trim(), locals);
            if (r) return [r.ptrWat, r.lenWat];
            return ["(i32.const 0)", "(i32.const 0)"];
          };
          const [thenPtr, thenLen] = getStrPtrLen(thenPart);
          const [elsePtr, elseLen] = getStrPtrLen(elsePart);
          return [{
            kind: "strexpr" as const,
            ptrWat: `(select ${thenPtr} ${elsePtr} ${condWat})`,
            lenWat: `(select ${thenLen} ${elseLen} ${condWat})`,
          }];
        }
      }
    }
  }

  // ── Arithmetic / numeric expression
  // Phase 42: if expression starts with a struct field access, infer type from the field.
  // This handles cases like `a.x + b.x` where `a` is an i32 pointer but `a.x` is f64.
  const leadDotM = token.match(/^(\w+)\.(\w+)\b/);
  if (leadDotM && structLookup) {
    const leadFi = structLookup(leadDotM[1], leadDotM[2]);
    if (leadFi) {
      if (leadFi.type === "f64" || leadFi.type === "f32") {
        return [{
          kind: "f64expr",
          wat: exprToWat(
            token,
            locals,
            "f64",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          ),
        }];
      }
      if (leadFi.type === "i64") {
        return [{
          kind: "i64expr",
          wat: exprToWat(
            token,
            locals,
            "i64",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          ),
        }];
      }
    }
  }
  // Infer i64 / i32 / f64 from the leading identifier's declared type. For a compound expression
  // led by an ARRAY variable (e.g. `arr[0] + arr[1]`), `locals.get(arr)` is the i32 POINTER type, not
  // the element type — so consult arrayLookup and route by the ELEMENT type (an f64[] element sum is
  // an f64 expression, not i32). Plain (non-array) leads keep their declared local type.
  const leadId = token.match(/^(\w+)/)?.[1];
  const leadArr = leadId ? arrayLookup?.(leadId) : undefined;
  // A lead atom may be a function-local OR a module GLOBAL (e.g. `const a: i32 = 1` at module scope
  // → `console.log(a + b)`); consult both, else `a + b` of i32 globals would default to f64.add.
  let leadType = leadArr
    ? leadArr.elemType
    : (leadId ? (locals.get(leadId) ?? globals?.get(leadId)) : undefined);
  // A leading INTEGER LITERAL or a leading PARENTHESIS has no declared type, so the expression was
  // classified f64 while its operands stayed i32 — `console.log("x:", 1 + n)` and
  // `console.log("x:", (n + 0) * 5)` emitted an f64 segment over i32 arithmetic and failed to
  // instantiate, even though `n + 1` worked. Take the type from the first TYPED atom instead. A
  // leading FLOAT literal (`1.5 + n`) genuinely means f64, so it is skipped. String/bool/ternary
  // forms are all handled by earlier branches, so only numeric expressions reach here.
  if (
    leadType === undefined &&
    (/^-?\d+\s*[-+*/%]/.test(token) || (token.startsWith("(") && /[-+*/%]/.test(token)))
  ) {
    for (const m of token.matchAll(/\b([A-Za-z_]\w*)\b/g)) {
      const a = arrayLookup?.(m[1]);
      const t = a ? a.elemType : (locals.get(m[1]) ?? globals?.get(m[1]));
      if (t !== undefined) {
        leadType = t;
        break;
      }
    }
  }
  if (leadType === "i64") {
    return [{
      kind: "i64expr",
      wat: exprToWat(
        token,
        locals,
        "i64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      ),
    }];
  }
  if (leadType === "i32" || leadType === "bool") {
    return [{
      kind: "i32expr",
      wat: exprToWat(
        token,
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      ),
    }];
  }
  return [{
    kind: "f64expr",
    wat: exprToWat(
      token,
      locals,
      "f64",
      funcLookup,
      allocString,
      arrayLookup,
      structLookup,
      globals,
    ),
  }];
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
  globals?: Map<string, string>,
  enumStringLookup?: (key: string) => string | undefined,
  closureVarLookup?: ClosureVarLookup,
): LogSegment[] {
  const segments: LogSegment[] = [];
  let i = 0;
  let textStart = 0;

  while (i < body.length) {
    if (body[i] === "$" && body[i + 1] === "{") {
      // Flush preceding text (unescape escape sequences in the static text)
      if (i > textStart) {
        segments.push({ kind: "literal", text: unescapeString(body.slice(textStart, i)) });
      }
      // Find closing }
      let depth = 1;
      let j = i + 2;
      while (j < body.length && depth > 0) {
        if (body[j] === "{") depth++;
        else if (body[j] === "}") depth--;
        j++;
      }
      const expr = body.slice(i + 2, j - 1).trim();
      segments.push(
        ...parseSingleArg(
          expr,
          locals,
          funcLookup,
          allocString,
          enumLookup,
          arrayLookup,
          structLookup,
          dotCallLookup,
          globals,
          enumStringLookup,
          closureVarLookup,
        ),
      );
      i = j;
      textStart = j;
    } else {
      i++;
    }
  }
  if (textStart < body.length) {
    segments.push({ kind: "literal", text: unescapeString(body.slice(textStart)) });
  }
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
  structLookup?: StructFieldLookup,
  globals?: Map<string, string>,
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
    return `(${
      expectedType === "i32" || expectedType === "i64" ? "f64" : expectedType
    }.const ${expr})`;
  }

  // Integer literal — emit const for the expected type
  if (/^-?\d+$/.test(expr)) {
    const t = (expectedType === "f32" || expectedType === "f64")
      ? expectedType
      : expectedType === "i64"
      ? "i64"
      : "i32";
    return `(${t}.const ${expr})`;
  }

  // Scientific notation literal (e.g. 1e16, 3.5e-4, -1e10) — always f64
  if (/^-?\d+(\.\d+)?[eE][+-]?\d+$/.test(expr)) {
    return `(f64.const ${expr})`;
  }

  // Special constants — must be checked before the identifier fallback
  const CONSTANTS: Record<string, string> = {
    NaN: "(f64.const nan)",
    Infinity: "(f64.const inf)",
    true: "(i32.const 1)",
    false: "(i32.const 0)",
    null: "(i32.const 0)",
    undefined: "(i32.const 0)",
  };
  if (Object.prototype.hasOwnProperty.call(CONSTANTS, expr)) return CONSTANTS[expr];

  // Bigint literal: 5n → (i64.const 5)  (must come before identifier check: /^\w+$/ matches "5n")
  if (/^-?\d+n$/.test(expr)) return `(i64.const ${expr.slice(0, -1)})`;

  // Inline string array literal: ["a", "b"] → allocate in data section, return i32 pointer
  if (expr.startsWith("[") && expr.endsWith("]") && _strArrAlloc) {
    const inner = expr.slice(1, -1).trim();
    const elems = inner ? splitTopLevelArgs(inner) : [];
    const allStrLits = elems.length > 0 && elems.every((e) => {
      const t = e.trim();
      return (t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"));
    });
    if (allStrLits) {
      return `(i32.const ${_strArrAlloc(elems)})`;
    }
  }

  // Array .length: dynamic → runtime i32 load from header; static → compile-time constant
  const dotLenM = expr.match(/^(\w+)\.length$/);
  if (dotLenM) {
    const ai = arrayLookup?.(dotLenM[1]);
    if (ai) {
      const getOp2 = ai.isGlobal ? `(global.get $${dotLenM[1]})` : `(local.get $${dotLenM[1]})`;
      return ai.dynamic ? `(i32.load ${getOp2})` : `(i32.const ${ai.length})`;
    }
    // String .length (UTF-8 byte length): local string, module string const, or string global.
    // Without this, a string `.length` used as a comparison/arithmetic operand (it reaches exprToWat,
    // not parseSingleArg) fell through to the terminal stub → 0.
    if (locals.get(dotLenM[1]) === "string") return `(local.get $${dotLenM[1]}_len)`;
    const glt = globals?.get(dotLenM[1]);
    if (glt?.startsWith("string:")) return `(i32.const ${Number(glt.split(":")[2])})`;
    if (glt?.startsWith("strglobal:")) {
      return `(global.get $${glt.slice("strglobal:".length)}_len)`;
    }
    // Phase 12: i32 local holding a dynamic array pointer
    if (locals.get(dotLenM[1]) === "i32") return `(i32.load (local.get $${dotLenM[1]}))`;
  }

  // `<stringExpr>.length` where the receiver is a non-trivial string expression — a string-returning
  // call `getName().length`, a slice `s.slice(0,3).length`, a method result, etc. Resolve the
  // receiver via the string-expr resolver and take the length word (run the ptr side so it captures
  // len into $__str_op_len, drop the ptr, then read len). Only fires when the receiver resolves to a
  // string; numeric/other receivers fall through.
  const exprLenM = expr.match(/^(.+)\.length$/);
  if (exprLenM && !/^\w+$/.test(exprLenM[1].trim())) {
    const r = _stringExprResolver?.(exprLenM[1].trim(), locals);
    if (r) return `(block (result i32) (drop ${r.ptrWat}) ${r.lenWat})`;
  }

  // Bug fix 2026-06-30: 2D dynamic-array element `arr[i][j]` as an OPERAND (e.g. `arr[0][0] + arr[0][1]`).
  // The recursive per-operand exprToWat call lands here; without this it fell to the terminal 0 stub.
  const twoDM = expr.match(/^(\w+)\[([^\]]+)\]\[([^\]]+)\]$/);
  if (twoDM && arrayLookup) {
    const a2 = arrayLookup(twoDM[1]);
    if (a2 && a2.is2D) {
      const base = a2.isGlobal
        ? `(global.get $${twoDM[1]})`
        : (a2.ptr === -1 || a2.ptr === -2 || a2.dynamic)
        ? `(local.get $${twoDM[1]})`
        : `(i32.const ${a2.ptr})`;
      const rowIdx = exprToWat(
        twoDM[2],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const colIdx = exprToWat(
        twoDM[3],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const rowPtr =
        `(i32.load (i32.add (i32.add ${base} (i32.const 8)) (i32.shl ${rowIdx} (i32.const 2))))`;
      const eShift = (a2.elemType === "f64" || a2.elemType === "i64") ? 3 : 2;
      const eLoad = a2.elemType === "f64"
        ? "f64.load"
        : a2.elemType === "i64"
        ? "i64.load"
        : "i32.load";
      return `(${eLoad} (i32.add (i32.add ${rowPtr} (i32.const 8)) (i32.shl ${colIdx} (i32.const ${eShift}))))`;
    }
  }
  // Array element read: arr[idx]. Guard the greedy index capture so `arr[0] + arr[1]` (index would
  // capture `0] + arr[1`) falls through to the binary-op loop below instead of emitting one mangled
  // access (mirrors emitExpr in wasic.ts, which already guards this).
  let bracketM = expr.match(/^(\w+)\[(.+)\]$/);
  if (bracketM && !parenDepthNeverNegative(bracketM[2])) bracketM = null;
  // Phase 23: tuple element access t[N] → struct field _N
  if (bracketM && structLookup && /^\d+$/.test(bracketM[2])) {
    const fi = structLookup(bracketM[1], `_${bracketM[2]}`);
    if (fi) return fi.watLoad;
  }
  if (bracketM && arrayLookup) {
    const ai = arrayLookup(bracketM[1]);
    if (ai) {
      // String arrays: each element is 8 bytes [ptr i32, len i32]; load the ptr here.
      if (ai.isStringArr || ai.elemType === "string") {
        const base = (ai.ptr === -1 || ai.dynamic)
          ? `(local.get $${bracketM[1]})`
          : `(i32.const ${ai.ptr})`;
        const idxW = exprToWat(
          bracketM[2],
          locals,
          "i32",
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        );
        const addr = `(i32.add (i32.add ${base} (i32.const 8)) (i32.shl ${idxW} (i32.const 3)))`;
        return `(i32.load ${addr})`;
      }
      // Phase 31: respect custom shift/loadOp for sub-word TypedArrays
      const loadOp = ai.customLoadOp ??
        (ai.elemType === "f64" ? "f64.load" : ai.elemType === "i64" ? "i64.load" : "i32.load");
      const shift = ai.shift !== undefined
        ? ai.shift
        : (ai.elemType === "f64" || ai.elemType === "i64")
        ? 3
        : 2;
      let idxWat = exprToWat(
        bracketM[2],
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      // If index is an f64 local/global, wrap with trunc to get i32
      if (/^\w+$/.test(bracketM[2].trim())) {
        const idxT = locals.get(bracketM[2].trim()) ?? globals?.get(bracketM[2].trim());
        if (idxT === "f64" || idxT === "f32") idxWat = `(i32.trunc_f64_s ${idxWat})`;
      }
      // All arrays use an 8-byte [length, capacity] header; data starts at ptr+8.
      const baseWat = (ai.ptr === -1 || ai.dynamic)
        ? `(local.get $${bracketM[1]})`
        : `(i32.const ${ai.ptr})`;
      const dataBase = `(i32.add ${baseWat} (i32.const 8))`;
      const addrWat = shift === 0
        ? `(i32.add ${dataBase} ${idxWat})`
        : `(i32.add ${dataBase} (i32.shl ${idxWat} (i32.const ${shift})))`;
      return `(${loadOp} ${addrWat})`;
    }
  }

  // Struct field access: p.field
  const sfDotM = expr.match(/^(\w+)\.(\w+)$/);
  if (sfDotM && structLookup) {
    const fi = structLookup(sfDotM[1], sfDotM[2]);
    if (fi) return fi.watLoad;
  }

  // Phase 42: three-part chained struct field access: a.b.c
  const sfChainedDotM = expr.match(/^(\w+)\.(\w+)\.(\w+)$/);
  if (sfChainedDotM && structLookup) {
    const fi = structLookup(`${sfChainedDotM[1]}.${sfChainedDotM[2]}`, sfChainedDotM[3]);
    if (fi) return fi.watLoad;
  }

  // Global isNaN(x) → f64.ne x x
  {
    const globalIsNaNEWat = expr.match(/^isNaN\s*\((.+)\)$/);
    if (globalIsNaNEWat && parenDepthNeverNegative(globalIsNaNEWat[1])) {
      const argWat = exprToWat(
        globalIsNaNEWat[1].trim(),
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      return `(f64.ne ${argWat} ${argWat})`;
    }
  }

  // Phase 48: Number.* constants and predicates
  if (expr.startsWith("Number.")) {
    const NUMBER_CONSTS: Record<string, string> = {
      NaN: "nan",
      POSITIVE_INFINITY: "inf",
      NEGATIVE_INFINITY: "-inf",
      EPSILON: "2.220446049250313e-16",
      MAX_SAFE_INTEGER: "9007199254740991",
      MIN_SAFE_INTEGER: "-9007199254740991",
      MAX_VALUE: "1.7976931348623157e+308",
      MIN_VALUE: "5e-324",
    };
    const numConstM = expr.match(/^Number\.(\w+)$/);
    if (numConstM && NUMBER_CONSTS[numConstM[1]] !== undefined) {
      return `(f64.const ${NUMBER_CONSTS[numConstM[1]]})`;
    }
    const numPredM = expr.match(/^Number\.(isNaN|isFinite|isInteger)\(([\s\S]*)\)$/);
    let _numPredCLOk = false;
    if (numPredM) {
      let _d = 0;
      _numPredCLOk = true;
      for (const _c of numPredM[2]) {
        if (_c === "(") _d++;
        else if (_c === ")") {
          if (_d === 0) {
            _numPredCLOk = false;
            break;
          }
          _d--;
        }
      }
    }
    if (numPredM && _numPredCLOk) {
      const predFn = numPredM[1];
      const argExpr = numPredM[2].trim();
      const argWat = exprToWat(
        argExpr,
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      if (predFn === "isNaN") return `(f64.ne ${argWat} ${argWat})`;
      if (predFn === "isFinite") {
        return `(i32.and (f64.lt ${argWat} (f64.const inf)) (f64.gt ${argWat} (f64.const -inf)))`;
      }
      if (predFn === "isInteger") return `(f64.eq (f64.floor ${argWat}) ${argWat})`;
    }
  }

  // Math.* constants and functions
  if (expr.startsWith("Math.")) {
    const MATH_CONSTS: Record<string, string> = {
      PI: "3.141592653589793",
      E: "2.718281828459045",
      LN2: "0.6931471805599453",
      LN10: "2.302585092994046",
      LOG2E: "1.4426950408889634",
      LOG10E: "0.4342944819032518",
      SQRT2: "1.4142135623730951",
      SQRT1_2: "0.7071067811865476",
    };
    const mathConstM = expr.match(/^Math\.(\w+)$/);
    if (mathConstM && MATH_CONSTS[mathConstM[1]] !== undefined) {
      return `(f64.const ${MATH_CONSTS[mathConstM[1]]})`;
    }
    const mathCallM = expr.match(/^Math\.(\w+)\(([\s\S]*)\)$/);
    let _mathCLOk = false;
    if (mathCallM) {
      let _d = 0;
      _mathCLOk = true;
      for (const _c of mathCallM[2]) {
        if (_c === "(") _d++;
        else if (_c === ")") {
          if (_d === 0) {
            _mathCLOk = false;
            break;
          }
          _d--;
        }
      }
    }
    if (mathCallM && _mathCLOk) {
      const fn = mathCallM[1];
      const aStr = mathCallM[2].trim();
      const a = aStr ? splitTopLevelArgs(aStr) : [];
      const arg0 = exprToWat(
        a[0] ?? "0",
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const arg1 = exprToWat(
        a[1] ?? "0",
        locals,
        "f64",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      if (fn === "clz32") {
        return `(i32.clz ${
          exprToWat(
            a[0] ?? "0",
            locals,
            "i32",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          )
        })`;
      }
      if (fn === "imul") {
        return `(i32.mul ${
          exprToWat(
            a[0] ?? "0",
            locals,
            "i32",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          )
        } ${
          exprToWat(
            a[1] ?? "0",
            locals,
            "i32",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          )
        })`;
      }
      if (fn === "abs") {
        return expectedType === "i32"
          ? `(call $__i32_abs ${
            exprToWat(
              a[0] ?? "0",
              locals,
              "i32",
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            )
          })`
          : `(f64.abs ${arg0})`;
      }
      if (fn === "min") {
        return expectedType === "i32"
          ? `(call $__i32_min ${
            exprToWat(
              a[0] ?? "0",
              locals,
              "i32",
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            )
          } ${
            exprToWat(
              a[1] ?? "0",
              locals,
              "i32",
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            )
          })`
          : `(f64.min ${arg0} ${arg1})`;
      }
      if (fn === "max") {
        return expectedType === "i32"
          ? `(call $__i32_max ${
            exprToWat(
              a[0] ?? "0",
              locals,
              "i32",
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            )
          } ${
            exprToWat(
              a[1] ?? "0",
              locals,
              "i32",
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            )
          })`
          : `(f64.max ${arg0} ${arg1})`;
      }
      if (fn === "sqrt") return `(f64.sqrt ${arg0})`;
      if (fn === "floor") return `(f64.floor ${arg0})`;
      if (fn === "ceil") return `(f64.ceil ${arg0})`;
      if (fn === "trunc") return `(f64.trunc ${arg0})`;
      if (fn === "round") return `(f64.floor (f64.add ${arg0} (f64.const 0.5)))`;
      if (fn === "pow") return `(call $mathlib_pow ${arg0} ${arg1})`;
      if (fn === "sign") {
        return `(if (result f64) (f64.eq ${arg0} (f64.const 0)) (then (f64.const 0)) (else (f64.copysign (f64.const 1) ${arg0})))`;
      }
      if (fn === "hypot") {
        return `(f64.sqrt (f64.add (f64.mul ${arg0} ${arg0}) (f64.mul ${arg1} ${arg1})))`;
      }
      if (fn === "fround") return `(f64.promote_f32 (f32.demote_f64 ${arg0}))`;
      // Phase 38: extended math library functions
      const MATH38_UNARY = [
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "atan",
        "log",
        "log2",
        "log10",
        "exp",
        "expm1",
        "log1p",
        "cbrt",
        "sinh",
        "cosh",
        "tanh",
        "asinh",
        "acosh",
        "atanh",
      ];
      if (MATH38_UNARY.includes(fn)) return `(call $mathlib_${fn} ${arg0})`;
      if (fn === "atan2") return `(call $mathlib_atan2 ${arg0} ${arg1})`;
      if (fn === "random") return `(call $mathlib_random)`;
    }
  }

  // Simple identifier — check locals first, then module globals, then function table
  if (/^\w+$/.test(expr)) {
    if (locals.has(expr)) return `(local.get $${expr})`;
    if (globals?.has(expr)) return `(global.get $${expr})`;
    // Function reference passed as a callback argument
    const funcIdx = _funcTableLookup?.(expr);
    if (funcIdx !== undefined) return `(i32.const ${funcIdx})`;
  }

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
            return exprToWat(
              a.trim(),
              locals,
              ptype,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            );
          }).join(" ");
          const innerSig = funcLookup?.(`${factoryHead}__inner`);
          const captureCount = innerSig?.closureCaptures?.length ?? 0;
          const innerCallParams = innerSig
            ? innerSig.params.slice(0, innerSig.params.length - captureCount)
            : [];
          const innerArgList = parts.innerRaw ? splitTopLevelArgs(parts.innerRaw) : [];
          const innerWat = innerArgList.map((a, i) => {
            const ptype = innerCallParams[i]?.type ?? "i32";
            return exprToWat(
              a.trim(),
              locals,
              ptype,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            );
          }).join(" ");
          return `(call $${factoryHead}__trampoline (call $${factoryHead} ${outerWat}) ${innerWat})`
            .trim();
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
    // Phase 33 guard: struct args must be layout-compatible with the params they bind to
    _structArgLayoutCheck?.(callee, argList);
    // String params expand to two stack values
    const watArgsList = argList.flatMap((a, i) => {
      const ptype = sig?.params[i]?.type ?? "i32";
      const aTrimmed2 = a.trim();
      if (
        ptype === "i32" && aTrimmed2.startsWith("{") && _structLiteralAlloc &&
        sig?.params[i]?.structType
      ) {
        const structName2 = sig.params[i].structType!;
        const braceContent2 = aTrimmed2.slice(1, aTrimmed2.lastIndexOf("}")).trim();
        const initFields2: Record<string, string> = {};
        const pairs2 = splitTopLevelArgs(braceContent2);
        for (const pair of pairs2) {
          const ci = pair.indexOf(":");
          const key = ci !== -1 ? pair.slice(0, ci).trim() : pair.trim();
          const val = ci !== -1 ? pair.slice(ci + 1).trim() : key;
          if (key) initFields2[key] = val;
        }
        return [`(i32.const ${_structLiteralAlloc(structName2, initFields2)})`];
      }
      return [
        exprToWat(
          a.trim(),
          locals,
          ptype,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        ),
      ];
    });
    // Fill in default values for omitted trailing params
    if (sig) {
      const baseParamCount = sig.params.length - (sig.closureCaptures?.length ?? 0);
      for (let i = argList.length; i < baseParamCount; i++) {
        const param = sig.params[i];
        if (param.defaultValue !== undefined) {
          watArgsList.push(
            exprToWat(
              param.defaultValue,
              locals,
              param.type,
              funcLookup,
              allocString,
              arrayLookup,
              structLookup,
              globals,
            ),
          );
        }
      }
    }
    return watArgsList.length > 0
      ? `(call $${callee} ${watArgsList.join(" ")})`
      : `(call $${callee})`;
  }

  // Parenthesised sub-expression — unwrap and recurse
  if (expr.startsWith("(") && expr.endsWith(")")) {
    return exprToWat(
      expr.slice(1, -1),
      locals,
      expectedType,
      funcLookup,
      allocString,
      arrayLookup,
      structLookup,
      globals,
    );
  }

  const isFloat = expectedType === "f64" || expectedType === "f32";
  // i64 is preserved; otherwise default numeric to f64
  const numType = isFloat ? (expectedType as string) : expectedType === "i64" ? "i64" : "f64";

  // Unary ! — logical not → i32.eqz
  if (expr.startsWith("!") && !expr.startsWith("!=")) {
    return `(i32.eqz ${
      exprToWat(
        expr.slice(1).trim(),
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      )
    })`;
  }

  // Unary ~ — bitwise not → i32.xor with -1
  if (expr.startsWith("~")) {
    return `(i32.xor ${
      exprToWat(
        expr.slice(1).trim(),
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      )
    } (i32.const -1))`;
  }

  // Unary - on a non-literal (e.g. -x, -(a+b))
  if (expr.startsWith("-") && !/^-\d/.test(expr)) {
    const inner = expr.slice(1).trim();
    if (isFloat) {
      return `(${expectedType}.neg ${
        exprToWat(
          inner,
          locals,
          numType,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        )
      })`;
    }
    return `(i32.sub (i32.const 0) ${
      exprToWat(inner, locals, "i32", funcLookup, allocString, arrayLookup, structLookup, globals)
    })`;
  }

  // Ternary: cond ? then : else
  const ternQ = findTopLevelOp(expr, "?");
  if (ternQ !== -1) {
    const rest = expr.slice(ternQ + 1);
    const ternC = findTopLevelOp(rest, ":");
    if (ternC !== -1) {
      const cond = expr.slice(0, ternQ).trim();
      const thenPart = rest.slice(0, ternC).trim();
      const elsePart = rest.slice(ternC + 1).trim();
      const resType = isFloat ? expectedType : "i32";
      return `(if (result ${resType}) ${
        exprToWat(cond, locals, "i32", funcLookup, allocString, arrayLookup, structLookup, globals)
      } (then ${
        exprToWat(
          thenPart,
          locals,
          resType,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        )
      }) (else ${
        exprToWat(
          elsePart,
          locals,
          resType,
          funcLookup,
          allocString,
          arrayLookup,
          structLookup,
          globals,
        )
      }))`;
    }
  }

  // String comparison: arr[i] === "str", str === arr[i], arr[i] === arr[j]
  // Must be checked before the generic binOps loop to avoid f64.eq on i32 string pointers.
  const STR_EQ_OPS = new Set(["===", "!==", "==", "!="]);
  for (const strOp of STR_EQ_OPS) {
    const strOpIdx = findTopLevelOp(expr, strOp);
    if (strOpIdx === -1) continue;
    const strLhs = expr.slice(0, strOpIdx).trim();
    const strRhs = expr.slice(strOpIdx + strOp.length).trim();
    if (
      !looksLikeString(strLhs, locals, arrayLookup) && !looksLikeString(strRhs, locals, arrayLookup)
    ) break;
    // Helper: get ptr+len WAT for a string expression
    const getStrPL = (e: string): [string, string] => {
      if (/^\w+$/.test(e) && locals.get(e) === "string") {
        return [`(local.get $${e}_ptr)`, `(local.get $${e}_len)`];
      }
      const litM = e.match(/^["'](.*)["']$/);
      if (litM && allocString) {
        const [p, l] = allocString(litM[1]);
        return [`(i32.const ${p})`, `(i32.const ${l})`];
      }
      const bM = e.match(/^(\w+)\[([^\]]+)\]$/);
      if (bM && arrayLookup) {
        const ai = arrayLookup(bM[1]);
        if (ai && (ai.isStringArr || ai.elemType === "string")) {
          const base = (ai.ptr === -1 || ai.dynamic)
            ? `(local.get $${bM[1]})`
            : `(i32.const ${ai.ptr})`;
          const idxW = exprToWat(
            bM[2],
            locals,
            "i32",
            funcLookup,
            allocString,
            arrayLookup,
            structLookup,
            globals,
          );
          const addr = `(i32.add (i32.add ${base} (i32.const 8)) (i32.shl ${idxW} (i32.const 3)))`;
          return [`(i32.load ${addr})`, `(i32.load offset=4 ${addr})`];
        }
      }
      // Any other string-valued form (string-returning call `fn()`, struct field `obj.f`,
      // `s.slice(...)`, `s.toUpperCase()`, …): delegate to wasic's emitStringPtrLen via the resolver.
      // Without this, such operands silently compared against the empty string → wrong boolean
      // (e.g. `a === getName()` printed false when true). The resolver captures len into
      // $__str_op_len, so a console.* line with a string-equality op pre-declares that temp.
      const resolved = _stringExprResolver?.(e, locals);
      if (resolved) return [resolved.ptrWat, resolved.lenWat];
      return [`(i32.const 0)`, `(i32.const 0)`];
    };
    const [lPtr, lLen] = getStrPL(strLhs);
    const [rPtr, rLen] = getStrPL(strRhs);
    _strCmpNeeded?.();
    // $__str_cmp returns 0 when the strings are equal (strcmp semantics). `===`/`==` → 1 iff equal
    // (i32.eqz); `!==`/`!=` → 1 iff NOT equal (cmp ≠ 0). The old `!==` form was inverted — it
    // returned true for EQUAL strings.
    const cmpCall = `(call $__str_cmp ${lPtr} ${lLen} ${rPtr} ${rLen})`;
    return (strOp === "===" || strOp === "==")
      ? `(i32.eqz ${cmpCall})`
      : `(i32.ne ${cmpCall} (i32.const 0))`;
  }

  // Binary operators — ascending precedence order (lowest first = outermost grouping).
  // [op, f64-watop, i32-watop, requiresPositiveIdx, alwaysI32]
  const binOps: Array<[string, string, string, boolean, boolean]> = [
    ["||", "i32.or", "i32.or", false, true], // logical OR
    ["&&", "i32.and", "i32.and", false, true], // logical AND
    ["|", "i32.or", "i32.or", false, true], // bitwise OR
    ["^", "i32.xor", "i32.xor", false, true], // bitwise XOR
    ["&", "i32.and", "i32.and", false, true], // bitwise AND
    ["===", "f64.eq", "i32.eq", false, false],
    ["!==", "f64.ne", "i32.ne", false, false],
    ["==", "f64.eq", "i32.eq", false, false], // non-strict equality
    ["!=", "f64.ne", "i32.ne", false, false], // non-strict inequality
    ["<=", "f64.le", "i32.le_s", false, false],
    [">=", "f64.ge", "i32.ge_s", false, false],
    ["<", "f64.lt", "i32.lt_s", false, false],
    [">", "f64.gt", "i32.gt_s", false, false],
    [">>>", "i32.shr_u", "i32.shr_u", false, true], // unsigned shift
    [">>", "i32.shr_s", "i32.shr_s", false, true], // signed shift
    ["<<", "i32.shl", "i32.shl", false, true], // left shift
    ["+", "f64.add", "i32.add", false, false],
    ["-", "f64.sub", "i32.sub", true, false], // positiveIdx: skip unary minus
    ["*", "f64.mul", "i32.mul", false, false],
    ["/", "f64.div", "i32.div_s", false, false],
    ["%", "f64.rem", "i32.rem_u", false, false],
  ];
  // `*`, `/` and `%` share ONE precedence level and are LEFT-associative, but this loop splits at
  // the first operator in table order, where `*` precedes `/` and `%`. `a * b / c` therefore
  // matched `*` and produced `a * (b / c)` — right-associative and silently wrong for integer
  // division/remainder. Skip a candidate when another member of its group sits further right, so
  // the later entry splits at the RIGHTMOST operator. This mirrors the identical guard in wasic.ts's
  // emitExpr; the two binary-op loops are parallel code paths and must be fixed together.
  const MUL_GROUP = ["*", "/", "%"];
  const mulRightmost = Math.max(...MUL_GROUP.map((o) => findTopLevelOp(expr, o)));
  for (const [op, f64op, i32op, positiveIdx, alwaysI32] of binOps) {
    const idx = findTopLevelOp(expr, op);
    if (idx === -1) continue;
    if (MUL_GROUP.includes(op) && idx < mulRightmost) continue;
    if (positiveIdx && idx === 0) continue;
    const lhs = expr.slice(0, idx).trim();
    const rhs = expr.slice(idx + op.length).trim();
    // Logical && / || — emit SHORT-CIRCUIT (if/result) form, matching emitExpr in wasic.ts, so
    // a guarded RHS side effect (e.g. `i < len && s.charCodeAt(i) === c`) does not run when the
    // LHS already decides the result. Avoids OOB access and the wasmmerge call-in-i32.and trap.
    if (op === "&&" || op === "||") {
      const lWat = exprToWat(
        lhs,
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      const rWat = exprToWat(
        rhs,
        locals,
        "i32",
        funcLookup,
        allocString,
        arrayLookup,
        structLookup,
        globals,
      );
      return op === "&&"
        ? `(if (result i32) ${lWat} (then ${rWat}) (else (i32.const 0)))`
        : `(if (result i32) ${lWat} (then (i32.const 1)) (else ${rWat}))`;
    }
    // Infer the operand type from the LEADING atom of the LHS so i32/i64 arithmetic isn't cast to
    // f64. Handles a plain local, `.length` (always i32), a struct/tuple field access `var.field`
    // (type via structLookup), AND a compound LHS like `a.i + b.i + c.i` (whose leading atom drives
    // the type). Without this, `console.log("x:", a.i + b.i)` on i32 struct fields emitted
    // `f64.add` of i32 loads and failed to compile (pre-existing bug). The leading atom is only used
    // when it's a simple var or var.field — `arr[i]` / `fn(...)` / `a.b.c` fall back to the numeric
    // default so f64 array elements / call results aren't mis-typed as i32.
    const leadM = lhs.match(/^(\w+)(?:\.(\w+))?/);
    const restAfterLead = leadM ? lhs.slice(leadM[0].length).trimStart() : "";
    const leadIsSimpleAtom = leadM !== null &&
      (restAfterLead === "" || !/^[.[(]/.test(restAfterLead));
    // Array-element operand led by `arr[…]`: the type follows the array's ELEMENT type (the lead
    // atom `arr` itself is an i32 pointer, so the generic lead-atom path below would mis-type it).
    // Keying on the lead atom (not the whole LHS) also covers a COMPOUND left operand like
    // `arr[0] + arr[1]` (3-term sums), where the LHS isn't a single bracket access. This makes
    // `console.log("x:", arr[0] + arr[1])` emit `i32.add` for an i32[] / `f64.add` for an f64[]
    // instead of defaulting to f64 (which produced wrong output or a type error).
    const leadArrElem = (leadM && leadM[2] === undefined && restAfterLead.startsWith("["))
      ? arrayLookup?.(leadM[1])?.elemType
      : undefined;
    const lhsArrNumType =
      (leadArrElem === "i32" || leadArrElem === "i64" || leadArrElem === "f64" ||
          leadArrElem === "f32")
        ? leadArrElem
        : undefined;
    const lhsLocalType = lhsArrNumType
      ? lhsArrNumType
      : !leadIsSimpleAtom || !leadM
      ? undefined
      : leadM[2] === "length"
      ? "i32" as const
      : leadM[2]
      ? (structLookup ? structLookup(leadM[1], leadM[2])?.type : undefined)
      // plain lead atom: a function-local OR a module global (`a + b` of i32 globals must be i32.add).
      : (locals.get(leadM[1]) ?? globals?.get(leadM[1]));
    // A plain INTEGER-literal LHS carries no type of its own, so opType fell back to f64 while an
    // i32 RHS stayed i32 — `console.log("x:", 1 + n)` emitted `f64.add` over an `i32` operand and
    // failed to instantiate (`a + 1` worked, `1 + a` did not). Take the type from the RHS lead atom
    // in that case. A FLOAT literal (`1.5 + n`) genuinely means f64, so it keeps the default.
    let effLhsType = lhsLocalType;
    if (effLhsType === undefined) {
      // First typed atom in `s`, or undefined. Deliberately used ONLY for the two operand shapes
      // that carry no type of their own (below) — applying it to e.g. a call LHS would wrongly
      // take the type of an argument instead of the return type.
      const firstTypedAtom = (s: string): string | undefined => {
        for (const m of s.matchAll(/\b([A-Za-z_]\w*)\b/g)) {
          const arr = arrayLookup?.(m[1]);
          const t = arr ? arr.elemType : (locals.get(m[1]) ?? globals?.get(m[1]));
          if (t !== undefined) return t;
        }
        return undefined;
      };
      const lhsTrim = lhs.trim();
      if (lhsTrim.startsWith("(")) {
        // Parenthesised LHS: `(n + 0) * 5` — the group has no lead atom, so the operand type
        // defaulted to f64 over i32 arithmetic and failed to instantiate.
        effLhsType = firstTypedAtom(lhsTrim);
      } else if (/^-?\d+$/.test(lhsTrim)) {
        // Integer-literal LHS: `1 + n`. Take the type from the RHS. A FLOAT literal (`1.5 + n`)
        // genuinely means f64 and is intentionally not matched here.
        effLhsType = firstTypedAtom(rhs);
      }
    }
    const opType = alwaysI32
      ? "i32"
      : effLhsType === "i64"
      ? "i64"
      : effLhsType === "i32" || effLhsType === "bool"
      ? "i32"
      : numType;
    const watOp = (opType === "f64" || opType === "f32")
      ? f64op
      : opType === "i64"
      ? i32op.replace(/^i32\./, "i64.")
      : i32op;
    return `(${watOp} ${
      exprToWat(lhs, locals, opType, funcLookup, allocString, arrayLookup, structLookup, globals)
    } ${
      exprToWat(rhs, locals, opType, funcLookup, allocString, arrayLookup, structLookup, globals)
    })`;
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
/** True if `token` is exactly ONE quoted string literal delimited by `q`, i.e. the closing
 *  quote is the final character with no earlier *unescaped* `q` in between. So `"abc"` →
 *  true, but `"a" + "b"` → false (an earlier closing quote), routing it to the concat path. */
function isWholeStringLiteral(token: string, q: string): boolean {
  if (token.length < 2 || token[0] !== q || token[token.length - 1] !== q) return false;
  for (let i = 1; i < token.length - 1; i++) {
    if (token[i] === "\\") {
      i++;
      continue;
    }
    if (token[i] === q) return false;
  }
  return true;
}

/** True if scanning `s` never drives `()`/`[]` depth below zero — i.e. a greedy `(.+)` arg capture
 *  didn't swallow a following `)`/`]`. Mirrors wasic.ts's guard so method handlers can fall through
 *  on an over-greedy match (e.g. `s.at(i) === t.at(j)`) instead of mis-emitting. */
function parenDepthNeverNegative(s: string): boolean {
  let d = 0;
  for (const ch of s) {
    if (ch === "(" || ch === "[") d++;
    else if (ch === ")" || ch === "]") {
      if (--d < 0) return false;
    }
  }
  return true;
}

/** Marks every index of `s` that lies inside a string/template literal (quotes included), so the
 *  depth scanner below skips literal content. A local twin of `wasic.ts`'s `buildStringLiteralMask`
 *  — this module is imported BY wasic.ts, so it cannot import back without a cycle. Keep the two in
 *  sync; see design-decisions.md § "Bracket/paren/operator scanners MUST skip string literals". */
function literalMask(s: string): boolean[] {
  const mask = new Array<boolean>(s.length).fill(false);
  let q: string | null = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q !== null) {
      mask[i] = true;
      if (c === "\\") {
        if (i + 1 < s.length) mask[i + 1] = true;
        i++;
        continue;
      }
      if (c === q) q = null;
    } else if (c === '"' || c === "'" || c === "`") {
      q = c;
      mask[i] = true;
    }
  }
  return mask;
}

function findTopLevelOp(expr: string, op: string): number {
  let depth = 0;
  // Brackets INSIDE a string literal must not count toward depth, and an operator inside one is
  // not a top-level operator. Without this, `w + "]"` drove depth to 1 at the literal's `]`, so the
  // top-level `+` was never seen at depth 0 and the whole concat silently fell through to the
  // numeric path printing `0`. (`"{" + w + "}"` worked only because braces aren't counted.)
  const inStr = literalMask(expr);
  // Scan the FULL string from the end so trailing ) / ] (e.g. a RHS ending in a call or
  // `.slice(…)`) are counted toward depth; only test for an op match at valid start positions
  // (i <= maxStart). Starting at `length - op.length` skipped those trailing chars, so an
  // expression like `a === s.slice(0, 3)` drove depth negative and the `===` was never found
  // at depth 0 → the comparison silently fell through to the numeric/terminal path.
  const maxStart = expr.length - op.length;
  for (let i = expr.length - 1; i >= 0; i--) {
    if (inStr[i]) continue; // literal content: neither depth nor a match site
    const ch = expr[i];
    if (ch === ")" || ch === "]") depth++;
    else if (ch === "(" || ch === "[") depth--;
    if (depth === 0 && i <= maxStart && expr.slice(i, i + op.length) === op) {
      const after = expr[i + op.length] ?? "";
      const before = i > 0 ? expr[i - 1] : "";
      if (op === "<" && (after === "=" || after === "<")) continue;
      if (op === ">" && (after === "=" || after === ">" || before === ">")) continue;
      if (op === "=" && after === "=") continue;
      if (op === "!" && after === "=") continue;
      if (op === "==" && (after === "=" || before === "=")) continue; // avoid ===
      if (op === "!=" && after === "=") continue; // avoid !==
      if (op === "&" && (after === "&" || before === "&")) continue;
      if (op === "|" && (after === "|" || before === "|")) continue;
      if (op === ">>" && (after === ">" || before === ">")) continue;
      if (op === "?" && after === ".") continue;
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
  globals?: Map<string, string>,
  enumStringLookup?: (key: string) => string | undefined,
  closureVarLookup?: ClosureVarLookup,
): LogSegment[] {
  const args = splitTopLevelArgs(argsStr);
  const segments: LogSegment[] = [];

  for (let i = 0; i < args.length; i++) {
    if (i > 0) segments.push({ kind: "literal", text: " " }); // space between args
    segments.push(
      ...parseSingleArg(
        args[i],
        locals,
        funcLookup,
        allocString,
        enumLookup,
        arrayLookup,
        structLookup,
        dotCallLookup,
        globals,
        enumStringLookup,
        closureVarLookup,
      ),
    );
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
): {
  statements: string[];
  needsHelpers: boolean;
  needsStrGather: boolean;
  needsArrPrintHelper: boolean;
  needsJoinHelper: boolean;
} {
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
  const numericKinds = new Set(["i32var", "i64var", "f64var", "i32expr", "i64expr", "f64expr"]);
  // `boolexpr` joined this set on 2026-08-24: gather mode evaluates the operand exactly once
  // now, so an arbitrary bool expression is safe to gather and can absorb a trailing newline.
  const strBoolKinds = new Set(["strvar", "boolvar", "boolexpr", "strcall", "strexpr"]);
  const trailingLitNL = merged.length >= 2 &&
    merged[merged.length - 1].kind === "literal" &&
    (merged[merged.length - 1] as { kind: "literal"; text: string }).text === "\n";
  const canInlineNL = trailingLitNL &&
    (numericKinds.has(merged[merged.length - 2].kind) ||
      strBoolKinds.has(merged[merged.length - 2].kind));

  // Active segments to process (strip standalone "\n" when we will inline it).
  const activeSegs = (trailingLitNL && canInlineNL) ? merged.slice(0, -1) : merged;

  // Step 3: decide emit strategy.
  // Gather mode consolidates ALL output into scratch (SCRATCH_BASE...) and emits a
  // single fd_write iov.
  //
  // ⚠️ CORRECTED 2026-08-24 — the previous note here read "needed because wasmtime 43 only
  // processes the first iov", which blamed the wrong side and would send the next reader to file a
  // wasmtime bug. Measured on wasmtime 47.0.3 with a two-iovec fixture: it writes iov[0] only AND
  // REPORTS `nwritten = 2` of the 3 requested. That is a SHORT WRITE, which WASI explicitly permits;
  // wasmtime is telling the truth. **The defect is ours — we never read `nwritten` back** (it is
  // stored at NWRITTEN_OFFSET and no emitted code ever loads it) and no emitted path retries, so any
  // short write silently truncates output.
  //
  // Gather mode therefore MITIGATES rather than fixes: one iovec makes a short write less likely,
  // not impossible — a large enough single write can still be truncated. The real fix is a retry
  // loop around fd_write. See cmem/compiler-bugs.md § "fd_write short writes".
  // strvar uses memory.copy into scratch; boolvar uses conditional memory.copy.
  // boolexpr USED to stay in per-iov mode because gather evaluated the operand three times, which
  // is unsafe for arbitrary WAT. The bool branch now evaluates it exactly once, so it can gather.
  const gatherable = (s: LogSegment) =>
    s.kind === "literal" || numericKinds.has(s.kind) || s.kind === "strvar" ||
    s.kind === "boolvar" || s.kind === "boolexpr" || s.kind === "arrptr" || s.kind === "joinarr" ||
    s.kind === "strcall" || s.kind === "strexpr";
  const arrptrKinds = new Set(["arrptr", "joinarr"]);
  // Single strvar/boolvar/arrptr/joinarr/strcall/strexpr segments also use gather so the newline can be inlined.
  const useGather = activeSegs.every(gatherable) &&
    (activeSegs.length > 1 || strBoolKinds.has(activeSegs[0]?.kind ?? "") ||
      arrptrKinds.has(activeSegs[0]?.kind ?? "") || activeSegs[0]?.kind === "strcall" ||
      activeSegs[0]?.kind === "strexpr");

  const statements: string[] = [];
  let needsHelpers = false;
  let needsStrGather = false;
  let needsArrPrintHelper = false;
  let needsJoinHelper = false;

  if (useGather) {
    // ── Gather-buffer mode ────────────────────────────────────────────────────
    // iov[0].ptr (iovBase+0) = scratchBase  (set once)
    // iov[0].len (iovBase+4) doubles as the running cursor into scratch.
    const cursorAddr = iovBase + 4;
    statements.push(
      `${indent}(i32.store (i32.const ${iovBase}) (i32.const ${scratchBase}))`,
      `${indent}(i32.store (i32.const ${cursorAddr}) (i32.const 0))`,
    );

    let compileCursor = 0; // byte offset from SCRATCH_BASE, valid until first numeric
    let runtimeCursor = false; // true after the first numeric (cursor only in mem[cursorAddr])

    for (const seg of activeSegs) {
      if (seg.kind === "literal") {
        const bytes = Array.from(new TextEncoder().encode(seg.text));
        if (!runtimeCursor) {
          // Compile-time position: fixed-address stores
          for (let j = 0; j < bytes.length; j++) {
            statements.push(
              `${indent}(i32.store8 (i32.const ${scratchBase + compileCursor + j}) (i32.const ${
                bytes[j]
              }))`,
            );
          }
          compileCursor += bytes.length;
        } else {
          // Runtime position: cursor-relative stores then advance cursor
          for (let j = 0; j < bytes.length; j++) {
            statements.push(
              `${indent}(i32.store8 (i32.add (i32.const ${scratchBase}) (i32.add (i32.load (i32.const ${cursorAddr})) (i32.const ${j}))) (i32.const ${
                bytes[j]
              }))`,
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
        // Support module string consts encoded as __strconst_ptr_NNN / __strconst_len_NNN
        const ptrMsc = seg.ptrLocal.match(/^__strconst_ptr_(\d+)$/);
        const lenMsc = seg.lenLocal.match(/^__strconst_len_(\d+)$/);
        const ptrWat = ptrMsc ? `(i32.const ${ptrMsc[1]})` : `(local.get $${seg.ptrLocal})`;
        const lenWat = lenMsc ? `(i32.const ${lenMsc[1]})` : `(local.get $${seg.lenLocal})`;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        statements.push(
          `${indent}(call $__str_gather ${ptrWat} ${lenWat} ${destExpr})`,
        );
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) ${lenWat}))`,
          );
          runtimeCursor = true;
        } else {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) ${lenWat}))`,
          );
        }
      } else if (seg.kind === "boolvar" || seg.kind === "boolexpr") {
        // Bool — copy "true"/"false" bytes into scratch via $__str_gather, advance cursor.
        //
        // ONE `if`, gather + cursor bump inside each arm, so the operand is evaluated EXACTLY ONCE.
        // The previous shape built `srcExpr` and `lenExpr` as separate value-form `if`s and used
        // `lenExpr` twice — THREE evaluations. Harmless for `boolvar` (`local.get` is pure), fatal
        // for `boolexpr`, which is why `boolexpr` was excluded from gather mode entirely. Evaluating
        // once is what lets it in (see `gatherable` below), so the exclusion and the double-eval bug
        // were one knot, not two.
        //
        // Everything duplicated across the arms is pure: `destExpr` is a constant or an i32.load,
        // and the offsets/lengths are compile-time constants.
        needsStrGather = true;
        const [trueOff] = allocString("true");
        const [falseOff] = allocString("false");
        const val = seg.kind === "boolvar" ? `(local.get $${seg.name})` : seg.wat;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        const bump = (len: number) =>
          runtimeCursor
            ? `(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) (i32.const ${len})))`
            : `(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) (i32.const ${len})))`;
        statements.push(
          `${indent}(if ${val}`,
          `${indent}  (then`,
          `${indent}    (call $__str_gather (i32.const ${trueOff}) (i32.const 4) ${destExpr})`,
          `${indent}    ${bump(4)})`,
          `${indent}  (else`,
          `${indent}    (call $__str_gather (i32.const ${falseOff}) (i32.const 5) ${destExpr})`,
          `${indent}    ${bump(5)}))`,
        );
        runtimeCursor = true;
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
        const helperName = seg.elemType === "f64"
          ? "$__write_f64arr_to_scratch"
          : seg.elemType === "i64"
          ? "$__write_i64arr_to_scratch"
          : "$__write_i32arr_to_scratch";
        statements.push(
          `${indent}(call ${helperName} ${seg.wat} (i32.const ${scratchBase}) (i32.const ${cursorAddr}))`,
        );
      } else if (seg.kind === "joinarr") {
        // Phase 28: arr.join(sep) — write joined string into scratch via helper
        needsJoinHelper = true;
        needsHelpers = true; // $__dynarr_join_to_scratch_* depends on $__i32_to_str / $__f64_to_str
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.const ${compileCursor}))`,
          );
          runtimeCursor = true;
        }
        const joinHelper = seg.elemType === "f64"
          ? "$__dynarr_join_to_scratch_f64"
          : "$__dynarr_join_to_scratch_i32";
        statements.push(
          `${indent}(call ${joinHelper} ${seg.arrWat} (i32.const ${seg.sepPtr}) (i32.const ${seg.sepLen}) (i32.const ${scratchBase}) (i32.const ${cursorAddr}))`,
        );
      } else if (seg.kind === "strcall") {
        // String-returning function: call (void, sets globals), then gather from globals
        needsStrGather = true;
        statements.push(`${indent}${seg.callWat}`);
        const ptrWat = `(global.get $__str_ret_ptr)`;
        const lenWat = `(global.get $__str_ret_len)`;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        statements.push(`${indent}(call $__str_gather ${ptrWat} ${lenWat} ${destExpr})`);
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) ${lenWat}))`,
          );
          runtimeCursor = true;
        } else {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) ${lenWat}))`,
          );
        }
      } else if (seg.kind === "strexpr") {
        // Arbitrary WAT ptr+len expressions — gather directly from the computed ptr/len
        needsStrGather = true;
        const destExpr = runtimeCursor
          ? `(i32.add (i32.const ${scratchBase}) (i32.load (i32.const ${cursorAddr})))`
          : `(i32.const ${scratchBase + compileCursor})`;
        statements.push(`${indent}(call $__str_gather ${seg.ptrWat} ${seg.lenWat} ${destExpr})`);
        if (!runtimeCursor) {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.const ${compileCursor}) ${seg.lenWat}))`,
          );
          runtimeCursor = true;
        } else {
          statements.push(
            `${indent}(i32.store (i32.const ${cursorAddr}) (i32.add (i32.load (i32.const ${cursorAddr})) ${seg.lenWat}))`,
          );
        }
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
      `${indent}(call $__fd_write_all`,
      `${indent}  (i32.const ${fd})`,
      `${indent}  (i32.const ${iovBase})`,
      `${indent}  (i32.const 1)`,
      `${indent}  (i32.const ${nwrittenOffset}))`,
    );
  } else {
    // ── Per-iov mode (single active segment, or strvar/bool segments) ─────────
    let numericSlot = 0;
    let lastNumericScratch = -1;
    let lastNumericIovLen = -1;

    for (let i = 0; i < activeSegs.length; i++) {
      const seg = activeSegs[i];
      const iovPtr = iovBase + i * 8; // iov[i].buf  (i32)
      const iovLen = iovBase + i * 8 + 4; // iov[i].buf_len (i32)

      if (seg.kind === "literal") {
        const [offset, len] = allocString(seg.text);
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${offset}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (i32.const ${len}))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "strvar") {
        const _ptrMsc = seg.ptrLocal.match(/^__strconst_ptr_(\d+)$/);
        const _lenMsc = seg.lenLocal.match(/^__strconst_len_(\d+)$/);
        const _ptrW = _ptrMsc ? `(i32.const ${_ptrMsc[1]})` : `(local.get $${seg.ptrLocal})`;
        const _lenW = _lenMsc ? `(i32.const ${_lenMsc[1]})` : `(local.get $${seg.lenLocal})`;
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) ${_ptrW})`,
          `${indent}(i32.store (i32.const ${iovLen}) ${_lenW})`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "boolvar" || seg.kind === "boolexpr") {
        const [trueOff] = allocString("true");
        const [falseOff] = allocString("false");
        const val = seg.kind === "boolvar" ? `(local.get $${seg.name})` : seg.wat;
        // ONE `if`, both stores inside each arm — so ${val} is evaluated EXACTLY ONCE.
        //
        // This used to be two value-form `(if (result i32) ${val} …)` stores, which interpolated the
        // operand twice. For `boolvar` that is harmless (`local.get` is pure), but `boolexpr` is
        // arbitrary WAT: `console.log(isPositive(5))` called isPositive TWICE, so any side effect in
        // a bool-returning function happened twice. That is a semantic bug, not a formatting one, and
        // no engine could have caught it — they all agree on the wrong answer.
        statements.push(
          `${indent}(if ${val}`,
          `${indent}  (then`,
          `${indent}    (i32.store (i32.const ${iovPtr}) (i32.const ${trueOff}))`,
          `${indent}    (i32.store (i32.const ${iovLen}) (i32.const 4)))`,
          `${indent}  (else`,
          `${indent}    (i32.store (i32.const ${iovPtr}) (i32.const ${falseOff}))`,
          `${indent}    (i32.store (i32.const ${iovLen}) (i32.const 5))))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "arrptr") {
        needsArrPrintHelper = true;
        needsHelpers = true;
        const helperName = seg.elemType === "f64"
          ? "$__write_f64arr_to_scratch"
          : "$__write_i32arr_to_scratch";
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${scratchBase}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (i32.const 0))`,
          `${indent}(call ${helperName} ${seg.wat} (i32.const ${scratchBase}) (i32.const ${iovLen}))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "joinarr") {
        needsJoinHelper = true;
        needsHelpers = true;
        const joinHelper = seg.elemType === "f64"
          ? "$__dynarr_join_to_scratch_f64"
          : "$__dynarr_join_to_scratch_i32";
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) (i32.const ${scratchBase}))`,
          `${indent}(i32.store (i32.const ${iovLen}) (i32.const 0))`,
          `${indent}(call ${joinHelper} ${seg.arrWat} (i32.const ${seg.sepPtr}) (i32.const ${seg.sepLen}) (i32.const ${scratchBase}) (i32.const ${iovLen}))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "strcall") {
        // String-returning function: call (void, sets globals), store globals in iov
        statements.push(
          `${indent}${seg.callWat}`,
          `${indent}(i32.store (i32.const ${iovPtr}) (global.get $__str_ret_ptr))`,
          `${indent}(i32.store (i32.const ${iovLen}) (global.get $__str_ret_len))`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else if (seg.kind === "strexpr") {
        // Arbitrary WAT ptr+len expressions — store computed values directly into iov
        statements.push(
          `${indent}(i32.store (i32.const ${iovPtr}) ${seg.ptrWat})`,
          `${indent}(i32.store (i32.const ${iovLen}) ${seg.lenWat})`,
        );
        lastNumericScratch = -1;
        lastNumericIovLen = -1;
      } else {
        // Numeric segment
        if (numericSlot >= SCRATCH_SLOTS) { // SCRATCH_SLOTS = 4 (constant)
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
        lastNumericIovLen = iovLen;
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
      `${indent}(call $__fd_write_all`,
      `${indent}  (i32.const ${fd})`,
      `${indent}  (i32.const ${iovBase})`,
      `${indent}  (i32.const ${activeSegs.length})`,
      `${indent}  (i32.const ${nwrittenOffset}))`,
    );
  }

  return { statements, needsHelpers, needsStrGather, needsArrPrintHelper, needsJoinHelper };
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
/**
 * WAT for `$__fd_write_all` — an `fd_write` that honours SHORT WRITES.
 *
 * WASI permits `fd_write` to write fewer bytes than requested and report the true count in
 * `*nwritten`. Measured 2026-08-24: wasmtime 47.0.3 writes `iov[0]` only and reports
 * `nwritten = 2` of 3 requested; wasmer 7.2.1 writes all 3. Both are conforming.
 *
 * Every emitted call used to be `(drop (call $fd_write …))` — the result and `nwritten` were
 * discarded — so on wasmtime any output split across more than one iovec silently truncated. The
 * visible symptom was `console.log(<bool expr>)` losing its trailing newline (37 corpus modules).
 *
 * The loop drains the iovec array in place, advancing `ptr` and shrinking `len` on a partial write.
 * It bails on a non-zero errno and on zero progress — the latter matters, because a runtime that
 * reports success while writing nothing would otherwise spin forever.
 *
 * Emitted whenever `hasConsoleLog` is set, i.e. exactly when `$fd_write` is imported.
 */
export function getFdWriteAllWat(): string {
  return `
  ;; ── fd_write that honours short writes ────────────────────────────────────
  (func $__fd_write_all (param $fd i32) (param $iov i32) (param $cnt i32) (param $nw i32)
    (local $n i32)
    (local $len i32)
    (block $done
      (loop $again
        (br_if $done (i32.eqz (local.get $cnt)))
        ;; non-zero errno: no progress is possible, stop. (The previous code dropped the
        ;; result entirely, so bailing here is no quieter than what it replaced.)
        (br_if $done
          (call $fd_write (local.get $fd) (local.get $iov) (local.get $cnt) (local.get $nw)))
        (local.set $n (i32.load (local.get $nw)))
        ;; zero bytes written would spin forever
        (br_if $done (i32.eqz (local.get $n)))
        ;; consume $n bytes across the iovec array, in place
        (block $consumed
          (loop $eat
            (br_if $consumed (i32.eqz (local.get $cnt)))
            (br_if $consumed (i32.eqz (local.get $n)))
            (local.set $len (i32.load (i32.add (local.get $iov) (i32.const 4))))
            (if (i32.ge_u (local.get $n) (local.get $len))
              (then
                ;; this iovec is fully written — move to the next
                (local.set $n (i32.sub (local.get $n) (local.get $len)))
                (local.set $iov (i32.add (local.get $iov) (i32.const 8)))
                (local.set $cnt (i32.sub (local.get $cnt) (i32.const 1))))
              (else
                ;; partial: advance ptr, shrink len, and re-issue
                (i32.store (local.get $iov)
                  (i32.add (i32.load (local.get $iov)) (local.get $n)))
                (i32.store (i32.add (local.get $iov) (i32.const 4))
                  (i32.sub (local.get $len) (local.get $n)))
                (local.set $n (i32.const 0))))
            (br $eat)))
        (br $again))))
`;
}

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

  ;; ── i32 → string in an arbitrary radix (2..36), e.g. (14).toString(2) = "1110" ──
  ;; Mirrors $__i32_to_str but with a parameterised base + digit→char (0-9→'0'+d, 10-35→'a'+d-10).
  ;; Negative values get a leading '-' and unsigned magnitude digits (JS sign-magnitude semantics).
  (func $__i32_to_str_radix (param $val i32) (param $radix i32) (param $buf i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $tmp i32)
    (local $ch i32)
    (local $swap i32)
    (local $orig i32)
    (local $d i32)
    (local.set $orig (local.get $buf))
    (local.set $start (local.get $buf))
    ;; clamp radix to [2,36] (JS RangeError otherwise; fall back to base 10)
    (if (i32.or (i32.lt_s (local.get $radix) (i32.const 2)) (i32.gt_s (local.get $radix) (i32.const 36)))
      (then (local.set $radix (i32.const 10)))
    )
    ;; Zero
    (if (i32.eqz (local.get $val))
      (then
        (i32.store8 (local.get $buf) (i32.const 48))
        (return (i32.const 1))
      )
    )
    ;; Negative → leading '-' then magnitude
    (if (i32.lt_s (local.get $val) (i32.const 0))
      (then
        (i32.store8 (local.get $buf) (i32.const 45))
        (local.set $buf (i32.add (local.get $buf) (i32.const 1)))
        (local.set $start (local.get $buf))
        (local.set $val (i32.sub (i32.const 0) (local.get $val)))
      )
    )
    (local.set $end (local.get $buf))
    ;; Write digits in reverse
    (block $done
      (loop $loop
        (br_if $done (i32.eqz (local.get $val)))
        (local.set $d (i32.rem_u (local.get $val) (local.get $radix)))
        (i32.store8
          (local.get $end)
          (if (result i32) (i32.lt_u (local.get $d) (i32.const 10))
            (then (i32.add (i32.const 48) (local.get $d)))
            (else (i32.add (i32.const 87) (local.get $d)))
          )
        )
        (local.set $val (i32.div_u (local.get $val) (local.get $radix)))
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
        (local.set $swap (i32.load8_u (local.get $tmp)))
        (i32.store8 (local.get $tmp) (i32.load8_u (local.get $ch)))
        (i32.store8 (local.get $ch) (local.get $swap))
        (local.set $tmp (i32.add (local.get $tmp) (i32.const 1)))
        (local.set $ch (i32.sub (local.get $ch) (i32.const 1)))
        (br $rloop)
      )
    )
    (i32.sub (local.get $end) (local.get $orig))
  )

  ;; -- Dragon4 (Burger-Dybvig) shortest + correctly-rounded f64 -> decimal ------
  ;; Fixed-size limb bignums (48 x u32 = 1536 bits) in a lazily-malloc'd scratch
  ;; region ($__d4s). Produces the shortest decimal digit string that round-trips
  ;; to the exact f64 (round-to-even ties), then formats per ECMAScript
  ;; Number.prototype.toString rules (fixed-point for pointPos in (-6,21], else
  ;; scientific). 100% byte-exact parity with V8 across normal + subnormal range.
  (func $__bz (param $p i32)
    (local $i i32)
    (loop $l
      (i32.store (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))) (i32.const 0))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bset64 (param $p i32) (param $v i64)
    (call $__bz (local.get $p))
    (i32.store (local.get $p) (i32.wrap_i64 (i64.and (local.get $v) (i64.const 0xffffffff))))
    (i32.store offset=4 (local.get $p) (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 32))))
  )
  (func $__bmul_u32 (param $p i32) (param $m i32)
    (local $i i32) (local $carry i64) (local $prod i64) (local $addr i32)
    (loop $l
      (local.set $addr (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
      (local.set $prod
        (i64.add
          (i64.mul (i64.extend_i32_u (i32.load (local.get $addr))) (i64.extend_i32_u (local.get $m)))
          (local.get $carry)))
      (i32.store (local.get $addr) (i32.wrap_i64 (i64.and (local.get $prod) (i64.const 0xffffffff))))
      (local.set $carry (i64.shr_u (local.get $prod) (i64.const 32)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bshl (param $p i32) (param $bits i32)
    (local $limbShift i32) (local $bitShift i32) (local $i i32) (local $src i32)
    (local $lo i32) (local $hi i32) (local $val i32)
    (local.set $limbShift (i32.div_u (local.get $bits) (i32.const 32)))
    (local.set $bitShift  (i32.rem_u (local.get $bits) (i32.const 32)))
    (local.set $i (i32.const 47))
    (loop $l
      (local.set $src (i32.sub (local.get $i) (local.get $limbShift)))
      (local.set $val (i32.const 0))
      (if (i32.ge_s (local.get $src) (i32.const 0))
        (then
          (local.set $lo (i32.load (i32.add (local.get $p) (i32.shl (local.get $src) (i32.const 2)))))
          (if (i32.eqz (local.get $bitShift))
            (then (local.set $val (local.get $lo)))
            (else
              (local.set $val (i32.shl (local.get $lo) (local.get $bitShift)))
              (if (i32.gt_s (local.get $src) (i32.const 0))
                (then
                  (local.set $hi (i32.load (i32.add (local.get $p) (i32.shl (i32.sub (local.get $src) (i32.const 1)) (i32.const 2)))))
                  (local.set $val (i32.or (local.get $val)
                    (i32.shr_u (local.get $hi) (i32.sub (i32.const 32) (local.get $bitShift)))))
                ))
            ))
        ))
      (i32.store (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))) (local.get $val))
      (local.set $i (i32.sub (local.get $i) (i32.const 1)))
      (br_if $l (i32.ge_s (local.get $i) (i32.const 0)))
    )
  )
  (func $__bcmp (param $a i32) (param $b i32) (result i32)
    (local $i i32) (local $va i32) (local $vb i32)
    (local.set $i (i32.const 47))
    (loop $l
      (local.set $va (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
      (local.set $vb (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2)))))
      (if (i32.ne (local.get $va) (local.get $vb))
        (then (return (select (i32.const 1) (i32.const -1) (i32.gt_u (local.get $va) (local.get $vb))))))
      (local.set $i (i32.sub (local.get $i) (i32.const 1)))
      (br_if $l (i32.ge_s (local.get $i) (i32.const 0)))
    )
    (i32.const 0)
  )
  (func $__badd (param $d i32) (param $a i32) (param $b i32)
    (local $i i32) (local $carry i64) (local $sum i64)
    (loop $l
      (local.set $sum
        (i64.add
          (i64.add
            (i64.extend_i32_u (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
            (i64.extend_i32_u (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))))
          (local.get $carry)))
      (i32.store (i32.add (local.get $d) (i32.shl (local.get $i) (i32.const 2)))
        (i32.wrap_i64 (i64.and (local.get $sum) (i64.const 0xffffffff))))
      (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__bsub (param $d i32) (param $a i32) (param $b i32)
    (local $i i32) (local $borrow i64) (local $diff i64)
    (loop $l
      (local.set $diff
        (i64.sub
          (i64.sub
            (i64.extend_i32_u (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
            (i64.extend_i32_u (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))))
          (local.get $borrow)))
      (i32.store (i32.add (local.get $d) (i32.shl (local.get $i) (i32.const 2)))
        (i32.wrap_i64 (i64.and (local.get $diff) (i64.const 0xffffffff))))
      (local.set $borrow (i64.and (i64.shr_u (local.get $diff) (i64.const 63)) (i64.const 1)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 48)))
    )
  )
  (func $__f64_to_str (param $val f64) (param $buf i32) (result i32)
    (local $bits i64) (local $e i32) (local $f i64)
    (local $even i32) (local $isMin i32)
    (local $R i32) (local $S i32) (local $MP i32) (local $MM i32) (local $TMP i32) (local $DIG i32)
    (local $k i32) (local $ndig i32) (local $i i32) (local $dg i32)
    (local $ptr i32) (local $sign i32) (local $cmp i32) (local $low i32) (local $high i32)
    (local $pp i32)
    (local.set $ptr (local.get $buf))
    ;; NaN
    (if (f64.ne (local.get $val) (local.get $val))
      (then
        (i32.store8 (local.get $ptr) (i32.const 78))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 97))
        (i32.store8 offset=2 (local.get $ptr) (i32.const 78))
        (return (i32.const 3))))
    ;; sign (-0 -> lt is false -> prints "0")
    (if (f64.lt (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (local.set $val (f64.neg (local.get $val)))
        (local.set $sign (i32.const 1))))
    ;; Infinity
    (if (f64.eq (local.get $val) (f64.const inf))
      (then
        (i32.store8 (local.get $ptr) (i32.const 73))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 110))
        (i32.store8 offset=2 (local.get $ptr) (i32.const 102))
        (i32.store8 offset=3 (local.get $ptr) (i32.const 105))
        (i32.store8 offset=4 (local.get $ptr) (i32.const 110))
        (i32.store8 offset=5 (local.get $ptr) (i32.const 105))
        (i32.store8 offset=6 (local.get $ptr) (i32.const 116))
        (i32.store8 offset=7 (local.get $ptr) (i32.const 121))
        (return (i32.add (i32.sub (local.get $ptr) (local.get $buf)) (i32.const 8)))))
    ;; zero
    (if (f64.eq (local.get $val) (f64.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 48))
        (return (i32.add (i32.sub (local.get $ptr) (local.get $buf)) (i32.const 1)))))
    ;; lazily allocate bignum scratch
    (if (i32.eqz (global.get $__d4s))
      (then (global.set $__d4s (call $__malloc (i32.const 1024)))))
    (local.set $R   (global.get $__d4s))
    (local.set $S   (i32.add (global.get $__d4s) (i32.const 192)))
    (local.set $MP  (i32.add (global.get $__d4s) (i32.const 384)))
    (local.set $MM  (i32.add (global.get $__d4s) (i32.const 576)))
    (local.set $TMP (i32.add (global.get $__d4s) (i32.const 768)))
    (local.set $DIG (i32.add (global.get $__d4s) (i32.const 960)))
    ;; decompose f64 -> f (mantissa integer) x 2^e
    (local.set $bits (i64.reinterpret_f64 (local.get $val)))
    (local.set $e (i32.wrap_i64 (i64.and (i64.shr_u (local.get $bits) (i64.const 52)) (i64.const 0x7ff))))
    (local.set $f (i64.and (local.get $bits) (i64.const 0xfffffffffffff)))
    (if (i32.eqz (local.get $e))
      (then (local.set $e (i32.const -1074)))
      (else
        (local.set $f (i64.or (local.get $f) (i64.shl (i64.const 1) (i64.const 52))))
        (local.set $e (i32.sub (local.get $e) (i32.const 1075)))))
    (local.set $even (i32.eqz (i32.wrap_i64 (i64.and (local.get $f) (i64.const 1)))))
    (local.set $isMin (i64.eq (local.get $f) (i64.shl (i64.const 1) (i64.const 52))))
    ;; build R, S, m+, m-
    (if (i32.ge_s (local.get $e) (i32.const 0))
      (then
        (call $__bset64 (local.get $TMP) (i64.const 1))
        (call $__bshl (local.get $TMP) (local.get $e))
        (if (i32.eqz (local.get $isMin))
          (then
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.add (local.get $e) (i32.const 1)))
            (call $__bset64 (local.get $S) (i64.const 2))
            (memory.copy (local.get $MP) (local.get $TMP) (i32.const 192))
            (memory.copy (local.get $MM) (local.get $TMP) (i32.const 192)))
          (else
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.add (local.get $e) (i32.const 2)))
            (call $__bset64 (local.get $S) (i64.const 4))
            (memory.copy (local.get $MP) (local.get $TMP) (i32.const 192))
            (call $__bshl (local.get $MP) (i32.const 1))
            (memory.copy (local.get $MM) (local.get $TMP) (i32.const 192)))))
      (else
        (if (i32.or (i32.eq (local.get $e) (i32.const -1074)) (i32.eqz (local.get $isMin)))
          (then
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.const 1))
            (call $__bset64 (local.get $S) (i64.const 1))
            (call $__bshl (local.get $S) (i32.add (i32.sub (i32.const 0) (local.get $e)) (i32.const 1)))
            (call $__bset64 (local.get $MP) (i64.const 1))
            (call $__bset64 (local.get $MM) (i64.const 1)))
          (else
            (call $__bset64 (local.get $R) (local.get $f))
            (call $__bshl (local.get $R) (i32.const 2))
            (call $__bset64 (local.get $S) (i64.const 1))
            (call $__bshl (local.get $S) (i32.add (i32.sub (i32.const 0) (local.get $e)) (i32.const 2)))
            (call $__bset64 (local.get $MP) (i64.const 2))
            (call $__bset64 (local.get $MM) (i64.const 1))))))
    ;; k estimate from binary magnitude (bidirectional fixup corrects any error)
    (local.set $k
      (i32.trunc_f64_s
        (f64.ceil
          (f64.mul (f64.convert_i32_s (i32.add (local.get $e) (i32.const 52)))
                   (f64.const 0.30102999566398114)))))
    ;; initial scale by 10^k
    (if (i32.ge_s (local.get $k) (i32.const 0))
      (then
        (local.set $i (i32.const 0))
        (block $se (loop $sl
          (br_if $se (i32.ge_s (local.get $i) (local.get $k)))
          (call $__bmul_u32 (local.get $S) (i32.const 10))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $sl))))
      (else
        (local.set $i (local.get $k))
        (block $re (loop $rl
          (br_if $re (i32.ge_s (local.get $i) (i32.const 0)))
          (call $__bmul_u32 (local.get $R)  (i32.const 10))
          (call $__bmul_u32 (local.get $MP) (i32.const 10))
          (call $__bmul_u32 (local.get $MM) (i32.const 10))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $rl)))))
    ;; too-small fixup: while high(R+m+, S) -> S*=10; k++
    (block $fse (loop $fsl
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (br_if $fse (i32.eqz
        (select (i32.ge_s (local.get $cmp) (i32.const 0))
                (i32.gt_s (local.get $cmp) (i32.const 0))
                (local.get $even))))
      (call $__bmul_u32 (local.get $S) (i32.const 10))
      (local.set $k (i32.add (local.get $k) (i32.const 1)))
      (br $fsl)))
    ;; too-big fixup: while NOT high(10*(R+m+), S) -> R,m+,m- *=10; k--
    (block $fbe (loop $fbl
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (call $__bmul_u32 (local.get $TMP) (i32.const 10))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (br_if $fbe (i32.eqz
        (select (i32.lt_s (local.get $cmp) (i32.const 0))
                (i32.le_s (local.get $cmp) (i32.const 0))
                (local.get $even))))
      (call $__bmul_u32 (local.get $R)  (i32.const 10))
      (call $__bmul_u32 (local.get $MP) (i32.const 10))
      (call $__bmul_u32 (local.get $MM) (i32.const 10))
      (local.set $k (i32.sub (local.get $k) (i32.const 1)))
      (br $fbl)))
    ;; digit generation
    (local.set $ndig (i32.const 0))
    (loop $dl
      (call $__bmul_u32 (local.get $R)  (i32.const 10))
      (call $__bmul_u32 (local.get $MP) (i32.const 10))
      (call $__bmul_u32 (local.get $MM) (i32.const 10))
      ;; dg = R/S ; R = R%S  (repeated subtract, dg in [0,9])
      (local.set $dg (i32.const 0))
      (block $sube (loop $subl
        (br_if $sube (i32.lt_s (call $__bcmp (local.get $R) (local.get $S)) (i32.const 0)))
        (call $__bsub (local.get $R) (local.get $R) (local.get $S))
        (local.set $dg (i32.add (local.get $dg) (i32.const 1)))
        (br $subl)))
      ;; low
      (local.set $cmp (call $__bcmp (local.get $R) (local.get $MM)))
      (local.set $low
        (select (i32.le_s (local.get $cmp) (i32.const 0))
                (i32.lt_s (local.get $cmp) (i32.const 0))
                (local.get $even)))
      ;; high
      (call $__badd (local.get $TMP) (local.get $R) (local.get $MP))
      (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
      (local.set $high
        (select (i32.ge_s (local.get $cmp) (i32.const 0))
                (i32.gt_s (local.get $cmp) (i32.const 0))
                (local.get $even)))
      ;; continue when neither boundary reached
      (if (i32.and (i32.eqz (local.get $low)) (i32.eqz (local.get $high)))
        (then
          (i32.store8 (i32.add (local.get $DIG) (local.get $ndig)) (i32.add (i32.const 48) (local.get $dg)))
          (local.set $ndig (i32.add (local.get $ndig) (i32.const 1)))
          (br $dl)))
      ;; terminate: choose final digit (default keep dg)
      (if (i32.and (local.get $high) (i32.eqz (local.get $low)))
        (then (local.set $dg (i32.add (local.get $dg) (i32.const 1))))
        (else
          (if (i32.and (local.get $high) (local.get $low))
            (then
              (call $__badd (local.get $TMP) (local.get $R) (local.get $R))
              (local.set $cmp (call $__bcmp (local.get $TMP) (local.get $S)))
              (if (i32.gt_s (local.get $cmp) (i32.const 0))
                (then (local.set $dg (i32.add (local.get $dg) (i32.const 1))))
                (else
                  (if (i32.eqz (local.get $cmp))
                    (then (if (i32.and (local.get $dg) (i32.const 1))
                            (then (local.set $dg (i32.add (local.get $dg) (i32.const 1)))))))))))))
      (i32.store8 (i32.add (local.get $DIG) (local.get $ndig)) (i32.add (i32.const 48) (local.get $dg)))
      (local.set $ndig (i32.add (local.get $ndig) (i32.const 1)))
    )
    ;; format per ECMAScript Number.prototype.toString (pointPos == k)
    (local.set $pp (local.get $k))
    ;; pp > 21 -> scientific "d[.ddd]e+E"
    (if (i32.gt_s (local.get $pp) (i32.const 21))
      (then
        (i32.store8 (local.get $ptr) (i32.load8_u (local.get $DIG)))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (if (i32.gt_s (local.get $ndig) (i32.const 1))
          (then
            (i32.store8 (local.get $ptr) (i32.const 46))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
            (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (i32.const 1)) (i32.sub (local.get $ndig) (i32.const 1)))
            (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (i32.const 1))))))
        (i32.store8 (local.get $ptr) (i32.const 101))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 43))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $ptr (i32.add (local.get $ptr) (call $__i32_to_str (i32.sub (local.get $pp) (i32.const 1)) (local.get $ptr))))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp <= -6 -> scientific "d[.ddd]e-E"
    (if (i32.le_s (local.get $pp) (i32.const -6))
      (then
        (i32.store8 (local.get $ptr) (i32.load8_u (local.get $DIG)))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (if (i32.gt_s (local.get $ndig) (i32.const 1))
          (then
            (i32.store8 (local.get $ptr) (i32.const 46))
            (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
            (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (i32.const 1)) (i32.sub (local.get $ndig) (i32.const 1)))
            (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (i32.const 1))))))
        (i32.store8 (local.get $ptr) (i32.const 101))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 45))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $ptr (i32.add (local.get $ptr) (call $__i32_to_str (i32.sub (i32.const 1) (local.get $pp)) (local.get $ptr))))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp <= 0 -> "0." + (-pp) zeros + digits
    (if (i32.le_s (local.get $pp) (i32.const 0))
      (then
        (i32.store8 (local.get $ptr) (i32.const 48))
        (i32.store8 offset=1 (local.get $ptr) (i32.const 46))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
        (local.set $i (i32.const 0))
        (block $ze (loop $zl
          (br_if $ze (i32.ge_s (local.get $i) (i32.sub (i32.const 0) (local.get $pp))))
          (i32.store8 (local.get $ptr) (i32.const 48))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $zl)))
        (memory.copy (local.get $ptr) (local.get $DIG) (local.get $ndig))
        (local.set $ptr (i32.add (local.get $ptr) (local.get $ndig)))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; pp >= ndig -> digits + (pp-ndig) zeros
    (if (i32.ge_s (local.get $pp) (local.get $ndig))
      (then
        (memory.copy (local.get $ptr) (local.get $DIG) (local.get $ndig))
        (local.set $ptr (i32.add (local.get $ptr) (local.get $ndig)))
        (local.set $i (i32.const 0))
        (block $ze2 (loop $zl2
          (br_if $ze2 (i32.ge_s (local.get $i) (i32.sub (local.get $pp) (local.get $ndig))))
          (i32.store8 (local.get $ptr) (i32.const 48))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $zl2)))
        (return (i32.sub (local.get $ptr) (local.get $buf)))))
    ;; else split at pp: digits[0..pp) "." digits[pp..]
    (memory.copy (local.get $ptr) (local.get $DIG) (local.get $pp))
    (local.set $ptr (i32.add (local.get $ptr) (local.get $pp)))
    (i32.store8 (local.get $ptr) (i32.const 46))
    (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
    (memory.copy (local.get $ptr) (i32.add (local.get $DIG) (local.get $pp)) (i32.sub (local.get $ndig) (local.get $pp)))
    (local.set $ptr (i32.add (local.get $ptr) (i32.sub (local.get $ndig) (local.get $pp))))
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
  )
  ;; ── write f64[] to scratch ────────────────────────────────────────────────
  ;; Appends "[ elem, elem, ... ]" into the gather buffer.
  ;; arr_ptr layout: [length:i32, 0:i32, elem0:f64, elem1:f64, ...]
  (func $__write_f64arr_to_scratch (param $arr_ptr i32) (param $scratch_base i32) (param $cursor_addr i32)
    (local $len i32)
    (local $idx i32)
    (local $cur i32)
    (local $elem f64)
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
        ;; Load element at arr_ptr+8+idx*8 and convert to decimal string
        (local.set $elem (f64.load (i32.add (i32.add (local.get $arr_ptr) (i32.const 8)) (i32.shl (local.get $idx) (i32.const 3)))))
        (local.set $slen (call $__f64_to_str (local.get $elem) (i32.add (local.get $scratch_base) (local.get $cur))))
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

/**
 * Phase 28: Returns WAT helper functions that write arr.join(sep) output
 * into the scratch gather buffer.
 *
 * Signatures:
 *   $__dynarr_join_to_scratch_i32(arr, sep_ptr, sep_len, scratch_base, cursor_addr)
 *   $__dynarr_join_to_scratch_f64(arr, sep_ptr, sep_len, scratch_base, cursor_addr)
 * Depends on: $__i32_to_str / $__f64_to_str (from getHelperWat)
 */
export function getJoinHelperWat(): string {
  return `
  ;; ── join i32[] to scratch ──────────────────────────────────────────────────
  (func $__dynarr_join_to_scratch_i32
    (param $arr i32) (param $sep_ptr i32) (param $sep_len i32)
    (param $scratch_base i32) (param $cursor_addr i32)
    (local $len i32)
    (local $idx i32)
    (local $cur i32)
    (local $si i32)
    (local $slen i32)
    (local $elem i32)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $cur (i32.load (local.get $cursor_addr)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $idx) (local.get $len)))
        ;; Write separator before each element except the first
        (if (i32.gt_u (local.get $idx) (i32.const 0))
          (then
            (local.set $si (i32.const 0))
            (block $sep_done
              (loop $sep_lp
                (br_if $sep_done (i32.ge_u (local.get $si) (local.get $sep_len)))
                (i32.store8
                  (i32.add (i32.add (local.get $scratch_base) (local.get $cur)) (local.get $si))
                  (i32.load8_u (i32.add (local.get $sep_ptr) (local.get $si))))
                (local.set $si (i32.add (local.get $si) (i32.const 1)))
                (br $sep_lp)
              )
            )
            (local.set $cur (i32.add (local.get $cur) (local.get $sep_len)))
          )
        )
        ;; Convert element to decimal string and write into scratch
        (local.set $elem (i32.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $idx) (i32.const 2)))))
        (local.set $slen (call $__i32_to_str (local.get $elem) (i32.add (local.get $scratch_base) (local.get $cur))))
        (local.set $cur (i32.add (local.get $cur) (local.get $slen)))
        (local.set $idx (i32.add (local.get $idx) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.store (local.get $cursor_addr) (local.get $cur))
  )
  ;; ── join f64[] to scratch ──────────────────────────────────────────────────
  (func $__dynarr_join_to_scratch_f64
    (param $arr i32) (param $sep_ptr i32) (param $sep_len i32)
    (param $scratch_base i32) (param $cursor_addr i32)
    (local $len i32)
    (local $idx i32)
    (local $cur i32)
    (local $si i32)
    (local $slen i32)
    (local $elem f64)
    (local.set $len (i32.load (local.get $arr)))
    (local.set $cur (i32.load (local.get $cursor_addr)))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $idx) (local.get $len)))
        (if (i32.gt_u (local.get $idx) (i32.const 0))
          (then
            (local.set $si (i32.const 0))
            (block $sep_done
              (loop $sep_lp
                (br_if $sep_done (i32.ge_u (local.get $si) (local.get $sep_len)))
                (i32.store8
                  (i32.add (i32.add (local.get $scratch_base) (local.get $cur)) (local.get $si))
                  (i32.load8_u (i32.add (local.get $sep_ptr) (local.get $si))))
                (local.set $si (i32.add (local.get $si) (i32.const 1)))
                (br $sep_lp)
              )
            )
            (local.set $cur (i32.add (local.get $cur) (local.get $sep_len)))
          )
        )
        (local.set $elem (f64.load (i32.add (i32.add (local.get $arr) (i32.const 8)) (i32.shl (local.get $idx) (i32.const 3)))))
        (local.set $slen (call $__f64_to_str (local.get $elem) (i32.add (local.get $scratch_base) (local.get $cur))))
        (local.set $cur (i32.add (local.get $cur) (local.get $slen)))
        (local.set $idx (i32.add (local.get $idx) (i32.const 1)))
        (br $loop)
      )
    )
    (i32.store (local.get $cursor_addr) (local.get $cur))
  )
  ;; ── join → a real (ptr, len) STRING value ──────────────────────────────────
  ;; The two helpers above write into a caller-supplied scratch buffer, which only suits the
  ;; console.log gather path. These wrappers give arr.join(sep) a string VALUE, so it also works in
  ;; \`const s: string = arr.join(sep)\`, in concatenation and in comparisons. They reuse the scratch
  ;; writers verbatim (same tested loop) over a heap buffer plus a 4-byte cursor cell. Capacity is a
  ;; worst-case bound: an i32 renders in <= 11 bytes ("-2147483648"), an f64 (Dragon4) in well under
  ;; 32, plus one separator per element and slack.
  (func $__dynarr_join_str_i32
    (param $arr i32) (param $sep_ptr i32) (param $sep_len i32)
    (result i32 i32)
    (local $buf i32)
    (local $cursor i32)
    (local $n i32)
    (local.set $n (i32.load (local.get $arr)))
    (local.set $buf (call $__malloc
      (i32.add (i32.const 16)
        (i32.add (i32.mul (local.get $n) (i32.const 12))
                 (i32.mul (local.get $n) (local.get $sep_len))))))
    (local.set $cursor (call $__malloc (i32.const 4)))
    (i32.store (local.get $cursor) (i32.const 0))
    (call $__dynarr_join_to_scratch_i32
      (local.get $arr) (local.get $sep_ptr) (local.get $sep_len)
      (local.get $buf) (local.get $cursor))
    (local.get $buf)
    (i32.load (local.get $cursor))
  )
  (func $__dynarr_join_str_f64
    (param $arr i32) (param $sep_ptr i32) (param $sep_len i32)
    (result i32 i32)
    (local $buf i32)
    (local $cursor i32)
    (local $n i32)
    (local.set $n (i32.load (local.get $arr)))
    (local.set $buf (call $__malloc
      (i32.add (i32.const 16)
        (i32.add (i32.mul (local.get $n) (i32.const 32))
                 (i32.mul (local.get $n) (local.get $sep_len))))))
    (local.set $cursor (call $__malloc (i32.const 4)))
    (i32.store (local.get $cursor) (i32.const 0))
    (call $__dynarr_join_to_scratch_f64
      (local.get $arr) (local.get $sep_ptr) (local.get $sep_len)
      (local.get $buf) (local.get $cursor))
    (local.get $buf)
    (i32.load (local.get $cursor))
  )`;
}
