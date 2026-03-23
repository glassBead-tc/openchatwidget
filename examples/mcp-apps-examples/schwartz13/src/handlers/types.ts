import type { Exa } from 'exa-js';

export type ToolResult = {
  content: Array<{ type: 'text'; text: string }>;
  isError?: boolean;
};

export type OperationHandler = (
  args: Record<string, unknown>,
  exa: Exa
) => Promise<ToolResult>;

export function successResult(data: unknown): ToolResult {
  return {
    content: [{ type: 'text', text: JSON.stringify(data, null, 2) }],
  };
}

export function errorResult(operation: string, error: unknown, hints?: string): ToolResult {
  const message = error instanceof Error ? error.message : String(error);
  let text = `Error in ${operation}: ${message}`;
  if (hints) text += `\n\n${hints}`;
  return {
    content: [{ type: 'text', text }],
    isError: true,
  };
}

export function requireParams(operation: string, args: Record<string, unknown>, ...names: string[]): ToolResult | null {
  const missing = names.filter(n => args[n] === undefined || args[n] === null);
  if (missing.length === 0) return null;
  return {
    content: [{ type: 'text', text: `Missing required parameter(s) for ${operation}: ${missing.join(', ')}` }],
    isError: true,
  };
}

export function validationError(message: string): ToolResult {
  return {
    content: [{ type: 'text', text: message }],
    isError: true,
  };
}
