export interface RawNotification {
  title: string;
  text: string;
  appPackage: string;
  timestamp: Date;
}

export interface ParserConfig {
  accountLabel: string;
}

export type ParseResult =
  | { kind: 'deposit'; depositorName: string; amount: number }
  | { kind: 'ignored'; reason: string }
  | { kind: 'unparsed'; reason: string };

export interface BankParser {
  readonly bankCode: string;
  parse(raw: RawNotification, config: ParserConfig): ParseResult;
}
