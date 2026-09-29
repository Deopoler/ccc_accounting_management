import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'state_views.dart';

/// Supabase 접속 정보가 주입되지 않았을 때 보여주는 앱.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCC 회계',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: EmptyView(
          icon: Icons.settings_suggest_outlined,
          message:
              'Supabase 접속 정보가 설정되지 않았습니다.\n'
              'flutter run -d chrome --dart-define-from-file=env.json\n'
              '형태로 실행해 주세요. (README 참고)',
        ),
      ),
    );
  }
}
