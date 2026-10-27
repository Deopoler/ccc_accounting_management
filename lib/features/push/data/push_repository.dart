import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/web_push.dart';
import '../../../core/utils/app_exception.dart';

/// 관리자 기기의 웹 푸시 구독. 보내기는 Edge Function `push` 가 한다.
class PushRepository {
  PushRepository(this._client);

  final SupabaseClient _client;

  /// 서버(VAPID) 공개 키. 개인 키는 Edge Function secret 에만 있다.
  Future<String> fetchPublicKey() async {
    final res = await _client.functions.invoke('push', method: HttpMethod.get);
    final data = res.data;
    if (data is Map && data['publicKey'] is String) {
      return data['publicKey'] as String;
    }
    throw const AppException('알림 서버 설정을 불러오지 못했습니다.');
  }

  /// 관리자만 저장할 수 있다. (RPC) 같은 기기를 다른 관리자가 쓰던 것이면 현재 관리자에게 옮긴다.
  Future<void> save(DevicePushSubscription sub) => _client.rpc<void>(
    'save_push_subscription',
    params: {
      'p_endpoint': sub.endpoint,
      'p_p256dh': sub.p256dh,
      'p_auth': sub.auth,
    },
  );

  /// 본인에게 저장된 구독인지. (RLS: 본인 것만 보인다)
  Future<bool> isSaved(String endpoint) async {
    final row = await _client
        .from('push_subscriptions')
        .select('id')
        .eq('endpoint', endpoint)
        .maybeSingle();
    return row != null;
  }

  Future<void> delete(String endpoint) =>
      _client.from('push_subscriptions').delete().eq('endpoint', endpoint);
}
