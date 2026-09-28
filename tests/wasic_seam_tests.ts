/**
 * wasic_seam_tests.ts — the `ts2wasm` seam gate (H12, 2026-09-28)
 *
 * The compiler CORE (today the `WasicTranspiler` class body in src/wasic.ts; after the
 * modularization, every module under the core tree) must be PURE: source text in, WAT + diagnostics
 * out. It must not touch the host or the backend, because it is what a future binaryang `./ts2wasm`
 * import will cross. See cmem/wasic-modularization-plan.md § "H12 update".
 *
 * Forbidden in core CODE (strings and comments are ignored; WAT templates legitimately contain
 * words like `console.log`):
 *   rt.*  Deno.*  process.exit  console.log/error/warn/info/debug  wabt  binaryen.*
 *   mergeWasmWat  mergeOneWasmImport  bundleImportsEx
 *
 * The scanner is its own: varscope's `maskCode` reads a `"` inside a REGEX literal as a string start,
 * and wasic.ts is full of regexes, so it could desync and silently blank real code: a gate that
 * passes because it stopped looking. Two self-checks guard this one: synthetic cases, and a
 * desync detector (every `this.diagnostics.push(` in the real file must survive masking).
 *
 * Usage:
 *   deno run --allow-read tests/wasic_seam_tests.ts
 *
 * @license MIT
 */

import { join } from "jsr:@std/path";

const SRC = join(import.meta.dirname!, "..", "src");

let passed = 0;
let failed = 0;
function ok(desc: string, cond: boolean, detail = ""): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${desc}`);
  } else {
    failed++;
    console.error(`  ✗ ${desc}${detail ? `\n${detail}` : ""}`);
  }
}

/**
 * Blank every comment, string, regex literal and template TEXT with spaces (newlines kept, so line
 * numbers survive), while keeping template `${…}` interpolations as code.
 */
export function maskNonCode(src: string): string {
  const out = src.split("");
  const n = src.length;
  let i = 0;
  const blank = (from: number, to: number) => {
    for (let k = from; k < to && k < n; k++) if (out[k] !== "\n") out[k] = " ";
  };
  // A `/` starts a regex when the previous significant character cannot end an expression. Look
  // back through the MASKED output (`out`), where earlier comments and strings are already blank:
  // looking at `src` saw a trailing `// comment`'s last character instead of the real token (`||`)
  // and misread the next line's regex as division (caught by the desync detector, 2026-09-28).
  const regexCanStart = (pos: number): boolean => {
    let j = pos - 1;
    while (j >= 0 && /\s/.test(out[j])) j--;
    if (j < 0) return true;
    if ("(,=:[!&|?{};+-*%<>~^".includes(out[j])) return true;
    const word = /([A-Za-z_$][\w$]*)$/.exec(out.slice(Math.max(0, j - 10), j + 1).join(""));
    return !!word &&
      ["return", "typeof", "case", "in", "of", "delete", "void", "throw"].includes(word[1]);
  };
  const skipString = (q: string): void => { // i at the opening quote
    const start = i++;
    while (i < n && src[i] !== q) i += src[i] === "\\" ? 2 : 1;
    i++;
    blank(start, i);
  };
  const skipTemplate = (): void => { // i at the opening backtick
    let textStart = i++;
    while (i < n) {
      if (src[i] === "\\") {
        i += 2;
        continue;
      }
      if (src[i] === "`") {
        i++;
        blank(textStart, i);
        return;
      }
      if (src[i] === "$" && src[i + 1] === "{") {
        blank(textStart, i + 2);
        i += 2;
        scanCode("}"); // interpolation is CODE
        textStart = i; // at the closing `}`
        continue;
      }
      i++;
    }
    blank(textStart, i);
  };
  const scanCode = (stopAt: string | null): void => {
    let depth = 0;
    while (i < n) {
      const c = src[i];
      if (c === "/" && src[i + 1] === "/") {
        const s = i;
        while (i < n && src[i] !== "\n") i++;
        blank(s, i);
      } else if (c === "/" && src[i + 1] === "*") {
        const s = i;
        i = src.indexOf("*/", i + 2);
        i = i === -1 ? n : i + 2;
        blank(s, i);
      } else if (c === '"' || c === "'") skipString(c);
      else if (c === "`") skipTemplate();
      else if (c === "/" && regexCanStart(i)) {
        const s = i++;
        let inClass = false;
        while (i < n && src[i] !== "\n") {
          if (src[i] === "\\") {
            i += 2;
            continue;
          }
          if (src[i] === "[") inClass = true;
          else if (src[i] === "]") inClass = false;
          else if (src[i] === "/" && !inClass) break;
          i++;
        }
        i++;
        while (i < n && /[a-z]/.test(src[i])) i++; // flags
        blank(s, i);
      } else if (stopAt !== null && c === "{") {
        depth++;
        i++;
      } else if (stopAt !== null && c === stopAt && depth === 0) {
        i++; // consume the closing `}` of an interpolation
        return;
      } else {
        if (stopAt !== null && c === "}") depth--;
        i++;
      }
    }
  };
  scanCode(null);
  return out.join("");
}

