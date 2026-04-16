/**
 * @module args
 * @description Utilities for parsing and validating command-line arguments using the modern Deno Standard Library.
 */

import { parseArgs } from "@std/cli/parse-args";

/**
 * Interface representing the parsed CLI arguments for the toolkit.
 */
export interface WasmtkArgs {
  /** The primary command (e.g., 'compile', 'run', 'info'). */
  command: string;
  /** The target file path or module name. */
  target: string;
  /** Additional positional arguments passed after the target. */
  extra: string[];
  /** Flag indicating if the version information should be displayed. */
  showVersion: boolean;
}

/**
 * Parses raw CLI arguments into a structured WasmtkArgs object.
 * Uses the modern `@std/cli/parse-args` implementation.
 * * @example
 * ```ts
 * const args = parseWasmtkArgs(Deno.args);
 * if (args.command === "run") {
 * executeWasm(args.target, args.extra);
 * }
 * ```
 * * @param rawArgs - Typically `Deno.args`.
 * @returns A structured and typed argument object.
 */
export function parseWasmtkArgs(rawArgs: string[]): WasmtkArgs {
  const parsed = parseArgs(rawArgs, {
    alias: { v: "version" },
    boolean: ["version"],
    stopEarly: false,
  });

  // Extract positional arguments
  const [command, target, ...extra] = parsed._;

  return {
    command: String(command || ""),
    target: String(target || ""),
    extra: extra.map(String),
    showVersion: !!parsed.version,
  };
}