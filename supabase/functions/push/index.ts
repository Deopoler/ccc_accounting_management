// =============================================================================
// push: 관리자 기기로 웹 푸시 보내기
//
//   GET                                       VAPID 공개 키 (앱이 구독할 때 사용)
//   POST { type: "signup", profile_id }       가입 신청 알림. DB 가입 트리거(pg_net)만 호출한다.
//        헤더 x-push-secret: PUSH_WEBHOOK_SECRET
//
// 받는 사람: 가입한 캠퍼스의 캠퍼스 관리자 + 총괄 관리자 중 이 기기에서 알림을 켠 사람.
// 만료된 구독(404 / 410)은 지운다.
//
// 보안
//   * POST 는 secret 이 맞아야 한다. 내용은 요청 본문이 아니라 DB 에서 다시 읽으므로,
//     secret 이 새더라도 실제 승인 대기 중인 가입의 알림을 다시 보내는 것밖에 못 한다.
//   * VAPID 개인 키 / secret 은 Edge Function secret 에만 있다.
//
// secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, PUSH_WEBHOOK_SECRET, VAPID_SUBJECT(선택, mailto: 또는 https:)
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const fail = (status: number, error: string) => json(status, { error });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 길이가 같을 때 걸리는 시간이 내용과 무관한 비교. */
function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY');
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!publicKey || !privateKey) return fail(500, '푸시 알림이 설정되지 않았습니다. (VAPID 키)');

  if (req.method === 'GET') return json(200, { publicKey });
  if (req.method !== 'POST') return fail(405, '허용되지 않는 요청입니다.');

  // ---- 호출자 검증 (DB 트리거) ------------------------------------------------
  const secret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!secret) return fail(500, '서버 설정 오류입니다. (PUSH_WEBHOOK_SECRET)');
  if (!safeEqual(req.headers.get('x-push-secret') ?? '', secret)) {
    return fail(401, '허용되지 않는 요청입니다.');
  }

  let body: { type?: unknown; profile_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, '요청 형식이 올바르지 않습니다.');
  }
  if (body.type !== 'signup' || typeof body.profile_id !== 'string' || !UUID.test(body.profile_id)) {
    return fail(400, '요청 형식이 올바르지 않습니다.');
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return fail(500, '서버 설정 오류입니다. (service role)');
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ---- 알림 내용 -------------------------------------------------------------
  const { data: signup } = await admin
    .from('profiles')
    .select('student_id, name, is_approved, campus_id, campuses(name)')
    .eq('id', body.profile_id)
    .maybeSingle();
  // 이미 승인 / 거절된 가입이면 보내지 않는다.
  if (!signup || signup.is_approved) return json(200, { sent: 0 });

  const campusName = (signup.campuses as { name?: string } | null)?.name ?? '';
  const payload = JSON.stringify({
    title: '새 가입 신청',
    body: `${campusName ? `${campusName} · ` : ''}${signup.name}(${signup.student_id}) 님이 가입을 신청했습니다.`,
    url: 'admin/members',
    tag: `signup-${body.profile_id}`,
  });

  // ---- 받는 사람 ---------------------------------------------------------------
  const { data: admins, error: adminsError } = await admin
    .from('profiles')
    .select('id')
    .eq('is_approved', true)
    .or(`role.eq.central_admin,and(role.eq.campus_admin,campus_id.eq.${signup.campus_id})`);
  if (adminsError) return fail(500, `관리자 조회 실패: ${adminsError.message}`);
  if (!admins?.length) return json(200, { sent: 0 });

  const { data: subs, error: subsError } = await admin
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .in('user_id', admins.map((a) => a.id));
  if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);

  // ---- 보내기 ----------------------------------------------------------------
  const vapidDetails = {
    subject: Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@example.com',
    publicKey,
    privateKey,
  };
  const expired: string[] = [];
  let sent = 0;
  await Promise.all(
    (subs ?? []).map(async (s) => {
      try {
        // web-push 는 암호화 / VAPID 서명만 쓰고, 전송은 Deno 의 fetch 로 한다.
        const r = webpush.generateRequestDetails(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
          { vapidDetails, TTL: 24 * 60 * 60, urgency: 'high' },
        );
        const res = await fetch(r.endpoint, { method: r.method, headers: r.headers, body: r.body });
        if (res.status === 404 || res.status === 410) expired.push(s.id);
        else if (res.ok) sent++;
        else console.warn('push 실패', res.status, await res.text());
      } catch (e) {
        console.warn('push 오류', e);
      }
    }),
  );
  if (expired.length) await admin.from('push_subscriptions').delete().in('id', expired);

  return json(200, { sent, expired: expired.length });
});
