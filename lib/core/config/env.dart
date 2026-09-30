/// 빌드 시 `--dart-define` 또는 `--dart-define-from-file=env.json` 으로 주입되는 설정값.
///
/// 코드에 키를 하드코딩하지 않는다. publishable 키(구 anon 키)는 공개되어도 되는 키이며,
/// 실제 권한은 Supabase RLS 가 강제한다.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// `staging` 이면 테스트 서버. 화면에 표시를 붙여 운영과 헷갈리지 않게 한다.
  static const appEnv = String.fromEnvironment('APP_ENV');

  static bool get isStaging => appEnv == 'staging';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
