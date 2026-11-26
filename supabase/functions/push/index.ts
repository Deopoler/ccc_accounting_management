// =============================================================================
// push: 웹 푸시 알림 보내기
//
//   GET                                                 VAPID 공개 키 (앱이 구독할 때 사용)
//   POST { type: "signup", profile_id }                 가입 신청 알림 (관리자에게)
//   POST { type: "order_shipped", user_id, order_ids }  교재 도착 알림 (주문자 본인에게)
//   POST { type: "feedback", feedback_id }              새 피드백 알림 (총괄 관리자에게)
//        헤더 x-push-secret: PUSH_WEBHOOK_SECRET (DB 트리거 pg_net 만 호출)
//
// 받는 사람:
//   * signup: 가입한 캠퍼스의 캠퍼스 관리자 + 총괄 관리자 중 알림을 켠 기기 (일반 회원 제외)
//   * order_shipped: 해당 주문을 신청한 승인된 회원 본인의 구독 기기
//   * feedback: 승인된 활성 총괄 관리자 중 알림을 켠 기기 (캠퍼스 관리자 / 일반 회원 제외)
// 만료된 구독(404 / 410)은 지운다.
//
// 보안
//   * POST 는 secret 이 맞아야 한다. 내용은 요청 본문이 아니라 DB 에서 다시 읽으므로,
//     secret 이 새더라도 실제 승인 대기 중인 가입이나 실제 배송된 신청의 알림을 다시 보내는 것밖에 못 한다.
//   * VAPID 개인 키 / secret 은 Edge Function secret 에만 있다.
//
// secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, PUSH_WEBHOOK_SECRET, VAPID_SUBJECT(선택, mailto: 또는 https:)
// =============================================================================

import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';
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

