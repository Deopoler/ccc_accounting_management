import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// 테스트 서버로 접속한 앱의 모든 화면 왼쪽 아래에 "테스트 서버" 띠를 붙인다.
/// 오른쪽 위는 계정 버튼 자리라 피한다.
class StagingBanner extends StatelessWidget {
  const StagingBanner({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Banner(
      message: '테스트 서버',
      location: BannerLocation.bottomStart,
      // 강조색(파랑)과 겹치지 않고, 오류색만큼 눈에 띄게. 주황 위에는 어두운 글자(7.5:1).
      color: const Color(0xFFFF9500),
      textStyle: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontFamilyFallback: AppTheme.fontFamilyFallback,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Color(0xFF191F28),
      ),
      child: child,
    );
  }
}
