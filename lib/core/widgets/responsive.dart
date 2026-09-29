import 'package:material_ui/material_ui.dart';

/// Material 3 기준 expanded 너비 이상이면 데스크톱 레이아웃을 사용한다.
const double kDesktopBreakpoint = 840;

bool isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// 페이지 본문을 가운데 정렬하고 최대 너비를 제한한다.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 스크롤 가능한 페이지 본문.
class ScrollPageBody extends StatelessWidget {
  const ScrollPageBody({
    super.key,
    required this.children,
    this.maxWidth = 1100,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: PageBody(
        maxWidth: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