const FORBIDDEN: [string, RegExp][] = [
  ["rt.* (host I/O)", /\brt\.[A-Za-z]/],
  ["Deno.*", /\bDeno\.[A-Za-z]/],
  ["process.exit", /\bprocess\.exit\b/],
  ["console.*", /\bconsole\.(log|error|warn|info|debug)\b/],
  ["wabt (assembler)", /\bwabt\b/],
  ["binaryen.* (optimiser)", /\bbinaryen\.[A-Za-z]/],
  ["merge (back edge)", /\bmerge(WasmWat|OneWasmImport)\b/],
  ["bundler (front edge)", /\bbundleImportsEx\b/],
];

/** Forbidden host/backend accesses in already-masked code, as `line N: kind` strings. */
export function violations(masked: string, firstLine: number): string[] {
  const found: string[] = [];
  masked.split("\n").forEach((line, k) => {
    for (const [name, re] of FORBIDDEN) {
      if (re.test(line)) found.push(`    line ${firstLine + k}: ${name}`);
    }
  });
  return found;
}

function main(): void {
  console.log("── scanner self-checks ───────────────────────────────────────");
  const selfCases: [string, string, boolean][] = [
    ["a regex with a quote does not hide later code", 'const r = /"x/; rt.exit(1);', true],
    ["code in a template interpolation is checked", "const s = `a ${rt.exit(1)} b`;", true],
    ["a forbidden word in a string is ignored", 'const s = "console.log(1)";', false],
    ["a forbidden word in a comment is ignored", "// rt.exit(1)\nconst x = 1;", false],
    ["a forbidden word in template TEXT is ignored", "const s = `;; console.log helper`;", false],
    ["division is not mistaken for a regex", "const a = b / c; rt.exit(1); const d = e / f;", true],
    [
      "a regex after a line ending in a comment is still a regex",
      "const ok = a ||  // note: `x`\n  /^[\"']/.test(t);\nrt.exit(1);",
      true,
    ],
  ];
  for (const [desc, code, shouldFlag] of selfCases) {
    ok(desc, (violations(maskNonCode(code), 1).length > 0) === shouldFlag);
  }

  console.log("── core seam: WasicTranspiler body ───────────────────────────");
  const src = Deno.readTextFileSync(join(SRC, "wasic.ts"));
  const lines = src.split("\n");
  const start = lines.findIndex((l) => /^(export )?class WasicTranspiler\b/.test(l));
  let end = -1;
  for (let k = start + 1; k < lines.length; k++) {
    if (/^}/.test(lines[k])) {
      end = k;
      break;
    }
  }
  ok("class WasicTranspiler located", start >= 0 && end > start);
  const masked = maskNonCode(src).split("\n").slice(start, end + 1).join("\n");

  // Desync detector: `this.diagnostics.push(` is always code; if masking desynced, some vanish.
  const rawBody = lines.slice(start, end + 1).join("\n");
  const rawPushes = (rawBody.match(/this\.diagnostics\.push\(/g) ?? []).length;
  const maskedPushes = (masked.match(/this\.diagnostics\.push\(/g) ?? []).length;
  ok(
    `masking kept all ${rawPushes} this.diagnostics.push( sites (no desync)`,
    rawPushes > 0 && maskedPushes === rawPushes,
    `    raw ${rawPushes}, after masking ${maskedPushes}`,
  );

  const found = violations(masked, start + 1);
  ok("no host or backend access in the core", found.length === 0, found.join("\n"));

  // After Phase 1, core modules live under src/wasic/ (the back edge under src/wasic/link/).
  let coreFiles: string[] = [];
  try {
    coreFiles = [...Deno.readDirSync(join(SRC, "wasic"))].filter((e) =>
      e.isFile && e.name.endsWith(".ts")
    )
      .map((e) => join(SRC, "wasic", e.name));
  } catch { /* not extracted yet */ }
  for (const f of coreFiles) {
    const v = violations(maskNonCode(Deno.readTextFileSync(f)), 1);
    ok(`core module ${f.split(/[\\/]/).pop()} is pure`, v.length === 0, v.join("\n"));
  }
}

if (import.meta.main) {
  main();
  console.log(`\n  ${passed} passed, ${failed} failed`);
  if (failed > 0) Deno.exit(1);
}
