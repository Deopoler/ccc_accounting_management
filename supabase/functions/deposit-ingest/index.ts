// deposit-ingest: MacroDroid / iOS Shortcuts notification receiver.
// Authenticates via per-campus X-Deposit-Token (SHA-256 hash stored in DB).

import { createClient } from 'npm:@supabase/supabase-js@2';
import { parseDepositNotification } from '../_shared/deposit-parsers/index.ts';
import {
  computeDedupeHashes,
  getClientIp,
  normalizeForHash,
  parseIngestTimestamp,
  sha256Hex,
} from '../_shared/deposit-parsers/ingest_utils.ts';

const MAX_BODY_BYTES = 8 * 1024;
const MAX_TITLE_LEN = 300;
const MAX_TEXT_LEN = 1000;
const MAX_PACKAGE_LEN = 100;
const MAX_EXTERNAL_ID_LEN = 128;

const AUTH_FAIL_WINDOW_MS = 60 * 1000;
const AUTH_FAIL_LIMIT = 20;
const authFailuresByIp = new Map<string, number[]>();

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-deposit-token',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const fail = (status: number, error: string) => json(status, { ok: false, error });

function isAuthRateLimited(ip: string, nowMs: number): boolean {
  const recent = (authFailuresByIp.get(ip) ?? []).filter((t) => nowMs - t < AUTH_FAIL_WINDOW_MS);
  if (recent.length === 0) {
    authFailuresByIp.delete(ip);
    return false;
  }
  authFailuresByIp.set(ip, recent);
  return recent.length >= AUTH_FAIL_LIMIT;
}

function recordAuthFailure(ip: string, nowMs: number): boolean {
  const recent = (authFailuresByIp.get(ip) ?? []).filter((t) => nowMs - t < AUTH_FAIL_WINDOW_MS);
  recent.push(nowMs);
  authFailuresByIp.set(ip, recent);
  if (authFailuresByIp.size > 1000) {
    for (const [k, times] of authFailuresByIp.entries()) {
      if (times.every((t) => nowMs - t >= AUTH_FAIL_WINDOW_MS)) {
        authFailuresByIp.delete(k);
      }
    }
  }
  return recent.length > AUTH_FAIL_LIMIT;
}

