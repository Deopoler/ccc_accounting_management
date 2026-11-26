import type { BankParser, ParseResult, ParserConfig, RawNotification } from './types.ts';

const MAX_AMOUNT = 100_000_000;
const ARROWS = /(?:->|→|➜|➡|▶)/;

const AD_KEYWORDS = [
  '(광고)',
  '[광고]',
  '광고',
  '혜택',
  '캐시백',
  '쿠폰',
  '포인트 적립',
  '이벤트 안내',
];

const WITHDRAWAL_KEYWORDS = [
  '출금',
  '결제',
  '승인',
  '보냈어요',
  '송금했어요',
  '이체 완료',
  '이체완료',
  '자동이체',
  '카드',
  '취소',
  '환불',
];

const GENERIC_NON_NAMES = new Set([
  '토스',
  '토스뱅크',
  'toss',
  '입금',
  '계좌',
  '알림',
  '내',
  '내계좌',
]);

function normalizeText(input: string): string {
  return input.normalize('NFC').replace(/\r\n?/g, '\n').trim();
}

function compactLower(input: string): string {
  return input.normalize('NFC').replace(/\s+/g, '').toLowerCase();
}

function escapeRegExp(input: string): string {
  return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildFlexibleLabelPattern(label: string): string {
  return label
    .normalize('NFC')
    .trim()
    .split(/\s+/)
    .map(escapeRegExp)
    .join('\\s*');
}

function cleanDepositorCandidate(raw: string): string {
  let s = raw.normalize('NFC').trim();
  // Remove leading app/bank tags, deposit markers, or amounts on the same line.
  let prev = '';
  while (s !== prev) {
    prev = s;
    s = s
      .replace(/^\[[^\]]{1,20}\]\s*/, '')
      .replace(/^(?:토스뱅크|토스|입금)\s*[:：·\-]?\s*/i, '')
      .replace(/^(?:\d{1,3}(?:,\d{3})+|\d+)\s*원\s*/, '')
      .replace(/^[:：·\-•|]+\s*/, '')
      .replace(/\s*[:：·\-•|]+$/, '')
      .trim();
  }
  s = s.replace(/\s+/g, ' ').trim();
  return s;
}

function isValidDepositorName(name: string): boolean {
  if (!name || name.length > 50) return false;
  if (/^[\d,\s]+원?$/.test(name)) return false;
  if (!/[가-힣A-Za-z0-9]/.test(name)) return false;
  if (GENERIC_NON_NAMES.has(compactLower(name))) return false;
  return true;
}

function extractAmount(combined: string): { ok: true; amount: number } | { ok: false; reason: string; ignored?: boolean } {
  const withoutBalance = combined.replace(/잔액\s*[\d,]+\s*원/g, '');
  if (/-\s*(?:\d{1,3}(?:,\d{3})+|\d+)\s*원/.test(withoutBalance)) {
    return { ok: false, reason: 'withdrawal', ignored: true };
  }

  const amounts = new Set<number>();
  const re = /(\d{1,3}(?:,\d{3})+|\d+)\s*원/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(withoutBalance)) !== null) {
    const value = Number(match[1].replace(/,/g, ''));
    if (Number.isSafeInteger(value)) {
      amounts.add(value);
    }
  }

  if (amounts.size === 0) return { ok: false, reason: 'no_amount' };
  if (amounts.size > 1) return { ok: false, reason: 'multiple_amounts' };

  const [amount] = amounts;
  if (amount <= 0 || amount > MAX_AMOUNT) {
    return { ok: false, reason: 'invalid_amount' };
  }
  return { ok: true, amount };
}

