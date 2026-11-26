import { parseDepositNotification } from './index.ts';
import { computeDedupeHashes, getClientIp, parseIngestTimestamp } from './ingest_utils.ts';

function assertDeepEqual(actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(`Assertion failed:\n  actual:   ${a}\n  expected: ${e}`);
  }
}

function assertNotEqual(actual: unknown, expected: unknown): void {
  if (actual === expected) {
    throw new Error(`Expected values to differ, both were: ${JSON.stringify(actual)}`);
  }
}

const assert = { deepEqual: assertDeepEqual, notEqual: assertNotEqual };

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

Deno.test('toss: account-label gate runs first even on withdrawal or ad notifications', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 50,000원', '엄마 -> 내 토스뱅크 통장'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'no_account_label' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('출금 10,000원', '내 토스뱅크 -> 홍길동'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'no_account_label' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('(광고) 토스뱅크', '혜택을 확인하세요'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'no_account_label' },
  );
});

Deno.test('toss: structural withdrawals, outgoing transfers, and ad prefix are ignored when label matches', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('출금 10,000원', '내 KAIST CCC -> 홍길동'), KAIST_CONFIG),
    { kind: 'ignored', reason: 'outgoing_transfer' },
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

Deno.test('toss: keywords inside depositor name or memo are NOT dropped on label-matching notifications', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 10,000원', '홍길동카드취소 -> 내 KAIST CCC'), KAIST_CONFIG),
    { kind: 'deposit', depositorName: '홍길동카드취소', amount: 10000 },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 10,000원', '김광고혜택 -> 내 KAIST CCC'), KAIST_CONFIG),
    { kind: 'deposit', depositorName: '김광고혜택', amount: 10000 },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 10,000원', '이출금 -> 내 KAIST CCC'), KAIST_CONFIG),
    { kind: 'deposit', depositorName: '이출금', amount: 10000 },
  );
  // Unrecognized format with keyword + campus label becomes unparsed (not silently ignored).
  assert.deepEqual(
    parseDepositNotification('toss', raw('토스뱅크', 'KAIST CCC 환불 안내 10,000원'), KAIST_CONFIG),
    { kind: 'unparsed', reason: 'no_depositor' },
  );
});

Deno.test('toss: returns unparsed when campus label matches but layout is unknown', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('토스뱅크', 'KAIST CCC 계좌에 새 알림이 도착했습니다'), KAIST_CONFIG),
    { kind: 'unparsed', reason: 'no_amount' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('KAIST CCC', '10,000원이 도착했어요'), KAIST_CONFIG),
    { kind: 'unparsed', reason: 'no_depositor' },
  );
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 10,000원', '홍길동 -> 내 KAIST CCC 수수료 500원'), KAIST_CONFIG),
    { kind: 'unparsed', reason: 'multiple_amounts' },
  );
});

Deno.test('toss: ignores when accountLabel config is empty', () => {
  assert.deepEqual(
    parseDepositNotification('toss', raw('입금 10,000원', '홍길동 -> 내 KAIST CCC'), { accountLabel: '   ' }),
    { kind: 'ignored', reason: 'config_missing_label' },
  );
});

Deno.test('registry: unsupported bank code returns unparsed', () => {
  assert.deepEqual(
    parseDepositNotification('unknown_bank', raw('입금 10,000원', '홍길동 -> 내 KAIST CCC'), KAIST_CONFIG),
    { kind: 'unparsed', reason: 'unsupported_bank' },
  );
});