async function readBodyWithLimit(
  req: Request,
  maxBytes: number,
): Promise<{ ok: true; text: string } | { ok: false; status: number; error: string }> {
  const contentLength = Number(req.headers.get('content-length') ?? '0');
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return { ok: false, status: 413, error: '요청 크기가 제한을 초과했습니다.' };
  }

  const stream = req.body;
  if (!stream) return { ok: true, text: '' };

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        return { ok: false, status: 413, error: '요청 크기가 제한을 초과했습니다.' };
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false, status: 400, error: '요청 본문을 읽을 수 없습니다.' };
  } finally {
    reader.releaseLock();
  }

  const merged = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.byteLength;
  }
  return { ok: true, text: new TextDecoder().decode(merged) };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail(405, '허용되지 않는 요청입니다.');

  const now = new Date();
  const ip = getClientIp(req.headers);

  // Verify the token before reading the request body; valid tokens are never blocked by per-IP auth limits.
  const token = req.headers.get('x-deposit-token')?.trim() ?? '';
  if (!token || token.length > 200) {
    if (isAuthRateLimited(ip, now.getTime()) || recordAuthFailure(ip, now.getTime())) {
      return fail(429, '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.');
    }
    return fail(401, '인증 토큰이 필요합니다.');
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return fail(500, '서버 설정 오류입니다.');

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const tokenHash = await sha256Hex(token);
  const { data: settings, error: settingsError } = await admin
    .from('campus_deposit_settings')
    .select('campus_id, enabled, bank_code, account_label')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (settingsError) return fail(500, '설정을 확인하지 못했습니다.');
  if (!settings) {
    if (isAuthRateLimited(ip, now.getTime()) || recordAuthFailure(ip, now.getTime())) {
      return fail(429, '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.');
    }
    return fail(401, '유효하지 않은 토큰입니다.');
  }
  if (!settings.enabled || !settings.account_label?.trim()) {
    return fail(403, '자동 입금 확인이 비활성화되어 있습니다.');
  }

  const bodyResult = await readBodyWithLimit(req, MAX_BODY_BYTES);
  if (!bodyResult.ok) return fail(bodyResult.status, bodyResult.error);

  let body: Record<string, unknown>;
  try {
    const parsed = JSON.parse(bodyResult.text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return fail(400, 'JSON 형식이 올바르지 않습니다.');
  }

  if (body.ping === true) {
    const { data, error } = await admin.rpc('ingest_bank_deposit', {
      p_campus_id: settings.campus_id,
      p_parse_kind: 'ping',
      p_bank_code: settings.bank_code,
    });
    if (error) return fail(500, `처리 실패: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    if (row?.status === 'rate_limited') return fail(429, '요청 한도를 초과했습니다.');
    if (row?.status === 'disabled') return fail(403, '자동 입금 확인이 비활성화되어 있습니다.');
    return json(200, { ok: true, status: row?.status ?? 'pong' });
  }

  const title = typeof body.title === 'string' ? body.title : '';
  const text = typeof body.text === 'string' ? body.text : '';
  const appPackage = typeof body.app_package === 'string' ? body.app_package.trim() : '';
  const externalId = typeof body.external_id === 'string' ? body.external_id.trim() : '';

  if (title.length > MAX_TITLE_LEN) return fail(400, 'title 길이가 제한을 초과했습니다.');
  if (!text.trim() || text.length > MAX_TEXT_LEN) {
    return fail(400, 'text 는 1자 이상 1000자 이하로 보내 주세요.');
  }
  if (appPackage.length > MAX_PACKAGE_LEN) return fail(400, 'app_package 길이가 제한을 초과했습니다.');
  if (externalId.length > MAX_EXTERNAL_ID_LEN) return fail(400, 'external_id 길이가 제한을 초과했습니다.');

  const { date: depositedAt, supplied: tsSupplied } = parseIngestTimestamp(body.timestamp, now);
  const { rawHash, dedupeKey } = await computeDedupeHashes({
    appPackage,
    title,
    text,
    externalId,
    depositedAt,
    tsSupplied,
  });

  const parsed = parseDepositNotification(
    settings.bank_code,
    { title, text, appPackage, timestamp: depositedAt },
    { accountLabel: settings.account_label },
  );

  const rpcParams: Record<string, unknown> = {
    p_campus_id: settings.campus_id,
    p_parse_kind: parsed.kind,
    p_bank_code: settings.bank_code,
    p_dedupe_key: dedupeKey,
    p_raw_hash: rawHash,
    p_deposited_at: depositedAt.toISOString(),
  };

  if (parsed.kind === 'deposit') {
    rpcParams.p_depositor_name = parsed.depositorName;
    rpcParams.p_amount = parsed.amount;
  } else if (parsed.kind === 'unparsed') {
    rpcParams.p_raw_title = normalizeForHash(title);
    rpcParams.p_raw_text = normalizeForHash(text);
    rpcParams.p_raw_package = appPackage;
    rpcParams.p_reason = parsed.reason;
  } else {
    rpcParams.p_reason = parsed.reason;
  }

  const { data, error } = await admin.rpc('ingest_bank_deposit', rpcParams);
  if (error) return fail(500, `입금 처리 실패: ${error.message}`);

  const row = Array.isArray(data) ? data[0] : data;
  const status = row?.status as string | undefined;
  if (status === 'rate_limited') return fail(429, '요청 한도를 초과했습니다.');
  if (status === 'disabled') return fail(403, '자동 입금 확인이 비활성화되어 있습니다.');

  return json(200, {
    ok: true,
    status: status ?? 'ignored',
    ...(row?.deposit_id ? { deposit_id: row.deposit_id } : {}),
  });
});
