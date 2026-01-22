/**
 * @module args
 * @description Utilities for parsing and validating command-line arguments for the wasmtk CLI.
 */

import { parse } from "@std/flags";

/**
 * Interface representing the parsed CLI arguments.
 */
export interface WasmtkArgs {
  /** The primary command (e.g., 'compile', 'run'). */
  command: string;
  /** The target file path. */
  target: string;
  /** Additional positional arguments. */
  extra: string[];
  /** Whether the version flag was passed. */
  showVersion: boolean;
}

/**
 * Parses raw Deno arguments into a structured format.
 * @param rawArgs - The `Deno.args` array.
 * @returns A structured WasmtkArgs object.
 */
export function parseWasmtkArgs(rawArgs: string[]): WasmtkArgs {
  const parsed = parse(rawArgs, {
    alias: { v: "version" },
    boolean: ["version"],
  });

  return {
    command: String(parsed._[0] || ""),
    target: String(parsed._[1] || ""),
    extra: parsed._.slice(2).map(String),
    showVersion: !!parsed.version,
  };
}