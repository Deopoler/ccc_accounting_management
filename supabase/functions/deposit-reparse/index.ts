// deposit-reparse: admin-authenticated re-parsing of unparsed deposit notifications.

import { createClient } from 'npm:@supabase/supabase-js@2';
import { parseDepositNotification } from '../_shared/deposit-parsers/index.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BATCH = 100;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const fail = (status: number, error: string) => json(status, { error });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail(405, '허용되지 않는 요청입니다.');

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return fail(500, '서버 설정 오류입니다.');

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return fail(401, '로그인이 필요합니다.');

  const { data: caller, error: callerError } = await admin.auth.getUser(token);
  if (callerError || !caller.user) return fail(401, '로그인이 만료되었습니다. 다시 로그인해 주세요.');

  const { data: callerProfile } = await admin
    .from('profiles')
    .select('role, is_approved, campus_id, deactivated_at')
    .eq('id', caller.user.id)
    .maybeSingle();

  const isCentral = callerProfile?.role === 'central_admin';
  if (
    !callerProfile?.is_approved ||
    callerProfile.deactivated_at ||
    (!isCentral && callerProfile.role !== 'campus_admin')
  ) {
    return fail(403, '관리자만 사용할 수 있습니다.');
  }

  let body: { deposit_id?: unknown; campus_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, '요청 형식이 올바르지 않습니다.');
  }

  const depositId = typeof body.deposit_id === 'string' ? body.deposit_id : null;
  const campusId = typeof body.campus_id === 'string' ? body.campus_id : null;

  if (depositId && !UUID.test(depositId)) return fail(400, 'deposit_id 형식이 올바르지 않습니다.');
  if (campusId && !UUID.test(campusId)) return fail(400, 'campus_id 형식이 올바르지 않습니다.');
  if (!depositId && !campusId) return fail(400, 'deposit_id 또는 campus_id 를 지정해 주세요.');

  let rows: Array<{
    id: string;
    campus_id: string;
    deposited_at: string;
    raw_title: string | null;
    raw_text: string | null;
    raw_package: string | null;
  }> = [];

  const nowIso = new Date().toISOString();

  if (depositId) {
    const { data: row, error } = await admin
      .from('bank_deposits')
      .select('id, campus_id, status, deposited_at, raw_title, raw_text, raw_package, raw_expires_at')
      .eq('id', depositId)
      .maybeSingle();
    if (error) return fail(500, `입금 조회 실패: ${error.message}`);
    if (!row || (!isCentral && row.campus_id !== callerProfile.campus_id)) {
      return fail(404, '입금 내역을 찾을 수 없습니다.');
    }
    if (row.status !== 'unparsed') {
      return fail(400, '해석 실패 상태의 입금만 다시 해석할 수 있습니다.');
    }
    const expired = !row.raw_expires_at || row.raw_expires_at <= nowIso;
    if (expired || (!row.raw_text && !row.raw_title)) {
      return fail(400, '원문 보관 기간이 만료되어 다시 해석할 수 없습니다.');
    }
    rows = [row];
  } else {
    const targetCampus = campusId!;
    if (!isCentral && targetCampus !== callerProfile.campus_id) {
      return fail(403, '해당 캠퍼스를 관리할 권한이 없습니다.');
    }
    const { data, error } = await admin
      .from('bank_deposits')
      .select('id, campus_id, deposited_at, raw_title, raw_text, raw_package')
      .eq('campus_id', targetCampus)
      .eq('status', 'unparsed')
      .gt('raw_expires_at', nowIso)
      .not('raw_text', 'is', null)
      .order('received_at', { ascending: true })
      .limit(MAX_BATCH);
    if (error) return fail(500, `입금 목록 조회 실패: ${error.message}`);
    rows = data ?? [];
  }

  if (rows.length === 0) {
    return json(200, { ok: true, results: [] });
  }

  const targetCampusId = rows[0].campus_id;
  const { data: settings, error: settingsError } = await admin
    .from('campus_deposit_settings')
    .select('bank_code, account_label')
    .eq('campus_id', targetCampusId)
    .maybeSingle();
  if (settingsError || !settings) {
    return fail(400, '캠퍼스 입금 설정을 찾을 수 없습니다.');
  }

  const results: Array<{ deposit_id: string; status: string }> = [];
  for (const row of rows) {
    const parsed = parseDepositNotification(
      settings.bank_code,
      {
        title: row.raw_title ?? '',
        text: row.raw_text ?? '',
        appPackage: row.raw_package ?? '',
        timestamp: new Date(row.deposited_at),
      },
      { accountLabel: settings.account_label ?? '' },
    );

    const params: Record<string, unknown> = {
      p_deposit_id: row.id,
      p_parse_kind: parsed.kind,
    };
    if (parsed.kind === 'deposit') {
      params.p_depositor_name = parsed.depositorName;
      params.p_amount = parsed.amount;
    } else {
      params.p_reason = parsed.reason;
    }

    const { data: applied, error: applyError } = await admin.rpc('apply_deposit_reparse', params);
    if (applyError) return fail(500, `재해석 반영 실패: ${applyError.message}`);
    const out = Array.isArray(applied) ? applied[0] : applied;
    results.push({ deposit_id: row.id, status: out?.status ?? 'unparsed' });
  }

  return json(200, { ok: true, results });
});