interface PushSub {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

interface VapidDetails {
  subject: string;
  publicKey: string;
  privateKey: string;
}

async function sendToSubscriptions(
  admin: SupabaseClient,
  subs: PushSub[],
  payload: string,
  vapidDetails: VapidDetails,
): Promise<{ sent: number; expired: number }> {
  const expired: string[] = [];
  let sent = 0;
  await Promise.all(
    subs.map(async (s) => {
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
  return { sent, expired: expired.length };
}

interface OrderItemRow {
  quantity?: number;
  textbooks?: { title?: string } | null;
}

interface OrderRow {
  id: string;
  user_id: string;
  is_shipped: boolean;
  status: string;
  profiles?: { is_approved?: boolean; deactivated_at?: string | null } | null;
  textbook_order_items?: OrderItemRow[] | null;
}

function formatTextbookArrivalBody(orders: OrderRow[]): string {
  const titles: string[] = [];
  for (const o of orders) {
    for (const item of o.textbook_order_items ?? []) {
      const title = item.textbooks?.title?.trim();
      if (title && !titles.includes(title)) titles.push(title);
    }
  }
  if (titles.length === 0) {
    return '신청하신 교재가 도착했습니다. 내 신청에서 확인해 주세요.';
  }
  if (titles.length === 1) {
    return `신청하신 ${titles[0]} 교재가 도착했습니다. 내 신청에서 확인해 주세요.`;
  }
  return `신청하신 ${titles[0]} 외 ${titles.length - 1}종 교재가 도착했습니다. 내 신청에서 확인해 주세요.`;
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

  let body: {
    type?: unknown;
    profile_id?: unknown;
    user_id?: unknown;
    order_id?: unknown;
    order_ids?: unknown;
    feedback_id?: unknown;
    deposit_id?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return fail(400, '요청 형식이 올바르지 않습니다.');
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return fail(500, '서버 설정 오류입니다. (service role)');
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const vapidDetails: VapidDetails = {
    subject: Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@example.com',
    publicKey,
    privateKey,
  };

  // ---- 1. 가입 신청 알림 (관리자에게만) ---------------------------------------
  if (body.type === 'signup') {
    if (typeof body.profile_id !== 'string' || !UUID.test(body.profile_id)) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }

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

    // 받는 사람: 해당 캠퍼스의 승인된 활성 캠퍼스 관리자 + 총괄 관리자만 (member / 비활성 제외)
    const { data: admins, error: adminsError } = await admin
      .from('profiles')
      .select('id')
      .eq('is_approved', true)
      .is('deactivated_at', null)
      .or(`role.eq.central_admin,and(role.eq.campus_admin,campus_id.eq.${signup.campus_id})`);
    if (adminsError) return fail(500, `관리자 조회 실패: ${adminsError.message}`);
    if (!admins?.length) return json(200, { sent: 0 });

    const { data: subs, error: subsError } = await admin
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth')
      .in('user_id', admins.map((a) => a.id));
    if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);

    const result = await sendToSubscriptions(admin, subs ?? [], payload, vapidDetails);
    return json(200, result);
  }

  // ---- 2. 교재 도착 알림 (주문자 본인에게만) ----------------------------------
  if (body.type === 'order_shipped') {
    const rawIds = Array.isArray(body.order_ids)
      ? body.order_ids
      : typeof body.order_id === 'string'
        ? [body.order_id]
        : null;
    if (
      !rawIds ||
      rawIds.length === 0 ||
      rawIds.length > 1000 ||
      !rawIds.every((id): id is string => typeof id === 'string' && UUID.test(id)) ||
      (body.user_id !== undefined && (typeof body.user_id !== 'string' || !UUID.test(body.user_id)))
    ) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }

    const { data: orders, error: ordersError } = await admin
      .from('textbook_orders')
      .select(
        'id, user_id, is_shipped, status, ' +
          'profiles:profiles!textbook_orders_user_id_fkey(is_approved, deactivated_at), ' +
          'textbook_order_items(quantity, textbooks(title))',
      )
      .in('id', rawIds);
    if (ordersError) return fail(500, `신청 조회 실패: ${ordersError.message}`);

    // DB 기준으로 여전히 배송됨 상태이고 취소되지 않았으며 주문자가 승인된 활성 회원인 건만 추린다.
    const valid = ((orders ?? []) as unknown as OrderRow[]).filter(
      (o) =>
        o.is_shipped &&
        o.status !== 'cancelled' &&
        o.profiles?.is_approved === true &&
        !o.profiles?.deactivated_at &&
        (body.user_id === undefined || o.user_id === body.user_id),
    );
    if (!valid.length) return json(200, { sent: 0 });

    // 주문자(user_id)별로 묶어 본인 구독 기기로만 보낸다.
    const byUser = new Map<string, OrderRow[]>();
    for (const o of valid) {
      const list = byUser.get(o.user_id) ?? [];
      list.push(o);
      byUser.set(o.user_id, list);
    }

    let totalSent = 0;
    let totalExpired = 0;
    for (const [userId, userOrders] of byUser.entries()) {
      const { data: subs, error: subsError } = await admin
        .from('push_subscriptions')
        .select('id, endpoint, p256dh, auth')
        .eq('user_id', userId);
      if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);
      if (!subs?.length) continue;

      const payload = JSON.stringify({
        title: '교재 도착',
        body: formatTextbookArrivalBody(userOrders),
        url: 'my-orders',
        tag: `order-shipped-${userOrders[0].id}`,
      });
      const { sent, expired } = await sendToSubscriptions(admin, subs, payload, vapidDetails);
      totalSent += sent;
      totalExpired += expired;
    }

    return json(200, { sent: totalSent, expired: totalExpired });
  }

  // ---- 3. 피드백 알림 (총괄 관리자에게만) -------------------------------------
  if (body.type === 'feedback') {
    if (typeof body.feedback_id !== 'string' || !UUID.test(body.feedback_id)) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }

    // 알림에는 보낸 사람과 내용을 넣지 않는다 (잠금화면 노출 방지). 도착 사실만 알린다.
    const { data: fb, error: fbError } = await admin
      .from('feedback')
      .select('id, resolved_at')
      .eq('id', body.feedback_id)
      .maybeSingle();
    if (fbError) return fail(500, `피드백 조회 실패: ${fbError.message}`);
    // 없거나 이미 확인 처리된 피드백이면 보내지 않는다.
    if (!fb || fb.resolved_at) return json(200, { sent: 0 });

    const payload = JSON.stringify({
      title: '새 피드백',
      body: '새 피드백이 도착했습니다.',
      url: 'admin/feedback',
      tag: `feedback-${fb.id}`,
    });

    // 받는 사람: 승인된 활성 총괄 관리자만
    const { data: centrals, error: centralsError } = await admin
      .from('profiles')
      .select('id')
      .eq('is_approved', true)
      .is('deactivated_at', null)
      .eq('role', 'central_admin');
    if (centralsError) return fail(500, `관리자 조회 실패: ${centralsError.message}`);
    if (!centrals?.length) return json(200, { sent: 0 });

    const { data: subs, error: subsError } = await admin
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth')
      .in('user_id', centrals.map((a) => a.id));
    if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);

