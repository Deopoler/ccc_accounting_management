import { parseDepositNotification } from './index.ts';

function assertDeepEqual(actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(`Assertion failed:\n  actual:   ${a}\n  expected: ${e}`);
  }
}

const assert = { deepEqual: assertDeepEqual };

const KAIST_CONFIG = { accountLabel: 'KAIST CCC' };

const raw = (title: string, text: string, appPackage = 'viva.republica.toss') => ({
  title,
  text,
  appPackage,
  timestamp: new Date('2026-11-26T03:00:00Z'),
});

Deno.test('toss: expected arrow format with amount in title', () => {
  const res = parseDepositNotification(
    'toss',
    raw('입금 10,000원', '홍길동 -> 내 KAIST CCC'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '홍길동', amount: 10000 });
});

Deno.test('toss: unicode arrow and amount in text with balance', () => {
  const res = parseDepositNotification(
    'toss',
    raw('토스뱅크', '김철수수련회 → 내 KAIST CCC 35,000원\n잔액 1,250,000원'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '김철수수련회', amount: 35000 });
});

Deno.test('toss: duplicate amount repeated in title and text still parses cleanly', () => {
  const res = parseDepositNotification(
    'toss',
    raw('15,000원 입금', '이영희 → 내 KAIST CCC 15,000원'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '이영희', amount: 15000 });
});

Deno.test('toss: Korean sentence format with 님이', () => {
  const res = parseDepositNotification(
    'toss',
    raw('토스뱅크 입금', '박민수님이 내 KAIST CCC 계좌로 20,000원 입금했어요.'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '박민수', amount: 20000 });
});

Deno.test('toss: bracketed account label format', () => {
  const res = parseDepositNotification(
    'toss',
    raw('', '[KAIST CCC] 최유리2024 12,500원 입금 잔액 500,000원', 'ios.shortcuts.sms'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '최유리2024', amount: 12500 });
});

Deno.test('toss: NFD Korean input and flexible label spacing', () => {
  const nfdName = '홍길동'.normalize('NFD');
  const res = parseDepositNotification(
    'toss',
    raw('입금 5,000원', `${nfdName} -> 내 kaist  ccc`),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '홍길동', amount: 5000 });
});

Deno.test('toss: ignores personal account notifications without campus label', () => {
  const res = parseDepositNotification(
    'toss',
    raw('입금 50,000원', '엄마 -> 내 토스뱅크 통장'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'ignored', reason: 'no_account_label' });
});

Deno.test('toss: ignores withdrawals, card approvals, and ads', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('출금 10,000원', '내 KAIST CCC -> 홍길동'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'withdrawal' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('결제 승인', 'KAIST CCC 체크카드 4,500원'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'withdrawal' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('(광고) 토스뱅크', 'KAIST CCC 특별 혜택 확인'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'ad' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('이체', '내 KAIST CCC -> 홍길동 10,000원'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'outgoing_transfer' },
  );
});

Deno.test('toss: returns unparsed when campus label matches but layout is unknown', () => {
  const noAmount = parseDepositNotification(
    'toss',
    raw('토스뱅크', 'KAIST CCC 계좌에 새 알림이 도착했습니다'),
    KAIST_CONFIG,
  );
  assert.deepEqual(noAmount, { kind: 'unparsed', reason: 'no_amount' });

  const noDepositor = parseDepositNotification(
    'toss',
    raw('KAIST CCC', '10,000원이 도착했어요'),
    KAIST_CONFIG,
  );
  assert.deepEqual(noDepositor, { kind: 'unparsed', reason: 'no_depositor' });

  const multiAmount = parseDepositNotification(
    'toss',
    raw('입금 10,000원', '홍길동 -> 내 KAIST CCC 수수료 500원'),
    KAIST_CONFIG,
  );
  assert.deepEqual(multiAmount, { kind: 'unparsed', reason: 'multiple_amounts' });
});

Deno.test('toss: ignores when accountLabel config is empty', () => {
  const res = parseDepositNotification(
    'toss',
    raw('입금 10,000원', '홍길동 -> 내 KAIST CCC'),
    { accountLabel: '   ' },
  );
  assert.deepEqual(res, { kind: 'ignored', reason: 'config_missing_label' });
});

Deno.test('registry: unsupported bank code returns unparsed', () => {
  const res = parseDepositNotification(
    'unknown_bank',
    raw('입금 10,000원', '홍길동 -> 내 KAIST CCC'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'unparsed', reason: 'unsupported_bank' });
});