Deno.test('ingest_utils: offset-less timestamp strings are interpreted as Asia/Seoul (+09:00) and unknown formats fall back to server time', () => {
  const now = new Date('2026-11-26T06:00:00Z');

  for (const [input, expectedIso] of [
    ['2026-11-26 14:30:05', '2026-11-26T05:30:05.000Z'],
    ['2026-11-26T14:30', '2026-11-26T05:30:00.000Z'],
    ['2026/11/26 14:30:05', '2026-11-26T05:30:05.000Z'],
    ['2026/11/26 14:30', '2026-11-26T05:30:00.000Z'],
    ['2026.11.26 14:30:05', '2026-11-26T05:30:05.000Z'],
    ['2026.11.26 9:05', '2026-11-26T00:05:00.000Z'],
    ['2026-11-26T05:30:05Z', '2026-11-26T05:30:05.000Z'],
    ['2026-11-26T14:30:05+09:00', '2026-11-26T05:30:05.000Z'],
  ] as const) {
    const res = parseIngestTimestamp(input, now);
    assert.deepEqual(res.supplied, true);
    assert.deepEqual(res.date.toISOString(), expectedIso);
  }

  for (const unknown of [
    undefined,
    '',
    'Nov 26 2026 14:30:00',
    'Thu, 26 Nov 2026 05:30:00 GMT',
    '26/11/2026 14:30',
    '2026-11-26',
    '2026-02-30 10:00:00',
    'yesterday',
  ]) {
    const res = parseIngestTimestamp(unknown, now);
    assert.deepEqual(res.supplied, false);
    assert.deepEqual(res.date.toISOString(), now.toISOString());
  }
});

Deno.test('ingest_utils: getClientIp prefers cf-connecting-ip, else last x-forwarded-for entry', () => {
  assert.deepEqual(
    getClientIp(new Headers({
      'cf-connecting-ip': '203.0.113.10',
      'x-forwarded-for': '198.51.100.1, 198.51.100.2',
    })),
    '203.0.113.10',
  );
  assert.deepEqual(
    getClientIp(new Headers({
      'x-forwarded-for': '1.2.3.4, 5.6.7.8, 198.51.100.9 ',
    })),
    '198.51.100.9',
  );
  assert.deepEqual(
    getClientIp(new Headers({ 'x-forwarded-for': '  , 198.51.100.7 , ' })),
    '198.51.100.7',
  );
  assert.deepEqual(getClientIp(new Headers()), 'unknown');
});

Deno.test('ingest_utils: external_id reuse with different notification produces a distinct dedupe_key', async () => {
  const ts = new Date('2026-11-26T05:30:05Z');
  const first = await computeDedupeHashes({
    appPackage: 'viva.republica.toss',
    title: '입금 10,000원',
    text: '홍길동 -> 내 KAIST CCC',
    externalId: 'notif-42',
    depositedAt: ts,
    tsSupplied: true,
  });
  const exactRetry = await computeDedupeHashes({
    appPackage: 'viva.republica.toss',
    title: '입금 10,000원',
    text: '홍길동 -> 내 KAIST CCC',
    externalId: 'notif-42',
    depositedAt: ts,
    tsSupplied: true,
  });
  const reusedIdDifferentNotif = await computeDedupeHashes({
    appPackage: 'viva.republica.toss',
    title: '입금 20,000원',
    text: '김철수 -> 내 KAIST CCC',
    externalId: 'notif-42',
    depositedAt: ts,
    tsSupplied: true,
  });

  assert.deepEqual(first.dedupeKey, exactRetry.dedupeKey);
  assert.notEqual(first.dedupeKey, reusedIdDifferentNotif.dedupeKey);
});

// 실제 토스 모임통장 입금 알림 형식 (2026-11-27 확인): 제목 "N원 입금", 내용 "<이름> → 내 <별칭> 모임통장"
Deno.test('toss: real 모임통장 deposit notification', () => {
  const res = parseDepositNotification(
    'toss',
    raw('15,000원 입금', '김철수 → 내 KAIST CCC 모임통장'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'deposit', depositorName: '김철수', amount: 15000 });
});

Deno.test('toss: real format with masked name (self transfer) is unparsed', () => {
  const res = parseDepositNotification(
    'toss',
    raw('1원 입금', '**** → 내 KAIST CCC 모임통장'),
    KAIST_CONFIG,
  );
  assert.deepEqual(res, { kind: 'unparsed', reason: 'no_depositor' });
});

Deno.test('toss: title only (empty text variable) is ignored as no_account_label', () => {
  const res = parseDepositNotification('toss', raw('1원 입금', ''), KAIST_CONFIG);
  assert.deepEqual(res, { kind: 'ignored', reason: 'no_account_label' });
});