    const result = await sendToSubscriptions(admin, subs ?? [], payload, vapidDetails);
    return json(200, result);
  }

  if (body.type === 'deposit_confirmed') {
    if (typeof body.deposit_id !== 'string' || !UUID.test(body.deposit_id)) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }

    const { data: deposit, error: depositError } = await admin
      .from('bank_deposits')
      .select('id, status')
      .eq('id', body.deposit_id)
      .maybeSingle();
    if (depositError) return fail(500, `입금 조회 실패: ${depositError.message}`);
    if (!deposit || deposit.status !== 'auto_matched') return json(200, { sent: 0 });

    const { data: linkedEvent, error: eventErr } = await admin
      .from('event_payments')
      .select(
        'id, user_id, is_paid, events(title), profiles:profiles!event_payments_user_id_fkey(is_approved, deactivated_at)',
      )
      .eq('confirmed_deposit_id', deposit.id)
      .eq('is_paid', true)
      .maybeSingle();
    if (eventErr) return fail(500, `이벤트 송금 조회 실패: ${eventErr.message}`);

    let targetUserId: string | null = null;
    let payload: string | null = null;

    if (linkedEvent) {
      const prof = linkedEvent.profiles as { is_approved?: boolean; deactivated_at?: string | null } | null;
      if (prof?.is_approved && !prof.deactivated_at) {
        const eventTitle = (linkedEvent.events as { title?: string } | null)?.title?.trim();
        targetUserId = linkedEvent.user_id;
        payload = JSON.stringify({
          title: '송금 확인',
          body: eventTitle ? `${eventTitle} 입금이 확인되었습니다.` : '이벤트 입금이 확인되었습니다.',
          url: 'events',
          tag: `deposit-confirmed-${deposit.id}`,
        });
      }
    } else {
      const { data: linkedOrders, error: ordersErr } = await admin
        .from('textbook_orders')
        .select(
          'id, user_id, status, ' +
            'profiles:profiles!textbook_orders_user_id_fkey(is_approved, deactivated_at), ' +
            'textbook_order_items(textbooks(title))',
        )
        .eq('confirmed_deposit_id', deposit.id)
        .eq('status', 'paid');
      if (ordersErr) return fail(500, `교재 신청 조회 실패: ${ordersErr.message}`);

      const validOrders = ((linkedOrders ?? []) as unknown as OrderRow[]).filter(
        (o) => o.profiles?.is_approved === true && !o.profiles?.deactivated_at,
      );
      if (validOrders.length > 0) {
        const titles: string[] = [];
        for (const o of validOrders) {
          for (const item of o.textbook_order_items ?? []) {
            const title = item.textbooks?.title?.trim();
            if (title && !titles.includes(title)) titles.push(title);
          }
        }
        const msg =
          titles.length === 0
            ? '교재 신청 입금이 확인되었습니다.'
            : titles.length === 1
              ? `${titles[0]} 교재 입금이 확인되었습니다.`
              : `${titles[0]} 외 ${titles.length - 1}종 교재 입금이 확인되었습니다.`;
        targetUserId = validOrders[0].user_id;
        payload = JSON.stringify({
          title: '입금 확인',
          body: msg,
          url: 'my-orders',
          tag: `deposit-confirmed-${deposit.id}`,
        });
      }
    }

    if (!targetUserId || !payload) return json(200, { sent: 0 });

    const { data: subs, error: subsError } = await admin
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth')
      .eq('user_id', targetUserId);
    if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);
    if (!subs?.length) return json(200, { sent: 0 });

    const result = await sendToSubscriptions(admin, subs, payload, vapidDetails);
    return json(200, result);
  }

  if (body.type === 'deposit_review') {
    if (typeof body.deposit_id !== 'string' || !UUID.test(body.deposit_id)) {
      return fail(400, '요청 형식이 올바르지 않습니다.');
    }

    const { data: deposit, error: depositError } = await admin
      .from('bank_deposits')
      .select('id, status, campus_id')
      .eq('id', body.deposit_id)
      .maybeSingle();
    if (depositError) return fail(500, `입금 조회 실패: ${depositError.message}`);
    if (!deposit || !['unmatched', 'ambiguous', 'unparsed'].includes(deposit.status)) {
      return json(200, { sent: 0 });
    }

    // Lock-screen text omits depositor names and amounts.
    const reviewBody =
      deposit.status === 'unparsed'
        ? '해석하지 못한 입금 알림이 있습니다.'
        : '확인이 필요한 입금이 있습니다.';
    const payload = JSON.stringify({
      title: '입금 확인 필요',
      body: reviewBody,
      url: 'admin/deposits',
      tag: `deposit-review-${deposit.id}`,
    });

    const { data: localAdmins, error: adminsError } = await admin
      .from('profiles')
      .select('id')
      .eq('is_approved', true)
      .is('deactivated_at', null)
      .eq('campus_id', deposit.campus_id)
      .in('role', ['campus_admin', 'central_admin']);
    if (adminsError) return fail(500, `관리자 조회 실패: ${adminsError.message}`);

    let recipients = localAdmins ?? [];
    if (recipients.length === 0) {
      const { data: centrals, error: centralsError } = await admin
        .from('profiles')
        .select('id')
        .eq('is_approved', true)
        .is('deactivated_at', null)
        .eq('role', 'central_admin');
      if (centralsError) return fail(500, `관리자 조회 실패: ${centralsError.message}`);
      recipients = centrals ?? [];
    }
    if (!recipients.length) return json(200, { sent: 0 });

    const { data: subs, error: subsError } = await admin
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth')
      .in('user_id', recipients.map((a) => a.id));
    if (subsError) return fail(500, `구독 조회 실패: ${subsError.message}`);

    const result = await sendToSubscriptions(admin, subs ?? [], payload, vapidDetails);
    return json(200, result);
  }

  return fail(400, '요청 형식이 올바르지 않습니다.');
});

