import 'package:ccc_accounting_management/core/widgets/staging_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget app(bool enabled) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => StagingBanner(enabled: enabled, child: child!),
    home: const Scaffold(body: Text('화면')),
  );

  testWidgets('테스트 서버면 모든 화면에 표시가 붙는다', (tester) async {
    await tester.pumpWidget(app(true));
    expect(find.byType(Banner), findsOneWidget);
    expect(find.text('화면'), findsOneWidget);
  });

  testWidgets('운영이면 표시가 없다', (tester) async {
    await tester.pumpWidget(app(false));
    expect(find.byType(Banner), findsNothing);
  });
}
