import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

bool get _keyboardNavigating =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// 키보드/터치 전환 때 포커스가 그대로여도 테두리를 다시 그리도록 강조 모드를 구독한다.
mixin _HighlightModeListener<T extends StatefulWidget> on State<T> {
  void _onModeChange(FocusHighlightMode _) => setState(() {});

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChange);
    super.dispose();
  }
}

BoxDecoration _ring(BuildContext context, BorderRadius radius, bool show) =>
    BoxDecoration(
      borderRadius: radius,
      border: show
          ? Border.all(color: context.colors.focusRing, width: 2)
          : null,
    );

/// 자손(예: ListTile)이 키보드 포커스를 받으면 2px 테두리를 그린다.
/// 테두리는 위에 덧칠만 하므로 레이아웃은 변하지 않는다.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> with _HighlightModeListener {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _ring(
          context,
          widget.borderRadius,
          _focused && _keyboardNavigating,
        ),
        child: widget.child,
      ),
    );
  }
}

/// NavigationBar 항목의 아이콘. 항목에 키보드 포커스가 오면 아이콘 둘레에 테두리를 그린다.
/// NavigationBar 는 포커스 표시를 투명한 인디케이터에 맡기고 있어 직접 그려야 한다.
class NavFocusIcon extends StatefulWidget {
  const NavFocusIcon(this.icon, {super.key});

  final IconData icon;

  @override
  State<NavFocusIcon> createState() => _NavFocusIconState();
}

class _NavFocusIconState extends State<NavFocusIcon>
    with _HighlightModeListener {
  @override
  Widget build(BuildContext context) {
    final focused = Focus.maybeOf(context)?.hasFocus ?? false;
    return SizedBox(
      width: 56,
      height: 32,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _ring(
          context,
          BorderRadius.circular(16),
          focused && _keyboardNavigating,
        ),
        child: Center(child: Icon(widget.icon)),
      ),
    );
  }
}
