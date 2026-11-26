import { tossParser } from './toss.ts';
import type { BankParser, ParseResult, ParserConfig, RawNotification } from './types.ts';

export type { BankParser, ParseResult, ParserConfig, RawNotification } from './types.ts';

const PARSERS: ReadonlyMap<string, BankParser> = new Map([
  [tossParser.bankCode, tossParser],
]);

export function getBankParser(bankCode: string): BankParser | null {
  return PARSERS.get(bankCode) ?? null;
}

export function parseDepositNotification(
  bankCode: string,
  raw: RawNotification,
  config: ParserConfig,
): ParseResult {
  const parser = getBankParser(bankCode);
  if (!parser) {
    return { kind: 'unparsed', reason: 'unsupported_bank' };
  }
  return parser.parse(raw, config);
}
