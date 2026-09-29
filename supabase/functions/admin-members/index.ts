// =============================================================================
// admin-members: service role 이 필요한 회원 관리 작업
//
//   POST { action: "reset_password", user_id }  비밀번호를 기본 비밀번호로 초기화
//                                               + 다음 로그인 시 변경 강제
//   POST { action: "reject_signup",  user_id }  승인 대기 가입 신청 거절 (계정 삭제)
//
// 보안
//   * 호출자의 access token 을 서버에서 검증하고, profiles 에서 승인된 admin 인지 확인한다.
//     (클라이언트의 역할 체크는 신뢰하지 않는다)
//   * 기본 비밀번호는 Edge Function secret(DEFAULT_PASSWORD)에만 있고 DB/클라이언트에 없다.
//   * 본인 계정에는 사용할 수 없다. 승인된 회원은 삭제할 수 없다(회계 기록 보존).
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const fail = (status: number, error: string) => json(status, { error });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail(405, '허용되지 않는 요청입니다.');

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return fail(500, '서버 설정 오류입니다. (service role)');

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ---- 호출자 검증 -----------------------------------------------------------
  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return fail(401, '로그인이 필요합니다.');

  const { data: caller, error: callerError } = await admin.auth.getUser(token);
  if (callerError || !caller.user) return fail(401, '로그인이 만료되었습니다. 다시 로그인해 주세요.');

  const { data: callerProfile } = await admin
    .from('profiles')
    .select('role, is_approved')
    .eq('id', caller.user.id)
    .maybeSingle();
  if (callerProfile?.role !== 'admin' || !callerProfile.is_approved) {
    return fail(403, '관리자만 사용할 수 있습니다.');
  }

  // ---- 요청 파싱 -------------------------------------------------------------
  let body: { action?: unknown; user_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, '요청 형식이 올바르지 않습니다.');
  }
  const { action, user_id: userId } = body;
  if (typeof userId !== 'string' || !UUID.test(userId)) {
    return fail(400, '대상 회원이 올바르지 않습니다.');
  }
  if (userId === caller.user.id) {
    return fail(400, '본인 계정에는 사용할 수 없습니다.');
  }

  const { data: target } = await admin
    .from('profiles')
    .select('id, student_id, name, is_approved')
    .eq('id', userId)
    .maybeSingle();
  if (!target) return fail(404, '회원을 찾을 수 없습니다.');

  // ---- 작업 ------------------------------------------------------------------
  switch (action) {
    case 'reset_password': {
      const defaultPassword = Deno.env.get('DEFAULT_PASSWORD');
      if (!defaultPassword || defaultPassword.length < 8) {
        return fail(500, '기본 비밀번호(DEFAULT_PASSWORD)가 설정되지 않았습니다.');
      }
      const { error } = await admin.auth.admin.updateUserById(userId, {
        password: defaultPassword,
      });
      if (error) return fail(500, `비밀번호 초기화 실패: ${error.message}`);

      // 비밀번호 변경 트리거가 플래그를 해제하므로, 그 다음에 다시 켠다.
      const { error: flagError } = await admin
        .from('profiles')
        .update({ must_change_password: true })
        .eq('id', userId);
      if (flagError) return fail(500, `비밀번호 변경 플래그 설정 실패: ${flagError.message}`);

      return json(200, { ok: true, message: `${target.name}(${target.student_id})의 비밀번호를 초기화했습니다.` });
    }

    case 'reject_signup': {
      if (target.is_approved) {
        return fail(400, '이미 승인된 회원은 삭제할 수 없습니다.');
      }
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return fail(500, `가입 거절 실패: ${error.message}`);
      return json(200, { ok: true, message: `${target.name}(${target.student_id})의 가입 신청을 거절했습니다.` });
    }

    default:
      return fail(400, '알 수 없는 작업입니다.');
  }
});