function extractDepositorName(combined: string, accountLabel: string): string | null {
  const lines = combined.split('\n').map((l) => l.trim()).filter(Boolean);
  const labelPattern = buildFlexibleLabelPattern(accountLabel);

  // Pattern 1: "<depositor> -> 내 <accountLabel>" (primary expected Toss format).
  const arrowRe = new RegExp(
    `^(.*?)\\s*(?:->|→|➜|➡|▶)\\s*(?:내\\s*)?${labelPattern}(?:\\s|$|\\b|계좌|통장|모임)`,
    'i',
  );
  for (const line of lines) {
    const m = line.match(arrowRe);
    if (m) {
      const cleaned = cleanDepositorCandidate(m[1]);
      if (isValidDepositorName(cleaned)) return cleaned;
    }
  }

  if (combined.includes('입금')) {
    // Pattern 2: "<depositor>님이 ... 입금".
    for (const line of lines) {
      const m = line.match(/^(.{1,60}?)\s*님이(?:\s|$)/);
      if (m) {
        const cleaned = cleanDepositorCandidate(m[1]);
        if (isValidDepositorName(cleaned)) return cleaned;
      }
    }

    // Pattern 3: "[<accountLabel>] <depositor> 10,000원 입금" or "<accountLabel> 입금 10,000원 <depositor>".
    const labelStripRe = new RegExp(`(?:내\\s*)?${labelPattern}(?:\\s*(?:계좌|통장))?`, 'gi');
    for (const line of lines) {
      const stripped = line
        .replace(labelStripRe, ' ')
        .replace(/잔액\s*[\d,]+\s*원/g, ' ')
        .trim();

      const beforeDeposit = stripped.match(/^(.*?)\s+(?:\d{1,3}(?:,\d{3})+|\d+)\s*원\s*입금/);
      if (beforeDeposit) {
        const cleaned = cleanDepositorCandidate(beforeDeposit[1]);
        if (isValidDepositorName(cleaned)) return cleaned;
      }

      const afterDeposit = stripped.match(/입금\s+(?:(?:\d{1,3}(?:,\d{3})+|\d+)\s*원\s+)?(.+)$/);
      if (afterDeposit) {
        const cleaned = cleanDepositorCandidate(afterDeposit[1]);
        if (isValidDepositorName(cleaned)) return cleaned;
      }
    }
  }

  return null;
}

export const tossParser: BankParser = {
  bankCode: 'toss',
  parse(raw: RawNotification, config: ParserConfig): ParseResult {
    const label = normalizeText(config.accountLabel);
    if (!label) {
      return { kind: 'ignored', reason: 'config_missing_label' };
    }

    const title = normalizeText(raw.title);
    const text = normalizeText(raw.text);
    const combined = [title, text].filter(Boolean).join('\n');
    if (!combined) {
      return { kind: 'ignored', reason: 'empty' };
    }

    const compact = compactLower(combined);

    if (AD_KEYWORDS.some((kw) => compact.includes(compactLower(kw)))) {
      return { kind: 'ignored', reason: 'ad' };
    }

    if (WITHDRAWAL_KEYWORDS.some((kw) => compact.includes(compactLower(kw)))) {
      return { kind: 'ignored', reason: 'withdrawal' };
    }

    // Privacy gate: drop notifications that do not mention the configured campus account label.
    const compactLabel = compactLower(label);
    if (!compact.includes(compactLabel)) {
      return { kind: 'ignored', reason: 'no_account_label' };
    }

    // Reject outgoing transfers where the campus account appears before the arrow.
    for (const line of combined.split('\n')) {
      if (!ARROWS.test(line)) continue;
      const [left, right = ''] = line.split(ARROWS);
      if (compactLower(left).includes(compactLabel) && !compactLower(right).includes(compactLabel)) {
        return { kind: 'ignored', reason: 'outgoing_transfer' };
      }
    }

    const amountResult = extractAmount(combined);
    if (!amountResult.ok) {
      if (amountResult.ignored) {
        return { kind: 'ignored', reason: amountResult.reason };
      }
      return { kind: 'unparsed', reason: amountResult.reason };
    }

    const depositorName = extractDepositorName(combined, label);
    if (!depositorName) {
      return { kind: 'unparsed', reason: 'no_depositor' };
    }

    return {
      kind: 'deposit',
      depositorName,
      amount: amountResult.amount,
    };
  },
};
