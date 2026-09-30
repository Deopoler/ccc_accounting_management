import 'package:material_ui/material_ui.dart';

/// 테스트 서버로 접속한 앱의 모든 화면 오른쪽 위에 "테스트 서버" 띠를 붙인다.
class StagingBanner extends StatelessWidget {
  const StagingBanner({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Banner(
      message: '테스트 서버',
      location: BannerLocation.topEnd,
      // 강조색(파랑)과 겹치지 않고, 오류색만큼 눈에 띄게.
      color: const Color(0xFFFF9500),
      textStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      child: child,
    );
  }
}
