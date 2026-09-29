import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/widgets/config_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 웹에서 `/#/home` 대신 `/home` 형태의 URL 을 사용한다. (호스팅 시 SPA rewrite 필요)
  usePathUrlStrategy();

  // 앱에 포함한 폰트의 라이선스 (Flutter 라이선스 목록 showLicensePage 에 표시된다)
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Noto Sans KR'], license);
  });

  Intl.defaultLocale = 'ko_KR';
  await initializeDateFormatting('ko_KR');

  if (!Env.isConfigured) {
    runApp(const ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  runApp(
    ProviderScope(
      // 실패한 요청을 자동 재시도하지 않고 즉시 에러 화면(다시 시도 버튼)을 보여준다.
      retry: (_, _) => null,
      child: const CccApp(),
    ),
  );
}
